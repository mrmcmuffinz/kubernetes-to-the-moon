# Assignment Prompt: Cluster Hardening — Assignment 1

**Series:** Cluster Hardening (1 of 2)
**Topic slug:** cluster-hardening
**Topic directory:** exercises/22-cluster-hardening/assignment-1/

## Metadata

**Domain:** CKS — Cluster Setup (10%), Cluster Hardening (15%)
**Competencies:** CIS benchmark scanning, API server hardening, authentication and authorization mode configuration
**Prerequisites:** 12-rbac/assignment-1, 17-cluster-lifecycle/assignment-1

## Scope — In Scope

*CIS Kubernetes Benchmark with kube-bench*
- What the CIS Kubernetes Benchmark is and why it matters
- Installing kube-bench (as a Job in the cluster or as a binary)
- Running kube-bench and reading PASS/FAIL/WARN output sections
- Understanding which checks apply to the API server, controller manager, scheduler, etcd, and worker nodes
- Remediating a FAIL finding by editing a static pod manifest flag

*API server hardening flags*
- --anonymous-auth=false: disabling anonymous access, verifying with curl -k https://apiserver:6443/api (should get 401 not 200)
- --authorization-mode: ensuring RBAC,Node is set, why AlwaysAllow is dangerous
- --enable-admission-plugins: NodeRestriction, PodSecurity, AlwaysPullImages — what each does
- --disable-admission-plugins: removing plugins that create security risk
- --insecure-port=0: ensuring the insecure HTTP port is disabled (default in modern Kubernetes but worth verifying)
- --profiling=false: disabling profiling endpoints to reduce information exposure
- --audit-log-path: confirming audit logging is enabled (full policy authoring deferred to 26-runtime-security)

*Editing static pod manifests*
- How to safely edit /etc/kubernetes/manifests/kube-apiserver.yaml in a kind cluster
- Exec into the kind control plane container: docker exec -it kind-control-plane bash (or nerdctl equivalent)
- Watching the API server restart after a manifest edit: kubectl get pods -n kube-system -w
- Recovering from a bad edit: restoring from backup

*Verifying hardening changes*
- kubectl get pods -n kube-system to confirm control plane pods are running after changes
- curl or kubectl --as=system:anonymous to verify anonymous auth is blocked
- kubectl auth can-i --list --as=system:anonymous to enumerate anonymous permissions

## Scope — Out of Scope

- Full audit log policy authoring: deferred to 26-runtime-security/assignment-2
- etcd access restriction and service account hardening: deferred to cluster-hardening/assignment-2
- Network policies for metadata protection: deferred to cluster-hardening/assignment-2
- Pod Security Standards: covered in 14-pod-security

## Environment

Single-node kind cluster. Exercises require exec into the kind control plane container to edit static pod manifests. The tutorial must show how to do this with nerdctl exec (not docker exec, since the environment uses nerdctl). kube-bench must be installed as part of the tutorial setup.

**Kind control plane exec pattern:**
```
nerdctl exec -it kind-control-plane bash
```

**Critical warning for the tutorial:** Editing kube-apiserver.yaml incorrectly will make the API server unreachable. Always take a backup before editing: `cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak`

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- All flag changes must be verified to take effect, not just applied. Include a verification step for every change.
- kube-bench output is verbose; the tutorial should show how to filter to just FAIL findings.
- Static pod manifest edits are the primary mechanism; do not suggest kubeadm config patches for this topic.
- The tutorial namespace is `tutorial-cluster-hardening`.

## Exercise Distribution

- Level 1: Read kube-bench output, identify a specific FAIL finding, describe what it means
- Level 2: Apply a specific API server flag change and verify it took effect
- Level 3 (debugging): Bare headings. Broken cluster configurations (anonymous auth accidentally enabled, wrong authorization mode, API server failing to start after bad flag)
- Level 4: Apply a set of CIS benchmark remediations to bring a cluster from multiple FAILs to PASS
- Level 5 (debugging): API server unreachable after a bad manifest edit; restore from backup and re-apply the correct change
