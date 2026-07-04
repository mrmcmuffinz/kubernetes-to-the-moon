# System Hardening Assignment 1: AppArmor Profiles Answer Key

---

## Exercise 1.1 Solution

The setup already loaded the profile `k8s-ex11-readonly` onto the kind node. The task is to verify it is there and create a pod that uses it.

Verify the profile:

```bash
nerdctl exec kind-control-plane aa-status | grep k8s-ex11-readonly
```

Create the pod:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: webserver
  namespace: ex-1-1
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex11-readonly
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

The `securityContext.appArmorProfile` field at the pod level applies the profile to all containers in the pod. `type: Localhost` means the profile is loaded on the node (as opposed to `RuntimeDefault` or `Unconfined`). The `localhostProfile` value must match the declared profile name inside the profile file exactly.

---

## Exercise 1.2 Solution

The pre-1.30 annotation syntax requires an annotation key that embeds the container name. The annotation format is:

```
container.apparmor.security.beta.kubernetes.io/<container-name>: localhost/<profile-name>
```

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: secured-app
  namespace: ex-1-2
  annotations:
    container.apparmor.security.beta.kubernetes.io/app: localhost/k8s-ex12-noshadow
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: [sleep, "3600"]
EOF
```

The container name in the annotation key (`app`) must exactly match the container name in the pod spec. If they do not match, the annotation is silently ignored (the container runs unconfined) rather than causing a scheduling failure. The value `localhost/k8s-ex12-noshadow` tells the kubelet to look for a locally loaded profile named `k8s-ex12-noshadow`.

---

## Exercise 1.3 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: alpine-test
  namespace: ex-1-3
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex13-denytest
  containers:
  - name: alpine
    image: alpine:3.20
    command: [sleep, "3600"]
EOF
```

After the pod starts, the deny rule for `/etc/apparmor-blocked` is active. Any write attempt to that specific path returns EACCES because the `deny` rule in the profile overrides the `file,` catch-all. The `/tmp/allowed-write` path is not covered by any deny rule, so writes there succeed normally.

The `cat /proc/self/attr/current` command reads the AppArmor label for the current process from the kernel's security filesystem. The output includes both the profile name and the mode in parentheses, making it the most reliable way to confirm which profile is active for a given container.

---

## Exercise 2.1 Solution

Write the profile:

```bash
cat <<'EOF' > /tmp/k8s-ex21-webguard
#include <tunables/global>
profile k8s-ex21-webguard flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /etc/** w,
  deny /etc/** a,
}
EOF
```

Load the profile:

```bash
nerdctl cp /tmp/k8s-ex21-webguard kind-control-plane:/etc/apparmor.d/k8s-ex21-webguard
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex21-webguard
```

Create the pod:

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: ex-2-1
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex21-webguard
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

The `deny /etc/** w,` and `deny /etc/** a,` rules override the `file,` catch-all for write and append operations in the `/etc/` tree. The `/etc/**` glob matches everything recursively under `/etc/`. Reads from `/etc/nginx/` still work because the deny rules only cover write and append, not read. nginx reads its configuration from `/etc/nginx/`, so this profile allows nginx to start while preventing any process inside the container from modifying configuration files.

---

## Exercise 2.2 Solution

Write the complain-mode profile:

```bash
cat <<'EOF' > /tmp/k8s-ex22-complain
#include <tunables/global>
profile k8s-ex22-complain flags=(attach_disconnected,complain) {
  #include <abstractions/base>
  file,
  deny /etc/** w,
  deny /etc/** a,
}
EOF
```

Load and apply:

```bash
nerdctl cp /tmp/k8s-ex22-complain kind-control-plane:/etc/apparmor.d/k8s-ex22-complain
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex22-complain

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: alpine-log
  namespace: ex-2-2
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex22-complain
  containers:
  - name: alpine
    image: alpine:3.20
    command: [sleep, "3600"]
EOF
```

In complain mode, writing to `/etc/complain-test` succeeds even though the profile has a deny rule for `/etc/**`. The kernel allows the operation but records an audit event. The audit event can be seen in the node's dmesg output (`nerdctl exec kind-control-plane dmesg | grep -i apparmor`). The `aa-status` output lists the profile under "complain mode profiles" rather than "enforce mode profiles". Complain mode is the standard starting point for iterative profile development: let the application run, observe what it accesses in the audit log, and add those accesses as explicit allow rules before converting to enforce mode.

---

## Exercise 2.3 Solution

```bash
cat <<'EOF' > /tmp/k8s-ex23-utilbox
#include <tunables/global>
profile k8s-ex23-utilbox flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /** w,
  deny /** a,
}
EOF
nerdctl cp /tmp/k8s-ex23-utilbox kind-control-plane:/etc/apparmor.d/k8s-ex23-utilbox
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex23-utilbox

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: utility
  namespace: ex-2-3
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex23-utilbox
  containers:
  - name: alpine
    image: alpine:3.20
    command: [sleep, "3600"]
EOF
```

The `deny /** w,` and `deny /** a,` rules deny writes and appends to all paths. The `/**` glob matches everything on the filesystem, making this a global write-deny profile. Reads still succeed because there is no deny rule for reads. The container itself starts because the alpine:3.20 image's entrypoint (`sleep 3600`) does not need to write any files during normal operation. Applications that write PID files, temp files, or log files would crash under this profile.

---

## Exercise 3.1 Solution

**Diagnosis:**

```bash
kubectl get pod webapp -n ex-3-1
# Shows: ContainerCreating or Error or similar non-Running status

kubectl describe pod webapp -n ex-3-1
# Look at Events section
# Expected: A Warning event with message containing "AppArmor profile not found"
# or "failed to load AppArmor profile"

nerdctl exec kind-control-plane aa-status | grep k8s-ex31-webapp
# Expected: (empty - the profile is not loaded)
```

**What the bug is and why it happens:** The pod spec references `localhostProfile: k8s-ex31-webapp`, but this profile was never loaded onto the kind node. The kubelet checks whether the requested profile exists in the kernel's AppArmor subsystem before creating the container. When the profile is missing, the kubelet cannot create the container and the pod stays in ContainerCreating (or transitions to an error state) with an event describing the missing profile. The profile file was referenced in the pod spec but the three-step loading workflow (copy, parse, verify) was never performed.

**Fix:**

Write and load the profile, then delete and recreate the pod:

```bash
cat <<'EOF' > /tmp/k8s-ex31-webapp
#include <tunables/global>
profile k8s-ex31-webapp flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
}
EOF
nerdctl cp /tmp/k8s-ex31-webapp kind-control-plane:/etc/apparmor.d/k8s-ex31-webapp
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex31-webapp

kubectl delete pod webapp -n ex-3-1
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: webapp
  namespace: ex-3-1
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex31-webapp
  containers:
  - name: webserver
    image: nginx:1.27
EOF
```

After loading the profile, you must delete and recreate the pod. The kubelet checks profile availability when creating the container; it does not retry automatically after a ContainerCreating failure.

---

## Exercise 3.2 Solution

**Diagnosis:**

```bash
kubectl get pod api-server -n ex-3-2
# Shows: ContainerCreating or Error

kubectl describe pod api-server -n ex-3-2
# Expected: Event mentioning AppArmor profile "k8s-ex32-secure" not found

nerdctl exec kind-control-plane aa-status | grep k8s-ex32
# Expected: k8s-ex32-secured (note the 'd' at the end)
# The loaded profile is k8s-ex32-secured but the pod references k8s-ex32-secure
```

**What the bug is and why it happens:** The pod spec has `localhostProfile: k8s-ex32-secure` (without the trailing `d`). The profile loaded on the node is named `k8s-ex32-secured` (with the trailing `d`). These are different profile names. AppArmor performs an exact string match between the name in the pod spec and the name declared inside the profile file. A single character difference means the profile is not found, producing the same error as Exercise 3.1. This type of typo is easy to make when the profile file name on disk looks similar to the declared profile name but differs in a subtle way.

**Fix:**

Delete the pod, correct the `localhostProfile` value, and recreate:

```bash
kubectl delete pod api-server -n ex-3-2

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: api-server
  namespace: ex-3-2
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex32-secured
  containers:
  - name: api
    image: nginx:1.27
EOF
```

The profile name in `localhostProfile` must match the `profile` keyword name inside the `.d` file exactly. The filename on disk is a convention; the declared name is what matters.

---

## Exercise 3.3 Solution

**Diagnosis:**

```bash
kubectl get pod webserver -n ex-3-3
# Shows: CrashLoopBackOff or Error

kubectl logs webserver -n ex-3-3
# Expected: nginx error like:
# nginx: [emerg] open() "/etc/nginx/mime.types" failed (13: Permission denied)

kubectl describe pod webserver -n ex-3-3
# Events may show container exit code 1
```

**What the bug is and why it happens:** The profile has the rule `deny /etc/nginx/mime.types r,`. The nginx default configuration file (`/etc/nginx/nginx.conf`) includes the line `include /etc/nginx/mime.types;`. When nginx starts, it reads its configuration and tries to open `/etc/nginx/mime.types` for reading. The AppArmor deny rule blocks this read even though the broader `file,` rule would otherwise allow all file reads. The `deny` keyword takes precedence over any prior allow rule. nginx fails to parse its configuration, exits with a non-zero code, and the container enters CrashLoopBackOff.

**Fix:**

Remove the deny rule from the profile, reload it, and delete the pod so it restarts:

```bash
cat <<'EOF' > /tmp/k8s-ex33-webserver
#include <tunables/global>
profile k8s-ex33-webserver flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
}
EOF
nerdctl cp /tmp/k8s-ex33-webserver kind-control-plane:/etc/apparmor.d/k8s-ex33-webserver
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex33-webserver

kubectl delete pod webserver -n ex-3-3
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: webserver
  namespace: ex-3-3
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex33-webserver
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

Reloading a profile with `apparmor_parser -r` updates the profile in the kernel immediately, but the running container is not affected. You must delete and recreate the pod to pick up the updated profile.

---

## Exercise 4.1 Solution

```bash
cat <<'EOF' > /tmp/k8s-ex41-nginx
#include <tunables/global>
profile k8s-ex41-nginx flags=(attach_disconnected) {
  #include <abstractions/base>

  # nginx configuration (read-only)
  /etc/nginx/** r,

  # web content (read-only)
  /usr/share/nginx/html/** r,

  # logs (write)
  /var/log/nginx/** w,

  # PID file (write)
  /var/run/nginx.pid w,
  /run/nginx.pid w,

  # cache and temp (read/write)
  /var/cache/nginx/** rw,
  /tmp/** rw,

  # nginx binary and shared libraries
  /usr/sbin/nginx mr,
  /usr/lib/** mr,
  /lib/** mr,
  /lib64/** mr,

  # kernel proc paths for nginx worker processes
  /proc/*/net/** r,
  /proc/sys/kernel/** r,

  # network
  network inet tcp,
  network inet6 tcp,

  # deny writes to config directory
  deny /etc/** w,
  deny /etc/** a,
}
EOF
nerdctl cp /tmp/k8s-ex41-nginx kind-control-plane:/etc/apparmor.d/k8s-ex41-nginx
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex41-nginx

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nginx-secured
  namespace: ex-4-1
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex41-nginx
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

This profile demonstrates the real-world complexity of writing a minimal nginx allow-list. The `/usr/sbin/nginx mr,` rule allows the nginx binary to be memory-mapped with execute permission (`m`) and read (`r`). Without the `m` permission, the dynamic linker cannot execute the binary from memory. The `/usr/lib/** mr,` rules allow loading shared libraries. The `deny /etc/** w,` and `deny /etc/** a,` rules override the more specific `/etc/nginx/** r,` allow only for writes, not for reads, so nginx can still read its configuration.

---

## Exercise 4.2 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: permissive-pod
  namespace: ex-4-2
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex42-permissive
  containers:
  - name: app
    image: busybox:1.36
    command: [sleep, "3600"]
EOF

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: readonly-pod
  namespace: ex-4-2
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex42-nodeny
  containers:
  - name: app
    image: busybox:1.36
    command: [sleep, "3600"]
EOF
```

Both pods run in the same namespace with different AppArmor profiles. The profile applies to the container process, not the namespace or node, so two pods in the same namespace can have completely different security postures. The `k8s-ex42-permissive` profile uses `file,` alone (no deny rules), so all file operations succeed. The `k8s-ex42-nodeny` profile adds `deny /** w,` and `deny /** a,` to block all writes across the entire filesystem hierarchy.

---

## Exercise 4.3 Solution

```bash
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: multi-container
  namespace: ex-4-3
spec:
  containers:
  - name: frontend
    image: nginx:1.27
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: k8s-ex43-frontend
  - name: sidecar
    image: busybox:1.36
    command: [sleep, "3600"]
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: k8s-ex43-sidecar
EOF
```

When `securityContext.appArmorProfile` is set at the container level, it takes precedence over any pod-level setting. Here there is no pod-level `securityContext.appArmorProfile`, so each container is assigned its profile independently. Each container in the pod runs as a separate process and receives its own AppArmor label from the kubelet when the container is created. The `/proc/self/attr/current` output from each container will show the respective profile name, confirming that AppArmor tracking is per-process, not per-pod.

---

## Exercise 5.1 Solution

**Diagnosis:**

```bash
kubectl get pod appserver -n ex-5-1
# Shows: CrashLoopBackOff or Error

kubectl logs appserver -n ex-5-1 -c app
# Expected: Output stops after "cat /etc/hostname" because the next line
# (writing to /var/log/appdata/app.log) fails with permission denied
# The script exits non-zero, causing the container to crash

kubectl describe pod appserver -n ex-5-1
# Events: Container "app" exited with code 1
```

**What the bug is and why it happens:** The profile `k8s-ex51-appserver` has `deny /var/log/appdata/** w,` and `deny /var/log/appdata/** a,`. The application script's second line is `echo "$(date): Application started" >> /var/log/appdata/app.log`, which uses the append operator (`>>`). AppArmor denies the append operation because of the deny rule. The script exits with a non-zero status code, which causes the container to exit, which causes the pod to enter CrashLoopBackOff.

**Fix:**

Switch to complain mode to confirm the denial, then write a corrected profile that allows writes to `/var/log/appdata/**`:

```bash
# First, switch to complain mode to observe the denied operations
cat <<'EOF' > /tmp/k8s-ex51-appserver
#include <tunables/global>
profile k8s-ex51-appserver flags=(attach_disconnected,complain) {
  #include <abstractions/base>
  file,
  deny /var/log/appdata/** w,
  deny /var/log/appdata/** a,
}
EOF
nerdctl cp /tmp/k8s-ex51-appserver kind-control-plane:/etc/apparmor.d/k8s-ex51-appserver
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex51-appserver

kubectl delete pod appserver -n ex-5-1
# Recreate with same manifest (setup commands above)
# The pod will now succeed in complain mode
# Check audit logs to confirm the denial that was occurring:
nerdctl exec kind-control-plane dmesg | grep -i apparmor | grep appdata | tail -5
# Expected: Lines showing operation="file_append" or similar, profile="k8s-ex51-appserver"
```

Write the corrected enforce-mode profile:

```bash
cat <<'EOF' > /tmp/k8s-ex51-appserver
#include <tunables/global>
profile k8s-ex51-appserver flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
}
EOF
nerdctl cp /tmp/k8s-ex51-appserver kind-control-plane:/etc/apparmor.d/k8s-ex51-appserver
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex51-appserver

kubectl delete pod appserver -n ex-5-1

kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: appserver
  namespace: ex-5-1
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex51-appserver
  initContainers:
  - name: setup
    image: busybox:1.36
    command: [sh, -c, "mkdir -p /var/log/appdata"]
    volumeMounts:
    - name: logdir
      mountPath: /var/log/appdata
  containers:
  - name: app
    image: alpine:3.20
    command: [sh, /scripts/run.sh]
    volumeMounts:
    - name: scripts
      mountPath: /scripts
    - name: logdir
      mountPath: /var/log/appdata
  volumes:
  - name: scripts
    configMap:
      name: app-script
      defaultMode: 0755
  - name: logdir
    emptyDir: {}
EOF
```

The corrected profile uses `file,` without any deny rules, which grants all file permissions. In a production hardening scenario you would use the complain mode audit logs to identify exactly which operations the application needs and add only those as explicit allow rules rather than using the catch-all `file,`. For this exercise, the important lesson is the workflow: crash in enforce mode, switch to complain to observe what is denied, write a corrected profile, return to enforce mode.

---

## Exercise 5.2 Solution

**Diagnosis:**

```bash
kubectl get pod service-pod -n ex-5-2
# Shows: CrashLoopBackOff

kubectl logs service-pod -n ex-5-2
# Expected: nginx error output
# nginx: [emerg] open() "/etc/nginx/mime.types" failed (13: Permission denied)
# This is one error. After fixing it, you may also see:
# nginx: [emerg] open() "/var/run/nginx.pid" failed (13: Permission denied)

# Or both errors may appear together if nginx fails before writing the pid file
```

**What the bug is and why it happens:** The profile `k8s-ex52-service` has two deny rules that together make nginx impossible to start. The first deny rule, `deny /etc/nginx/mime.types r,`, prevents nginx from reading its MIME types file, which is included from the default `nginx.conf`. This causes nginx to fail at configuration parse time with a permission denied error on the MIME types file. The second deny rule, `deny /var/run/nginx.pid w,` and `deny /run/nginx.pid w,`, prevents nginx from writing its PID file, which nginx also requires during startup. Either rule alone would be sufficient to crash nginx; both together mean nginx fails before it can even attempt to bind to a port.

**Fix:**

Remove both deny rules from the profile, reload it, and restart the pod:

```bash
cat <<'EOF' > /tmp/k8s-ex52-service
#include <tunables/global>
profile k8s-ex52-service flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
  network inet6 tcp,
}
EOF
nerdctl cp /tmp/k8s-ex52-service kind-control-plane:/etc/apparmor.d/k8s-ex52-service
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex52-service

kubectl delete pod service-pod -n ex-5-2
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: service-pod
  namespace: ex-5-2
spec:
  securityContext:
    appArmorProfile:
      type: Localhost
      localhostProfile: k8s-ex52-service
  containers:
  - name: nginx
    image: nginx:1.27
EOF
```

The corrected profile retains the network access rules (needed for nginx to bind and accept connections) while removing the two deny rules that were blocking essential file operations. When debugging CrashLoopBackOff with AppArmor profiles, always check `kubectl logs` first since the application's own error messages often name the file or operation that is being denied before the container exits.

---

## Exercise 5.3 Solution

**Diagnosis:**

```bash
kubectl get pod gateway-pod -n ex-5-3
# Shows: Pending or ContainerCreating or CrashLoopBackOff

kubectl describe pod gateway-pod -n ex-5-3
# Expected: Events section shows two issues:
# 1. Warning for "monitor" container: AppArmor profile "k8s-ex53-monitor" not found
# 2. If the pod does start (it may not due to issue 1), nginx logs show CrashLoopBackOff

kubectl logs gateway-pod -n ex-5-3 -c frontend 2>/dev/null || true
# If the frontend container ever started and logged before crashing:
# nginx: [emerg] open() "/var/log/nginx/error.log" failed (13: Permission denied)

nerdctl exec kind-control-plane aa-status | grep k8s-ex53
# Expected: k8s-ex53-front appears, k8s-ex53-monitor does NOT appear
```

**What the bugs are and why they happen:** There are two separate issues. First, the `monitor` container references `k8s-ex53-monitor` as its AppArmor profile, but this profile was never loaded onto the kind node. The kubelet cannot create either container in the pod until all profile references are resolvable, so the entire pod may fail to start. Second, the `k8s-ex53-front` profile has deny rules for `/var/log/nginx/** w,` and `/var/log/nginx/** a,`. nginx writes both `access.log` and `error.log` to `/var/log/nginx/` during startup and on every request. The deny rule blocks these writes, causing nginx to crash with permission denied when it tries to open its log files.

**Fix:**

Create the missing `k8s-ex53-monitor` profile, fix the `k8s-ex53-front` profile by removing the deny rules, reload both, then recreate the pod:

```bash
cat <<'EOF' > /tmp/k8s-ex53-front
#include <tunables/global>
profile k8s-ex53-front flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
  network inet6 tcp,
}
EOF
nerdctl cp /tmp/k8s-ex53-front kind-control-plane:/etc/apparmor.d/k8s-ex53-front
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex53-front

cat <<'EOF' > /tmp/k8s-ex53-monitor
#include <tunables/global>
profile k8s-ex53-monitor flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
}
EOF
nerdctl cp /tmp/k8s-ex53-monitor kind-control-plane:/etc/apparmor.d/k8s-ex53-monitor
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex53-monitor

kubectl delete pod gateway-pod -n ex-5-3
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: gateway-pod
  namespace: ex-5-3
spec:
  containers:
  - name: frontend
    image: nginx:1.27
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: k8s-ex53-front
  - name: monitor
    image: busybox:1.36
    command: [sleep, "3600"]
    securityContext:
      appArmorProfile:
        type: Localhost
        localhostProfile: k8s-ex53-monitor
EOF
```

This exercise illustrates that AppArmor issues in multi-container pods require checking both the pod-level events and per-container logs. The missing profile for one container can prevent the entire pod from starting (depending on kubelet implementation), so the presence of one working container does not guarantee the other is running correctly. Always verify both containers with `cat /proc/self/attr/current` after a fix.

---

## Common Mistakes

**Forgetting `flags=(attach_disconnected)` in container profiles.** AppArmor profiles written for standalone processes on a host do not include this flag. When used in Kubernetes containers (which run in mount namespaces detached from the root), the profile may not attach at all, leaving the container unconfined without any error. Always include `flags=(attach_disconnected)` in profiles intended for containers.

**Confusing the profile filename with the declared profile name.** The file at `/etc/apparmor.d/my-profile` can contain `profile different-name flags=(...) {...}`. The pod spec `localhostProfile` must match the declared name (`different-name`), not the filename (`my-profile`). Keeping these identical (filename matches the declared name) avoids the confusion, but you must still know which one matters when debugging.

**Not restarting the pod after reloading a profile.** `apparmor_parser -r` updates the profile in the kernel, but the running container was already assigned a profile label at start time. The container's AppArmor label does not update automatically when the profile changes. You must delete and recreate the pod to pick up the new profile version. This is a frequent source of confusion when iterating on a profile: you reload the profile, the pod keeps crashing, and you assume the reload had no effect -- but actually the old container is still running under the old profile.

**Using `deny` rules without understanding that they override `file,`.** A profile with `file,` followed by `deny /etc/** w,` restricts writes to `/etc/**` even though `file,` would otherwise allow them. Conversely, a profile that lacks `file,` and only has explicit allow rules for certain paths will deny everything not explicitly listed. Both patterns are valid, but mixing them incorrectly (for example, adding a deny rule for a path that is not already allowed) can make a profile appear more restrictive than it is, or the deny can be redundant and give a false sense of security.

**Applying AppArmor profiles to pods scheduled on nodes where the profile is not loaded.** A single-node kind cluster has only one node, so this is not an issue in exercises. In a real multi-node cluster, the profile must be loaded on every node where the pod might be scheduled. Forgetting to load the profile on a new node after a node scale-out causes pods that were previously Running to fail if they are rescheduled to the new node.

**Writing deny rules with paths that do not match container filesystem layout.** A profile that denies `/var/log/nginx/**` works correctly for the official nginx image because nginx logs there. A custom application that logs to `/app/logs/` would not be affected by that deny rule. Always verify the actual paths the application uses (via complain mode audit logs or by examining the container filesystem) before writing path-based deny rules.

---

## Verification Commands Cheat Sheet

| Task | Command |
|------|---------|
| Check all loaded profiles and modes | `nerdctl exec kind-control-plane aa-status` |
| Check whether a specific profile is loaded | `nerdctl exec kind-control-plane aa-status \| grep <profile-name>` |
| Copy a profile file to the kind node | `nerdctl cp /tmp/<profile> kind-control-plane:/etc/apparmor.d/<profile>` |
| Load or reload a profile into the kernel | `nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/<profile>` |
| Unload a profile from the kernel | `nerdctl exec kind-control-plane apparmor_parser -R /etc/apparmor.d/<profile>` |
| Check which profile is active in a container | `kubectl exec <pod> [-c <container>] -- cat /proc/self/attr/current` |
| Check pod's appArmorProfile field | `kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.securityContext.appArmorProfile}'` |
| Check container-level appArmorProfile | `kubectl get pod <pod> -n <ns> -o jsonpath='{.spec.containers[0].securityContext.appArmorProfile}'` |
| Check pre-1.30 annotation | `kubectl get pod <pod> -n <ns> -o jsonpath='{.metadata.annotations}'` |
| View AppArmor audit events on node | `nerdctl exec kind-control-plane dmesg \| grep -i apparmor` |
| View AppArmor events via journalctl | `nerdctl exec kind-control-plane journalctl -k \| grep -i apparmor \| tail -20` |
| Test a denied write operation | `kubectl exec <pod> -- sh -c 'touch /path/to/file 2>&1; echo "exit:$?"'` |
| Describe pod for AppArmor events | `kubectl describe pod <pod> -n <ns>` |
| Get pod logs for crash diagnosis | `kubectl logs <pod> -n <ns> [-c <container>] --previous` |
