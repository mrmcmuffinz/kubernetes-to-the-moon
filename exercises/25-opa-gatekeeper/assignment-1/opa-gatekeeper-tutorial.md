# OPA/Gatekeeper Tutorial: ConstraintTemplates and Policy Enforcement

## Introduction

Every Kubernetes cluster has admission controllers sitting between the API server and etcd. When you run `kubectl apply`, the request passes through these controllers before any object is persisted, and any controller can reject the request with an error message. The built-in admission controllers cover common cases, but organizations invariably need custom policies: all pods must carry cost-center labels, no container may run as privileged, images must come from an approved internal registry. Building that kind of policy with webhooks means writing, hosting, and maintaining a webhook server yourself.

OPA/Gatekeeper solves this by providing a general-purpose admission webhook backed by the Open Policy Agent engine. You write policies in a language called Rego and package them as ConstraintTemplates. Gatekeeper installs the webhook for you, compiles your Rego at policy-load time, and evaluates it against every incoming admission request. The result is an extensible policy engine that you configure purely through Kubernetes resources, with no external webhook server to maintain.

This tutorial walks through the complete Gatekeeper policy authoring cycle. You will install Gatekeeper, understand its architecture, author four ConstraintTemplates covering the most common policy patterns, create Constraint resources that instantiate those templates, and test that compliant resources are admitted while violating resources are blocked with clear error messages. By the end you will have the mental model and muscle memory for the full workflow, which the exercises then put into practice.

## Prerequisites

This tutorial assumes a running single-node kind cluster. Follow the [single-node cluster setup](../../../docs/cluster-setup.md#single-node-kind-cluster) in `docs/cluster-setup.md` before continuing. You need `kubectl` configured to target the cluster. No additional add-ons (MetalLB, Calico, ingress controllers) are required.

## Setup: Installing Gatekeeper

Gatekeeper ships as a single manifest that installs all its components into the `gatekeeper-system` namespace. Check the [Gatekeeper releases page](https://github.com/open-policy-agent/gatekeeper/releases) for the current stable version and substitute it below. This tutorial uses v3.17.1.

```bash
GATEKEEPER_VERSION=v3.17.1
kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/${GATEKEEPER_VERSION}/deploy/gatekeeper.yaml
```

The manifest creates the `gatekeeper-system` namespace, installs the CRDs (ConstraintTemplate, Config, and others), deploys the controller-manager pods, deploys the audit pod, and registers the ValidatingWebhookConfiguration. Watch the pods come up:

```bash
kubectl get pods -n gatekeeper-system --watch
```

You should eventually see output similar to:

```text
NAME                                             READY   STATUS    RESTARTS   AGE
gatekeeper-audit-5f8d9b6c7-xqpn2                1/1     Running   0          45s
gatekeeper-controller-manager-7d4f8b9c6-hkzl4   1/1     Running   0          45s
gatekeeper-controller-manager-7d4f8b9c6-mrt9v   1/1     Running   0          45s
gatekeeper-controller-manager-7d4f8b9c6-wlp3x   1/1     Running   0          45s
```

Three controller-manager replicas provide high availability for the webhook. The single audit pod runs the periodic background check against existing cluster resources. Once all pods show `1/1 Running`, wait for the webhook to be ready:

```bash
kubectl wait --for=condition=ready pod \
  -l control-plane=controller-manager \
  -n gatekeeper-system \
  --timeout=120s
```

Do not create any ConstraintTemplates or Constraints until this wait completes. The webhook must be registered and serving before any policy takes effect.

Now create the tutorial namespace:

```bash
kubectl create namespace tutorial-opa-gatekeeper
```

## Gatekeeper Architecture

Gatekeeper's core concept is the Constraint Framework. Understanding it requires holding two resource types in mind simultaneously: the ConstraintTemplate and the Constraint.

A ConstraintTemplate does two things when you apply it. First, it creates a new CRD in the cluster whose `kind` you specify in the template's `spec.crd.spec.names.kind` field. Second, it embeds a Rego policy in its `spec.targets[].rego` field. The Rego policy defines what constitutes a violation. Once the CRD exists, you create instances of it as Constraints. Each Constraint says: use the Rego logic from this template, apply it to these resource types, scope it to these namespaces, and enforce it with this action (deny, dryrun, or warn).

The ValidatingWebhookConfiguration that Gatekeeper installs intercepts admission requests and runs every applicable Constraint's Rego policy against the incoming object. If any violation is found, the webhook returns a rejection with the violation message. If the enforcement action is `dryrun`, the violation is recorded in the Constraint's status without blocking the request.

The audit controller runs separately on a configurable interval (default 60 seconds). It re-evaluates all existing cluster resources against all active Constraints and records violations in each Constraint's `status.totalViolations` and `status.violations` fields. This catches resources that were created before a Constraint existed or before a policy was tightened.

One critical operational rule: always exclude the `gatekeeper-system` namespace from all Constraints. Gatekeeper's own pods must be able to start and restart without being caught by your policies. Excluding `kube-system` is equally important for cluster stability.

## The ConstraintTemplate Structure

Let's look at the anatomy of a ConstraintTemplate before writing one. Every template has the same high-level shape:

```yaml
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: <lowercase-kind-name>   # must exactly match the lowercase of spec.crd.spec.names.kind
spec:
  crd:
    spec:
      names:
        kind: <PascalCaseKindName>  # the CRD kind that Constraints will use
      validation:
        openAPIV3Schema:            # schema for spec.parameters in Constraints
          type: object
          properties:
            <param-name>:
              type: <type>
  targets:
    - target: admission.k8s.gatekeeper.sh  # always this value for Kubernetes admission
      rego: |
        package <lowercase-kind-name>

        violation[{"msg": msg}] {
          # Rego conditions
          msg := sprintf("...", [...])
        }
```

The spec fields in detail:

`spec.crd.spec.names.kind`: Defines the kind name of the new CRD Gatekeeper creates. This is the value you use in `kind:` when writing a Constraint. The metadata.name of the ConstraintTemplate must be the all-lowercase version of this kind. If `kind` is `K8sRequiredLabels`, the name must be `k8srequiredlabels`. Mismatch causes Gatekeeper to reject the template.

`spec.crd.spec.validation.openAPIV3Schema`: Defines the schema for the `spec.parameters` field that Constraints pass to the Rego policy. Gatekeeper validates Constraints against this schema before applying them. If you omit the schema, Gatekeeper accepts any parameters without validation, which can lead to runtime errors in your Rego if the parameters have an unexpected shape.

`spec.targets[].target`: Must be exactly `admission.k8s.gatekeeper.sh`. Any other value causes the template to be rejected.

`spec.targets[].rego`: The Rego policy code. Gatekeeper compiles this at template-load time. Compilation errors appear in the ConstraintTemplate's `status.byPod` field. The code must define a `violation` rule that produces objects of the form `{"msg": msg}` where `msg` is a string describing the violation. If the rule body evaluates to false or undefined, no violation is reported.

When the Rego compilation fails, the template status will contain entries like:

```bash
kubectl describe constrainttemplate <name>
# Look for: status.byPod[*].errors
```

## Writing Your First ConstraintTemplate: Require Labels

The scenario: your organization's alerting system identifies workloads by their `app` and `owner` labels. Any pod without both labels is invisible to alerting. You want to enforce these labels on all pods.

The Rego for this policy needs to:
1. Collect the set of labels currently on the pod
2. Collect the set of required labels from the policy parameters
3. Compute the difference (required minus provided)
4. Fire a violation if any required labels are missing

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
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
        package k8srequiredlabels

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Required labels are missing: %v", [missing])
        }
EOF
```

Walk through the Rego carefully. `input.review.object` is the admission request object: the pod YAML that was submitted. `input.review.object.metadata.labels` is a map of label key to value. The comprehension `{label | input.review.object.metadata.labels[label]}` iterates over all label keys and collects them into a set. Similarly, `{label | label := input.parameters.labels[_]}` builds a set from the array of required label names passed in from the Constraint's `spec.parameters`. The `_` is a wildcard index that iterates over every element. Set subtraction (`required - provided`) produces the labels that are required but not present. If that set is non-empty (`count(missing) > 0`), the violation fires with a message listing the missing labels.

After applying the template, verify that Gatekeeper created the new CRD:

```bash
kubectl get crd k8srequiredlabels.constraints.gatekeeper.sh
```

```text
NAME                                          CREATED AT
k8srequiredlabels.constraints.gatekeeper.sh   2025-01-15T14:30:00Z
```

Check the template status to confirm Rego compiled without errors:

```bash
kubectl get constrainttemplate k8srequiredlabels -o yaml | grep -A10 "status:"
```

If the `status.byPod` list shows entries with empty `errors` arrays, the Rego is valid and active. If you see a non-empty `errors` field, the Rego failed to compile and the policy is not enforcing.

## Creating a Constraint

A Constraint is an instance of the CRD that the ConstraintTemplate created. It binds the Rego policy to specific resource types, namespaces, and parameters:

```bash
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: tutorial-require-app-owner
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  parameters:
    labels:
      - app
      - owner
EOF
```

The Constraint spec fields in detail:

`spec.enforcementAction`: Controls what happens when a violation is found. `deny` rejects the admission request and returns an error to the user. `dryrun` records the violation in the Constraint's status but admits the resource. `warn` admits the resource but includes the violation message as a warning in the API response. Default is `deny`. When rolling out a new policy, starting with `dryrun` is safer because it lets you discover violations without breaking existing workflows.

`spec.match.kinds`: An array of objects with `apiGroups` and `kinds` fields specifying which resource types this constraint evaluates. For core API resources (Pods, Services, ConfigMaps), `apiGroups` is `[""]` (the empty string). For Deployments, it is `["apps"]`. If you omit `kinds`, the constraint evaluates all resource types, which is almost always too broad. Specifying the wrong `apiGroups` (for example, using `"v1"` instead of `""`) causes the constraint to match nothing silently.

`spec.match.namespaces`: Restrict the constraint to a list of specific namespaces by name. If omitted, the constraint applies cluster-wide.

`spec.match.excludedNamespaces`: A list of namespaces to skip. Always include `gatekeeper-system` here. Omitting it means Gatekeeper's own controller pods could be evaluated against your policy, which can prevent Gatekeeper from restarting during upgrades. Including `kube-system` is equally important to prevent system pod disruptions.

`spec.match.namespaceSelector`: A standard Kubernetes label selector that matches namespaces by their labels. Use this for fine-grained progressive rollout: label namespaces as `policy=enforced` and scope the constraint to those namespaces, then gradually add the label to more namespaces.

`spec.match.labelSelector`: Selects individual resources by label. Combined with `namespaceSelector`, this lets you apply a constraint only to pods carrying a specific label, which is useful for exempting legacy workloads from a new policy.

`spec.parameters`: Passed into the Rego policy as `input.parameters`. The shape must conform to the schema defined in the ConstraintTemplate. If you provide a key that the schema doesn't define or pass the wrong type, the Constraint is rejected by Gatekeeper's validating webhook. If the Rego tries to access `input.parameters.labels` and the Constraint doesn't include a `labels` field, the Rego evaluates `input.parameters.labels` as undefined, typically causing the violation block to never fire.

## Testing the Policy

First, confirm a compliant pod is admitted. Create a pod with both required labels:

```bash
kubectl run compliant-web \
  --image=nginx:1.27 \
  --labels="app=web,owner=platform-team" \
  -n tutorial-opa-gatekeeper
```

The pod should be created without errors. Verify it is running:

```bash
kubectl get pod compliant-web -n tutorial-opa-gatekeeper
# Expected: STATUS Running (after image pull)
```

Now try a pod missing both labels. Since this will be rejected, use `--dry-run=server` to test without persisting:

```bash
kubectl run violating-web \
  --image=nginx:1.27 \
  --dry-run=server \
  -n tutorial-opa-gatekeeper
```

Expected output:

```text
Error from server (Forbidden): admission webhook "validation.gatekeeper.sh" denied the request: [tutorial-require-app-owner] Required labels are missing: {"app","owner"}
```

The error message includes the constraint name in brackets, making it clear which policy blocked the request. Now try a pod with only one label missing:

```bash
kubectl run partial-web \
  --image=nginx:1.27 \
  --labels="app=web" \
  --dry-run=server \
  -n tutorial-opa-gatekeeper
```

```text
Error from server (Forbidden): ... [tutorial-require-app-owner] Required labels are missing: {"owner"}
```

The violation message adapts to show exactly which labels are missing. This specificity is what makes Gatekeeper policies useful in practice: developers get actionable errors rather than generic rejection messages.

Check the constraint status to see recorded violations:

```bash
kubectl describe constraint tutorial-require-app-owner
```

Look for the `Status` section which shows `Total Violations`. The audit controller periodically sweeps existing resources; `compliant-web` has both labels and should not appear in violations.

## The disallow-privileged Pattern

Privileged containers can break out of their container boundaries and access host resources. The `disallow-privileged` pattern uses one important Rego technique: a helper function to iterate over both `spec.containers` and `spec.initContainers`. A policy that checks only `spec.containers` misses privileged init containers, which is a common exam gotcha.

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8sdisallowprivileged
spec:
  crd:
    spec:
      names:
        kind: K8sDisallowPrivileged
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8sdisallowprivileged

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
```

The `input_containers` helper is defined twice with different bodies. In Rego, multiple definitions of the same rule are combined with OR: `input_containers` evaluates to every container from `spec.containers` OR from `spec.initContainers`. The violation block iterates over this unified set using `[_]`, which means "any element." If any element has `securityContext.privileged == true`, the violation fires for that container.

Create a Constraint applying this template:

```bash
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sDisallowPrivileged
metadata:
  name: tutorial-no-privileged
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
EOF
```

Test with a privileged container:

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: priv-test
  namespace: tutorial-opa-gatekeeper
spec:
  containers:
    - name: shell
      image: busybox:1.36
      command: ["sleep", "3600"]
      securityContext:
        privileged: true
EOF
```

```text
Error from server (Forbidden): ... [tutorial-no-privileged] Container shell has privileged: true, which is not permitted
```

Test with a privileged init container to verify the helper covers both:

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: priv-init-test
  namespace: tutorial-opa-gatekeeper
spec:
  initContainers:
    - name: setup
      image: busybox:1.36
      command: ["sh", "-c", "echo init"]
      securityContext:
        privileged: true
  containers:
    - name: app
      image: nginx:1.27
EOF
```

The init container is caught by the helper, and the violation fires even though the main container is not privileged.

## The restrict-registries Pattern

Registry restriction ensures images come from approved sources. This pattern requires parameters (the list of allowed registries), demonstrates the `startswith` Rego built-in, and uses the same `input_containers` helper to cover init containers.

An important nuance: the image string in a pod spec is whatever the user typed. `nginx:1.27` is a different string from `docker.io/library/nginx:1.27` even though they refer to the same image. In the tutorial exercises you will use explicit registry prefixes (`docker.io/library/nginx:1.27`) to make the policy logic unambiguous. In production you would add logic to normalize short image names, but that is out of scope for this assignment.

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srestrictregistries
spec:
  crd:
    spec:
      names:
        kind: K8sRestrictRegistries
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
        package k8srestrictregistries

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
```

The `registry_allowed` helper iterates over every allowed registry prefix and returns true if any prefix matches. The `not registry_allowed(c.image)` in the violation block inverts this: the violation fires only when NO allowed prefix matches the image. The `_` in `input.parameters.allowedRegistries[_]` is Rego's way of saying "for some element in this array"; it does not need to iterate all elements and return all matches, because `registry_allowed` returns as soon as one prefix matches.

Create a Constraint:

```bash
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRestrictRegistries
metadata:
  name: tutorial-restrict-registries
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
  parameters:
    allowedRegistries:
      - "docker.io/library/"
      - "registry.k8s.io/"
EOF
```

Test with a compliant image (fully qualified with allowed registry prefix):

```bash
kubectl run compliant-image-test \
  --image=docker.io/library/nginx:1.27 \
  --dry-run=server \
  -n tutorial-opa-gatekeeper
```

This should succeed. Now test with a disallowed registry:

```bash
kubectl run violating-image-test \
  --image=quay.io/prometheus/busybox:1.36 \
  --dry-run=server \
  -n tutorial-opa-gatekeeper
```

```text
Error from server (Forbidden): ... [tutorial-restrict-registries] Container violating-image-test uses a disallowed registry. Image: quay.io/prometheus/busybox:1.36. Allowed: ["docker.io/library/","registry.k8s.io/"]
```

## The require-resource-limits Pattern

Resource limits prevent noisy-neighbor problems and protect cluster stability. The `require-resource-limits` pattern uses `not` to check for the absence of a field, which is slightly counterintuitive in Rego: `not c.resources.limits.cpu` evaluates to true when the `cpu` field under `resources.limits` is absent or falsy.

```bash
kubectl apply -f - <<EOF
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequireresourcelimits
spec:
  crd:
    spec:
      names:
        kind: K8sRequireResourceLimits
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequireresourcelimits

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
```

Note that there are two separate `violation` definitions: one for missing CPU and one for missing memory. In Rego, multiple violation definitions are all evaluated independently. If a container is missing both limits, both violations fire and both messages appear in the rejection error. This gives developers specific, actionable feedback.

The key insight is `not c.resources.limits.cpu`. When a container has no `resources` block at all, `c.resources` is undefined. In Rego, accessing a field on an undefined object also yields undefined. The `not` of an undefined expression is true. So this condition fires whether `resources` is missing entirely, `resources.limits` is missing, or `resources.limits.cpu` specifically is missing. All three cases produce the violation.

Create a Constraint for this template:

```bash
kubectl apply -f - <<EOF
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequireResourceLimits
metadata:
  name: tutorial-require-limits
spec:
  enforcementAction: deny
  match:
    kinds:
      - apiGroups: [""]
        kinds: ["Pod"]
    excludedNamespaces:
      - gatekeeper-system
      - kube-system
EOF
```

Test with a pod that has no resource limits:

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: no-limits-test
  namespace: tutorial-opa-gatekeeper
spec:
  containers:
    - name: app
      image: nginx:1.27
EOF
```

```text
Error from server (Forbidden): ... [tutorial-require-limits] Container app is missing a CPU limit, [tutorial-require-limits] Container app is missing a memory limit
```

Both violations appear in the same error message, separated by commas. Now test with a compliant pod:

```bash
kubectl apply --dry-run=server -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: limits-test
  namespace: tutorial-opa-gatekeeper
spec:
  containers:
    - name: app
      image: nginx:1.27
      resources:
        limits:
          cpu: "200m"
          memory: "256Mi"
EOF
```

This should succeed with no error.

## Cleanup

Delete the tutorial namespace and all cluster-scoped Gatekeeper resources:

```bash
kubectl delete namespace tutorial-opa-gatekeeper

# Delete constraints (instances of the CRDs)
kubectl delete k8srequiredlabels tutorial-require-app-owner --ignore-not-found
kubectl delete k8sdisallowprivileged tutorial-no-privileged --ignore-not-found
kubectl delete k8srestrictregistries tutorial-restrict-registries --ignore-not-found
kubectl delete k8srequireresourcelimits tutorial-require-limits --ignore-not-found

# Delete constraint templates (these also delete the CRDs and all constraints of that type)
kubectl delete constrainttemplate k8srequiredlabels k8sdisallowprivileged k8srestrictregistries k8srequireresourcelimits --ignore-not-found
```

Deleting a ConstraintTemplate also deletes the CRD it created and all Constraint resources of that type. After cleanup, confirm no tutorial constraints remain:

```bash
kubectl get constrainttemplate
# Expected: No resources found (or only resources created in other sessions)
```

## Reference Commands

| Task | Command |
|---|---|
| Install Gatekeeper | `kubectl apply -f https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.17.1/deploy/gatekeeper.yaml` |
| Wait for webhook ready | `kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n gatekeeper-system --timeout=120s` |
| List all ConstraintTemplates | `kubectl get constrainttemplate` |
| Inspect CT status for Rego errors | `kubectl describe constrainttemplate <name>` |
| List all Constraints of a type | `kubectl get <constraint-kind>` |
| Check constraint violations | `kubectl describe <constraint-kind> <name>` |
| Full violation details | `kubectl get <constraint-kind> <name> -o yaml` |
| Test admission (dry run) | `kubectl apply --dry-run=server -f <file>` |
| Change enforcementAction | `kubectl patch <kind> <name> --type=merge -p '{"spec":{"enforcementAction":"deny"}}'` |
| Delete a ConstraintTemplate | `kubectl delete constrainttemplate <name>` |
| Delete a Constraint | `kubectl delete <constraint-kind> <name>` |
| View Gatekeeper controller logs | `kubectl logs -n gatekeeper-system -l control-plane=controller-manager` |
