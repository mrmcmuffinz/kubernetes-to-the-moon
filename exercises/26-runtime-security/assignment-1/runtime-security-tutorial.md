# Runtime Security Tutorial: Falco Threat Detection

## Introduction

Runtime security is the practice of detecting and responding to threats while workloads are actively running, as opposed to catching misconfigurations before deployment. Kubernetes admission controllers and security policies can prevent many classes of misconfiguration at creation time, but they cannot observe what happens inside a container once it is running. A container image that passes every policy check at admission can still have a process execution, a file read, or a network connection that violates your expectations at runtime. Falco fills that gap by hooking into the Linux kernel using either a loadable kernel module or an eBPF program, intercepting every system call from every container, and evaluating those calls against a rule engine in real time.

For the CKA and CKS exams, Falco is the canonical runtime security tool. The exam expects you to understand how Falco is deployed, how its rules are structured, how to write and modify rules, and how to observe alerts. This tutorial builds a complete workflow: you will install Falco using the eBPF probe (which is compatible with kind's rootless containerd setup), explore the default ruleset, write custom rules for specific threat behaviors, tune rules to reduce false positives, and trigger alerts intentionally so you can read and understand the output format.

## Prerequisites

This tutorial uses a single-node kind cluster. Create one using the instructions at [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster). You also need Helm installed on your workstation; if it is not present, install it with `curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash`. The tutorial uses kubectl and nerdctl; both are assumed to be available.

## Installing Falco as a DaemonSet with the eBPF Probe

Falco runs as a DaemonSet so that it monitors system calls on every node. In a standard Linux environment you would use the kernel module driver, but kind clusters run inside containers and the kernel module driver requires loading a module into the host kernel, which is often blocked in container environments. The eBPF probe is the supported alternative: it uses a BPF program that the Falco DaemonSet loads into the host kernel directly, without a loadable module, and it works correctly in kind.

Add the Falco Helm repository and install with the eBPF driver:

```bash
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set driver.kind=ebpf \
  --set tty=true \
  --version 4.7.2
```

The `driver.kind=ebpf` flag tells Falco to use the eBPF probe. The `tty=true` flag keeps stdout output readable in log streams. Wait for the DaemonSet pod to reach Running status:

```bash
kubectl get pods -n falco -w
```

Once the pod is Running, verify that Falco is producing output:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20
```

You should see lines like `Falco initialized. One or more rules loaded.` and the list of loaded rule files. If the pod is in CrashLoopBackOff, the eBPF probe failed to load; in kind this is almost always a permissions issue. Run `kubectl describe pod -n falco -l app.kubernetes.io/name=falco` and look at the Events section for details.

## Falco Configuration Files

Falco's behavior is controlled by two categories of files: the main configuration file (`falco.yaml`) and one or more rule files. In the Helm deployment, `falco.yaml` is provided as a ConfigMap and the default rules ship inside the container image under `/etc/falco/`. You can supply additional rules files via the `customRules` value in the Helm chart.

The `falco.yaml` configuration controls:

| Field | What it does | Default |
|---|---|---|
| `rules_file` | List of rule file paths to load | `/etc/falco/falco_rules.yaml` and `/etc/falco/falco_rules.local.yaml` |
| `json_output` | Emit alerts as JSON instead of text | `false` |
| `log_stderr` | Write Falco's own log to stderr | `true` |
| `log_syslog` | Write to syslog | `true` |
| `priority` | Minimum priority level to emit | `debug` |
| `buffered_outputs` | Buffer alert output for throughput | `false` |

Rule files are loaded in the order listed in `rules_file`. If two rules share the same name, the later file's definition wins unless `append: true` is used.

## The Falco Rule File Structure

A Falco rule file is a YAML document containing a list of items. Each item is one of three types: a `rule`, a `macro`, or a `list`. Understanding all three is essential for writing rules that are readable and maintainable.

### Lists

A list is a named collection of values you can reference in conditions and macros. Lists exist so you can define a set of allowed or disallowed values once and reference it by name everywhere:

```yaml
- list: shell_binaries
  items: [bash, sh, zsh, dash, fish]
```

You reference the list in a condition with the `in` operator: `proc.name in (shell_binaries)`. The parentheses around the list name are required.

### Macros

A macro is a reusable condition fragment. It gives a name to a condition expression so you can compose complex conditions from readable pieces:

```yaml
- macro: container
  condition: container.id != host

- macro: spawned_process
  condition: evt.type = execve and evt.dir = <
```

The `container.id != host` condition is how Falco distinguishes events inside containers from events on the host. The value `host` is a special sentinel meaning the host PID namespace. The `evt.dir = <` part of `spawned_process` filters to the syscall exit direction (the `<` means "exit"), which is when the process has finished spawning and its metadata is available.

### Rules

A rule binds a condition to an output format and a priority:

```yaml
- rule: Terminal Shell in Container
  desc: A shell was used as the entrypoint or as a child process in a container
  condition: >
    spawned_process and container and
    proc.name in (shell_binaries) and
    terminal.isatty = true
  output: >
    Shell spawned in container
    (user=%user.name container=%container.name pod=%k8s.pod.name
     ns=%k8s.ns.name shell=%proc.name parent=%proc.pname)
  priority: WARNING
  tags: [container, shell, mitre_execution]
```

The fields of a rule and their behavior when misconfigured:

| Field | What it does | Valid values | Default | Failure mode if missing or wrong |
|---|---|---|---|---|
| `rule` | Unique name for the rule | Any string | Required | File load error if missing |
| `desc` | Human-readable description | Any string | Required | File load error if missing |
| `condition` | Filter expression evaluated per syscall event | Falco condition language | Required | File load error if missing; logic error if wrong |
| `output` | Alert message format string | String with `%field.name` substitutions | Required | File load error if missing; garbled output if field name is wrong |
| `priority` | Severity level | EMERGENCY, ALERT, CRITICAL, ERROR, WARNING, NOTICE, INFORMATIONAL, DEBUG | Required | File load error if missing |
| `tags` | Optional categorization | List of strings | `[]` | No effect if omitted; ignored at runtime |
| `enabled` | Whether the rule is active | `true`, `false` | `true` | Set to `false` to suppress a noisy built-in rule |
| `append` | Add to an existing rule's condition or output | `true`, `false` | `false` | If `true` on a rule that does not exist, load error |

### The Condition Language

Falco conditions are boolean expressions evaluated against event metadata. The most important fields are:

| Field | Meaning | Example value |
|---|---|---|
| `evt.type` | System call name | `execve`, `open`, `connect`, `write` |
| `evt.dir` | Syscall direction | `<` (exit/return), `>` (entry) |
| `proc.name` | Process name | `bash`, `python3`, `curl` |
| `proc.args` | Process argument string | `/etc/shadow` |
| `proc.pname` | Parent process name | `kubelet`, `containerd-shim` |
| `fd.name` | File descriptor path | `/etc/shadow`, `/bin/bash` |
| `fd.directory` | Directory portion of `fd.name` | `/etc`, `/bin` |
| `user.name` | Username of the process owner | `root`, `nobody` |
| `container.id` | Container ID, or `host` for the host | `a3f2b1c0d4e5` |
| `container.name` | Container name | `nginx`, `myapp` |
| `k8s.pod.name` | Kubernetes pod name | `nginx-abc123` |
| `k8s.ns.name` | Kubernetes namespace | `production`, `kube-system` |
| `terminal.isatty` | Whether a terminal is attached | `true`, `false` |

Operators: `=`, `!=`, `<`, `>`, `<=`, `>=`, `in` (list membership), `contains` (substring), `startswith` (prefix), `and`, `or`, `not`.

Common condition pitfalls: forgetting `evt.dir = <` means your condition matches both the syscall entry and exit and may double-fire. Using `evt.type = open` without a directory or file filter matches every file open in the entire system. Always combine type filters with scope filters.

## Creating the Tutorial Namespace

```bash
kubectl create namespace tutorial-runtime-security
```

## Exploring Built-in Rules

The default Falco rule set ships with several hundred rules covering common attack patterns. You can list all rules and their metadata:

```bash
# List rules available in the Falco pod
kubectl exec -n falco -l app.kubernetes.io/name=falco -- \
  falco --list -o short 2>/dev/null | head -50
```

Three built-in rules are worth understanding in detail because the exercises will use them:

**Terminal Shell in Container** fires when a process with `terminal.isatty = true` is spawned with a shell binary inside a container. This catches `kubectl exec -it ... -- bash` sessions.

**Read sensitive file untrusted** fires when `/etc/shadow` or `/etc/passwd` is opened by a process that is not an expected system tool. The built-in macro `sensitive_files` defines the path list and `trusted_programs` defines the allowed process list.

**Write below binary dir** fires when a process writes to a path under `/bin`, `/usr/bin`, or `/sbin`. This catches in-container file tampering that would modify the executable environment.

## Triggering a Built-in Rule

Deploy a test pod and trigger the terminal shell rule:

```bash
kubectl run trigger-pod -n tutorial-runtime-security \
  --image=busybox:1.36 \
  --restart=Never \
  -- sleep 3600
```

Wait for the pod to be Running:

```bash
kubectl get pod trigger-pod -n tutorial-runtime-security
# Expected: STATUS Running
```

Now trigger the Terminal Shell in Container rule:

```bash
kubectl exec -it trigger-pod -n tutorial-runtime-security -- sh
```

Inside the shell, type `exit` to leave. Then read the Falco log:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=30
```

You should see an alert line resembling:

```text
07:23:14.881932891: Warning Shell spawned in container
(user=root container=trigger-pod pod=trigger-pod ns=tutorial-runtime-security
 shell=sh parent=runc)
```

The alert format shows the time, priority level, rule name (encoded in the output string), and the output fields substituted with their runtime values.

Now trigger the sensitive file rule:

```bash
kubectl exec trigger-pod -n tutorial-runtime-security -- cat /etc/shadow
```

Check the Falco log again; you should see an alert for the sensitive file read. If the alert does not appear, check that the Falco pod is still Running and that you are reading the correct pod logs.

## Writing a Custom Rule

Custom rules are injected via the `customRules` Helm value. Create a values file:

```bash
cat > /tmp/falco-custom-rules.yaml <<'EOF'
customRules:
  custom_rules.yaml: |-
    - list: monitored_binaries
      items: [curl, wget, nc, ncat, nmap]

    - macro: outbound_tool_in_container
      condition: >
        evt.type = execve and evt.dir = < and
        container.id != host and
        proc.name in (monitored_binaries)

    - rule: Suspicious Outbound Tool in Container
      desc: A network reconnaissance or download tool was executed inside a container
      condition: outbound_tool_in_container
      output: >
        Network tool executed in container
        (tool=%proc.name pod=%k8s.pod.name ns=%k8s.ns.name
         user=%user.name args=%proc.args)
      priority: WARNING
      tags: [container, network, custom]
EOF
```

Apply the custom rules by upgrading the Helm release:

```bash
helm upgrade falco falcosecurity/falco \
  --namespace falco \
  --reuse-values \
  --values /tmp/falco-custom-rules.yaml \
  --version 4.7.2
```

Wait for the DaemonSet to roll out the updated pod:

```bash
kubectl rollout status daemonset/falco -n falco
```

Verify the custom rule loaded:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=10
# Look for: Loading rules from file /etc/falco/custom_rules.yaml
```

Trigger the custom rule:

```bash
kubectl exec trigger-pod -n tutorial-runtime-security -- wget -q -O /dev/null http://example.com || true
```

Read the log to see the alert:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco --tail=20
```

## Overriding Built-in Rules

### Disabling a Rule

To disable a built-in rule, add an override that sets `enabled: false`. This is useful when a rule fires on legitimate operations in your environment:

```yaml
customRules:
  disable_rules.yaml: |-
    - rule: Terminal Shell in Container
      enabled: false
      override:
        enabled: replace
```

### Appending to a Condition

Use `append: true` with an `override` block to add exceptions to an existing rule's condition without replacing the whole rule. This is the safest way to tune a built-in rule:

```yaml
customRules:
  append_rules.yaml: |-
    - rule: Write below binary dir
      condition: and not k8s.ns.name = "tutorial-runtime-security"
      override:
        condition: append
```

This appends ` and not k8s.ns.name = "tutorial-runtime-security"` to the existing condition, suppressing alerts from that namespace only.

### Changing a Rule's Priority

To raise or lower the priority of an existing rule:

```yaml
customRules:
  priority_rules.yaml: |-
    - rule: Terminal Shell in Container
      priority: CRITICAL
      override:
        priority: replace
```

## Reading Falco Alert Output

A Falco alert line has a fixed structure:

```text
<timestamp>: <Priority> <output string with substituted fields>
```

With JSON output enabled (`--set falco.jsonOutput=true` in Helm values), each alert is a structured JSON object:

```json
{
  "output": "Shell spawned in container ...",
  "priority": "Warning",
  "rule": "Terminal Shell in Container",
  "source": "syscall",
  "tags": ["container", "shell", "mitre_execution"],
  "time": "2024-01-15T07:23:14.881932891Z",
  "output_fields": {
    "container.name": "trigger-pod",
    "k8s.ns.name": "tutorial-runtime-security",
    "proc.name": "sh"
  }
}
```

JSON output makes it easy to filter alerts with `jq`:

```bash
kubectl logs -n falco -l app.kubernetes.io/name=falco | \
  jq -r 'select(.priority == "Warning") | "\(.time) \(.rule)"'
```

## Cleanup

```bash
kubectl delete namespace tutorial-runtime-security
```

The Falco DaemonSet and namespace remain installed for the homework exercises. If you want to remove Falco entirely after finishing the assignment:

```bash
helm uninstall falco -n falco
kubectl delete namespace falco
```

## Reference Commands

| Task | Command |
|---|---|
| Install Falco with eBPF | `helm install falco falcosecurity/falco -n falco --create-namespace --set driver.kind=ebpf --version 4.7.2` |
| Upgrade with custom rules | `helm upgrade falco falcosecurity/falco -n falco --reuse-values --values <file>` |
| Watch Falco logs | `kubectl logs -n falco -l app.kubernetes.io/name=falco -f` |
| List available fields | `kubectl exec -n falco -l app.kubernetes.io/name=falco -- falco --list` |
| Check DaemonSet rollout | `kubectl rollout status daemonset/falco -n falco` |
| Trigger shell alert | `kubectl exec -it <pod> -- sh` |
| Trigger file read alert | `kubectl exec <pod> -- cat /etc/shadow` |
| Filter JSON alerts with jq | `kubectl logs -n falco ... \| jq 'select(.rule == "...")'` |
