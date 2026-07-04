# Container Images Homework

Work through the tutorial in container-images-tutorial.md before attempting these exercises. The tutorial covers every Dockerfile instruction, the ENTRYPOINT and CMD combination table, image inspection with nerdctl, and the nerdctl save plus kind load image-archive pattern that Levels 4 and 5 require.

Each exercise gives you a setup block to run first, a task to complete, and verification commands that show you precisely what a correct solution looks like. For Level 3 and Level 5 exercises, the objective tells you the desired end state only; discovering what is broken is part of the exercise.

## Exercise Setup

No global cluster setup is required. Levels 1 through 3 work entirely with local nerdctl operations. Levels 4 and 5 require a running kind cluster. Create the cluster before attempting Level 4:

```bash
# Verify cluster is running
kubectl get nodes
# Expected: one node in Ready state
```

All image builds produce images named `ex-N-M:v1` (for example, `ex-1-1:v1` for Level 1, Exercise 1). All exercise namespaces follow the pattern `ex-N-M` (for example, `ex-4-1`).

---

## Level 1: Basic Single-Concept Tasks

---

### Exercise 1.1

Write a Dockerfile for a minimal shell script application. The script and Dockerfile must satisfy the following requirements: the base image is `busybox:1.36`, the working directory inside the image is `/app`, the script `hello.sh` is copied to `/app/hello.sh`, an environment variable `GREETING` is set to `"Hello from the container"`, port 8080 is documented, and the container runs `hello.sh` by default using exec form.

**Setup:**

```bash
mkdir -p ~/ex-1-1
cat > ~/ex-1-1/hello.sh << 'EOF'
#!/bin/sh
echo "$GREETING"
EOF
```

**Task:**

Create `~/ex-1-1/Dockerfile` that satisfies all the requirements above. Build the image tagged as `ex-1-1:v1` using `~/ex-1-1/` as the build context.

**Verification:**

```bash
nerdctl images --format '{{.Repository}}:{{.Tag}}' | grep 'ex-1-1:v1'
# Expected: ex-1-1:v1

nerdctl run --rm ex-1-1:v1
# Expected: Hello from the container

nerdctl image inspect ex-1-1:v1 --format '{{.Config.WorkingDir}}'
# Expected: /app

nerdctl image inspect ex-1-1:v1 --format '{{json .Config.ExposedPorts}}'
# Expected: {"8080/tcp":{}}
```

---

### Exercise 1.2

Write a Dockerfile that adds OCI-standard labels to a busybox image. The image must carry three labels: `org.opencontainers.image.title` set to `"label-demo"`, `org.opencontainers.image.version` set to `"2.0.0"`, and `org.opencontainers.image.description` set to `"Demonstrates OCI label annotations"`. The container's default command should print `"labels present"`.

**Setup:**

```bash
mkdir -p ~/ex-1-2
```

**Task:**

Create `~/ex-1-2/Dockerfile` meeting the requirements above. Build the image tagged as `ex-1-2:v1`.

**Verification:**

```bash
nerdctl image inspect ex-1-2:v1 --format '{{json .Config.Labels}}' | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('org.opencontainers.image.title'))"
# Expected: label-demo

nerdctl image inspect ex-1-2:v1 --format '{{json .Config.Labels}}' | \
  python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('org.opencontainers.image.version'))"
# Expected: 2.0.0

nerdctl run --rm ex-1-2:v1
# Expected: labels present
```

---

### Exercise 1.3

Write a Dockerfile that uses WORKDIR to create a nested directory path that does not exist in the base image. The working directory must be `/reports/monthly`. The container's default command should print the current working directory.

**Setup:**

```bash
mkdir -p ~/ex-1-3
```

**Task:**

Create `~/ex-1-3/Dockerfile` using `alpine:3.20` as the base. Set WORKDIR to `/reports/monthly`. The CMD must print the current directory using exec form. Build the image tagged as `ex-1-3:v1`.

**Verification:**

```bash
nerdctl run --rm ex-1-3:v1
# Expected: /reports/monthly

nerdctl image inspect ex-1-3:v1 --format '{{.Config.WorkingDir}}'
# Expected: /reports/monthly
```

---

## Level 2: Multi-Concept Tasks

---

### Exercise 2.1

Write a Dockerfile that demonstrates the distinction between ARG and ENV. The Dockerfile must accept a build-time argument `BUILD_VARIANT` (default `"dev"`) and must set a runtime environment variable `SERVICE_STATUS` with the value `"active"`. The container's default command prints all environment variables.

**Setup:**

```bash
mkdir -p ~/ex-2-1
```

**Task:**

Create `~/ex-2-1/Dockerfile` using `alpine:3.20`. Define `ARG BUILD_VARIANT="dev"` and `ENV SERVICE_STATUS="active"`. The CMD must print all environment variables using exec form (`["env"]`). Build the image twice: first with the default (no `--build-arg`), then with `--build-arg BUILD_VARIANT=release`. Tag both runs as `ex-2-1:v1` (the tag can be the same; the point is to observe the runtime environment).

**Verification:**

```bash
nerdctl build -t ex-2-1:v1 ~/ex-2-1/

# SERVICE_STATUS is an ENV and must be present at runtime
nerdctl run --rm ex-2-1:v1 | grep SERVICE_STATUS
# Expected: SERVICE_STATUS=active

# BUILD_VARIANT is an ARG and must NOT be present at runtime
nerdctl run --rm ex-2-1:v1 | grep BUILD_VARIANT
# Expected: (no output)

# Build again with a custom build arg; runtime env must be unchanged
nerdctl build --build-arg BUILD_VARIANT=release -t ex-2-1:v1 ~/ex-2-1/
nerdctl run --rm ex-2-1:v1 | grep BUILD_VARIANT
# Expected: (no output; ARG still does not persist)
```

---

### Exercise 2.2

Write a Dockerfile that uses both exec-form ENTRYPOINT and exec-form CMD so that CMD provides overrideable default arguments. The ENTRYPOINT must be `["echo"]` and the CMD must be `["default message"]`. Then write a pod spec in namespace `ex-2-2` that overrides CMD using the pod spec's `args:` field to output `"pod override"` instead.

**Setup:**

```bash
mkdir -p ~/ex-2-2
kubectl create namespace ex-2-2
```

**Task:**

Create `~/ex-2-2/Dockerfile` using `busybox:1.36`. Set exec-form ENTRYPOINT `["echo"]` and exec-form CMD `["default message"]`. Build as `ex-2-2:v1`. Verify the default behavior. Then save the image, load it into kind, and write a pod spec at `~/ex-2-2/pod.yaml` for namespace `ex-2-2` that uses `args: ["pod override"]` so the pod outputs `"pod override"`. Apply the pod spec.

```bash
nerdctl build -t ex-2-2:v1 ~/ex-2-2/
nerdctl save ex-2-2:v1 -o ~/ex-2-2/ex-2-2.tar
kind load image-archive ~/ex-2-2/ex-2-2.tar
```

**Verification:**

```bash
# Verify default CMD behavior locally
nerdctl run --rm ex-2-2:v1
# Expected: default message

# Verify CMD override locally
nerdctl run --rm ex-2-2:v1 "runtime override"
# Expected: runtime override

# Verify the pod is running
kubectl get pod echo-pod -n ex-2-2 -o jsonpath='{.status.phase}'
# Expected: Succeeded

# Verify the pod output
kubectl logs echo-pod -n ex-2-2
# Expected: pod override
```

---

### Exercise 2.3

Write a Dockerfile from `alpine:3.20` that creates a non-root user named `builder` with UID 2001 and GID 2001, copies an application script with correct ownership using `COPY --chown`, and switches to that user with the USER directive. The application script must already exist in the build context directory.

**Setup:**

```bash
mkdir -p ~/ex-2-3
cat > ~/ex-2-3/run.sh << 'EOF'
#!/bin/sh
echo "Running as: $(whoami) (uid=$(id -u))"
EOF
```

**Task:**

Create `~/ex-2-3/Dockerfile`. The Dockerfile must: use `alpine:3.20` as the base; create group `builder` with GID 2001 and user `builder` with UID 2001 using `addgroup` and `adduser`; set WORKDIR to `/workspace`; copy `run.sh` to `/workspace/run.sh` with `--chown=builder:builder`; make `run.sh` executable; switch to USER builder; and set CMD to run `run.sh` in exec form. Build as `ex-2-3:v1`.

**Verification:**

```bash
nerdctl run --rm ex-2-3:v1
# Expected: Running as: builder (uid=2001)

nerdctl run --rm ex-2-3:v1 whoami
# Expected: builder

nerdctl run --rm ex-2-3:v1 id -u
# Expected: 2001

nerdctl image inspect ex-2-3:v1 --format '{{.Config.User}}'
# Expected: builder
```

---

## Level 3: Debugging Broken Configurations

---

### Exercise 3.1

The Dockerfile in the setup below has one or more problems. Find and fix whatever is needed so that the image builds successfully and the container starts running as the intended user.

**Setup:**

```bash
mkdir -p ~/ex-3-1
cat > ~/ex-3-1/app.sh << 'EOF'
#!/bin/sh
echo "Service started as: $(whoami)"
exec sleep 3600
EOF

cat > ~/ex-3-1/Dockerfile << 'EOF'
FROM alpine:3.20
USER svcuser
RUN addgroup -S svcgrp && adduser -S -G svcgrp -u 1500 svcuser
WORKDIR /service
COPY app.sh /service/app.sh
RUN chmod +x /service/app.sh
CMD ["/service/app.sh"]
EOF
```

**Task:**

Fix the Dockerfile in `~/ex-3-1/Dockerfile` so the image builds and the container starts running as `svcuser`. Rebuild as `ex-3-1:v1`.

**Verification:**

```bash
nerdctl build -t ex-3-1:v1 ~/ex-3-1/
# Expected: build completes without errors

nerdctl run --rm ex-3-1:v1 whoami
# Expected: svcuser

nerdctl run --rm ex-3-1:v1 id -u
# Expected: 1500
```

---

### Exercise 3.2

The build context directory below contains a Dockerfile and supporting files. The image fails to build or the container does not behave as expected. Find and fix whatever is needed so the image builds and the container runs the intended script.

**Setup:**

```bash
mkdir -p ~/ex-3-2

cat > ~/ex-3-2/start.sh << 'EOF'
#!/bin/sh
echo "Application started successfully"
EOF

cat > ~/ex-3-2/Dockerfile << 'EOF'
FROM alpine:3.20
WORKDIR /app
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh
CMD ["/app/start.sh"]
EOF

cat > ~/ex-3-2/.dockerignore << 'EOF'
*.sh
Dockerfile
EOF
```

**Task:**

Diagnose why the build fails and fix the problem in `~/ex-3-2/`. Rebuild the image as `ex-3-2:v1`. Do not modify `start.sh` itself.

**Verification:**

```bash
nerdctl build -t ex-3-2:v1 ~/ex-3-2/
# Expected: build completes without errors

nerdctl run --rm ex-3-2:v1
# Expected: Application started successfully
```

---

### Exercise 3.3

The Dockerfile below is intended to produce a container that prints its target database host at startup. The container builds and starts without errors, but the output is not what the developer expects. Find and fix the problem so the container prints the correct value.

**Setup:**

```bash
mkdir -p ~/ex-3-3

cat > ~/ex-3-3/Dockerfile << 'EOF'
FROM alpine:3.20
ARG DB_HOST="postgres.internal"
RUN echo "Build-time host: $DB_HOST"
CMD ["sh", "-c", "echo Connecting to: $DB_HOST"]
EOF
```

**Task:**

Diagnose why the container output is incorrect and fix `~/ex-3-3/Dockerfile` so that running the container prints `"Connecting to: postgres.internal"`. Rebuild as `ex-3-3:v1`.

**Verification:**

```bash
nerdctl build -t ex-3-3:v1 ~/ex-3-3/
# Expected: build output shows "Build-time host: postgres.internal"

nerdctl run --rm ex-3-3:v1
# Expected: Connecting to: postgres.internal
```

---

## Level 4: Production-Style Build Tasks

---

### Exercise 4.1

Write a complete production-style Dockerfile for the Python HTTP application provided below. Load the image into kind and deploy it as a pod. Verify the pod runs the process as a non-root user.

**Setup:**

```bash
mkdir -p ~/ex-4-1
kubectl create namespace ex-4-1

cat > ~/ex-4-1/server.py << 'EOF'
#!/usr/bin/env python3
import http.server
import os
import socketserver

PORT = int(os.environ.get("PORT", "8080"))
APP_NAME = os.environ.get("APP_NAME", "ex-4-1-server")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        body = f"Hello from {APP_NAME} | uid={os.getuid()}\n"
        self.wfile.write(body.encode())

    def log_message(self, fmt, *args):
        pass


with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"[{APP_NAME}] listening on :{PORT}", flush=True)
    httpd.serve_forever()
EOF
```

**Task:**

Create `~/ex-4-1/Dockerfile` that satisfies all of the following requirements:

- Base image: `python:3.13-slim`
- LABEL: `org.opencontainers.image.title="ex-4-1-server"`
- Create user `svcuser` with UID 1100 and group `svcgrp` with GID 1100 using `groupadd` and `useradd`
- WORKDIR: `/srv`
- COPY `server.py` to `/srv/server.py` with `--chown=svcuser:svcgrp`
- USER: `svcuser`
- ENV: `PORT=8080` and `APP_NAME=ex-4-1-server`
- EXPOSE: `8080`
- ENTRYPOINT in exec form: `["python", "/srv/server.py"]`

Build the image as `ex-4-1:v1`, save it, load it into kind, and apply the following pod spec:

```bash
nerdctl build -t ex-4-1:v1 ~/ex-4-1/
nerdctl save ex-4-1:v1 -o ~/ex-4-1/ex-4-1.tar
kind load image-archive ~/ex-4-1/ex-4-1.tar

kubectl apply -f - << 'PODEOF'
apiVersion: v1
kind: Pod
metadata:
  name: server-pod
  namespace: ex-4-1
spec:
  containers:
  - name: server
    image: ex-4-1:v1
    imagePullPolicy: Never
    ports:
    - containerPort: 8080
PODEOF
```

**Verification:**

```bash
kubectl get pod server-pod -n ex-4-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl logs server-pod -n ex-4-1
# Expected: [ex-4-1-server] listening on :8080

kubectl exec -n ex-4-1 server-pod -- whoami
# Expected: svcuser

kubectl exec -n ex-4-1 server-pod -- id -u
# Expected: 1100

kubectl exec -n ex-4-1 server-pod -- sh -c 'wget -qO- http://localhost:8080'
# Expected: Hello from ex-4-1-server | uid=1100
```

---

### Exercise 4.2

Build an image from `alpine:3.20` for a configuration validator utility. The build context contains application files, test files in a `tests/` subdirectory, and a `secrets/` directory containing sensitive data. Write both the Dockerfile and a `.dockerignore` file that excludes `tests/` and `secrets/` from the image. Verify that the excluded content is not present in the final image.

**Setup:**

```bash
mkdir -p ~/ex-4-2/tests ~/ex-4-2/secrets

cat > ~/ex-4-2/validate.sh << 'EOF'
#!/bin/sh
echo "Validator running"
echo "Config path: ${CONFIG_PATH:-/etc/app/config}"
EOF

cat > ~/ex-4-2/tests/test_validate.sh << 'EOF'
#!/bin/sh
echo "This is a test file and should not be in the image"
EOF

cat > ~/ex-4-2/secrets/api.key << 'EOF'
super-secret-api-key-do-not-ship
EOF
```

**Task:**

Create `~/ex-4-2/Dockerfile` and `~/ex-4-2/.dockerignore`. The Dockerfile must: use `alpine:3.20`; set WORKDIR to `/validator`; copy `validate.sh` with `--chown=nobody:nobody`; make it executable; set USER to `nobody`; and set CMD to run `validate.sh` in exec form. The `.dockerignore` must exclude both `tests/` and `secrets/`. Build as `ex-4-2:v1`.

**Verification:**

```bash
nerdctl build -t ex-4-2:v1 ~/ex-4-2/
# Expected: build completes without errors

nerdctl run --rm ex-4-2:v1
# Expected: Validator running

# Confirm secrets are not in the image
nerdctl run --rm ex-4-2:v1 sh -c 'ls /validator/'
# Expected: validate.sh (only; no tests/ or secrets/ directories)

nerdctl run --rm ex-4-2:v1 sh -c 'test -d /validator/secrets && echo "FAIL: secrets present" || echo "secrets absent"'
# Expected: secrets absent

nerdctl run --rm ex-4-2:v1 sh -c 'test -d /validator/tests && echo "FAIL: tests present" || echo "tests absent"'
# Expected: tests absent
```

---

### Exercise 4.3

Write a Dockerfile that creates a Python-based report generator. After building the image, use `nerdctl history` to identify which instructions created size-adding layers and which created zero-size metadata entries. Then deploy the image to kind and verify the correct running user and environment configuration.

**Setup:**

```bash
mkdir -p ~/ex-4-3
kubectl create namespace ex-4-3

cat > ~/ex-4-3/report.py << 'EOF'
#!/usr/bin/env python3
import os

log_level = os.environ.get("LOG_LEVEL", "info")
report_dir = os.environ.get("REPORT_DIR", "/reports")

print(f"Report generator starting | log_level={log_level} | uid={os.getuid()}")
print(f"Report directory: {report_dir}")
EOF
```

**Task:**

Create `~/ex-4-3/Dockerfile` with all of the following:

- Base image: `python:3.13-slim`
- Two LABEL instructions: `org.opencontainers.image.title="report-generator"` and `org.opencontainers.image.version="1.0"`
- Create user `reporter` with UID 1200 and group `reporters` with GID 1200
- WORKDIR: `/reporter`
- COPY `report.py` to `/reporter/report.py` with `--chown=reporter:reporters`
- USER: `reporter`
- ENV: `LOG_LEVEL=info` and `REPORT_DIR=/reports`
- EXPOSE: `9090`
- CMD in exec form: `["python", "/reporter/report.py"]`

Build as `ex-4-3:v1`. Examine the history. Then save, load into kind, and deploy:

```bash
nerdctl build -t ex-4-3:v1 ~/ex-4-3/
nerdctl history ex-4-3:v1
# Identify which entries show non-zero SIZE (RUN and COPY instructions)
# Identify which entries show SIZE 0B (LABEL, ENV, EXPOSE, WORKDIR, USER, CMD)

nerdctl save ex-4-3:v1 -o ~/ex-4-3/ex-4-3.tar
kind load image-archive ~/ex-4-3/ex-4-3.tar

kubectl apply -f - << 'PODEOF'
apiVersion: v1
kind: Pod
metadata:
  name: reporter-pod
  namespace: ex-4-3
spec:
  containers:
  - name: reporter
    image: ex-4-3:v1
    imagePullPolicy: Never
PODEOF
```

**Verification:**

```bash
kubectl get pod reporter-pod -n ex-4-3 -o jsonpath='{.status.phase}'
# Expected: Succeeded

kubectl logs reporter-pod -n ex-4-3
# Expected first line: Report generator starting | log_level=info | uid=1200
# Expected second line: Report directory: /reports

# Verify metadata instructions appear as 0B in history
nerdctl history ex-4-3:v1 | grep -E "LABEL|ENV|EXPOSE"
# Expected: all matched lines show 0B in the SIZE column
```

---

## Level 5: Advanced Debugging and Comprehensive Tasks

---

### Exercise 5.1

The setup below builds an image and creates a pod spec intended to print a specific message. The pod is not behaving as the developer expected. Find and fix whatever is needed so the pod outputs exactly `"server started on port 8080"` in its logs and so the process running as PID 1 in the container is not a shell interpreter.

**Setup:**

```bash
mkdir -p ~/ex-5-1
kubectl create namespace ex-5-1

cat > ~/ex-5-1/app.sh << 'EOF'
#!/bin/sh
echo "server started on port ${PORT:-8080}"
exec sleep 3600
EOF

cat > ~/ex-5-1/Dockerfile << 'EOF'
FROM alpine:3.20
WORKDIR /app
COPY app.sh /app/app.sh
RUN chmod +x /app/app.sh
ENV PORT=8080
ENTRYPOINT sh /app/app.sh
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
    command: ["--port", "8080"]
EOF

nerdctl build -t ex-5-1:v1 ~/ex-5-1/
nerdctl save ex-5-1:v1 -o ~/ex-5-1/ex-5-1.tar
kind load image-archive ~/ex-5-1/ex-5-1.tar
```

**Task:**

Diagnose the problems with both the Dockerfile and the pod spec. Fix the Dockerfile in `~/ex-5-1/Dockerfile` and the pod spec in `~/ex-5-1/pod.yaml`. Rebuild and reload the image if you change the Dockerfile. Apply the corrected pod spec.

**Verification:**

```bash
kubectl get pod server-pod -n ex-5-1 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl logs server-pod -n ex-5-1
# Expected: server started on port 8080

kubectl exec -n ex-5-1 server-pod -- cat /proc/1/cmdline | tr '\0' ' '
# Expected: /app/app.sh (or sh with the script path; not: /bin/sh -c sh /app/app.sh)
# The first token must NOT be /bin/sh invoked by the shell-form wrapper
```

---

### Exercise 5.2

The setup below provides a pre-built image loaded into kind and a pod spec to deploy it. The pod is failing to start, and even when the pod spec is corrected, the container's output does not match expectations. Find and fix all problems so the pod runs successfully and its logs show the correct message.

**Setup:**

```bash
mkdir -p ~/ex-5-2
kubectl create namespace ex-5-2

cat > ~/ex-5-2/Dockerfile << 'EOF'
FROM alpine:3.20
ARG STARTUP_MSG="system ready"
RUN echo "Building with message: $STARTUP_MSG"
CMD ["sh", "-c", "echo Status: $STARTUP_MSG"]
EOF

nerdctl build -t ex-5-2:v1 ~/ex-5-2/
nerdctl save ex-5-2:v1 -o ~/ex-5-2/ex-5-2.tar
kind load image-archive ~/ex-5-2/ex-5-2.tar

cat > ~/ex-5-2/pod.yaml << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: status-pod
  namespace: ex-5-2
spec:
  containers:
  - name: status
    image: ex-5-2:v1
    imagePullPolicy: Always
EOF
```

**Task:**

Apply the pod spec and observe what happens. Then diagnose all problems, fix both `~/ex-5-2/Dockerfile` and `~/ex-5-2/pod.yaml`, rebuild the image, reload it into kind, delete the existing pod, and apply the corrected pod spec. The pod logs must show `"Status: system ready"`.

**Verification:**

```bash
kubectl get pod status-pod -n ex-5-2 -o jsonpath='{.status.phase}'
# Expected: Succeeded

kubectl logs status-pod -n ex-5-2
# Expected: Status: system ready

kubectl get pod status-pod -n ex-5-2 -o jsonpath='{.spec.containers[0].imagePullPolicy}'
# Expected: Never
```

---

### Exercise 5.3

The setup below provides a broken Dockerfile intended to produce a production-ready image. The image either fails to build or the resulting container does not behave correctly when deployed to kind. Find and fix all problems so the image builds, the container runs as the intended user, and the process running as PID 1 is not a shell wrapper.

**Setup:**

```bash
mkdir -p ~/ex-5-3
kubectl create namespace ex-5-3

cat > ~/ex-5-3/worker.sh << 'EOF'
#!/bin/sh
echo "Worker started as $(whoami) (uid=$(id -u))"
exec sleep 3600
EOF

cat > ~/ex-5-3/config.ini << 'EOF'
[worker]
pool_size=4
EOF

cat > ~/ex-5-3/Dockerfile << 'EOF'
FROM alpine:3.20
USER workeracct
RUN addgroup -S workergrp && adduser -S -G workergrp -u 1300 workeracct
WORKDIR /worker
COPY ../configs/config.ini /worker/config.ini
COPY worker.sh /worker/worker.sh
RUN chmod +x /worker/worker.sh
CMD /worker/worker.sh
EOF
```

**Task:**

Diagnose all problems in `~/ex-5-3/Dockerfile`. Fix each one, rebuild as `ex-5-3:v1`, save and load into kind, and deploy using the pod spec below. Apply the pod spec only after the image builds and local verification passes.

```bash
nerdctl build -t ex-5-3:v1 ~/ex-5-3/
# Fix until this succeeds

nerdctl save ex-5-3:v1 -o ~/ex-5-3/ex-5-3.tar
kind load image-archive ~/ex-5-3/ex-5-3.tar

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

**Verification:**

```bash
nerdctl run --rm ex-5-3:v1 whoami
# Expected: workeracct

nerdctl run --rm ex-5-3:v1 id -u
# Expected: 1300

# Verify exec-form CMD: PID 1 must be the script, not a shell wrapper
nerdctl run --rm -d --name ex-5-3-test ex-5-3:v1
nerdctl exec ex-5-3-test cat /proc/1/cmdline | tr '\0' ' '
# Expected output starts with: /worker/worker.sh
nerdctl stop ex-5-3-test

kubectl get pod worker-pod -n ex-5-3 -o jsonpath='{.status.phase}'
# Expected: Running

kubectl logs worker-pod -n ex-5-3
# Expected: Worker started as workeracct (uid=1300)
```

---

## Cleanup

After completing all exercises, remove the exercise namespaces and locally built images:

```bash
kubectl delete namespace ex-2-2 ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2 ex-5-3

nerdctl rmi \
  ex-1-1:v1 ex-1-2:v1 ex-1-3:v1 \
  ex-2-1:v1 ex-2-2:v1 ex-2-3:v1 \
  ex-3-1:v1 ex-3-2:v1 ex-3-3:v1 \
  ex-4-1:v1 ex-4-2:v1 ex-4-3:v1 \
  ex-5-1:v1 ex-5-2:v1 ex-5-3:v1 2>/dev/null || true

rm -rf ~/ex-1-1 ~/ex-1-2 ~/ex-1-3 \
       ~/ex-2-1 ~/ex-2-2 ~/ex-2-3 \
       ~/ex-3-1 ~/ex-3-2 ~/ex-3-3 \
       ~/ex-4-1 ~/ex-4-2 ~/ex-4-3 \
       ~/ex-5-1 ~/ex-5-2 ~/ex-5-3
```

## Key Takeaways

Working through these exercises builds practical fluency with the full Dockerfile instruction set and develops the diagnostic instincts needed for the CKA exam. The most important patterns to internalize: exec form is the correct default for ENTRYPOINT and CMD; ARG and ENV are distinct scopes and confusing them is the most common Dockerfile mistake; USER must come after the RUN that creates the user; COPY paths must stay inside the build context; and `imagePullPolicy: Never` is required for locally loaded images in kind. The Kubernetes command and args fields override ENTRYPOINT and CMD respectively, which is the opposite direction from what the field names suggest.
