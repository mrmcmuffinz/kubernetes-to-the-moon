# System Hardening Assignment 1: AppArmor Profiles Homework

Complete the tutorial in `system-hardening-tutorial.md` before attempting these exercises. The tutorial covers the profile loading workflow, the difference between complain and enforce modes, and both the `securityContext.appArmorProfile` field and the pre-1.30 annotation syntax. The exercises build on that foundation, so skipping the tutorial will make the debugging exercises harder to diagnose.

Each exercise creates its own isolated namespace. Run the setup commands exactly as shown before attempting the task. For Level 3 and Level 5 exercises, the setup installs a broken configuration; examine the symptoms before looking at the task description.

---

## Level 1: Basic AppArmor Application

### Exercise 1.1

**Objective:** A profile named `k8s-ex11-readonly` has been loaded onto the kind node by the setup commands. Verify that the profile is present, then create a pod that uses it via the `securityContext.appArmorProfile` field. Confirm the pod is running and the profile is active inside the container.

**Setup:**

```bash
kubectl create namespace ex-1-1

cat <<'EOF' > /tmp/k8s-ex11-readonly
#include <tunables/global>
profile k8s-ex11-readonly flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
  network inet6 tcp,
  deny /etc/shadow r,
}
EOF
nerdctl cp /tmp/k8s-ex11-readonly kind-control-plane:/etc/apparmor.d/k8s-ex11-readonly
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex11-readonly
```

**Task:** First, confirm the profile appears in `aa-status` on the kind node. Then create a pod named `webserver` in namespace `ex-1-1` using `nginx:1.27`, applying the `k8s-ex11-readonly` profile at the pod level via `securityContext.appArmorProfile`. The pod must reach Running status and the profile must be active inside the container.

**Verification:**

```bash
nerdctl exec kind-control-plane aa-status | grep k8s-ex11-readonly
# Expected: k8s-ex11-readonly

kubectl get pod webserver -n ex-1-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec webserver -n ex-1-1 -- cat /proc/self/attr/current
# Expected: k8s-ex11-readonly (enforce)
```

---

### Exercise 1.2

**Objective:** Apply an AppArmor profile to a pod using the pre-1.30 annotation syntax. The profile `k8s-ex12-noshadow` is loaded by the setup commands. Create a pod that uses this profile via the `container.apparmor.security.beta.kubernetes.io/<container-name>` annotation. Verify both that the annotation is present on the pod and that the profile is active inside the container.

**Setup:**

```bash
kubectl create namespace ex-1-2

cat <<'EOF' > /tmp/k8s-ex12-noshadow
#include <tunables/global>
profile k8s-ex12-noshadow flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
  deny /etc/shadow r,
  deny /etc/shadow l,
}
EOF
nerdctl cp /tmp/k8s-ex12-noshadow kind-control-plane:/etc/apparmor.d/k8s-ex12-noshadow
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex12-noshadow
```

**Task:** Create a pod named `secured-app` in namespace `ex-1-2` using `busybox:1.36` with the command `sleep 3600`. The container must be named `app`. Apply the `k8s-ex12-noshadow` profile using the annotation `container.apparmor.security.beta.kubernetes.io/app: localhost/k8s-ex12-noshadow`. Do not use the `securityContext.appArmorProfile` field for this exercise.

**Verification:**

```bash
kubectl get pod secured-app -n ex-1-2 -o jsonpath='{.metadata.annotations.container\.apparmor\.security\.beta\.kubernetes\.io/app}'
# Expected: localhost/k8s-ex12-noshadow

kubectl get pod secured-app -n ex-1-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec secured-app -n ex-1-2 -- cat /proc/self/attr/current
# Expected: k8s-ex12-noshadow (enforce)
```

---

### Exercise 1.3

**Objective:** Apply a profile that denies writes to a specific path and verify that enforcement is active by demonstrating that the denied operation fails while normal operations succeed.

**Setup:**

```bash
kubectl create namespace ex-1-3

cat <<'EOF' > /tmp/k8s-ex13-denytest
#include <tunables/global>
profile k8s-ex13-denytest flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /etc/apparmor-blocked w,
  deny /etc/apparmor-blocked a,
}
EOF
nerdctl cp /tmp/k8s-ex13-denytest kind-control-plane:/etc/apparmor.d/k8s-ex13-denytest
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex13-denytest
```

**Task:** Create a pod named `alpine-test` in namespace `ex-1-3` using `alpine:3.20` with the command `sleep 3600`. Apply the `k8s-ex13-denytest` profile via the `securityContext.appArmorProfile` field. After the pod starts, verify enforcement: confirm that writing to `/etc/apparmor-blocked` fails and that writing to `/tmp/allowed-write` succeeds.

**Verification:**

```bash
kubectl get pod alpine-test -n ex-1-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec alpine-test -n ex-1-3 -- cat /proc/self/attr/current
# Expected: k8s-ex13-denytest (enforce)

kubectl exec alpine-test -n ex-1-3 -- sh -c 'touch /etc/apparmor-blocked 2>&1; echo "exit:$?"'
# Expected: touch: /etc/apparmor-blocked: Permission denied followed by exit:1

kubectl exec alpine-test -n ex-1-3 -- sh -c 'echo ok > /tmp/allowed-write && echo write_success'
# Expected: write_success
```

---

## Level 2: Profile Authoring

### Exercise 2.1

**Objective:** Write an AppArmor profile named `k8s-ex21-webguard` from scratch. The profile must include `#include <abstractions/base>`, use `file,` as the baseline allow rule, and add explicit deny rules for writes to `/etc/**` (both write and append modes). Load the profile onto the kind node, apply it to an nginx pod, and verify the pod starts correctly with the profile active.

**Setup:**

```bash
kubectl create namespace ex-2-1
```

**Task:** Write the profile file `/tmp/k8s-ex21-webguard` with the requirements above. Load it into the kind node, create a pod named `nginx` in `ex-2-1` using `nginx:1.27` with the `k8s-ex21-webguard` profile applied via `securityContext.appArmorProfile`. Verify the pod is Running and the profile is in enforce mode inside the container. Also confirm that a write attempt to `/etc/test-write` fails.

**Verification:**

```bash
nerdctl exec kind-control-plane aa-status | grep k8s-ex21-webguard
# Expected: k8s-ex21-webguard

kubectl get pod nginx -n ex-2-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec nginx -n ex-2-1 -- cat /proc/self/attr/current
# Expected: k8s-ex21-webguard (enforce)

kubectl exec nginx -n ex-2-1 -- sh -c 'touch /etc/test-write 2>&1; echo "exit:$?"'
# Expected: touch: /etc/test-write: Permission denied followed by exit:1
```

---

### Exercise 2.2

**Objective:** Write and load a profile in complain mode. Verify that operations the profile would deny in enforce mode are allowed in complain mode, and confirm the profile appears in the complain section of `aa-status`.

**Setup:**

```bash
kubectl create namespace ex-2-2
```

**Task:** Write a profile named `k8s-ex22-complain` with `flags=(attach_disconnected,complain)`. The profile should include `#include <abstractions/base>`, use `file,` as the baseline, and add a deny rule for writes to `/etc/**`. Load it onto the kind node. Create a pod named `alpine-log` in `ex-2-2` using `alpine:3.20` with the command `sleep 3600`, applying the `k8s-ex22-complain` profile. Verify the profile appears in the complain section of `aa-status`, confirm the pod is Running, and demonstrate that a write to `/etc/complain-test` succeeds (because complain mode does not block).

**Verification:**

```bash
nerdctl exec kind-control-plane aa-status | grep -A1 "complain mode"
# Expected: Output includes k8s-ex22-complain

kubectl get pod alpine-log -n ex-2-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec alpine-log -n ex-2-2 -- cat /proc/self/attr/current
# Expected: k8s-ex22-complain (complain)

kubectl exec alpine-log -n ex-2-2 -- sh -c 'echo test > /etc/complain-test && echo write_allowed'
# Expected: write_allowed (succeeds because complain mode logs but does not block)
```

---

### Exercise 2.3

**Objective:** Write a profile for a read-only utility container. The profile should allow reads from `/etc/**` and deny writes to `/**` (all paths). Apply it to an alpine pod in enforce mode, verify the pod starts, verify that reading `/etc/hostname` works, and verify that writing to `/tmp/test` fails.

**Setup:**

```bash
kubectl create namespace ex-2-3
```

**Task:** Write a profile named `k8s-ex23-utilbox` with `flags=(attach_disconnected)`. Include `#include <abstractions/base>` and use `file,` as the baseline (so reads everywhere are allowed). Add deny rules for writes to `/**` and appends to `/**`. Load the profile onto the kind node and create a pod named `utility` in `ex-2-3` using `alpine:3.20` with the command `sleep 3600`. Apply the profile at the pod level via `securityContext.appArmorProfile`. Verify the pod is running, reads succeed, and write attempts fail.

**Verification:**

```bash
kubectl get pod utility -n ex-2-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec utility -n ex-2-3 -- cat /proc/self/attr/current
# Expected: k8s-ex23-utilbox (enforce)

kubectl exec utility -n ex-2-3 -- cat /etc/hostname
# Expected: the pod's hostname (a non-empty string)

kubectl exec utility -n ex-2-3 -- sh -c 'echo test > /tmp/test 2>&1; echo "exit:$?"'
# Expected: Permission denied message followed by exit:1
```

---

## Level 3: Debugging Broken Configurations

### Exercise 3.1

**Objective:** The configuration below has a problem preventing the pod from running. Find and fix whatever is needed so the pod reaches Running status.

**Setup:**

```bash
kubectl create namespace ex-3-1

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

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so the pod reaches Running status and the profile is active inside the container.

**Verification:**

```bash
kubectl get pod webapp -n ex-3-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec webapp -n ex-3-1 -- cat /proc/self/attr/current
# Expected: k8s-ex31-webapp (enforce)
```

---

### Exercise 3.2

**Objective:** The configuration below has a problem preventing the pod from running. Find and fix whatever is needed so the pod reaches Running status.

**Setup:**

```bash
kubectl create namespace ex-3-2

cat <<'EOF' > /tmp/k8s-ex32-secured
#include <tunables/global>
profile k8s-ex32-secured flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
}
EOF
nerdctl cp /tmp/k8s-ex32-secured kind-control-plane:/etc/apparmor.d/k8s-ex32-secured
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex32-secured

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
      localhostProfile: k8s-ex32-secure
  containers:
  - name: api
    image: nginx:1.27
EOF
```

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so the pod reaches Running status with the correct profile active.

**Verification:**

```bash
kubectl get pod api-server -n ex-3-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec api-server -n ex-3-2 -- cat /proc/self/attr/current
# Expected: k8s-ex32-secured (enforce)
```

---

### Exercise 3.3

**Objective:** The nginx pod below has an AppArmor profile applied but the pod is not healthy. Find and fix whatever is needed so nginx is Running and serving HTTP requests.

**Setup:**

```bash
kubectl create namespace ex-3-3

cat <<'EOF' > /tmp/k8s-ex33-webserver
#include <tunables/global>
profile k8s-ex33-webserver flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
  deny /etc/nginx/mime.types r,
}
EOF
nerdctl cp /tmp/k8s-ex33-webserver kind-control-plane:/etc/apparmor.d/k8s-ex33-webserver
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex33-webserver

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

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so the nginx pod is Running and responds to HTTP requests.

**Verification:**

```bash
kubectl get pod webserver -n ex-3-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec webserver -n ex-3-3 -- curl -s http://localhost/ | head -3
# Expected: HTML content (non-empty, beginning with <!DOCTYPE or <html)

kubectl exec webserver -n ex-3-3 -- cat /proc/self/attr/current
# Expected: k8s-ex33-webserver (enforce)
```

---

## Level 4: Realistic Scenarios

### Exercise 4.1

**Objective:** Write a complete AppArmor profile for an nginx web server that enforces a minimal allow-list: reads from the nginx configuration directory, reads from the web content directory, writes to the log directory, writes to the PID file location, writes to temporary and cache directories, and TCP network access. Deny writes to `/etc/**`. Load the profile, apply it to an nginx pod, and verify the server starts and serves requests.

**Setup:**

```bash
kubectl create namespace ex-4-1
```

**Task:** Write a profile named `k8s-ex41-nginx` in enforce mode. The profile must include `#include <abstractions/base>` and add explicit allow rules for:
- `/etc/nginx/**` (read)
- `/usr/share/nginx/html/**` (read)
- `/var/log/nginx/**` (write)
- `/var/run/nginx.pid` and `/run/nginx.pid` (write)
- `/var/cache/nginx/**` (read and write)
- `/tmp/**` (read and write)
- `/usr/sbin/nginx` (memory-map and read)
- `/usr/lib/**` and `/lib/**` and `/lib64/**` (memory-map and read)
- `network inet tcp` and `network inet6 tcp`

Add a deny rule for writes to `/etc/**`. Load the profile, create a pod named `nginx-secured` in `ex-4-1` using `nginx:1.27`, apply the profile, and verify nginx serves requests.

**Verification:**

```bash
nerdctl exec kind-control-plane aa-status | grep k8s-ex41-nginx
# Expected: k8s-ex41-nginx

kubectl get pod nginx-secured -n ex-4-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec nginx-secured -n ex-4-1 -- cat /proc/self/attr/current
# Expected: k8s-ex41-nginx (enforce)

kubectl exec nginx-secured -n ex-4-1 -- curl -s http://localhost/ | head -3
# Expected: HTML content (non-empty)

kubectl exec nginx-secured -n ex-4-1 -- sh -c 'touch /etc/injected 2>&1; echo "exit:$?"'
# Expected: Permission denied followed by exit:1
```

---

### Exercise 4.2

**Objective:** Apply two different AppArmor profiles to two pods running in the same namespace. One pod runs a permissive profile (all file operations allowed, no network). One pod runs a write-deny profile (all reads allowed, writes denied everywhere). Verify each pod has its respective profile active and that enforcement matches expectations.

**Setup:**

```bash
kubectl create namespace ex-4-2

cat <<'EOF' > /tmp/k8s-ex42-permissive
#include <tunables/global>
profile k8s-ex42-permissive flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
}
EOF
nerdctl cp /tmp/k8s-ex42-permissive kind-control-plane:/etc/apparmor.d/k8s-ex42-permissive
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex42-permissive

cat <<'EOF' > /tmp/k8s-ex42-nodeny
#include <tunables/global>
profile k8s-ex42-nodeny flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /** w,
  deny /** a,
}
EOF
nerdctl cp /tmp/k8s-ex42-nodeny kind-control-plane:/etc/apparmor.d/k8s-ex42-nodeny
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex42-nodeny
```

**Task:** Create a pod named `permissive-pod` in `ex-4-2` using `busybox:1.36` with the command `sleep 3600`, applying the `k8s-ex42-permissive` profile. Create a second pod named `readonly-pod` in `ex-4-2` using `busybox:1.36` with the command `sleep 3600`, applying the `k8s-ex42-nodeny` profile. Verify each pod has its correct profile active, and verify that `readonly-pod` cannot write to `/tmp/testfile` while `permissive-pod` can.

**Verification:**

```bash
kubectl exec permissive-pod -n ex-4-2 -- cat /proc/self/attr/current
# Expected: k8s-ex42-permissive (enforce)

kubectl exec readonly-pod -n ex-4-2 -- cat /proc/self/attr/current
# Expected: k8s-ex42-nodeny (enforce)

kubectl exec permissive-pod -n ex-4-2 -- sh -c 'echo ok > /tmp/testfile && echo write_success'
# Expected: write_success

kubectl exec readonly-pod -n ex-4-2 -- sh -c 'echo ok > /tmp/testfile 2>&1; echo "exit:$?"'
# Expected: Permission denied followed by exit:1
```

---

### Exercise 4.3

**Objective:** Apply per-container AppArmor profiles in a multi-container pod. The container-level `securityContext.appArmorProfile` field overrides the pod-level field. Create a pod with two containers, each using a different AppArmor profile applied at the container level.

**Setup:**

```bash
kubectl create namespace ex-4-3

cat <<'EOF' > /tmp/k8s-ex43-frontend
#include <tunables/global>
profile k8s-ex43-frontend flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
  network inet6 tcp,
}
EOF
nerdctl cp /tmp/k8s-ex43-frontend kind-control-plane:/etc/apparmor.d/k8s-ex43-frontend
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex43-frontend

cat <<'EOF' > /tmp/k8s-ex43-sidecar
#include <tunables/global>
profile k8s-ex43-sidecar flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /** w,
  deny /** a,
}
EOF
nerdctl cp /tmp/k8s-ex43-sidecar kind-control-plane:/etc/apparmor.d/k8s-ex43-sidecar
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex43-sidecar
```

**Task:** Create a pod named `multi-container` in namespace `ex-4-3`. The pod must have two containers: `frontend` running `nginx:1.27` with the `k8s-ex43-frontend` profile applied at the container level, and `sidecar` running `busybox:1.36` (command: `sleep 3600`) with the `k8s-ex43-sidecar` profile applied at the container level. Both `securityContext.appArmorProfile` fields must be set at the container level, not the pod level. Verify each container has its respective profile active.

**Verification:**

```bash
kubectl get pod multi-container -n ex-4-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec multi-container -n ex-4-3 -c frontend -- cat /proc/self/attr/current
# Expected: k8s-ex43-frontend (enforce)

kubectl exec multi-container -n ex-4-3 -c sidecar -- cat /proc/self/attr/current
# Expected: k8s-ex43-sidecar (enforce)

kubectl exec multi-container -n ex-4-3 -c sidecar -- sh -c 'echo test > /tmp/sidefile 2>&1; echo "exit:$?"'
# Expected: Permission denied followed by exit:1

kubectl exec multi-container -n ex-4-3 -c frontend -- curl -s http://localhost/ | head -3
# Expected: HTML content (non-empty)
```

---

## Level 5: Advanced Debugging

### Exercise 5.1

**Objective:** A pod is crashing because its AppArmor profile is too restrictive. Diagnose which operations are being denied, use complain mode to identify the access the application actually needs, write a corrected enforce-mode profile, and verify the application runs cleanly.

**Setup:**

```bash
kubectl create namespace ex-5-1

kubectl create configmap app-script -n ex-5-1 --from-literal=run.sh='#!/bin/sh
cat /etc/hostname
echo "$(date): Application started" >> /var/log/appdata/app.log
cat /etc/os-release | head -3
echo "Application ready"
'

cat <<'EOF' > /tmp/k8s-ex51-appserver
#include <tunables/global>
profile k8s-ex51-appserver flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  deny /var/log/appdata/** w,
  deny /var/log/appdata/** a,
}
EOF
nerdctl cp /tmp/k8s-ex51-appserver kind-control-plane:/etc/apparmor.d/k8s-ex51-appserver
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex51-appserver

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

**Task:** The configuration above has one or more problems. Find and fix whatever is needed so the appserver pod completes successfully (status Completed or remains Running). You must identify which AppArmor denials are causing the failure, write a corrected profile, and apply it.

**Verification:**

```bash
kubectl get pod appserver -n ex-5-1 -o jsonpath='{.status.phase}'
# Expected: Succeeded (or Running if you modify the script to loop)

kubectl logs appserver -n ex-5-1 -c app
# Expected: Logs showing "Application started", os-release content, and "Application ready"

kubectl exec appserver -n ex-5-1 -c app -- cat /proc/self/attr/current 2>/dev/null || kubectl logs appserver -n ex-5-1 -c app | grep -c "Application ready"
# Expected: Profile name visible or log count is 1 (application completed at least once)
```

---

### Exercise 5.2

**Objective:** A pod has multiple AppArmor-related problems preventing it from running correctly. Find and fix all issues so the pod reaches Running status with a working nginx serving HTTP traffic.

**Setup:**

```bash
kubectl create namespace ex-5-2

cat <<'EOF' > /tmp/k8s-ex52-service
#include <tunables/global>
profile k8s-ex52-service flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
  network inet6 tcp,
  deny /etc/nginx/mime.types r,
  deny /var/run/nginx.pid w,
  deny /run/nginx.pid w,
}
EOF
nerdctl cp /tmp/k8s-ex52-service kind-control-plane:/etc/apparmor.d/k8s-ex52-service
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex52-service

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

**Task:** The configuration above has one or more problems. Find and fix all issues so the `service-pod` reaches Running status and nginx responds to HTTP requests.

**Verification:**

```bash
kubectl get pod service-pod -n ex-5-2 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec service-pod -n ex-5-2 -- curl -s http://localhost/ | head -3
# Expected: HTML content (non-empty)

kubectl exec service-pod -n ex-5-2 -- cat /proc/self/attr/current
# Expected: k8s-ex52-service (enforce)
```

---

### Exercise 5.3

**Objective:** A multi-container pod has AppArmor problems affecting both containers. Find and fix all issues so both containers are Running with their respective profiles active.

**Setup:**

```bash
kubectl create namespace ex-5-3

cat <<'EOF' > /tmp/k8s-ex53-front
#include <tunables/global>
profile k8s-ex53-front flags=(attach_disconnected) {
  #include <abstractions/base>
  file,
  network inet tcp,
  network inet6 tcp,
  deny /var/log/nginx/** w,
  deny /var/log/nginx/** a,
}
EOF
nerdctl cp /tmp/k8s-ex53-front kind-control-plane:/etc/apparmor.d/k8s-ex53-front
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/k8s-ex53-front

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

**Task:** The configuration above has one or more problems. Find and fix all issues so both the `frontend` container (nginx serving HTTP) and the `monitor` container (busybox) are Running with their respective profiles active.

**Verification:**

```bash
kubectl get pod gateway-pod -n ex-5-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl exec gateway-pod -n ex-5-3 -c frontend -- cat /proc/self/attr/current
# Expected: k8s-ex53-front (enforce)

kubectl exec gateway-pod -n ex-5-3 -c monitor -- cat /proc/self/attr/current
# Expected: k8s-ex53-monitor (enforce)

kubectl exec gateway-pod -n ex-5-3 -c frontend -- curl -s http://localhost/ | head -3
# Expected: HTML content (non-empty)
```

---

## Cleanup

Delete all exercise namespaces after completing the exercises:

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-3-3 ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3
```

To also unload exercise profiles from the kind node:

```bash
for profile in k8s-ex11-readonly k8s-ex12-noshadow k8s-ex13-denytest k8s-ex21-webguard k8s-ex22-complain k8s-ex23-utilbox k8s-ex31-webapp k8s-ex32-secured k8s-ex33-webserver k8s-ex41-nginx k8s-ex42-permissive k8s-ex42-nodeny k8s-ex43-frontend k8s-ex43-sidecar k8s-ex51-appserver k8s-ex52-service k8s-ex53-front k8s-ex53-monitor; do
  nerdctl exec kind-control-plane apparmor_parser -R /etc/apparmor.d/${profile} 2>/dev/null || true
done
```

## Key Takeaways

Working through these exercises reinforces several skills that the CKA/CKS exam tests. The profile loading workflow (copy file to node, parse it, verify in aa-status) is a repeatable three-step sequence that you must execute correctly before any pod that references a profile can start. The distinction between the profile file name on disk and the profile name declared inside the file is a common source of errors: the pod spec references the declared name, not the filename. Complain mode is your primary tool when a profile is too restrictive and you need to understand what the application actually accesses before tightening the rules. The three-stage debugging approach (check pod status and events, check node-level profile status, check container logs) covers the majority of AppArmor failures you will encounter.
