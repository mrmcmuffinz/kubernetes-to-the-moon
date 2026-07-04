# Cluster Hardening

**Topic area:** Cluster security and infrastructure hardening
**Certification relevance:** CKS (Cluster Setup 10%, Cluster Hardening 15%)
**Assignments in this topic:** 2

---

## Why Two Assignments

Cluster hardening spans two distinct problem spaces. The first is auditing and locking down the API server and control plane: running CIS benchmark tools, disabling anonymous authentication, restricting API access, and hardening API server flags. The second is hardening the surrounding infrastructure: restricting etcd access, tightening service account defaults, securing kubeconfig files, and blocking node metadata access. These two spaces have different tooling and different mental models (scanning and flagging vs. actively restricting), making two focused assignments more effective than one dense one.

---

## Assignment Summary

| Assignment | Focus | Prerequisites |
|---|---|---|
| assignment-1 | CIS benchmarks with kube-bench, API server hardening flags, disabling anonymous auth, restricting authorization modes | 12-rbac/assignment-1, 17-cluster-lifecycle/assignment-1 |
| assignment-2 | etcd access restriction, service account token controls, kubeconfig hardening, node metadata protection | cluster-hardening/assignment-1 |

---

## Assignment 1: API Server and Control Plane Hardening

Subtopics:
- *CIS Kubernetes Benchmark:* what kube-bench is, running it against a kind cluster, reading PASS/FAIL/WARN output, understanding which checks are remediable vs informational
- *Anonymous authentication:* --anonymous-auth=false on the API server, what anonymous access enables by default, verifying the flag takes effect
- *Authorization modes:* --authorization-mode, why AlwaysAllow is dangerous, RBAC+Node as the correct production mode, how to verify the current mode
- *API server admission plugins:* --enable-admission-plugins and --disable-admission-plugins, which plugins are security-relevant (NodeRestriction, PodSecurity, AlwaysPullImages)
- *Audit logging basics:* --audit-log-path, --audit-policy-file on the API server static pod manifest; covered at the flag level here, full audit policy authoring is in 26-runtime-security
- *Static pod manifest editing:* modifying /etc/kubernetes/manifests/kube-apiserver.yaml in a kind cluster, verifying the API server restarts cleanly, recovering from a bad edit

---

## Assignment 2: etcd, Service Accounts, and kubeconfig Hardening

Subtopics:
- *etcd access restriction:* etcd client certificates, restricting which components can connect, verifying etcd is not exposed without TLS
- *Service account token automounting:* automountServiceAccountToken: false at the pod and ServiceAccount level, when to disable it, verifying the default token is not mounted
- *Service account least privilege:* auditing default service accounts in kube-system, restricting permissions on the default service account
- *kubeconfig file permissions:* file mode for ~/.kube/config, restricting read access, the risk of world-readable kubeconfig files
- *RBAC audit:* kubectl auth can-i --list for a service account, identifying overly broad permissions
- *Node metadata protection:* blocking access to cloud provider instance metadata endpoints (169.254.169.254) via NetworkPolicy, why this matters for credential theft

---

## Scope Boundaries

**Not covered:**
- Full audit log policy authoring: deferred to 26-runtime-security
- Pod Security Standards enforcement: covered in 14-pod-security
- Network policies (general): covered in 10-network-policies
- TLS certificate management: covered in 18-tls-and-certificates
- System-level hardening (AppArmor, seccomp): covered in 28-system-hardening

---

## Cluster Requirements

Both assignments require a single-node kind cluster where the control plane node is accessible for editing static pod manifests. The kube-bench tool must be installed in the tutorial. Some API server flag changes require exec into the kind control plane container. The tutorial must document how to exec into the kind control plane node and edit /etc/kubernetes/manifests/kube-apiserver.yaml safely.

---

## Recommended Order

Assignment-1 before assignment-2. The API server hardening concepts in assignment-1 establish the mental model for control plane security that assignment-2 builds on.
