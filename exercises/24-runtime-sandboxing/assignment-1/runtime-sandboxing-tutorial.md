# Runtime Sandboxing Tutorial

## Introduction

Every container in a standard Kubernetes cluster shares the host kernel. When a container process makes a syscall, that call goes directly to the same Linux kernel that runs every other workload on the node, including the kubelet, the container runtime, and other tenants' containers. For most workloads this is acceptable because the container isolation provided by namespaces and cgroups is sufficient. But for multi-tenant platforms, for workloads running untrusted code, and for environments subject to PCI-DSS or HIPAA controls, a kernel exploit in one container is a kernel exploit that affects every container on the same node. Runtime sandboxing addresses this by placing an additional isolation layer between the container and the host kernel.

Kubernetes models runtime sandboxing through the RuntimeClass resource. A RuntimeClass names a container runtime handler that the kubelet should use for pods that reference it. The two most common sandboxed runtimes are gVisor and Kata containers. gVisor (the `runsc` binary) implements a user-space kernel written in Go that intercepts every syscall from the container process and re-implements it in user space, so the container's code never directly reaches the host kernel. Kata containers take a different approach: each pod runs inside a lightweight virtual machine (backed by QEMU or Cloud Hypervisor), giving the workload a complete, isolated kernel. gVisor has lower overhead than Kata but does not support every syscall; Kata has VM startup overhead and requires nested virtualization but provides stronger isolation guarantees because the isolation boundary is a full hypervisor.

This tutorial installs gVisor on a kind node, registers it with containerd, creates a RuntimeClass, and deploys a pod that you can verify is running under the sandbox. Along the way you will learn how the kubelet, containerd, and the RuntimeClass resource interact so that the debugging exercises in the homework make sense mechanically, not just as a recipe to follow.

## Prerequisites

This tutorial assumes a single-node kind cluster running with rootless containerd via nerdctl. Create the cluster following the instructions at [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster). No additional CRDs, ingress controllers, or metrics-server are required. You need `nerdctl` available on the host because the gVisor installation steps use `nerdctl exec` to run commands inside the kind control-plane container.

## How RuntimeClass Works

Before installing anything, it helps to understand the call chain. When you create a pod with `spec.runtimeClassName: gvisor-sandbox`, the kubelet looks up the RuntimeClass object in the cluster and reads its `spec.handler` field. It then passes that handler name to containerd's CRI layer when asking containerd to create the container. Containerd looks up the handler name in its own configuration at `/etc/containerd/config.toml` and uses the associated runtime plugin to actually create the container. If the RuntimeClass does not exist, the pod gets a `RuntimeClass not found` error in its events. If the RuntimeClass exists but the containerd handler is not configured, the pod gets a `failed to create containerd task` error. If both exist but the binary is missing, containerd returns an error about the runtime binary. Each of these failure modes produces a distinct symptom, which is why the debugging exercises are diagnostic rather than configuration-look-up exercises.

### The RuntimeClass resource

A RuntimeClass has a minimal spec:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor-sandbox
spec:
  handler: runsc
```

The important fields and their behavior:

| Field | What it does | Valid values | Default | Failure mode when misconfigured |
|---|---|---|---|---|
| `spec.handler` | Names the containerd runtime handler; must match a key in `/etc/containerd/config.toml` | Any string; must match containerd config exactly (case-sensitive) | None (required) | Pod stays in `ContainerCreating`; Events show `failed to create containerd task` or `unknown runtime handler` |
| `spec.scheduling.nodeSelector` | Restricts pods using this RuntimeClass to nodes with the matching labels | Label key-value map | None (no restriction) | Pod stays in `Pending`; Events show `Insufficient` or no matching nodes |
| `spec.overhead.podFixed` | Additional resource overhead to account for the sandbox's own resource use | Resource quantity map | None | Reported in pod resource accounting; no pod-level failure |

RuntimeClass is a cluster-scoped resource (no namespace). The `metadata.name` is the value you put in `spec.runtimeClassName` on the pod. The `spec.handler` is entirely separate and refers to the containerd layer.

## Setup

Create the tutorial namespace:

```bash
kubectl create namespace tutorial-runtime-sandboxing
```

## Installing gVisor on the Kind Node

The kind control-plane container is itself a container managed by nerdctl. To install gVisor, you enter that container and install the `runsc` binary inside it.

### Step 1: Enter the kind control-plane container

```bash
nerdctl exec -it kind-control-plane bash
```

All subsequent commands in this section run inside the kind-control-plane container, not on the host. The prompt changes to indicate you are inside the container. If your cluster is named something other than `kind`, the container will be named `<cluster-name>-control-plane`.

### Step 2: Download and install the runsc binary

gVisor releases are published at `https://storage.googleapis.com/gvisor/releases/`. The `latest` path always resolves to the most recent release. In an exam environment you would use a pinned version; for this tutorial, the latest release is fine:

```bash
# Run inside kind-control-plane
ARCH=$(uname -m)
URL="https://storage.googleapis.com/gvisor/releases/release/latest/$(uname -s)_${ARCH}"
wget -O /usr/local/bin/runsc "${URL}/runsc" \
     -O /usr/local/bin/containerd-shim-runsc-v1 "${URL}/containerd-shim-runsc-v1"
chmod 755 /usr/local/bin/runsc /usr/local/bin/containerd-shim-runsc-v1
```

Verify the binary is working:

```bash
runsc --version
```

Expected output (version numbers vary):

```text
runsc version release-20240422.0
spec: 1.1.0-rc.1
```

If the binary executes and prints a version, gVisor is installed correctly on the node.

### Step 3: Configure containerd to register the runsc handler

containerd reads its runtime handlers from `/etc/containerd/config.toml`. You need to add a section that maps the handler name `runsc` to the gVisor containerd shim:

```bash
# Run inside kind-control-plane
cat >> /etc/containerd/config.toml <<'EOF'

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
EOF
```

The handler name in the TOML key (`runsc` in `runtimes.runsc`) is the value you will put in `spec.handler` on the RuntimeClass. The `runtime_type` field tells containerd which containerd shim binary to call; it corresponds to the `containerd-shim-runsc-v1` binary you installed in Step 2.

Verify the configuration was appended correctly:

```bash
grep -A2 "runtimes.runsc" /etc/containerd/config.toml
```

Expected output:

```text
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
```

### Step 4: Restart containerd

```bash
# Run inside kind-control-plane
systemctl restart containerd
```

Wait a few seconds, then verify containerd is running:

```bash
systemctl is-active containerd
```

Expected output:

```text
active
```

### Step 5: Exit the kind container

```bash
exit
```

You are now back on the host. The gVisor runtime is installed and registered inside the kind node.

### Fallback note for hosts without gVisor support

If the host kernel does not allow the gVisor installation to succeed (for example, if certain ptrace or seccomp capabilities are not available to the kind container), the `runsc` binary will still install but pod creation will fail with a message like `failed to create sandbox: ...` in the pod events. In that case, you can still work through the Kubernetes-side steps (creating RuntimeClass objects, assigning them to pods, reading error events) and refer to the expected output shown in the tutorial for the verification steps. The conceptual understanding of the containerd handler chain is the same regardless of whether the binary executes successfully.

## Creating the RuntimeClass

Back on the host, create the RuntimeClass that maps to the containerd `runsc` handler you just configured:

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor-sandbox
spec:
  handler: runsc
EOF
```

Verify it was created:

```bash
kubectl get runtimeclass gvisor-sandbox
```

Expected output:

```text
NAME             HANDLER   AGE
gvisor-sandbox   runsc     5s
```

The `HANDLER` column shows the containerd handler name. This is the value containerd uses when looking up the runtime configuration in `config.toml`.

You can also list all RuntimeClasses in the cluster:

```bash
kubectl get runtimeclass
```

On a fresh kind cluster with gVisor added, you will see only `gvisor-sandbox` unless other runtime classes were pre-installed. The `node.k8s.io/v1` API group is where RuntimeClass lives; there is no namespaced equivalent.

## Deploying a Pod Under gVisor

Create a pod that references the RuntimeClass:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: sandboxed-pod
  namespace: tutorial-runtime-sandboxing
spec:
  runtimeClassName: gvisor-sandbox
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

Watch it start:

```bash
kubectl get pod -n tutorial-runtime-sandboxing -w
```

When the pod reaches `Running`, press Ctrl+C. If the pod stays in `ContainerCreating` for more than thirty seconds, check events:

```bash
kubectl describe pod sandboxed-pod -n tutorial-runtime-sandboxing
```

The Events section will indicate whether the problem is a missing RuntimeClass, a handler name mismatch, or a containerd shim error.

## Verifying gVisor Isolation

Once the pod is running, run `uname -r` inside it:

```bash
kubectl exec -n tutorial-runtime-sandboxing sandboxed-pod -- uname -r
```

Under gVisor, the output will be a version string reported by gVisor's own kernel emulation, not the host kernel. It typically looks like:

```text
4.4.0
```

or a similar older version string, regardless of what the host kernel version actually is. Run the same command on a standard pod in a different namespace to see the contrast:

```bash
kubectl run compare-pod --image=busybox:1.36 --restart=Never \
  --command -- sleep 3600
kubectl exec compare-pod -- uname -r
```

The standard pod will report the actual host kernel version, for example:

```text
6.8.0-47-generic
```

The difference in `uname -r` output is the simplest confirmation that gVisor's user-space kernel is intercepting syscalls.

### Inspecting the runtimeClassName field

```bash
kubectl get pod sandboxed-pod -n tutorial-runtime-sandboxing \
  -o jsonpath='{.spec.runtimeClassName}'
```

Expected output:

```text
gvisor-sandbox
```

### Checking /proc/1/exe inside the pod

Under gVisor, `/proc/1/exe` points to the gVisor runsc internals rather than the sleep binary:

```bash
kubectl exec -n tutorial-runtime-sandboxing sandboxed-pod -- \
  readlink /proc/1/exe
```

On a standard runc pod, this would return the path to the sleep binary. Under gVisor it typically returns something like `/proc/self/exe` or a path internal to the gVisor sandbox, reflecting that the process view is mediated by gVisor's kernel emulation.

### Checking kubectl describe for runtimeClassName

```bash
kubectl describe pod sandboxed-pod -n tutorial-runtime-sandboxing | grep -i runtime
```

Expected output:

```text
Runtime Class Name:  gvisor-sandbox
```

The `Runtime Class Name` field in the `kubectl describe` output is the clearest human-readable confirmation that the pod is using the sandbox.

## Understanding Kata Containers (Conceptual)

Kata containers are not installable in most kind environments because kind itself runs as a container, and running a full virtual machine inside a container requires nested virtualization support that many CI systems and development machines do not expose. Understanding Kata conceptually is still required for the CKS exam domain.

Kata containers give each pod a full virtual machine boundary. The container process runs inside a lightweight guest kernel (backed by QEMU or Cloud Hypervisor), so a kernel exploit inside the container cannot reach the host kernel. This is a stronger isolation guarantee than gVisor's syscall interception approach. The tradeoff is VM startup overhead (typically 1-2 seconds per pod instead of milliseconds) and additional memory consumption for the guest kernel.

The RuntimeClass definition for Kata follows the same pattern as gVisor, just with a different handler name:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-containers
spec:
  handler: kata
```

The containerd configuration for Kata would include:

```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.kata]
  runtime_type = "io.containerd.kata.v2"
```

The pattern is identical to gVisor. The handler name in the TOML key matches `spec.handler` in the RuntimeClass, and the `runtime_type` names the containerd shim. For Kata, the shim is `containerd-shim-kata-v2`.

### When to choose Kata vs gVisor

The choice between Kata and gVisor depends on the threat model and workload characteristics. Kata provides stronger isolation because the boundary is a full hypervisor; if the workload is completely untrusted (for example, a code execution platform running arbitrary user code), Kata is the better choice despite the overhead. gVisor is appropriate when the workload is partially trusted but you want an additional defense-in-depth layer, and when syscall compatibility is acceptable (most Go and Python workloads work fine under gVisor; workloads that rely on `io_uring`, raw sockets, or unusual `ioctl` variants may not). Both are complementary to seccomp and AppArmor, not replacements for them. Sandboxing adds a kernel-level isolation boundary; seccomp and AppArmor add syscall filtering and mandatory access control within that boundary.

## Reference Commands

| Operation | Command |
|---|---|
| List all RuntimeClasses | `kubectl get runtimeclass` |
| Describe a RuntimeClass | `kubectl describe runtimeclass <name>` |
| Get RuntimeClass handler | `kubectl get runtimeclass <name> -o jsonpath='{.spec.handler}'` |
| Check pod runtimeClassName | `kubectl get pod <name> -o jsonpath='{.spec.runtimeClassName}'` |
| Verify sandbox kernel | `kubectl exec <pod> -- uname -r` |
| Check pod runtime in describe | `kubectl describe pod <name> \| grep -i runtime` |
| Enter kind node | `nerdctl exec -it kind-control-plane bash` |
| Check containerd config | `grep -A3 "runtimes" /etc/containerd/config.toml` |
| Check containerd status | `systemctl is-active containerd` (inside kind node) |
| Restart containerd | `systemctl restart containerd` (inside kind node) |
| Verify runsc binary | `runsc --version` (inside kind node) |

## Cleanup

Delete the tutorial namespace and the cluster-scoped RuntimeClass:

```bash
kubectl delete namespace tutorial-runtime-sandboxing
kubectl delete runtimeclass gvisor-sandbox
kubectl delete pod compare-pod --ignore-not-found
```

The gVisor binary and containerd configuration inside the kind node will persist until the cluster is deleted. That is intentional: the homework exercises depend on the runtime being installed and registered.
