# VM Provisioning: Three Nodes

**Based on:** [`two-kubeadm/02-vm-provisioning.md`](../two-kubeadm/02-vm-provisioning.md)

**Purpose:** Create three headless Ubuntu 24.04 VMs on the host bridge with static IPs
and cloud-init. The process is identical to the two-node guide but extended to cover a
third VM (`nodes-2` at `192.168.100.12`).

---

## Prerequisites

- `br-vm` bridge is configured (document 01 or pre-existing from another guide).
- Ubuntu 24.04 cloud image is cached at `~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img`.
  If not, see `two-kubeadm/02-vm-provisioning.md` Part 1 for the download step.
- `qemu-system-x86_64`, `qemu-img`, and `genisoimage` are installed on the host.

## Node Assignment

| Hostname | Bridge IP | Role |
|----------|-----------|------|
| `controlplane-1` | `192.168.100.10` | Control plane (static pods, etcd) |
| `nodes-1` | `192.168.100.11` | Worker |
| `nodes-2` | `192.168.100.12` | Worker |

## Part 1: Directory Structure

```bash
BASE=~/cka-lab/three-kubeadm
mkdir -p "$BASE"/{controlplane-1,nodes-1,nodes-2}/{cloud-init}
mkdir -p "$BASE"  # cluster-level scripts go here
```

## Part 2: Cloud-Init Configurations

Each VM needs its own `user-data` and `meta-data`. The `user-data` is the same for all
three nodes (packages, kernel modules, sysctl, swap off). Only the hostname differs.

### Shell function: generate per-node files

Run these commands on the host (not inside any VM):

```bash
BASE=~/cka-lab/three-kubeadm
IMAGE=~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img

generate_node() {
  local name="$1"
  local ip="$2"
  local node_dir="$BASE/$name"

  # meta-data
  cat > "$node_dir/cloud-init/meta-data" <<EOF
instance-id: ${name}
local-hostname: ${name}
EOF

  # user-data: static IP via netplan, kubeadm prerequisites
  cat > "$node_dir/cloud-init/user-data" <<EOF
#cloud-config

hostname: ${name}
manage_etc_hosts: true
fqdn: ${name}.cka.local

users:
  - name: kube
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    plain_text_passwd: "kubeadmin"
    ssh_authorized_keys: []

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
  - vim

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

  - path: /etc/netplan/99-cka-bridge.yaml
    content: |
      network:
        version: 2
        ethernets:
          enp0s2:
            dhcp4: false
            addresses: [${ip}/24]
            routes:
              - to: default
                via: 192.168.100.1
            nameservers:
              addresses: [8.8.8.8, 8.8.4.4]

runcmd:
  - netplan apply
  - modprobe overlay
  - modprobe br_netfilter
  - sysctl --system
  - swapoff -a
  - sed -i '/\sswap\s/s/^/#/' /etc/fstab

power_state:
  mode: reboot
  message: "Cloud-init complete. Rebooting."
  timeout: 30
  condition: true
EOF

  # Build seed ISO
  genisoimage -output "$node_dir/seed.iso" \
    -volid cidata -joliet -rock \
    "$node_dir/cloud-init/user-data" \
    "$node_dir/cloud-init/meta-data"

  # Create qcow2 disk backed by cloud image
  qemu-img create -f qcow2 \
    -b "$(realpath "$IMAGE")" -F qcow2 \
    "$node_dir/${name}.qcow2" 40G

  echo "Node $name configured at $node_dir"
}

generate_node controlplane-1 192.168.100.10
generate_node nodes-1        192.168.100.11
generate_node nodes-2        192.168.100.12
```

## Part 3: Per-Node Start and Stop Scripts

```bash
BASE=~/cka-lab/three-kubeadm

make_scripts() {
  local name="$1"
  local node_dir="$BASE/$name"

  cat > "$node_dir/start-${name}.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
qemu-system-x86_64 \\
    -name ${name} \\
    -machine type=q35,accel=kvm \\
    -cpu host -smp 2 -m 4096 \\
    -drive file="\$SCRIPT_DIR/${name}.qcow2",format=qcow2,if=virtio \\
    -drive file="\$SCRIPT_DIR/seed.iso",format=raw,if=virtio \\
    -netdev bridge,id=net0,br=br-vm \\
    -device virtio-net-pci,netdev=net0 \\
    -display none \\
    -serial file:"\$SCRIPT_DIR/${name}-console.log" \\
    -daemonize \\
    -pidfile "\$SCRIPT_DIR/${name}.pid" "\$@"
echo "${name} started (PID \$(cat "\$SCRIPT_DIR/${name}.pid"))"
SCRIPT
  chmod +x "$node_dir/start-${name}.sh"

  cat > "$node_dir/stop-${name}.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="\$SCRIPT_DIR/${name}.pid"
if [[ -f "\$PID_FILE" ]]; then
  PID=\$(cat "\$PID_FILE")
  if kill -0 "\$PID" 2>/dev/null; then
    kill "\$PID"
    tail --pid="\$PID" -f /dev/null 2>/dev/null || true
    echo "${name} stopped."
  else
    echo "${name} is not running (stale PID file)."
  fi
  rm -f "\$PID_FILE"
else
  echo "No PID file found. ${name} may not be running."
fi
SCRIPT
  chmod +x "$node_dir/stop-${name}.sh"
}

for node in controlplane-1 nodes-1 nodes-2; do
  make_scripts "$node"
done
```

## Part 4: Cluster-Level Scripts

```bash
BASE=~/cka-lab/three-kubeadm

# Start all three VMs
cat > "$BASE/start-cluster.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for node in controlplane-1 nodes-1 nodes-2; do
  "$DIR/$node/start-${node}.sh"
  sleep 2
done
echo "All three nodes starting. Wait 60-90 seconds for cloud-init to complete."
SCRIPT
chmod +x "$BASE/start-cluster.sh"

# Stop all three VMs
cat > "$BASE/stop-cluster.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for node in nodes-2 nodes-1 controlplane-1; do
  "$DIR/$node/stop-${node}.sh"
done
SCRIPT
chmod +x "$BASE/stop-cluster.sh"
```

## Part 5: Start the VMs and Wait for Boot

```bash
~/cka-lab/three-kubeadm/start-cluster.sh

# Watch the boot progress on all three nodes
for node in controlplane-1 nodes-1 nodes-2; do
  echo "=== $node ===" && \
  tail -5 ~/cka-lab/three-kubeadm/$node/$node-console.log
done
```

Wait 60-90 seconds for cloud-init to complete and all VMs to reboot. Then verify SSH
access to all three:

```bash
for node in controlplane-1 nodes-1 nodes-2; do
  ssh "$node" 'echo "$(hostname): OK"'
done
```

## Part 6: Verification

On each node, confirm the kubeadm prerequisites are met:

```bash
for node in controlplane-1 nodes-1 nodes-2; do
  echo "=== $node ==="
  ssh "$node" '
    echo "Hostname: $(hostname)"
    echo "IP: $(ip -4 addr show enp0s2 | awk "/inet / {print \$2}")"
    echo "Swap: $(free -h | awk "/Swap/ {print \$2}")"
    lsmod | grep -E "overlay|br_netfilter" | awk "{print \$1}"
    sysctl -n net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
  '
done
```

All nodes should show: no swap, both kernel modules loaded, both sysctls = 1.

**Result:** Three VMs at `192.168.100.10`, `.11`, `.12` with static bridge IPs,
kubeadm prerequisites met.

---

← [Previous: Host Bridge Setup for Three-Node Networking](01-host-bridge-setup.md) | [Next: Node Prerequisites: Three Nodes →](03-node-prerequisites.md)
