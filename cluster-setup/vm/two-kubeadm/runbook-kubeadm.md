# Troubleshooting Runbook: kubeadm Two-Node Cluster

This runbook covers diagnostic and repair procedures specific to a `kubeadm`-installed two-node cluster: `kubeadm init` failures, `kubeadm join` failures, kubelet on either node, static pod control plane edits, certificate problems, CoreDNS, kube-proxy, Calico CNI, and cluster upgrade.

For host-side QEMU and bridge issues (VMs not starting, bridge missing, NAT not working), see `runbook-qemu-vm.md`. For containerd, kubelet, and kube-proxy fundamentals, the single-node `runbook-worker-components.md` still applies, with the file path substitutions shown in the static pod section below. For etcd, apiserver, controller-manager, and scheduler diagnostics, the single-node `runbook-control-plane.md` still applies, again with path substitutions.

---

## General Diagnostic Workflow

### Step 1: Cluster-Level Triage

```bash
# From host or controlplane-1
kubectl get nodes -o wide
kubectl get pods -A -o wide | grep -Ev '\bRunning\b|\bCompleted\b'
kubectl get events --sort-by='.lastTimestamp' | tail -30
```

If both nodes are `Ready` and no pods are misbehaving, the cluster is healthy.

### Step 2: Per-Node Triage

```bash
# On the node in question
sudo systemctl status kubelet --no-pager
sudo systemctl status containerd --no-pager
sudo journalctl -u kubelet -n 50 --no-pager
sudo crictl pods | head -20
```

### Step 3: Identify the Failure Category

Most multi-node failures fall into one of these buckets:

- **Node `NotReady`:** kubelet down, containerd down, CNI broken, disk full
- **Pods `Pending` forever:** scheduler issue, node taint or selector mismatch, no Ready node, resource shortage
- **Pods `CrashLoopBackOff`:** image pull, container start command, config volume missing
- **Pods `Running` but not reachable:** Service/Endpoint mismatch, kube-proxy broken, `NetworkPolicy` denying, CNI broken
- **`kubectl` itself fails:** kubeconfig wrong, apiserver down, certificate expired, network path broken

---

## kubeadm init Failures

### Preflight Failures

```bash
# Re-run preflight on its own to see all errors at once
sudo kubeadm init phase preflight --config ~/kubeadm-init.yaml
```

The most common preflight failures:

| Error | Fix |
|---|---|
| `swap is enabled` | `sudo swapoff -a && sudo sed -i '/swap/d' /etc/fstab` |
| `container runtime is not running` | `sudo systemctl start containerd && sudo crictl info` |
| `port 6443 is in use` | Previous `kubeadm init` left static pods. `sudo kubeadm reset --force` |
| `port 10250 is in use` | kubelet is already running with leftover config. `sudo systemctl stop kubelet`, then re-run init |
| `cri-tools not installed` | `crictl` is missing. See `03-node-prerequisites.md` Step 7 |

### kubelet-start Hangs Indefinitely

The init output sticks at:

```
[wait-control-plane] Waiting for the kubelet to boot up the control plane as static Pods
```

This means kubelet started but cannot bring up the static pods. Check:

```bash
sudo systemctl status kubelet
sudo journalctl -u kubelet -n 100 | grep -i error

# Container runtime view
sudo crictl pods
sudo crictl ps -a
```

The most common cause is cgroup driver mismatch. The driver must be `systemd` in three places:

```bash
# 1. containerd config
grep -n SystemdCgroup /etc/containerd/config.toml

# 2. KubeletConfiguration in the kubeadm config
grep cgroupDriver ~/kubeadm-init.yaml

# 3. kubelet's runtime view (after init writes the file)
grep cgroupDriver /var/lib/kubelet/config.yaml
```

All three should say `systemd`. Fix any that disagree, restart containerd and kubelet, and re-run `kubeadm init`.

### etcd Phase Fails

```
[etcd] Creating static Pod manifest for local etcd
... etcd healthcheck failed
```

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
sudo rm -rf /etc/cni/net.d
sudo rm -rf /var/lib/etcd
sudo iptables -F && sudo iptables -t nat -F && sudo iptables -t mangle -F && sudo iptables -X
sudo systemctl restart containerd
sudo systemctl restart kubelet  # will fail until init runs, that is fine

sudo kubeadm init --config ~/kubeadm-init.yaml
```

For multi-node resets, run `kubeadm reset` on the worker first, then on the control plane.

---

## kubeadm join Failures

### Token Expired

```
[discovery] Failed to request cluster-info, will try again: ... unauthorized
```

Tokens default to 24-hour TTL. Generate a fresh one on `controlplane-1`:

```bash
ssh controlplane-1
kubeadm token create --print-join-command
```

Use the new command on `nodes-1`.

### CA Cert Hash Wrong

```
[discovery] Failed to validate API server's identity
```

The hash in the join command does not match the cluster's CA. Get the current hash on `controlplane-1`:

```bash
openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed 's/^.* //'
```

Use this hash in the join command's `--discovery-token-ca-cert-hash sha256:...`.

### Cert SAN Missing

```
x509: certificate is valid for 192.168.100.10, but not for ...
```

The IP or hostname being joined to was not in the kubeadm config's `certSANs`. Two options:

1. Use an IP or name that is in the SANs (`192.168.100.10` always is).
2. Renew the apiserver cert with new SANs:

```bash
# On controlplane-1
sudo kubeadm certs renew apiserver
# kubelet will restart the apiserver static pod automatically
```

### Worker Joins but Stays NotReady

This is normal for 30 to 60 seconds while the Calico DaemonSet schedules a `calico-node` pod onto the new node. If still `NotReady` after a minute:

```bash
# From controlplane-1
kubectl describe node nodes-1 | grep -A 5 Conditions
kubectl -n calico-system get pods -o wide -l k8s-app=calico-node
kubectl -n calico-system describe pod -l k8s-app=calico-node | grep -A 5 Events
```

If `calico-node` on `nodes-1` is stuck in `Init:0/3`, see the Calico section below.

---

## Static Pod Control Plane

### Path Mapping from Single-Node

The single-node `runbook-control-plane.md` covers each component in detail. The diagnostics still apply; only the file paths change with `kubeadm`:

| Component | Single-node path | kubeadm path |
|-----------|------------------|--------------|
| etcd manifest | `/etc/systemd/system/etcd.service` | `/etc/kubernetes/manifests/etcd.yaml` |
| etcd certs | `/etc/etcd/*.pem` | `/etc/kubernetes/pki/etcd/*.crt`, `*.key` |
| etcd data | `/var/lib/etcd/` | `/var/lib/etcd/` (same) |
| apiserver manifest | `/etc/systemd/system/kube-apiserver.service` | `/etc/kubernetes/manifests/kube-apiserver.yaml` |
| apiserver certs | `/var/lib/kubernetes/*.pem` | `/etc/kubernetes/pki/*.crt`, `*.key` |
| controller-manager manifest | `/etc/systemd/system/kube-controller-manager.service` | `/etc/kubernetes/manifests/kube-controller-manager.yaml` |
| controller-manager kubeconfig | `/var/lib/kubernetes/kube-controller-manager.kubeconfig` | `/etc/kubernetes/controller-manager.conf` |
| scheduler manifest | `/etc/systemd/system/kube-scheduler.service` | `/etc/kubernetes/manifests/kube-scheduler.yaml` |
| scheduler kubeconfig | `/var/lib/kubernetes/kube-scheduler.kubeconfig` | `/etc/kubernetes/scheduler.conf` |
| admin kubeconfig | `~/auth/admin.kubeconfig` | `/etc/kubernetes/admin.conf` |

### Editing a Static Pod Manifest

kubelet watches `/etc/kubernetes/manifests/`. Any edit to a YAML file there causes kubelet to recreate the pod within seconds.

```bash
# Example: change apiserver authorization mode for testing
sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Save and exit. Watch the pod recreate:
sudo crictl ps | grep apiserver
sleep 10
sudo crictl ps | grep apiserver
# Pod ID should have changed
```

If the pod will not recreate, the manifest YAML is broken. kubelet logs (`journalctl -u kubelet -n 30`) will show the parse error.

### Recovering from a Bad Manifest Edit

If you saved a manifest that kubelet rejects:

```bash
# Restore from backup
sudo cp /tmp/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml
# kubelet will pick it up within 20 seconds
```

If you do not have a backup, regenerate from the kubeadm config:

```bash
sudo kubeadm init phase control-plane apiserver --config ~/kubeadm-init.yaml
```

This regenerates only the apiserver manifest without touching anything else.

### etcd Backup and Restore

A guaranteed exam topic. Practice it on this cluster.

Backup:

```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify
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

## kubelet Issues

The single-node `runbook-worker-components.md` covers kubelet in detail. The differences with `kubeadm` are file paths:

| Single-node path | kubeadm path |
|---|---|
| `/var/lib/kubelet/kubelet-config.yaml` | `/var/lib/kubelet/config.yaml` |
| `/var/lib/kubelet/kubeconfig` | `/etc/kubernetes/kubelet.conf` |
| `/var/lib/kubelet/controlplane-1.pem`, `controlplane-1-key.pem` | `/var/lib/kubelet/pki/kubelet-client-current.pem` (auto-rotated) |

`kubeadm` also writes a systemd drop-in at `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf` that injects extra args from `/var/lib/kubelet/kubeadm-flags.env`. If kubelet starts with the wrong arguments, that drop-in is the place to look.

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

### CoreDNS Pod Diagnostics

```bash
kubectl -n kube-system get pods -l k8s-app=kube-dns
kubectl -n kube-system logs -l k8s-app=kube-dns --tail=50

# Config
kubectl -n kube-system get configmap coredns -o yaml
```

The most common config issue is the `forward . /etc/resolv.conf` line referencing a stale upstream. The host's `/etc/resolv.conf` becomes the cluster's upstream by default; if it changed, restart CoreDNS:

```bash
kubectl -n kube-system rollout restart deployment coredns
```

---

## kube-proxy

If Service IPs do not respond but pod IPs do, kube-proxy is broken on the affected node.

```bash
kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide
kubectl -n kube-system logs -l k8s-app=kube-proxy --tail=50

# Per-node iptables view
ssh controlplane-1 'sudo iptables-save | grep KUBE | head -20'
ssh nodes-1 'sudo iptables-save | grep KUBE | head -20'
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

## Calico CNI

### calico-node Pod Stuck

```bash
kubectl -n calico-system get pods -l k8s-app=calico-node -o wide
kubectl -n calico-system describe pod -l k8s-app=calico-node | grep -A 10 Events
kubectl -n calico-system logs -l k8s-app=calico-node --tail=50
```

| Symptom | Cause | Fix |
|---|---|---|
| `Init:0/3` forever | Missing kernel module (`xt_set`, `ip_set`) | `sudo modprobe ip_set xt_set` on the node |
| `CrashLoopBackOff` with BIRD message | BGP peering failure (only matters in BGP mode) | Check `BGPConfiguration` resource |
| `Running` but node still `NotReady` | CNI config not written | Check `/etc/cni/net.d/10-calico.conflist` exists |

### Cross-Node Pod Traffic Fails

Pods on the same node can talk; pods on different nodes cannot. The Calico VXLAN tunnel is broken.

```bash
# On both nodes
ip -d link show vxlan.calico
# Should show vxlan with id and a remote group

# Check Calico routes
sudo ip route | grep 10.244

# Verify the IPPool encapsulation
kubectl get ippool default-ipv4-ippool -o jsonpath='{.spec.vxlanMode}'; echo
```

If the vxlan interface is missing or routes are not present, restart the daemonset:

```bash
kubectl -n calico-system rollout restart daemonset calico-node
```

### Pod CIDR Mismatch

If the kubeadm `podSubnet` and the Calico IPPool `cidr` do not match, pods get IPs from one CIDR while routes are written for the other, and nothing works.

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

## metrics-server

`kubectl top nodes` says "metrics not available yet" forever:

```bash
# Confirm the lab-only insecure flag is present
kubectl -n kube-system get deployment metrics-server -o jsonpath='{.spec.template.spec.containers[0].args}'
```

If `--kubelet-insecure-tls` is missing, add it (see document 07).

---

## Cluster Upgrade

A guaranteed exam topic. The two-node setup gives you a clean way to practice both control plane and worker upgrades.

### Plan

```bash
# On controlplane-1
sudo kubeadm upgrade plan
```

Output lists the available upgrade target.

### Control Plane Upgrade

```bash
# Update apt source for the new minor version (example: 1.36)
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.36/deb/ /' \
  | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update

# Unhold and install kubeadm at the target version
sudo apt-mark unhold kubeadm
sudo apt install -y kubeadm=1.36.0-1.1
sudo apt-mark hold kubeadm

# Apply the upgrade
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

### Worker Upgrade

Same pattern on `nodes-1`, except `sudo kubeadm upgrade node` instead of `apply`:

```bash
ssh nodes-1

# Update apt source the same way as controlplane-1
sudo apt update
sudo apt-mark unhold kubeadm
sudo apt install -y kubeadm=1.36.0-1.1
sudo apt-mark hold kubeadm

sudo kubeadm upgrade node

# Drain from the control plane
ssh controlplane-1 'kubectl drain nodes-1 --ignore-daemonsets --delete-emptydir-data'

# Upgrade kubelet and kubectl on nodes-1
sudo apt-mark unhold kubelet kubectl
sudo apt install -y kubelet=1.36.0-1.1 kubectl=1.36.0-1.1
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet

# Uncordon
ssh controlplane-1 'kubectl uncordon nodes-1'
```

### Verify

```bash
kubectl get nodes -o wide
# All nodes should show the new version
```

---

## Quick Diagnostic Reference

```bash
# 1. Cluster overview
kubectl get nodes -o wide
kubectl get pods -A | grep -Ev 'Running|Completed'

# 2. Node-level
ssh <node> 'sudo systemctl status kubelet containerd --no-pager | head -20'
ssh <node> 'sudo journalctl -u kubelet -n 30 --no-pager'

# 3. Static pods (control plane only)
ssh controlplane-1 'sudo crictl ps | grep -E "apiserver|etcd|controller|scheduler"'

# 4. CNI
kubectl -n calico-system get pods -o wide

# 5. DNS
kubectl -n kube-system get pods -l k8s-app=kube-dns

# 6. kube-proxy
kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide

# 7. Cross-node
kubectl run xtest --image=nginx:1.27 --overrides='{"spec":{"nodeName":"nodes-1"}}' --restart=Never
kubectl get pod xtest -o wide
kubectl exec xtest -- curl -s --max-time 3 -o /dev/null -w "%{http_code}\n" http://kubernetes.default.svc.cluster.local
kubectl delete pod xtest
```
