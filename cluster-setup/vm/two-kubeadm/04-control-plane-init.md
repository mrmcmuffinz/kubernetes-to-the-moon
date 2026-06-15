# Initializing the Control Plane with kubeadm

**Based on:** [03-control-plane.md](../../vm/docs/03-control-plane.md) of the single-node guide (replaced wholesale by `kubeadm`) and the upstream [kubeadm init documentation](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/create-cluster-kubeadm/).

**Purpose:** Bring up the entire control plane (etcd, kube-apiserver, kube-controller-manager, kube-scheduler) on `controlplane-1` with one `kubeadm init` command driven by a YAML config. This is the equivalent of single-node documents 02 and 03 combined, compressed from a hundred-plus commands into one.

---

## What This Chapter Does

`kubeadm init` does in one command what the single-node guide did manually across two documents: generates the cluster CA and all component certificates, writes kubeconfig files for each control plane component, generates the encryption key for Secrets at rest, writes static pod manifests for etcd and the three apiserver-side components, and starts kubelet which then brings the static pods up.

This is faster but loses the visibility of the manual approach. The single-node guide is the right tool for understanding what each file does; this document is the right tool for getting an exam-shaped cluster up quickly. After init, document 04 includes a mapping table from each `kubeadm`-generated file back to its hand-rolled equivalent, so you can use the single-node guide as a reference when troubleshooting.

## What Is Different from the Single-Node Guide

- **No cfssl.** `kubeadm` generates all certificates itself.
- **No hand-written systemd units for control plane components.** They run as static pods, defined by manifests in `/etc/kubernetes/manifests/` and managed by kubelet.
- **No manual kubeconfig generation.** `kubeadm` writes them.
- **YAML config instead of flags.** `kubeadm init --config` is what the exam expects you to be fluent with.

The control plane node is left untainted in this guide so workloads can also schedule there. That is non-default for `kubeadm init` and is corrected in document 05.

## Prerequisites

`controlplane-1` from the previous document must have containerd running and `kubeadm`, `kubelet`, `kubectl` installed at v1.35.3. SSH into `controlplane-1` before proceeding.

```bash
ssh controlplane-1
systemctl is-active containerd
kubeadm version -o short    # v1.35.3
```


All verification commands in Parts 3-6 that reference `192.168.100.10` must use your actual controlplane-1 IP.

---

## Part 1: Write the kubeadm Config

A flag-based `kubeadm init` works, but a YAML config is what you will see on the exam and in production. It is also easier to diff if you need to rebuild later.

```bash
cat > ~/kubeadm-init.yaml <<'EOF'
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: 192.168.100.10
  bindPort: 6443
nodeRegistration:
  name: controlplane-1
  criSocket: unix:///run/containerd/containerd.sock
  kubeletExtraArgs:
    - name: node-ip
      value: 192.168.100.10
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: v1.35.3
clusterName: cka-twonode
controlPlaneEndpoint: 192.168.100.10:6443
networking:
  serviceSubnet: 10.96.0.0/16
  podSubnet: 10.244.0.0/16
  dnsDomain: cluster.local
apiServer:
  extraArgs:
    - name: authorization-mode
      value: Node,RBAC
  certSANs:
    - 192.168.100.10
    - controlplane-1
    - controlplane-1.cka.local
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
```

A few details worth noting:

- `advertiseAddress` and `node-ip` both point at `192.168.100.10`. With a single network interface the default would work, but setting them explicitly removes ambiguity and matches what you would do in any environment with multiple interfaces.
- `podSubnet: 10.244.0.0/16` matches the Calico install in document 05. If you change one, change the other.
- `controlPlaneEndpoint` is set even on a single control plane node so that worker join tokens reference a stable name. It also means the cluster could grow to HA later without re-issuing certificates.
- `cgroupDriver: systemd` matches the containerd config from document 03. A mismatch here is one of the most common `kubeadm init` failure modes.

## Part 2: Run kubeadm init

```bash
sudo kubeadm init --config ~/kubeadm-init.yaml --upload-certs
```

Successful output ends with two key blocks. The first shows how to set up `kubectl`:

```
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

The second shows the join command for `nodes-1`:

```
You can now join any number of worker nodes by running the following on each as root:

kubeadm join 192.168.100.10:6443 --token abcdef.0123456789abcdef \
        --discovery-token-ca-cert-hash sha256:1234...
```

Save that join command somewhere. You will need it on `nodes-1` in document 06. If you lose it, you can regenerate later with `kubeadm token create --print-join-command`.

## Part 3: Set Up kubectl Access

Run on `controlplane-1` as the `kube` user:

```bash
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown $(id -u):$(id -g) ~/.kube/config

# Smoke test
kubectl cluster-info
kubectl get nodes
```

`kubectl get nodes` should show `controlplane-1` with status `NotReady` and role `control-plane`. `NotReady` is expected at this stage: there is no CNI yet, so kubelet refuses to mark the node Ready. Document 05 fixes that.

## Part 4: Copy admin.conf to the Host

For working from your dev machine instead of SSH'ing in every time:

```bash
# From the host
mkdir -p ~/cka-lab/two-kubeadm
scp controlplane-1:/home/kube/.kube/config ~/cka-lab/two-kubeadm/admin.conf

# Use it
export KUBECONFIG=~/cka-lab/two-kubeadm/admin.conf
kubectl get nodes
```

The `admin.conf` already references `192.168.100.10:6443` because of `controlPlaneEndpoint`, so no edits are needed.

## Part 5: Verify Control Plane Components

All four control plane components run as static pods in the `kube-system` namespace, defined by manifests in `/etc/kubernetes/manifests/`. kubelet watches that directory and creates a pod for each file.

```bash
# Static pod manifests (on controlplane-1)
sudo ls -la /etc/kubernetes/manifests/
# Should list: etcd.yaml, kube-apiserver.yaml,
#              kube-controller-manager.yaml, kube-scheduler.yaml

# Static pods running
kubectl -n kube-system get pods -o wide

# Component health endpoints
curl -k https://192.168.100.10:6443/healthz
curl -k https://127.0.0.1:10257/healthz   # controller-manager
curl -k https://127.0.0.1:10259/healthz   # scheduler

# etcd health
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

All four endpoints should return success (a `200 OK` body of `ok`, or a JSON `is healthy` for etcd).

## Part 6: Inspect What kubeadm Built

Spend a few minutes looking at what `kubeadm init` actually created. This is the same set of files you built by hand in the single-node guide, just generated automatically. Knowing the mapping is what makes the single-node guide useful as a reference.

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

The mapping from single-node-guide hand-rolled files to `kubeadm`-generated files is:

| Single-node manual file | kubeadm equivalent |
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
| Manual encryption-config.yaml | Not enabled by default in `kubeadm`; configured separately if needed |

This is the most useful thing about doing the manual build first: when something breaks, you know exactly which file to look at, and the runbooks from the single-node guide still apply with these path substitutions.

---

## Summary

The control plane is up and reachable:

| Component | Manifest | Health Endpoint |
|-----------|----------|-----------------|
| etcd | `/etc/kubernetes/manifests/etcd.yaml` | etcdctl endpoint health |
| kube-apiserver | `/etc/kubernetes/manifests/kube-apiserver.yaml` | `https://192.168.100.10:6443/healthz` |
| kube-controller-manager | `/etc/kubernetes/manifests/kube-controller-manager.yaml` | `https://127.0.0.1:10257/healthz` |
| kube-scheduler | `/etc/kubernetes/manifests/kube-scheduler.yaml` | `https://127.0.0.1:10259/healthz` |

`kubectl get nodes` shows `controlplane-1` as `NotReady`. The next document installs Calico to make the node `Ready` and enable pod networking.

---

← [Previous: Installing Container Runtime and kubeadm Toolchain](03-node-prerequisites.md) | [Next: Installing Calico as the Cluster CNI →](05-cni-installation.md)
