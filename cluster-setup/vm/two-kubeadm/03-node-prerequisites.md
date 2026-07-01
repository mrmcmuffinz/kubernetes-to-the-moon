# Installing Container Runtime and kubeadm Toolchain

**Based on:** The upstream [kubeadm install documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/).

**Purpose:** Install containerd via apt, then add the Kubernetes apt repo and install kubeadm, kubelet, kubectl, and crictl from it in a single pass. Run every step on both nodes.

---

## What This Chapter Does

Before `kubeadm init` can run, both nodes need a working container runtime and the `kubeadm` toolchain at the matching version. This document installs containerd first (it has no dependency on the Kubernetes apt repo), then adds the Kubernetes apt repo as the single source for crictl (`cri-tools`), `kubeadm`, `kubelet`, and `kubectl`. All four tools are installed together and pinned with `apt-mark hold`.

CNI plugin binaries are not pre-installed here. Calico installs its own CNI binaries (`calico` and `calico-ipam`) via an init container in the `calico-node` DaemonSet when deployed in document 05. No manual pre-installation is required.

This document is identical for `controlplane-1` and `nodes-1`. Run every step on both nodes. The cleanest way is to open two terminals (one SSH'd into each node) and walk through in lockstep.

## What Is Different from the systemd Guides

The systemd guides (`single-systemd`, `two-systemd`) install containerd as a raw binary and write the systemd unit by hand. This guide installs containerd via apt, which registers and starts the unit automatically. crictl is also installed via the Kubernetes apt repo (`cri-tools` package) rather than a direct binary download, so future updates follow the same `apt-mark unhold / apt install / apt-mark hold` pattern as kubeadm -- the same workflow the CKA exam tests.

## Prerequisites

SSH into either node. Cloud-init from the previous document already disabled swap, loaded `overlay` and `br_netfilter`, and set the necessary sysctls. Verify briefly:

```bash
free -h | grep Swap                 # All zeros
lsmod | grep -E 'overlay|br_netfilter'  # Both present
sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward
# Both should be 1
```

If any of those are wrong, see the cloud-init troubleshooting in `runbook-qemu-vm.md`.

---

## Part 1: Container Runtime

### Step 1: Install containerd

```bash
sudo apt-get update
sudo apt-get install -y containerd
```

apt installs containerd and pulls in `runc` as a dependency. The systemd unit is registered and started automatically.

### Step 2: Configure containerd

apt does not write a config file. Generate the defaults and enable the systemd cgroup driver:

```bash
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml > /dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
```

`SystemdCgroup = true` is required because Ubuntu 24.04 uses systemd as the cgroup manager. Running cgroupfs and systemd managers simultaneously on the same node causes instability.

### Step 3: Restart containerd

```bash
sudo systemctl restart containerd
systemctl status containerd --no-pager
```

---

## Part 2: Kubernetes Apt Repo and Toolchain

The upstream Kubernetes apt repo is versioned per minor release. Adding the v1.35 repo gives access to `1.35.x` packages only; upgrading to v1.36 later requires changing the repo URL, which is intentional and matches the CKA exam upgrade workflow. crictl, kubeadm, kubelet, and kubectl all come from this repo, so the repo is added once and all four tools are installed in the same pass.

### Step 1: Add the Kubernetes Apt Repo

```bash
sudo mkdir -p /etc/apt/keyrings
sudo curl -fsSL -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg.tmp \
  https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key
sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg /etc/apt/keyrings/kubernetes-apt-keyring.gpg.tmp
sudo rm /etc/apt/keyrings/kubernetes-apt-keyring.gpg.tmp

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list

sudo apt update
```

### Step 2: Check Available Version Strings

The exact package version suffix (e.g., `1.35.3-1.1`) can differ by repo mirror. Check before pinning:

```bash
apt-cache madison kubelet | head -3
apt-cache madison cri-tools | head -3
```

### Step 3: Install Pinned to v1.35

Substitute the exact suffix shown by `madison` if it differs:

```bash
sudo apt install -y \
  cri-tools=1.35.0-1.1 \
  kubelet=1.35.3-1.1 \
  kubeadm=1.35.3-1.1 \
  kubectl=1.35.3-1.1
```

### Step 4: Hold the Versions

`apt-mark hold` prevents `apt upgrade` from bumping these silently. Cluster upgrades on the CKA exam are intentional, version-pinned operations.

```bash
sudo apt-mark hold cri-tools kubelet kubeadm kubectl
```

### Step 5: Configure the crictl Default Endpoint

`kubeadm init` uses `crictl` and expects to find the runtime endpoint without flags. Write the config and verify it can reach containerd:

```bash
sudo tee /etc/crictl.yaml > /dev/null <<'EOF'
runtime-endpoint: unix:///run/containerd/containerd.sock
image-endpoint: unix:///run/containerd/containerd.sock
timeout: 10
debug: false
EOF

sudo crictl version
sudo crictl info > /dev/null && echo "crictl OK"
```

### Step 6: Verify the Toolchain

```bash
kubeadm version -o short        # v1.35.3
kubelet --version               # Kubernetes v1.35.3
kubectl version --client -o yaml | grep gitVersion
```

All three should report `v1.35.3`.

### Step 7: Pre-Pull Control Plane Images (controlplane-1 only)

On `controlplane-1` only, pre-pull the images `kubeadm init` will need. This is optional but lets you catch image-pull errors before `kubeadm init` runs.

```bash
sudo kubeadm config images pull --kubernetes-version v1.35.3
```

This pulls `kube-apiserver`, `kube-controller-manager`, `kube-scheduler`, `kube-proxy`, `pause`, `etcd`, and `coredns`. On `nodes-1` skip this step; the worker only needs `kube-proxy` and `pause`, which `kubeadm join` will pull when needed.

---

## Part 3: Verify Both Nodes Are Ready

Same checklist on each node. Repeat on `controlplane-1` and `nodes-1`:

```bash
# Swap off
free -m | awk '/Swap/ {print "swap_total="$2}'

# Modules loaded
lsmod | grep -E '^(overlay|br_netfilter)' | wc -l    # 2

# Sysctls
sysctl net.bridge.bridge-nf-call-iptables net.ipv4.ip_forward

# containerd up
systemctl is-active containerd

# crictl can talk to containerd
sudo crictl info > /dev/null && echo "crictl OK"

# kubeadm tools at the right version
kubeadm version -o short
kubelet --version
kubectl version --client -o yaml | grep gitVersion
```

If every check passes on both nodes, move to document 04.

---

## Summary

Both nodes are now ready for `kubeadm init` and `kubeadm join`:

| Component | Location | Purpose |
|-----------|----------|---------|
| containerd | `/usr/bin/containerd` (via apt) | Container lifecycle daemon, CRI implementation |
| runc | `/usr/sbin/runc` (via apt, dep of containerd) | Low-level container executor (OCI runtime) |
| crictl | `/usr/bin/crictl` (via apt, cri-tools) | CLI tool for container inspection/debugging |
| kubeadm | `/usr/bin/kubeadm` | Cluster bootstrap and lifecycle tool |
| kubelet | `/usr/bin/kubelet` | Node agent (started by `kubeadm init` or `kubeadm join`) |
| kubectl | `/usr/bin/kubectl` | Kubernetes CLI |

CNI plugin binaries (`calico`, `calico-ipam`) are not listed here. Calico installs them into `/opt/cni/bin/` automatically via its init container when deployed in document 05.

The next document runs `kubeadm init` on `controlplane-1`.

---

← [Previous: VM Provisioning for Two-Node Cluster](02-vm-provisioning.md) | [Next: Initializing the Control Plane with kubeadm →](04-control-plane-init.md)
