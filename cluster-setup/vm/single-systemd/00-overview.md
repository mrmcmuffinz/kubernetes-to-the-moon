# Kubernetes the Hard Way: Single-Node Cluster

A step-by-step guide for bootstrapping a single-node Kubernetes cluster from scratch inside a QEMU/KVM virtual machine on an Ubuntu 24.04 host. Built for CKA exam preparation.

---

## Documents

Follow these in order. Each document builds on the previous one.

| # | Document | What It Does | Time |
|---|----------|-------------|------|
| 01 | [QEMU VM Setup](01-qemu-vm-setup.md) | Verifies the QEMU/KVM stack on the host, creates a headless Ubuntu 24.04 VM with cloud-init, configures port forwarding for SSH and Kubernetes APIs | 25-35 min |
| 02 | [Bootstrapping Security](02-bootstrapping-security.md) | Generates a root CA, TLS certificates for all components, kubeconfig files, and the etcd encryption key | 30-40 min |
| 03 | [Control Plane](03-control-plane.md) | Installs etcd, kube-apiserver, kube-controller-manager, and kube-scheduler as systemd services | 35-45 min |
| 04 | [Container Runtime](04-container-runtime.md) | Installs containerd, runc, and crictl | 10-15 min |
| 05 | [Worker Components](05-worker-components.md) | Installs CNI plugins (bridge + loopback), kubelet, kube-proxy, and RBAC rules. Schedules a test pod to verify the cluster | 20-30 min |
| 06 | [Cluster Services](06-cluster-services.md) | Installs Helm, CoreDNS for cluster DNS, and optionally local-path-provisioner for PersistentVolumeClaims | 20-30 min |

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

Two IP ranges are used throughout the documents and must stay consistent:

| CIDR | Purpose | Where It Appears |
|------|---------|-----------------|
| `10.96.0.0/16` | Service ClusterIP range | kube-apiserver `--service-cluster-ip-range`, kube-controller-manager `--service-cluster-ip-range`, CoreDNS ClusterIP (`10.96.0.10`), kubelet `clusterDNS`, API server certificate SAN (`10.96.0.1`) |
| `10.244.0.0/16` | Pod IP range | kube-controller-manager `--cluster-cidr`, kube-proxy `clusterCIDR`, CNI bridge plugin `subnet` |

## VM Access

| Access Method | Command |
|--------------|---------|
| SSH into VM | `ssh kube@127.0.0.1 -p 2222` |
| API server from host | `curl -k https://127.0.0.1:6443/healthz` |
| kubectl from host | Copy kubeconfig from VM, set server to `https://127.0.0.1:6443` |
| VM console log | `tail -f ~/cka-lab/controlplane-1/controlplane-1-console.log` |
| Stop VM | `~/cka-lab/controlplane-1/stop-controlplane-1.sh` |

Default VM credentials: user `kube`, password `kubeadmin`.

## Where Everything Runs

All Kubernetes components run inside the VM. Certificate generation (cfssl) and kubeconfig generation (kubectl) also run inside the VM. The QEMU host is only used to manage the VM lifecycle (start/stop) and optionally to reach the API server through port forwarding.

## Scope

This guide covers a single-node cluster only. Multi-node (2-node and 3-node) clusters will require different networking (Linux bridge + TAP devices instead of QEMU user-mode), additional node certificates, and changes to etcd clustering. Those will be separate documents.
