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

Generate the default containerd configuration, then apply three overrides before starting
it. Debian's containerd ships defaults that do not match what kubeadm v1.35 and Calico
expect, so all three matter:

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null

# 1. systemd cgroup driver (must match the kubelet)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 2. CNI bin_dir: Debian defaults to /usr/lib/cni (empty); plugins and Calico live in /opt/cni/bin
sudo sed -i 's#bin_dir = "/usr/lib/cni"#bin_dir = "/opt/cni/bin"#' /etc/containerd/config.toml

# 3. sandbox image: Debian defaults to pause:3.8; kubeadm v1.35 expects pause:3.10.1
sudo sed -i 's#sandbox_image = "registry.k8s.io/pause:3.8"#sandbox_image = "registry.k8s.io/pause:3.10.1"#' /etc/containerd/config.toml

# Restart and verify
sudo systemctl restart containerd
sudo systemctl enable containerd
sudo systemctl is-active containerd
# Expected: active

# Confirm the overrides are live
sudo grep -E 'SystemdCgroup|bin_dir|sandbox_image' /etc/containerd/config.toml
```

The cgroup driver must match the kubelet, which document 04 sets to `systemd` via
`KubeletConfiguration`. The `bin_dir` override points containerd at `/opt/cni/bin`, where
Calico's `calico-node` init container installs its CNI plugins in document 04 (see Part 2). Debian's default of `/usr/lib/cni` is empty, which causes every pod
sandbox to fail with `failed to find plugin "calico" in path [/usr/lib/cni]`. The
`sandbox_image` override pins the pause image to the version kubeadm v1.35 expects,
silencing the inconsistency warning kubeadm prints at init time.

---

## Part 2: CNI Plugins

No separate CNI plugin install is needed for this guide. When Calico comes up in document
04, its `calico-node` pod runs an `install-cni` init container that copies the plugins its
config chains (`calico`, `calico-ipam`, `portmap`, `bandwidth`, `tuning`, and the standard
helpers) into `/opt/cni/bin`, the `bin_dir` set in Part 1. Calico creates the directory if
it does not exist.

Install the upstream `containernetworking/plugins` release explicitly only if you plan to
run a different CNI, or want the standard plugins on the node regardless of Calico:

```bash
CNI_VERSION="v1.7.1"
sudo mkdir -p /opt/cni/bin
curl -fsSL "https://github.com/containernetworking/plugins/releases/download/${CNI_VERSION}/cni-plugins-linux-arm64-${CNI_VERSION}.tgz" \
  | sudo tar -xz -C /opt/cni/bin
```

---

## Part 3: kubeadm, kubelet, kubectl, cri-tools (ARM64)

Add the Kubernetes apt repository and install the toolchain plus `cri-tools` (which
provides `crictl`). All four come from the same `pkgs.k8s.io` v1.35 channel, so a single
`apt install` keeps their versions aligned. The package source is identical to the x86-64
guides but targets `arm64`. `apt-transport-https`, `ca-certificates`, `curl`, and `gpg`
are pre-installed in the base image.

```bash
# Add the Kubernetes apt signing key
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key \
  | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Install the toolchain and crictl together
sudo apt update
sudo apt install -y kubeadm kubelet kubectl cri-tools

# Hold all four so an apt upgrade cannot bump them out from under the cluster
sudo apt-mark hold kubeadm kubelet kubectl cri-tools

# Enable kubelet (it restarts once per bootstrap phase)
sudo systemctl enable kubelet
```

The `v1.35` channel installs the latest patch available at build time (v1.35.6 here), so
set `kubernetesVersion` in the document 04 config to whatever `kubeadm version` reports.

`crictl` auto-detects the containerd socket, so no `/etc/crictl.yaml` is required on a
single-runtime node. Create it only to pin the endpoint explicitly or to silence the
endpoint-probe message:

```bash
sudo tee /etc/crictl.yaml > /dev/null <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 2
EOF
```

Verify the toolchain:

```bash
kubeadm version -o short   # v1.35.x
kubectl version --client
crictl --version           # crictl version v1.35.0
sudo crictl ps             # lists containers, empty before cluster init
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
