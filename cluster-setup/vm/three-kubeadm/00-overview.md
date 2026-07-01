# Three-Node Kubernetes Cluster: Overview

A step-by-step guide for bootstrapping a three-node Kubernetes cluster on QEMU/KVM
virtual machines using `kubeadm`. Built for CKA exam preparation as the three-node
companion to the single-node and two-node guides.

---

## Documents

Follow these in order. Each document builds on the previous one.

| # | Document | What It Does | Time |
|---|----------|-------------|------|
| 01 | [Host Network Setup](01-host-bridge-setup.md) | Confirms the VLAN-isolated bridge `br-vm` is configured per `00-vlan-host-network-setup.md` | 20-30 min (first time only) |
| 02 | [VM Provisioning](02-vm-provisioning.md) | Creates three VMs (`controlplane-1`, `nodes-1`, `nodes-2`) with cloud-init and static bridge IPs | 20-25 min |
| 03 | [Node Prerequisites](03-node-prerequisites.md) | Installs containerd, runc, CNI binaries, crictl, and the kubeadm toolchain on all three nodes | 10-15 min |
| 04 | [Control Plane Init](04-control-plane-init.md) | Runs `kubeadm init` on `controlplane-1`, sets up `kubectl`, copies kubeconfig to host | 10-15 min |
| 05 | [CNI Installation](05-cni-installation.md) | Installs Calico via Tigera operator, removes control-plane taint, verifies `NetworkPolicy` | 5-10 min |
| 06 | [Worker Join](06-worker-join.md) | Joins `nodes-1` and `nodes-2`, verifies cross-node networking, snapshots all disks | 15-20 min |
| 07 | [Cluster Services](07-cluster-services.md) | Installs Helm, `local-path-provisioner`, `metrics-server`, optionally MetalLB | 5-10 min |

## Component Versions

| Component | Version |
|-----------|---------|
| Ubuntu (guest) | 24.04 LTS |
| Kubernetes | v1.35.3 |
| containerd | Ubuntu 24.04 apt |
| runc | Ubuntu 24.04 apt |
| cri-tools (crictl) | v1.35.0 |
| CNI plugins | v1.7.1 |
| Calico | v3.31.0 |

Kubernetes v1.35 is the version the CKA exam currently targets.

## Network Configuration

| CIDR / Address | Purpose | Where It Appears |
|----------------|---------|------------------|
| `192.168.100.0/24` | Lab-VMs VLAN 100, bridge `br-vm` | VM IPs (`.10`, `.11`, `.12`), host at `.2`, UCG-Fiber gateway at `.1`, MetalLB pool (optional) |
| `10.96.0.0/16` | Service ClusterIP range | `kubeadm` `serviceSubnet`, CoreDNS ClusterIP (`10.96.0.10`), kubelet `clusterDNS`, `kubernetes` Service (`10.96.0.1`) |
| `10.244.0.0/16` | Pod IP range | `kubeadm` `podSubnet`, Calico IPPool `cidr` |

## VM Access

All three VMs are reachable directly over SSH from the host through the bridge.

| Access Method | Command |
|--------------|---------|
| SSH into control plane | `ssh controlplane-1` |
| SSH into worker 1 | `ssh nodes-1` |
| SSH into worker 2 | `ssh nodes-2` |
| API server from host | `curl --cacert ~/cka-lab/three-kubeadm/ca.crt https://192.168.100.10:6443/healthz` |
| `kubectl` from host | `KUBECONFIG=~/cka-lab/three-kubeadm/admin.conf kubectl get nodes` |
| `controlplane-1` console log | `tail -f ~/cka-lab/three-kubeadm/controlplane-1/controlplane-1-console.log` |
| `nodes-1` console log | `tail -f ~/cka-lab/three-kubeadm/nodes-1/nodes-1-console.log` |
| `nodes-2` console log | `tail -f ~/cka-lab/three-kubeadm/nodes-2/nodes-2-console.log` |
| Stop all VMs | `~/cka-lab/three-kubeadm/stop-cluster.sh` |
| Start all VMs | `~/cka-lab/three-kubeadm/start-cluster.sh` |

Default VM credentials: user `kube`, password `kubeadmin`.

## SSH Config

Add this to `~/.ssh/config` on the host once:

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

Host nodes-2
    HostName 192.168.100.12
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
```

## Where Everything Runs

All Kubernetes components run inside the VMs. The static-pod control plane (etcd,
kube-apiserver, kube-controller-manager, kube-scheduler) runs only on `controlplane-1`.
`controlplane-1` is left untainted so workloads can also schedule there, giving you a
three-node scheduling surface.

## Scope

Three-node cluster: one control plane, two workers. The control plane is intentionally
left untainted. HA control plane setups (stacked etcd, multiple control planes, external
load balancer) are documented in `ha-kubeadm`.

---

[Next: Host Bridge Setup for Three-Node Networking →](01-host-bridge-setup.md)
