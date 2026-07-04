# Runtime Security Homework Answers — Assignment 2: Audit Logging and Immutable Containers

---

## Exercise 1.1 Solution

Create the policy and update the kube-apiserver manifest. The audit policy is already created in the setup block. The manifest changes needed are:

1. Add `--audit-policy-file=/etc/kubernetes/audit/ex-1-1-policy.yaml` to the command list.
2. Add `--audit-log-path=/var/log/kubernetes/audit/ex-1-1.log` to the command list.
3. Add `--audit-log-maxage=7`, `--audit-log-maxbackup=3`, `--audit-log-maxsize=100`.
4. Mount `/etc/kubernetes/audit` as a read-only `hostPath` volume named `audit-policy`.
5. Mount `/var/log/kubernetes/audit` as a `hostPath` volume named `audit-log`.
6. Add corresponding `volumeMounts` to the kube-apiserver container.

After the API server restarts:

```bash
kubectl get secret ex11-secret -n ex-1-1

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"secrets\" and .objectRef.name == \"ex11-secret\") | \"\(.verb) \(.objectRef.name) \(.user.username) \(.responseStatus.code)\"" \
   /var/log/kubernetes/audit/ex-1-1.log'
```

Expected: `get ex11-secret kubernetes-admin 200`. The `kubernetes-admin` user is the default kubeconfig user for a kind cluster. The response code `200` confirms the request was authorized and served successfully.

---

## Exercise 1.2 Solution

```bash
kubectl get secrets -n ex-1-1 -w &
WATCH_PID=$!
sleep 5
kill $WATCH_PID 2>/dev/null || true

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.verb == \"watch\" and .objectRef.resource == \"secrets\" and .objectRef.namespace == \"ex-1-1\") | \"\(.verb) \(.objectRef.resource) \(.user.username) \(.responseStatus.code)\"" \
   /var/log/kubernetes/audit/ex-1-1.log' | head -3
```

The watch event appears with `verb: watch`, `user.username: kubernetes-admin`, and a `200` response code. Watch requests appear at both `RequestReceived` and `ResponseStarted` stages because they are long-lived streaming responses. You may see two or more audit events for the single `kubectl get -w` command. The `stage: ResponseStarted` event confirms the server began sending the streaming response; the `stage: ResponseComplete` event (if present) confirms the watch was cancelled.

---

## Exercise 1.3 Solution

Update the policy file:

```bash
nerdctl exec kind-control-plane sh -c 'cat > /etc/kubernetes/audit/ex-1-1-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: None
    nonResourceURLs:
      - /healthz
      - /readyz
      - /livez
  - level: Metadata
EOF'
```

Touching the manifest file (or making any no-op edit) causes kubelet to re-read it and restart the API server:

```bash
nerdctl exec kind-control-plane sh -c \
  'stat /etc/kubernetes/manifests/kube-apiserver.yaml'
# Update modification time to trigger kubelet reload:
nerdctl exec kind-control-plane touch /etc/kubernetes/manifests/kube-apiserver.yaml
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
```

After 30 seconds, the `/healthz` event count is zero:

```bash
nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.requestURI == \"/healthz\") | .requestURI" \
   /var/log/kubernetes/audit/ex-1-1.log' | wc -l
```

The `None` level rule matching `nonResourceURLs` takes effect immediately after the API server loads the new policy. All health check events that were captured before the policy change remain in the log; the zero count refers only to events after the restart.

---

## Exercise 2.1 Solution

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  - level: None
```

The key detail is `group: ""` for core resources (secrets, pods, services, configmaps, serviceaccounts). Writing `group: "core"` or `group: "v1"` causes the rule to never match because those strings are not valid API group names. The correct empty string tells the policy engine to match the core API group, which has no name.

After applying, the pod events are completely absent from the log because the catch-all is `None`. Only the three explicitly targeted event categories appear.

---

## Exercise 2.2 Solution

The resource `pods/exec` is a subresource, not a top-level resource. In an audit policy, subresources are specified in the `resources` list:

```yaml
- level: Request
  resources:
    - group: ""
      resources: ["pods/exec"]
```

After applying this policy and execing into `ex22-pod`:

```bash
kubectl exec ex22-pod -n ex-2-2 -- echo hello-audit

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.subresource == \"exec\" and .objectRef.namespace == \"ex-2-2\") | \"\(.verb) \(.objectRef.resource)/\(.objectRef.subresource) \(.objectRef.name) \(.user.username)\"" \
   /var/log/kubernetes/audit/ex-2-2.log'
```

Expected: `create pods/exec ex22-pod kubernetes-admin`. The verb for an exec request is `create` (not `exec`), because from the API server's perspective the client is creating a new exec session as a subresource of the pod. The audit log shows `objectRef.resource: pods` and `objectRef.subresource: exec`, which is why the `jq` filter uses `.objectRef.subresource == "exec"` rather than searching the resource field.

---

## Exercise 2.3 Solution

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: None
    nonResourceURLs: [/healthz, /readyz, /livez]
  - level: Metadata
    users: ["system:anonymous"]
  - level: None
```

Place the anonymous user rule before the catch-all `None`. Because the policy is evaluated top-to-bottom and first-match wins, the anonymous user rule must come before any `None` catch-all, otherwise the `None` rule matches first and suppresses the anonymous event.

After the API server restarts:

```bash
nerdctl exec kind-control-plane sh -c \
  'curl -sk https://localhost:6443/api/v1/namespaces/default/secrets 2>&1' || true

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.user.username == \"system:anonymous\") | \"\(.verb) \(.requestURI) \(.responseStatus.code)\"" \
   /var/log/kubernetes/audit/ex-2-3.log' | head -5
```

Expected: `get /api/v1/namespaces/default/secrets 403`. The 403 confirms the anonymous request was rejected by the RBAC system. Audit logging captures all stages of the request lifecycle including rejected requests, which is why this log pattern is valuable: it reveals that an unauthenticated client probed the API server even though the request was denied.

---

## Exercise 3.1 Solution

### Diagnosis

After applying the broken policy and restarting:

```bash
kubectl get nodes
# Unable to connect -- API server is down

nerdctl exec kind-control-plane sh -c \
  'crictl logs $(crictl ps -a --name kube-apiserver -q | head -1) 2>&1 | tail -20'
```

Look for a line like:

```text
E ... failed to load audit policy file: failed to decode audit policy file
```

or:

```text
error: could not apply policy: unknown group "core"
```

The API server rejects the policy because `group: "core"` is not a valid API group name. In the Kubernetes API, the core group (pods, secrets, services, etc.) is identified by the empty string `""`, not by the string `"core"`. The audit policy engine validates resource group names against the API server's group registry, and `"core"` is not registered.

### Bug

`group: core` should be `group: ""` (empty string). The core API group has no name; it is identified by an empty string in all Kubernetes APIs.

### Fix

```bash
nerdctl exec kind-control-plane sh -c 'cat > /etc/kubernetes/audit/ex-3-1-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: None
    nonResourceURLs:
      - /healthz
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]
  - level: Metadata
EOF'
```

Touch the manifest to trigger a restart:

```bash
nerdctl exec kind-control-plane touch /etc/kubernetes/manifests/kube-apiserver.yaml
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
kubectl get secret -n ex-3-1
nerdctl exec kind-control-plane sh -c \
  'jq "select(.objectRef.resource == \"secrets\" and .level == \"RequestResponse\")" \
   /var/log/kubernetes/audit/ex-3-1.log | head -5'
```

---

## Exercise 3.2 Solution

### Diagnosis

Exec into the pod and check the audit log:

```bash
kubectl exec ex32-debug -n ex-3-2 -- echo audit-check

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.subresource == \"exec\")" \
   /var/log/kubernetes/audit/ex-3-2.log' | head -5
# No output
```

Inspect the policy:

```yaml
rules:
  - level: None
    nonResourceURLs: [/healthz, /readyz, /livez]
  - level: Request
    resources:
      - group: ""
        resources: ["pods/log"]
  - level: None
```

The policy targets `pods/log`, not `pods/exec`. The exec subresource is different from the log subresource. Because the only named resource is `pods/log`, exec requests fall through to the catch-all `None` rule and are suppressed.

### Bug

The resource in the `Request` level rule is `pods/log` when it should be `pods/exec`. These are different subresources and must be listed separately.

### Fix

```bash
nerdctl exec kind-control-plane sh -c 'cat > /etc/kubernetes/audit/ex-3-2-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: None
    nonResourceURLs: [/healthz, /readyz, /livez]
  - level: Request
    resources:
      - group: ""
        resources: ["pods/exec"]
  - level: None
EOF'

nerdctl exec kind-control-plane touch /etc/kubernetes/manifests/kube-apiserver.yaml
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
kubectl exec ex32-debug -n ex-3-2 -- echo audit-check
nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.subresource == \"exec\" and .objectRef.namespace == \"ex-3-2\") | \"\(.verb) \(.objectRef.subresource)\"" \
   /var/log/kubernetes/audit/ex-3-2.log'
```

---

## Exercise 3.3 Solution

### Diagnosis

The API server starts cleanly, but:

```bash
nerdctl exec kind-control-plane ls /var/log/kubernetes/audit-reports/ex-3-3.log
# ls: cannot access '/var/log/kubernetes/audit-reports/ex-3-3.log': No such file or directory
```

Two problems. First, the `--audit-log-path` flag points to a directory (`/var/log/kubernetes/audit-reports/`) that does not exist inside the control plane container and is not mounted as a volume. Second, no `hostPath` volume for the log directory is present in the manifest, so the kube-apiserver container cannot write to that path.

The API server starts without erroring on a missing log directory because the flag validation only checks that the flag is provided, not that the path is writable at startup. The first write attempt fails silently in some versions, or the log file is never created.

### Bug

The `--audit-log-path` points to a non-existent directory without a corresponding volume mount. The fix is to use the existing `/var/log/kubernetes/audit/` directory (which is already mounted from the tutorial setup) and update the flag accordingly.

### Fix

Update the kube-apiserver manifest to change:
- `--audit-log-path=/var/log/kubernetes/audit-reports/ex-3-3.log` to `--audit-log-path=/var/log/kubernetes/audit/ex-3-3.log`

No additional volume mounts are needed because `/var/log/kubernetes/audit` is already mounted from the prior exercises. If starting fresh:

```bash
nerdctl exec kind-control-plane mkdir -p /var/log/kubernetes/audit
```

And ensure the volume and volumeMount for `/var/log/kubernetes/audit` are present in the manifest:

```yaml
# volumeMount in the kube-apiserver container:
- mountPath: /var/log/kubernetes/audit
  name: audit-log

# volume in spec.volumes:
- hostPath:
    path: /var/log/kubernetes/audit
    type: DirectoryOrCreate
  name: audit-log
```

After fixing and restarting:

```bash
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
kubectl get secret -n kube-system
nerdctl exec kind-control-plane ls /var/log/kubernetes/audit/ex-3-3.log
# Expected: file present
```

---

## Exercise 4.1 Solution

The complete policy:

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: None
    nonResourceURLs: [/healthz, /readyz, /livez]
  - level: None
    users: [system:kube-proxy, kubelet]
    verbs: [watch]
  - level: RequestResponse
    resources:
      - group: ""
        resources: ["secrets"]
  - level: Request
    resources:
      - group: ""
        resources: ["pods/exec"]
  - level: RequestResponse
    resources:
      - group: "rbac.authorization.k8s.io"
        resources: ["roles", "rolebindings", "clusterroles", "clusterrolebindings"]
  - level: Metadata
```

The chronological summary query:

```bash
nerdctl exec kind-control-plane sh -c \
  'jq -r "[.stageTimestamp, .verb, ((.objectRef.resource // "none") + "/" + (.objectRef.name // "none")), "by", .user.username, "->", (.responseStatus.code | tostring)] | join(" ")" \
   /var/log/kubernetes/audit/ex-4-1.log | grep -E "(ex41-db-password|exec|ex41-viewer)"'
```

The output shows three distinct lines:
1. The `get secrets/ex41-db-password` request at `RequestResponse` level.
2. The `create pods/exec` request for the exec into `ex41-app`.
3. The `create clusterroles/ex41-viewer` request at `RequestResponse` level.

The response body for the secret get (available because of `RequestResponse` level) includes the base64-encoded secret data in `responseObject.data`. This is why the CKS exam requires logging secrets at `RequestResponse` level when monitoring for credential exfiltration: `Metadata` level would show that a secret was accessed, but only `RequestResponse` reveals what data was returned.

---

## Exercise 4.2 Solution

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: ex42-immutable
  namespace: ex-4-2
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
```

Apply:

```bash
kubectl apply -f - <<'EOF'
<paste the YAML above>
EOF
```

Verify:

```bash
kubectl exec ex42-immutable -n ex-4-2 -- \
  sh -c "echo test > /etc/nginx/test.conf" 2>&1
# Expected: Read-only file system

kubectl exec ex42-immutable -n ex-4-2 -- \
  sh -c "echo success > /tmp/test.txt && cat /tmp/test.txt"
# Expected: success
```

Nginx requires write access to `/var/cache/nginx` for caching, `/var/run` for the PID file, and `/tmp` for temporary files. Without those three `emptyDir` mounts, nginx would fail to start with a permissions error even though the root filesystem is read-only. The emptyDir volumes overlay specific subdirectories with writable tmpfs-backed storage, leaving the rest of the root filesystem read-only.

---

## Exercise 4.3 Solution

The Falco custom rule:

```yaml
customRules:
  ex_4_3_rules.yaml: |-
    - rule: Unexpected Root Write
      desc: A process attempted to write to the container root filesystem outside of /tmp
      condition: >
        evt.type = write and evt.dir = < and
        container.id != host and
        k8s.ns.name = "ex-4-3" and
        not fd.directory startswith /tmp
      output: >
        Write to root filesystem outside allowed mounts
        (proc=%proc.name file=%fd.name pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: WARNING
      tags: [container, filesystem, immutable]
```

Apply:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-4-3-rules.yaml \
  --version 4.7.2
kubectl rollout status daemonset/falco -n falco
```

The write to `/tmp/ok.txt` does not trigger the alert because `fd.directory startswith /tmp` evaluates to `true`, and the `not` negates to `false`, so the whole condition is `false`. The write to `/etc/test.txt` does trigger the alert because `/etc` does not start with `/tmp`, so the `not` evaluates to `true` and the condition fires. The OS returns `EACCES` or `EROFS` to the process (which is why the shell command exits with an error), but Falco hooks the syscall at the kernel level and evaluates the condition before the kernel's permission check result is returned, meaning the alert fires even on rejected writes.

---

## Exercise 5.1 Solution

The three `jq` queries:

**Query 1: Identify the service account:**

```bash
nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"secrets\" and .objectRef.namespace == \"ex-5-1\" and .verb == \"get\") | .user.username" \
   /var/log/kubernetes/audit/ex-5-1.log | sort -u'
```

Output: `system:serviceaccount:ex-5-1:ex51-compromised`. This format is the standard Kubernetes service account username: `system:serviceaccount:<namespace>:<name>`.

**Query 2: Which secrets were read:**

```bash
nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"secrets\" and .objectRef.namespace == \"ex-5-1\" and .verb == \"get\" and .user.username == \"system:serviceaccount:ex-5-1:ex51-compromised\") | .objectRef.name" \
   /var/log/kubernetes/audit/ex-5-1.log | sort -u'
```

Output: three lines, one per secret name (`ex51-api-key`, `ex51-db-pass`, `ex51-tls-cert`). The sort deduplicates because each secret read may produce multiple audit events (one per stage).

**Query 3: Find the binding creation:**

```bash
nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"clusterrolebindings\" and .verb == \"create\") | \"\(.objectRef.name) \(.stageTimestamp) by \(.user.username)\"" \
   /var/log/kubernetes/audit/ex-5-1.log'
```

Output: `ex51-compromise-binding <timestamp> by kubernetes-admin`. This reveals that `kubernetes-admin` (a human operator or CI system) created the ClusterRoleBinding that granted `ex51-compromised` access to all secrets cluster-wide. The audit trail shows both the RBAC configuration change that opened the access and the subsequent series of secret reads, enabling a complete incident timeline.

---

## Common Mistakes

**Using `group: "core"` instead of `group: ""` for core API resources.** The Kubernetes core API group (pods, secrets, services, configmaps, persistentvolumeclaims) has no name; it is identified by an empty string in all Kubernetes APIs including audit policy files. Writing `group: "core"` or `group: "v1"` causes the rule to never match, silently failing to log the events you intended to capture. This is the single most common audit policy authoring mistake.

**Targeting `pods` instead of `pods/exec` for exec event logging.** The `kubectl exec` command submits a `create` request to the `pods/exec` subresource, not to the `pods` resource itself. A rule targeting `resources: ["pods"]` captures pod creation, deletion, and update events, but it does not capture exec sessions. To log exec events, you must explicitly list `pods/exec` in the resources field. The verb in an exec audit event is `create`, which is counterintuitive but correct.

**Placing suppression rules after catch-all rules.** Audit policy rules are evaluated top-to-bottom and first-match wins. If you place a `level: Metadata` catch-all rule before your `level: None` suppression rules, every event matches the catch-all first and the suppression rules are never reached. Always place `None` level suppression rules at the top of the policy (or at least before any catch-all), with targeted logging rules in the middle and the catch-all at the end.

**Forgetting that `readOnlyRootFilesystem: true` requires explicit emptyDir mounts for any path the application needs to write to.** Most application images expect to write to at least one directory (`/tmp`, `/var/run`, a log directory). Without emptyDir mounts at those paths, the application fails to start with a permissions error. The set of required writable paths varies by image and must be determined from the image documentation or by running the container without the restriction first and observing which paths it writes to during startup.

**Not waiting for `kubectl rollout status daemonset/falco -n falco` after a Helm upgrade before triggering rules.** A Helm upgrade triggers a DaemonSet rollout. The old pod is terminated and a new pod starts. If you trigger a rule during the rollout, the old pod (with the old rules) may respond and the new rule will not be in effect. Always wait for the rollout to complete before running verification commands.

---

## Verification Commands Cheat Sheet

| Task | Command |
|---|---|
| Exec into control plane container | `nerdctl exec -it kind-control-plane sh` |
| Create audit policy file | `nerdctl exec kind-control-plane sh -c 'cat > /etc/kubernetes/audit/policy.yaml <<EOF ...'` |
| Trigger kubelet manifest reload | `nerdctl exec kind-control-plane touch /etc/kubernetes/manifests/kube-apiserver.yaml` |
| Wait for API server return | `until kubectl get nodes 2>/dev/null \| grep -q Ready; do sleep 5; done` |
| Read API server crash log | `nerdctl exec kind-control-plane sh -c 'crictl logs $(crictl ps -a --name kube-apiserver -q \| head -1) 2>&1 \| tail -30'` |
| Stream audit log | `nerdctl exec kind-control-plane tail -f /var/log/kubernetes/audit/audit.log` |
| All events for a resource | `jq 'select(.objectRef.resource == "secrets")'` |
| All events by a user | `jq 'select(.user.username == "X")'` |
| All failed requests | `jq 'select(.responseStatus.code >= 400)'` |
| All exec events | `jq 'select(.objectRef.subresource == "exec")'` |
| Chronological one-line summary | `jq -r '[.stageTimestamp, .verb, .objectRef.resource, .objectRef.name, .user.username, (.responseStatus.code \| tostring)] \| join(" ")'` |
| Filter by namespace | `jq 'select(.objectRef.namespace == "ex-4-1")'` |
| Unique users who accessed a resource | `jq -r 'select(.objectRef.resource == "secrets") \| .user.username' \| sort -u` |
| Verify readOnlyRootFilesystem | `kubectl get pod <pod> -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'` |
| Verify emptyDir mounts | `kubectl get pod <pod> -o jsonpath='{.spec.volumes}'` |
