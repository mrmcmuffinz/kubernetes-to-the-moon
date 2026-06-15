# HA Kubernetes Cluster (kubeadm): Overview

A step-by-step guide for bootstrapping a five-node, highly available Kubernetes cluster
on QEMU/KVM virtual machines using `kubeadm`. Built for CKA exam preparation.

---

## Documents

| # | Document | What It Does | Time |
|---|----------|-------------|------|
| 01 | [Host Network Setup](01-host-bridge-setup.md) | Confirms `br-vm` VLAN bridge and installs HAProxy on the host | 25-35 min |
| 02 | [VM Provisioning](02-vm-provisioning.md) | Creates five VMs with cloud-init and static bridge IPs | 25-30 min |
| 03 | [Node Prerequisites](03-node-prerequisites.md) | Installs containerd, runc, CNI binaries, crictl, and kubeadm on all five nodes | 15-20 min |
| 04 | [Load Balancer Setup](04-load-balancer-setup.md) | Configures HAProxy to load balance the two API servers; verifies the VIP | 10-15 min |
| 05 | [First Control Plane Init](05-control-plane-init.md) | `kubeadm init` on `controlplane-1` with `--control-plane-endpoint` pointing to the VIP | 15-20 min |
| 06 | [CNI Installation](06-cni-installation.md) | Installs Calico via Tigera operator, removes control-plane taint | 5-10 min |
| 07 | [Second Control Plane Join](07-second-control-plane-join.md) | `kubeadm join --control-plane` on `controlplane-2`; verifies two-member etcd | 10-15 min |
| 08 | [Worker Join](08-worker-join.md) | Joins `nodes-1`, `nodes-2`, `nodes-3`; verifies cross-node networking | 15-20 min |
| 09 | [Cluster Services](09-cluster-services.md) | Installs Helm, `local-path-provisioner`, `metrics-server`, optionally MetalLB | 5-10 min |

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
| HAProxy | 2.x (Ubuntu 24.04 default) |

Kubernetes v1.35 is the version the CKA exam currently targets.

## Node Assignments

| Hostname | VLAN 100 IP | Role |
|----------|-------------|------|
| `controlplane-1` | `192.168.100.20` | First control plane (stacked etcd) |
| `controlplane-2` | `192.168.100.21` | Second control plane (stacked etcd) |
| `nodes-1` | `192.168.100.22` | Worker |
| `nodes-2` | `192.168.100.23` | Worker |
| `nodes-3` | `192.168.100.24` | Worker |
| HAProxy VIP | `192.168.100.100` | Control plane load balancer (host-side only) |
| Host bridge `br-vm` | `192.168.100.2` | Host management access |
| UCG-Fiber (gateway) | `192.168.100.1` | Default gateway for all VMs |

## Network Configuration

| CIDR / Address | Purpose | Where It Appears |
|----------------|---------|------------------|
| `192.168.100.0/24` | Lab-VMs VLAN 100, bridge `br-vm` | All VM IPs, host at `.2`, UCG-Fiber gateway at `.1` |
| `192.168.100.100` | HAProxy VIP | `controlPlaneEndpoint` in kubeadm config, all kubeconfigs |
| `10.96.0.0/16` | Service ClusterIP range | `kubeadm` `serviceSubnet`, CoreDNS ClusterIP (`10.96.0.10`), kubelet `clusterDNS` |
| `10.244.0.0/16` | Pod IP range | `kubeadm` `podSubnet`, Calico IPPool `cidr` |

## VM Access

| Access Method | Command |
|--------------|---------|
| SSH control plane 1 | `ssh controlplane-1` |
| SSH control plane 2 | `ssh controlplane-2` |
| SSH worker 1 | `ssh nodes-1` |
| SSH worker 2 | `ssh nodes-2` |
| SSH worker 3 | `ssh nodes-3` |
| API via VIP | `curl -k https://192.168.100.100:6443/healthz` |
| `kubectl` from host | `KUBECONFIG=~/cka-lab/ha-kubeadm/admin.conf kubectl get nodes` |
| Stop all VMs | `~/cka-lab/ha-kubeadm/stop-cluster.sh` |
| Start all VMs | `~/cka-lab/ha-kubeadm/start-cluster.sh` |

Default credentials: user `kube`, password `kubeadmin`.

## SSH Config

Add to `~/.ssh/config`:

```ssh-config
Host controlplane-1
    HostName 192.168.100.20
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host controlplane-2
    HostName 192.168.100.21
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host nodes-1
    HostName 192.168.100.22
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host nodes-2
    HostName 192.168.100.23
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new

Host nodes-3
    HostName 192.168.100.24
    User kube
    IdentityFile ~/.ssh/id_ed25519
    StrictHostKeyChecking accept-new
```

## HAProxy Design

HAProxy runs on the host (not inside any VM). It listens on the VIP address
(`192.168.100.100:6443`) and forwards connections to both API servers using a
`tcp` mode frontend/backend pair. Health checks use the `/healthz` path. If
`controlplane-1`'s API server fails, HAProxy automatically routes new connections to
`controlplane-2`.

```
                  ┌────────────────────────────────────┐
Client            │  HAProxy (host)                    │
──────> :6443 ──> │  192.168.100.100:6443              │
                  │    backend: 192.168.100.20:6443 (CP1)│
                  │    backend: 192.168.100.21:6443 (CP2)│
                  └────────────────────────────────────┘
```

## HA Limitations in This Lab

This is a two-member etcd cluster, which means:
- Normal operation: both members participate in Raft elections and writes.
- One control plane down: the remaining member cannot elect a leader alone. The cluster
  becomes read-only (Pods keep running; no new API writes).
- Both down: full outage.

A three-member etcd cluster (three control planes) tolerates one failure and is the
minimum for production HA. The two-member setup here is suitable for practicing the
join workflow and API server load balancing without the RAM cost of a third control
plane.

---

[Next: Host Bridge Setup and HAProxy Load Balancer →](01-host-bridge-setup.md)
