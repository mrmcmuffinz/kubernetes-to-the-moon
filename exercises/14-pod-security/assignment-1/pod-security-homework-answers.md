# Pod Security Homework Answers

Complete solutions for all 15 exercises. Level 3 and Level 5 debugging exercises follow the three-stage structure: Diagnosis, What the bug is and why, Fix.

-----

## Exercise 1.1 Solution

```bash
kubectl label namespace ex-1-1 pod-security.kubernetes.io/enforce=baseline

cat <<'EOF' | kubectl apply -n ex-1-1 -f -
apiVersion: v1
kind: Pod
metadata:
  name: web
spec:
  containers:
  - name: web
    image: nginx:1.25
    ports:
    - containerPort: 80
EOF
```

Nginx running as root is acceptable under Baseline; Baseline blocks known privilege escalations but does not require `runAsNonRoot`. The pod is accepted and reaches Running.

-----

## Exercise 1.2 Solution

```bash
kubectl label namespace ex-1-2 pod-security.kubernetes.io/warn=restricted

cat <<'EOF' | kubectl apply -n ex-1-2 -f -
apiVersion: v1
kind: Pod
metadata:
  name: probe
spec:
  containers:
  - name: app
    image: nginx:1.25
EOF
```

The apply will produce output of the form:

```
Warning: would violate PodSecurity "restricted:latest":
allowPrivilegeEscalation != false (container "app" must set
securityContext.allowPrivilegeEscalation=false),
unrestricted capabilities (container "app" must set
securityContext.capabilities.drop=["ALL"]),
runAsNonRoot != true (pod or container "app" must set
securityContext.runAsNonRoot=true), seccompProfile (pod or container "app"
must set securityContext.seccompProfile.type to "RuntimeDefault" or
"Localhost")
pod/probe created
```

The final line is `created`; warn mode does not block. The four violations listed are the four Restricted-specific requirements the pod would fail if the namespace were at enforce Restricted.

-----

## Exercise 1.3 Solution

```bash
kubectl label namespace ex-1-3 pod-security.kubernetes.io/enforce=restricted

cat <<'EOF' | kubectl apply -n ex-1-3 -f - || true
apiVersion: v1
kind: Pod
metadata:
  name: naive
spec:
  containers:
  - name: app
    image: nginx:1.25
EOF
```

The apply errors out with a `Forbidden` response; the pod is not created. The error message lists the four Restricted violations just like the warn output in 1.2, but the outcome is rejection rather than acceptance.

-----

## Exercise 2.1 Solution

```bash
kubectl label namespace ex-2-1 \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/warn=restricted
```

All three labels are independent and can be applied in one command. Order does not matter.

The common migration pattern behind this configuration is "run at Baseline today, but start surfacing what it would take to tighten to Restricted." Audit captures violations in the audit log (for monitoring tools), warn shows them in kubectl output (for developers), and enforce keeps the current policy in force so nothing breaks.

-----

## Exercise 2.2 Solution

```bash
kubectl label namespace ex-2-2 \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=v1.30

cat <<'EOF' | kubectl apply -n ex-2-2 -f -
apiVersion: v1
kind: Pod
metadata:
  name: anchor
spec:
  containers:
  - name: app
    image: nginx:1.25
EOF
```

The `-version` label pins the enforce policy to v1.30's Baseline definition. If the cluster upgrades to 1.36 later and the Baseline definition tightens (new fields added to the blocks list), this namespace keeps using the v1.30 definition until the version label is changed.

-----

## Exercise 2.3 Solution

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: hardened
  namespace: ex-2-3
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginxinc/nginx-unprivileged:1.25
    ports:
    - containerPort: 8080
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
      seccompProfile:
        type: RuntimeDefault
```

Pod-level `securityContext` provides defaults inherited by every container. Container-level `securityContext` overrides per-container. Both layers are set here because Restricted evaluates both: `runAsNonRoot` and `seccompProfile.type` can be satisfied at either level, `allowPrivilegeEscalation` and `capabilities` must be at the container level.

The image `nginxinc/nginx-unprivileged:1.25` runs as UID 101 by default (not root), which is why `runAsNonRoot: true` is satisfied. Standard `nginx:1.25` runs as root and would additionally need a `runAsUser: NON_ZERO` setting.

-----

## Exercise 3.1 Solution

### Diagnosis

```bash
kubectl apply -n ex-3-1 -f - <<'EOF'
# ... (the broken setup)
EOF
# Error from server (Forbidden): pods "broken-1" is forbidden: violates PodSecurity "restricted:latest":
#   unrestricted capabilities (container "app" must set securityContext.capabilities.drop=["ALL"])
```

Only one violation is listed: missing `capabilities.drop`. The setup already has `runAsNonRoot`, `seccompProfile`, and `allowPrivilegeEscalation: false`, so those three Restricted requirements are met. The fourth, `capabilities.drop: ["ALL"]`, is missing.

### What the bug is and why

Restricted requires every container to explicitly drop ALL capabilities, not merely to leave them at the runtime default. Container runtimes start containers with a default capability set even if you do not add any; Restricted's contract is that you have opted out of all defaults. The rejection message tells you exactly which field needs to be set.

### Fix

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: broken-1
  namespace: ex-3-1
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginxinc/nginx-unprivileged:1.25
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
EOF
```

Adding the four lines of `capabilities.drop: ["ALL"]` satisfies Restricted.

-----

## Exercise 3.2 Solution

### Diagnosis

```bash
kubectl get deployment broken-2 -n ex-3-2
# READY 0/2

kubectl describe rs -n ex-3-2 -l app=broken-2
# Events section:
#   FailedCreate ... Error creating: pods "broken-2-..." is forbidden:
#   violates PodSecurity "baseline:latest": host namespaces (hostNetwork=true)
```

### What the bug is and why

The Deployment was accepted because PSA `enforce` only validates Pod objects, not workload resources that wrap them. The ReplicaSet controller tried to create pods from the template, and each pod creation was rejected because `hostNetwork: true` violates Baseline's host-namespace blocks. The visible symptom is a Deployment with `READY 0/N` and `FailedCreate` events on the child ReplicaSet.

Finding the error requires one extra hop: look at the ReplicaSet, not the Deployment, because the Deployment controller does not surface child-creation failures on itself.

### Fix

Remove `hostNetwork: true` from the pod template.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: broken-2
  namespace: ex-3-2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: broken-2
  template:
    metadata:
      labels:
        app: broken-2
    spec:
      containers:
      - name: app
        image: nginx:1.25
```

`hostNetwork` defaulted to false when removed, which satisfies Baseline. Nginx running as root is fine under Baseline. The Deployment reaches 2 ready after the fix.

-----

## Exercise 3.3 Solution

### Diagnosis

```bash
kubectl apply -n ex-3-3 -f - <<'EOF'
# ... (the broken setup with no securityContext at all)
EOF
# Error from server (Forbidden): pods "broken-3" is forbidden: violates PodSecurity "restricted:latest":
#   allowPrivilegeEscalation != false, unrestricted capabilities, runAsNonRoot != true,
#   seccompProfile
```

All four Restricted requirements are missing.

### What the bug is and why

The setup pod has no `securityContext` at all. Restricted requires four specific fields to be set; every one of them fails. This is the textbook Restricted rejection: a completely unhardened pod hits all four violations at once. The fix is to add pod-level and container-level `securityContext` fields for each.

### Fix

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: broken-3
  namespace: ex-3-3
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
```

`runAsUser: 1000` is needed because busybox does not have a pre-configured non-root user; setting an explicit non-zero UID makes `runAsNonRoot` satisfiable.

-----

## Exercise 4.1 Solution

```bash
kubectl label namespace ex-4-1 \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=v1.35 \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=v1.35 \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=v1.35

cat <<'EOF' | kubectl apply -n ex-4-1 -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 3
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: api
        image: nginxinc/nginx-unprivileged:1.25
        ports:
        - containerPort: 8080
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
EOF
```

-----

## Exercise 4.2 Solution

```bash
kubectl label namespace ex-4-2 pod-security.kubernetes.io/warn=restricted

cat <<'EOF' | kubectl apply -n ex-4-2 -f -
apiVersion: v1
kind: Pod
metadata:
  name: probe
spec:
  containers:
  - name: app
    image: nginx:1.25
EOF
```

Adding `warn=restricted` to a namespace that already enforces Baseline is safe: warnings are surfaced, but nothing is blocked. The `legacy` pod applied in setup remains Running; the new `probe` pod also starts Running and produces Warning lines in the kubectl output listing the four Restricted violations. This is the correct way to start a migration: leave enforce in place, add warn at the tighter level, fix workloads one at a time.

-----

## Exercise 4.3 Solution

```bash
kubectl label namespace ex-4-3 \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=v1.30

kubectl label namespace ex-4-3-audit pod-security.kubernetes.io/enforce=restricted

# accepted in ex-4-3 (Baseline allows an unhardened pod)
cat <<'EOF' | kubectl apply -n ex-4-3 -f -
apiVersion: v1
kind: Pod
metadata:
  name: explorer
spec:
  containers:
  - name: app
    image: nginx:1.25
EOF

# rejected in ex-4-3-audit (Restricted requires hardening)
cat <<'EOF' | kubectl apply -n ex-4-3-audit -f - || true
apiVersion: v1
kind: Pod
metadata:
  name: explorer
spec:
  containers:
  - name: app
    image: nginx:1.25
EOF
```

This exercise is a side-by-side comparison of Baseline vs Restricted enforcement on the same pod spec. The same YAML produces two different outcomes depending on the namespace label. That is the whole mental model for PSA: namespace policy determines what is allowed, pod spec determines what is submitted.

-----

## Exercise 5.1 Solution

```bash
# apply all six labels
kubectl label namespace ex-5-1 \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=v1.35 \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest

cat <<'EOF' | kubectl apply -n ex-5-1 -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: secure-api
  template:
    metadata:
      labels:
        app: secure-api
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: api
        image: nginxinc/nginx-unprivileged:1.25
        ports:
        - containerPort: 8080
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
EOF
```

Note the version pins differ by mode: enforce is pinned to v1.35 (stable policy version for enforcement that cannot change across cluster upgrades), while audit and warn use `latest` to always report against the newest definition (preparing for future tightening).

-----

## Exercise 5.2 Solution

### Diagnosis

```bash
kubectl get deployment multibug -n ex-5-2
# READY 0/2

kubectl describe rs -n ex-5-2 -l app=multibug | grep -A 5 Events
# FailedCreate ... violates PodSecurity "restricted:latest":
#   host namespaces (hostNetwork=true),
#   privileged (container "app" must not set securityContext.privileged=true),
#   unrestricted capabilities (adding NET_ADMIN, and not dropping ALL),
#   allowPrivilegeEscalation != false,
#   runAsNonRoot != true (runAsUser=0 is root),
#   seccompProfile type not set
```

### What the bugs are and why

Stacked Restricted violations, each reported in one rejection message:

1. `hostNetwork: true` - violates Baseline (also Restricted).
2. `securityContext.runAsUser: 0` on the pod - UID 0 is root, violates `runAsNonRoot`.
3. `privileged: true` - violates Baseline.
4. `capabilities.add: ["NET_ADMIN"]` - NET_ADMIN is not in the Baseline-allowed list; violates Baseline.
5. Missing `allowPrivilegeEscalation: false` - violates Restricted.
6. Missing `capabilities.drop: ["ALL"]` - violates Restricted (implicit, not fixed by removing `add`).
7. Missing `seccompProfile.type` - violates Restricted.

Each one must be addressed. Changing the image to `nginxinc/nginx-unprivileged:1.25` is the simplest way to satisfy the non-root requirement because that image's baked-in user is UID 101.

### Fix

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: multibug
  namespace: ex-5-2
spec:
  replicas: 2
  selector:
    matchLabels:
      app: multibug
  template:
    metadata:
      labels:
        app: multibug
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        image: nginxinc/nginx-unprivileged:1.25
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
```

Remove `hostNetwork`, remove `privileged`, remove `capabilities.add`, set `runAsNonRoot` and `seccompProfile` at the pod level, set `allowPrivilegeEscalation: false` and `capabilities.drop: ["ALL"]` at the container level, and switch the image. The Deployment reaches 2 ready replicas.

-----

## Exercise 5.3 Solution

### Diagnosis

```bash
kubectl get deployment subtle -n ex-5-3
# READY 0/2

kubectl describe rs -n ex-5-3 -l app=subtle
# FailedCreate: violates PodSecurity "restricted:latest":
#   runAsNonRoot != true (pod must not set runAsUser=0 with runAsNonRoot=true)
```

### What the bug is and why

This is the subtle contradiction. The pod's `securityContext` sets `runAsNonRoot: true` AND `runAsUser: 0`. The kubelet treats `runAsUser: 0` as an attempt to run as root, which directly contradicts `runAsNonRoot: true`. The container would be rejected at runtime with `CreateContainerConfigError`, but PSA catches it earlier at admission time because the two settings are logically incompatible.

Everything else in the pod template satisfies Restricted. Only this one inconsistency prevents the pods from being created.

### Fix

Change `runAsUser: 0` to a non-zero UID (the image runs as UID 101 naturally, so that value works; any non-zero UID the image can use is correct).

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: subtle
  namespace: ex-5-3
spec:
  replicas: 2
  selector:
    matchLabels:
      app: subtle
  template:
    metadata:
      labels:
        app: subtle
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        seccompProfile:
          type: RuntimeDefault
      containers:
      - name: app
        image: nginxinc/nginx-unprivileged:1.25
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            drop: ["ALL"]
          seccompProfile:
            type: RuntimeDefault
```

Or, simpler: remove the `runAsUser: 0` line entirely and let the image's default UID (101) apply.

-----

## Common Mistakes

### Forgetting that Restricted is a superset of Baseline

Restricted requires every Baseline control plus the hardening four (runAsNonRoot, allowPrivilegeEscalation, capabilities.drop, seccompProfile). A pod that passes Baseline might still fail Restricted on any of the four, and the rejection message can list all four at once for a completely unhardened pod. Read the message fully and fix every listed violation in one edit; iterating one-at-a-time through four separate rejections wastes clock time.

### PSA enforce applies only to Pod objects

A Deployment, StatefulSet, or Job whose pod template violates enforce is accepted by the API server (no immediate rejection on apply). The rejection happens when the ReplicaSet or Job controller tries to create the pods. The symptom is `readyReplicas: 0` and `FailedCreate` events on the child ReplicaSet (Deployment) or Job. Always check the workload's child events when a controller is not producing pods. Setting audit and warn at the same level as enforce compensates because audit and warn evaluate the workload resource itself, not just the pods.

### Forgetting to use `--overwrite` on relabels

`kubectl label namespace NS pod-security.kubernetes.io/enforce=restricted` fails if the label is already set to something else. You need `--overwrite` to change an existing value. The error is helpful but the command does not tell you "you meant to add --overwrite"; it says the label already exists.

### `runAsNonRoot: true` with `runAsUser: 0`

Setting `runAsNonRoot: true` and `runAsUser: 0` at the same time is a direct contradiction. PSA rejects it at admission, and even if PSA were disabled, the kubelet would reject it at pod start with `CreateContainerConfigError`. When auditing a pod spec that claims to satisfy Restricted, always verify that the effective `runAsUser` is not zero.

### Version pins on mode-version labels, not on the mode labels themselves

The `-version` pin is a separate label. You cannot combine them into one label like `pod-security.kubernetes.io/enforce=restricted:v1.35`. The correct form is two labels: `pod-security.kubernetes.io/enforce=restricted` and `pod-security.kubernetes.io/enforce-version=v1.35`.

### Exemptions are cluster-scoped, not namespace-labeled

You cannot exempt a namespace by adding a label to it. Exemptions live in the API server's admission configuration file under `plugins[].name: PodSecurity`, exempting by username, runtime class, or namespace name. In kind, this is cumbersome to set up and usually out of exam scope. The exam question is more likely to be "why is this pod rejected?" than "how do I exempt it?"

-----

## Verification Commands Cheat Sheet

### Check namespace labels

```bash
kubectl get namespace NS --show-labels
kubectl get namespace NS -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'
kubectl get namespace NS -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce-version}'
```

### Attempt and observe apply results

```bash
# apply and capture the message (Warning: or Error:)
kubectl apply -n NS -f pod.yaml
```

### Investigate a Deployment with no ready pods

```bash
kubectl get deployment NAME -n NS
kubectl describe deployment NAME -n NS
kubectl describe rs -n NS -l <app-label>
# Events on the ReplicaSet will show FailedCreate with the PSA violation message
```

### Relabel

```bash
kubectl label namespace NS pod-security.kubernetes.io/enforce=restricted --overwrite
kubectl label namespace NS pod-security.kubernetes.io/enforce-   # remove
```

### Restricted-compliant pod template

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: <non-zero UID>
    seccompProfile:
      type: RuntimeDefault
  containers:
  - securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
```

### Checking PSA is enabled

```bash
nerdctl exec kind-control-plane cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep -E "admission|PodSecurity"
```

If PSA is in the default-enabled set, you will see no explicit reference; that is normal. If it is explicitly enabled or disabled, you will see it in `--enable-admission-plugins` or `--disable-admission-plugins`.
