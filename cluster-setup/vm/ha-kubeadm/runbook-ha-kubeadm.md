# Troubleshooting Runbook: HA kubeadm Cluster

This runbook covers HA-specific diagnostic procedures. For the full diagnostic workflow
for `kubeadm init` failures, static pod manifests, Calico, CoreDNS, and kube-proxy,
see [`two-kubeadm/runbook-kubeadm.md`](../two-kubeadm/runbook-kubeadm.md) -- the
path mappings and diagnostic commands apply here with the additional nodes.

---

## Quick Diagnostic Reference

```bash
# All five nodes
kubectl get nodes -o wide

# Non-running pods
kubectl get pods -A | grep -Ev 'Running|Completed'

# Per-node health (run from host)
for node in controlplane-1 controlplane-2 nodes-1 nodes-2 nodes-3; do
  echo "=== $node ==="
  ssh "$node" 'sudo systemctl status kubelet containerd --no-pager | grep -E "Active:|Loaded:"'
done

# etcd cluster health (from controlplane-1)
ssh controlplane-1 '
  sudo ETCDCTL_API=3 etcdctl endpoint health \
    --cluster \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key
'

# etcd member list
ssh controlplane-1 '
  sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key
'

# HAProxy stats
curl -su admin:admin http://192.168.100.1:9000/stats | grep -E "controlplane|Status"
```

---

## HAProxy Issues

### VIP Not Responding

```bash
# HAProxy is running
sudo systemctl status haproxy --no-pager

# HAProxy is listening on the VIP
sudo ss -tlnp | grep 6443

# Config is valid
sudo haproxy -c -f /etc/haproxy/haproxy.cfg

# Restart if needed
sudo systemctl restart haproxy
```

### HAProxy Shows Both Backends DOWN

Before `kubeadm init` runs, both backends are down -- this is expected. After init,
if both stay down:

```bash
# Direct check against each control plane
curl -sk https://192.168.100.20:6443/healthz
curl -sk https://192.168.100.21:6443/healthz

# If one responds, check HAProxy config for IP typo
grep backend /etc/haproxy/haproxy.cfg
```

### VIP Works but kubectl Uses Wrong Server

```bash
grep server ~/cka-lab/ha-kubeadm/admin.conf
# Must be https://192.168.100.100:6443 (the VIP)
# If it shows a node IP directly, regenerate from controlplane-1:
scp controlplane-1:/etc/kubernetes/admin.conf ~/cka-lab/ha-kubeadm/admin.conf
```

---

## etcd Issues

### etcd Member Showing as Unstarted

```bash
ssh controlplane-1 '
  sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key \
    --write-out=table
'
```

If `controlplane-2`'s member shows `unstarted`, the etcd pod on `controlplane-2` is
not running:

```bash
ssh controlplane-2 'sudo crictl ps | grep etcd'
ssh controlplane-2 'sudo crictl logs $(sudo crictl ps -q --name etcd 2>/dev/null) 2>/dev/null | tail -20'
```

### etcd Cluster Has Only One Member After Join Failure

If `kubeadm join --control-plane` failed partway through, clean up and retry:

```bash
# On controlplane-2
ssh controlplane-2 'sudo kubeadm reset --force'
ssh controlplane-2 'sudo rm -rf /var/lib/etcd'

# On controlplane-1 -- regenerate the certificate key (old one may have expired)
ssh controlplane-1 'sudo kubeadm init phase upload-certs --upload-certs'

# Re-run the join with the new certificate key
```

### etcd Read-Only (Cluster Operational but Writes Fail)

With a two-member etcd cluster, one member being down leaves the cluster without a
quorum majority. Kubernetes continues to serve read requests but cannot process writes.

Symptoms:
- `kubectl get pods` works
- `kubectl create deployment` hangs or fails with timeout
- etcd logs show `raft: proposed blocked until quorum is restored`

Resolution: bring the missing control plane back up.

```bash
# Start the stopped control plane (from host)
~/cka-lab/ha-kubeadm/controlplane-1/start-controlplane-1.sh
# OR
~/cka-lab/ha-kubeadm/controlplane-2/start-controlplane-2.sh

# Wait for it to rejoin etcd (30-60 seconds)
ssh controlplane-1 '
  sudo ETCDCTL_API=3 etcdctl member list \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key
'
```

---

## Second Control Plane Issues

### controlplane-2 Stays NotReady After Join

```bash
kubectl describe node controlplane-2 | grep -A 5 Conditions
ssh controlplane-2 'sudo journalctl -u kubelet -n 50 --no-pager'
```

If Calico has not scheduled on `controlplane-2`:

```bash
kubectl -n calico-system get pods -o wide -l k8s-app=calico-node
kubectl -n calico-system describe pod -l k8s-app=calico-node -l kubernetes.io/hostname=controlplane-2
```

### API Server on controlplane-2 Not Accessible Directly

```bash
curl -sk https://192.168.100.21:6443/healthz
ssh controlplane-2 'sudo crictl ps | grep apiserver'
ssh controlplane-2 'sudo crictl logs $(sudo crictl ps -q --name kube-apiserver 2>/dev/null) 2>/dev/null | tail -30'
```

---

## Control Plane Upgrade (HA)

The HA upgrade sequence upgrades the first control plane, then the second, then workers.
Only one node is drained at a time.

### Step 1: Upgrade controlplane-1 (first control plane)

```bash
# Update kubeadm
ssh controlplane-1 '
  sudo apt-mark unhold kubeadm
  sudo apt install -y kubeadm=1.36.0-1.1
  sudo apt-mark hold kubeadm
  sudo kubeadm upgrade apply v1.36.0
'

kubectl drain controlplane-1 --ignore-daemonsets --delete-emptydir-data

ssh controlplane-1 '
  sudo apt-mark unhold kubelet kubectl
  sudo apt install -y kubelet=1.36.0-1.1 kubectl=1.36.0-1.1
  sudo apt-mark hold kubelet kubectl
  sudo systemctl daemon-reload && sudo systemctl restart kubelet
'
kubectl uncordon controlplane-1
```

### Step 2: Upgrade controlplane-2 (second control plane)

```bash
ssh controlplane-2 '
  sudo apt-mark unhold kubeadm
  sudo apt install -y kubeadm=1.36.0-1.1
  sudo apt-mark hold kubeadm
  sudo kubeadm upgrade node
'

kubectl drain controlplane-2 --ignore-daemonsets --delete-emptydir-data

ssh controlplane-2 '
  sudo apt-mark unhold kubelet kubectl
  sudo apt install -y kubelet=1.36.0-1.1 kubectl=1.36.0-1.1
  sudo apt-mark hold kubelet kubectl
  sudo systemctl daemon-reload && sudo systemctl restart kubelet
'
kubectl uncordon controlplane-2
```

### Step 3: Upgrade workers (one at a time)

```bash
for node in nodes-1 nodes-2 nodes-3; do
  kubectl drain "$node" --ignore-daemonsets --delete-emptydir-data
  ssh "$node" '
    sudo apt-mark unhold kubeadm kubelet kubectl
    sudo apt install -y kubeadm=1.36.0-1.1 kubelet=1.36.0-1.1 kubectl=1.36.0-1.1
    sudo apt-mark hold kubeadm kubelet kubectl
    sudo kubeadm upgrade node
    sudo systemctl daemon-reload && sudo systemctl restart kubelet
  '
  kubectl uncordon "$node"
  sleep 10
done

kubectl get nodes -o wide
```

---

## etcd Backup and Restore (HA)

Backup from either control plane:

```bash
ssh controlplane-1 '
  sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
    --endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key
  sudo ETCDCTL_API=3 etcdctl --write-out=table snapshot status /tmp/etcd-backup.db
'
```

Restore in a two-member cluster requires stopping both API servers and both etcd
members, then restoring from snapshot on each node separately before restarting:

```bash
# Stop API servers on both control planes (move their manifests out)
for cp in controlplane-1 controlplane-2; do
  ssh "$cp" '
    sudo mkdir -p /tmp/manifest-backup
    sudo mv /etc/kubernetes/manifests/{kube-apiserver,etcd}.yaml /tmp/manifest-backup/
    while sudo crictl ps | grep -E "apiserver|etcd"; do sleep 1; done
  '
done

# Restore on both control planes with different --initial-cluster args
ssh controlplane-1 '
  sudo mv /var/lib/etcd /var/lib/etcd.old
  sudo ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
    --data-dir /var/lib/etcd \
    --name controlplane-1 \
    --initial-cluster "controlplane-1=https://192.168.100.20:2380,controlplane-2=https://192.168.100.21:2380" \
    --initial-cluster-token etcd-cluster-1 \
    --initial-advertise-peer-urls https://192.168.100.20:2380
  sudo chown -R root:root /var/lib/etcd
'

ssh controlplane-2 '
  sudo mv /var/lib/etcd /var/lib/etcd.old
  # Copy the backup from controlplane-1
  scp controlplane-1:/tmp/etcd-backup.db /tmp/etcd-backup.db
  sudo ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db \
    --data-dir /var/lib/etcd \
    --name controlplane-2 \
    --initial-cluster "controlplane-1=https://192.168.100.20:2380,controlplane-2=https://192.168.100.21:2380" \
    --initial-cluster-token etcd-cluster-1 \
    --initial-advertise-peer-urls https://192.168.100.21:2380
  sudo chown -R root:root /var/lib/etcd
'

# Restore manifests on both control planes
for cp in controlplane-1 controlplane-2; do
  ssh "$cp" 'sudo mv /tmp/manifest-backup/*.yaml /etc/kubernetes/manifests/'
done

sleep 30
kubectl get nodes
```
