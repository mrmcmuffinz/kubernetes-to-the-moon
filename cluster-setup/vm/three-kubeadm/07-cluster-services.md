# Cluster Services

**Based on:** [`two-kubeadm/07-cluster-services.md`](../two-kubeadm/07-cluster-services.md)

**Purpose:** Install the same set of services as the two-node guide. All steps are
identical except that MetalLB and metrics-server deploy pods across three nodes rather
than two.

---

## Prerequisites

All three nodes are `Ready` (document 06).

## Follow two-kubeadm/07

Follow [`two-kubeadm/07-cluster-services.md`](../two-kubeadm/07-cluster-services.md)
exactly. The local-path-provisioner, Helm, metrics-server, and MetalLB configurations
are unchanged for three nodes.

## Three-Node Specific Verification

After completing the two-kubeadm document, verify that cluster services spread correctly:

```bash
# metrics-server should report all three nodes
kubectl top nodes

# local-path-provisioner runs on one node (single replica)
kubectl -n local-path-storage get pods -o wide

# DaemonSets (calico-node, kube-proxy) should show 3 desired/3 available
kubectl get daemonsets -A
```

**Result:** Complete cluster with DNS, storage, and metrics ready for Day 1-14 Mumshad
scenarios across three nodes.

---

← [Previous: Worker Join: nodes-1 and nodes-2](06-worker-join.md)
