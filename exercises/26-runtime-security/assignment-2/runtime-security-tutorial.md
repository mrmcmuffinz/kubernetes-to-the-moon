# Runtime Security Tutorial: Audit Logging and Immutable Containers

## Introduction

Falco watches what happens inside running containers by hooking into the Linux kernel's system call layer. That visibility covers process execution, file access, and network connections from inside a container. What Falco cannot see is the Kubernetes control plane activity: who made API requests, what they accessed, and whether the API server accepted or rejected the request. Kubernetes audit logging fills that gap. Every request the API server receives, processes, and responds to can be recorded in a structured audit log, giving you a complete trail of control-plane activity that complements Falco's in-container view.

Together, audit logging and Falco provide two complementary layers of visibility. Audit logs tell you that a `get secret` request was made by a specific service account at a specific time with a specific response code. Falco tells you that a process inside a container opened a file path that corresponds to a mounted secret. Neither tool alone gives the complete picture; both together let you trace an incident from the API request through to the in-container behavior. This tutorial builds the audit logging half of that picture, then connects it to the immutable container pattern that makes Falco's write-detection rules more actionable.

For the CKS exam, you are expected to be able to enable audit logging by editing the kube-apiserver static pod manifest, write audit policies targeting specific resources and actions, and read audit log output to identify security-relevant events.

## Prerequisites

This tutorial uses a single-node kind cluster. Create one using [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster). You need `nerdctl` to exec into the kind control plane container, `jq` for log analysis (install with `sudo apt-get install -y jq` on Ubuntu if not present), and `kubectl`. Falco should still be installed from runtime-security/assignment-1; the immutable container section uses it. If you removed Falco, reinstall with `helm install falco falcosecurity/falco -n falco --create-namespace --set driver.kind=ebpf --version 4.7.2`.

## How Kubernetes Audit Logging Works

Every API request that reaches the kube-apiserver generates one or more audit events depending on your policy. An audit event records the request metadata (verb, resource, namespace, name), the identity making the request (user or service account), the request and response bodies (at higher logging levels), and the response status code. Events are written at specific stages of the request lifecycle:

| Stage | When it fires | Notes |
|---|---|---|
| `RequestReceived` | Immediately when the API server receives the request | Always emitted at the minimum policy level for a matching rule |
| `ResponseStarted` | After response headers are sent, before the body | Only for streaming responses (watch) |
| `ResponseComplete` | After the full response is sent | Most rules target this stage |
| `Panic` | If the API server panics handling the request | Rarely seen; useful for debugging API server bugs |

The audit policy controls which events are recorded and at what detail level. The level field per rule determines what information is captured:

| Level | What is recorded | Use case |
|---|---|---|
| `None` | Nothing | Suppress high-volume noise (health checks, watch from kubelet) |
| `Metadata` | Request metadata only (verb, resource, user, response code) | Most events; minimal storage cost |
| `Request` | Metadata plus the request body | For create/update operations where you need to see what was submitted |
| `RequestResponse` | Metadata, request body, and response body | For Secrets (you want to see the secret data on reads) and RBAC changes |

## Audit Policy Structure

An audit policy is a YAML file with a `rules` list. Rules are evaluated top-to-bottom; the first matching rule's level applies. If no rule matches, the event is recorded at the default level (which is `None` if no catch-all rule is present).

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  # First rule: suppress health check noise
  - level: None
    nonResourceURLs:
      - /healthz
      - /readyz
      - /livez

  # Second rule: suppress watch requests from system components
  - level: None
    users:
      - system:kube-proxy
      - kubelet
    verbs:
      - watch

  # Third rule: log all Secret access at RequestResponse level
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]

  # Catch-all: log everything else at Metadata level
  - level: Metadata
```

Key policy rule fields and their behavior when misconfigured:

| Field | What it does | When omitted | Failure mode if wrong |
|---|---|---|---|
| `level` | Logging detail level | Required | Policy load error |
| `verbs` | HTTP verbs to match (`get`, `list`, `watch`, `create`, `update`, `patch`, `delete`) | Match all verbs | A rule without verbs matches more than expected |
| `resources` | API group and resource list | Match all resources | Wrong `group` value causes rule to never match |
| `namespaces` | Scope rule to specific namespaces | Match all namespaces | Omitting means all namespaces, not just default |
| `users` | Match specific user names | Match all users | Wrong username means the rule never matches |
| `userGroups` | Match specific user groups | Match all groups | Useful for targeting service accounts in a group |
| `omitStages` | Skip logging at specific stages | Log at all stages | Can reduce log volume; `RequestReceived` is rarely needed |
| `nonResourceURLs` | Match non-resource URL paths (health checks) | Not matched | Only valid with `level: None` or very narrow policies |

The most common mistake is getting the `resources.group` field wrong. Core API resources (pods, secrets, services, configmaps, serviceaccounts) belong to the empty group (`group: ""`). RBAC resources (roles, rolebindings, clusterroles, clusterrolebindings) belong to `group: "rbac.authorization.k8s.io"`. CRDs belong to their specific group. Writing `group: "core"` is wrong; the empty string is the correct value for core resources.

## Enabling Audit Logging on the kube-apiserver Static Pod

The kube-apiserver in a kind cluster runs as a static pod managed by kubelet on the control plane node. Its manifest lives at `/etc/kubernetes/manifests/kube-apiserver.yaml` inside the kind control plane container. Editing this file causes kubelet to detect the change and restart the API server.

Enabling audit logging requires three changes to the static pod manifest:
1. Creating the audit policy file at a path inside the control plane container.
2. Mounting that path and the log output path into the kube-apiserver container.
3. Adding the `--audit-policy-file`, `--audit-log-path`, `--audit-log-maxage`, `--audit-log-maxbackup`, and `--audit-log-maxsize` flags to the kube-apiserver command.

### Step 1: Create the audit policy file

First, find the kind control plane container name:

```bash
nerdctl ps | grep control-plane
# Note the NAMES column, for example: kind-control-plane
```

Create the directory and policy file inside the control plane container:

```bash
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/audit

nerdctl exec kind-control-plane sh -c 'cat > /etc/kubernetes/audit/policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: None
    nonResourceURLs:
      - /healthz
      - /readyz
      - /livez
  - level: None
    users:
      - system:kube-proxy
    verbs:
      - watch
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]
  - level: Metadata
EOF'
```

Verify the file is in place:

```bash
nerdctl exec kind-control-plane cat /etc/kubernetes/audit/policy.yaml
```

### Step 2: Create the log directory

```bash
nerdctl exec kind-control-plane mkdir -p /var/log/kubernetes/audit
```

### Step 3: Edit the kube-apiserver static pod manifest

Take a backup of the manifest before editing:

```bash
nerdctl exec kind-control-plane cp \
  /etc/kubernetes/manifests/kube-apiserver.yaml \
  /etc/kubernetes/kube-apiserver.yaml.bak
```

Now edit the manifest. You will add flags to the `command` list and volumes/volumeMounts to the container spec. Use `nerdctl exec` with a heredoc to write the changes, or use `nerdctl exec -it kind-control-plane vi /etc/kubernetes/manifests/kube-apiserver.yaml` if your kind container has vi available.

The changes to add are:

**Under `spec.containers[0].command`, add these flags:**

```yaml
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-log-maxage=7
    - --audit-log-maxbackup=3
    - --audit-log-maxsize=100
```

**Under `spec.containers[0].volumeMounts`, add:**

```yaml
    - mountPath: /etc/kubernetes/audit
      name: audit-policy
      readOnly: true
    - mountPath: /var/log/kubernetes/audit
      name: audit-log
```

**Under `spec.volumes`, add:**

```yaml
  - hostPath:
      path: /etc/kubernetes/audit
      type: DirectoryOrCreate
    name: audit-policy
  - hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
    name: audit-log
```

To apply these changes in one step using a Python-based sed-like approach that does not require an interactive editor:

```bash
# This approach reads the existing manifest, applies the changes, and writes it back.
# Adjust the exact insertion points to match the current manifest structure.
nerdctl exec kind-control-plane sh -c '
python3 - <<PYEOF
import re

with open("/etc/kubernetes/manifests/kube-apiserver.yaml") as f:
    content = f.read()

# Add audit flags after the last existing -- flag line
audit_flags = """    - --audit-log-maxage=7
    - --audit-log-maxbackup=3
    - --audit-log-maxsize=100
    - --audit-log-path=/var/log/kubernetes/audit/audit.log
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml"""

# Find position after the last - -- line in command
content = re.sub(
    r"(    - --tls-private-key-file=.*)",
    r"\1\n" + audit_flags,
    content
)

# Add volumeMounts (insert before the last existing volumeMount entry or after livenessProbe)
audit_mounts = """    - mountPath: /etc/kubernetes/audit
      name: audit-policy
      readOnly: true
    - mountPath: /var/log/kubernetes/audit
      name: audit-log
"""
content = content.replace("  volumes:", audit_mounts + "  volumes:", 1)

# Add volumes
audit_vols = """  - hostPath:
      path: /etc/kubernetes/audit
      type: DirectoryOrCreate
    name: audit-policy
  - hostPath:
      path: /var/log/kubernetes/audit
      type: DirectoryOrCreate
    name: audit-log
"""
content = content.rstrip() + "\n" + audit_vols

with open("/etc/kubernetes/manifests/kube-apiserver.yaml", "w") as f:
    f.write(content)

print("Done")
PYEOF
'
```

Alternatively, if you prefer to make the edits manually with vi inside the container, the structure to aim for is clear from the steps above. The exact flag insertion point is after the last existing `--tls-*` flag, and the volume and volumeMount insertions follow the same pattern as the existing `etcd-certs` and `k8s-certs` entries in the manifest.

### Step 4: Verify the API server restarts

After writing the manifest, kubelet detects the change and restarts the API server. This takes 30 to 60 seconds. Watch for the API server to return:

```bash
kubectl get nodes
# May return: The connection to the server was refused (normal during restart)

# Wait for it to return
until kubectl get nodes 2>/dev/null | grep -q Ready; do
  echo "Waiting for API server..."
  sleep 5
done
echo "API server is back"
```

If the API server does not come back within 2 minutes, the manifest has a syntax error. Check the kube-apiserver container logs:

```bash
nerdctl exec kind-control-plane sh -c \
  'crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail -30'
```

A policy file parse error will appear in these logs as:

```text
E ... "error":"failed to load audit policy: ..."
```

In that case, check the policy file for YAML errors, fix it, and save the manifest again (kubelet will detect the change and retry).

### Step 5: Verify audit events appear

```bash
nerdctl exec kind-control-plane ls /var/log/kubernetes/audit/
# Expected: audit.log present

# Trigger a secret read
kubectl create secret generic tutorial-secret \
  --from-literal=key=value \
  -n default

kubectl get secret tutorial-secret -n default

# Check the audit log for the secret read
nerdctl exec kind-control-plane sh -c \
  'cat /var/log/kubernetes/audit/audit.log | \
   jq -r "select(.objectRef.resource == \"secrets\") | \"\(.verb) \(.objectRef.name) by \(.user.username)\""'
```

Expected output:

```text
create tutorial-secret by kubernetes-admin
get tutorial-secret by kubernetes-admin
```

If `jq` is not available in the control plane container:

```bash
nerdctl exec kind-control-plane sh -c \
  'which jq || (apt-get update -q && apt-get install -y jq)'
```

## Creating the Tutorial Namespace

```bash
kubectl create namespace tutorial-runtime-security
```

## Analyzing Audit Log Output

The audit log is a newline-delimited JSON file where each line is one audit event. The structure of each event:

```json
{
  "kind": "Event",
  "apiVersion": "audit.k8s.io/v1",
  "level": "RequestResponse",
  "auditID": "...",
  "stage": "ResponseComplete",
  "requestURI": "/api/v1/namespaces/default/secrets/tutorial-secret",
  "verb": "get",
  "user": {
    "username": "kubernetes-admin",
    "groups": ["system:masters", "system:authenticated"]
  },
  "sourceIPs": ["172.18.0.1"],
  "objectRef": {
    "resource": "secrets",
    "namespace": "default",
    "name": "tutorial-secret",
    "apiVersion": "v1"
  },
  "responseStatus": {
    "code": 200
  },
  "requestReceivedTimestamp": "...",
  "stageTimestamp": "..."
}
```

Useful `jq` filters for audit log analysis:

```bash
# All events for a specific resource
nerdctl exec kind-control-plane sh -c \
  'jq "select(.objectRef.resource == \"secrets\")" /var/log/kubernetes/audit/audit.log'

# All events by a specific user
nerdctl exec kind-control-plane sh -c \
  'jq "select(.user.username == \"kubernetes-admin\")" /var/log/kubernetes/audit/audit.log'

# Only failed requests (non-2xx response)
nerdctl exec kind-control-plane sh -c \
  'jq "select(.responseStatus.code >= 400)" /var/log/kubernetes/audit/audit.log'

# Pod exec events
nerdctl exec kind-control-plane sh -c \
  'jq "select(.requestURI | contains(\"exec\"))" /var/log/kubernetes/audit/audit.log'

# Compact one-line summary per event
nerdctl exec kind-control-plane sh -c \
  'jq -r "[.stageTimestamp, .verb, .objectRef.resource, .objectRef.name, .user.username, (.responseStatus.code | tostring)] | join(\" \")" \
   /var/log/kubernetes/audit/audit.log'
```

## Immutable Container Patterns

An immutable container is one whose filesystem cannot be written to at runtime. This is enforced with `readOnlyRootFilesystem: true` in the security context. When this is set, any attempt to write to the container's root filesystem results in a "Read-only file system" error. Legitimate writes (log files, temp files, caches) are redirected to explicitly declared `emptyDir` volume mounts.

Deploy a pod with a read-only root filesystem:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: immutable-app
  namespace: tutorial-runtime-security
spec:
  containers:
  - name: app
    image: nginx:1.27
    securityContext:
      readOnlyRootFilesystem: true
    volumeMounts:
    - name: cache-vol
      mountPath: /var/cache/nginx
    - name: run-vol
      mountPath: /var/run
    - name: tmp-vol
      mountPath: /tmp
  volumes:
  - name: cache-vol
    emptyDir: {}
  - name: run-vol
    emptyDir: {}
  - name: tmp-vol
    emptyDir: {}
EOF
```

Verify the pod is Running (nginx needs write access to `/var/cache/nginx`, `/var/run`, and `/tmp`):

```bash
kubectl get pod immutable-app -n tutorial-runtime-security
# Expected: Running
```

Verify that writes to non-mounted paths fail:

```bash
kubectl exec immutable-app -n tutorial-runtime-security -- \
  sh -c "echo test > /etc/nginx/test.conf" 2>&1
# Expected: sh: can't create /etc/nginx/test.conf: Read-only file system
```

Verify that writes to explicitly mounted paths succeed:

```bash
kubectl exec immutable-app -n tutorial-runtime-security -- \
  sh -c "echo test > /tmp/test.txt && cat /tmp/test.txt"
# Expected: test
```

The security benefit of `readOnlyRootFilesystem` is that Falco's write-detection rules become more precise. Without immutability, every container write is potentially noise (log rotation, temp files, package managers). With immutability, any write to the root filesystem is anomalous by definition, so a Falco write rule scoped to `container.id != host` has essentially zero false positives for containers running with `readOnlyRootFilesystem: true`.

## Correlating Audit Logs with Falco Alerts

A complete runtime security investigation uses both sources. Suppose you see a Falco alert:

```text
Warning Shell spawned in container
(pod=suspect-pod ns=production shell=bash)
```

You can correlate this with the audit log to find the `kubectl exec` request that spawned the shell:

```bash
nerdctl exec kind-control-plane sh -c \
  'jq "select(.requestURI | contains(\"exec\")) | 
   select(.objectRef.namespace == \"production\")" \
   /var/log/kubernetes/audit/audit.log | \
   jq -r "[.stageTimestamp, .verb, .objectRef.name, .user.username] | join(\" \")"'
```

This reveals which user or service account submitted the exec request, from which IP, at what time. The Falco alert shows what happened inside the container; the audit log shows who opened the door.

## Cleanup

```bash
kubectl delete namespace tutorial-runtime-security
kubectl delete secret tutorial-secret -n default 2>/dev/null || true
```

To disable audit logging after the assignment (reverting the kube-apiserver manifest):

```bash
nerdctl exec kind-control-plane cp \
  /etc/kubernetes/kube-apiserver.yaml.bak \
  /etc/kubernetes/manifests/kube-apiserver.yaml
```

Wait for the API server to restart, then verify it is back:

```bash
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
```

## Reference Commands

| Task | Command |
|---|---|
| Exec into control plane | `nerdctl exec -it kind-control-plane sh` |
| Create policy file | `nerdctl exec kind-control-plane sh -c 'cat > /etc/kubernetes/audit/policy.yaml <<EOF ...'` |
| Edit kube-apiserver manifest | `nerdctl exec -it kind-control-plane vi /etc/kubernetes/manifests/kube-apiserver.yaml` |
| Watch API server restart | `until kubectl get nodes 2>/dev/null \| grep -q Ready; do sleep 5; done` |
| Check API server crash log | `nerdctl exec kind-control-plane sh -c 'crictl logs $(crictl ps -a --name kube-apiserver -q \| head -1) 2>&1 \| tail -30'` |
| View audit log | `nerdctl exec kind-control-plane cat /var/log/kubernetes/audit/audit.log` |
| Stream audit log | `nerdctl exec kind-control-plane tail -f /var/log/kubernetes/audit/audit.log` |
| Filter by resource | `nerdctl exec kind-control-plane sh -c 'jq "select(.objectRef.resource == \"secrets\")" /var/log/kubernetes/audit/audit.log'` |
| Filter by user | `nerdctl exec kind-control-plane sh -c 'jq "select(.user.username == \"X\")" /var/log/kubernetes/audit/audit.log'` |
| Filter failed requests | `nerdctl exec kind-control-plane sh -c 'jq "select(.responseStatus.code >= 400)" /var/log/kubernetes/audit/audit.log'` |
| Install jq in control plane | `nerdctl exec kind-control-plane sh -c 'apt-get update -q && apt-get install -y jq'` |
