# Assignment Prompt: OPA/Gatekeeper — Assignment 2

**Series:** OPA/Gatekeeper (2 of 2)
**Topic slug:** opa-gatekeeper
**Topic directory:** exercises/25-opa-gatekeeper/assignment-2/

## Metadata

**Domain:** CKS — Minimize Microservice Vulnerabilities (20%)
**Competencies:** Audit mode, mutation policies, policy troubleshooting, Gatekeeper Config
**Prerequisites:** opa-gatekeeper/assignment-1

## Scope — In Scope

*Audit mode*
- enforcementAction: dryrun — policies record violations without blocking
- The audit controller runs on a configurable interval and checks all existing resources
- kubectl get constraint <name> -o yaml: reading status.violations (list of violating resources with namespace, name, and message)
- Using audit to discover pre-existing violations before switching to deny enforcement
- The workflow: deploy as dryrun, review violations, fix existing resources, switch to deny

*AssignMetadata mutation*
- What AssignMetadata does: injects or overwrites metadata fields (labels, annotations) on resources matching the spec.match criteria
- spec.location: always "metadata/labels/<key>" or "metadata/annotations/<key>" for AssignMetadata
- spec.parameters.assign.value: the value to inject
- Use case: automatically adding a cost-center label, injecting a managed-by annotation

*Assign mutation*
- What Assign does: mutates arbitrary fields in matching resources (not just metadata)
- spec.location: JSONPath to the target field (e.g., spec/containers/0/securityContext/readOnlyRootFilesystem)
- Use cases: injecting default resource limits, setting readOnlyRootFilesystem: true, adding a default seccomp profile
- The condition field: only mutate if the field is not already set (spec.match.scope)

*Policy troubleshooting*
- Gatekeeper controller logs: kubectl logs -n gatekeeper-system -l control-plane=controller-manager
- Webhook failure modes: failurePolicy: Fail vs Ignore on the ValidatingWebhookConfiguration
- Rego logic bugs: policy not triggering when it should (wrong field path, wrong negation), policy triggering when it should not (overly broad match)
- Using dryrun to test before enabling deny
- Constraint status showing 0 violations when violations are expected: checking the match criteria, checking the audit interval

*Gatekeeper Config resource*
- The Config resource in gatekeeper-system: controls which resources the audit controller syncs
- Excluding namespaces from enforcement: spec.match.excludedNamespaces on Constraints (not Config)
- Excluding the gatekeeper-system namespace from all policies (critical for avoiding self-blocking)
- The syncOnly field in Config: specifying which resource types the audit controller caches

*Common operational policy patterns*
- Combining multiple Constraints for defense in depth: require-labels + restrict-registries + require-resource-limits all active simultaneously
- Rolling out policies progressively: dryrun all namespaces, fix violations, enforce namespace by namespace using namespaceSelector

## Scope — Out of Scope

- ConstraintTemplate authoring and Rego basics: covered in opa-gatekeeper/assignment-1
- ValidatingAdmissionPolicy (CEL): covered in 16-admission-controllers
- Cosign image verification in admission: covered in 23-supply-chain-security/assignment-2

## Environment

Single-node kind cluster with Gatekeeper installed (from opa-gatekeeper/assignment-1 setup). Mutation requires Gatekeeper 3.x with the mutation feature enabled (--enable-mutation flag on the controller, or the default in recent versions).

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- Mutation exercises must verify the mutation occurred by inspecting the created resource: kubectl get pod -o yaml and checking the injected field.
- Tutorial namespace: `tutorial-opa-gatekeeper`.

## Exercise Distribution

- Level 1: Run a constraint in dryrun mode, list violations from status, identify which existing pods are non-compliant
- Level 2: Write an AssignMetadata mutation to inject a label on all pods; write an Assign mutation to set a default seccomp profile
- Level 3 (debugging): Bare headings. Broken policies (mutation not applying because match criteria wrong, audit showing 0 violations when violations exist, constraint blocking gatekeeper-system namespace)
- Level 4: Full operational rollout — deploy constraints in dryrun, audit existing resources, fix violations, promote to deny with namespace-by-namespace enforcement
- Level 5 (debugging): A mutation policy and a validation policy are conflicting (mutation injects a value the validator then rejects); diagnose the interaction and resolve
