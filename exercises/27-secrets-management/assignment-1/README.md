# Secrets Management, Assignment 1: etcd Encryption at Rest

This assignment is the first in the two-part Secrets Management series and addresses the most commonly overlooked storage security gap in Kubernetes clusters. By default, Kubernetes Secrets are stored in etcd as base64-encoded data, which means anyone who gains direct access to etcd, through a compromised node, a stolen backup file, or a misconfigured etcd endpoint, can read every Secret in the cluster without any Kubernetes RBAC check at all. This assignment teaches you to demonstrate that plaintext exposure using etcdctl, configure EncryptionConfiguration to store new Secrets as ciphertext, verify the change, and perform a key rotation to protect existing Secrets. The second assignment in the series extends this foundation to external secret stores, introducing the External Secrets Operator and HashiCorp Vault.

## Files

| File | Description |
|---|---|
| `README.md` | This file, assignment overview, prerequisites, workflow, and scope |
| `prompt.md` | The generation prompt used to produce this assignment |
| `secrets-management-tutorial.md` | Step-by-step tutorial covering etcd inspection, EncryptionConfiguration, key rotation, and Secret exposure patterns |
| `secrets-management-homework.md` | 15 progressive exercises across five difficulty levels |
| `secrets-management-homework-answers.md` | Full solutions, debugging walkthroughs, common mistakes, and a command cheat sheet |

## Recommended Workflow

Work through the tutorial completely before attempting the exercises. The tutorial is structured to show the security problem first, reading a Secret directly from etcd, so that when you configure EncryptionConfiguration, you understand what you are actually protecting against and how to verify the fix works. After finishing the tutorial, clean up the tutorial namespace and restore the kube-apiserver manifest to its original state before starting the exercises, since several exercises require you to make the same configuration changes independently. Each exercise documents its own setup, so exercises are self-contained once the cluster is in a clean starting state.

## Difficulty Progression

Level 1 exercises build fluency with etcdctl and the two ways to expose a Secret to a running pod, reinforcing the core insight that base64 is encoding rather than encryption by having you inspect what etcd actually stores. Level 2 exercises step through enabling EncryptionConfiguration, comparing the etcd representation of a Secret written before and after encryption is enabled, and configuring safer pod exposure patterns such as volume mounts and projected volumes. Level 3 presents broken encryption configurations with bare headings and no hints; your job is to identify the symptom from error output, locate the root cause in the configuration, and produce a corrected result. Level 4 covers the complete key rotation workflow, a multi-step coordinated procedure that must be done in a specific order to avoid losing access to existing Secrets. Level 5 places you in the role of a security auditor who discovers that encryption is nominally enabled but some Secrets in etcd remain in plaintext; you must diagnose the cause, enumerate the affected Secrets, and remediate the gap.

## Prerequisites

This assignment assumes you have completed 17-cluster-lifecycle/assignment-3 and are comfortable editing static pod manifests, reasoning about kube-apiserver startup flags, and understanding how the kubelet manages static pods. Familiarity with Secret creation and pod mounting patterns from 01-pods/assignment-2 is also assumed. You should be comfortable running kubectl exec, encoding values with base64, and editing YAML files on the kind control plane node. The kind cluster setup is documented at [docs/cluster-setup.md](../../../docs/cluster-setup.md).

## Cluster Requirements

This assignment requires a single-node kind cluster. No additional components are needed beyond the base cluster; etcdctl is invoked through kubectl exec into the etcd pod, which already has etcdctl available and has the required certificates mounted at the standard paths. Editing the kube-apiserver manifest requires exec access to the kind-control-plane container via nerdctl. See [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster) for the cluster creation command. All nerdctl exec and nerdctl cp commands used in this assignment are fully documented in the tutorial and in each exercise's setup section.

## Estimated Time Commitment

Level 1 exercises take approximately five to eight minutes each; they involve straightforward kubectl commands and etcdctl reads with no manifest editing. Level 2 exercises take ten to fifteen minutes each because they require writing the EncryptionConfiguration to the kind node, editing the kube-apiserver manifest, and waiting for the API server to restart cleanly before verifying. Level 3 debugging exercises take eight to twelve minutes each; the challenge is reading kubectl and kubelet output to diagnose why the API server fails to start or why certain Secret reads fail, rather than recalling correct syntax. Level 4 exercises take fifteen to twenty minutes each due to the multi-step key rotation sequence. Level 5 exercises take fifteen to twenty-five minutes; the diagnosis phase requires correlating etcdctl output with kubectl output across multiple Secrets in multiple namespaces before beginning remediation.

## Scope Boundary and What Comes Next

This assignment covers encryption of Secrets at rest in etcd and the patterns for exposing Secrets to running pods. It does not cover external secret stores, the External Secrets Operator, syncing from AWS Secrets Manager or HashiCorp Vault, or the CSI secrets driver, all of those are covered in secrets-management/assignment-2. etcd backup and restore operations are covered in 17-cluster-lifecycle/assignment-3. RBAC controls restricting which principals can read Secrets via the Kubernetes API are covered in 12-rbac. The encryption knowledge from this assignment is assumed context for assignment-2, so you understand why external secrets management is valuable even when etcd encryption is already in place.

## Key Takeaways After Completing This Assignment

After completing this assignment you should be able to read a Kubernetes Secret directly from etcd using etcdctl and confirm that unencrypted Secrets are stored as base64-encoded plaintext with no additional protection. You should be able to write a valid EncryptionConfiguration file using the aescbc provider, correctly generate a 32-byte key, write the configuration to the kind control plane node, and add the required flag, volume mount, and volume to the kube-apiserver static pod manifest. You should understand the provider ordering rule, the first provider is used for writes, all providers are tried in order for reads, and the consequence of omitting the identity provider when pre-existing plaintext Secrets are present. You should be able to perform a key rotation end-to-end: add a new key as the first provider, re-encrypt all Secrets with kubectl replace, verify the new ciphertext prefix in etcd, and remove the old key only after confirming re-encryption is complete. Finally, you should be able to explain why volume-mounted Secrets are preferred over environment variable exposure and configure automountServiceAccountToken: false on a pod to limit service account token exposure.
