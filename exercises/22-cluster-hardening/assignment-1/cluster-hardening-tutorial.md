# CIS Benchmark Scanning and API Server Hardening Tutorial

## Introduction

The CIS Kubernetes Benchmark is a consensus-based set of security recommendations published by the Center for Internet Security. It translates years of collective operational experience into numbered controls, each describing a configuration the benchmark considers mandatory or strongly recommended for a secure cluster. When a third party audits your Kubernetes infrastructure or when you run your own pre-certification checks, the CIS benchmark is almost always the reference document. On the CKA and CKS exams, the cluster hardening domain tests whether you can navigate the control plane configuration and apply targeted changes to bring a cluster's security posture in line with documented guidelines.

The primary tool for automated CIS benchmark checking is kube-bench, an open-source Go program from Aqua Security that reads the API server, controller manager, scheduler, etcd, and kubelet configurations and reports each control as PASS, FAIL, WARN, or INFO. kube-bench does not make changes; it only reports. The remediation work is yours to do, and for the API server, that means editing the static pod manifest at `/etc/kubernetes/manifests/kube-apiserver.yaml` inside the kind control plane container. This tutorial walks through that complete cycle: scan, read output, back up the manifest, apply flags, verify each change, and recover from a mistake if something goes wrong.

By the end of this tutorial you will have hardened a default kind cluster's API server with five security flags, run kube-bench before and after to confirm the change in status, and practiced the recovery procedure that turns a completely unreachable API server back into a running cluster. That end-to-end competency is what the exercises in this assignment test.

## Prerequisites

You need a single-node kind cluster running with rootless nerdctl. See the [single-node kind cluster](../../../docs/cluster-setup.md#single-node-kind-cluster) section of the cluster setup document for the exact creation command. No additional components are required for this tutorial. Confirm your cluster is up before starting:

```bash
kubectl get nodes
# Expected: one node with STATUS Ready
kubectl get pods -n kube-system
# Expected: all control plane pods Running
```

## Setup

Create the tutorial namespace and confirm you can reach the cluster normally:

```bash
kubectl create namespace tutorial-cluster-hardening
kubectl get namespace tutorial-cluster-hardening
# Expected: STATUS Active
```

The tutorial namespace is used for verification tests (checking anonymous access, RBAC checks) rather than for deploying workloads, because the core work of this tutorial happens at the cluster infrastructure level.

## Part 1: Installing kube-bench

kube-bench runs best when it can read the API server configuration directly from the filesystem, which means running it inside the kind control plane container. The simplest approach for a kind cluster is to download the kube-bench binary into the container and run it there, bypassing the need to configure a Kubernetes Job with the precise volume mounts the tool requires.

Start a shell in the control plane container:

```bash
nerdctl exec -it kind-control-plane bash
```

From inside the container, download the kube-bench binary and place it in `/tmp`:

```bash
curl -sSL \
  https://github.com/aquasecurity/kube-bench/releases/download/v0.8.0/kube-bench_0.8.0_linux_amd64.tar.gz \
  -o /tmp/kube-bench.tar.gz
tar xzf /tmp/kube-bench.tar.gz -C /tmp kube-bench
chmod +x /tmp/kube-bench
/tmp/kube-bench version
# Expected: kube-bench version 0.8.0
```

Exit the container for now:

```bash
exit
```

You can also invoke kube-bench without an interactive shell using `nerdctl exec kind-control-plane bash -c "..."`. The tutorial uses both forms depending on how much output is expected.

## Part 2: Running kube-bench and Reading Output

Run kube-bench targeting the master components. The `--targets master` flag scopes the run to API server, controller manager, scheduler, and etcd:

```bash
nerdctl exec kind-control-plane bash -c "/tmp/kube-bench run --targets master 2>/dev/null"
```

The output is organized into sections. Section `[INFO]` lines are context notes. Section `[PASS]`, `[FAIL]`, and `[WARN]` lines each begin with a control ID like `1.2.1` or `1.3.4`. The first number indicates the component (1 = master, 2 = etcd, 3 = control plane in some benchmark versions). Within the master section, `1.2.x` controls apply to the API server, `1.3.x` controls apply to the controller manager, and `1.4.x` controls apply to the scheduler.

The FAIL lines are the ones you act on. Filter to just those:

```bash
nerdctl exec kind-control-plane bash -c \
  "/tmp/kube-bench run --targets master 2>/dev/null | grep '^\[FAIL\]'"
```

A fresh kind cluster will show several FAIL findings in the `1.2.x` range. Common ones include:

- `[FAIL] 1.2.1 Ensure that the --anonymous-auth argument is set to false` -- The API server defaults to allowing anonymous access, which lets anyone query unauthenticated endpoints.
- `[FAIL] 1.2.17 Ensure that the --profiling argument is set to false` -- The profiling handler is enabled by default, exposing runtime internals.
- A finding about audit logging not being configured.

WARN findings indicate controls that kube-bench cannot automatically verify (often because they require human judgment or external configuration) and are not necessarily broken. INFO findings are purely informational.

To save only the API server FAIL findings:

```bash
nerdctl exec kind-control-plane bash -c \
  "/tmp/kube-bench run --targets master 2>/dev/null | grep '^\[FAIL\]' | grep '1\.2\.' > /tmp/apiserver-fails.txt"
nerdctl exec kind-control-plane cat /tmp/apiserver-fails.txt
```

You will use this output to know which flags to set.

## Part 3: How the API Server Static Pod Manifest Works

The API server, controller manager, and scheduler in a kubeadm-provisioned cluster (including kind) run as static pods rather than regular pods. The kubelet on the control plane node watches the directory `/etc/kubernetes/manifests/` and keeps a pod running for every YAML file it finds there. When you change a file in that directory, the kubelet detects the change within a few seconds and restarts the corresponding pod with the new configuration. No `kubectl apply` is needed; the kubelet is the controller.

This design means that editing `/etc/kubernetes/manifests/kube-apiserver.yaml` is both the only supported way to change most API server flags and a significant operational risk. A YAML syntax error or an invalid flag value will cause the kubelet to crash the pod repeatedly, and since the API server is down, `kubectl` will not work until you fix the manifest. The backup-before-edit discipline is therefore not optional.

## Part 4: The Safe Editing Workflow

Every manifest edit in this tutorial and in the homework exercises follows the same four-step pattern:

1. **Back up the current manifest.** Copy it to `/tmp` before making any changes.
2. **Make the targeted change.** Add, remove, or modify exactly the flags you intend to change.
3. **Watch for the restart.** The kubelet will detect the change and restart the API server within 10 to 20 seconds.
4. **Verify the change took effect.** Confirm the flag is present in the running manifest and that the behavioral change is observable.

Open a shell in the control plane container and do the backup first:

```bash
nerdctl exec -it kind-control-plane bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
```

**Never skip the backup step.** The recovery procedure in Part 7 depends on having this file.

## Part 5: Hardening the API Server

### Understanding the Manifest Structure

The kube-apiserver.yaml manifest follows the static pod format. The `spec.containers[0].command` list contains the binary name followed by flag arguments. Every flag appears as a separate list element:

```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --advertise-address=172.18.0.2
    - --authorization-mode=Node,RBAC
    - --enable-admission-plugins=NodeRestriction
    ...
```

Adding a flag means adding a new list element in the correct position. Changing a flag value means editing the existing element's value. Removing a flag means deleting its list element. The YAML indentation must be preserved exactly or the kubelet will reject the file.

Both imperative and declarative forms exist in Kubernetes broadly, but for API server flag changes there is no imperative path. You cannot run `kubectl set apiserver-flag ...`; the only supported mechanism is editing the static pod manifest directly. This is worth understanding explicitly because the CKA exam sometimes presents static pod configuration as a kubectl operation, and knowing the real mechanism saves time.

### Flag: --anonymous-auth

**What it does:** Controls whether API requests that arrive with no credentials are treated as the anonymous user `system:anonymous` (group `system:unauthenticated`) and allowed to proceed to authorization. When true, the API server assigns the anonymous identity and passes the request to the authorizer; whether the request is ultimately permitted depends on your RBAC policy. When false, unauthenticated requests are rejected immediately with `401 Unauthorized` before reaching the authorizer.

**Valid values:** `true` or `false`.

**Default when omitted:** `true`. Anonymous access is on by default.

**Failure mode when set to false:** Health check probes from some monitoring tools that do not carry credentials will start returning 401. The cluster API itself remains fully functional for any client that presents valid credentials. The risk of leaving it on is that an attacker with network access to the API server can query the `/version`, `/api`, and other unauthenticated endpoints to gather information.

Inside the control plane container, edit the manifest with `vi`:

```bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
```

Find the command list and add `- --anonymous-auth=false` as a new list element directly after `- kube-apiserver`:

```yaml
  - command:
    - kube-apiserver
    - --anonymous-auth=false
    - --advertise-address=172.18.0.2
    ...
```

Save the file and exit `vi`. Exit the container:

```bash
exit
```

Watch for the API server to restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Wait until the pod shows `Running` again (typically 15 to 30 seconds). Press Ctrl+C once the pod is stable.

Verify the change from outside the cluster:

```bash
kubectl --as=system:anonymous auth can-i get pods -n tutorial-cluster-hardening
# expect: no

kubectl --as=system:anonymous auth can-i list namespaces
# expect: no
```

You can also verify with the kube-bench control:

```bash
nerdctl exec kind-control-plane bash -c \
  "/tmp/kube-bench run --targets master 2>/dev/null | grep '1.2.1'"
# Expected: [PASS] 1.2.1 Ensure that the --anonymous-auth argument is set to false (Automated)
```

### Flag: --profiling

**What it does:** Enables or disables the profiling HTTP handler at `/debug/pprof/`. When enabled, any entity with network access to the API server can retrieve goroutine dumps, heap profiles, CPU traces, and other runtime internals that could expose sensitive operational data or assist an attacker in understanding the cluster's internal state.

**Valid values:** `true` or `false`.

**Default when omitted:** `true`. Profiling is enabled by default.

**Failure mode when set to false:** No cluster functionality depends on the profiling endpoint. Setting it to false is entirely safe and has no observable effect on cluster operation. Setting it to true is the risky configuration.

Enter the container, back up (the existing backup is still valid if no other changes were made), and add the flag:

```bash
nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add: - --profiling=false
exit
```

Wait for the restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Verify the change is in the manifest:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --profiling=false
```

### Flag: --authorization-mode

**What it does:** Specifies which authorization plugin or plugins the API server uses to evaluate API requests after authentication. Multiple modes are listed comma-separated and checked in the listed order; the first plugin to return a definitive Allow or Deny wins. If no plugin returns a decision, the request is denied.

**Valid values:** Any combination of `Node`, `RBAC`, `ABAC`, `Webhook`, `AlwaysAllow`, and `AlwaysDeny`. The critical values for CKA and CKS are `Node,RBAC`.

**Default when omitted:** In kubeadm-provisioned clusters, `Node,RBAC` is set explicitly in the generated manifest. In some minimal cluster configurations, the default can be `AlwaysAllow`, which bypasses all access controls.

**Failure mode when misconfigured:** Using `AlwaysAllow` disables all RBAC rules; every authenticated request is permitted regardless of role bindings. Omitting `Node` from the mode list causes worker node kubelets to fail their node authorization checks, breaking node status updates and pod scheduling. Using only `RBAC` without `Node` will eventually cause nodes to appear NotReady.

Check the current value in your cluster:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --authorization-mode=Node,RBAC
```

If the value already shows `Node,RBAC`, no change is needed for this flag. To see what happens when it is misconfigured, the Level 3 exercises deliberately break this setting so you can practice the diagnostic sequence.

### Flag: --enable-admission-plugins

**What it does:** Specifies additional admission controllers to activate beyond the compiled-in default set. Admission controllers intercept API requests after authentication and authorization, before the resource is persisted, and can validate or mutate objects based on policy. The `NodeRestriction` plugin prevents worker node kubelets from modifying labels or taints on other nodes, a lateral movement defense. The `AlwaysPullImages` plugin forces every pod to always pull its container image from the registry, preventing the use of locally cached images from other namespaces.

**Valid values:** Any named admission plugin supported by the server binary. Common values for hardening: `NodeRestriction`, `AlwaysPullImages`, `PodSecurity`.

**Default when omitted:** A built-in set of plugins is always active (`NamespaceLifecycle`, `LimitRanger`, `ServiceAccount`, and others). kubeadm adds `NodeRestriction` explicitly. The default does not include `AlwaysPullImages`.

**Failure mode when misconfigured:** Adding `AlwaysPullImages` can cause pods to fail in environments with private registries if image pull secrets are not configured. Removing `NodeRestriction` creates a lateral movement risk. Specifying an invalid plugin name causes the API server to refuse to start.

To add `AlwaysPullImages` alongside the existing `NodeRestriction`:

```bash
nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Change: - --enable-admission-plugins=NodeRestriction
# To:     - --enable-admission-plugins=NodeRestriction,AlwaysPullImages
exit
```

Wait for the restart, then verify:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep enable-admission-plugins /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --enable-admission-plugins=NodeRestriction,AlwaysPullImages
```

### Flag: --audit-log-path

**What it does:** Specifies the file path where the API server writes audit log records. When set, every API request and response is recorded according to the active audit policy. Audit logging is essential for compliance, incident response, and detecting anomalous API activity. The value `-` (a single hyphen) directs audit output to stdout.

**Valid values:** Any absolute file path writable by the API server process, or `-` for stdout.

**Default when omitted:** Audit logging is disabled entirely. No API requests are recorded.

**Failure mode when misconfigured:** If the specified path exists but its parent directory does not, the API server fails to start. If the path is set but the underlying disk fills up, the API server's behavior depends on the `--audit-log-mode` setting (batch or blocking modes differ in how they handle a full disk). A common mistake is setting the path to a file inside the container filesystem without mounting a persistent host path, which means logs are lost when the API server pod restarts.

For the tutorial, write audit logs to `/var/log/kubernetes/audit.log`. This path inside the kind control plane container is on the container filesystem; in a production cluster you would mount a host path, but for learning purposes this is sufficient:

```bash
nerdctl exec -it kind-control-plane bash
mkdir -p /var/log/kubernetes
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Add: - --audit-log-path=/var/log/kubernetes/audit.log
exit
```

Wait for the restart, then verify the log file is being written:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
# Wait until Running, then Ctrl+C

nerdctl exec kind-control-plane bash -c \
  "ls -la /var/log/kubernetes/audit.log"
# Expected: a regular file with recent modification time

# Make a request to generate an audit entry
kubectl get nodes

nerdctl exec kind-control-plane bash -c \
  "tail -1 /var/log/kubernetes/audit.log | python3 -m json.tool | grep verb"
# Expected: "verb": "get" or similar
```

## Part 6: Running kube-bench After Hardening

Run kube-bench again and compare the FAIL count for the API server section:

```bash
nerdctl exec kind-control-plane bash -c \
  "/tmp/kube-bench run --targets master 2>/dev/null | grep '^\[FAIL\]' | grep '1\.2\.'"
```

The controls you addressed should now show `[PASS]`. Controls related to certificate rotation, kubelet certificate authority, and other items you did not configure will remain FAIL. The point of this exercise is not to reach zero FAIL findings in one pass but to understand the loop: scan, identify, remediate, verify.

## Part 7: Recovering from a Bad Edit

If you add an invalid flag or corrupt the YAML, the API server will fail to start and `kubectl` will become unresponsive. The recovery procedure does not require `kubectl`:

1. Open a shell in the control plane container directly:
   ```bash
   nerdctl exec -it kind-control-plane bash
   ```

2. Restore the backup you made before editing:
   ```bash
   cp /tmp/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml
   ```

3. The kubelet detects the restored file within a few seconds and restarts the API server. Wait and confirm:
   ```bash
   exit
   # Give the API server 20-30 seconds to come back up
   kubectl get pods -n kube-system -l component=kube-apiserver
   # Expected: STATUS Running
   ```

4. Once the API server is running again, re-enter the container, examine the manifest carefully, and re-apply only the correct changes.

If you do not have a backup, you can regenerate the kube-apiserver.yaml from kubeadm:

```bash
nerdctl exec kind-control-plane bash -c \
  "kubeadm init phase control-plane apiserver --config /etc/kubernetes/kubeadm-config.yaml"
```

However, this regenerates a minimal manifest and loses any hardening flags you applied before the bad edit. The backup approach is always faster and safer.

## Cleanup

Remove the tutorial namespace. The kube-apiserver.yaml changes you made to the manifest persist in the cluster (they are part of the cluster configuration), so there is nothing to undo for the API server flags unless you want to restore the original configuration:

```bash
kubectl delete namespace tutorial-cluster-hardening

# Optional: restore the original API server manifest
# nerdctl exec kind-control-plane bash -c \
#   "cp /tmp/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml"
```

## Reference Commands

**kube-bench operations:**

| Command | Purpose |
|---|---|
| `nerdctl exec kind-control-plane bash -c "/tmp/kube-bench run --targets master 2>/dev/null"` | Run kube-bench against all master components |
| `... \| grep '^\[FAIL\]'` | Filter to FAIL findings only |
| `... \| grep '^\[FAIL\]' \| grep '1\.2\.'` | Filter to API server FAIL findings |
| `... \| grep '1.2.1'` | Check a specific control ID |

**API server manifest operations:**

| Command | Purpose |
|---|---|
| `nerdctl exec -it kind-control-plane bash` | Open interactive shell in control plane container |
| `cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak` | Backup before editing |
| `vi /etc/kubernetes/manifests/kube-apiserver.yaml` | Edit the API server manifest |
| `cp /tmp/kube-apiserver.yaml.bak /etc/kubernetes/manifests/kube-apiserver.yaml` | Restore from backup |
| `kubectl get pods -n kube-system -l component=kube-apiserver -w` | Watch API server restart |

**Verification operations:**

| Command | Expected Output |
|---|---|
| `kubectl --as=system:anonymous auth can-i get pods -n default` | `no` |
| `kubectl --as=system:anonymous auth can-i list namespaces` | `no` |
| `nerdctl exec kind-control-plane bash -c "grep anonymous-auth /etc/kubernetes/manifests/kube-apiserver.yaml"` | `- --anonymous-auth=false` |
| `nerdctl exec kind-control-plane bash -c "grep profiling /etc/kubernetes/manifests/kube-apiserver.yaml"` | `- --profiling=false` |
| `nerdctl exec kind-control-plane bash -c "grep authorization-mode /etc/kubernetes/manifests/kube-apiserver.yaml"` | `- --authorization-mode=Node,RBAC` |
