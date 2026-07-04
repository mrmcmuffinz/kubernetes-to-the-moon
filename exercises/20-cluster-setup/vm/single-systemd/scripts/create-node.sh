#!/usr/bin/env bash
#
# create-node.sh
#
# Creates a single headless Ubuntu 24.04 VM for CKA exam prep using QEMU/KVM.
# Uses cloud-init for automated first-boot configuration and user-mode networking
# with port forwarding for host-to-VM access.
#
# Usage: ./create-node.sh [node-name]
#   node-name defaults to "controlplane-1" if not provided.

set -euo pipefail

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
NODE_NAME="${1:-controlplane-1}"
BASE_DIR="$HOME/cka-lab"
IMAGE_DIR="$BASE_DIR/images"
NODE_DIR="$BASE_DIR/$NODE_NAME"

# VM resources
VCPUS=2
MEMORY_MB=4096
DISK_SIZE="40G"

# Ubuntu cloud image
UBUNTU_VERSION="24.04"
IMAGE_URL="https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
IMAGE_FILE="$IMAGE_DIR/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"

# Networking (user-mode with port forwarding)
SSH_HOST_PORT=2222
HOST_IP="127.0.0.1"

# VM user credentials
VM_USER="kube"
VM_PASSWORD="kubeadmin"

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------
echo "=== Preflight checks ==="

if [[ ! -e /dev/kvm ]]; then
    echo "ERROR: /dev/kvm not found. Is KVM enabled? See Part 1 of the setup guide."
    exit 1
fi

if ! command -v qemu-system-x86_64 &>/dev/null; then
    echo "ERROR: qemu-system-x86_64 not found. Install qemu-system-x86 first."
    exit 1
fi

if ! command -v qemu-img &>/dev/null; then
    echo "ERROR: qemu-img not found. Install qemu-utils first."
    exit 1
fi

if ! command -v genisoimage &>/dev/null; then
    echo "ERROR: genisoimage not found. Install genisoimage first."
    exit 1
fi

echo "All preflight checks passed."

# -------------------------------------------------------------------
# Create directory structure
# -------------------------------------------------------------------
echo "=== Setting up directories ==="
mkdir -p "$IMAGE_DIR"
mkdir -p "$NODE_DIR/cloud-init"

# -------------------------------------------------------------------
# Download Ubuntu cloud image (if not already cached)
# -------------------------------------------------------------------
echo "=== Checking cloud image ==="
if [[ -f "$IMAGE_FILE" ]]; then
    echo "Cloud image already downloaded: $IMAGE_FILE"
else
    echo "Downloading Ubuntu $UBUNTU_VERSION cloud image..."
    wget -O "$IMAGE_FILE" "$IMAGE_URL"
    echo "Download complete."
fi

# -------------------------------------------------------------------
# Create VM disk (backed by cloud image)
# -------------------------------------------------------------------
create_qcow2() {
  qemu-img create -f qcow2 \
      -b "$(realpath "$IMAGE_FILE")" \
      -F qcow2 \
      "$NODE_DIR/${NODE_NAME}.qcow2" \
      "$DISK_SIZE"
  echo "VM disk created: $NODE_DIR/${NODE_NAME}.qcow2 ($DISK_SIZE, backed by cloud image)"
}

echo "=== Creating VM disk ==="
if [[ -f "$NODE_DIR/${NODE_NAME}.qcow2" ]]; then
    echo "WARNING: Disk $NODE_DIR/${NODE_NAME}.qcow2 already exists."
    confirm=""
    read -rt 10 -p "Overwrite? (y/N, default N in 10s): " confirm || confirm=""
    if [[ "${confirm,,}" == "y" ]]; then
        create_qcow2
    else
        echo "Keeping existing disk. Continuing with cloud-init and script generation."
    fi
else
    create_qcow2
fi


# -------------------------------------------------------------------
# Generate cloud-init configuration
# -------------------------------------------------------------------
echo "=== Generating cloud-init config ==="

cat > "$NODE_DIR/cloud-init/meta-data" <<EOF
instance-id: ${NODE_NAME}
local-hostname: ${NODE_NAME}
EOF

cat > "$NODE_DIR/cloud-init/user-data" <<EOF
#cloud-config

hostname: ${NODE_NAME}
manage_etc_hosts: true
fqdn: ${NODE_NAME}.cka.local

users:
  - name: ${VM_USER}
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: "${VM_PASSWORD}"
    ssh_authorized_keys: []

# Enable password-based SSH (for initial access before keys are set up)
ssh_pwauth: true

# Disable cloud-init network config to avoid conflicts
# (QEMU user-mode networking handles DHCP automatically)
network:
  config: disabled

# Install baseline packages useful for Kubernetes setup
packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release
  - socat
  - conntrack
  - ipset
  - net-tools
  - jq
  - bash-completion
  - golang-cfssl

# Kernel modules and sysctl settings required by Kubernetes
write_files:
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter

  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

runcmd:
  # Load kernel modules
  - modprobe overlay
  - modprobe br_netfilter
  # Apply sysctl settings
  - sysctl --system
  # Disable swap (Kubernetes requirement)
  - swapoff -a
  - sed -i '/\sswap\s/s/^/#/' /etc/fstab

# Reboot after cloud-init completes to ensure all changes take effect
power_state:
  mode: reboot
  message: "Cloud-init complete. Rebooting to apply all configuration."
  timeout: 30
  condition: true
EOF

echo "cloud-init config written to $NODE_DIR/cloud-init/"

# -------------------------------------------------------------------
# Build cloud-init ISO
# -------------------------------------------------------------------
echo "=== Building cloud-init ISO ==="

genisoimage -output "$NODE_DIR/seed.iso" \
    -volid cidata \
    -joliet \
    -rock \
    "$NODE_DIR/cloud-init/user-data" \
    "$NODE_DIR/cloud-init/meta-data"

echo "Cloud-init ISO created: $NODE_DIR/seed.iso"

# -------------------------------------------------------------------
# Generate the VM start script
# -------------------------------------------------------------------
echo "=== Generating VM start script ==="

cat > "$NODE_DIR/start-${NODE_NAME}.sh" <<STARTSCRIPT
#!/usr/bin/env bash
#
# Start the ${NODE_NAME} VM (daemonized).
# The VM forks to the background automatically.
# Console log: tail -f \$SCRIPT_DIR/${NODE_NAME}-console.log
# SSH: ssh ${VM_USER}@${HOST_IP} -p ${SSH_HOST_PORT}

set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

qemu-system-x86_64 \\
    -name ${NODE_NAME} \\
    -machine type=q35,accel=kvm \\
    -cpu host \\
    -smp ${VCPUS} \\
    -m ${MEMORY_MB} \\
    -drive file="\$SCRIPT_DIR/${NODE_NAME}.qcow2",format=qcow2,if=virtio \\
    -drive file="\$SCRIPT_DIR/seed.iso",format=raw,if=virtio \\
    -netdev user,id=net0,hostfwd=tcp::${SSH_HOST_PORT}-:22,hostfwd=tcp::6443-:6443,hostfwd=tcp::2379-:2379,hostfwd=tcp::2380-:2380,hostfwd=tcp::10250-:10250,hostfwd=tcp::10257-:10257,hostfwd=tcp::10259-:10259 \\
    -device virtio-net-pci,netdev=net0 \\
    -display none \\
    -serial file:"\$SCRIPT_DIR/${NODE_NAME}-console.log" \\
    -daemonize \\
    -pidfile "\$SCRIPT_DIR/${NODE_NAME}.pid" \\
    "\$@"

echo "${NODE_NAME} started (PID \$(cat "\$SCRIPT_DIR/${NODE_NAME}.pid"))."
echo "Console log: \$SCRIPT_DIR/${NODE_NAME}-console.log"
STARTSCRIPT

chmod +x "$NODE_DIR/start-${NODE_NAME}.sh"

echo "Start script created: $NODE_DIR/start-${NODE_NAME}.sh"

# -------------------------------------------------------------------
# Generate the VM stop script
# -------------------------------------------------------------------
cat > "$NODE_DIR/stop-${NODE_NAME}.sh" <<STOPSCRIPT
#!/usr/bin/env bash
#
# Stop the ${NODE_NAME} VM gracefully.

set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="\$SCRIPT_DIR/${NODE_NAME}.pid"

if [[ -f "\$PID_FILE" ]]; then
    PID=\$(cat "\$PID_FILE")
    if kill -0 "\$PID" 2>/dev/null; then
        echo "Sending SIGTERM to ${NODE_NAME} (PID \$PID)..."
        kill "\$PID"
        echo "Waiting for process to exit..."
        tail --pid="\$PID" -f /dev/null 2>/dev/null || true
        echo "${NODE_NAME} stopped."
    else
        echo "${NODE_NAME} is not running (stale PID file)."
    fi
    rm -f "\$PID_FILE"
else
    echo "No PID file found. ${NODE_NAME} may not be running."
fi
STOPSCRIPT

chmod +x "$NODE_DIR/stop-${NODE_NAME}.sh"

echo "Stop script created: $NODE_DIR/stop-${NODE_NAME}.sh"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo ""
echo "============================================="
echo "  VM setup complete: ${NODE_NAME}"
echo "============================================="
echo ""
echo "Directory:   $NODE_DIR"
echo "Disk:        $NODE_DIR/${NODE_NAME}.qcow2 ($DISK_SIZE)"
echo "vCPUs:       $VCPUS"
echo "Memory:      ${MEMORY_MB}MB"
echo "VM user:     $VM_USER"
echo "VM password: $VM_PASSWORD"
echo ""
echo "To start the VM:"
echo "  $NODE_DIR/start-${NODE_NAME}.sh"
echo ""
echo "To watch the boot process:"
echo "  tail -f $NODE_DIR/${NODE_NAME}-console.log"
echo ""
echo "To SSH into the VM (after boot completes, ~60-90 seconds):"
echo "  ssh ${VM_USER}@${HOST_IP} -p ${SSH_HOST_PORT}"
echo ""
echo "To stop the VM:"
echo "  $NODE_DIR/stop-${NODE_NAME}.sh"
echo ""
echo "First boot will run cloud-init and reboot once."
echo "Wait for the second boot to complete before SSHing in."
echo "============================================="
