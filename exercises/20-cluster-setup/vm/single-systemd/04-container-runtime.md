# Installing the Container Runtime (Single Node)

**Based on:** [kubernetes-the-harder-way/06_Spinning_up_Worker_Nodes.md](https://github.com/ghik/kubernetes-the-harder-way/blob/linux/docs/06_Spinning_up_Worker_Nodes.md) (first half)

**Simplified for:** A single-node cluster where the same VM runs control plane and worker components.

---

## What This Chapter Does

Before kubelet can run pods, the node needs a container runtime. The runtime is responsible for pulling images, creating containers, managing their lifecycle, and connecting them to the network. This chapter installs three binaries that together form the container runtime stack:

- `containerd` is the daemon that manages container lifecycle and implements the Container Runtime Interface (CRI) that kubelet talks to.
- `runc` is the low-level tool that actually creates and runs containers using Linux namespaces and cgroups. containerd calls runc under the hood.
- `crictl` is a command-line tool for inspecting and troubleshooting containers. It is not required for the cluster to function but is essential for debugging.

Docker is not involved. containerd and runc are the same components Docker itself uses internally; we are just skipping Docker's frontend layer, which Kubernetes does not need.

## Prerequisites

SSH into the VM. The control plane components (etcd, kube-apiserver, kube-controller-manager, kube-scheduler) should already be running from the previous chapter.

## Shell Variables

```bash
arch=amd64
k8s_version=1.35.3
cri_version=1.35.0
runc_version=1.3.0
containerd_version=2.1.3
```

## Installing the Binaries

Download containerd, runc, and crictl:

```bash
crictl_archive=crictl-v${cri_version}-linux-${arch}.tar.gz
containerd_archive=containerd-${containerd_version}-linux-${arch}.tar.gz

wget -q --show-progress --https-only --timestamping \
  "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${cri_version}/${crictl_archive}" \
  "https://github.com/opencontainers/runc/releases/download/v${runc_version}/runc.${arch}" \
  "https://github.com/containerd/containerd/releases/download/v${containerd_version}/${containerd_archive}"

mkdir -p containerd
tar -xvf ${crictl_archive}
tar -xvf ${containerd_archive} -C containerd
cp runc.${arch} runc
chmod +x crictl runc
sudo cp crictl runc /usr/local/bin/
sudo cp containerd/bin/* /bin/
```

## Configuring containerd

Create the containerd configuration directory and write the config file:

```bash
sudo mkdir -p /etc/containerd/

cat <<EOF | sudo tee /etc/containerd/config.toml
version = 3
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = 'io.containerd.runc.v2'
  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
    SystemdCgroup = true
    BinaryName = '/usr/local/bin/runc'
EOF
```

Two things to note about this configuration. `SystemdCgroup = true` tells containerd to use systemd for cgroup management rather than the cgroupfs driver. This is required because Ubuntu uses systemd, and running two cgroup managers simultaneously (systemd + cgroupfs) causes instability. `BinaryName` tells containerd where to find the runc binary.

## Creating the systemd Service

```bash
cat <<EOF | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
```

The `Delegate=yes` setting is important. It tells systemd to delegate cgroup management to containerd, allowing it to create sub-cgroups for containers. Without this, container resource limits would not work correctly.

## Starting containerd

```bash
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl start containerd
```

Verify it is running:

```bash
systemctl status containerd.service
```

You can also test crictl against the running containerd:

```bash
sudo crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock info
```

This should return JSON output showing containerd's status and configuration.

## Summary

The container runtime stack is now installed and running:

| Component | Binary Location | Purpose |
|-----------|----------------|---------|
| containerd | `/bin/containerd` | Container lifecycle daemon, CRI implementation |
| runc | `/usr/local/bin/runc` | Low-level container executor (OCI runtime) |
| crictl | `/usr/local/bin/crictl` | CLI tool for container inspection/debugging |

The next document installs the CNI plugins, kubelet, and kube-proxy to complete the worker-side setup.
