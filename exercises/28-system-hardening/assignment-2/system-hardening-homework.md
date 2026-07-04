# System Hardening Assignment 2: Custom Seccomp Profiles Homework

Complete the tutorial in `system-hardening-tutorial.md` before attempting these exercises. The tutorial explains the JSON profile format, the three seccomp profile types, the SCMP_ACT_LOG discovery workflow, and node OS hardening concepts. The Level 4 exercises in particular require understanding the SCMP_ACT_LOG workflow before attempting them.

Each exercise creates its own namespace. Run the setup commands exactly as shown. For Level 3 and Level 5 debugging exercises, the setup installs a broken configuration; examine the failure mode before reading the task description.

---

## Level 1: Seccomp Profile Application

### Exercise 1.1

**Objective:** A custom deny-list seccomp profile is provided and copied to the kind node by the setup commands. Apply this profile to a pod using `type: Localhost`, verify that seccomp filtering is active inside the container, and confirm the pod's profile configuration in the pod spec.

**Setup:**

```bash
kubectl create namespace ex-1-1

cat <<'EOF' > /tmp/k8s-ex11-seccomp.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": ["ptrace", "mount", "unshare", "kexec_load"],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex11-seccomp.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex11-seccomp.json
```

**Task:** Create a pod named `alpine-secured` in namespace `ex-1-1` using `alpine:3.20` with the command `sleep 3600`. Apply the `k8s-ex11-seccomp.json` profile at the pod level using `securityContext.seccompProfile` with `type: Localhost`. Verify that the seccomp filter is active and the profile path is set correctly.

**Verification:**

```bash
kubectl get pod alpine-secured -n ex-1-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec alpine-secured -n ex-1-1 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2

kubectl get pod alpine-secured -n ex-1-1 -o jsonpath='{.spec.securityContext.seccompProfile.type}'
# Expected: Localhost

kubectl get pod alpine-secured -n ex-1-1 -o jsonpath='{.spec.securityContext.seccompProfile.localhostProfile}'
# Expected: k8s-ex11-seccomp.json
```

---

### Exercise 1.2

**Objective:** Apply `type: RuntimeDefault` to a pod and compare the Seccomp status with an Unconfined pod. Create two pods in the same namespace: one using RuntimeDefault, one using Unconfined. Verify that RuntimeDefault produces a Seccomp value of 2 and Unconfined produces 0.

**Setup:**

```bash
kubectl create namespace ex-1-2
```

**Task:** Create a pod named `runtime-pod` in `ex-1-2` using `busybox:1.36` (command: `sleep 3600`) with `securityContext.seccompProfile.type: RuntimeDefault`. Create a second pod named `unconfined-pod` in `ex-1-2` using `busybox:1.36` (command: `sleep 3600`) with `securityContext.seccompProfile.type: Unconfined`. Verify the Seccomp values differ between the two pods.

**Verification:**

```bash
kubectl get pod runtime-pod -n ex-1-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl get pod unconfined-pod -n ex-1-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec runtime-pod -n ex-1-2 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2

kubectl exec unconfined-pod -n ex-1-2 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	0
```

---

### Exercise 1.3

**Objective:** Apply a seccomp profile at the container level, overriding a pod-level Unconfined setting. The container-level `seccompProfile` takes precedence over the pod-level one. Verify the override works.

**Setup:**

```bash
kubectl create namespace ex-1-3

cat <<'EOF' > /tmp/k8s-ex13-seccomp.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": ["ptrace", "kexec_load"],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex13-seccomp.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex13-seccomp.json
```

**Task:** Create a pod named `override-pod` in `ex-1-3` using `alpine:3.20` (command: `sleep 3600`). Set the pod-level `securityContext.seccompProfile.type` to `Unconfined`. At the container level (inside the `containers[0].securityContext`), set `seccompProfile.type: Localhost` with `localhostProfile: k8s-ex13-seccomp.json`. Verify that the container uses the Localhost profile (Seccomp value 2), not the pod-level Unconfined.

**Verification:**

```bash
kubectl get pod override-pod -n ex-1-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec override-pod -n ex-1-3 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2

kubectl get pod override-pod -n ex-1-3 -o jsonpath='{.spec.securityContext.seccompProfile.type}'
# Expected: Unconfined

kubectl get pod override-pod -n ex-1-3 -o jsonpath='{.spec.containers[0].securityContext.seccompProfile.type}'
# Expected: Localhost
```

---

## Level 2: Profile Authoring

### Exercise 2.1

**Objective:** Write a deny-list seccomp profile that blocks `ptrace`, `mount`, `unshare`, and `pivot_root`. Apply it to an nginx pod and verify the pod runs normally (none of these syscalls are needed for basic nginx operation).

**Setup:**

```bash
kubectl create namespace ex-2-1
```

**Task:** Write the profile as `/tmp/k8s-ex21-denylist.json` with `defaultAction: SCMP_ACT_ALLOW` and explicit `SCMP_ACT_ERRNO` entries for `ptrace`, `mount`, `unshare`, and `pivot_root`. Include the architectures field. Copy the profile to the kind node at `/var/lib/kubelet/seccomp/k8s-ex21-denylist.json`. Create a pod named `nginx-secured` in `ex-2-1` using `nginx:1.27` with the profile applied at the pod level. Verify the pod starts and nginx serves responses.

**Verification:**

```bash
nerdctl exec kind-control-plane ls /var/lib/kubelet/seccomp/k8s-ex21-denylist.json
# Expected: /var/lib/kubelet/seccomp/k8s-ex21-denylist.json (file exists)

kubectl get pod nginx-secured -n ex-2-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec nginx-secured -n ex-2-1 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2

kubectl exec nginx-secured -n ex-2-1 -- curl -s http://localhost/ | head -3
# Expected: HTML content (non-empty)
```

---

### Exercise 2.2

**Objective:** Write a deny-list profile that adds `SCMP_ACT_LOG` for a specific dangerous syscall rather than `SCMP_ACT_ERRNO`. This lets you observe when the syscall is attempted without blocking the process. Apply the profile to a pod, trigger an operation that would call the logged syscall, and observe the audit entry in the kind node's dmesg.

**Setup:**

```bash
kubectl create namespace ex-2-2
```

**Task:** Write a profile named `k8s-ex22-logptrace.json` with `defaultAction: SCMP_ACT_ALLOW` and a `syscalls` entry that sets `SCMP_ACT_LOG` for `ptrace`. Copy it to the kind node. Create a pod named `log-watcher` in `ex-2-2` using `alpine:3.20` (command: `sleep 3600`). Apply the profile at the pod level. Verify the pod runs (the logged syscall is allowed, just monitored). Then run `ls /` from inside the pod and check the kind node's dmesg for any SECCOMP audit lines.

**Verification:**

```bash
kubectl get pod log-watcher -n ex-2-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec log-watcher -n ex-2-2 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2

kubectl exec log-watcher -n ex-2-2 -- ls / > /dev/null

nerdctl exec kind-control-plane dmesg | grep "type=1326" | tail -5
# Expected: Zero or more SECCOMP audit lines (ptrace is rarely called by ls,
# but the important thing is the pod is running with the profile active)
```

---

### Exercise 2.3

**Objective:** Write a minimal allow-list profile for a simple busybox workload. The profile should use `defaultAction: SCMP_ACT_ERRNO` and explicitly allow the syscalls needed for `cat /etc/hostname && echo done`. Apply the profile, verify the command succeeds, and verify the exit code is 0.

**Setup:**

```bash
kubectl create namespace ex-2-3
```

**Task:** Write a profile named `k8s-ex23-allowlist.json` with `defaultAction: SCMP_ACT_ERRNO`. The `syscalls` list must include at minimum the following syscall names with `SCMP_ACT_ALLOW`:
`read`, `write`, `openat`, `close`, `fstat`, `newfstatat`, `mmap`, `mprotect`, `munmap`, `brk`, `rt_sigaction`, `rt_sigprocmask`, `rt_sigreturn`, `access`, `execve`, `exit_group`, `getpid`, `getuid`, `getgid`, `geteuid`, `getegid`, `set_tid_address`, `set_robust_list`, `uname`, `ioctl`, `prlimit64`, `getrandom`, `rseq`, `futex`, `clone3`, `clone`

Copy the profile to the kind node. Create a pod named `cat-pod` in `ex-2-3` using `busybox:1.36` with the command `sh -c 'cat /etc/hostname && echo done'` and the profile applied at the pod level. Verify the pod reaches Succeeded status and the logs show the hostname followed by `done`.

**Verification:**

```bash
kubectl get pod cat-pod -n ex-2-3 -o jsonpath='{.status.phase}'
# Expected: Succeeded

kubectl logs cat-pod -n ex-2-3
# Expected: Two lines: the pod's hostname string, then the word "done"
```

---

## Level 3: Debugging Broken Configurations

### Exercise 3.1

**Objective:** The configuration below has a problem preventing the pod from running. Find and fix whatever is needed so the pod reaches Running status with a seccomp profile active.

**Setup:**

```bash
kubectl create namespace ex-3-1

cat <<'EOF' > /tmp/k8s-ex31-denylist.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {"names": ["ptrace", "mount"], "action": "SCMP_ACT_ERRNO"}
  ]
}
EOF
nerdctl cp /tmp/k8s-ex31-denylist.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex31-denylist.json

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: secured-pod
  namespace: ex-3-1
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex31-wrong-path.json
  containers:
  - name: app
    image: alpine:3.20
    command: [sleep, "3600"]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so the pod reaches Running status with a Localhost seccomp profile active.

**Verification:**

```bash
kubectl get pod secured-pod -n ex-3-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec secured-pod -n ex-3-1 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2
```

---

### Exercise 3.2

**Objective:** The seccomp profile file below contains a JSON error. The pod fails because the kubelet cannot parse the profile. Find and fix the JSON error so the pod starts.

**Setup:**

```bash
kubectl create namespace ex-3-2

cat <<'EOF' > /tmp/k8s-ex32-broken.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {"names": ["ptrace" "mount"], "action": "SCMP_ACT_ERRNO"}
  ]
}
EOF
nerdctl cp /tmp/k8s-ex32-broken.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex32-broken.json

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: json-pod
  namespace: ex-3-2
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex32-broken.json
  containers:
  - name: app
    image: alpine:3.20
    command: [sleep, "3600"]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so the pod reaches Running status.

**Verification:**

```bash
kubectl get pod json-pod -n ex-3-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec json-pod -n ex-3-2 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2
```

---

### Exercise 3.3

**Objective:** A pod using an allow-list seccomp profile is crashing. The profile is too restrictive: it is blocking a syscall the application needs. Find and fix the profile so the pod runs successfully.

**Setup:**

```bash
kubectl create namespace ex-3-3

cat <<'EOF' > /tmp/k8s-ex33-toostrict.json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": [
        "read", "write", "close", "fstat", "mmap", "mprotect", "munmap",
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "access", "getpid", "exit_group", "set_tid_address",
        "set_robust_list", "uname", "prlimit64", "getrandom", "rseq"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex33-toostrict.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex33-toostrict.json

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: strict-pod
  namespace: ex-3-3
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex33-toostrict.json
  containers:
  - name: app
    image: busybox:1.36
    command: [sh, -c, "cat /etc/hostname && echo ready"]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so the pod reaches Succeeded status and the logs show the hostname followed by `ready`.

**Verification:**

```bash
kubectl get pod strict-pod -n ex-3-3 -o jsonpath='{.status.phase}'
# Expected: Succeeded

kubectl logs strict-pod -n ex-3-3
# Expected: Two lines: hostname string then "ready"
```

---

## Level 4: Realistic Scenarios

### Exercise 4.1

**Objective:** Use the SCMP_ACT_LOG discovery workflow to build an allow-list profile for a specific workload. Apply a log-only profile, run the workload, collect syscall numbers from dmesg, map them to names, write an SCMP_ACT_ERRNO allow-list profile, and verify the workload completes under the strict profile.

**Setup:**

```bash
kubectl create namespace ex-4-1

cat <<'EOF' > /tmp/k8s-ex41-logonly.json
{
  "defaultAction": "SCMP_ACT_LOG",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": []
}
EOF
nerdctl cp /tmp/k8s-ex41-logonly.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex41-logonly.json
```

**Task:**

Phase 1: Create a pod named `logger-pod` in `ex-4-1` using `busybox:1.36` with the command `sh -c 'cat /etc/hostname && ls /tmp && echo complete'` and the `k8s-ex41-logonly.json` profile applied at the pod level. Wait for the pod to reach Succeeded status, then collect the SECCOMP audit entries from the kind node's dmesg.

```bash
# Collect syscall numbers logged during the pod's run
nerdctl exec kind-control-plane dmesg | grep "type=1326" | grep -oP "syscall=\K[0-9]+" | sort -n | uniq
```

Phase 2: Map the syscall numbers to names (reference: syscall table entries for x86_64 are in `/usr/include/asm/unistd_64.h` on the kind node or via `ausyscall` if available). Write a new profile named `k8s-ex41-allowlist.json` with `defaultAction: SCMP_ACT_ERRNO` and `SCMP_ACT_ALLOW` for each syscall that appeared in the log. Copy it to the kind node. Delete `logger-pod` and create a new pod named `strict-pod` in `ex-4-1` with the same workload command and the new allow-list profile. Verify the pod reaches Succeeded status.

**Verification:**

```bash
kubectl get pod strict-pod -n ex-4-1 -o jsonpath='{.status.phase}'
# Expected: Succeeded

kubectl logs strict-pod -n ex-4-1
# Expected: Three lines: hostname, a directory listing (may be empty), then "complete"

kubectl exec strict-pod -n ex-4-1 -- cat /proc/self/status 2>/dev/null | grep Seccomp || \
  kubectl get pod strict-pod -n ex-4-1 -o jsonpath='{.spec.securityContext.seccompProfile.type}'
# Expected: Localhost
```

---

### Exercise 4.2

**Objective:** Apply a deny-list seccomp profile to an nginx deployment and verify that the denied syscalls do not interfere with normal nginx operation. Then inspect the kind node's listening services and identify which ports are expected for a Kubernetes node.

**Setup:**

```bash
kubectl create namespace ex-4-2

cat <<'EOF' > /tmp/k8s-ex42-nginxdeny.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": ["ptrace", "mount", "unshare", "pivot_root", "kexec_load", "kexec_file_load"],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex42-nginxdeny.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex42-nginxdeny.json
```

**Task:** Create a pod named `nginx-hardened` in `ex-4-2` using `nginx:1.27` with the `k8s-ex42-nginxdeny.json` profile applied at the pod level. Verify the pod is Running and nginx serves HTTP. Then run `ss -tlnp` on the kind node to list its listening ports and create a ConfigMap named `node-ports` in `ex-4-2` containing a `ports.txt` key whose value is the full output of that command.

**Verification:**

```bash
kubectl get pod nginx-hardened -n ex-4-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec nginx-hardened -n ex-4-2 -- curl -s http://localhost/ | head -3
# Expected: HTML content (non-empty)

kubectl exec nginx-hardened -n ex-4-2 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2

kubectl get configmap node-ports -n ex-4-2 -o jsonpath='{.data.ports\.txt}' | head -3
# Expected: Header line and port listing from ss -tlnp (non-empty)
```

---

### Exercise 4.3

**Objective:** A multi-container pod should have different seccomp profiles for two containers. Apply a Localhost profile at the pod level and a RuntimeDefault profile at the container level for one specific container. Verify the override is in effect.

**Setup:**

```bash
kubectl create namespace ex-4-3

cat <<'EOF' > /tmp/k8s-ex43-podlevel.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {"names": ["ptrace", "mount"], "action": "SCMP_ACT_ERRNO"}
  ]
}
EOF
nerdctl cp /tmp/k8s-ex43-podlevel.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex43-podlevel.json
```

**Task:** Create a pod named `mixed-pod` in `ex-4-3` with two containers: `main` running `nginx:1.27` and `sidecar` running `busybox:1.36` (command: `sleep 3600`). Set the pod-level `seccompProfile` to the `k8s-ex43-podlevel.json` Localhost profile. At the container level for `sidecar` only, set `seccompProfile.type: RuntimeDefault`. Verify that `main` uses the pod-level Localhost profile and `sidecar` uses RuntimeDefault (both should show Seccomp: 2, and the pod-level vs container-level spec paths should confirm the configurations).

**Verification:**

```bash
kubectl get pod mixed-pod -n ex-4-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec mixed-pod -n ex-4-3 -c main -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2

kubectl exec mixed-pod -n ex-4-3 -c sidecar -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2

kubectl get pod mixed-pod -n ex-4-3 -o jsonpath='{.spec.securityContext.seccompProfile.type}'
# Expected: Localhost

kubectl get pod mixed-pod -n ex-4-3 -o jsonpath='{.spec.containers[1].securityContext.seccompProfile.type}'
# Expected: RuntimeDefault
```

---

## Level 5: Advanced Debugging

### Exercise 5.1

**Objective:** A pod running a web server workload has a seccomp allow-list profile applied. The pod starts but fails when handling actual requests. Diagnose which syscall is being denied, add it to the allow-list, and verify the server works correctly.

**Setup:**

```bash
kubectl create namespace ex-5-1

cat <<'EOF' > /tmp/k8s-ex51-incomplete.json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": [
        "read", "write", "open", "close", "stat", "fstat", "lstat",
        "poll", "lseek", "mmap", "mprotect", "munmap", "brk",
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "access", "getpid", "socket", "connect", "sendto", "recvfrom",
        "shutdown", "bind", "listen", "getsockname", "getpeername",
        "setsockopt", "getsockopt", "clone", "execve", "exit_group",
        "fcntl", "ioctl", "pread64", "pwrite64", "readv", "writev",
        "sched_yield", "futex", "set_tid_address", "set_robust_list",
        "epoll_create", "epoll_create1", "epoll_ctl", "epoll_wait",
        "openat", "getdents64", "newfstatat", "prlimit64",
        "getrandom", "rseq", "uname", "pipe", "pipe2",
        "rt_sigsuspend", "sigaltstack",
        "getdents", "clock_gettime", "gettimeofday",
        "getuid", "getgid", "geteuid", "getegid",
        "madvise", "getcwd", "chdir", "sendfile",
        "sysinfo", "prctl", "arch_prctl",
        "munlockall", "mremap"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex51-incomplete.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex51-incomplete.json

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: webserver
  namespace: ex-5-1
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex51-incomplete.json
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

**Task:** The configuration above has one or more problems. The pod may start but nginx cannot serve requests (or may crash). Find and fix whatever is needed so the webserver pod is Running and nginx returns a valid HTTP response.

**Verification:**

```bash
kubectl get pod webserver -n ex-5-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec webserver -n ex-5-1 -- curl -s http://localhost/ | head -3
# Expected: HTML content (non-empty)

kubectl exec webserver -n ex-5-1 -- cat /proc/self/status | grep Seccomp
# Expected: Seccomp:	2
```

---

### Exercise 5.2

**Objective:** A pod has two separate seccomp-related problems. Find and fix both so the pod reaches Succeeded status and produces the expected output.

**Setup:**

```bash
kubectl create namespace ex-5-2

cat <<'EOF' > /tmp/k8s-ex52-allowlist.json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": [
        "read", "write", "openat", "close", "fstat", "newfstatat",
        "mmap", "mprotect", "munmap", "brk",
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "access", "execve", "exit_group", "getpid",
        "set_tid_address", "set_robust_list", "uname",
        "ioctl", "prlimit64", "getrandom", "rseq",
        "futex", "clone3", "clone", "nanosleep"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex52-allowlist.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex52-allowlist.json

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: batch-job
  namespace: ex-5-2
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex52-wrongpath.json
  containers:
  - name: worker
    image: busybox:1.36
    command: [sh, -c, "echo starting && cat /etc/hostname && echo finished"]
EOF
```

**Task:** The configuration above has one or more problems. Find and fix all issues so the `batch-job` pod reaches Succeeded status and the logs show `starting`, the hostname, and `finished`.

**Verification:**

```bash
kubectl get pod batch-job -n ex-5-2 -o jsonpath='{.status.phase}'
# Expected: Succeeded

kubectl logs batch-job -n ex-5-2
# Expected: Three lines: "starting", hostname string, "finished"
```

---

### Exercise 5.3

**Objective:** A pod is crashing intermittently with no obvious error in the container logs. The crash is caused by a seccomp profile denial that only triggers under a specific condition. Diagnose using the kind node's audit log and fix the profile.

**Setup:**

```bash
kubectl create namespace ex-5-3

cat <<'EOF' > /tmp/k8s-ex53-partial.json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "architectures": ["SCMP_ARCH_X86_64", "SCMP_ARCH_X86", "SCMP_ARCH_X32"],
  "syscalls": [
    {
      "names": [
        "read", "write", "openat", "close", "fstat", "newfstatat",
        "mmap", "mprotect", "munmap", "brk",
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "execve", "exit_group",
        "set_tid_address", "set_robust_list", "prlimit64",
        "getrandom", "rseq", "futex", "clone3", "clone",
        "uname", "ioctl"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex53-partial.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex53-partial.json

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: probe-pod
  namespace: ex-5-3
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex53-partial.json
  containers:
  - name: checker
    image: busybox:1.36
    command: [sh, -c, "echo probe-start && cat /etc/hostname && sleep 1 && echo probe-end"]
EOF
```

**Task:** The configuration above has one or more problems. The pod may crash or exit before printing `probe-end`. Find and fix whatever is needed so the probe-pod reaches Succeeded status and the logs show `probe-start`, the hostname, and `probe-end`.

**Verification:**

```bash
kubectl get pod probe-pod -n ex-5-3 -o jsonpath='{.status.phase}'
# Expected: Succeeded

kubectl logs probe-pod -n ex-5-3
# Expected: Three lines: "probe-start", hostname string, "probe-end"
```

---

## Cleanup

Delete all exercise namespaces:

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-3-3 ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3
```

Remove exercise profile files from the kind node:

```bash
for profile in k8s-ex11-seccomp.json k8s-ex13-seccomp.json k8s-ex21-denylist.json k8s-ex22-logptrace.json k8s-ex23-allowlist.json k8s-ex31-denylist.json k8s-ex32-broken.json k8s-ex33-toostrict.json k8s-ex41-logonly.json k8s-ex41-allowlist.json k8s-ex42-nginxdeny.json k8s-ex43-podlevel.json k8s-ex51-incomplete.json k8s-ex52-allowlist.json k8s-ex53-partial.json; do
  nerdctl exec kind-control-plane rm -f /var/lib/kubelet/seccomp/${profile}
done
```

## Key Takeaways

The seccomp profile development cycle follows a consistent pattern that these exercises rehearse: start permissive (SCMP_ACT_LOG or SCMP_ACT_ALLOW as default) to understand what the application actually does, then tighten the profile to block what you do not need (deny-list) or explicitly allow only what you do need (allow-list). The allow-list strategy is stronger because it blocks everything by default, but it requires knowing every syscall the application makes under all conditions, including error paths and edge cases. The deny-list strategy is faster to write and less likely to break the application, but it only blocks known-bad syscalls and misses new attack vectors. In practice, most production hardening starts with RuntimeDefault (a well-maintained deny-list provided by the container runtime) and adds custom deny rules only for specific threats.
