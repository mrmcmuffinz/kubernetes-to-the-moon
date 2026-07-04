# OPA/Gatekeeper

**Topic area:** Policy-based admission control
**Certification relevance:** CKS (Minimize Microservice Vulnerabilities 20%)
**Assignments in this topic:** 2

---

## Why Two Assignments

OPA/Gatekeeper has two natural learning phases. The first is understanding the architecture and writing policies: deploying Gatekeeper, authoring ConstraintTemplates in Rego, creating Constraint resources, and testing enforcement. The second is the operational layer: audit mode for discovering existing violations, mutation policies for injecting defaults, and troubleshooting misbehaving policies. These phases require different skills (Rego authoring vs operational workflow) and warrant separate focused assignments.

---

## Assignment Summary

| Assignment | Focus | Prerequisites |
|---|---|---|
| assignment-1 | Gatekeeper installation, ConstraintTemplate authoring (Rego), Constraint resources, enforcement actions, testing policies | 16-admission-controllers/assignment-1, 12-rbac/assignment-1 |
| assignment-2 | Audit mode, mutation policies (AssignMetadata, Assign), policy troubleshooting, common policy patterns | opa-gatekeeper/assignment-1 |

---

## Assignment 1: ConstraintTemplates and Enforcement

Subtopics:
- *Gatekeeper architecture:* the ValidatingWebhookConfiguration Gatekeeper installs, the audit controller, the constraint framework CRDs (ConstraintTemplate, Config)
- *ConstraintTemplate authoring:* spec.crd.spec.names (the Constraint CRD it creates), spec.targets[].rego (the policy logic), input.review.object structure, how to access pod spec fields in Rego
- *Rego basics for Kubernetes policies:* deny rules, violation blocks, msg field for rejection messages, using future.keywords, basic Rego operators (==, !=, not, startswith, contains)
- *Constraint resources:* spec.enforcementAction (deny, dryrun, warn), spec.match (kinds, namespaceSelector, labelSelector), spec.parameters passing values into Rego via input.parameters
- *Common policy patterns:* require-labels (all pods must have specific labels), disallow-privileged (no privileged containers), restrict-registries (images must come from approved registries), require-resource-limits
- *Testing policies:* deploying a violating resource and observing the denial message, using kubectl describe constraint to see violation counts

---

## Assignment 2: Audit, Mutation, and Troubleshooting

Subtopics:
- *Audit mode:* setting enforcementAction: dryrun or warn, running the audit controller, kubectl get constraint -o yaml to read status.violations, using audit to discover pre-existing violations without blocking deployments
- *AssignMetadata mutation:* injecting labels and annotations into resources automatically, spec.match to target specific resource types, the Assign vs AssignMetadata distinction
- *Assign mutation:* mutating arbitrary fields (adding default resource limits, injecting securityContext defaults), location field for targeting nested fields
- *Policy troubleshooting:* Gatekeeper webhook failure modes (fail-open vs fail-closed), debugging Rego logic errors via constraint status, checking Gatekeeper controller logs
- *Config resource:* gatekeeper-system Config for excluding namespaces from enforcement, sync configuration for audit
- *Policy exemptions:* using namespace labels or constraint match exclusions to exempt specific namespaces or resources from a policy

---

## Scope Boundaries

**Not covered:**
- Kubernetes built-in admission controllers: covered in 16-admission-controllers
- ValidatingAdmissionPolicy (CEL-based): covered in 16-admission-controllers/assignment-1
- Image signing policy enforcement via Cosign: covered in 23-supply-chain-security/assignment-2
- NetworkPolicy: covered in 10-network-policies

---

## Cluster Requirements

Both assignments require Gatekeeper installed in the kind cluster. The tutorial must include the Gatekeeper installation steps (kubectl apply -f the official Gatekeeper manifest, waiting for the webhook to become ready). Single-node kind cluster is sufficient.

---

## Recommended Order

Assignment-1 before assignment-2. Audit and mutation build on the ConstraintTemplate concepts from assignment-1.
