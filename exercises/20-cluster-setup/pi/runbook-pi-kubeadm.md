# Runbook: Raspberry Pi kubeadm Cluster

Quick-reference for day-to-day cluster operations on the Pi 5 cluster.

---

## SSH Access

```bash
ssh rpi-node-01   # 192.168.200.10
ssh rpi-node-02   # 192.168.200.11
ssh rpi-node-03   # 192.168.200.12
```

## kubectl from Host

```bash
export KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf
kubectl get nodes
```

---

## Cluster Health

```bash
# Node status
kubectl get nodes -o wide

# All pods across namespaces
kubectl get pods -A

# API server health
curl -k https://192.168.200.10:6443/healthz

# etcd health (on rpi-node-01)
ssh rpi-node-01 sudo etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
```

---

## Drain and Uncordon a Worker

```bash
# Drain (evicts pods, marks unschedulable)
kubectl drain rpi-node-02 --ignore-daemonsets --delete-emptydir-data

# Do maintenance on rpi-node-02, then restore
kubectl uncordon rpi-node-02
```

---

## etcd Backup and Restore

**Backup** (run on `rpi-node-01`):

```bash
ssh rpi-node-01 sudo etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  snapshot save /tmp/etcd-snapshot-$(date +%Y%m%d-%H%M%S).db

# Copy snapshot to host
scp rpi-node-01:/tmp/etcd-snapshot-*.db ~/cka-lab/pi-kubeadm/
```

**Restore** (run on `rpi-node-01` -- restores to a new data directory, then updates the etcd static pod):

```bash
# Stop etcd by moving the static pod manifest out of the watched directory
ssh rpi-node-01 sudo mv /etc/kubernetes/manifests/etcd.yaml /tmp/etcd.yaml

# Restore
ssh rpi-node-01 sudo etcdctl snapshot restore /tmp/etcd-snapshot-<timestamp>.db \
  --data-dir=/var/lib/etcd-restore

# Update etcd to use the restored data dir
ssh rpi-node-01 sudo sed -i 's|/var/lib/etcd|/var/lib/etcd-restore|g' /tmp/etcd.yaml

# Put the manifest back (restarts etcd)
ssh rpi-node-01 sudo mv /tmp/etcd.yaml /etc/kubernetes/manifests/etcd.yaml
```

---

## Certificate Renewal

```bash
# Check certificate expiry
ssh rpi-node-01 sudo kubeadm certs check-expiration

# Renew all certificates
ssh rpi-node-01 sudo kubeadm certs renew all

# Restart control plane static pods to pick up renewed certs
ssh rpi-node-01 sudo crictl pods | grep -E 'apiserver|controller|scheduler|etcd'
# Then kill each pod (kubelet restarts them automatically)
```

---

## Add a Join Token

Join tokens expire after 24 hours. Generate a new one when joining a new or reset node:

```bash
ssh rpi-node-01 kubeadm token create --print-join-command
```

---

## Reset a Node

To reset a worker and rejoin it (useful for practicing the join workflow):

```bash
# On the host: drain first
kubectl drain rpi-node-02 --ignore-daemonsets --delete-emptydir-data
kubectl delete node rpi-node-02

# On rpi-node-02: reset kubeadm
ssh rpi-node-02 sudo kubeadm reset -f
ssh rpi-node-02 sudo ip link delete flannel.1 2>/dev/null || true
ssh rpi-node-02 sudo ip link delete tunl0 2>/dev/null || true
ssh rpi-node-02 sudo rm -rf /etc/cni/net.d

# Rejoin (generate fresh token first)
JOIN_CMD=$(ssh rpi-node-01 kubeadm token create --print-join-command)
ssh rpi-node-02 sudo $JOIN_CMD
```

---

## Upgrade Kubernetes Version

On `rpi-node-01`:

```bash
# Upgrade kubeadm
sudo apt-mark unhold kubeadm
sudo apt install -y kubeadm=1.36.0-*   # substitute target version
sudo apt-mark hold kubeadm

# Plan upgrade
sudo kubeadm upgrade plan

# Apply upgrade
sudo kubeadm upgrade apply v1.36.0

# Upgrade kubelet and kubectl on rpi-node-01
sudo apt-mark unhold kubelet kubectl
sudo apt install -y kubelet=1.36.0-* kubectl=1.36.0-*
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

On each worker (`rpi-node-02`, `rpi-node-03`) after the control plane:

```bash
sudo kubeadm upgrade node
sudo apt-mark unhold kubelet kubectl
sudo apt install -y kubelet=1.36.0-* kubectl=1.36.0-*
sudo apt-mark hold kubelet kubectl
sudo systemctl daemon-reload
sudo systemctl restart kubelet
```

---

## Useful One-Liners

```bash
# Show pod distribution across nodes
kubectl get pods -A -o wide | awk '{print $8}' | sort | uniq -c

# Check Calico node status
kubectl get pods -n calico-system -o wide

# Test cluster DNS
kubectl run dns --image=busybox:1.36 --restart=Never --rm -it -- nslookup kubernetes

# Watch node conditions
kubectl get nodes -w
```
