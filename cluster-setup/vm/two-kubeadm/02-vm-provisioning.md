# VM Provisioning for Two-Node Cluster

**Based on:** [01-qemu-vm-setup.md](../../vm/docs/01-qemu-vm-setup.md) from the single-node guide.

**Adapted for:** Two VMs on a host bridge instead of one VM with QEMU user-mode networking. Cloud-init now configures a static IP per VM via a `network-config` seed file and writes both nodes into `/etc/hosts` so name resolution works without DNS.

---

## What This Chapter Does

Creates two headless Ubuntu 24.04 VMs (`controlplane-1` and `nodes-1`) attached to the `br-vm` bridge from the previous document. Each VM gets a static IP via cloud-init, your SSH key, the `kube` user with passwordless sudo, kernel modules and sysctls for Kubernetes, and is rebooted once at the end of cloud-init so all changes take effect cleanly.

The single-node guide used QEMU user-mode networking and a single `create-node.sh` script. This guide uses bridge networking and a `create-cluster.sh` script that provisions both VMs in a single command, plus cluster-level `start-cluster.sh`, `stop-cluster.sh`, and `destroy-cluster.sh`.

## What Was Removed from the Original Script

- **Port forwarding for SSH and component APIs.** No longer needed. With real IPs on the bridge, you SSH directly to `192.168.100.10` or `192.168.100.11`, and `kubectl` from the host points at `https://192.168.100.10:6443`.
- **`hostfwd` flags on the QEMU command line.** Replaced with `-netdev bridge,br=br-vm`.
- **Netplan via `write_files` + `runcmd`.** The single-node guide wrote `/etc/netplan/01-static.yaml` in `write_files` and then called `netplan apply` in `runcmd`. Both run in `modules:final`, after `package-update-upgrade-install`, so packages installed before the static IP was set. This guide uses a `network-config` seed file instead. Cloud-init reads `network-config` in `cloud-init-local` (the pre-network stage), writes the Netplan config, and applies it before `systemd-networkd` starts. The static IP is in place before `wait-online` runs, and packages install with a working interface.

## Prerequisites

The host bridge from document 01 must be active. Quick check:

```bash
ip addr show br-vm | grep 'inet 192.168.100.2' && echo "bridge OK"
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
wget -O ~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img \
  https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img
```

The script also assumes an apt-cache proxy is running on the host bridge IP (`192.168.100.2:3142`). See [`../apt-cache-proxy.md`](../apt-cache-proxy.md) for setup. The proxy caches Ubuntu and Kubernetes packages so VMs on the VLAN-isolated `192.168.100.0/24` network do not need direct internet access.

A binary cache directory is bind-mounted into each VM via virtio-9p as `/mnt/bincache`. Create it once on the host:

```bash
mkdir -p ~/cka-lab/binary-cache
```

---

## Part 1: Directory Structure

The script creates the following layout:

```
~/cka-lab/
  images/                   # Cached cloud images (shared with single-node guide)
    ubuntu-24.04-server-cloudimg-amd64.img
  binary-cache/             # Shared host directory mounted as /mnt/bincache in each VM
  two-kubeadm/
    create-cluster.sh       # Provisions both VMs
    start-cluster.sh        # Starts both VMs
    stop-cluster.sh         # Stops both VMs cleanly
    destroy-cluster.sh      # Removes per-VM directories (keeps cached image)
    controlplane-1/
      controlplane-1.qcow2  # controlplane-1 disk (backed by cloud image)
      seed.iso              # Cloud-init NoCloud seed ISO
      cloud-init/
        user-data
        meta-data
        network-config
      start-controlplane-1.sh
      stop-controlplane-1.sh
    nodes-1/
      nodes-1.qcow2
      seed.iso
      cloud-init/
        user-data
        meta-data
        network-config
      start-nodes-1.sh
      stop-nodes-1.sh
```

The `two-kubeadm/` parent directory keeps everything separate from the single-node `controlplane-1/` if you ever want to run both labs simultaneously.

---

## Part 2: The create-cluster.sh Script

The script is checked into the repository at `cluster-setup/vm/two-kubeadm/scripts/create-cluster.sh`. Copy it to the cluster directory and make it executable:

```bash
mkdir -p ~/cka-lab/two-kubeadm
cp /path/to/repo/cluster-setup/vm/two-kubeadm/scripts/create-cluster.sh \
  ~/cka-lab/two-kubeadm/create-cluster.sh
chmod +x ~/cka-lab/two-kubeadm/create-cluster.sh
```

Or paste the script directly if you do not have the repo on the host:

```bash
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

  # cloud-init network-config: read in cloud-init-local (pre-network stage) so the
  # static IP is assigned before systemd-networkd-wait-online runs on first boot.
  cat > "$node_dir/cloud-init/network-config" <<EOF
network:
  version: 2
  ethernets:
    enp0s2:
      dhcp4: false
      addresses:
        - $node_ip/24
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [1.1.1.1, 8.8.8.8]
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

  # Build cloud-init ISO (three files: user-data, meta-data, network-config)
  genisoimage -output "$node_dir/seed.iso" \
    -volid cidata -joliet -rock \
    "$node_dir/cloud-init/user-data" \
    "$node_dir/cloud-init/meta-data" \
    "$node_dir/cloud-init/network-config" 2>/dev/null
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
```

---

## Part 3: Run the Script

```bash
cd ~/cka-lab/two-kubeadm

# Provision both VMs
./create-cluster.sh

# Boot them
./start-cluster.sh

# Watch first boot. Cloud-init runs, reboots, then the second boot finishes quickly.
tail -f controlplane-1/controlplane-1-console.log
# Ctrl-C once you see a login prompt, then check nodes-1 the same way.
```

First boot: cloud-init runs `cloud-init-local` at ~4 seconds (static IP assigned), packages install via the apt proxy, then the VM reboots. Allow 60-90 seconds total depending on proxy cache warmth. Second boot completes in under 10 seconds.

---

## Part 4: Configure SSH Access

Add the following to `~/.ssh/config` on the host so `ssh controlplane-1` and `ssh nodes-1` work without flags.

```ssh-config
Host controlplane-1
    HostName 192.168.100.10
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host nodes-1
    HostName 192.168.100.11
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
```

If your SSH key is at a different path, adjust the `IdentityFile` line accordingly.

---

## Part 5: Verify Both VMs

After cloud-init completes and the VM reboots, verify everything is in place. Run from the host:

```bash
# Both VMs respond to ping
ping -c 2 192.168.100.10
ping -c 2 192.168.100.11

# SSH works to both
ssh controlplane-1 'hostname && ip -4 addr show enp0s2 | grep inet'
ssh nodes-1 'hostname && ip -4 addr show enp0s2 | grep inet'

# Each node can resolve and reach the other by name
ssh controlplane-1 'ping -c 2 nodes-1'
ssh nodes-1 'ping -c 2 controlplane-1'

# Binary cache mount is visible
ssh controlplane-1 'ls /mnt/bincache'
ssh nodes-1 'ls /mnt/bincache'

# Cloud-init reports done
ssh controlplane-1 'cloud-init status'
ssh nodes-1 'cloud-init status'
```

All checks should pass before moving to document 03.

### What Cloud-Init Pre-Configures

On both VMs after first boot:

- Hostname set to `controlplane-1` or `nodes-1`
- `/etc/hosts` populated with both nodes for name resolution without DNS
- Static IP assigned via `network-config` seed file, processed in `cloud-init-local` (pre-network stage) so the IP is up before `systemd-networkd-wait-online` runs
- `kube` user created with passwordless sudo and your SSH key authorized
- Ubuntu apt sources pointed at the nginx apt proxy (`192.168.100.2:3142`) for all packages
- Kubernetes apt keyring and source file written and indexed (`apt-get update`)
- Baseline packages installed (`socat`, `conntrack`, `ipset`, `curl`, `jq`, others)
- `overlay` and `br_netfilter` kernel modules loaded
- 9p and 9pnet_virtio modules loaded for the binary cache virtio-9p mount
- `/mnt/bincache` mounted from the host via virtio-9p
- Sysctls set for bridge filtering and IPv4 forwarding
- Swap disabled permanently
- Reboot once after cloud-init to apply everything cleanly

The cloud-init config does not install containerd, runc, kubeadm, kubelet, or kubectl. Those are installed manually in document 03.

---

## Summary

The two VMs are now provisioned and accessible:

| VM | Role (assigned later) | IP | SSH Alias |
|----|------------------------|----|-----------|
| `controlplane-1` | Control plane | `192.168.100.10` | `ssh controlplane-1` |
| `nodes-1` | Worker | `192.168.100.11` | `ssh nodes-1` |

All cluster-level lifecycle commands:

| Command | Purpose |
|---------|---------|
| `~/cka-lab/two-kubeadm/start-cluster.sh` | Boot both VMs |
| `~/cka-lab/two-kubeadm/stop-cluster.sh` | Graceful shutdown |
| `~/cka-lab/two-kubeadm/destroy-cluster.sh` | Remove disks and seed ISOs (keeps cached image) |
| `~/cka-lab/two-kubeadm/create-cluster.sh` | Re-provision (after destroy, or on first run) |

The next document installs the container runtime and `kubeadm` toolchain on both nodes.

---

← [Previous: Host Bridge Setup for Multi-Node Networking](01-host-bridge-setup.md) | [Next: Installing Container Runtime and kubeadm Toolchain →](03-node-prerequisites.md)
