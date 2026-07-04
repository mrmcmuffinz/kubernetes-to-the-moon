# Container Images Homework Answers

Complete solutions for all 15 exercises. For Level 3 and Level 5 debugging exercises, each answer follows a three-stage structure: diagnosis (the exact commands to run and what output to look for), bug explanation (what is wrong and why it happens), and fix (the corrected configuration with the commands to apply it).

---

## Exercise 1.1 Solution

**Dockerfile:**

```bash
cat > ~/ex-1-1/Dockerfile << 'EOF'
FROM busybox:1.36

WORKDIR /app

COPY hello.sh /app/hello.sh

ENV GREETING="Hello from the container"

EXPOSE 8080

CMD ["/app/hello.sh"]
EOF
```

**Build:**

```bash
chmod +x ~/ex-1-1/hello.sh
nerdctl build -t ex-1-1:v1 ~/ex-1-1/
```

The chmod step is necessary because the script is copied into the image as-is. If it lacks execute permission in the build context, the CMD will fail with "permission denied" even though the file is present. An alternative is to add `RUN chmod +x /app/hello.sh` in the Dockerfile after the COPY, which is cleaner because the Dockerfile is self-contained. Either approach produces a working image.

Note that WORKDIR is declared before COPY, which means the COPY destination `/app/hello.sh` is relative to the WORKDIR already set. You could equivalently write `COPY hello.sh /app/hello.sh` with an absolute destination or `COPY hello.sh hello.sh` with a WORKDIR-relative destination; all three resolve to the same path.

---

## Exercise 1.2 Solution

**Dockerfile:**

```bash
cat > ~/ex-1-2/Dockerfile << 'EOF'
FROM busybox:1.36

LABEL org.opencontainers.image.title="label-demo"
LABEL org.opencontainers.image.version="2.0.0"
LABEL org.opencontainers.image.description="Demonstrates OCI label annotations"

CMD ["echo", "labels present"]
EOF

nerdctl build -t ex-1-2:v1 ~/ex-1-2/
```

LABEL instructions can be combined on a single instruction with backslash continuation, but multiple LABEL instructions also work correctly. In modern BuildKit-based builds, multiple LABEL instructions do not create multiple layers; the metadata is merged into a single configuration entry. The separate-instruction style is more readable when each label has a long key or value.

The CMD uses exec form (`["echo", "labels present"]`) rather than shell form (`echo "labels present"`). Both work for this simple case, but exec form is the consistent choice across all exercises.

---

## Exercise 1.3 Solution

**Dockerfile:**

```bash
cat > ~/ex-1-3/Dockerfile << 'EOF'
FROM alpine:3.20

WORKDIR /reports/monthly

CMD ["pwd"]
EOF

nerdctl build -t ex-1-3:v1 ~/ex-1-3/
```

WORKDIR creates all intermediate directories in the path if they do not already exist. The alpine:3.20 base image has no `/reports` directory; WORKDIR creates it along with the `monthly` subdirectory in a single instruction. This is equivalent to a preceding `RUN mkdir -p /reports/monthly` followed by `WORKDIR /reports/monthly`, but WORKDIR does both in one step.

The CMD is `["pwd"]` in exec form. Alpine includes `pwd` as a built-in shell command, but in exec form it is invoked as the external binary at `/bin/pwd`. Running `nerdctl run --rm ex-1-3:v1` produces `/reports/monthly` because WORKDIR sets both the image's default working directory and the working directory for CMD.

---

## Exercise 2.1 Solution

**Dockerfile:**

```bash
cat > ~/ex-2-1/Dockerfile << 'EOF'
FROM alpine:3.20

ARG BUILD_VARIANT="dev"

LABEL build.variant="${BUILD_VARIANT}"

ENV SERVICE_STATUS="active"

CMD ["env"]
EOF

nerdctl build -t ex-2-1:v1 ~/ex-2-1/
```

The key distinction is scope. ARG exists only during the build; it is substituted into the Dockerfile instruction that references it (here, the LABEL value), but once the build is complete the variable is gone. ENV is written into the image's configuration and is inherited by every process that starts from the image. The LABEL in this solution uses the ARG value to embed the build variant in image metadata, which is a common pattern: bake the build-time context into a label (for audit/traceability), but do not expose it as a runtime variable.

Setting `--build-arg BUILD_VARIANT=release` changes the label value in the built image but has no effect on what `nerdctl run` sees in the environment.

---

## Exercise 2.2 Solution

**Dockerfile:**

```bash
cat > ~/ex-2-2/Dockerfile << 'EOF'
FROM busybox:1.36

ENTRYPOINT ["echo"]
CMD ["default message"]
EOF

nerdctl build -t ex-2-2:v1 ~/ex-2-2/
```

**Pod spec (`~/ex-2-2/pod.yaml`):**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: echo-pod
  namespace: ex-2-2
spec:
  restartPolicy: Never
  containers:
  - name: echo
    image: ex-2-2:v1
    imagePullPolicy: Never
    args: ["pod override"]
```

**Apply:**

```bash
kubectl apply -f ~/ex-2-2/pod.yaml
```

With ENTRYPOINT `["echo"]` and CMD `["default message"]`, the container runs `echo "default message"` by default. Passing arguments after the image name at runtime replaces CMD, so `nerdctl run --rm ex-2-2:v1 "runtime override"` runs `echo "runtime override"`. In the Kubernetes pod spec, `args:` replaces CMD, so `args: ["pod override"]` makes the container run `echo "pod override"`. The ENTRYPOINT remains fixed and cannot be overridden by `args:` alone; only `command:` can override ENTRYPOINT.

The pod spec uses `restartPolicy: Never` because the container runs echo and exits immediately with code 0. With the default `restartPolicy: Always`, Kubernetes would restart the container in a loop, producing a CrashLoopBackOff even though each run exits cleanly.

---

## Exercise 2.3 Solution

**Dockerfile:**

```bash
cat > ~/ex-2-3/Dockerfile << 'EOF'
FROM alpine:3.20

RUN addgroup -g 2001 -S builder && adduser -u 2001 -S -G builder builder

WORKDIR /workspace

COPY --chown=builder:builder run.sh /workspace/run.sh

RUN chmod +x /workspace/run.sh

USER builder

CMD ["/workspace/run.sh"]
EOF

nerdctl build -t ex-2-3:v1 ~/ex-2-3/
```

The order of instructions matters here. The `addgroup` and `adduser` commands must appear before USER because USER switches the build context to the named user, and the named user must already exist in /etc/passwd. The COPY uses `--chown=builder:builder` to set ownership at copy time, which is more efficient than a subsequent `RUN chown` because it avoids creating an extra layer that duplicates the file data with different metadata. The chmod must also appear before USER because after switching to `builder`, the build user may not have permission to change file permissions on files owned by another user (in general; with the specific ownership setup here, builder already owns the file, so chmod would also work after USER, but the convention is to complete all root-owned setup before switching).

---

## Exercise 3.1 Solution

### Diagnosis

Attempt to build the image as provided:

```bash
nerdctl build -t ex-3-1:v1 ~/ex-3-1/
```

The build fails immediately. Look at the error message:

```text
#5 [2/6] USER svcuser
#5 ERROR: OCI runtime exec failed: ... no such user: svcuser
```

The error appears on the line that processes USER svcuser. The build daemon attempts to switch the filesystem user to `svcuser` during the build, but `svcuser` does not yet exist in `/etc/passwd` at that point in the Dockerfile.

Run `grep svcuser /etc/passwd` in a bare alpine:3.20 container to confirm:

```bash
nerdctl run --rm alpine:3.20 grep svcuser /etc/passwd
# Expected: (no output; svcuser does not exist in the base image)
```

### What the Bug Is and Why It Happens

The USER instruction appears before the RUN instruction that creates the user. Dockerfile instructions execute in order from top to bottom, and each instruction operates on the filesystem state left by all preceding instructions. When USER svcuser runs on line 2, the `adduser` command on line 3 has not yet executed, so the user does not exist. The build daemon validates the user at the time the USER instruction is processed, not at the time the final image is run.

This is one of the most common Dockerfile mistakes when adding non-root user support, because the logical grouping ("I want to run as svcuser") feels natural at the top of the file, but the mechanical requirement ("create the user before switching to it") demands a specific ordering.

### Fix

Move the USER instruction to after the RUN instruction that creates the user:

```bash
cat > ~/ex-3-1/Dockerfile << 'EOF'
FROM alpine:3.20
RUN addgroup -S svcgrp && adduser -S -G svcgrp -u 1500 svcuser
WORKDIR /service
COPY app.sh /service/app.sh
RUN chmod +x /service/app.sh
USER svcuser
CMD ["/service/app.sh"]
EOF

nerdctl build -t ex-3-1:v1 ~/ex-3-1/
```

---

## Exercise 3.2 Solution

### Diagnosis

Attempt to build the image:

```bash
nerdctl build -t ex-3-2:v1 ~/ex-3-2/
```

The build fails with an error similar to:

```text
COPY failed: file not found in build context or excluded by .dockerignore: stat start.sh: file does not match any files in context
```

The COPY instruction in the Dockerfile references `start.sh`, but the file cannot be found in the build context. Check the `.dockerignore` file:

```bash
cat ~/ex-3-2/.dockerignore
```

The pattern `*.sh` matches all files with a `.sh` extension. Since `start.sh` matches this pattern, the build daemon excludes it from the build context before any Dockerfile instruction runs. The file exists on disk but is invisible to the build daemon.

### What the Bug Is and Why It Happens

The `.dockerignore` file uses `*.sh` to exclude all shell scripts. The intent was probably to exclude test scripts or helper scripts, but the pattern is too broad. Since `start.sh` (the main application entry point) also matches `*.sh`, it gets excluded along with everything else. The COPY instruction then fails because the file it needs is not in the context the daemon received.

This is a realistic mistake. Developers add `.dockerignore` patterns to reduce context size or prevent secrets from leaking into the image, but overly broad patterns can silently break builds. The error message specifically says "excluded by .dockerignore," but if a developer is scanning build output quickly they may miss this clue.

### Fix

Fix the `.dockerignore` so that `start.sh` is included. The simplest fix is to remove the `*.sh` pattern entirely. If the intent is to exclude other shell scripts, use a more specific pattern or negate the exclusion:

```bash
cat > ~/ex-3-2/.dockerignore << 'EOF'
Dockerfile
EOF

nerdctl build -t ex-3-2:v1 ~/ex-3-2/
```

The Dockerfile line is excluded as a convention (no point sending the build instructions into the image), but `start.sh` is now included. An alternative that preserves excluding other scripts would be to add `!start.sh` as a negation after `*.sh`, but the simpler fix is to only exclude what actually needs to be excluded.

---

## Exercise 3.3 Solution

### Diagnosis

Build and run the image:

```bash
nerdctl build -t ex-3-3:v1 ~/ex-3-3/

nerdctl run --rm ex-3-3:v1
```

The build output shows "Building with message: postgres.internal" confirming the ARG was available during the build. But the container output is:

```text
Connecting to:
```

The value of `$DB_HOST` is empty at runtime. Inspect the image environment:

```bash
nerdctl run --rm ex-3-3:v1 env | grep DB_HOST
# Expected: (no output)
```

`DB_HOST` is not present in the container's environment at all. Check the Dockerfile:

```bash
cat ~/ex-3-3/Dockerfile
```

The Dockerfile uses ARG to define `DB_HOST`. The ARG is used in the RUN instruction (which runs during the build), but because ARG does not persist to the container runtime environment, `$DB_HOST` expands to an empty string when the CMD runs.

### What the Bug Is and Why It Happens

ARG defines a variable scoped to the build process. It is available from the ARG instruction forward through the end of the Dockerfile, but it is not written into the image's environment configuration. The image carries no record of the ARG's value (unless you explicitly copy it into an ENV). The CMD in this Dockerfile is a shell-form command: `sh -c "echo Connecting to: $DB_HOST"`. When the container starts, `$DB_HOST` is evaluated by the shell at runtime. Since ARG was not converted to ENV, the shell finds an unset variable and expands it to an empty string.

The confusing part is that the build output shows the correct value ("Building with message: postgres.internal"). This is the RUN instruction during build time, where the ARG is available. The runtime CMD is a completely separate execution context where ARG values are gone.

### Fix

Replace ARG with ENV, or use ARG to set a default and then copy that default into an ENV:

```bash
cat > ~/ex-3-3/Dockerfile << 'EOF'
FROM alpine:3.20
ENV DB_HOST="postgres.internal"
RUN echo "Build-time host: $DB_HOST"
CMD ["sh", "-c", "echo Connecting to: $DB_HOST"]
EOF

nerdctl build -t ex-3-3:v1 ~/ex-3-3/
nerdctl run --rm ex-3-3:v1
# Expected: Connecting to: postgres.internal
```

If you want to allow the default to be customized at build time (without hardcoding it into ENV), combine ARG and ENV:

```dockerfile
ARG DB_HOST="postgres.internal"
ENV DB_HOST="${DB_HOST}"
```

This makes the ENV value customizable at build time via `--build-arg DB_HOST=other.host`, while still persisting the final value into the image environment for runtime use.

---

## Exercise 4.1 Solution

**Dockerfile (`~/ex-4-1/Dockerfile`):**

```dockerfile
FROM python:3.13-slim

LABEL org.opencontainers.image.title="ex-4-1-server"

RUN groupadd -g 1100 svcgrp \
    && useradd -r -u 1100 -g svcgrp svcuser

WORKDIR /srv

COPY --chown=svcuser:svcgrp server.py /srv/server.py

USER svcuser

ENV PORT=8080
ENV APP_NAME=ex-4-1-server

EXPOSE 8080

ENTRYPOINT ["python", "/srv/server.py"]
```

The RUN instruction uses `&&` chaining to create both the group and the user in a single layer. `groupadd -g 1100 svcgrp` creates the group with a specified GID, and `useradd -r -u 1100 -g svcgrp svcuser` creates a system account with a specified UID belonging to that group. The `-r` flag suppresses creation of a home directory, which is appropriate for a service account. COPY uses `--chown=svcuser:svcgrp` so the application file is owned by the non-root user from the moment it is copied, avoiding a separate chown layer. USER appears after COPY so that the chmod or any other root-level setup can complete before the privilege drop.

---

## Exercise 4.2 Solution

**Dockerfile (`~/ex-4-2/Dockerfile`):**

```dockerfile
FROM alpine:3.20

WORKDIR /validator

COPY --chown=nobody:nobody validate.sh /validator/validate.sh

RUN chmod +x /validator/validate.sh

USER nobody

CMD ["/validator/validate.sh"]
```

**`.dockerignore` (`~/ex-4-2/.dockerignore`):**

```
tests/
secrets/
```

Build:

```bash
nerdctl build -t ex-4-2:v1 ~/ex-4-2/
```

The `.dockerignore` uses directory patterns to exclude entire subdirectories. `tests/` matches the tests directory and all its contents. `secrets/` matches the secrets directory and all its contents. The trailing slash is a convention that makes the exclusion intent explicit, though `tests` (without the slash) would also work for directory exclusion in most implementations.

The `nobody` user is a system-level user that exists in Alpine's default `/etc/passwd`, so no `adduser` step is needed. Using `nobody` is appropriate for a read-only utility that does not need to write files and does not need a specific UID.

---

## Exercise 4.3 Solution

**Dockerfile (`~/ex-4-3/Dockerfile`):**

```dockerfile
FROM python:3.13-slim

LABEL org.opencontainers.image.title="report-generator"
LABEL org.opencontainers.image.version="1.0"

RUN groupadd -g 1200 reporters \
    && useradd -r -u 1200 -g reporters reporter

WORKDIR /reporter

COPY --chown=reporter:reporters report.py /reporter/report.py

USER reporter

ENV LOG_LEVEL=info
ENV REPORT_DIR=/reports

EXPOSE 9090

CMD ["python", "/reporter/report.py"]
```

After building and running `nerdctl history ex-4-3:v1`, you will see something like:

```text
IMAGE         CREATED         CREATED BY                                         SIZE
sha256:...    2 seconds ago   CMD ["python" "/reporter/report.py"]               0B
sha256:...    2 seconds ago   EXPOSE map[9090/tcp:{}]                            0B
sha256:...    2 seconds ago   ENV REPORT_DIR=/reports                            0B
sha256:...    2 seconds ago   ENV LOG_LEVEL=info                                 0B
sha256:...    2 seconds ago   USER reporter                                      0B
sha256:...    2 seconds ago   COPY report.py /reporter/report.py # buildkit      2.0kB
sha256:...    2 seconds ago   WORKDIR /reporter                                  0B
sha256:...    2 seconds ago   RUN groupadd -g 1200 reporters && useradd ...      4.1MB
sha256:...    2 seconds ago   LABEL org.opencontainers.image.version=1.0         0B
sha256:...    2 seconds ago   LABEL org.opencontainers.image.title=...           0B
<missing>     ...             (python:3.13-slim base layers)                     ...
```

The instructions that add file content to the filesystem (RUN and COPY) show non-zero SIZE values. All other instructions (LABEL, WORKDIR, USER, ENV, EXPOSE, CMD) produce zero-size metadata entries. This directly reflects how container image layers work: a layer is a filesystem delta, and instructions that do not modify the filesystem produce no delta.

---

## Exercise 5.1 Solution

### Diagnosis

Apply the pod spec as provided:

```bash
kubectl apply -f ~/ex-5-1/pod.yaml
kubectl get pod server-pod -n ex-5-1
```

The pod enters CrashLoopBackOff or Error state almost immediately. Check the events:

```bash
kubectl describe pod server-pod -n ex-5-1
```

The Events section shows something like:

```text
Error: failed to create containerd task: ... exec: "--port": executable file not found in $PATH
```

The pod spec sets `command: ["--port", "8080"]`. In Kubernetes, `command:` overrides the image's ENTRYPOINT entirely. The container runtime then attempts to execute `--port` as a binary, which does not exist. The developer likely intended to pass `--port 8080` as arguments to the existing ENTRYPOINT, not to replace the ENTRYPOINT.

Now examine the Dockerfile for a second issue:

```bash
cat ~/ex-5-1/Dockerfile
```

The ENTRYPOINT uses shell form: `ENTRYPOINT sh /app/app.sh`. Verify this by running a container from the built image:

```bash
nerdctl run --rm -d --name diag-5-1 ex-5-1:v1
nerdctl exec diag-5-1 cat /proc/1/cmdline | tr '\0' ' '
nerdctl stop diag-5-1
```

The output shows `/bin/sh -c sh /app/app.sh`, confirming that PID 1 is a shell interpreter, not `app.sh` directly.

### What the Bugs Are and Why They Happen

**Bug 1 (pod spec):** The developer used `command: ["--port", "8080"]` thinking it would pass additional arguments to the existing ENTRYPOINT. In Kubernetes, `command:` does not append to ENTRYPOINT; it replaces it. To pass arguments while preserving the ENTRYPOINT, you use `args:`. If the application does not actually accept a `--port` flag (it reads from the ENV variable `PORT` instead), the `command:` field should simply be removed.

**Bug 2 (Dockerfile):** Shell-form ENTRYPOINT (`ENTRYPOINT sh /app/app.sh`) wraps the command in `/bin/sh -c "sh /app/app.sh"`. This makes `/bin/sh` the PID 1 process. When Kubernetes sends SIGTERM to the pod during graceful shutdown, the signal goes to `/bin/sh` (PID 1), which may not forward it to the actual application process. Exec form `ENTRYPOINT ["/app/app.sh"]` makes `app.sh` directly PID 1, ensuring signals are delivered to the intended process.

### Fix

Fix the Dockerfile to use exec-form ENTRYPOINT, and fix the pod spec to remove the incorrect `command:` field:

```bash
cat > ~/ex-5-1/Dockerfile << 'EOF'
FROM alpine:3.20
WORKDIR /app
COPY app.sh /app/app.sh
RUN chmod +x /app/app.sh
ENV PORT=8080
ENTRYPOINT ["/app/app.sh"]
EOF

cat > ~/ex-5-1/pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: server-pod
  namespace: ex-5-1
spec:
  containers:
  - name: server
    image: ex-5-1:v1
    imagePullPolicy: Never
    env:
    - name: PORT
      value: "8080"
EOF

nerdctl build -t ex-5-1:v1 ~/ex-5-1/
nerdctl save ex-5-1:v1 -o ~/ex-5-1/ex-5-1.tar
kind load image-archive ~/ex-5-1/ex-5-1.tar

kubectl delete pod server-pod -n ex-5-1 --ignore-not-found
kubectl apply -f ~/ex-5-1/pod.yaml
```

---

## Exercise 5.2 Solution

### Diagnosis

Apply the pod spec as provided:

```bash
kubectl apply -f ~/ex-5-2/pod.yaml
kubectl get pod status-pod -n ex-5-2
```

The pod enters ImagePullBackOff. Check the events:

```bash
kubectl describe pod status-pod -n ex-5-2
```

The events show a failed image pull attempt. The pod spec sets `imagePullPolicy: Always`, which forces Kubernetes to pull the image from a registry every time the pod starts. Since `ex-5-2:v1` is a locally built image that has not been pushed to any registry, the pull fails.

Fix the imagePullPolicy and reapply to see the pod start:

```bash
# Before fixing the Dockerfile, delete the pod and apply a corrected spec temporarily
kubectl delete pod status-pod -n ex-5-2
```

Now examine the Dockerfile for the second issue:

```bash
cat ~/ex-5-2/Dockerfile
```

The Dockerfile uses `ARG STARTUP_MSG="system ready"` and the CMD references `$STARTUP_MSG`. Run the container locally to observe the second bug:

```bash
nerdctl run --rm ex-5-2:v1
```

The output is:

```text
Status:
```

The value is empty. ARG does not persist to the container runtime environment. The CMD executes in a shell where `$STARTUP_MSG` is unset, so it expands to an empty string.

### What the Bugs Are and Why They Happen

**Bug 1 (pod spec):** `imagePullPolicy: Always` on a locally built image that exists only in the kind cluster nodes (loaded via kind load image-archive) causes an ImagePullBackOff because Kubernetes attempts a network pull before running the container, and no registry has this image.

**Bug 2 (Dockerfile):** `ARG STARTUP_MSG` is used in CMD. ARG is a build-time variable only. When the CMD runs inside the started container, `$STARTUP_MSG` is not in the environment. The developer expected ARG to behave like ENV at runtime, which it does not.

### Fix

Fix both the Dockerfile (ARG to ENV) and the pod spec (Always to Never):

```bash
cat > ~/ex-5-2/Dockerfile << 'EOF'
FROM alpine:3.20
ENV STARTUP_MSG="system ready"
RUN echo "Building with message: $STARTUP_MSG"
CMD ["sh", "-c", "echo Status: $STARTUP_MSG"]
EOF

cat > ~/ex-5-2/pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: status-pod
  namespace: ex-5-2
spec:
  restartPolicy: Never
  containers:
  - name: status
    image: ex-5-2:v1
    imagePullPolicy: Never
EOF

nerdctl build -t ex-5-2:v1 ~/ex-5-2/
nerdctl save ex-5-2:v1 -o ~/ex-5-2/ex-5-2.tar
kind load image-archive ~/ex-5-2/ex-5-2.tar

kubectl delete pod status-pod -n ex-5-2 --ignore-not-found
kubectl apply -f ~/ex-5-2/pod.yaml
```

---

## Exercise 5.3 Solution

### Diagnosis

Attempt to build the image:

```bash
nerdctl build -t ex-5-3:v1 ~/ex-5-3/
```

The build fails at the first instruction after FROM. The error is:

```text
OCI runtime exec failed: ... no such user: workeracct
```

**Bug 1:** `USER workeracct` appears before the RUN instruction that creates `workeracct`. The build daemon attempts to switch to the user at line 2, before the user exists.

Fix Bug 1 and re-attempt the build to expose Bug 2:

```bash
# Temporarily swap the order to continue diagnosis
```

After reordering USER after RUN, the build fails at the COPY instruction:

```text
COPY failed: forbidden path outside the build context: ../configs/config.ini
```

**Bug 2:** The COPY source path `../configs/config.ini` uses `..` to escape the build context root. The build daemon rejects any COPY source that resolves outside the context directory. The `config.ini` file is actually in the build context directory itself (`~/ex-5-3/config.ini`), not in a parent-level `configs/` subdirectory.

Fix Bug 2 and re-attempt to expose Bug 3:

After building successfully, check the CMD instruction:

```bash
cat ~/ex-5-3/Dockerfile | grep CMD
# CMD /worker/worker.sh
```

**Bug 3:** CMD uses shell form (`CMD /worker/worker.sh`). This wraps the command in `/bin/sh -c "/worker/worker.sh"`, making `/bin/sh` PID 1 instead of `worker.sh`. Verify:

```bash
nerdctl run --rm -d --name diag-5-3 ex-5-3:v1
nerdctl exec diag-5-3 cat /proc/1/cmdline | tr '\0' ' '
# Shows: /bin/sh -c /worker/worker.sh
nerdctl stop diag-5-3
```

### What the Bugs Are and Why They Happen

**Bug 1 (USER before RUN):** Dockerfile instructions execute in order. USER cannot switch to a user that does not yet exist in the image's `/etc/passwd`. This is the same fundamental mistake as Exercise 3.1, applied to a multi-bug scenario.

**Bug 2 (COPY with `..` path):** The build context is a directory tree sent to the build daemon. By design, the daemon cannot access files outside the context root. A COPY source of `../configs/config.ini` attempts to reference the parent directory, which the daemon rejects with "forbidden path." The file to be copied (`config.ini`) is already in the build context root at `~/ex-5-3/config.ini`; the COPY path just needs to reference it correctly.

**Bug 3 (shell-form CMD):** Shell-form CMD (`CMD /worker/worker.sh`) passes the command through `/bin/sh -c`, making the shell PID 1. Exec-form CMD (`CMD ["/worker/worker.sh"]`) invokes the script directly as PID 1. In a Kubernetes pod, PID 1 receives SIGTERM during graceful shutdown; a shell wrapper typically does not forward signals to child processes, meaning the application inside the script would be killed with SIGKILL rather than receiving the termination signal it may need for clean shutdown.

### Fix

Correct all three bugs:

```bash
cat > ~/ex-5-3/Dockerfile << 'EOF'
FROM alpine:3.20
RUN addgroup -S workergrp && adduser -S -G workergrp -u 1300 workeracct
WORKDIR /worker
COPY config.ini /worker/config.ini
COPY worker.sh /worker/worker.sh
RUN chmod +x /worker/worker.sh
USER workeracct
CMD ["/worker/worker.sh"]
EOF

nerdctl build -t ex-5-3:v1 ~/ex-5-3/
nerdctl save ex-5-3:v1 -o ~/ex-5-3/ex-5-3.tar
kind load image-archive ~/ex-5-3/ex-5-3.tar

kubectl delete pod worker-pod -n ex-5-3 --ignore-not-found

kubectl apply -f - << 'PODEOF'
apiVersion: v1
kind: Pod
metadata:
  name: worker-pod
  namespace: ex-5-3
spec:
  containers:
  - name: worker
    image: ex-5-3:v1
    imagePullPolicy: Never
PODEOF
```

---

## Common Mistakes

**Using ARG when ENV is needed.** ARG and ENV look similar and are often listed together in tutorials, but they serve different purposes. ARG is erased after the build; ENV persists into the container. The mistake is especially common when a value is needed at both build time (to configure a tool during `RUN`) and runtime (to configure the application at startup). The correct pattern is to use ARG to provide a customizable build-time default, then copy it into an ENV: `ARG VALUE=default` followed by `ENV VALUE="${VALUE}"`. Without the ENV line, the container starts with an empty variable and the failure is often a silent empty-string expansion rather than a clear error message.

**Placing USER before the RUN that creates the user.** The intuition "I want the whole image to be non-root" leads naturally to putting USER at the top of the Dockerfile. But Dockerfile instructions execute in order, and USER validates that the named user exists in the image's /etc/passwd at the time the instruction is processed, not at the time the image runs. Every USER instruction must be preceded by a RUN instruction that creates the user (via useradd or adduser). The error message from the build daemon clearly says "no such user," but it only appears at build time, and developers sometimes miss it if they are not watching build output carefully.

**Confusing Kubernetes command and args with Docker ENTRYPOINT and CMD.** The naming is inverted. In a pod spec, `command:` overrides the image's ENTRYPOINT and `args:` overrides the image's CMD. Many developers expect `command:` to be appended to ENTRYPOINT (as the Docker CLI's positional arguments are appended after an --entrypoint override), but that is not how Kubernetes works. Setting `command:` alone completely replaces ENTRYPOINT and runs with no CMD arguments. The common symptom is a pod in CrashLoopBackOff where the Events show an executable not found error for a value that looks like a flag (`--port` or `--debug`).

**Using shell-form ENTRYPOINT and expecting clean signal handling.** Shell form (`ENTRYPOINT python app.py`) runs the command as a child of `/bin/sh`, which becomes PID 1. When Kubernetes sends SIGTERM during pod termination, the signal goes to `/bin/sh`. Whether the shell forwards SIGTERM to its child depends on the shell implementation; busybox sh does not forward signals, which means the application process is killed with SIGKILL after the grace period rather than having the opportunity to shut down cleanly. Exec form (`ENTRYPOINT ["python", "app.py"]`) makes Python PID 1 directly and ensures it receives SIGTERM.

**Accidentally excluding needed files with .dockerignore.** A .dockerignore pattern like `*.sh` or `*.py` excludes all matching files from the build context, including application entry points. The build daemon raises "not found in build context or excluded by .dockerignore" rather than "the file does not exist," which can be confusing because the file is clearly present on disk. The fix is to use more specific patterns (`test_*.sh` to exclude test scripts, `secrets/` to exclude a directory) rather than broad wildcards that capture application files.

**Using COPY with a path that escapes the build context.** The build context is a self-contained directory tree. COPY cannot reference files outside that tree using `..` path segments; the daemon rejects them with "forbidden path outside the build context." If a file that the Dockerfile needs exists outside the directory you are using as the build context, the solution is either to restructure the directory layout so the file is inside the context, or to run `nerdctl build` with a broader context path and adjust the COPY source path accordingly.

---

## Verification Commands Cheat Sheet

| Task | Command | Expected Output |
|---|---|---|
| Check image exists | `nerdctl images name:tag` | Row showing repository, tag, ID, size |
| List all local images | `nerdctl images` | All images in the local store |
| Check ENV vars in image | `nerdctl run --rm name:tag env` | Lines of KEY=VALUE pairs |
| Check working directory | `nerdctl run --rm name:tag pwd` | Absolute path string |
| Check running user | `nerdctl run --rm name:tag whoami` | Username string |
| Check running UID | `nerdctl run --rm name:tag id -u` | Numeric UID |
| Check PID 1 command | `nerdctl run --rm -d --name test name:tag && nerdctl exec test cat /proc/1/cmdline \| tr '\0' ' '` | Executable path (exec form) vs `/bin/sh -c ...` (shell form) |
| Inspect all config | `nerdctl image inspect name:tag` | Full JSON config |
| Inspect ENTRYPOINT | `nerdctl image inspect name:tag --format '{{json .Config.Entrypoint}}'` | JSON array or `null` |
| Inspect CMD | `nerdctl image inspect name:tag --format '{{json .Config.Cmd}}'` | JSON array or `null` |
| Inspect ENV | `nerdctl image inspect name:tag --format '{{json .Config.Env}}'` | JSON array of KEY=VALUE strings |
| Inspect labels | `nerdctl image inspect name:tag --format '{{json .Config.Labels}}'` | JSON object of key-value pairs |
| Inspect working dir | `nerdctl image inspect name:tag --format '{{.Config.WorkingDir}}'` | Absolute path string |
| Inspect user | `nerdctl image inspect name:tag --format '{{.Config.User}}'` | Username or UID string |
| View layer history | `nerdctl history name:tag` | Table of layers with SIZE column |
| Save image to tar | `nerdctl save name:tag -o file.tar` | Creates tar file at given path |
| Load into kind | `kind load image-archive file.tar` | Imports image into all kind nodes |
| Pod phase check | `kubectl get pod NAME -n NS -o jsonpath='{.status.phase}'` | Running, Succeeded, or Failed |
| Pod logs | `kubectl logs NAME -n NS` | Container stdout |
| Pod exec | `kubectl exec -n NS NAME -- COMMAND` | Command output |
| Pod describe | `kubectl describe pod NAME -n NS` | Full spec plus Events section |
| Pod pull policy check | `kubectl get pod NAME -n NS -o jsonpath='{.spec.containers[0].imagePullPolicy}'` | Always, IfNotPresent, or Never |
