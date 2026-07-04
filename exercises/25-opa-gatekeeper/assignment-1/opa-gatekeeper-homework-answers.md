# OPA/Gatekeeper Homework Answers: ConstraintTemplates and Policy Enforcement

---

## Exercise 1.1 Solution

Create the compliant pod with both required labels:

```bash
kubectl run web-compliant \
  --image=nginx:1.27 \
  --labels="app=frontend,owner=alice" \
  -n ex-1-1
```

Verify it is running:

```bash
kubectl get pod web-compliant -n ex-1-1 -o jsonpath='{.status.phase}'
# Expected: Running
```

Test the violating case (dry-run so no persistent pod is created):

```bash
kubectl run web-missing --image=nginx:1.27 --dry-run=server -n ex-1-1
# Expected: error from server containing "Required labels are missing"
```

The `--dry-run=server` flag sends the request to the API server, which runs it through admission webhooks including Gatekeeper, but does not persist the resource. This is the correct pattern for testing policy enforcement without cluttering the namespace with rejected pods.

---

## Exercise 1.2 Solution

Create the non-privileged pod:

```bash
kubectl run safe-app \
  --image=busybox:1.36 \
  --command \
  -- sleep 3600 \
  -n ex-1-2
```

Verify:

```bash
kubectl get pod safe-app -n ex-1-2 -o jsonpath='{.status.phase}'
# Expected: Running
```

The privileged main container and privileged initContainer tests are verification steps from the homework and should both produce errors from the server. If they pass without error, the CT's Rego or the Constraint's match configuration is incorrect.

---

## Exercise 1.3 Solution

Create the compliant pod using the full image reference with the allowed registry prefix:

```bash
kubectl run approved-app \
  --image=docker.io/library/nginx:1.27 \
  -n ex-1-3
```

Verify:

```bash
kubectl get pod approved-app -n ex-1-3 -o jsonpath='{.status.phase}'
# Expected: Running
```

The blocked test:

```bash
kubectl run blocked-app \
  --image=quay.io/prometheus/busybox:1.36 \
  --dry-run=server \
  -n ex-1-3
# Expected: error from server containing "uses a disallowed registry"
```

Note that `nginx:1.27` (without an explicit registry) would also be blocked by this policy because it does not start with `docker.io/library/`. This is intentional: using explicit registry prefixes is better hygiene and makes policy enforcement unambiguous.

---

## Exercise 2.1 Solution

**Step 1: Create the Constraint in dryrun mode:**

```bash
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRestrictRegistries21
metadata:
  name: ex21-restrict-registries
spec:
  enforcementAction: dryrun
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-2-1]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    allowedRegistries:
      - "docker.io/library/"
EOF
```

**Step 2: Deploy the violating pod:**

```bash
kubectl run violating-dryrun \
  --image=quay.io/prometheus/busybox:1.36 \
  --command -- sleep 3600 \
  -n ex-2-1
```

The pod should be created because `enforcementAction: dryrun` allows it through.

**Step 3: Wait for audit and check status:**

```bash
sleep 90
kubectl get k8srestrictregistries21 ex21-restrict-registries -o jsonpath='{.status.totalViolations}'
# Expected: 1
```

The audit controller checks existing resources on its interval (default 60 seconds). After one full cycle the violation appears in `status.totalViolations`.

**Step 4: Switch to deny:**

```bash
kubectl patch k8srestrictregistries21 ex21-restrict-registries \
  --type=merge \
  -p '{"spec":{"enforcementAction":"deny"}}'
```

**Step 5: Verify deny mode:**

```bash
kubectl run violating-deny-test \
  --image=quay.io/prometheus/busybox:1.36 \
  --dry-run=server \
  -n ex-2-1
# Expected: error from server containing "not from an allowed registry"
```

The key lesson: `dryrun` is the safe rollout path. You discover violations without disrupting existing workloads, fix them, then promote to `deny`. The `violating-dryrun` pod that was admitted during dryrun mode continues running, but no new violating pods can be created after the switch to deny.

---

## Exercise 2.2 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels22
metadata:
  name: ex22-require-labels
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaceSelector:
      matchLabels:
        policy: enforced
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  parameters:
    labels: ["app", "team"]
EOF
```

The `namespaceSelector.matchLabels` key uses the namespace label `policy=enforced`. Namespace `ex-2-2` was labeled with this value in the setup; `ex-2-2-open` was not. Gatekeeper evaluates the `namespaceSelector` against the labels on the target namespace at request time.

Verification confirms the scoping: the same pod spec is blocked in `ex-2-2` (labeled, enforced) and admitted in `ex-2-2-open` (unlabeled, exempt).

---

## Exercise 2.3 Solution

```bash
kubectl run compliant-all \
  --image=nginx:1.27 \
  --labels="app=api,owner=bob" \
  -n ex-2-3
```

Wait for the pod to start, then verify:

```bash
kubectl get pod compliant-all -n ex-2-3 -o jsonpath='{.status.phase}'
# Expected: Running
```

For the multi-violation test, the pod violates all three constraints simultaneously. Gatekeeper collects all violations across all matching constraints and returns them in one error response. The error message will contain violations from `ex23-require-labels`, `ex23-no-privileged`, and `ex23-require-limits` separated by commas.

---

## Exercise 3.1 Solution

### Diagnosis

Start by checking the ConstraintTemplate status:

```bash
kubectl describe constrainttemplate k8sdisallowprivileged31
```

Look at the `Status` section, specifically `By Pod`. You will see something like:

```text
Status:
  By Pod:
    Errors:
      Code:          rego_parse_error
      Location:      1:9
      Message:       1 error occurred: ...sprint is not defined
```

The Rego code uses `sprint(...)` which is not a valid Rego built-in function. The correct function is `sprintf(...)`. Because the Rego compilation failed, the policy is not active: no admission check runs, so all pods are admitted regardless of their configuration.

### Bug Explanation

Rego's string formatting function is `sprintf`, not `sprint`. When Gatekeeper loads the ConstraintTemplate, it compiles the Rego code. An undefined function reference is a compilation error. The template is stored in etcd but the policy is not enforced because there is no valid compiled policy to evaluate. The compilation error is visible in the ConstraintTemplate's status but does not cause the `kubectl apply` to fail: Gatekeeper accepts the resource and records the error in status.

### Fix

Edit the ConstraintTemplate to replace `sprint` with `sprintf`:

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowprivileged31
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowPrivileged31
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowprivileged31

        violation[{"msg": msg}] {
          c := input.review.object.spec.containers[_]
          c.securityContext.privileged == true
          msg := sprintf("Container %v is running as privileged", [c.name])
        }
EOF
```

Wait a few seconds for Gatekeeper to recompile, then confirm the policy is active:

```bash
kubectl describe constrainttemplate k8sdisallowprivileged31
# Look for: no errors in status.byPod
```

---

## Exercise 3.2 Solution

### Diagnosis

Test the policy with a pod that should be blocked:

```bash
kubectl run no-labels-test --image=nginx:1.27 --dry-run=server -n ex-3-2
# Expect: blocked; instead: pod/no-labels-test created (dry run)
```

The pod gets through. Check the CT status for compilation errors:

```bash
kubectl describe constrainttemplate k8srequiredlabels32
```

No compilation errors are present. The Rego is syntactically valid. The issue is a logic error. Read the Rego carefully:

```rego
provided := {label | input.review.object.spec.labels[label]}
```

Compare this to the correct path: `input.review.object.metadata.labels`. Pod objects have labels under `.metadata.labels`, not `.spec.labels`. The `spec` of a pod does not have a `labels` field. When the Rego evaluates `input.review.object.spec.labels[label]`, it finds nothing (the field does not exist), so `provided` evaluates to an empty set. Then `required - provided` equals `required` (all required labels are "missing"), and `count(missing) > 0` should be true.

Wait -- if `provided` is always empty, then all labels are always missing, and the violation should always fire. But we observed the pod was admitted. Why?

The reason is that when a Rego comprehension iterates over a non-existent field, the entire comprehension produces an empty set. So `provided = {}`. And `required = {"app", "owner"}`. Then `missing = {"app","owner"} - {} = {"app","owner"}`. `count(missing) = 2 > 0` is true. This should fire the violation. But the pod was admitted.

Check whether there is an issue with the namespace scoping by testing without dry-run in a different namespace:

```bash
kubectl describe constraint ex32-require-labels
```

Review the match.namespaces field. The constraint targets `ex-3-2`. The pod creation is in `ex-3-2`. That should match.

Actually: re-read the Rego above more carefully. The policy should fire for ALL pods (since provided is always empty). Try a pod WITH the required labels:

```bash
kubectl run labeled-test \
  --image=nginx:1.27 \
  --labels="app=api,owner=charlie" \
  --dry-run=server \
  -n ex-3-2
# This should also be blocked (because provided=empty, missing=all), but is it?
```

If both labeled and unlabeled pods are blocked, the real fix is just to correct the field path so the policy works correctly. But if both are admitted, there's an additional issue (perhaps the Rego compiled with a different error path).

The fix is clear regardless: change `spec.labels` to `metadata.labels`.

### Bug Explanation

Pod metadata fields (name, namespace, labels, annotations) live under `.metadata`, not `.spec`. The `.spec` of a pod contains containers, volumes, nodeSelector, tolerations, and similar scheduling and runtime configuration. Using `input.review.object.spec.labels` accesses a field that does not exist in a pod spec, producing an empty set for `provided`. While this technically means the violation should fire (all labels are "missing"), in practice Rego's undefined-field behavior combined with the comprehension syntax means the policy either always fires or never fires depending on how Gatekeeper evaluates undefined intermediate values. The correct fix is the right field path.

### Fix

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels32
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels32
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
        package k8srequiredlabels32

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Required labels are missing: %v", [missing])
        }
EOF
```

---

## Exercise 3.3 Solution

### Diagnosis

Test with a pod that has limits:

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: with-limits
  namespace: ex-3-3
spec:
  containers:
    - name: app
      image: nginx:1.27
      resources:
        limits:
          cpu: "200m"
          memory: "256Mi"
EOF
# Expected: admitted; actual: blocked
```

The pod with limits is blocked. Now test without limits:

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: no-limits
  namespace: ex-3-3
spec:
  containers:
    - name: app
      image: nginx:1.27
EOF
# Expected: blocked; actual: admitted
```

The behavior is exactly backwards. Read the Rego:

```rego
violation[{"msg": msg}] {
  c := input.review.object.spec.containers[_]
  c.resources.limits.cpu
  msg := sprintf("Container %v must not set a CPU limit", [c.name])
}
```

The condition `c.resources.limits.cpu` without `not` evaluates to true when the field EXISTS and is truthy. So the violation fires when a container HAS a CPU limit. The message even says "must not set a CPU limit" which is the inverted intent. The violation should fire when the limit is ABSENT, which requires `not c.resources.limits.cpu`. Additionally, the policy has no memory limit check.

### Bug Explanation

In Rego, `c.resources.limits.cpu` as a bare condition is a truthiness check: the rule body only continues evaluating if this expression is defined and non-falsy. This fires when the CPU limit exists. Adding `not` inverts this: `not c.resources.limits.cpu` is true when the field is absent (undefined) or falsy. The common error is forgetting `not` in presence-checking policies, causing the policy to fire for compliant resources and admit violating ones. The violation message in the broken version ("must not set a CPU limit") was also backwards, making this a double red flag during diagnosis.

### Fix

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequireresourcelimits33
spec:
  crd:
    spec:
      names:
        kind: K8sRequireResourceLimits33
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequireresourcelimits33

        violation[{"msg": msg}] {
          c := input.review.object.spec.containers[_]
          not c.resources.limits.cpu
          msg := sprintf("Container %v is missing a CPU limit", [c.name])
        }

        violation[{"msg": msg}] {
          c := input.review.object.spec.containers[_]
          not c.resources.limits.memory
          msg := sprintf("Container %v is missing a memory limit", [c.name])
        }
EOF
```

---

## Exercise 4.1 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequireresourcelimits41
spec:
  crd:
    spec:
      names:
        kind: K8sRequireResourceLimits41
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequireresourcelimits41

        violation[{"msg": msg}] {
          c := input_containers[_]
          not c.resources.limits.cpu
          msg := sprintf("Container %v is missing a CPU limit", [c.name])
        }

        violation[{"msg": msg}] {
          c := input_containers[_]
          not c.resources.limits.memory
          msg := sprintf("Container %v is missing a memory limit", [c.name])
        }

        input_containers[c] {
          c := input.review.object.spec.containers[_]
        }

        input_containers[c] {
          c := input.review.object.spec.initContainers[_]
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireResourceLimits41
metadata:
  name: ex41-require-limits
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-4-1]
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF
```

The `input_containers` helper is defined twice using two separate rule bodies. Rego treats these as OR: a container is in `input_containers` if it matches either definition. The violation block iterates over the complete set, checking CPU and memory limits for every container regardless of whether it is a regular or init container.

---

## Exercise 4.2 Solution

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srestrictregistries42
spec:
  crd:
    spec:
      names:
        kind: K8sRestrictRegistries42
      validation:
        openAPIV3Schema:
          type: object
          properties:
            allowedRegistries:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srestrictregistries42

        violation[{"msg": msg}] {
          c := input_containers[_]
          not registry_allowed(c.image)
          msg := sprintf("Container %v uses a disallowed registry. Image: %v. Allowed registries: %v", [c.name, c.image, input.parameters.allowedRegistries])
        }

        input_containers[c] {
          c := input.review.object.spec.containers[_]
        }

        input_containers[c] {
          c := input.review.object.spec.initContainers[_]
        }

        registry_allowed(image) {
          prefix := input.parameters.allowedRegistries[_]
          startswith(image, prefix)
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRestrictRegistries42
metadata:
  name: ex42-restrict-registries
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-4-2]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    allowedRegistries:
      - "docker.io/library/"
      - "registry.k8s.io/"
EOF

kubectl run valid-registry \
  --image=docker.io/library/nginx:1.27 \
  -n ex-4-2
```

---

## Exercise 4.3 Solution

The exercise leaves the ConstraintTemplate choice to you. If the templates from exercises 4.1 and 4.2 are still present, create new constraints that use namespaceSelector:

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels43
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels43
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
        package k8srequiredlabels43

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Required labels missing: %v", [missing])
        }
---
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowprivileged43
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowPrivileged43
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowprivileged43

        violation[{"msg": msg}] {
          c := input_containers[_]
          c.securityContext.privileged == true
          msg := sprintf("Privileged container not allowed: %v", [c.name])
        }

        input_containers[c] { c := input.review.object.spec.containers[_] }
        input_containers[c] { c := input.review.object.spec.initContainers[_] }
---
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequireresourcelimits43
spec:
  crd:
    spec:
      names:
        kind: K8sRequireResourceLimits43
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequireresourcelimits43

        violation[{"msg": msg}] {
          c := input.review.object.spec.containers[_]
          not c.resources.limits.cpu
          msg := sprintf("Container %v missing CPU limit", [c.name])
        }

        violation[{"msg": msg}] {
          c := input.review.object.spec.containers[_]
          not c.resources.limits.memory
          msg := sprintf("Container %v missing memory limit", [c.name])
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels43
metadata:
  name: ex43-require-labels
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaceSelector:
      matchLabels:
        security: strict
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    labels: ["app", "team"]
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowPrivileged43
metadata:
  name: ex43-no-privileged
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaceSelector:
      matchLabels:
        security: strict
    excludedNamespaces: [gatekeeper-system, kube-system]
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireResourceLimits43
metadata:
  name: ex43-require-limits
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaceSelector:
      matchLabels:
        security: strict
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: strict-compliant
  namespace: ex-4-3-enforced
  labels:
    app: api
    team: platform
spec:
  containers:
    - name: app
      image: nginx:1.27
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
EOF
```

---

## Exercise 5.1 Solution

### Diagnosis

Test whether a disallowed image is blocked:

```bash
kubectl run blocked-quay \
  --image=quay.io/prometheus/busybox:1.36 \
  --dry-run=server \
  -n ex-5-1
# Expected: blocked; actual: admitted (no error)
```

Test whether an allowed image is admitted:

```bash
kubectl run allowed-docker \
  --image=docker.io/library/nginx:1.27 \
  --dry-run=server \
  -n ex-5-1
# Expected: admitted; actual: error (blocked)
```

The behavior is reversed: allowed images are blocked, disallowed images are admitted. Read the Rego:

```rego
violation[{"msg": msg}] {
  c := input_containers[_]
  registry_allowed(c.image)         # <-- fires when registry IS allowed (missing "not")
  msg := sprintf("Container %v image %v is from an approved registry", [c.name, c.image])
}
```

The violation fires when `registry_allowed(c.image)` is true, which is when the image IS from an allowed registry. The `not` keyword is missing before `registry_allowed(c.image)`. The violation message even says "is from an approved registry," which is the inverted intent.

Second issue: `input_containers` only includes `spec.containers`, not `spec.initContainers`:

```rego
input_containers[c] {
  c := input.review.object.spec.containers[_]
}
# initContainers rule is missing
```

### What the bugs are and why they happen

Bug 1 (missing `not`): This is the most common Gatekeeper authoring mistake. The violation block should fire when the condition is bad. For a "blocklist" style policy (block if NOT in allowed list), the violation requires `not registry_allowed(c.image)`. Dropping the `not` makes it a "fire if in allowlist" policy, which is the opposite intent. The violation message being backwards is a diagnostic signal: always read the message and check if it describes a violation or a compliance state.

Bug 2 (missing initContainers): The `input_containers` helper was defined only for `spec.containers`. A pod with a disallowed image only in an initContainer would slip through undetected.

### Fix

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srestrictregistries51
spec:
  crd:
    spec:
      names:
        kind: K8sRestrictRegistries51
      validation:
        openAPIV3Schema:
          type: object
          properties:
            allowedRegistries:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srestrictregistries51

        violation[{"msg": msg}] {
          c := input_containers[_]
          not registry_allowed(c.image)
          msg := sprintf("Container %v image %v is not from an allowed registry. Allowed: %v", [c.name, c.image, input.parameters.allowedRegistries])
        }

        input_containers[c] {
          c := input.review.object.spec.containers[_]
        }

        input_containers[c] {
          c := input.review.object.spec.initContainers[_]
        }

        registry_allowed(image) {
          prefix := input.parameters.allowedRegistries[_]
          startswith(image, prefix)
        }
EOF
```

---

## Exercise 5.2 Solution

### Diagnosis

Test whether a pod without labels is blocked:

```bash
kubectl run missing-labels --image=nginx:1.27 --dry-run=server -n ex-5-2
# Expected: blocked; actual: admitted
```

Test whether a pod with required labels is admitted:

```bash
kubectl run with-labels \
  --image=nginx:1.27 \
  --labels="app=web,owner=diana" \
  --dry-run=server \
  -n ex-5-2
# Expected: admitted; actual: blocked
```

Reversed behavior again. Read the Rego:

```rego
violation[{"msg": msg}] {
  provided := {label | input.review.object.metadata.labels[label]}
  required := {label | label := input.parameters.labels[_]}
  missing := provided - required
  count(missing) > 0
  msg := sprintf("Unexpected labels found: %v", [missing])
}
```

The set subtraction is `provided - required` when it should be `required - provided`. With `provided - required`, the `missing` set contains labels that the pod has but that are NOT in the required list. This fires when a pod carries extra labels beyond the required ones, which is backwards. The message "Unexpected labels found" is the tell: it describes extra labels, not missing labels.

### What the bug is and why it happens

Set subtraction order matters critically in Rego. `A - B` gives elements in A that are not in B. For a "require these labels" policy, you want `required - provided`: the labels that are required but not present. Writing `provided - required` instead gives the labels that are provided but not required (extra labels), which is the wrong check. The violation message in the broken version reveals the intent was inverted.

### Fix

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels52
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels52
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
        package k8srequiredlabels52

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Required labels are missing: %v", [missing])
        }
EOF
```

---

## Exercise 5.3 Solution

### Diagnosis

Test a privileged main container:

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: priv-main
  namespace: ex-5-3
spec:
  containers:
    - name: app
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        privileged: true
EOF
# Expected: blocked; actual: admitted
```

The privileged main container gets through. Test a privileged initContainer:

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: priv-init
  namespace: ex-5-3
spec:
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["echo", "init"]
      securityContext:
        privileged: true
  containers:
    - name: app
      image: nginx:1.27
EOF
# Expected: blocked; actual: admitted
```

Both pass through. Check CT status for errors:

```bash
kubectl describe constrainttemplate k8sdisallowprivileged53
```

Look at `status.byPod.errors`. You will find a compile error or a warning. Read the Rego:

```rego
input_containers[c] {
  c := input.review.object.spec.container[_]   # <-- "container" (singular), not "containers"
}

input_containers[c] {
  c := input.review.object.spec.initContainers[_]
}
```

The first helper definition uses `spec.container` (singular, no `s`). Pod specs have `spec.containers` (plural array). Accessing `spec.container` on a pod returns undefined (the field does not exist). When the comprehension iterates over an undefined value, it produces no elements. So the `spec.containers` branch of `input_containers` is always empty.

The `spec.initContainers` branch is correct. So `input_containers` only yields init containers. A pod with a privileged main container and a non-privileged initContainer would slip through.

Actually both tests showed all privileged pods getting through. With only the initContainers branch working, a privileged initContainer should be caught. Check whether there is a secondary issue: if the initContainers branch is also broken... Re-reading: `spec.initContainers[_]` is correct. A pod with a privileged initContainer should be blocked. Try it in isolation:

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: only-priv-init
  namespace: ex-5-3
spec:
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["echo", "init"]
      securityContext:
        privileged: true
  containers:
    - name: app
      image: nginx:1.27
EOF
```

This should be blocked by the working initContainers branch. If it is blocked, the main fix is adding the `s` to `containers`.

### What the bug is and why it happens

`spec.container` (singular) is not a valid pod spec field. Kubernetes pods have `spec.containers` (plural). Rego does not raise an error when you access a non-existent field; it simply evaluates to undefined. The comprehension `{c | c := undefined[_]}` produces an empty set silently. This is one of the trickier Rego debugging situations: the code is syntactically valid, the CT compiles without errors, but one branch of the `input_containers` helper never produces any elements. The fix is a single character: adding the `s` to `containers`.

### Fix

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowprivileged53
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowPrivileged53
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowprivileged53

        violation[{"msg": msg}] {
          c := input_containers[_]
          c.securityContext.privileged == true
          msg := sprintf("Privileged container not allowed: %v", [c.name])
        }

        input_containers[c] {
          c := input.review.object.spec.containers[_]
        }

        input_containers[c] {
          c := input.review.object.spec.initContainers[_]
        }
EOF
```

---

## Common Mistakes

**Using `sprint` instead of `sprintf` in Rego.** Rego's string formatting function is `sprintf`. The function `sprint` does not exist. When you use an undefined function, Gatekeeper records a compilation error in the ConstraintTemplate's status but does not reject the `kubectl apply`. The policy appears installed but does not enforce. Always check `kubectl describe constrainttemplate <name>` after applying a template and look for errors in `status.byPod`. If you see a rego_parse_error or similar, the policy is inactive.

**Using the wrong `input.review.object` field path.** Pod labels live at `input.review.object.metadata.labels`, not `input.review.object.spec.labels`. Container image fields are at `input.review.object.spec.containers[_].image`. The `spec` of a pod contains scheduling and runtime config; `metadata` contains identifying information. Always reference the Kubernetes API docs or a known-good pod YAML to confirm the exact field path before writing the policy condition.

**Forgetting `not` in absence-checking conditions.** The `require-resource-limits` and similar policies fire when a field is ABSENT. In Rego, `not c.resources.limits.cpu` is true when the field is undefined or falsy. Without `not`, the condition checks for presence, which is the opposite intent. The resulting policy blocks compliant pods (those with limits) and admits violating pods (those without limits). This is the most common Rego logic mistake and the hardest to spot because the policy runs without errors.

**Missing initContainers in the `input_containers` helper.** A single `violation` rule that iterates over `spec.containers[_]` misses initContainers. Privileged initContainers, images from disallowed registries in initContainers, and missing resource limits on initContainers all slip through. Always define the `input_containers` helper with two rule bodies covering both container types.

**Omitting `excludedNamespaces: [gatekeeper-system]` from Constraints.** Gatekeeper's own controller pods must be able to restart and scale without being blocked by your policies. If a constraint applies to gatekeeper-system, a rolling update or crash recovery may fail if the new pods violate the policy. This is a bootstrapping problem: the webhook that enforces the constraint is the same process that needs to restart. Always add `excludedNamespaces: [gatekeeper-system, kube-system]` to every Constraint's match block.

**Wrong set subtraction order for label policies.** `required - provided` gives labels required but missing. `provided - required` gives extra labels not in the required set. These have completely different semantics. Writing `provided - required` makes a policy that blocks pods with extra labels and passes pods with missing labels. Read set expressions left to right: "what is in A that is not in B."

**Using `spec.container` (singular) instead of `spec.containers` (plural).** Pod specs use plural field names for arrays: `containers`, `initContainers`, `volumes`. The singular `container` does not exist and evaluates to undefined in Rego silently, causing the comprehension to yield no elements. The policy compiles, the constraint is active, but the helper function produces an empty set, so the violation never fires.

---

## Verification Commands Cheat Sheet

| Task | Command |
|---|---|
| List all ConstraintTemplates | `kubectl get constrainttemplate` |
| Inspect CT for Rego errors | `kubectl describe constrainttemplate <name>` |
| Check CT status for byPod errors | `kubectl get constrainttemplate <name> -o yaml \| grep -A20 "byPod"` |
| List all Constraints of a type | `kubectl get <ConstraintKind>` |
| Check total violation count | `kubectl get <ConstraintKind> <name> -o jsonpath='{.status.totalViolations}'` |
| Read full violation details | `kubectl get <ConstraintKind> <name> -o yaml` |
| Test admission dry-run | `kubectl apply --dry-run=server -f <file>` |
| Test pod admission dry-run | `kubectl run test --image=nginx:1.27 --dry-run=server -n <namespace>` |
| Change enforcementAction | `kubectl patch <Kind> <name> --type=merge -p '{"spec":{"enforcementAction":"deny"}}'` |
| View Gatekeeper controller logs | `kubectl logs -n gatekeeper-system -l control-plane=controller-manager --tail=50` |
| Check ValidatingWebhookConfiguration | `kubectl get validatingwebhookconfiguration gatekeeper-validating-webhook-configuration` |
| Delete a ConstraintTemplate and all its Constraints | `kubectl delete constrainttemplate <name>` |
