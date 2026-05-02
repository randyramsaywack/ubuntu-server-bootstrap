#!/usr/bin/env bash
set -Eeuo pipefail

VMID="${VMID:-9000}"
VM_NAME="${VM_NAME:-ubuntu-2404-cloudinit}"
STORAGE="${STORAGE:-local-lvm}"
SNIPPET_STORAGE="${SNIPPET_STORAGE:-local}"
SNIPPET_NAME="${SNIPPET_NAME:-ubuntu-server-bootstrap.yaml}"
BRIDGE="${BRIDGE:-vmbr0}"
MEMORY="${MEMORY:-2048}"
CORES="${CORES:-2}"
DISK_SIZE="${DISK_SIZE:-32G}"
IMAGE_URL="${IMAGE_URL:-https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img}"
IMAGE_DIR="${IMAGE_DIR:-/var/lib/vz/template/iso}"
IMAGE_PATH="${IMAGE_PATH:-${IMAGE_DIR}/noble-server-cloudimg-amd64.img}"

info() { printf '[INFO] %s\n' "$*"; }
ok() { printf '[OK] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; }
done_msg() { printf '[DONE] %s\n' "$*"; }

on_error() {
  local line_number="$1"
  fail "Template creation failed near line ${line_number}."
}

trap 'on_error "$LINENO"' ERR

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    fail "Run this script as root on a Proxmox VE node."
    exit 1
  fi
}

require_proxmox_tools() {
  local commands=(qm pvesm curl)

  for command in "${commands[@]}"; do
    if ! command -v "$command" >/dev/null 2>&1; then
      fail "Required command not found: ${command}"
      exit 1
    fi
  done

  ok "Required Proxmox tools are available."
}

validate_inputs() {
  if qm status "$VMID" >/dev/null 2>&1; then
    fail "VMID ${VMID} already exists. Choose another VMID or remove the existing VM/template first."
    exit 1
  fi

  if ! pvesm status --storage "$STORAGE" >/dev/null 2>&1; then
    fail "Storage ${STORAGE} was not found."
    exit 1
  fi

  if ! pvesm status --storage "$SNIPPET_STORAGE" >/dev/null 2>&1; then
    fail "Snippet storage ${SNIPPET_STORAGE} was not found."
    exit 1
  fi

  ok "Inputs validated."
}

download_cloud_image() {
  install -m 0755 -d "$IMAGE_DIR"

  if [[ -s "$IMAGE_PATH" ]]; then
    ok "Cloud image already exists at ${IMAGE_PATH}."
    return
  fi

  info "Downloading Ubuntu 24.04 cloud image."
  curl -fL "$IMAGE_URL" -o "$IMAGE_PATH"
  ok "Downloaded ${IMAGE_PATH}."
}

create_vm() {
  info "Creating Proxmox VM ${VMID} (${VM_NAME})."
  qm create "$VMID" \
    --name "$VM_NAME" \
    --ostype l26 \
    --machine q35 \
    --cpu host \
    --cores "$CORES" \
    --memory "$MEMORY" \
    --net0 "virtio,bridge=${BRIDGE}" \
    --scsihw virtio-scsi-single \
    --agent enabled=1

  ok "VM shell created."
}

import_cloud_disk() {
  info "Importing cloud image into ${STORAGE}."
  qm importdisk "$VMID" "$IMAGE_PATH" "$STORAGE"

  local imported_disk
  imported_disk="$(qm config "$VMID" | awk -F': ' '/^unused[0-9]+:/{print $2; exit}')"

  if [[ -z "$imported_disk" ]]; then
    fail "Could not find imported disk in VM config."
    exit 1
  fi

  qm set "$VMID" --scsi0 "${imported_disk},discard=on,ssd=1"
  qm resize "$VMID" scsi0 "$DISK_SIZE"
  ok "Imported and resized boot disk to ${DISK_SIZE}."
}

configure_cloud_init() {
  info "Adding cloud-init drive and boot settings."
  qm set "$VMID" --ide2 "${STORAGE}:cloudinit"
  qm set "$VMID" --boot order=scsi0
  qm set "$VMID" --serial0 socket --vga serial0
  qm set "$VMID" --ipconfig0 ip=dhcp
  ok "Cloud-init and console settings configured."
}

attach_custom_snippet_if_present() {
  local snippet_path="/var/lib/vz/snippets/${SNIPPET_NAME}"

  if [[ "$SNIPPET_STORAGE" != "local" ]]; then
    warn "Automatic snippet path check only supports local storage. Skipping cicustom attachment check."
    return
  fi

  if [[ -f "$snippet_path" ]]; then
    qm set "$VMID" --cicustom "user=${SNIPPET_STORAGE}:snippets/${SNIPPET_NAME}"
    ok "Attached cloud-init snippet ${SNIPPET_STORAGE}:snippets/${SNIPPET_NAME}."
  else
    warn "Snippet not found at ${snippet_path}; template created without custom user-data."
    warn "Copy cloud-init.local.yaml there later and run: qm set ${VMID} --cicustom \"user=${SNIPPET_STORAGE}:snippets/${SNIPPET_NAME}\""
  fi
}

convert_to_template() {
  info "Converting VM ${VMID} to a template."
  qm template "$VMID"
  done_msg "Template ${VMID} (${VM_NAME}) is ready."
}

print_next_steps() {
  cat <<EOF

[INFO] Next steps
Clone the template:
  qm clone ${VMID} 101 --name ubuntu-test-01 --full true

Start the clone:
  qm start 101

Check cloud-init output inside the VM:
  sudo cloud-init status --long
  sudo tail -n 100 /var/log/cloud-init-output.log
  sudo tail -n 100 /var/log/ubuntu-base-setup.log
EOF
}

main() {
  require_root
  require_proxmox_tools
  validate_inputs
  download_cloud_image
  create_vm
  import_cloud_disk
  configure_cloud_init
  attach_custom_snippet_if_present
  convert_to_template
  print_next_steps
}

main "$@"
