# QEMU Environment Setup and Single-Node VM for CKA Exam Prep

**Purpose:** Stand up a headless Ubuntu VM on the local Ubuntu 24.04 host using QEMU/KVM, suitable for a from-scratch Kubernetes installation. This is step 1 of 3 in an incremental cluster build-out (1-node, 2-node, 3-node).

**Networking goal:** Two forms of host-to-VM access. First, SSH into the VM from the host for interactive administration. Second, direct host-side access to all Kubernetes component APIs (API server, etcd, kubelet, controller-manager, scheduler) via port forwarding, so that tools like `kubectl` and `curl` running on the QEMU host can reach the cluster without SSHing into the VM first. Both are achieved through QEMU user-mode networking with forwarded ports.

**Scope boundary:** This document covers QEMU verification, VM creation, and host-to-VM connectivity. Kubernetes installation and configuration are handled separately by the administrator.

---

## Part 1: QEMU/KVM Verification and Setup

Since QEMU was previously installed but has not been used in several months, the safest approach is to verify each layer from the bottom up: CPU virtualization support, kernel module, packages, and user permissions. If anything is missing or broken, the fix is included inline.

### Step 1: Verify CPU Virtualization Support

The host CPU must support hardware virtualization (Intel VT-x or AMD-V). This is a BIOS/UEFI-level setting that cannot be fixed from software if it is disabled.

```bash
# Check for virtualization flags in /proc/cpuinfo.
# Intel CPUs show "vmx", AMD CPUs show "svm".
grep -Eoc '(vmx|svm)' /proc/cpuinfo
```

If the output is 0, virtualization is disabled in the BIOS/UEFI. Reboot into firmware settings and enable Intel VT-x or AMD-V before continuing.

If the output is a positive number (matching the number of CPU threads), hardware virtualization is available and you can proceed.

### Step 2: Verify or Install the KVM Kernel Module

KVM is the kernel-level hypervisor that QEMU uses for near-native performance. Without it, QEMU falls back to software emulation, which is unusably slow for a Kubernetes node.

```bash
# Check if the KVM module is loaded.
lsmod | grep kvm
```

You should see `kvm_intel` (Intel) or `kvm_amd` (AMD) along with the base `kvm` module. If the modules are not loaded, load them manually and verify:

```bash
sudo modprobe kvm
sudo modprobe kvm_intel   # or kvm_amd for AMD CPUs
lsmod | grep kvm
```

If `modprobe` fails, the kernel headers or KVM modules may not be installed. The package installation in the next step will resolve this.

### Step 3: Install or Reinstall QEMU and Supporting Packages

Rather than troubleshooting a potentially stale installation, reinstall the full package set to ensure everything is current and consistent.

```bash
sudo apt update
sudo apt install -y \
  qemu-system-x86 \
  qemu-utils \
  libvirt-daemon-system \
  libvirt-clients \
  bridge-utils \
  virtinst \
  cloud-image-utils \
  genisoimage
```

Package purposes:

- `qemu-system-x86` is the core QEMU emulator for x86_64 guests.
- `qemu-utils` provides `qemu-img` for disk image creation and conversion.
- `libvirt-daemon-system` and `libvirt-clients` provide `virsh` and the libvirt management layer (useful for the multi-node steps later, optional for step 1).
- `bridge-utils` provides `brctl` for creating network bridges (needed for multi-node).
- `virtinst` provides `virt-install` as an alternative VM creation method.
- `cloud-image-utils` and `genisoimage` are used to build the cloud-init ISO that configures the VM on first boot.

### Step 4: Verify User Permissions

Your user account needs membership in the `kvm` and `libvirt` groups to access `/dev/kvm` and manage VMs without `sudo`.

```bash
# Check current group membership.
groups $USER
```

If `kvm` or `libvirt` are missing from the output, add them:

```bash
sudo usermod -aG kvm $USER
sudo usermod -aG libvirt $USER
```

After adding groups, either log out and back in, or use `newgrp kvm` in the current shell for immediate effect.

### Step 5: Smoke Test

Run a quick validation to confirm that QEMU can access KVM acceleration.

```bash
# This should print "kvm" or "KVM" and exit cleanly.
qemu-system-x86_64 -accel help 2>&1 | grep -i kvm
```

If you see `kvm` in the output, the QEMU/KVM stack is functional and ready for VM creation.

As a deeper check, verify direct access to `/dev/kvm`:

```bash
ls -la /dev/kvm
# Should show crw-rw---- with group "kvm".
```

If permissions are correct and your user is in the `kvm` group, you are clear to proceed to Part 2.

---

## Part 2: Single-Node VM Creation Script

This section provides a self-contained script that creates a headless Ubuntu VM using a cloud image and cloud-init for automated first-boot configuration. The VM uses QEMU user-mode networking with port forwarding, which is the simplest option for a single node and requires no host network reconfiguration.

### Networking Approach

For a single-node setup, QEMU's user-mode networking (SLiRP) is the path of least resistance. It provides:

- NAT-based outbound internet access from the VM (for `apt install`, downloading binaries, etc.)
- Port forwarding from the host to specific VM ports (SSH, Kubernetes API server, etcd, kubelet)
- No bridge interfaces, no iptables rules, no host network disruption

The tradeoff is that user-mode networking does not support VM-to-VM communication, which is why steps 2 and 3 (multi-node) will switch to bridge networking. For the single-node case, port forwarding is sufficient.

**Port forwarding map:**

| Host Port | VM Port | Service            |
|-----------|---------|--------------------|
| 2222      | 22      | SSH                |
| 6443      | 6443    | Kubernetes API     |
| 2379      | 2379    | etcd client        |
| 2380      | 2380    | etcd peer          |
| 10250     | 10250   | kubelet            |
| 10257     | 10257   | kube-controller-manager |
| 10259     | 10259   | kube-scheduler     |
| 30000-30100 | 30000-30100 | NodePort range (subset) |

Note: QEMU user-mode networking does not support forwarding port ranges in a single flag. The script forwards a small set of representative NodePort ports. If you need a specific NodePort during testing, add it to the forwarding flags.

### Directory Structure

The script creates the following layout under a configurable base directory:

```
~/cka-lab/
  images/                 # Downloaded cloud images (shared across VMs)
  controlplane-1/                  # Per-node directory
    controlplane-1.qcow2           # VM disk (backed by cloud image)
    seed.iso              # Cloud-init ISO
    cloud-init/           # cloud-init source files
      user-data
      meta-data
```

### The Script

Save the following as `create-node.sh` and make it executable with `chmod +x create-node.sh`.

```bash
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
echo "=== Creating VM disk ==="
if [[ -f "$NODE_DIR/${NODE_NAME}.qcow2" ]]; then
    echo "WARNING: Disk $NODE_DIR/${NODE_NAME}.qcow2 already exists."
    read -rp "Overwrite? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Aborting."
        exit 1
    fi
fi

qemu-img create -f qcow2 \
    -b "$(realpath "$IMAGE_FILE")" \
    -F qcow2 \
    "$NODE_DIR/${NODE_NAME}.qcow2" \
    "$DISK_SIZE"

echo "VM disk created: $NODE_DIR/${NODE_NAME}.qcow2 ($DISK_SIZE, backed by cloud image)"

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
```

### Usage

After saving and making the script executable, run it with the default node name:

```bash
chmod +x create-node.sh
./create-node.sh
```

Or specify a custom node name:

```bash
./create-node.sh controlplane
```

The script will download the Ubuntu cloud image on the first run (cached for subsequent VMs), create the disk and cloud-init ISO, and generate start/stop helper scripts.

### Starting and Accessing the VM

**Start the VM** (daemonizes automatically, returns control to your shell immediately):

```bash
~/cka-lab/controlplane-1/start-controlplane-1.sh
```

**Watch the boot process** by tailing the console log. This is especially useful on first boot to confirm cloud-init completes successfully:

```bash
tail -f ~/cka-lab/controlplane-1/controlplane-1-console.log
```

**SSH into the VM** once boot completes (approximately 60 to 90 seconds on first boot, faster on subsequent boots):

```bash
ssh kube@127.0.0.1 -p 2222
```

The default credentials are user `kube` with password `kubeadmin`. You should add your SSH public key and disable password authentication once you have confirmed access.

**Stop the VM gracefully:**

```bash
~/cka-lab/controlplane-1/stop-controlplane-1.sh
```

### What Cloud-Init Pre-Configures

The cloud-init configuration handles the baseline OS setup so that the VM is ready for a Kubernetes installation when you SSH in. Specifically, it performs the following:

- Sets the hostname to the node name (e.g., `controlplane-1`).
- Creates the `kube` user with passwordless sudo.
- Enables password-based SSH for initial access.
- Installs prerequisite packages that `kubeadm`, `kubelet`, and container runtimes commonly require: `socat`, `conntrack`, `ipset`, `curl`, `jq`, and others.
- Loads the `overlay` and `br_netfilter` kernel modules required by container networking.
- Configures sysctl parameters for bridge networking and IP forwarding.
- Disables swap permanently (Kubernetes refuses to start with swap enabled).
- Reboots once to ensure all changes take effect cleanly.

The cloud-init config intentionally does **not** install containerd, runc, kubeadm, kubelet, or kubectl. Those are left for you to install and configure manually, which is the point of the exercise.

### Verifying the VM is Ready

After SSHing in, run through these checks to confirm the VM is in the expected state before starting your Kubernetes installation:

```bash
# Hostname should match the node name
hostname

# Swap should be off
free -h
# The Swap line should show all zeros

# Kernel modules should be loaded
lsmod | grep br_netfilter
lsmod | grep overlay

# IP forwarding should be enabled
sysctl net.ipv4.ip_forward
# Expected: net.ipv4.ip_forward = 1

# Bridge netfilter should be enabled
sysctl net.bridge.bridge-nf-call-iptables
# Expected: net.bridge.bridge-nf-call-iptables = 1

# Required packages should be installed
dpkg -l | grep -E 'socat|conntrack|ipset'
```

### Accessing Kubernetes Components from the Host

Once you have Kubernetes installed and running inside the VM, you can reach its components from the host through the forwarded ports:

```bash
# API server (after kubeadm init or manual setup)
curl -k https://127.0.0.1:6443/healthz

# etcd health (if etcd is configured to listen on all interfaces)
curl http://127.0.0.1:2379/health

# kubectl from the host (copy the kubeconfig from the VM first)
scp -P 2222 kube@127.0.0.1:~/.kube/config ~/.kube/cka-controlplane-1-config
KUBECONFIG=~/.kube/cka-controlplane-1-config kubectl get nodes
```

Note that for `kubectl` from the host to work, the kubeconfig's `server` field must point to `https://127.0.0.1:6443` (which it will, since that is the forwarded port). If `kubeadm init` writes the internal VM IP instead, update the kubeconfig after copying it.

---

## Looking Ahead: Steps 2 and 3

When you are ready to expand to a multi-node cluster, the main change is the networking layer. User-mode networking does not allow VM-to-VM communication, so the multi-node setup will switch to a Linux bridge with TAP devices. Each VM will get a static IP on a shared subnet, and all nodes will be able to reach each other directly.

The cloud-init config, disk management, and VM resource allocation patterns from this script will carry forward with minimal changes. The primary additions for steps 2 and 3 will be:

- A shared bridge interface on the host (e.g., `cka-br0` on a `10.0.100.0/24` subnet).
- TAP devices per VM instead of user-mode networking.
- Static IP assignment via cloud-init network config.
- Adjusted port forwarding or host routing to reach each node.

Those will be addressed in a separate document when you are ready to move past the single-node setup.
