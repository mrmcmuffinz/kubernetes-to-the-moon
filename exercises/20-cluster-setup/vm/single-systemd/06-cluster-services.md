# Installing Cluster Services: DNS and Storage (Single Node)

**Based on:** [kubernetes-the-harder-way/07_Installing_Essential_Cluster_Services.md](https://github.com/ghik/kubernetes-the-harder-way/blob/linux/docs/07_Installing_Essential_Cluster_Services.md) and [08_Simplifying_Network_Setup_with_Cilium.md](https://github.com/ghik/kubernetes-the-harder-way/blob/linux/docs/08_Simplifying_Network_Setup_with_Cilium.md)

**Simplified for:** A single-node cluster running inside a QEMU VM with user-mode networking.

---

## What This Chapter Does

The cluster is functional but missing two services that typical workloads depend on:

1. **CoreDNS** provides cluster-internal DNS so pods can reach services by name (e.g., `my-service.default.svc.cluster.local`) instead of by ClusterIP.
2. **A storage provisioner** handles PersistentVolumeClaim requests so stateful workloads (databases, caches) can get dynamically allocated volumes.

Both are installed using Helm.

## What Was Removed from the Original Guide

The original guide installs three additional services. Two of them do not apply to a single-node QEMU setup:

- **NFS dynamic provisioner:** Requires the guest VM to mount NFS shares from the QEMU host. With user-mode networking, the guest cannot reliably reach the host as an NFS server. This document substitutes the simpler `local-path-provisioner` instead.
- **MetalLB:** Assigns external IPs to LoadBalancer-type Services by advertising them via ARP/NDP on the local network. With QEMU user-mode networking there is no shared L2 network to advertise on, so MetalLB serves no purpose here.

## Prerequisites

SSH into the VM. All control plane and worker components should be running. You should be able to run `kubectl get nodes` and see `controlplane-1` in `Ready` status.

## Installing Helm

Helm is the package manager used to install CoreDNS and the storage provisioner. It runs as a client tool on the same machine where you run kubectl.

```bash
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

Verify:

```bash
helm version
```

## Installing CoreDNS

CoreDNS is the standard cluster DNS server for Kubernetes. It runs as a Deployment inside the cluster and gets a fixed ClusterIP that kubelet was configured to inject into every pod's DNS configuration.

```bash
helm repo add coredns https://coredns.github.io/helm
helm install -n kube-system coredns coredns/coredns \
  --set service.clusterIP=10.96.0.10 \
  --set replicaCount=1
```

The `service.clusterIP=10.96.0.10` must match the `clusterDNS` value in the kubelet configuration from the previous chapter. The original guide uses 2 replicas for high availability across nodes; with a single node, 1 replica is sufficient.

The chart defaults handle RBAC creation (`rbac.create: true`) and deployment creation (`deployment.enabled: true`). These do not need to be set explicitly.

Wait for the CoreDNS pod to start:

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=coredns -w
```

Once it shows `1/1 Running`, DNS is operational. Verify the Service:

```bash
kubectl -n kube-system get svc coredns
```

Expected output:

```
NAME      TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)         AGE
coredns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP   60s
```

### Testing DNS Resolution

Create a test pod and verify it can resolve Kubernetes service names. Use `curl` rather than `nslookup` for this test. `nslookup` in busybox and other minimal images does not apply search domain expansion the same way a standard libc resolver does, which causes false NXDOMAIN failures for short names even when DNS is working correctly. `curl` goes through `getaddrinfo` and applies the ndots and search domain rules from the pod's `resolv.conf`.

```bash
kubectl run dnstest --image=curlimages/curl --rm -it --restart=Never -- \
  curl -sk -o /dev/null -w "%{http_code}" https://kubernetes.default
```

A `403` response confirms DNS is working. The short name `kubernetes.default` is expanded to `kubernetes.default.svc.cluster.local` by the resolver, which CoreDNS resolves to `10.96.0.1` (the API server's ClusterIP). The API server returns 403 because the request is unauthenticated, not because DNS failed.

To confirm the fully qualified name also resolves:

```bash
kubectl run dnstest --image=curlimages/curl --rm -it --restart=Never -- \
  curl -sk -o /dev/null -w "%{http_code}" https://kubernetes.default.svc.cluster.local
```

This should also return `403`.

### Troubleshooting CoreDNS

**Check pod status and logs:**

```bash
kubectl -n kube-system get pods -l app.kubernetes.io/name=coredns
kubectl -n kube-system logs -l app.kubernetes.io/name=coredns
```

**Verify the Service and Endpoints are populated:**

```bash
kubectl -n kube-system get svc coredns
kubectl -n kube-system get endpoints coredns
```

The endpoints should show the CoreDNS pod IP on port 53. If endpoints are empty, the pod is not running or its labels do not match the service selector.

**Verify the Corefile is correct:**

```bash
kubectl -n kube-system get configmap coredns -o yaml
```

The `kubernetes` plugin block must be present with `cluster.local` in the zone list. If it is missing, CoreDNS will not handle in-cluster DNS queries.

**Verify RBAC was created:**

```bash
kubectl get clusterrole coredns
kubectl get clusterrolebinding coredns
```

Both must exist. If either is missing, the kubernetes plugin cannot list services and endpoints from the API server and will return NXDOMAIN for all in-cluster names. Reinstall the chart cleanly rather than applying RBAC manually, since the chart manages these resources.

**Enable debug logging temporarily:**

Edit the Corefile configmap to add `log` and `debug` inside the `.:53` block:

```bash
kubectl -n kube-system edit configmap coredns
```

Add after `errors`:

```
errors
log
debug
```

The `reload` plugin picks up the change automatically within 30 seconds. Watch the logs while running a DNS test to see exactly what queries CoreDNS receives and how it handles them:

```bash
kubectl -n kube-system logs -l app.kubernetes.io/name=coredns -f
```

Remove `log` and `debug` from the Corefile after troubleshooting is complete.

**Check what resolv.conf pods are receiving:**

```bash
kubectl run dnstest --image=curlimages/curl --rm -it --restart=Never -- cat /etc/resolv.conf
```

Expected output for a pod in the `default` namespace:

```
search default.svc.cluster.local svc.cluster.local cluster.local
nameserver 10.96.0.10
options ndots:5
```

If the nameserver is not `10.96.0.10` or the search domains are missing, the issue is in kubelet's DNS configuration rather than CoreDNS. Check:

```bash
systemctl cat kubelet | grep -E 'cluster-dns|cluster-domain'
```

Both `--cluster-dns=10.96.0.10` and `--cluster-domain=cluster.local` must be set.

---

## Installing local-path-provisioner (Optional)

If you plan to run any stateful workloads that need PersistentVolumeClaims, you need a storage provisioner. The `local-path-provisioner` from Rancher is the simplest option for a single-node lab. It creates PersistentVolumes backed by directories on the node's local filesystem.

This is not production-appropriate (data is tied to the node and does not survive node loss), but it is perfectly fine for a CKA study environment.

```bash
kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.35/deploy/local-path-storage.yaml
```

Verify the provisioner is running:

```bash
kubectl -n local-path-storage get pods
```

Set it as the default StorageClass:

```bash
kubectl patch storageclass local-path \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

Verify:

```bash
kubectl get storageclass
```

Expected output:

```
NAME                   PROVISIONER             RECLAIMPOLICY   VOLUMEBINDINGMODE      ...
local-path (default)   rancher.io/local-path   Delete          WaitForFirstConsumer   ...
```

### Testing Storage Provisioning

Create a PVC and a pod that writes a file to the mounted volume:

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 128Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: test-pvc-pod
spec:
  containers:
    - name: busybox
      image: busybox
      command: ["sh", "-c", "echo 'storage test' > /data/test.txt && sleep 3600"]
      volumeMounts:
        - mountPath: /data
          name: storage
  volumes:
    - name: storage
      persistentVolumeClaim:
        claimName: test-pvc
EOF
```

Wait for the pod to start, then verify the PVC is bound:

```bash
kubectl get pvc test-pvc
kubectl get pv
```

Confirm the file was written from inside the pod:

```bash
kubectl exec test-pvc-pod -- cat /data/test.txt
```

Expected output:

```
storage test
```

The local-path-provisioner stores data under `/opt/local-path-provisioner/` on the node, with one directory per PVC named `<pv-name>_<namespace>_<pvc-name>`. Find the directory and verify the file is visible directly on the node filesystem:

```bash
# Get the PV name
PV_NAME=$(kubectl get pvc test-pvc -o jsonpath='{.spec.volumeName}')

# Find the directory on the node
ls /opt/local-path-provisioner/${PV_NAME}_default_test-pvc/

# Read the file directly from the node
cat /opt/local-path-provisioner/${PV_NAME}_default_test-pvc/test.txt
```

Both should show `storage test`, confirming that data written inside the pod is stored on the node filesystem and accessible outside the pod.

### Verifying Cleanup

Before deleting, capture the PV directory path so you can confirm it is removed afterward:

```bash
PV_NAME=$(kubectl get pvc test-pvc -o jsonpath='{.spec.volumeName}')
PV_DIR="/opt/local-path-provisioner/${PV_NAME}_default_test-pvc"
echo "Watching: $PV_DIR"
ls $PV_DIR
```

Delete the pod and PVC:

```bash
kubectl delete pod test-pvc-pod
kubectl delete pvc test-pvc
```

The PVC deletion triggers the provisioner to run its teardown script, which removes the directory. Confirm it is gone:

```bash
ls $PV_DIR 2>&1
```

Expected output:

```
ls: cannot access '/opt/local-path-provisioner/pvc-...': No such file or directory
```

If the directory still exists a few seconds after PVC deletion, check that the provisioner pod is running:

```bash
kubectl -n local-path-storage get pods
```

---

## Final Cluster Verification

At this point, all components of the single-node cluster are running. Here is a comprehensive check:

```bash
echo "=== Node Status ==="
kubectl get nodes -o wide

echo ""
echo "=== System Pods ==="
kubectl -n kube-system get pods

echo ""
echo "=== All Services ==="
kubectl get svc --all-namespaces

echo ""
echo "=== Component Health ==="
kubectl get componentstatuses 2>/dev/null || echo "(componentstatuses deprecated, checking health endpoints)"
curl -s --cacert /var/lib/kubernetes/ca.pem https://127.0.0.1:6443/healthz && echo ""

echo ""
echo "=== Storage Classes ==="
kubectl get storageclass
```

---

## What About Cilium?

The original guide includes an optional chapter on replacing the basic CNI plugins and kube-proxy with [Cilium](https://cilium.io/), an eBPF-based networking solution. Cilium provides several advantages in multi-node clusters: it handles pod-to-pod routing across nodes via tunneling (eliminating the need for host-side routes), replaces iptables-based kube-proxy with eBPF programs, and supports advanced features like network policies and observability.

For a single-node cluster, Cilium is overkill. The basic bridge CNI works fine when there is no cross-node traffic to route, and iptables-based kube-proxy is perfectly adequate for a lab environment. Cilium is worth exploring later when you expand to multi-node (steps 2 and 3 of the incremental cluster build-out), or if you want hands-on experience with a production-grade CNI for CKA prep. The Mumshad course covers CNI concepts in S9 (Networking), and understanding both the basic bridge approach (what you have now) and a full CNI like Cilium or Calico gives you strong coverage of that exam domain.

---

## Summary

The single-node Kubernetes cluster is now complete:

| Layer | Components | Status |
|-------|-----------|--------|
| VM infrastructure | QEMU/KVM, Ubuntu 24.04 | Running |
| Container runtime | containerd, runc | Running |
| Control plane | etcd, kube-apiserver, kube-controller-manager, kube-scheduler | Running |
| Worker | kubelet, kube-proxy, CNI (bridge) | Running |
| Cluster services | CoreDNS | Running |
| Storage | local-path-provisioner (optional) | Running |

You can now deploy workloads, create Services, use PersistentVolumeClaims, and manage the cluster with kubectl, either from inside the VM or from the QEMU host through the port-forwarded 6443.
