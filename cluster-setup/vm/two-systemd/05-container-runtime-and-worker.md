# Container Runtime and Worker Components (Both Nodes)

**Based on:** [04-container-runtime.md](../../single-systemd/04-container-runtime.md) and [05-worker-components.md](../../single-systemd/05-worker-components.md) of the single-node guide.

**Adapted for:** Two-node cluster. Same containerd configuration on each node. CNI bridge configuration uses a per-node pod CIDR slice. kubelet kubeconfigs reference the apiserver's bridge IP. RBAC for apiserver-to-kubelet is applied once from `controlplane-1`.

---

## What This Chapter Does

Installs the container runtime stack (containerd, runc, crictl) and the worker-side Kubernetes components (kubelet, kube-proxy) on both nodes. Each node gets its own slice of the pod CIDR via the CNI bridge configuration. After this document, both nodes should appear in `kubectl get nodes` as `Ready` for any traffic that stays within a single node. Cross-node pod traffic will not work yet; document 06 adds the routes for that.

This is two documents from the single-node guide combined into one, because both halves are the same on each node and you want to do them in lockstep.

## What Is Different from the Single-Node Guide

- All commands run on **both** nodes, except where noted.
- Each node uses a different pod CIDR slice in `/etc/cni/net.d/10-bridge.conf`:
  - `controlplane-1`: `10.244.0.0/24`
  - `nodes-1`: `10.244.1.0/24`
- kubelet kubeconfig points at `https://192.168.122.10:6443` instead of `127.0.0.1:6443`.
- The kubelet certificate filename is per-node (`controlplane-1.pem` / `nodes-1.pem`).
- RBAC for apiserver-to-kubelet is applied once from `controlplane-1` after both kubelets are running.

## Prerequisites

Document 04 complete. The control plane is up on `controlplane-1`. Both nodes have their certs and kubeconfigs in `~/auth/` from document 03.

---

## Part 1: Install Container Runtime (Both Nodes)

Run on **both** nodes.

### Step 1: Shell Variables

```bash
arch=amd64
k8s_version=1.35.3
cri_version=1.35.0
runc_version=1.3.0
containerd_version=2.1.3
cni_plugins_version=1.7.1
cni_spec_version=1.0.0
```

### Step 2: Download Binaries

```bash
crictl_archive=crictl-v${cri_version}-linux-${arch}.tar.gz
containerd_archive=containerd-${containerd_version}-linux-${arch}.tar.gz
cni_plugins_archive=cni-plugins-linux-${arch}-v${cni_plugins_version}.tgz

wget -q --show-progress --https-only --timestamping \
  "https://github.com/kubernetes-sigs/cri-tools/releases/download/v${cri_version}/${crictl_archive}" \
  "https://github.com/opencontainers/runc/releases/download/v${runc_version}/runc.${arch}" \
  "https://github.com/containerd/containerd/releases/download/v${containerd_version}/${containerd_archive}" \
  "https://github.com/containernetworking/plugins/releases/download/v${cni_plugins_version}/${cni_plugins_archive}"
```

### Step 3: Install

```bash
# crictl
tar -xvf ${crictl_archive}
chmod +x crictl
sudo cp crictl /usr/local/bin/

# runc
cp runc.${arch} runc
chmod +x runc
sudo cp runc /usr/local/bin/

# containerd
mkdir -p containerd
tar -xvf ${containerd_archive} -C containerd
sudo cp containerd/bin/* /bin/

# CNI plugin binaries
sudo mkdir -p /opt/cni/bin
sudo tar -xvf ${cni_plugins_archive} -C /opt/cni/bin/
```

### Step 4: containerd Config

```bash
sudo mkdir -p /etc/containerd

cat <<'EOF' | sudo tee /etc/containerd/config.toml
version = 3
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]
  runtime_type = 'io.containerd.runc.v2'
  [plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]
    SystemdCgroup = true
    BinaryName = '/usr/local/bin/runc'
EOF
```

### Step 5: containerd systemd Unit

```bash
cat <<'EOF' | sudo tee /etc/systemd/system/containerd.service
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target

[Service]
ExecStartPre=/sbin/modprobe overlay
ExecStart=/bin/containerd
Restart=always
RestartSec=5
Delegate=yes
KillMode=process
OOMScoreAdjust=-999
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity

[Install]
WantedBy=multi-user.target
EOF
```

### Step 6: Start containerd

```bash
sudo systemctl daemon-reload
sudo systemctl enable containerd
sudo systemctl start containerd

# Verify
sudo crictl --runtime-endpoint unix:///var/run/containerd/containerd.sock info | head -10
```

---

## Part 2: Install kubelet and kube-proxy Binaries (Both Nodes)

```bash
wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kubelet" \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kube-proxy" \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kubectl"

chmod +x kubelet kube-proxy kubectl
sudo cp kubelet kube-proxy kubectl /usr/local/bin/
```

---

## Part 3: CNI Configuration (Per-Node)

The CNI bridge plugin uses a different subnet on each node. This is the key difference from the single-node guide and is what makes manual host routes (document 06) possible.

### On controlplane-1

```bash
ssh controlplane-1
sudo mkdir -p /etc/cni/net.d

cat <<'EOF' | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "1.0.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "10.244.0.0/24"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

cat <<'EOF' | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "1.0.0",
    "name": "lo",
    "type": "loopback"
}
EOF
```

### On nodes-1

```bash
ssh nodes-1
sudo mkdir -p /etc/cni/net.d

cat <<'EOF' | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "1.0.0",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "10.244.1.0/24"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

cat <<'EOF' | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "1.0.0",
    "name": "lo",
    "type": "loopback"
}
EOF
```

The only difference between the two `10-bridge.conf` files is the subnet. Get this wrong and pods on the wrong node will end up with overlapping IPs, which manifests as random connection failures that are very confusing to debug.

---

## Part 4: kubelet (Per-Node)

The kubelet config is per-node because it references the node's specific certificate file. The systemd unit and configuration YAML are the same shape on both nodes; only the cert and kubeconfig filenames differ.

### Step 1: Place Files (controlplane-1)

```bash
ssh controlplane-1
sudo mkdir -p /var/lib/kubelet /var/lib/kubernetes
sudo cp ~/auth/controlplane-1-key.pem ~/auth/controlplane-1.pem /var/lib/kubelet/
sudo cp ~/auth/controlplane-1.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp ~/auth/ca.pem /var/lib/kubernetes/
```

### Step 1: Place Files (nodes-1)

```bash
ssh nodes-1
sudo mkdir -p /var/lib/kubelet /var/lib/kubernetes
sudo cp ~/auth/nodes-1-key.pem ~/auth/nodes-1.pem /var/lib/kubelet/
sudo cp ~/auth/nodes-1.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp ~/auth/ca.pem /var/lib/kubernetes/
```

### Step 2: kubelet Config (controlplane-1)

```bash
ssh controlplane-1
cat <<'EOF' | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.96.0.10"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/controlplane-1.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/controlplane-1-key.pem"
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
cgroupDriver: "systemd"
EOF
```

### Step 2: kubelet Config (nodes-1)

```bash
ssh nodes-1
cat <<'EOF' | sudo tee /var/lib/kubelet/kubelet-config.yaml
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
authentication:
  anonymous:
    enabled: false
  webhook:
    enabled: true
  x509:
    clientCAFile: "/var/lib/kubernetes/ca.pem"
authorization:
  mode: Webhook
clusterDomain: "cluster.local"
clusterDNS:
  - "10.96.0.10"
resolvConf: "/run/systemd/resolve/resolv.conf"
runtimeRequestTimeout: "15m"
tlsCertFile: "/var/lib/kubelet/nodes-1.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/nodes-1-key.pem"
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
cgroupDriver: "systemd"
EOF
```

### Step 3: kubelet systemd Unit (Both Nodes, Identical)

Run on **both** nodes:

```bash
cat <<'EOF' | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \
  --config=/var/lib/kubelet/kubelet-config.yaml \
  --kubeconfig=/var/lib/kubelet/kubeconfig \
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kubelet
sudo systemctl start kubelet
```

### Step 4: Verify Both Nodes Register

From `controlplane-1`:

```bash
kubectl get nodes -o wide
```

You should see:

```
NAME    STATUS   ROLES    AGE   VERSION   INTERNAL-IP       ...
controlplane-1   Ready    <none>   30s   v1.35.3   192.168.122.10    ...
nodes-1   Ready    <none>   25s   v1.35.3   192.168.122.11    ...
```

If a node is `NotReady`, check its kubelet logs:

```bash
ssh <node> 'sudo journalctl -u kubelet -n 50'
```

### Step 5: Confirm Pod CIDRs Were Assigned

The controller-manager assigns each kubelet a pod CIDR slice when the node registers. Verify:

```bash
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.podCIDR}{"\n"}{end}'
```

Expected output:

```
controlplane-1   10.244.0.0/24
nodes-1   10.244.1.0/24
```

The CIDR shown here is what the **controller-manager** assigned. The CIDR you wrote in `/etc/cni/net.d/10-bridge.conf` is what the **CNI plugin** will actually use. If they do not match, pods on a node will get IPs that the cluster does not know how to route to. They should match here because we picked the same /24 slices manually that the controller would have picked anyway.

---

## Part 5: API Server to kubelet RBAC (Run Once)

The apiserver needs to be authorized to call kubelet for `kubectl exec`, `kubectl logs`, port-forwarding, and metrics. Create the RBAC rules from `controlplane-1` only:

```bash
ssh controlplane-1

cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups: [""]
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs: ["*"]
EOF

cat <<'EOF' | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: system:kube-apiserver
  namespace: ""
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:kube-apiserver-to-kubelet
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: User
    name: kubernetes
EOF
```

The `User: kubernetes` subject matches the CN of the apiserver's certificate, which is how the apiserver authenticates to kubelet.

---

## Part 6: kube-proxy (Both Nodes)

### Step 1: Place Files (Both Nodes)

```bash
sudo mkdir -p /var/lib/kube-proxy
sudo cp ~/auth/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig
```

### Step 2: kube-proxy Config (Both Nodes, Identical)

```bash
cat <<'EOF' | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.244.0.0/16"
EOF
```

`clusterCIDR` is the parent /16, not the per-node /24. kube-proxy uses this to decide which traffic counts as "cluster pod traffic" for SNAT purposes. It must match `--cluster-cidr` on the controller-manager.

### Step 3: kube-proxy systemd Unit (Both Nodes)

```bash
cat <<'EOF' | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable kube-proxy
sudo systemctl start kube-proxy
```

### Step 4: Verify

```bash
systemctl is-active kube-proxy
sudo iptables -t nat -L KUBE-SERVICES 2>/dev/null | head -10
# Should show some KUBE-SVC-... rules
```

---

## Part 7: Smoke Test (Single-Node Pods Only)

Schedule a pod and verify it gets an IP. At this point, cross-node pod traffic does not work yet (document 06 fixes that), so this test only verifies the basic CNI on each node.

```bash
ssh controlplane-1

# Schedule a pod, pinned to controlplane-1
kubectl run busybox-n1 --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"nodeName":"controlplane-1"}}' \
  --command -- sleep 600
kubectl wait --for=condition=Ready pod/busybox-n1 --timeout=60s

# Pod IP should be in 10.244.0.0/24
kubectl get pod busybox-n1 -o wide

# Schedule a pod on nodes-1
kubectl run busybox-n2 --image=busybox:1.36 --restart=Never \
  --overrides='{"spec":{"nodeName":"nodes-1"}}' \
  --command -- sleep 600
kubectl wait --for=condition=Ready pod/busybox-n2 --timeout=60s

# Pod IP should be in 10.244.1.0/24
kubectl get pod busybox-n2 -o wide
```

If both pods get IPs in their expected ranges, the per-node CNI is working. Try `kubectl exec`:

```bash
kubectl exec busybox-n1 -- sh -c 'echo "from controlplane-1 pod: $(hostname)"'
kubectl exec busybox-n2 -- sh -c 'echo "from nodes-1 pod: $(hostname)"'
```

Both `exec` commands should succeed because the apiserver-to-kubelet RBAC is in place.

Now try cross-node networking, which is **expected to fail** at this stage:

```bash
N1_IP=$(kubectl get pod busybox-n1 -o jsonpath='{.status.podIP}')
N2_IP=$(kubectl get pod busybox-n2 -o jsonpath='{.status.podIP}')

# These will time out
kubectl exec busybox-n1 -- ping -c 1 -W 2 "$N2_IP" || echo "controlplane-1 -> nodes-1 pod: blocked (expected at this stage)"
kubectl exec busybox-n2 -- ping -c 1 -W 2 "$N1_IP" || echo "nodes-1 -> controlplane-1 pod: blocked (expected at this stage)"
```

This is the routing problem document 06 solves. Leave the test pods running for now; you will use them again to verify after adding routes.

---

## Summary

The worker components are running on both nodes:

| Component | controlplane-1 | nodes-1 |
|-----------|-------|-------|
| containerd | Running | Running |
| kubelet | Running, registered | Running, registered |
| kube-proxy | Running | Running |
| CNI bridge subnet | `10.244.0.0/24` | `10.244.1.0/24` |
| Same-node pod traffic | Working | Working |
| Cross-node pod traffic | **Not working** (document 06 fixes) | **Not working** |

`kubectl get nodes` shows both nodes as `Ready`. Pods schedule. Same-node communication works. The next document adds the host routes that make cross-node pod traffic work.
