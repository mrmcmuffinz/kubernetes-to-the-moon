# Worker Join: nodes-1 and nodes-2

**Based on:** [`two-kubeadm/06-worker-join.md`](../two-kubeadm/06-worker-join.md)

**Purpose:** Join both worker nodes to the cluster using a freshly generated kubeadm
token. Verify that pods schedule across all three nodes and that cross-node networking
works. Snapshot all disks for rollback practice.

---

## Prerequisites

- `controlplane-1` is `Ready` with Calico installed (document 05).
- `nodes-1` and `nodes-2` have containerd and kubeadm installed (document 03).

## Part 1: Preflight Checks on Both Workers

On each worker, verify the runtime and network path to the control plane:

```bash
for node in nodes-1 nodes-2; do
  echo "=== $node ==="
  ssh "$node" '
    sudo crictl info 2>/dev/null | grep -q runtimeHandlers && echo "containerd: OK" || echo "containerd: FAIL"
    free -h | grep Swap
    curl -sk https://192.168.100.10:6443/healthz && echo " (apiserver reachable)"
  '
done
```

## Part 2: Generate a Fresh Join Token

On `controlplane-1`:

```bash
ssh controlplane-1 'kubeadm token create --print-join-command'
```

This prints a `kubeadm join` command valid for 24 hours. Copy it -- you will run it on
both workers.

## Part 3: Join Both Workers

Run the join command on each worker. The command is the same for both:

```bash
JOIN_CMD=$(ssh controlplane-1 'kubeadm token create --print-join-command')

for node in nodes-1 nodes-2; do
  echo "=== Joining $node ==="
  ssh "$node" "sudo $JOIN_CMD"
done
```

## Part 4: Verify All Nodes Ready

From `controlplane-1` or the host:

```bash
kubectl get nodes -o wide
```

Wait 60-90 seconds for Calico to schedule a `calico-node` DaemonSet pod on each new
worker. All three nodes should show `Ready`:

```
NAME              STATUS   ROLES           AGE
controlplane-1    Ready    control-plane   10m
nodes-1           Ready    <none>          2m
nodes-2           Ready    <none>          1m
```

## Part 5: Verify Cross-Node Pod Scheduling

Test that pods land on all three nodes and can communicate across nodes:

```bash
# Schedule one pod on each node
for node in controlplane-1 nodes-1 nodes-2; do
  kubectl run "ping-${node}" --image=busybox:1.36 --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"${node}\"}}" -- sleep 600 &
done
wait

kubectl get pods -o wide
```

Verify cross-node connectivity:

```bash
# Get pod IPs
CP_POD_IP=$(kubectl get pod ping-controlplane-1 -o jsonpath='{.status.podIP}')
W1_POD_IP=$(kubectl get pod ping-nodes-1       -o jsonpath='{.status.podIP}')
W2_POD_IP=$(kubectl get pod ping-nodes-2       -o jsonpath='{.status.podIP}')

# Ping across all pairs
kubectl exec ping-controlplane-1 -- ping -c 2 "$W1_POD_IP"
kubectl exec ping-controlplane-1 -- ping -c 2 "$W2_POD_IP"
kubectl exec ping-nodes-1        -- ping -c 2 "$CP_POD_IP"
kubectl exec ping-nodes-1        -- ping -c 2 "$W2_POD_IP"
kubectl exec ping-nodes-2        -- ping -c 2 "$CP_POD_IP"
kubectl exec ping-nodes-2        -- ping -c 2 "$W1_POD_IP"

kubectl delete pod ping-controlplane-1 ping-nodes-1 ping-nodes-2
```

All pings should succeed. If any fail, check the Calico pod on the affected node.

## Part 6: Verify DaemonSet Placement

```bash
kubectl -n calico-system get pods -l k8s-app=calico-node -o wide
```

One `calico-node` pod should be running on each of the three nodes.

## Part 7: Disk Snapshots

Snapshot all three disks so you can roll back to this clean-install state after
deliberately breaking the cluster:

```bash
~/cka-lab/three-kubeadm/stop-cluster.sh

for node in controlplane-1 nodes-1 nodes-2; do
  DISK=~/cka-lab/three-kubeadm/$node/$node.qcow2
  qemu-img snapshot -c clean-install "$DISK"
  echo "Snapshot created for $node"
done

~/cka-lab/three-kubeadm/start-cluster.sh
```

To restore to the snapshot later:

```bash
~/cka-lab/three-kubeadm/stop-cluster.sh
for node in controlplane-1 nodes-1 nodes-2; do
  DISK=~/cka-lab/three-kubeadm/$node/$node.qcow2
  qemu-img snapshot -a clean-install "$DISK"
done
~/cka-lab/three-kubeadm/start-cluster.sh
```

**Result:** All three nodes `Ready`, pods scheduling across all nodes, cross-node Service
resolution working, disks snapshotted.

---

← [Previous: CNI Installation: Calico](05-cni-installation.md) | [Next: Cluster Services →](07-cluster-services.md)
