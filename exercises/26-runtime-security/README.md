# Runtime Security

**Topic area:** Runtime threat detection and audit logging
**Certification relevance:** CKS (Monitoring, Logging and Runtime Security 20%)
**Assignments in this topic:** 2

---

## Why Two Assignments

Runtime security splits cleanly into two tools with different detection approaches. Falco watches system calls and Kubernetes API events in real time to detect threats as they happen. Kubernetes audit logging records all API server activity to a persistent log for forensics and compliance. Both are critical CKS skills, but they require different setup, different configuration languages (Falco rules vs audit policy YAML), and different analysis workflows. One assignment per tool keeps the focus sharp.

---

## Assignment Summary

| Assignment | Focus | Prerequisites |
|---|---|---|
| assignment-1 | Falco architecture, rules engine, custom rules, alert output channels, detecting runtime threats | 13-security-contexts/assignment-1, 01-pods/assignment-1 |
| assignment-2 | Kubernetes audit logging, audit policy authoring, log analysis, immutable container patterns | 17-cluster-lifecycle/assignment-1, cluster-hardening/assignment-1 |

---

## Assignment 1: Falco

Subtopics:
- *Falco architecture:* kernel module or eBPF probe for syscall capture, the rules engine, falco.yaml configuration, output channels (stdout, file, webhook, gRPC)
- *Rule structure:* rule, desc, condition, output, priority fields; macros and lists for reuse; the condition language (evt.type, proc.name, fd.name, container.id, k8s.pod.name)
- *Built-in rules:* reviewing the default ruleset, understanding what Terminal shell in container, Sensitive file opened for reading, and similar rules detect
- *Writing custom rules:* defining a macro, defining a list, writing a rule that triggers on a specific process name or file path in a container
- *Overriding and tuning rules:* appending to existing rules (append: true), disabling noisy rules (enabled: false), adjusting priority levels
- *Falco outputs:* reading alert output format, the output fields (time, priority, rule, container, pod), configuring file output for persistence
- *Triggering and observing alerts:* kubectl exec into a pod and run a shell, read /etc/shadow, write to a sensitive path; observe Falco alerts in real time

---

## Assignment 2: Kubernetes Audit Logging

Subtopics:
- *Audit logging architecture:* how the API server generates audit events, the audit event stages (RequestReceived, ResponseStarted, ResponseComplete, Panic), audit backends (log file, webhook)
- *Audit policy structure:* rules list with level (None, Metadata, Request, RequestResponse), verbs, resources, namespaces, users; policy evaluation order (first matching rule wins)
- *Common audit policy patterns:* log all secrets access at RequestResponse level, log pod exec at Request level, suppress health check noise (omit /healthz), log all changes to RBAC resources
- *Enabling audit logging on the API server:* --audit-log-path, --audit-log-maxage, --audit-log-maxbackup, --audit-log-maxsize flags on the kube-apiserver static pod manifest
- *Reading audit logs:* JSON log format, jq queries to filter by verb/resource/user, identifying suspicious patterns (unexpected secret reads, exec into privileged pods)
- *Immutable container patterns:* readOnlyRootFilesystem: true combined with specific writable emptyDir mounts, why immutability makes runtime threat detection more reliable (fewer legitimate write events)

---

## Scope Boundaries

**Not covered:**
- AppArmor and seccomp profiles: covered in 28-system-hardening
- Falco as a Gatekeeper integration: out of scope
- SIEM integration (Splunk, Elasticsearch): out of scope
- Cluster hardening audit logging flags at a surface level: introduced in 22-cluster-hardening/assignment-1; full policy authoring is here

---

## Cluster Requirements

Assignment-1 requires Falco installed in the kind cluster (as a DaemonSet using the eBPF probe, since kind nodes may not support kernel module loading). The tutorial must include Falco installation steps. Assignment-2 requires modifying the kube-apiserver static pod manifest to enable audit logging; the tutorial must document exec into the kind control plane container to edit /etc/kubernetes/manifests/kube-apiserver.yaml and mount the audit policy file.

---

## Recommended Order

Assignment-1 before assignment-2. Both can be used independently but Falco (real-time) complements audit logging (forensic) as a pair.
