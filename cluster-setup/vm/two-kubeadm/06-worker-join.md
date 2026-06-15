# Joining the Worker Node

**Based on:** Original work, with reference to the upstream [kubeadm join documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/join-nodes/).

**Purpose:** Add `nodes-1` to the cluster as a worker, verify cross-node pod networking through the Calico VXLAN tunnel, and snapshot both qcow2 disks so you can roll back to clean-install state after deliberately breaking things.

---

## What This Chapter Does

The actual `kubeadm join` is a single command on `nodes-1`. The surrounding work in this document is the part that matters: generating a fresh join token (the default token from `kubeadm init` expires after 24 hours), verifying network connectivity from `nodes-1` to the apiserver before the join, confirming that `calico-node` schedules onto the new node automatically, and exercising cross-node networking to make sure the Calico VXLAN tunnel is actually working.

The CKA exam tests `kubeadm join` and token rotation explicitly, so the practice of generating a fresh token here matches the exam workflow.

## Prerequisites

`controlplane-1` is `Ready` with Calico installed. `nodes-1` has containerd running and the `kubeadm` toolchain installed at v1.35.3 from document 03. SSH access to both nodes from the host.



All verification commands that reference `192.168.100.10` must use your actual controlplane-1 IP.

---

## Part 1: Generate a Fresh Join Command

If you still have the join command from `kubeadm init` and it is less than 24 hours old, use it. Otherwise (or if you just want to do this the way you would on the exam):

```bash
ssh controlplane-1

# Print a complete join command with a new token (default TTL: 24h)
kubeadm token create --print-join-command
```

The output is a single line:

```
kubeadm join 192.168.100.10:6443 --token a1b2c3.d4e5f6g7h8i9j0k1 --discovery-token-ca-cert-hash sha256:abc123...
```

Copy that line. You will paste it on `nodes-1`.

If you need a token that lasts longer:

```bash
kubeadm token create --ttl 0 --print-join-command   # never expires
```

For exam practice, the default 24-hour TTL is the right habit. Token rotation under time pressure is a real exam scenario.

## Part 2: Pre-flight on nodes-1

Quick sanity checks before the join:

```bash
ssh nodes-1

# Prerequisites still in place after any reboots
sudo swapon --show               # should be empty
systemctl is-active containerd   # active
sudo crictl version > /dev/null && echo "crictl OK"

# nodes-1 can reach the apiserver
curl -k https://192.168.100.10:6443/healthz
# Should print: ok

# nodes-1 can resolve and reach controlplane-1 by name (kubelet relies on this for some operations)
ping -c 2 controlplane-1
```

The hostname resolution works because cloud-init wrote `/etc/hosts` entries on both nodes during provisioning. If `ping controlplane-1` fails, see the cloud-init troubleshooting in `runbook-qemu-vm.md`.

## Part 3: Join the Cluster

Run the join command from Part 1 on `nodes-1`. Substitute your actual token and hash:

```bash
sudo kubeadm join 192.168.100.10:6443 \
  --token <your-token> \
  --discovery-token-ca-cert-hash sha256:<your-hash> \
  --node-name nodes-1 \
  --cri-socket unix:///run/containerd/containerd.sock
```

Successful output ends with:

```
Run 'kubectl get nodes' on the control-plane to see this node join the cluster.
```

The join takes 10 to 30 seconds.

## Part 4: Verify From the Control Plane

```bash
ssh controlplane-1

# nodes-1 should appear, possibly NotReady at first
kubectl get nodes -o wide
```

Within a minute, `nodes-1` should transition to `Ready`. Calico's daemonset schedules a `calico-node` pod onto `nodes-1` automatically:

```bash
# Watch the calico-node pod for nodes-1 come up
kubectl -n calico-system get pods -o wide -l k8s-app=calico-node -w
```

Press Ctrl-C once both `calico-node` pods are `1/1 Running`.

```bash
# Final state
kubectl get nodes -o wide
kubectl get pods -A -o wide
```

Both nodes should be `Ready`, and the `kube-system` pods should be spread between them. CoreDNS typically lands on whichever node had capacity first; you may see both replicas on `controlplane-1` right after the join, then a rebalance.

## Part 5: Pod Spreading Test

By default the scheduler tries to balance pod count across nodes. Schedule four pods and verify it spreads them.

```bash
for i in 1 2 3 4; do
  kubectl run web-$i --image=nginx:1.27 --restart=Never
done

kubectl wait --for=condition=Ready pod/web-1 pod/web-2 pod/web-3 pod/web-4 --timeout=60s

# Should be roughly 2 per node
kubectl get pods -o wide
kubectl get pods -o wide --no-headers | awk '{print $7}' | sort | uniq -c

# Cleanup
kubectl delete pod web-1 web-2 web-3 web-4
```

## Part 6: Cross-Node Pod-to-Pod Networking Test

This is the multi-node version of the smoke test from document 05. It confirms Calico's VXLAN tunnel is actually doing its job between nodes.

```bash
# Pin one pod per node
kubectl run alpha --image=nginx:1.27 --overrides='{"spec":{"nodeName":"controlplane-1"}}' --restart=Never
kubectl run beta  --image=nginx:1.27 --overrides='{"spec":{"nodeName":"nodes-1"}}' --restart=Never
kubectl wait --for=condition=Ready pod/alpha pod/beta --timeout=60s

# Verify they are on different nodes
kubectl get pods -o wide alpha beta

# Pod IPs
ALPHA_IP=$(kubectl get pod alpha -o jsonpath='{.status.podIP}')
BETA_IP=$(kubectl get pod beta -o jsonpath='{.status.podIP}')
echo "alpha=${ALPHA_IP} on controlplane-1"
echo "beta=${BETA_IP} on nodes-1"

# Cross-node curl (both directions)
kubectl exec alpha -- curl -s --max-time 3 -o /dev/null -w "%{http_code}\n" "http://${BETA_IP}"
kubectl exec beta  -- curl -s --max-time 3 -o /dev/null -w "%{http_code}\n" "http://${ALPHA_IP}"
# Both should print 200

# Cleanup
kubectl delete pod alpha beta
```

If the cross-node curls fail, the Calico VXLAN tunnel is broken. See the multi-node section of `runbook-kubeadm.md` for diagnostics.

## Part 7: Service Resolution Across Nodes

Last sanity check: a Service backed by a pod on one node, accessed from a pod on the other.

```bash
# Deployment + Service
kubectl create deployment web --image=nginx:1.27 --replicas=1
kubectl wait --for=condition=Available deployment/web --timeout=60s
kubectl expose deployment web --port=80

# Find which node the web pod landed on
WEB_NODE=$(kubectl get pod -l app=web -o jsonpath='{.items[0].spec.nodeName}')
OTHER_NODE=$( [[ "$WEB_NODE" == "controlplane-1" ]] && echo nodes-1 || echo controlplane-1 )
echo "web is on ${WEB_NODE}, scheduling client on ${OTHER_NODE}"

# Client pod on the other node
kubectl run client --image=busybox:1.36 --restart=Never \
  --overrides="{\"spec\":{\"nodeName\":\"${OTHER_NODE}\"}}" \
  --command -- sleep 600
kubectl wait --for=condition=Ready pod/client --timeout=60s

# DNS resolution and HTTP both work
kubectl exec client -- nslookup web.default.svc.cluster.local
kubectl exec client -- wget -qO- --timeout=3 http://web.default.svc.cluster.local | head -5

# Cleanup
kubectl delete deployment web
kubectl delete service web
kubectl delete pod client
```

If DNS resolution fails, CoreDNS or kube-proxy is broken. The runbook covers both.

---

## Part 8: Snapshot the Clean-Install State

At this point you have a fresh, fully working two-node cluster. Snapshot the qcow2 disks so you can roll back after deliberately breaking things in a future troubleshooting practice script.

```bash
# Stop the cluster cleanly first (offline snapshots are reliable; live snapshots require qemu-guest-agent)
~/cka-lab/two-kubeadm/stop-cluster.sh

# Snapshot
qemu-img snapshot -c clean-install ~/cka-lab/two-kubeadm/controlplane-1/controlplane-1.qcow2
qemu-img snapshot -c clean-install ~/cka-lab/two-kubeadm/nodes-1/nodes-1.qcow2

# Verify
qemu-img snapshot -l ~/cka-lab/two-kubeadm/controlplane-1/controlplane-1.qcow2
qemu-img snapshot -l ~/cka-lab/two-kubeadm/nodes-1/nodes-1.qcow2

# Restart
~/cka-lab/two-kubeadm/start-cluster.sh
```

To roll back later:

```bash
~/cka-lab/two-kubeadm/stop-cluster.sh
qemu-img snapshot -a clean-install ~/cka-lab/two-kubeadm/controlplane-1/controlplane-1.qcow2
qemu-img snapshot -a clean-install ~/cka-lab/two-kubeadm/nodes-1/nodes-1.qcow2
~/cka-lab/two-kubeadm/start-cluster.sh
```

After the VMs come back up, the cluster will be in exactly the state it was when you snapshotted. This is much faster than `kubeadm reset` plus rebuild and avoids the risk of leaving subtle state behind.

---

## Summary

The two-node cluster is fully operational:

| Node | Role | Status | Pods |
|------|------|--------|------|
| `controlplane-1` | Control plane (untainted) | Ready | etcd, apiserver, controller-manager, scheduler (all static), kube-proxy, calico-node, plus workloads |
| `nodes-1` | Worker | Ready | kube-proxy, calico-node, plus workloads |

Both nodes can schedule pods, cross-node networking works, Service resolution works, and `NetworkPolicy` is enforced. The next document installs the optional cluster services (storage provisioner, Helm, metrics-server, MetalLB).

---

← [Previous: Installing Calico as the Cluster CNI](05-cni-installation.md) | [Next: Installing Cluster Services: Storage, Helm, Metrics, and Optional MetalLB →](07-cluster-services.md)
