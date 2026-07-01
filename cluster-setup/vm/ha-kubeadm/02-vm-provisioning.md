# VM Provisioning: Five Nodes

**Based on:** [`three-kubeadm/02-vm-provisioning.md`](../three-kubeadm/02-vm-provisioning.md)

**Purpose:** Create five headless Ubuntu 24.04 VMs on the host bridge with static IPs
and cloud-init. The process is identical to the three-node guide but extended to cover
two control planes and three workers.

---

## Prerequisites

- `br-vm` bridge is configured and HAProxy is running (document 01).
- Ubuntu 24.04 cloud image is cached at `~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img`.
- `qemu-system-x86_64`, `qemu-img`, and `genisoimage` are installed on the host.

## Node Assignment

| Hostname | Bridge IP | Role |
|----------|-----------|------|
| `controlplane-1` | `192.168.100.20` | First control plane |
| `controlplane-2` | `192.168.100.21` | Second control plane |
| `nodes-1` | `192.168.100.22` | Worker |
| `nodes-2` | `192.168.100.23` | Worker |
| `nodes-3` | `192.168.100.24` | Worker |

## Part 1: Directory Structure

```bash
BASE=~/cka-lab/ha-kubeadm
for name in controlplane-1 controlplane-2 nodes-1 nodes-2 nodes-3; do
  mkdir -p "$BASE/$name/cloud-init"
done
```

## Part 2: Generate Per-Node Cloud-Init and Disks

```bash
BASE=~/cka-lab/ha-kubeadm
IMAGE=~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img

generate_node() {
  local name="$1"
  local ip="$2"
  local node_dir="$BASE/$name"

  cat > "$node_dir/cloud-init/meta-data" <<EOF
instance-id: ${name}
local-hostname: ${name}
EOF

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

  genisoimage -output "$node_dir/seed.iso" \
    -volid cidata -joliet -rock \
    "$node_dir/cloud-init/user-data" \
    "$node_dir/cloud-init/meta-data"

  qemu-img create -f qcow2 \
    -b "$(realpath "$IMAGE")" -F qcow2 \
    "$node_dir/${name}.qcow2" 40G

  echo "Node $name configured at $node_dir"
}

generate_node controlplane-1 192.168.100.20
generate_node controlplane-2 192.168.100.21
generate_node nodes-1        192.168.100.22
generate_node nodes-2        192.168.100.23
generate_node nodes-3        192.168.100.24
```

## Part 3: Per-Node Start and Stop Scripts

```bash
BASE=~/cka-lab/ha-kubeadm

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
    echo "${name} not running (stale PID)."
  fi
  rm -f "\$PID_FILE"
else
  echo "No PID file for ${name}."
fi
SCRIPT
  chmod +x "$node_dir/stop-${name}.sh"
}

for node in controlplane-1 controlplane-2 nodes-1 nodes-2 nodes-3; do
  make_scripts "$node"
done
```

## Part 4: Cluster-Level Scripts

```bash
BASE=~/cka-lab/ha-kubeadm

cat > "$BASE/start-cluster.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for node in controlplane-1 controlplane-2 nodes-1 nodes-2 nodes-3; do
  "$DIR/$node/start-${node}.sh"
  sleep 2
done
echo "All five nodes starting. Wait 60-90 seconds for cloud-init."
SCRIPT
chmod +x "$BASE/start-cluster.sh"

cat > "$BASE/stop-cluster.sh" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for node in nodes-3 nodes-2 nodes-1 controlplane-2 controlplane-1; do
  "$DIR/$node/stop-${node}.sh"
done
SCRIPT
chmod +x "$BASE/stop-cluster.sh"
```

## Part 5: Start All VMs and Verify

```bash
~/cka-lab/ha-kubeadm/start-cluster.sh
```

Wait 60-90 seconds, then check all five:

```bash
for node in controlplane-1 controlplane-2 nodes-1 nodes-2 nodes-3; do
  echo "=== $node ==="
  ssh "$node" '
    echo "IP: $(hostname -I)"
    echo "Swap: $(free -h | awk "/Swap/ {print \$2}")"
    lsmod | grep -E "overlay|br_netfilter" | awk "{print \$1}"
    sysctl -n net.ipv4.ip_forward
  '
done
```

**Result:** Five VMs at `.10`, `.11`, `.12`, `.13`, `.14` with static bridge IPs,
kubeadm prerequisites met.

---

## Option C: Dual-NIC Setup (Separate Cluster and External Traffic)

By default each VM has one NIC on `br-vm` that carries all traffic: inter-node Kubernetes
communication, image pulls, package installs, and SSH. This is fine for exam prep, but
a more realistic production-like setup separates:

- **NIC 0 (`enp0s2`):** cluster network -- all Kubernetes traffic (apiserver, etcd,
  kubelet, pod-to-pod via Calico VXLAN). Static IP on `192.168.100.x`, no default route.
- **NIC 1 (`enp0s3`):** external network -- image pulls, package installs, internet.
  QEMU user-mode NAT, DHCP, default route.

SSH access stays on `enp0s2` (bridge), since the bridge gives direct host-to-VM
connectivity. `enp0s3` only needs outbound internet access.

### What Changes From the Single-NIC Setup

Two things need updating: the QEMU start scripts (add a second `-netdev`/`-device`
pair) and the cloud-init netplan (separate the two interfaces and remove the default
route from the cluster NIC). Documents 05, 07, and 08 also need `--node-ip` added to
kubeadm configurations so kubelet registers with the cluster NIC IP rather than the
external NIC's `10.0.2.x` DHCP address.

### Modified generate_node Function (Dual-NIC Cloud-Init)

Replace the `generate_node` call in Part 2 with the version below, or run it in
addition if you want to create a new set of VMs alongside existing ones.

```bash
BASE=~/cka-lab/ha-kubeadm
IMAGE=~/cka-lab/images/ubuntu-24.04-server-cloudimg-amd64.img

generate_node_dual_nic() {
  local name="$1"
  local ip="$2"
  local node_dir="$BASE/$name"
  mkdir -p "$node_dir/cloud-init"

  cat > "$node_dir/cloud-init/meta-data" <<EOF
instance-id: ${name}
local-hostname: ${name}
EOF

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
            # No default route -- cluster traffic only.
            # SSH also uses this interface (direct bridge connectivity).
          enp0s3:
            dhcp4: true
            # Gets 10.0.2.x from QEMU user-mode, becomes the default route.
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

  genisoimage -output "$node_dir/seed.iso" \
    -volid cidata -joliet -rock \
    "$node_dir/cloud-init/user-data" \
    "$node_dir/cloud-init/meta-data"

  qemu-img create -f qcow2 \
    -b "$(realpath "$IMAGE")" -F qcow2 \
    "$node_dir/${name}.qcow2" 40G

  echo "Node $name (dual-NIC) configured at $node_dir"
}

generate_node_dual_nic controlplane-1 192.168.100.20
generate_node_dual_nic controlplane-2 192.168.100.21
generate_node_dual_nic nodes-1        192.168.100.22
generate_node_dual_nic nodes-2        192.168.100.23
generate_node_dual_nic nodes-3        192.168.100.24
```

### Modified make_scripts Function (Second QEMU NIC)

The only change is the addition of `-netdev user,id=net1` and its device. Replace the
`make_scripts` loop in Part 3:

```bash
BASE=~/cka-lab/ha-kubeadm

make_scripts_dual_nic() {
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
    -netdev user,id=net1 \\
    -device virtio-net-pci,netdev=net1 \\
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
    echo "${name} not running (stale PID)."
  fi
  rm -f "\$PID_FILE"
else
  echo "No PID file for ${name}."
fi
SCRIPT
  chmod +x "$node_dir/stop-${name}.sh"
}

for node in controlplane-1 controlplane-2 nodes-1 nodes-2 nodes-3; do
  make_scripts_dual_nic "$node"
done
```

### Verify Both NICs Inside a VM

After starting the VMs and waiting for cloud-init, SSH in and check:

```bash
ssh controlplane-1 '
  echo "=== Cluster NIC (enp0s2) ==="
  ip addr show enp0s2 | grep inet

  echo "=== External NIC (enp0s3) ==="
  ip addr show enp0s3 | grep inet

  echo "=== Default route ==="
  ip route show default
  # Expected: default via 10.0.2.2 dev enp0s3 (user-mode gateway)

  echo "=== Cluster subnet route ==="
  ip route show 192.168.100.0/24
  # Expected: 192.168.100.0/24 dev enp0s2

  echo "=== Internet access (via enp0s3) ==="
  curl -s --max-time 5 https://dl.k8s.io/release/stable.txt && echo " OK"
'
```

The interface names `enp0s2` and `enp0s3` assume QEMU q35 with virtio NICs in the order
above. If they differ inside the VM, run `ip -brief link show` and substitute the
actual names in the netplan file and in the `--node-ip` values below.

### Required Changes in Downstream Documents

With dual NICs, kubelet will pick the default-route interface (`enp0s3`, `10.0.2.15`)
when registering the node IP unless you tell it otherwise. The next three documents each
need a `--node-ip` addition:

- **Document 05** (First control plane init): add `nodeRegistration.kubeletExtraArgs`
  to the `InitConfiguration` (see that document's Dual-NIC callout).
- **Document 07** (Second control plane join): add `nodeRegistration.kubeletExtraArgs`
  to the `JoinConfiguration` (see that document's Dual-NIC callout).
- **Document 08** (Worker join): pass a kubeadm join config file per worker with
  `nodeRegistration.kubeletExtraArgs` (see that document's Dual-NIC callout).

---

← [Previous: Host Bridge Setup and HAProxy Load Balancer](01-host-bridge-setup.md) | [Next: Node Prerequisites: Five Nodes →](03-node-prerequisites.md)
