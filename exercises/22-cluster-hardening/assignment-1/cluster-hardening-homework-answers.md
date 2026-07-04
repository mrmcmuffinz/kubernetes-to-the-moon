# Cluster Hardening Assignment 1 Homework Answers

---

## Exercise 1.1 Solution

Download kube-bench and save the apiserver FAIL findings.

```bash
nerdctl exec kind-control-plane bash -c "
  curl -sSL \
    https://github.com/aquasecurity/kube-bench/releases/download/v0.8.0/kube-bench_0.8.0_linux_amd64.tar.gz \
    -o /tmp/kube-bench.tar.gz
  tar xzf /tmp/kube-bench.tar.gz -C /tmp kube-bench
  chmod +x /tmp/kube-bench
  /tmp/kube-bench run --targets master 2>/dev/null \
    | grep '^\[FAIL\]' | grep '1\.2\.' > /tmp/apiserver-fails.txt
  cat /tmp/apiserver-fails.txt
"
```

Verification:

```bash
nerdctl exec kind-control-plane test -s /tmp/apiserver-fails.txt && echo "file-exists"
# Expected: file-exists

nerdctl exec kind-control-plane bash -c "grep '1\.2\.1' /tmp/apiserver-fails.txt"
# Expected: [FAIL] 1.2.1 Ensure that the --anonymous-auth argument is set to false (Automated)
```

The file will typically contain 3 to 6 FAIL lines depending on the cluster's current configuration. Any line that starts with `[FAIL] 1.2.` represents an API server control that needs remediation.

---

## Exercise 1.2 Solution

Add `--profiling=false` to the API server manifest:

```bash
nerdctl exec -it kind-control-plane bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add the line: - --profiling=false
# Position it after the - kube-apiserver line in the command list
exit
```

Wait for the restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
# Wait until Running, then Ctrl+C
```

Verify:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false
```

---

## Exercise 1.3 Solution

Check the authorization mode:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --authorization-mode=Node,RBAC
```

If the value already shows `Node,RBAC`, no edit is needed. If it is missing or wrong, edit the manifest:

```bash
nerdctl exec -it kind-control-plane bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Set: - --authorization-mode=Node,RBAC
exit
```

Verify RBAC enforcement:

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-1-3:audit-check \
  -n ex-1-3
# expect: no
```

The service account has no RoleBinding, so RBAC denies all requests from it. If the authorization mode were `AlwaysAllow`, this would return `yes`, which would indicate a broken state.

---

## Exercise 2.1 Solution

Back up and edit the manifest:

```bash
nerdctl exec -it kind-control-plane bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add: - --anonymous-auth=false
exit
```

Wait for the restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Verify:

```bash
kubectl --as=system:anonymous auth can-i get pods -n ex-2-1
# expect: no

kubectl --as=system:anonymous auth can-i list namespaces
# expect: no
```

---

## Exercise 2.2 Solution

Inspect the current value:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml"
```

Edit the manifest:

```bash
nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Change or add: - --enable-admission-plugins=NodeRestriction,AlwaysPullImages
exit
```

Wait for the restart, then verify:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c \
  "grep enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --enable-admission-plugins=NodeRestriction,AlwaysPullImages
```

---

## Exercise 2.3 Solution

Create the log directory and edit the manifest:

```bash
nerdctl exec kind-control-plane bash -c "mkdir -p /var/log/kubernetes"

nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add: - --audit-log-path=/var/log/kubernetes/audit.log
exit
```

Wait for the restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Generate an audit entry and verify:

```bash
kubectl get namespaces

nerdctl exec kind-control-plane bash -c \
  "test -f /var/log/kubernetes/audit.log && echo log-exists"
# Expected: log-exists

nerdctl exec kind-control-plane bash -c \
  "wc -l /var/log/kubernetes/audit.log"
# Expected: a number >= 1
```

---

## Exercise 3.1 Solution

**Diagnosis:**

Start by confirming the symptom: anonymous access is working when it should not be.

```bash
kubectl --as=system:anonymous auth can-i get pods -n ex-3-1
# If this returns: yes -- that confirms the problem
```

Next, inspect the API server manifest for the anonymous-auth flag:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Look for: - --anonymous-auth=true
```

If you see `--anonymous-auth=true` (or the flag is explicitly set to `true`), that is the misconfiguration. The `kubectl auth can-i` output showing `yes` for system:anonymous is the direct symptom.

**What the bug is and why it happens:**

The `--anonymous-auth=true` flag explicitly enables anonymous access. This is the API server's default, which means it is easy to end up with this value either through an accidental reset, a bad kubeadm config, or a miscommunication during a team hardening pass. When anonymous auth is enabled, any unauthenticated HTTP or HTTPS request to the API server is given the identity `system:anonymous` with group `system:unauthenticated`. If any ClusterRole or Role grants permissions to that identity (some clusters grant `get /healthz` or similar), those requests succeed. More critically, the presence of the anonymous user means that requests can reach the API server without credentials at all.

**The fix:**

```bash
nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Change: - --anonymous-auth=true
# To:     - --anonymous-auth=false
exit
```

Wait for the API server to restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Verify:

```bash
kubectl --as=system:anonymous auth can-i get pods -n ex-3-1
# expect: no
```

---

## Exercise 3.2 Solution

**Diagnosis:**

Start by verifying the symptom: a service account with no RBAC permissions can perform actions it should be denied.

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-3-2:restricted-sa \
  -n ex-3-2
# If this returns: yes -- that confirms RBAC is not being enforced
```

Next, inspect the authorization mode:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"
# Look for: - --authorization-mode=AlwaysAllow
```

Seeing `AlwaysAllow` in the authorization mode list explains the symptom completely. This mode bypasses all other authorization checks.

**What the bug is and why it happens:**

The `--authorization-mode=AlwaysAllow` flag tells the API server to permit every authenticated request regardless of any RBAC or other authorization rules. It is sometimes set in test clusters for convenience but is catastrophically insecure in any real environment. A common path to this misconfiguration is a developer or automation script that sets AlwaysAllow to debug an authorization problem and then forgets to revert it. The result is that any authenticated entity, including service accounts with empty role bindings, can perform any API action.

**The fix:**

```bash
nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Change: - --authorization-mode=AlwaysAllow
# To:     - --authorization-mode=Node,RBAC
exit
```

Wait for the restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Verify RBAC is now enforced:

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-3-2:restricted-sa \
  -n ex-3-2
# expect: no
```

The `Node` mode must be included alongside `RBAC`. Node authorization handles the specific permissions that kubelet agents need to read their assigned pods, secrets, and configmaps. Omitting it will eventually cause nodes to appear NotReady as their kubelets lose the ability to communicate node and pod status.

---

## Exercise 3.3 Solution

**Diagnosis:**

kubectl is unavailable because the API server is not running. Access the container directly:

```bash
nerdctl exec -it kind-control-plane bash
```

Look for the problem in the manifest:

```bash
grep -n '' /etc/kubernetes/manifests/kube-apiserver.yaml | head -30
# Scan the command list for any unusual or invalid flags
```

The setup added `--invalid-security-flag=misconfigured` immediately after `- kube-apiserver`. The API server binary does not recognize this flag and exits on startup. You can also check the container logs for evidence:

```bash
# From inside the control plane container:
crictl ps -a | grep kube-apiserver
# Look for a container that keeps restarting

crictl logs $(crictl ps -a | grep kube-apiserver | awk '{print $1}' | head -1)
# Expected: error about unknown flag or similar startup failure
```

**What the bug is and why it happens:**

The API server binary (like most Go programs) uses a strict flag parser. Any unrecognized flag causes the process to print a usage error and exit immediately. The kubelet then attempts to restart the pod, sees it fail again, and enters a crash loop. Since the API server never successfully starts, kubectl cannot reach it, which makes the usual diagnostic tools unavailable. This failure mode is realistic: it can happen when someone copies a flag from a blog post for a different Kubernetes version, or when a CI script applies a configuration from the wrong component (for example, a kubelet flag accidentally added to the API server manifest).

**The fix:**

From inside the container:

```bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Remove the line: - --invalid-security-flag=misconfigured
exit
```

Wait for the API server to come back:

```bash
# Give it 20-30 seconds, then:
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

kubectl version
# Expected: Server Version shown
```

---

## Exercise 4.1 Solution

Reset state check and kube-bench run:

```bash
nerdctl exec kind-control-plane bash -c \
  "/tmp/kube-bench run --targets master 2>/dev/null | grep '^\[FAIL\]' | grep '1\.2\.'"
# Note which controls are failing
```

Create the log directory if needed, then edit the manifest in one session:

```bash
nerdctl exec kind-control-plane bash -c "mkdir -p /var/log/kubernetes"

nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add all three flags that are missing:
# - --anonymous-auth=false
# - --profiling=false
# - --audit-log-path=/var/log/kubernetes/audit.log
exit
```

Wait for the restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Verify all three are addressed:

```bash
nerdctl exec kind-control-plane bash -c "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false

nerdctl exec kind-control-plane bash -c "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false

nerdctl exec kind-control-plane bash -c "grep audit-log-path /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --audit-log-path=/var/log/kubernetes/audit.log

kubectl --as=system:anonymous auth can-i get pods -n ex-4-1
# expect: no
```

---

## Exercise 4.2 Solution

Inspect current values, then edit the manifest to set all five flags:

```bash
nerdctl exec -it kind-control-plane bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Ensure these five lines are present in the command list:
# - --anonymous-auth=false
# - --profiling=false
# - --authorization-mode=Node,RBAC
# - --enable-admission-plugins=NodeRestriction,AlwaysPullImages
# - --audit-log-path=/var/log/kubernetes/audit.log
exit
```

Wait for the restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Verify each flag:

```bash
for flag in anonymous-auth profiling authorization-mode enable-admission-plugins audit-log-path; do
  echo "--- $flag ---"
  nerdctl exec kind-control-plane bash -c "grep $flag /etc/kubernetes/manifests/kube-apiserver.yaml"
done
```

Each line should show the correct value.

---

## Exercise 4.3 Solution

Inspect the current state:

```bash
nerdctl exec kind-control-plane bash -c "grep -E 'anonymous-auth|profiling|enable-admission' /etc/kubernetes/manifests/kube-apiserver.yaml"
```

The setup left the cluster with `--anonymous-auth=true`, `--profiling` missing, and `--enable-admission-plugins=NodeRestriction` (missing `AlwaysPullImages`). The authorization mode was not changed, so it should be `Node,RBAC`.

Edit the manifest to fix all three issues:

```bash
nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Change: - --anonymous-auth=true  to  - --anonymous-auth=false
# Add:    - --profiling=false
# Change: - --enable-admission-plugins=NodeRestriction
# To:     - --enable-admission-plugins=NodeRestriction,AlwaysPullImages
exit
```

Wait for the restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Verify:

```bash
nerdctl exec kind-control-plane bash -c "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false

nerdctl exec kind-control-plane bash -c "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false

nerdctl exec kind-control-plane bash -c "grep enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --enable-admission-plugins=NodeRestriction,AlwaysPullImages
```

---

## Exercise 5.1 Solution

**Diagnosis:**

kubectl is unavailable. Access the container directly:

```bash
nerdctl exec -it kind-control-plane bash
```

Examine the manifest for the problematic flag:

```bash
grep -n '' /etc/kubernetes/manifests/kube-apiserver.yaml | grep -v '^[0-9]*:$'
```

Scan the command list for anything unusual. The setup added `--tls-cipher-suites=INVALID_CIPHER_THAT_DOES_NOT_EXIST`. The API server validates TLS cipher suite names on startup; an invalid suite causes an immediate exit.

You can also check the API server container logs to see the exact error:

```bash
crictl ps -a | grep kube-apiserver
crictl logs $(crictl ps -a | grep kube-apiserver | awk '{print $1}' | head -1) 2>&1 | tail -20
# Expected: error referencing invalid cipher suite or TLS configuration
```

**What the bug is and why it happens:**

The `--tls-cipher-suites` flag accepts only cipher suite names from a specific list of supported Go TLS suites. Specifying any name outside that list causes the API server to reject the configuration and exit. This is a realistic failure mode because cipher suite names look like constants but are actually version-specific; a suite valid in Kubernetes 1.28 may have been removed in 1.35, and copying configurations between clusters or versions can introduce this error. The fact that the API server never starts means the backup is the safest recovery path.

**The fix:**

From inside the container, remove the invalid flag:

```bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Remove the line: - --tls-cipher-suites=INVALID_CIPHER_THAT_DOES_NOT_EXIST
exit
```

Wait for recovery and verify:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c \
  "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false (hardening flag preserved)

kubectl version
# Expected: Server Version shown
```

---

## Exercise 5.2 Solution

**Diagnosis:**

Start with the symptoms: check what the anonymous user and an unprivileged service account can do.

```bash
kubectl --as=system:anonymous auth can-i get pods -n ex-5-2
# If yes: anonymous-auth is broken

kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-5-2:observer \
  -n ex-5-2
# If yes: authorization-mode is broken
```

Inspect the manifest for all three flag values at once:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep -E 'anonymous-auth|profiling|authorization-mode' /etc/kubernetes/manifests/kube-apiserver.yaml"
```

The setup introduced three misconfigurations: `--anonymous-auth=true`, `--profiling=true`, and `--authorization-mode=AlwaysAllow`.

**What the bugs are and why they happen:**

All three of these flags represent dangerous non-defaults that are easy to introduce in bulk when someone applies a "developer convenience" configuration to a cluster without reverting it. The combination is particularly harmful: `AlwaysAllow` means every authenticated request is permitted, `anonymous-auth=true` means unauthenticated requests are allowed to reach the authorizer, and `profiling=true` exposes runtime internals. Together they create a cluster that is open to both unauthenticated information disclosure and full API access by any authenticated entity.

**The fix:**

Edit all three in one session:

```bash
nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Change: - --anonymous-auth=true    to  - --anonymous-auth=false
# Change: - --profiling=true         to  - --profiling=false
# Change: - --authorization-mode=AlwaysAllow  to  - --authorization-mode=Node,RBAC
exit
```

Wait for the restart, then verify all three:

```bash
kubectl --as=system:anonymous auth can-i get pods -n ex-5-2
# expect: no

kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-5-2:observer \
  -n ex-5-2
# expect: no

nerdctl exec kind-control-plane bash -c "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false
```

---

## Exercise 5.3 Solution

**Diagnosis:**

kubectl is unavailable. Enter the container:

```bash
nerdctl exec -it kind-control-plane bash
```

Scan the manifest for problems:

```bash
grep -n '' /etc/kubernetes/manifests/kube-apiserver.yaml
```

The setup introduced two distinct failures. First, `--authorization-mode=AlwaysAllow,BOGUS` contains an invalid mode name (`BOGUS` is not a recognized authorizer). Second, `--service-cluster-ip-range=999.999.999.0/24` is an invalid CIDR (the 999 octet is not a valid IP). Both of these will cause the API server binary to exit on startup.

You can confirm with the container logs:

```bash
crictl logs $(crictl ps -a | grep kube-apiserver | awk '{print $1}' | head -1) 2>&1 | tail -30
# Look for: unknown authorization mode or invalid CIDR
```

**What the bugs are and why they happen:**

These two failures represent two different categories of misconfiguration. The invalid authorization mode is a typo or copy-paste error in a flag that accepts a specific enum of values. The invalid CIDR is a value range error where someone may have typed a test value without verifying it. Both cause the same visible symptom (API server won't start), but each requires a separate targeted fix. On the CKA exam, the skill being tested is reading the manifest carefully enough to find all problems, not just the first one.

**The fix:**

```bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Change: - --authorization-mode=AlwaysAllow,BOGUS
# To:     - --authorization-mode=Node,RBAC

# Change: - --service-cluster-ip-range=999.999.999.0/24
# To:     - --service-cluster-ip-range=10.96.0.0/16
# (use the original value from your cluster; 10.96.0.0/16 is the kind default)
exit
```

Wait for recovery:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c \
  "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --authorization-mode=Node,RBAC

nerdctl exec kind-control-plane bash -c \
  "grep service-cluster-ip-range /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --service-cluster-ip-range=10.96.0.0/16

kubectl version
# Expected: Server Version shown
```

---

## Common Mistakes

**1. Skipping the backup before editing the manifest.**

The most common mistake in this assignment is editing `/etc/kubernetes/manifests/kube-apiserver.yaml` without first copying it to `/tmp/kube-apiserver.yaml.bak`. When the edit produces an invalid manifest and the API server stops, the only fast recovery path is restoring the backup. Without it, you must regenerate the manifest from kubeadm (which loses any hardening flags you applied) or try to fix the YAML blindly while the API server is down. The backup takes two seconds and saves enormous pain.

**2. Not waiting for the API server to restart before verifying.**

The kubelet restarts the API server pod within 10 to 30 seconds of detecting a manifest change. Running verification commands immediately after saving the file (before the restart completes) will show the old behavior and create confusion about whether the change worked. Always wait for `kubectl get pods -n kube-system -l component=kube-apiserver` to show `Running` before running verification commands.

**3. Using `--authorization-mode=RBAC` without `Node`.**

The Node authorization mode is required for kubelet agents to perform their normal operations: reading pod specs, secrets, and configmaps assigned to their node, and writing pod and node status updates back to the API server. Removing `Node` from the authorization mode list does not immediately break anything visible, but within minutes the kubelets will fail to update node status and the nodes will transition to `NotReady`. Always set `--authorization-mode=Node,RBAC` together.

**4. Assuming a flag's absence means it is disabled.**

Several API server flags default to the dangerous value when omitted. `--anonymous-auth` defaults to `true`, meaning anonymous access is on unless you explicitly set it to `false`. `--profiling` defaults to `true`. If you are auditing a cluster and you do not see `--anonymous-auth=false` in the manifest, anonymous access is active, even though the flag is not there. Do not assume absence means disabled.

**5. Not verifying that a change is behavioral, not just syntactic.**

After adding `--anonymous-auth=false`, confirming the flag is in the manifest is necessary but not sufficient. You must also run `kubectl --as=system:anonymous auth can-i get pods` and confirm the result is `no`. A YAML syntax error that puts the flag in the wrong place (for example, as a label value rather than a command argument) will look correct in `grep` output but have no effect on the running API server.

---

## Verification Commands Cheat Sheet

| Goal | Command | Expected Output |
|---|---|---|
| Check API server is running | `kubectl get pods -n kube-system -l component=kube-apiserver` | STATUS Running |
| Watch API server restart | `kubectl get pods -n kube-system -l component=kube-apiserver -w` | (observe Running after restart) |
| Verify anonymous auth blocked | `kubectl --as=system:anonymous auth can-i get pods -n default` | `no` |
| Verify anonymous auth list blocked | `kubectl --as=system:anonymous auth can-i list namespaces` | `no` |
| Check flag in manifest | `nerdctl exec kind-control-plane bash -c "grep FLAGNAME /etc/kubernetes/manifests/kube-apiserver.yaml"` | expected flag=value |
| Check SA RBAC denial | `kubectl auth can-i list pods --as=system:serviceaccount:NS:SA -n NS` | `no` |
| Run kube-bench all master | `nerdctl exec kind-control-plane bash -c "/tmp/kube-bench run --targets master 2>/dev/null"` | full report |
| Filter kube-bench FAILs | `nerdctl exec kind-control-plane bash -c "/tmp/kube-bench run --targets master 2>/dev/null \| grep '^\[FAIL\]'"` | FAIL lines only |
| Check specific control | `nerdctl exec kind-control-plane bash -c "/tmp/kube-bench run --targets master 2>/dev/null \| grep '1\.2\.1'"` | [PASS] or [FAIL] |
| Shell into control plane | `nerdctl exec -it kind-control-plane bash` | (interactive shell) |
| Backup manifest | `cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak` | (run inside container) |
| Restore manifest | `cp /tmp/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml` | (run inside container) |
| Check API server logs | `crictl logs $(crictl ps -a \| grep kube-apiserver \| awk '{print $1}' \| head -1) 2>&1 \| tail -20` | (run inside container) |
| Verify cluster version | `kubectl version` | Server Version shown |
