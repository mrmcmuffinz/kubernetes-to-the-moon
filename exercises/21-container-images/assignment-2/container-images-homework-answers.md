# Container Images Homework Answers -- Assignment 2

## Exercise 1.1 Solution

Tag the nginx image for the local registry, push it, remove the local copies, and verify a fresh pull works.

```bash
# Tag for the local registry
nerdctl tag nginx:1.27 localhost:5001/nginx:v1.0.0

# Push to the local registry
nerdctl push localhost:5001/nginx:v1.0.0

# Remove the local cached copies so the fresh pull proves the registry works
nerdctl rmi nginx:1.27
nerdctl rmi localhost:5001/nginx:v1.0.0

# Pull fresh from the local registry
nerdctl pull localhost:5001/nginx:v1.0.0

# Deploy a pod using the locally-registered image
kubectl apply -n ex-1-1 -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: nginx-test
  namespace: ex-1-1
spec:
  containers:
  - name: nginx
    image: localhost:5001/nginx:v1.0.0
    ports:
    - containerPort: 80
EOF

kubectl wait -n ex-1-1 --for=condition=Ready pod/nginx-test --timeout=60s
```

The `nerdctl tag` command creates a new name/tag pointing to the same image manifest in the local image store. It does not push anything to the registry. The separate `nerdctl push` command is what sends the manifest and layers to `localhost:5001`. After removing both local copies with `nerdctl rmi`, the image exists only in the registry. The `nerdctl pull` then fetches it from there, proving the registry is serving the content correctly.

---

## Exercise 1.2 Solution

The fixed multi-stage Dockerfile for `/tmp/ex-1-2/Dockerfile`:

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

Build and push:

```bash
nerdctl build -t localhost:5001/ex12server:v1.0.0 /tmp/ex-1-2/
nerdctl push localhost:5001/ex12server:v1.0.0
```

The key changes from the single-stage Dockerfile are: adding `AS builder` to name the first stage, adding the second `FROM gcr.io/distroless/static:nonroot` to start the runtime stage, and replacing the `ENTRYPOINT` in the first stage with a `COPY --from=builder` in the second stage plus a new `ENTRYPOINT`. The `USER nonroot:nonroot` instruction ensures the server process does not run as root inside the container.

The size reduction happens because the `FROM gcr.io/distroless/static:nonroot` stage starts fresh from the distroless base image (around 1 MB) and only adds the compiled binary from the builder. The entire Go toolchain, Alpine system libraries, and intermediate compilation artifacts stay in the builder stage and are discarded after the build.

---

## Exercise 1.3 Solution

The instructions in the provided Dockerfile that create new filesystem layers are:

```
FROM alpine:3.20
RUN apk add --no-cache curl
WORKDIR /app
COPY . .
RUN echo "build complete"
```

Instructions that do NOT create layers (they only update the image manifest metadata):

```
LABEL maintainer="student@example.com"
ENV APP_ENV=production
ARG BUILD_DATE
CMD ["sh", "-c", "echo hello"]
ENTRYPOINT ["sh"]
```

Create the layer-count.txt file and result.txt:

```bash
cat > /tmp/ex-1-3/layer-count.txt << 'EOF'
FROM alpine:3.20
RUN apk add --no-cache curl
WORKDIR /app
COPY . .
RUN echo "build complete"
EOF

echo "5" > /tmp/ex-1-3/result.txt
```

Build and verify:

```bash
nerdctl build --no-cache -t ex13app:v1.0.0 /tmp/ex-1-3/
nerdctl image inspect ex13app:v1.0.0 --format '{{len .RootFS.Layers}}'
# Expected output: 5
```

The distinction matters for understanding image size. `LABEL`, `ENV`, `ARG`, `CMD`, and `ENTRYPOINT` are metadata-only instructions that affect the image configuration JSON but do not add any filesystem content. `FROM` imports all the layers from the base image (Alpine:3.20 already has layers; the `FROM` instruction makes this image inherit them, with alpine:3.20 contributing its own layers to the count). Each `RUN` instruction that executes shell commands creates a new layer containing the filesystem changes from that command. `WORKDIR` creates the directory if it does not exist, making a filesystem change and therefore a layer. `COPY` adds files to the filesystem, creating a layer.

---

## Exercise 2.1 Solution

The well-ordered Dockerfile at `/tmp/ex-2-1/Dockerfile`:

```dockerfile
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
```

Build the baseline (cold cache):

```bash
nerdctl build --no-cache -t localhost:5001/ex21app:v1.0.0 /tmp/ex-2-1/
nerdctl push localhost:5001/ex21app:v1.0.0
```

Update app.py to v2:

```bash
cat > /tmp/ex-2-1/app.py << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route("/")
def index():
    return "Exercise 2.1 app v2\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF
```

Rebuild and observe the cache behavior:

```bash
nerdctl build -t localhost:5001/ex21app:v1.0.1 /tmp/ex-2-1/
```

The output will show `CACHED` for the `FROM python:3.13-slim`, `WORKDIR /app`, `COPY requirements.txt .`, and `RUN pip install` layers. Only `COPY app.py .` runs fresh. Push the second tag:

```bash
nerdctl push localhost:5001/ex21app:v1.0.1
```

The poorly-ordered `Dockerfile.bad` copies the entire source directory (`COPY . .`) before running `pip install`. Because `COPY . .` is sensitive to any file change in the directory (including changes to `app.py`), modifying `app.py` invalidates the `COPY . .` layer and forces `pip install` to rerun even though `requirements.txt` has not changed. By separating the dependency copy from the source copy, the `pip install` step only reruns when `requirements.txt` actually changes.

---

## Exercise 2.2 Solution

The correct choice for this workload is `python:3.13-slim`. Here is why: the workload requirements specify Python 3.13 with no C library dependencies and a production security policy requiring no shell. `ubuntu:24.04` is a full OS (700+ MB) with a shell and package manager, far more than needed. `alpine:3.20` has a shell and requires testing compatibility of Python wheels against musl libc. `gcr.io/distroless/python3:nonroot` has no shell (good for security) but its Python version and extension compatibility can be unpredictable for applications that use pip. The `python:3.13-slim` variant is Debian-based with glibc (ensuring pip wheel compatibility), removes most non-essential packages, and stays well under 150 MB.

```bash
cat > /tmp/ex-2-2/Dockerfile << 'EOF'
FROM python:3.13-slim
WORKDIR /app
COPY app.py .
CMD ["python", "app.py"]
EOF

nerdctl build -t localhost:5001/ex22app:v1.0.0 /tmp/ex-2-2/
nerdctl push localhost:5001/ex22app:v1.0.0
```

Justification file:

```bash
cat > /tmp/ex-2-2/choice.txt << 'EOF'
python:3.13-slim is the correct choice for this workload. ubuntu:24.04 is too large (700+ MB) and includes a full package manager and shell that are not needed at runtime. alpine:3.20 requires validating all Python wheels against musl libc, which adds testing overhead and risk. gcr.io/distroless/python3:nonroot has version and compatibility constraints that make pip-based dependency management unreliable. python:3.13-slim provides the exact Python version needed, uses glibc for full pip wheel compatibility, and stays well under 150 MB.
EOF
```

---

## Exercise 2.3 Solution

Retrieve the actual digest after pushing:

```bash
# Get the manifest digest of the pushed image
DIGEST=$(nerdctl image inspect localhost:5001/ex23app:v1.0.0 \
  --format '{{index .RepoDigests 0}}' | cut -d@ -f2)
echo "Using digest: $DIGEST"
```

Write and apply the pod manifest with digest pinning:

```bash
kubectl apply -n ex-2-3 -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  name: digest-pinned
  namespace: ex-2-3
spec:
  containers:
  - name: app
    image: localhost:5001/ex23app@${DIGEST}
    imagePullPolicy: IfNotPresent
EOF
```

Wait for the pod to be ready:

```bash
kubectl wait -n ex-2-3 --for=condition=Ready pod/digest-pinned --timeout=60s
```

The digest-pinned reference (`localhost:5001/ex23app@sha256:...`) is immutable: it will always resolve to the same manifest regardless of what tags change in the registry. The tag `v1.0.0` is mutable: if someone pushes a new image with that tag, any pod restarted with `imagePullPolicy: Always` would get the new image silently. Digest pinning eliminates this risk and is the correct approach for production deployments where reproducibility matters.

---

## Exercise 3.1 Solution

### Diagnosis

Run the build and read the error:

```bash
nerdctl build -t localhost:5001/ex31server:v1.0.0 /tmp/ex-3-1/
```

The build fails with an error similar to:

```text
failed to solve: failed to compute cache key: failed to copy: please provide the source file
```

or more specifically:

```text
ERROR: failed to solve: failed to read dockerfile: failed to copy: stage "builder" not found
```

Read the Dockerfile carefully, focusing on the stage names and the COPY --from reference:

```bash
cat /tmp/ex-3-1/Dockerfile
```

Look at the first `FROM` line and the `COPY --from=` line in the second stage.

### What the Bug Is and Why It Happens

The first stage is named `compile` (via `AS compile`), but the `COPY --from=builder` instruction in the second stage references a stage named `builder`. There is no stage named `builder` in this Dockerfile. BuildKit cannot resolve the `--from=builder` reference, so the build fails with a stage-not-found error.

This is a common mistake when a Dockerfile is refactored: a developer renames a stage for clarity (`compile` is a reasonable name for a build stage) but forgets to update all the `COPY --from=` instructions that reference the old name. The error message can be confusing because it sometimes reports a cache key error rather than directly saying "stage not found."

### Fix

Change `COPY --from=builder` to `COPY --from=compile` to match the stage name defined in the first `FROM` instruction:

```dockerfile
FROM golang:1.22-alpine AS compile
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=compile /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

Apply the fix and rebuild:

```bash
# Edit the Dockerfile to fix the stage name reference
sed -i 's/COPY --from=builder/COPY --from=compile/' /tmp/ex-3-1/Dockerfile

# Rebuild
nerdctl build -t localhost:5001/ex31server:v1.0.0 /tmp/ex-3-1/

# Verify it runs
nerdctl run -d --rm -p 18085:8080 --name ex-3-1-test localhost:5001/ex31server:v1.0.0
sleep 2
curl -s http://localhost:18085/
nerdctl rm -f ex-3-1-test
```

---

## Exercise 3.2 Solution

### Diagnosis

Check the pod status:

```bash
kubectl get pod -n ex-3-2 digest-consumer
```

The STATUS will show `ImagePullBackOff` or `ErrImagePull`. Read the events:

```bash
kubectl describe pod -n ex-3-2 digest-consumer
```

Look at the Events section at the bottom of the output. You will see a message like:

```text
Failed to pull image "localhost:5001/ex32app@sha256:0000000000000000000000000000000000000000000000000000000000000000":
failed to pull and unpack image: failed to resolve reference: unexpected status code: 404 Not Found
```

The registry returned 404 because no manifest with the all-zeros digest exists. The error confirms the digest in the pod spec is invalid.

Check what the actual digest of the image in the registry is:

```bash
nerdctl images --digests localhost:5001/ex32app:v1.0.0
```

The DIGEST column shows the real manifest digest (a long hex string that is definitely not all zeros).

### What the Bug Is and Why It Happens

The pod spec contains `sha256:0000...0000` as the image digest. This is a fabricated placeholder that does not correspond to any manifest in the registry. The registry API returns 404 when it receives a request for a digest that does not exist, which the kubelet reports as `ErrImagePull`. After several failed pull attempts the kubelet enters exponential backoff, which is what `ImagePullBackOff` means: the kubelet is waiting before retrying because repeated failures have triggered a cooldown.

This scenario happens in practice when a digest is copied incorrectly (truncated, edited, or fabricated), when a CI system writes a placeholder that was never replaced, or when the registry garbage-collects a manifest that the pod spec still references.

### Fix

Get the actual digest from the registry and update the pod spec:

```bash
# Get the real digest
REAL_DIGEST=$(nerdctl image inspect localhost:5001/ex32app:v1.0.0 \
  --format '{{index .RepoDigests 0}}' | cut -d@ -f2)
echo "Real digest: $REAL_DIGEST"

# Delete the broken pod
kubectl delete pod -n ex-3-2 digest-consumer

# Recreate with the correct digest
kubectl apply -n ex-3-2 -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  name: digest-consumer
  namespace: ex-3-2
spec:
  containers:
  - name: app
    image: localhost:5001/ex32app@${REAL_DIGEST}
    imagePullPolicy: Always
EOF

kubectl wait -n ex-3-2 --for=condition=Ready pod/digest-consumer --timeout=60s
```

---

## Exercise 3.3 Solution

### Diagnosis

Attempt to push as instructed and observe the error:

```bash
nerdctl push ex33nginx:v1.0.0
```

The error message will be something like:

```text
time="..." level=fatal msg="failed to push: failed to do request: ... 
cannot parse reference \"ex33nginx:v1.0.0\" 
... does not exist on remote registry"
```

Or in some versions of nerdctl:

```text
FATA[...] failed to push: unexpected status code: 404 Not Found
```

The core problem: `nerdctl push` interprets the image name `ex33nginx:v1.0.0` as a reference to the public Docker Hub registry (or the default registry configured for nerdctl). There is no `ex33nginx` repository on Docker Hub, so the push fails. The local registry at `localhost:5001` never receives the push request.

Check what images are tagged and confirm the one you want to push exists locally:

```bash
nerdctl images | grep ex33nginx
```

You will see `ex33nginx v1.0.0` in the local image store, confirming it was built but tagged without the registry hostname prefix.

### What the Bug Is and Why It Happens

For a registry push to reach `localhost:5001`, the image tag must include `localhost:5001/` as a prefix: `localhost:5001/ex33nginx:v1.0.0`. The image was built with just `ex33nginx:v1.0.0`, which has no registry host prefix. When nerdctl (or Docker) sees a tag without a hostname, it defaults to the configured default registry, which is typically `docker.io` (Docker Hub). The push then goes to the wrong destination.

This is one of the most common mistakes when starting with local registries: forgetting to include the registry host in the tag at build time. The build succeeds, the image is local, but the push fails because the tag is not routed to the correct registry.

### Fix

Tag the existing image with the registry hostname prefix and then push:

```bash
# Add the registry-prefixed tag to the existing image
nerdctl tag ex33nginx:v1.0.0 localhost:5001/ex33nginx:v1.0.0

# Push the correctly-tagged version
nerdctl push localhost:5001/ex33nginx:v1.0.0

# Verify the registry received it
curl -s http://localhost:5001/v2/ex33nginx/tags/list
```

Alternatively, you could rebuild with the correct tag from the start:

```bash
nerdctl build -t localhost:5001/ex33nginx:v1.0.0 /tmp/ex-3-3/
nerdctl push localhost:5001/ex33nginx:v1.0.0
```

The `nerdctl tag` approach is faster since it avoids a full rebuild.

---

## Exercise 4.1 Solution

Write the Dockerfile at `/tmp/ex-4-1/Dockerfile`:

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

Build and push:

```bash
nerdctl build -t localhost:5001/goserver:v1.0.0 /tmp/ex-4-1/
nerdctl push localhost:5001/goserver:v1.0.0
```

Deploy the Deployment:

```bash
kubectl apply -n ex-4-1 -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: goserver
  namespace: ex-4-1
spec:
  replicas: 2
  selector:
    matchLabels:
      app: goserver
  template:
    metadata:
      labels:
        app: goserver
    spec:
      containers:
      - name: server
        image: localhost:5001/goserver:v1.0.0
        env:
        - name: APP_VERSION
          value: "v1.0.0"
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 3
          periodSeconds: 5
EOF

kubectl rollout status deployment/goserver -n ex-4-1 --timeout=120s
```

Verify:

```bash
kubectl port-forward -n ex-4-1 deployment/goserver 18087:8080 &
PF_PID=$!
sleep 3
curl -s http://localhost:18087/
kill $PF_PID 2>/dev/null
```

---

## Exercise 4.2 Solution

Write the Dockerfile at `/tmp/ex-4-2/Dockerfile` (same structure as 4.1):

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

Build and push:

```bash
nerdctl build -t localhost:5001/goserver:v1.1.0 /tmp/ex-4-2/
nerdctl push localhost:5001/goserver:v1.1.0
```

Update the Deployment image and environment variable:

```bash
kubectl set image deployment/goserver server=localhost:5001/goserver:v1.1.0 -n ex-4-2
kubectl set env deployment/goserver APP_VERSION=v1.1.0 -n ex-4-2
kubectl rollout status deployment/goserver -n ex-4-2 --timeout=120s
```

Alternatively, patch both in a single apply. The `kubectl set image` approach is the most exam-relevant because it is fast and works without editing a YAML file.

Verify:

```bash
kubectl port-forward -n ex-4-2 deployment/goserver 18088:8080 &
PF_PID=$!
sleep 3
curl -s http://localhost:18088/
kill $PF_PID 2>/dev/null
```

The rolling update works by creating new pods with the updated image, waiting for them to pass the readiness probe, and then terminating old pods. The Deployment's `strategy.rollingUpdate.maxUnavailable` defaults to 25% (rounded down to 0 for small replica counts), so you will always have at least some pods serving traffic during the update.

---

## Exercise 4.3 Solution

Write the optimized Dockerfile at `/tmp/ex-4-3/Dockerfile`:

```dockerfile
FROM python:3.13-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 8080
CMD ["python", "app.py"]
```

Build and push:

```bash
nerdctl build -t localhost:5001/pyapp:v1.0.0 /tmp/ex-4-3/
nerdctl push localhost:5001/pyapp:v1.0.0
```

Deploy:

```bash
kubectl apply -n ex-4-3 -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pyapp
  namespace: ex-4-3
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pyapp
  template:
    metadata:
      labels:
        app: pyapp
    spec:
      containers:
      - name: app
        image: localhost:5001/pyapp:v1.0.0
        ports:
        - containerPort: 8080
        readinessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
EOF

kubectl rollout status deployment/pyapp -n ex-4-3 --timeout=120s
```

The key Dockerfile ordering here is: `COPY requirements.txt .` then `RUN pip install` then `COPY app.py .`. Flask has several transitive dependencies (Werkzeug, Jinja2, click, etc.) and pip install for this set takes 10 to 15 seconds. By separating the dependency install from the source copy, every rebuild that changes only `app.py` reuses the pip install layer and completes in under 2 seconds instead of 15+.

---

## Exercise 5.1 Solution

### Diagnosis

Check the pod status immediately after setup:

```bash
kubectl get pod -n ex-5-1 crasher
```

The STATUS will show `CrashLoopBackOff`. Check the container logs:

```bash
kubectl logs -n ex-5-1 crasher
```

You may see no output at all, or a very short message before the container exits. This indicates the binary started but crashed at the OS level before any user-space code ran. Check the container exit code:

```bash
kubectl describe pod -n ex-5-1 crasher
```

Look at the `Last State` section under the container status. The `Exit Code` field will likely show `132` (SIGILL, illegal instruction) or `1` (general error). You may also see a message referencing the dynamic linker, such as `/lib/x86_64-linux-gnu/libc.so.6: version 'GLIBC_2.34' not found` in the describe output events, or no message at all if the crash happens before the C runtime initializes.

Inspect the Dockerfile to find the build configuration:

```bash
cat /tmp/ex-5-1/Dockerfile
```

The first stage uses `FROM golang:1.22` (the standard Debian-based golang image). The `RUN` command for the build is `GOOS=linux go build -o server .` without setting `CGO_ENABLED=0`. On a Debian-based Go builder, when CGO_ENABLED is not explicitly set to 0, it defaults to 1. This means the Go compiler links the networking stack and other stdlib components against glibc via CGO. The resulting binary requires glibc at runtime to load the dynamic linker. The final stage is `gcr.io/distroless/static:nonroot`, which has no libc of any kind. The dynamic linker path (`/lib/x86_64-linux-gnu/ld-linux-x86_64.so.2`) does not exist in the filesystem, so the kernel cannot start the process and the container exits with a crash immediately.

### What the Bug Is and Why It Happens

The bug is the missing `CGO_ENABLED=0` flag in the Go build command. When using a Debian-based golang image (`golang:1.22`, not `-alpine`), the default CGO_ENABLED=1 causes the Go runtime to dynamically link against glibc for DNS resolution and some other system calls. The resulting binary cannot run in distroless/static because distroless/static contains no libc. This failure mode is silent and confusing because the build itself succeeds completely (the compiler does not warn you that you are producing a dynamically linked binary that will be incompatible with your chosen runtime base).

This is different from the alpine-builder scenario. When using `golang:1.22-alpine` as the builder, CGO defaults to 0 because Alpine's musl libc environment does not easily support CGO without explicit configuration. The Debian-based `golang:1.22` image has glibc available and defaults CGO to 1 because glibc CGO linking works out of the box.

### Fix

Update the Dockerfile to add `CGO_ENABLED=0` to the build command:

```dockerfile
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

Rebuild with the fix, push, and update the pod:

```bash
# Write the fixed Dockerfile
cat > /tmp/ex-5-1/Dockerfile << 'EOF'
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
EOF

nerdctl build -t localhost:5001/ex51server:v1.0.1 /tmp/ex-5-1/
nerdctl push localhost:5001/ex51server:v1.0.1

# Delete the crashing pod and redeploy with the fixed image
kubectl delete pod -n ex-5-1 crasher

kubectl apply -n ex-5-1 -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: crasher
  namespace: ex-5-1
spec:
  containers:
  - name: server
    image: localhost:5001/ex51server:v1.0.1
    imagePullPolicy: Always
    ports:
    - containerPort: 8080
EOF

kubectl wait -n ex-5-1 --for=condition=Ready pod/crasher --timeout=60s
```

---

## Exercise 5.2 Solution

### Diagnosis

Check which cluster context you are on and then examine the pod:

```bash
kubectl config current-context
# Should show: kind-broken

kubectl get pod -n ex-5-2 registry-consumer
```

The STATUS will be `ImagePullBackOff`. Read the events:

```bash
kubectl describe pod -n ex-5-2 registry-consumer
```

In the Events section you will see a message like:

```text
Failed to pull image "localhost:5001/ex52app:v1.0.0": 
failed to pull and unpack image "localhost:5001/ex52app:v1.0.0": 
failed to resolve reference "localhost:5001/ex52app:v1.0.0": 
failed to do request: Head "https://localhost:5001/v2/ex52app/manifests/v1.0.0": 
dial tcp [::1]:5001: connect: connection refused
```

The error `connection refused` on `localhost:5001` from inside the kind node is the key signal. From the kind node's perspective, `localhost` refers to the node container itself, not your host machine. Port 5001 is not listening inside the kind node container; it is listening on your host. The kind node's containerd daemon does not have a mirror configuration telling it to resolve `localhost:5001` via a different endpoint.

Verify the cluster was created without containerdConfigPatches by checking if there is any registry mirror config on the node:

```bash
docker exec kind-broken-control-plane cat /etc/containerd/config.toml | grep -A5 "mirrors"
```

The output will be empty or show no mirrors section for `localhost:5001`.

### What the Bug Is and Why It Happens

The `kind-broken` cluster was created with a minimal configuration file that has no `containerdConfigPatches` block. Without this block, the containerd daemon on the kind nodes has no knowledge of the local registry at `localhost:5001` and no HTTP endpoint configured to resolve requests for `localhost:5001` images. When a pod on the kind cluster tries to pull `localhost:5001/ex52app:v1.0.0`, the containerd daemon on the node attempts an HTTPS connection to localhost port 5001, which does not exist from the node's network namespace. The connection is refused and the pull fails.

The `containerdConfigPatches` block is the mechanism that teaches kind nodes to treat a specific registry hostname as a mirror pointing to an actual HTTP endpoint. Without it, pulling from local insecure registries is impossible through the normal Kubernetes image pull flow.

### Fix (Option A: Recreate the cluster with correct configuration)

The most thorough fix is to recreate the broken cluster with the proper containerdConfigPatches. Delete the broken cluster, recreate it with the registry config, reconnect the registry to the kind network, and redeploy the pod.

```bash
# Delete the broken cluster
kind delete cluster --name broken

# Create it with the correct containerdConfigPatches
cat > /tmp/kind-fixed-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: broken
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5001"]
        endpoint = ["http://localhost:5001"]
EOF

KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster --config /tmp/kind-fixed-config.yaml

# Reconnect the registry to the kind network
nerdctl network connect kind kind-registry

# Switch kubectl to the fixed cluster
kubectl config use-context kind-broken

# Recreate the namespace and pod
kubectl create namespace ex-5-2
kubectl apply -n ex-5-2 -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: registry-consumer
  namespace: ex-5-2
spec:
  containers:
  - name: app
    image: localhost:5001/ex52app:v1.0.0
    imagePullPolicy: Always
EOF

kubectl wait -n ex-5-2 --for=condition=Ready pod/registry-consumer --timeout=60s
```

### Fix (Option B: Load the image directly into the broken cluster)

If recreating the cluster is not feasible, you can load the image directly into the kind node's containerd image store using `kind load docker-archive`. This bypasses the registry entirely and places the image directly in the node's image cache.

```bash
# Save the image to a tar archive
nerdctl save localhost:5001/ex52app:v1.0.0 -o /tmp/ex52app.tar

# Load it into the broken cluster's node
kind load docker-archive /tmp/ex52app.tar --name broken

# The pod needs imagePullPolicy: IfNotPresent to use the cached image
# (imagePullPolicy: Always would still try to pull from the registry)
kubectl delete pod -n ex-5-2 registry-consumer
kubectl apply -n ex-5-2 -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: registry-consumer
  namespace: ex-5-2
spec:
  containers:
  - name: app
    image: localhost:5001/ex52app:v1.0.0
    imagePullPolicy: IfNotPresent
EOF

kubectl wait -n ex-5-2 --for=condition=Ready pod/registry-consumer --timeout=60s
```

Option A is the correct long-term fix. Option B is a useful workaround for situations where the cluster cannot be recreated (for example, if it has other workloads running). Understanding both options matters for the exam.

---

## Exercise 5.3 Solution

### Diagnosis

Check the pod status:

```bash
kubectl get pod -n ex-5-3 scratch-server
```

The STATUS shows `CrashLoopBackOff`. Retrieve the logs:

```bash
kubectl logs -n ex-5-3 scratch-server
```

There will be no output, or the container exits so fast that logs are empty. Check the previous container logs for the exit reason:

```bash
kubectl logs -n ex-5-3 scratch-server --previous
```

Again, likely empty. Check the describe output for the exit code:

```bash
kubectl describe pod -n ex-5-3 scratch-server
```

Look at the container `Last State` block. The `Exit Code` will be `1` or `132`. With a scratch base image, the crash happens before any user-space initialization, which is why there are no log messages.

Examine the Dockerfile carefully:

```bash
cat /tmp/ex-5-3/Dockerfile
```

The builder uses `golang:1.22-alpine` and the build command explicitly sets `CGO_ENABLED=1`. Alpine's build environment requires installing `gcc` and `musl-dev` for CGO, which was done with `apk add --no-cache gcc musl-dev`. The resulting binary dynamically links against musl libc (Alpine's C library). The path to the musl dynamic linker is `/lib/ld-musl-x86_64.so.1`. The final stage is `FROM scratch`, which is a completely empty filesystem. When the kernel tries to start the binary, it looks for the dynamic linker path embedded in the binary's ELF header, finds nothing in the empty filesystem, and the process cannot start. This manifests as an immediate exit with code 1 (or 132 on some kernel versions).

### What the Bug Is and Why It Happens

The combination of `CGO_ENABLED=1` in an Alpine builder and a `FROM scratch` runtime stage is the problem. `CGO_ENABLED=1` tells the Go compiler to link against the system C library. In an Alpine environment, that library is musl libc. The linker embeds the path `/lib/ld-musl-x86_64.so.1` into the binary as the interpreter (the dynamic linker) that the kernel must load before executing the program. In a `FROM scratch` container, there is no `/lib/ld-musl-x86_64.so.1`, so the kernel cannot load the interpreter, and the process fails to start.

The `FROM scratch` base image works only for completely static binaries: binaries with no dynamic library dependencies at all. For Go programs, this requires `CGO_ENABLED=0`, which tells the Go compiler to implement all system interface calls (networking, file I/O, etc.) in pure Go without linking any external C library.

### Fix

Change `CGO_ENABLED=1` to `CGO_ENABLED=0` in the build command. With a static binary, `FROM scratch` is perfectly valid.

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM scratch
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]
```

Note that `RUN apk add --no-cache gcc musl-dev` is also no longer needed when CGO_ENABLED=0, and it would add an unnecessary layer. The simplified Dockerfile omits it.

Apply the fix:

```bash
cat > /tmp/ex-5-3/Dockerfile << 'EOF'
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM scratch
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]
EOF

nerdctl build -t localhost:5001/ex53server:v1.0.1 /tmp/ex-5-3/
nerdctl push localhost:5001/ex53server:v1.0.1

kubectl delete pod -n ex-5-3 scratch-server

kubectl apply -n ex-5-3 -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: scratch-server
  namespace: ex-5-3
spec:
  containers:
  - name: server
    image: localhost:5001/ex53server:v1.0.1
    imagePullPolicy: Always
    ports:
    - containerPort: 8080
EOF

kubectl wait -n ex-5-3 --for=condition=Ready pod/scratch-server --timeout=60s
```

Note that `FROM scratch` is even more minimal than `gcr.io/distroless/static:nonroot`. The scratch image has literally nothing, which means no SSL certificate bundle and no timezone data. If your Go application makes outbound TLS connections or uses `time.LoadLocation`, `FROM scratch` will cause runtime errors in those specific code paths. For a simple HTTP server that only accepts inbound connections, scratch works fine. For applications that need TLS or timezone support, use `gcr.io/distroless/static:nonroot` instead, which includes those files.

---

## Common Mistakes

**Forgetting CGO_ENABLED=0 when targeting distroless/static or scratch.** This is the most frequent mistake when writing multi-stage Dockerfiles for Go. The Debian-based `golang:1.22` image has glibc available, and CGO defaults to 1, so the binary links against glibc silently. The build succeeds, the binary is copied to distroless/static, and the pod crashes immediately with no useful logs. The fix is always `CGO_ENABLED=0 GOOS=linux` in the build RUN instruction. The alpine-based `golang:1.22-alpine` image has a lower risk of this mistake because CGO linking requires explicitly installing `gcc` and `musl-dev`, making the CGO dependency visible. With the Debian builder, CGO linking just works, which makes the mistake invisible until runtime.

**Tagging an image without the registry hostname prefix, then wondering why the push fails.** When you build with `nerdctl build -t myapp:v1.0.0`, the image is tagged for the default registry (docker.io for nerdctl and Docker). Running `nerdctl push myapp:v1.0.0` will attempt to push to Docker Hub, not your local registry. To push to `localhost:5001`, the image must be tagged as `localhost:5001/myapp:v1.0.0` either at build time (`-t localhost:5001/myapp:v1.0.0`) or afterwards with `nerdctl tag myapp:v1.0.0 localhost:5001/myapp:v1.0.0`. The correction is to always include the registry hostname in the tag when working with a non-default registry.

**Creating a kind cluster without containerdConfigPatches and then being confused by ImagePullBackOff.** The containerdConfigPatches block is not optional when using a local insecure registry with kind. Without it, kind nodes cannot resolve `localhost:5001` as a valid insecure mirror. The ImagePullBackOff error message says `connection refused` when read carefully, but the connection refused error is easy to misread as a network policy or pod spec problem. The correct diagnosis is to check whether the kind node's containerd config includes the mirror entry. The only fix that restores full registry functionality is recreating the cluster with the patches block; the image-load workaround (`kind load docker-archive`) bypasses the registry but does not fix the underlying configuration gap.

**Using a mutable tag (`latest` or a moving alias like `stable`) with imagePullPolicy: IfNotPresent in production.** If a pod is scheduled to a node that already has the image cached, `IfNotPresent` will use the cached version without checking whether the registry has a newer image under the same tag. A push that updates the `stable` tag will not propagate to nodes that already have the old image cached. The correct production practice is either to use immutable version tags (so a tag change always requires a pod spec update) or to use `imagePullPolicy: Always` (with the understanding that this adds a registry round-trip on every pod start). Digest pinning eliminates the problem entirely because the digest identifies the exact manifest, and a pod pinned to a digest cannot accidentally use a different image regardless of tag changes.

**Placing COPY source before dependency install in a Dockerfile.** A Dockerfile that copies all source files before installing dependencies (via `pip install`, `go mod download`, `npm install`, etc.) will reinstall all dependencies on every build where any source file changes. For a Python app with a large requirements.txt, this turns every source change into a multi-minute build. The correct ordering is: copy only the dependency manifest (requirements.txt, go.mod, package.json) first, install dependencies, then copy the remaining source. This way the dependency install layer is only invalidated when the manifest changes, not when application code changes.

**Referencing the wrong stage name in COPY --from=.** Multi-stage Dockerfiles break at build time when a `COPY --from=` instruction references a stage name that does not exist. The error message from BuildKit can be opaque ("failed to compute cache key" or "stage not found") and does not always clearly point to the line with the incorrect stage name. The most reliable way to catch this is to keep stage names short, consistent, and checked against every `COPY --from=` reference. A common pattern is to always name the first stage `builder` and use `COPY --from=builder` in the final stage, keeping the naming convention simple and memorable.

---

## Verification Commands Cheat Sheet

### Image Build and Inspection

| Task | Command | Expected output |
|------|---------|----------------|
| Build with no cache | `nerdctl build --no-cache -t name:tag .` | Exits 0, no CACHED labels |
| Build with cache | `nerdctl build -t name:tag .` | Exits 0, CACHED labels on unchanged layers |
| List images | `nerdctl images` | Table with REPOSITORY, TAG, SIZE columns |
| List with digests | `nerdctl images --digests` | Includes DIGEST column |
| Image size | `nerdctl images name:tag --format '{{.Size}}'` | Human-readable size string |
| Layer count | `nerdctl image inspect name:tag --format '{{len .RootFS.Layers}}'` | Integer |
| Image digests | `nerdctl image inspect name:tag --format '{{index .RepoDigests 0}}'` | `localhost:5001/name@sha256:...` |
| All image metadata | `nerdctl image inspect name:tag` | Large JSON object |

### Registry Operations

| Task | Command | Expected output |
|------|---------|----------------|
| Tag for local registry | `nerdctl tag src:tag localhost:5001/dst:tag` | No output (success) |
| Push to registry | `nerdctl push localhost:5001/name:tag` | Progress bars, then DIGEST line |
| Pull from registry | `nerdctl pull localhost:5001/name:tag` | Progress bars, exits 0 |
| Registry health | `curl -s http://localhost:5001/v2/` | `{}` |
| List repos | `curl -s http://localhost:5001/v2/_catalog` | `{"repositories":["name",...]}` |
| List tags | `curl -s http://localhost:5001/v2/name/tags/list` | `{"name":"name","tags":["v1.0.0",...]}` |

### Kubernetes Pod and Deployment Verification

| Task | Command | Expected output |
|------|---------|----------------|
| Pod phase | `kubectl get pod <name> -o jsonpath='{.status.phase}'` | `Running` |
| Pod image | `kubectl get pod <name> -o jsonpath='{.spec.containers[0].image}'` | Image reference string |
| Pull errors | `kubectl describe pod <name>` | Events section shows ErrImagePull or ImagePullBackOff with reason |
| Container exit code | `kubectl describe pod <name>` | `Last State: Terminated ... Exit Code: N` |
| Previous logs | `kubectl logs <name> --previous` | Logs from the previous container instance |
| Deployment ready replicas | `kubectl get deployment <name> -o jsonpath='{.status.readyReplicas}'` | Integer matching spec replicas |
| Rollout status | `kubectl rollout status deployment/<name>` | `deployment "..." successfully rolled out` |
| Rollout history | `kubectl rollout history deployment/<name>` | Table of revisions |
| Update image | `kubectl set image deployment/<name> <container>=<image>` | `deployment.apps/<name> image updated` |
| Readiness probe config | `kubectl get deployment <name> -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}'` | JSON probe object |

### Kind Cluster and Registry Integration

| Task | Command | Expected output |
|------|---------|----------------|
| Create cluster with config | `KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster --config config.yaml` | Cluster creation messages |
| Delete cluster | `kind delete cluster --name <name>` | `Deleting cluster "..." ...` |
| Connect registry to kind network | `nerdctl network connect kind kind-registry` | No output (success) |
| Check network members | `nerdctl network inspect kind --format '{{range .Containers}}{{.Name}} {{end}}'` | Lists containers on kind network |
| Load image directly | `nerdctl save name:tag -o img.tar && kind load docker-archive img.tar` | `Image "..." with ID "..." not yet present on node...loaded` |
| Check node image cache | `docker exec kind-control-plane crictl images` | Table of images in node containerd |
