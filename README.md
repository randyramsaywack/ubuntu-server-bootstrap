# Ubuntu Server Bootstrap

## Overview

Ubuntu Server Bootstrap is a practical Bash provisioning script for Ubuntu 24.04 server virtual machines. It is designed for repeatable first-boot setup, especially Proxmox cloud-init deployments, where a fresh VM needs sane administration tools, guest integration, Docker, baseline security controls, automatic updates, and a clear post-install health summary.

The project is intentionally small and readable so it can be audited, customized, and used as a resume-ready example of Linux server administration and automation.

## Features

- Updates and full-upgrades Ubuntu 24.04
- Installs common Linux administration tools
- Installs and enables `qemu-guest-agent` for Proxmox readiness
- Installs Docker Engine and the Docker Compose plugin
- Installs and enables Fail2Ban
- Installs and enables Chrony
- Enables UFW and allows OpenSSH
- Configures unattended upgrades
- Applies SSH hardening through an `sshd_config.d` drop-in
- Backs up `/etc/ssh/sshd_config` before SSH changes
- Validates SSH configuration with `sshd -t` before reloading SSH
- Validates key services after installation
- Detects whether a reboot is required
- Logs all output to `/var/log/ubuntu-base-setup.log`
- Prints a system health summary at the end of the run
- Includes a Proxmox template creation script for Ubuntu 24.04 cloud-init images

## Installed Components

The script installs and configures:

- Docker Engine
- Docker Compose plugin
- QEMU Guest Agent
- Fail2Ban
- Chrony
- UFW
- OpenSSH server
- unattended-upgrades
- Common administration tools including `curl`, `wget`, `vim`, `htop`, `jq`, `tmux`, `rsync`, `unzip`, and `net-tools`

Docker is installed from Docker's official Ubuntu apt repository.

## Usage

Clone the repository onto a fresh Ubuntu 24.04 server:

```bash
git clone https://github.com/randyramsaywack/ubuntu-server-bootstrap.git
cd ubuntu-server-bootstrap
chmod +x ubuntu-base-setup.sh
sudo ./ubuntu-base-setup.sh
```

If you want a specific non-root account added to the `docker` group, set `DOCKER_USER`:

```bash
sudo DOCKER_USER=admin ./ubuntu-base-setup.sh
```

You can also run it directly from cloud-init by downloading the script during first boot. See [docs/cloud-init-example.yaml](docs/cloud-init-example.yaml).

To create a reusable Proxmox Ubuntu 24.04 cloud-init template, see [docs/proxmox-template.md](docs/proxmox-template.md) and [scripts/create-proxmox-ubuntu-template.sh](scripts/create-proxmox-ubuntu-template.sh).

## Cloud-Init Example

This repository includes a Proxmox-friendly cloud-init example in [docs/cloud-init-example.yaml](docs/cloud-init-example.yaml). The example creates a user, installs the script, and runs it once during VM initialization.

For deployment, keep the public example generic and create a local copy:

```bash
cp docs/cloud-init-example.yaml cloud-init.local.yaml
```

Then edit `cloud-init.local.yaml` with your real SSH public key and deployment-specific settings. The local file is ignored by Git so your key and environment details are not committed.

## SSH Hardening Warning

This script disables SSH password authentication and root login:

```text
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
```

Make sure SSH key access is configured and tested before running this script on a remote server. If you run it without a valid SSH key for your user, you may lock yourself out after SSH reloads or after the next login attempt.

## System Health Output

At the end of the run, the script prints a concise health summary:

- Uptime
- Root filesystem disk usage
- Memory usage
- CPU architecture, CPU count, and model
- IP addresses
- Failed systemd units
- Docker version
- Docker Compose plugin version

This gives you a quick operational snapshot immediately after provisioning.

Example successful completion:

```text
[OK] SSH hardening applied and ssh service reloaded.
[OK] qemu-guest-agent is active with enable state 'static'.
[OK] chrony is active with enable state 'enabled'.
[OK] fail2ban is active with enable state 'enabled'.
[OK] docker is active with enable state 'enabled'.
[OK] ssh is active with enable state 'enabled'.
[DONE] Ubuntu Server Bootstrap completed. Log saved to /var/log/ubuntu-base-setup.log.
```

## Logging

All output is written to:

```text
/var/log/ubuntu-base-setup.log
```

The log includes package installation output, service enablement, SSH validation, service checks, and the final health summary. Use it for troubleshooting failed provisioning runs or for confirming what changed on a host.

## Use Cases

- Proxmox Ubuntu 24.04 cloud-init VM templates
- Home lab server provisioning
- Docker host bootstrap
- Baseline hardening for small Ubuntu servers
- Repeatable VM setup for testing and development
- Demonstrating Linux administration automation in a portfolio or resume

## Related Projects

- [proxmox-vm-factory](https://github.com/randyramsaywack/proxmox-vm-factory): clone and configure Proxmox VMs from the templates created by this project.

## Tested With

- Ubuntu 24.04 Noble cloud image
- Proxmox VE cloud-init VMs
- NoCloud cloud-init datasource
- ZFS-backed Proxmox VM storage
- DHCP networking with QEMU Guest Agent enabled

## Design Philosophy

This project favors practical automation over heavy abstraction. The script uses plain Bash functions, clear status labels, standard Ubuntu packages, and idempotent checks where they add value.

It is meant to be easy to read, easy to modify, and safe enough for common VM provisioning workflows without becoming a full configuration management framework.

## Resume-Ready Project Description

Built a Bash-based Ubuntu 24.04 server provisioning tool for Proxmox cloud-init virtual machines. Automated system updates, Linux administration tooling, QEMU guest integration, Docker installation, firewall configuration, Fail2Ban, Chrony, unattended upgrades, SSH hardening, service validation, reboot detection, and operational health reporting with full logging to `/var/log`.

Resume bullet:

```text
Built a Bash-based Ubuntu 24.04 provisioning toolkit for Proxmox cloud-init VMs, automating Docker installation, guest agent setup, SSH hardening, firewall configuration, unattended upgrades, service validation, and operational health logging.
```

## Disclaimer

Review the script before running it on any production system. It changes SSH authentication behavior, enables a firewall, installs packages from Docker's official apt repository, and modifies system services. Test in a disposable VM before using it on critical infrastructure.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
