# Codex XFCE Workstation

This optional layer turns a bootstrapped Ubuntu 24.04 VM into a lightweight Codex workstation with XFCE and XRDP access.

Use it after `ubuntu-base-setup.sh` when you want both SSH-based Codex CLI work and occasional desktop access through Microsoft Remote Desktop.

## What It Installs

- XFCE desktop
- XRDP and `xorgxrdp`
- Codex CLI through npm
- GitHub CLI
- Node.js and npm
- Python 3, `venv`, `pip`, and `pipx`
- `tmux`, `fzf`, `ripgrep`, `jq`, `shellcheck`, `shfmt`, `bat`, `fd`, `btop`, and `ncdu`

## Security Notes

XRDP uses a Linux account password, not SSH keys. If the target user does not have a password, set one:

```bash
sudo passwd randy
```

The script allows RDP only from a LAN CIDR. The default is:

```text
10.1.1.0/24
```

Do not expose TCP port `3389` directly to the internet.

## Usage

Run on the Ubuntu VM:

```bash
curl -fsSL https://raw.githubusercontent.com/randyramsaywack/ubuntu-server-bootstrap/main/scripts/setup-codex-xfce-workstation.sh -o /tmp/setup-codex-xfce-workstation.sh
chmod +x /tmp/setup-codex-xfce-workstation.sh
sudo WORKSTATION_USER=randy RDP_ALLOWED_CIDR=10.1.1.0/24 /tmp/setup-codex-xfce-workstation.sh
```

To skip Codex CLI installation:

```bash
sudo WORKSTATION_USER=randy INSTALL_CODEX=false /tmp/setup-codex-xfce-workstation.sh
```

## Connect With RDP

From Microsoft Remote Desktop, connect to:

```text
10.1.1.149:3389
```

Login with the Linux username and password:

```text
randy
```

## Verify

```bash
systemctl is-active xrdp
systemctl is-active xrdp-sesman
sudo ss -tulpn | grep 3389
sudo ufw status verbose
codex --version
gh --version
```

## First Codex Login

Run Codex interactively over SSH or inside the RDP desktop terminal:

```bash
codex
```

Complete the browser-based sign-in flow when prompted.

## Workstation Folders

The setup creates:

```text
~/code
~/agent-logs
```

Use `~/code` for cloned repositories and `~/agent-logs` for recorded long-running sessions.
