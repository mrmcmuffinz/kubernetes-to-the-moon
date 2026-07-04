# OPA/Gatekeeper Homework: Audit Mode, Mutation, and Policy Troubleshooting

Work through the tutorial (`opa-gatekeeper-tutorial.md`) before starting these exercises. Gatekeeper and its webhook must be installed and running. The exercises in this assignment use ConstraintTemplates provided in the setup commands, so authoring Rego is not required except in the Level 4 exercises. Clean up tutorial resources before starting to avoid naming conflicts.

## Global Setup

Confirm Gatekeeper is running with both the webhook and audit pods ready:

```bash
kubectl get pods -n gatekeeper-system
# Expected: audit and controller-manager pods in Running state
```

---

## Level 1: Audit Mode

These exercises drill the dryrun enforcement workflow: creating constraints in dryrun mode, reading violation status, fixing non-compliant resources, and promoting to deny.

---

### Exercise 1.1

**Objective:** Deploy a require-labels constraint in dryrun mode, create several pods with different compliance states, then fix the non-compliant pods and verify that audit violations drop to zero.

**Setup:**

```bash
kubectl create namespace ex-1-1

# Create three pods: one compliant, two violating
kubectl run compliant-pod \
  --image=nginx:1.27 \
  --labels="app=frontend,owner=alice" \
  -n ex-1-1

kubectl run violating-one \
  --image=busybox:1.36 \
  --command -- sleep 3600 \
  -n ex-1-1

kubectl run violating-two \
  --image=redis:7.2 \
  --labels="app=cache" \
  -n ex-1-1

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels11a
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels11a
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
        package k8srequiredlabels11a

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
kind: K8sRequiredLabels11a
metadata:
  name: ex11a-require-labels
spec:
  enforcementAction: dryrun
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-1-1]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    labels: ["app", "owner"]
EOF
```

**Task:**

1. Wait 90 seconds for the audit cycle to run, then check the constraint's `status.totalViolations`. Confirm it reports 2 violations.
2. Identify which pods are violating by reading the constraint's full status.
3. Fix the violating pods by adding the missing labels (`app` and/or `owner` as needed).
4. Wait for the next audit cycle, then confirm violations drop to 0.

**Verification:**

```bash
# After audit cycle runs
kubectl get k8srequiredlabels11a ex11a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 2 (before fix), then 0 (after fix)

# Read violation details
kubectl get k8srequiredlabels11a ex11a-require-labels \
  -o jsonpath='{.status.violations[*].name}'
# Expected: violating-one violating-two (before fix)

# After fix and next audit cycle
kubectl get k8srequiredlabels11a ex11a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 0
```

---

### Exercise 1.2

**Objective:** Operate a constraint in both dryrun and deny modes to observe how each mode behaves when a new violating resource is submitted.

**Setup:**

```bash
kubectl create namespace ex-1-2

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowprivileged12a
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowPrivileged12a
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowprivileged12a

        violation[{"msg": msg}] {
          c := input_containers[_]
          c.securityContext.privileged == true
          msg := sprintf("Container %v is running privileged", [c.name])
        }

        input_containers[c] { c := input.review.object.spec.containers[_] }
        input_containers[c] { c := input.review.object.spec.initContainers[_] }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowPrivileged12a
metadata:
  name: ex12a-no-privileged
spec:
  enforcementAction: dryrun
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-1-2]
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF
```

**Task:**

1. Apply a privileged pod named `priv-pod` in `ex-1-2` (it will be admitted because the constraint is in dryrun). Confirm the pod is running.
2. Wait for the audit cycle. Confirm the constraint records 1 violation showing `priv-pod`.
3. Change the constraint's `enforcementAction` from `dryrun` to `deny`.
4. Delete `priv-pod` and attempt to re-create it. Verify that the constraint now blocks it.
5. Create a non-privileged pod named `safe-pod` and verify it is admitted.

**Verification:**

```bash
# Step 1: priv-pod admitted in dryrun
kubectl get pod priv-pod -n ex-1-2 -o jsonpath='{.status.phase}'
# Expected: Running

# Step 2: audit records violation
kubectl get k8sdisallowprivileged12a ex12a-no-privileged \
  -o jsonpath='{.status.totalViolations}'
# Expected: 1

# Step 4: after switching to deny, recreate is blocked
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: priv-pod-new
  namespace: ex-1-2
spec:
  containers:
    - name: shell
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        privileged: true
EOF
# Expected: error from server containing "is running privileged"

# Step 5: non-privileged pod admitted
kubectl get pod safe-pod -n ex-1-2 -o jsonpath='{.status.phase}'
# Expected: Running
```

---

### Exercise 1.3

**Objective:** Run a full dryrun → audit → fix → deny promotion cycle on a restrict-registries policy.

**Setup:**

```bash
kubectl create namespace ex-1-3

# Pre-create pods that will violate the policy
kubectl run approved-app \
  --image=docker.io/library/nginx:1.27 \
  --labels="app=web,owner=alice" \
  -n ex-1-3

kubectl run legacy-app \
  --image=quay.io/prometheus/busybox:1.36 \
  --labels="app=legacy,owner=bob" \
  --command -- sleep 3600 \
  -n ex-1-3

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srestrictregistries13a
spec:
  crd:
    spec:
      names:
        kind: K8sRestrictRegistries13a
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
        package k8srestrictregistries13a

        violation[{"msg": msg}] {
          c := input_containers[_]
          not registry_allowed(c.image)
          msg := sprintf("Container %v uses a disallowed registry: %v", [c.name, c.image])
        }

        input_containers[c] { c := input.review.object.spec.containers[_] }
        input_containers[c] { c := input.review.object.spec.initContainers[_] }

        registry_allowed(image) {
          prefix := input.parameters.allowedRegistries[_]
          startswith(image, prefix)
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRestrictRegistries13a
metadata:
  name: ex13a-restrict-registries
spec:
  enforcementAction: dryrun
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-1-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    allowedRegistries:
      - "docker.io/library/"
      - "registry.k8s.io/"
EOF
```

**Task:**

1. Wait for the audit cycle. Verify the constraint reports 1 violation for `legacy-app`.
2. Fix `legacy-app` by replacing it with a pod using an approved image (`docker.io/library/busybox:1.36`). Delete the original and create the replacement.
3. Wait for the next audit cycle. Verify violations drop to 0.
4. Switch the constraint to `deny`.
5. Verify a pod using `quay.io/` image is now blocked.

**Verification:**

```bash
# Step 1
kubectl get k8srestrictregistries13a ex13a-restrict-registries \
  -o jsonpath='{.status.violations[0].name}'
# Expected: legacy-app

# Step 3: after fix
kubectl get k8srestrictregistries13a ex13a-restrict-registries \
  -o jsonpath='{.status.totalViolations}'
# Expected: 0

# Step 5: after switching to deny
kubectl run blocked-test \
  --image=quay.io/prometheus/busybox:1.36 \
  --dry-run=server \
  -n ex-1-3
# Expected: error from server containing "disallowed registry"
```

---

## Level 2: Mutation Resources

These exercises require authoring and applying AssignMetadata and Assign mutation resources. Verify mutations by inspecting created pod YAML.

---

### Exercise 2.1

**Objective:** Create an AssignMetadata mutation that injects a `cost-center` label on all pods in the exercise namespace.

**Setup:**

```bash
kubectl create namespace ex-2-1
```

**Task:**

1. Create an AssignMetadata resource named `ex21-inject-cost-center` that:
   - Targets pods (`kinds: ["Pod"]`) in namespace `ex-2-1`
   - Sets the label `cost-center=backend`
   - Excludes `gatekeeper-system` and `kube-system`

2. Create a pod named `labeled-pod` in `ex-2-1` using `nginx:1.27` without specifying `cost-center` in the `kubectl run` command.

3. Verify the `cost-center=backend` label is present on the pod.

4. Create a second pod named `existing-label-pod` that already has `cost-center=frontend`. Verify that AssignMetadata overwrites it to `backend` (AssignMetadata always overwrites existing values).

**Verification:**

```bash
kubectl get pod labeled-pod -n ex-2-1 \
  -o jsonpath='{.metadata.labels.cost-center}'
# Expected: backend

kubectl get pod existing-label-pod -n ex-2-1 \
  -o jsonpath='{.metadata.labels.cost-center}'
# Expected: backend (overwritten by AssignMetadata)
```

---

### Exercise 2.2

**Objective:** Create an Assign mutation that injects `readOnlyRootFilesystem: true` on all containers, but only when the field is not already explicitly set by the user.

**Setup:**

```bash
kubectl create namespace ex-2-2
```

**Task:**

1. Create an Assign resource named `ex22-readonly-root` that:
   - Applies to Pods (`groups: [""]`, `kinds: ["Pod"]`, `versions: ["v1"]`)
   - Targets namespace `ex-2-2` with `excludedNamespaces: [gatekeeper-system, kube-system]`
   - Sets `spec/containers/[name:*]/securityContext/readOnlyRootFilesystem` to `true`
   - Uses `pathTests` with `condition: MustNotExist` to avoid overriding explicit settings

2. Create pod `default-readonly` in `ex-2-2` using `nginx:1.27` without any securityContext. Verify `readOnlyRootFilesystem` is `true`.

3. Create pod `explicit-false` in `ex-2-2` with `securityContext.readOnlyRootFilesystem: false`. Verify the mutation did NOT override it (field remains `false`).

**Verification:**

```bash
kubectl get pod default-readonly -n ex-2-2 \
  -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
# Expected: true

kubectl get pod explicit-false -n ex-2-2 \
  -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
# Expected: false
```

---

### Exercise 2.3

**Objective:** Create an Assign mutation that injects default memory and CPU limits on containers that do not already have limits set.

**Setup:**

```bash
kubectl create namespace ex-2-3
```

**Task:**

1. Create an Assign resource named `ex23-default-cpu-limit` that:
   - Applies to Pods in `ex-2-3`
   - Sets `spec/containers/[name:*]/resources/limits/cpu` to `"200m"`
   - Uses `pathTests: MustNotExist` on `spec/containers/[name:*]/resources/limits/cpu`

2. Create a second Assign resource named `ex23-default-memory-limit` that:
   - Applies to Pods in `ex-2-3`
   - Sets `spec/containers/[name:*]/resources/limits/memory` to `"256Mi"`
   - Uses `pathTests: MustNotExist` on `spec/containers/[name:*]/resources/limits/memory`

3. Create pod `default-limits-pod` in `ex-2-3` with no resource limits specified. Verify both CPU and memory limits are injected.

4. Create pod `custom-limits-pod` with explicit CPU limit `"500m"` and no memory limit. Verify that CPU remains at `"500m"` (not overridden) and memory is injected as `"256Mi"`.

**Verification:**

```bash
kubectl get pod default-limits-pod -n ex-2-3 \
  -o jsonpath='{.spec.containers[0].resources.limits.cpu}'
# Expected: 200m

kubectl get pod default-limits-pod -n ex-2-3 \
  -o jsonpath='{.spec.containers[0].resources.limits.memory}'
# Expected: 256Mi

kubectl get pod custom-limits-pod -n ex-2-3 \
  -o jsonpath='{.spec.containers[0].resources.limits.cpu}'
# Expected: 500m (user value preserved)

kubectl get pod custom-limits-pod -n ex-2-3 \
  -o jsonpath='{.spec.containers[0].resources.limits.memory}'
# Expected: 256Mi (injected because user did not set it)
```

---

## Level 3: Debugging Broken Policies

These exercises present policies with misconfigurations. The symptoms are described in each objective. Your task is to find and fix the issue. Exercise headings are bare.

---

### Exercise 3.1

**Objective:** An AssignMetadata mutation is installed and reports no errors when you describe it, but the intended label is never appearing on pods in the exercise namespace. Find and fix the configuration so the mutation applies correctly.

**Setup:**

```bash
kubectl create namespace ex-3-1

kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: AssignMetadata
metadata:
  name: ex31-inject-team
spec:
  match:
    scope: Namespaced
    kinds:
      - apiGroups: ["apps"]
        kinds: ["Pod"]
    namespaces:
      - ex-3-1
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  location: "metadata/labels/team"
  parameters:
    assign:
      value: "platform"
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that pods created in namespace `ex-3-1` automatically receive the label `team=platform`.

**Verification:**

```bash
kubectl run test-pod --image=nginx:1.27 -n ex-3-1

kubectl get pod test-pod -n ex-3-1 \
  -o jsonpath='{.metadata.labels.team}'
# Expected: platform
```

---

### Exercise 3.2

**Objective:** A constraint is set to dryrun mode and should be recording violations for pods missing required labels, but `status.totalViolations` remains at 0 even though you can see unlabeled pods running in the namespace. Find and fix the configuration so the audit correctly captures all violations.

**Setup:**

```bash
kubectl create namespace ex-3-2

# Create several pods, some with labels, some without
kubectl run labeled-one \
  --image=nginx:1.27 \
  --labels="app=web,owner=alice,audit-scope=yes" \
  -n ex-3-2

kubectl run no-labels-one \
  --image=busybox:1.36 \
  --command -- sleep 3600 \
  -n ex-3-2

kubectl run no-labels-two \
  --image=redis:7.2 \
  -n ex-3-2

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels32a
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels32a
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
        package k8srequiredlabels32a

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
    labelSelector:
      matchLabels:
        audit-scope: "yes"
  parameters:
    labels: ["app", "owner"]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that ALL pods in namespace `ex-3-2` missing `app` and `owner` labels are captured in the constraint's violations (not just those with `audit-scope=yes`).

**Verification:**

```bash
# Wait 90 seconds for audit, then:
kubectl get k8srequiredlabels32a ex32a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 2 (no-labels-one and no-labels-two)
```

---

### Exercise 3.3

**Objective:** A constraint with deny enforcement is blocking pods in a namespace that should be exempt. Find and fix the configuration so system pods in gatekeeper-system are not blocked.

**Setup:**

```bash
kubectl create namespace ex-3-3

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels33a
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels33a
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
        package k8srequiredlabels33a

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
      - gatekeeper-system
  parameters:
    labels: ["app", "owner"]
EOF
```

**Task:** The configuration above has one or more problems. Verify that pods in gatekeeper-system are being blocked by testing pod creation there. Then fix the constraint so that `gatekeeper-system` and `kube-system` pods are exempt, while pods in `ex-3-3` without `app` and `owner` labels are still blocked.

**Verification:**

```bash
# A pod in gatekeeper-system should NOT be blocked after the fix
kubectl run gk-test \
  --image=busybox:1.36 \
  --command -- sleep 30 \
  --dry-run=server \
  -n gatekeeper-system
# Expected: pod/gk-test created (dry run) - no error (gatekeeper-system is excluded)

# A pod in ex-3-3 without labels should still be blocked
kubectl run missing-labels-test \
  --image=nginx:1.27 \
  --dry-run=server \
  -n ex-3-3
# Expected: error from server containing "Required labels missing"
```

---

## Level 4: Complex Operational Scenarios

These exercises combine multiple concepts in multi-step operational workflows.

---

### Exercise 4.1

**Objective:** Execute a complete policy rollout: deploy in dryrun, discover violations, remediate them, and then promote to deny with namespace-by-namespace enforcement.

**Setup:**

```bash
kubectl create namespace ex-4-1-alpha
kubectl create namespace ex-4-1-beta

# Pre-deploy a mix of compliant and violating pods in both namespaces
kubectl run alpha-compliant \
  --image=nginx:1.27 \
  --labels="app=api,team=platform" \
  -n ex-4-1-alpha

kubectl run alpha-violating \
  --image=busybox:1.36 \
  --command -- sleep 3600 \
  -n ex-4-1-alpha

kubectl run beta-compliant \
  --image=nginx:1.27 \
  --labels="app=frontend,team=ui" \
  -n ex-4-1-beta

kubectl run beta-violating \
  --image=redis:7.2 \
  -n ex-4-1-beta

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels41a
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels41a
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
        package k8srequiredlabels41a

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Required labels missing: %v", [missing])
        }
EOF
```

**Task:**

1. Create a single constraint `ex41a-require-labels` of kind `K8sRequiredLabels41a` in dryrun mode, targeting both `ex-4-1-alpha` and `ex-4-1-beta` namespaces (use `namespaces` in match, not namespaceSelector). Set parameters to require `app` and `team`.

2. Wait for audit. Confirm there are 2 violations (one per namespace).

3. Fix the violating pods by adding the missing labels.

4. Wait for the next audit. Confirm violations drop to 0.

5. Change the constraint to `deny` mode.

6. Label namespace `ex-4-1-alpha` with `enforce=v1` and update the constraint to use `namespaceSelector: {matchLabels: {enforce: v1}}` (replace the `namespaces` field with `namespaceSelector`).

7. Verify that unlabeled namespace `ex-4-1-beta` is now exempt, while `ex-4-1-alpha` is still enforced.

**Verification:**

```bash
# Step 2: initial violations
kubectl get k8srequiredlabels41a ex41a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 2

# Step 4: after fix
kubectl get k8srequiredlabels41a ex41a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 0

# Step 7: enforcement scoped to alpha only
kubectl run test-alpha --image=nginx:1.27 --dry-run=server -n ex-4-1-alpha
# Expected: error from server (alpha is enforced)

kubectl run test-beta --image=nginx:1.27 --dry-run=server -n ex-4-1-beta
# Expected: pod/test-beta created (dry run) - exempt
```

---

### Exercise 4.2

**Objective:** Build a two-constraint layered defense: require labels on all pods and inject a default `managed-by` annotation on pods in the enforced namespace using a mutation.

**Setup:**

```bash
kubectl create namespace ex-4-2
kubectl label namespace ex-4-2 tier=managed
```

**Task:**

1. Create an AssignMetadata mutation named `ex42-inject-managed-by` that injects the annotation `managed-by=gatekeeper` on all pods in namespaces labeled `tier=managed`. Use `namespaceSelector` in the mutation's match.

2. Create a ConstraintTemplate and Constraint that requires pods in namespace `ex-4-2` to have both the label `app` and the annotation `managed-by`. (Use a require-labels-and-annotations policy, checking both `metadata.labels` and `metadata.annotations`.) Set `enforcementAction: deny`.

3. Create a compliant pod named `managed-pod` with label `app=api`. Verify that:
   - The mutation injects `managed-by=gatekeeper` annotation automatically
   - The pod satisfies the constraint (has both `app` label and `managed-by` annotation)
   - The pod is admitted and running

**Verification:**

```bash
kubectl get pod managed-pod -n ex-4-2 \
  -o jsonpath='{.metadata.labels.app}'
# Expected: api

kubectl get pod managed-pod -n ex-4-2 \
  -o jsonpath='{.metadata.annotations.managed-by}'
# Expected: gatekeeper

kubectl get pod managed-pod -n ex-4-2 \
  -o jsonpath='{.status.phase}'
# Expected: Running
```

---

### Exercise 4.3

**Objective:** Configure a Gatekeeper Config resource to enable audit caching, then deploy a constraint that uses audit and verify it catches all violations across both namespaces.

**Setup:**

```bash
kubectl create namespace ex-4-3-north
kubectl create namespace ex-4-3-south

kubectl run north-violating \
  --image=nginx:1.27 \
  -n ex-4-3-north

kubectl run south-violating \
  --image=redis:7.2 \
  -n ex-4-3-south

kubectl run south-compliant \
  --image=nginx:1.27 \
  --labels="app=db,owner=hannah" \
  -n ex-4-3-south
```

**Task:**

1. Create or update the Gatekeeper Config resource in `gatekeeper-system` to include Pods in `syncOnly`.

2. Create a ConstraintTemplate and dryrun Constraint that requires labels `app` and `owner`, targeting both `ex-4-3-north` and `ex-4-3-south` namespaces.

3. Wait for the audit cycle. Verify the constraint reports exactly 2 violations (`north-violating` and `south-violating`), and that `south-compliant` does not appear.

4. Fix both violating pods by adding the missing labels.

5. Confirm violations drop to 0 after the next audit.

**Verification:**

```bash
kubectl get k8srequiredlabels43a ex43a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 2 (before fix)

kubectl get k8srequiredlabels43a ex43a-require-labels \
  -o jsonpath='{.status.violations[*].name}'
# Expected: north-violating south-violating

# After fix:
kubectl get k8srequiredlabels43a ex43a-require-labels \
  -o jsonpath='{.status.totalViolations}'
# Expected: 0
```

---

## Level 5: Advanced Policy Conflict Debugging

These exercises present scenarios where a mutation policy and a validation policy interact in ways that make pods inadmissible. The symptom in each case is that pod creation fails even though the user's submitted pod spec looks correct. Your task is to diagnose the conflict and fix it.

---

### Exercise 5.1

**Objective:** The configuration below has one or more problems. Pod creation is failing in the exercise namespace even for pods that appear to comply with all policies. Find and fix whatever is needed so compliant pods can be created.

**Setup:**

```bash
kubectl create namespace ex-5-1

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
      value: "production"
EOF

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sblockproductionlabel51
spec:
  crd:
    spec:
      names:
        kind: K8sBlockProductionLabel51
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sblockproductionlabel51

        violation[{"msg": msg}] {
          input.review.object.metadata.labels.env == "production"
          msg := "Pods with env=production label require a production-approval annotation"
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sBlockProductionLabel51
metadata:
  name: ex51-block-production
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-5-1]
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF
```

**Task:** The configuration above has one or more problems. Attempting to create any pod in `ex-5-1` fails with the production label violation. Find the root cause of why ALL pods are being blocked and fix it so that regular pods can be created successfully.

**Verification:**

```bash
kubectl run test-pod \
  --image=nginx:1.27 \
  --labels="app=web,owner=ian" \
  -n ex-5-1
# Expected: pod created successfully (not blocked)

kubectl get pod test-pod -n ex-5-1 -o jsonpath='{.status.phase}'
# Expected: Running
```

---

### Exercise 5.2

**Objective:** The configuration below has one or more problems. All pods in the exercise namespace are being blocked by the validator, even though they look compliant in the submitted spec. Find and fix the conflict.

**Setup:**

```bash
kubectl create namespace ex-5-2

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
      value: false
    pathTests:
      - subPath: "spec/securityContext/runAsNonRoot"
        condition: MustNotExist
EOF

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequirerunasnonroot52
spec:
  crd:
    spec:
      names:
        kind: K8sRequireRunAsNonRoot52
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequirerunasnonroot52

        violation[{"msg": msg}] {
          input.review.object.spec.securityContext.runAsNonRoot == false
          msg := "Pod must set securityContext.runAsNonRoot: true"
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireRunAsNonRoot52
metadata:
  name: ex52-require-nonroot
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-5-2]
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF
```

**Task:** The configuration above has one or more problems. Every pod you try to create in `ex-5-2` is rejected by the validator. Trace the mutation-validation interaction, find the conflict, and fix it so pods can be created successfully while still enforcing the `runAsNonRoot: true` requirement.

**Verification:**

```bash
kubectl run test-pod \
  --image=nginx:1.27 \
  --dry-run=server \
  -n ex-5-2
# Expected: pod/test-pod created (dry run) - no error

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: compliant-pod
  namespace: ex-5-2
spec:
  containers:
    - name: app
      image: nginx:1.27
EOF

kubectl get pod compliant-pod -n ex-5-2 -o jsonpath='{.spec.securityContext.runAsNonRoot}'
# Expected: true (injected by the corrected mutation)
```

---

### Exercise 5.3

**Objective:** The configuration below has one or more problems. Pods with label `tier=api` are consistently blocked even though the user believes their pod spec is fully compliant. Find and fix the conflict so api-tier pods can run.

**Setup:**

```bash
kubectl create namespace ex-5-3

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
      value: "50m"
    pathTests:
      - subPath: "spec/containers/[name:*]/resources/limits/cpu"
        condition: MustNotExist
EOF

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequirecpufor53
spec:
  crd:
    spec:
      names:
        kind: K8sRequireCpuFor53
      validation:
        openAPIV3Schema:
          type: object
          properties:
            minCpuMillicores:
              type: integer
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequirecpufor53

        violation[{"msg": msg}] {
          c := input.review.object.spec.containers[_]
          input.review.object.metadata.labels.tier == "api"
          cpu := c.resources.limits.cpu
          cpu_millis := to_number(trim_suffix(cpu, "m"))
          cpu_millis < input.parameters.minCpuMillicores
          msg := sprintf("Container %v CPU limit %v is below minimum %vm for tier=api pods", [c.name, cpu, input.parameters.minCpuMillicores])
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireCpuFor53
metadata:
  name: ex53-require-cpu-for-api
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-5-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    minCpuMillicores: 100
EOF
```

**Task:** The configuration above has one or more problems. Pods labeled `tier=api` that do not specify a CPU limit are being rejected by the validator. Trace the mutation-validation pipeline to understand why the pods are blocked, and fix the issue so `tier=api` pods without an explicit CPU limit are admitted.

**Verification:**

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
# Expected: pod created without error

kubectl get pod api-pod -n ex-5-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod api-pod -n ex-5-3 \
  -o jsonpath='{.spec.containers[0].resources.limits.cpu}'
# Expected: 100m or higher (sufficient to pass the validator)
```

---

## Cleanup

```bash
# Exercise namespaces
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 \
  ex-2-1 ex-2-2 ex-2-3 \
  ex-3-1 ex-3-2 ex-3-3 \
  ex-4-1-alpha ex-4-1-beta ex-4-2 ex-4-3-north ex-4-3-south \
  ex-5-1 ex-5-2 ex-5-3 \
  --ignore-not-found

# Mutation resources
kubectl delete assignmetadata ex21-inject-cost-center ex22-inject-team-placeholder \
  ex31-inject-team ex42-inject-managed-by ex51-inject-env --ignore-not-found
kubectl delete assign ex22-readonly-root ex23-default-cpu-limit ex23-default-memory-limit \
  ex52-set-run-as-nonroot ex53-inject-default-limits --ignore-not-found

# ConstraintTemplates (also deletes all Constraints of that type)
kubectl delete constrainttemplate \
  k8srequiredlabels11a k8sdisallowprivileged12a k8srestrictregistries13a \
  k8srequiredlabels32a k8srequiredlabels33a k8srequiredlabels41a \
  k8srequiredlabelsor42a k8srequiredlabels43a \
  k8sblockproductionlabel51 k8srequirerunasnonroot52 k8srequirecpufor53 \
  --ignore-not-found

# Config resource (optional)
kubectl delete config config -n gatekeeper-system --ignore-not-found
```

## Key Takeaways

The exercises in this assignment develop the operational Gatekeeper skills: using dryrun as the safe rollout path, reading audit status to identify non-compliant resources, and promoting to deny only after violations are cleared. The mutation exercises show how to inject defaults without overriding explicit user settings using `pathTests: MustNotExist`. The Level 5 exercises demonstrate the most important diagnostic skill in multi-policy environments: when a pod is unexpectedly blocked, always check what the resource looks like AFTER mutations run, not just what the user submitted, because the validating webhook sees the mutated version.
