# Cluster Hardening Assignment 1 Homework

Work through the tutorial in `cluster-hardening-tutorial.md` before attempting these exercises. The tutorial introduces kube-bench, the API server manifest structure, the backup-edit-verify-recover workflow, and the specific flags each exercise uses. Exercises at Level 3 and Level 5 require you to diagnose broken configurations; read the symptoms before reaching for the manifest.

All exercises in this assignment require a single-node kind cluster. Exercises that edit the kube-apiserver.yaml manifest require exec into the kind control plane container with `nerdctl exec -it kind-control-plane bash`.

## Exercise Setup

Each exercise creates its own namespace using the `ex-<level>-<exercise>` pattern. Level 3 and Level 5 exercises include setup commands that put the cluster in a broken state; run the setup commands exactly as written, then proceed to the task.

---

## Level 1: Tool Familiarity and Single-Flag Verification

### Exercise 1.1

**Objective:** Download kube-bench into the kind control plane container and save its API server FAIL findings to a file.

**Setup:**

No additional setup is required. Ensure your single-node kind cluster is running.

**Task:**

Download the kube-bench binary into the kind control plane container at `/tmp/kube-bench`. Run kube-bench targeting the master component. Filter the output to lines starting with `[FAIL]` that belong to the `1.2.x` API server section and save those lines to `/tmp/apiserver-fails.txt` inside the container.

**Verification:**

```bash
nerdctl exec kind-control-plane test -s /tmp/apiserver-fails.txt && echo "file-exists"
# Expected: file-exists

nerdctl exec kind-control-plane bash -c "grep '1\.2\.1' /tmp/apiserver-fails.txt"
# Expected: [FAIL] 1.2.1 Ensure that the --anonymous-auth argument is set to false (Automated)
```

---

### Exercise 1.2

**Objective:** Verify whether `--profiling=false` is set on the API server. If it is missing or set to `true`, add or correct it, wait for the API server to restart, and confirm the flag is active.

**Setup:**

```bash
kubectl create namespace ex-1-2
```

**Task:**

Inspect the kube-apiserver.yaml manifest. Locate the `--profiling` flag if present. If `--profiling=false` is not in the manifest, add it using the backup-edit-verify workflow from the tutorial. Wait for the API server to restart, then confirm the flag is present.

**Verification:**

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c \
  "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false

nerdctl exec kind-control-plane bash -c \
  "/tmp/kube-bench run --targets master 2>/dev/null | grep '1\.2\.17'"
# Expected: [PASS] 1.2.17 ...profiling... (or the equivalent control in your benchmark version)
```

---

### Exercise 1.3

**Objective:** Verify that `--authorization-mode` includes both `Node` and `RBAC`. If not, correct the flag. Confirm the authorization mode is enforced by verifying that a ServiceAccount with no RoleBindings cannot list pods.

**Setup:**

```bash
kubectl create namespace ex-1-3
kubectl create serviceaccount audit-check -n ex-1-3
```

**Task:**

Inspect the kube-apiserver.yaml manifest and confirm the `--authorization-mode` flag. If it does not include both `Node` and `RBAC`, edit the manifest to set `--authorization-mode=Node,RBAC`. Once the API server is running, verify that the `audit-check` ServiceAccount in `ex-1-3` cannot list pods (it has no RoleBinding, so RBAC should deny the request).

**Verification:**

```bash
nerdctl exec kind-control-plane bash -c \
  "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --authorization-mode=Node,RBAC

kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-1-3:audit-check \
  -n ex-1-3
# expect: no

kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running
```

---

## Level 2: Active Hardening with Verification

### Exercise 2.1

**Objective:** Disable anonymous authentication on the API server and verify the change is enforced.

**Setup:**

```bash
kubectl create namespace ex-2-1
```

**Task:**

Back up the kube-apiserver.yaml manifest. Edit it to set `--anonymous-auth=false`. Wait for the API server to restart. Verify that anonymous requests to the Kubernetes API are rejected.

**Verification:**

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

kubectl --as=system:anonymous auth can-i get pods -n ex-2-1
# expect: no

kubectl --as=system:anonymous auth can-i list namespaces
# expect: no

nerdctl exec kind-control-plane bash -c \
  "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false
```

---

### Exercise 2.2

**Objective:** Add `NodeRestriction` and `AlwaysPullImages` to the `--enable-admission-plugins` flag and verify both are active.

**Setup:**

```bash
kubectl create namespace ex-2-2
```

**Task:**

Inspect the current `--enable-admission-plugins` value in kube-apiserver.yaml. Update it to include `NodeRestriction,AlwaysPullImages` (preserving any existing plugins). Wait for the API server to restart and confirm the updated flag value is live.

**Verification:**

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c \
  "grep enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: a line containing both NodeRestriction and AlwaysPullImages

kubectl api-versions | grep admissionregistration
# Expected: admissionregistration.k8s.io/v1 (admission infrastructure is working)
```

---

### Exercise 2.3

**Objective:** Enable audit logging on the API server by configuring `--audit-log-path`.

**Setup:**

```bash
kubectl create namespace ex-2-3
```

**Task:**

Create the log directory `/var/log/kubernetes/` inside the kind control plane container. Edit the kube-apiserver.yaml manifest to add `--audit-log-path=/var/log/kubernetes/audit.log`. Wait for the API server to restart. Make at least one API request to generate an audit entry, then confirm the log file exists and contains at least one JSON record.

**Verification:**

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c \
  "test -f /var/log/kubernetes/audit.log && echo log-exists"
# Expected: log-exists

kubectl get namespaces

nerdctl exec kind-control-plane bash -c \
  "wc -l /var/log/kubernetes/audit.log"
# Expected: a number >= 1 (at least one log entry)
```

---

## Level 3: Debugging Broken Configurations

### Exercise 3.1

**Objective:** The API server is configured in a way that allows unauthenticated access when it should be blocked. The configuration has one or more problems. Find and fix whatever is needed so that anonymous requests to the Kubernetes API are denied.

**Setup:**

```bash
kubectl create namespace ex-3-1

nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex31.bak
  cat > /tmp/fix_ex31.py << 'PYEOF'
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    lines = f.readlines()
new_lines = []
found = False
for line in lines:
    if '--anonymous-auth' in line:
        found = True
        new_lines.append('    - --anonymous-auth=true\n')
    else:
        new_lines.append(line)
        if '- kube-apiserver' in line.strip() and not found:
            new_lines.append('    - --anonymous-auth=true\n')
            found = True
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.writelines(new_lines)
PYEOF
python3 /tmp/fix_ex31.py
"
sleep 30
kubectl get pods -n kube-system -l component=kube-apiserver
```

**Task:**

Investigate why anonymous access is allowed. Find the misconfiguration in the API server manifest, fix it so that unauthenticated requests are rejected, and verify the change took effect.

**Verification:**

```bash
kubectl --as=system:anonymous auth can-i get pods -n ex-3-1
# expect: no

kubectl --as=system:anonymous auth can-i list namespaces
# expect: no

nerdctl exec kind-control-plane bash -c \
  "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false
```

---

### Exercise 3.2

**Objective:** RBAC rules in this cluster are not being enforced. A service account with no role bindings can perform actions it should be denied. The configuration has one or more problems. Find and fix whatever is needed so that RBAC authorization is correctly applied.

**Setup:**

```bash
kubectl create namespace ex-3-2
kubectl create serviceaccount restricted-sa -n ex-3-2

nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex32.bak
  cat > /tmp/fix_ex32.py << 'PYEOF'
import re
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    content = f.read()
content = re.sub(r'--authorization-mode=\S+', '--authorization-mode=AlwaysAllow', content)
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.write(content)
PYEOF
python3 /tmp/fix_ex32.py
"
sleep 30
kubectl get pods -n kube-system -l component=kube-apiserver
```

**Task:**

Verify that the `restricted-sa` service account can perform actions it has no RBAC permission for. Identify the API server flag responsible for this behavior, correct it to properly enforce RBAC and Node authorization, wait for the restart, and verify that RBAC rules are now applied.

**Verification:**

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-3-2:restricted-sa \
  -n ex-3-2
# expect: no

kubectl auth can-i delete deployments \
  --as=system:serviceaccount:ex-3-2:restricted-sa \
  -n ex-3-2
# expect: no

nerdctl exec kind-control-plane bash -c \
  "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --authorization-mode=Node,RBAC
```

---

### Exercise 3.3

**Objective:** The API server is not responding to requests. Find the problem in the static pod manifest and restore normal cluster operation.

**Setup:**

```bash
nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex33.bak
  cat > /tmp/fix_ex33.py << 'PYEOF'
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    lines = f.readlines()
new_lines = []
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-apiserver':
        new_lines.append('    - --invalid-security-flag=misconfigured\n')
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.writelines(new_lines)
PYEOF
python3 /tmp/fix_ex33.py
"
# The API server will stop responding. This is expected.
```

**Task:**

The cluster's API server is unreachable. Without kubectl access, locate the problem in the manifest and fix it so the API server starts again. Once the API server is running, verify the cluster is healthy.

**Verification:**

```bash
# Run these after the API server is restored
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

kubectl get nodes
# Expected: control-plane node with STATUS Ready

kubectl version
# Expected: Server Version shown (not a connection error)
```

---

## Level 4: Complex Real-World Remediation

### Exercise 4.1

**Objective:** Apply a set of CIS benchmark remediations to address three known FAIL findings on the API server in a single editing session.

**Setup:**

```bash
kubectl create namespace ex-4-1

# Reset the API server to a default-like state with multiple issues
nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex41.bak
  cat > /tmp/fix_ex41.py << 'PYEOF'
import re
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    content = f.read()
# Remove hardening flags that may have been set by previous exercises
content = '\n'.join(l for l in content.split('\n')
    if '--anonymous-auth' not in l
    and '--profiling' not in l
    and '--audit-log-path' not in l)
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.write(content)
PYEOF
python3 /tmp/fix_ex41.py
"
sleep 30
kubectl get pods -n kube-system -l component=kube-apiserver
```

**Task:**

Run kube-bench against the master component and identify FAIL findings for the API server section. In a single editing session, apply remediations for the following three controls: anonymous authentication (set to false), profiling (set to false), and audit logging (set path to `/var/log/kubernetes/audit.log`). Create the log directory if needed. Wait for the API server to restart and verify all three controls are addressed.

**Verification:**

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c \
  "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false

nerdctl exec kind-control-plane bash -c \
  "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false

nerdctl exec kind-control-plane bash -c \
  "grep audit-log-path /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --audit-log-path=/var/log/kubernetes/audit.log

kubectl --as=system:anonymous auth can-i get pods -n ex-4-1
# expect: no

nerdctl exec kind-control-plane bash -c \
  "test -f /var/log/kubernetes/audit.log && echo log-exists"
# Expected: log-exists
```

---

### Exercise 4.2

**Objective:** Apply a complete hardening configuration to the API server as specified below and verify every flag is active.

**Setup:**

```bash
kubectl create namespace ex-4-2
```

**Task:**

Edit the kube-apiserver.yaml manifest to ensure all five of the following flags are present with the specified values:

- `--anonymous-auth=false`
- `--profiling=false`
- `--authorization-mode=Node,RBAC`
- `--enable-admission-plugins=NodeRestriction,AlwaysPullImages`
- `--audit-log-path=/var/log/kubernetes/audit.log`

If any flag already has the correct value, leave it. If a flag is missing or has a different value, add or correct it. Make all changes in a single editing session, wait for the API server to restart, and verify each flag.

**Verification:**

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false

nerdctl exec kind-control-plane bash -c "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false

nerdctl exec kind-control-plane bash -c "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --authorization-mode=Node,RBAC

nerdctl exec kind-control-plane bash -c "grep enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: a line containing both NodeRestriction and AlwaysPullImages

nerdctl exec kind-control-plane bash -c "grep audit-log-path /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --audit-log-path=/var/log/kubernetes/audit.log

kubectl --as=system:anonymous auth can-i get pods -n ex-4-2
# expect: no
```

---

### Exercise 4.3

**Objective:** Start from a cluster with partially inconsistent hardening and bring it to a fully compliant state. Some flags may already be set correctly; others may need to be added, changed, or removed.

**Setup:**

```bash
kubectl create namespace ex-4-3

nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex43.bak
  cat > /tmp/fix_ex43.py << 'PYEOF'
import re
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    content = f.read()
# Set a mixed state: anonymous-auth wrong, profiling missing, authorization-mode correct
content = '\n'.join(l for l in content.split('\n')
    if '--anonymous-auth' not in l
    and '--profiling' not in l
    and '--enable-admission-plugins' not in l)
# Re-add with broken values
lines = content.split('\n')
new_lines = []
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-apiserver':
        new_lines.append('    - --anonymous-auth=true')
        new_lines.append('    - --enable-admission-plugins=NodeRestriction')
content = '\n'.join(new_lines)
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.write(content)
PYEOF
python3 /tmp/fix_ex43.py
"
sleep 30
kubectl get pods -n kube-system -l component=kube-apiserver
```

**Task:**

Inspect the current API server configuration. Identify which of the following flags are missing, incorrect, or need to be added:

- `--anonymous-auth=false`
- `--profiling=false`
- `--enable-admission-plugins=NodeRestriction,AlwaysPullImages`

Apply all necessary corrections in a single editing session. Do not change flags that are already set correctly. Verify each corrected flag after the API server restarts.

**Verification:**

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false

nerdctl exec kind-control-plane bash -c "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false

nerdctl exec kind-control-plane bash -c "grep enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: a line containing both NodeRestriction and AlwaysPullImages

kubectl --as=system:anonymous auth can-i get pods -n ex-4-3
# expect: no
```

---

## Level 5: Advanced Debugging

### Exercise 5.1

**Objective:** The API server is not responding to any requests. Diagnose the failure, restore the cluster to an operational state, and verify that the hardening flags from the previous exercises are still present after recovery.

**Setup:**

```bash
# This setup assumes the API server currently has --anonymous-auth=false set
# It will break the API server by introducing an invalid flag
nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex51.bak
  cat > /tmp/fix_ex51.py << 'PYEOF'
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    lines = f.readlines()
new_lines = []
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-apiserver':
        new_lines.append('    - --tls-cipher-suites=INVALID_CIPHER_THAT_DOES_NOT_EXIST\n')
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.writelines(new_lines)
PYEOF
python3 /tmp/fix_ex51.py
"
# The API server will stop. This is expected.
```

**Task:**

The configuration above has one or more problems that prevent the API server from starting. Without kubectl access, diagnose the failure by examining the manifest and any available logs, then fix the problem so the API server starts again. After recovery, confirm that `--anonymous-auth=false` is still in the manifest (do not lose hardening flags while restoring).

**Verification:**

```bash
# Run these after the API server is restored
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

kubectl get nodes
# Expected: control-plane node with STATUS Ready

nerdctl exec kind-control-plane bash -c \
  "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false

kubectl version
# Expected: Server Version shown
```

---

### Exercise 5.2

**Objective:** The cluster has multiple security misconfigurations that were introduced simultaneously. The configuration has one or more problems. Find and fix all of them so that anonymous access is blocked, RBAC is enforced, and profiling is disabled.

**Setup:**

```bash
kubectl create namespace ex-5-2
kubectl create serviceaccount observer -n ex-5-2

nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex52.bak
  cat > /tmp/fix_ex52.py << 'PYEOF'
import re
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    content = f.read()
# Remove hardening flags, inject broken values
content = '\n'.join(l for l in content.split('\n')
    if '--anonymous-auth' not in l
    and '--profiling' not in l
    and '--authorization-mode' not in l)
lines = content.split('\n')
new_lines = []
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-apiserver':
        new_lines.append('    - --anonymous-auth=true')
        new_lines.append('    - --profiling=true')
        new_lines.append('    - --authorization-mode=AlwaysAllow')
content = '\n'.join(new_lines)
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.write(content)
PYEOF
python3 /tmp/fix_ex52.py
"
sleep 30
kubectl get pods -n kube-system -l component=kube-apiserver
```

**Task:**

The configuration above has one or more problems. Identify each misconfiguration in the API server manifest, fix all of them in a single editing session, wait for the API server to restart, and verify every correction is active.

**Verification:**

```bash
kubectl --as=system:anonymous auth can-i get pods -n ex-5-2
# expect: no

kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-5-2:observer \
  -n ex-5-2
# expect: no

nerdctl exec kind-control-plane bash -c "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --anonymous-auth=false

nerdctl exec kind-control-plane bash -c "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false

nerdctl exec kind-control-plane bash -c "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --authorization-mode=Node,RBAC
```

---

### Exercise 5.3

**Objective:** The API server is failing to start and the cluster is completely unreachable. Multiple issues may be present in the manifest. The configuration has one or more problems. Diagnose the failures, restore the API server, and ensure the cluster is fully operational before verifying.

**Setup:**

```bash
nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex53.bak
  cat > /tmp/fix_ex53.py << 'PYEOF'
import re
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    content = f.read()
# Introduce two distinct failures
content = re.sub(r'--authorization-mode=\S+', '--authorization-mode=AlwaysAllow,BOGUS', content)
lines = content.split('\n')
new_lines = []
for line in lines:
    new_lines.append(line)
    if line.strip() == '- kube-apiserver':
        new_lines.append('    - --service-cluster-ip-range=999.999.999.0/24')
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.write('\n'.join(new_lines))
PYEOF
python3 /tmp/fix_ex53.py
"
# The API server will stop. This is expected.
```

**Task:**

The configuration above has one or more problems that prevent the API server from starting. Diagnose all failures by examining the manifest directly (kubectl is unavailable). Fix every problem you find, restore normal API server operation, and verify the cluster is healthy. After recovery, ensure `--authorization-mode=Node,RBAC` is set correctly.

**Verification:**

```bash
# Run these after the API server is restored
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

kubectl get nodes
# Expected: control-plane node with STATUS Ready

nerdctl exec kind-control-plane bash -c \
  "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --authorization-mode=Node,RBAC

nerdctl exec kind-control-plane bash -c \
  "grep service-cluster-ip-range /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --service-cluster-ip-range=10.96.0.0/16 (or the original value, not 999.x.x.x)

kubectl version
# Expected: Server Version shown
```

---

## Cleanup

Delete all exercise namespaces created during this homework:

```bash
kubectl delete namespace ex-1-2 ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-4-1 ex-4-2 ex-4-3 ex-5-2

# Restore the API server manifest to a clean hardened state if desired
# (Level 3, 4, and 5 exercises may have left the manifest in a modified state)
# See the tutorial for the full set of hardening flags to re-apply.
```

---

## Key Takeaways

The exercises in this assignment build two categories of muscle memory. The first is the operational skill of editing a static pod manifest safely: always back up, edit precisely, watch for the restart, verify the behavioral change, and know the recovery path before you need it. The second is the diagnostic skill of reading API server configuration to identify dangerous defaults: anonymous authentication enabled, authorization mode set to AlwaysAllow, profiling exposed, and audit logging absent. Both skills transfer directly to the CKA and CKS exam environments.
