# Manual Pod Routing Between Nodes

**Based on:** Original work. The single-node guide had no equivalent because cross-node traffic does not exist on a single node. Production CNIs (Calico, Cilium, Flannel) do this work automatically.

**Purpose:** Make cross-node pod-to-pod traffic actually work. Without this document, pods on `controlplane-1` can talk to other pods on `controlplane-1` (same bridge), and pods on `nodes-1` can talk to other pods on `nodes-1`, but neither can reach pods on the other node.

---

## What This Chapter Does

Adds Linux routing rules so that pod traffic destined for the other node's pod CIDR gets sent to that node's bridge IP. This is the routing layer that Calico, Cilium, and Flannel handle automatically. With the basic `bridge` CNI plugin you have to add these routes by hand. The routing model itself is straightforward; the reason this document exists at all is to make the model visible, because in a `kubeadm`-installed cluster with a real CNI, none of this is exposed to you.

## The Routing Problem

Each node has a CNI bridge with its own pod CIDR slice. After document 05, the situation looks like:

```
controlplane-1 (192.168.122.10):
  cnio0: 10.244.0.1/24       (CNI bridge)
  pods:  10.244.0.2, 10.244.0.3, ...
  routing table:
    10.244.0.0/24 dev cnio0          # local, knows how to reach
    192.168.122.0/24 dev enp0s2      # bridge, knows how to reach
    default via 192.168.122.1        # bridge gateway

nodes-1 (192.168.122.11):
  cnio0: 10.244.1.1/24       (CNI bridge)
  pods:  10.244.1.2, 10.244.1.3, ...
  routing table:
    10.244.1.0/24 dev cnio0          # local
    192.168.122.0/24 dev enp0s2      # bridge
    default via 192.168.122.1
```

When a pod on `controlplane-1` (say `10.244.0.5`) sends a packet to a pod on `nodes-1` (say `10.244.1.5`), the kernel on `controlplane-1` has no idea where `10.244.1.0/24` is. The default route sends it to the bridge gateway (`192.168.122.1`), which has no idea either, so the packet eventually gets dropped.

The fix is one route on each node:

```
On controlplane-1:  ip route add 10.244.1.0/24 via 192.168.122.11
On nodes-1:  ip route add 10.244.0.0/24 via 192.168.122.10
```

Now `controlplane-1` knows that `10.244.1.0/24` is reachable through `nodes-1`'s bridge IP. When the packet arrives at `nodes-1`, its existing route says "pods at `10.244.1.0/24` live on `cnio0`", and the packet is delivered.

## Why This Is Not Persistent in Production

Production CNIs do this automatically and usually with encapsulation (VXLAN, IP-in-IP) so you do not need to add routes at all. The trade-off is more moving parts. The bridge plugin with manual routes is the simplest possible multi-node setup and exposes the routing layer directly, which is useful for understanding what the more complex CNIs are doing under the hood.

## Prerequisites

Document 05 complete. Both nodes are `Ready`. Same-node pod traffic works. Cross-node pod traffic does not. The two test pods (`busybox-n1` and `busybox-n2`) from the document 05 smoke test should still be running.

---

## Part 1: Confirm the Problem

Verify that cross-node pod traffic is currently broken:

```bash
ssh controlplane-1

N1_IP=$(kubectl get pod busybox-n1 -o jsonpath='{.status.podIP}')
N2_IP=$(kubectl get pod busybox-n2 -o jsonpath='{.status.podIP}')
echo "busybox-n1 IP: $N1_IP"
echo "busybox-n2 IP: $N2_IP"

# Same-node: pod-to-bridge-gateway should work
kubectl exec busybox-n1 -- ping -c 1 -W 2 10.244.0.1 && echo "controlplane-1 pod -> controlplane-1 bridge: OK"

# Cross-node: should time out
kubectl exec busybox-n1 -- ping -c 1 -W 2 "$N2_IP" || echo "FAIL: controlplane-1 pod cannot reach nodes-1 pod"
kubectl exec busybox-n2 -- ping -c 1 -W 2 "$N1_IP" || echo "FAIL: nodes-1 pod cannot reach controlplane-1 pod"
```

The same-node ping works. The two cross-node pings fail. That is the symptom.

You can also see the problem in the routing tables:

```bash
ssh controlplane-1 'ip route | grep 10.244'
# Output: 10.244.0.0/24 dev cnio0 ...
# Notice: no route for 10.244.1.0/24

ssh nodes-1 'ip route | grep 10.244'
# Output: 10.244.1.0/24 dev cnio0 ...
# Notice: no route for 10.244.0.0/24
```

---

## Part 2: Add the Routes

### Step 1: On controlplane-1

```bash
ssh controlplane-1
sudo ip route add 10.244.1.0/24 via 192.168.122.11

# Verify
ip route | grep 10.244
# Should now show:
# 10.244.0.0/24 dev cnio0 ...
# 10.244.1.0/24 via 192.168.122.11 ...
```

### Step 2: On nodes-1

```bash
ssh nodes-1
sudo ip route add 10.244.0.0/24 via 192.168.122.10

# Verify
ip route | grep 10.244
# Should now show:
# 10.244.0.0/24 via 192.168.122.10 ...
# 10.244.1.0/24 dev cnio0 ...
```

---

## Part 3: Verify Cross-Node Pod Traffic Works

```bash
ssh controlplane-1

N1_IP=$(kubectl get pod busybox-n1 -o jsonpath='{.status.podIP}')
N2_IP=$(kubectl get pod busybox-n2 -o jsonpath='{.status.podIP}')

# Both should now succeed
kubectl exec busybox-n1 -- ping -c 2 "$N2_IP"
kubectl exec busybox-n2 -- ping -c 2 "$N1_IP"
```

Both pings should succeed.

---

## Part 4: Make the Routes Persistent

`ip route add` is in-memory only. The routes vanish on reboot. The cleanest way to persist them is via systemd-networkd, since the bridge interfaces are already managed there. Run the appropriate snippet on each node.

### On controlplane-1

```bash
ssh controlplane-1

# Add a [Route] block to the netplan-managed config, or write a systemd-networkd
# drop-in. Ubuntu 24.04 cloud images use netplan, so add it there.

sudo tee -a /etc/netplan/01-static.yaml > /dev/null <<'EOF'
        # Cross-node pod CIDR route (added in 06-manual-pod-routing.md)
        # Note: this assumes the existing netplan structure already has
        # this section under network.ethernets.<iface>.routes
EOF

# Cleaner: write a systemd-networkd drop-in directly
sudo mkdir -p /etc/systemd/network/10-enp0s2.network.d
sudo tee /etc/systemd/network/10-enp0s2.network.d/pod-routes.conf > /dev/null <<'EOF'
[Route]
Gateway=192.168.122.11
Destination=10.244.1.0/24
EOF
```

### On nodes-1

```bash
ssh nodes-1

sudo mkdir -p /etc/systemd/network/10-enp0s2.network.d
sudo tee /etc/systemd/network/10-enp0s2.network.d/pod-routes.conf > /dev/null <<'EOF'
[Route]
Gateway=192.168.122.10
Destination=10.244.0.0/24
EOF
```

systemd-networkd reads drop-in files from `<unit>.d/` directories. The exact unit name (`10-enp0s2.network`) depends on what cloud-init wrote during VM provisioning. Verify with:

```bash
ls /etc/systemd/network/
# You should see something like 50-cloud-init.network or 10-enp0s2.network
```

If the existing file has a different name, adjust the directory name in the commands above to match. The `.d/` suffix is what matters.

### Apply

On both nodes:

```bash
sudo systemctl restart systemd-networkd
ip route | grep 10.244
```

Both routes should be present after restart.

### Reboot Test (Optional)

The most reliable way to confirm persistence is to actually reboot the VMs and verify the routes come back:

```bash
# From the host
~/cka-lab/two-systemd/stop-cluster.sh
~/cka-lab/two-systemd/start-cluster.sh

# After both nodes are back up
ssh controlplane-1 'ip route | grep 10.244'
ssh nodes-1 'ip route | grep 10.244'

# Cross-node pod ping (recreate pods if you cleaned them up)
```

---

## Part 5: Service Resolution Across Nodes

Now that pod-to-pod cross-node traffic works, Service IPs should also work. kube-proxy programs iptables rules on each node that DNAT a Service ClusterIP to a backend pod IP. With routes in place, the resulting traffic follows the same path you just verified.

```bash
ssh controlplane-1

# Deployment + Service
kubectl create deployment web --image=nginx:1.27 --replicas=2
kubectl wait --for=condition=Available deployment/web --timeout=60s
kubectl expose deployment web --port=80

# Where did the replicas land?
kubectl get pods -l app=web -o wide

# Run a client pod, anywhere
kubectl run client --image=busybox:1.36 --restart=Never --command -- sleep 600
kubectl wait --for=condition=Ready pod/client --timeout=60s

# Client should reach the Service ClusterIP, which sometimes resolves to a pod
# on the same node and sometimes to a pod on the other node
for i in 1 2 3 4 5; do
  kubectl exec client -- wget -qO- --timeout=3 http://web | head -1
done

# Cleanup
kubectl delete deployment web
kubectl delete service web
kubectl delete pod client busybox-n1 busybox-n2
```

If some `wget` calls succeed and some fail, the per-node routing is asymmetric (one direction works, the other does not). Double-check the routes on both nodes.

If all `wget` calls succeed, the cluster networking is fully functional.

---

## Part 6: NodePort Access from the Host

`NodePort` Services should be reachable from the host through either node's bridge IP:

```bash
ssh controlplane-1

kubectl create deployment np-test --image=nginx:1.27
kubectl expose deployment np-test --port=80 --type=NodePort
NODEPORT=$(kubectl get svc np-test -o jsonpath='{.spec.ports[0].nodePort}')
echo "NodePort: $NODEPORT"
exit  # back to host

# From the host
curl http://192.168.122.10:${NODEPORT}/ | head -5
curl http://192.168.122.11:${NODEPORT}/ | head -5
# Both should return the nginx welcome page

# Cleanup (back on controlplane-1)
ssh controlplane-1 'kubectl delete deployment np-test && kubectl delete service np-test'
```

Both URLs should return content. kube-proxy programs each node to forward NodePort traffic to a backend pod, even if that pod is on the other node, which is exactly the case the manual routes enable.

---

## Summary

Cross-node pod traffic now works:

| Path | Mechanism |
|------|-----------|
| Pod on `controlplane-1` → pod on same node | bridge `cnio0` on `controlplane-1` |
| Pod on `nodes-1` → pod on same node | bridge `cnio0` on `nodes-1` |
| Pod on `controlplane-1` → pod on `nodes-1` | host route on `controlplane-1`: `10.244.1.0/24 via 192.168.122.11` |
| Pod on `nodes-1` → pod on `controlplane-1` | host route on `nodes-1`: `10.244.0.0/24 via 192.168.122.10` |
| Pod → Service ClusterIP | kube-proxy iptables DNAT, then one of the above paths |
| Pod → outside cluster | `ipMasq: true` in `/etc/cni/net.d/10-bridge.conf` (SNAT) |
| Host → NodePort | kube-proxy on either node accepts traffic, forwards to a pod |

The routing model is now complete. The next document installs CoreDNS and the optional cluster services on top.
