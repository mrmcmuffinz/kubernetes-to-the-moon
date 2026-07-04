# Assignment Prompt: OPA/Gatekeeper — Assignment 1

**Series:** OPA/Gatekeeper (1 of 2)
**Topic slug:** opa-gatekeeper
**Topic directory:** exercises/25-opa-gatekeeper/assignment-1/

## Metadata

**Domain:** CKS — Minimize Microservice Vulnerabilities (20%)
**Competencies:** Gatekeeper architecture, ConstraintTemplate authoring, Constraint resources, enforcement actions
**Prerequisites:** 16-admission-controllers/assignment-1, 12-rbac/assignment-1

## Scope — In Scope

*Gatekeeper architecture*
- What Gatekeeper is: an OPA-based admission controller implementing the Kubernetes Constraint Framework
- The ValidatingWebhookConfiguration Gatekeeper installs (gatekeeper-validating-webhook-configuration)
- The audit controller: runs periodically to check existing resources against constraints
- Core CRDs: ConstraintTemplate (defines a new constraint type), Constraint instances (enforce the template), Config (Gatekeeper configuration)
- Installing Gatekeeper: kubectl apply -f the official release manifest, verifying gatekeeper-controller-manager and gatekeeper-audit pods are running

*ConstraintTemplate authoring*
- spec.crd.spec.names: the openAPIV3Schema and names.kind field that define the new Constraint CRD
- spec.targets[].rego: the OPA Rego policy logic
- input.review.object: accessing the incoming Kubernetes resource
- input.parameters: accessing parameters passed from the Constraint resource
- The violation block: `violation[{"msg": msg}]` structure
- The deny block alternative: when to use deny vs violation

*Rego basics for Kubernetes policies*
- Package declaration: package k8srequiredlabels
- Rules and functions in Rego
- String operations: startswith, contains, endswith, sprintf
- Array/set operations: count, input.review.object.spec.containers[_]
- Negation: not
- The msg field must be a string describing the violation clearly

*Common policy patterns to implement*
- require-labels: all pods must have a specific label key (e.g., app, owner, env); parameters: required label names
- disallow-privileged: no container may have securityContext.privileged: true
- restrict-registries: container images must start with an approved registry prefix; parameters: allowed registry list
- require-resource-limits: all containers must have CPU and memory limits set

*Constraint resources*
- spec.enforcementAction: deny (blocks the resource), dryrun (records violations but allows), warn (allows with a warning)
- spec.match.kinds: targeting specific resource types (pods, deployments)
- spec.match.namespaceSelector and labelSelector: scoping the constraint to specific namespaces
- spec.parameters: passing values into the Rego policy

*Testing policies*
- Deploying a compliant resource: should be admitted without errors
- Deploying a violating resource: observe the denial message from Gatekeeper
- kubectl describe constraint <name>: reading violation counts in status.totalViolations
- kubectl get constraint <name> -o yaml: reading the full status including violation details

## Scope — Out of Scope

- Audit mode and mutation: covered in opa-gatekeeper/assignment-2
- Gatekeeper Config resource for namespace exclusions: covered in opa-gatekeeper/assignment-2
- Built-in Kubernetes admission controllers: covered in 16-admission-controllers
- ValidatingAdmissionPolicy (CEL-based): covered in 16-admission-controllers/assignment-1

## Environment

Single-node kind cluster with Gatekeeper installed. The tutorial must include Gatekeeper installation steps and a readiness check (waiting for the webhook to become available before creating policies).

## Resource Gate

All Kubernetes resources are in scope. Exercises create ConstraintTemplate and Constraint resources as the primary work product.

## Topic-specific Conventions

- All ConstraintTemplate examples must include a test section in the tutorial showing both a compliant and a violating resource.
- Rego code must be syntactically correct — test it mentally by tracing through the logic with a sample input.review.object.
- Tutorial namespace: `tutorial-opa-gatekeeper`.
- The gatekeeper-system namespace should be excluded from all constraint matches to avoid breaking Gatekeeper itself.

## Exercise Distribution

- Level 1: Apply a provided ConstraintTemplate and Constraint, test with compliant and violating pods
- Level 2: Write a Constraint for an existing ConstraintTemplate with parameters; change enforcementAction from dryrun to deny
- Level 3 (debugging): Bare headings. Broken ConstraintTemplates (Rego syntax error, wrong input path, violation block not triggering)
- Level 4: Author a complete ConstraintTemplate from scratch implementing a require-resource-limits policy; create a Constraint and verify it blocks non-compliant pods
- Level 5 (debugging): A policy is admitting resources it should block; trace through the Rego logic to find the bug (wrong negation, wrong field path, missing container iteration)
