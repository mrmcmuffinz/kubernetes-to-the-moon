# Runtime Sandboxing

**Topic area:** Container runtime isolation
**Certification relevance:** CKS (Minimize Microservice Vulnerabilities 20%)
**Assignments in this topic:** 1

---

## Why One Assignment

Runtime sandboxing is a focused topic with a single central concept: the RuntimeClass resource and its two main implementations (gVisor and kata containers). The subtopics — installing a sandbox runtime, creating a RuntimeClass, assigning it to pods, verifying isolation, and understanding the trade-offs — fit comfortably within a single 15-exercise assignment without needing to thin the content. Both gVisor and kata containers should appear in the same assignment since their Kubernetes integration pattern is identical; the difference is in the underlying isolation mechanism, which is a comparison exercise rather than a separate topic.

---

## Assignment Summary

| Assignment | Focus | Prerequisites |
|---|---|---|
| assignment-1 | RuntimeClass resource, gVisor (runsc) installation and use, kata containers comparison, isolation verification, performance trade-offs | 01-pods/assignment-1, 13-security-contexts/assignment-1 |

---

## Assignment 1: RuntimeClass and Sandbox Runtimes

Subtopics:
- *RuntimeClass resource:* spec.handler field, how the Kubernetes scheduler uses RuntimeClass to select the correct runtime on a node, RuntimeClass scheduling with nodeSelector via scheduling.nodeClassSelector
- *gVisor (runsc):* what gVisor is (user-space kernel intercepting syscalls), installing runsc and configuring containerd to use it as a runtime handler, creating a RuntimeClass pointing to the runsc handler
- *Assigning RuntimeClass to pods:* spec.runtimeClassName field, verifying the pod runs under the sandbox runtime with kubectl exec and /proc inspection
- *Verifying sandbox isolation:* running a pod with and without RuntimeClass and comparing syscall visibility, using dmesg or uname -r to confirm the gVisor kernel
- *Kata containers:* conceptual comparison with gVisor (VM-based isolation vs syscall interception), kata-runtime as a containerd handler, RuntimeClass for kata
- *Trade-offs:* performance overhead of sandbox runtimes, startup latency, workload compatibility (some syscalls not supported by gVisor), when to use a sandbox vs security contexts vs seccomp

---

## Scope Boundaries

**Not covered:**
- seccomp profiles: covered in 28-system-hardening
- AppArmor profiles: covered in 28-system-hardening
- Pod security contexts: covered in 13-security-contexts
- OPA/Gatekeeper policy to enforce RuntimeClass usage: covered in 25-opa-gatekeeper

---

## Cluster Requirements

Single-node kind cluster with gVisor installed on the node. The tutorial must document installing runsc on the kind node container (exec into the kind control plane container, install runsc, configure containerd). Kata containers are covered conceptually and with a RuntimeClass definition; a working kata installation in kind is not required given the nested virtualization constraints of most development environments. If kata cannot be demonstrated live, the tutorial should clearly note this and focus live exercises on gVisor.

---

## Recommended Order

This is a standalone single assignment. Complete 13-security-contexts before this topic for context on pod-level security controls that complement runtime sandboxing.
