# OPA/Gatekeeper Homework: ConstraintTemplates and Policy Enforcement

Work through the tutorial (`opa-gatekeeper-tutorial.md`) before starting these exercises. Gatekeeper and its webhook must be installed and running. Each exercise creates its own namespace and cluster-scoped resources. ConstraintTemplates and Constraints are cluster-scoped, so the naming scheme below ensures no cross-exercise conflicts. Complete the tutorial cleanup before starting exercises to avoid name collisions with tutorial resources.

## Global Setup

Confirm Gatekeeper is installed and the webhook is ready:

```bash
kubectl get pods -n gatekeeper-system
# Expected: gatekeeper-audit and gatekeeper-controller-manager pods in Running state

kubectl wait --for=condition=ready pod \
  -l control-plane=controller-manager \
  -n gatekeeper-system \
  --timeout=60s
```

---

## Level 1: Applying Provided ConstraintTemplates

These exercises give you the ConstraintTemplate in the setup commands. Your work is to create the exercise namespace, deploy the template and constraint, create a compliant resource, and verify that a violating resource is rejected.

---

### Exercise 1.1

**Objective:** Apply a require-labels ConstraintTemplate and Constraint, then confirm that compliant pods are admitted and pods missing the required labels are blocked.

**Setup:**

```bash
kubectl create namespace ex-1-1

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels11
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels11
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
        package k8srequiredlabels11

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Required labels are missing: %v", [missing])
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels11
metadata:
  name: ex11-require-labels
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - ex-1-1
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  parameters:
    labels:
      - app
      - owner
EOF
```

**Task:** Create a pod named `web-compliant` in namespace `ex-1-1` using image `nginx:1.27` with labels `app=frontend` and `owner=alice`. Verify it runs. Then verify that attempting to create a pod named `web-missing` in `ex-1-1` without any labels is rejected by the webhook.

**Verification:**

```bash
kubectl get pod web-compliant -n ex-1-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl run web-missing --image=nginx:1.27 --dry-run=server -n ex-1-1
# Expected: error from server containing "Required labels are missing"
```

---

### Exercise 1.2

**Objective:** Apply a disallow-privileged ConstraintTemplate and Constraint, then verify it blocks privileged containers including those in initContainers.

**Setup:**

```bash
kubectl create namespace ex-1-2

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowprivileged12
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowPrivileged12
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowprivileged12

        violation[{"msg": msg}] {
          c := input_containers[_]
          c.securityContext.privileged == true
          msg := sprintf("Container %v has privileged: true, which is not permitted", [c.name])
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
kind: K8sDisallowPrivileged12
metadata:
  name: ex12-no-privileged
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - ex-1-2
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
EOF
```

**Task:** Create a non-privileged pod named `safe-app` in `ex-1-2` using `busybox:1.36` with command `sleep 3600`. Verify it runs. Then verify that a pod with `securityContext.privileged: true` is blocked. Finally, verify that a pod whose initContainer has `privileged: true` is also blocked, even if the main container is not privileged.

**Verification:**

```bash
kubectl get pod safe-app -n ex-1-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: priv-main
  namespace: ex-1-2
spec:
  containers:
    - name: shell
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        privileged: true
EOF
# Expected: error from server containing "privileged: true, which is not permitted"

kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: priv-init
  namespace: ex-1-2
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
# Expected: error from server containing "setup has privileged: true"
```

---

### Exercise 1.3

**Objective:** Apply a restrict-registries ConstraintTemplate and Constraint, then verify only images from the approved registry prefixes are admitted.

**Setup:**

```bash
kubectl create namespace ex-1-3

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srestrictregistries13
spec:
  crd:
    spec:
      names:
        kind: K8sRestrictRegistries13
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
        package k8srestrictregistries13

        violation[{"msg": msg}] {
          c := input_containers[_]
          not registry_allowed(c.image)
          msg := sprintf("Container %v uses a disallowed registry. Image: %v. Allowed: %v", [c.name, c.image, input.parameters.allowedRegistries])
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
kind: K8sRestrictRegistries13
metadata:
  name: ex13-restrict-registries
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - ex-1-3
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  parameters:
    allowedRegistries:
      - "docker.io/library/"
      - "registry.k8s.io/"
EOF
```

**Task:** Create a pod named `approved-app` in `ex-1-3` using the image `docker.io/library/nginx:1.27`. Verify it is admitted and running. Then verify that a pod using image `quay.io/prometheus/busybox:1.36` is blocked.

**Verification:**

```bash
kubectl get pod approved-app -n ex-1-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl run blocked-app \
  --image=quay.io/prometheus/busybox:1.36 \
  --dry-run=server \
  -n ex-1-3
# Expected: error from server containing "uses a disallowed registry"
```

---

## Level 2: Writing Constraints with Parameters and Enforcement Actions

These exercises provide a ConstraintTemplate in the setup but require you to write the Constraint yourself, choosing parameters and enforcement actions.

---

### Exercise 2.1

**Objective:** Create a Constraint in dryrun mode, observe that violating resources are admitted but recorded, then promote the constraint to deny mode and verify that violations are blocked.

**Setup:**

```bash
kubectl create namespace ex-2-1

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srestrictregistries21
spec:
  crd:
    spec:
      names:
        kind: K8sRestrictRegistries21
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
        package k8srestrictregistries21

        violation[{"msg": msg}] {
          c := input_containers[_]
          not registry_allowed(c.image)
          msg := sprintf("Container %v image %v is not from an allowed registry", [c.name, c.image])
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

**Task:**

1. Create a Constraint named `ex21-restrict-registries` of kind `K8sRestrictRegistries21` with `enforcementAction: dryrun`. Set `allowedRegistries` to `["docker.io/library/"]`. Scope it to namespace `ex-2-1` with `gatekeeper-system` and `kube-system` excluded.

2. Apply a pod named `violating-dryrun` using `quay.io/prometheus/busybox:1.36` in `ex-2-1`. Confirm it is created (dryrun allows it through).

3. Wait 90 seconds for the audit cycle to run, then check the Constraint's status to confirm the violation is recorded.

4. Change the Constraint's `enforcementAction` to `deny` using `kubectl patch`.

5. Verify that now `violating-dryrun` pod deletion followed by re-creation is blocked.

**Verification:**

```bash
# Step 2: pod exists despite violating the policy
kubectl get pod violating-dryrun -n ex-2-1 -o jsonpath='{.status.phase}'
# Expected: Running (dryrun admits it)

# Step 3: audit records the violation
kubectl get k8srestrictregistries21 ex21-restrict-registries -o jsonpath='{.status.totalViolations}'
# Expected: 1

# Step 5: after switching to deny, new violating pod is blocked
kubectl run violating-deny-test \
  --image=quay.io/prometheus/busybox:1.36 \
  --dry-run=server \
  -n ex-2-1
# Expected: error from server containing "not from an allowed registry"
```

---

### Exercise 2.2

**Objective:** Create a Constraint that uses `namespaceSelector` to enforce a policy only in namespaces carrying a specific label, and verify that unlabeled namespaces are exempt.

**Setup:**

```bash
kubectl create namespace ex-2-2
kubectl label namespace ex-2-2 policy=enforced

kubectl create namespace ex-2-2-open
# ex-2-2-open intentionally has no policy=enforced label

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels22
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels22
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
        package k8srequiredlabels22

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Required labels are missing: %v", [missing])
        }
EOF
```

**Task:** Create a Constraint named `ex22-require-labels` of kind `K8sRequiredLabels22` that:
- Uses `namespaceSelector` to target namespaces with label `policy=enforced`
- Requires labels `app` and `team` on all pods
- Has `enforcementAction: deny`
- Excludes `gatekeeper-system` and `kube-system`
- Sets `parameters.labels` to `["app", "team"]`

After creating the Constraint, verify that a pod without labels is blocked in `ex-2-2` (which has `policy=enforced`) but is admitted in `ex-2-2-open` (which does not).

**Verification:**

```bash
kubectl run blocked-pod --image=nginx:1.27 --dry-run=server -n ex-2-2
# Expected: error from server containing "Required labels are missing"

kubectl run allowed-pod --image=nginx:1.27 --dry-run=server -n ex-2-2-open
# Expected: pod/allowed-pod created (dry run) - no error
```

---

### Exercise 2.3

**Objective:** Operate three constraints simultaneously and observe that a pod violating multiple policies receives all violation messages in a single rejection.

**Setup:**

```bash
kubectl create namespace ex-2-3

kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels23
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels23
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
        package k8srequiredlabels23

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
  name: k8sdisallowprivileged23
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowPrivileged23
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowprivileged23

        violation[{"msg": msg}] {
          c := input.review.object.spec.containers[_]
          c.securityContext.privileged == true
          msg := sprintf("Privileged container not allowed: %v", [c.name])
        }
---
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequireresourcelimits23
spec:
  crd:
    spec:
      names:
        kind: K8sRequireResourceLimits23
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequireresourcelimits23

        violation[{"msg": msg}] {
          c := input.review.object.spec.containers[_]
          not c.resources.limits.cpu
          msg := sprintf("Container %v is missing CPU limit", [c.name])
        }

        violation[{"msg": msg}] {
          c := input.review.object.spec.containers[_]
          not c.resources.limits.memory
          msg := sprintf("Container %v is missing memory limit", [c.name])
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels23
metadata:
  name: ex23-require-labels
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-2-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    labels: ["app", "owner"]
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowPrivileged23
metadata:
  name: ex23-no-privileged
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-2-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
---
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireResourceLimits23
metadata:
  name: ex23-require-limits
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-2-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF
```

**Task:** Create a fully compliant pod named `compliant-all` in `ex-2-3` that satisfies all three constraints: it has labels `app=api` and `owner=bob`, is not privileged, and has CPU limit `100m` and memory limit `128Mi`. Then verify that a pod violating all three constraints receives three separate violation messages when its admission is tested.

**Verification:**

```bash
kubectl get pod compliant-all -n ex-2-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: violates-all
  namespace: ex-2-3
spec:
  containers:
    - name: app
      image: nginx:1.27
      securityContext:
        privileged: true
EOF
# Expected: error from server containing all of:
#   "Required labels missing"
#   "Privileged container not allowed"
#   "missing CPU limit"
#   "missing memory limit"
```

---

## Level 3: Debugging Broken ConstraintTemplates

These exercises present ConstraintTemplates with defects. The setup applies the broken configuration. Your task is to find the problem and fix it so the constraint enforces correctly.

---

### Exercise 3.1

**Objective:** The ConstraintTemplate below installs without a kubectl error, but the Constraint does not block privileged containers. Find and fix the issue.

**Setup:**

```bash
kubectl create namespace ex-3-1

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
          msg := sprint("Container %v is running as privileged", [c.name])
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowPrivileged31
metadata:
  name: ex31-no-privileged
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-3-1]
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that a privileged pod is rejected in namespace `ex-3-1`.

**Verification:**

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: priv-test
  namespace: ex-3-1
spec:
  containers:
    - name: shell
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        privileged: true
EOF
# Expected: error from server containing "is running as privileged"
```

---

### Exercise 3.2

**Objective:** The ConstraintTemplate and Constraint below are installed without errors, but pods missing required labels are admitted when they should be rejected. Find and fix the issue.

**Setup:**

```bash
kubectl create namespace ex-3-2

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
          provided := {label | input.review.object.spec.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Required labels are missing: %v", [missing])
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels32
metadata:
  name: ex32-require-labels
spec:
  enforcementAction: deny
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

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that pods missing the `app` and `owner` labels are rejected in namespace `ex-3-2`.

**Verification:**

```bash
kubectl run missing-labels-test --image=nginx:1.27 --dry-run=server -n ex-3-2
# Expected: error from server containing "Required labels are missing"

kubectl run labeled-test \
  --image=nginx:1.27 \
  --labels="app=api,owner=charlie" \
  --dry-run=server \
  -n ex-3-2
# Expected: pod/labeled-test created (dry run) - no error
```

---

### Exercise 3.3

**Objective:** The ConstraintTemplate and Constraint below are installed without errors and do produce violations, but they fire for the wrong pods. Find and fix the issue.

**Setup:**

```bash
kubectl create namespace ex-3-3

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
          c.resources.limits.cpu
          msg := sprintf("Container %v must not set a CPU limit", [c.name])
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireResourceLimits33
metadata:
  name: ex33-require-limits
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-3-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that pods missing CPU or memory limits are rejected, and pods with both limits set are admitted.

**Verification:**

```bash
# Pod without limits should be rejected
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
# Expected: error from server containing "missing" or "CPU limit" or "memory limit"

# Pod with limits should be admitted
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
# Expected: pod/with-limits created (dry run) - no error
```

---

## Level 4: Authoring Complete ConstraintTemplates

These exercises ask you to write the entire ConstraintTemplate from scratch, including the Rego policy, CRD schema, and Constraint resource.

---

### Exercise 4.1

**Objective:** Author a complete `require-resource-limits` ConstraintTemplate that checks both `spec.containers` and `spec.initContainers`, blocks pods missing CPU or memory limits on any container, and exposes no parameters.

**Setup:**

```bash
kubectl create namespace ex-4-1
```

**Task:**

1. Write and apply a ConstraintTemplate named `k8srequireresourcelimits41` with kind `K8sRequireResourceLimits41`. The Rego must:
   - Define an `input_containers` helper that yields containers from both `spec.containers` and `spec.initContainers`
   - Fire a violation for each container missing a CPU limit, naming the container in the message
   - Fire a separate violation for each container missing a memory limit

2. Create a Constraint named `ex41-require-limits` that applies the template to pods in namespace `ex-4-1` with `enforcementAction: deny`. Exclude `gatekeeper-system` and `kube-system`.

3. Verify a pod with an initContainer that is missing limits is blocked.

**Verification:**

```bash
# Pod with unlimted initContainer should be blocked
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: init-no-limits
  namespace: ex-4-1
spec:
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["echo", "setup"]
  containers:
    - name: app
      image: nginx:1.27
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
EOF
# Expected: error from server containing "setup" and "missing" (init container missing limits)

# Pod with all limits set should be admitted
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: all-limits
  namespace: ex-4-1
spec:
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["echo", "setup"]
      resources:
        limits:
          cpu: "50m"
          memory: "64Mi"
  containers:
    - name: app
      image: nginx:1.27
      resources:
        limits:
          cpu: "100m"
          memory: "128Mi"
EOF
# Expected: pod/all-limits created (dry run) - no error
```

---

### Exercise 4.2

**Objective:** Author a complete restrict-registries ConstraintTemplate that accepts a list of allowed registry prefixes as parameters, covers both containers and initContainers, and produces informative error messages.

**Setup:**

```bash
kubectl create namespace ex-4-2
```

**Task:**

1. Write and apply a ConstraintTemplate named `k8srestrictregistries42` with kind `K8sRestrictRegistries42`. The Rego must:
   - Accept `allowedRegistries` as a string array parameter
   - Define an `input_containers` helper for both container types
   - Define a `registry_allowed` helper that returns true when an image starts with any allowed prefix
   - Fire a violation naming the container, image, and allowed registry list

2. Create a Constraint named `ex42-restrict-registries` with `allowedRegistries: ["docker.io/library/", "registry.k8s.io/"]`. Apply to pods in `ex-4-2` with deny enforcement. Exclude `gatekeeper-system` and `kube-system`.

3. Create a running pod named `valid-registry` using `docker.io/library/nginx:1.27` in `ex-4-2`. Verify it is admitted and running.

4. Verify that a pod with an initContainer from `quay.io/prometheus/busybox:1.36` is blocked, even if the main container uses an allowed registry.

**Verification:**

```bash
kubectl get pod valid-registry -n ex-4-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: disallowed-init
  namespace: ex-4-2
spec:
  initContainers:
    - name: checker
      image: quay.io/prometheus/busybox:1.36
      command: ["echo", "check"]
  containers:
    - name: app
      image: docker.io/library/nginx:1.27
EOF
# Expected: error from server containing "disallowed registry" and "checker"
```

---

### Exercise 4.3

**Objective:** Build a multi-constraint defense-in-depth setup where three policies apply to one namespace but not another, using a namespaceSelector.

**Setup:**

```bash
kubectl create namespace ex-4-3-enforced
kubectl label namespace ex-4-3-enforced security=strict

kubectl create namespace ex-4-3-exempt
# ex-4-3-exempt has no security=strict label
```

**Task:**

Using any ConstraintTemplates (author them from scratch or reuse ones you have created earlier in the homework if they are still present in the cluster), create three Constraints that:
- Require labels `app` and `team` on all pods
- Disallow privileged containers
- Require both CPU and memory limits

All three Constraints must use `namespaceSelector` to target only namespaces with label `security=strict`. Exclude `gatekeeper-system` and `kube-system`. Set `enforcementAction: deny`.

After deploying, create a fully compliant pod named `strict-compliant` in `ex-4-3-enforced` (with labels, non-privileged, with limits), and verify it runs. Then verify that a non-compliant pod (no labels, no limits) is blocked in `ex-4-3-enforced` but is admitted in `ex-4-3-exempt`.

**Verification:**

```bash
kubectl get pod strict-compliant -n ex-4-3-enforced -o jsonpath='{.status.phase}'
# Expected: Running

kubectl run non-compliant \
  --image=nginx:1.27 \
  --dry-run=server \
  -n ex-4-3-enforced
# Expected: error from server (labels and limits missing)

kubectl run non-compliant \
  --image=nginx:1.27 \
  --dry-run=server \
  -n ex-4-3-exempt
# Expected: pod/non-compliant created (dry run) - no error (exempt namespace)
```

---

## Level 5: Advanced Policy Debugging

These exercises present policies that appear correct: they install without errors and the Constraint shows as active. However, each policy is admitting workloads that it should block. Trace the Rego logic to find and fix the defects.

---

### Exercise 5.1

**Objective:** The configuration below has one or more problems. Find and fix whatever is needed so that pods using images from disallowed registries are blocked.

**Setup:**

```bash
kubectl create namespace ex-5-1

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
          registry_allowed(c.image)
          msg := sprintf("Container %v image %v is from an approved registry", [c.name, c.image])
        }

        input_containers[c] {
          c := input.review.object.spec.containers[_]
        }

        registry_allowed(image) {
          prefix := input.parameters.allowedRegistries[_]
          startswith(image, prefix)
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRestrictRegistries51
metadata:
  name: ex51-restrict-registries
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-5-1]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    allowedRegistries:
      - "docker.io/library/"
      - "registry.k8s.io/"
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that:
- Pods using images from `quay.io/` are blocked
- Pods using images from `docker.io/library/` are admitted
- Pods with a disallowed image in an initContainer are also blocked

**Verification:**

```bash
kubectl run blocked-quay \
  --image=quay.io/prometheus/busybox:1.36 \
  --dry-run=server \
  -n ex-5-1
# Expected: error from server (disallowed registry)

kubectl run allowed-docker \
  --image=docker.io/library/nginx:1.27 \
  --dry-run=server \
  -n ex-5-1
# Expected: pod/allowed-docker created (dry run) - no error

kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: blocked-init
  namespace: ex-5-1
spec:
  initContainers:
    - name: setup
      image: quay.io/prometheus/busybox:1.36
      command: ["echo", "check"]
  containers:
    - name: app
      image: docker.io/library/nginx:1.27
EOF
# Expected: error from server containing "setup" (init container blocked)
```

---

### Exercise 5.2

**Objective:** The configuration below has one or more problems. Find and fix whatever is needed so that pods without required labels are blocked and pods with the labels are admitted.

**Setup:**

```bash
kubectl create namespace ex-5-2

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
          missing := provided - required
          count(missing) > 0
          msg := sprintf("Unexpected labels found: %v", [missing])
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels52
metadata:
  name: ex52-require-labels
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-5-2]
    excludedNamespaces: [gatekeeper-system, kube-system]
  parameters:
    labels: ["app", "owner"]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that pods missing the required labels `app` and `owner` are blocked, and pods carrying both labels are admitted regardless of any additional labels they may have.

**Verification:**

```bash
# Pod without required labels should be blocked
kubectl run missing-labels \
  --image=nginx:1.27 \
  --dry-run=server \
  -n ex-5-2
# Expected: error from server (labels missing)

# Pod with required labels but extra labels should be admitted
kubectl run with-extra-labels \
  --image=nginx:1.27 \
  --labels="app=web,owner=diana,version=v1" \
  --dry-run=server \
  -n ex-5-2
# Expected: pod/with-extra-labels created (dry run) - no error
```

---

### Exercise 5.3

**Objective:** The configuration below has one or more problems. Find and fix whatever is needed so that privileged containers are blocked in all container types, including both spec.containers and spec.initContainers.

**Setup:**

```bash
kubectl create namespace ex-5-3

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
          c := input.review.object.spec.container[_]
        }

        input_containers[c] {
          c := input.review.object.spec.initContainers[_]
        }
EOF

kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowPrivileged53
metadata:
  name: ex53-no-privileged
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces: [ex-5-3]
    excludedNamespaces: [gatekeeper-system, kube-system]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that privileged containers in both `spec.containers` and `spec.initContainers` are blocked, and non-privileged pods are admitted.

**Verification:**

```bash
# Privileged main container should be blocked
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
# Expected: error from server containing "Privileged container not allowed: app"

# Privileged initContainer should be blocked
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
# Expected: error from server containing "Privileged container not allowed: setup"

# Non-privileged pod should be admitted
kubectl run safe-pod \
  --image=nginx:1.27 \
  --dry-run=server \
  -n ex-5-3
# Expected: pod/safe-pod created (dry run) - no error
```

---

## Cleanup

Delete all exercise namespaces and cluster-scoped resources created in this homework:

```bash
# Exercise namespaces
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 \
  ex-2-1 ex-2-2 ex-2-2-open ex-2-3 \
  ex-3-1 ex-3-2 ex-3-3 \
  ex-4-1 ex-4-2 ex-4-3-enforced ex-4-3-exempt \
  ex-5-1 ex-5-2 ex-5-3 \
  --ignore-not-found

# Constraints (delete by type)
for ct in k8srequiredlabels11 k8sdisallowprivileged12 k8srestrictregistries13 \
          k8srestrictregistries21 k8srequiredlabels22 k8srequiredlabels23 \
          k8sdisallowprivileged23 k8srequireresourcelimits23 \
          k8sdisallowprivileged31 k8srequiredlabels32 k8srequireresourcelimits33 \
          k8srequireresourcelimits41 k8srestrictregistries42 \
          k8srestrictregistries51 k8srequiredlabels52 k8sdisallowprivileged53; do
  # Get the kind from the CT and delete all constraints of that type
  kind=$(kubectl get constrainttemplate ${ct} -o jsonpath='{.spec.crd.spec.names.kind}' 2>/dev/null)
  if [ -n "${kind}" ]; then
    kubectl delete ${kind} --all --ignore-not-found 2>/dev/null
  fi
done

# ConstraintTemplates
kubectl delete constrainttemplate \
  k8srequiredlabels11 k8sdisallowprivileged12 k8srestrictregistries13 \
  k8srestrictregistries21 k8srequiredlabels22 k8srequiredlabels23 \
  k8sdisallowprivileged23 k8srequireresourcelimits23 \
  k8sdisallowprivileged31 k8srequiredlabels32 k8srequireresourcelimits33 \
  k8srequireresourcelimits41 k8srestrictregistries42 \
  k8srestrictregistries51 k8srequiredlabels52 k8sdisallowprivileged53 \
  --ignore-not-found
```

Verify cleanup:

```bash
kubectl get constrainttemplate
# Expected: no exercise templates remain

kubectl get namespace | grep "ex-"
# Expected: no output
```

## Key Takeaways

The exercises in this assignment develop the core Gatekeeper skills: reading CT status to diagnose Rego compilation errors, tracing `input.review.object` field paths against real pod structures, using `not` correctly to detect absent fields, iterating over arrays with `[_]`, and building the `input_containers` helper to cover both container types. The Level 5 exercises reinforce a critical diagnostic habit: when a policy appears to be working (no error at install time, constraint shows as active) but is admitting violating resources, you cannot trust the policy surface. You must trace the Rego by hand, substituting a known-violating `input.review.object` into the rules and checking whether the violation block actually evaluates to true.
