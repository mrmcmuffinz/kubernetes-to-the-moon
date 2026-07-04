# OPA/Gatekeeper Homework Answers: Audit Mode, Mutation, and Policy Troubleshooting

---

## Exercise 1.1 Solution

**Step 1: Wait for audit and confirm violations:**

```bash
sleep 90
kubectl get k8srequiredlabels11a ex11a-require-labels -o jsonpath='{.status.totalViolations}'
# Expected: 2
```

**Step 2: Read violation details:**

```bash
kubectl get k8srequiredlabels11a ex11a-require-labels -o yaml
# Under status.violations: violating-one (missing app, owner) and violating-two (missing owner)
```

**Step 3: Fix the violating pods:**

```bash
kubectl label pod violating-one app=worker owner=bob -n ex-1-1
kubectl label pod violating-two owner=alice -n ex-1-1
```

`violating-one` needs both labels. `violating-two` already has `app=cache` so only `owner` is missing. Read the violation message carefully before applying labels to avoid adding unnecessary ones.

**Step 4: Wait for next audit and confirm:**

```bash
sleep 90
kubectl get k8srequiredlabels11a ex11a-require-labels -o jsonpath='{.status.totalViolations}'
# Expected: 0
```

The audit timestamp shows when the last audit ran. If violations don't drop immediately, wait for the next cycle. The audit interval is configurable but defaults to 60 seconds.

---

## Exercise 1.2 Solution

**Step 1: Apply the privileged pod (it will be admitted in dryrun):**

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: priv-pod
  namespace: ex-1-2
spec:
  containers:
    - name: shell
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        privileged: true
EOF

kubectl get pod priv-pod -n ex-1-2 -o jsonpath='{.status.phase}'
# Expected: Running (dryrun allows it)
```

**Step 2: Wait and check violation:**

```bash
sleep 90
kubectl get k8sdisallowprivileged12a ex12a-no-privileged -o jsonpath='{.status.totalViolations}'
# Expected: 1
```

**Step 3: Switch to deny:**

```bash
kubectl patch k8sdisallowprivileged12a ex12a-no-privileged \
  --type=merge \
  -p '{"spec":{"enforcementAction":"deny"}}'
```

**Step 4: Verify deny blocks new violating pods:**

```bash
kubectl delete pod priv-pod -n ex-1-2
# Wait for deletion, then try to recreate - should fail
```

**Step 5: Create safe-pod:**

```bash
kubectl run safe-pod \
  --image=busybox:1.36 \
  --command -- sleep 3600 \
  -n ex-1-2
```

The key lesson from this exercise: the existing `priv-pod` (admitted during dryrun) continues running even after you switch to deny. Switching to deny only affects NEW admission requests, not pods already running. To remediate existing violating pods, you must delete and recreate them (or wait for a natural restart, which is why fixing violations before switching to deny is so important).

---

## Exercise 1.3 Solution

**Step 1: Confirm legacy-app violation:**

```bash
sleep 90
kubectl get k8srestrictregistries13a ex13a-restrict-registries \
  -o jsonpath='{.status.violations[0].name}'
# Expected: legacy-app
```

**Step 2: Replace legacy-app with an approved image:**

```bash
kubectl delete pod legacy-app -n ex-1-3

kubectl run legacy-app \
  --image=docker.io/library/busybox:1.36 \
  --labels="app=legacy,owner=bob" \
  --command -- sleep 3600 \
  -n ex-1-3
```

The replacement pod uses `docker.io/library/busybox:1.36` which starts with the allowed prefix `docker.io/library/`.

**Step 3: Confirm violations drop:**

```bash
sleep 90
kubectl get k8srestrictregistries13a ex13a-restrict-registries \
  -o jsonpath='{.status.totalViolations}'
# Expected: 0
```

**Step 4: Switch to deny and verify:**

```bash
kubectl patch k8srestrictregistries13a ex13a-restrict-registries \
  --type=merge \
  -p '{"spec":{"enforcementAction":"deny"}}'

kubectl run blocked-test \
  --image=quay.io/prometheus/busybox:1.36 \
  --dry-run=server \
  -n ex-1-3
# Expected: error from server containing "disallowed registry"
```

---

## Exercise 2.1 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: AssignMetadata
metadata:
  name: ex21-inject-cost-center
spec:
  match:
    scope: Namespaced
    kinds:
      - apiGroups: ["*"]
        kinds: ["Pod"]
    namespaces: [ex-2-1]
    excludedNamespaces: [gatekeeper-system, kube-system]
  location: "metadata/labels/cost-center"
  parameters:
    assign:
      value: "backend"
EOF

kubectl run labeled-pod --image=nginx:1.27 -n ex-2-1

kubectl get pod labeled-pod -n ex-2-1 -o jsonpath='{.metadata.labels.cost-center}'
# Expected: backend
```

For the second pod with an existing `cost-center` label:

```bash
kubectl run existing-label-pod \
  --image=nginx:1.27 \
  --labels="cost-center=frontend" \
  -n ex-2-1

kubectl get pod existing-label-pod -n ex-2-1 -o jsonpath='{.metadata.labels.cost-center}'
# Expected: backend (AssignMetadata overwrites it)
```

AssignMetadata does not have a `MustNotExist` pathTest option like Assign does. It always overwrites the target label or annotation. If you need non-overwriting behavior for metadata, use Assign with a pathTest instead.

---

## Exercise 2.2 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: Assign
metadata:
  name: ex22-readonly-root
spec:
  applyTo:
    - groups: [""]
      kinds: ["Pod"]
      versions: ["v1"]
  match:
    scope: Namespaced
    namespaces: [ex-2-2]
    excludedNamespaces: [gatekeeper-system, kube-system]
  location: "spec/containers/[name:*]/securityContext/readOnlyRootFilesystem"
  parameters:
    assign:
      value: true
    pathTests:
      - subPath: "spec/containers/[name:*]/securityContext/readOnlyRootFilesystem"
        condition: MustNotExist
EOF

kubectl run default-readonly --image=nginx:1.27 -n ex-2-2

kubectl get pod default-readonly -n ex-2-2 \
  -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
# Expected: true
```

For the explicit-false pod:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: explicit-false
  namespace: ex-2-2
spec:
  containers:
    - name: app
      image: nginx:1.27
      securityContext:
        readOnlyRootFilesystem: false
EOF

kubectl get pod explicit-false -n ex-2-2 \
  -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
# Expected: false (MustNotExist condition prevented override)
```

---

## Exercise 2.3 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: Assign
metadata:
  name: ex23-default-cpu-limit
spec:
  applyTo:
    - groups: [""]
      kinds: ["Pod"]
      versions: ["v1"]
  match:
    scope: Namespaced
    namespaces: [ex-2-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
  location: "spec/containers/[name:*]/resources/limits/cpu"
  parameters:
    assign:
      value: "200m"
    pathTests:
      - subPath: "spec/containers/[name:*]/resources/limits/cpu"
        condition: MustNotExist
---
apiVersion: mutations.gatekeeper.sh/v1
kind: Assign
metadata:
  name: ex23-default-memory-limit
spec:
  applyTo:
    - groups: [""]
      kinds: ["Pod"]
      versions: ["v1"]
  match:
    scope: Namespaced
    namespaces: [ex-2-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
  location: "spec/containers/[name:*]/resources/limits/memory"
  parameters:
    assign:
      value: "256Mi"
    pathTests:
      - subPath: "spec/containers/[name:*]/resources/limits/memory"
        condition: MustNotExist
EOF

kubectl run default-limits-pod --image=nginx:1.27 -n ex-2-3

kubectl get pod default-limits-pod -n ex-2-3 \
  -o jsonpath='{.spec.containers[0].resources.limits.cpu}'
# Expected: 200m

kubectl get pod default-limits-pod -n ex-2-3 \
  -o jsonpath='{.spec.containers[0].resources.limits.memory}'
# Expected: 256Mi
```

For `custom-limits-pod`:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: custom-limits-pod
  namespace: ex-2-3
spec:
  containers:
    - name: app
      image: nginx:1.27
      resources:
        limits:
          cpu: "500m"
EOF

kubectl get pod custom-limits-pod -n ex-2-3 \
  -o jsonpath='{.spec.containers[0].resources.limits.cpu}'
# Expected: 500m

kubectl get pod custom-limits-pod -n ex-2-3 \
  -o jsonpath='{.spec.containers[0].resources.limits.memory}'
# Expected: 256Mi
```

---

## Exercise 3.1 Solution

### Diagnosis

Create a test pod and check whether the label appears:

```bash
kubectl run test-pod --image=nginx:1.27 -n ex-3-1

kubectl get pod test-pod -n ex-3-1 -o jsonpath='{.metadata.labels.team}'
# Expected: platform; actual: (empty)
```

The label is not being injected. Describe the mutation resource:

```bash
kubectl describe assignmetadata ex31-inject-team
```

No status errors. The resource is valid. Read the `match` configuration:

```yaml
spec:
  match:
    scope: Namespaced
    kinds:
      - apiGroups: ["apps"]   # <-- BUG: Pods are in apiGroups: [""]
        kinds: ["Pod"]
```

The `apiGroups` is set to `"apps"`. Pods belong to the core API group, which is the empty string `""`. The `apps` group contains Deployments, StatefulSets, ReplicaSets, and DaemonSets. Setting `apiGroups: ["apps"]` for kind `Pod` means the mutation targets resources of kind `Pod` in the `apps` group, which do not exist. Gatekeeper accepts this configuration without error but the mutation never fires.

### Bug Explanation

The `apiGroups` field in a Gatekeeper match block is a filter by API group, not by API version. The core Kubernetes API group (Pods, Services, ConfigMaps, Secrets, Namespaces, PersistentVolumes) uses the empty string `""`. The `apps` group contains workload controllers. Using `"apps"` for Pod filtering causes a silent mismatch: Gatekeeper looks for Pod resources in the `apps` group, finds none, and never applies the mutation. There is no error because the configuration is syntactically valid.

### Fix

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: AssignMetadata
metadata:
  name: ex31-inject-team
spec:
  match:
    scope: Namespaced
    kinds:
      - apiGroups: ["*"]
        kinds: ["Pod"]
    namespaces: [ex-3-1]
    excludedNamespaces: [gatekeeper-system, kube-system]
  location: "metadata/labels/team"
  parameters:
    assign:
      value: "platform"
EOF
```

Delete the existing test pod and recreate it to trigger the mutation:

```bash
kubectl delete pod test-pod -n ex-3-1
kubectl run test-pod --image=nginx:1.27 -n ex-3-1

kubectl get pod test-pod -n ex-3-1 -o jsonpath='{.metadata.labels.team}'
# Expected: platform
```

---

## Exercise 3.2 Solution

### Diagnosis

Wait for the audit cycle and check violations:

```bash
sleep 90
kubectl get k8srequiredlabels32a ex32a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 2; actual: 0
```

The constraint reports 0 violations despite clearly non-compliant pods existing. Check the constraint's audit timestamp to confirm audit did run:

```bash
kubectl get k8srequiredlabels32a ex32a-require-labels \
  -o jsonpath='{.status.auditTimestamp}'
# Shows a recent timestamp: audit ran, but found nothing
```

Read the constraint's full match configuration:

```bash
kubectl get k8srequiredlabels32a ex32a-require-labels -o yaml | grep -A20 "match:"
```

You will see:

```yaml
match:
  kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  namespaces: [ex-3-2]
  excludedNamespaces: [gatekeeper-system, kube-system]
  labelSelector:
    matchLabels:
      audit-scope: "yes"
```

The `labelSelector.matchLabels: {audit-scope: "yes"}` restricts the constraint to pods that CARRY this label. Only `labeled-one` (which has `audit-scope=yes`) is evaluated. `no-labels-one` and `no-labels-two` don't have `audit-scope=yes`, so they're invisible to this constraint. And `labeled-one` has both required labels (`app` and `owner`), so no violation fires.

### Bug Explanation

The `spec.match.labelSelector` field filters which RESOURCE INSTANCES the constraint evaluates, based on labels on those resources. It is not a namespace selector. Adding `labelSelector: matchLabels: {audit-scope: "yes"}` means the constraint only checks pods that happen to carry that specific label. Non-compliant pods without that label are never evaluated. This is a common misconfiguration when trying to target a subset of resources: the intent is usually to scope by namespace, not by pod labels.

### Fix

Remove the `labelSelector` from the constraint match:

```bash
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels32a
metadata:
  name: ex32a-require-labels
spec:
  enforcementAction: dryrun
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-3-2]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    labels: ["app", "owner"]
EOF
```

---

## Exercise 3.3 Solution

### Diagnosis

Test pod creation in gatekeeper-system:

```bash
kubectl run gk-test \
  --image=busybox:1.36 \
  --command -- sleep 30 \
  --dry-run=server \
  -n gatekeeper-system
# Expected (before fix): error from server containing "Required labels missing"
```

The constraint is blocking gatekeeper-system pods. Read the constraint:

```bash
kubectl get k8srequiredlabels33a ex33a-require-labels -o yaml | grep -A10 "match:"
```

```yaml
match:
  kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  namespaces:
    - ex-3-3
    - gatekeeper-system
```

The `namespaces` field explicitly lists `gatekeeper-system` as a target. This means Gatekeeper's own pods are subject to the constraint. When Gatekeeper's controller-manager tries to restart during an upgrade or crash, new pods may be blocked if they don't have `app` and `owner` labels (which Gatekeeper pods typically don't use as standard labels). This can create a situation where Gatekeeper cannot recover: the webhook is down (the pod crashed), but the webhook's failurePolicy: Fail means no new pods can start.

### Bug Explanation

The `namespaces` field in `spec.match` is a whitelist: only resources in listed namespaces are evaluated. Adding `gatekeeper-system` to this list makes Gatekeeper pods subject to the constraint. The correct approach is to use `excludedNamespaces` to explicitly exempt system namespaces. The `namespaces` and `excludedNamespaces` fields have inverse semantics: `namespaces` is an allowlist (only target these) and `excludedNamespaces` is a denylist (never target these). Using `namespaces` to target specific namespaces is valid, but you must also exclude system namespaces using `excludedNamespaces`, because `namespaces` alone doesn't automatically exempt them.

### Fix

Change from using `namespaces` (which explicitly included gatekeeper-system) to scoping only to `ex-3-3` with explicit exclusions:

```bash
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels33a
metadata:
  name: ex33a-require-labels
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - ex-3-3
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  parameters:
    labels: ["app", "owner"]
EOF
```

---

## Exercise 4.1 Solution

**Step 1: Create constraint in dryrun targeting both namespaces:**

```bash
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels41a
metadata:
  name: ex41a-require-labels
spec:
  enforcementAction: dryrun
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-4-1-alpha, ex-4-1-beta]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    labels: ["app", "team"]
EOF
```

**Step 2: Confirm violations:**

```bash
sleep 90
kubectl get k8srequiredlabels41a ex41a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 2
```

**Step 3: Fix violating pods:**

```bash
kubectl label pod alpha-violating app=worker team=platform -n ex-4-1-alpha
kubectl label pod beta-violating app=db team=data -n ex-4-1-beta
```

**Step 4: Confirm zero violations:**

```bash
sleep 90
kubectl get k8srequiredlabels41a ex41a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 0
```

**Step 5: Switch to deny:**

```bash
kubectl patch k8srequiredlabels41a ex41a-require-labels \
  --type=merge \
  -p '{"spec":{"enforcementAction":"deny"}}'
```

**Step 6 and 7: Label alpha and switch to namespaceSelector:**

```bash
kubectl label namespace ex-4-1-alpha enforce=v1

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels41a
metadata:
  name: ex41a-require-labels
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaceSelector:
      matchLabels:
        enforce: v1
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    labels: ["app", "team"]
EOF
```

---

## Exercise 4.2 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: AssignMetadata
metadata:
  name: ex42-inject-managed-by
spec:
  match:
    scope: Namespaced
    kinds:
      - apiGroups: ["*"]
        kinds: ["Pod"]
    namespaceSelector:
      matchLabels:
        tier: managed
    excludedNamespaces: [gatekeeper-system, kube-system]
  location: "metadata/annotations/managed-by"
  parameters:
    assign:
      value: "gatekeeper"
EOF

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiremanagedby42
spec:
  crd:
    spec:
      names:
        kind: K8sRequireManagedBy42
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiremanagedby42

        violation[{"msg": msg}] {
          not input.review.object.metadata.labels.app
          msg := "Pod is missing required label: app"
        }

        violation[{"msg": msg}] {
          not input.review.object.metadata.annotations["managed-by"]
          msg := "Pod is missing required annotation: managed-by"
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireManagedBy42
metadata:
  name: ex42-require-managed-by
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-4-2]
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF

kubectl run managed-pod \
  --image=nginx:1.27 \
  --labels="app=api" \
  -n ex-4-2
```

The pod is admitted because the AssignMetadata mutation injects `managed-by=gatekeeper` during admission, before the validator runs. The validator sees both `app=api` (user-provided) and `managed-by=gatekeeper` (injected) and finds no violations.

---

## Exercise 4.3 Solution

**Apply the Config resource:**

```bash
kubectl apply -f - <<EOF
apiVersion: config.gatekeeper.sh/v1alpha1
kind: Config
metadata:
  name: config
  namespace: gatekeeper-system
spec:
  sync:
    syncOnly:
      - group: ""
        version: "v1"
        kind: "Namespace"
      - group: ""
        version: "v1"
        kind: "Pod"
EOF
```

**Create the CT and constraint:**

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels43a
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels43a
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels43a

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Required labels missing: %v", [missing])
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels43a
metadata:
  name: ex43a-require-labels
spec:
  enforcementAction: dryrun
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-4-3-north, ex-4-3-south]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    labels: ["app", "owner"]
EOF
```

**Fix violations and confirm:**

```bash
sleep 90
kubectl label pod north-violating app=north-app owner=karl -n ex-4-3-north
kubectl label pod south-violating app=south-app owner=luna -n ex-4-3-south

sleep 90
kubectl get k8srequiredlabels43a ex43a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 0
```

---

## Exercise 5.1 Solution

### Diagnosis

Try to create any pod in `ex-5-1`:

```bash
kubectl run test-pod \
  --image=nginx:1.27 \
  --labels="app=web,owner=ian" \
  -n ex-5-1
# Expected: created; actual: error from server "Pods with env=production label require a production-approval annotation"
```

The pod is rejected even though the user did not set `env=production`. Inspect what labels the pod would actually have by examining the mutation:

```bash
kubectl describe assignmetadata ex51-inject-env
```

The AssignMetadata resource injects `env=production` on ALL pods in `ex-5-1`. The validator then checks `input.review.object.metadata.labels.env == "production"` and fires the violation. The admission chain is: user submits pod → mutation injects `env=production` → validator sees `env=production` → validator blocks the pod. Every pod in the namespace is blocked because the mutation runs first.

### What the bugs are and why they happen

This is a mutation-validation conflict. The mutation was written to tag pods with an environment label, and the validator was written to block unvetted production pods. Neither policy is individually wrong, but together they create a deadlock: the mutation marks everything as production, and the validator blocks everything marked as production. The conflict reveals a design flaw: the mutation should not inject `production` as the default. A safer default would be `env=development` or the annotation requirement check in the validator should not apply to pods injected by the mutation automatically.

### Fix

The cleanest fix is to change the mutation to inject a different, non-blocking label value, or to change the validator to not apply to pods that received the label via mutation. For this exercise, change the AssignMetadata to inject `env=development` instead of `env=production`:

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: AssignMetadata
metadata:
  name: ex51-inject-env
spec:
  match:
    scope: Namespaced
    kinds:
      - apiGroups: ["*"]
        kinds: ["Pod"]
    namespaces: [ex-5-1]
    excludedNamespaces: [gatekeeper-system, kube-system]
  location: "metadata/labels/env"
  parameters:
    assign:
      value: "development"
EOF
```

After applying the fix, pod creation succeeds:

```bash
kubectl run test-pod \
  --image=nginx:1.27 \
  --labels="app=web,owner=ian" \
  -n ex-5-1

kubectl get pod test-pod -n ex-5-1 -o jsonpath='{.status.phase}'
# Expected: Running
```

---

## Exercise 5.2 Solution

### Diagnosis

Try to create a pod:

```bash
kubectl run test-pod --image=nginx:1.27 --dry-run=server -n ex-5-2
# Expected: success; actual: error containing "Pod must set securityContext.runAsNonRoot: true"
```

The pod is blocked for having `runAsNonRoot: false`. But the user didn't set that field. Inspect the Assign mutation:

```bash
kubectl describe assign ex52-set-run-as-nonroot
```

The mutation sets `spec/securityContext/runAsNonRoot` to `false`. The validator then checks `input.review.object.spec.securityContext.runAsNonRoot == false` and fires the violation. The mutation injects `false`, then the validator blocks `false`.

The conflict is clear: the mutation injects `false`, and the validator blocks `false`. They are directly opposed.

### What the bugs are and why they happen

The Assign mutation is injecting the wrong value. The intent (based on the validator) is to enforce `runAsNonRoot: true`. The mutation should be setting `true` to act as a safe default for pods that don't specify this field. Instead it is setting `false`, which creates an immediate violation for every pod that doesn't explicitly set `runAsNonRoot`.

A secondary observation: even if the mutation injected `true`, the validator's condition `runAsNonRoot == false` would fire for pods that explicitly set `runAsNonRoot: false`. That is correct validator behavior. The mutation just needs to inject the right default.

### Fix

Change the Assign mutation value from `false` to `true`:

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: Assign
metadata:
  name: ex52-set-run-as-nonroot
spec:
  applyTo:
    - groups: [""]
      kinds: ["Pod"]
      versions: ["v1"]
  match:
    scope: Namespaced
    namespaces: [ex-5-2]
    excludedNamespaces: [gatekeeper-system, kube-system]
  location: "spec/securityContext/runAsNonRoot"
  parameters:
    assign:
      value: true
    pathTests:
      - subPath: "spec/securityContext/runAsNonRoot"
        condition: MustNotExist
EOF
```

---

## Exercise 5.3 Solution

### Diagnosis

Try to create a `tier=api` pod without explicit CPU limits:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api-pod
  namespace: ex-5-3
  labels:
    tier: api
    app: service
    owner: jane
spec:
  containers:
    - name: app
      image: nginx:1.27
EOF
# Expected: success; actual: error "CPU limit 50m is below minimum 100m for tier=api pods"
```

The pod is blocked because its CPU limit is `50m`. But the user did not set a CPU limit. Inspect the mutation:

```bash
kubectl describe assign ex53-inject-default-limits
```

The Assign mutation injects `cpu: 50m` as the default when no CPU limit is set. The validator then checks pods with `tier=api` label and finds CPU limit `50m`, which is below the required `100m` minimum.

The pipeline: user submits pod with no CPU limit → mutation injects `cpu: 50m` → validator checks `tier=api` pods for CPU limit → finds `50m < 100m` → blocks the pod.

### What the bug is and why it happens

The mutation's default CPU limit (`50m`) is below the validator's minimum (`100m`) for `tier=api` pods. The mutation was likely authored with general-purpose pods in mind, where 50m is adequate. The validator was authored for API-tier pods specifically, where 100m is the minimum. Neither policy was wrong individually, but they were not designed together: the mutation's default falls below the validator's minimum for a specific pod class.

This is a coordination failure between two independently authored policies. The fix is to either raise the mutation's default to meet the validator's minimum, or create a separate mutation with a higher default that only applies to `tier=api` pods.

### Fix

Update the Assign mutation to inject `100m` as the default CPU limit (satisfying the validator's minimum):

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: Assign
metadata:
  name: ex53-inject-default-limits
spec:
  applyTo:
    - groups: [""]
      kinds: ["Pod"]
      versions: ["v1"]
  match:
    scope: Namespaced
    namespaces: [ex-5-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
  location: "spec/containers/[name:*]/resources/limits/cpu"
  parameters:
    assign:
      value: "100m"
    pathTests:
      - subPath: "spec/containers/[name:*]/resources/limits/cpu"
        condition: MustNotExist
EOF
```

After applying the fix, the pod creation succeeds. The mutation injects `100m`, which satisfies the `>= 100m` validator requirement for `tier=api` pods.

---

## Common Mistakes

**Switching a constraint to deny before fixing existing violations.** The most dangerous rollout mistake. Once you switch to deny, any pod that crashes, gets evicted, or is rescheduled may fail to restart if it violates the policy. The fix: always use dryrun first, remediate all violations shown in audit status, confirm `totalViolations` is 0, then switch to deny. The audit status gives you the full picture before you create an incident.

**Using `apiGroups: ["apps"]` to target Pods in a mutation.** Pods are in the core API group `""`, not the `apps` group. Using `apiGroups: ["apps"]` for `kinds: ["Pod"]` is a silent miss: Gatekeeper accepts the configuration, but the mutation never fires because no Pod resources exist in the `apps` group. Always use `""` or `"*"` as the apiGroups value when targeting core resources like Pods, Services, and ConfigMaps.

**Forgetting `applyTo` on Assign resources.** `AssignMetadata` does not require `applyTo`; `Assign` does. An Assign resource without `applyTo` is accepted by Gatekeeper but applies to nothing. The symptom is identical to wrong `match` criteria: the resource exists, describes no errors, but the injected field never appears on created resources.

**Writing mutations without `pathTests: MustNotExist`.** Without this condition, the mutation overwrites any value the user set explicitly. This breaks workloads that legitimately need a setting different from the default (for example, a pod that needs `readOnlyRootFilesystem: false` because it writes temporary files to the root filesystem). Always use `pathTests: MustNotExist` for default-injection mutations so users can opt out.

**Diagnosing mutation failures by looking at the submitted spec.** When a pod is blocked by a validator, the error message describes what the validator saw, which is the MUTATED spec, not what the user submitted. If you compare the error to the user's YAML and it doesn't match, mutations are the cause. Always check `kubectl describe assignmetadata` and `kubectl describe assign` to understand what fields are being injected before blaming the validator or the user.

**Using `namespaces` to include gatekeeper-system.** The `namespaces` field in constraint match is an allowlist of namespaces to target. If `gatekeeper-system` appears in `namespaces`, Gatekeeper pods are subject to the constraint. If Gatekeeper's pods violate the constraint (e.g., missing required labels) and the constraint is in deny mode, Gatekeeper pods cannot restart after a crash, creating a self-inflicted denial of service. Always include `excludedNamespaces: [gatekeeper-system, kube-system]` in every constraint regardless of which `namespaces` are in the target list.

---

## Verification Commands Cheat Sheet

| Task | Command |
|---|---|
| Check constraint violation count | `kubectl get <kind> <name> -o jsonpath='{.status.totalViolations}'` |
| Read violation details | `kubectl get <kind> <name> -o yaml` |
| Check last audit timestamp | `kubectl get <kind> <name> -o jsonpath='{.status.auditTimestamp}'` |
| List all AssignMetadata resources | `kubectl get assignmetadata` |
| Inspect mutation status | `kubectl describe assignmetadata <name>` |
| Inspect Assign status | `kubectl describe assign <name>` |
| Verify label injected by mutation | `kubectl get pod <name> -o jsonpath='{.metadata.labels.<key>}'` |
| Verify annotation injected | `kubectl get pod <name> -o jsonpath='{.metadata.annotations.<key>}'` |
| Verify spec field injected | `kubectl get pod <name> -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'` |
| Verify resource limits injected | `kubectl get pod <name> -o jsonpath='{.spec.containers[0].resources.limits.cpu}'` |
| Change enforcementAction | `kubectl patch <kind> <name> --type=merge -p '{"spec":{"enforcementAction":"deny"}}'` |
| Read Gatekeeper controller logs | `kubectl logs -n gatekeeper-system -l control-plane=controller-manager --tail=50` |
| Check webhook failurePolicy | `kubectl get validatingwebhookconfiguration gatekeeper-validating-webhook-configuration -o yaml \| grep failurePolicy` |
| Check MutatingWebhookConfiguration | `kubectl get mutatingwebhookconfiguration gatekeeper-mutating-webhook-configuration` |
| View Config resource | `kubectl get config config -n gatekeeper-system -o yaml` |
| Force audit cycle restart | `kubectl delete pod -n gatekeeper-system -l control-plane=audit-controller` |
