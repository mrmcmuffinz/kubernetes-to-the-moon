# Installing Worker Components: CNI, kubelet, and kube-proxy (Single Node)

**Based on:** [kubernetes-the-harder-way/06_Spinning_up_Worker_Nodes.md](https://github.com/ghik/kubernetes-the-harder-way/blob/linux/docs/06_Spinning_up_Worker_Nodes.md) (second half)

**Simplified for:** A single-node cluster where the same VM runs control plane and worker components.

---

## What This Chapter Does

With the container runtime running, this chapter installs the remaining worker-side components:

1. **CNI plugins** configure pod networking (virtual interfaces, IP assignment, bridge)
2. **kubelet** is the node agent that registers the node with the API server and manages pod lifecycle
3. **kube-proxy** handles Kubernetes Service IP routing and load balancing
4. **RBAC rules** authorize the API server to call back to kubelet (for logs, exec, port-forward)

By the end, you will schedule your first pod and confirm the cluster is fully functional.

## What Was Removed from the Original Guide

The original guide installs these components across six nodes and includes several multi-node concerns that do not apply to a single-node setup:

- Per-node pod CIDR splitting (single node gets the entire pod range)
- Host-side routing rules to forward pod traffic between nodes
- Control plane taint to prevent scheduling on control nodes (we want pods on this node)
- tmux pane synchronization for parallel installation

## Prerequisites

SSH into the VM. The control plane (etcd, kube-apiserver, kube-controller-manager, kube-scheduler) and container runtime (containerd) should be running from the previous chapters.

## Shell Variables

```bash
arch=amd64
k8s_version=1.35.3
cni_plugins_version=1.7.1
cni_spec_version=1.0.0

vmname=controlplane-1
pod_cidr=10.244.0.0/16
```

The `pod_cidr` here is the full pod IP range. In a multi-node cluster, each node would get a slice of this range. Since everything runs on one node, it gets the entire `/16`.

## Installing CNI Plugins

CNI (Container Network Interface) plugins are executables that kubelet calls to set up networking for each pod. We use two standard plugins: `bridge` (creates a virtual bridge and assigns pod IPs) and `loopback` (configures the loopback interface inside the pod).

Download and install the plugins:

```bash
cni_plugins_archive=cni-plugins-linux-${arch}-v${cni_plugins_version}.tgz

wget -q --show-progress --https-only --timestamping \
  "https://github.com/containernetworking/plugins/releases/download/v${cni_plugins_version}/${cni_plugins_archive}"

sudo mkdir -p /opt/cni/bin
sudo tar -xvf ${cni_plugins_archive} -C /opt/cni/bin/
```

Create the CNI configuration files:

```bash
sudo mkdir -p /etc/cni/net.d

cat <<EOF | sudo tee /etc/cni/net.d/10-bridge.conf
{
    "cniVersion": "${cni_spec_version}",
    "name": "bridge",
    "type": "bridge",
    "bridge": "cnio0",
    "isGateway": true,
    "ipMasq": true,
    "ipam": {
        "type": "host-local",
        "ranges": [
          [{"subnet": "${pod_cidr}"}]
        ],
        "routes": [{"dst": "0.0.0.0/0"}]
    }
}
EOF

cat <<EOF | sudo tee /etc/cni/net.d/99-loopback.conf
{
    "cniVersion": "${cni_spec_version}",
    "name": "lo",
    "type": "loopback"
}
EOF
```

The bridge plugin creates a Linux bridge named `cnio0` on the node. Each pod gets a virtual ethernet pair: one end inside the pod's network namespace, the other end connected to the bridge. The `host-local` IPAM allocates pod IPs from the `pod_cidr` range. The `ipMasq` flag enables source NAT so pods can reach the internet (through the VM's default route).

## Installing kubelet

Download and install the binary:

```bash
wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kubelet"

chmod +x kubelet
sudo cp kubelet /usr/local/bin/
```

Copy the security files into place. These are the node certificate and kubeconfig generated during the security bootstrapping chapter:

```bash
sudo mkdir -p /var/lib/kubelet/ /var/lib/kubernetes/
sudo cp ~/auth/${vmname}-key.pem ~/auth/${vmname}.pem /var/lib/kubelet/
sudo cp ~/auth/${vmname}.kubeconfig /var/lib/kubelet/kubeconfig
sudo cp ~/auth/ca.pem /var/lib/kubernetes/
```

Create the kubelet configuration file:

```bash
cat <<EOF | sudo tee /var/lib/kubelet/kubelet-config.yaml
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
tlsCertFile: "/var/lib/kubelet/${vmname}.pem"
tlsPrivateKeyFile: "/var/lib/kubelet/${vmname}-key.pem"
containerRuntimeEndpoint: "unix:///var/run/containerd/containerd.sock"
cgroupDriver: "systemd"
EOF
```

Key configuration details:

- `clusterDNS` is set to `10.96.0.10`, which is the IP that the CoreDNS service will get in the next chapter. This must be inside the service CIDR (`10.96.0.0/16`). kubelet injects this as the DNS server into every pod's `/etc/resolv.conf`.
- `authentication.webhook.enabled: true` means kubelet verifies API requests by consulting the API server.
- `cgroupDriver: "systemd"` must match the containerd configuration.
- There is no `registerWithTaints` section. Unlike the original guide where control nodes are tainted to prevent scheduling, this single node needs to accept pods.

Create the systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kubelet.service
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/kubernetes/kubernetes
After=containerd.service
Requires=containerd.service

[Service]
ExecStart=/usr/local/bin/kubelet \\
  --config=/var/lib/kubelet/kubelet-config.yaml \\
  --kubeconfig=/var/lib/kubelet/kubeconfig \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Start kubelet:

```bash
sudo systemctl daemon-reload
sudo systemctl enable kubelet
sudo systemctl start kubelet
```

## Verifying Node Registration

Once kubelet starts, it registers itself with the API server. Verify using kubectl (installed in the control plane chapter):

```bash
kubectl get nodes -o wide
```

You should see:

```
NAME    STATUS   ROLES    AGE   VERSION   INTERNAL-IP   ...
controlplane-1   Ready    <none>   30s   v1.35.3   10.0.2.15     ...
```

The `Ready` status confirms that kubelet is running and the CNI plugins are properly configured. If the status shows `NotReady`, check kubelet logs with `journalctl -u kubelet`.

## Authorizing API Server to kubelet Communication

Some cluster operations require the API server to call kubelet (for `kubectl exec`, `kubectl logs`, port-forwarding). The RBAC rules for this are not set up automatically and must be created manually.

Run these from inside the VM (using the admin kubeconfig set up in the control plane chapter):

```bash
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:kube-apiserver-to-kubelet
rules:
  - apiGroups:
      - ""
    resources:
      - nodes/proxy
      - nodes/stats
      - nodes/log
      - nodes/spec
      - nodes/metrics
    verbs:
      - "*"
EOF

cat <<EOF | kubectl apply -f -
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

The `User: kubernetes` subject matches the CN of the API server's certificate, which is how the API server authenticates to kubelet.

## Installing kube-proxy

kube-proxy handles Kubernetes Service routing. When a pod connects to a Service ClusterIP, kube-proxy's iptables rules redirect that traffic to one of the backing pods.

Download and install:

```bash
wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kube-proxy"

chmod +x kube-proxy
sudo cp kube-proxy /usr/local/bin/
```

Configure kube-proxy:

```bash
sudo mkdir -p /var/lib/kube-proxy/
sudo cp ~/auth/kube-proxy.kubeconfig /var/lib/kube-proxy/kubeconfig

cat <<EOF | sudo tee /var/lib/kube-proxy/kube-proxy-config.yaml
kind: KubeProxyConfiguration
apiVersion: kubeproxy.config.k8s.io/v1alpha1
clientConnection:
  kubeconfig: "/var/lib/kube-proxy/kubeconfig"
mode: "iptables"
clusterCIDR: "10.244.0.0/16"
EOF
```

The `clusterCIDR` must match the `--cluster-cidr` flag from the kube-controller-manager configuration.

Create the systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kube-proxy.service
[Unit]
Description=Kubernetes Kube Proxy
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-proxy \\
  --config=/var/lib/kube-proxy/kube-proxy-config.yaml
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Start kube-proxy:

```bash
sudo systemctl daemon-reload
sudo systemctl enable kube-proxy
sudo systemctl start kube-proxy
```

## Enabling iptables for Bridge Traffic

By default, Linux does not pass bridge traffic through iptables. This breaks kube-proxy's Service IP handling when two pods on the same node communicate via a Service. The fix is to enable the `br_netfilter` module and set the appropriate sysctl parameter.

This should already be done by cloud-init from the VM creation step, but verify:

```bash
lsmod | grep br_netfilter
sysctl net.bridge.bridge-nf-call-iptables
```

If `br_netfilter` is not loaded or the sysctl is not set to 1:

```bash
sudo modprobe br_netfilter
sudo sysctl -w net.bridge.bridge-nf-call-iptables=1
```

## Scheduling a First Pod

Everything is in place. Schedule a test pod:

```bash
kubectl run busybox --image=busybox --command -- sleep 3600
```

Watch it start:

```bash
kubectl get pods -o wide -w
```

After pulling the image (this may take a minute on first run), you should see:

```
NAME      READY   STATUS    RESTARTS   AGE   IP            NODE    ...
busybox   1/1     Running   0          45s   10.244.0.2    controlplane-1   ...
```

The pod has an IP from the `10.244.0.0/16` range, confirming the CNI is working.

Test that `kubectl exec` works (which validates the RBAC rules):

```bash
kubectl exec -it busybox -- sh
```

You should get a shell inside the container. Type `exit` to leave.

Clean up the test pod when done:

```bash
kubectl delete pod busybox
```

## Summary

The worker-side components are now running:

| Component | Status | Purpose |
|-----------|--------|---------|
| CNI plugins | Configured | Pod networking (bridge + loopback) |
| kubelet | Running | Node agent, pod lifecycle management |
| kube-proxy | Running | Service IP routing via iptables |
| RBAC | Applied | Authorizes API server to kubelet calls |

All six core Kubernetes components are now operational on the single node. The next document installs CoreDNS to enable DNS-based service discovery within the cluster.
