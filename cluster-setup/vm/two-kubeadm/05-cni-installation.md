# Installing Calico as the Cluster CNI

**Based on:** Original work, with reference to the [Calico install documentation](https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart) and the upstream [kubeadm CNI guidance](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network).

**Purpose:** Install Calico as the cluster CNI so pods can get IPs and communicate. Replaces the basic `bridge` plugin from the single-node guide. Calico is chosen because it is the most common CNI in CKA exam scenarios and KodeKloud labs, and it is one of the few CNIs that actually enforces `NetworkPolicy`.

---

## What This Chapter Does

The control plane is up but `kubectl get nodes` shows `controlplane-1` as `NotReady` because there is no CNI. kubelet does not mark a node Ready until pod networking can be set up, which requires a CNI plugin to be present and a config file in `/etc/cni/net.d/`. This document installs Calico via the Tigera operator with a custom `Installation` resource, removes the control plane taint so workloads can run on `controlplane-1`, and verifies that `NetworkPolicy` is actually enforced.

`NetworkPolicy` enforcement is the reason Calico is preferred over Flannel for the CKA. Flannel will let you create a `NetworkPolicy` resource without complaint and then silently ignore it. Any exam question that asks you to use `NetworkPolicy` to deny traffic will mark you wrong if your CNI does not enforce it.

## What Is Different from the Single-Node Guide

The single-node guide installed the basic CNI plugins (`bridge`, `loopback`) directly and wrote a config file by hand. That works for a single node where there is no cross-node traffic, but does not give you `NetworkPolicy` and does not handle pod-to-pod routing across nodes.

Calico uses the same CNI plugin binaries you installed in document 03, plus its own controller plane (a daemonset that runs `calico-node` on every node, plus `calico-typha` and `calico-kube-controllers` as deployments). The Tigera operator manages all of this as Kubernetes resources, which is also the recommended modern install path.

## Prerequisites

`controlplane-1` is up and `kubectl get nodes` returns the single node in `NotReady` state. SSH into `controlplane-1` or use the kubeconfig from the host. The commands below assume `kubectl` is configured.

---

## Part 1: Install the Tigera Operator

Calico's recommended install path is via the Tigera operator. The operator runs as a deployment in the `tigera-operator` namespace and manages Calico itself as Kubernetes resources.

```bash
ssh controlplane-1

kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.5/manifests/tigera-operator.yaml

# Wait for the operator
kubectl -n tigera-operator wait --for=condition=Available deployment/tigera-operator --timeout=120s

kubectl -n tigera-operator get pods
```

The operator pod should be `1/1 Running` before continuing.

## Part 2: Install Calico via the Installation Resource

The `Installation` custom resource tells the operator how to deploy Calico. The default `custom-resources.yaml` from the Calico repo uses pod CIDR `192.168.0.0/16`, which collides with the host bridge subnet. Use a customized version that matches the `kubeadm` `podSubnet`.

```bash
cat > ~/calico-install.yaml <<'EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - name: default-ipv4-ippool
        blockSize: 26
        cidr: 10.244.0.0/16
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

kubectl apply -f ~/calico-install.yaml
```

A few notes on the configuration:

- `cidr: 10.244.0.0/16` must match `podSubnet` in the kubeadm config from document 04. Mismatch here means pods get IPs from one CIDR but routes are written for the other, and nothing works.
- `encapsulation: VXLANCrossSubnet` skips encapsulation when both pods are on the same subnet (which is always the case in this lab) and uses VXLAN otherwise. This is a sensible default that keeps working if you ever extend the lab.
- `natOutgoing: Enabled` means pods reach the internet through the host's NAT, which is what you want.
- `nodeSelector: all()` runs `calico-node` on every node, including the control plane.
- The `APIServer` resource enables the Calico API extension, which lets you `kubectl get networkpolicies` and use Calico-specific resources later if needed.

## Part 3: Wait for Calico to Come Up

```bash
# Watch calico-system come alive
kubectl get pods -n calico-system -w
```

Press Ctrl-C once everything is `Running`. You should see at least:

- `calico-typha-*` (1 pod, scales with cluster size)
- `calico-node-*` (1 pod per node, currently 1)
- `calico-kube-controllers-*` (1 pod)

```bash
kubectl get pods -n calico-system
kubectl get pods -n calico-apiserver
```

## Part 4: Verify the Node Goes Ready

```bash
kubectl get nodes -o wide
```

`controlplane-1` status should now be `Ready`. If it is still `NotReady` after a minute, check the kubelet logs:

```bash
sudo journalctl -u kubelet -n 50 | grep -i 'cni\|network'
```

The kubelet typically reports the missing CNI as `network plugin returns error: cni plugin not initialized`. Once Calico writes `/etc/cni/net.d/10-calico.conflist`, this error clears within seconds.

```bash
# Confirm Calico's CNI config landed
sudo ls -la /etc/cni/net.d/
sudo cat /etc/cni/net.d/10-calico.conflist | head -10
```

## Part 5: Remove the Control Plane Taint

By default, `kubeadm init` taints the control plane node with `node-role.kubernetes.io/control-plane:NoSchedule`. With only two nodes available, you want every pod to have somewhere to run if a worker is drained. The CKA exam frequently asks you to drain a node and verify pods reschedule; if `controlplane-1` is tainted and you drain `nodes-1`, pods will go `Pending` instead of moving to `controlplane-1`.

```bash
# Check current taints
kubectl describe node controlplane-1 | grep -i taint

# Remove the control-plane NoSchedule taint
kubectl taint nodes controlplane-1 node-role.kubernetes.io/control-plane:NoSchedule-

# Verify
kubectl describe node controlplane-1 | grep -i taint
# Expected: Taints: <none>
```

Re-tainting later is a single command, and worth knowing because the CKA exam tests the taint syntax both ways:

```bash
# To put the taint back later (for practice):
kubectl taint nodes controlplane-1 node-role.kubernetes.io/control-plane=:NoSchedule
```

## Part 6: Pod Networking Smoke Test

Schedule a pod and verify it gets an IP from the pod CIDR.

```bash
# Run a test pod
kubectl run nettest --image=busybox:1.36 --restart=Never --command -- sleep 600
kubectl wait --for=condition=Ready pod/nettest --timeout=60s

# IP should be in 10.244.0.0/16
kubectl get pod nettest -o wide
kubectl get pod nettest -o jsonpath='{.status.podIP}'; echo

# Cleanup
kubectl delete pod nettest
```

## Part 7: NetworkPolicy Enforcement Smoke Test

This confirms Calico is actually enforcing `NetworkPolicy`, not just doing CNI plumbing. `NetworkPolicy` questions are common on the exam and easy to get wrong if your CNI silently ignores them.

```bash
# Create two pods in a fresh namespace
kubectl create namespace netpol-test
kubectl run alpha --namespace netpol-test --image=nginx:1.27 --labels="app=alpha"
kubectl run beta  --namespace netpol-test --image=nginx:1.27 --labels="app=beta"
kubectl wait --namespace netpol-test --for=condition=Ready pod/alpha pod/beta --timeout=60s

# Baseline: beta can reach alpha
ALPHA_IP=$(kubectl get pod alpha -n netpol-test -o jsonpath='{.status.podIP}')
kubectl exec -n netpol-test beta -- curl -s --max-time 3 -o /dev/null -w "%{http_code}\n" "http://${ALPHA_IP}"
# Expected: 200

# Apply a deny-all-ingress policy on alpha
kubectl apply -n netpol-test -f - <<'EOF'
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-to-alpha
spec:
  podSelector:
    matchLabels:
      app: alpha
  policyTypes:
    - Ingress
EOF

# Now beta cannot reach alpha (curl will hang on the connect, hence --max-time)
kubectl exec -n netpol-test beta -- curl -s --max-time 3 -o /dev/null -w "%{http_code}\n" "http://${ALPHA_IP}" || echo "blocked"
# Expected: blocked

# Cleanup
kubectl delete namespace netpol-test
```

If the second curl returns `200`, Calico is not enforcing the policy and something is wrong with the install. The most common cause is that the install completed but the `calico-node` pod is not actually `Ready`. Confirm with:

```bash
kubectl -n calico-system get pods -o wide -l k8s-app=calico-node
```

The READY column should show `1/1`.

---

## Summary

The cluster now has working pod networking with `NetworkPolicy` enforcement:

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| `tigera-operator` | `tigera-operator` | Reconciles Calico installation against the `Installation` CR |
| `calico-typha` | `calico-system` | Connection multiplexer between `calico-node` pods and the apiserver |
| `calico-node` | `calico-system` | Per-node daemonset, programs routes and `NetworkPolicy` |
| `calico-kube-controllers` | `calico-system` | Watches Kubernetes resources and updates Calico state |
| `calico-apiserver` | `calico-apiserver` | Aggregated API server for Calico-specific resources |

`controlplane-1` is `Ready`, the control-plane taint is removed, and `NetworkPolicy` enforcement is verified. The next document joins `nodes-1` to the cluster.

---

← [Previous: Initializing the Control Plane with kubeadm](04-control-plane-init.md) | [Next: Joining the Worker Node →](06-worker-join.md)
