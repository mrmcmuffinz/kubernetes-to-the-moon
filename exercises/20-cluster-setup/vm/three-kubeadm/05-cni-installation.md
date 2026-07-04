# CNI Installation: Calico

**Based on:** [`two-kubeadm/05-cni-installation.md`](../two-kubeadm/05-cni-installation.md)

**Purpose:** Install Calico via the Tigera operator. Identical to the two-node guide.

---

## Prerequisites

`kubeadm init` has completed on `controlplane-1` and `kubectl get nodes` works.

## Part 1: Install the Tigera Operator

On `controlplane-1` (or from the host with `KUBECONFIG` set):

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.0/manifests/tigera-operator.yaml
```

## Part 2: Apply the Calico Installation CR

The `cidr` must match the `podSubnet` from the kubeadm config (`10.244.0.0/16`):

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

## Part 3: Wait for Calico and Node Ready

```bash
kubectl wait --for=condition=Ready node/controlplane-1 --timeout=180s
kubectl -n calico-system get pods -l k8s-app=calico-node
```

All `calico-node` pods should be `Running`. Workers will also show `calico-node` pods
once they join.

## Part 4: Verify NetworkPolicy Enforcement

```bash
kubectl create namespace np-test
kubectl apply -n np-test -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: server
  labels:
    app: server
spec:
  containers:
  - name: nginx
    image: nginx:1.27
EOF

kubectl apply -n np-test -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes: [Ingress]
EOF

# Should time out (policy is blocking):
kubectl run client --rm -i --restart=Never --image=busybox:1.36 -- \
  wget -qO- --timeout=3 "$(kubectl -n np-test get pod server -o jsonpath='{.status.podIP}')" \
  || echo "Blocked as expected"

kubectl delete namespace np-test
```

**Result:** `controlplane-1` goes `Ready`, pods get IPs from `10.244.0.0/16`, and
`NetworkPolicy` is enforced.

---

← [Previous: Control Plane Initialization](04-control-plane-init.md) | [Next: Worker Join: nodes-1 and nodes-2 →](06-worker-join.md)
