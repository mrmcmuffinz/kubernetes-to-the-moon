# Cluster Hardening Assignment 2: etcd Security, Service Account Controls, and Metadata Protection

This is the second of two Cluster Hardening assignments. It picks up where Assignment 1 stopped, treating the API server as already hardened and extending that work to the remaining components of a secure cluster. The assignment covers four distinct hardening areas: verifying etcd's TLS authentication configuration, disabling unnecessary service account token automounting, securing kubeconfig file permissions, and blocking node metadata endpoint access with a NetworkPolicy egress rule. Together these controls address the cluster hardening domain competencies that the CKA and CKS exams test beyond the API server itself. Assignment 1 (CIS benchmark scanning and API server flags) is a direct prerequisite; you should also have the RBAC foundation from 12-rbac/assignment-1 and the NetworkPolicy basics from 10-network-policies.

## Files

| File | Description |
|---|---|
| `README.md` | Assignment overview (this file) |
| `prompt.md` | Scope, constraints, and generator input |
| `cluster-hardening-tutorial.md` | Step-by-step tutorial: etcd verification, SA token controls, kubeconfig security, metadata protection |
| `cluster-hardening-homework.md` | 15 progressive exercises across five difficulty levels |
| `cluster-hardening-homework-answers.md` | Complete solutions with explanations and a verification cheat sheet |

## Recommended Workflow

Read the tutorial before starting the exercises. The tutorial covers all four security areas in order, building from the simplest verification tasks (checking a file permission or a manifest flag) through the operational procedures that matter most (disabling token automounting, writing NetworkPolicy egress rules). The etcd section uses `etcdctl` via `kubectl exec` into the etcd pod; the tutorial shows the exact command pattern. The NetworkPolicy exercises in Levels 2 through 5 require a CNI that enforces NetworkPolicy rules; the tutorial references the appropriate cluster-setup.md section for installing Calico before starting those exercises.

## Difficulty Progression

Level 1 exercises are verification and configuration tasks: check an etcd flag, fix a file permission, create a ServiceAccount with the correct token setting. Level 2 introduces the four main operational skills: disabling automount at the ServiceAccount level, creating a metadata protection NetworkPolicy, and auditing service account RBAC permissions. Level 3 presents debugging scenarios where security controls were applied incorrectly and are now breaking normal cluster operation; your task is to find the overly restrictive configuration and fix it without removing the security control entirely. Level 4 combines all four hardening areas into a comprehensive namespace hardening workflow. Level 5 presents multi-issue debugging scenarios that mix over-privileged service accounts, misconfigured NetworkPolicies, and etcd configuration errors.

## Prerequisites

This assignment requires cluster-hardening/assignment-1 (API server hardening and the kube-apiserver.yaml editing workflow). It also assumes RBAC familiarity from 12-rbac/assignment-1 and NetworkPolicy conceptual knowledge from 10-network-policies. You should be comfortable with `kubectl auth can-i`, `kubectl exec`, and running commands inside the kind control plane container via `nerdctl exec`. See [docs/cluster-setup.md](../../../docs/cluster-setup.md) for cluster setup instructions.

## Cluster Requirements

Most exercises use a single-node kind cluster. NetworkPolicy exercises (Level 2 Exercise 2.2 and Level 3 Exercise 3.2 onward) require a CNI that enforces NetworkPolicy rules. The default kind CNI (kindnet) does not support NetworkPolicy. See the [multi-node with Calico NetworkPolicy support](../../../docs/cluster-setup.md#multi-node-with-calico-networkpolicy-support) section of the cluster setup document; a single-node Calico cluster can be created by adapting the same Calico install steps to a single-node kind config. The tutorial provides the exact steps. etcd exercises use `kubectl exec -n kube-system etcd-kind-control-plane -- etcdctl ...` and require no additional cluster components.

## Estimated Time Commitment

Level 1 exercises take 5 to 10 minutes each; they are primarily inspection and single-action tasks. Level 2 exercises run 10 to 15 minutes each, with the NetworkPolicy exercise on the longer end because it requires writing and testing the policy. Level 3 debugging exercises range from 15 to 25 minutes depending on how quickly you identify the overly restrictive rule that is breaking things. Level 4 exercises are comprehensive workflows; allow 25 to 35 minutes each. Level 5 multi-issue scenarios are the most demanding at 30 to 45 minutes each, particularly the scenario that combines SA misconfiguration with NetworkPolicy and etcd certificate issues.

## Scope Boundary and What Comes Next

This assignment covers etcd TLS verification, service account automount controls, kubeconfig file permissions, RBAC auditing for over-privileged accounts, and node metadata endpoint protection via NetworkPolicy. It deliberately excludes API server flag hardening (covered in Assignment 1), general NetworkPolicy constructs (covered in 10-network-policies), etcd backup and restore (covered in 17-cluster-lifecycle/assignment-3), and audit log policy authoring (deferred to a later runtime security assignment). The combination of Assignment 1 and Assignment 2 together covers the full cluster hardening domain as tested in CKA and CKS.

## Key Takeaways After Completing This Assignment

After finishing this assignment you should be able to inspect etcd's static pod manifest to verify that `--client-cert-auth=true` and `--peer-client-cert-auth=true` are set, run `etcdctl` against the kind cluster's etcd using the correct TLS flags, disable service account token automounting at both the ServiceAccount and Pod spec levels and verify the token is absent, set correct permissions on a kubeconfig file and explain the risk of a world-readable kubeconfig, write a NetworkPolicy egress rule that blocks access to the cloud metadata endpoint (169.254.169.254/32) while allowing legitimate cluster traffic, and audit service account RBAC permissions with `kubectl auth can-i --list` to find over-privileged bindings. These controls form the hardening baseline for any Kubernetes cluster intended for production use.
