# Cluster Verification

**Purpose:** Confirm the cluster is healthy and ready for exam practice: DNS resolves,
pods schedule on all nodes, cross-node pod-to-pod traffic works through Calico.

Run these checks from the host against `~/cka-lab/pi-kubeadm/admin.conf`.

---

## Check 1: All Nodes Ready

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes -o wide
```

Expected: three nodes in `Ready` state with correct INTERNAL-IPs:

```
NAME    STATUS   ROLES           ...   INTERNAL-IP      ...
pi-cp   Ready    control-plane   ...   192.168.200.10   ...
pi-w1   Ready    worker          ...   192.168.200.11   ...
pi-w2   Ready    worker          ...   192.168.200.12   ...
```

---

## Check 2: All System Pods Running

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get pods -A
```

All pods should be `Running` or `Completed`. Common pods:
- `kube-system`: kube-apiserver, etcd, kube-controller-manager, kube-scheduler (on pi-cp), kube-proxy (on each node), CoreDNS (two replicas)
- `calico-system`: calico-node (one per node), calico-kube-controllers

---

## Check 3: DNS Resolution

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl run dns-test --image=busybox:1.36 \
  --restart=Never --rm -it -- nslookup kubernetes.default
```

Expected output includes:
```
Server:    10.96.0.10
Address 1: 10.96.0.10 kube-dns.kube-system.svc.cluster.local

Name:      kubernetes.default
Address 1: 10.96.0.1 kubernetes.default.svc.cluster.local
```

---

## Check 4: Pods Schedule on All Nodes

Deploy a DaemonSet to confirm all nodes accept workloads:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: verify-ds
  namespace: default
spec:
  selector:
    matchLabels:
      app: verify-ds
  template:
    metadata:
      labels:
        app: verify-ds
    spec:
      containers:
      - name: pause
        image: registry.k8s.io/pause:3.10
        resources:
          requests:
            cpu: 10m
            memory: 10Mi
EOF

# Wait for pods
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl rollout status daemonset/verify-ds

# Confirm one pod per node
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get pods -l app=verify-ds -o wide
```

Expected: 3 pods, one on each of `pi-cp`, `pi-w1`, `pi-w2`.

Clean up:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl delete daemonset verify-ds
```

---

## Check 5: Cross-Node Pod Communication

Deploy two pods on different nodes and ping between them:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: net-a
  namespace: default
spec:
  nodeName: pi-w1
  containers:
  - name: net
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: net-b
  namespace: default
spec:
  nodeName: pi-w2
  containers:
  - name: net
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl wait pod/net-a pod/net-b --for=condition=ready --timeout=120s

# Get pod IPs
NET_A_IP=$(KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get pod net-a -o jsonpath='{.status.podIP}')
NET_B_IP=$(KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get pod net-b -o jsonpath='{.status.podIP}')

# Ping from net-a to net-b (cross-node Calico VXLAN)
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf \
  kubectl exec net-a -- ping -c 3 "$NET_B_IP"
# Expected: 3 packets transmitted, 3 received, 0% packet loss
```

Clean up:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl delete pod net-a net-b
```

---

## Check 6: API Server Health from Host

```bash
curl -k https://192.168.200.10:6443/healthz
# Expected: ok
```

---

**Result:** All six checks pass. The Pi cluster is ready for CKA exam practice. Use
`KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf` as a prefix for all `kubectl` commands,
or add it to your shell profile:

```bash
echo 'export KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf' >> ~/.bashrc
source ~/.bashrc
```

---

← [Previous: Worker Join](05-worker-join.md) | [Runbook →](runbook-pi-kubeadm.md)
