# Worker Join: rpi-node-02 and rpi-node-03

**Purpose:** Join both worker nodes to the cluster, verify that all three nodes are
Ready, and confirm pods schedule on both workers.

Run the join command on each worker node separately.

---

## Prerequisites

- Document 04 is complete and `rpi-node-01` is in `Ready` state.
- Document 03 prerequisites are complete on `rpi-node-02` and `rpi-node-03`, including the
  containerd `bin_dir` and `sandbox_image` overrides. Without them a worker joins fine but
  every pod scheduled to it fails with `failed to find plugin "calico" in path [/usr/lib/cni]`,
  because `calico-node` is host-networked and starts regardless. Confirm on each worker
  before joining:

```bash
# On rpi-node-02 and rpi-node-03
sudo grep -E 'bin_dir|sandbox_image' /etc/containerd/config.toml
# Expected: bin_dir = "/opt/cni/bin"  and  sandbox_image = "registry.k8s.io/pause:3.10.1"
```

Quick check from the host:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes
# Expected: rpi-node-01   Ready   control-plane   ...
```

---

## Part 1: Generate a Fresh Join Token

Tokens from `kubeadm init` expire after 24 hours. Generate a fresh one from `rpi-node-01`:

```bash
# On rpi-node-01
kubeadm token create --print-join-command
```

Copy the output. It looks like:

```
kubeadm join 192.168.200.10:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

---

## Part 2: Join rpi-node-02

```bash
# On rpi-node-02 -- paste the join command with sudo
sudo kubeadm join 192.168.200.10:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

The join takes 1-2 minutes. When it completes, verify from the host:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes
# Expected: rpi-node-01 Ready, rpi-node-02 Ready (or NotReady briefly while Calico initializes)
```

---

## Part 3: Join rpi-node-03

```bash
# On rpi-node-03 -- same join command
sudo kubeadm join 192.168.200.10:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

Wait for `rpi-node-03` to appear:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes
# Expected: all three nodes Ready
```

---

## Part 4: Assign node-ip Annotation

If you want kubectl node annotations to show the correct IP, ensure kubelet is
advertising the right address on each worker. Verify:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes -o wide
# Expected: INTERNAL-IP shows 192.168.200.11 for rpi-node-02, 192.168.200.12 for rpi-node-03
```

If the INTERNAL-IP shows an unexpected address (e.g., a loopback), add `node-ip` to
kubelet's extra args. On the affected worker:

```bash
sudo tee /etc/default/kubelet > /dev/null <<'EOF'
KUBELET_EXTRA_ARGS=--node-ip=192.168.200.11
EOF
# Use 192.168.200.12 on rpi-node-03
sudo systemctl restart kubelet
```

---

## Part 5: Label Workers

Apply the worker role label so `kubectl get nodes` shows `worker` in the ROLES column:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf \
  kubectl label node rpi-node-02 rpi-node-03 node-role.kubernetes.io/worker=worker
```

---

## Verification

```bash
# All three nodes Ready with correct roles
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes -o wide
# Expected:
# rpi-node-01   Ready   control-plane   ...   192.168.200.10   ...
# rpi-node-02   Ready   worker          ...   192.168.200.11   ...
# rpi-node-03   Ready   worker          ...   192.168.200.12   ...

# All system pods running
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get pods -A
# Expected: All pods Running or Completed, none Pending or CrashLoopBackOff

# Calico nodes on all three
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get pods -n calico-system
# Expected: one calico-node pod per node, all Running
```

**Result:** Three-node cluster with one control plane and two workers. All Ready.

---

← [Previous: Control Plane Init](04-control-plane-init.md) | [Next: Verify →](06-verify.md)
