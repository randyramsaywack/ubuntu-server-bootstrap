#!/usr/bin/env bash
set -Eeuo pipefail

LOG_FILE="/var/log/codex-xfce-workstation-setup.log"
WORKSTATION_USER="${WORKSTATION_USER:-${SUDO_USER:-randy}}"
RDP_ALLOWED_CIDR="${RDP_ALLOWED_CIDR:-10.1.1.0/24}"
INSTALL_CODEX="${INSTALL_CODEX:-true}"

export DEBIAN_FRONTEND=noninteractive

if [[ "${EUID}" -ne 0 ]]; then
  printf '[FAIL] This script must be run as root. Use sudo.\n'
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
  fail "Workstation setup failed near line ${line_number}. Review ${LOG_FILE} for details."
}

trap 'on_error "$LINENO"' ERR

require_user() {
  if ! getent passwd "$WORKSTATION_USER" >/dev/null 2>&1; then
    fail "User ${WORKSTATION_USER} does not exist. Set WORKSTATION_USER=username and rerun."
    exit 1
  fi

  ok "Configuring workstation user ${WORKSTATION_USER}."
}

install_packages() {
  local packages=(
    bat
    btop
    build-essential
    ca-certificates
    curl
    dbus-x11
    fd-find
    fzf
    gh
    git
    jq
    ncdu
    nodejs
    npm
    pipx
    python3
    python3-pip
    python3-venv
    ripgrep
    shellcheck
    shfmt
    tmux
    ufw
    xfce4
    xfce4-goodies
    xorgxrdp
    xrdp
  )

  info "Installing Codex workstation, XFCE, and XRDP packages."
  apt-get update
  apt-get install -y "${packages[@]}"
  ok "Workstation packages installed."
}

create_command_aliases() {
  if [[ ! -e /usr/local/bin/bat && -x /usr/bin/batcat ]]; then
    ln -s /usr/bin/batcat /usr/local/bin/bat
    ok "Created /usr/local/bin/bat alias for batcat."
  fi

  if [[ ! -e /usr/local/bin/fd && -x /usr/bin/fdfind ]]; then
    ln -s /usr/bin/fdfind /usr/local/bin/fd
    ok "Created /usr/local/bin/fd alias for fdfind."
  fi
}

install_codex_cli() {
  if [[ "$INSTALL_CODEX" != "true" ]]; then
    warn "Codex CLI installation skipped because INSTALL_CODEX=${INSTALL_CODEX}."
    return
  fi

  if command -v codex >/dev/null 2>&1; then
    ok "Codex CLI is already installed: $(codex --version)"
    return
  fi

  info "Installing Codex CLI with npm."
  npm install -g @openai/codex
  ok "Installed Codex CLI: $(codex --version)"
}

configure_xfce_session() {
  local user_home
  user_home="$(getent passwd "$WORKSTATION_USER" | cut -d: -f6)"

  info "Configuring XFCE session for ${WORKSTATION_USER}."
  cat > "${user_home}/.xsession" <<'EOF'
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
startxfce4
EOF

  chown "${WORKSTATION_USER}:${WORKSTATION_USER}" "${user_home}/.xsession"
  chmod 0644 "${user_home}/.xsession"
  ok "Configured ${user_home}/.xsession."
}

configure_xrdp() {
  info "Configuring XRDP."
  adduser xrdp ssl-cert
  systemctl enable --now xrdp
  systemctl restart xrdp
  ok "XRDP enabled and running."
}

configure_firewall() {
  info "Allowing RDP from ${RDP_ALLOWED_CIDR} only."
  ufw allow from "$RDP_ALLOWED_CIDR" to any port 3389 proto tcp
  ufw --force enable
  ok "UFW allows RDP from ${RDP_ALLOWED_CIDR}."
}

configure_user_shell_helpers() {
  local user_home
  user_home="$(getent passwd "$WORKSTATION_USER" | cut -d: -f6)"

  mkdir -p "${user_home}/code" "${user_home}/agent-logs"
  chown -R "${WORKSTATION_USER}:${WORKSTATION_USER}" "${user_home}/code" "${user_home}/agent-logs"

  if ! grep -q 'alias ll=' "${user_home}/.bashrc"; then
    cat >> "${user_home}/.bashrc" <<'EOF'

# Codex workstation helpers
alias ll='ls -alF'
alias gs='git status --short --branch'
EOF
    chown "${WORKSTATION_USER}:${WORKSTATION_USER}" "${user_home}/.bashrc"
  fi

  ok "Created ${user_home}/code and ${user_home}/agent-logs."
}

print_validation() {
  info "Validating workstation setup."

  printf '\n[INFO] Tool versions\n'
  command -v codex >/dev/null 2>&1 && codex --version || warn "codex command not found."
  node --version || true
  npm --version || true
  git --version || true
  gh --version | head -n1 || true
  rg --version | head -n1 || true
  shellcheck --version | awk -F': ' '/version:/ { print "shellcheck " $2 }' || true
  shfmt --version || true

  printf '\n[INFO] XRDP status\n'
  systemctl is-active xrdp
  systemctl is-active xrdp-sesman
  ss -tulpn | grep ':3389' || warn "XRDP does not appear to be listening on 3389."

  printf '\n[INFO] UFW status\n'
  ufw status verbose

  if passwd -S "$WORKSTATION_USER" | awk '{ exit ($2 == "P") ? 0 : 1 }'; then
    ok "${WORKSTATION_USER} has a password set for XRDP login."
  else
    warn "${WORKSTATION_USER} may not have a password set. XRDP requires a Linux password. Run: sudo passwd ${WORKSTATION_USER}"
  fi
}

main() {
  info "Starting Codex XFCE workstation setup."
  require_user
  install_packages
  create_command_aliases
  install_codex_cli
  configure_xfce_session
  configure_xrdp
  configure_firewall
  configure_user_shell_helpers
  print_validation
  done_msg "Codex XFCE workstation setup completed. Log saved to ${LOG_FILE}."
}

main "$@"
