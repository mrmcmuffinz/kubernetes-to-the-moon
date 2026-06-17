# Control Plane Initialization

**Purpose:** Run `kubeadm init` on `rpi-node-01` to bring up the full control plane (etcd,
kube-apiserver, kube-controller-manager, kube-scheduler) and generate the join token
for the worker nodes.

This document runs on `rpi-node-01` only.

---

## Prerequisites

Document 03 must be complete on all three nodes.

Quick check:

```bash
# On rpi-node-01
kubeadm version -o short
# Expected: v1.35.x

sudo systemctl is-active containerd
# Expected: active

swapon --show
# Expected: no output
```

---

## Part 1: kubeadm init

Use a YAML config file to set the key parameters explicitly. This uses the `v1beta4`
kubeadm API (the current version for Kubernetes v1.35; `v1beta3` is removed in v1.36). The
`controlPlaneEndpoint` is the static IP of `rpi-node-01` (no HAProxy needed for a single
control plane).

```bash
sudo tee /tmp/kubeadm-config.yaml > /dev/null <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.200.10
  bindPort: 6443
nodeRegistration:
  name: rpi-node-01
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    - name: node-ip
      value: 192.168.200.10
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.35.6
clusterName: kubernetes
controlPlaneEndpoint: 192.168.200.10:6443
networking:
  serviceSubnet: 10.96.0.0/16
  podSubnet: 10.244.0.0/16
  dnsDomain: cluster.local
apiServer:
  extraArgs:
    - name: authorization-mode
      value: Node,RBAC
  certSANs:
    - 192.168.200.10
    - rpi-node-01
    - rpi-node-01.cka.local
controllerManager:
  extraArgs:
    - name: bind-address
      value: 0.0.0.0
scheduler:
  extraArgs:
    - name: bind-address
      value: 0.0.0.0
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF

sudo kubeadm init --config /tmp/kubeadm-config.yaml --upload-certs
```

A few notes on the fields. In `v1beta4` every `extraArgs` block is a list of `name`/`value`
pairs rather than a map, which is why `authorization-mode` and the two `bind-address`
entries take that shape. The explicit `KubeletConfiguration` sets `cgroupDriver: systemd` to
match the containerd setting from document 03; the two must agree or the kubelet fails under
load. Setting `bind-address: 0.0.0.0` on the controller-manager and scheduler exposes their
metrics endpoints for the observability stack later. `certSANs` lists every name and IP a
client might use to reach the API server, and `criSocket` pins containerd explicitly so
kubeadm does not have to autodetect it.

`--upload-certs` is included in case you want to add a second control plane node later.
It uploads the certs to a kubeadm-certs Secret in the cluster and prints a `--certificate-key` for the join command.

`kubeadm init` takes 3-5 minutes. The output ends with a `kubeadm join` command -- save it.

---

## Part 2: Configure kubectl on rpi-node-01

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Verify
kubectl get nodes
# Expected: rpi-node-01   NotReady   control-plane   <age>   v1.35.x
```

`NotReady` is expected at this stage because there is no CNI plugin yet.

---

## Part 3: Copy kubeconfig to Host

Run this on the **host machine**:

```bash
mkdir -p ~/cka-lab/pi-kubeadm
scp rpi-node-01:.kube/config ~/cka-lab/pi-kubeadm/admin.conf

# Test from host
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes
# Expected: rpi-node-01   NotReady   control-plane   ...
```

---

## Part 4: Install Calico CNI

Still on `rpi-node-01`:

```bash
# Install Tigera operator
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.31.5/manifests/tigera-operator.yaml

# Apply custom resources (defines the Calico IPPool matching podSubnet)
kubectl create -f - <<'EOF'
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
---
apiVersion: operator.tigera.io/v1
kind: APIServer
metadata:
  name: default
spec: {}
EOF

# Wait for Calico to come up (1-3 minutes)
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=300s
```

On ARM64, the Tigera operator manifest pulls ARM64 images automatically via multi-arch
image manifests. No additional configuration is needed.

---

## Part 5: Verification

```bash
# rpi-node-01 should now be Ready
kubectl get nodes
# Expected: rpi-node-01   Ready   control-plane   <age>   v1.35.x

# All system pods should be Running
kubectl get pods -n kube-system
kubectl get pods -n calico-system

# API server is reachable
curl -k https://192.168.200.10:6443/healthz
# Expected: ok

# Save the join command for document 05
kubeadm token create --print-join-command
```

**Result:** `rpi-node-01` is a single-node cluster with Calico CNI. Workers will join in
document 05.

---

← [Previous: Node Prerequisites](03-node-prerequisites.md) | [Next: Worker Join →](05-worker-join.md)
