# OPA/Gatekeeper Assignment 2: Audit Mode, Mutation, and Policy Troubleshooting

This is the second of two OPA/Gatekeeper assignments and covers the operational layer of a Gatekeeper deployment. It builds directly on the ConstraintTemplate and Constraint authoring skills from assignment-1 and adds three new competencies: audit mode for discovering pre-existing violations without disrupting running workloads, mutation policies for automatically injecting default values into admitted resources, and policy troubleshooting for diagnosing the full range of ways a Gatekeeper configuration can misbehave. Together these two assignments cover the OPA/Gatekeeper material expected in the CKS exam domain "Minimize Microservice Vulnerabilities." Assignment-1 must be complete before starting this one because the exercises assume you can read and write ConstraintTemplates and Constraints fluently.

## Files

| File | Description |
|---|---|
| `README.md` | This overview file |
| `prompt.md` | The generation specification used to create this assignment |
| `opa-gatekeeper-tutorial.md` | Step-by-step tutorial covering audit mode workflows, AssignMetadata and Assign mutation resources, policy troubleshooting, and the Gatekeeper Config resource |
| `opa-gatekeeper-homework.md` | 15 progressive exercises across five difficulty levels |
| `opa-gatekeeper-homework-answers.md` | Complete solutions with diagnostic reasoning and explanations for all 15 exercises |

## Recommended Workflow

Work through the tutorial before attempting the exercises. Mutation resources (AssignMetadata and Assign) introduce a new admission phase that runs before validation, and understanding the sequencing is essential for diagnosing the Level 5 exercises where a mutation and a validator interact unexpectedly. The tutorial covers each topic with a complete worked example, so you see the full field documentation and a test cycle before the exercises ask you to apply the same patterns independently.

The exercises are sequenced to build the operational workflow. Level 1 drills the dryrun→audit→fix→deny pipeline that you use when rolling out any new policy to a live cluster. Level 2 builds mutation resources from scratch. Level 3 is debugging broken policies where the symptom (mutation not applying, audit showing wrong numbers, constraint blocking system pods) requires reading status fields and logs rather than Rego logic. Level 4 is the full operational rollout scenario you would perform in production. Level 5 is the advanced case: mutation and validation policies interacting in ways that make pods inadmissible.

## Difficulty Progression

Level 1 and Level 2 build operational fluency: creating constraints in dryrun, reading violation counts from status fields, applying AssignMetadata and Assign mutations, and verifying that mutations took effect by inspecting the created pod. Level 3 introduces three distinct debugging scenarios that each require a different diagnostic approach: reading mutation status, reading constraint match configuration, and identifying namespace exclusion problems. Level 4 asks you to orchestrate a multi-step policy rollout end-to-end, including fixing existing violations before tightening enforcement. Level 5 is the most demanding: two policies interact such that mutation produces a resource the validator then blocks. Finding the conflict requires understanding the admission processing order and inspecting both the mutation outcome and the validator logic. Anti-spoiler conventions apply to Levels 3 and 5.

## Prerequisites

This assignment requires opa-gatekeeper/assignment-1 to be complete. All ConstraintTemplate and Constraint authoring skills from assignment-1 are used without re-explanation here. Gatekeeper must still be running in the cluster; if you cleaned up Gatekeeper after assignment-1, reinstall it following the tutorial instructions before starting. This assignment assumes you are comfortable with `kubectl describe constraint`, `kubectl get constraint -o yaml`, and reading Gatekeeper status fields.

## Cluster Requirements

This assignment uses the same single-node kind cluster as assignment-1. See the [single-node cluster setup section](../../../docs/cluster-setup.md#single-node-kind-cluster) in `docs/cluster-setup.md` for cluster creation. Gatekeeper must be installed; the tutorial's prerequisites section shows how to confirm it is running. Mutation features (AssignMetadata and Assign) require Gatekeeper 3.14 or later; in v3.17.1 mutation is enabled by default with no additional flags needed.

## Estimated Time Commitment

Level 1 exercises take 8-12 minutes each, mostly waiting for audit cycles. Level 2 takes 10-15 minutes each: authoring a mutation resource and verifying the injection via kubectl get -o yaml. Level 3 debugging exercises take 10-15 minutes each depending on how quickly you find the misconfiguration. Level 4 is 20-25 minutes per exercise for the full rollout workflow. Level 5 is the most intensive at 25-30 minutes per exercise because you must trace two policies simultaneously. Total estimated time including the tutorial walkthrough is 4-5 hours.

## Scope Boundary and What Comes Next

This assignment deliberately omits ConstraintTemplate authoring and Rego basics, which belong to assignment-1. It does not cover ValidatingAdmissionPolicy (CEL-based, covered in 16-admission-controllers/assignment-1) or image signing enforcement via Cosign (covered in 23-supply-chain-security/assignment-2). The network-level pod security controls (Calico NetworkPolicy, seccomp profiles managed by node configuration) are in their own assignments. After completing both OPA/Gatekeeper assignments, the natural next step is 19-troubleshooting, which uses multi-constraint setups as part of cross-domain capstone scenarios.

## Key Takeaways After Completing This Assignment

After completing this assignment, you should be able to deploy a constraint in dryrun mode, read its status.violations to identify non-compliant resources, fix those resources, and promote to deny mode without disrupting running workloads. You should be able to author an AssignMetadata resource to inject labels or annotations and an Assign resource to mutate spec fields, verify that mutations applied by inspecting a created pod's YAML, and diagnose why a mutation is not applying by checking the match criteria. You should understand how mutation ordering interacts with validation and be able to diagnose and resolve a mutation-validation conflict. You should also understand what the Gatekeeper Config resource's syncOnly field does and when it matters for audit.
