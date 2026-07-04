# Cluster Hardening Assignment 1: CIS Benchmark Scanning and API Server Hardening

This is the first of two Cluster Hardening assignments and covers the skills most directly tested when the CKA and CKS exams ask about securing the Kubernetes control plane. You will learn to run the CIS Kubernetes Benchmark using kube-bench, interpret its FAIL findings, and remediate those findings by editing the kube-apiserver static pod manifest. The assignment builds on RBAC concepts from 12-rbac/assignment-1 (particularly `kubectl auth can-i`) and on the static pod manifest mechanics introduced in 17-cluster-lifecycle/assignment-1. Assignment 2 continues from here, treating the API server as hardened and extending that work to etcd TLS verification, service account token controls, kubeconfig file security, and node metadata protection.

## Files

| File | Description |
|---|---|
| `README.md` | Assignment overview (this file) |
| `prompt.md` | Scope, constraints, and generator input |
| `cluster-hardening-tutorial.md` | Step-by-step tutorial: kube-bench scanning and API server flag hardening |
| `cluster-hardening-homework.md` | 15 progressive exercises across five difficulty levels |
| `cluster-hardening-homework-answers.md` | Complete solutions with explanations and a verification cheat sheet |

## Recommended Workflow

Read the tutorial file before attempting any exercises. The tutorial walks through a complete hardening session: downloading kube-bench into the kind control plane container, interpreting its FAIL output, backing up the API server manifest, adding hardening flags one at a time, and verifying each change took effect. That workflow becomes the muscle memory for everything in the homework. Because editing `/etc/kubernetes/manifests/kube-apiserver.yaml` carries real risk (a bad edit makes the API server unreachable and kills all `kubectl` access), the tutorial covers the recovery procedure in detail. Do not skip that section; Level 5 exercises require you to execute a recovery under time pressure.

## Difficulty Progression

Level 1 exercises build familiarity with the tooling: running kube-bench, reading its component-specific output, and verifying a single API server flag. Level 2 exercises move into active hardening, where each exercise changes one or two flags, waits for the API server to restart, and confirms the change is effective from outside the container. Level 3 presents broken configurations where the API server is either misconfigured in a dangerous way or has stopped starting entirely; your task is to read the symptoms, identify the cause from the manifest, and apply a targeted fix. Level 4 combines multiple flag changes into a realistic remediation workflow that mirrors what a CKA or CKS task actually asks for. Level 5 exercises are advanced debugging scenarios, including one where the API server becomes unreachable and must be recovered before any other work can proceed.

## Prerequisites

This assignment assumes familiarity with RBAC objects and the `kubectl auth can-i` command from 12-rbac/assignment-1. It also assumes you understand how static pod manifests work and how the kubelet detects and applies changes to files in `/etc/kubernetes/manifests/`, as covered in 17-cluster-lifecycle/assignment-1. You should be comfortable editing YAML files inside a running container with `vi`. See [docs/cluster-setup.md](../../../docs/cluster-setup.md) for cluster setup instructions.

## Cluster Requirements

This assignment uses a single-node kind cluster. See the [single-node kind cluster](../../../docs/cluster-setup.md#single-node-kind-cluster) section of the cluster setup document. No additional components are needed. kube-bench is downloaded and run as a binary inside the kind control plane container as part of the tutorial and exercises; no separate installation step is required before starting.

## Estimated Time Commitment

Level 1 exercises take 5 to 8 minutes each once you are comfortable with the backup-edit-verify loop. Level 2 exercises typically run 10 to 15 minutes each because each one includes waiting for the API server to restart and then verifying the change from outside the container. Level 3 debugging exercises range from 10 to 20 minutes depending on how quickly you isolate the failure mode. Level 4 exercises involve coordinating multiple flags in a single editing session with a full verification pass afterward; allow 20 to 30 minutes per exercise. Level 5 exercises are the most demanding at 25 to 40 minutes each; the API server recovery scenario is particularly challenging the first time through.

## Scope Boundary and What Comes Next

This assignment covers CIS benchmark scanning with kube-bench, API server flag hardening, and safe static pod manifest editing. It deliberately excludes etcd TLS configuration (covered in Assignment 2), service account token controls (Assignment 2), full audit log policy authoring (deferred to a later runtime security assignment), and Pod Security Standards (covered in 14-pod-security). If you want to understand how `--audit-log-path` works beyond confirming it is set, that full policy authoring treatment belongs to the runtime security topic. Assignment 2 picks up immediately where this one stops.

## Key Takeaways After Completing This Assignment

After finishing this assignment you should be able to run kube-bench against a kind cluster, filter its output to FAIL findings for a specific component, and map a control ID to the CIS benchmark remediation guidance. You should be able to safely edit the kube-apiserver.yaml static pod manifest using the backup-edit-verify-recover workflow, apply at least five security-relevant API server flags (`--anonymous-auth`, `--authorization-mode`, `--enable-admission-plugins`, `--profiling`, `--audit-log-path`), and verify each one took effect. You should also be able to recover a cluster where the API server failed to start after a bad manifest edit, a skill that the CKA exam tests directly in its cluster troubleshooting scenarios.
