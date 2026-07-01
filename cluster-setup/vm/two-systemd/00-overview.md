# Two-Node Kubernetes Cluster (systemd, From Scratch): Overview

A step-by-step guide for bootstrapping a two-node Kubernetes cluster on a pair of QEMU/KVM VMs, built entirely from raw binaries and systemd services. This is the multi-node companion to `cka/vm/single-systemd`. No `kubeadm`, no CNI operator, no overlay networking.

---

## Documents

Follow these in order. Each document builds on the previous one.

| # | Document | What It Does | Time |
|---|----------|-------------|------|
| 01 | [Host Bridge Setup](01-host-bridge-setup.md) | Configures the Linux bridge `br0` on the host, IP forwarding, NAT for outbound traffic | 20-30 min |
| 02 | [VM Provisioning](02-vm-provisioning.md) | Creates two headless Ubuntu 24.04 VMs (`controlplane-1`, `nodes-1`) with cloud-init and static IPs | 20-25 min |
| 03 | [Bootstrapping Security](03-bootstrapping-security.md) | Generates the CA on `controlplane-1`, copies it to `nodes-1`, each node generates its own component certs | 35-45 min |
| 04 | [Control Plane on controlplane-1](04-control-plane.md) | Installs etcd, apiserver, controller-manager, scheduler as systemd services | 30-40 min |
| 05 | [Container Runtime and Worker (Both Nodes)](05-container-runtime-and-worker.md) | Installs containerd, runc, crictl, CNI binaries, kubelet, kube-proxy on both nodes | 30-40 min |
| 06 | [Manual Pod Routing](06-manual-pod-routing.md) | Adds host routes between nodes so cross-node pod traffic actually works -- the step that reveals what CNI plugins do automatically | 20-30 min |
| 07 | [Cluster Services](07-cluster-services.md) | Installs Helm, CoreDNS, local-path-provisioner, optionally MetalLB | 20-30 min |

## Component Versions

| Component | Version |
|-----------|---------|
| Ubuntu (guest) | 24.04 LTS |
| etcd | v3.6.9 |
| Kubernetes | v1.35.3 |
| containerd | v2.1.3 |
| runc | v1.3.0 |
| cri-tools (crictl) | v1.35.0 |
| CNI plugins | v1.7.1 |

Kubernetes v1.35 is the version the CKA exam currently targets.

## Network Configuration

| CIDR | Purpose | Where It Appears |
|------|---------|------------------|
| `192.168.122.0/24` | Host bridge `br0` | VM IPs (`192.168.122.10`, `192.168.122.11`), host gateway (`192.168.122.1`) |
| `10.96.0.0/16` | Service ClusterIP range | apiserver `--service-cluster-ip-range`, controller-manager match, CoreDNS (`10.96.0.10`), kubelet `clusterDNS`, apiserver cert SAN (`10.96.0.1`) |
| `10.244.0.0/16` | Total pod IP range | controller-manager `--cluster-cidr`, kube-proxy `clusterCIDR` |
| `10.244.0.0/24` | `controlplane-1` pod slice | CNI bridge subnet on `controlplane-1` |
| `10.244.1.0/24` | `nodes-1` pod slice | CNI bridge subnet on `nodes-1` |

## VM Access

Both VMs are reachable directly over SSH from the host through the bridge.

| Access Method | Command |
|--------------|---------|
| SSH into `controlplane-1` | `ssh controlplane-1` (after SSH config setup) |
| SSH into `nodes-1` | `ssh nodes-1` |
| API server from host | `curl --cacert ~/cka-lab/two-systemd/ca.pem https://192.168.122.10:6443/healthz` |
| `kubectl` from host | Copy `~/auth/admin.kubeconfig` from `controlplane-1`, edit server URL |
| `controlplane-1` console log | `tail -f ~/cka-lab/two-systemd/controlplane-1/controlplane-1-console.log` |
| `nodes-1` console log | `tail -f ~/cka-lab/two-systemd/nodes-1/nodes-1-console.log` |
| Stop both VMs | `~/cka-lab/two-systemd/stop-cluster.sh` |
| Start both VMs | `~/cka-lab/two-systemd/start-cluster.sh` |

Default VM credentials: user `kube`, password `kubeadmin`.

## SSH Config

Add this to `~/.ssh/config` once. After this, `ssh controlplane-1` and `ssh nodes-1` work without flags.

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

## Where Everything Runs

- `controlplane-1` runs the entire control plane (etcd, apiserver, controller-manager, scheduler) as systemd services. It also runs kubelet and kube-proxy so workloads can schedule on it.
- `nodes-1` runs kubelet and kube-proxy only.
- All certificates are generated per-node, on each VM, so the CA travels from `controlplane-1` to `nodes-1` over scp.
- The host machine manages VM lifecycle, holds the SSH config, and runs the manual route programming for cross-node pod traffic.

## What's Different from `single-systemd`

- VM networking: bridge + TAP instead of QEMU user-mode + port forwarding.
- Cert SAN list: includes both VMs' IPs.
- Per-node identity: each node generates its own `system:node:nodeN` certificate.
- CNI: per-node pod CIDR slice, with manual host routes between nodes.
- Worker components installed on both nodes instead of one.

## Scope

Two-node cluster. The control plane node is left untainted so workloads can also schedule there. HA control plane setups (multiple control plane nodes, external load balancer) are out of scope.
