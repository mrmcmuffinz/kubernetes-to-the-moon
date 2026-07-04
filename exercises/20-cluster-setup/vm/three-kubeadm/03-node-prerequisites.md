# Node Prerequisites: Three Nodes

**Based on:** [`two-kubeadm/03-node-prerequisites.md`](../two-kubeadm/03-node-prerequisites.md)

**Purpose:** Install the container runtime and kubeadm toolchain on all three nodes.
The steps are identical to the two-node guide, but run on three nodes instead of two.

---

## Prerequisites

All three VMs must be running and reachable:

```bash
for node in controlplane-1 nodes-1 nodes-2; do
  ssh "$node" 'echo "$(hostname): $(hostname -I)"'
done
```

## Part 1: Install containerd and runc (all three nodes)

```bash
CNI_VERSION=1.7.1
CRI_VERSION=1.35.0
ARCH=amd64

for node in controlplane-1 nodes-1 nodes-2; do
  echo "=== $node ==="
  ssh "$node" "sudo bash" <<EOF
set -euo pipefail

# containerd and runc (dependency)
apt-get update -qq
apt-get install -y containerd

# crictl (cri-tools is not in Ubuntu default repos; binary from upstream)
curl -fsSLo /tmp/crictl.tar.gz https://github.com/kubernetes-sigs/cri-tools/releases/download/v${CRI_VERSION}/crictl-v${CRI_VERSION}-linux-${ARCH}.tar.gz
tar -C /usr/local/bin -xzf /tmp/crictl.tar.gz
rm /tmp/crictl.tar.gz

# CNI plugins
mkdir -p /opt/cni/bin
curl -fsSLo /tmp/cni-plugins.tgz https://github.com/containernetworking/plugins/releases/download/v${CNI_VERSION}/cni-plugins-linux-${ARCH}-v${CNI_VERSION}.tgz
tar -C /opt/cni/bin -xzf /tmp/cni-plugins.tgz
rm /tmp/cni-plugins.tgz

# containerd config with systemd cgroup driver
mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# crictl config
cat > /etc/crictl.yaml <<CRICTL
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
CRICTL

systemctl restart containerd
EOF
done
```

## Part 2: Install kubeadm, kubelet, kubectl (all three nodes)

```bash
K8S_VERSION=1.35

for node in controlplane-1 nodes-1 nodes-2; do
  echo "=== $node ==="
  ssh "$node" "sudo bash" <<EOF
set -euo pipefail

# Kubernetes apt repo
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubeadm=1.35.3-1.1 kubelet=1.35.3-1.1 kubectl=1.35.3-1.1
apt-mark hold kubeadm kubelet kubectl

systemctl enable kubelet
EOF
done
```

## Part 3: Verify

```bash
for node in controlplane-1 nodes-1 nodes-2; do
  echo "=== $node ==="
  ssh "$node" '
    sudo ctr version 2>/dev/null | grep Version || echo "containerd: ERROR"
    sudo crictl info 2>/dev/null | grep -q runtimeHandlers && echo "crictl: OK" || echo "crictl: ERROR"
    kubeadm version -o short
    kubelet --version
  '
done
```

**Result:** All three nodes have containerd running and the kubeadm toolchain at v1.35.3.

---

← [Previous: VM Provisioning: Three Nodes](02-vm-provisioning.md) | [Next: Control Plane Initialization →](04-control-plane-init.md)
