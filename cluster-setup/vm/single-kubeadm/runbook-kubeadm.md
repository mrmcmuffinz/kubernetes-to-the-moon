# Troubleshooting Runbook: Single-Node kubeadm Cluster

This runbook covers diagnostic and repair procedures specific to a `kubeadm`-installed single-node cluster: `kubeadm init` failures, kubelet, static pod control plane edits, certificate problems, CoreDNS, kube-proxy, and Calico CNI.

For host-side QEMU and VM issues (KVM not available, port forwarding not working, cloud-init failures), see `single-systemd/runbook-qemu-vm.md`. The QEMU layer is identical between the systemd and kubeadm guides.

For the underlying systemd component diagnostics (etcd, apiserver, controller-manager, scheduler, kubelet, kube-proxy), the principles in `single-systemd/runbook-control-plane.md` and `single-systemd/runbook-worker-components.md` still apply. The path mapping below shows where each file lives in a kubeadm cluster.

---

## File Path Mapping

The systemd runbooks reference paths under `/etc/systemd/system/`, `/etc/etcd/`, and `/var/lib/kubernetes/`. With kubeadm, those files live in different locations:

| systemd path | kubeadm path |
|---|---|
| `/etc/systemd/system/etcd.service` | `/etc/kubernetes/manifests/etcd.yaml` |
| `/etc/systemd/system/kube-apiserver.service` | `/etc/kubernetes/manifests/kube-apiserver.yaml` |
| `/etc/systemd/system/kube-controller-manager.service` | `/etc/kubernetes/manifests/kube-controller-manager.yaml` |
| `/etc/systemd/system/kube-scheduler.service` | `/etc/kubernetes/manifests/kube-scheduler.yaml` |
| `/etc/etcd/*.pem` | `/etc/kubernetes/pki/etcd/*.crt`, `*.key` |
| `/var/lib/etcd/` | `/var/lib/etcd/` (same) |
| `/var/lib/kubernetes/*.pem` | `/etc/kubernetes/pki/*.crt`, `*.key` |
| `/var/lib/kubernetes/kube-controller-manager.kubeconfig` | `/etc/kubernetes/controller-manager.conf` |
| `/var/lib/kubernetes/kube-scheduler.kubeconfig` | `/etc/kubernetes/scheduler.conf` |
| `/var/lib/kubelet/kubelet-config.yaml` | `/var/lib/kubelet/config.yaml` |
| `/var/lib/kubelet/kubeconfig` | `/etc/kubernetes/kubelet.conf` |
| `/var/lib/kubelet/controlplane-1.pem`, `controlplane-1-key.pem` | `/var/lib/kubelet/pki/kubelet-client-current.pem` (auto-rotated) |
| `~/auth/admin.kubeconfig` | `/etc/kubernetes/admin.conf` |

Static pods are managed by kubelet, not systemd. Editing a manifest in `/etc/kubernetes/manifests/` causes kubelet to recreate the corresponding pod within seconds. There is no `systemctl restart` for static pod components; kubelet drives their lifecycle automatically.

---

## General Diagnostic Workflow

### Step 1: Cluster-Level Triage

```bash
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep -Ev '\bRunning\b|\bCompleted\b'
kubectl get events --sort-by='.lastTimestamp' | tail -30
```

If the node is `Ready` and no pods are misbehaving, the cluster is healthy.

### Step 2: Node-Level Triage

```bash
sudo systemctl status kubelet --no-pager
sudo systemctl status containerd --no-pager
sudo journalctl -u kubelet -n 50 --no-pager
sudo crictl pods | head -20
```

### Step 3: Identify the Failure Category

- **Node `NotReady`:** kubelet down, containerd down, CNI broken, disk full
- **Pods `Pending` forever:** scheduler issue, taint or selector mismatch, resource shortage
- **Pods `CrashLoopBackOff`:** application problem, image pull failure, config volume missing
- **Pods `Running` but Service IPs unreachable:** kube-proxy broken, CNI broken, `NetworkPolicy` denying
- **`kubectl` itself fails:** kubeconfig wrong, apiserver down, certificate expired

---

## kubeadm init Failures

### Preflight Failures

```bash
# Re-run preflight on its own to see all errors at once
sudo kubeadm init phase preflight --config ~/kubeadm-init.yaml
```

| Error | Fix |
|---|---|
| `swap is enabled` | `sudo swapoff -a && sudo sed -i '/swap/d' /etc/fstab` |
| `container runtime is not running` | `sudo systemctl start containerd && sudo crictl info` |
| `port 6443 is in use` | Previous `kubeadm init` left static pods. `sudo kubeadm reset --force` |
| `port 10250 is in use` | kubelet is already running. `sudo systemctl stop kubelet`, then re-run init |
| `cri-tools not installed` | `crictl` is missing. See `01-node-prerequisites.md` Step 7 |

### kubelet-start Hangs Indefinitely

The init output sticks at:

```
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods
```

This means kubelet started but cannot bring up the static pods. Check:

```bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 100 | grep -i error
sudo crictl pods
sudo crictl ps -a
```

The most common cause is cgroup driver mismatch. The driver must be `systemd` in three places:

```bash
grep -n SystemdCgroup /etc/containerd/config.toml      # 1. containerd
grep cgroupDriver ~/kubeadm-init.yaml                  # 2. kubeadm config
grep cgroupDriver /var/lib/kubelet/config.yaml         # 3. kubelet runtime view
```

All three should say `systemd`. Fix any that disagree, restart containerd and kubelet, and re-run `kubeadm init`.

### etcd Phase Fails

Old etcd data still in place from a previous init.

```bash
sudo kubeadm reset --force
sudo rm -rf /var/lib/etcd
sudo kubeadm init --config ~/kubeadm-init.yaml
```

### Recovery: Full Reset

When in doubt, reset and start over:

```bash
sudo kubeadm reset --force
sudo rm -rf /etc/cni/net.d /var/lib/etcd
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sudo systemctl restart containerd
sudo systemctl restart kubelet  # will fail until init runs, that is fine

sudo kubeadm init --config ~/kubeadm-init.yaml
```

---

## Editing Static Pod Manifests

kubelet watches `/etc/kubernetes/manifests/`. Any edit to a YAML file there causes kubelet to recreate the pod within seconds.

```bash
# Backup before editing
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak

# Edit
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml

# Watch the pod recreate
sudo crictl ps | grep apiserver
sleep 10
sudo crictl ps | grep apiserver
# Pod ID should have changed
```

If the pod will not recreate, the manifest YAML is broken. kubelet logs (`journalctl -u kubelet -n 30`) will show the parse error.

### Recovering from a Bad Manifest Edit

```bash
# Restore from backup
sudo cp /tmp/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml
# kubelet will pick it up within 20 seconds
```

If you do not have a backup, regenerate from the kubeadm config:

```bash
sudo kubeadm init phase control-plane apiserver --config ~/kubeadm-init.yaml
```

This regenerates only the apiserver manifest without touching anything else. Same pattern for `controller-manager` and `scheduler` phases.

### etcd Backup and Restore

A guaranteed exam topic. Practice it on this cluster.

Backup:

```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

sudo ETCDCTL_API=3 etcdctl --write-out=table snapshot status /tmp/etcd-backup.db
```

Restore:

```bash
# Stop apiserver and etcd by moving their manifests
sudo mkdir -p /tmp/manifest-backup
sudo mv /etc/kubernetes/manifests/{kube-apiserver,etcd}.yaml /tmp/manifest-backup/

# Wait for the pods to actually stop
while sudo crictl ps | grep -E 'kube-apiserver|etcd'; do sleep 1; done

# Move old data aside, restore from snapshot
sudo mv /var/lib/etcd /var/lib/etcd.old
sudo ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db --data-dir /var/lib/etcd

# Put the manifests back
sudo mv /tmp/manifest-backup/*.yaml /etc/kubernetes/manifests/

# Wait for the cluster to come back
sleep 30
kubectl get nodes
```

---

## Calico CNI

### calico-node Pod Stuck

```bash
kubectl -n calico-system get pods -l k8s-app=calico-node -o wide
kubectl -n calico-system describe pod -l k8s-app=calico-node | grep -A 10 Events
kubectl -n calico-system logs -l k8s-app=calico-node --tail=50
```

| Symptom | Cause | Fix |
|---|---|---|
| `Init:0/3` forever | Missing kernel module (`xt_set`, `ip_set`) | `sudo modprobe ip_set xt_set` |
| `Running` but node still `NotReady` | CNI config not written | Check `/etc/cni/net.d/10-calico.conflist` exists |

### Pod CIDR Mismatch

If the kubeadm `podSubnet` and the Calico IPPool `cidr` do not match, pods get IPs from one CIDR while routes are written for the other.

```bash
# What kubeadm thinks
kubectl -n kube-system get configmap kubeadm-config -o yaml | grep podSubnet

# What Calico thinks
kubectl get ippool default-ipv4-ippool -o jsonpath='{.spec.cidr}'; echo

# What pods actually get
kubectl get pods -A -o jsonpath='{range .items[*]}{.status.podIP}{"\n"}{end}' | sort -u | head
```

All three must reference `10.244.0.0/16`.

---

## CoreDNS

### Symptoms of DNS Failure

```bash
kubectl run dns-test --image=busybox:1.36 --restart=Never -- sleep 600
kubectl wait --for=condition=Ready pod/dns-test --timeout=60s

kubectl exec dns-test -- nslookup kubernetes.default.svc.cluster.local
kubectl exec dns-test -- nslookup google.com

kubectl delete pod dns-test
```

If both fail, CoreDNS or kube-proxy is broken. If only the second fails, CoreDNS forward to upstream resolvers is broken.

### CoreDNS Diagnostics

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50

kubectl -n kube-system get configmap coredns -o yaml
```

The most common config issue is the `forward . /etc/resolv.conf` line referencing a stale upstream:

```bash
kubectl -n kube-system rollout restart deployment coredns
```

---

## kube-proxy

If Service IPs do not respond but pod IPs do, kube-proxy is broken.

```bash
kubectl -n kube-system get pods -l k8s-app=kube-proxy
kubectl -n kube-system logs -l k8s-app=kube-proxy --tail=50

# iptables view
sudo iptables-save | grep KUBE | head -20
```

Common kube-proxy issue is wrong `clusterCIDR`:

```bash
kubectl -n kube-system get configmap kube-proxy -o yaml | grep clusterCIDR
# Should be 10.244.0.0/16
```

To fix:

```bash
kubectl -n kube-system edit configmap kube-proxy
# Change clusterCIDR, save, then:
kubectl -n kube-system delete pods -l k8s-app=kube-proxy
```

---

## metrics-server

`kubectl top nodes` says "metrics not available" forever:

```bash
# Confirm the lab-only insecure flag is present
kubectl -n kube-system get deployment metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}'
```

If `--kubelet-insecure-tls` is missing, add it (see `04-cluster-services.md`).

---

## Cluster Upgrade

Single-node version of the kubeadm upgrade workflow. Practice this here before the multi-node version.

### Plan

```bash
sudo kubeadm upgrade plan
```

### Apply

```bash
# Update apt source for the new minor version (example: 1.36)
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update

# Unhold and install kubeadm at target version
sudo apt-mark unhold kubeadm
sudo apt install -y kubeadm=1.36.0-1.1
sudo apt-mark hold kubeadm

# Apply
sudo kubeadm upgrade apply v1.36.0

# Drain
kubectl drain controlplane-1 --ignore-daemonsets --delete-emptydir-data

# Upgrade kubelet and kubectl
sudo apt-mark unhold kubelet kubectl
sudo apt install -y kubelet=1.36.0-1.1 kubectl=1.36.0-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Uncordon
kubectl uncordon controlplane-1
```

### Verify

```bash
kubectl get nodes -o wide
# Node should show v1.36.0
```

---

## Quick Diagnostic Reference

```bash
# 1. Cluster overview
kubectl get nodes -o wide
kubectl get pods -A | grep -Ev 'Running|Completed'

# 2. Node-level
sudo systemctl status kubelet containerd --no-pager | head -20
sudo journalctl -u kubelet -n 30 --no-pager

# 3. Static pods
sudo crictl ps | grep -E "apiserver|etcd|controller|scheduler"

# 4. CNI
kubectl -n calico-system get pods

# 5. DNS
kubectl -n kube-system get pods -l k8s-app=kube-dns

# 6. kube-proxy
kubectl -n kube-system get pods -l k8s-app=kube-proxy
```
