# Runtime Sandboxing Homework: Answer Key

---

## Exercise 1.1 Solution

Create the RuntimeClass and the pod in separate steps:

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: sandbox-basic
spec:
  handler: runsc
EOF

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: level1-pod
  namespace: ex-1-1
spec:
  runtimeClassName: sandbox-basic
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

The key point is that the RuntimeClass must exist before or at the same time as the pod. Kubernetes looks up the RuntimeClass when scheduling the pod, so a pod that references a RuntimeClass that does not yet exist will stay in `Pending` with a RuntimeClass-not-found event until the RuntimeClass is created. Creating them in the same `kubectl apply` with `---` separators is fine; the order in the file does not matter because Kubernetes resolves references at scheduling time, not at apply time.

---

## Exercise 1.2 Solution

The pod needs `restartPolicy: Never` (or `OnFailure`) so that it does not restart after `uname -r` exits:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: kernel-check
  namespace: ex-1-2
spec:
  runtimeClassName: gvisor-sandbox
  restartPolicy: Never
  containers:
  - name: check
    image: busybox:1.36
    command: ["uname", "-r"]
EOF
```

After the pod completes:

```bash
kubectl logs kernel-check -n ex-1-2
```

Under gVisor the output is typically `4.4.0` or a similar older version string, while the host kernel will be something like `6.8.0-47-generic`. The difference is the clearest observable confirmation that gVisor's user-space kernel is handling the syscall. If the pod reports the same version as the host, the RuntimeClass was not applied (check `kubectl get pod kernel-check -n ex-1-2 -o jsonpath='{.spec.runtimeClassName}'`).

---

## Exercise 1.3 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: kata-knowledge
spec:
  handler: kata
EOF

kubectl get runtimeclass
```

Creating a RuntimeClass with an uninstalled handler does not fail at creation time. The RuntimeClass object is stored in etcd successfully. The failure only occurs when a pod tries to use it and containerd cannot find the handler named `kata` in its configuration. This is useful to know because it means you can pre-create RuntimeClasses for runtimes that will be installed later, or for knowledge-level exercises like this one.

---

## Exercise 2.1 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: sandbox-deploy
spec:
  handler: runsc
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: sandboxed-app
  namespace: ex-2-1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: sandboxed-app
  template:
    metadata:
      labels:
        app: sandboxed-app
    spec:
      runtimeClassName: sandbox-deploy
      containers:
      - name: web
        image: nginx:1.27
EOF
```

The `runtimeClassName` field goes under `spec.template.spec`, not under `spec` of the Deployment itself. Every pod the Deployment creates will inherit the `runtimeClassName` from the pod template. Verify with:

```bash
kubectl get pods -n ex-2-1 -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.runtimeClassName}{"\n"}{end}'
```

---

## Exercise 2.2 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: pod-sandboxed
  namespace: ex-2-2
spec:
  runtimeClassName: gvisor-sandbox
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: pod-standard
  namespace: ex-2-2
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

After both pods are running:

```bash
kubectl exec -n ex-2-2 pod-sandboxed -- uname -r
kubectl exec -n ex-2-2 pod-standard -- uname -r
```

The `pod-standard` pod has no `runtimeClassName`, so it uses the node's default runtime (runc), which passes syscalls directly to the host kernel. The host kernel version appears. The `pod-sandboxed` pod goes through gVisor, which intercepts `uname` and returns its own emulated kernel version. If both pods report the same version, the RuntimeClass `gvisor-sandbox` may not have been created in the cluster from the tutorial setup.

---

## Exercise 2.3 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: sandbox-overhead
spec:
  handler: runsc
  overhead:
    podFixed:
      memory: "128Mi"
      cpu: "250m"
---
apiVersion: v1
kind: Pod
metadata:
  name: overhead-pod
  namespace: ex-2-3
spec:
  runtimeClassName: sandbox-overhead
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

The `overhead.podFixed` field declares the additional resources the sandbox runtime itself consumes, separate from the container's own requests. Kubernetes adds this overhead to the pod's total resource accounting so that schedulers and resource quotas reflect the real cost of running a sandboxed pod. The overhead does not appear in the container's resource fields; it is a property of the RuntimeClass. For gVisor, a realistic overhead value is around 100-200Mi memory and 150-250m CPU, though the exact cost depends on workload.

---

## Exercise 3.1 Solution

### Diagnosis

Start by checking why the pod is not running:

```bash
kubectl get pod debug-pod-a -n ex-3-1
kubectl describe pod debug-pod-a -n ex-3-1
```

In the Events section of the describe output, look for messages about the container runtime. The event will say something like:

```text
failed to create containerd task: failed to create shim task: OCI runtime exec failed: unable to retrieve OCI runtime ... "runc-shim" ... does not exist
```

or:

```text
runtime handler "runc-shim" not supported
```

This tells you containerd received the handler name `runc-shim` and could not find a matching entry in its configuration.

### What the bug is and why it happens

The RuntimeClass `debug-sandbox-a` has `spec.handler: runc-shim`. The containerd configuration on the kind node registers `runsc` (from the tutorial installation), not `runc-shim`. The handler name in the RuntimeClass must match the key in containerd's `config.toml` exactly. `runc-shim` is not a valid handler name for the gVisor runtime; the correct handler name is `runsc`.

### Fix

Update the RuntimeClass to use the correct handler name:

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: debug-sandbox-a
spec:
  handler: runsc
EOF
```

Then delete and recreate the pod (RuntimeClass changes do not propagate to existing pods):

```bash
kubectl delete pod debug-pod-a -n ex-3-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: debug-pod-a
  namespace: ex-3-1
spec:
  runtimeClassName: debug-sandbox-a
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

---

## Exercise 3.2 Solution

### Diagnosis

```bash
kubectl get pod debug-pod-b -n ex-3-2
kubectl describe pod debug-pod-b -n ex-3-2
```

The Events section will show an error like:

```text
Failed to create pod sandbox: rpc error: code = NotFound desc = failed to handle a request by RuntimeClass controller: RuntimeClass.node.k8s.io "nonexistent-sandbox" not found
```

The kubelet attempted to look up a RuntimeClass named `nonexistent-sandbox` and received a 404.

### What the bug is and why it happens

The pod's `spec.runtimeClassName` references a RuntimeClass that does not exist in the cluster. This is one of the simplest runtime sandboxing errors to encounter in production: a pod was deployed with a `runtimeClassName` that was copy-pasted from documentation or another environment where the RuntimeClass existed, but it was never created in the current cluster.

### Fix

Either create the missing RuntimeClass or update the pod to reference one that exists. The cleanest fix is to update the pod to use the `gvisor-sandbox` RuntimeClass created during the tutorial:

```bash
kubectl delete pod debug-pod-b -n ex-3-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: debug-pod-b
  namespace: ex-3-2
spec:
  runtimeClassName: gvisor-sandbox
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

Alternatively, create a RuntimeClass named `nonexistent-sandbox` with handler `runsc` to match the pod's existing `runtimeClassName` without changing the pod.

---

## Exercise 3.3 Solution

### Diagnosis

```bash
kubectl get pod debug-pod-c -n ex-3-3
kubectl describe pod debug-pod-c -n ex-3-3
```

The Events section will show:

```text
Failed to create pod sandbox: rpc error: code = NotFound desc = ... RuntimeClass.node.k8s.io "debug-sandbox-d" not found
```

The pod references `debug-sandbox-d`, but the RuntimeClass that was created is named `debug-sandbox-c`.

### What the bug is and why it happens

The pod's `spec.runtimeClassName` value (`debug-sandbox-d`) does not match the name of the RuntimeClass that was created (`debug-sandbox-c`). This is a name mismatch at the Kubernetes object level, distinct from the handler mismatch in Exercise 3.1. In 3.1 the RuntimeClass existed but referenced the wrong containerd handler; here the RuntimeClass itself is named differently from what the pod expects. Both produce errors that mention "not found," but the not-found object differs: in 3.1 the RuntimeClass exists but containerd cannot find the handler; in 3.2 and 3.3 Kubernetes cannot find the RuntimeClass at all.

### Fix

Update the pod to reference the correct RuntimeClass name:

```bash
kubectl delete pod debug-pod-c -n ex-3-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: debug-pod-c
  namespace: ex-3-3
spec:
  runtimeClassName: debug-sandbox-c
  containers:
  - name: server
    image: nginx:1.27
EOF
```

---

## Exercise 4.1 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: production-sandbox
spec:
  handler: runsc
---
apiVersion: v1
kind: Pod
metadata:
  name: production-app
  namespace: ex-4-1
spec:
  runtimeClassName: production-sandbox
  containers:
  - name: web
    image: nginx:1.27
---
apiVersion: v1
kind: Pod
metadata:
  name: standard-app
  namespace: ex-4-1
spec:
  containers:
  - name: web
    image: nginx:1.27
EOF
```

After both pods are running:

```bash
kubectl exec -n ex-4-1 production-app -- uname -r
kubectl exec -n ex-4-1 standard-app -- uname -r
```

The two `uname -r` outputs will differ, confirming that `production-app` is running under gVisor's user-space kernel while `standard-app` is running under the host kernel via runc. This side-by-side comparison is the most direct way to validate that a sandboxed pod is genuinely isolated.

---

## Exercise 4.2 Solution

Create the initial Deployment:

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: multi-replica-sandbox
spec:
  handler: runsc
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-frontend
  namespace: ex-4-2
spec:
  replicas: 3
  selector:
    matchLabels:
      app: secure-frontend
  template:
    metadata:
      labels:
        app: secure-frontend
    spec:
      runtimeClassName: multi-replica-sandbox
      containers:
      - name: web
        image: nginx:1.27
EOF
```

Wait for the Deployment to be ready:

```bash
kubectl rollout status deployment secure-frontend -n ex-4-2
```

Add the `security: sandboxed` label to the pod template:

```bash
kubectl patch deployment secure-frontend -n ex-4-2 \
  --type=json \
  -p='[{"op":"add","path":"/spec/template/metadata/labels/security","value":"sandboxed"}]'
```

Wait for the rollout:

```bash
kubectl rollout status deployment secure-frontend -n ex-4-2
```

Verify:

```bash
kubectl get pods -n ex-4-2 -l security=sandboxed --no-headers | wc -l
kubectl get pods -n ex-4-2 \
  -o jsonpath='{range .items[*]}{.spec.runtimeClassName}{"\n"}{end}' | sort | uniq
```

The patch triggers a rolling update because the pod template changed, but the `runtimeClassName` on the existing pod spec is preserved because only the label was modified. Kubernetes never mutates `runtimeClassName` on existing pods; a pod's runtime handler is fixed at creation time. The rolling update creates new pods from the updated template, which still includes `runtimeClassName: multi-replica-sandbox`.

---

## Exercise 4.3 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: high-security
spec:
  handler: runsc
---
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: standard-runtime
spec:
  handler: runc
---
apiVersion: v1
kind: Pod
metadata:
  name: sensitive-data-processor
  namespace: ex-4-3
spec:
  runtimeClassName: high-security
  containers:
  - name: processor
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: web-frontend
  namespace: ex-4-3
spec:
  runtimeClassName: standard-runtime
  containers:
  - name: web
    image: nginx:1.27
EOF
```

The `standard-runtime` RuntimeClass uses handler `runc`, which is the default containerd runtime. It is already registered in containerd without any additional installation. The `high-security` RuntimeClass uses handler `runsc` (gVisor). Both pods start successfully because both handlers are registered. Verify:

```bash
kubectl exec -n ex-4-3 sensitive-data-processor -- uname -r
```

The output will be the gVisor kernel version, confirming the high-security workload is sandboxed while the web frontend runs under runc.

---

## Exercise 5.1 Solution

### Diagnosis

```bash
kubectl get pod level5-pod-a -n ex-5-1
kubectl describe pod level5-pod-a -n ex-5-1
```

The Events section will show a containerd error mentioning `runsc-secure` or the `containerd-shim-runsc-v2` binary. The error will likely read something like:

```text
failed to create containerd task: failed to create shim task: ... "io.containerd.runsc.v2": ... no such file or directory
```

Next, examine the containerd configuration that was injected during setup:

```bash
nerdctl exec kind-control-plane grep -A3 "runtimes.runsc-secure" /etc/containerd/config.toml
```

Output:

```text
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc-secure]
  runtime_type = "io.containerd.runsc.v2"
```

### What the bugs are and why they happen

The setup injected `runtime_type = "io.containerd.runsc.v2"` but the correct runtime type for gVisor is `"io.containerd.runsc.v1"`. The version suffix matters: containerd uses the `runtime_type` string to find the shim binary. The binary installed in the tutorial is `containerd-shim-runsc-v1`. There is no `containerd-shim-runsc-v2` binary, so containerd cannot find the shim and the pod fails to start.

### Fix

Correct the containerd configuration to use `v1`:

```bash
nerdctl exec kind-control-plane bash -c "
sed -i 's/io.containerd.runsc.v2/io.containerd.runsc.v1/g' /etc/containerd/config.toml
systemctl restart containerd
"
```

Verify the fix took effect:

```bash
nerdctl exec kind-control-plane grep -A3 "runtimes.runsc-secure" /etc/containerd/config.toml
```

Expected:

```text
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc-secure]
  runtime_type = "io.containerd.runsc.v1"
```

Then delete and recreate the pod to trigger a fresh start:

```bash
kubectl delete pod level5-pod-a -n ex-5-1
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: level5-pod-a
  namespace: ex-5-1
spec:
  runtimeClassName: level5-sandbox-a
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

---

## Exercise 5.2 Solution

### Diagnosis

```bash
kubectl get pods -n ex-5-2
kubectl describe pod level5-pod-b2 -n ex-5-2
```

`level5-pod-b1` should be running because it references `level5-sandbox-b`, which exists with handler `runsc`. `level5-pod-b2` will be stuck in `ContainerCreating` or `Pending` because it references `level5-sandbox-x`, which was never created.

The Events for `level5-pod-b2` will show:

```text
Failed to create pod sandbox: ... RuntimeClass.node.k8s.io "level5-sandbox-x" not found
```

### What the bug is and why it happens

`level5-pod-b2` references a RuntimeClass named `level5-sandbox-x` that does not exist. `level5-sandbox-b` (with the `b` suffix) was created, but `level5-sandbox-x` was not. The setup YAML contained a typo in the pod's `runtimeClassName`. This is the most common production runtime sandboxing error: a RuntimeClass is created with one name and referenced in the workload with a different name.

### Fix

Update `level5-pod-b2` to reference the existing RuntimeClass:

```bash
kubectl delete pod level5-pod-b2 -n ex-5-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: level5-pod-b2
  namespace: ex-5-2
spec:
  runtimeClassName: level5-sandbox-b
  containers:
  - name: main
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

Verify:

```bash
kubectl get pods -n ex-5-2
kubectl get pod level5-pod-b2 -n ex-5-2 -o jsonpath='{.spec.runtimeClassName}'
```

---

## Exercise 5.3 Solution

### Diagnosis

```bash
kubectl get pod level5-pod-c -n ex-5-3
kubectl describe pod level5-pod-c -n ex-5-3
```

The Events section will show an error like:

```text
failed to create containerd task: failed to create shim task: ... runtime handler "gvisor-production" not supported
```

The RuntimeClass `level5-sandbox-c` has `spec.handler: gvisor-production`. Check what the containerd configuration actually registered:

```bash
nerdctl exec kind-control-plane grep -A2 "runtimes.gvisor" /etc/containerd/config.toml
```

Output:

```text
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.gvisor-prod]
  runtime_type = "io.containerd.runsc.v1"
```

The containerd configuration registered handler `gvisor-prod` (truncated), but the RuntimeClass `spec.handler` says `gvisor-production` (the full word). These are different strings; containerd performs an exact match.

### What the bugs are and why they happen

There is a name mismatch between the RuntimeClass handler and the containerd configuration key. The setup injected `runtimes.gvisor-prod` into containerd but the RuntimeClass references `gvisor-production`. The handler name comparison is case-sensitive and character-exact; there is no partial matching or fuzzy lookup. This is the subtler variant of the handler mismatch bug from Exercise 3.1: in 3.1 the handler name was completely wrong (a non-existent name); here both handler names look plausible and differ only in the trailing characters.

### Fix

The cleanest fix is to update the RuntimeClass to match the containerd configuration key:

```bash
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: level5-sandbox-c
spec:
  handler: gvisor-prod
EOF
```

Then delete and recreate the pod:

```bash
kubectl delete pod level5-pod-c -n ex-5-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: level5-pod-c
  namespace: ex-5-3
spec:
  runtimeClassName: level5-sandbox-c
  containers:
  - name: app
    image: nginx:1.27
EOF
```

Alternatively, you could rename the containerd handler from `gvisor-prod` to `gvisor-production` by editing `config.toml` inside the kind container and restarting containerd, then keeping the RuntimeClass as-is. The fix that changes fewer components is generally preferred in production because editing containerd configuration requires a containerd restart, which briefly interrupts container operations on the node.

---

## Common Mistakes

**Confusing `spec.handler` (containerd layer) with `metadata.name` (Kubernetes layer).** The RuntimeClass `metadata.name` is what you put in the pod's `spec.runtimeClassName`. The RuntimeClass `spec.handler` is the name of the containerd runtime handler in `/etc/containerd/config.toml`. These can be the same string or different strings. When they differ, it is easy to cross them when debugging: looking at the pod events and seeing "handler X not found" means containerd could not find X in its config, not that the Kubernetes RuntimeClass object named X is missing. Always check both layers separately: `kubectl get runtimeclass <name>` confirms the Kubernetes object exists; `grep runtimes /etc/containerd/config.toml` (inside the kind node) confirms the containerd handler exists.

**Not restarting containerd after editing `config.toml`.** containerd reads its configuration at startup. If you edit `/etc/containerd/config.toml` inside the kind node and do not run `systemctl restart containerd`, the new handler is invisible to all subsequent pod creation attempts. The pod will fail with the same handler-not-found error as before the edit. This is an easy mistake to make when troubleshooting quickly under exam pressure. Always verify with `systemctl is-active containerd` after restarting to confirm it came back up.

**Expecting `runtimeClassName` changes on existing pods to take effect.** A pod's `runtimeClassName` is immutable after creation. If you apply a manifest that changes `runtimeClassName` on an existing pod, Kubernetes will reject the update with an immutable field error. To change a pod's runtime, you must delete and recreate it. For Deployments, updating the pod template's `runtimeClassName` triggers a rolling update that replaces the pods, which is the correct mechanism.

**Using `:latest` or an incorrect image tag and blaming the RuntimeClass.** If a pod stays in `ImagePullBackOff` instead of `ContainerCreating`, the problem is image pulling, not the RuntimeClass. Check the Events section carefully before assuming the runtime handler is to blame. `ContainerCreating` with a duration longer than thirty seconds, followed by an error event mentioning `runtime`, `containerd`, `shim`, or `handler`, is the signature of a RuntimeClass or containerd configuration problem.

**Not accounting for gVisor syscall compatibility.** gVisor does not implement every Linux syscall. Workloads that use `io_uring`, certain `ioctl` variants, or obscure kernel features may fail or perform poorly under gVisor even when the RuntimeClass and containerd configuration are correct. The failure mode is typically a container that crashes immediately after starting, with exit code 1 or 2 and a log message about an unsupported syscall or operation. This is not a Kubernetes configuration problem and cannot be fixed by adjusting the RuntimeClass; it requires either switching to Kata containers (which provide a full kernel) or modifying the workload to avoid the unsupported syscall.

---

## Verification Commands Cheat Sheet

| Use case | Command | Expected output |
|---|---|---|
| List all RuntimeClasses | `kubectl get runtimeclass` | Table with NAME and HANDLER columns |
| Get handler for a RuntimeClass | `kubectl get runtimeclass <name> -o jsonpath='{.spec.handler}'` | Handler string (e.g., `runsc`) |
| Check pod's runtimeClassName | `kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.runtimeClassName}'` | RuntimeClass name or empty |
| Confirm gVisor is active | `kubectl exec -n <ns> <pod> -- uname -r` | Version differs from host kernel |
| Check runtime in describe | `kubectl describe pod <pod> -n <ns> \| grep "Runtime Class Name"` | `Runtime Class Name: <name>` |
| Check pod events | `kubectl describe pod <pod> -n <ns> \| grep -A10 Events` | Events section with runtime errors |
| Enter kind node | `nerdctl exec -it kind-control-plane bash` | Shell inside kind container |
| Check containerd handlers | `grep -A2 "runtimes\." /etc/containerd/config.toml` (inside kind node) | TOML sections for each handler |
| Verify runsc binary | `runsc --version` (inside kind node) | Version string |
| Check containerd status | `systemctl is-active containerd` (inside kind node) | `active` |
| Restart containerd | `systemctl restart containerd` (inside kind node) | No output; wait ~3 seconds |
| Verify handler registration | `grep "runtimes\.<name>" /etc/containerd/config.toml` (inside kind node) | Matching TOML key |
