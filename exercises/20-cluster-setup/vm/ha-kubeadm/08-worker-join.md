# Worker Join: nodes-1, nodes-2, nodes-3

**Purpose:** Join all three worker nodes to the cluster. The process is identical to
the three-node guide -- generate a fresh token on `controlplane-1` and run `kubeadm
join` on each worker. Verify that pods schedule across all nodes and that cross-node
networking works through the Calico VXLAN tunnel.

---

## Prerequisites

- Both control planes are `Ready` (document 07).
- All three workers have containerd and kubeadm installed (document 03).

## Part 1: Preflight Checks on All Three Workers

```bash
for node in nodes-1 nodes-2 nodes-3; do
  echo "=== $node ==="
  ssh "$node" '
    sudo crictl info 2>/dev/null | grep -q runtimeHandlers && echo "containerd: OK"
    free -h | grep Swap
    curl -sk https://192.168.100.100:6443/healthz && echo " (VIP reachable)"
  '
done
```

## Part 2: Generate a Fresh Worker Join Token

Note: worker join uses the regular `kubeadm join` (no `--control-plane` flag).

```bash
JOIN_CMD=$(ssh controlplane-1 'kubeadm token create --print-join-command')
echo "$JOIN_CMD"
```

The join command points to the VIP (`192.168.100.100:6443`), not directly to either
control plane node.

## Part 3: Join All Three Workers

**Single-NIC setup (default):**

```bash
for node in nodes-1 nodes-2 nodes-3; do
  echo "=== Joining $node ==="
  ssh "$node" "sudo $JOIN_CMD"
done
```

**Dual-NIC callout:** If you used Option C from document 02, pass a per-node config
file so kubelet registers with the cluster NIC IP instead of the external NIC's DHCP
address. Worker IPs are `192.168.100.22`, `.13`, `.14` for `nodes-1`, `nodes-2`,
`nodes-3` respectively.

```bash
TOKEN=$(ssh controlplane-1 'kubeadm token create')
HASH=$(ssh controlplane-1 'openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | \
  openssl rsa -pubin -outform der 2>/dev/null | \
  openssl dgst -sha256 -hex | sed "s/^.* //"')

declare -A WORKER_IPS=( [nodes-1]=192.168.100.22 [nodes-2]=192.168.100.23 [nodes-3]=192.168.100.24 )

for node in nodes-1 nodes-2 nodes-3; do
  NODE_IP="${WORKER_IPS[$node]}"
  ssh "$node" "cat > ~/kubeadm-join.yaml" <<EOF
apiVersion: kubeadm.k8s.io/v1beta4
kind: JoinConfiguration
discovery:
  bootstrapToken:
    apiServerEndpoint: "192.168.100.100:6443"
    token: ${TOKEN}
    caCertHashes:
      - sha256:${HASH}
nodeRegistration:
  kubeletExtraArgs:
    - name: "node-ip"
      value: "${NODE_IP}"
EOF
  ssh "$node" "sudo kubeadm join --config ~/kubeadm-join.yaml"
  echo "=== $node joined ==="
done
```

## Part 4: Verify All Five Nodes Ready

```bash
kubectl get nodes -o wide
```

Wait 60-90 seconds for Calico to schedule `calico-node` pods on the new workers. All
five nodes should show `Ready`:

```
NAME              STATUS   ROLES           AGE
controlplane-1    Ready    control-plane   20m
controlplane-2    Ready    control-plane   10m
nodes-1           Ready    <none>          2m
nodes-2           Ready    <none>          1m
nodes-3           Ready    <none>          30s
```

## Part 5: Verify Cross-Node Networking

```bash
# Schedule one test pod on each node
for node in controlplane-1 nodes-1 nodes-2 nodes-3; do
  kubectl run "test-${node}" --image=busybox:1.36 --restart=Never \
    --overrides="{\"spec\":{\"nodeName\":\"${node}\"}}" -- sleep 300
done

kubectl wait --for=condition=Ready pod -l run --timeout=120s

# Get pod IPs
kubectl get pods -o wide

# Cross-node ping: worker to worker
W1_IP=$(kubectl get pod test-nodes-1 -o jsonpath='{.status.podIP}')
W2_IP=$(kubectl get pod test-nodes-2 -o jsonpath='{.status.podIP}')
W3_IP=$(kubectl get pod test-nodes-3 -o jsonpath='{.status.podIP}')

kubectl exec test-nodes-1 -- ping -c 2 "$W2_IP"
kubectl exec test-nodes-1 -- ping -c 2 "$W3_IP"
kubectl exec test-nodes-2 -- ping -c 2 "$W3_IP"

kubectl delete pods -l run
```

## Part 6: Verify DaemonSets

```bash
# calico-node should be on all 5 nodes (or 3 workers if control planes are tainted)
kubectl -n calico-system get pods -l k8s-app=calico-node -o wide

# kube-proxy should be on all 5 nodes
kubectl -n kube-system get pods -l k8s-app=kube-proxy -o wide
```

## Part 7: Disk Snapshots

Snapshot all five disks for rollback:

```bash
~/cka-lab/ha-kubeadm/stop-cluster.sh

for node in controlplane-1 controlplane-2 nodes-1 nodes-2 nodes-3; do
  qemu-img snapshot -c clean-install ~/cka-lab/ha-kubeadm/$node/$node.qcow2
  echo "Snapshot created for $node"
done

~/cka-lab/ha-kubeadm/start-cluster.sh
```

**Result:** All five nodes `Ready`, cross-node pod networking working through Calico
VXLAN, DaemonSets deployed on all nodes.

---

← [Previous: Second Control Plane Join](07-second-control-plane-join.md) | [Next: Cluster Services →](09-cluster-services.md)
