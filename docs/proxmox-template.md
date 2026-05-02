# Proxmox Ubuntu 24.04 Cloud-Init Template

This guide creates a reusable Ubuntu 24.04 cloud-init template on a Proxmox VE node. The template is designed to work with this repository's bootstrap cloud-init user-data.

## What It Builds

- Ubuntu 24.04 Noble cloud image template
- Q35 machine type
- VirtIO network adapter
- VirtIO SCSI boot disk
- Cloud-init drive
- DHCP networking
- Serial console
- QEMU Guest Agent enabled in Proxmox
- Optional attachment of this repo's cloud-init snippet

## Prerequisites

Run these steps on a Proxmox VE node as `root`.

Confirm your target storage names:

```bash
pvesm status
```

Common defaults:

- VM disk storage: `local-lvm`
- Snippet storage: `local`
- Bridge: `vmbr0`

Enable snippets on `local` storage in the Proxmox UI:

```text
Datacenter -> Storage -> local -> Edit -> Content -> Snippets
```

## Add Your Cloud-Init Snippet

From your workstation, copy your ignored local deployment file to the Proxmox node:

```bash
scp cloud-init.local.yaml root@PROXMOX-HOST:/var/lib/vz/snippets/ubuntu-server-bootstrap.yaml
```

The public `docs/cloud-init-example.yaml` should keep placeholders. Your real SSH key belongs in `cloud-init.local.yaml`.

## Create The Template

Copy the template script to your Proxmox node:

```bash
scp scripts/create-proxmox-ubuntu-template.sh root@PROXMOX-HOST:/root/create-proxmox-ubuntu-template.sh
```

Run it on the Proxmox node:

```bash
chmod +x /root/create-proxmox-ubuntu-template.sh
/root/create-proxmox-ubuntu-template.sh
```

By default, the script creates VMID `9000` named `ubuntu-2404-cloudinit`.

## Customize Template Settings

Override settings with environment variables:

```bash
VMID=9024 \
VM_NAME=ubuntu-2404-bootstrap \
STORAGE=local-lvm \
SNIPPET_STORAGE=local \
BRIDGE=vmbr0 \
MEMORY=4096 \
CORES=2 \
DISK_SIZE=40G \
/root/create-proxmox-ubuntu-template.sh
```

The script downloads the official Ubuntu Noble cloud image from:

```text
https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
```

## Clone And Test

Create a test VM from the template:

```bash
qm clone 9000 101 --name ubuntu-test-01 --full true
qm start 101
```

After the VM boots, SSH in as the user from `cloud-init.local.yaml`, then check:

```bash
sudo cloud-init status --long
sudo tail -n 100 /var/log/cloud-init-output.log
sudo tail -n 100 /var/log/ubuntu-base-setup.log
sudo systemctl status qemu-guest-agent chrony fail2ban docker ssh --no-pager
```

## Attach Or Update The Snippet Later

If you copy the snippet after creating the template, attach it manually:

```bash
qm set 9000 --cicustom "user=local:snippets/ubuntu-server-bootstrap.yaml"
```

Regenerate the cloud-init drive for an existing clone after changing cloud-init settings:

```bash
qm cloudinit update 101
```

For a clean test, it is usually simpler to destroy the test clone and create a fresh clone from the template.
