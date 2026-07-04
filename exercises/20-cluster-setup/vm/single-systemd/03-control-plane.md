# Installing Kubernetes Control Plane (Single Node)

**Based on:** [kubernetes-the-harder-way/05_Installing_Kubernetes_Control_Plane.md](https://github.com/ghik/kubernetes-the-harder-way/blob/linux/docs/05_Installing_Kubernetes_Control_Plane.md)

**Simplified for:** A single-node cluster running inside a QEMU VM (`controlplane-1`, IP `10.0.2.15`), where all control plane and worker components run on the same machine.

**Version updates from the original guide:**

| Component | Original Guide | This Document |
|-----------|---------------|---------------|
| etcd | v3.6.2 | v3.6.9 |
| Kubernetes | v1.33.2 | v1.35.3 |

Kubernetes v1.35 is used because that is the version the CKA exam currently targets. etcd v3.6.9 is the latest stable patch release.

---

## What This Chapter Does

This chapter installs the four control plane components as systemd services inside the VM:

1. `etcd` (cluster state database)
2. `kube-apiserver` (API frontend)
3. `kube-controller-manager` (reconciliation loops)
4. `kube-scheduler` (pod placement)

By the end, you will have a functioning Kubernetes API that you can query with `kubectl` from the QEMU host through the port-forwarded 6443.

## What Was Removed from the Original Guide

The original guide installs these components across three control plane nodes using synchronized tmux panes and then sets up a load balancer (IPVS on a gateway VM) with a virtual IP. For a single node, all of that is unnecessary:

- No tmux pane synchronization (one VM, one shell)
- No multi-node etcd cluster (single instance, no peer communication)
- No load balancer, virtual IP, IPVS, or ldirectord
- No gateway VM

## Prerequisites

SSH into your VM and confirm that the certificates and kubeconfigs from the security bootstrapping chapter are present:

```bash
ls ~/auth/
```

You should see `ca.pem`, `ca-key.pem`, `kubernetes.pem`, `kubernetes-key.pem`, `service-account.pem`, `service-account-key.pem`, `encryption-config.yaml`, and the various `.kubeconfig` files.

## Quick Overview of systemd

Every Kubernetes component in this guide runs as a systemd service. A service is defined by a unit file in `/etc/systemd/system/`, which tells systemd what binary to run, how to restart it on failure, and what other services it depends on.

The key commands you will use throughout:

```bash
sudo systemctl daemon-reload    # Reload unit file definitions after changes
sudo systemctl enable <service> # Mark a service to start on boot
sudo systemctl start <service>  # Start a service now
systemctl status <service>      # Check if a service is running
journalctl -u <service>         # View logs for a service
```

## Shell Variables

Define these once at the top of your session inside the VM. They are referenced throughout the rest of the chapter.

```bash
arch=amd64

etcd_version=3.6.9
k8s_version=1.35.3

vmaddr=10.0.2.15
vmname=controlplane-1
```

## Installing etcd

Download, extract, and install the etcd binaries:

```bash
etcd_archive=etcd-v${etcd_version}-linux-${arch}.tar.gz
wget -q --show-progress --https-only --timestamping \
  "https://github.com/etcd-io/etcd/releases/download/v${etcd_version}/${etcd_archive}"
tar -xvf ${etcd_archive}
sudo cp etcd-v${etcd_version}-linux-${arch}/etcd* /usr/local/bin/
```

Create the data and configuration directories, then copy the certificates:

```bash
sudo mkdir -p /etc/etcd /var/lib/etcd
sudo chmod 700 /var/lib/etcd/
sudo cp ~/auth/ca.pem ~/auth/kubernetes-key.pem ~/auth/kubernetes.pem /etc/etcd/
```

Create the systemd unit file. Since this is a single-node etcd instance, there is no peer cluster configuration. The `--initial-cluster` contains only this node, and peer URLs point to localhost.

```bash
cat <<EOF | sudo tee /etc/systemd/system/etcd.service
[Unit]
Description=etcd
Documentation=https://github.com/etcd-io/etcd

[Service]
Type=notify
ExecStart=/usr/local/bin/etcd \\
  --name ${vmname} \\
  --cert-file=/etc/etcd/kubernetes.pem \\
  --key-file=/etc/etcd/kubernetes-key.pem \\
  --peer-cert-file=/etc/etcd/kubernetes.pem \\
  --peer-key-file=/etc/etcd/kubernetes-key.pem \\
  --trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-trusted-ca-file=/etc/etcd/ca.pem \\
  --peer-client-cert-auth \\
  --client-cert-auth \\
  --initial-advertise-peer-urls https://127.0.0.1:2380 \\
  --listen-peer-urls https://127.0.0.1:2380 \\
  --listen-client-urls https://${vmaddr}:2379,https://127.0.0.1:2379 \\
  --advertise-client-urls https://127.0.0.1:2379 \\
  --initial-cluster-token etcd-cluster-0 \\
  --initial-cluster ${vmname}=https://127.0.0.1:2380 \\
  --initial-cluster-state new \\
  --data-dir=/var/lib/etcd
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Key differences from the multi-node version: the `--initial-cluster` flag lists only one member instead of three, and all peer URLs use `127.0.0.1` since there are no peers to communicate with externally. The client listen URL includes both `${vmaddr}` (so the API server can reach it by IP) and `127.0.0.1`.

Start etcd:

```bash
sudo systemctl daemon-reload
sudo systemctl enable etcd
sudo systemctl start etcd
```

Verify it is running:

```bash
systemctl status etcd.service
```

If something is wrong, check the logs:

```bash
journalctl -u etcd.service
```

Confirm the single-member cluster is healthy:

```bash
sudo ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/ca.pem \
  --cert=/etc/etcd/kubernetes.pem \
  --key=/etc/etcd/kubernetes-key.pem
```

You should see one member listed with the name `controlplane-1`.

## Installing kube-apiserver

Download and install the binary:

```bash
wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kube-apiserver"
chmod +x kube-apiserver
sudo cp kube-apiserver /usr/local/bin/
```

Create the configuration directory and copy the security files:

```bash
sudo mkdir -p /var/lib/kubernetes/
sudo cp ~/auth/ca.pem ~/auth/ca-key.pem \
  ~/auth/kubernetes-key.pem ~/auth/kubernetes.pem \
  ~/auth/service-account-key.pem ~/auth/service-account.pem \
  ~/auth/encryption-config.yaml \
  /var/lib/kubernetes/
```

Create the systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kube-apiserver.service
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-apiserver \\
  --advertise-address=${vmaddr} \\
  --allow-privileged=true \\
  --apiserver-count=1 \\
  --audit-log-maxage=30 \\
  --audit-log-maxbackup=3 \\
  --audit-log-maxsize=100 \\
  --audit-log-path=/var/log/audit.log \\
  --authorization-mode=Node,RBAC \\
  --bind-address=0.0.0.0 \\
  --client-ca-file=/var/lib/kubernetes/ca.pem \\
  --enable-admission-plugins=NamespaceLifecycle,NodeRestriction,LimitRanger,ServiceAccount,DefaultStorageClass,ResourceQuota \\
  --etcd-cafile=/var/lib/kubernetes/ca.pem \\
  --etcd-certfile=/var/lib/kubernetes/kubernetes.pem \\
  --etcd-keyfile=/var/lib/kubernetes/kubernetes-key.pem \\
  --etcd-servers=https://127.0.0.1:2379 \\
  --event-ttl=1h \\
  --encryption-provider-config=/var/lib/kubernetes/encryption-config.yaml \\
  --kubelet-certificate-authority=/var/lib/kubernetes/ca.pem \\
  --kubelet-client-certificate=/var/lib/kubernetes/kubernetes.pem \\
  --kubelet-client-key=/var/lib/kubernetes/kubernetes-key.pem \\
  --runtime-config='api/all=true' \\
  --service-account-key-file=/var/lib/kubernetes/service-account.pem \\
  --service-account-signing-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-account-issuer=https://127.0.0.1:6443 \\
  --service-cluster-ip-range=10.96.0.0/16 \\
  --service-node-port-range=30000-32767 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Key differences from the multi-node version:

- `--apiserver-count=1` instead of 3.
- `--etcd-servers` points to a single local etcd instance instead of three separate endpoints.
- `--service-account-issuer` uses `127.0.0.1` instead of a load-balanced virtual IP.
- `--service-cluster-ip-range` is `10.96.0.0/16`. This is the range from which Kubernetes Services get their ClusterIPs. The first address in this range (`10.96.0.1`) is automatically assigned to the `kubernetes` API service, and it must be listed in the API server certificate's SAN list (which we did in the security chapter).

Notable options worth understanding:

- `--authorization-mode=Node,RBAC` enables both Node authorization (for kubelets) and RBAC (for everything else). This is why the "magic" CN and O values in the certificates matter.
- `--enable-admission-plugins` lists the admission controllers that intercept API requests. These are exam-relevant from S3 of the Mumshad course.
- `--service-node-port-range=30000-32767` defines the port range for NodePort services. These ports are forwarded from your QEMU host if you added them to the start script.

Start the API server:

```bash
sudo systemctl daemon-reload
sudo systemctl enable kube-apiserver
sudo systemctl start kube-apiserver
```

Verify it is running:

```bash
systemctl status kube-apiserver.service
```

Test the health endpoint:

```bash
curl --cacert /var/lib/kubernetes/ca.pem https://127.0.0.1:6443/healthz
```

You should get `ok` as the response.

## Installing kube-controller-manager

Download and install the binary:

```bash
wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kube-controller-manager"
chmod +x kube-controller-manager
sudo cp kube-controller-manager /usr/local/bin/
```

Copy the kubeconfig into the Kubernetes configuration directory:

```bash
sudo cp ~/auth/kube-controller-manager.kubeconfig /var/lib/kubernetes/
```

Create the systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kube-controller-manager.service
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-controller-manager \\
  --bind-address=0.0.0.0 \\
  --cluster-cidr=10.244.0.0/16 \\
  --cluster-name=kubernetes \\
  --cluster-signing-cert-file=/var/lib/kubernetes/ca.pem \\
  --cluster-signing-key-file=/var/lib/kubernetes/ca-key.pem \\
  --kubeconfig=/var/lib/kubernetes/kube-controller-manager.kubeconfig \\
  --leader-elect=true \\
  --root-ca-file=/var/lib/kubernetes/ca.pem \\
  --service-account-private-key-file=/var/lib/kubernetes/service-account-key.pem \\
  --service-cluster-ip-range=10.96.0.0/16 \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --use-service-account-credentials=true \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Notes on specific options:

- `--service-cluster-ip-range=10.96.0.0/16` must match the same flag on `kube-apiserver`.
- `--cluster-cidr=10.244.0.0/16` is the IP range for pods. This is the range your CNI plugin (Flannel, Calico, Cilium) will allocate pod IPs from. The `10.244.0.0/16` range is the Flannel default and is commonly used in CKA lab environments.
- `--cluster-signing-cert-file` and `--cluster-signing-key-file` allow the controller-manager to sign certificate signing requests (CSRs) via the Kubernetes Certificates API.
- `--leader-elect=true` enables leader election. With a single instance this has no practical effect, but it is the standard configuration and does not cause problems.

Start the controller-manager:

```bash
sudo systemctl daemon-reload
sudo systemctl enable kube-controller-manager
sudo systemctl start kube-controller-manager
```

## Installing kube-scheduler

Download and install the binary:

```bash
wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kube-scheduler"
chmod +x kube-scheduler
sudo cp kube-scheduler /usr/local/bin/
```

Copy the kubeconfig and create the scheduler configuration file:

```bash
sudo cp ~/auth/kube-scheduler.kubeconfig /var/lib/kubernetes/
sudo mkdir -p /etc/kubernetes/config

cat <<EOF | sudo tee /etc/kubernetes/config/kube-scheduler.yaml
apiVersion: kubescheduler.config.k8s.io/v1
kind: KubeSchedulerConfiguration
clientConnection:
  kubeconfig: "/var/lib/kubernetes/kube-scheduler.kubeconfig"
leaderElection:
  leaderElect: true
EOF
```

Create the systemd unit file:

```bash
cat <<EOF | sudo tee /etc/systemd/system/kube-scheduler.service
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
ExecStart=/usr/local/bin/kube-scheduler \\
  --config=/etc/kubernetes/config/kube-scheduler.yaml \\
  --tls-cert-file=/var/lib/kubernetes/kubernetes.pem \\
  --tls-private-key-file=/var/lib/kubernetes/kubernetes-key.pem \\
  --v=2
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
```

Start the scheduler:

```bash
sudo systemctl daemon-reload
sudo systemctl enable kube-scheduler
sudo systemctl start kube-scheduler
```

## Verifying the Control Plane

At this point all four control plane components should be running. Check them all at once:

```bash
systemctl status etcd.service
systemctl status kube-apiserver.service
systemctl status kube-controller-manager.service
systemctl status kube-scheduler.service
```

All four should show `active (running)`. If any service failed, check its logs with `journalctl -u <service-name>`.

You can also install `kubectl` inside the VM to interact with the API directly:

```bash
wget -q --show-progress --https-only --timestamping \
  "https://dl.k8s.io/release/v${k8s_version}/bin/linux/${arch}/kubectl"
chmod +x kubectl
sudo cp kubectl /usr/local/bin/
```

Copy the admin kubeconfig into place:

```bash
mkdir -p ~/.kube
cp ~/auth/admin.kubeconfig ~/.kube/config
```

Test it:

```bash
kubectl get namespaces
```

Expected output:

```
NAME              STATUS   AGE
default           Active   <age>
kube-node-lease   Active   <age>
kube-public       Active   <age>
kube-system       Active   <age>
```

You can also verify the API server health check from the QEMU host (through the port-forwarded 6443):

```bash
curl -k https://127.0.0.1:6443/healthz
```

The `-k` flag skips certificate verification. For proper verification, use:

```bash
curl --cacert ~/auth/ca.pem https://127.0.0.1:6443/healthz
```

## Summary

At this point you have a running Kubernetes control plane on a single node:

| Component | Status | Listening |
|-----------|--------|-----------|
| etcd | Running | `127.0.0.1:2379` (client), `127.0.0.1:2380` (peer) |
| kube-apiserver | Running | `0.0.0.0:6443` |
| kube-controller-manager | Running | `0.0.0.0:10257` |
| kube-scheduler | Running | `0.0.0.0:10259` |

The API is functional and responding to `kubectl` commands, but there are no worker nodes registered yet. The node cannot schedule pods until `kubelet`, a container runtime, and a CNI plugin are installed. That is the next chapter.

## CIDR Reference

Two IP ranges are configured in this chapter that must stay consistent across components:

| CIDR | Purpose | Used by |
|------|---------|---------|
| `10.96.0.0/16` | Service ClusterIP range | `kube-apiserver --service-cluster-ip-range`, `kube-controller-manager --service-cluster-ip-range` |
| `10.244.0.0/16` | Pod IP range | `kube-controller-manager --cluster-cidr`, CNI plugin configuration (next chapter) |
