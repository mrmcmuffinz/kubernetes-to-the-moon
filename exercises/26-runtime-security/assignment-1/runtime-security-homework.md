# Runtime Security Homework — Assignment 1: Falco Threat Detection

Work through the tutorial (`runtime-security-tutorial.md`) before attempting these exercises. The tutorial installs Falco and walks through the rule structure and output format. All exercises assume Falco is installed and Running in the `falco` namespace.

---

## Level 1: Reading Falco Alerts

Level 1 exercises focus on triggering built-in Falco rules and reading the alert output to identify the rule name, priority, and triggering behavior.

### Exercise 1.1

**Objective:** Deploy a pod and trigger the Terminal Shell in Container rule. Confirm the alert appears in the Falco log.

**Setup:**

```bash
kubectl create namespace ex-1-1
kubectl run shell-test -n ex-1-1 \
  --image=busybox:1.36 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/shell-test -n ex-1-1 --timeout=60s
```

**Task:** Execute an interactive shell inside the `shell-test` pod. After exiting the shell, read the Falco logs and locate the alert that fired. Record the rule name and priority from the alert line.

**Verification:**

```bash
kubectl exec -it shell-test -n ex-1-1 -- sh
# (type exit to leave the shell)

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "shell-test"
# Expected: at least one alert line containing "shell-test" and "sh"

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Warning"
# Expected: output includes a line with priority Warning
```

---

### Exercise 1.2

**Objective:** Trigger the sensitive file read rule and identify which file access caused the alert.

**Setup:**

```bash
kubectl create namespace ex-1-2
kubectl run secret-reader -n ex-1-2 \
  --image=alpine:3.20 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/secret-reader -n ex-1-2 --timeout=60s
```

**Task:** Execute a command inside the `secret-reader` pod that reads `/etc/shadow`. Read the Falco log and locate the alert. Identify the file path that appears in the alert output.

**Verification:**

```bash
kubectl exec secret-reader -n ex-1-2 -- cat /etc/shadow

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "shadow"
# Expected: alert line containing /etc/shadow and the pod name secret-reader

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "secret-reader"
# Expected: at least one alert line referencing secret-reader
```

---

### Exercise 1.3

**Objective:** Confirm that a normal file read does not trigger the sensitive file rule, and that the rule is specific to the paths it monitors.

**Setup:**

```bash
kubectl create namespace ex-1-3
kubectl run baseline-reader -n ex-1-3 \
  --image=alpine:3.20 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/baseline-reader -n ex-1-3 --timeout=60s
```

**Task:** Execute a command inside the `baseline-reader` pod that reads `/etc/hostname` (a non-sensitive file). Then execute a command that reads `/etc/passwd`. Check the Falco logs and confirm that only the `/etc/passwd` read produced an alert, and that the `/etc/hostname` read did not.

**Verification:**

```bash
kubectl exec baseline-reader -n ex-1-3 -- cat /etc/hostname
kubectl exec baseline-reader -n ex-1-3 -- cat /etc/passwd

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=40 | grep "baseline-reader"
# Expected: alert for /etc/passwd read; no alert for /etc/hostname read
# The alert line should contain the string "passwd" or the rule name for sensitive file access
```

---

## Level 2: Writing and Modifying Rules

Level 2 exercises ask you to write custom Falco rules, modify existing rule properties, and apply the changes to a running cluster.

### Exercise 2.1

**Objective:** Write a custom Falco rule that fires when the `curl` binary is executed inside any container. Apply the rule to the cluster and verify an alert fires when you run curl inside a pod.

**Setup:**

```bash
kubectl create namespace ex-2-1
kubectl run curl-test -n ex-2-1 \
  --image=curlimages/curl:8.5.0 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/curl-test -n ex-2-1 --timeout=60s
```

**Task:** Create a Helm values file that adds a custom rule named `Curl Executed in Container` with priority `WARNING`. The rule must fire when `proc.name = curl` and `container.id != host`. Apply the rule by upgrading the Falco Helm release. Trigger the rule by running curl inside `curl-test`. Verify the alert appears in the Falco log.

**Verification:**

```bash
kubectl rollout status daemonset/falco -n falco
# Expected: successfully rolled out

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=10 | grep "custom"
# Expected: log line indicating custom rules file was loaded

kubectl exec curl-test -n ex-2-1 -- curl -s -o /dev/null http://example.com || true

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Curl Executed"
# Expected: alert line containing "Curl Executed in Container"
```

---

### Exercise 2.2

**Objective:** Disable the Terminal Shell in Container built-in rule using an override, then verify that running an interactive shell no longer produces that specific alert.

**Setup:**

```bash
kubectl create namespace ex-2-2
kubectl run no-alert-shell -n ex-2-2 \
  --image=busybox:1.36 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/no-alert-shell -n ex-2-2 --timeout=60s
```

**Task:** Add an override to your Falco Helm values that disables the `Terminal Shell in Container` rule. Apply the change and wait for the DaemonSet to roll out. Run an interactive shell inside `no-alert-shell`. Confirm that no alert for that rule appears in the Falco log for that pod.

**Verification:**

```bash
kubectl rollout status daemonset/falco -n falco
# Expected: successfully rolled out

kubectl exec -it no-alert-shell -n ex-2-2 -- sh
# (type exit immediately)

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "no-alert-shell" | grep "Shell spawned"
# Expected: no output (the rule is disabled, so no alert fires)
```

---

### Exercise 2.3

**Objective:** Change the priority of the `Write below binary dir` built-in rule from its default level to `CRITICAL`, then verify the changed priority appears in the alert when you trigger the rule.

**Setup:**

```bash
kubectl create namespace ex-2-3
kubectl run write-test -n ex-2-3 \
  --image=alpine:3.20 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/write-test -n ex-2-3 --timeout=60s
```

**Task:** Add an override to your Falco Helm values that sets the priority of `Write below binary dir` to `CRITICAL`. Apply the change. Trigger the rule by writing a file under `/usr/bin` inside the pod. Verify the Falco log shows `Critical` priority for the alert.

**Verification:**

```bash
kubectl rollout status daemonset/falco -n falco
# Expected: successfully rolled out

kubectl exec write-test -n ex-2-3 -- sh -c "echo test > /usr/bin/testfile && rm /usr/bin/testfile" || true

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "write-test" | grep -i "critical"
# Expected: alert line containing "Critical" and referencing write-test or binary dir
```

---

## Level 3: Debugging Broken Configurations

Each exercise in this level presents a broken Falco rule configuration. Use the Falco logs and your understanding of the condition language to diagnose and fix the problem.

### Exercise 3.1

**Objective:** The custom rule below does not fire when a shell is executed inside a container. Find and fix what is wrong so the rule fires correctly.

**Setup:** Apply the following Helm values to your Falco release:

```bash
cat > /tmp/ex-3-1-rules.yaml <<'EOF'
customRules:
  ex_3_1_rules.yaml: |-
    - rule: Detect Shell in Container
      desc: A shell process was started inside a container
      condition: >
        evt.type = execve and
        proc.name in (shell_binaries) and
        container.id != host
      output: >
        Shell in container
        (shell=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: WARNING
      tags: [container, shell]
EOF

helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-3-1-rules.yaml \
  --version 4.7.2

kubectl rollout status daemonset/falco -n falco
```

```bash
kubectl create namespace ex-3-1
kubectl run debug-shell -n ex-3-1 \
  --image=busybox:1.36 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/debug-shell -n ex-3-1 --timeout=60s
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that running `kubectl exec -it debug-shell -n ex-3-1 -- sh` causes the `Detect Shell in Container` rule to fire and an alert appears in the Falco log.

**Verification:**

```bash
kubectl exec -it debug-shell -n ex-3-1 -- sh
# (type exit)

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Detect Shell in Container"
# Expected: alert line containing "Detect Shell in Container"
```

---

### Exercise 3.2

**Objective:** The custom rule below is supposed to fire when a process reads `/etc/shadow` inside a container, but it never fires. Find and fix the problem.

**Setup:**

```bash
cat > /tmp/ex-3-2-rules.yaml <<'EOF'
customRules:
  ex_3_2_rules.yaml: |-
    - rule: Shadow File Access
      desc: A process read the shadow password file inside a container
      condition: >
        evt.type = open and
        fd.name = /etc/shadow and
        container.id != host
      output: >
        Shadow file opened
        (proc=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name file=%fd.filepath)
      priority: CRITICAL
      tags: [container, credentials]
EOF

helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-3-2-rules.yaml \
  --version 4.7.2

kubectl rollout status daemonset/falco -n falco
```

```bash
kubectl create namespace ex-3-2
kubectl run shadow-debug -n ex-3-2 \
  --image=alpine:3.20 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/shadow-debug -n ex-3-2 --timeout=60s
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so that running `kubectl exec shadow-debug -n ex-3-2 -- cat /etc/shadow` causes the `Shadow File Access` rule to fire.

**Verification:**

```bash
kubectl exec shadow-debug -n ex-3-2 -- cat /etc/shadow || true

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Shadow File Access"
# Expected: alert line containing "Shadow File Access"
```

---

### Exercise 3.3

**Objective:** The custom rule below tries to produce an alert output that shows the file path, but the output contains garbled or missing field values. Find and fix the output format string.

**Setup:**

```bash
cat > /tmp/ex-3-3-rules.yaml <<'EOF'
customRules:
  ex_3_3_rules.yaml: |-
    - rule: Binary Dir Write Alert
      desc: A process wrote to a binary directory inside a container
      condition: >
        evt.type in (write, open) and
        evt.dir = < and
        fd.directory in (/bin, /usr/bin, /sbin) and
        container.id != host
      output: >
        Write to binary directory
        (proc=%process.name pod=%k8s.pod.label ns=%k8s.ns.name path=%fd.path)
      priority: ERROR
      tags: [container, filesystem]
EOF

helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-3-3-rules.yaml \
  --version 4.7.2

kubectl rollout status daemonset/falco -n falco
```

```bash
kubectl create namespace ex-3-3
kubectl run bindir-debug -n ex-3-3 \
  --image=alpine:3.20 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/bindir-debug -n ex-3-3 --timeout=60s
```

**Task:** The configuration above has one or more problems in the output format string. Find and fix all invalid field names so that triggering the rule produces a properly formatted alert with the process name, pod name, namespace, and file path correctly substituted.

**Verification:**

```bash
kubectl exec bindir-debug -n ex-3-3 -- sh -c "echo x > /usr/bin/debug-probe && rm /usr/bin/debug-probe" || true

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Binary Dir Write Alert"
# Expected: alert line containing "Binary Dir Write Alert" with non-empty field values
# The proc= and ns= fields should not show literal null or empty strings
```

---

## Level 4: Complete Threat Detection Scenario

### Exercise 4.1

**Objective:** Write a complete custom ruleset covering three distinct threat behaviors for a simulated application workload: unexpected process execution, unexpected file access, and suspicious outbound network tool usage.

**Setup:**

```bash
kubectl create namespace ex-4-1
kubectl run app-workload -n ex-4-1 \
  --image=nginx:1.27 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/app-workload -n ex-4-1 --timeout=60s
```

**Task:** Create and apply a Helm values file containing three custom rules:

1. `Unexpected Process in App Container` fires when any process other than `nginx` or `sh` is executed inside a container in the `ex-4-1` namespace. Use a list named `allowed_app_processes`.
2. `Sensitive Config Read in App` fires when a process reads any file under `/etc/nginx` using `fd.directory startswith /etc/nginx` scoped to the `ex-4-1` namespace and to container events.
3. `Recon Tool in App` fires when `wget`, `curl`, or `nc` is executed in a container in the `ex-4-1` namespace. Use a list named `recon_tools`.

After applying, trigger each rule by running appropriate commands inside `app-workload`. Verify all three rules produce alerts.

**Verification:**

```bash
kubectl rollout status daemonset/falco -n falco
# Expected: successfully rolled out

# Trigger rule 1
kubectl exec app-workload -n ex-4-1 -- python3 --version || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep "Unexpected Process in App Container"
# Expected: alert line present

# Trigger rule 2
kubectl exec app-workload -n ex-4-1 -- cat /etc/nginx/nginx.conf
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep "Sensitive Config Read in App"
# Expected: alert line present

# Trigger rule 3
kubectl exec app-workload -n ex-4-1 -- wget -q -O /dev/null http://example.com || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep "Recon Tool in App"
# Expected: alert line present
```

---

### Exercise 4.2

**Objective:** Write a custom rule that uses a macro for reuse across two rules sharing common scoping logic.

**Setup:**

```bash
kubectl create namespace ex-4-2
kubectl run macro-test -n ex-4-2 \
  --image=alpine:3.20 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/macro-test -n ex-4-2 --timeout=60s
```

**Task:** Create and apply a Helm values file that defines:

1. A macro named `container_in_ex42` with condition `container.id != host and k8s.ns.name = "ex-4-2"`.
2. A rule named `Shell in Ex42` that uses `container_in_ex42` and fires when `proc.name in (shell_binaries)` and `spawned_process` (use the built-in macro).
3. A rule named `File Write in Ex42` that uses `container_in_ex42` and fires when `evt.type = write` and `evt.dir = <`.

Trigger both rules and verify alerts appear for the `macro-test` pod.

**Verification:**

```bash
kubectl rollout status daemonset/falco -n falco
# Expected: successfully rolled out

kubectl exec -it macro-test -n ex-4-2 -- sh
# (type exit)
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Shell in Ex42"
# Expected: alert line present

kubectl exec macro-test -n ex-4-2 -- sh -c "echo test > /tmp/testfile"
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "File Write in Ex42"
# Expected: alert line present
```

---

### Exercise 4.3

**Objective:** Configure Falco to emit JSON-formatted output and use `jq` to filter alerts to only those from a specific namespace.

**Setup:**

```bash
kubectl create namespace ex-4-3
kubectl run json-test -n ex-4-3 \
  --image=busybox:1.36 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/json-test -n ex-4-3 --timeout=60s
```

**Task:** Upgrade the Falco Helm release to enable JSON output by adding `--set falco.jsonOutput=true`. After the DaemonSet rolls out, trigger the Terminal Shell in Container rule by execing into `json-test`. Then use `kubectl logs` piped to `jq` to display only alerts where `output_fields["k8s.ns.name"]` equals `"ex-4-3"`. The filtered output must include at least one alert.

**Verification:**

```bash
kubectl rollout status daemonset/falco -n falco
# Expected: successfully rolled out

kubectl exec -it json-test -n ex-4-3 -- sh
# (type exit)

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | \
  jq -r 'select(.output_fields["k8s.ns.name"] == "ex-4-3") | .rule'
# Expected: at least one line showing "Terminal Shell in Container"
```

---

## Level 5: Advanced Debugging

### Exercise 5.1

**Objective:** A rule is firing too broadly, generating alerts for a legitimate operation that runs in every pod. Tune the condition to suppress the false positives while retaining detection for the actual threat.

**Setup:**

```bash
cat > /tmp/ex-5-1-rules.yaml <<'EOF'
customRules:
  ex_5_1_rules.yaml: |-
    - list: network_tools
      items: [wget, curl, nc, ncat, nmap, ping]

    - rule: Network Tool Execution
      desc: A network tool was executed inside a container
      condition: >
        evt.type = execve and evt.dir = < and
        container.id != host and
        proc.name in (network_tools)
      output: >
        Network tool in container
        (tool=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: WARNING
      tags: [container, network]
EOF

helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-5-1-rules.yaml \
  --version 4.7.2

kubectl rollout status daemonset/falco -n falco
```

```bash
kubectl create namespace ex-5-1

# Deploy a monitoring pod that legitimately runs ping every 30 seconds
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: health-monitor
  namespace: ex-5-1
  labels:
    role: monitor
spec:
  containers:
  - name: monitor
    image: alpine:3.20
    command: [sh, -c]
    args:
    - |
      while true; do
        ping -c 1 -W 1 8.8.8.8 > /dev/null 2>&1 || true
        sleep 30
      done
EOF

# Deploy a suspicious pod
kubectl run attacker -n ex-5-1 \
  --image=alpine:3.20 \
  --restart=Never \
  -- sleep 3600

kubectl wait --for=condition=Ready pod/health-monitor -n ex-5-1 --timeout=60s
kubectl wait --for=condition=Ready pod/attacker -n ex-5-1 --timeout=60s
```

**Task:** The `Network Tool Execution` rule fires for both the `health-monitor` pod (which legitimately uses `ping`) and the `attacker` pod. The `health-monitor` alerts are false positives. Tune the rule condition so that:

- `ping` from pods with `role=monitor` does not trigger an alert.
- `wget`, `curl`, `nc`, `ncat`, and `nmap` from any pod still trigger an alert.
- `ping` from the `attacker` pod still triggers an alert.

Apply the tuned rule and verify the behavior.

**Verification:**

```bash
kubectl rollout status daemonset/falco -n falco
# Expected: successfully rolled out

# Confirm health-monitor ping no longer triggers alert
sleep 35
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=60 | grep "health-monitor" | grep "Network Tool"
# Expected: no output (health-monitor ping is suppressed)

# Confirm attacker curl still triggers
kubectl exec attacker -n ex-5-1 -- wget -q -O /dev/null http://example.com || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "attacker" | grep "Network Tool"
# Expected: at least one alert line referencing attacker

# Confirm attacker ping still triggers
kubectl exec attacker -n ex-5-1 -- ping -c 1 8.8.8.8 || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "attacker" | grep "ping"
# Expected: at least one alert line referencing attacker and ping
```

---

### Exercise 5.2

**Objective:** A rule fires for the correct threat but the output format makes it hard to identify which pod and namespace the alert came from. Rewrite the output to include structured, readable context.

**Setup:**

```bash
cat > /tmp/ex-5-2-rules.yaml <<'EOF'
customRules:
  ex_5_2_rules.yaml: |-
    - rule: Privileged Exec Attempt
      desc: A process was executed with arguments that look like privilege escalation
      condition: >
        evt.type = execve and evt.dir = < and
        container.id != host and
        (proc.name = sudo or proc.name = su)
      output: >
        Priv escalation attempt (proc=%proc.name)
      priority: CRITICAL
      tags: [container, privilege_escalation]
EOF

helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-5-2-rules.yaml \
  --version 4.7.2

kubectl rollout status daemonset/falco -n falco
```

```bash
kubectl create namespace ex-5-2
kubectl run privesc-test -n ex-5-2 \
  --image=alpine:3.20 \
  --restart=Never \
  -- sleep 3600
kubectl wait --for=condition=Ready pod/privesc-test -n ex-5-2 --timeout=60s
```

**Task:** The `Privileged Exec Attempt` rule fires correctly but the output string only shows the process name. Rewrite the output to include the pod name, namespace, parent process name, user name, and process arguments so that a security analyst can identify the source of the alert without additional investigation. Apply the updated rule and verify the richer output appears in the Falco log.

**Verification:**

```bash
kubectl rollout status daemonset/falco -n falco
# Expected: successfully rolled out

kubectl exec privesc-test -n ex-5-2 -- su root || true

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Privileged Exec Attempt"
# Expected: alert line containing pod name, namespace, and additional context fields
# The output should include more than just proc=%proc.name
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Privileged Exec Attempt" | grep "ex-5-2"
# Expected: at least one line showing the ex-5-2 namespace
```

---

### Exercise 5.3

**Objective:** A Falco DaemonSet pod is in CrashLoopBackOff because a custom rules file has a syntax error. Diagnose the failure and fix the rules file so the DaemonSet comes back up cleanly.

**Setup:**

```bash
cat > /tmp/ex-5-3-rules.yaml <<'EOF'
customRules:
  ex_5_3_rules.yaml: |-
    - list: sensitive_dirs
      items: [/etc, /root, /home]

    - macro: sensitive_dir_access
      condition: fd.directory in (sensitive_dirs)

    - rule: Sensitive Dir Read
      desc: A process read from a sensitive directory
      condition: >
        evt.type = open and evt.dir = < and
        container != host and
        sensitive_dir_access
      output: >
        Sensitive directory accessed
        (proc=%proc.name dir=%fd.directory pod=%k8s.pod.name ns=%k8s.ns.name
      priority: WARNING
      tags: [container, filesystem]
EOF

helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-5-3-rules.yaml \
  --version 4.7.2
```

**Task:** The Falco DaemonSet will fail to start after this upgrade. The configuration above has one or more problems. Diagnose what is wrong by reading the pod logs. Fix all errors in the rules file and re-apply the upgrade so the Falco DaemonSet returns to Running status.

**Verification:**

```bash
kubectl get pods -n falco
# Expected: Falco pod is Running (not CrashLoopBackOff)

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20
# Expected: no ERROR or FATAL lines about rule parse failures

kubectl create namespace ex-5-3
kubectl run dir-test -n ex-5-3 --image=alpine:3.20 --restart=Never -- sleep 3600
kubectl wait --for=condition=Ready pod/dir-test -n ex-5-3 --timeout=60s

kubectl exec dir-test -n ex-5-3 -- ls /root || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep "Sensitive Dir Read"
# Expected: alert line present
```

---

## Cleanup

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 \
  ex-2-1 ex-2-2 ex-2-3 \
  ex-3-1 ex-3-2 ex-3-3 \
  ex-4-1 ex-4-2 ex-4-3 \
  ex-5-1 ex-5-2 ex-5-3 2>/dev/null || true
```

To restore Falco to a clean default state after the exercises:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --version 4.7.2 \
  --set driver.kind=ebpf \
  --set tty=true
kubectl rollout status daemonset/falco -n falco
```

## Key Takeaways

This assignment covered the complete Falco workflow for a CKA/CKS candidate: installing Falco with the eBPF probe in a kind cluster, understanding the structure of rules, macros, and lists, reading alert output to correlate events with pods and namespaces, writing custom rules using the condition language fields that appear on the exam, overriding built-in rules with `enabled: false` and `append: true`, and tuning rules to reduce false positives without losing detection coverage. The debugging exercises emphasized reading Falco pod logs to identify parse errors and logic errors, which is the diagnostic skill the exam tests when it presents a broken runtime security configuration.
