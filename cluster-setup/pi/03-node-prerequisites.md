# Node Prerequisites

**Purpose:** Install containerd, runc, the CNI plugin binaries, crictl, and the
kubeadm/kubelet/kubectl toolchain on all three nodes. All packages use the `arm64`
architecture, which is the same `pkgs.k8s.io` apt source as the x86-64 guides.

The base image ships with prerequisite packages pre-installed (`apt-transport-https`,
`ca-certificates`, `curl`, `gnupg`, etc.). Cloud-init handled kernel modules and sysctl
via `write_files` during first boot. This document covers only the container runtime
and Kubernetes toolchain.

Run on all three nodes (`rpi-node-01`, `rpi-node-02`, `rpi-node-03`). Steps are
identical on all three.

---

## Part 1: containerd and runc

Install containerd and runc from the Debian Trixie apt repository (ARM64 packages are
available in the standard repository).

```bash
sudo apt update
sudo apt install -y containerd runc
```

Configure containerd to use the systemd cgroup driver (required for kubeadm clusters):

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# Enable systemd cgroup driver
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Restart and verify
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl is-active containerd
# Expected: active
```

---

## Part 2: CNI Plugins

```bash
CNI_VERSION="v1.7.1"
sudo mkdir -p /opt/cni/bin
curl -fsSL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-arm64-${CNI_VERSION}.tgz" \
  | sudo tar -xz -C /opt/cni/bin

# Verify
ls /opt/cni/bin/
# Expected: bridge, loopback, host-local, portmap, etc.
```

---

## Part 3: crictl

```bash
CRICTL_VERSION="v1.35.0"
curl -fsSL "https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-arm64.tar.gz" \
  | sudo tar -xz -C /usr/local/bin

# Configure crictl to use containerd
sudo tee /etc/crictl.yaml > /dev/null <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
debug: false
EOF

# Verify
crictl --version
# Expected: crictl version v1.35.0
```

---

## Part 4: kubeadm, kubelet, kubectl (ARM64)

Add the Kubernetes apt repository and install the toolchain. The package source is
identical to the x86-64 guides but targets `arm64`. `apt-transport-https`,
`ca-certificates`, `curl`, and `gpg` are pre-installed in the base image.

```bash
# Add the Kubernetes apt signing key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Install
sudo apt update
sudo apt install -y kubeadm kubelet kubectl

# Hold versions to prevent accidental upgrades
sudo apt-mark hold kubeadm kubelet kubectl

# Enable and start kubelet (will restart once per bootstrap phase)
sudo systemctl enable kubelet

# Verify
kubeadm version
kubectl version --client
crictl --runtime-endpoint unix:///run/containerd/containerd.sock ps
```

---

## Verification

After completing all parts on a node:

```bash
# containerd is active
sudo systemctl is-active containerd
# Expected: active

# kubeadm version matches target
kubeadm version -o short
# Expected: v1.35.x

# CNI plugins present
ls /opt/cni/bin/ | grep -E "bridge|loopback"
# Expected: bridge, loopback

# crictl can list containers (empty is fine before cluster init)
sudo crictl ps
# Expected: no error (container listing, possibly empty)
```

**Result:** All three nodes have containerd, crictl, CNI plugins, and the
kubeadm/kubelet/kubectl toolchain installed. Kernel modules, sysctl, and prerequisite
packages were handled by cloud-init during first boot.

---

← [Previous: Network Setup](02-network-setup.md) | [Next: Control Plane Init →](04-control-plane-init.md)
