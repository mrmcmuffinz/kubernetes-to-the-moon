# Troubleshooting Runbook: Worker Components

This runbook covers diagnostic and repair procedures for the worker-side components running on the single-node cluster: containerd, kubelet, kube-proxy, and CNI networking.

---

## General Diagnostic Workflow

### Step 1: Check All Component Status

```bash
for svc in containerd kubelet kube-proxy; do
  printf "%-30s %s\n" "$svc" "$(systemctl is-active $svc)"
done
```

### Step 2: Check Node Status

```bash
kubectl get nodes -o wide
```

If the node shows `NotReady`, the problem is almost always kubelet or the container runtime. If the node shows `Ready` but pods are not working, the problem is likely CNI or kube-proxy.

### Step 3: Check Pod Status

```bash
kubectl get pods -A -o wide
```

Common status indicators:

- `Pending`: Scheduler cannot place the pod (resource limits, taints, affinity) or PVC not bound
- `ContainerCreating`: kubelet accepted the pod but containerd or CNI is failing
- `CrashLoopBackOff`: Container starts and immediately exits (application problem, not infrastructure)
- `ImagePullBackOff`: Cannot pull the container image (network, registry, image name)
- `Error`: Container exited with a non-zero exit code

---

## containerd

### What It Does

containerd is the container runtime daemon. It pulls images, creates containers, and manages their lifecycle. kubelet communicates with it through the Container Runtime Interface (CRI) over a Unix socket.

### Key Files

| File | Purpose |
|------|---------|
| `/etc/systemd/system/containerd.service` | systemd unit file |
| `/etc/containerd/config.toml` | containerd configuration |
| `/var/run/containerd/containerd.sock` | CRI socket (kubelet connects here) |
| `/usr/local/bin/runc` | Low-level container runtime |

### Health Check

```bash
# Quick version check (works even without Kubernetes configured)
sudo ctr version

# Full CRI info (confirms the socket is usable by kubelet)
sudo crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock info
```

### Common Failures

**containerd won't start, logs show "runc not found"**

The runc binary is missing or not in the expected path.

```bash
which runc
ls -la /usr/local/bin/runc

# Check what path containerd is configured to use
grep BinaryName /etc/containerd/config.toml
```

**containerd is stopped or disabled**

```bash
systemctl is-enabled containerd
# If disabled:
sudo systemctl enable containerd
sudo systemctl start containerd
```

**containerd is running but kubelet cannot connect**

The CRI socket does not exist or has wrong permissions.

```bash
ls -la /var/run/containerd/containerd.sock
# Should exist and be accessible

# Check what socket kubelet is configured to use
grep containerRuntimeEndpoint /var/lib/kubelet/kubelet-config.yaml
# Must match: unix:///var/run/containerd/containerd.sock
```

**containerd is running but containers fail with cgroup errors**

The cgroup driver mismatch between containerd and kubelet.

```bash
# Check containerd cgroup driver
grep SystemdCgroup /etc/containerd/config.toml
# Should be: SystemdCgroup = true

# Check kubelet cgroup driver
grep cgroupDriver /var/lib/kubelet/kubelet-config.yaml
# Should be: cgroupDriver: "systemd"

# Both must use the same driver
```

**Containers fail to start with "overlay" errors**

The overlay kernel module is not loaded.

```bash
lsmod | grep overlay
# If not loaded:
sudo modprobe overlay
```

### After Fixing

```bash
sudo systemctl daemon-reload
sudo systemctl restart containerd
# Then restart kubelet since it depends on containerd
sleep 2
sudo systemctl restart kubelet
```

---

## kubelet

### What It Does

kubelet is the node agent. It registers the node with the API server, watches for pod assignments, and tells containerd to create and manage containers. If kubelet is down, the node shows `NotReady` and no pods can be started, stopped, or monitored on this node.

### Key Files

| File | Purpose |
|------|---------|
| `/etc/systemd/system/kubelet.service` | systemd unit file |
| `/var/lib/kubelet/kubelet-config.yaml` | kubelet configuration |
| `/var/lib/kubelet/kubeconfig` | Kubeconfig for API server auth |
| `/var/lib/kubelet/controlplane-1.pem` | Node TLS certificate |
| `/var/lib/kubelet/controlplane-1-key.pem` | Node TLS private key |
| `/var/lib/kubernetes/ca.pem` | CA certificate |

### Health Check

```bash
# kubelet's own health endpoint (works even if the API server is down)
curl -sk http://127.0.0.1:10248/healthz

# Node registration status (requires API server)
kubectl get nodes
```

### Common Failures

**Node shows "NotReady"**

This is the most common kubelet problem indicator. Start with the logs:

```bash
journalctl -u kubelet --no-pager -n 100
```

The most frequent causes:

1. containerd is not running (kubelet cannot create containers)
2. CNI plugin is not configured (kubelet cannot set up pod networking)
3. kubelet cannot reach the API server (wrong kubeconfig server URL)

```bash
# Check containerd
systemctl is-active containerd

# Check CNI config exists
ls /etc/cni/net.d/

# Check API server connectivity
grep server /var/lib/kubelet/kubeconfig
curl -k https://127.0.0.1:6443/healthz
```

**kubelet won't start, logs show "failed to load kubelet config file"**

The config file path is wrong or the file does not exist.

```bash
systemctl cat kubelet | grep config
ls -la /var/lib/kubelet/kubelet-config.yaml
```

**kubelet won't start, logs show "failed to construct kubeconfig"**

The kubeconfig file is missing or malformed.

```bash
ls -la /var/lib/kubelet/kubeconfig
cat /var/lib/kubelet/kubeconfig
# Verify the file is valid YAML and has server, certificate-authority-data, etc.
```

**kubelet starts but cannot connect to the API server**

The server URL in the kubeconfig is wrong (pointing to the wrong IP or port).

```bash
grep server /var/lib/kubelet/kubeconfig
# Should be: https://127.0.0.1:6443

# Test connectivity directly
curl -k https://127.0.0.1:6443/healthz
```

**kubelet starts but node stays "NotReady" with CNI errors**

```bash
journalctl -u kubelet --no-pager | grep -i cni

# Check if CNI config files exist
ls /etc/cni/net.d/
# Should have 10-bridge.conf and 99-loopback.conf

# Check if CNI binaries exist
ls /opt/cni/bin/
# Should have bridge, loopback, host-local, and others
```

**kubelet starts but cannot use the container runtime**

The `containerRuntimeEndpoint` in the kubelet config does not match the actual containerd socket.

```bash
grep containerRuntimeEndpoint /var/lib/kubelet/kubelet-config.yaml
ls -la /var/run/containerd/containerd.sock
```

**kubelet certificate issues**

```bash
# Verify the node cert exists
ls -la /var/lib/kubelet/controlplane-1.pem /var/lib/kubelet/controlplane-1-key.pem

# Verify it was signed by the cluster CA
openssl verify -CAfile /var/lib/kubernetes/ca.pem /var/lib/kubelet/controlplane-1.pem

# Check the identity in the cert
openssl x509 -noout -subject -in /var/lib/kubelet/controlplane-1.pem
# Should show CN=system:node:controlplane-1, O=system:nodes
```

**Swap is enabled**

kubelet refuses to start if swap is active.

```bash
free -h | grep Swap
# Swap should show all zeros

# If swap is active:
sudo swapoff -a
sudo sed -i '/\sswap\s/s/^/#/' /etc/fstab
```

### After Fixing

```bash
sudo systemctl daemon-reload
sudo systemctl restart kubelet
# Wait for the node to re-register
sleep 10
kubectl get nodes
```

---

## kube-proxy

### What It Does

kube-proxy programs iptables rules on the node so that Kubernetes Service ClusterIPs and NodePorts route traffic to the correct pod endpoints. If kube-proxy is down, Services still resolve via DNS (CoreDNS handles that), but the actual traffic routing to backend pods breaks.

### Key Files

| File | Purpose |
|------|---------|
| `/etc/systemd/system/kube-proxy.service` | systemd unit file |
| `/var/lib/kube-proxy/kube-proxy-config.yaml` | kube-proxy configuration |
| `/var/lib/kube-proxy/kubeconfig` | Kubeconfig for API server auth |

### Health Check

```bash
systemctl status kube-proxy
```

Verify iptables rules are being programmed:

```bash
sudo iptables -t nat -L KUBE-SERVICES 2>/dev/null | head -20
# Should show rules for Kubernetes services
```

### Common Failures

**kube-proxy won't start, logs show kubeconfig errors**

```bash
systemctl cat kube-proxy | grep config
ls -la /var/lib/kube-proxy/kube-proxy-config.yaml
ls -la /var/lib/kube-proxy/kubeconfig
```

**kube-proxy runs but Services are not reachable**

Check if kube-proxy is actually programming iptables rules:

```bash
sudo iptables -t nat -L KUBE-SERVICES 2>/dev/null | wc -l
# Should be more than 2 lines (header + at least the kubernetes service)

# If empty, kube-proxy might not be connecting to the API server
journalctl -u kube-proxy --no-pager -n 50 | grep -i error
```

**Cluster CIDR mismatch**

The `clusterCIDR` in the kube-proxy config must match the controller-manager's `--cluster-cidr`.

```bash
grep clusterCIDR /var/lib/kube-proxy/kube-proxy-config.yaml
# Should be: 10.244.0.0/16

systemctl cat kube-controller-manager | grep cluster-cidr
# Should also be: 10.244.0.0/16
```

### After Fixing

```bash
sudo systemctl daemon-reload
sudo systemctl restart kube-proxy
```

---

## CNI (Container Network Interface)

### What It Does

CNI plugins configure pod networking. When kubelet creates a pod, it calls the CNI plugins to set up a virtual network interface inside the pod, assign it an IP address, and connect it to the node's network bridge. Without CNI, pods cannot get IP addresses and the node shows as `NotReady`.

### Key Files

| File | Purpose |
|------|---------|
| `/etc/cni/net.d/10-bridge.conf` | Bridge CNI configuration |
| `/etc/cni/net.d/99-loopback.conf` | Loopback CNI configuration |
| `/opt/cni/bin/` | CNI plugin binaries |

### Common Failures

**Node is "NotReady" and kubelet logs mention CNI**

```bash
journalctl -u kubelet --no-pager | grep -i "cni\|network"

# Check if config files exist
ls -la /etc/cni/net.d/
# Should have 10-bridge.conf and 99-loopback.conf

# Check if binaries exist
ls /opt/cni/bin/ | grep -E 'bridge|loopback|host-local'
```

**Pods stuck in "ContainerCreating" with network errors**

```bash
kubectl describe pod <pod-name> | grep -A 5 "Warning\|Error"

# Common cause: CNI config references a binary that is not in /opt/cni/bin/
cat /etc/cni/net.d/10-bridge.conf
# Check the "type" field and verify that binary exists in /opt/cni/bin/
```

**Pods get IP addresses but cannot communicate**

Check if the bridge interface exists and has the expected IP:

```bash
ip addr show cnio0
# Should exist with an IP in the pod CIDR range

# Check if IP forwarding is enabled
sysctl net.ipv4.ip_forward
# Should be 1

# Check bridge netfilter
sysctl net.bridge.bridge-nf-call-iptables
# Should be 1
```

If the bridge interface does not exist, restart kubelet to trigger CNI setup:

```bash
sudo systemctl restart kubelet
```

**Pod CIDR mismatch**

The subnet in the CNI config must match the `--cluster-cidr` from the controller-manager.

```bash
grep subnet /etc/cni/net.d/10-bridge.conf
# Should be: 10.244.0.0/16
```

### After Fixing CNI

CNI changes take effect on new pods, not existing ones. After fixing the configuration:

```bash
sudo systemctl restart kubelet

# Delete and recreate any pods that were stuck
kubectl delete pod <pod-name>
```

---

## Quick Diagnostic Reference

A compact checklist for rapid triage:

```bash
# 1. Are all services running?
for svc in etcd kube-apiserver kube-controller-manager kube-scheduler containerd kubelet kube-proxy; do
  printf "%-30s %s\n" "$svc" "$(systemctl is-active $svc)"
done

# 2. Is the API server reachable?
curl -k https://127.0.0.1:6443/healthz

# 3. Is the node registered and ready?
kubectl get nodes -o wide

# 4. Are system pods running?
kubectl get pods -n kube-system

# 5. Is DNS working?
kubectl run dnstest --image=busybox --rm -it --restart=Never -- nslookup kubernetes.default

# 6. Can pods get IP addresses?
kubectl run nettest --image=busybox --rm -it --restart=Never -- ip addr

# 7. Is swap off?
free -h | grep Swap

# 8. Are kernel modules loaded?
lsmod | grep -E 'br_netfilter|overlay'

# 9. Are sysctl parameters set?
sysctl net.ipv4.ip_forward net.bridge.bridge-nf-call-iptables
```
