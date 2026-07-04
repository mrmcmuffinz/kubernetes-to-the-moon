# Runtime Security — Assignment 2: Audit Logging and Immutable Containers

This is the second of two Runtime Security assignments. It focuses on Kubernetes audit logging and the immutable container pattern. You will enable audit logging on the kube-apiserver by editing its static pod manifest inside the kind control plane container, write audit policies that capture security-relevant events while suppressing noise, analyze audit log output with `jq` to reconstruct event sequences, and combine `readOnlyRootFilesystem` with Falco write-detection rules to build defense-in-depth. The first assignment in this series covers Falco architecture and runtime syscall monitoring.

## Files

| File | Description |
|---|---|
| `README.md` | This overview: prerequisites, workflow, scope, and time estimates |
| `prompt.md` | Generation input used to produce this assignment |
| `runtime-security-tutorial.md` | Step-by-step tutorial enabling audit logging and demonstrating immutable container patterns |
| `runtime-security-homework.md` | 15 progressive exercises across five difficulty levels |
| `runtime-security-homework-answers.md` | Complete solutions with diagnostic reasoning and a verification cheat sheet |

## Recommended Workflow

Work through the tutorial completely before attempting the homework. The tutorial covers the three steps required to enable audit logging: creating an audit policy file inside the kind control plane container, editing the kube-apiserver static pod manifest to add the required flags and mounts, and verifying that the API server restarts cleanly and audit events appear at the configured log path. These steps are not reversible without re-creating the cluster, so read the tutorial carefully before making changes. The exercises build on a working audit logging setup that the tutorial establishes.

## Difficulty Progression

Level 1 exercises ask you to enable audit logging with a minimal policy and verify that specific API requests produce audit events. Level 2 exercises require writing targeted audit policies that capture Secrets access, RBAC changes, and pod exec events while suppressing health check noise. Level 3 is debugging: broken audit policy configurations where the API server fails to start, events are missing due to wrong resource groups, or log files are not written because of a mount error. Level 4 builds a complete production-style audit policy, applies it, performs a sequence of operations, and requires you to reconstruct the event sequence from the log. Level 5 presents a simulated suspicious access pattern in an audit log and asks you to trace its source and scope.

## Prerequisites

This assignment requires completing runtime-security/assignment-1 for Falco familiarity (used in the immutable container section), cluster-lifecycle/assignment-1 for experience editing static pod manifests, and cluster-hardening/assignment-1 for background on the `--audit-log-path` flag. You must also be comfortable with `nerdctl exec` to run commands inside the kind control plane container and with `jq` for log analysis. See [docs/cluster-setup.md](../../../docs/cluster-setup.md) for cluster setup instructions.

## Cluster Requirements

This assignment uses a single-node kind cluster. Follow [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster). No additional cluster add-ons are required. Audit logging is configured by directly editing the kube-apiserver static pod manifest inside the kind control plane container, which the tutorial documents in detail.

## Estimated Time Commitment

Level 1 exercises take 10 to 15 minutes including the time to enable audit logging and verify event output. Level 2 exercises take 15 to 20 minutes to write and apply targeted policies. Level 3 debugging exercises take 15 to 25 minutes depending on how quickly you diagnose the API server failure or missing events. Level 4 is the most involved exercise in the set and takes 30 to 40 minutes to write a multi-rule policy, perform the required operations, and analyze the log. Level 5 takes 20 to 30 minutes to read the audit log carefully enough to trace an access pattern back to its source.

## Scope Boundary and What Comes Next

This assignment does not revisit Falco rule authoring, which is fully covered in runtime-security/assignment-1. AppArmor and seccomp profiles are in scope for 28-system-hardening. The `--audit-log-path` flag and basic API server configuration is touched on in cluster-hardening/assignment-1; this assignment goes further into policy structure and log analysis. Falco Sidekick and external log forwarding are out of scope for this course.

## Key Takeaways After Completing This Assignment

By the end of this assignment you should be able to write a valid Kubernetes audit policy with multiple rules targeting specific resources, verbs, users, and namespaces; enable audit logging on the kube-apiserver static pod in a kind cluster by editing the manifest and mounting the policy file and log directory; verify the API server restarts cleanly after manifest changes and audit events appear at the configured path; use `jq` to filter audit log JSON for specific verbs, resources, users, and response codes; correlate audit log events to reconstruct a sequence of operations by a specific identity; configure pods with `readOnlyRootFilesystem` and explain why immutability makes Falco write-detection rules more precise.
