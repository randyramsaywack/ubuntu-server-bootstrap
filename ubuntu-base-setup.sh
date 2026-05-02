#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/ubuntu-base-setup.log"
SSH_CONFIG="/etc/ssh/sshd_config"
SSH_HARDENING_DROPIN="/etc/ssh/sshd_config.d/99-ubuntu-base-hardening.conf"

export DEBIAN_FRONTEND=noninteractive

if [[ "${EUID}" -ne 0 ]]; then
  printf '[FAIL] This script must be run as root. Use sudo or run it from cloud-init.\n'
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; }
done_msg() { printf '[DONE] %s\n' "$*"; }

on_error() {
  local line_number="$1"
  fail "Setup failed near line ${line_number}. Review ${LOG_FILE} for details."
}

trap 'on_error "$LINENO"' ERR

require_root() {
  ok "Root privileges confirmed."
}

require_ubuntu_2404() {
  if [[ ! -r /etc/os-release ]]; then
    warn "Unable to read /etc/os-release. Continuing without OS validation."
    return
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  if [[ "${ID:-}" != "ubuntu" || "${VERSION_ID:-}" != "24.04" ]]; then
    warn "This script is intended for Ubuntu 24.04. Detected: ${PRETTY_NAME:-unknown}."
  else
    ok "Detected ${PRETTY_NAME}."
  fi
}

apt_update_and_upgrade() {
  info "Updating package lists and applying full upgrade."
  apt-get update
  apt-get -y full-upgrade
  ok "System packages are up to date."
}

install_admin_tools() {
  local packages=(
    apt-transport-https
    ca-certificates
    chrony
    curl
    fail2ban
    gnupg
    htop
    jq
    lsb-release
    net-tools
    openssh-server
    qemu-guest-agent
    rsync
    software-properties-common
    tmux
    ufw
    unzip
    vim
    wget
  )

  info "Installing common Linux administration tools."
  apt-get install -y "${packages[@]}"
  ok "Administration tools installed."
}

install_docker() {
  if command -v docker >/dev/null 2>&1 && dpkg -s docker-compose-plugin >/dev/null 2>&1; then
    ok "Docker and Docker Compose plugin are already installed."
    return
  fi

  info "Installing Docker Engine and Docker Compose plugin from Docker's official apt repository."
  install -m 0755 -d /etc/apt/keyrings

  if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
  fi

  local codename
  codename="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME}")"
  local arch
  arch="$(dpkg --print-architecture)"
  local repo_file="/etc/apt/sources.list.d/docker.list"
  local repo_line="deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu ${codename} stable"

  if [[ ! -f "$repo_file" ]] || ! grep -Fxq "$repo_line" "$repo_file"; then
    printf '%s\n' "$repo_line" > "$repo_file"
  fi

  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  ok "Docker Engine and Docker Compose plugin installed."
}

add_docker_group_user() {
  local docker_user="${DOCKER_USER:-${SUDO_USER:-}}"

  if [[ -z "$docker_user" ]] && getent passwd ubuntu >/dev/null 2>&1; then
    docker_user="ubuntu"
  fi

  if [[ -z "$docker_user" || "$docker_user" == "root" ]]; then
    warn "No non-root Docker user detected. Set DOCKER_USER=username before running if needed."
    return
  fi

  if getent passwd "$docker_user" >/dev/null 2>&1; then
    usermod -aG docker "$docker_user"
    ok "Added ${docker_user} to the docker group. A new login session is required for group membership to apply."
  else
    warn "Requested Docker user ${docker_user} does not exist; skipping docker group assignment."
  fi
}

enable_services() {
  local services=(
    qemu-guest-agent
    chrony
    fail2ban
    docker
    ssh
  )

  info "Enabling and starting core services."
  for service in "${services[@]}"; do
    local enable_state
    enable_state="$(systemctl is-enabled "$service" 2>/dev/null || true)"

    case "$enable_state" in
      enabled|enabled-runtime)
        ok "${service} is already enabled."
        ;;
      static|generated|indirect|alias)
        warn "${service} has enable state '${enable_state}', so it cannot be enabled directly."
        ;;
      *)
        systemctl enable "$service"
        ok "Enabled ${service}."
        ;;
    esac

    systemctl start "$service"
    ok "Started ${service}."
  done
}

configure_ufw() {
  info "Configuring UFW firewall."
  ufw allow OpenSSH
  ufw --force enable
  ok "UFW enabled with OpenSSH allowed."
}

configure_unattended_upgrades() {
  info "Configuring unattended security upgrades."
  apt-get install -y unattended-upgrades apt-listchanges

  cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

  dpkg-reconfigure -f noninteractive unattended-upgrades
  ok "Unattended upgrades configured."
}

backup_sshd_config() {
  local backup_path
  backup_path="${SSH_CONFIG}.bak.$(date +%Y%m%d%H%M%S)"

  if [[ -f "$SSH_CONFIG" ]]; then
    cp -a "$SSH_CONFIG" "$backup_path"
    ok "Backed up SSH configuration to ${backup_path}."
  else
    warn "${SSH_CONFIG} was not found; OpenSSH server may not be installed."
  fi
}

warn_about_ssh_keys() {
  local user_home=""
  local ssh_user="${SSH_KEY_USER:-${DOCKER_USER:-${SUDO_USER:-root}}}"

  if [[ "$ssh_user" == "root" ]]; then
    user_home="/root"
  else
    user_home="$(getent passwd "$ssh_user" | cut -d: -f6 || true)"
  fi

  if [[ -z "$user_home" || ! -s "${user_home}/.ssh/authorized_keys" ]]; then
    warn "No authorized_keys file found for ${ssh_user}. Confirm SSH key access before relying on this host remotely."
  else
    ok "Detected SSH authorized_keys for ${ssh_user}."
  fi
}

configure_ssh_hardening() {
  info "Applying SSH hardening."
  backup_sshd_config
  warn_about_ssh_keys
  install -m 0755 -d /etc/ssh/sshd_config.d
  install -m 0755 -d /run/sshd

  if [[ -f "$SSH_CONFIG" ]] && ! grep -Eq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' "$SSH_CONFIG"; then
    sed -i '1iInclude /etc/ssh/sshd_config.d/*.conf' "$SSH_CONFIG"
    ok "Added sshd_config.d include directive to ${SSH_CONFIG}."
  fi

  cat > "$SSH_HARDENING_DROPIN" <<'EOF'
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
EOF

  if sshd -t; then
    systemctl reload ssh || systemctl restart ssh
    ok "SSH hardening applied and ssh service reloaded."
  else
    fail "SSH configuration validation failed. Restoring from the newest backup."
    local latest_backup
    latest_backup="$(ls -1t "${SSH_CONFIG}".bak.* 2>/dev/null | head -n1 || true)"
    [[ -n "$latest_backup" ]] && cp -a "$latest_backup" "$SSH_CONFIG"
    rm -f "$SSH_HARDENING_DROPIN"
    sshd -t || true
    exit 1
  fi
}

validate_service() {
  local service="$1"
  local enable_state
  enable_state="$(systemctl is-enabled "$service" 2>/dev/null || true)"

  if ! systemctl is-active "$service" >/dev/null 2>&1; then
    warn "${service} is not active."
    systemctl --no-pager --full status "$service" || true
    return
  fi

  case "$enable_state" in
    enabled|enabled-runtime|static|generated|indirect|alias)
      ok "${service} is active with enable state '${enable_state}'."
      ;;
    *)
      warn "${service} is active but has enable state '${enable_state:-unknown}'."
      systemctl --no-pager --full status "$service" || true
      ;;
  esac
}

validate_services() {
  info "Validating service state."
  validate_service qemu-guest-agent
  validate_service chrony
  validate_service fail2ban
  validate_service docker
  validate_service ssh
}

print_system_health() {
  info "System health summary."

  printf '\n[INFO] Uptime\n'
  uptime

  printf '\n[INFO] Disk usage\n'
  df -h /

  printf '\n[INFO] Memory usage\n'
  free -h

  printf '\n[INFO] CPU info\n'
  lscpu | awk -F: '/Model name|CPU\(s\)|Architecture/ { gsub(/^[ \t]+/, "", $2); printf "%s: %s\n", $1, $2 }'

  printf '\n[INFO] IP addresses\n'
  hostname -I | tr ' ' '\n' | sed '/^$/d'

  printf '\n[INFO] Failed systemd units\n'
  systemctl --failed --no-pager || true

  printf '\n[INFO] Docker version\n'
  docker --version || warn "Docker command is unavailable."
  docker compose version || warn "Docker Compose plugin is unavailable."
}

check_reboot_required() {
  if [[ -f /var/run/reboot-required ]]; then
    warn "A reboot is required to complete system updates."
    if [[ -f /var/run/reboot-required.pkgs ]]; then
      info "Packages requesting reboot:"
      cat /var/run/reboot-required.pkgs
    fi
  else
    ok "No reboot is currently required."
  fi
}

main() {
  info "Starting Ubuntu Server Bootstrap."
  require_root
  require_ubuntu_2404
  apt_update_and_upgrade
  install_admin_tools
  install_docker
  add_docker_group_user
  enable_services
  configure_ufw
  configure_unattended_upgrades
  configure_ssh_hardening
  validate_services
  print_system_health
  check_reboot_required
  done_msg "Ubuntu Server Bootstrap completed. Log saved to ${LOG_FILE}."
}

main "$@"
