# Container Images Homework -- Assignment 2

Work through the tutorial in `container-images-tutorial.md` before starting these exercises. The local registry and kind cluster setup from the tutorial is required for all exercises. Specifically: the kind-registry container must be running on port 5001, and your kind cluster must have been created with the `containerdConfigPatches` block that teaches kind nodes to reach `localhost:5001`. Verify both before starting.

```bash
# Verify registry is running
curl -s http://localhost:5001/v2/
# Expected: {}

# Verify kind cluster is up
kubectl get nodes
# Expected: one node in Ready state
```

## Level 1: Basic Fluency

### Exercise 1.1

**Objective:** Tag a public image for the local registry and push it. Then delete the local cached copy and verify the registry serves the image on a fresh pull.

**Setup:**

```bash
kubectl create namespace ex-1-1

# Pull nginx from the public registry if not already present
nerdctl pull nginx:1.27
```

**Task:**

Tag the `nginx:1.27` image as `localhost:5001/nginx:v1.0.0`. Push it to the local registry. Then remove both the original tag and the registry-tagged version from your local image store, and pull `localhost:5001/nginx:v1.0.0` fresh from the registry to prove it was stored there successfully. Finally, deploy a pod in namespace `ex-1-1` that uses the locally-registered image and verify the pod reaches Running state.

**Verification:**

```bash
# After pulling the image fresh from the registry, confirm it is present locally
nerdctl images localhost:5001/nginx:v1.0.0
# Expected: one row in the output with repository localhost:5001/nginx and tag v1.0.0

# Confirm the image digest is present (registry stored it correctly)
nerdctl images --digests localhost:5001/nginx:v1.0.0
# Expected: one row with a non-empty DIGEST column starting with sha256:

# Confirm the pod in ex-1-1 is Running
kubectl get pod -n ex-1-1 nginx-test -o jsonpath='{.status.phase}'
# Expected: Running

# Confirm the pod is using the correct image
kubectl get pod -n ex-1-1 nginx-test -o jsonpath='{.spec.containers[0].image}'
# Expected: localhost:5001/nginx:v1.0.0
```

### Exercise 1.2

**Objective:** Convert a provided single-stage Dockerfile to a multi-stage build that produces a smaller final image.

**Setup:**

```bash
kubectl create namespace ex-1-2
mkdir -p /tmp/ex-1-2

cat > /tmp/ex-1-2/main.go << 'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Exercise 1.2 server")
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

cat > /tmp/ex-1-2/go.mod << 'EOF'
module ex12server

go 1.22
EOF

cat > /tmp/ex-1-2/Dockerfile << 'EOF'
FROM golang:1.22-alpine
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .
ENTRYPOINT ["/app/server"]
EOF
```

**Task:**

Modify `/tmp/ex-1-2/Dockerfile` to use a two-stage build. The first stage (named `builder`) must use `golang:1.22-alpine` to compile the binary. The second stage must use `gcr.io/distroless/static:nonroot` as the runtime base, copy only the compiled binary from the builder stage, and set `USER nonroot:nonroot`. Build the multi-stage image as `localhost:5001/ex12server:v1.0.0` and push it to the local registry. Verify the image is under 20 MB.

**Verification:**

```bash
# Confirm the image exists in the local registry
curl -s http://localhost:5001/v2/ex12server/tags/list
# Expected: {"name":"ex12server","tags":["v1.0.0"]}

# Confirm the local image size is under 20 MB
nerdctl images localhost:5001/ex12server:v1.0.0 \
  --format '{{.Size}}'
# Expected: a value under 20MB (should be approximately 7MB)

# Run the image locally and confirm it responds
nerdctl run -d --rm -p 18082:8080 --name ex-1-2-test localhost:5001/ex12server:v1.0.0
sleep 2
curl -s http://localhost:18082/
# Expected: Exercise 1.2 server

nerdctl rm -f ex-1-2-test
```

### Exercise 1.3

**Objective:** Rebuild a Dockerfile with explicit knowledge of which instructions create new filesystem layers and which do not.

**Setup:**

```bash
kubectl create namespace ex-1-3
mkdir -p /tmp/ex-1-3

cat > /tmp/ex-1-3/Dockerfile << 'EOF'
FROM alpine:3.20
LABEL maintainer="student@example.com"
ENV APP_ENV=production
ARG BUILD_DATE
RUN apk add --no-cache curl
WORKDIR /app
COPY . .
RUN echo "build complete"
CMD ["sh", "-c", "echo hello"]
ENTRYPOINT ["sh"]
EOF

cat > /tmp/ex-1-3/app.txt << 'EOF'
placeholder app file
EOF
```

**Task:**

Study the Dockerfile in `/tmp/ex-1-3/Dockerfile`. Identify which instructions create new filesystem layers in the resulting image and which instructions add only metadata (with no new layer). Build the image as `ex13app:v1.0.0`. Then add only the layer-creating instructions to a new file at `/tmp/ex-1-3/layer-count.txt` (one instruction per line), and rebuild the image using `--no-cache` to confirm the number of layers in `RootFS.Layers` matches the number of layer-creating instructions you identified. Record the layer count in a file named `/tmp/ex-1-3/result.txt` containing only the integer count.

**Verification:**

```bash
# Build the image
nerdctl build -t ex13app:v1.0.0 /tmp/ex-1-3/

# Get the layer count from the image
LAYER_COUNT=$(nerdctl image inspect ex13app:v1.0.0 \
  --format '{{len .RootFS.Layers}}')
echo "Layer count: $LAYER_COUNT"
# Expected: 5 (FROM creates 1, RUN apk creates 1, WORKDIR creates 1, COPY creates 1, RUN echo creates 1)
# LABEL, ENV, ARG, CMD, ENTRYPOINT do not create layers

# Confirm your result.txt matches
cat /tmp/ex-1-3/result.txt
# Expected: 5

# Confirm layer-count.txt lists exactly those instructions
wc -l /tmp/ex-1-3/layer-count.txt
# Expected: 5
```

## Level 2: Multi-Concept

### Exercise 2.1

**Objective:** Reorder a poorly structured Dockerfile to maximize layer cache hits, then demonstrate the improvement by running two consecutive builds with only a source change.

**Setup:**

```bash
kubectl create namespace ex-2-1
mkdir -p /tmp/ex-2-1

cat > /tmp/ex-2-1/requirements.txt << 'EOF'
flask==3.0.3
EOF

cat > /tmp/ex-2-1/app.py << 'EOF'
from flask import Flask
app = Flask(__name__)

@app.route("/")
def index():
    return "Exercise 2.1 app v1\n"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

# This Dockerfile has a poor ordering that defeats layer caching
cat > /tmp/ex-2-1/Dockerfile.bad << 'EOF'
FROM python:3.13-slim
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir -r requirements.txt
CMD ["python", "app.py"]
EOF
```

**Task:**

Create `/tmp/ex-2-1/Dockerfile` with the instructions reordered so that `pip install` is cached whenever only `app.py` changes. Build the optimized image as `localhost:5001/ex21app:v1.0.0` with `--no-cache` to establish a cold baseline. Then change `app.py` to return `"Exercise 2.1 app v2\n"` and rebuild as `localhost:5001/ex21app:v1.0.1` without `--no-cache`. The second build must show `CACHED` for the `pip install` layer. Push both tags to the local registry.

**Verification:**

```bash
# Both tags must be in the registry
curl -s http://localhost:5001/v2/ex21app/tags/list
# Expected: {"name":"ex21app","tags":["v1.0.0","v1.0.1"]} (order may differ)

# Pull and run v1.0.1 to confirm the source change is present
nerdctl run -d --rm -p 18083:8080 --name ex-2-1-test localhost:5001/ex21app:v1.0.1
sleep 3
curl -s http://localhost:18083/
# Expected: Exercise 2.1 app v2

nerdctl rm -f ex-2-1-test

# Confirm the Dockerfile copies requirements.txt before app.py
grep -n "COPY" /tmp/ex-2-1/Dockerfile
# Expected: requirements.txt appears on an earlier line than app.py (or "." is not copied before requirements.txt)
```

### Exercise 2.2

**Objective:** Choose an appropriate base image for a given set of workload requirements, justify the choice, and build a working image using that base.

**Setup:**

```bash
kubectl create namespace ex-2-2
mkdir -p /tmp/ex-2-2
```

**Workload requirements:** A Python 3.13 web API that serves JSON responses. The application has no external C library dependencies. It will run in a production Kubernetes cluster with a strict security policy requiring no shell in the final image and minimized package footprint. It does not need apt or apk access at runtime. The image must be under 150 MB.

**Task:**

Choose one of the following base images for the runtime stage of this workload: `ubuntu:24.04`, `alpine:3.20`, `python:3.13-slim`, `gcr.io/distroless/python3:nonroot`. Write a short justification (two to three sentences) to `/tmp/ex-2-2/choice.txt` explaining which base you chose and why the others were ruled out for this specific workload. Then create `/tmp/ex-2-2/app.py` and `/tmp/ex-2-2/Dockerfile` using your chosen base, build the image as `localhost:5001/ex22app:v1.0.0`, and confirm it runs and returns a response.

```bash
# Minimal app.py for this exercise
cat > /tmp/ex-2-2/app.py << 'EOF'
import http.server
import json

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps({"status": "ok"}).encode())
    def log_message(self, format, *args):
        pass

if __name__ == "__main__":
    http.server.HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
EOF
```

**Verification:**

```bash
# Confirm the image is in the local registry
curl -s http://localhost:5001/v2/ex22app/tags/list
# Expected: {"name":"ex22app","tags":["v1.0.0"]}

# Confirm the image is under 150 MB
nerdctl images localhost:5001/ex22app:v1.0.0 --format '{{.Size}}'
# Expected: a value under 150MB

# Run and verify it responds with valid JSON
nerdctl run -d --rm -p 18084:8080 --name ex-2-2-test localhost:5001/ex22app:v1.0.0
sleep 3
curl -s http://localhost:18084/
# Expected: {"status": "ok"}

nerdctl rm -f ex-2-2-test

# Confirm your justification is present
wc -w /tmp/ex-2-2/choice.txt
# Expected: at least 20 words
```

### Exercise 2.3

**Objective:** Push an image to the local registry, retrieve its manifest digest, and deploy a Kubernetes pod that references the image by digest rather than tag.

**Setup:**

```bash
kubectl create namespace ex-2-3

# Build and push a simple image to pin
mkdir -p /tmp/ex-2-3
cat > /tmp/ex-2-3/Dockerfile << 'EOF'
FROM busybox:1.36
CMD ["sh", "-c", "echo 'digest-pinned image running'; sleep 3600"]
EOF

nerdctl build -t localhost:5001/ex23app:v1.0.0 /tmp/ex-2-3/
nerdctl push localhost:5001/ex23app:v1.0.0
```

**Task:**

Retrieve the manifest digest of `localhost:5001/ex23app:v1.0.0` using `nerdctl images --digests` or `nerdctl image inspect`. Then write a Pod manifest to `/tmp/ex-2-3/pinned-pod.yaml` for namespace `ex-2-3` that references the image by digest (in the form `localhost:5001/ex23app@sha256:<actual-digest>`) rather than by tag. The pod should have the name `digest-pinned` and set `imagePullPolicy: IfNotPresent`. Apply the manifest and verify the pod is running.

**Verification:**

```bash
# Confirm the pod is running
kubectl get pod -n ex-2-3 digest-pinned -o jsonpath='{.status.phase}'
# Expected: Running

# Confirm the pod image reference contains @sha256: (not a tag)
kubectl get pod -n ex-2-3 digest-pinned \
  -o jsonpath='{.spec.containers[0].image}'
# Expected: output containing @sha256: (e.g. localhost:5001/ex23app@sha256:...)

# Confirm imagePullPolicy is set correctly
kubectl get pod -n ex-2-3 digest-pinned \
  -o jsonpath='{.spec.containers[0].imagePullPolicy}'
# Expected: IfNotPresent
```

## Level 3: Debugging

### Exercise 3.1

**Setup:**

```bash
kubectl create namespace ex-3-1
mkdir -p /tmp/ex-3-1

cat > /tmp/ex-3-1/main.go << 'EOF'
package main

import (
	"fmt"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Exercise 3.1")
	})
	http.ListenAndServe(":8080", nil)
}
EOF

cat > /tmp/ex-3-1/go.mod << 'EOF'
module ex31server

go 1.22
EOF

cat > /tmp/ex-3-1/Dockerfile << 'EOF'
FROM golang:1.22-alpine AS compile
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
```

**Objective:** The Dockerfile above fails to build. Find and fix whatever is needed so that `nerdctl build -t localhost:5001/ex31server:v1.0.0 /tmp/ex-3-1/` succeeds and the resulting image runs correctly.

**Verification:**

```bash
# Build must succeed without errors
nerdctl build -t localhost:5001/ex31server:v1.0.0 /tmp/ex-3-1/
# Expected: exits with code 0, final line shows FINISHED

# Image must be present
nerdctl images localhost:5001/ex31server:v1.0.0
# Expected: one row with repository localhost:5001/ex31server

# Container must start and respond
nerdctl run -d --rm -p 18085:8080 --name ex-3-1-test localhost:5001/ex31server:v1.0.0
sleep 2
curl -s http://localhost:18085/
# Expected: Exercise 3.1

nerdctl rm -f ex-3-1-test
```

### Exercise 3.2

**Setup:**

```bash
kubectl create namespace ex-3-2

# Build and push a legitimate image so the registry has a valid entry
mkdir -p /tmp/ex-3-2
cat > /tmp/ex-3-2/Dockerfile << 'EOF'
FROM busybox:1.36
CMD ["sh", "-c", "echo 'ex-3-2 running'; sleep 3600"]
EOF
nerdctl build -t localhost:5001/ex32app:v1.0.0 /tmp/ex-3-2/
nerdctl push localhost:5001/ex32app:v1.0.0

# Apply a pod spec that references a corrupted digest
kubectl apply -n ex-3-2 -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: digest-consumer
  namespace: ex-3-2
spec:
  containers:
  - name: app
    image: localhost:5001/ex32app@sha256:0000000000000000000000000000000000000000000000000000000000000000
    imagePullPolicy: Always
EOF
```

**Objective:** The pod above is not running. Find and fix whatever is needed so that the pod named `digest-consumer` in namespace `ex-3-2` reaches `Running` state. You may delete and recreate the pod.

**Verification:**

```bash
# Pod must be in Running state
kubectl get pod -n ex-3-2 digest-consumer -o jsonpath='{.status.phase}'
# Expected: Running

# The image reference in the running pod must contain a valid sha256 digest
kubectl get pod -n ex-3-2 digest-consumer \
  -o jsonpath='{.spec.containers[0].image}'
# Expected: output containing @sha256: with a non-zero digest (64 hex characters)
```

### Exercise 3.3

**Setup:**

```bash
kubectl create namespace ex-3-3
mkdir -p /tmp/ex-3-3

cat > /tmp/ex-3-3/Dockerfile << 'EOF'
FROM nginx:1.27
RUN echo "ex-3-3 image" > /usr/share/nginx/html/index.html
EOF

# Build the image with a tag that is missing the registry hostname
nerdctl build -t ex33nginx:v1.0.0 /tmp/ex-3-3/
```

**Objective:** Pushing this image to the local registry is failing. Find and fix whatever is needed so that `nerdctl push` successfully stores the image in the local registry at `localhost:5001/ex33nginx:v1.0.0`.

**Verification:**

```bash
# The image must be queryable from the registry API
curl -s http://localhost:5001/v2/ex33nginx/tags/list
# Expected: {"name":"ex33nginx","tags":["v1.0.0"]}

# Pull the image fresh from the registry to confirm it is stored correctly
nerdctl pull localhost:5001/ex33nginx:v1.0.0
# Expected: exits with code 0

# The image must be pullable into a running container
nerdctl run -d --rm -p 18086:80 --name ex-3-3-test localhost:5001/ex33nginx:v1.0.0
sleep 2
curl -s http://localhost:18086/
# Expected: ex-3-3 image

nerdctl rm -f ex-3-3-test
```

## Level 4: Production-Style Build and Deploy

### Exercise 4.1

**Objective:** Build a multi-stage Go HTTP server image from provided source, push it to the local registry, and deploy it as a Kubernetes Deployment. Verify the deployment is healthy and serves HTTP correctly.

**Setup:**

```bash
kubectl create namespace ex-4-1
mkdir -p /tmp/ex-4-1

cat > /tmp/ex-4-1/main.go << 'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "v1.0.0"
	}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Go server %s\n", version)
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})
	log.Printf("Starting server version %s on :8080", version)
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

cat > /tmp/ex-4-1/go.mod << 'EOF'
module goserver

go 1.22
EOF
```

**Task:**

Write a multi-stage Dockerfile at `/tmp/ex-4-1/Dockerfile` using `golang:1.22-alpine` as the builder stage (named `builder`) and `gcr.io/distroless/static:nonroot` as the runtime stage. Build the image as `localhost:5001/goserver:v1.0.0`, push it to the local registry, and deploy it as a Deployment named `goserver` in namespace `ex-4-1` with 2 replicas. Set the `APP_VERSION` environment variable to `v1.0.0` in the container spec. Expose port 8080 and add a readiness probe on `/healthz`. Verify all replicas are Running and serving the correct response.

**Verification:**

```bash
# All replicas must be ready
kubectl get deployment -n ex-4-1 goserver \
  -o jsonpath='{.status.readyReplicas}'
# Expected: 2

# Both pods must be in Running phase
kubectl get pods -n ex-4-1 -l app=goserver \
  -o jsonpath='{range .items[*]}{.status.phase}{"\n"}{end}'
# Expected: Running (twice)

# The image tag in the deployment must be correct
kubectl get deployment -n ex-4-1 goserver \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: localhost:5001/goserver:v1.0.0

# Forward a port and verify the response content
kubectl port-forward -n ex-4-1 deployment/goserver 18087:8080 &
PF_PID=$!
sleep 3
curl -s http://localhost:18087/
# Expected: Go server v1.0.0

kill $PF_PID 2>/dev/null
```

### Exercise 4.2

**Objective:** Update the Go server from Exercise 4.1 to a new version, build and push the new image, then perform a rolling update on the Deployment and verify the rollout completes successfully.

**Setup:**

```bash
kubectl create namespace ex-4-2

# Create updated source with a new version string
mkdir -p /tmp/ex-4-2
cp /tmp/ex-4-1/go.mod /tmp/ex-4-2/go.mod

cat > /tmp/ex-4-2/main.go << 'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "v1.1.0"
	}
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "Go server %s (updated)\n", version)
	})
	http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ok")
	})
	log.Printf("Starting server version %s on :8080", version)
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

# Deploy v1.0.0 in ex-4-2 as the starting state
# (Reuse the image from ex-4-1 if already pushed, or rebuild)
nerdctl build -f /tmp/ex-4-1/Dockerfile -t localhost:5001/goserver:v1.0.0 /tmp/ex-4-1/ 2>/dev/null || true

kubectl apply -n ex-4-2 -f - << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: goserver
  namespace: ex-4-2
spec:
  replicas: 3
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
EOF

kubectl rollout status deployment/goserver -n ex-4-2 --timeout=60s
```

**Task:**

Using the source in `/tmp/ex-4-2/`, write a multi-stage Dockerfile at `/tmp/ex-4-2/Dockerfile` (same structure as Exercise 4.1: `golang:1.22-alpine` builder, `gcr.io/distroless/static:nonroot` runtime). Build the image as `localhost:5001/goserver:v1.1.0` and push it. Then update the `goserver` Deployment in namespace `ex-4-2` to use the new image (`localhost:5001/goserver:v1.1.0`) and update the `APP_VERSION` environment variable to `v1.1.0`. Wait for the rollout to complete and verify the new version is serving.

**Verification:**

```bash
# Rollout must complete successfully
kubectl rollout status deployment/goserver -n ex-4-2 --timeout=120s
# Expected: deployment "goserver" successfully rolled out

# All replicas must be at the new image
kubectl get pods -n ex-4-2 -l app=goserver \
  -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}'
# Expected: localhost:5001/goserver:v1.1.0 (three times)

# The deployment image must reflect the update
kubectl get deployment -n ex-4-2 goserver \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: localhost:5001/goserver:v1.1.0

# Forward port and verify the updated response
kubectl port-forward -n ex-4-2 deployment/goserver 18088:8080 &
PF_PID=$!
sleep 3
curl -s http://localhost:18088/
# Expected: Go server v1.1.0 (updated)

kill $PF_PID 2>/dev/null

# Verify the rollout history shows two revisions
kubectl rollout history deployment/goserver -n ex-4-2
# Expected: at least 2 revisions listed
```

### Exercise 4.3

**Objective:** Build a Python Flask application image optimized for layer caching, push it to the local registry, and deploy it as a Deployment.

**Setup:**

```bash
kubectl create namespace ex-4-3
mkdir -p /tmp/ex-4-3

cat > /tmp/ex-4-3/requirements.txt << 'EOF'
flask==3.0.3
EOF

cat > /tmp/ex-4-3/app.py << 'EOF'
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def index():
    return jsonify({"service": "ex-4-3", "version": "1.0.0", "status": "running"})

@app.route("/healthz")
def health():
    return "ok", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF
```

**Task:**

Write a Dockerfile at `/tmp/ex-4-3/Dockerfile` using `python:3.13-slim` as the base. The Dockerfile must be structured so that `pip install` is cached when only `app.py` changes (copy `requirements.txt` and run `pip install` before copying `app.py`). Build the image as `localhost:5001/pyapp:v1.0.0` and push it to the local registry. Deploy it as a Deployment named `pyapp` with 2 replicas in namespace `ex-4-3`. Add a readiness probe on `/healthz` (HTTP GET, port 8080). Verify the deployment is healthy and returns the expected JSON response.

**Verification:**

```bash
# Deployment must have 2 ready replicas
kubectl get deployment -n ex-4-3 pyapp \
  -o jsonpath='{.status.readyReplicas}'
# Expected: 2

# Image must be correct
kubectl get deployment -n ex-4-3 pyapp \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
# Expected: localhost:5001/pyapp:v1.0.0

# Readiness probe must be configured
kubectl get deployment -n ex-4-3 pyapp \
  -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}'
# Expected: /healthz

# Forward port and verify JSON response
kubectl port-forward -n ex-4-3 deployment/pyapp 18089:8080 &
PF_PID=$!
sleep 5
curl -s http://localhost:18089/
# Expected: {"service": "ex-4-3", "version": "1.0.0", "status": "running"} (keys may be in any order)

kill $PF_PID 2>/dev/null

# Confirm Dockerfile copies requirements.txt before app source
grep -n "requirements.txt" /tmp/ex-4-3/Dockerfile
# Expected: a line number lower than the COPY for app.py
```

## Level 5: Advanced Debugging

### Exercise 5.1

**Setup:**

```bash
kubectl create namespace ex-5-1
mkdir -p /tmp/ex-5-1

cat > /tmp/ex-5-1/main.go << 'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ex-5-1 server")
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

cat > /tmp/ex-5-1/go.mod << 'EOF'
module ex51server

go 1.22
EOF

# This Dockerfile has a build flag issue that causes a runtime crash
cat > /tmp/ex-5-1/Dockerfile << 'EOF'
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN GOOS=linux go build -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
EOF

# Build and push the broken image
nerdctl build -t localhost:5001/ex51server:v1.0.0 /tmp/ex-5-1/
nerdctl push localhost:5001/ex51server:v1.0.0

# Deploy it
kubectl apply -n ex-5-1 -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: crasher
  namespace: ex-5-1
spec:
  containers:
  - name: server
    image: localhost:5001/ex51server:v1.0.0
    imagePullPolicy: Always
    ports:
    - containerPort: 8080
EOF
```

**Objective:** The pod above is not staying Running. The configuration above has one or more problems. Find and fix whatever is needed so that the pod named `crasher` in namespace `ex-5-1` reaches and stays in `Running` state and responds to HTTP requests.

**Verification:**

```bash
# Pod must be in Running state and not restarting
kubectl get pod -n ex-5-1 crasher
# Expected: STATUS=Running, RESTARTS=0 (or very low)

kubectl get pod -n ex-5-1 crasher -o jsonpath='{.status.phase}'
# Expected: Running

# Container must respond to HTTP after port forwarding
kubectl port-forward -n ex-5-1 pod/crasher 18090:8080 &
PF_PID=$!
sleep 3
curl -s http://localhost:18090/
# Expected: ex-5-1 server

kill $PF_PID 2>/dev/null

# The fixed image must be in the local registry
curl -s http://localhost:5001/v2/ex51server/tags/list
# Expected: contains v1.0.0 or v1.0.1 (whichever tag you used for the fix)
```

### Exercise 5.2

**Setup:**

```bash
# Create a broken kind cluster without the registry configuration
cat > /tmp/kind-broken-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: broken
EOF

# Verify the local registry is still running from the tutorial setup
nerdctl ps --filter name=kind-registry

# Build and push a test image to the local registry
mkdir -p /tmp/ex-5-2
cat > /tmp/ex-5-2/Dockerfile << 'EOF'
FROM busybox:1.36
CMD ["sh", "-c", "echo 'ex-5-2 running'; sleep 3600"]
EOF
nerdctl build -t localhost:5001/ex52app:v1.0.0 /tmp/ex-5-2/
nerdctl push localhost:5001/ex52app:v1.0.0

# Create the broken cluster (no containerdConfigPatches)
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster --config /tmp/kind-broken-config.yaml

# Switch kubectl to the broken cluster
kubectl config use-context kind-broken

# Deploy a pod that tries to pull from the local registry
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
```

**Objective:** The pod `registry-consumer` in namespace `ex-5-2` on the `kind-broken` cluster is not running. The configuration above has one or more problems. Find and fix whatever is needed so the pod reaches `Running` state. You may use any valid approach, including recreating the cluster or loading the image by an alternative method.

**Verification:**

```bash
# Ensure you are on the correct cluster context
kubectl config current-context
# Expected: kind-broken

# Pod must be in Running state
kubectl get pod -n ex-5-2 registry-consumer -o jsonpath='{.status.phase}'
# Expected: Running

# Container must be running the correct image
kubectl get pod -n ex-5-2 registry-consumer \
  -o jsonpath='{.spec.containers[0].image}'
# Expected: localhost:5001/ex52app:v1.0.0

# Switch back to the original cluster after completing this exercise
kubectl config use-context kind-kind
```

### Exercise 5.3

**Setup:**

```bash
kubectl config use-context kind-kind
kubectl create namespace ex-5-3
mkdir -p /tmp/ex-5-3

cat > /tmp/ex-5-3/main.go << 'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "ex-5-3 server")
	})
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

cat > /tmp/ex-5-3/go.mod << 'EOF'
module ex53server

go 1.22
EOF

# This Dockerfile builds successfully but the container crashes at runtime
cat > /tmp/ex-5-3/Dockerfile << 'EOF'
FROM golang:1.22-alpine AS builder
WORKDIR /app
RUN apk add --no-cache gcc musl-dev
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=1 GOOS=linux go build -o server .

FROM scratch
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]
EOF

# Build and push the broken image
nerdctl build -t localhost:5001/ex53server:v1.0.0 /tmp/ex-5-3/
nerdctl push localhost:5001/ex53server:v1.0.0

# Deploy it
kubectl apply -n ex-5-3 -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: scratch-server
  namespace: ex-5-3
spec:
  containers:
  - name: server
    image: localhost:5001/ex53server:v1.0.0
    imagePullPolicy: Always
    ports:
    - containerPort: 8080
EOF
```

**Objective:** The pod `scratch-server` in namespace `ex-5-3` is not staying Running. The configuration above has one or more problems. Find and fix whatever is needed so that the pod reaches and stays in `Running` state and responds to HTTP requests on port 8080.

**Verification:**

```bash
# Pod must be in Running state
kubectl get pod -n ex-5-3 scratch-server -o jsonpath='{.status.phase}'
# Expected: Running

# Pod must not be restarting frequently
kubectl get pod -n ex-5-3 scratch-server \
  -o jsonpath='{.status.containerStatuses[0].restartCount}'
# Expected: 0

# Container must respond after port forwarding
kubectl port-forward -n ex-5-3 pod/scratch-server 18091:8080 &
PF_PID=$!
sleep 3
curl -s http://localhost:18091/
# Expected: ex-5-3 server

kill $PF_PID 2>/dev/null

# The fixed image must be present in the registry
curl -s http://localhost:5001/v2/ex53server/tags/list
# Expected: JSON with tags list containing your fixed tag
```

## Cleanup

After completing all exercises, delete the exercise namespaces and clean up host resources.

```bash
# Delete all exercise namespaces from the main cluster
kubectl config use-context kind-kind
for ns in ex-1-1 ex-1-2 ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-3-3 ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-3; do
  kubectl delete namespace $ns --ignore-not-found
done

# Delete the broken cluster from exercise 5.2
kind delete cluster --name broken

# Clean up temporary directories
rm -rf /tmp/ex-1-1 /tmp/ex-1-2 /tmp/ex-1-3 /tmp/ex-2-1 /tmp/ex-2-2 /tmp/ex-2-3
rm -rf /tmp/ex-3-1 /tmp/ex-3-2 /tmp/ex-3-3 /tmp/ex-4-1 /tmp/ex-4-2 /tmp/ex-4-3
rm -rf /tmp/ex-5-1 /tmp/ex-5-2 /tmp/ex-5-3

# Stop the local registry and clean up images (only after exercises are complete)
nerdctl rm -f kind-registry
```

## Key Takeaways

Multi-stage builds are not optional for compiled languages in production: the difference between a 300 MB single-stage image and a 7 MB multi-stage image is the entire build toolchain, and that toolchain is an attack surface you do not need at runtime. Dockerfile instruction ordering is not aesthetic: placing frequently-changing instructions after rarely-changing ones directly reduces build time for every developer on the team. Base image selection is a real tradeoff between debuggability and attack surface: distroless/static provides the smallest attack surface but requires static binaries and debugging through ephemeral containers. Tags are mutable pointers; digests are immutable content hashes. Digest pinning in pod specs is the only way to guarantee that a re-deployed pod uses exactly the same image binary. The kind cluster needs explicit configuration to reach a local insecure registry: the `containerdConfigPatches` block in the kind cluster config is what enables node-level pulls from `localhost:5001`, and its absence causes ImagePullBackOff for any image stored in the local registry.
