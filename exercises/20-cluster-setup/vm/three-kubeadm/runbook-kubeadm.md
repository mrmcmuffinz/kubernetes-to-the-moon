# Troubleshooting Runbook: Three-Node kubeadm Cluster

This runbook covers issues specific to the three-node cluster. For the full diagnostic
workflow for `kubeadm init` failures, static pod manifests, etcd backup/restore,
Calico, CoreDNS, and cluster upgrades, see the two-node runbook at
[`two-kubeadm/runbook-kubeadm.md`](../two-kubeadm/runbook-kubeadm.md). The
path substitutions and diagnostic commands in that runbook apply directly here with
`nodes-2` as an additional node.

---

## Quick Diagnostic Reference

```bash
# 1. All three nodes registered and Ready
kubectl get nodes -o wide

# 2. Non-running pods
kubectl get pods -A | grep -Ev 'Running|Completed'

# 3. Node-level triage (all three nodes)
for node in controlplane-1 nodes-1 nodes-2; do
  echo "=== $node ==="
  ssh "$node" 'sudo systemctl status kubelet containerd --no-pager | grep -E "Active:|Loaded:"'
done

# 4. Static pods (control plane only)
ssh controlplane-1 'sudo crictl ps | grep -E "apiserver|etcd|controller|scheduler"'

# 5. Calico on all three nodes
kubectl -n calico-system get pods -l k8s-app=calico-node -o wide

# 6. DNS
kubectl -n kube-system get pods -l k8s-app=kube-dns

# 7. kube-proxy on all nodes
kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide
```

---

## Three-Node-Specific Issues

### nodes-2 Joins but Stays NotReady

This is normal for 30-60 seconds while Calico schedules a pod. If still `NotReady`
after 90 seconds:

```bash
kubectl describe node nodes-2 | grep -A 5 Conditions
kubectl -n calico-system get pods -o wide -l k8s-app=calico-node
kubectl -n calico-system describe pod -l k8s-app=calico-node -l kubernetes.io/hostname=nodes-2
```

Check containerd and kubelet on `nodes-2`:

```bash
ssh nodes-2 'sudo systemctl status containerd kubelet --no-pager | head -6'
ssh nodes-2 'sudo journalctl -u kubelet -n 30 --no-pager'
```

### Cross-Node Traffic Fails for nodes-2 Only

If pods on `controlplane-1` and `nodes-1` can ping each other but not `nodes-2`:

```bash
# Verify Calico VXLAN on nodes-2
ssh nodes-2 'ip -d link show vxlan.calico'

# Check Calico routes on nodes-2
ssh nodes-2 'sudo ip route | grep 10.244'

# Restart Calico on nodes-2 if routes are missing
kubectl -n calico-system delete pod -l k8s-app=calico-node \
  --field-selector spec.nodeName=nodes-2
```

### Workloads Not Scheduling on nodes-2

If pods stick on `controlplane-1` and `nodes-1` but not `nodes-2`:

```bash
# Check for taints
kubectl describe node nodes-2 | grep Taints

# Check node conditions
kubectl describe node nodes-2 | grep -A 5 Conditions

# If nodes-2 is cordoned
kubectl uncordon nodes-2
```

### Drain Leaves One Worker Empty

With two workers you can drain one and the other absorbs the load:

```bash
kubectl drain nodes-2 --ignore-daemonsets --delete-emptydir-data

# Verify all pods moved to nodes-1 or controlplane-1
kubectl get pods -A -o wide | grep -v calico

# Return nodes-2 to service
kubectl uncordon nodes-2
```

---

## kubeadm join Failures for nodes-2

### Token Expired

Tokens have a 24-hour TTL by default. Generate a fresh one:

```bash
ssh controlplane-1 'kubeadm token create --print-join-command'
```

### nodes-2 Already Joined (Re-Join)

If `nodes-2` was previously in the cluster and needs to re-join:

```bash
# On nodes-2
ssh nodes-2 'sudo kubeadm reset --force'
ssh nodes-2 'sudo rm -rf /etc/cni/net.d'

# Then run the fresh join command
ssh nodes-2 "sudo $(ssh controlplane-1 'kubeadm token create --print-join-command')"
```

---

## Cluster Upgrade (Three-Node)

The upgrade sequence follows the two-node pattern, extended to include `nodes-2`. See
`two-kubeadm/runbook-kubeadm.md` for the control plane upgrade steps, then apply the
worker upgrade to both `nodes-1` and `nodes-2` in sequence:

```bash
# Upgrade nodes-1
kubectl drain nodes-1 --ignore-daemonsets --delete-emptydir-data
ssh nodes-1 '
  sudo apt-mark unhold kubeadm
  sudo apt install -y kubeadm=1.36.0-1.1
  sudo apt-mark hold kubeadm
  sudo kubeadm upgrade node
  sudo apt-mark unhold kubelet kubectl
  sudo apt install -y kubelet=1.36.0-1.1 kubectl=1.36.0-1.1
  sudo apt-mark hold kubelet kubectl
  sudo systemctl daemon-reload && sudo systemctl restart kubelet
'
kubectl uncordon nodes-1

# Upgrade nodes-2 (same steps)
kubectl drain nodes-2 --ignore-daemonsets --delete-emptydir-data
ssh nodes-2 '... same commands ...'
kubectl uncordon nodes-2

kubectl get nodes -o wide  # All should show v1.36.0
```
