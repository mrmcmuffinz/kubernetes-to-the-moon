# Container Images Tutorial: Multi-Stage Builds, Layer Caching, and Local Registry Operations

Container images are the unit of deployment in Kubernetes, and understanding what is inside them, how they are built, and where they come from is fundamental to operating a cluster reliably. In assignment 1 you learned how to write a Dockerfile, build an image with nerdctl, and inspect the resulting layers. This tutorial goes a level deeper: you will learn why multi-stage builds produce dramatically smaller and safer images, how to structure your Dockerfile so the build cache works for you rather than against you, how to choose an appropriate base image for a given workload, and how to push and pull images through a local container registry configured to work with your kind cluster.

The complete worked example is a Go HTTP server. You will build it first as a naive single-stage image (which ends up over 300 MB), then as a multi-stage image that produces a final image under 10 MB using a distroless base, then restructure the Dockerfile to maximize layer cache reuse, and finally push it to a local registry and deploy it to the kind cluster. Along the way you will explore what the OCI image format actually contains and how content-addressing via SHA256 makes tags and digests behave very differently from one another.

All tutorial resources that land in the Kubernetes cluster go into a dedicated namespace called `tutorial-container-images`. Resources you build on the host (images, Dockerfiles, the registry itself) are scoped by directory and image name.

## Prerequisites

You need a working kind cluster and kubectl before starting this tutorial. Verify both with the following commands.

```bash
kubectl get nodes
kubectl cluster-info
```

If the cluster is not running, follow the single-node kind cluster setup in [docs/cluster-setup.md](../../../docs/cluster-setup.md#single-node-kind-cluster) before continuing.

This tutorial also requires nerdctl for building and pushing images. Verify nerdctl is available.

```bash
nerdctl version
```

You should see both client and server version information. If nerdctl is not available, follow your platform setup to install it.

## Part 1: Setting Up the Local Registry and Kind Cluster

The standard kind workflow for image distribution during development is `kind load docker-archive`, which loads a pre-built image directly into the kind node's containerd store. That workflow bypasses the registry entirely, which is convenient for simple cases but does not mirror how production clusters work. Production clusters pull images from a registry over the network, and the exercises in this assignment use a real push/pull workflow through a local registry. Setting this up requires two pieces: a registry container running on the host, and a kind cluster configured to recognize that registry as a trusted mirror.

### Starting the Registry Container

Run the official registry image. Version 2 of the registry (which maps to image tag `registry:2`) is the standard self-hosted registry. The `-p 5001:5000` flag maps port 5001 on your host to port 5000 inside the registry container, and `--restart=always` ensures the registry survives host reboots.

```bash
nerdctl run -d \
  --name kind-registry \
  --restart=always \
  -p 5001:5000 \
  registry:2
```

Verify the registry is running and listening.

```bash
nerdctl ps --filter name=kind-registry
curl -s http://localhost:5001/v2/
```

The curl command should return `{}`. That is the empty repository list response from the registry API and it confirms the registry is reachable and healthy. If curl fails, check the nerdctl logs for the registry container with `nerdctl logs kind-registry`.

### Creating the Kind Cluster with Registry Configuration

A plain kind cluster does not know about your local registry. When a pod tries to pull `localhost:5001/myimage:v1.0.0`, the kind node's containerd daemon does not know that `localhost:5001` is accessible and trusted as an HTTP (insecure) registry. Without configuration, the pull will fail with a connection error or a TLS certificate error.

The fix is to include a `containerdConfigPatches` block in the kind cluster configuration. This block is written directly into the containerd configuration on each kind node at cluster creation time, telling containerd to treat `localhost:5001` as a mirror with an HTTP endpoint.

Create the kind cluster configuration file.

```bash
cat > /tmp/kind-registry-config.yaml << 'EOF'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches:
- |-
  [plugins."io.containerd.grpc.v1.cri".registry]
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors]
      [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:5001"]
        endpoint = ["http://localhost:5001"]
EOF
```

Create the cluster using this configuration.

```bash
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster --config /tmp/kind-registry-config.yaml
```

This takes a few minutes. When it finishes, verify the cluster is running.

```bash
kubectl get nodes
```

You should see one control-plane node in `Ready` state.

### Connecting the Registry to the Kind Network

Kind creates its own Docker/nerdctl network called `kind`. The nodes inside the cluster can reach other containers on that network, but the registry container was created before the cluster and is not on the kind network yet. Connect it now.

```bash
nerdctl network connect kind kind-registry
```

This command has no output on success. Verify the registry is on the kind network.

```bash
nerdctl network inspect kind --format '{{range .Containers}}{{.Name}} {{end}}'
```

You should see both the kind control-plane container and `kind-registry` in the output.

### Verifying the Complete Setup

Push a test image to the registry and verify a pod in the cluster can pull it. First, pull the busybox image from the public registry, tag it for your local registry, and push it.

```bash
nerdctl pull busybox:1.36
nerdctl tag busybox:1.36 localhost:5001/busybox:1.36
nerdctl push localhost:5001/busybox:1.36
```

The push should complete without errors. Now verify a pod in the cluster can pull this image from the local registry.

```bash
kubectl run registry-test \
  --image=localhost:5001/busybox:1.36 \
  --restart=Never \
  --command -- sh -c "echo 'registry pull successful'"
kubectl wait --for=condition=Ready pod/registry-test --timeout=30s
kubectl logs registry-test
kubectl delete pod registry-test
```

The logs should contain `registry pull successful`. If the pod fails with ImagePullBackOff, the most common causes are: the registry container is not on the kind network (run the `nerdctl network connect` command again), or the containerdConfigPatches block was not included when the cluster was created (recreate the cluster). You can also check pull errors by running `kubectl describe pod registry-test` and reading the Events section.

## Part 2: The OCI Image Format

Before building images, it is worth understanding what an image actually is, because many of the tradeoffs in base image selection, multi-stage builds, and digest pinning only make sense once you know the internal structure.

An OCI image consists of three types of objects: an image manifest, an image configuration, and a set of layers. The manifest is a JSON document that lists the SHA256 digest of the image configuration and the SHA256 digest of each layer. The image configuration is another JSON document that records the full metadata: environment variables, the entrypoint and command, the working directory, labels, and the complete history of instructions that built the image. Each layer is a compressed tarball of filesystem changes (files added, modified, or deleted) relative to the previous layer.

The critical design principle is content-addressable storage. Every layer and every manifest is identified by the SHA256 hash of its content, not by a human-readable name. This means two images that share a common base layer (for example, both starting with `FROM golang:1.22-alpine`) will share the exact same layer objects on disk, because both layers have identical content and therefore identical hashes. The registry stores each layer once and serves it to any image that references it.

A tag like `localhost:5001/goserver:v1.0.0` is a mutable pointer stored in the registry's database. It points to a manifest by digest. When you push a new image with the same tag, you update the pointer. The old manifest still exists in the registry (until it is garbage collected) but the tag no longer points to it. This is why `latest` tags are unreliable for reproducibility: someone pushing a new `latest` silently changes what every pod that uses that tag will get on its next image pull.

A digest reference like `localhost:5001/goserver@sha256:a3f8...` is immutable. It points to a specific manifest by its content hash. As long as the registry has not deleted the manifest, the digest always refers to the same image contents, regardless of what tag changes happen. This is what digest pinning in pod specs provides: reproducible deployments that cannot be changed by a registry push.

Inspect the layers of an image you already have locally to see this structure concretely.

```bash
nerdctl image inspect busybox:1.36 --format '{{json .RootFS.Layers}}'
```

Each entry in the output is a SHA256 digest identifying one layer in the image. Now inspect the full metadata to see the image config.

```bash
nerdctl image inspect busybox:1.36
```

Look for the `Config` object in the output. It contains `Cmd`, `Entrypoint`, `Env`, `WorkingDir`, and other fields that define how a container started from this image will behave by default.

## Part 3: Multi-Stage Builds

Multi-stage builds solve the problem of build toolchain bloat. To compile a Go binary, you need the Go compiler, the standard library source, and various build tools. The Go compiler alone adds over 200 MB to an image. But once the binary is compiled, the compiler is completely unnecessary at runtime. Multi-stage builds let you compile in one image and then copy only the output artifact into a second, much smaller image.

### The Single-Stage Problem

Start by building the server the naive way: one FROM instruction, all compilation happening in the final image. Create a working directory for this section.

```bash
mkdir -p /tmp/goserver
cd /tmp/goserver
```

Write the Go server source.

```bash
cat > /tmp/goserver/main.go << 'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Hello from Go server v1.0.0!")
	})
	log.Println("Server starting on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF
```

Write the Go module file.

```bash
cat > /tmp/goserver/go.mod << 'EOF'
module goserver

go 1.22
EOF
```

Write the single-stage Dockerfile.

```bash
cat > /tmp/goserver/Dockerfile.single << 'EOF'
FROM golang:1.22-alpine
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .
ENTRYPOINT ["/app/server"]
EOF
```

Build it and check the size.

```bash
nerdctl build -f /tmp/goserver/Dockerfile.single -t goserver:single /tmp/goserver/
nerdctl images goserver:single
```

The image will be around 270 to 310 MB. Almost all of that is the Go compiler, the standard library source, and the Alpine base. The compiled binary itself is around 6 to 7 MB.

### The Multi-Stage Solution

A multi-stage Dockerfile uses multiple `FROM` instructions. Each `FROM` starts a new build stage. Stages can be named with `AS <name>`, and a later stage can copy files from an earlier stage using `COPY --from=<name>`. The final image is built from the last stage, and intermediate stages are discarded entirely after the build.

Write the multi-stage Dockerfile.

```bash
cat > /tmp/goserver/Dockerfile << 'EOF'
# Stage 1: Build the binary
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

# Stage 2: Runtime image
FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
EOF
```

Build the multi-stage version and compare sizes.

```bash
nerdctl build -t localhost:5001/goserver:v1.0.0 /tmp/goserver/
nerdctl images | grep -E "goserver|REPOSITORY"
```

You should see output like this.

```text
REPOSITORY                    TAG       IMAGE ID       CREATED          SIZE
localhost:5001/goserver       v1.0.0    a3f8c2d91b2e   5 seconds ago    6.97 MB
goserver                      single    f4e7a8b2c1d9   2 minutes ago    309 MB
```

The size difference is dramatic: around 6 to 7 MB for the multi-stage image versus 300+ MB for the single-stage. The multi-stage image contains exactly two things: the compiled binary (around 6 MB) and the distroless/static base image (around 1 MB of certificate bundles and timezone data). There is no shell, no package manager, no compiler, and no Alpine system libraries.

### Understanding distroless/static

The `gcr.io/distroless/static:nonroot` base image is maintained by Google and contains only what a statically compiled binary needs to run: the root certificate bundle (for TLS), timezone data, and a minimal Linux filesystem skeleton. It has no shell (`/bin/sh` does not exist), no package manager, and no system utilities. This dramatically reduces the attack surface: there is nothing an attacker can use to pivot if they achieve code execution inside the container.

The `nonroot` tag (as opposed to `latest`) specifies that the image is configured to run as a non-root user (UID 65532). The `USER nonroot:nonroot` instruction in the Dockerfile tells the container runtime to run the process as that user rather than root. If you omit the USER instruction, the container still starts as root by default inside the container, which most security policies prohibit.

The `:nonroot` tag is an explicit version choice that also encodes a security intent. Other tags for this image family include `:debug` (adds busybox shell for debugging) and `:latest` (which you must never use). Always use `:nonroot` or `:debug-nonroot` in a Dockerfile.

If you need to debug a container built on distroless/static because it has no shell, use kubectl's ephemeral container feature.

```bash
kubectl debug -it <pod-name> --image=busybox:1.36 --target=<container-name>
```

This attaches a temporary debug container to the running pod's process namespace without modifying the main container.

### Why CGO_ENABLED=0 Is Required

The `CGO_ENABLED=0` build flag tells the Go compiler to produce a purely static binary with no dynamic library dependencies. Without it, Go's networking stack links against the system C library (glibc or musl depending on the builder base image) to use the operating system's DNS resolution. The resulting binary then requires that C library to be present at runtime.

If you copy a dynamically linked binary into `distroless/static`, the container crashes immediately at startup with an error like `exec format error` or a missing dynamic linker message, because the C library and the dynamic linker path do not exist in the distroless/static filesystem. The only way to use distroless/static is with a truly static binary, which requires `CGO_ENABLED=0 GOOS=linux`.

The `GOOS=linux` flag is technically redundant when building on a Linux host, but it is a useful explicit statement of intent and prevents confusion when someone reads the Dockerfile later or tries to build on macOS.

## Part 4: Layer Caching

Every instruction in a Dockerfile that modifies the filesystem creates a new layer. Nerdctl (and the underlying BuildKit engine) cache each layer keyed by the instruction text and the content of any files referenced by COPY or ADD. If an instruction and all preceding instructions are unchanged, the build engine reuses the cached layer and outputs `CACHED` in the build log. The moment any layer is invalidated (by a changed instruction or changed file content), all subsequent layers are also invalidated and must be rebuilt from scratch.

This has a critical consequence for Dockerfile ordering: put instructions that change frequently near the end, and instructions that change rarely near the beginning. The most common mistake is copying all source files before installing dependencies, so that every source change forces a full dependency reinstall.

### The Poorly-Ordered Dockerfile

Here is the badly ordered version. It copies the entire source directory first, then runs `go mod download`.

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
# WRONG: copies all source before downloading deps
COPY . .
RUN go mod download
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
ENTRYPOINT ["/server"]
```

With this ordering, any change to `main.go` invalidates the `COPY . .` layer. That invalidates the `go mod download` layer that follows it. The full dependency download happens on every build, even if `go.mod` has not changed. For a small module with no external dependencies this is fast, but for a real application with dozens of dependencies it adds significant time to every build.

### The Well-Ordered Dockerfile

The correct ordering separates the dependency manifest (which changes rarely) from the application source (which changes constantly). Copy only `go.mod` (and `go.sum` if it exists) first, run the dependency download, then copy the remaining source.

The Dockerfile at `/tmp/goserver/Dockerfile` already uses this pattern. To see the caching behavior, you need to run two builds in sequence.

Do the first build (or a clean build after removing the cache).

```bash
nerdctl build --no-cache -t localhost:5001/goserver:v1.0.0 /tmp/goserver/
```

The `--no-cache` flag forces every layer to be rebuilt. You will see output like this (slightly abbreviated).

```text
[+] Building 48.2s (12/12) FINISHED
 => [internal] load build definition from Dockerfile                       0.1s
 => [builder 1/5] FROM golang:1.22-alpine                                 12.4s
 => [builder 2/5] WORKDIR /app                                             0.0s
 => [builder 3/5] COPY go.mod .                                            0.0s
 => [builder 4/5] RUN go mod download                                      4.1s
 => [builder 5/5] COPY . .                                                 0.0s
 => [builder 6/6] RUN CGO_ENABLED=0 GOOS=linux go build -o server .       8.3s
 => [stage-1 1/2] FROM gcr.io/distroless/static:nonroot                   2.1s
 => [stage-1 2/2] COPY --from=builder /app/server /server                 0.0s
```

No CACHED labels appear because the cache was cleared.

Now make a small change to main.go only. Change the response message.

```bash
sed -i 's/v1.0.0/v1.0.1/' /tmp/goserver/main.go
```

Run the build again without `--no-cache`.

```bash
nerdctl build -t localhost:5001/goserver:v1.0.1 /tmp/goserver/
```

The output will look like this.

```text
[+] Building 10.1s (12/12) FINISHED
 => [internal] load build definition from Dockerfile                       0.0s
 => CACHED [builder 1/5] FROM golang:1.22-alpine                          0.0s
 => CACHED [builder 2/5] WORKDIR /app                                     0.0s
 => CACHED [builder 3/5] COPY go.mod .                                    0.0s
 => CACHED [builder 4/5] RUN go mod download                              0.0s
 => [builder 5/5] COPY . .                                                0.0s
 => [builder 6/6] RUN CGO_ENABLED=0 GOOS=linux go build -o server .      8.2s
 => CACHED [stage-1 1/2] FROM gcr.io/distroless/static:nonroot            0.0s
 => [stage-1 2/2] COPY --from=builder /app/server /server                0.0s
```

The golang base image, the WORKDIR, the `COPY go.mod`, and the `RUN go mod download` layers are all CACHED. The only work done is copying the updated source and compiling the binary. The total build time dropped from 48 seconds to 10 seconds.

Now add a dependency to go.mod to see a full cache bust. Edit go.mod to add a require block.

```bash
cat > /tmp/goserver/go.mod << 'EOF'
module goserver

go 1.22

require golang.org/x/text v0.14.0
EOF
```

Rebuild.

```bash
nerdctl build -t localhost:5001/goserver:v1.0.2 /tmp/goserver/
```

This time the output will show that `COPY go.mod .` is no longer CACHED (because go.mod changed), and therefore `RUN go mod download` must also run again (downloading the new dependency and taking 15+ seconds). The lesson is clear: the cache break point propagates downward from the first changed layer.

## Part 5: Base Image Selection

Choosing a base image is a real design decision with tradeoffs. The right answer depends on whether you are optimizing for debuggability, security, compatibility, or build simplicity.

**ubuntu:24.04 and debian:12:** These are full Linux distributions with package managers, shells, and extensive system libraries. They are large (100 to 150 MB) but contain everything a traditional application expects. They are the right default for applications that need apt packages, have complex dependency chains, or where image size is not a constraint. They use glibc, which is the C library most dynamically linked applications expect.

**alpine:3.20:** Alpine is a minimal Linux distribution based on musl libc and BusyBox. The base image is around 5 MB. It includes a shell (/bin/sh) and a package manager (apk). The key gotcha is musl libc: binaries compiled against glibc (which includes most pre-built Python extension wheels and many C programs) will fail to run on Alpine because the dynamic linker and symbol names differ. Alpine is excellent as a build stage (where you need a shell and package manager) but requires careful testing when used as the final runtime stage for language runtimes or binaries compiled on glibc systems.

**python:3.13-slim and node:22-slim:** The slim variants are Debian-based with non-essential packages removed. They are typically 50 to 80 MB, smaller than the full variants but much larger than Alpine. They use glibc, so pre-built Python wheels and Node modules work without surprises. The slim variant is the right choice for most language-runtime workloads where you cannot use distroless.

**gcr.io/distroless/static:nonroot:** No shell, no package manager, no C runtime library. Only SSL certificates and timezone data. Requires statically compiled binaries (CGO_ENABLED=0 for Go). Smallest attack surface, hardest to debug (use ephemeral containers). The right choice for compiled Go or Rust binaries that are built with static linking.

**gcr.io/distroless/cc:nonroot:** Like distroless/static but includes glibc. For Go binaries built with CGO_ENABLED=1, or for C/C++ programs that need the C runtime. Larger than static (includes libgcc, libstdc++) but still has no shell or package manager.

**scratch:** The completely empty base image. Not a real image at all but a special Docker keyword meaning "start from nothing." The final image will contain only what your COPY instructions add. This works for truly static binaries but is even more aggressive than distroless/static because it lacks even the certificate bundle and timezone data. Use it if your binary never makes outbound TLS connections and does not care about time zones.

To compare sizes concretely, build the same Go binary with different final stages.

```bash
# Restore main.go to v1.0.0 for clean comparison
cat > /tmp/goserver/main.go << 'EOF'
package main

import (
	"fmt"
	"log"
	"net/http"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintln(w, "Hello from Go server v1.0.0!")
	})
	log.Println("Server starting on :8080")
	log.Fatal(http.ListenAndServe(":8080", nil))
}
EOF

# Build multi-stage with distroless/static (already done above as v1.0.0)
# Build a variant using alpine as the runtime stage
cat > /tmp/goserver/Dockerfile.alpine-runtime << 'EOF'
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod .
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o server .

FROM alpine:3.20
WORKDIR /app
COPY --from=builder /app/server /app/server
ENTRYPOINT ["/app/server"]
EOF

# Restore go.mod to no external deps for the comparison builds
cat > /tmp/goserver/go.mod << 'EOF'
module goserver

go 1.22
EOF

nerdctl build -f /tmp/goserver/Dockerfile.alpine-runtime -t goserver:alpine-runtime /tmp/goserver/
nerdctl images | grep -E "goserver|REPOSITORY"
```

The output will show roughly: `localhost:5001/goserver:v1.0.0` at about 7 MB (distroless/static) versus `goserver:alpine-runtime` at about 12 MB (alpine with a shell and package manager). Alpine is still small but twice the size of distroless/static, and it includes a shell and package manager that are unnecessary at runtime.

## Part 6: Image Tagging Conventions and Digest Pinning

### Tagging Conventions

A container image tag is just a string stored as a pointer in the registry. Tags have no enforced format, but a widely adopted convention exists: semantic versioning with a `v` prefix (`v1.0.0`, `v1.2.3-beta.1`). Using semantic version tags communicates intent (major versions signal breaking changes, minor versions add features, patch versions fix bugs) and allows infrastructure tools to apply update policies automatically.

The `:latest` tag is the default when no tag is specified in a FROM instruction or an image reference. It is updated by convention to point to the most recent stable build, but there is nothing in the registry protocol that enforces this or prevents someone from pushing a completely different image as `:latest`. This makes `:latest` dangerous for production use: it changes silently, makes rollbacks unclear (you cannot easily find the previous `:latest`), and prevents reproducible builds. Never use `:latest` in Dockerfiles or Kubernetes manifests.

The `nerdctl tag` command creates an additional tag pointing to the same image manifest. It does not copy the image content; it just adds a pointer in the local image store.

```bash
nerdctl tag localhost:5001/goserver:v1.0.0 localhost:5001/goserver:stable
nerdctl images localhost:5001/goserver
```

Both tags will show the same IMAGE ID, confirming they point to the same content.

### Retrieving an Image Digest

After pushing an image to a registry, you can retrieve its manifest digest. This is the SHA256 hash of the image manifest JSON, and it is the immutable identifier for that specific image build.

Push the goserver image to the local registry.

```bash
nerdctl push localhost:5001/goserver:v1.0.0
```

Retrieve the digest of the pushed image.

```bash
nerdctl images --digests localhost:5001/goserver
```

The output includes a DIGEST column showing the manifest digest, starting with `sha256:`. Copy the full digest for use in the next step.

You can also retrieve the digest after a push by inspecting the image.

```bash
nerdctl image inspect localhost:5001/goserver:v1.0.0 \
  --format '{{index .RepoDigests 0}}'
```

This outputs the full image reference with digest, for example `localhost:5001/goserver@sha256:a3f8c2d91b2e...`.

### Pinning a Pod to a Specific Digest

Create the tutorial namespace and deploy a pod that references the image by digest instead of tag.

```bash
kubectl create namespace tutorial-container-images
```

Get your actual digest from the local registry.

```bash
DIGEST=$(nerdctl image inspect localhost:5001/goserver:v1.0.0 \
  --format '{{index .RepoDigests 0}}' | cut -d@ -f2)
echo "Digest: $DIGEST"
```

Deploy a pod using the digest-pinned reference.

```bash
kubectl apply -n tutorial-container-images -f - << EOF
apiVersion: v1
kind: Pod
metadata:
  name: goserver-pinned
  namespace: tutorial-container-images
spec:
  containers:
  - name: server
    image: localhost:5001/goserver@${DIGEST}
    ports:
    - containerPort: 8080
EOF
```

Wait for the pod to be ready and verify it is running the correct image.

```bash
kubectl wait -n tutorial-container-images \
  --for=condition=Ready pod/goserver-pinned --timeout=60s
kubectl get pod -n tutorial-container-images goserver-pinned \
  -o jsonpath='{.spec.containers[0].image}'
```

The output will show the full digest-pinned image reference. This pod is now immune to any future push that changes what `localhost:5001/goserver:v1.0.0` points to. Even if someone overwrites the `v1.0.0` tag, this pod will continue to pull the same manifest on every restart.

### imagePullPolicy and the Local Registry

The `imagePullPolicy` field on a container spec controls when the kubelet pulls an image before starting a container.

`IfNotPresent` (the default when the tag is not `latest`): The kubelet checks if the image is already in the containerd image store on the node. If it is, the stored image is used without contacting the registry. If it is not, the kubelet pulls from the registry. This is the most efficient setting for production use.

`Always`: The kubelet contacts the registry on every pod start to check whether the remote manifest has changed. If the remote and local digests match, the local image is reused; if not, the image is pulled. This is appropriate when you are using a mutable tag (like `latest` or `stable`) and want to guarantee you always run the newest version.

`Never`: The kubelet never contacts the registry. If the image is not present in the local store, the pod fails with `ErrImageNeverPull`. Use this only in environments where you control image distribution through other means (like `kind load docker-image`).

When using the local registry with digest pinning, `IfNotPresent` is the correct choice. The pod will pull the image once on first scheduling, cache it on the node, and reuse it for all subsequent restarts. If you push a new image with the same tag, pods using digest pinning will not see the change until you update the pod spec with the new digest, which is exactly the behavior you want for reproducible deployments.

## Part 7: Registry Operations Reference

The local registry exposes the standard OCI Distribution Specification API. You can query it directly with curl to list images and inspect manifests.

List all repositories in the registry.

```bash
curl -s http://localhost:5001/v2/_catalog
```

List all tags for the goserver repository.

```bash
curl -s http://localhost:5001/v2/goserver/tags/list
```

Retrieve the manifest for a specific tag (the response is the JSON manifest document).

```bash
curl -s \
  -H "Accept: application/vnd.oci.image.manifest.v1+json" \
  http://localhost:5001/v2/goserver/manifests/v1.0.0
```

The manifest JSON shows the config digest and the list of layer digests. Each layer digest is the SHA256 of the compressed tarball for that layer. Two images that share a common layer (for example, both built from the same golang:1.22-alpine base) will show the same layer digest in their manifests, and the registry stores that layer only once.

## Cleanup

Delete the tutorial namespace and all resources in it.

```bash
kubectl delete namespace tutorial-container-images
```

The images and registry you created during the tutorial are needed for the homework exercises. Do not delete the registry container or the images. After you finish all homework exercises, you can clean up with the following.

```bash
# After completing all exercises:
nerdctl rm -f kind-registry
kind delete cluster
nerdctl rmi localhost:5001/goserver:v1.0.0 localhost:5001/busybox:1.36 goserver:single goserver:alpine-runtime
```

## Reference Commands

### nerdctl Image Operations

| Task | Command |
|------|---------|
| Build an image | `nerdctl build -t name:tag .` |
| Build with no cache | `nerdctl build --no-cache -t name:tag .` |
| Build from specific Dockerfile | `nerdctl build -f Dockerfile.name -t name:tag .` |
| List images with digests | `nerdctl images --digests` |
| Tag an image | `nerdctl tag source:tag dest:tag` |
| Push to registry | `nerdctl push localhost:5001/name:tag` |
| Pull from registry | `nerdctl pull localhost:5001/name:tag` |
| Inspect image | `nerdctl image inspect name:tag` |
| Show image layers | `nerdctl image inspect name:tag --format '{{json .RootFS.Layers}}'` |
| Get image digest | `nerdctl image inspect name:tag --format '{{index .RepoDigests 0}}'` |

### Registry API Operations

| Task | Command |
|------|---------|
| Health check | `curl -s http://localhost:5001/v2/` |
| List repositories | `curl -s http://localhost:5001/v2/_catalog` |
| List tags | `curl -s http://localhost:5001/v2/<repo>/tags/list` |
| Get manifest | `curl -s http://localhost:5001/v2/<repo>/manifests/<tag>` |

### Kind Registry Operations

| Task | Command |
|------|---------|
| Create cluster with registry config | `KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster --config config.yaml` |
| Connect registry to kind network | `nerdctl network connect kind kind-registry` |
| Load image directly (no registry) | `nerdctl save name:tag | kind load docker-archive` |
| Check what nodes have cached | `docker exec kind-control-plane crictl images` |

### Pod and Deployment Registry Verification

| Task | Command |
|------|---------|
| Get image a pod is running | `kubectl get pod <name> -o jsonpath='{.spec.containers[0].image}'` |
| Check pull errors | `kubectl describe pod <name>` (read Events section) |
| Force pull with Always policy | `kubectl set image deployment/<name> <container>=<image> --record` |
| Check rollout status | `kubectl rollout status deployment/<name>` |
