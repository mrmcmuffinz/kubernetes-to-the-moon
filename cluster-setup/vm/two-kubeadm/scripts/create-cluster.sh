#!/usr/bin/env bash
#
# create-cluster.sh
#
# Provisions two headless Ubuntu 24.04 VMs (controlplane-1, nodes-1) for the two-kubeadm
# Kubernetes cluster lab. Both VMs attach to the host bridge br-vm from
# 01-host-bridge-setup.md (which references ../00-vlan-host-network-setup.md).
#
# Usage:
#   ./create-cluster.sh                                              # both VMs, default IPs
#   ./create-cluster.sh controlplane-1                               # one VM only
#   ./create-cluster.sh nodes-1                                      # one VM only
#   ./create-cluster.sh --gateway 192.168.100.1 \
#                       --cp-ip 192.168.100.10 \
#                       --worker-ip 192.168.100.11 \
#                       --apt-proxy-host 192.168.100.2               # override defaults

set -euo pipefail

# -------------------------------------------------------------------
# Configuration
# -------------------------------------------------------------------
BASE_DIR="$HOME/cka-lab"
IMAGE_DIR="$BASE_DIR/images"
CLUSTER_DIR="$BASE_DIR/two-kubeadm"

UBUNTU_VERSION="24.04"
IMAGE_FILE="$IMAGE_DIR/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"
IMAGE_URL="https://cloud-images.ubuntu.com/releases/${UBUNTU_VERSION}/release/ubuntu-${UBUNTU_VERSION}-server-cloudimg-amd64.img"

VCPUS=2
MEMORY_MB=4096
DISK_SIZE="40G"

VM_USER="kube"
VM_PASSWORD="kubeadmin"

BRIDGE="br-vm"
GATEWAY="192.168.100.1"
APT_PROXY_HOST="192.168.100.2"  # Host bridge IP (apt-cache proxy runs on the QEMU host)

# Per-node configuration
declare -A NODES=(
  [controlplane-1]="192.168.100.10"
  [nodes-1]="192.168.100.11"
)

# -------------------------------------------------------------------
# Argument overrides (override defaults without editing this file)
# -------------------------------------------------------------------
# Usage: ./create-cluster.sh [--gateway IP] [--cp-ip IP] [--worker-ip IP] [--apt-proxy-host IP] [node-name...]
NODE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gateway)       GATEWAY="${2:?--gateway requires a value}";              shift 2 ;;
    --cp-ip)         NODES[controlplane-1]="${2:?--cp-ip requires a value}";  shift 2 ;;
    --worker-ip)     NODES[nodes-1]="${2:?--worker-ip requires a value}";     shift 2 ;;
    --apt-proxy-host) APT_PROXY_HOST="${2:?--apt-proxy-host requires a value}"; shift 2 ;;
    --*)             echo "ERROR: Unknown option $1"; exit 1 ;;
    *)               NODE_ARGS+=("$1"); shift ;;
  esac
done

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

apt:
  preserve_sources_list: false
  sources_list: |
    Types: deb
    URIs: http://$APT_PROXY_HOST:3142/mirror.arizona.edu/ubuntu/
    Suites: noble noble-updates noble-backports noble-security
    Components: main restricted universe multiverse
    Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

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
      ${NODES[controlplane-1]} controlplane-1 controlplane-1.cka.local
      ${NODES[nodes-1]} nodes-1 nodes-1.cka.local
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
  - path: /etc/modules-load.d/9p.conf
    content: |
      9p
      9pnet_virtio
    permissions: '0644'
  - path: /etc/modules-load.d/k8s.conf
    content: |
      overlay
      br_netfilter
  - path: /etc/sysctl.d/k8s.conf
    content: |
      net.bridge.bridge-nf-call-iptables  = 1
      net.bridge.bridge-nf-call-ip6tables = 1
      net.ipv4.ip_forward                 = 1

mounts:
  - [bincache, /mnt/bincache, 9p, "trans=virtio,version=9p2000.L,nofail,_netdev", "0", "0"]

runcmd:
  - rm -f /etc/netplan/50-cloud-init.yaml
  - netplan apply
  - mkdir -p /etc/apt/keyrings
  - curl -fsSL http://$APT_PROXY_HOST:3142/pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - |
    cat > /etc/apt/sources.list.d/kubernetes.sources <<'KUBE_EOF'
    Types: deb
    URIs: http://$APT_PROXY_HOST:3142/pkgs.k8s.io/core:/stable:/v1.35/deb/
    Suites: /
    Components:
    Signed-By: /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    KUBE_EOF
  - apt-get update
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
    -virtfs local,path="${HOME}/cka-lab/binary-cache",mount_tag=bincache,security_model=none,id=bincache \\
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
if [[ ${#NODE_ARGS[@]} -eq 0 ]]; then
  for n in controlplane-1 nodes-1; do
    provision_node "$n"
  done
else
  for n in "${NODE_ARGS[@]}"; do
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
echo "  ssh ${VM_USER}@${NODES[controlplane-1]}   # controlplane-1"
echo "  ssh ${VM_USER}@${NODES[nodes-1]}   # nodes-1"
echo ""
echo "(Add a Host controlplane-1/nodes-1 entry to ~/.ssh/config for short names.)"
echo ""
echo "To stop both nodes:"
echo "  $CLUSTER_DIR/stop-cluster.sh"
echo "============================================="
