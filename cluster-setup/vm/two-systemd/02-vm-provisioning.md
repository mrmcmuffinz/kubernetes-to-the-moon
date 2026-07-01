# VM Provisioning for Two-Node Cluster

**Based on:** [01-qemu-vm-setup.md](../../vm/docs/01-qemu-vm-setup.md) from the single-node guide.

**Adapted for:** Two VMs on a host bridge instead of one VM with QEMU user-mode networking. Cloud-init now configures a static IP per VM and writes both nodes into `/etc/hosts` so name resolution works without DNS.

---

## What This Chapter Does

Creates two headless Ubuntu 24.04 VMs (`controlplane-1` and `nodes-1`) attached to the `br0` bridge from the previous document. Each VM gets a static IP via cloud-init, your SSH key, the `kube` user with passwordless sudo, kernel modules and sysctls for Kubernetes, and is rebooted once at the end of cloud-init so all changes take effect cleanly.

The single-node guide used QEMU user-mode networking and a single `create-node.sh` script. This guide uses bridge networking and a `create-cluster.sh` script that wraps `create-node.sh` to provision both VMs in a single command, plus cluster-level `start-cluster.sh` and `stop-cluster.sh`.

## What Was Removed from the Original Script

- **Port forwarding for SSH and component APIs.** No longer needed. With real IPs on the bridge, you SSH directly to `192.168.122.10` or `192.168.122.11`, and `kubectl` from the host points at `https://192.168.122.10:6443`.
- **`hostfwd` flags on the QEMU command line.** Replaced with `-netdev bridge,br=br0`.
- **`network: config: disabled`** in cloud-init. The single-node guide disabled cloud-init networking because QEMU user-mode handled DHCP. With a bridge, there is no DHCP server, so cloud-init writes a netplan file with the static IP.

## Prerequisites

The host bridge from document 01 must be active. Quick check:

```bash
ip addr show br0 | grep 'inet 192.168.122.1' && echo "bridge OK"
ls -la /usr/lib/qemu/qemu-bridge-helper | grep '^-rws' && echo "helper OK"
```

You also need an SSH key on the host. cloud-init injects the public key into both VMs.

```bash
# Check if you have a key
ls ~/.ssh/id_ed25519.pub 2>/dev/null || ls ~/.ssh/id_rsa.pub 2>/dev/null

# If not, generate one
ssh-keygen -t ed25519
```

The Ubuntu cloud image is reused from the single-node guide. If you do not have it cached:

```bash
mkdir -p ~/cka-lab/images
cd ~/cka-lab/images
wget https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
```

---

## Part 1: Directory Structure

The script creates the following layout:

```
~/cka-lab/
  images/                   # Cached cloud images (shared with single-node guide)
    ubuntu-24.04-server-cloudimg-amd64.img
  two-systemd/
    create-cluster.sh       # Provisions both VMs
    start-cluster.sh        # Starts both VMs
    stop-cluster.sh         # Stops both VMs cleanly
    destroy-cluster.sh      # Removes per-VM directories (keeps cached image)
    controlplane-1/
      controlplane-1.qcow2           # controlplane-1 disk (backed by cloud image)
      seed.iso              # Cloud-init ISO
      cloud-init/
        user-data
        meta-data
      start-controlplane-1.sh
      stop-controlplane-1.sh
    nodes-1/
      nodes-1.qcow2
      seed.iso
      cloud-init/
        user-data
        meta-data
      start-nodes-1.sh
      stop-nodes-1.sh
```

The `two-systemd/` parent directory keeps everything separate from the single-node `controlplane-1/` if you ever want to run both labs simultaneously.

---

## Part 2: The create-cluster.sh Script

Save the following as `~/cka-lab/two-systemd/create-cluster.sh` and make it executable.

```bash
#!/usr/bin/env bash
#
# create-cluster.sh
#
# Provisions two headless Ubuntu 24.04 VMs (controlplane-1, nodes-1) for the two-systemd
# Kubernetes cluster lab. Both VMs attach to the host bridge br0 from
# 01-host-bridge-setup.md.
#
# Usage:
#   ./create-cluster.sh           # Create both VMs
#   ./create-cluster.sh controlplane-1     # Create only controlplane-1
#   ./create-cluster.sh nodes-1     # Create only nodes-1

set -euo pipefail

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
BASE_DIR="$HOME/cka-lab"
IMAGE_DIR="$BASE_DIR/images"
CLUSTER_DIR="$BASE_DIR/two-systemd"

UBUNTU_VERSION="24.04"
IMAGE_FILE="$IMAGE_DIR/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
IMAGE_URL="https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"

VCPUS=2
MEMORY_MB=4096
DISK_SIZE="40G"

VM_USER="kube"
VM_PASSWORD="kubeadmin"

BRIDGE="br0"
GATEWAY="192.168.122.1"

# Per-node configuration
declare -A NODES=(
  [controlplane-1]="192.168.122.10"
  [nodes-1]="192.168.122.11"
)

# -------------------------------------------------------------------
# Preflight checks
# -------------------------------------------------------------------
echo "=== Preflight checks ==="

if [[ ! -e /dev/kvm ]]; then
  echo "ERROR: /dev/kvm not found. Is KVM enabled?"
  exit 1
fi

if ! command -v qemu-system-x86_64 &>/dev/null; then
  echo "ERROR: qemu-system-x86_64 not found. Install qemu-system-x86 first."
  exit 1
fi

if ! command -v genisoimage &>/dev/null; then
  echo "ERROR: genisoimage not found. Install genisoimage first."
  exit 1
fi

if ! ip link show "$BRIDGE" &>/dev/null; then
  echo "ERROR: Bridge $BRIDGE not found. See 01-host-bridge-setup.md."
  exit 1
fi

if ! ls -la /usr/lib/qemu/qemu-bridge-helper | grep -q '^-rws'; then
  echo "ERROR: qemu-bridge-helper is not setuid. Run:"
  echo "  sudo chmod u+s /usr/lib/qemu/qemu-bridge-helper"
  exit 1
fi

SSH_KEY_FILE=""
for candidate in ~/.ssh/id_ed25519.pub ~/.ssh/id_rsa.pub; do
  if [[ -f "$candidate" ]]; then
    SSH_KEY_FILE="$candidate"
    break
  fi
done

if [[ -z "$SSH_KEY_FILE" ]]; then
  echo "ERROR: No SSH public key found. Generate one with:"
  echo "  ssh-keygen -t ed25519"
  exit 1
fi

SSH_KEY="$(cat "$SSH_KEY_FILE")"
echo "Using SSH key: $SSH_KEY_FILE"
echo "All preflight checks passed."

# -------------------------------------------------------------------
# Cache the cloud image if missing
# -------------------------------------------------------------------
echo "=== Checking cloud image ==="
mkdir -p "$IMAGE_DIR"
if [[ -f "$IMAGE_FILE" ]]; then
  echo "Cloud image already cached: $IMAGE_FILE"
else
  echo "Downloading Ubuntu $UBUNTU_VERSION cloud image..."
  wget -O "$IMAGE_FILE" "$IMAGE_URL"
  echo "Download complete."
fi

# -------------------------------------------------------------------
# Function: provision_node
# -------------------------------------------------------------------
provision_node() {
  local node_name="$1"
  local node_ip="${NODES[$node_name]}"
  local node_dir="$CLUSTER_DIR/$node_name"

  echo ""
  echo "=== Provisioning $node_name ($node_ip) ==="

  # Per-node directory
  mkdir -p "$node_dir/cloud-init"

  # Disk
  if [[ -f "$node_dir/${node_name}.qcow2" ]]; then
    echo "WARNING: Disk $node_dir/${node_name}.qcow2 already exists."
    read -rp "Overwrite? (y/N): " confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
      echo "Skipping $node_name."
      return 0
    fi
  fi

  qemu-img create -f qcow2 \
    -b "$(realpath "$IMAGE_FILE")" \
    -F qcow2 \
    "$node_dir/${node_name}.qcow2" \
    "$DISK_SIZE"
  echo "Disk created: $node_dir/${node_name}.qcow2"

  # cloud-init metadata
  cat > "$node_dir/cloud-init/meta-data" <<EOF
instance-id: $node_name
local-hostname: $node_name
EOF

  # cloud-init user-data
  cat > "$node_dir/cloud-init/user-data" <<EOF
#cloud-config

hostname: $node_name
manage_etc_hosts: false
fqdn: ${node_name}.cka.local

users:
  - name: $VM_USER
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: "$VM_PASSWORD"
    ssh_authorized_keys:
      - $SSH_KEY

ssh_pwauth: true

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

write_files:
  - path: /etc/hosts
    content: |
      127.0.0.1 localhost
      192.168.122.10 controlplane-1 controlplane-1.cka.local
      192.168.122.11 nodes-1 nodes-1.cka.local
  - path: /etc/netplan/01-static.yaml
    permissions: '0600'
    content: |
      network:
        version: 2
        ethernets:
          enp0s2:
            dhcp4: false
            addresses: [$node_ip/24]
            routes:
              - to: default
                via: $GATEWAY
            nameservers:
              addresses: [1.1.1.1, 8.8.8.8]
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
  - netplan apply
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
  - swapoff -a
  - sed -i '/\sswap\s/s/^/#/' /etc/fstab

power_state:
  mode: reboot
  message: "Cloud-init complete. Rebooting to apply all configuration."
  timeout: 30
  condition: true
EOF

  # Build cloud-init ISO
  genisoimage -output "$node_dir/seed.iso" \
    -volid cidata -joliet -rock \
    "$node_dir/cloud-init/user-data" \
    "$node_dir/cloud-init/meta-data" 2>/dev/null
  echo "cloud-init ISO created: $node_dir/seed.iso"

  # Per-VM start script. The MAC address last octet matches the IP last
  # octet so each VM gets a stable, unique MAC.
  local mac_suffix
  mac_suffix=$(printf '%02x' "${node_ip##*.}")

  cat > "$node_dir/start-${node_name}.sh" <<STARTSCRIPT
#!/usr/bin/env bash
#
# Start the ${node_name} VM (daemonized).

set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"

qemu-system-x86_64 \\
    -name ${node_name} \\
    -machine type=q35,accel=kvm \\
    -cpu host \\
    -smp ${VCPUS} \\
    -m ${MEMORY_MB} \\
    -drive file="\$SCRIPT_DIR/${node_name}.qcow2",format=qcow2,if=virtio \\
    -drive file="\$SCRIPT_DIR/seed.iso",format=raw,if=virtio \\
    -netdev bridge,id=net0,br=${BRIDGE} \\
    -device virtio-net-pci,netdev=net0,mac=52:54:00:12:34:${mac_suffix} \\
    -display none \\
    -serial file:"\$SCRIPT_DIR/${node_name}-console.log" \\
    -daemonize \\
    -pidfile "\$SCRIPT_DIR/${node_name}.pid" \\
    "\$@"

echo "${node_name} started (PID \$(cat "\$SCRIPT_DIR/${node_name}.pid"))."
echo "Console log: \$SCRIPT_DIR/${node_name}-console.log"
STARTSCRIPT
  chmod +x "$node_dir/start-${node_name}.sh"

  # Per-VM stop script
  cat > "$node_dir/stop-${node_name}.sh" <<STOPSCRIPT
#!/usr/bin/env bash
#
# Stop the ${node_name} VM gracefully.

set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="\$SCRIPT_DIR/${node_name}.pid"

if [[ -f "\$PID_FILE" ]]; then
    PID=\$(cat "\$PID_FILE")
    if kill -0 "\$PID" 2>/dev/null; then
        echo "Sending SIGTERM to ${node_name} (PID \$PID)..."
        kill "\$PID"
        tail --pid="\$PID" -f /dev/null 2>/dev/null || true
        echo "${node_name} stopped."
    else
        echo "${node_name} is not running (stale PID file)."
    fi
    rm -f "\$PID_FILE"
else
    echo "No PID file found. ${node_name} may not be running."
fi
STOPSCRIPT
  chmod +x "$node_dir/stop-${node_name}.sh"

  echo "Provisioned: $node_name"
}

# -------------------------------------------------------------------
# Provision the requested nodes
# -------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  for n in controlplane-1 nodes-1; do
    provision_node "$n"
  done
else
  for n in "$@"; do
    if [[ -z "${NODES[$n]:-}" ]]; then
      echo "ERROR: Unknown node $n (expected: controlplane-1 or nodes-1)"
      exit 1
    fi
    provision_node "$n"
  done
fi

# -------------------------------------------------------------------
# Cluster-level scripts
# -------------------------------------------------------------------
cat > "$CLUSTER_DIR/start-cluster.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/controlplane-1/start-controlplane-1.sh"
"$SCRIPT_DIR/nodes-1/start-nodes-1.sh"
echo ""
echo "Both nodes started. First boot takes 60-90 seconds for cloud-init."
echo "Tail console logs to watch:"
echo "  tail -f $SCRIPT_DIR/controlplane-1/controlplane-1-console.log"
echo "  tail -f $SCRIPT_DIR/nodes-1/nodes-1-console.log"
EOF
chmod +x "$CLUSTER_DIR/start-cluster.sh"

cat > "$CLUSTER_DIR/stop-cluster.sh" <<'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/nodes-1/stop-nodes-1.sh" || true
"$SCRIPT_DIR/controlplane-1/stop-controlplane-1.sh" || true
echo "Both nodes stopped."
EOF
chmod +x "$CLUSTER_DIR/stop-cluster.sh"

cat > "$CLUSTER_DIR/destroy-cluster.sh" <<'EOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/stop-cluster.sh" 2>/dev/null || true
rm -rf "$SCRIPT_DIR/controlplane-1" "$SCRIPT_DIR/nodes-1"
echo "Cluster destroyed. Cached cloud image preserved at ~/cka-lab/images/."
echo "Rebuild with: $SCRIPT_DIR/create-cluster.sh"
EOF
chmod +x "$CLUSTER_DIR/destroy-cluster.sh"

# -------------------------------------------------------------------
# Summary
# -------------------------------------------------------------------
echo ""
echo "============================================="
echo "  Two-node cluster provisioned"
echo "============================================="
echo ""
echo "Cluster directory: $CLUSTER_DIR"
echo ""
echo "To start both nodes:"
echo "  $CLUSTER_DIR/start-cluster.sh"
echo ""
echo "To watch boot:"
echo "  tail -f $CLUSTER_DIR/controlplane-1/controlplane-1-console.log"
echo "  tail -f $CLUSTER_DIR/nodes-1/nodes-1-console.log"
echo ""
echo "First boot runs cloud-init and reboots. Allow 90 seconds."
echo ""
echo "After boot, SSH in:"
echo "  ssh ${VM_USER}@192.168.122.10   # controlplane-1"
echo "  ssh ${VM_USER}@192.168.122.11   # nodes-1"
echo ""
echo "(Add a Host controlplane-1/nodes-1 entry to ~/.ssh/config for short names.)"
echo ""
echo "To stop both nodes:"
echo "  $CLUSTER_DIR/stop-cluster.sh"
echo "============================================="
```

---

## Part 3: Run the Script

```bash
mkdir -p ~/cka-lab/two-systemd
cd ~/cka-lab/two-systemd

# Save the script above as create-cluster.sh
chmod +x create-cluster.sh

# Provision both VMs
./create-cluster.sh

# Boot them
./start-cluster.sh

# Watch first boot. Cloud-init runs, reboots, then the second boot finishes.
tail -f controlplane-1/controlplane-1-console.log
# Ctrl-C once you see a login prompt, then check nodes-1 the same way.
```

---

## Part 4: Configure SSH Access

Add the following to `~/.ssh/config` on the host so `ssh controlplane-1` and `ssh nodes-1` work without flags:

```ssh-config
Host controlplane-1
    HostName 192.168.122.10
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host nodes-1
    HostName 192.168.122.11
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
```

If your SSH key is at a different path, adjust the `IdentityFile` line accordingly.

---

## Part 5: Verify Both VMs

After cloud-init completes (60 to 90 seconds for the first boot, plus the reboot), verify everything is in place. Run from the host:

```bash
# Both VMs respond to ping
ping -c 2 192.168.122.10
ping -c 2 192.168.122.11

# SSH works to both
ssh controlplane-1 'hostname && ip -4 addr show enp0s2 | grep inet'
ssh nodes-1 'hostname && ip -4 addr show enp0s2 | grep inet'

# Each node can resolve and reach the other by name
ssh controlplane-1 'ping -c 2 nodes-1'
ssh nodes-1 'ping -c 2 controlplane-1'

# Both have internet via NAT
ssh controlplane-1 'curl -sI -o /dev/null -w "%{http_code}\n" https://kubernetes.io'
ssh nodes-1 'curl -sI -o /dev/null -w "%{http_code}\n" https://kubernetes.io'

# Cloud-init reports done
ssh controlplane-1 'cloud-init status'
ssh nodes-1 'cloud-init status'
```

All checks should pass before moving to document 03.

### What Cloud-Init Pre-Configures

Same set as the single-node guide, plus the static IP. On both VMs after first boot:

- Hostname set to `controlplane-1` or `nodes-1`
- `/etc/hosts` populated with both nodes for name resolution without DNS
- Static IP assigned via netplan, bound to interface `enp0s2`
- `kube` user created with passwordless sudo and your SSH key authorized
- Baseline packages installed (`socat`, `conntrack`, `ipset`, `curl`, `jq`, others)
- `overlay` and `br_netfilter` kernel modules loaded
- Sysctls set for bridge filtering and IPv4 forwarding
- Swap disabled permanently
- Reboot once after cloud-init to apply everything cleanly

The cloud-init config does not install containerd, runc, kubeadm, kubelet, or kubectl. Those are installed manually in document 03.

---

## Summary

The two VMs are now provisioned and accessible:

| VM | Role (assigned later) | IP | SSH Alias |
|----|------------------------|----|-----------|
| `controlplane-1` | Control plane | `192.168.122.10` | `ssh controlplane-1` |
| `nodes-1` | Worker | `192.168.122.11` | `ssh nodes-1` |

All cluster-level lifecycle commands:

| Command | Purpose |
|---------|---------|
| `~/cka-lab/two-systemd/start-cluster.sh` | Boot both VMs |
| `~/cka-lab/two-systemd/stop-cluster.sh` | Graceful shutdown |
| `~/cka-lab/two-systemd/destroy-cluster.sh` | Remove disks and seed ISOs (keeps cached image) |
| `~/cka-lab/two-systemd/create-cluster.sh` | Re-provision (after destroy, or on first run) |

The next document installs the container runtime and `kubeadm` toolchain on both nodes.
