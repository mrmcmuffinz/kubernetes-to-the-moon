# System Hardening Assignment 2: Custom Seccomp Profiles Answer Key

---

## Exercise 1.1 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: alpine-secured
  namespace: ex-1-1
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex11-seccomp.json
  containers:
  - name: alpine
    image: alpine:3.20
    command: [sleep, "3600"]
EOF
```

The `localhostProfile` value is the path relative to `/var/lib/kubelet/seccomp/` inside the kind node. Since the file was copied directly to that directory root, the value is just the filename. The Seccomp value of `2` in `/proc/self/status` confirms that a seccomp filter is active (mode 2 means BPF filter mode, which covers both RuntimeDefault and Localhost profiles). Value `0` means disabled (Unconfined), value `1` means strict mode (legacy, rarely used in containers).

---

## Exercise 1.2 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: runtime-pod
  namespace: ex-1-2
spec:
  securityContext:
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: busybox:1.36
    command: [sleep, "3600"]
EOF

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: unconfined-pod
  namespace: ex-1-2
spec:
  securityContext:
    seccompProfile:
      type: Unconfined
  containers:
  - name: app
    image: busybox:1.36
    command: [sleep, "3600"]
EOF
```

RuntimeDefault uses the container runtime's built-in seccomp profile. Containerd ships with a profile that blocks a list of syscalls known to be dangerous or unnecessary for typical container workloads (including `ptrace`, `kexec_load`, `mount` without flags, and others). The process still gets Seccomp: 2 because a BPF filter is installed. With Unconfined, no filter is installed and the process reads Seccomp: 0, meaning every syscall is permitted. The difference in the Seccomp field is the clearest observable distinction between these two types.

---

## Exercise 1.3 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: override-pod
  namespace: ex-1-3
spec:
  securityContext:
    seccompProfile:
      type: Unconfined
  containers:
  - name: alpine
    image: alpine:3.20
    command: [sleep, "3600"]
    securityContext:
      seccompProfile:
        type: Localhost
        localhostProfile: k8s-ex13-seccomp.json
EOF
```

The container-level `securityContext.seccompProfile` always takes precedence over the pod-level field for that specific container. The pod-level field acts as a default that applies to any container without its own override. Here, the pod-level `Unconfined` setting never applies to the `alpine` container because the container-level `Localhost` override is present. This means the pod spec shows `Unconfined` at the pod level while the container actually runs with a BPF filter installed (Seccomp: 2).

---

## Exercise 2.1 Solution

```bash
cat <<'EOF' > /tmp/k8s-ex21-denylist.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": [
    {
      "names": ["ptrace", "mount", "unshare", "pivot_root"],
      "action": "SCMP_ACT_ERRNO"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex21-denylist.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex21-denylist.json

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nginx-secured
  namespace: ex-2-1
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex21-denylist.json
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

nginx does not call `ptrace`, `mount`, `unshare`, or `pivot_root` during normal operation, so the deny rules do not affect nginx's ability to start or serve requests. The deny-list strategy is appropriate when you know which specific syscalls to block (typically dangerous administrative operations) but do not want to audit every syscall the application makes. The profile allows all syscalls not explicitly listed, which means unknown-bad syscalls that are not in the deny list are still permitted. RuntimeDefault from containerd is a more carefully maintained deny list that covers a wider set of known-dangerous syscalls, which is why RuntimeDefault is recommended as the baseline for most workloads.

---

## Exercise 2.2 Solution

```bash
cat <<'EOF' > /tmp/k8s-ex22-logptrace.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": [
    "SCMP_ARCH_X86_64",
    "SCMP_ARCH_X86",
    "SCMP_ARCH_X32"
  ],
  "syscalls": [
    {
      "names": ["ptrace"],
      "action": "SCMP_ACT_LOG"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex22-logptrace.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex22-logptrace.json

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: log-watcher
  namespace: ex-2-2
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex22-logptrace.json
  containers:
  - name: alpine
    image: alpine:3.20
    command: [sleep, "3600"]
EOF
```

The `SCMP_ACT_LOG` action permits the syscall and writes a kernel audit event. This is distinct from `SCMP_ACT_ALLOW` (permits silently) and `SCMP_ACT_ERRNO` (denies with error). SCMP_ACT_LOG is useful during monitoring of production workloads when you suspect a process is making a syscall but want to confirm before blocking it. When checking dmesg after running `ls /` inside the pod, you may or may not see a ptrace audit entry: `ls` does not typically call ptrace, so the log entry appears only when the process itself or the container runtime invokes ptrace. The absence of a log entry is itself informative: it confirms the observed workload does not use that syscall.

---

## Exercise 2.3 Solution

```bash
cat <<'EOF' > /tmp/k8s-ex23-allowlist.json
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
        "read", "write", "openat", "close", "fstat", "newfstatat",
        "mmap", "mprotect", "munmap", "brk",
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "access", "execve", "exit_group", "getpid",
        "getuid", "getgid", "geteuid", "getegid",
        "set_tid_address", "set_robust_list", "uname",
        "ioctl", "prlimit64", "getrandom", "rseq",
        "futex", "clone3", "clone", "arch_prctl",
        "madvise", "lstat", "stat"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex23-allowlist.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex23-allowlist.json

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: cat-pod
  namespace: ex-2-3
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex23-allowlist.json
  containers:
  - name: app
    image: busybox:1.36
    command: [sh, -c, "cat /etc/hostname && echo done"]
EOF
```

The allow-list strategy requires identifying every syscall the application makes under all conditions it will encounter. The list above covers the syscalls busybox sh and cat need on x86_64. If the allow-list is incomplete and the pod crashes, switch the `defaultAction` to `SCMP_ACT_LOG`, recreate the pod, run the workload, check `dmesg | grep "type=1326"` for logged syscall numbers, map those numbers to names, add the names to the allow list, switch back to `SCMP_ACT_ERRNO`, and iterate. The allow-list above may include more syscalls than strictly necessary; in production you would run the workload through all its code paths under the log profile before finalizing the allow list.

---

## Exercise 3.1 Solution

**Diagnosis:**

```bash
kubectl get pod secured-pod -n ex-3-1
# Shows: ContainerCreating or pending without progressing

kubectl describe pod secured-pod -n ex-3-1
# Expected: Event like:
# Warning  Failed   kubelet  Error: failed to create containerd container for [app]:
#   failed to generate spec: cannot load seccomp profile "/var/lib/kubelet/seccomp/k8s-ex31-wrong-path.json": ...

nerdctl exec kind-control-plane ls /var/lib/kubelet/seccomp/
# Expected: k8s-ex31-denylist.json is listed but k8s-ex31-wrong-path.json is NOT
```

**What the bug is and why it happens:** The pod spec has `localhostProfile: k8s-ex31-wrong-path.json`, but the file was copied to the kind node as `k8s-ex31-denylist.json`. The kubelet looks for the profile at `/var/lib/kubelet/seccomp/k8s-ex31-wrong-path.json`, which does not exist. Unlike AppArmor (where the profile name is declared inside the file), seccomp uses the file path as the identifier. A mismatch between the pod spec path and the actual file path produces a "cannot load seccomp profile" error. The pod stays in ContainerCreating indefinitely because the kubelet cannot proceed without the profile.

**Fix:**

Delete the pod and recreate it with the correct `localhostProfile`:

```bash
kubectl delete pod secured-pod -n ex-3-1

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
      localhostProfile: k8s-ex31-denylist.json
  containers:
  - name: app
    image: alpine:3.20
    command: [sleep, "3600"]
EOF
```

---

## Exercise 3.2 Solution

**Diagnosis:**

```bash
kubectl get pod json-pod -n ex-3-2
# Shows: ContainerCreating or Error

kubectl describe pod json-pod -n ex-3-2
# Expected: Event containing "invalid seccomp profile" or "cannot unmarshal" or "invalid character"
# The exact message depends on the containerd version but it will reference a JSON parse error

# Verify the JSON is invalid by printing the file content
nerdctl exec kind-control-plane cat /var/lib/kubelet/seccomp/k8s-ex32-broken.json
# Expected: Output shows "ptrace" "mount" without a comma between the strings
```

**What the bug is and why it happens:** The JSON array in the `names` field has two string values without a comma separator: `["ptrace" "mount"]`. Valid JSON arrays require commas between elements: `["ptrace", "mount"]`. The kubelet passes the profile content to containerd when creating the container, and containerd's JSON parser rejects the malformed input. The error message usually contains "invalid character" or similar phrasing that points to a JSON parsing failure rather than a missing file.

**Fix:**

Correct the JSON and recopy the profile, then delete and recreate the pod:

```bash
cat <<'EOF' > /tmp/k8s-ex32-broken.json
{
  "defaultAction": "SCMP_ACT_ALLOW",
  "architectures": ["SCMP_ARCH_X86_64"],
  "syscalls": [
    {"names": ["ptrace", "mount"], "action": "SCMP_ACT_ERRNO"}
  ]
}
EOF
nerdctl cp /tmp/k8s-ex32-broken.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex32-broken.json

kubectl delete pod json-pod -n ex-3-2
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

JSON syntax errors in seccomp profiles are common because the files are written by hand and the JSON format is unforgiving. Always validate profile JSON before copying to the node: `python3 -m json.tool /tmp/profile.json` or `jq . /tmp/profile.json` will catch syntax errors before you waste time debugging a pod creation failure.

---

## Exercise 3.3 Solution

**Diagnosis:**

```bash
kubectl get pod strict-pod -n ex-3-3
# Shows: CrashLoopBackOff or Error

kubectl logs strict-pod -n ex-3-3
# Expected: Empty or partial output, followed by exit code 1
# The shell may not even produce output if basic syscalls fail

kubectl describe pod strict-pod -n ex-3-3
# Events: Container "app" exited with non-zero exit code

# Switch to SCMP_ACT_LOG temporarily to observe what is denied
nerdctl exec kind-control-plane dmesg | grep "type=1326" | tail -30
# Expected: Multiple lines showing denied syscalls (look for execve, openat, brk)
```

**What the bug is and why it happens:** The allow-list profile for this exercise is missing several syscalls that busybox sh and the `cat` command require to function. The most critical missing syscalls are `execve` (needed for the shell to exec the `cat` binary), `openat` (needed for opening `/etc/hostname`), and `brk` (needed for heap memory allocation). Without `execve`, the shell cannot run `cat /etc/hostname` at all. Without `openat`, file opens fail. Without `brk`, memory allocation for the shell itself fails. The process exits immediately with a non-zero code because the kernel blocks these fundamental operations at startup.

**Fix:**

Add the missing syscalls and update the profile. The minimum additions are `execve`, `openat`, `brk`, `futex`, `clone`, and `clone3`. A comprehensive fix adds all commonly needed syscalls:

```bash
cat <<'EOF' > /tmp/k8s-ex33-toostrict.json
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
        "getuid", "getgid", "geteuid", "getegid",
        "set_tid_address", "set_robust_list", "uname",
        "ioctl", "prlimit64", "getrandom", "rseq",
        "futex", "clone3", "clone", "arch_prctl",
        "lstat", "stat"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex33-toostrict.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex33-toostrict.json

kubectl delete pod strict-pod -n ex-3-3
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

---

## Exercise 4.1 Solution

Phase 1: Apply the log-only profile and collect syscall numbers.

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: logger-pod
  namespace: ex-4-1
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex41-logonly.json
  containers:
  - name: worker
    image: busybox:1.36
    command: [sh, -c, "cat /etc/hostname && ls /tmp && echo complete"]
EOF

kubectl wait --for=condition=Ready pod/logger-pod -n ex-4-1 --timeout=60s
kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/logger-pod -n ex-4-1 --timeout=60s

nerdctl exec kind-control-plane dmesg | grep "type=1326" | grep -oP "syscall=\K[0-9]+" | sort -n | uniq
```

The syscall numbers you collect will vary depending on the kernel version and the container runtime. Common syscall numbers on x86_64 you should see include entries from this reference:

| Number | Name | Number | Name |
|--------|------|--------|------|
| 0 | read | 12 | brk |
| 1 | write | 21 | access |
| 3 | close | 39 | getpid |
| 5 | fstat | 59 | execve |
| 9 | mmap | 231 | exit_group |
| 10 | mprotect | 257 | openat |
| 11 | munmap | 262 | newfstatat |

Phase 2: Write the allow-list profile and verify.

```bash
cat <<'EOF' > /tmp/k8s-ex41-allowlist.json
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
        "read", "write", "openat", "close", "fstat", "newfstatat",
        "mmap", "mprotect", "munmap", "brk",
        "rt_sigaction", "rt_sigprocmask", "rt_sigreturn",
        "access", "execve", "exit_group", "getpid",
        "getuid", "getgid", "geteuid", "getegid",
        "set_tid_address", "set_robust_list", "uname",
        "ioctl", "prlimit64", "getrandom", "rseq",
        "futex", "clone3", "clone", "arch_prctl",
        "lstat", "stat", "getdents64"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex41-allowlist.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex41-allowlist.json

kubectl delete pod logger-pod -n ex-4-1

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: strict-pod
  namespace: ex-4-1
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex41-allowlist.json
  containers:
  - name: worker
    image: busybox:1.36
    command: [sh, -c, "cat /etc/hostname && ls /tmp && echo complete"]
EOF
```

If `strict-pod` crashes, check `dmesg | grep "type=1326"` again for newly denied syscalls, add their names to the allow list, and iterate. The allow-list profile development cycle is inherently iterative: SCMP_ACT_LOG reveals syscalls, you allow them, SCMP_ACT_ERRNO reveals any you missed, you add those too.

---

## Exercise 4.2 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nginx-hardened
  namespace: ex-4-2
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex42-nginxdeny.json
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

After verifying nginx is Running and serving:

```bash
# Capture the ss output and create the ConfigMap
NODE_PORTS=$(nerdctl exec kind-control-plane ss -tlnp)

kubectl create configmap node-ports -n ex-4-2 \
  --from-literal="ports.txt=${NODE_PORTS}"
```

The `ss -tlnp` output on a kind node typically shows ports for the Kubernetes API server (6443), kubelet (10250 and 10255), and any CNI-specific listeners. Ports like 2379/2380 (etcd) are expected on a single-node cluster running the control plane. In a production cluster security audit, you would verify that no unexpected ports appear in this list and that all listening services are documented. Creating the ConfigMap with the port listing is a concrete deliverable that proves you inspected the node state.

---

## Exercise 4.3 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: mixed-pod
  namespace: ex-4-3
spec:
  securityContext:
    seccompProfile:
      type: Localhost
      localhostProfile: k8s-ex43-podlevel.json
  containers:
  - name: main
    image: nginx:1.27
  - name: sidecar
    image: busybox:1.36
    command: [sleep, "3600"]
    securityContext:
      seccompProfile:
        type: RuntimeDefault
EOF
```

The `main` container has no container-level `securityContext.seccompProfile`, so it inherits the pod-level Localhost profile. The `sidecar` container has a container-level `securityContext.seccompProfile.type: RuntimeDefault`, which overrides the pod-level Localhost profile for that container only. Both containers show Seccomp: 2 because both RuntimeDefault and Localhost install BPF filters. The distinction is visible in the pod spec fields: `spec.securityContext.seccompProfile.type` shows `Localhost` (the pod-level), and `spec.containers[1].securityContext.seccompProfile.type` shows `RuntimeDefault` (the sidecar override). The containers array index for `sidecar` is 1 because `main` is index 0.

---

## Exercise 5.1 Solution

**Diagnosis:**

```bash
kubectl get pod webserver -n ex-5-1 -o jsonpath='{.status.phase}'
# Shows: Running (the pod started, nginx bound to port 80)

kubectl exec webserver -n ex-5-1 -- curl -s --max-time 5 http://localhost/
# Expected: curl times out or returns "Connection refused"
# nginx is listening but cannot accept connections

kubectl exec webserver -n ex-5-1 -- curl -v --max-time 5 http://localhost/ 2>&1 | tail -5
# Expected: connection hangs or is refused

# Check dmesg for SECCOMP denials generated by nginx
nerdctl exec kind-control-plane dmesg | grep "type=1326" | grep -i nginx | tail -20
# Expected: Lines containing syscall=288 (accept4) for comm="nginx"
# syscall 288 on x86_64 is accept4
```

**What the bug is and why it happens:** The allow-list profile for this exercise is missing the `accept4` syscall (syscall number 288 on x86_64). nginx uses `accept4()` (not the older `accept()`) to accept new TCP connections from clients. The nginx worker processes bind to port 80, call `listen()`, and then enter an epoll event loop. When the event loop wakes because a new connection is ready (epoll_wait returns), nginx calls `accept4()` to obtain the client socket. The seccomp profile allows `epoll_wait` and `bind` and `listen`, so nginx starts and the port appears open. But when a client connects, nginx's `accept4()` call is blocked by the seccomp filter, which means no connections are actually accepted. The request never reaches nginx's HTTP handler, so curl sees the connection hang or reset.

**Fix:**

Add `accept4` to the allow-list, update the profile, and restart the pod:

```bash
cat /tmp/k8s-ex51-incomplete.json | python3 -c "
import json, sys
profile = json.load(sys.stdin)
profile['syscalls'][0]['names'].append('accept4')
profile['syscalls'][0]['names'].append('accept')
print(json.dumps(profile, indent=2))
" > /tmp/k8s-ex51-fixed.json

nerdctl cp /tmp/k8s-ex51-fixed.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex51-incomplete.json

kubectl delete pod webserver -n ex-5-1
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

Alternatively, write a completely new profile file including `accept4` in the allow list. After the fix, nginx can accept connections and serve HTTP responses. This exercise illustrates a subtle class of seccomp bugs: the pod is Running and the port is open, but the application fails silently when a specific code path (accepting a connection) triggers a blocked syscall. The symptom (connection refused or timeout) is indistinguishable from a network misconfiguration without checking the SECCOMP audit log.

---

## Exercise 5.2 Solution

**Diagnosis:**

```bash
kubectl get pod batch-job -n ex-5-2
# Shows: Pending or ContainerCreating

kubectl describe pod batch-job -n ex-5-2
# Expected: Event like:
# Warning  Failed  kubelet  Error: failed to create containerd container for [worker]:
#   failed to generate spec: cannot load seccomp profile
#   "/var/lib/kubelet/seccomp/k8s-ex52-wrongpath.json": ...

nerdctl exec kind-control-plane ls /var/lib/kubelet/seccomp/ | grep k8s-ex52
# Expected: k8s-ex52-allowlist.json (correct file)
# k8s-ex52-wrongpath.json does NOT appear
```

**What the bug is and why it happens:** The pod spec has `localhostProfile: k8s-ex52-wrongpath.json`, but the profile file was copied to the kind node as `k8s-ex52-allowlist.json`. The kubelet resolves the profile path to `/var/lib/kubelet/seccomp/k8s-ex52-wrongpath.json`, which does not exist. The container creation fails with a "cannot load seccomp profile" error. This is the same class of error as Exercise 3.1 but using a different naming mismatch pattern. The fix is straightforward: update the pod spec to reference the file that actually exists.

**Fix:**

```bash
kubectl delete pod batch-job -n ex-5-2

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
      localhostProfile: k8s-ex52-allowlist.json
  containers:
  - name: worker
    image: busybox:1.36
    command: [sh, -c, "echo starting && cat /etc/hostname && echo finished"]
EOF
```

The `k8s-ex52-allowlist.json` profile includes enough syscalls for the busybox workload to complete successfully.

---

## Exercise 5.3 Solution

**Diagnosis:**

```bash
kubectl get pod probe-pod -n ex-5-3 -o jsonpath='{.status.phase}'
# Shows: Failed or Error (after briefly running)

kubectl logs probe-pod -n ex-5-3
# Expected: probe-start and hostname appear, but probe-end does NOT
# The pod failed after cat /etc/hostname but before echo probe-end
# The failure point is at "sleep 1"

kubectl logs probe-pod -n ex-5-3 --previous 2>/dev/null | tail -5
# May show the same partial output from previous runs

# Check SECCOMP audit log for denied syscalls
nerdctl exec kind-control-plane dmesg | grep "type=1326" | tail -20
# Expected: Lines showing syscall=35 (nanosleep) for comm="sleep"
# syscall 35 on x86_64 is nanosleep
```

**What the bug is and why it happens:** The allow-list profile is missing `nanosleep` (syscall number 35 on x86_64). The workload command is `echo probe-start && cat /etc/hostname && sleep 1 && echo probe-end`. The first two commands succeed (they use read, write, openat, execve, which are all in the allow list). When the shell reaches `sleep 1`, busybox executes the `sleep` binary, which calls `nanosleep()` to pause for one second. The seccomp profile's `SCMP_ACT_ERRNO` default action blocks `nanosleep`, causing `sleep` to fail with EPERM. Since the command uses `&&` chaining, the failure of `sleep 1` prevents `echo probe-end` from running. The container exits with a non-zero code, which can look like an intermittent problem because the pod runs for a short time before failing.

**Fix:**

Add `nanosleep` to the allow-list profile:

```bash
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
        "uname", "ioctl",
        "nanosleep"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
EOF
nerdctl cp /tmp/k8s-ex53-partial.json kind-control-plane:/var/lib/kubelet/seccomp/k8s-ex53-partial.json

kubectl delete pod probe-pod -n ex-5-3
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

This exercise models a real class of seccomp failures: the pod appears to start successfully, runs for a period of time, and then exits due to a blocked syscall that is only triggered by a specific code path (in this case, a time.sleep call). In production workloads, the "code path only triggered under load" scenario from the prompt description looks similar: the application handles basic requests but fails when a specific operation (such as a timer, a file rotation, or a network retry) triggers a syscall that is not in the allow list. The diagnostic approach is always the same: check `dmesg | grep "type=1326"` for denied syscalls, correlate the `comm=` field with the process name you expect, and map the `syscall=` number to a name to know what to add.

---

## Common Mistakes

**Forgetting to delete and recreate the pod after changing a seccomp profile.** Unlike AppArmor, seccomp profiles are read from the JSON file at container creation time. If you update the JSON file on the node and recopy it, running containers are not affected. The pod must be deleted and recreated to pick up the updated profile. This is the most common source of confusion when iterating on a profile: you update the file, the pod keeps failing, and you assume the update had no effect.

**Confusing the profile file path with the localhostProfile value.** The `localhostProfile` field in the pod spec is a relative path from `/var/lib/kubelet/seccomp/`. If the file is at `/var/lib/kubelet/seccomp/profiles/myapp.json`, the `localhostProfile` must be `profiles/myapp.json`, not the full path and not just `myapp.json`. Always verify the exact path with `nerdctl exec kind-control-plane ls /var/lib/kubelet/seccomp/` before writing the pod spec.

**Writing a deny-list and assuming it provides meaningful security.** A deny-list profile that blocks `ptrace`, `mount`, and `unshare` does not block the hundreds of other syscalls that can be used in creative ways by an attacker with code execution inside the container. A deny-list is better than nothing (RuntimeDefault covers the most obvious dangerous syscalls), but an allow-list profile that explicitly permits only the syscalls the application needs provides significantly stronger isolation. Knowing which strategy to use, and being able to build allow-list profiles using the SCMP_ACT_LOG discovery workflow, is the key skill this assignment develops.

**Using `SCMP_ACT_KILL` as the default action in a production allow-list.** SCMP_ACT_KILL terminates the process immediately with SIGSYS (exit code 159) when a disallowed syscall is attempted. Unlike SCMP_ACT_ERRNO (which returns an error the application can handle), SCMP_ACT_KILL gives the application no opportunity to clean up or log the failure. This is appropriate for the most critical security contexts (you want to prevent the process from doing anything after the disallowed syscall), but it makes debugging much harder because the only visible symptom is an unexpected exit code 159. SCMP_ACT_ERRNO is the safer starting point; switch to SCMP_ACT_KILL only after thorough testing confirms the allow-list is complete.

**Not accounting for indirect syscalls made by the language runtime or libc.** The application developer writes code that calls `time.Sleep(1 * time.Second)` in Go, or `time.sleep(1)` in Python. The developer does not write `nanosleep`. But at the kernel level, `time.sleep` translates to `nanosleep` (on Linux). When building an allow-list profile, you must understand not just the application-level API calls but every syscall those calls translate to, including those made by the runtime, the standard library, and the container entrypoint process. The SCMP_ACT_LOG discovery workflow captures this automatically; a profile written from documentation alone often misses syscalls at this layer.

---

## Verification Commands Cheat Sheet

| Task | Command |
|------|---------|
| List seccomp profiles on kind node | `nerdctl exec kind-control-plane ls /var/lib/kubelet/seccomp/` |
| Copy a profile to the kind node | `nerdctl cp /tmp/profile.json kind-control-plane:/var/lib/kubelet/seccomp/profile.json` |
| Remove a profile from the kind node | `nerdctl exec kind-control-plane rm /var/lib/kubelet/seccomp/profile.json` |
| Check seccomp is active in a container | `kubectl exec <pod> -- cat /proc/self/status \| grep Seccomp` |
| Check pod-level seccompProfile | `kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.securityContext.seccompProfile}'` |
| Check container-level seccompProfile | `kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[0].securityContext.seccompProfile}'` |
| View SECCOMP audit events on node | `nerdctl exec kind-control-plane dmesg \| grep "type=1326"` |
| Extract unique denied syscall numbers | `nerdctl exec kind-control-plane dmesg \| grep "type=1326" \| grep -oP "syscall=\K[0-9]+" \| sort -n \| uniq` |
| Map syscall number to name (node) | `nerdctl exec kind-control-plane grep -r "__NR_<name>" /usr/include/asm/ 2>/dev/null` |
| Validate profile JSON locally | `python3 -m json.tool /tmp/profile.json` |
| Check listening ports on kind node | `nerdctl exec kind-control-plane ss -tlnp` |
| View running processes on kind node | `nerdctl exec kind-control-plane ps aux` |
| Describe pod for profile load errors | `kubectl describe pod <pod> -n <ns>` |
| Get pod logs for crash diagnosis | `kubectl logs <pod> -n <ns> [--previous]` |
| Wait for pod to complete | `kubectl wait --for=jsonpath='{.status.phase}'=Succeeded pod/<name> -n <ns> --timeout=120s` |
