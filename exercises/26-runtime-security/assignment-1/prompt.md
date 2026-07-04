# Assignment Prompt: Runtime Security — Assignment 1

**Series:** Runtime Security (1 of 2)
**Topic slug:** runtime-security
**Topic directory:** exercises/26-runtime-security/assignment-1/

## Metadata

**Domain:** CKS — Monitoring, Logging and Runtime Security (20%)
**Competencies:** Falco architecture, rule authoring, alert output, threat detection
**Prerequisites:** 13-security-contexts/assignment-1, 01-pods/assignment-1

## Scope — In Scope

*Falco architecture*
- What Falco is: a runtime security tool that monitors system calls and Kubernetes API events
- The eBPF probe (preferred in kind over the kernel module): how it intercepts syscalls at the kernel level
- The rules engine: evaluating conditions against syscall events in real time
- falco.yaml: configuration file (rules_file, output channels, log level)
- Running Falco as a DaemonSet in the kind cluster

*Rule structure*
- Top-level fields: rule (name), desc (description), condition (filter expression), output (alert format string), priority (EMERGENCY/ALERT/CRITICAL/ERROR/WARNING/NOTICE/INFORMATIONAL/DEBUG), tags
- Macros: reusable condition fragments (`macro: is_interactive_session`)
- Lists: reusable value sets (`list: shell_binaries`)
- The condition language: evt.type (syscall name), proc.name, proc.args, fd.name (file descriptor path), container.id, container.name, k8s.pod.name, k8s.ns.name
- Logical operators in conditions: and, or, not, in, contains, startswith

*Built-in rules*
- Terminal shell in container: spawning a shell (bash, sh, zsh) inside a container
- Sensitive file opened for reading: reading /etc/shadow, /etc/passwd by unexpected processes
- Write below binary dir: writing to /bin, /usr/bin, /sbin
- Contact K8S API Server From Container: unexpected API server calls from inside a container
- Reading and understanding the default ruleset: falco --list to see available fields

*Writing custom rules*
- Defining a macro for reuse
- Defining a list of allowed process names
- Writing a rule that triggers on a specific file path access
- Writing a rule that triggers on an unexpected binary execution in a container
- Using container.id != host to scope rules to containers only

*Overriding and tuning*
- append: true to add conditions to an existing rule without replacing it
- enabled: false to disable a noisy built-in rule
- Adjusting priority level of a rule

*Falco outputs and alert format*
- Output format string: using %proc.name, %container.name, %fd.name, %k8s.pod.name in the output field
- Configuring file output in falco.yaml: output.file.enabled, output.file.filename
- stdout output for development/debugging
- Reading a Falco alert: time, priority, rule name, output string

*Triggering and observing alerts*
- kubectl exec into a pod and run bash: observe the Terminal shell in container alert
- kubectl exec and cat /etc/shadow: observe the sensitive file rule
- Confirming the alert appears in Falco logs/output

## Scope — Out of Scope

- Kubernetes audit logging: covered in runtime-security/assignment-2
- Falco sidekick (webhook forwarding): out of scope
- AppArmor and seccomp profiles: covered in 28-system-hardening
- Immutable container patterns: covered in runtime-security/assignment-2

## Environment

Single-node kind cluster with Falco installed as a DaemonSet using the eBPF probe. The tutorial must include Falco installation steps using the official Helm chart (falcosecurity/falco with the --set driver.kind=ebpf flag). The exercises verify alert output by reading Falco pod logs.

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- All custom rules must be syntactically valid Falco rule YAML. Test by tracing condition logic manually.
- Tutorial namespace: `tutorial-runtime-security`.
- Exercise setups that trigger alerts intentionally (exec into pod, read sensitive file) must include the trigger commands so the learner knows what to run to produce the alert.

## Exercise Distribution

- Level 1: Read Falco logs after a shell exec event, identify the rule that fired, describe what triggered it
- Level 2: Write a custom macro and rule; disable a noisy built-in rule; change a rule priority
- Level 3 (debugging): Bare headings. Broken rules (condition syntax error, rule never triggers because condition is too specific, output format string with wrong field name)
- Level 4: Write a complete custom ruleset for a threat scenario (unexpected process execution, unexpected outbound connection, sensitive file access); apply and verify alerts fire
- Level 5 (debugging): A rule is firing too broadly (generating noise for legitimate operations); tune the condition to allow expected behavior while still catching the threat
