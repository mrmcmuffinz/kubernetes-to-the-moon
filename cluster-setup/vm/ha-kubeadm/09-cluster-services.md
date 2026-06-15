# Cluster Services

**Based on:** [`two-kubeadm/07-cluster-services.md`](../two-kubeadm/07-cluster-services.md)

**Purpose:** Install cluster services. The process is identical to the other kubeadm
guides. With five nodes and three workers, all services benefit from true multi-node
placement.

---

## Prerequisites

All five nodes are `Ready` (document 08).

## Follow two-kubeadm/07

Follow [`two-kubeadm/07-cluster-services.md`](../two-kubeadm/07-cluster-services.md)
exactly. The local-path-provisioner, Helm, metrics-server, and MetalLB configurations
are unchanged.

## HA-Specific Verification

After completing the two-kubeadm document:

```bash
# All five nodes report metrics
kubectl top nodes

# CoreDNS should have 2 replicas spread across workers (anti-affinity)
kubectl -n kube-system get pods -l k8s-app=kube-dns -o wide

# DaemonSets: expected count depends on whether control planes are tainted
kubectl get daemonsets -A

# Verify cluster state is healthy via VIP
curl -sk https://192.168.100.100:6443/healthz
```

## Test Control Plane Failover

With cluster services installed, test that the cluster remains operational when
`controlplane-1` is shut down:

```bash
# Stop controlplane-1
~/cka-lab/ha-kubeadm/controlplane-1/stop-controlplane-1.sh

# Wait for HAProxy to detect the failure and reroute
sleep 15

# Cluster should still respond via VIP (now routing to controlplane-2)
export KUBECONFIG=~/cka-lab/ha-kubeadm/admin.conf
kubectl get nodes
kubectl get pods -A | grep -v Running

# Restart controlplane-1
~/cka-lab/ha-kubeadm/controlplane-1/start-controlplane-1.sh
```

Note: while `controlplane-1` is down, etcd has one member and cannot elect a new leader.
The cluster is read-only during this time (existing pods keep running; no new deployments
or changes can be written). HAProxy's health check detects the API server down within
10-15 seconds; connections to the VIP continue working via `controlplane-2`.

**Result:** Complete five-node HA cluster with DNS, storage, and metrics, capable of
surviving single control plane node failures.

---

← [Previous: Worker Join: nodes-1, nodes-2, nodes-3](08-worker-join.md)
