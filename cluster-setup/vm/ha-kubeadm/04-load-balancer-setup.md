# Load Balancer Verification

**Purpose:** Confirm that the HAProxy load balancer installed in document 01 is working
correctly before running `kubeadm init`. The VIP (`192.168.100.100:6443`) must be
reachable from the host, and HAProxy must forward to the control plane API servers once
they are up.

---

## Prerequisites

- HAProxy is installed and running on the host (document 01).
- `controlplane-1` is up but `kubeadm init` has not run yet.

## Part 1: Verify HAProxy is Listening

On the host:

```bash
sudo ss -tlnp | grep 6443
# Expected: haproxy listening on 192.168.100.100:6443

sudo haproxy -c -f /etc/haproxy/haproxy.cfg
# Expected: Configuration file is valid
```

## Part 2: Understand the Pre-Init State

Before `kubeadm init` runs, neither control plane has an API server. HAProxy health
checks to `192.168.100.20:6443` and `192.168.100.21:6443` will fail (connection
refused). This is expected.

A connection attempt to the VIP at this stage:

```bash
curl -sk --connect-timeout 3 https://192.168.100.100:6443/healthz || echo "VIP not yet serving (expected before init)"
```

HAProxy keeps the frontend bound even with all backends down, so the TCP connection
reaches HAProxy and is refused at the application level.

## Part 3: Post-Init Verification (Run After Document 05)

After `kubeadm init` completes on `controlplane-1`, verify that the VIP serves traffic:

```bash
# Retry for up to 60 seconds
for i in {1..12}; do
  curl -sk --connect-timeout 3 https://192.168.100.100:6443/healthz && echo "" && break
  echo "Waiting for API via VIP... ($i/12)"
  sleep 5
done
```

Expected response: `ok`

## Part 4: View HAProxy Stats

The stats page is available on the host:

```bash
curl -su admin:admin http://192.168.100.1:9000/stats | grep -E "controlplane|Status"
```

Or open `http://192.168.100.1:9000/stats` in a browser on the host. After
`controlplane-1`'s API server starts, it should show `UP`. `controlplane-2` will be
`DOWN` until document 07.

## Part 5: Test VIP Failover (After Both Control Planes are Up)

After completing document 07, test that the VIP survives losing one control plane:

```bash
# Stop controlplane-1 (from the host)
~/cka-lab/ha-kubeadm/controlplane-1/stop-controlplane-1.sh

# Wait for HAProxy health checks to detect the failure (up to 10 seconds)
sleep 12

# The VIP should still respond (now routing to controlplane-2)
curl -sk https://192.168.100.100:6443/healthz
# Expected: ok

# kubectl should still work
KUBECONFIG=~/cka-lab/ha-kubeadm/admin.conf kubectl get nodes

# Restart controlplane-1
~/cka-lab/ha-kubeadm/controlplane-1/start-controlplane-1.sh
```

**Result:** HAProxy is running with the VIP on `192.168.100.100:6443`. After kubeadm
init (document 05), all kubeconfigs and worker join commands will use this address.

---

← [Previous: Node Prerequisites: Five Nodes](03-node-prerequisites.md) | [Next: First Control Plane Initialization →](05-control-plane-init.md)
