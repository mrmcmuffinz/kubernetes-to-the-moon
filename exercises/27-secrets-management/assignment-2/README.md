# Secrets Management, Assignment 2: External Secrets Operator and Vault

This assignment is the second in the two-part Secrets Management series and addresses the limitations of storing secrets directly in Kubernetes: native Secrets live inside the cluster, require manual rotation coordination, and cannot draw from your organization's canonical secret stores such as HashiCorp Vault or cloud provider secret managers. The External Secrets Operator (ESO) bridges that gap by syncing secrets from external stores into Kubernetes Secrets automatically, with configurable refresh intervals that keep the in-cluster copy current as values rotate. This assignment teaches you to install and configure ESO, use the fake provider to work through all the configuration patterns without a real external system, integrate with a Vault dev-mode instance running as a pod in kind, and diagnose the most common ESO failures. It assumes you have completed secrets-management/assignment-1 and understand how Kubernetes Secrets are stored and protected at rest.

## Files

| File | Description |
|---|---|
| `README.md` | This file, assignment overview, prerequisites, workflow, and scope |
| `prompt.md` | The generation prompt used to produce this assignment |
| `secrets-management-tutorial.md` | Step-by-step tutorial covering ESO installation, fake provider usage, Vault integration, and rotation patterns |
| `secrets-management-homework.md` | 15 progressive exercises across five difficulty levels |
| `secrets-management-homework-answers.md` | Full solutions, debugging walkthroughs, common mistakes, and a command cheat sheet |

## Recommended Workflow

Work through the tutorial before attempting the exercises. The tutorial installs ESO on your kind cluster, builds a complete workflow using the fake provider (no external dependencies), and then integrates with a Vault dev-mode pod. The exercises assume ESO is already installed; the Level 1 exercise setup commands will fail if ESO's CRDs are not present. Install ESO once after reading the tutorial's prerequisites section and leave it running for all exercises. The Vault dev-mode pod is per-exercise where needed, and each exercise documents its own Vault setup.

## Difficulty Progression

Level 1 exercises establish the core three-object pattern, SecretStore, ExternalSecret, and the resulting Kubernetes Secret, using the fake provider, which gives you immediate feedback without needing a real external system. Level 2 exercises explore what happens when the external value changes: triggering re-syncs, observing the ExternalSecret status, and deploying a Vault dev-mode instance to store secrets. Level 3 exercises present broken ESO configurations; each has a bare heading and a symptom description, and your task is to read the ESO sync status, identify the root cause, and apply a fix. Level 4 exercises build the full Vault integration: installing Vault with Kubernetes auth, creating a SecretStore that authenticates with a service account JWT, and syncing secrets into pods. Level 5 exercises focus on the failure mode where an application is reading stale secret values because ESO has not re-synced; you must diagnose the sync status, identify the configuration gap, and fix the refresh behavior.

## Prerequisites

This assignment requires completion of secrets-management/assignment-1 (familiarity with Kubernetes Secrets, base64 encoding, and kubectl). RBAC concepts from 12-rbac/assignment-1 are used in Level 4 when configuring Vault Kubernetes auth; you should be comfortable with ServiceAccounts and RBAC policies. Helm must be available for ESO installation. The kind cluster setup is documented at [docs/cluster-setup.md](../../../docs/cluster-setup.md).

## Cluster Requirements

This assignment requires a single-node kind cluster. ESO is installed via Helm and runs as a Deployment in its own namespace. Vault dev-mode runs as a Pod in the exercise namespace for exercises that require it. No MetalLB, Calico, or Gateway API components are needed. See [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster) for the cluster creation command. ESO should be installed once at the start using the Helm installation documented in the tutorial, and left running for all exercises.

## Estimated Time Commitment

Level 1 exercises take five to ten minutes each once ESO is installed; they are straightforward create-and-verify tasks. Level 2 exercises take ten to fifteen minutes each; the Vault exercises involve deploying the pod, storing secrets, and verifying CLI access before moving on to the ESO integration. Level 3 debugging exercises take eight to fifteen minutes each; the key skill is reading the ExternalSecret status conditions and ESO controller logs to identify the root cause rather than guessing. Level 4 exercises take fifteen to twenty minutes each and require careful sequencing: Vault must be ready and the Kubernetes auth method configured before the SecretStore will authenticate successfully. Level 5 exercises take ten to twenty minutes; they start with a deliberate misconfiguration and require you to correlate ExternalSecret status with the actual Kubernetes Secret state to understand the gap.

## Scope Boundary and What Comes Next

This assignment covers the External Secrets Operator with the fake provider and HashiCorp Vault dev mode, plus the ESO-based secret rotation patterns. It does not cover etcd encryption at rest (secrets-management/assignment-1), AWS Secrets Manager or GCP Secret Manager as ESO providers (the ESO docs cover those once you understand the provider model from this assignment), the CSI secrets driver, or Vault production setup (HA storage backends, Raft clustering, seal configuration). The troubleshooting series (19-troubleshooting) extends the debugging skills practiced in Level 3 and Level 5 to cross-domain cluster failures.

## Key Takeaways After Completing This Assignment

After completing this assignment you should be able to install the External Secrets Operator using Helm, create a SecretStore and ExternalSecret using the fake provider, and verify that ESO creates and maintains the target Kubernetes Secret. You should understand the difference between SecretStore (namespace-scoped) and ClusterSecretStore (cluster-scoped), when to use each, and how ExternalSecret's secretStoreRef must match. You should be able to trigger an immediate re-sync using the force-sync annotation, read the ExternalSecret status conditions to diagnose sync failures, and fix the three most common failures (non-existent key reference, wrong kind reference, and wrong creationPolicy). You should be able to deploy a Vault dev-mode pod in kind, store and retrieve KV secrets using the vault CLI, and create an ESO SecretStore that authenticates to Vault using a token Secret. Finally, you should understand the refreshInterval field and the operational consequence of setting it too long when external values rotate.
