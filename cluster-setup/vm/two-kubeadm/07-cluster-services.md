# Installing Cluster Services: Storage, Helm, Metrics, and Optional MetalLB

**Based on:** [06-cluster-services.md](../../vm/docs/06-cluster-services.md) of the single-node guide.

**Adapted for:** A two-node bridge-networked cluster. CoreDNS is already installed by `kubeadm init` (the single-node guide had to install it manually because the manual control plane build did not include it). MetalLB is now viable because there is real L2 connectivity, so it is included as an optional step.

---

## What This Chapter Does

The cluster is functional. This document adds the small set of cluster services that make it useful for practicing CKA exam scenarios beyond raw pod scheduling: a default StorageClass so PVC questions work, `metrics-server` so HPA and `kubectl top` work, Helm because the Mumshad course covers it in S12, and optionally MetalLB so `LoadBalancer`-type Services actually get IPs. All four are independent; install whichever you need.

CoreDNS is already running in `kube-system` because `kubeadm init` deployed it. No manual install step is needed for DNS.

## What Is Different from the Single-Node Guide

- **CoreDNS step removed.** Already installed by `kubeadm init` with the correct ClusterIP (`10.96.0.10`).
- **MetalLB included.** The single-node guide skipped it because user-mode networking has no shared L2 to advertise on. With bridge networking, MetalLB's L2 mode works.
- **`metrics-server` added.** Mumshad S5 covers HPA which depends on `metrics-server`. Worth installing once and leaving in place.

## Prerequisites

Both nodes are `Ready`. `kubectl` is configured (either on `controlplane-1` or via the kubeconfig copied to the host).

---

## Part 1: local-path-provisioner

The single-node guide used local-path-provisioner because NFS does not work with QEMU user-mode networking. With the bridge, NFS would work too, but local-path-provisioner is still the right choice for a CKA lab: it is the simplest possible dynamic provisioner, KodeKloud labs use the same pattern, and the CKA exam tests StorageClass and PVC behavior, not NFS server administration.

### Step 1: Install

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml

kubectl -n local-path-storage wait --for=condition=Available deployment/local-path-provisioner --timeout=120s
```

### Step 2: Set as Default StorageClass

```bash
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

kubectl get storageclass
```

The `local-path` StorageClass should show `(default)`.

### Step 3: Smoke Test

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: smoke-pvc
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 128Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: smoke-pvc-pod
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo hello > /data/test && sleep 600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: smoke-pvc
EOF

kubectl wait --for=condition=Ready pod/smoke-pvc-pod --timeout=60s
kubectl exec smoke-pvc-pod -- cat /data/test    # should print: hello

# Cleanup
kubectl delete pod smoke-pvc-pod
kubectl delete pvc smoke-pvc
```

local-path-provisioner uses `volumeBindingMode: WaitForFirstConsumer`, which is the correct exam-relevant behavior to know: a PVC stays `Pending` until a pod claims it, and the underlying PV is provisioned on the node where that pod lands.

---

## Part 2: Helm

Helm is in the Mumshad course (S12) and shows up on the exam.

### Step 1: Install

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm version
```

### Step 2: Smoke Test

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install hello bitnami/nginx --set service.type=ClusterIP

kubectl get pods,svc -l app.kubernetes.io/instance=hello

# Cleanup
helm uninstall hello
```

---

## Part 3: metrics-server

`kubectl top nodes`, `kubectl top pods`, and HPA all depend on `metrics-server`. The HPA scenarios in S5 of the Mumshad course are unmissable on the exam.

### Step 1: Install

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.1/components.yaml
```

### Step 2: Add the Insecure-TLS Flag for Lab Use

In a lab the kubelet's serving cert is self-signed and metrics-server rejects it by default. Add the lab-only insecure flag:

```bash
kubectl -n kube-system patch deployment metrics-server --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}
]'

kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s
```

This flag is for lab environments only. Never use it in production.

### Step 3: Smoke Test

```bash
# First scrape takes ~30 seconds
sleep 30
kubectl top nodes
kubectl top pods -A
```

If `kubectl top nodes` returns "metrics not available", give it another 30 seconds. If it still fails, see the `metrics-server` section of `runbook-kubeadm.md`.

---

## Part 4: MetalLB (Optional)



Choose a range that:
- Is on the same subnet as your bridge and VMs
- Does not conflict with your VMs (e.g., .210, .211), gateway, or bridge IP
- Has enough addresses for your testing needs (20 IPs is typically sufficient)

---

Without a cloud provider, `Service type=LoadBalancer` stays in `<pending>` forever because there is nothing to assign external IPs. MetalLB fills that role on bare metal and makes Ingress controller install scenarios work end to end. Skip this if you only care about ClusterIP and NodePort.

### Step 1: Install

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.8/config/manifests/metallb-native.yaml

kubectl -n metallb-system wait --for=condition=Available deployment/controller --timeout=120s
```

### Step 2: Configure an Address Pool

Pick a slice of the bridge subnet that does not overlap with the two VMs. The VMs use `.10` and `.11`, so `.200` to `.220` is safe.

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: bridge-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.100.200-192.168.100.220
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: bridge-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - bridge-pool
EOF
```

### Step 3: Smoke Test

```bash
kubectl create deployment lb-test --image=nginx:1.27
kubectl expose deployment lb-test --port=80 --type=LoadBalancer

# Wait for MetalLB to assign an IP
sleep 5
kubectl get svc lb-test
# EXTERNAL-IP should be in 192.168.100.200-220

# Reach it from the host
LB_IP=$(kubectl get svc lb-test -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -s "http://${LB_IP}" | head -5

# Cleanup
kubectl delete service lb-test
kubectl delete deployment lb-test
```

---

## Final Cluster State

After all of the above, run a comprehensive check:

```bash
echo "=== Node Status ==="
kubectl get nodes -o wide

echo ""
echo "=== System Pods ==="
kubectl get pods -A

echo ""
echo "=== Storage Classes ==="
kubectl get storageclass

echo ""
echo "=== API Health ==="
kubectl get --raw /healthz && echo
```

`kubectl get pods -A` should show pods running in:

| Namespace | Pods |
|-----------|------|
| `kube-system` | apiserver, controller-manager, scheduler, etcd (all static, on `controlplane-1`), kube-proxy (one per node), coredns (2 replicas) |
| `calico-system` | calico-typha, calico-node (one per node), calico-kube-controllers |
| `calico-apiserver` | calico-apiserver |
| `tigera-operator` | tigera-operator |
| `local-path-storage` | local-path-provisioner |
| `kube-system` (continued) | metrics-server |
| `metallb-system` | controller, speaker (one per node) |

This is the full, exam-shaped cluster.

## What to Skip

For the CKA exam specifically, these are nice but not necessary:

- An Ingress controller. The exam tests Ingress YAML, not nginx-ingress install per se. Mumshad S9 covers it if you want to practice it.
- Cilium. Calico is sufficient. If you want hands-on with eBPF networking later, Cilium is straightforward to install with `cilium install` after uninstalling Calico.
- Multiple control planes. Real HA practice requires a third node and an external load balancer; out of scope here.

---

## Summary

The two-node cluster is now complete:

| Layer | Components | Status |
|-------|-----------|--------|
| VM infrastructure | QEMU/KVM, Ubuntu 24.04, host bridge | Running |
| Container runtime | containerd, runc | Running on both nodes |
| Control plane | etcd, kube-apiserver, kube-controller-manager, kube-scheduler | Running on `controlplane-1` (static pods) |
| Worker | kubelet, kube-proxy | Running on both nodes |
| Cluster networking | Calico (VXLANCrossSubnet), CoreDNS | Running |
| Storage | local-path-provisioner | Running, default StorageClass |
| Metrics | metrics-server | Running |
| Helm | Helm v3 | Installed |
| Load balancing | MetalLB (optional) | Running, address pool configured |

The cluster is ready for every Day 1 through Day 14 scenario in the Mumshad CKA course.

---

← [Previous: Joining the Worker Node](06-worker-join.md)
