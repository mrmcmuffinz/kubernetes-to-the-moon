# Raspberry Pi 5 Kubernetes Cluster (kubeadm)

A step-by-step guide for bootstrapping a three-node Kubernetes cluster on Raspberry Pi 5
8GB nodes using `kubeadm`. Built for CKA exam preparation on real bare-metal ARM64 hardware.

---

## Network

All Pi nodes are on VLAN 200 (`192.168.200.0/24`), configured in UCG-Fiber and the US-24
switch per [`../vm/00-vlan-host-network-setup.md`](../vm/00-vlan-host-network-setup.md)
Parts 1 and 2.

| Node | Hostname | IP | Role |
|------|----------|----|------|
| Pi 1 | `rpi-node-01` | `192.168.200.10` | Control plane |
| Pi 2 | `rpi-node-02` | `192.168.200.11` | Worker |
| Pi 3 | `rpi-node-03` | `192.168.200.12` | Worker |
| UCG-Fiber | — | `192.168.200.1` | Gateway |

---

## Documents

Follow these in order.

| # | Document | What It Does | Time |
|---|----------|-------------|------|
| 00 | [Overview](00-overview.md) | Hardware list, component versions, time estimate | — |
| 01 | [OS Setup](01-os-setup.md) | Flash with `dd`, write per-node cloud-init files (hostname, static IP, user, keyboard, kernel modules, swap disable) | 5-10 min per node (plus 3-5 min unattended first boot) |
| 02 | [Network Setup](02-network-setup.md) | Verify cloud-init results, add cluster /etc/hosts entries, confirm SSH and inter-node connectivity | 5 min per node |
| 03 | [Node Prerequisites](03-node-prerequisites.md) | containerd, runc, CNI plugins, crictl, kubeadm, kubelet, kubectl (ARM64) | 10-15 min all nodes |
| 04 | [Control Plane Init](04-control-plane-init.md) | `kubeadm init` on `rpi-node-01`, set up kubectl, copy kubeconfig to host | 10-15 min |
| 05 | [Worker Join](05-worker-join.md) | `kubeadm join` on `rpi-node-02` and `rpi-node-03`, verify all nodes Ready | 10 min |
| 06 | [Verify](06-verify.md) | DNS, pod scheduling across all nodes, cross-node connectivity | 5-10 min |

**Total time:** ~90 minutes (first pass; subsequent reprovisioning is faster once packages are cached locally).

---

## Component Versions

| Component | Version |
|-----------|---------|
| Raspberry Pi OS | Trixie Lite (arm64) |
| Kubernetes | v1.35.6 |
| containerd | 1.7.24 (Debian Trixie apt) |
| runc | Debian Trixie apt |
| cri-tools (crictl) | v1.35.0 |
| CNI plugins | Bundled with Calico |
| Calico | v3.31.5 (Tigera operator) |

Kubernetes v1.35 is the version the CKA exam currently targets.

---

## Runbook

[`runbook-pi-kubeadm.md`](runbook-pi-kubeadm.md) is the quick-reference card for day-to-day operations: start/stop cluster, drain/uncordon nodes, reset a node, etcd snapshot.
