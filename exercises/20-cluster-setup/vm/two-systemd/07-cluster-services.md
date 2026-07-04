# Cluster Services: DNS, Storage, Helm, Metrics, LoadBalancer (Two Nodes)

**Based on:** [06-cluster-services.md](../../single-systemd/06-cluster-services.md) of the single-node guide.

**Adapted for:** Two-node cluster. CoreDNS runs with 2 replicas to take advantage of both nodes. local-path-provisioner now provisions volumes on whichever node a pod lands on. MetalLB is added because bridge networking now makes LoadBalancer Services viable, unlike with QEMU user-mode.

---

## What This Chapter Does

Adds the optional cluster services on top of the working two-node cluster: CoreDNS for DNS resolution, Helm because the Mumshad course uses it in S12, local-path-provisioner for PVCs, metrics-server for `kubectl top` and HPA, and optionally MetalLB so that `LoadBalancer`-type Services get IPs you can actually reach from the host.

Run all commands from `controlplane-1` unless noted.

## What Is Different from the Single-Node Guide

- CoreDNS deployed with `replicas: 2` so each node can run a copy.
- local-path-provisioner unchanged but actually exercises its node-aware behavior because there is more than one node now.
- MetalLB added (skipped in single-node because QEMU user-mode networking has no L2 to advertise on; bridge networking does).
- metrics-server added (was added in single-kubeadm; should be added here too).

## Prerequisites

Document 06 complete. Cross-node pod traffic works. Both nodes are `Ready` and untainted. Run from `controlplane-1`:

```bash
ssh controlplane-1
kubectl get nodes
```

---

## Part 1: CoreDNS

CoreDNS is what makes Service DNS names work inside the cluster. Without it, pods can reach Services by ClusterIP but not by `web.default.svc.cluster.local`. The systemd guide does not get CoreDNS for free (kubeadm clusters do), so install it manually.

### Step 1: Install Helm

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version
```

### Step 2: Install CoreDNS via Helm

```bash
helm repo add coredns https://coredns.github.io/helm
helm repo update

helm install coredns coredns/coredns \
  --namespace kube-system \
  --set service.clusterIP=10.96.0.10 \
  --set replicaCount=2

# Wait for both replicas to come up
kubectl -n kube-system wait --for=condition=Ready pod -l k8s-app=coredns --timeout=120s

kubectl -n kube-system get pods -l k8s-app=coredns -o wide
```

The `service.clusterIP=10.96.0.10` value matches the `clusterDNS` in `/var/lib/kubelet/kubelet-config.yaml` from document 05. If you change one, change the other or DNS will not work.

`replicaCount=2` lets the scheduler put one CoreDNS pod on each node (it will not necessarily do that, but it can).

### Step 3: Smoke Test

```bash
kubectl run dns-test --image=busybox:1.36 --restart=Never -- sleep 600
kubectl wait --for=condition=Ready pod/dns-test --timeout=60s

kubectl exec dns-test -- nslookup kubernetes.default.svc.cluster.local
kubectl exec dns-test -- nslookup google.com

kubectl delete pod dns-test
```

The first `nslookup` should return `10.96.0.1`. The second should return Google's external IPs. If the first works but the second does not, CoreDNS cannot reach upstream resolvers; check the `forward` plugin in the CoreDNS ConfigMap.

---

## Part 2: local-path-provisioner

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.31/deploy/local-path-storage.yaml

kubectl -n local-path-storage wait --for=condition=Available deployment/local-path-provisioner --timeout=120s

# Make it default
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

kubectl get storageclass
```

### Smoke Test (Two-Node Aware)

This time, schedule the consumer on a specific node and verify the volume gets provisioned there:

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
  nodeName: nodes-1          # force to nodes-1
  containers:
    - name: app
      image: busybox:1.36
      command: ["sh", "-c", "echo hello-from-nodes-1 > /data/test && sleep 600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: smoke-pvc
EOF

kubectl wait --for=condition=Ready pod/smoke-pvc-pod --timeout=60s
kubectl exec smoke-pvc-pod -- cat /data/test    # hello-from-nodes-1

# The volume should physically exist on nodes-1
ssh nodes-1 'sudo ls /opt/local-path-provisioner/'

# Cleanup
kubectl delete pod smoke-pvc-pod
kubectl delete pvc smoke-pvc
```

The `WaitForFirstConsumer` binding mode means the PV is provisioned where the pod lands. With two nodes, this becomes meaningful: a PVC scheduled to `nodes-1` gets storage on `nodes-1`, not `controlplane-1`.

---

## Part 3: metrics-server

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.8.1/components.yaml

# Add the lab-only insecure flag
kubectl -n kube-system patch deployment metrics-server --type=json -p='[
  {"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}
]'

kubectl -n kube-system rollout status deployment/metrics-server --timeout=120s

# Wait for first scrape (~30s)
sleep 30
kubectl top nodes
kubectl top pods -A
```

`--kubelet-insecure-tls` is required because we did not bother setting up cluster-trusted kubelet serving certs in this lab. Production clusters use proper cert rotation and do not need this flag.

---

## Part 4: MetalLB (Optional)

MetalLB lets `LoadBalancer`-type Services actually get IPs. The single-node guide skipped it because QEMU user-mode networking has no L2 segment to advertise on. With the bridge in this guide, MetalLB works.

### Step 1: Install

```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

kubectl -n metallb-system wait --for=condition=Available deployment/controller --timeout=120s
kubectl -n metallb-system get pods
```

### Step 2: Configure an Address Pool

Allocate a small range from the bridge subnet for MetalLB to hand out. The bridge is `192.168.122.0/24`, with the host at `.1` and VMs at `.10` and `.11`. A safe range is `.100`-`.110`:

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: bridge-pool
  namespace: metallb-system
spec:
  addresses:
    - 192.168.122.100-192.168.122.110
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
kubectl create deployment lb-test --image=nginx:1.27 --replicas=2
kubectl expose deployment lb-test --port=80 --type=LoadBalancer

# Wait for an IP to be assigned
sleep 5
kubectl get svc lb-test

# The EXTERNAL-IP should be in the 192.168.122.100-110 range
LB_IP=$(kubectl get svc lb-test -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "LoadBalancer IP: $LB_IP"

# From the host (exit out of controlplane-1 first)
exit
curl http://${LB_IP}/    # should return nginx welcome
ssh controlplane-1

# Cleanup
kubectl delete deployment lb-test
kubectl delete service lb-test
```

If the host cannot reach the LoadBalancer IP, check that the host did not steal the IP for itself or that some other ARP responder is interfering. `arping -I br0 ${LB_IP}` from the host shows what is responding.

---

## Final Cluster Verification

```bash
echo "=== Nodes ==="
kubectl get nodes -o wide

echo ""
echo "=== System Pods ==="
kubectl get pods -A -o wide | grep -Ev '\bRunning\b|\bCompleted\b' || echo "All system pods running"

echo ""
echo "=== StorageClasses ==="
kubectl get storageclass

echo ""
echo "=== API Health ==="
kubectl get --raw /healthz && echo
```

The `kubectl get pods -A` view at this point should show pods running in:

| Namespace | What |
|-----------|------|
| `kube-system` | CoreDNS (2 replicas), metrics-server |
| `local-path-storage` | local-path-provisioner |
| `metallb-system` | MetalLB controller and speaker pods (if installed) |

Plus whatever you scheduled yourself.

---

## Summary

The two-node, from-scratch, systemd-managed cluster is complete:

| Layer | Components | Where |
|-------|-----------|-------|
| Control plane | etcd, kube-apiserver, kube-controller-manager, kube-scheduler | `controlplane-1` only, systemd |
| Worker | containerd, kubelet, kube-proxy | both nodes, systemd |
| Pod networking | bridge CNI per node + manual host routes | both nodes |
| DNS | CoreDNS (2 replicas, ClusterIP `10.96.0.10`) | scheduled on either node |
| Storage | local-path-provisioner (default StorageClass) | provisions on the consumer's node |
| Metrics | metrics-server | scheduled on either node |
| LoadBalancer | MetalLB (`192.168.122.100-110` pool, L2 mode) | optional, host-reachable |
| Helm | Helm v3 client | on `controlplane-1` |

The cluster is ready for any CKA scenario in the Mumshad course that does not specifically require `kubeadm` operations. For `kubeadm` lifecycle scenarios (`kubeadm init`, `join`, `upgrade`, `reset`, certificate renewal via `kubeadm certs`), use the `cka/vm/two-kubeadm` guide.
