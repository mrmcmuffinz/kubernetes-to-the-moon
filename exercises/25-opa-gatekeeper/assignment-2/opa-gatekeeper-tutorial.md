# OPA/Gatekeeper Tutorial: Audit Mode, Mutation, and Policy Troubleshooting

## Introduction

When you deploy a new Gatekeeper policy to a live cluster, you face a practical problem: existing workloads may already violate it. Setting the constraint to `deny` immediately would block legitimate pods from restarting after node rescheduling or rolling updates. The solution is to start in `dryrun` mode, run the audit controller to discover all existing violations, fix those resources, and only then promote the constraint to `deny`. This workflow, and the operational skills that support it, is the subject of this tutorial.

Beyond validation, Gatekeeper also supports mutation: policies that automatically inject or modify fields in admitted resources. Mutation runs before validation in the admission chain. You can use it to inject default labels, set security context defaults, or add resource limits to pods that don't specify them. Used thoughtfully, mutation reduces policy drift and simplifies developer workflows by making compliant the default outcome of a simple pod definition. Used carelessly, it can create subtle conflicts where a mutation makes a resource look a certain way to a subsequent validator, producing failures that are hard to trace.

This tutorial builds the three operational skills needed for the exercises: running audit-mode policies, authoring mutation resources, and troubleshooting policy interactions. The tutorial scenario is a platform team rolling out a suite of policies to a cluster that already has running workloads. You will discover violations without breaking anything, fix the existing workloads, enable enforcement, and then layer in mutations to reduce future compliance burden.

## Prerequisites

This tutorial requires opa-gatekeeper/assignment-1 to be complete. All ConstraintTemplate and Constraint concepts are used here without re-introduction. Gatekeeper must be installed and the webhook must be ready. Verify:

```bash
kubectl get pods -n gatekeeper-system
# Expected: audit and controller-manager pods in Running state
```

If Gatekeeper is not running, reinstall following the installation steps in `opa-gatekeeper-tutorial.md` from assignment-1. Create the tutorial namespace:

```bash
kubectl create namespace tutorial-opa-gatekeeper
```

Confirm mutation is enabled by checking for the MutatingWebhookConfiguration:

```bash
kubectl get mutatingwebhookconfiguration gatekeeper-mutating-webhook-configuration
```

If this resource is absent, mutation is not enabled. In Gatekeeper 3.14 and later it is enabled by default; earlier versions required the `--enable-mutation` controller flag.

## Section 1: Audit Mode

The audit controller is a separate Gatekeeper pod that periodically re-evaluates all existing resources against all active Constraints. Unlike the admission webhook (which only sees new or updated resources), the audit controller catches resources that existed before a constraint was created and resources that slipped through during a webhook downtime.

When a constraint's `enforcementAction` is `dryrun`, violations are recorded in the constraint's status but no admission request is blocked. This makes `dryrun` the safe mode for rolling out policies to live clusters.

First, create some workloads in the tutorial namespace that will be in different compliance states:

```bash
# A compliant pod with required labels
kubectl run compliant-pod \
  --image=nginx:1.27 \
  --labels="app=frontend,owner=alice" \
  -n tutorial-opa-gatekeeper

# A violating pod missing required labels
kubectl run violating-pod-1 \
  --image=busybox:1.36 \
  --command -- sleep 3600 \
  -n tutorial-opa-gatekeeper

# Another violating pod with only one label
kubectl run violating-pod-2 \
  --image=redis:7.2 \
  --labels="app=cache" \
  -n tutorial-opa-gatekeeper
```

Now create a require-labels ConstraintTemplate and a constraint in `dryrun` mode:

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabelstutorial2
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabelsTutorial2
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
        package k8srequiredlabelstutorial2

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
kind: K8sRequiredLabelsTutorial2
metadata:
  name: tutorial2-require-labels-dryrun
spec:
  enforcementAction: dryrun
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaces:
      - tutorial-opa-gatekeeper
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  parameters:
    labels:
      - app
      - owner
EOF
```

The constraint is now active in dryrun mode. It will not block any pods, but it will record violations. Wait for the audit controller to run (default interval is 60 seconds):

```bash
sleep 70
kubectl get k8srequiredlabelstutorial2 tutorial2-require-labels-dryrun -o yaml
```

Look at the `status` section. You will see:

```yaml
status:
  totalViolations: 2
  violations:
    - enforcementAction: dryrun
      kind: Pod
      message: 'Required labels missing: {"owner"}'
      name: violating-pod-2
      namespace: tutorial-opa-gatekeeper
    - enforcementAction: dryrun
      kind: Pod
      message: 'Required labels missing: {"app","owner"}'
      name: violating-pod-1
      namespace: tutorial-opa-gatekeeper
```

The audit controller has found both violating pods. `compliant-pod` does not appear because it has both required labels. Notice that the violation messages are per-resource and include the specific missing labels, making it straightforward to know what to fix.

## Section 2: The dryrun → Fix → deny Workflow

With the violations identified, fix the non-compliant pods before switching to deny:

```bash
kubectl label pod violating-pod-1 app=worker owner=bob -n tutorial-opa-gatekeeper
kubectl label pod violating-pod-2 owner=alice -n tutorial-opa-gatekeeper
```

Wait for the next audit cycle to confirm the violations are cleared:

```bash
sleep 70
kubectl get k8srequiredlabelstutorial2 tutorial2-require-labels-dryrun \
  -o jsonpath='{.status.totalViolations}'
# Expected: 0
```

With zero violations, it is safe to promote to deny. No existing pod will be blocked because all pods are now compliant:

```bash
kubectl patch k8srequiredlabelstutorial2 tutorial2-require-labels-dryrun \
  --type=merge \
  -p '{"spec":{"enforcementAction":"deny"}}'
```

Confirm that the deny mode now blocks new violating pods:

```bash
kubectl run new-violating-pod --image=nginx:1.27 --dry-run=server -n tutorial-opa-gatekeeper
# Expected: error from server containing "Required labels missing"
```

And compliant pods still pass:

```bash
kubectl run new-compliant-pod \
  --image=nginx:1.27 \
  --labels="app=web,owner=charlie" \
  --dry-run=server \
  -n tutorial-opa-gatekeeper
# Expected: pod/new-compliant-pod created (dry run)
```

This is the complete operational workflow for policy rollout. The key insight is that `dryrun` gives you visibility before enforcement, so you can remediate without causing an incident.

## Section 3: AssignMetadata Mutation

Mutation policies run before validation in the admission chain. When a pod is submitted, Gatekeeper's MutatingWebhookConfiguration sends the resource to the mutation controller, which applies all matching mutations. The modified resource is then re-sent through the admission chain, where the validating webhook evaluates it against all active Constraints.

`AssignMetadata` is a mutation resource specifically for metadata fields: labels and annotations. It injects or overwrites a single label or annotation key on matching resources.

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: AssignMetadata
metadata:
  name: tutorial2-inject-cost-center
spec:
  match:
    scope: Namespaced
    kinds:
      - apiGroups: ["*"]
        kinds: ["Pod"]
    namespaces:
      - tutorial-opa-gatekeeper
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  location: "metadata/labels/cost-center"
  parameters:
    assign:
      value: "platform"
EOF
```

The spec fields in detail:

`spec.match`: Standard Gatekeeper match block. For mutation resources, `scope: Namespaced` restricts the mutation to namespaced resources only. `kinds` specifies which resource types to mutate. The `apiGroups: ["*"]` wildcard matches all API groups. For pods specifically, the core group `""` works equally well; the wildcard is common in mutation resources because it's less likely to accidentally miss the right group.

`spec.location`: For AssignMetadata, this must be exactly `metadata/labels/<key>` or `metadata/annotations/<key>`. The key follows the slash. If you use any other path prefix, Gatekeeper rejects the AssignMetadata resource at apply time. This restriction exists because AssignMetadata is specifically designed for metadata; use Assign for spec-level mutations. If the field already exists, AssignMetadata overwrites it. There is no built-in "MustNotExist" condition for AssignMetadata (unlike Assign).

`spec.parameters.assign.value`: The string value to inject. Must be a string for labels and annotations. Valid label values follow Kubernetes naming conventions: alphanumeric, hyphens, underscores, dots, up to 63 characters.

Failure mode when misconfigured: If `location` doesn't start with `metadata/labels/` or `metadata/annotations/`, the AssignMetadata is rejected at creation time with a clear error. If `match` criteria are wrong (wrong apiGroups, wrong scope, typo in namespace), the mutation is accepted by Gatekeeper but silently never applies to any resources. Always verify by creating a test resource and inspecting its metadata.

Create a pod and verify the label was injected:

```bash
kubectl run mutated-web \
  --image=nginx:1.27 \
  --labels="app=web,owner=diana" \
  -n tutorial-opa-gatekeeper

kubectl get pod mutated-web -n tutorial-opa-gatekeeper \
  -o jsonpath='{.metadata.labels.cost-center}'
# Expected: platform
```

The `cost-center=platform` label was not in the `kubectl run` command. Gatekeeper's mutation controller injected it before the pod was persisted to etcd. This is the key mutation behavior: the user's submitted resource is modified before storage, so the stored resource is different from what the user submitted.

## Section 4: Assign Mutation

`Assign` is the general-purpose mutation resource for modifying any field in a resource, not just metadata. It can set fields in `spec`, inject security context defaults, or add default resource limits. Unlike AssignMetadata, Assign requires an `applyTo` field that specifies the exact API group, version, and kind of resource to target.

The following example injects `readOnlyRootFilesystem: true` into all containers in the tutorial namespace that don't already have this field set:

```bash
kubectl apply -f - <<EOF
apiVersion: mutations.gatekeeper.sh/v1
kind: Assign
metadata:
  name: tutorial2-set-readonly-root
spec:
  applyTo:
    - groups: [""]
      kinds: ["Pod"]
      versions: ["v1"]
  match:
    scope: Namespaced
    namespaces:
      - tutorial-opa-gatekeeper
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  location: "spec/containers/[name:*]/securityContext/readOnlyRootFilesystem"
  parameters:
    assign:
      value: true
    pathTests:
      - subPath: "spec/containers/[name:*]/securityContext/readOnlyRootFilesystem"
        condition: MustNotExist
EOF
```

The spec fields in detail:

`spec.applyTo`: Required for Assign. Specifies which API resources this mutation targets using group, version, and kind. Unlike `spec.match.kinds` (which controls instance filtering), `applyTo` controls the resource type routing at the API level. If `applyTo` is wrong (wrong group or version), the mutation is accepted but never applies. For core Kubernetes resources like Pods, use `groups: [""]` and `versions: ["v1"]`.

`spec.location`: A slash-separated JSONPath to the target field. Array elements are addressed using the `[key:value]` syntax where `key` is the name of the identifying field and `value` is the value to match. The `*` wildcard matches all elements. `spec/containers/[name:*]/securityContext/readOnlyRootFilesystem` targets the `readOnlyRootFilesystem` field in `securityContext` for every container, regardless of name. If the path does not exist, Gatekeeper creates the intermediate fields as needed. If the path is wrong (e.g., `spec/container` instead of `spec/containers`), the mutation creates a spurious field that has no effect.

`spec.parameters.assign.value`: The value to set at the location. For boolean fields, pass `true` or `false` (not quoted strings).

`spec.parameters.pathTests`: Optional but strongly recommended. Controls when the mutation fires. Each entry has a `subPath` (a location to check) and a `condition` (`MustNotExist` or `MustExist`). With `MustNotExist`, the mutation only applies if the field at `subPath` does not already exist. This prevents Gatekeeper from overriding an explicit user setting. If you omit `pathTests`, the mutation always overwrites the field, even if the user explicitly set it to `false`. For opt-out patterns where users can override defaults, always use `MustNotExist`.

Failure modes when misconfigured:
- Wrong `applyTo` group/version: mutation is accepted by Gatekeeper but never fires. Verify by creating a test pod and checking the field.
- Wrong `location` path: Gatekeeper may create a spurious field at the wrong path with no effect on the intended field.
- Missing `pathTests`: mutation overrides explicit user settings, which can break workloads that intentionally need the field set differently.
- Wrong `match` criteria: mutation targets the wrong namespaces or resources.

Create a pod and verify the mutation applied:

```bash
kubectl run readonly-test \
  --image=nginx:1.27 \
  --labels="app=test,owner=eric" \
  -n tutorial-opa-gatekeeper

kubectl get pod readonly-test -n tutorial-opa-gatekeeper \
  -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
# Expected: true
```

Now verify that a pod that explicitly sets `readOnlyRootFilesystem: false` is not overridden (because of `pathTests: MustNotExist`):

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: explicit-false
  namespace: tutorial-opa-gatekeeper
  labels:
    app: legacy
    owner: fiona
spec:
  containers:
    - name: app
      image: nginx:1.27
      securityContext:
        readOnlyRootFilesystem: false
EOF

kubectl get pod explicit-false -n tutorial-opa-gatekeeper \
  -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
# Expected: false  (mutation did not override the explicit setting)
```

## Section 5: Policy Troubleshooting

When a policy is not behaving as expected, there are four places to look: the ConstraintTemplate status (Rego compilation), the Constraint status (violation counts, match conditions), the Gatekeeper controller logs (admission webhook errors), and the Mutation resource status (for mutation issues).

### Reading Gatekeeper Controller Logs

The controller-manager pods log every admission decision that results in a webhook call. When debugging why a policy is or is not triggering, the logs can show the raw admission request and the constraint evaluation result:

```bash
kubectl logs -n gatekeeper-system \
  -l control-plane=controller-manager \
  --tail=50
```

Look for lines mentioning the constraint name, the resource kind, and either `denied` or `allowed`. Errors in Rego evaluation also appear here with context about which constraint caused the error.

### Webhook Failure Modes

Gatekeeper's ValidatingWebhookConfiguration has a `failurePolicy` field that controls what happens if the Gatekeeper webhook is unreachable:

```bash
kubectl get validatingwebhookconfiguration gatekeeper-validating-webhook-configuration -o yaml \
  | grep failurePolicy
```

`failurePolicy: Fail` (the default) means: if Gatekeeper is unreachable, reject ALL admission requests. This is the secure default because it prevents policy bypass during Gatekeeper downtime. However, it also means that if all Gatekeeper pods crash, no new pods can be created until Gatekeeper recovers. `failurePolicy: Ignore` means: if Gatekeeper is unreachable, allow all requests. This is safer for cluster operations but creates a security gap during downtime.

Understanding this is important for exam scenarios where you need to explain why pods cannot be created even though no constraint should block them.

### Diagnosing a Constraint with Zero Violations

A common issue: you apply a constraint expecting it to report violations, but `status.totalViolations` is 0 when violations clearly exist. Possible causes:

1. The `match.kinds` is wrong. Check whether the `apiGroups` field matches the target resource. Pods use `apiGroups: [""]`, not `["v1"]`.
2. The `match.namespaces` or `match.namespaceSelector` is too restrictive. The resources exist in a namespace not covered by the match.
3. The audit controller has not yet run. Wait 90 seconds and recheck.
4. The Config resource's `syncOnly` does not include the resource type, so the audit controller is not caching it.

Check each of these in sequence:

```bash
# Inspect match configuration
kubectl get k8srequiredlabelstutorial2 tutorial2-require-labels-dryrun -o yaml | grep -A20 match

# Force an audit cycle check
kubectl get k8srequiredlabelstutorial2 tutorial2-require-labels-dryrun \
  -o jsonpath='{.status.auditTimestamp}'
```

The `auditTimestamp` shows when the last audit ran. If it is recent (within the last 2 minutes), the constraint did run but found nothing, suggesting a match issue rather than a timing issue.

### Diagnosing a Mutation Not Applying

When a mutation resource exists but the injected field is not appearing on created resources:

```bash
# Check if the mutation resource itself has errors
kubectl describe assignmetadata tutorial2-inject-cost-center
kubectl describe assign tutorial2-set-readonly-root
```

Look at the `Status` section for errors. Then verify the match criteria:
- Is `scope` set correctly? Pods are `Namespaced`.
- Does `kinds` specify the right `apiGroups`? Pods use `""` (or `"*"` as wildcard).
- Is the namespace in `namespaces` or is it excluded by `excludedNamespaces`?
- For Assign: does `applyTo` specify the right group, version, and kind?

Create a test pod and check whether the field is present:

```bash
kubectl run mutation-test --image=nginx:1.27 --labels="app=test,owner=george" \
  -n tutorial-opa-gatekeeper

kubectl get pod mutation-test -n tutorial-opa-gatekeeper -o yaml \
  | grep -A5 "cost-center"
```

If the field is absent, the mutation did not fire. Re-read the match criteria and applyTo configuration.

## Section 6: The Gatekeeper Config Resource

The Config resource in the `gatekeeper-system` namespace controls the audit controller's behavior. The most important field is `spec.sync.syncOnly`, which tells the audit controller which resource types to cache in memory. The audit controller needs this cache to evaluate Rego policies that reference `data.inventory` (existing cluster state).

For most simple policies (those that evaluate only `input.review.object`), the Config resource is not needed. But if a Rego policy checks whether a resource exists elsewhere in the cluster, that data must be in the sync cache. A policy that checks "is there already a pod with this name in the cluster?" would need Pods in `syncOnly`.

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

The `syncOnly` list tells the audit controller to cache Namespaces and Pods. Without this, a Rego policy that reads `data.inventory.namespace["default"]["v1"]["Pod"]` would find nothing and might behave incorrectly.

Namespace exclusion from enforcement does NOT use the Config resource. It uses `excludedNamespaces` in each Constraint's `spec.match`. The Config resource's `syncOnly` is purely about which resources the audit controller caches for reference; it does not control which namespaces are excluded from validation.

## Section 7: Progressive Namespace-by-Namespace Enforcement

In large clusters, you often want to roll out a policy incrementally: first to one namespace, then to more, then cluster-wide. The `namespaceSelector` in a Constraint's match block supports this. Label namespaces with a phase indicator and tighten the selector as you grow the rollout:

```bash
# Phase 1: label one namespace as ready for enforcement
kubectl label namespace tutorial-opa-gatekeeper policy-phase=v1

# Create a constraint that only targets namespaces in phase v1
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabelsTutorial2
metadata:
  name: tutorial2-require-labels-phased
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    namespaceSelector:
      matchLabels:
        policy-phase: v1
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  parameters:
    labels:
      - app
      - owner
EOF
```

Test that the constraint applies to the labeled namespace:

```bash
kubectl run phase-test --image=nginx:1.27 --dry-run=server -n tutorial-opa-gatekeeper
# Expected: error (namespace has policy-phase=v1 label, pod missing required labels)
```

Create a new namespace without the phase label and verify it is exempt:

```bash
kubectl create namespace tutorial-opa-unlabeled
kubectl run phase-test --image=nginx:1.27 --dry-run=server -n tutorial-opa-unlabeled
# Expected: pod/phase-test created (dry run) - exempt because namespace lacks the label
```

## Cleanup

```bash
# Tutorial namespaces
kubectl delete namespace tutorial-opa-gatekeeper tutorial-opa-unlabeled --ignore-not-found

# Mutation resources
kubectl delete assignmetadata tutorial2-inject-cost-center --ignore-not-found
kubectl delete assign tutorial2-set-readonly-root --ignore-not-found

# Constraints
kubectl delete k8srequiredlabelstutorial2 tutorial2-require-labels-dryrun tutorial2-require-labels-phased --ignore-not-found

# ConstraintTemplates
kubectl delete constrainttemplate k8srequiredlabelstutorial2 --ignore-not-found

# Config resource (optional; leave if other tutorials use it)
kubectl delete config config -n gatekeeper-system --ignore-not-found
```

## Reference Commands

| Task | Command |
|---|---|
| Check constraint violations | `kubectl get <kind> <name> -o yaml` |
| Total violation count | `kubectl get <kind> <name> -o jsonpath='{.status.totalViolations}'` |
| Last audit timestamp | `kubectl get <kind> <name> -o jsonpath='{.status.auditTimestamp}'` |
| List AssignMetadata resources | `kubectl get assignmetadata` |
| Inspect mutation resource | `kubectl describe assignmetadata <name>` |
| List Assign resources | `kubectl get assign` |
| Verify mutation applied | `kubectl get pod <name> -o jsonpath='{.metadata.labels.<key>}'` |
| Verify mutation applied (field) | `kubectl get pod <name> -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'` |
| Change enforcementAction to deny | `kubectl patch <kind> <name> --type=merge -p '{"spec":{"enforcementAction":"deny"}}'` |
| Gatekeeper controller logs | `kubectl logs -n gatekeeper-system -l control-plane=controller-manager --tail=50` |
| Webhook failure policy | `kubectl get validatingwebhookconfiguration gatekeeper-validating-webhook-configuration -o yaml \| grep failurePolicy` |
| View Config resource | `kubectl get config config -n gatekeeper-system -o yaml` |
| Add namespace label for phased rollout | `kubectl label namespace <ns> policy-phase=v1` |
| Force audit by restarting audit pod | `kubectl delete pod -n gatekeeper-system -l control-plane=audit-controller` |
