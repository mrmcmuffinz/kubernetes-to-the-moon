# Raspberry Pi 5 Kubeadm Cluster: Overview

A three-node Kubernetes cluster on bare-metal Raspberry Pi 5 8GB nodes. One control
plane, two workers. Raspberry Pi OS Trixie Lite (arm64). Uses the same `kubeadm`
workflow as the `three-kubeadm` QEMU guide but runs on real hardware with ARM64 packages.

---

## Hardware

| Item | Quantity | Notes |
|------|----------|-------|
| Raspberry Pi 5 8GB | 3 | 8GB required for control plane; 4GB would be tight |
| MicroSD or NVMe | 3 | 32GB minimum; NVMe via PCIe HAT preferred for speed |
| Ethernet cable | 3 | Wired only; Wi-Fi is not recommended for Kubernetes |
| USB-C power supply (27W+) | 3 | Official Raspberry Pi 27W PSU recommended |
| Managed switch port (VLAN 200) | 3 | Configured via US-24 per `00-vlan-host-network-setup.md` |

## Network Configuration

VLAN 200 (`Lab-Pi`) is configured on the UCG-Fiber and US-24 per
[`../vm/00-vlan-host-network-setup.md`](../vm/00-vlan-host-network-setup.md) Parts 1 and 2.
No host bridge needed; Pi nodes plug directly into US-24 access ports on VLAN 200.

| Address | Role |
|---------|------|
| `192.168.200.1` | UCG-Fiber gateway (VLAN 200) |
| `192.168.200.10` | `rpi-node-01` (control plane) |
| `192.168.200.11` | `rpi-node-02` (worker 1) |
| `192.168.200.12` | `rpi-node-03` (worker 2) |

Internal Kubernetes ranges (same as all other kubeadm guides):

| CIDR | Purpose |
|------|---------|
| `10.96.0.0/16` | Service ClusterIP range (`serviceSubnet`) |
| `10.244.0.0/16` | Pod IP range (`podSubnet`, Calico IPPool) |

## Component Versions

| Component | Version | Source |
|-----------|---------|--------|
| Raspberry Pi OS | Trixie Lite (arm64) | `raspberrypi.com/software/operating-systems` |
| Kubernetes | v1.35.3 | `pkgs.k8s.io` (arch=arm64) |
| containerd | Debian Trixie apt | `apt install containerd` |
| runc | Debian Trixie apt | `apt install runc` |
| cri-tools (crictl) | v1.35.0 | GitHub release (arm64) |
| CNI plugins | v1.7.1 | GitHub release (arm64) |
| Calico | v3.31.0 | Tigera operator manifest (pulls ARM64 images automatically) |

## Time Estimate

| Phase | Time |
|-------|------|
| OS flash + first boot (per Pi) | 10-15 min |
| Network setup (per Pi) | 5 min |
| Node prerequisites (all 3 in parallel) | 15-20 min |
| Control plane init | 10-15 min |
| Worker join (both) | 5-10 min |
| Verification | 5-10 min |
| **Total** | **~90 min** |

## Differences from the QEMU kubeadm Guides

| Aspect | QEMU guides | Pi guide |
|--------|------------|---------|
| Architecture | x86_64 | ARM64 |
| OS delivery | QEMU cloud image + cloud-init | Flashed with `dd` from pre-configured image |
| Cloud-init | Used for VM network and user setup | Used extensively: hostname, static IP, user creation, keyboard, kernel modules, sysctl, package prereqs, swap disable, auto-reboot |
| Cgroup config | Not required (cloud image defaults work) | Required: `cmdline.txt` must include `cgroup_enable=memory cgroup_memory=1` |
| Package arch | `amd64` | `arm64` |
| Bridge on host | `br-vm` at `192.168.100.2` | Not needed; Pis connect directly to switch |
| VLAN | VLAN 100 (tagged on host trunk port) | VLAN 200 (access port, untagged to Pi) |

---

[Next: OS Setup →](01-os-setup.md)
