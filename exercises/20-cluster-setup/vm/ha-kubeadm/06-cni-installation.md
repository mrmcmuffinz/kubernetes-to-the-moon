# CNI Installation: Calico

**Based on:** [`two-kubeadm/05-cni-installation.md`](../two-kubeadm/05-cni-installation.md)

**Purpose:** Install Calico via the Tigera operator. Identical to the other kubeadm
guides. Once Calico is running, `controlplane-1` goes `Ready`. `controlplane-2` and the
workers are still not joined.

---

## Prerequisites

`kubeadm init` has completed on `controlplane-1` (document 05).

```bash
export KUBECONFIG=~/cka-lab/ha-kubeadm/admin.conf
kubectl get nodes
# controlplane-1   NotReady   control-plane   ...
```

## Part 1: Install the Tigera Operator

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.0/manifests/tigera-operator.yaml
```

## Part 2: Apply the Calico Installation CR

```bash
cat <<EOF | kubectl create -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
      - name: default-ipv4-ippool
        cidr: 10.244.0.0/16
        encapsulation: VXLANCrossSubnet
        natOutgoing: Enabled
        nodeSelector: all()
EOF
```

## Part 3: Wait for controlplane-1 Ready

```bash
kubectl wait --for=condition=Ready node/controlplane-1 --timeout=180s
kubectl get nodes
# controlplane-1   Ready   control-plane   ...
```

## Part 4: Remove Taint from controlplane-1

The taint should have been removed in document 05. Verify:

```bash
kubectl describe node controlplane-1 | grep Taints
# Expected: Taints: <none>
```

If still tainted:

```bash
kubectl taint nodes controlplane-1 node-role.kubernetes.io/control-plane:NoSchedule-
```

Leave `controlplane-2` tainted for now. After it joins, remove its taint if you want
workloads to schedule there too (document 07).

**Result:** `controlplane-1` is `Ready`, pods get IPs from `10.244.0.0/16`, and
`NetworkPolicy` is enforced. `controlplane-2` and all workers are not yet joined.

---

← [Previous: First Control Plane Initialization](05-control-plane-init.md) | [Next: Second Control Plane Join →](07-second-control-plane-join.md)
