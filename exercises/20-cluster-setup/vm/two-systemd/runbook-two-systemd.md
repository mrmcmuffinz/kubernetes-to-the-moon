# Troubleshooting Runbook: Two-Node systemd Cluster

This runbook covers diagnostic and repair procedures specific to the two-node, from-scratch, systemd-managed cluster: bridge networking issues, per-node certificate problems, cross-node pod routing failures, and the multi-node version of every problem the single-node guide already covered.

For host-side QEMU and bridge issues, see the document 01 (`01-host-bridge-setup.md`) of this guide for the original setup, and the analogous sections in `single-systemd/runbook-qemu-vm.md` for low-level KVM troubleshooting (the QEMU layer is the same).

For the underlying systemd component diagnostics (etcd, apiserver, controller-manager, scheduler, kubelet, kube-proxy), the principles in `single-systemd/runbook-control-plane.md` and `single-systemd/runbook-worker-components.md` still apply unchanged because the components themselves are the same.

---

## Quick Diagnostic Reference

Run these from `controlplane-1`:

```bash
# 1. Both nodes registered and Ready
kubectl get nodes -o wide

# 2. Pod CIDRs assigned correctly
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'

# 3. Routing table on each node
ssh controlplane-1 'ip route | grep 10.244'
ssh nodes-1 'ip route | grep 10.244'

# 4. Control plane health (controlplane-1 only)
ssh controlplane-1 'systemctl is-active etcd kube-apiserver kube-controller-manager kube-scheduler'

# 5. Worker health (both)
ssh controlplane-1 'systemctl is-active containerd kubelet kube-proxy'
ssh nodes-1 'systemctl is-active containerd kubelet kube-proxy'

# 6. Cross-node ping
N1_POD=$(kubectl run --rm -i --restart=Never --image=busybox:1.36 ping-test --overrides='{"spec":{"nodeName":"nodes-1"}}' -- sh -c 'hostname -i')
echo "Reached nodes-1 pod: $N1_POD"
```

---

## Routing Problems

### Cross-Node Pod Traffic Suddenly Stops Working

If pods on the same node still talk to each other but cross-node pings fail, the host route is missing. This commonly happens after a VM reboot if the persistence step in `06-manual-pod-routing.md` was skipped or used the wrong systemd-networkd unit name.

```bash
ssh controlplane-1 'ip route | grep "10.244.1"'
ssh nodes-1 'ip route | grep "10.244.0"'
```

If either is missing, re-add manually:

```bash
ssh controlplane-1 'sudo ip route add 10.244.1.0/24 via 192.168.122.11'
ssh nodes-1 'sudo ip route add 10.244.0.0/24 via 192.168.122.10'
```

Then fix persistence. Check that the systemd-networkd drop-in actually applies:

```bash
ssh controlplane-1 'ls /etc/systemd/network/'
ssh controlplane-1 'sudo networkctl status enp0s2 | grep -A5 Route'
```

If the drop-in directory name does not match the actual network unit, the route file is being ignored. Adjust the directory name to match.

### Pod Gets an IP from the Wrong CIDR

Pod on `nodes-1` shows up with an IP in `10.244.0.0/24`:

```bash
kubectl get pods -A -o wide | awk '$8 == "nodes-1"' | head
# look for any IP not in 10.244.1.x
```

This means `/etc/cni/net.d/10-bridge.conf` on `nodes-1` references the wrong subnet. Fix the file (it should be `10.244.1.0/24`), then delete the affected pods so they get rescheduled:

```bash
ssh nodes-1 'cat /etc/cni/net.d/10-bridge.conf | grep subnet'

# Delete and let kubelet recreate (deployments only)
kubectl delete pod <name>
```

For host-local IPAM, the in-memory state lives in `/var/lib/cni/networks/bridge/` on each node. If a node's CNI config was changed, clearing this cache may help:

```bash
ssh nodes-1 'sudo rm -rf /var/lib/cni/networks/bridge/*'
ssh nodes-1 'sudo systemctl restart kubelet'
```

### controller-manager Does Not Assign a CIDR to a Newly-Joined Node

`kubectl describe node nodeN` shows no `PodCIDR`:

```bash
kubectl describe node nodes-1 | grep -i podcidr
```

Check that controller-manager has the right flags:

```bash
ssh controlplane-1 'sudo grep -E "allocate-node-cidrs|cluster-cidr|node-cidr-mask" /etc/systemd/system/kube-controller-manager.service'
```

All three must be present:
- `--allocate-node-cidrs=true`
- `--cluster-cidr=10.244.0.0/16`
- `--node-cidr-mask-size=24`

Restart if you changed anything:

```bash
ssh controlplane-1 'sudo systemctl daemon-reload && sudo systemctl restart kube-controller-manager'
```

---

## Certificate Problems

### nodes-1 kubelet Logs: "Unauthorized"

```bash
ssh nodes-1 'sudo journalctl -u kubelet -n 30 | grep -i unauthorized'
```

The kubelet's client cert is being rejected. Common causes:

1. **CN mismatch.** The cert CN must be `system:node:nodes-1`, not `nodes-1` or `kubelet`. Check:
   ```bash
   ssh nodes-1 'sudo openssl x509 -in /var/lib/kubelet/nodes-1.pem -noout -subject'
   # Should show: subject=CN = system:node:nodes-1, O = system:nodes
   ```

2. **CA on `nodes-1` differs from CA the apiserver trusts.** Compare:
   ```bash
   ssh controlplane-1 'sudo sha256sum /etc/etcd/ca.pem /var/lib/kubernetes/ca.pem'
   ssh nodes-1 'sudo sha256sum /var/lib/kubernetes/ca.pem ~/auth/ca.pem'
   ```
   All hashes must match. If they do not, re-copy the CA from `controlplane-1` to `nodes-1`.

### apiserver Logs: "x509: certificate is valid for X, not Y"

```bash
ssh controlplane-1 'sudo journalctl -u kube-apiserver -n 30 | grep -i x509'
```

The apiserver cert's SAN list does not include the IP something is connecting on. Check the SANs:

```bash
ssh controlplane-1 'sudo openssl x509 -in /var/lib/kubernetes/kubernetes.pem -noout -text | grep -A2 "Subject Alternative Name"'
```

You should see at minimum:
- `DNS:kubernetes`, `DNS:kubernetes.default`, `...`
- `DNS:controlplane-1`, `DNS:nodes-1`
- `IP Address:10.96.0.1`
- `IP Address:192.168.122.10`, `IP Address:192.168.122.11`
- `IP Address:127.0.0.1`

If a needed entry is missing, you have to regenerate the cert (re-run document 03 from Step 1 of Part 3) and restart kube-apiserver.

### nodes-1 Stuck "NotReady" After Join

```bash
kubectl describe node nodes-1 | grep -A5 Conditions
```

If the message is "container runtime not ready: NetworkPluginNotReady", the CNI config or binaries are missing on `nodes-1`:

```bash
ssh nodes-1 'sudo ls /etc/cni/net.d/'
ssh nodes-1 'sudo ls /opt/cni/bin/'
```

Both must be populated. See document 05 Parts 1 and 3.

---

## Control Plane Problems (Same as Single-Node)

The control plane runs on `controlplane-1` only. The diagnostic flow is identical to `single-systemd/runbook-control-plane.md`. Quick reference:

```bash
ssh controlplane-1
sudo systemctl status etcd kube-apiserver kube-controller-manager kube-scheduler --no-pager | head -40
sudo journalctl -u kube-apiserver -n 50 --no-pager
```

If etcd is healthy but apiserver is failing, it is almost always one of:

1. Encryption config file missing or unreadable
2. Wrong path to a cert in the systemd unit
3. etcd endpoint URL wrong in `--etcd-servers`
4. Cert SAN missing the IP that something is connecting on

---

## etcd Backup and Restore (Two-Node Specific)

Same `etcdctl` commands as single-node, but you can practice the "what if I have to restore on a different node" scenario:

### Backup (from controlplane-1)

```bash
ssh controlplane-1
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

### Restore (still on controlplane-1)

```bash
# Stop the apiserver so it does not write while we are restoring
sudo systemctl stop kube-apiserver

# Stop etcd
sudo systemctl stop etcd

# Move old data, restore from snapshot
sudo mv /var/lib/etcd /var/lib/etcd.old
sudo ETCDCTL_API=3 etcdctl snapshot restore /tmp/etcd-backup.db --data-dir /var/lib/etcd
sudo chown -R etcd:etcd /var/lib/etcd 2>/dev/null || true

# Start
sudo systemctl start etcd
sleep 2
sudo systemctl start kube-apiserver

# Verify
kubectl get nodes
```

### Restore on nodes-1 (Disaster Drill)

If `controlplane-1`'s VM disk dies, you would have to re-bootstrap the entire control plane on `nodes-1`. That is out of scope for the runbook (it is essentially "redo documents 03 and 04 with `nodes-1` everywhere") but is good practice for the CKA mindset.

---

## CoreDNS Problems

### DNS Lookups Time Out from One Node Only

If pods on `controlplane-1` can resolve names but pods on `nodes-1` cannot (or vice versa):

1. Both CoreDNS replicas might be on the same node. Check:
   ```bash
   kubectl -n kube-system get pods -l k8s-app=coredns -o wide
   ```
   If both are on `controlplane-1`, traffic from `nodes-1` pods has to cross the bridge to reach a CoreDNS pod, which requires the routes from document 06.

2. If routes look fine, test from a `nodes-1` pod directly:
   ```bash
   kubectl run dns-test --image=busybox:1.36 --restart=Never \
     --overrides='{"spec":{"nodeName":"nodes-1"}}' -- sleep 600
   kubectl wait --for=condition=Ready pod/dns-test --timeout=60s
   kubectl exec dns-test -- nslookup kubernetes.default.svc.cluster.local
   kubectl exec dns-test -- ping -c 1 -W 2 10.96.0.10
   kubectl delete pod dns-test
   ```
   If `nslookup` fails but `ping 10.96.0.10` succeeds, kube-proxy DNAT is fine but CoreDNS itself is unhappy. Check CoreDNS pod logs.

---

## kube-proxy Problems

### Service IPs Work from controlplane-1 But Not nodes-1

```bash
ssh nodes-1
sudo iptables-save | grep KUBE-SERVICES | head -10
```

If the output is empty, kube-proxy on `nodes-1` is not running or not programming iptables.

```bash
ssh nodes-1 'sudo systemctl status kube-proxy --no-pager'
ssh nodes-1 'sudo journalctl -u kube-proxy -n 30 --no-pager'
```

Common kube-proxy issue: clusterCIDR mismatch.

```bash
ssh nodes-1 'cat /var/lib/kube-proxy/kube-proxy-config.yaml | grep clusterCIDR'
# should be 10.244.0.0/16, not a /24
```

---

## Full Cluster Reset

If everything is broken and you want a clean slate without rebuilding the VMs:

### Stop Everything

```bash
# Both nodes
ssh controlplane-1 'sudo systemctl stop kubelet kube-proxy containerd kube-scheduler kube-controller-manager kube-apiserver etcd 2>/dev/null'
ssh nodes-1 'sudo systemctl stop kubelet kube-proxy containerd 2>/dev/null'
```

### Wipe State

```bash
# Both nodes
for node in controlplane-1 nodes-1; do
  ssh $node 'sudo rm -rf /var/lib/kubelet/* /var/lib/kube-proxy/* /var/lib/cni/* /etc/cni/net.d/*'
done

# Just controlplane-1
ssh controlplane-1 'sudo rm -rf /var/lib/etcd /var/lib/kubernetes/* ~/.kube ~/auth'
```

### Re-Run from Document 03

You will need to regenerate certs and reinstall everything. This takes 30 to 60 minutes from a clean wipe.

For an even cleaner reset, delete the VMs entirely and re-run document 02. Cloud-init reruns from scratch, the qcow2 disks are recreated empty, and you are guaranteed no leftover state.

---

## Path Reference

Same paths as the single-systemd guide, plus the per-node specifics:

| File | controlplane-1 | nodes-1 |
|------|-------|-------|
| CA cert and key | `/etc/etcd/ca.pem`, `~/auth/ca-key.pem` | `/var/lib/kubernetes/ca.pem`, `~/auth/ca-key.pem` |
| etcd cert | `/etc/etcd/kubernetes.pem` | n/a |
| apiserver cert | `/var/lib/kubernetes/kubernetes.pem` | n/a |
| kubelet cert | `/var/lib/kubelet/controlplane-1.pem` | `/var/lib/kubelet/nodes-1.pem` |
| kubelet kubeconfig | `/var/lib/kubelet/kubeconfig` (uses `controlplane-1`) | `/var/lib/kubelet/kubeconfig` (uses `nodes-1`) |
| kube-proxy cert | `~/auth/kube-proxy.pem` (shared) | `~/auth/kube-proxy.pem` (shared) |
| kube-proxy kubeconfig | `/var/lib/kube-proxy/kubeconfig` (shared) | `/var/lib/kube-proxy/kubeconfig` (shared) |
| CNI bridge config | `/etc/cni/net.d/10-bridge.conf` (10.244.0.0/24) | `/etc/cni/net.d/10-bridge.conf` (10.244.1.0/24) |
| Pod route persistence | `/etc/systemd/network/<unit>.d/pod-routes.conf` | `/etc/systemd/network/<unit>.d/pod-routes.conf` |
