# Installing Calico as the Cluster CNI (Single Node)

**Based on:** Original work, with reference to the [Calico install documentation](https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart) and the upstream [kubeadm CNI guidance](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/#pod-network).

**Adapted for:** A single-node `kubeadm` cluster. Replaces the basic `bridge` plugin from `single-systemd/05-worker-components.md`. Calico is chosen because it is the most common CNI in CKA exam scenarios and KodeKloud labs, and because it actually enforces `NetworkPolicy`.

---

## What This Chapter Does

The control plane is up but `kubectl get nodes` shows `controlplane-1` as `NotReady` because there is no CNI. kubelet does not mark a node Ready until pod networking can be set up, which requires a CNI plugin to be present and a config file in `/etc/cni/net.d/`. This document installs Calico via the Tigera operator with a custom `Installation` resource and verifies that `NetworkPolicy` is actually enforced.

`NetworkPolicy` enforcement is the reason Calico is preferred over Flannel for the CKA. Flannel will let you create a `NetworkPolicy` resource without complaint and then silently ignore it. Any exam question that asks you to use `NetworkPolicy` to deny traffic will mark you wrong if your CNI does not enforce it.

## What Is Different from the systemd Guide

The systemd guide installed the basic CNI plugins (`bridge`, `loopback`) directly and wrote a config file by hand. That works for a single node where there is no cross-node traffic to handle, but does not give you `NetworkPolicy`.

Calico uses the same CNI plugin binaries you installed in document 01, plus its own controller plane (a daemonset that runs `calico-node` on every node, plus `calico-typha` and `calico-kube-controllers` as deployments). The Tigera operator manages all of this as Kubernetes resources, which is also the recommended modern install path.

## Prerequisites

`kubeadm init` complete. `kubectl get nodes` returns the single node in `NotReady` state. SSH into the VM or use the kubeconfig from the host. The commands below assume `kubectl` is configured.

---

## Part 1: Install the Tigera Operator

The Tigera operator runs as a deployment in the `tigera-operator` namespace and manages Calico itself as Kubernetes resources.

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.0/manifests/tigera-operator.yaml

# Wait for the operator
kubectl -n tigera-operator wait --for=condition=Available deployment/tigera-operator --timeout=120s

kubectl -n tigera-operator get pods
```

The operator pod should be `1/1 Running` before continuing.

## Part 2: Install Calico via the Installation Resource

The `Installation` custom resource tells the operator how to deploy Calico. The default `custom-resources.yaml` from the Calico repo uses pod CIDR `192.168.0.0/16`, which we need to change to match the kubeadm `podSubnet`.

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

- `cidr: 10.244.0.0/16` must match `podSubnet` in the kubeadm config from document 02. Mismatch here means pods get IPs from one CIDR but routes are written for the other.
- `encapsulation: VXLANCrossSubnet` skips encapsulation when both pods are on the same subnet (always the case on a single node) and uses VXLAN otherwise. This setting keeps working if you ever extend the lab.
- `natOutgoing: Enabled` means pods reach the internet through the host's NAT.
- `nodeSelector: all()` runs `calico-node` on every node, including the control plane.

## Part 3: Wait for Calico to Come Up

```bash
# Watch calico-system come alive
kubectl get pods -n calico-system -w
```

Press Ctrl-C once everything is `Running`. You should see at least:

- `calico-typha-*` (1 pod)
- `calico-node-*` (1 pod, one per node)
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

## Part 5: Pod Networking Smoke Test

Schedule a pod and verify it gets an IP from the pod CIDR.

```bash
kubectl run nettest --image=busybox:1.36 --restart=Never --command -- sleep 600
kubectl wait --for=condition=Ready pod/nettest --timeout=60s

# IP should be in 10.244.0.0/16
kubectl get pod nettest -o wide
kubectl get pod nettest -o jsonpath='{.status.podIP}'; echo

# Cleanup
kubectl delete pod nettest
```

## Part 6: NetworkPolicy Enforcement Smoke Test

This confirms Calico is actually enforcing `NetworkPolicy`, not just doing CNI plumbing.

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

# Now beta cannot reach alpha
kubectl exec -n netpol-test beta -- curl -s --max-time 3 -o /dev/null -w "%{http_code}\n" "http://${ALPHA_IP}" || echo "blocked"
# Expected: blocked

# Cleanup
kubectl delete namespace netpol-test
```

If the second curl returns `200`, Calico is not enforcing the policy and something is wrong with the install. The most common cause is that the install completed but `calico-node` is not actually `Ready`. Confirm with:

```bash
kubectl -n calico-system get pods -o wide -l k8s-app=calico-node
```

The READY column should show `1/1`.

---

## Summary

The cluster has working pod networking with `NetworkPolicy` enforcement:

| Component | Namespace | Purpose |
|-----------|-----------|---------|
| `tigera-operator` | `tigera-operator` | Reconciles Calico installation against the `Installation` CR |
| `calico-typha` | `calico-system` | Connection multiplexer between `calico-node` pods and the apiserver |
| `calico-node` | `calico-system` | Per-node daemonset, programs routes and `NetworkPolicy` |
| `calico-kube-controllers` | `calico-system` | Watches Kubernetes resources and updates Calico state |
| `calico-apiserver` | `calico-apiserver` | Aggregated API server for Calico-specific resources |

`controlplane-1` is `Ready`, the control-plane taint is removed, and `NetworkPolicy` enforcement is verified. The next document installs the optional cluster services.

---

← [Previous: Initializing the Control Plane with kubeadm (Single Node)](02-control-plane-init.md) | [Next: Installing Cluster Services: Storage, Helm, and Metrics (Single Node) →](04-cluster-services.md)
