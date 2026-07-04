# Runtime Security Homework — Assignment 2: Audit Logging and Immutable Containers

Work through the tutorial (`runtime-security-tutorial.md`) before attempting these exercises. The tutorial enables audit logging on the kube-apiserver static pod and demonstrates audit policy structure, log analysis, and immutable container configuration. These exercises assume audit logging is already enabled and the audit log is writing to `/var/log/kubernetes/audit/audit.log` inside the kind control plane container.

---

## Level 1: Enabling Audit Logging and Verifying Events

Level 1 exercises focus on enabling audit logging with a minimal policy and confirming that specific API operations produce audit events.

### Exercise 1.1

**Objective:** Enable audit logging with a policy that logs all requests at the `Metadata` level. Verify that a `kubectl get secret` produces an audit event with the correct verb and resource fields.

**Setup:**

```bash
kubectl create namespace ex-1-1
kubectl create secret generic ex11-secret \
  --from-literal=password=hunter2 \
  -n ex-1-1
```

Create a minimal audit policy inside the control plane container:

```bash
nerdctl exec kind-control-plane mkdir -p /etc/kubernetes/audit/ex-1-1

nerdctl exec kind-control-plane sh -c 'cat > /etc/kubernetes/audit/ex-1-1-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
EOF'
```

**Task:** Update the kube-apiserver static pod manifest to use the policy file at `/etc/kubernetes/audit/ex-1-1-policy.yaml` and write audit logs to `/var/log/kubernetes/audit/ex-1-1.log`. Wait for the API server to restart. Then run `kubectl get secret ex11-secret -n ex-1-1` and verify that an audit event for that request appears in the log.

**Verification:**

```bash
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
echo "API server ready"

kubectl get secret ex11-secret -n ex-1-1

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"secrets\" and .objectRef.name == \"ex11-secret\") | \"\(.verb) \(.objectRef.name) \(.user.username) \(.responseStatus.code)\"" \
   /var/log/kubernetes/audit/ex-1-1.log'
# Expected: output line containing: get ex11-secret kubernetes-admin 200
```

---

### Exercise 1.2

**Objective:** Verify that a `watch` request from a system component produces an audit event under the minimal policy, and identify the user and verb in the event.

**Setup:** Audit logging must be enabled from Exercise 1.1. No additional resources needed.

**Task:** Run a brief watch against the secrets API from your workstation and then cancel it. Query the audit log to find the `watch` event and confirm the verb, user, and resource appear correctly.

**Verification:**

```bash
# Start a watch for 5 seconds, then cancel
kubectl get secrets -n ex-1-1 -w &
WATCH_PID=$!
sleep 5
kill $WATCH_PID 2>/dev/null || true

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.verb == \"watch\" and .objectRef.resource == \"secrets\" and .objectRef.namespace == \"ex-1-1\") | \"\(.verb) \(.objectRef.resource) \(.user.username) \(.responseStatus.code)\"" \
   /var/log/kubernetes/audit/ex-1-1.log' | head -3
# Expected: at least one line containing: watch secrets kubernetes-admin 200
```

---

### Exercise 1.3

**Objective:** Add a `None` level rule to suppress health check endpoint noise from the audit log and verify that health check events no longer appear after applying the policy change.

**Setup:** Audit logging must be enabled. No additional resources needed.

**Task:** Update the audit policy file to add a `None` level rule targeting the `nonResourceURLs` `/healthz`, `/readyz`, and `/livez` before the catch-all `Metadata` rule. Restart the API server by saving the updated manifest. After the restart, query the audit log to confirm no events for `/healthz` appear.

**Verification:**

```bash
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
echo "API server ready"

# Wait 30 seconds for background health checks to accumulate
sleep 30

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.requestURI == \"/healthz\") | .requestURI" \
   /var/log/kubernetes/audit/ex-1-1.log' | wc -l
# Expected: 0 (no /healthz events appear after the suppression rule was added)

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"secrets\" and .objectRef.namespace == \"ex-1-1\") | \"\(.verb) \(.objectRef.name)\"" \
   /var/log/kubernetes/audit/ex-1-1.log' | head -5
# Expected: lines still appear for secrets (only health checks are suppressed)
```

---

## Level 2: Writing Targeted Audit Policies

Level 2 exercises require writing multi-rule audit policies that capture specific security-relevant events while suppressing noise.

### Exercise 2.1

**Objective:** Write an audit policy that logs all Secret operations at `RequestResponse` level and all RBAC changes at `RequestResponse` level, and suppresses all other requests with `None`.

**Setup:**

```bash
kubectl create namespace ex-2-1
kubectl create secret generic ex21-creds \
  --from-literal=token=abc123 \
  -n ex-2-1
```

**Task:** Create and apply an audit policy with exactly three rules (in order):

1. `RequestResponse` for `secrets` in the core API group (all verbs, all namespaces).
2. `RequestResponse` for `roles`, `rolebindings`, `clusterroles`, `clusterrolebindings` in the `rbac.authorization.k8s.io` group.
3. `None` as a catch-all.

Apply the policy by updating the kube-apiserver manifest. After the API server restarts, create a Role in `ex-2-1`, create a RoleBinding, and get the secret. Verify that the secret get, role creation, and rolebinding creation all appear in the audit log, and that a `kubectl get pod` does not produce a log entry.

**Verification:**

```bash
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done

kubectl create role ex21-reader \
  --verb=get,list \
  --resource=configmaps \
  -n ex-2-1

kubectl create rolebinding ex21-rb \
  --role=ex21-reader \
  --serviceaccount=ex-2-1:default \
  -n ex-2-1

kubectl get secret ex21-creds -n ex-2-1

kubectl run silence-test -n ex-2-1 --image=busybox:1.36 --restart=Never -- sleep 1
kubectl get pods -n ex-2-1

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"secrets\" and .objectRef.name == \"ex21-creds\") | \"\(.verb) \(.objectRef.resource) \(.objectRef.name) \(.responseStatus.code)\"" \
   /var/log/kubernetes/audit/ex-2-1.log'
# Expected: get secrets ex21-creds 200

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"roles\" or .objectRef.resource == \"rolebindings\") | \"\(.verb) \(.objectRef.resource) \(.objectRef.name)\"" \
   /var/log/kubernetes/audit/ex-2-1.log'
# Expected: create roles ex21-reader and create rolebindings ex21-rb

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"pods\") | .objectRef.resource" \
   /var/log/kubernetes/audit/ex-2-1.log' | wc -l
# Expected: 0 (pods are suppressed by the catch-all None rule)
```

---

### Exercise 2.2

**Objective:** Write an audit policy that logs `pods/exec` at the `Request` level so that kubectl exec sessions are recorded.

**Setup:**

```bash
kubectl create namespace ex-2-2
kubectl run ex22-pod -n ex-2-2 \
  --image=busybox:1.36 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/ex22-pod -n ex-2-2 --timeout=60s
```

**Task:** Update the audit policy to add a `Request` level rule targeting the resource `pods/exec` in the core API group (empty group string). Apply the policy. After the API server restarts, exec into `ex22-pod` and run a command. Verify the exec request appears in the audit log with the correct resource subresource and verb.

**Verification:**

```bash
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done

kubectl exec ex22-pod -n ex-2-2 -- echo hello-audit

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.subresource == \"exec\" and .objectRef.namespace == \"ex-2-2\") | \"\(.verb) \(.objectRef.resource)/\(.objectRef.subresource) \(.objectRef.name) \(.user.username)\"" \
   /var/log/kubernetes/audit/ex-2-2.log'
# Expected: create pods/exec ex22-pod kubernetes-admin
```

---

### Exercise 2.3

**Objective:** Write a policy that logs anonymous authentication failures (requests from unauthenticated users) at `Metadata` level.

**Setup:** No additional resources needed. The kube-apiserver must be running with audit logging enabled.

**Task:** Add a rule to the audit policy that targets `users: ["system:anonymous"]` at `Metadata` level, before the catch-all rule. Apply the policy. After the API server restarts, trigger an anonymous request using curl against the API server from inside the control plane container:

```bash
nerdctl exec kind-control-plane sh -c \
  'curl -sk https://localhost:6443/api/v1/namespaces/default/secrets 2>&1 | head -5'
```

Verify the anonymous request appears in the audit log.

**Verification:**

```bash
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done

nerdctl exec kind-control-plane sh -c \
  'curl -sk https://localhost:6443/api/v1/namespaces/default/secrets 2>&1' || true

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.user.username == \"system:anonymous\") | \"\(.verb) \(.requestURI) \(.responseStatus.code)\"" \
   /var/log/kubernetes/audit/ex-2-3.log' | head -5
# Expected: get /api/v1/namespaces/default/secrets 403
```

---

## Level 3: Debugging Broken Audit Configurations

Each exercise in this level presents a broken audit logging setup. Diagnose the failure and fix it.

### Exercise 3.1

**Objective:** The audit policy below causes the kube-apiserver to fail to start. Find and fix the error.

**Setup:** Apply the following broken policy:

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
      - group: core
        resources: ["secrets"]
  - level: Metadata
EOF'
```

Update the `--audit-policy-file` flag in the kube-apiserver manifest to point to `/etc/kubernetes/audit/ex-3-1-policy.yaml` and restart. The API server will fail to start.

**Task:** The configuration above has one or more problems. Diagnose the failure by reading the kube-apiserver container logs. Fix the policy file and re-apply the manifest so the API server starts cleanly and a `kubectl get secret` produces a `RequestResponse` level audit event.

**Verification:**

```bash
kubectl get nodes
# Expected: node shows Ready

nerdctl exec kind-control-plane sh -c \
  'jq "select(.objectRef.resource == \"secrets\" and .level == \"RequestResponse\")" \
   /var/log/kubernetes/audit/ex-3-1.log | head -5'
# Expected: JSON event with level: RequestResponse for a secrets resource
```

---

### Exercise 3.2

**Objective:** Audit logging is enabled but pod exec events do not appear in the log even after execing into a pod. Find and fix the problem.

**Setup:**

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
        resources: ["pods/log"]
  - level: None
EOF'
```

Update the manifest to use this policy file (writing to `/var/log/kubernetes/audit/ex-3-2.log`) and restart.

```bash
kubectl create namespace ex-3-2
kubectl run ex32-debug -n ex-3-2 \
  --image=busybox:1.36 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/ex32-debug -n ex-3-2 --timeout=60s
```

**Task:** The configuration above has one or more problems. Exec into `ex32-debug` and run a command. Confirm that no exec event appears in the log. Diagnose the issue and fix the policy file so that `pods/exec` events are logged at `Request` level.

**Verification:**

```bash
kubectl exec ex32-debug -n ex-3-2 -- echo audit-check

nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.subresource == \"exec\") | \"\(.verb) \(.objectRef.subresource) \(.objectRef.namespace)\"" \
   /var/log/kubernetes/audit/ex-3-2.log' | head -5
# Expected: create exec ex-3-2
```

---

### Exercise 3.3

**Objective:** The audit log file is not being created even though the kube-apiserver starts cleanly. Find and fix the configuration issue.

**Setup:**

```bash
nerdctl exec kind-control-plane sh -c 'cat > /etc/kubernetes/audit/ex-3-3-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
EOF'
```

Apply the following (intentionally broken) kube-apiserver manifest change: update `--audit-log-path` to point to `/var/log/kubernetes/audit-reports/ex-3-3.log` without creating the directory or a corresponding `hostPath` volume mount. The API server will start (it creates its own log file if the directory exists) but the directory does not exist and the volume is not mounted.

**Task:** The configuration above has one or more problems. Diagnose why no log file is being created. Fix the manifest so that the audit log is written to `/var/log/kubernetes/audit/ex-3-3.log` with appropriate volume mounts and the directory exists inside the control plane container.

**Verification:**

```bash
kubectl get nodes
# Expected: Ready

kubectl get secret -n kube-system

nerdctl exec kind-control-plane ls /var/log/kubernetes/audit/ex-3-3.log
# Expected: file exists (ls exits 0)

nerdctl exec kind-control-plane sh -c \
  'jq -r ".verb" /var/log/kubernetes/audit/ex-3-3.log | head -5'
# Expected: verb strings such as list, get, watch
```

---

## Level 4: Production Audit Policy Scenario

### Exercise 4.1

**Objective:** Write and apply a complete production-style audit policy, perform a sequence of operations, and analyze the audit log to reconstruct the full event sequence.

**Setup:**

```bash
kubectl create namespace ex-4-1

kubectl create secret generic ex41-db-password \
  --from-literal=password=supersecret \
  -n ex-4-1

kubectl create serviceaccount ex41-reader -n ex-4-1

kubectl create role ex41-secret-reader \
  --verb=get,list \
  --resource=secrets \
  -n ex-4-1

kubectl create rolebinding ex41-reader-binding \
  --role=ex41-secret-reader \
  --serviceaccount=ex-4-1:ex41-reader \
  -n ex-4-1

kubectl run ex41-app -n ex-4-1 \
  --image=busybox:1.36 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/ex41-app -n ex-4-1 --timeout=60s
```

**Task:** Create and apply an audit policy at `/etc/kubernetes/audit/ex-4-1-policy.yaml` writing to `/var/log/kubernetes/audit/ex-4-1.log` with these rules (in order):

1. Suppress `/healthz`, `/readyz`, `/livez` with `None`.
2. Suppress `watch` from `system:kube-proxy` and `kubelet` with `None`.
3. Log all `secrets` operations at `RequestResponse`.
4. Log `pods/exec` at `Request`.
5. Log RBAC resources (`roles`, `rolebindings`, `clusterroles`, `clusterrolebindings` in `rbac.authorization.k8s.io`) at `RequestResponse`.
6. Log everything else at `Metadata`.

After applying, perform all of the following operations in order:

```bash
kubectl get secret ex41-db-password -n ex-4-1
kubectl exec ex41-app -n ex-4-1 -- cat /etc/hostname
kubectl create clusterrole ex41-viewer --verb=get --resource=pods
```

Then use `jq` to print a chronological summary of all events in `ex-4-1.log` using the format: `<stageTimestamp> <verb> <objectRef.resource>/<objectRef.name> by <user.username> -> <responseStatus.code>`. The summary must show at least three distinct events corresponding to the operations above.

**Verification:**

```bash
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done

kubectl get secret ex41-db-password -n ex-4-1
kubectl exec ex41-app -n ex-4-1 -- cat /etc/hostname
kubectl create clusterrole ex41-viewer --verb=get --resource=pods

nerdctl exec kind-control-plane sh -c \
  'jq -r "[.stageTimestamp, .verb, ((.objectRef.resource // "none") + "/" + (.objectRef.name // "none")), "by", .user.username, "->", (.responseStatus.code | tostring)] | join(" ")" \
   /var/log/kubernetes/audit/ex-4-1.log | grep -E "(ex41-db-password|exec|ex41-viewer)"'
# Expected: three lines corresponding to the secret get, the exec, and the clusterrole create
# Each line shows timestamp verb resource/name by user -> code

nerdctl exec kind-control-plane sh -c \
  'jq "select(.objectRef.name == \"ex41-db-password\" and .level == \"RequestResponse\")" \
   /var/log/kubernetes/audit/ex-4-1.log | jq ".responseObject.data" | head -5'
# Expected: JSON with base64-encoded "password" key (RequestResponse includes response body for secrets)
```

---

### Exercise 4.2

**Objective:** Deploy a pod with `readOnlyRootFilesystem: true` and verify that write attempts to non-mounted paths fail at the OS level while writes to explicitly mounted `emptyDir` paths succeed.

**Setup:**

```bash
kubectl create namespace ex-4-2
```

**Task:** Create a pod named `ex42-immutable` in namespace `ex-4-2` using the `nginx:1.27` image with `readOnlyRootFilesystem: true`. Mount three `emptyDir` volumes for the paths that nginx requires to write at runtime: `/var/cache/nginx`, `/var/run`, and `/tmp`. Verify the pod reaches `Running` status. Then verify that writing to `/etc/nginx/test.conf` fails and that writing to `/tmp/test.txt` succeeds.

**Verification:**

```bash
kubectl get pod ex42-immutable -n ex-4-2
# Expected: STATUS Running

kubectl exec ex42-immutable -n ex-4-2 -- \
  sh -c "echo test > /etc/nginx/test.conf" 2>&1
# Expected: Read-only file system error

kubectl exec ex42-immutable -n ex-4-2 -- \
  sh -c "echo success > /tmp/test.txt && cat /tmp/test.txt"
# Expected: success

kubectl get pod ex42-immutable -n ex-4-2 -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'
# Expected: true
```

---

### Exercise 4.3

**Objective:** Combine `readOnlyRootFilesystem` with a Falco write-detection rule so that any write to the container's root filesystem (outside of mounted volumes) triggers an alert.

**Setup:**

```bash
kubectl create namespace ex-4-3
```

**Task:** Create a pod named `ex43-monitored` in namespace `ex-4-3` using `alpine:3.20` with `readOnlyRootFilesystem: true` and a single `emptyDir` mount at `/tmp`. Add (or update) a Falco custom rule named `Unexpected Root Write` that fires when `evt.type = write`, `evt.dir = <`, `container.id != host`, `k8s.ns.name = "ex-4-3"`, and `not fd.directory startswith /tmp`. Apply the Falco rule via Helm upgrade. Verify that writing to `/tmp/ok.txt` does NOT trigger the alert, and that writing to `/etc/test.txt` (which will fail at the OS level with EACCES but the syscall still fires and Falco still sees it) triggers the `Unexpected Root Write` rule.

**Verification:**

```bash
kubectl rollout status daemonset/falco -n falco
kubectl wait --for=condition=Ready pod/ex43-monitored -n ex-4-3 --timeout=60s

kubectl exec ex43-monitored -n ex-4-3 -- sh -c "echo ok > /tmp/ok.txt"
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep "Unexpected Root Write" | grep "ex-4-3"
# Expected: no output (write to /tmp is permitted)

kubectl exec ex43-monitored -n ex-4-3 -- sh -c "echo bad > /etc/test.txt" 2>/dev/null || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep "Unexpected Root Write"
# Expected: at least one alert line for the /etc write attempt
```

---

## Level 5: Advanced Log Analysis

### Exercise 5.1

**Objective:** An audit log shows a pattern of repeated secret reads from an unexpected service account. Trace the access back to its source, identify all secrets that were read, and determine whether any RBAC bindings were created that explain the access.

**Setup:**

First, simulate the suspicious access pattern by creating a series of audit events:

```bash
kubectl create namespace ex-5-1

kubectl create secret generic ex51-api-key --from-literal=key=prod-key-abc -n ex-5-1
kubectl create secret generic ex51-db-pass --from-literal=pass=db-secret-xyz -n ex-5-1
kubectl create secret generic ex51-tls-cert --from-literal=cert=cert-data-here -n ex-5-1

kubectl create serviceaccount ex51-compromised -n ex-5-1

kubectl create clusterrole ex51-secret-lister \
  --verb=get,list \
  --resource=secrets

kubectl create clusterrolebinding ex51-compromise-binding \
  --clusterrole=ex51-secret-lister \
  --serviceaccount=ex-5-1:ex51-compromised

# Simulate the service account reading secrets (using impersonation)
kubectl get secret ex51-api-key -n ex-5-1 \
  --as=system:serviceaccount:ex-5-1:ex51-compromised
kubectl get secret ex51-db-pass -n ex-5-1 \
  --as=system:serviceaccount:ex-5-1:ex51-compromised
kubectl get secret ex51-tls-cert -n ex-5-1 \
  --as=system:serviceaccount:ex-5-1:ex51-compromised
kubectl list secrets -n ex-5-1 \
  --as=system:serviceaccount:ex-5-1:ex51-compromised 2>/dev/null || \
kubectl get secrets -n ex-5-1 \
  --as=system:serviceaccount:ex-5-1:ex51-compromised
```

**Task:** Query the audit log (writing to whatever log path your current policy uses) to answer these questions by constructing `jq` queries:

1. Which service account performed the secret reads? (Identify the `user.username` value.)
2. Which specific secrets were read by that service account? (List each `objectRef.name`.)
3. Was a ClusterRoleBinding created that granted this service account access? (Find create events for `clusterrolebindings` that reference `ex51-compromised`.)

Construct and run each query against the audit log. The queries must produce output that directly answers each question.

**Verification:**

```bash
# Query 1: identify the service account
nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"secrets\" and .objectRef.namespace == \"ex-5-1\" and .verb == \"get\") | .user.username" \
   /var/log/kubernetes/audit/ex-5-1.log | sort -u'
# Expected: system:serviceaccount:ex-5-1:ex51-compromised

# Query 2: which secrets were read
nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"secrets\" and .objectRef.namespace == \"ex-5-1\" and .verb == \"get\" and .user.username == \"system:serviceaccount:ex-5-1:ex51-compromised\") | .objectRef.name" \
   /var/log/kubernetes/audit/ex-5-1.log | sort -u'
# Expected: ex51-api-key, ex51-db-pass, ex51-tls-cert (one per line)

# Query 3: find the binding creation
nerdctl exec kind-control-plane sh -c \
  'jq -r "select(.objectRef.resource == \"clusterrolebindings\" and .verb == \"create\") | \"\(.objectRef.name) \(.stageTimestamp)\"" \
   /var/log/kubernetes/audit/ex-5-1.log'
# Expected: ex51-compromise-binding followed by timestamp
```

---

## Cleanup

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 \
  ex-2-1 ex-2-2 ex-2-3 \
  ex-3-1 ex-3-2 ex-3-3 \
  ex-4-1 ex-4-2 ex-4-3 \
  ex-5-1 2>/dev/null || true

kubectl delete clusterrole ex41-viewer ex51-secret-lister 2>/dev/null || true
kubectl delete clusterrolebinding ex51-compromise-binding 2>/dev/null || true
```

To disable audit logging and restore the original kube-apiserver manifest:

```bash
nerdctl exec kind-control-plane cp \
  /etc/kubernetes/kube-apiserver.yaml.bak \
  /etc/kubernetes/manifests/kube-apiserver.yaml
until kubectl get nodes 2>/dev/null | grep -q Ready; do sleep 5; done
```

## Key Takeaways

This assignment covered the complete audit logging workflow: writing a valid `audit.k8s.io/v1` Policy, enabling it on the kube-apiserver static pod by editing the manifest inside the kind control plane container, using `jq` to filter the newline-delimited JSON audit log for specific verbs, resources, users, and response codes, and correlating audit events to reconstruct an access sequence. The immutable container exercises demonstrated that `readOnlyRootFilesystem: true` with explicit `emptyDir` mounts is a production pattern that both hardens the container filesystem and sharpens the signal-to-noise ratio of Falco write-detection rules. The debugging exercises practiced the most common audit logging failures: wrong API group in the policy, missing subresource (`pods/exec` vs `pods`), and mount/directory issues that prevent the log file from being created.
