# Troubleshooting Runbook: Control Plane Components

This runbook covers diagnostic and repair procedures for the four control plane components running as systemd services on the single-node cluster: etcd, kube-apiserver, kube-controller-manager, and kube-scheduler.

---

## General Diagnostic Workflow

Before diving into a specific component, follow this triage sequence to identify which component is broken and narrow down the failure category.

### Step 1: Check All Component Status

```bash
for svc in etcd kube-apiserver kube-controller-manager kube-scheduler; do
  printf "%-30s %s\n" "$svc" "$(systemctl is-active $svc)"
done
```

Any service showing `inactive`, `failed`, or `activating` is the starting point.

### Step 2: Read the Logs

```bash
journalctl -u <service-name> --no-pager -n 50
```

For the most recent failure:

```bash
journalctl -u <service-name> --no-pager -n 50 -p err
```

For a live stream while you restart the service:

```bash
journalctl -u <service-name> -f &
sudo systemctl restart <service-name>
```

### Step 3: Identify the Failure Category

Most control plane failures fall into one of these buckets:

- **Service won't start:** Binary missing, bad flag, missing config file, wrong file path
- **Service starts but crashes immediately:** Certificate issue, port conflict, permission denied
- **Service runs but is unhealthy:** Wrong endpoint, mismatched configuration, connectivity to another component failed
- **Service runs but behaves incorrectly:** Wrong CIDR, wrong authorization mode, mismatched flags between components

### Step 4: Inspect the Unit File

```bash
systemctl cat <service-name>
```

This shows the full systemd unit file with all `ExecStart` flags. Compare what you see against what you expect.

---

## etcd

### What It Does

etcd is the cluster state database. Every Kubernetes object (pods, services, secrets, configmaps) is stored here. If etcd is down, the API server cannot read or write any cluster state. Nothing works without etcd.

### Key Files

| File | Purpose |
|------|---------|
| `/etc/systemd/system/etcd.service` | systemd unit file |
| `/var/lib/etcd/` | Data directory |
| `/etc/etcd/ca.pem` | CA certificate for TLS |
| `/etc/etcd/kubernetes.pem` | Server/client certificate |
| `/etc/etcd/kubernetes-key.pem` | Server/client private key |

### Health Check

```bash
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

### Common Failures

**etcd refuses to start, logs show "data-dir not found" or "permission denied"**

The data directory path in the unit file is wrong, does not exist, or has incorrect permissions.

```bash
# Check what data-dir is configured
systemctl cat etcd | grep data-dir

# Verify the directory exists and has correct permissions
ls -la /var/lib/etcd/
# Should be drwx------ owned by root

# Fix if needed
sudo mkdir -p /var/lib/etcd
sudo chmod 700 /var/lib/etcd
```

**etcd refuses to start, logs show certificate errors**

The cert files referenced in the unit file are missing, have wrong paths, or the cert does not match the key.

```bash
# Check which cert files are configured
systemctl cat etcd | grep -E 'cert-file|key-file|ca-file'

# Verify each file exists
ls -la /etc/etcd/*.pem

# Verify cert matches key
openssl x509 -noout -modulus -in /etc/etcd/kubernetes.pem | md5sum
openssl rsa -noout -modulus -in /etc/etcd/kubernetes-key.pem | md5sum
# Both md5sums must match
```

**etcd starts but API server cannot connect, logs show "connection refused"**

The listen-client-urls in the etcd unit file do not include the address the API server is trying to reach.

```bash
# Check what etcd is listening on
systemctl cat etcd | grep listen-client-urls
sudo ss -tlnp | grep 2379

# The listen-client-urls must include both 127.0.0.1 and the VM IP
# Example: https://10.0.2.15:2379,https://127.0.0.1:2379
```

**etcd starts but API server gets TLS errors**

The API server is connecting with `https://` but etcd is listening on `http://`, or vice versa.

```bash
# Check etcd listen URL scheme
systemctl cat etcd | grep listen-client-urls

# Check API server etcd connection
systemctl cat kube-apiserver | grep etcd-servers

# Both must use the same scheme (https)
```

### After Fixing

```bash
sudo systemctl daemon-reload
sudo systemctl restart etcd
systemctl status etcd
```

Wait a few seconds, then restart the API server since it depends on etcd:

```bash
sudo systemctl restart kube-apiserver
```

---

## kube-apiserver

### What It Does

The API server is the central hub of the cluster. Every component talks to it: kubectl, kubelet, controller-manager, scheduler, kube-proxy. If the API server is down, `kubectl` commands fail, no new pods are scheduled, and no controllers run.

### Key Files

| File | Purpose |
|------|---------|
| `/etc/systemd/system/kube-apiserver.service` | systemd unit file |
| `/var/lib/kubernetes/ca.pem` | CA certificate |
| `/var/lib/kubernetes/ca-key.pem` | CA private key |
| `/var/lib/kubernetes/kubernetes.pem` | API server TLS cert |
| `/var/lib/kubernetes/kubernetes-key.pem` | API server TLS key |
| `/var/lib/kubernetes/service-account.pem` | ServiceAccount signing cert |
| `/var/lib/kubernetes/service-account-key.pem` | ServiceAccount signing key |
| `/var/lib/kubernetes/encryption-config.yaml` | Encryption config for Secrets at rest |

### Health Check

```bash
# From inside the VM
curl -k https://127.0.0.1:6443/healthz

# With CA verification
curl --cacert /var/lib/kubernetes/ca.pem https://127.0.0.1:6443/healthz

# From the QEMU host (through port forwarding)
curl -k https://127.0.0.1:6443/healthz
```

### Common Failures

**API server won't start, logs show "bind: address already in use"**

Another process is already listening on port 6443, or a previous API server instance did not shut down cleanly.

```bash
sudo ss -tlnp | grep 6443
# If something is there, kill it or wait for it to exit
```

**API server won't start, logs show "open /var/lib/kubernetes/missing.pem: no such file"**

A certificate or key file path in the unit file is wrong.

```bash
# List all file references in the unit file
systemctl cat kube-apiserver | grep -E 'file=|config='

# Verify each file exists
ls -la /var/lib/kubernetes/*.pem
ls -la /var/lib/kubernetes/encryption-config.yaml
```

**API server starts but kubectl returns "connection refused"**

The API server might be binding to a specific IP instead of all interfaces, or it crashed after startup.

```bash
# Check what address it binds to
systemctl cat kube-apiserver | grep bind-address
# Should be 0.0.0.0 for the single-node setup

# Check if it is actually listening
sudo ss -tlnp | grep 6443

# If not listening, check logs for crash reason
journalctl -u kube-apiserver --no-pager -n 50
```

**API server starts but kubectl returns "Forbidden"**

The authorization mode is set to something other than `Node,RBAC`, or the client certificate does not have the expected CN/O fields.

```bash
# Check authorization mode
systemctl cat kube-apiserver | grep authorization-mode
# Should be: --authorization-mode=Node,RBAC

# Verify your admin cert has the right identity
openssl x509 -noout -subject -in ~/auth/admin.pem
# Should show CN=admin, O=system:masters
```

**API server starts but cannot connect to etcd**

```bash
# Check what etcd endpoint the API server is configured to use
systemctl cat kube-apiserver | grep etcd-servers

# Verify etcd is actually listening on that endpoint
sudo ss -tlnp | grep 2379

# Verify etcd is healthy
sudo ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

**API server starts but admission controllers block everything**

If `AlwaysDeny` is in the admission plugins list, all API requests will be rejected.

```bash
systemctl cat kube-apiserver | grep enable-admission-plugins
# Look for AlwaysDeny or other unexpected plugins
```

**Service CIDR mismatch causes DNS or internal service failures**

The `--service-cluster-ip-range` must be `10.96.0.0/16` to match the rest of the cluster configuration. If it is different, CoreDNS and the `kubernetes` ClusterIP service will not work.

```bash
systemctl cat kube-apiserver | grep service-cluster-ip-range
```

### After Fixing

```bash
sudo systemctl daemon-reload
sudo systemctl restart kube-apiserver
curl -k https://127.0.0.1:6443/healthz
```

---

## kube-controller-manager

### What It Does

The controller-manager runs reconciliation loops: it watches the desired state in the API server and takes action to make the actual state match. If it is down, deployments will not scale, failed pods will not be replaced, endpoints will not update, and certificate signing requests will not be processed.

### Key Files

| File | Purpose |
|------|---------|
| `/etc/systemd/system/kube-controller-manager.service` | systemd unit file |
| `/var/lib/kubernetes/kube-controller-manager.kubeconfig` | Kubeconfig for API server auth |
| `/var/lib/kubernetes/ca.pem` | CA cert (for cluster signing) |
| `/var/lib/kubernetes/ca-key.pem` | CA key (for cluster signing) |
| `/var/lib/kubernetes/service-account-key.pem` | ServiceAccount signing key |

### Health Check

```bash
curl -k https://127.0.0.1:10257/healthz
```

### Common Failures

**Controller-manager won't start, logs show "failed to read kubeconfig"**

The kubeconfig path in the unit file is wrong or the file does not exist.

```bash
systemctl cat kube-controller-manager | grep kubeconfig
ls -la /var/lib/kubernetes/kube-controller-manager.kubeconfig
```

**Controller-manager starts but cannot reach the API server**

The kubeconfig file contains the wrong server URL, or the API server is down.

```bash
# Check the server URL in the kubeconfig
grep server /var/lib/kubernetes/kube-controller-manager.kubeconfig
# Should be https://127.0.0.1:6443

# Verify API server is up
curl -k https://127.0.0.1:6443/healthz
```

**Controller-manager runs but pods are not being scheduled or reconciled**

The controller-manager might be running but in a degraded state. Check for errors in the logs:

```bash
journalctl -u kube-controller-manager --no-pager -n 100 | grep -i error
```

Common causes: wrong `--cluster-cidr` (must match `10.244.0.0/16`), wrong `--service-cluster-ip-range` (must match `10.96.0.0/16`), or missing signing key files.

```bash
systemctl cat kube-controller-manager | grep -E 'cluster-cidr|service-cluster-ip|signing'
```

### After Fixing

```bash
sudo systemctl daemon-reload
sudo systemctl restart kube-controller-manager
curl -k https://127.0.0.1:10257/healthz
```

---

## kube-scheduler

### What It Does

The scheduler watches for newly created pods that have no node assignment and selects a node for them to run on. If the scheduler is down, new pods will stay in `Pending` state indefinitely.

### Key Files

| File | Purpose |
|------|---------|
| `/etc/systemd/system/kube-scheduler.service` | systemd unit file |
| `/etc/kubernetes/config/kube-scheduler.yaml` | Scheduler configuration |
| `/var/lib/kubernetes/kube-scheduler.kubeconfig` | Kubeconfig for API server auth |

### Health Check

```bash
curl -k https://127.0.0.1:10259/healthz
```

### Diagnosing Scheduler Problems Without the Scheduler Being Down

If the scheduler is running but pods are stuck in `Pending`:

```bash
# Check pod events
kubectl describe pod <pod-name> | grep -A 10 Events

# Common reasons:
# - Insufficient resources (CPU/memory requests exceed node capacity)
# - Taints on the node with no matching tolerations
# - Node selector or affinity rules that no node satisfies
# - PVC bound to a volume on a different node
```

### Common Failures

**Scheduler won't start, logs show "no such file or directory" for config**

The `--config` flag points to a file that does not exist.

```bash
systemctl cat kube-scheduler | grep config
ls -la /etc/kubernetes/config/kube-scheduler.yaml
```

**Scheduler won't start, logs show kubeconfig errors**

The scheduler config YAML references a kubeconfig that does not exist or has a wrong path.

```bash
cat /etc/kubernetes/config/kube-scheduler.yaml
# Check the kubeconfig path inside this file
ls -la /var/lib/kubernetes/kube-scheduler.kubeconfig
```

**Scheduler runs but cannot reach the API server**

Same diagnostic as the controller-manager: check the server URL in the kubeconfig.

```bash
grep server /var/lib/kubernetes/kube-scheduler.kubeconfig
curl -k https://127.0.0.1:6443/healthz
```

### After Fixing

```bash
sudo systemctl daemon-reload
sudo systemctl restart kube-scheduler
curl -k https://127.0.0.1:10259/healthz
```

---

## Cross-Component Issues

Some problems are not isolated to a single component but involve mismatches between them.

### CIDR Mismatches

Three values must be consistent across components:

```bash
# Service CIDR (must match between apiserver and controller-manager)
systemctl cat kube-apiserver | grep service-cluster-ip-range
systemctl cat kube-controller-manager | grep service-cluster-ip-range

# Pod CIDR (must match between controller-manager and kube-proxy)
systemctl cat kube-controller-manager | grep cluster-cidr
cat /var/lib/kube-proxy/kube-proxy-config.yaml | grep clusterCIDR

# CoreDNS ClusterIP (must be inside the service CIDR)
kubectl -n kube-system get svc coredns-coredns -o jsonpath='{.spec.clusterIP}'
```

### Certificate Chain Issues

If a component's certificate was not signed by the cluster CA, it will be rejected by other components.

```bash
# Verify a certificate was signed by the CA
openssl verify -CAfile /var/lib/kubernetes/ca.pem /var/lib/kubernetes/kubernetes.pem
# Should output: /var/lib/kubernetes/kubernetes.pem: OK
```

### Restart Order

If multiple components are broken and you need to restart everything, follow this order:

```bash
# Control plane
sudo systemctl restart etcd
sleep 3
sudo systemctl restart kube-apiserver
sleep 3
sudo systemctl restart kube-controller-manager
sudo systemctl restart kube-scheduler

# Worker components (if they were also affected)
sudo systemctl restart containerd
sleep 2
sudo systemctl restart kubelet
sudo systemctl restart kube-proxy
```

etcd must come first because the API server depends on it. The API server must come before the controller-manager and scheduler because they depend on it. The controller-manager and scheduler have no dependency on each other and can start in either order. If restarting kubelet, containerd must be running first because kubelet connects to it at startup via `containerd.socket`.
