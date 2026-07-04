# Control Plane Initialization

**Based on:** [`two-kubeadm/04-control-plane-init.md`](../two-kubeadm/04-control-plane-init.md)

**Purpose:** Run `kubeadm init` on `controlplane-1`. The configuration is identical to
the two-node guide.

---

## Prerequisites

- All three nodes have containerd running and the kubeadm toolchain installed (document 03).
- SSH access to `controlplane-1` is working.

## Part 1: kubeadm Configuration File

On `controlplane-1`:

```bash
ssh controlplane-1
```

Create `~/kubeadm-init.yaml`:

```yaml
apiVersion: kubeadm.k8s.io/v1beta4
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: "192.168.100.10"
  bindPort: 6443
---
apiVersion: kubeadm.k8s.io/v1beta4
kind: ClusterConfiguration
kubernetesVersion: "v1.35.3"
controlPlaneEndpoint: "192.168.100.10:6443"
networking:
  serviceSubnet: "10.96.0.0/16"
  podSubnet: "10.244.0.0/16"
certSANs:
  - "192.168.100.10"
  - "127.0.0.1"
  - "localhost"
  - "controlplane-1"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

## Part 2: Run kubeadm init

```bash
sudo kubeadm init --config ~/kubeadm-init.yaml
```

kubeadm prints a `kubeadm join` command at the end. Save it -- you will use it in
document 06.

## Part 3: Set Up kubectl

```bash
mkdir -p ~/.kube
sudo cp /etc/kubernetes/admin.conf ~/.kube/config
sudo chown "$(id -u):$(id -g)" ~/.kube/config

kubectl get nodes
# controlplane-1   NotReady   control-plane   ...
```

The node is `NotReady` because Calico is not installed yet.

## Part 4: Remove the Control Plane Taint

```bash
kubectl taint nodes controlplane-1 node-role.kubernetes.io/control-plane:NoSchedule-
```

This lets workloads schedule on `controlplane-1`. With three nodes (one control plane +
two workers) you have a useful three-node scheduling surface.

## Part 5: Copy kubeconfig to Host

Exit the VM (`exit`) and run on the host:

```bash
mkdir -p ~/cka-lab/three-kubeadm
scp controlplane-1:/etc/kubernetes/admin.conf ~/cka-lab/three-kubeadm/admin.conf
scp controlplane-1:/etc/kubernetes/pki/ca.crt  ~/cka-lab/three-kubeadm/ca.crt
export KUBECONFIG=~/cka-lab/three-kubeadm/admin.conf
kubectl get nodes
```

## File Mapping (kubeadm vs. single-systemd)

| Purpose | systemd guide | kubeadm path |
|---------|--------------|--------------|
| etcd manifest | `/etc/systemd/system/etcd.service` | `/etc/kubernetes/manifests/etcd.yaml` |
| API server manifest | `/etc/systemd/system/kube-apiserver.service` | `/etc/kubernetes/manifests/kube-apiserver.yaml` |
| etcd certs | `/etc/etcd/*.pem` | `/etc/kubernetes/pki/etcd/*.crt`, `*.key` |
| API server certs | `/var/lib/kubernetes/*.pem` | `/etc/kubernetes/pki/*.crt`, `*.key` |
| kubelet config | `/var/lib/kubelet/kubelet-config.yaml` | `/var/lib/kubelet/config.yaml` |
| kubelet kubeconfig | `/var/lib/kubelet/kubeconfig` | `/etc/kubernetes/kubelet.conf` |
| admin kubeconfig | `~/auth/admin.kubeconfig` | `/etc/kubernetes/admin.conf` |

**Result:** Kubernetes API reachable at `https://192.168.100.10:6443`. `controlplane-1`
is `NotReady` (no CNI yet).

---

← [Previous: Node Prerequisites: Three Nodes](03-node-prerequisites.md) | [Next: CNI Installation: Calico →](05-cni-installation.md)
