# Runtime Security Homework Answers — Assignment 1: Falco Threat Detection

---

## Exercise 1.1 Solution

Run an interactive shell in the pod and then read the Falco log:

```bash
kubectl exec -it shell-test -n ex-1-1 -- sh
# type exit

kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "shell-test"
```

The Falco alert line for this exercise looks like:

```text
07:23:14.881932891: Warning Shell spawned in container
(user=root container=shell-test pod=shell-test ns=ex-1-1 shell=sh parent=containerd-shim)
```

The rule that fired is `Terminal Shell in Container`. The priority is `Warning`. The output fields identify the shell binary (`sh`), the pod name (`shell-test`), and the namespace (`ex-1-1`). The `parent=containerd-shim` field shows that the shell's parent process is the container runtime shim, confirming the shell was spawned as an exec rather than as the container entrypoint.

---

## Exercise 1.2 Solution

```bash
kubectl exec secret-reader -n ex-1-2 -- cat /etc/shadow
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "shadow"
```

The alert identifies the file path `/etc/shadow` in the output. The built-in rule that fires is `Read sensitive file untrusted` (exact name may vary slightly between Falco versions; look for a line containing `shadow` or `sensitive`). The alert's file field shows `/etc/shadow`, confirming which access triggered the rule. Note that `cat` reading `/etc/shadow` fires the rule because `cat` is not in Falco's built-in `trusted_programs` list for shadow file access.

---

## Exercise 1.3 Solution

```bash
kubectl exec baseline-reader -n ex-1-3 -- cat /etc/hostname
kubectl exec baseline-reader -n ex-1-3 -- cat /etc/passwd
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=40 | grep "baseline-reader"
```

Only the `/etc/passwd` read produces an alert. The `/etc/hostname` read does not appear in the log because it is not in the sensitive files list. This demonstrates that Falco's built-in sensitive file rule is scoped to specific paths (`/etc/shadow`, `/etc/passwd`, and a few others), not to the entire `/etc` directory. Understanding this specificity is important for knowing when to write additional custom rules for other paths you want to monitor.

---

## Exercise 2.1 Solution

Create the values file:

```yaml
customRules:
  ex_2_1_rules.yaml: |-
    - rule: Curl Executed in Container
      desc: The curl binary was executed inside a container
      condition: >
        evt.type = execve and evt.dir = < and
        container.id != host and
        proc.name = curl
      output: >
        Curl executed in container
        (pod=%k8s.pod.name ns=%k8s.ns.name user=%user.name args=%proc.args)
      priority: WARNING
      tags: [container, network, custom]
```

Apply it:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-2-1-rules.yaml \
  --version 4.7.2

kubectl rollout status daemonset/falco -n falco
kubectl exec curl-test -n ex-2-1 -- curl -s -o /dev/null http://example.com || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Curl Executed in Container"
```

The condition uses `evt.type = execve and evt.dir = <` to match the syscall exit point after the process has been created and its metadata (`proc.name`, `k8s.pod.name`) is available. Using `evt.dir = >` (entry) would not have `proc.name` populated yet for the new process, and omitting `evt.dir` entirely causes the rule to evaluate twice per execve (entry and exit), which may double the alert count.

---

## Exercise 2.2 Solution

The correct override syntax using Helm values:

```yaml
customRules:
  ex_2_2_rules.yaml: |-
    - rule: Terminal Shell in Container
      enabled: false
      override:
        enabled: replace
```

Apply:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-2-2-rules.yaml \
  --version 4.7.2

kubectl rollout status daemonset/falco -n falco
```

After the rollout, running `kubectl exec -it no-alert-shell -n ex-2-2 -- sh` no longer produces a `Terminal Shell in Container` alert. The `override.enabled: replace` instruction replaces the existing `enabled: true` value in the built-in rule with `false`. If you omit the `override` block, newer versions of Falco will reject the rule as a duplicate definition rather than treating it as an override. Always use the `override` block when modifying a built-in rule's fields.

---

## Exercise 2.3 Solution

```yaml
customRules:
  ex_2_3_rules.yaml: |-
    - rule: Write below binary dir
      priority: CRITICAL
      override:
        priority: replace
```

Apply:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-2-3-rules.yaml \
  --version 4.7.2

kubectl rollout status daemonset/falco -n falco
kubectl exec write-test -n ex-2-3 -- sh -c "echo test > /usr/bin/testfile && rm /usr/bin/testfile" || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep -i "binary dir" | grep -i "critical"
```

The alert now shows `Critical` instead of the default priority. Priority changes are useful for integrating Falco with alerting systems that route on severity, since a `Critical` alert can go to a pager while a `Warning` goes to a ticket queue.

---

## Exercise 3.1 Solution

### Diagnosis

Load the rules and try to trigger the alert:

```bash
kubectl exec -it debug-shell -n ex-3-1 -- sh
# exit
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Detect Shell in Container"
# No output
```

Check whether Falco loaded the rule without errors:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep -i "error\|warn\|rule"
```

The rule loads without a parse error, but the alert never fires. This means the condition logic is syntactically valid but logically wrong. Inspect the condition carefully:

```yaml
condition: >
  evt.type = execve and
  proc.name in (shell_binaries) and
  container.id != host
```

The condition references `shell_binaries`, which is a built-in Falco list. That part is correct. However, the condition is missing `evt.dir = <`. Without this filter, Falco evaluates the condition at both the entry (`>`) and exit (`<`) of the execve syscall. At entry, `proc.name` reflects the process that is calling execve (the parent), not the new process being spawned. The new shell's `proc.name` is only available at exit. In some Falco versions and configurations, the missing direction filter causes the condition to evaluate against the caller's process name rather than the spawned shell, so the `in (shell_binaries)` check never matches.

### Bug

The condition is missing `evt.dir = <`, which means the rule may evaluate at syscall entry before the new process name is set, causing the condition to never match the shell binary name.

### Fix

```yaml
customRules:
  ex_3_1_fixed.yaml: |-
    - rule: Detect Shell in Container
      desc: A shell process was started inside a container
      condition: >
        evt.type = execve and evt.dir = < and
        proc.name in (shell_binaries) and
        container.id != host
      output: >
        Shell in container
        (shell=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: WARNING
      tags: [container, shell]
```

Apply:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-3-1-fixed.yaml \
  --version 4.7.2
kubectl rollout status daemonset/falco -n falco
kubectl exec -it debug-shell -n ex-3-1 -- sh
# exit
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep "Detect Shell in Container"
```

---

## Exercise 3.2 Solution

### Diagnosis

The rule condition uses `evt.type = open`. Check whether the alert fires:

```bash
kubectl exec shadow-debug -n ex-3-2 -- cat /etc/shadow || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Shadow File Access"
# No output
```

Also check whether Falco reports an error loading the rule:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | grep -i "error\|fail"
```

Look at the output format field:

```yaml
output: >
  Shadow file opened
  (proc=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name file=%fd.filepath)
```

The field `%fd.filepath` does not exist. The correct field is `%fd.name`. A nonexistent field name does not prevent the rule from loading, but it may produce an empty or literal substitution in the output. The more critical issue is that on modern Linux kernels and with the eBPF probe, `cat /etc/shadow` may use the `openat` syscall rather than `open`. The condition `evt.type = open` misses `openat` entirely.

### Bug

Two problems. First, `evt.type = open` does not match `openat`, which is what `cat` uses on modern kernels. Second, the output field `%fd.filepath` is not a valid Falco field; it should be `%fd.name`.

### Fix

```yaml
customRules:
  ex_3_2_fixed.yaml: |-
    - rule: Shadow File Access
      desc: A process read the shadow password file inside a container
      condition: >
        evt.type in (open, openat, openat2) and
        evt.dir = < and
        fd.name = /etc/shadow and
        container.id != host
      output: >
        Shadow file opened
        (proc=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name file=%fd.name)
      priority: CRITICAL
      tags: [container, credentials]
```

Apply and verify:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-3-2-fixed.yaml \
  --version 4.7.2
kubectl rollout status daemonset/falco -n falco
kubectl exec shadow-debug -n ex-3-2 -- cat /etc/shadow || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep "Shadow File Access"
```

---

## Exercise 3.3 Solution

### Diagnosis

Load the rules and trigger the behavior:

```bash
kubectl exec bindir-debug -n ex-3-3 -- sh -c "echo x > /usr/bin/debug-probe && rm /usr/bin/debug-probe" || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30 | grep "Binary Dir Write Alert"
```

If the Falco pod is in CrashLoopBackOff, read the logs for a parse error. If it is Running but alerts show garbled output, the problem is in the output string. The output format string is:

```yaml
output: >
  Write to binary directory
  (proc=%process.name pod=%k8s.pod.label ns=%k8s.ns.name path=%fd.path)
```

Three invalid fields are present:
- `%process.name` is not a valid field; the correct field is `%proc.name`.
- `%k8s.pod.label` is not a valid field; the correct field is `%k8s.pod.name` (to get the pod name) or `%k8s.pod.labels` (to get all labels as a key=value string).
- `%fd.path` is not a valid field; the correct field is `%fd.name`.

### Bug

Three invalid field names in the output format string: `%process.name`, `%k8s.pod.label`, and `%fd.path`. Falco will either fail to load the rule or emit literal null/empty values for these fields depending on the version.

### Fix

```yaml
customRules:
  ex_3_3_fixed.yaml: |-
    - rule: Binary Dir Write Alert
      desc: A process wrote to a binary directory inside a container
      condition: >
        evt.type in (write, open) and
        evt.dir = < and
        fd.directory in (/bin, /usr/bin, /sbin) and
        container.id != host
      output: >
        Write to binary directory
        (proc=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name path=%fd.name)
      priority: ERROR
      tags: [container, filesystem]
```

Apply and verify:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-3-3-fixed.yaml \
  --version 4.7.2
kubectl rollout status daemonset/falco -n falco
kubectl exec bindir-debug -n ex-3-3 -- sh -c "echo x > /usr/bin/debug-probe && rm /usr/bin/debug-probe" || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep "Binary Dir Write Alert"
```

The alert output should now show the correct process name, pod name, namespace, and file path.

---

## Exercise 4.1 Solution

```yaml
customRules:
  ex_4_1_rules.yaml: |-
    - list: allowed_app_processes
      items: [nginx, sh, pause]

    - list: recon_tools
      items: [wget, curl, nc]

    - rule: Unexpected Process in App Container
      desc: A process not in the expected list was executed in the application namespace
      condition: >
        evt.type = execve and evt.dir = < and
        container.id != host and
        k8s.ns.name = "ex-4-1" and
        not proc.name in (allowed_app_processes)
      output: >
        Unexpected process in app container
        (proc=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: WARNING
      tags: [container, process]

    - rule: Sensitive Config Read in App
      desc: A process read from the nginx configuration directory
      condition: >
        evt.type in (open, openat, openat2) and evt.dir = < and
        container.id != host and
        k8s.ns.name = "ex-4-1" and
        fd.directory startswith /etc/nginx
      output: >
        Nginx config file accessed
        (proc=%proc.name file=%fd.name pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: NOTICE
      tags: [container, filesystem]

    - rule: Recon Tool in App
      desc: A network reconnaissance tool was executed in the application namespace
      condition: >
        evt.type = execve and evt.dir = < and
        container.id != host and
        k8s.ns.name = "ex-4-1" and
        proc.name in (recon_tools)
      output: >
        Recon tool executed in app container
        (tool=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name args=%proc.args)
      priority: WARNING
      tags: [container, network]
```

Apply and trigger:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-4-1-rules.yaml \
  --version 4.7.2
kubectl rollout status daemonset/falco -n falco
kubectl exec app-workload -n ex-4-1 -- python3 --version || true
kubectl exec app-workload -n ex-4-1 -- cat /etc/nginx/nginx.conf
kubectl exec app-workload -n ex-4-1 -- wget -q -O /dev/null http://example.com || true
```

Note that the `allowed_app_processes` list includes `pause` because the pause container in every pod will briefly run and its process name would otherwise trigger the unexpected-process rule. Tuning lists to include expected system processes is a normal part of Falco rule development.

---

## Exercise 4.2 Solution

```yaml
customRules:
  ex_4_2_rules.yaml: |-
    - macro: container_in_ex42
      condition: container.id != host and k8s.ns.name = "ex-4-2"

    - rule: Shell in Ex42
      desc: A shell was spawned in namespace ex-4-2
      condition: spawned_process and container_in_ex42 and proc.name in (shell_binaries)
      output: >
        Shell in ex-4-2
        (shell=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: WARNING
      tags: [container, shell]

    - rule: File Write in Ex42
      desc: A process wrote to a file in namespace ex-4-2
      condition: >
        evt.type = write and evt.dir = < and
        container_in_ex42
      output: >
        File write in ex-4-2
        (proc=%proc.name file=%fd.name pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: NOTICE
      tags: [container, filesystem]
```

The `container_in_ex42` macro captures the scoping condition (`container.id != host and k8s.ns.name = "ex-4-2"`) in one place. Both rules reference the macro, so if you ever need to change the scoping (for example, to add a second namespace), you change the macro once rather than every rule. This is the correct use of macros: extracting reusable condition fragments that would otherwise be repeated verbatim.

---

## Exercise 4.3 Solution

Enable JSON output:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --set falco.jsonOutput=true \
  --version 4.7.2
kubectl rollout status daemonset/falco -n falco
```

Trigger an alert and filter with jq:

```bash
kubectl exec -it json-test -n ex-4-3 -- sh
# exit
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 | \
  jq -r 'select(.output_fields["k8s.ns.name"] == "ex-4-3") | .rule'
```

Expected output: `Terminal Shell in Container`. With JSON output enabled, each Falco alert is a complete JSON object with `rule`, `priority`, `time`, `output`, and `output_fields` keys. The `output_fields` object contains every `%field` substitution as a key-value pair, making it straightforward to filter and correlate alerts programmatically. This is the format used by Falco Sidekick and most SIEM integrations.

---

## Exercise 5.1 Solution

### Diagnosis

The `health-monitor` pod runs `ping` every 30 seconds as part of its legitimate monitoring loop. The `Network Tool Execution` rule fires on `ping` because `ping` is in the `network_tools` list. To suppress the false positives, you need a condition that allows `ping` specifically when it comes from a pod labeled `role=monitor`, while still alerting on `ping` from unlabeled pods and on all other network tools from any pod.

Falco does not have a built-in field for individual pod label values in all versions. A practical approach is to use `k8s.pod.labels` (the full labels string) and the `contains` operator, or to restructure the list and condition to separate `ping` from the other tools.

### Fix

The cleanest solution splits the rule into two: one for general recon tools (no exception needed), and one for `ping` that excludes pods labeled `role=monitor`:

```yaml
customRules:
  ex_5_1_tuned.yaml: |-
    - list: hard_recon_tools
      items: [wget, curl, nc, ncat, nmap]

    - rule: Network Tool Execution
      desc: A network tool was executed inside a container
      condition: >
        evt.type = execve and evt.dir = < and
        container.id != host and
        proc.name in (hard_recon_tools)
      output: >
        Network tool in container
        (tool=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: WARNING
      tags: [container, network]

    - rule: Ping in Non-Monitor Container
      desc: The ping tool was executed in a container that is not a monitoring pod
      condition: >
        evt.type = execve and evt.dir = < and
        container.id != host and
        proc.name = ping and
        not k8s.pod.labels contains "role:monitor"
      output: >
        Ping executed in non-monitor container
        (pod=%k8s.pod.name ns=%k8s.ns.name user=%user.name)
      priority: WARNING
      tags: [container, network]
```

Apply and verify:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-5-1-tuned.yaml \
  --version 4.7.2
kubectl rollout status daemonset/falco -n falco
```

After a 35-second wait, the `health-monitor` pod's periodic ping no longer generates alerts. The `attacker` pod's `wget` still triggers `Network Tool Execution` and its `ping` still triggers `Ping in Non-Monitor Container` because the `attacker` pod has no `role=monitor` label.

---

## Exercise 5.2 Solution

The original output string is:

```yaml
output: >
  Priv escalation attempt (proc=%proc.name)
```

A richer output showing all contextually useful fields:

```yaml
customRules:
  ex_5_2_fixed.yaml: |-
    - rule: Privileged Exec Attempt
      desc: A process was executed with arguments that look like privilege escalation
      condition: >
        evt.type = execve and evt.dir = < and
        container.id != host and
        (proc.name = sudo or proc.name = su)
      output: >
        Privilege escalation attempt in container
        (proc=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name
         parent=%proc.pname user=%user.name args=%proc.args)
      priority: CRITICAL
      tags: [container, privilege_escalation]
```

Apply:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-5-2-fixed.yaml \
  --version 4.7.2
kubectl rollout status daemonset/falco -n falco
kubectl exec privesc-test -n ex-5-2 -- su root || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep "Privileged Exec Attempt"
```

The alert now shows the pod name, namespace, parent process, user, and arguments. A security analyst can immediately see that `su root` was run in pod `privesc-test` in namespace `ex-5-2` by user `root` (the default container user), invoked from the shell that the exec session started. This context is what separates actionable alerts from noise.

---

## Exercise 5.3 Solution

### Diagnosis

After applying the upgrade, check the Falco pod status:

```bash
kubectl get pods -n falco
# Likely shows CrashLoopBackOff
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30
```

Look for error lines. Falco will print something like:

```text
FATAL Rule "Sensitive Dir Read": Could not parse rule: ...
```

or a YAML parse error pointing at a specific line. Inspect the rules file for problems:

1. The condition uses `container != host` but the correct field path is `container.id != host`. The field `container` does not exist in the Falco field schema.
2. The output string has an unclosed parenthesis: `(proc=%proc.name dir=%fd.directory pod=%k8s.pod.name ns=%k8s.ns.name` is missing the closing `)`.

### Bugs

Two bugs. First, `container != host` should be `container.id != host`. Second, the output string parenthesis is not closed.

### Fix

```yaml
customRules:
  ex_5_3_fixed.yaml: |-
    - list: sensitive_dirs
      items: [/etc, /root, /home]

    - macro: sensitive_dir_access
      condition: fd.directory in (sensitive_dirs)

    - rule: Sensitive Dir Read
      desc: A process read from a sensitive directory
      condition: >
        evt.type = open and evt.dir = < and
        container.id != host and
        sensitive_dir_access
      output: >
        Sensitive directory accessed
        (proc=%proc.name dir=%fd.directory pod=%k8s.pod.name ns=%k8s.ns.name)
      priority: WARNING
      tags: [container, filesystem]
```

Apply:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/ex-5-3-fixed.yaml \
  --version 4.7.2
kubectl rollout status daemonset/falco -n falco
# Expected: successfully rolled out

kubectl get pods -n falco
# Expected: Running

kubectl exec dir-test -n ex-5-3 -- ls /root || true
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20 | grep "Sensitive Dir Read"
```

---

## Common Mistakes

**Using `evt.type = open` instead of `evt.type in (open, openat, openat2)` for file access rules.** Modern Linux userspace programs (including `cat`, `cp`, and most utilities on Alpine and Debian) use the `openat` or `openat2` syscall rather than the original `open`. A rule that only matches `open` will silently miss most file access events on contemporary kernels. Always use the `in` form when writing file-access conditions.

**Referencing nonexistent output fields such as `%process.name`, `%fd.path`, or `%k8s.pod.label`.** Falco's output field names are exact and case-sensitive. A typo in the output string may not prevent the rule from loading, but the field substitution will produce an empty or literal null value in the alert, making the alert harder to interpret. Always verify field names against `falco --list` output or the official Falco documentation before applying a rule.

**Omitting `evt.dir = <` from execve-based rules.** The `execve` syscall has two event points: entry (`>`) when the syscall is invoked, and exit (`<`) when the new process has finished loading. The new process's `proc.name` is only available at exit. Without `evt.dir = <`, your condition evaluates against the calling process's name, which is almost never the shell or tool you want to detect. The fix is to always include `evt.dir = <` in conditions that check `proc.name` for spawned processes.

**Using `container != host` instead of `container.id != host`.** The field is `container.id`, not `container`. This typo causes a Falco parse error or a rule that never fires, and the error message may not be obvious. The special sentinel value `host` is compared against `container.id` (a string), not against a hypothetical `container` field.

**Forgetting to wait for `kubectl rollout status daemonset/falco -n falco` before triggering a rule.** After a `helm upgrade`, the old Falco pod may still be Running with the old rules while the new pod is Starting. If you trigger a rule immediately after the upgrade, the old pod may respond and the new rule may not yet be loaded. Always wait for the rollout to complete before testing rule changes.

---

## Verification Commands Cheat Sheet

| Task | Command |
|---|---|
| Watch Falco pod status | `kubectl get pods -n falco -w` |
| Stream Falco alerts | `kubectl logs -n falco -l app.kubernetes.io/name=falco -f` |
| Check last 30 alerts | `kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30` |
| Filter alerts for a pod | `kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 \| grep <pod-name>` |
| Filter by rule name | `kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=50 \| grep "<Rule Name>"` |
| Filter JSON by namespace | `kubectl logs ... \| jq 'select(.output_fields["k8s.ns.name"] == "ns")'` |
| List Falco fields | `kubectl exec -n falco -l app.kubernetes.io/name=falco -- falco --list` |
| Install Falco with eBPF | `helm install falco falcosecurity/falco -n falco --create-namespace --set driver.kind=ebpf --version 4.7.2` |
| Upgrade with custom rules | `helm upgrade falco falcosecurity/falco -n falco --reuse-values --values <file> --version 4.7.2` |
| Wait for DaemonSet rollout | `kubectl rollout status daemonset/falco -n falco` |
| Trigger shell alert | `kubectl exec -it <pod> -n <ns> -- sh` |
| Trigger shadow file alert | `kubectl exec <pod> -n <ns> -- cat /etc/shadow` |
| Trigger binary dir write | `kubectl exec <pod> -n <ns> -- sh -c "echo x > /usr/bin/probe && rm /usr/bin/probe"` |
