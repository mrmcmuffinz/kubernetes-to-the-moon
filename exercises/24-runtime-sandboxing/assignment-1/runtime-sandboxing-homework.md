# Runtime Sandboxing Homework

Work through the tutorial in `runtime-sandboxing-tutorial.md` before attempting these exercises. The tutorial installs gVisor on the kind node, configures containerd, and creates a RuntimeClass. The exercises assume that installation is complete. If you are working on a host where gVisor cannot be fully activated, you can still attempt the Kubernetes-side steps for Levels 1, 2, and 3 and compare your output against the expected values shown in each exercise.

## Exercise Setup

Verify that gVisor is installed and the RuntimeClass exists before starting:

```bash
nerdctl exec kind-control-plane runsc --version
kubectl get runtimeclass gvisor-sandbox
```

If either command fails, return to the tutorial and complete the installation steps.

---

## Level 1: RuntimeClass Basics

### Exercise 1.1

Create a RuntimeClass named `sandbox-basic` with a handler named `runsc`. Then create a pod named `level1-pod` in namespace `ex-1-1` using image `busybox:1.36` that runs `sleep 3600` and references this RuntimeClass. Verify the pod is running and that its `runtimeClassName` field is set correctly.

**Setup:**

```bash
kubectl create namespace ex-1-1
```

**Task:** Create the RuntimeClass and the pod. The pod must reach `Running` status.

**Verification:**

```bash
kubectl get runtimeclass sandbox-basic -o jsonpath='{.spec.handler}'
# Expected: runsc

kubectl get pod level1-pod -n ex-1-1 -o jsonpath='{.spec.runtimeClassName}'
# Expected: sandbox-basic

kubectl get pod level1-pod -n ex-1-1 -o jsonpath='{.status.phase}'
# Expected: Running
```

---

### Exercise 1.2

In namespace `ex-1-2`, create a pod named `kernel-check` using image `busybox:1.36` with `runtimeClassName: gvisor-sandbox` that runs `uname -r` and exits (do not use sleep). The pod should complete successfully. Retrieve the kernel version string the pod reported and confirm it does not match the host kernel version.

**Setup:**

```bash
kubectl create namespace ex-1-2

# Check host kernel version for comparison
uname -r
```

**Task:** Create the pod so it runs `uname -r` and exits with status 0. Retrieve its log output.

**Verification:**

```bash
kubectl get pod kernel-check -n ex-1-2 -o jsonpath='{.status.phase}'
# Expected: Succeeded

kubectl logs kernel-check -n ex-1-2
# Expected: a version string different from your host kernel version (gVisor reports its own kernel, typically 4.4.0 or similar)

kubectl get pod kernel-check -n ex-1-2 -o jsonpath='{.spec.runtimeClassName}'
# Expected: gvisor-sandbox
```

---

### Exercise 1.3

List all RuntimeClasses in the cluster. Then create a RuntimeClass named `kata-knowledge` with handler `kata` (you do not need gVisor or Kata installed for this handler; you are practicing the resource definition). Do not create any pods referencing it. Verify the RuntimeClass was created with the correct handler.

**Setup:**

```bash
kubectl create namespace ex-1-3
```

**Task:** Create the RuntimeClass. Verify it appears in the cluster-wide RuntimeClass listing with the correct handler.

**Verification:**

```bash
kubectl get runtimeclass
# Expected: output includes kata-knowledge with HANDLER kata

kubectl get runtimeclass kata-knowledge -o jsonpath='{.spec.handler}'
# Expected: kata
```

---

## Level 2: RuntimeClass with Workloads

### Exercise 2.1

In namespace `ex-2-1`, create a RuntimeClass named `sandbox-deploy` with handler `runsc`. Create a Deployment named `sandboxed-app` with 2 replicas using image `nginx:1.27` that references this RuntimeClass. Verify both pods are running and both have `runtimeClassName` set.

**Setup:**

```bash
kubectl create namespace ex-2-1
```

**Task:** Create the RuntimeClass and Deployment. Both replicas must reach `Running` status.

**Verification:**

```bash
kubectl get pods -n ex-2-1 -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.runtimeClassName}{"\n"}{end}'
# Expected: both pods show runtimeClassName: sandbox-deploy

kubectl get pods -n ex-2-1 --no-headers | awk '{print $3}' | sort | uniq
# Expected: Running

kubectl get deployment sandboxed-app -n ex-2-1 -o jsonpath='{.spec.replicas}'
# Expected: 2
```

---

### Exercise 2.2

In namespace `ex-2-2`, create two pods side by side: `pod-sandboxed` using image `busybox:1.36` with `runtimeClassName: gvisor-sandbox` running `sleep 3600`, and `pod-standard` using the same image with no `runtimeClassName`, also running `sleep 3600`. Exec into each pod and run `uname -r`. Confirm the outputs differ.

**Setup:**

```bash
kubectl create namespace ex-2-2
```

**Task:** Create both pods. Both must reach `Running` status.

**Verification:**

```bash
kubectl get pod pod-sandboxed -n ex-2-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod pod-standard -n ex-2-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec -n ex-2-2 pod-sandboxed -- uname -r
# Expected: a gVisor kernel version (e.g., 4.4.0), not the host kernel version

kubectl exec -n ex-2-2 pod-standard -- uname -r
# Expected: the host kernel version (matches output of uname -r on the host)
```

---

### Exercise 2.3

Create a RuntimeClass named `sandbox-overhead` with handler `runsc` and a `spec.overhead.podFixed` of 128Mi memory and 250m CPU. In namespace `ex-2-3`, create a pod named `overhead-pod` using image `busybox:1.36` running `sleep 3600` that references this RuntimeClass. Verify the RuntimeClass overhead is defined and the pod is running.

**Setup:**

```bash
kubectl create namespace ex-2-3
```

**Task:** Create the RuntimeClass with overhead and the pod referencing it. The pod must reach `Running` status.

**Verification:**

```bash
kubectl get runtimeclass sandbox-overhead \
  -o jsonpath='{.spec.overhead.podFixed.memory}'
# Expected: 128Mi

kubectl get runtimeclass sandbox-overhead \
  -o jsonpath='{.spec.overhead.podFixed.cpu}'
# Expected: 250m

kubectl get pod overhead-pod -n ex-2-3 -o jsonpath='{.spec.runtimeClassName}'
# Expected: sandbox-overhead

kubectl get pod overhead-pod -n ex-2-3 -o jsonpath='{.status.phase}'
# Expected: Running
```

---

## Level 3: Debugging Broken Configurations

### Exercise 3.1

Apply the configuration below, then fix whatever is preventing the pod from starting.

**Setup:**

```bash
kubectl create namespace ex-3-1

kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: debug-sandbox-a
spec:
  handler: runc-shim
---
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

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that the pod runs successfully.

**Verification:**

```bash
kubectl get pod debug-pod-a -n ex-3-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl describe pod debug-pod-a -n ex-3-1 | grep -i "runtime class"
# Expected: Runtime Class Name: debug-sandbox-a (or the corrected RuntimeClass name)
```

---

### Exercise 3.2

Apply the configuration below, then fix whatever is preventing the pod from starting.

**Setup:**

```bash
kubectl create namespace ex-3-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: debug-pod-b
  namespace: ex-3-2
spec:
  runtimeClassName: nonexistent-sandbox
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that the pod runs successfully.

**Verification:**

```bash
kubectl get pod debug-pod-b -n ex-3-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod debug-pod-b -n ex-3-2 -o jsonpath='{.spec.runtimeClassName}'
# Expected: gvisor-sandbox (or another valid RuntimeClass that exists in the cluster)
```

---

### Exercise 3.3

Apply the configuration below, then fix whatever is preventing the pod from starting.

**Setup:**

```bash
kubectl create namespace ex-3-3

kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: debug-sandbox-c
spec:
  handler: runsc
---
apiVersion: v1
kind: Pod
metadata:
  name: debug-pod-c
  namespace: ex-3-3
spec:
  runtimeClassName: debug-sandbox-d
  containers:
  - name: server
    image: nginx:1.27
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that the pod reaches Running status.

**Verification:**

```bash
kubectl get pod debug-pod-c -n ex-3-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod debug-pod-c -n ex-3-3 -o jsonpath='{.spec.runtimeClassName}'
# Expected: debug-sandbox-c
```

---

## Level 4: Full Workflow Scenarios

### Exercise 4.1

This exercise simulates the complete gVisor setup workflow. Assume gVisor is already installed on the kind node from the tutorial. Your task is to create a fresh RuntimeClass named `production-sandbox` with handler `runsc`, deploy a pod named `production-app` in namespace `ex-4-1` using image `nginx:1.27` that uses this RuntimeClass, verify the pod is running under gVisor, and then deploy a second pod named `standard-app` in the same namespace using the same image but no RuntimeClass. Use `kubectl exec` and `uname -r` to confirm the kernel version difference between the two pods.

**Setup:**

```bash
kubectl create namespace ex-4-1
```

**Task:** Create the RuntimeClass, both pods, and verify the kernel version differs between them.

**Verification:**

```bash
kubectl get pod production-app -n ex-4-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod production-app -n ex-4-1 -o jsonpath='{.spec.runtimeClassName}'
# Expected: production-sandbox

kubectl get pod standard-app -n ex-4-1 -o jsonpath='{.spec.runtimeClassName}'
# Expected: (empty string, no runtimeClassName set)

kubectl exec -n ex-4-1 production-app -- uname -r
# Expected: gVisor kernel version (different from host kernel)

kubectl exec -n ex-4-1 standard-app -- uname -r
# Expected: host kernel version

kubectl describe pod production-app -n ex-4-1 | grep "Runtime Class Name"
# Expected: Runtime Class Name:  production-sandbox
```

---

### Exercise 4.2

In namespace `ex-4-2`, create a RuntimeClass named `multi-replica-sandbox` with handler `runsc`. Create a Deployment named `secure-frontend` with 3 replicas using image `nginx:1.27` that references this RuntimeClass. After the Deployment is ready, update it to add a label `security: sandboxed` to the pod template without changing the runtimeClassName. Verify all three new pods carry both the label and the runtimeClassName after the rollout completes.

**Setup:**

```bash
kubectl create namespace ex-4-2
```

**Task:** Create the RuntimeClass, Deployment, perform the label update rollout, and verify the final state.

**Verification:**

```bash
kubectl get deployment secure-frontend -n ex-4-2 -o jsonpath='{.status.readyReplicas}'
# Expected: 3

kubectl get pods -n ex-4-2 -l security=sandboxed --no-headers | wc -l
# Expected: 3

kubectl get pods -n ex-4-2 \
  -o jsonpath='{range .items[*]}{.spec.runtimeClassName}{"\n"}{end}' | sort | uniq
# Expected: multi-replica-sandbox (only one unique value, repeated 3 times)
```

---

### Exercise 4.3

In namespace `ex-4-3`, implement a multi-workload isolation policy: create two RuntimeClasses, `high-security` (handler `runsc`) and `standard-runtime` (handler `runc`). Deploy two pods: `sensitive-data-processor` using image `busybox:1.36` with `runtimeClassName: high-security` running `sleep 3600`, and `web-frontend` using image `nginx:1.27` with `runtimeClassName: standard-runtime`. The `standard-runtime` RuntimeClass references the default containerd runc handler. Verify both pods are running and have their respective runtimeClassNames set, and confirm the `sensitive-data-processor` pod is running under gVisor by checking its kernel version.

**Setup:**

```bash
kubectl create namespace ex-4-3
```

**Task:** Create both RuntimeClasses and both pods. Both pods must reach Running status.

**Verification:**

```bash
kubectl get pod sensitive-data-processor -n ex-4-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod web-frontend -n ex-4-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod sensitive-data-processor -n ex-4-3 -o jsonpath='{.spec.runtimeClassName}'
# Expected: high-security

kubectl get pod web-frontend -n ex-4-3 -o jsonpath='{.spec.runtimeClassName}'
# Expected: standard-runtime

kubectl exec -n ex-4-3 sensitive-data-processor -- uname -r
# Expected: gVisor kernel version (not the host kernel)
```

---

## Level 5: Advanced Debugging

### Exercise 5.1

Apply the configuration below. The pod is failing to start. Find and fix whatever is needed so it runs successfully.

**Setup:**

```bash
kubectl create namespace ex-5-1

# Apply configuration inside the kind node
nerdctl exec kind-control-plane bash -c "
cat >> /etc/containerd/config.toml <<'TOML'

[plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.runsc-secure]
  runtime_type = \"io.containerd.runsc.v2\"
TOML
systemctl restart containerd
"

kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: level5-sandbox-a
spec:
  handler: runsc-secure
---
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

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that the pod reaches Running status.

**Verification:**

```bash
kubectl get pod level5-pod-a -n ex-5-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod level5-pod-a -n ex-5-1 -o jsonpath='{.spec.runtimeClassName}'
# Expected: level5-sandbox-a

kubectl exec -n ex-5-1 level5-pod-a -- uname -r
# Expected: gVisor kernel version
```

---

### Exercise 5.2

Apply the configuration below. One or more things are broken. Find and fix whatever is needed so both pods run successfully.

**Setup:**

```bash
kubectl create namespace ex-5-2

kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: level5-sandbox-b
spec:
  handler: runsc
---
apiVersion: v1
kind: Pod
metadata:
  name: level5-pod-b1
  namespace: ex-5-2
spec:
  runtimeClassName: level5-sandbox-b
  containers:
  - name: main
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: level5-pod-b2
  namespace: ex-5-2
spec:
  runtimeClassName: level5-sandbox-x
  containers:
  - name: main
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that both pods reach Running status and both are using a RuntimeClass backed by the `runsc` handler.

**Verification:**

```bash
kubectl get pod level5-pod-b1 -n ex-5-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod level5-pod-b2 -n ex-5-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod level5-pod-b2 -n ex-5-2 -o jsonpath='{.spec.runtimeClassName}'
# Expected: level5-sandbox-b (corrected to reference the existing RuntimeClass)

kubectl exec -n ex-5-2 level5-pod-b1 -- uname -r
# Expected: gVisor kernel version

kubectl exec -n ex-5-2 level5-pod-b2 -- uname -r
# Expected: gVisor kernel version
```

---

### Exercise 5.3

Apply the configuration below. One or more things are broken. Find and fix whatever is needed so the pod runs successfully.

**Setup:**

```bash
kubectl create namespace ex-5-3

# Inject a broken containerd config section
nerdctl exec kind-control-plane bash -c "
cat >> /etc/containerd/config.toml <<'TOML'

[plugins.\"io.containerd.grpc.v1.cri\".containerd.runtimes.gvisor-prod]
  runtime_type = \"io.containerd.runsc.v1\"
TOML
systemctl restart containerd
"

kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: level5-sandbox-c
spec:
  handler: gvisor-production
---
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

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that the pod reaches Running status under gVisor.

**Verification:**

```bash
kubectl get pod level5-pod-c -n ex-5-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod level5-pod-c -n ex-5-3 -o jsonpath='{.spec.runtimeClassName}'
# Expected: level5-sandbox-c

kubectl exec -n ex-5-3 level5-pod-c -- uname -r
# Expected: gVisor kernel version

kubectl describe pod level5-pod-c -n ex-5-3 | grep "Runtime Class Name"
# Expected: Runtime Class Name:  level5-sandbox-c
```

---

## Cleanup

Delete all exercise namespaces and the RuntimeClasses created during the exercises:

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 \
  ex-2-1 ex-2-2 ex-2-3 \
  ex-3-1 ex-3-2 ex-3-3 \
  ex-4-1 ex-4-2 ex-4-3 \
  ex-5-1 ex-5-2 ex-5-3 \
  --ignore-not-found

kubectl delete runtimeclass sandbox-basic kata-knowledge sandbox-deploy \
  sandbox-overhead production-sandbox multi-replica-sandbox \
  high-security standard-runtime level5-sandbox-a level5-sandbox-b \
  level5-sandbox-c debug-sandbox-a debug-sandbox-c \
  --ignore-not-found
```

The gVisor binary and containerd configuration inside the kind node persist across this cleanup, as they are node-level resources. If you want to remove the runsc handler entries from containerd, you can edit `/etc/containerd/config.toml` inside the kind container and remove the `runtimes.runsc*` sections, then restart containerd.

## Key Takeaways

The RuntimeClass resource decouples the Kubernetes pod spec from the underlying containerd runtime handler. The `spec.handler` field on the RuntimeClass must match a key in `/etc/containerd/config.toml` exactly, case-sensitively. gVisor intercepts syscalls in user space, producing a distinct `uname -r` output that confirms the sandbox is active. The most common failure modes are handler name mismatches (the RuntimeClass `spec.handler` does not match the containerd config key) and missing RuntimeClasses (a pod references a RuntimeClass that does not exist in the cluster). Kata containers follow the same Kubernetes-side pattern but require nested virtualization, making them impractical in most kind environments. Both runtime sandboxes add depth to a security posture but do not replace seccomp, AppArmor, or security contexts.
