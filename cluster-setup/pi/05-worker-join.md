# Worker Join: pi-w1 and pi-w2

**Purpose:** Join both worker nodes to the cluster, verify that all three nodes are
Ready, and confirm pods schedule on both workers.

Run the join command on each worker node separately.

---

## Prerequisites

- Document 04 is complete and `pi-cp` is in `Ready` state.
- Document 03 prerequisites are complete on `pi-w1` and `pi-w2`.

Quick check from the host:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes
# Expected: pi-cp   Ready   control-plane   ...
```

---

## Part 1: Generate a Fresh Join Token

Tokens from `kubeadm init` expire after 24 hours. Generate a fresh one from `pi-cp`:

```bash
# On pi-cp
kubeadm token create --print-join-command
```

Copy the output. It looks like:

```
kubeadm join 192.168.200.10:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

---

## Part 2: Join pi-w1

```bash
# On pi-w1 -- paste the join command with sudo
sudo kubeadm join 192.168.200.10:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

The join takes 1-2 minutes. When it completes, verify from the host:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes
# Expected: pi-cp Ready, pi-w1 Ready (or NotReady briefly while Calico initializes)
```

---

## Part 3: Join pi-w2

```bash
# On pi-w2 -- same join command
sudo kubeadm join 192.168.200.10:6443 --token <token> \
    --discovery-token-ca-cert-hash sha256:<hash>
```

Wait for `pi-w2` to appear:

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
# Expected: INTERNAL-IP shows 192.168.200.11 for pi-w1, 192.168.200.12 for pi-w2
```

If the INTERNAL-IP shows an unexpected address (e.g., a loopback), add `node-ip` to
kubelet's extra args. On the affected worker:

```bash
sudo tee /etc/default/kubelet > /dev/null <<'EOF'
KUBELET_EXTRA_ARGS=--node-ip=192.168.200.11
EOF
# Use 192.168.200.12 on pi-w2
sudo systemctl restart kubelet
```

---

## Part 5: Label Workers

Apply the worker role label so `kubectl get nodes` shows `worker` in the ROLES column:

```bash
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf \
  kubectl label node pi-w1 pi-w2 node-role.kubernetes.io/worker=worker
```

---

## Verification

```bash
# All three nodes Ready with correct roles
KUBECONFIG=~/cka-lab/pi-kubeadm/admin.conf kubectl get nodes -o wide
# Expected:
# pi-cp   Ready   control-plane   ...   192.168.200.10   ...
# pi-w1   Ready   worker          ...   192.168.200.11   ...
# pi-w2   Ready   worker          ...   192.168.200.12   ...

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
