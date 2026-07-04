# OPA/Gatekeeper Assignment 1: ConstraintTemplates and Policy Enforcement

This is the first of two OPA/Gatekeeper assignments and covers the full policy authoring cycle: installing Gatekeeper in a kind cluster, understanding the Constraint Framework architecture, writing ConstraintTemplates in Rego, creating Constraint resources with enforcement actions, and testing policies against compliant and violating workloads. It assumes you have completed the admission-controllers assignment so that the concept of a validating webhook is already familiar. Assignment 2 builds on this foundation to cover audit mode, mutation policies, and operational troubleshooting. Together these two assignments prepare you for the CKS exam domain "Minimize Microservice Vulnerabilities," which tests your ability to use policy-based admission control to enforce organizational security standards across a cluster.

## Files

| File | Description |
|---|---|
| `README.md` | This overview file |
| `prompt.md` | The generation specification used to create this assignment |
| `opa-gatekeeper-tutorial.md` | Step-by-step tutorial covering Gatekeeper installation, ConstraintTemplate authoring in Rego, Constraint resource configuration, and policy testing |
| `opa-gatekeeper-homework.md` | 15 progressive exercises across five difficulty levels |
| `opa-gatekeeper-homework-answers.md` | Complete solutions with diagnostic reasoning and explanations for all 15 exercises |

## Recommended Workflow

Work through the tutorial before attempting the exercises. Gatekeeper introduces two new custom resource types whose relationship is easy to confuse: a ConstraintTemplate defines the policy logic in Rego and creates a new CRD, while a Constraint is an instance of that CRD that applies the policy to specific resource types with specific parameters. The tutorial builds that mental model by walking through the full cycle from installation to testing, so you arrive at the exercises with the vocabulary and workflow already internalized.

The exercises are sequenced deliberately. Level 1 provides pre-written ConstraintTemplates so you can practice the deployment and testing workflow before writing Rego yourself. Level 2 adds parameters and enforcement action changes. Level 3 puts you in the debugging seat with broken ConstraintTemplates. Level 4 asks you to author complete templates from scratch. Level 5 is advanced debugging where a policy looks valid but admits workloads it should block, requiring you to trace through the Rego logic manually.

## Difficulty Progression

Level 1 and Level 2 build fluency with the Gatekeeper API: applying provided ConstraintTemplates, creating Constraints with different enforcementAction values, scoping constraints with match selectors, and verifying that compliant pods are admitted while violating pods are rejected with informative error messages. Level 3 introduces debugging broken ConstraintTemplates, which is a realistic exam skill because Rego errors produce cryptic status conditions and require systematic inspection of CT status fields. Level 4 escalates to authoring complete ConstraintTemplates from scratch, including the `input_containers` helper function pattern that handles both `spec.containers` and `spec.initContainers`. Level 5 is the most demanding: a policy that starts up without errors but admits resources it should block, requiring you to trace the Rego logic with a sample `input.review.object` to find the misplaced condition. Anti-spoiler conventions apply to Levels 3 and 5: exercise headings are bare numbers and objectives do not state the bug count or type.

## Prerequisites

This assignment assumes you have completed 16-admission-controllers/assignment-1 (ValidatingAdmissionPolicy and built-in admission controllers) and 12-rbac/assignment-1 (RBAC fundamentals). The admission controller concepts carry over directly: Gatekeeper installs a ValidatingWebhookConfiguration, and requests flow through the admission chain the same way they do with built-in webhooks. No prior experience with OPA or Rego is required; the tutorial introduces both from scratch. Familiarity with YAML and kubectl is assumed throughout.

## Cluster Requirements

This assignment uses a single-node kind cluster. See the [single-node cluster setup section](../../../docs/cluster-setup.md#single-node-kind-cluster) in `docs/cluster-setup.md` for cluster creation steps. Gatekeeper is installed on top of the base cluster; the tutorial walks through installation and readiness verification before any policy work begins. You do not need MetalLB, Calico, or any other add-on beyond the base kind cluster.

## Estimated Time Commitment

Level 1 exercises take 5-8 minutes each: applying a provided manifest, creating a constraint, and running two or three verification commands to confirm admission behavior. Level 2 adds parameter configuration and enforcement action changes, running 8-12 minutes each. The three Level 3 debugging exercises take 10-15 minutes each depending on how quickly you find the Rego error. Level 4 requires authoring complete ConstraintTemplates from scratch and takes 15-20 minutes each. Level 5 is the most time-intensive at 20-25 minutes per exercise. Total estimated time including the tutorial walkthrough is 3-4 hours.

## Scope Boundary and What Comes Next

This assignment deliberately omits audit mode (dryrun enforcement for discovering pre-existing violations without blocking), mutation policies (AssignMetadata and Assign resources that modify resources at admission time), policy troubleshooting via Gatekeeper controller logs, and the Gatekeeper Config resource for audit sync configuration. These operational topics are covered in opa-gatekeeper/assignment-2 and build on the ConstraintTemplate and Constraint fluency this assignment develops. The ValidatingAdmissionPolicy CRD (the CEL-based built-in alternative to Gatekeeper) is covered in 16-admission-controllers/assignment-1 and is not revisited here.

## Key Takeaways After Completing This Assignment

After completing this assignment, you should be able to install Gatekeeper in a kind cluster and confirm the webhook is active, read the status fields on a ConstraintTemplate to diagnose Rego compilation errors, author a ConstraintTemplate that uses `input.review.object` and `input.parameters` correctly, create a Constraint that scopes to specific namespaces and resource kinds with proper excludedNamespaces, change enforcementAction between dryrun and deny and observe the difference in behavior, and implement the four common policy patterns (require-labels, disallow-privileged, restrict-registries, require-resource-limits) from scratch including correct iteration over both `spec.containers` and `spec.initContainers`. You should also be able to diagnose a broken policy by tracing Rego logic manually against a known `input.review.object` structure.
