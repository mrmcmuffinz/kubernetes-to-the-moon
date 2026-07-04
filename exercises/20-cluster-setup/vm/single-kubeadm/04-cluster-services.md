# Installing Cluster Services: Storage, Helm, and Metrics (Single Node)

**Based on:** [06-cluster-services.md](../../single-systemd/06-cluster-services.md) of the systemd guide.

**Adapted for:** A single-node `kubeadm`-installed cluster. CoreDNS is already installed by `kubeadm init`, so the manual CoreDNS install from the systemd guide is dropped. `metrics-server` is added because HPA scenarios in S5 of the Mumshad course depend on it.

---

## What This Chapter Does

The cluster is functional. This document adds the small set of cluster services that make it useful for practicing CKA exam scenarios beyond raw pod scheduling: a default StorageClass so PVC questions work, `metrics-server` so HPA and `kubectl top` work, and Helm because the Mumshad course covers it in S12. All three are independent; install whichever you need.

CoreDNS is already running in `kube-system` because `kubeadm init` deployed it. No manual install step is needed for DNS.

## What Is Different from the systemd Guide

- **CoreDNS step removed.** Already installed by `kubeadm init` with the correct ClusterIP (`10.96.0.10`).
- **`metrics-server` added.** Mumshad S5 covers HPA which depends on `metrics-server`.
- **MetalLB still skipped.** With QEMU user-mode networking there is no shared L2 network to advertise on, same as the systemd guide. MetalLB is included in the two-node guides where bridge networking makes it viable.

## Prerequisites

`controlplane-1` is `Ready` with Calico installed. `kubectl` is configured.

---

## Part 1: local-path-provisioner

The systemd guide used local-path-provisioner because NFS does not work with QEMU user-mode networking. That constraint is unchanged here. local-path-provisioner is the simplest possible dynamic provisioner, KodeKloud labs use the same pattern, and the CKA exam tests StorageClass and PVC behavior, not NFS server administration.

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

local-path-provisioner uses `volumeBindingMode: WaitForFirstConsumer`. A PVC stays `Pending` until a pod claims it, and the underlying PV is provisioned on the node where that pod lands. This is the correct exam-relevant behavior.

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

If `kubectl top nodes` returns "metrics not available", give it another 30 seconds.

---

## Final Cluster Verification

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
| `kube-system` | apiserver, controller-manager, scheduler, etcd (all static), kube-proxy, coredns (2 replicas), metrics-server |
| `calico-system` | calico-typha, calico-node, calico-kube-controllers |
| `calico-apiserver` | calico-apiserver |
| `tigera-operator` | tigera-operator |
| `local-path-storage` | local-path-provisioner |

This is the full, exam-shaped cluster.

---

## Summary

The single-node `kubeadm` cluster is now complete:

| Layer | Components | Status |
|-------|-----------|--------|
| VM infrastructure | QEMU/KVM, Ubuntu 24.04 | Running |
| Container runtime | containerd, runc | Running |
| Control plane | etcd, kube-apiserver, kube-controller-manager, kube-scheduler | Running (static pods) |
| Worker | kubelet, kube-proxy | Running |
| Cluster networking | Calico (VXLANCrossSubnet), CoreDNS | Running |
| Storage | local-path-provisioner | Running, default StorageClass |
| Metrics | metrics-server | Running |
| Helm | Helm v3 | Installed |

You can now deploy workloads, create Services, use PersistentVolumeClaims, and manage the cluster with `kubectl` from inside the VM or from the host through the port-forwarded 6443.

---

← [Previous: Installing Calico as the Cluster CNI (Single Node)](03-cni-installation.md)
