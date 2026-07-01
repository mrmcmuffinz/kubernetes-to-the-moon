# Initializing the Control Plane with kubeadm (Single Node)

**Based on:** [03-control-plane.md](../../single-systemd/03-control-plane.md) of the systemd guide (replaced wholesale by `kubeadm`) and the upstream [kubeadm init documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/).

**Adapted for:** A single-node cluster where the control-plane taint is removed so workloads can run on the same node.

---

## What This Chapter Does

`kubeadm init` does in one command what the systemd guide did manually across two documents (`02-bootstrapping-security.md` and `03-control-plane.md`): generates the cluster CA and all component certificates, writes kubeconfig files for each control plane component, generates the encryption key for Secrets at rest, writes static pod manifests for etcd and the three apiserver-side components, and starts kubelet which then brings the static pods up.

This is faster but loses the visibility of the manual approach. Part 6 of this document includes a mapping table from each `kubeadm`-generated file back to its hand-rolled equivalent in `single-systemd`, so you can use that guide as a reference when troubleshooting.

The control plane node is intentionally untainted in this single-node setup so workloads can also schedule on it.

## What Is Different from the systemd Guide

- **No cfssl.** `kubeadm` generates all certificates itself.
- **No hand-written systemd units for control plane components.** They run as static pods, defined by manifests in `/etc/kubernetes/manifests/` and managed by kubelet.
- **No manual kubeconfig generation.** `kubeadm` writes them.
- **YAML config instead of flags.** `kubeadm init --config` is what the exam expects you to be fluent with.
- **Control plane taint removed.** With one node, you want every pod to schedule somewhere.

## Prerequisites

Document 01 complete. SSH into the VM:

```bash
ssh kube@127.0.0.1 -p 2222
systemctl is-active containerd
kubeadm version -o short    # v1.35.3
```

---

## Part 1: Write the kubeadm Config

A flag-based `kubeadm init` works, but a YAML config is what you will see on the exam. It is also easier to diff if you need to rebuild later.

```bash
cat > ~/kubeadm-init.yaml <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 10.0.2.15
  bindPort: 6443
nodeRegistration:
  name: controlplane-1
  criSocket: unix:///run/containerd/containerd.sock
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.35.3
clusterName: cka-single
controlPlaneEndpoint: 10.0.2.15:6443
networking:
  serviceSubnet: 10.96.0.0/16
  podSubnet: 10.244.0.0/16
  dnsDomain: cluster.local
apiServer:
  extraArgs:
    - name: authorization-mode
      value: Node,RBAC
  certSANs:
    - 10.0.2.15
    - 127.0.0.1
    - localhost
    - controlplane-1
controllerManager: {}
scheduler: {}
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
EOF
```

A few details worth noting:

- `advertiseAddress: 10.0.2.15` is the VM's QEMU user-mode IP. If your VM has a different IP, run `ip addr show enp0s2` inside the VM and substitute the actual value.
- `certSANs` includes both `10.0.2.15` (where components inside the VM connect) and `127.0.0.1` (where you connect from the host through port forwarding). Without `127.0.0.1` in the SANs, the host-side `kubectl` will fail certificate validation.
- `podSubnet: 10.244.0.0/16` matches the Calico install in document 03. If you change one, change the other.
- `cgroupDriver: systemd` matches the containerd config from document 01. A mismatch here is one of the most common `kubeadm init` failure modes.

## Part 2: Run kubeadm init

```bash
sudo kubeadm init --config ~/kubeadm-init.yaml
```

The init takes 30 to 60 seconds. Successful output ends with:

```
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

## Part 3: Set Up kubectl Access

```bash
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Smoke test
kubectl cluster-info
kubectl get nodes
```

`kubectl get nodes` should show `controlplane-1` with status `NotReady` and role `control-plane`. `NotReady` is expected at this stage: there is no CNI yet, so kubelet refuses to mark the node Ready. Document 03 fixes that.

## Part 4: Remove the Control Plane Taint

By default, `kubeadm init` taints the control plane node with `node-role.kubernetes.io/control-plane:NoSchedule` so that workloads do not schedule on it. With a single node, you need to remove that taint so anything can run.

```bash
# Check current taints
kubectl describe node controlplane-1 | grep -i taint

# Remove the control-plane NoSchedule taint
kubectl taint nodes controlplane-1 node-role.kubernetes.io/control-plane:NoSchedule-

# Verify
kubectl describe node controlplane-1 | grep -i taint
# Expected: Taints: <none>
```

The CKA exam tests both directions of this taint syntax, so it is worth knowing how to put the taint back as well:

```bash
# To put the taint back later (for practice):
kubectl taint nodes controlplane-1 node-role.kubernetes.io/control-plane=:NoSchedule
```

## Part 5: Copy admin.conf to the Host

For working from your dev machine instead of SSH'ing in every time:

```bash
# From the host (not the VM)
mkdir -p ~/cka-lab/single-kubeadm
scp -P 2222 kube@127.0.0.1:/home/kube/.kube/config ~/cka-lab/single-kubeadm/admin.conf
```

The kubeconfig's `server` field will reference `10.0.2.15:6443` because of `controlPlaneEndpoint`. The host cannot reach `10.0.2.15` (it is the VM's internal NAT'd IP), so update the server to the port-forwarded address:

```bash
# From the host
sed -i 's|server: https://10.0.2.15:6443|server: https://127.0.0.1:6443|' \
  ~/cka-lab/single-kubeadm/admin.conf

# Use it
export KUBECONFIG=~/cka-lab/single-kubeadm/admin.conf
kubectl get nodes
```

The `127.0.0.1` SAN you added in Part 1 is what makes this work. Without it, the kubectl call would fail with a certificate validation error.

## Part 6: Verify Control Plane Components

The four static-pod control plane components are defined by manifests in `/etc/kubernetes/manifests/`. kubelet watches that directory and creates a pod for each file. CoreDNS and kube-proxy are also installed by `kubeadm init`, but they are not static pods.

```bash
# Static pod manifests (etcd and the three apiserver-side components only)
sudo ls -la /etc/kubernetes/manifests/
# Expected: etcd.yaml  kube-apiserver.yaml
#           kube-controller-manager.yaml  kube-scheduler.yaml
# CoreDNS is not here -- it runs as a Deployment, not a static pod.

# All pods in kube-system
kubectl -n kube-system get pods -o wide
```

Expected output after `kubeadm init` but before CNI is installed:

```
NAME                                      READY   STATUS    ...
coredns-<hash>-<hash>                     0/1     Pending   ...  ← Pending: no CNI yet
coredns-<hash>-<hash>                     0/1     Pending   ...  ← Pending: no CNI yet
etcd-controlplane-1                       1/1     Running   ...
kube-apiserver-controlplane-1             1/1     Running   ...
kube-controller-manager-controlplane-1    1/1     Running   ...
kube-proxy-<hash>                         0/1     Pending   ...  ← Pending: no CNI yet
kube-scheduler-controlplane-1             1/1     Running   ...
```

CoreDNS and kube-proxy are installed by kubeadm as a Deployment and DaemonSet respectively. Their images were pre-pulled in document 01. They stay Pending until Calico provides pod networking in document 03.

```bash
# Component health endpoints
curl -k https://127.0.0.1:6443/healthz
curl -k https://127.0.0.1:10257/healthz   # controller-manager
curl -k https://127.0.0.1:10259/healthz   # scheduler

# etcd health
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

All four endpoints should return success. The four static pods are `Running`; CoreDNS and kube-proxy being `Pending` at this stage is correct.

## Part 7: Inspect What kubeadm Built

Spend a few minutes looking at what `kubeadm init` actually created. This is the same set of files you built by hand in `single-systemd`, just generated automatically. Knowing the mapping is what makes the systemd guide useful as a reference.

```bash
# Certificates
sudo ls -la /etc/kubernetes/pki/

# Kubeconfigs
sudo ls -la /etc/kubernetes/*.conf

# Static pod manifests
sudo cat /etc/kubernetes/manifests/kube-apiserver.yaml | head -40

# kubelet config
sudo cat /var/lib/kubelet/config.yaml

# kubelet's kubeadm-managed environment
cat /var/lib/kubelet/kubeadm-flags.env
```

The mapping from systemd-guide hand-rolled files to `kubeadm`-generated files is:

| systemd-guide manual file | kubeadm equivalent |
|---|---|
| `~/auth/ca.pem`, `ca-key.pem` | `/etc/kubernetes/pki/ca.crt`, `ca.key` |
| `~/auth/kubernetes.pem`, `kubernetes-key.pem` | `/etc/kubernetes/pki/apiserver.crt`, `apiserver.key` |
| `~/auth/admin.pem`, `admin-key.pem` | Embedded in `/etc/kubernetes/admin.conf` |
| `~/auth/service-account.pem` | `/etc/kubernetes/pki/sa.pub`, `sa.key` |
| etcd certs in `/etc/etcd/` | `/etc/kubernetes/pki/etcd/*.crt`, `*.key` |
| `/etc/systemd/system/etcd.service` | `/etc/kubernetes/manifests/etcd.yaml` |
| `/etc/systemd/system/kube-apiserver.service` | `/etc/kubernetes/manifests/kube-apiserver.yaml` |
| `/etc/systemd/system/kube-controller-manager.service` | `/etc/kubernetes/manifests/kube-controller-manager.yaml` |
| `/etc/systemd/system/kube-scheduler.service` | `/etc/kubernetes/manifests/kube-scheduler.yaml` |
| `~/auth/admin.kubeconfig` | `/etc/kubernetes/admin.conf` |
| `~/auth/kube-controller-manager.kubeconfig` | `/etc/kubernetes/controller-manager.conf` |
| `~/auth/kube-scheduler.kubeconfig` | `/etc/kubernetes/scheduler.conf` |
| `/var/lib/kubelet/kubelet-config.yaml` | `/var/lib/kubelet/config.yaml` |

This is the most useful thing about doing the manual build first: when something breaks, you know exactly which file to look at.

---

## Summary

The control plane is up and reachable. Static pods are `Running`; CoreDNS and kube-proxy are `Pending` until Calico is installed in the next document:

| Component | How Managed | Status |
|-----------|-------------|--------|
| etcd | Static pod (`/etc/kubernetes/manifests/etcd.yaml`) | Running |
| kube-apiserver | Static pod (`/etc/kubernetes/manifests/kube-apiserver.yaml`) | Running |
| kube-controller-manager | Static pod (`/etc/kubernetes/manifests/kube-controller-manager.yaml`) | Running |
| kube-scheduler | Static pod (`/etc/kubernetes/manifests/kube-scheduler.yaml`) | Running |
| kube-proxy | DaemonSet (installed by kubeadm) | Pending (no CNI) |
| CoreDNS | Deployment (installed by kubeadm) | Pending (no CNI) |

`kubectl get nodes` shows `controlplane-1` as `NotReady`. The next document installs Calico to make the node `Ready` and move CoreDNS and kube-proxy to `Running`.

---

← [Previous: Installing Container Runtime and kubeadm Toolchain (Single Node)](01-node-prerequisites.md) | [Next: Installing Calico as the Cluster CNI (Single Node) →](03-cni-installation.md)
