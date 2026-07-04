# Assignment Prompt: Runtime Security — Assignment 2

**Series:** Runtime Security (2 of 2)
**Topic slug:** runtime-security
**Topic directory:** exercises/26-runtime-security/assignment-2/

## Metadata

**Domain:** CKS — Monitoring, Logging and Runtime Security (20%)
**Competencies:** Kubernetes audit logging, audit policy authoring, log analysis, immutable container patterns
**Prerequisites:** runtime-security/assignment-1, 17-cluster-lifecycle/assignment-1, 22-cluster-hardening/assignment-1

## Scope — In Scope

*Kubernetes audit logging architecture*
- How the API server generates audit events: every API request produces an event at multiple stages
- Audit event stages: RequestReceived (always logged at lowest policy level), ResponseStarted (streaming responses), ResponseComplete (after response sent), Panic (unexpected errors)
- The two audit backends: log (write to a file on the API server node), webhook (POST to an external endpoint)
- Audit event JSON structure: stage, requestURI, verb, user.username, user.groups, objectRef (resource/namespace/name), responseStatus.code

*Audit policy structure*
- rules list: evaluated top-to-bottom, first match wins
- level field per rule: None (omit), Metadata (only metadata, no request/response body), Request (metadata + request body), RequestResponse (full request and response bodies)
- verbs list: get, list, watch, create, update, patch, delete, deletecollection
- resources list: {group, resources} targeting specific API groups and resource types
- namespaces list: scoping a rule to specific namespaces
- users and userGroups: targeting specific identities
- omitStages: which stages to skip for a rule

*Common audit policy patterns*
- Log all Secrets access at RequestResponse level (catch credential reads and writes)
- Log pod exec at Request level: resources: [{group: "", resources: ["pods/exec"]}]
- Log RBAC changes at RequestResponse: targeting roles, rolebindings, clusterroles, clusterrolebindings
- Suppress noise: None level for health check endpoints (/healthz, /readyz, /livez)
- Suppress noise: None level for watch requests from system components (kubelet, kube-proxy)
- Log all authentication failures: nonResourceURLs, anonymous user

*Enabling audit logging on the kube-apiserver static pod*
- Writing an audit policy file to a path on the kind control plane node
- Adding --audit-log-path, --audit-log-maxage, --audit-log-maxbackup, --audit-log-maxsize flags
- Adding --audit-policy-file pointing to the policy file
- Mounting the audit policy file and log directory as hostPath volumes in the static pod manifest
- Verifying the API server restarts and audit logs appear at the configured path

*Reading and analyzing audit logs*
- Tailing the audit log file: tail -f /var/log/kubernetes/audit.log inside the kind control plane container
- jq queries for filtering: jq 'select(.verb == "get" and .objectRef.resource == "secrets")' audit.log
- Identifying suspicious patterns: repeated failed authentication, unexpected secret reads, exec into privileged pods
- Correlating audit log events with Falco alerts for a complete threat picture

*Immutable container patterns*
- readOnlyRootFilesystem: true with specific writable emptyDir mounts (logs dir, temp dir, cache dir)
- Why immutability helps runtime security: legitimate writes are predictable, unexpected writes are anomalous
- Combining readOnlyRootFilesystem with Falco rules for write detection
- Audit log events for attempted writes to read-only filesystems: the API server does not see filesystem events, but Falco does; the two tools are complementary

## Scope — Out of Scope

- Falco rules and runtime syscall monitoring: covered in runtime-security/assignment-1
- API server flag basics (just --audit-log-path): covered at surface level in cluster-hardening/assignment-1; full policy authoring is here
- AppArmor and seccomp: covered in 28-system-hardening

## Environment

Single-node kind cluster. Audit logging requires editing the kube-apiserver static pod manifest, creating a policy file inside the kind control plane container, and mounting the log path. The tutorial must document all three steps. Log analysis exercises read audit log output from the mounted path.

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- All audit policy files must be valid YAML and the tutorial must verify the API server accepts them (starts cleanly).
- jq must be available in the kind control plane container for log analysis exercises; the tutorial must verify or install it.
- Tutorial namespace: `tutorial-runtime-security` (same topic slug as assignment-1).

## Exercise Distribution

- Level 1: Enable audit logging with a minimal policy (log everything at Metadata), verify an audit event appears after a kubectl get secret
- Level 2: Write an audit policy that logs Secret access at RequestResponse, suppresses health check noise, and logs RBAC changes; apply it
- Level 3 (debugging): Bare headings. Broken audit policy configurations (API server fails to start due to policy parse error, events not appearing due to wrong resource group, log file not writable due to mount issue)
- Level 4: Write a complete audit policy for a production scenario, enable it, perform a series of operations (read secret, exec into pod, create RBAC binding), then analyze the audit log to reconstruct the event sequence
- Level 5 (debugging): An audit log shows a suspicious pattern (repeated secret reads from an unexpected service account); trace back through the log to identify the source and the scope of potential compromise
