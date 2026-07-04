# AppArmor Profiles Tutorial

AppArmor is a Linux kernel security module that implements mandatory access control (MAC) by confining programs to a defined set of resources. Unlike traditional discretionary access control (where a process runs with the permissions of the user who launched it), mandatory access control enforces restrictions regardless of process privileges. A container running as root is still confined by its AppArmor profile, which is why AppArmor provides a meaningful security layer even after you have applied non-root security contexts. On Ubuntu 24.04 LTS, AppArmor is enabled by default and active for every process on the system.

When a container starts in Kubernetes, the kubelet instructs the container runtime (containerd) to apply an AppArmor profile to the container process. From that point forward, every file access, network operation, and capability request the container makes is checked against the profile rules before the kernel allows or denies the operation. The profile runs at the kernel level, so it cannot be bypassed from inside the container. This makes AppArmor a useful defense-in-depth layer: even if an attacker gains code execution inside a container, the profile limits what damage they can do.

This tutorial builds a complete AppArmor workflow around an nginx web server container. You will write a profile, start in complain mode to observe what nginx actually needs, convert to enforce mode with a minimal allow-list, and then verify that the profile blocks unauthorized operations. By the end, you will understand the entire lifecycle from profile authoring through pod deployment and violation debugging.

## Prerequisites

This tutorial uses a single-node kind cluster. See [docs/cluster-setup.md](../../../docs/cluster-setup.md#single-node-kind-cluster) for setup instructions. Confirm that AppArmor is available on your kind node before proceeding:

```bash
nerdctl exec kind-control-plane aa-status
```

The command should print a summary showing loaded profiles and confined processes. If it returns a "command not found" error, your host kernel does not have AppArmor enabled or the `apparmor-utils` package is not installed inside the kind node image.

## Setup

Create the tutorial namespace:

```bash
kubectl create namespace tutorial-system-hardening
```

## AppArmor Architecture

AppArmor profiles are text files stored on the node (conventionally in `/etc/apparmor.d/`). Each profile defines a set of rules for a named program or process. When the profile is loaded into the kernel using `apparmor_parser`, the kernel registers it as a security policy. Any process running under that profile name is then subject to those rules for every operation it attempts.

A profile can run in two modes. In enforce mode, violations are blocked: the kernel returns EACCES (permission denied) to the process and the violation is logged as an audit event. In complain mode, violations are allowed but logged: the process proceeds as if no restriction existed, while the kernel records an audit event describing what would have been blocked in enforce mode. Complain mode is invaluable during profile development because it lets the application run normally while you observe its actual access patterns before writing a restrictive enforce-mode profile.

You can check which profiles are loaded and their modes at any time:

```bash
nerdctl exec kind-control-plane aa-status
```

The output groups profiles into sections: enforce mode profiles, complain mode profiles, and a summary of which processes are running under which profiles.

## Profile Syntax

An AppArmor profile is a block of rules enclosed in braces. The profile must have a name, which is what Kubernetes references when associating the profile with a container. Here is the minimal valid structure:

```
#include <tunables/global>

profile my-profile-name flags=(attach_disconnected) {
  #include <abstractions/base>

  # rules go here
}
```

The `#include <tunables/global>` line at the top brings in global variable definitions (like `@{HOME}`) that rules can use. The `flags=(attach_disconnected)` annotation on the profile is required for containers: it tells AppArmor to apply the profile even when the process is in a mount namespace that is not attached to the root mount namespace, which is the situation every container is in.

The `#include <abstractions/base>` line inside the profile is a convenience shorthand that allows the basic file accesses every process needs to function: loading shared libraries from `/lib/` and `/usr/lib/`, reading locale data, accessing `/dev/null` and `/dev/urandom`, and a small set of `/proc/` paths. Without this abstraction, even a simple `ls` command would fail because it cannot load `libc.so`.

**File rules** control access to filesystem paths. The format is `path permissions,` where permissions are one or more characters from the set below. The trailing comma is required.

| Permission | Meaning | Default when omitted | Failure mode when missing |
|------------|---------|----------------------|--------------------------|
| `r` | Read the file | No read access | EACCES on open() for reading |
| `w` | Write or truncate the file | No write access | EACCES on open() for writing |
| `a` | Append to the file | No append access | EACCES on open() with O_APPEND |
| `x` | Execute the file | No execute access | EACCES on execve() |
| `m` | Memory-map with execute permission (mmap PROT_EXEC) | No executable mmap | EACCES on mmap() with PROT_EXEC |
| `k` | File locking (flock/fcntl) | No lock access | EACCES on flock() |
| `l` | Hard link creation | No hard link | EACCES on link() |

Glob patterns use two forms: `*` matches any characters within a single path component (not including `/`), while `**` matches any characters including slashes (matching across multiple path components). So `/etc/nginx/*` matches files directly in `/etc/nginx/` but not in subdirectories, while `/etc/nginx/**` matches everything recursively under `/etc/nginx/`.

**The `file,` shorthand** allows all file operations for all paths. It is equivalent to `/** rwmlk,` and is useful as a starting point when you want to allow everything and then selectively deny specific paths.

**Deny rules** use the `deny` keyword and override any prior allow rule, including `file,`. The rule `deny /etc/shadow r,` prevents reads of `/etc/shadow` even if an earlier `file,` allows all reads.

**Network rules** use the format `network [domain] [type],`. The rule `network inet tcp,` allows IPv4 TCP connections. Omitting network rules (without `file,` covering network) means all network access is denied, which would prevent most server applications from binding to a port.

**Capability rules** use `capability name,`. The rule `capability net_admin,` allows the NET_ADMIN capability. Without a capability rule, even a process running as root inside a container cannot exercise that capability.

**Execute transition modes** control what profile applies after an exec. The `ix` mode (inherit and execute) keeps the current profile. The `px` mode transitions to the new executable's own profile. Use `ix` when the child process should remain confined by the same profile.

## Writing a Complain-Mode Profile

Start by writing a profile that uses `file,` to allow all file access but runs in complain mode. This profile lets nginx operate normally while the kernel logs every operation that a more restrictive profile might deny. The logs tell you what the real application actually needs.

Write the following profile to a file on your local system:

```bash
cat <<'EOF' > /tmp/k8s-tutorial-complain
#include <tunables/global>

profile k8s-tutorial-complain flags=(attach_disconnected,complain) {
  #include <abstractions/base>
  file,
  network inet tcp,
  network inet6 tcp,
}
EOF
```

The `flags=(attach_disconnected,complain)` combination sets both the container attachment flag and complain mode. Notice that even though `file,` allows all file operations, violations against rules we would later add can still be observed in the audit log when the profile is in complain mode. For now, the profile effectively allows everything, which means nginx can run freely.

## Loading the Profile into the Kind Node

Kind runs its Kubernetes cluster inside a container managed by nerdctl. The AppArmor profiles must be installed inside that container (on the node's filesystem), not on your host. The workflow is always three steps: copy the profile file, load it with `apparmor_parser`, and verify it appears in `aa-status`.

```bash
# Copy the profile file into the kind control-plane container
nerdctl cp /tmp/k8s-tutorial-complain kind-control-plane:/etc/apparmor.d/k8s-tutorial-complain

# Load the profile into the kernel on the kind node
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-tutorial-complain

# Verify the profile is loaded
nerdctl exec kind-control-plane aa-status | grep k8s-tutorial-complain
```

You should see `k8s-tutorial-complain` appear in the output. If you run `aa-status` without the grep, you will see it listed under "profiles in complain mode."

The `-r` flag passed to `apparmor_parser` means "replace": if a profile with this name is already loaded, replace it with the new version. This is the flag you use for both initial loading and subsequent updates.

## Applying a Profile to a Pod

Kubernetes 1.30 introduced the `securityContext.appArmorProfile` field, which is the canonical way to apply an AppArmor profile. The field can be set at the pod level (applies to all containers in the pod) or at the individual container level (overrides the pod-level setting for that container).

```yaml
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-tutorial-complain
```

The `type` field accepts three values. `Localhost` means the profile is loaded on the node and referenced by name. `RuntimeDefault` means use the container runtime's default seccomp-like AppArmor profile (if the runtime has one). `Unconfined` disables AppArmor for the container. The default when the field is omitted entirely depends on the cluster's AppArmor admission policy; in most clusters without explicit policy, AppArmor is unconfined.

When `type` is `Localhost`, the `localhostProfile` field holds the profile name exactly as it appears inside the profile file after the `profile` keyword. The profile must already be loaded on the node before the pod is scheduled; the kubelet does not load profiles on demand.

Create an nginx pod using the complain-mode profile:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: tutorial-nginx
  namespace: tutorial-system-hardening
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-tutorial-complain
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

Wait for the pod to start:

```bash
kubectl get pod tutorial-nginx -n tutorial-system-hardening
# Expected: STATUS Running
```

Confirm the profile is active from inside the container by reading the process's AppArmor attribute:

```bash
kubectl exec tutorial-nginx -n tutorial-system-hardening -- cat /proc/self/attr/current
# Expected: k8s-tutorial-complain (complain)
```

The format is `profile-name (mode)`. The `(complain)` suffix confirms complain mode is active.

## Pre-1.30 Annotation Syntax

Before Kubernetes 1.30, AppArmor was applied using a pod annotation. The annotation key encodes the container name: `container.apparmor.security.beta.kubernetes.io/<container-name>`. The value is `localhost/<profile-name>` for a locally loaded profile.

```yaml
metadata:
  annotations:
    container.apparmor.security.beta.kubernetes.io/nginx: localhost/k8s-tutorial-complain
```

Both the annotation and the `securityContext.appArmorProfile` field are valid in Kubernetes 1.30+ clusters. The `securityContext` field takes precedence if both are set for the same container. The annotation is still used in some existing workloads and in exam environments running older Kubernetes versions, so it is worth knowing both forms.

## Observing Complain Mode Violations

Generate some nginx traffic so that the access log and error log paths get written:

```bash
kubectl exec tutorial-nginx -n tutorial-system-hardening -- curl -s http://localhost/ > /dev/null
```

Now check the audit log on the kind node for any AppArmor audit events:

```bash
nerdctl exec kind-control-plane dmesg | grep -i apparmor | tail -20
```

In complain mode, you will see lines starting with `audit:` and containing `apparmor="ALLOWED"` entries for operations that would have been denied if the profile had been in enforce mode. The lines also include the profile name (`profile="k8s-tutorial-complain"`), the operation type (`operation="file_perm"` or `operation="network_create"`), and the specific resource being accessed (`name="/path/to/file"`).

These audit entries are the raw material you use to build an accurate enforce-mode allow-list: you run the application in complain mode, observe everything it tries to do, and then write explicit allow rules for each of those operations.

## Writing an Enforce-Mode Profile

Now write a more restrictive profile that allows what nginx actually needs and enforces in enforce mode. The rules below are derived from observing what nginx requires:

```bash
cat <<'EOF' > /tmp/k8s-tutorial-webserver
#include <tunables/global>

profile k8s-tutorial-webserver flags=(attach_disconnected) {
  #include <abstractions/base>

  # nginx reads its configuration from here
  /etc/nginx/** r,

  # nginx serves static content from here
  /usr/share/nginx/html/** r,

  # nginx writes access and error logs here
  /var/log/nginx/** w,

  # nginx writes its PID file here
  /var/run/nginx.pid w,
  /run/nginx.pid w,

  # nginx writes temporary client body files here
  /var/cache/nginx/** rw,
  /tmp/** rw,

  # nginx executable and shared libraries
  /usr/sbin/nginx mr,
  /usr/lib/** mr,
  /lib/** mr,
  /lib64/** mr,

  # nginx needs to read /proc paths for worker processes
  /proc/*/net/** r,
  /proc/sys/kernel/** r,

  # network access for serving HTTP
  network inet tcp,
  network inet6 tcp,
}
EOF
```

No `flags=(complain)` means this profile defaults to enforce mode. Load it:

```bash
nerdctl cp /tmp/k8s-tutorial-webserver kind-control-plane:/etc/apparmor.d/k8s-tutorial-webserver
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-tutorial-webserver
nerdctl exec kind-control-plane aa-status | grep k8s-tutorial-webserver
```

Delete the complain-mode pod and create a new one using the enforce-mode profile:

```bash
kubectl delete pod tutorial-nginx -n tutorial-system-hardening

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: tutorial-nginx
  namespace: tutorial-system-hardening
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-tutorial-webserver
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

Wait for it to start:

```bash
kubectl get pod tutorial-nginx -n tutorial-system-hardening
# Expected: STATUS Running

kubectl exec tutorial-nginx -n tutorial-system-hardening -- cat /proc/self/attr/current
# Expected: k8s-tutorial-webserver (enforce)
```

## Verifying Enforcement

With the enforce-mode profile active, test that denied operations fail. The profile does not include a rule allowing writes to `/etc/`, so any attempt to create or modify a file there should fail with permission denied:

```bash
kubectl exec tutorial-nginx -n tutorial-system-hardening -- sh -c 'touch /etc/apparmor-test 2>&1'
# Expected: touch: /etc/apparmor-test: Permission denied

kubectl exec tutorial-nginx -n tutorial-system-hardening -- sh -c 'echo "test" > /etc/nginx/injected.conf 2>&1'
# Expected: sh: /etc/nginx/injected.conf: Permission denied
```

The error comes from the kernel denying the write, not from file ownership or permissions. Even if the container process runs as root, AppArmor enforcement overrides the DAC (discretionary access control) check.

Verify that normal nginx operations still work:

```bash
kubectl exec tutorial-nginx -n tutorial-system-hardening -- curl -s http://localhost/ | head -5
# Expected: HTML content beginning with <!DOCTYPE html> or <html>
```

## Troubleshooting AppArmor Issues

**Pod stuck in ContainerCreating with no logs.** Check the pod events:

```bash
kubectl describe pod <pod-name> -n <namespace>
```

Look for an event mentioning "AppArmor profile not found" or "failed to load AppArmor profile". This means the profile named in the pod spec is not loaded on the node. Load it using `nerdctl cp` and `apparmor_parser`, then delete and recreate the pod.

**Profile name mismatch.** The `localhostProfile` value must match the `profile` keyword name inside the profile file exactly, including case. A common mistake is naming the file `k8s-webserver` but writing `profile k8s-web-server` inside it. The kubelet uses the profile name, not the filename.

```bash
# Check what profile names are loaded
nerdctl exec kind-control-plane aa-status

# Compare with what the pod spec requests
kubectl get pod <pod-name> -n <namespace> -o jsonpath='{.spec.securityContext.appArmorProfile.localhostProfile}'
```

**Pod crashes with permission denied errors in logs.** The profile is too restrictive. Switch to complain mode to identify what is being blocked:

```bash
# Modify the profile flags in the file
# Change: flags=(attach_disconnected)
# To:     flags=(attach_disconnected,complain)

# Reload the profile
nerdctl cp /tmp/myprofile kind-control-plane:/etc/apparmor.d/myprofile
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/myprofile

# Delete and recreate the pod (profile change requires pod restart)
kubectl delete pod <pod-name> -n <namespace>
kubectl apply -f <pod-manifest.yaml>

# Run the workload, then check audit logs
nerdctl exec kind-control-plane dmesg | grep -i apparmor | tail -30
```

The audit messages will show `apparmor="ALLOWED"` entries for operations the enforce profile would have blocked. Add explicit allow rules for those operations, switch back to enforce mode, and reload.

**Profile change does not take effect.** AppArmor profiles are applied at container start time. Reloading a profile with `apparmor_parser -r` does not affect running containers. You must delete and recreate the pod after any profile change.

## Cleanup

```bash
kubectl delete namespace tutorial-system-hardening
```

The AppArmor profiles remain loaded in the kind node kernel. They do not affect anything unless a pod spec references them. To unload them from the kernel explicitly:

```bash
nerdctl exec kind-control-plane apparmor_parser -R /etc/apparmor.d/k8s-tutorial-complain
nerdctl exec kind-control-plane apparmor_parser -R /etc/apparmor.d/k8s-tutorial-webserver
```

The `-R` flag removes the profile from the kernel.

## Reference Commands

| Task | Command |
|------|---------|
| Check loaded profiles and modes | `nerdctl exec kind-control-plane aa-status` |
| Copy a profile to the kind node | `nerdctl cp /tmp/myprofile kind-control-plane:/etc/apparmor.d/myprofile` |
| Load or reload a profile | `nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/myprofile` |
| Unload a profile | `nerdctl exec kind-control-plane apparmor_parser -R /etc/apparmor.d/myprofile` |
| Check profile active for a process | `kubectl exec <pod> -- cat /proc/self/attr/current` |
| Check pod's AppArmor profile field | `kubectl get pod <pod> -o jsonpath='{.spec.securityContext.appArmorProfile}'` |
| Check pod's annotation (pre-1.30) | `kubectl get pod <pod> -o jsonpath='{.metadata.annotations}'` |
| View AppArmor audit events on node | `nerdctl exec kind-control-plane dmesg \| grep -i apparmor` |
| View AppArmor events via journalctl | `nerdctl exec kind-control-plane journalctl -k \| grep -i apparmor` |
| Verify profile is in enforce section | `nerdctl exec kind-control-plane aa-status \| grep -A5 "enforce"` |
| Verify profile is in complain section | `nerdctl exec kind-control-plane aa-status \| grep -A5 "complain"` |
