# Custom Seccomp Profiles and Node OS Hardening Tutorial

Seccomp (Secure Computing Mode) is a Linux kernel feature that filters system calls. Every process on Linux communicates with the kernel through system calls: opening files, allocating memory, creating sockets, and hundreds of other operations all go through the syscall interface. A seccomp profile defines which syscalls a process is allowed to make. If the process attempts a syscall not covered by an allow rule, the kernel rejects it, either killing the process or returning an error code.

Seccomp and AppArmor operate at different layers and complement each other. AppArmor restricts what resources a process can access (which files, which network connections, which capabilities), using path-based rules. Seccomp restricts the mechanism the process uses to interact with the kernel, regardless of what it is trying to access. A process calling `openat()` to read a file is checked by both: AppArmor evaluates the path being opened, and seccomp evaluates whether `openat` is a permitted syscall. Disabling seccomp does not make AppArmor irrelevant, and vice versa.

This tutorial builds a complete seccomp workflow. You will write a deny-list profile to block specific dangerous syscalls, place it in the kind node, apply it to a pod, and verify that the blocked syscall is rejected. You will then use SCMP_ACT_LOG to discover what syscalls a simple workload needs and convert that observation into a working allow-list profile. The final section covers node OS hardening concepts: what a minimally footprinted node looks like and what an administrator would check to reduce the node attack surface in a production environment.

## Prerequisites

This tutorial uses a single-node kind cluster. See [docs/cluster-setup.md](../../../docs/cluster-setup.md#single-node-kind-cluster) for setup instructions. The tutorial also assumes you have completed 13-security-contexts/assignment-3, which introduced the basic seccompProfile field syntax and RuntimeDefault.

## Setup

```bash
kubectl create namespace tutorial-system-hardening
```

## Seccomp Profile Types

Kubernetes supports three seccomp profile types, set via `securityContext.seccompProfile.type`:

| Type | Meaning | Default when omitted |
|------|---------|---------------------|
| `Unconfined` | No syscall filtering. The process can call any syscall. | This is the default for most clusters without explicit policy |
| `RuntimeDefault` | Uses the container runtime's built-in seccomp profile, which blocks a set of syscalls known to be dangerous and rarely needed by legitimate workloads | Not default; must be explicitly specified or enabled via PodSecurityAdmission |
| `Localhost` | Uses a custom profile file placed on the node at `/var/lib/kubelet/seccomp/<localhostProfile>` | N/A (requires localhostProfile path) |

When the field is omitted entirely, the effective behavior depends on the cluster's Pod Security Admission configuration and the container runtime defaults. Do not rely on the default being safe; explicitly set the profile type in your pod specs.

A useful observation about profile type and syscall filtering: you can verify which mode is active inside the container by reading `/proc/self/status`:

```bash
# 0 = disabled, 1 = strict mode, 2 = filter mode (profile applied)
cat /proc/self/status | grep Seccomp
```

Any non-zero value means syscall filtering is active. The value `2` (filter mode) appears for both RuntimeDefault and Localhost profiles.

## Custom Seccomp Profile JSON Format

A custom seccomp profile is a JSON file with three top-level fields.

**`defaultAction`** defines what happens to syscalls that are not matched by any entry in the `syscalls` list. This is the most important field because it determines the overall posture of the profile.

| defaultAction value | Effect | When to use |
|--------------------|--------|-------------|
| `SCMP_ACT_ALLOW` | Permit the syscall. Used as the default in deny-list profiles. | When you want to allow most syscalls and only block specific dangerous ones |
| `SCMP_ACT_ERRNO` | Deny the syscall, returning ENOSYS or EPERM to the process. | When you want to allow only specific syscalls (allow-list strategy) |
| `SCMP_ACT_LOG` | Permit the syscall but log it via the kernel audit system. | During profile development to discover what syscalls a workload actually makes |
| `SCMP_ACT_KILL` | Kill the process immediately when a disallowed syscall is attempted. | When you need the strongest possible enforcement; the process gets no chance to handle the error |

The failure mode when `defaultAction` is misconfigured is immediate application death: if you set `SCMP_ACT_ERRNO` as the default and forget to allow a syscall the application requires at startup (such as `openat` or `read`), the process will fail to start or will crash immediately with an exit code.

**`architectures`** lists the CPU architectures the profile applies to. A container running on x86_64 hardware needs at minimum `SCMP_ARCH_X86_64`. Including `SCMP_ARCH_X86` and `SCMP_ARCH_X32` covers 32-bit compatibility mode and x32 ABI. Omitting this field is valid (the profile applies to all architectures), but including it is a best practice for clarity.

```json
"architectures": [
  "SCMP_ARCH_X86_64",
  "SCMP_ARCH_X86",
  "SCMP_ARCH_X32"
]
```

**`syscalls`** is a list of entries, each specifying one or more syscall names and the action to take for those syscalls. The format of each entry is:

```json
{
  "names": ["read", "write", "openat"],
  "action": "SCMP_ACT_ALLOW"
}
```

The `names` field is a list of syscall names (strings matching the kernel syscall table). The `action` field is one of the same values as `defaultAction`. An entry in the `syscalls` list overrides the `defaultAction` for those specific syscalls.

## Writing a Deny-List Profile

A deny-list profile allows all syscalls by default and blocks specific dangerous ones. This is the most permissive strategy and is appropriate when you want to harden a workload without deep understanding of its syscall usage. The canonical dangerous syscalls to block in a container context are:

- `ptrace`: Allows one process to read and write the memory of another. Used by debuggers and attackers for memory inspection.
- `mount`: Allows mounting filesystems. A container should not be able to mount additional filesystems.
- `unshare`: Creates new Linux namespaces. A container escaping to the host often involves creating a new user namespace.
- `kexec_load`: Loads a new kernel. Never needed in a container.
- `clone` with CLONE_NEWUSER flag: Creates new user namespaces, a common container escape vector. Note that you cannot filter by flag value in seccomp; you can only block the syscall entirely.

Write the deny-list profile:

```bash
cat <<'EOF' > /tmp/k8s-tutorial-denylist.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": [
    {
      "names": ["ptrace", "mount", "unshare", "kexec_load", "pivot_root"],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
EOF
```

## Placing Profiles in the Kind Node

Custom seccomp profiles must be placed inside the kind control-plane container at `/var/lib/kubelet/seccomp/`. The kubelet reads profiles from this directory at container creation time. The path you specify in the pod spec's `localhostProfile` field is relative to this directory.

```bash
# Copy the profile into the kind control-plane container
nerdctl cp /tmp/k8s-tutorial-denylist.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-tutorial-denylist.json

# Verify the file is present
nerdctl exec kind-control-plane ls -la /var/lib/kubelet/seccomp/
```

Unlike AppArmor, seccomp profiles do not need to be loaded into the kernel with a separate parser command. The kubelet reads the JSON file directly when creating the container. If the file is not present when the pod is scheduled, the container fails to start with an error describing the missing profile.

## Applying a Custom Seccomp Profile to a Pod

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: tutorial-secured
  namespace: tutorial-system-hardening
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-tutorial-denylist.json
  containers:
  - name: alpine
    image: alpine:3.20
    command: [sleep, "3600"]
EOF
```

The `localhostProfile` value is a path relative to `/var/lib/kubelet/seccomp/`. If you placed the profile at a subdirectory (for example, `/var/lib/kubelet/seccomp/profiles/deny.json`), the `localhostProfile` would be `profiles/deny.json`. Verify the pod started and seccomp is active:

```bash
kubectl get pod tutorial-secured -n tutorial-system-hardening
# Expected: STATUS Running

kubectl exec tutorial-secured -n tutorial-system-hardening -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2

kubectl get pod tutorial-secured -n tutorial-system-hardening -o jsonpath='{.spec.securityContext.seccompProfile}'
# Expected: {"localhostProfile":"k8s-tutorial-denylist.json","type":"Localhost"}
```

## Verifying That a Denied Syscall Is Blocked

To verify that the `ptrace` denial works, you would normally call `ptrace` from inside the container and observe the EPERM return code. The alpine image does not include a program that calls ptrace directly, but the kernel audit log records denied syscalls when the profile uses `SCMP_ACT_ERRNO`. Check the kind node's dmesg after running any command inside the container:

```bash
# Run a command inside the container (any command triggers syscalls)
kubectl exec tutorial-secured -n tutorial-system-hardening -- ls /

# Check the kind node's dmesg for SECCOMP audit entries
nerdctl exec kind-control-plane dmesg | grep -i seccomp | tail -10
```

If any denied syscall was attempted, you will see lines with `type=1326` (the kernel audit type for SECCOMP events). The format includes the syscall number, the process name, and the action taken. Note that the deny-list profile only logs denied syscalls, so if alpine's `ls` did not attempt `ptrace`, no SECCOMP audit line appears for ptrace.

## Using SCMP_ACT_LOG for Discovery

The allow-list strategy (defaultAction: SCMP_ACT_ERRNO) requires you to know every syscall the application will make before you can write a working profile. The standard approach is to start with SCMP_ACT_LOG as the defaultAction, run the workload, observe which syscalls appear in the audit log, and then convert those observations into an allow-list.

Write a log-only profile:

```bash
cat <<'EOF' > /tmp/k8s-tutorial-logonly.json
{
  "defaultAction": "SCMP_ACT_LOG",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": []
}
EOF
nerdctl cp /tmp/k8s-tutorial-logonly.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-tutorial-logonly.json
```

Apply it to a pod running a specific workload:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: tutorial-logger
  namespace: tutorial-system-hardening
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-tutorial-logonly.json
  containers:
  - name: worker
    image: busybox:1.36
    command: [sh, -c, "cat /etc/hostname && echo hello > /tmp/out && cat /tmp/out && exit 0"]
EOF
```

Wait for the pod to complete (status Succeeded), then read the audit log from the kind node:

```bash
kubectl get pod tutorial-logger -n tutorial-system-hardening
# Expected: STATUS Succeeded

nerdctl exec kind-control-plane dmesg | grep "type=1326" | tail -40
```

The audit messages show syscall numbers. An audit line looks like:

```
[kernel] type=1326 audit(...): auid=... uid=0 gid=0 ... pid=12345 comm="sh" exe="/bin/sh" sig=0 arch=c000003e syscall=257 compat=0 ip=... code=0x7ffc0000
```

The `syscall=257` field is the syscall number on x86_64. Syscall 257 is `openat`. To read syscall names, check the node's header file:

```bash
nerdctl exec kind-control-plane grep -r "define __NR_openat" /usr/include/ 2>/dev/null | head -3
# Or look up syscall numbers directly:
# syscall 0 = read, 1 = write, 2 = open, 3 = close, 4 = stat, 5 = fstat
# 9 = mmap, 10 = mprotect, 11 = munmap, 12 = brk
# 21 = access, 39 = getpid, 59 = execve
# 231 = exit_group, 257 = openat, 262 = newfstatat
```

Collect all unique syscall numbers from the log and map them to names. Then write the allow-list profile:

```bash
cat <<'EOF' > /tmp/k8s-tutorial-allowlist.json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": [
    {
      "names": [
        "read", "write", "open", "close", "stat", "fstat", "lstat",
        "poll", "lseek", "mmap", "mprotect", "munmap", "brk",
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "access", "pipe", "dup", "dup2", "nanosleep",
        "getpid", "socket", "connect", "sendto", "recvfrom",
        "exit", "wait4", "kill", "uname", "fcntl", "ioctl",
        "getdents", "getcwd", "chdir", "rename", "mkdir", "rmdir",
        "creat", "link", "unlink", "symlink", "readlink", "chmod", "chown",
        "umask", "gettimeofday", "getrlimit", "getrusage",
        "sysinfo", "times", "getuid", "getgid", "setuid", "setgid",
        "geteuid", "getegid", "getppid", "getpgrp", "setsid",
        "sigaltstack", "clone", "execve", "exit_group",
        "openat", "getdents64", "newfstatat", "set_tid_address",
        "set_robust_list", "prlimit64", "getrandom", "rseq"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-tutorial-allowlist.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-tutorial-allowlist.json
```

Delete the log-mode pod and create a new one using the allow-list profile:

```bash
kubectl delete pod tutorial-logger -n tutorial-system-hardening

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: tutorial-strict
  namespace: tutorial-system-hardening
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-tutorial-allowlist.json
  containers:
  - name: worker
    image: busybox:1.36
    command: [sh, -c, "cat /etc/hostname && echo hello > /tmp/out && cat /tmp/out && exit 0"]
EOF

kubectl get pod tutorial-strict -n tutorial-system-hardening
# Expected: STATUS Succeeded
```

If the allow-list is too restrictive and the pod crashes, switch back to SCMP_ACT_LOG, add the missing syscall to the allow list, and try again. This iterative approach is the standard workflow for developing minimal allow-list profiles.

## Container-Level Seccomp Profiles

Like AppArmor, seccomp profiles can be set at the container level to override the pod-level setting:

```yaml
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: pod-level-profile.json
  containers:
  - name: main
    securityContext:
      seccompProfile:
        type: RuntimeDefault  # Overrides the pod-level Localhost profile for this container
```

Container-level `seccompProfile` always takes precedence over pod-level for that specific container. The other containers in the pod still use the pod-level profile.

## Troubleshooting Seccomp Issues

**Pod stays in ContainerCreating or crashes immediately with "invalid seccomp profile" message:** Check whether the profile file exists at the correct path inside the kind node:

```bash
nerdctl exec kind-control-plane ls /var/lib/kubelet/seccomp/
kubectl describe pod <pod> -n <namespace>
# Look for events mentioning the profile path
```

**Pod crashes immediately with exit code 1 but no obvious application error:** The seccomp profile's SCMP_ACT_ERRNO is blocking a syscall required at startup. Switch to SCMP_ACT_LOG temporarily:

```bash
# Modify the profile's defaultAction to SCMP_ACT_LOG
# Recopy and delete/recreate the pod
nerdctl cp /tmp/modified-profile.json kind-control-plane:/var/lib/kubelet/seccomp/modified-profile.json
kubectl delete pod <pod> -n <namespace>
kubectl apply -f <manifest>
# Check dmesg after the pod starts
nerdctl exec kind-control-plane dmesg | grep "type=1326" | tail -30
```

**Profile is copied to the node but the pod still fails with "profile not found":** Verify the `localhostProfile` path in the pod spec matches the actual file path relative to `/var/lib/kubelet/seccomp/`. A path mismatch of a single character causes the same "profile not found" error as a missing file. The kubelet error message includes the path it looked for.

**Exit code 159:** This is the signal 31 (SIGSYS) exit code. When a seccomp profile uses `SCMP_ACT_KILL`, the process is killed with SIGSYS and the container exits with code 159 (128 + 31). Check the profile's defaultAction and look for `SCMP_ACT_KILL` entries.

## Node OS Hardening Concepts

Node OS hardening is the practice of reducing the attack surface on the nodes running your Kubernetes cluster. Unlike AppArmor and seccomp (which restrict per-container processes), node OS hardening targets the node itself: the services running on it, the packages installed, the open network ports, and the kernel configuration. In a kind cluster you cannot easily apply real OS hardening (the kind node runs as a container on your host), but understanding the concepts is essential for the CKA/CKS exam and for real cluster deployments.

**Minimize installed packages.** Every installed package is potential attack surface. If a package is not needed for running Kubernetes, remove it. On a Debian/Ubuntu-based node you would use `apt-get remove --purge <package>` and verify with `dpkg -l`. On a RHEL/CentOS node you would use `yum remove`. The goal is a minimal OS that runs the kubelet, the container runtime, and nothing else.

**Disable unnecessary services.** Services listening on the network or running as privileged processes are potential entry points. Use `systemctl list-units --state=active` to see what is running and `systemctl disable <service>` to prevent unnecessary services from starting. In a typical Kubernetes node, the expected services are: the container runtime (containerd), the kubelet, and the host networking daemon (NetworkManager or systemd-networkd). Additional services like CUPS (printing) or avahi (mDNS) have no place on a Kubernetes worker node.

**Audit listening ports.** The `ss -tlnp` command lists all TCP sockets in listen state, showing the port, the process binding to it, and the PID. Any port not required for Kubernetes operation (the API server on 6443, the kubelet on 10250, the container runtime socket, and CNI-specific ports) should be closed by removing the service that is binding to it. Do not close ports by adding firewall rules while leaving the service running; remove the service so the port does not appear in the first place.

**Kernel hardening.** The `/proc/sys/kernel/` tree exposes kernel parameters that can be adjusted for security. Key settings include `kernel.dmesg_restrict=1` (prevent non-root users from reading kernel messages), `fs.suid_dumpable=0` (prevent core dumps from setuid programs), and `net.ipv4.conf.all.send_redirects=0` (prevent the node from sending ICMP redirects). These are set via `sysctl -w` or via `/etc/sysctl.conf` for persistence.

In the kind environment, you can examine these concepts by inspecting the kind node container without making changes:

```bash
# See what services are running on the kind node
nerdctl exec kind-control-plane ps aux

# See what ports are listening on the kind node
nerdctl exec kind-control-plane ss -tlnp

# See kernel security parameters
nerdctl exec kind-control-plane sysctl kernel.dmesg_restrict
nerdctl exec kind-control-plane sysctl fs.suid_dumpable
```

## Cleanup

```bash
kubectl delete namespace tutorial-system-hardening
```

Seccomp profile files on the kind node persist until manually removed:

```bash
nerdctl exec kind-control-plane rm /var/lib/kubelet/seccomp/k8s-tutorial-denylist.json
nerdctl exec kind-control-plane rm /var/lib/kubelet/seccomp/k8s-tutorial-logonly.json
nerdctl exec kind-control-plane rm /var/lib/kubelet/seccomp/k8s-tutorial-allowlist.json
```

## Reference Commands

| Task | Command |
|------|---------|
| List files in seccomp profile directory on kind node | `nerdctl exec kind-control-plane ls /var/lib/kubelet/seccomp/` |
| Copy a profile to the kind node | `nerdctl cp /tmp/profile.json kind-control-plane:/var/lib/kubelet/seccomp/profile.json` |
| Verify seccomp is active in a container | `kubectl exec <pod> -- cat /proc/self/status \| grep Seccomp` |
| Check pod's seccompProfile field | `kubectl get pod <pod> -o jsonpath='{.spec.securityContext.seccompProfile}'` |
| View SECCOMP audit events on node | `nerdctl exec kind-control-plane dmesg \| grep "type=1326"` |
| View recent SECCOMP events | `nerdctl exec kind-control-plane dmesg \| grep -i seccomp \| tail -20` |
| View listening ports on kind node | `nerdctl exec kind-control-plane ss -tlnp` |
| View running processes on kind node | `nerdctl exec kind-control-plane ps aux` |
| Check kernel security parameters | `nerdctl exec kind-control-plane sysctl kernel.dmesg_restrict` |
| Describe pod for profile errors | `kubectl describe pod <pod> -n <ns>` |
| Get pod logs for crash diagnosis | `kubectl logs <pod> -n <ns> [--previous]` |
