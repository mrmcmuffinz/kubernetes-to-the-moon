# Kubernetes from Scratch: VM and Pi Cluster Guides

This directory contains guides for building Kubernetes clusters on QEMU/KVM virtual
machines and on physical Raspberry Pi 5 hardware. Two VM guides use manual systemd
configuration to show how Kubernetes works under the hood; the rest use `kubeadm` to
match the exam environment. A separate Pi track builds a three-node ARM64 kubeadm
cluster on dedicated hardware for hands-on exam practice.

These guides are optional and not required for CKA exam preparation. The main exercises
in this repository (`exercises/`) are built around kind clusters, which start fast, clean
up easily, and closely match the exam environment. The VM and Pi guides exist for learners
who find that understanding the internals makes the exam topics click, or who want a
persistent cluster to practice on.

## VM Guides

**Network prerequisite for multi-node VM guides:** All multi-node QEMU clusters (two-kubeadm,
three-kubeadm, ha-kubeadm) use a VLAN-isolated host bridge rather than NAT. Complete
[`vm/00-vlan-host-network-setup.md`](vm/00-vlan-host-network-setup.md) before starting
any of those guides. Single-node and two-systemd guides are unaffected.

| Guide | Install Method | Nodes | Time Estimate | Purpose |
|-------|----------------|-------|---------------|---------|
| [`vm/single-systemd`](vm/single-systemd/) | Manual binaries + systemd units | 1 | 2-3 hours | Understand what every component does and how they connect |
| [`vm/single-kubeadm`](vm/single-kubeadm/) | kubeadm | 1 | 30-45 minutes | See what kubeadm automates, practice exam-style operations |
| [`vm/two-systemd`](vm/two-systemd/) | Manual binaries + systemd units | 2 | 3-4 hours | Understand multi-node networking, manual route programming |
| [`vm/two-kubeadm`](vm/two-kubeadm/) | kubeadm | 2 (1 CP + 1 worker) | 1 hour | Practice kubeadm join, multi-node exam scenarios |
| [`vm/three-kubeadm`](vm/three-kubeadm/) | kubeadm | 3 (1 CP + 2 workers) | 1.5 hours | Scheduling across multiple workers, drain and upgrade practice |
| [`vm/ha-kubeadm`](vm/ha-kubeadm/) | kubeadm + HAProxy | 5 (2 CP + 3 workers) | 2-2.5 hours | HA control plane, second control plane join, VIP load balancing |

All VM guides target Kubernetes v1.35.3 (the CKA exam version) and use Ubuntu 24.04 LTS guest VMs.

## Pi Cluster Guide

The [`pi/`](pi/) track builds a three-node kubeadm cluster on Raspberry Pi 5 8GB hardware
running Ubuntu Server 24.04 LTS (ARM64). It targets the same Kubernetes version (v1.35.3)
and installs the same Calico CNI as the VM guides. Use this cluster as a persistent
practice environment that stays up between sessions.

| Guide | Nodes | Time Estimate | Purpose |
|-------|-------|---------------|---------|
| [`pi/`](pi/) | 3 (1 CP + 2 workers, ARM64) | ~90 minutes | Physical kubeadm cluster for persistent CKA exam practice |

See [`pi/README.md`](pi/README.md) for the full guide list and component version table.

### Single-Systemd: The Deepest Dive

The [`vm/single-systemd`](vm/single-systemd/) guide builds a single-node cluster entirely from scratch. You download raw binaries for etcd, kube-apiserver, kube-controller-manager, kube-scheduler, kubelet, and kube-proxy, write systemd units for each, generate all certificates by hand with cfssl, and configure the CNI plugin directly. This is the slowest path (2-3 hours start to finish) but the one with the most visibility. When something breaks in a production cluster, the mental model you build here is what helps you diagnose it.

This guide is adapted from [Kubernetes the Harder Way](https://github.com/ghik/kubernetes-the-harder-way/tree/linux) by ghik, which itself is inspired by Kelsey Hightower's [Kubernetes the Hard Way](https://github.com/kelseyhightower/kubernetes-the-hard-way).

### Single-Kubeadm: The Exam-Focused Path

The [`vm/single-kubeadm`](vm/single-kubeadm/) guide builds the same single-node cluster but uses `kubeadm init` instead of manual systemd units. It takes 30-45 minutes instead of 2-3 hours. The guide includes a file mapping table that shows where each `kubeadm`-generated file lives and what its hand-rolled equivalent was in the systemd guide, so you can use the systemd guide as a reference when troubleshooting.

The CKA exam runs on `kubeadm`-installed clusters and tests `kubeadm` lifecycle operations directly: cluster init, worker join, token rotation, certificate renewal, control plane upgrades, and etcd backup/restore. This guide is the right tool for practicing those exam-shaped operations.

### Two-Systemd: Multi-Node Internals

The [`vm/two-systemd`](vm/two-systemd/) guide extends the single-systemd approach to two nodes: one control plane, one worker. The VMs sit on a Linux bridge with real IPs instead of QEMU user-mode networking. Cross-node pod traffic requires manually adding `ip route` entries on each node, which exposes the routing layer that Calico, Cilium, and Flannel handle automatically. This is the guide to work through if you want to understand how CNI plugins actually program routes and what "overlay network" means in concrete terms.

Nobody runs production clusters this way. The point is educational: seeing the seams makes the abstractions less magical.

### Two-Kubeadm: Multi-Node Exam Practice

The [`vm/two-kubeadm`](vm/two-kubeadm/) guide builds a two-node cluster with `kubeadm`, installs Calico (so `NetworkPolicy` actually works), and is suitable for practicing every Day 1 through Day 14 scenario in the Mumshad CKA course: scheduling, taints and tolerations, node affinity, daemonsets, cordon and drain, control plane upgrades, kubeadm join token rotation, etcd backup and restore, and multi-node networking troubleshooting.

### Three-Kubeadm: Scheduling Across Two Workers

The [`vm/three-kubeadm`](vm/three-kubeadm/) guide extends the two-node setup to one control plane and two workers. The key reason to add a second worker is scheduling visibility: with two workers you can drain one and watch workloads migrate, see DaemonSet pods placed one-per-worker, and exercise pod affinity and anti-affinity rules that spread (or co-locate) pods across nodes. The setup is otherwise identical to the two-node guide and reuses the same bridge, containerd configuration, and kubeadm workflow.

### HA-Kubeadm: High Availability Control Plane

The [`vm/ha-kubeadm`](vm/ha-kubeadm/) guide builds a five-node cluster with two control plane nodes and three workers. A HAProxy instance on the host bridge serves as the control plane VIP (`192.168.100.100:6443`), and `kubeadm init --upload-certs` + `kubeadm join --control-plane` handle the stacked-etcd HA join. This is the guide to use if you want to practice the `kubeadm join --control-plane` workflow, understand how `controlPlaneEndpoint` works, see how etcd quorum changes when a control plane node goes down, and test HAProxy health-check-driven failover.

## Is This For You?

### Use kind clusters (per docs/cluster-setup.md) if:
- You want to work through the main exercises quickly
- You value speed and disposability (cluster up in 30 seconds, tear down instantly)
- You are on macOS or Windows (kind runs anywhere Docker/nerdctl runs)
- You just want to pass the CKA exam

### Use these VM guides if:
- You want to understand how Kubernetes works internally
- Exam topics like "etcd backup" or "certificate renewal" feel opaque and you want to see what those operations actually touch
- You learn best by building something from first principles
- You have an Ubuntu 24.04 host with KVM support and 8-16 GB RAM to spare
- You are comfortable with multi-hour exercises

The two approaches are complementary. Many learners work through the main exercises with kind first, then come back to the VM guides later when they want deeper understanding of specific topics (PKI, CNI, etcd clustering, static pods).

## Platform Requirements

All guides assume:
- **Host OS:** Ubuntu 24.04 LTS
- **CPU:** x86_64 with hardware virtualization enabled (Intel VT-x or AMD-V)
- **RAM:** 8 GB for single-node, 16 GB for two-node, 24 GB for three-node, 40 GB for five-node HA (4 GB per VM plus host overhead)
- **Disk:** 50 GB free for single-node, 100-250 GB for multi-node (40 GB per VM)
- **Tooling:** QEMU/KVM, cloud-init, basic shell proficiency

These are more restrictive than kind. If you are on macOS, Windows, or a Linux host without KVM, stick with kind.

### Optional: Reducing Repeated Downloads

If you rebuild VMs frequently to practice the init workflow, you will re-download the
same packages, binary archives, and container images on every run. Three optional guides address this:

- [`vm/apt-cache-proxy.md`](vm/apt-cache-proxy.md) sets up nginx as an APT caching proxy on the host so that Ubuntu and Kubernetes packages are served from a local cache after the first download (sub-second `apt-get update` on cache hits).
- [`vm/binary-cache.md`](vm/binary-cache.md) uses a QEMU 9p virtfs share to give the VM persistent access to a host directory where the install scripts save their binary archives, so `wget --timestamping` skips all downloads on subsequent rebuilds. Applies to systemd-based guides only.
- [`vm/registry-cache.md`](vm/registry-cache.md) runs pull-through registry caches on the host via nerdctl so that container images (pause, kube-apiserver, etcd, coredns, calico, etc.) are served from local cache after the first pull. Applies to all guides.

## Recommended Sequence

**New to Kubernetes?** Start with the main exercises in `exercises/01-pods/` using kind clusters (per `docs/cluster-setup.md`). The VM guides assume you already know what pods, services, and namespaces are.

**Preparing for CKA exam operations?** Do `vm/single-kubeadm` first to practice cluster init and lifecycle operations, then `vm/two-kubeadm` for multi-node scenarios (kubeadm join, drain, upgrade).

**Want to truly understand Kubernetes?** The deepest path is:
1. `vm/single-systemd` (2-3 hours): Build every component by hand
2. `vm/single-kubeadm` (30-45 min): See what kubeadm automates, use the file mapping table to connect back to the systemd guide
3. `vm/two-systemd` (3-4 hours): Extend the systemd approach to two nodes, program routes manually
4. `vm/two-kubeadm` (1 hour): See the kubeadm equivalent for multi-node

**Want to practice exam scheduling scenarios?** Do `two-kubeadm` first, then `three-kubeadm` for a richer scheduling surface (two workers to spread pods across, drain-and-migrate practice).

**Want to understand HA control planes?** Work through `two-kubeadm` first, then `ha-kubeadm` for the HA join workflow, HAProxy VIP, and etcd quorum behavior.

Most learners do not work through all six. Common patterns:
- Just `single-systemd` for the deepest dive on control plane components
- Just `single-kubeadm` + `two-kubeadm` for exam-focused practice
- `two-kubeadm` + `three-kubeadm` for richer multi-node scheduling practice
- `two-kubeadm` + `ha-kubeadm` for HA control plane understanding

## What These Guides Offer That kind Doesn't

1. **PKI visibility**: Hand-generating certificates with cfssl exposes the full CA chain, SANs, and how component identities work
2. **systemd service files**: See exact component flags and their purpose (kind abstracts this into container entrypoints)
3. **CNI routing layer**: Manual route programming demystifies overlay networks (kind uses kindnet, which is opaque)
4. **etcd operations**: Direct `etcdctl` interaction (kind runs etcd as a static pod, less visible)
5. **Certificate SANs**: Understand why the apiserver cert needs multiple IPs (matters for troubleshooting)
6. **kubelet bootstrap**: See the CSR approval flow that kubeadm automates
7. **Control plane as static pods**: Understand `/etc/kubernetes/manifests/` watching (kubeadm uses this, systemd guide explains it)

## What kind Offers That VMs Don't

1. **Speed**: Cluster up in 30 seconds vs. 10 minutes (kubeadm) or 2 hours (systemd)
2. **Disposability**: `kind delete cluster` and start fresh instantly
3. **Resource efficiency**: No full VM overhead
4. **Multi-cluster**: Run several in parallel for testing
5. **Cross-platform**: Works on macOS, Windows, Linux

**Conclusion:** kind is for practicing, VMs are for understanding. Use the right tool for your goal.

## Relationship to Main Exercises

The 45 assignments in `exercises/` are the core of this repository. They are built to develop exam fluency through repetition on a kind cluster. Each assignment has a tutorial, 15 progressive exercises, and a complete answer key. The content is designed to be worked through in sequence, following the `LEARNING_PATH.md` curriculum.

The VM guides in this directory are supplementary. They exist for learners who want to go deeper on specific topics after completing the relevant main exercises. The table below maps each guide to the exercises that share its subject matter.

| Guide | Pairs well with | Connection |
|-------|----------------|------------|
| `vm/single-systemd` | `exercises/18-tls-and-certificates/` | `02-bootstrapping-security.md` shows every cert generated by hand using cfssl, which makes certificate renewal in the exam exercises concrete |
| `vm/single-systemd` | `exercises/17-cluster-lifecycle/` | `03-control-plane.md` shows the systemd units behind every component kubeadm manages; useful context before doing kubeadm upgrades |
| `vm/single-systemd` | `exercises/09-coredns/` | `06-cluster-services.md` installs CoreDNS via Helm with a hand-set ClusterIP, exposing the clusterDNS/clusterIP coupling that CoreDNS debugging exercises rely on |
| `vm/single-kubeadm` | `exercises/17-cluster-lifecycle/` | `02-control-plane-init.md` is the kubeadm init walkthrough with a file mapping table -- read it before working through upgrade and join exercises |
| `vm/single-kubeadm` | `exercises/14-pod-security/` | The single-kubeadm cluster uses Calico and has `PodSecurity` admission available; use it to test Pod Security Standards without relying on kind |
| `vm/two-systemd` | `exercises/10-network-policies/` | `06-manual-pod-routing.md` explains exactly what a CNI plugin does under the hood, which is the right mental model for debugging NetworkPolicy |
| `vm/two-systemd` | `exercises/09-coredns/` | The two-node CoreDNS install (two replicas, per-node) is the reference for what the exercises' CoreDNS debugging scenarios are based on |
| `vm/two-kubeadm` | `exercises/17-cluster-lifecycle/` | `06-worker-join.md` and the runbook cover kubeadm join, token rotation, and the two-node upgrade workflow end to end |
| `vm/two-kubeadm` | `exercises/10-network-policies/` | Calico on bridge networking enforces NetworkPolicy; use the two-kubeadm cluster to test cross-node NetworkPolicy exercises |
| `vm/three-kubeadm` | `exercises/17-cluster-lifecycle/` | Two-worker drain exercises are realistic here -- drain one worker and watch pods migrate to the other |
| `vm/three-kubeadm` | `exercises/08-services/` | Three-node cluster gives you better service load-balancing visibility with kube-proxy distributing traffic across two real worker nodes |
| `vm/ha-kubeadm` | `exercises/17-cluster-lifecycle/` | `07-second-control-plane-join.md` covers the `kubeadm join --control-plane` path and etcd quorum behavior that the lifecycle exercises reference |
| `vm/ha-kubeadm` | `exercises/18-tls-and-certificates/` | The multi-SAN certificate requirement (VIP + both control plane IPs) in `05-control-plane-init.md` directly reinforces the cert SAN exercises |

The VM guides are not prerequisites for the main exercises. Start with the main exercises, come back to the VM guides when a topic feels opaque and you want to see the internals.

## Next Steps

Pick a guide from the table above, read its README, and start building. Each guide is self-contained with step-by-step instructions, verification commands after each major operation, and troubleshooting runbooks.
