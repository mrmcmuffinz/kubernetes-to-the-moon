# Installing the Control Plane on controlplane-1 (Two Nodes)

**Based on:** [03-control-plane.md](../../single-systemd/03-control-plane.md) of the single-node guide.

**Adapted for:** A two-node cluster. The control plane runs only on `controlplane-1`. The apiserver advertises itself on the bridge IP `192.168.122.10` so `nodes-1`'s kubelet can reach it.

---

## What This Chapter Does

Installs etcd, kube-apiserver, kube-controller-manager, and kube-scheduler as systemd services on `controlplane-1`. The components and configuration are nearly identical to the single-node guide, with three notable differences. First, the apiserver listens on `0.0.0.0` and advertises `192.168.122.10` so `nodes-1` can reach it. Second, etcd's listen-client-urls include both `127.0.0.1` and `192.168.122.10`. Third, controller-manager binds on `0.0.0.0` for the same reason (so health checks and metrics work from anywhere on the cluster).

The control plane does not run on `nodes-1`. Only kubelet and kube-proxy run there, set up in document 05.

## What Is Different from the Single-Node Guide

- apiserver `--advertise-address=192.168.122.10` instead of `10.0.2.15`
- apiserver `--bind-address=0.0.0.0` (same as single-node, but now meaningful since something other than localhost is reaching it)
- etcd `--listen-client-urls` includes `192.168.122.10:2379` instead of `10.0.2.15:2379`
- controller-manager `--bind-address=0.0.0.0` so its `:10257/healthz` is reachable from `nodes-1` for debugging

Everything else is the same shape: same paths, same flags, same systemd unit structure.

## Prerequisites

Document 03 complete. SSH into `controlplane-1`:

```bash
ssh controlplane-1
cd ~/auth
```

The certs and kubeconfigs from document 03 should be in `~/auth/`.

---

## Part 1: Install Binaries

Same as single-systemd document 03. Run on `controlplane-1`:

```bash
arch=amd64
k8s_version=1.35.3
etcd_version=3.6.9

etcd_archive=etcd-v${etcd_version}-linux-${arch}.tar.gz

wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/v${etcd_version}/${etcd_archive}" \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kube-apiserver" \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kube-controller-manager" \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kube-scheduler" \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kubectl"

chmod +x kube-apiserver kube-controller-manager kube-scheduler kubectl
sudo cp kube-apiserver kube-controller-manager kube-scheduler kubectl /usr/local/bin/

mkdir -p etcd
tar -xvf ${etcd_archive} -C etcd --strip-components=1
sudo cp etcd/etcd etcd/etcdctl etcd/etcdutl /usr/local/bin/
```

Verify:

```bash
etcd --version
etcdctl version
kube-apiserver --version
kube-controller-manager --version
kube-scheduler --version
kubectl version --client
```

---

## Part 2: etcd

### Step 1: Place Certificates

```bash
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo cp ~/auth/ca.pem ~/auth/kubernetes.pem ~/auth/kubernetes-key.pem /etc/etcd/
sudo chmod 700 /var/lib/etcd
```

### Step 2: systemd Unit

```bash
cat <<'EOF' | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/etcd-io/etcd
After=network.target

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \
  --name=controlplane-1 \
  --cert-file=/etc/etcd/kubernetes.pem \
  --key-file=/etc/etcd/kubernetes-key.pem \
  --peer-cert-file=/etc/etcd/kubernetes.pem \
  --peer-key-file=/etc/etcd/kubernetes-key.pem \
  --trusted-ca-file=/etc/etcd/ca.pem \
  --peer-trusted-ca-file=/etc/etcd/ca.pem \
  --peer-client-cert-auth \
  --client-cert-auth \
  --initial-advertise-peer-urls=https://192.168.122.10:2380 \
  --listen-peer-urls=https://192.168.122.10:2380 \
  --listen-client-urls=https://192.168.122.10:2379,https://127.0.0.1:2379 \
  --advertise-client-urls=https://192.168.122.10:2379 \
  --initial-cluster-token=etcd-cluster-0 \
  --initial-cluster=controlplane-1=https://192.168.122.10:2380 \
  --initial-cluster-state=new \
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
EOF
```

### Step 3: Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd

# Verify
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

---

## Part 3: kube-apiserver

### Step 1: Place Certificates and Configs

```bash
sudo mkdir -p /var/lib/kubernetes
sudo cp ~/auth/ca.pem ~/auth/ca-key.pem \
        ~/auth/kubernetes.pem ~/auth/kubernetes-key.pem \
        ~/auth/service-account.pem ~/auth/service-account-key.pem \
        ~/auth/encryption-config.yaml \
        /var/lib/kubernetes/
```

### Step 2: systemd Unit

```bash
cat <<'EOF' | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes
After=etcd.service
Requires=etcd.service

[Service]
ExecStart=/usr/local/bin/kube-apiserver \
  --advertise-address=192.168.122.10 \
  --allow-privileged=true \
  --apiserver-count=1 \
  --audit-log-maxage=30 \
  --audit-log-maxbackup=3 \
  --audit-log-maxsize=100 \
  --audit-log-path=/var/log/audit.log \
  --authorization-mode=Node,RBAC \
  --bind-address=0.0.0.0 \
  --client-ca-file=/var/lib/kubernetes/ca.pem \
  --enable-admission-plugins=NodeRestriction,ServiceAccount \
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \
  --etcd-cafile=/var/lib/kubernetes/ca.pem \
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \
  --etcd-servers=https://127.0.0.1:2379 \
  --event-ttl=1h \
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \
  --runtime-config=api/all=true \
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \
  --service-account-issuer=https://192.168.122.10:6443 \
  --service-cluster-ip-range=10.96.0.0/16 \
  --service-node-port-range=30000-32767 \
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Step 3: Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver
sudo systemctl start kube-apiserver

# Verify (give it a few seconds)
sleep 5
curl --cacert /var/lib/kubernetes/ca.pem https://192.168.122.10:6443/healthz
# Expected: ok
```

---

## Part 4: kube-controller-manager

### Step 1: Place kubeconfig

```bash
sudo cp ~/auth/kube-controller-manager.kubeconfig /var/lib/kubernetes/
```

### Step 2: systemd Unit

```bash
cat <<'EOF' | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes
After=kube-apiserver.service
Requires=kube-apiserver.service

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \
  --bind-address=0.0.0.0 \
  --cluster-cidr=10.244.0.0/16 \
  --cluster-name=cka-twonode \
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \
  --leader-elect=true \
  --root-ca-file=/var/lib/kubernetes/ca.pem \
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \
  --service-cluster-ip-range=10.96.0.0/16 \
  --use-service-account-credentials=true \
  --allocate-node-cidrs=true \
  --node-cidr-mask-size=24 \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Two important flags here that did not appear (or were less important) in the single-node guide:

- `--allocate-node-cidrs=true` tells controller-manager to assign each node a slice of the cluster CIDR. With one node this was just `10.244.0.0/24`. With two nodes the controller will assign `controlplane-1` and `nodes-1` distinct /24 slices.
- `--node-cidr-mask-size=24` sets the slice size. With `cluster-cidr=10.244.0.0/16` and `mask-size=24`, you get up to 256 nodes' worth of slices, more than enough for this lab.

### Step 3: Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable kube-controller-manager
sudo systemctl start kube-controller-manager

# Verify
curl -k https://127.0.0.1:10257/healthz
```

---

## Part 5: kube-scheduler

### Step 1: Place kubeconfig

```bash
sudo cp ~/auth/kube-scheduler.kubeconfig /var/lib/kubernetes/
```

### Step 2: Scheduler Configuration File

```bash
sudo mkdir -p /etc/kubernetes/config

cat <<'EOF' | sudo tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF
```

### Step 3: systemd Unit

```bash
cat <<'EOF' | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes
After=kube-apiserver.service

[Service]
ExecStart=/usr/local/bin/kube-scheduler \
  --config=/etc/kubernetes/config/kube-scheduler.yaml \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

### Step 4: Start

```bash
sudo systemctl daemon-reload
sudo systemctl enable kube-scheduler
sudo systemctl start kube-scheduler

curl -k https://127.0.0.1:10259/healthz
```

---

## Part 6: kubectl Setup

```bash
mkdir -p ~/.kube
cp ~/auth/admin.kubeconfig ~/.kube/config

# Smoke test
kubectl get --raw /healthz
kubectl get componentstatuses 2>/dev/null || echo "(componentstatuses deprecated; check with /healthz)"
kubectl get namespaces
```

---

## Part 7: Verify Reachability from nodes-1

The whole point of binding the control plane on the bridge IP is that `nodes-1` can reach it. Confirm:

```bash
ssh nodes-1 'curl --cacert /tmp/ca.pem https://192.168.122.10:6443/healthz' 2>/dev/null || \
  ssh nodes-1 'curl -k https://192.168.122.10:6443/healthz'
# Expected: ok
```

If this fails:

```bash
# From controlplane-1
sudo ss -tlnp | grep 6443
# apiserver should be listening on 0.0.0.0:6443 (or *:6443)

# From the host
sudo iptables -L FORWARD -n | grep 192.168.122
# Forwarding between bridge ports should be allowed
```

---

## Summary

The control plane is up on `controlplane-1` and reachable from both `controlplane-1` and `nodes-1`:

| Service | Status | Listening On | Health |
|---------|--------|-------------|--------|
| etcd | Running | `192.168.122.10:2379`, `127.0.0.1:2379` | `etcdctl endpoint health` |
| kube-apiserver | Running | `0.0.0.0:6443` | `https://192.168.122.10:6443/healthz` |
| kube-controller-manager | Running | `0.0.0.0:10257` | `https://127.0.0.1:10257/healthz` |
| kube-scheduler | Running | `0.0.0.0:10259` | `https://127.0.0.1:10259/healthz` |

`kubectl get nodes` returns no rows yet because no kubelet has registered. The next document fixes that by installing the worker components on both nodes.
