# Container Images Tutorial: Defining, Building, and Inspecting Images

Container images are the fundamental unit of deployment in Kubernetes. Every pod runs containers, and every container starts from an image that packages the application binary, its dependencies, and the runtime configuration that tells the container runtime how to start the process. Understanding how to build, inspect, and correctly configure images is not an optional skill: it sits beneath every other topic in the CKA and CKAD syllabi, and subtle Dockerfile mistakes produce the kind of hard-to-diagnose pod failures that cost time on the exam.

This tutorial builds a minimal Python HTTP server through a sequence of Dockerfile iterations, introducing each instruction family at the point where it becomes necessary and explaining the tradeoffs involved in each choice. By the end you will have a production-style image with labels, environment configuration, a non-root user, and exec-form ENTRYPOINT. You will then load that image into a kind cluster and deploy it as a pod, observing how the Kubernetes pod spec maps to the Dockerfile's ENTRYPOINT and CMD. All builds use nerdctl, the containerd-native CLI used in this repository's dev container environment.

## Prerequisites and Setup

This tutorial assumes a single-node kind cluster created with nerdctl as described in [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster). The nerdctl command must be available in your shell. Verify both before starting:

```bash
kubectl get nodes
# Expected: one node in Ready state

nerdctl version
# Expected: version output showing Client and Server sections
```

No additional Kubernetes components are required. All image builds in this tutorial are local operations; the cluster is only needed for the section on loading images into kind.

## Setup: Working Directory and Tutorial Namespace

Create a working directory for tutorial files and a Kubernetes namespace for the pod deployment section:

```bash
mkdir -p ~/container-images-tutorial
cd ~/container-images-tutorial

kubectl create namespace tutorial-container-images
```

All Dockerfiles and application code in this tutorial live under `~/container-images-tutorial/`. The Kubernetes namespace `tutorial-container-images` is used only in the section on loading images into kind; Levels 1 through 3 of the tutorial work entirely with local nerdctl commands.

## The Application

The tutorial builds images for a minimal Python HTTP server. Create the application file now:

```bash
cat > ~/container-images-tutorial/app.py << 'PYEOF'
#!/usr/bin/env python3
import http.server
import os
import socketserver

PORT = int(os.environ.get("PORT", "8080"))
APP_NAME = os.environ.get("APP_NAME", "greeting-server")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        uid = os.getuid()
        pid = os.getpid()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.end_headers()
        body = f"Hello from {APP_NAME} | uid={uid} | pid={pid}\n"
        self.wfile.write(body.encode())

    def log_message(self, fmt, *args):
        pass


with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
    print(f"[{APP_NAME}] listening on :{PORT}", flush=True)
    httpd.serve_forever()
PYEOF
```

The server reads APP_NAME and PORT from environment variables, then serves a single GET endpoint that reports the application name, the running user's UID, and the process ID. The UID lets you verify non-root identity later. The PID lets you observe the difference between exec-form and shell-form ENTRYPOINT, because PID 1 is the Python interpreter under exec form and is /bin/sh under shell form.

## The Build Context

Before writing any Dockerfile, it is important to understand what a build context is. When you run `nerdctl build`, the CLI sends a directory tree to the containerd build daemon. That tree is called the build context, and it is the only filesystem the daemon can see during the build. COPY and ADD instructions in your Dockerfile resolve source paths relative to the build context root, not relative to any path on your host outside that directory. If you run `nerdctl build ~/container-images-tutorial/`, the context is that directory and all its contents.

Context size matters even when the files being sent are never COPYd into the image. A directory with a large node_modules folder or a .git history makes every build slower because the entire context is transferred before the first layer is processed. The solution is a `.dockerignore` file at the context root. Its syntax is similar to `.gitignore`: one pattern per line, with `*` for wildcards and `!` for negation. Common entries include `node_modules`, `.git`, `test/`, and any file containing secrets. The COPY instruction's path resolution is unaffected by patterns that appear in `.dockerignore`; if a file is excluded, COPY will fail with "not found in build context" rather than silently copying nothing.

## Writing a Dockerfile: The Core Instructions

### FROM: Choosing a Base Image

Every Dockerfile starts with a FROM instruction that selects the base image. That image provides the filesystem layers your subsequent instructions build on top of. There is no default: FROM is required (except in special scratch-based images).

```dockerfile
FROM python:3.13-slim
```

**Field semantics for FROM:**

| Aspect | Detail |
|---|---|
| Value | `<image>`, `<image>:<tag>`, `<image>@<digest>`, or `scratch` |
| Default tag | If omitted, the daemon resolves `:latest`; never omit the tag in production Dockerfiles |
| Digest pinning | `FROM python:3.13-slim@sha256:abc123...` pins to an exact immutable layer; more reproducible but harder to update |
| `scratch` | An empty base with no OS files; used for statically compiled binaries |
| Failure mode | A typo in the image name produces `pull access denied` or `manifest unknown` at build time; an omitted tag silently uses `:latest`, which changes meaning whenever the upstream image is updated |

This tutorial uses `python:3.13-slim` throughout because it includes the Python interpreter and a minimal Debian base with common system libraries, keeping the image small without requiring a compiled Python installation.

### RUN: Executing Commands at Build Time

RUN executes a command in a new layer on top of the current image. The result of that execution is committed as a layer that subsequent instructions build on. RUN is used to install packages, create directories, compile code, set permissions, and any other filesystem mutation you want baked into the image.

RUN has two forms, and the distinction matters:

```dockerfile
# Shell form: wraps the command in /bin/sh -c
RUN apt-get update && apt-get install -y --no-install-recommends curl

# Exec form: invokes the executable directly, without a shell
RUN ["apt-get", "install", "-y", "--no-install-recommends", "curl"]
```

Shell form is convenient for multi-command chaining with `&&` and shell variable expansion. Exec form is necessary when the base image has no shell (such as scratch-based images) or when you want precise control over the argument list.

One critical performance pattern: each RUN instruction creates a new layer. More layers means a larger final image when those layers cannot be merged, and more cache invalidation points. The standard pattern for apt-based installs is to combine update, install, and cleanup in a single RUN:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
```

Running `apt-get update` in a separate RUN from `apt-get install` is a common mistake: if the install layer is cached, the update never runs again, and you may install stale packages. The cleanup of `/var/lib/apt/lists/*` is important because those index files are large and are only needed at install time, not at runtime.

### WORKDIR: Setting the Working Directory

WORKDIR sets the working directory for subsequent RUN, COPY, ADD, CMD, and ENTRYPOINT instructions. If the path does not exist, WORKDIR creates it (including any intermediate directories). You can call WORKDIR multiple times in a single Dockerfile; each call changes the current working directory for everything that follows.

```dockerfile
WORKDIR /app
```

**Field semantics for WORKDIR:**

| Aspect | Detail |
|---|---|
| Value | An absolute path (preferred) or a path relative to the previous WORKDIR |
| Default | The base image's working directory, usually `/` |
| Created automatically | Yes; WORKDIR does not require a preceding `RUN mkdir` |
| Failure mode | Using a relative WORKDIR without a preceding absolute WORKDIR produces a path relative to `/`, which is rarely what you want; a COPY to a WORKDIR-relative path before WORKDIR is set places files in the wrong location |

WORKDIR also sets the default directory for processes running inside the container. If you exec into a running container without specifying a working directory, you land in the image's WORKDIR.

### COPY: Adding Files from the Build Context

COPY copies files or directories from the build context into the image filesystem. The source path is relative to the build context root; the destination path is relative to WORKDIR (if relative) or absolute.

```dockerfile
COPY app.py /app/app.py
```

The similar ADD instruction has two behaviors that COPY does not: it can fetch files from URLs, and it automatically extracts tar archives. The official Docker guidance is to use COPY for all local file copies and only use ADD when you specifically need the tar extraction behavior. COPY's semantics are simpler and its behavior is always predictable.

```dockerfile
# COPY: straightforward, preferred for local files
COPY app.py /app/app.py

# ADD: use only when you specifically need tar extraction or URL fetch
ADD https://example.com/file.tar.gz /tmp/  # not recommended in practice (use curl in RUN instead)
```

**Field semantics for COPY:**

| Aspect | Detail |
|---|---|
| Source | Path relative to the build context root; cannot use `..` to escape the context |
| Destination | Absolute path, or relative to WORKDIR |
| Wildcards | Supported: `COPY src/*.py /app/` |
| `--chown` flag | `COPY --chown=user:group src dest` sets ownership at copy time (more on this in the USER section) |
| Failure mode | If the source path does not exist in the build context (including if it is excluded by .dockerignore), the build fails with "not found in build context or excluded by .dockerignore" |

### LABEL: Image Metadata

LABEL attaches key-value metadata to the image. This metadata is visible in nerdctl image inspect output but has no effect on the running container. The OCI image specification defines a standard set of well-known label keys under the `org.opencontainers.image.*` prefix.

```dockerfile
LABEL org.opencontainers.image.title="greeting-server"
LABEL org.opencontainers.image.version="1.0"
LABEL org.opencontainers.image.description="A minimal Python HTTP greeting server"
```

Labels can also be combined in a single instruction as a map:

```dockerfile
LABEL org.opencontainers.image.title="greeting-server" \
      org.opencontainers.image.version="1.0" \
      org.opencontainers.image.description="A minimal Python HTTP greeting server"
```

**Field semantics for LABEL:**

| Aspect | Detail |
|---|---|
| Value | Any string key-value pair |
| Default | None; images have no labels unless you add them |
| Effect at runtime | None; labels are metadata only |
| Failure mode | None at runtime; incorrect label values are purely a documentation error |

### ENV: Runtime Environment Variables

ENV sets environment variables that persist from build time into the running container. Every process started in the container inherits these variables. ENV variables are also available to subsequent RUN, COPY, and ENTRYPOINT/CMD instructions in the Dockerfile itself.

```dockerfile
ENV APP_NAME="greeting-server"
ENV PORT="8080"
```

**Field semantics for ENV:**

| Aspect | Detail |
|---|---|
| Scope | Available both during subsequent build steps and at container runtime |
| Default | None; no environment variables are set unless explicitly added via ENV or inherited from the base image |
| Override at runtime | `nerdctl run -e PORT=9090 image` overrides the ENV value for that container instance; the Kubernetes `env:` field does the same |
| Failure mode | A process that expects an environment variable to be set will fail silently (reading an empty string) if the ENV instruction was omitted; this is the most common cause of "works on my machine" image bugs |

### ARG: Build-Time Variables

ARG declares a variable that can be passed to the build via `--build-arg` at nerdctl build time. Unlike ENV, ARG values do not persist into the running container. Once the build is complete, the ARG is gone.

```dockerfile
ARG BUILD_DATE="unknown"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
```

Built with a date:

```bash
nerdctl build --build-arg BUILD_DATE="2026-07-04" -t tutorial-app:v1 .
```

**Field semantics for ARG:**

| Aspect | Detail |
|---|---|
| Scope | Available only during the build, from the ARG instruction forward; not in the running container |
| Default | Optional: `ARG NAME=default_value`; if no default and not passed at build time, the value is empty |
| Predefined ARGs | `TARGETPLATFORM`, `BUILDPLATFORM`, and related cross-build variables are predefined; no ARG declaration needed |
| Before FROM | ARG can appear before FROM to parameterize the base image tag: `ARG BASE=python:3.13-slim\nFROM $BASE` |
| Failure mode | Using ARG for a value you expect to be available at runtime produces a container where that variable is empty; use ENV to persist a value to runtime, optionally seeded from an ARG: `ARG VERSION && ENV VERSION=$VERSION` |

This is one of the most common Dockerfile mistakes in practice: a developer sets `ARG DATABASE_URL=localhost:5432` and then expects the running container to have `DATABASE_URL` in its environment. It does not. If you want a value at runtime, use ENV (with a static default) or combine ARG with ENV to allow build-time customization of a runtime default.

### EXPOSE: Documenting Ports

EXPOSE declares which network ports the containerized process listens on. It is documentation only. It does not publish the port, does not open a firewall rule, and does not affect pod networking. It appears in nerdctl image inspect output under `ExposedPorts` and is used by some tooling to infer default port mappings, but Kubernetes ignores it entirely when scheduling pods.

```dockerfile
EXPOSE 8080
```

In a Kubernetes pod spec, the equivalent is `containerPort:` in the container spec. Like EXPOSE, `containerPort:` is documentation only. Kubernetes does not use it to configure networking; it is there for human readers and monitoring tools.

**Field semantics for EXPOSE:**

| Aspect | Detail |
|---|---|
| Value | A port number, optionally with protocol: `8080/tcp` or `8080/udp`; default protocol is `tcp` |
| Default | None; processes that listen on ports do not need EXPOSE to function |
| Effect | Visible in inspect output; consumed by some Docker Compose tooling for automatic mapping |
| Failure mode | Omitting EXPOSE has no functional impact; adding it for a port the process does not actually listen on is a documentation error with no runtime consequence |

## The First Complete Dockerfile

With all the metadata and configuration instructions covered, here is the first complete Dockerfile for the tutorial application:

```bash
cat > ~/container-images-tutorial/Dockerfile.v1 << 'EOF'
FROM python:3.13-slim

LABEL org.opencontainers.image.title="greeting-server"
LABEL org.opencontainers.image.version="1.0"
LABEL org.opencontainers.image.description="A minimal Python HTTP greeting server"

WORKDIR /app
COPY app.py /app/app.py

ENV APP_NAME="greeting-server"
ENV PORT="8080"

EXPOSE 8080

CMD ["python", "/app/app.py"]
EOF
```

Build it and verify:

```bash
cd ~/container-images-tutorial
nerdctl build -f Dockerfile.v1 -t tutorial-app:v1 .

nerdctl images tutorial-app
```

The `nerdctl images` output shows columns for REPOSITORY, TAG, IMAGE ID, CREATED, and SIZE. The IMAGE ID is a truncated content-addressed hash of the image manifest; it changes whenever the image content changes.

Inspect the image configuration:

```bash
nerdctl image inspect tutorial-app:v1 --format '{{json .Config.Env}}'
# Expected: ["APP_NAME=greeting-server","PATH=/usr/local/bin:...","PORT=8080"]

nerdctl image inspect tutorial-app:v1 --format '{{json .Config.Labels}}'
# Expected: {"org.opencontainers.image.description":"A minimal Python HTTP greeting server","org.opencontainers.image.title":"greeting-server","org.opencontainers.image.version":"1.0"}
```

Run the container to verify the ENV variables are visible at runtime:

```bash
nerdctl run --rm tutorial-app:v1 env | grep -E "APP_NAME|PORT"
# Expected:
# APP_NAME=greeting-server
# PORT=8080
```

## ENTRYPOINT and CMD: Controlling How the Container Starts

The CMD instruction in Dockerfile.v1 provides the default command the container runs. ENTRYPOINT provides a fixed executable that CMD can supply arguments to. Understanding the interaction between the two is one of the most important concepts in this assignment, and it is also one of the most common sources of confusion when working with Kubernetes.

### Exec Form Versus Shell Form

Both ENTRYPOINT and CMD support two syntax forms. **Exec form** uses a JSON array and invokes the specified executable directly via execve(), making the process PID 1 in the container:

```dockerfile
# Exec form (preferred): executable is PID 1
ENTRYPOINT ["python", "/app/app.py"]
CMD ["--debug"]
```

**Shell form** uses a plain string and wraps the command in `/bin/sh -c "..."`, making /bin/sh the PID 1 process and the specified command a child:

```dockerfile
# Shell form (not preferred): /bin/sh is PID 1, python is a child
ENTRYPOINT python /app/app.py
CMD --debug
```

The PID 1 distinction matters for signal handling. When Kubernetes terminates a pod, it sends SIGTERM to PID 1. If PID 1 is /bin/sh and shell form is used, /bin/sh may or may not forward SIGTERM to child processes, depending on the shell implementation. The common result is that your application process is killed with SIGKILL after the termination grace period rather than receiving the SIGTERM it needs for clean shutdown. Exec form avoids this entirely: your application is PID 1 and receives SIGTERM directly.

You can observe the PID 1 difference by running the container and reading the kernel's process information:

```bash
# With exec form (tutorial-app:v1 uses CMD exec form, not ENTRYPOINT yet)
nerdctl run --rm -d --name pid-test tutorial-app:v1
nerdctl exec pid-test cat /proc/1/cmdline | tr '\0' ' '
# Expected: python /app/app.py (exec form CMD; python is PID 1)
nerdctl stop pid-test
```

### The Four ENTRYPOINT and CMD Combinations

The interaction between ENTRYPOINT and CMD follows specific rules depending on which is set:

| ENTRYPOINT | CMD | What the container runs |
|---|---|---|
| Not set | Not set | Inherits whatever the base image defined; error if the base image also has none |
| Not set | `["echo", "hello"]` | `echo hello` (CMD acts as both executable and arguments) |
| `["echo"]` | Not set | `echo` with no arguments (empty output line) |
| `["echo"]` | `["hello world"]` | `echo "hello world"` (ENTRYPOINT is the executable, CMD provides default arguments) |

When you pass additional arguments after the image name to `nerdctl run`, those arguments replace CMD entirely. ENTRYPOINT remains fixed:

```bash
# Override CMD at runtime: pass extra args after the image name
nerdctl run --rm busybox:1.36 echo "override"
# (no ENTRYPOINT set in busybox by default, so "echo override" becomes the command)

# Override ENTRYPOINT at runtime
nerdctl run --rm --entrypoint /bin/sh busybox:1.36 -c "echo custom entrypoint"
# Expected: custom entrypoint
```

### Adding ENTRYPOINT to the Tutorial Image

Update the Dockerfile to use exec-form ENTRYPOINT:

```bash
cat > ~/container-images-tutorial/Dockerfile.v2 << 'EOF'
FROM python:3.13-slim

LABEL org.opencontainers.image.title="greeting-server"
LABEL org.opencontainers.image.version="1.1"

WORKDIR /app
COPY app.py /app/app.py

ENV APP_NAME="greeting-server"
ENV PORT="8080"

EXPOSE 8080

ENTRYPOINT ["python", "/app/app.py"]
EOF

nerdctl build -f Dockerfile.v2 -t tutorial-app:v2 .
```

With only ENTRYPOINT set and no CMD, the container runs `python /app/app.py` with no arguments. If you want to pass arguments, you add them after the image name on the nerdctl run command line; they become the CMD for that run.

## ARG in Context: Build-Time Customization

Add an ARG to pass the build date into a label:

```bash
cat > ~/container-images-tutorial/Dockerfile.v3 << 'EOF'
FROM python:3.13-slim

ARG BUILD_DATE="unknown"

LABEL org.opencontainers.image.title="greeting-server"
LABEL org.opencontainers.image.version="1.2"
LABEL org.opencontainers.image.created="${BUILD_DATE}"

WORKDIR /app
COPY app.py /app/app.py

ENV APP_NAME="greeting-server"
ENV PORT="8080"

EXPOSE 8080

ENTRYPOINT ["python", "/app/app.py"]
EOF

nerdctl build -f Dockerfile.v3 \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t tutorial-app:v3 .

nerdctl image inspect tutorial-app:v3 --format '{{json .Config.Labels}}'
# Expected: includes "org.opencontainers.image.created":"2026-..."
```

Now verify that BUILD_DATE is NOT present in the container's environment (ARG does not persist to runtime):

```bash
nerdctl run --rm tutorial-app:v3 env | grep BUILD_DATE
# Expected: (no output; BUILD_DATE is a build-time ARG and does not persist)
```

Contrast this with APP_NAME, which is an ENV and is present at runtime:

```bash
nerdctl run --rm tutorial-app:v3 env | grep APP_NAME
# Expected: APP_NAME=greeting-server
```

## Building with nerdctl: Key Flags

```bash
# Basic build: tag the image and use the current directory as context
nerdctl build -t image:tag .

# Use a non-default Dockerfile name
nerdctl build -f Dockerfile.production -t image:tag .

# Pass a build argument
nerdctl build --build-arg KEY=VALUE -t image:tag .

# Disable the build cache (forces every layer to rebuild)
nerdctl build --no-cache -t image:tag .

# Tag an existing image with a new name
nerdctl tag tutorial-app:v3 tutorial-app:latest-build

# List images (optionally filter by name)
nerdctl images tutorial-app

# Remove an image
nerdctl rmi tutorial-app:v1

# Remove an image even if containers reference it
nerdctl rmi --force tutorial-app:v1
```

## Inspecting Images: nerdctl image inspect and nerdctl history

`nerdctl image inspect` returns the full image configuration as JSON. The most useful fields are Config.Env, Config.Labels, Config.Cmd, Config.Entrypoint, Config.WorkingDir, Config.User, and Config.ExposedPorts.

```bash
# Inspect the full image config in JSON
nerdctl image inspect tutorial-app:v3

# Extract specific fields with Go templates
nerdctl image inspect tutorial-app:v3 --format '{{json .Config.Entrypoint}}'
# Expected: ["python","/app/app.py"]

nerdctl image inspect tutorial-app:v3 --format '{{.Config.WorkingDir}}'
# Expected: /app

nerdctl image inspect tutorial-app:v3 --format '{{json .Config.ExposedPorts}}'
# Expected: {"8080/tcp":{}}
```

`nerdctl history` shows the layer history of an image: what command created each layer and how much storage it contributes.

```bash
nerdctl history tutorial-app:v3
```

The output lists rows from newest to oldest. Each row shows the IMAGE digest (or `<missing>` for base layers from the registry), the creation timestamp, the Dockerfile instruction that created the layer, and the SIZE of that layer. Instructions like LABEL, ENV, EXPOSE, WORKDIR, and ENTRYPOINT typically show a SIZE of 0B because they add no file content. RUN, COPY, and ADD instructions that modify the filesystem show a non-zero SIZE corresponding to the bytes they added.

Combining multiple RUN commands into one reduces the number of layers that can accumulate temporary files. For example, `RUN apt-get update && apt-get install X && rm -rf /var/lib/apt/lists/*` produces one layer with a net size equal to the installed package minus the cleaned cache. Running the same steps as three separate RUN instructions produces three layers, and the cleanup in the third layer cannot reclaim space from the install layer (because layers are immutable).

## Non-root USER: Baking Identity into the Image

By default, processes in a container run as root (UID 0). This is a significant security concern: a process that escapes the container's filesystem isolation with root privileges can cause much more damage than one running as an unprivileged user. The USER instruction sets the user (and optionally group) that all subsequent RUN, CMD, and ENTRYPOINT commands run as. It also sets the default user for any container started from the image.

### Creating the User Before Switching

USER cannot switch to a user that does not exist in the image's /etc/passwd. The user must be created first with a RUN instruction. On Debian/Ubuntu-based images, use useradd:

```bash
RUN groupadd -g 1001 appgrp && useradd -r -u 1001 -g appgrp appuser
```

On Alpine-based images (which use busybox's adduser), the equivalent is:

```bash
RUN addgroup -g 1001 -S appgrp && adduser -u 1001 -S -G appgrp appuser
```

The `-r` flag on useradd (or `-S` on adduser) creates a system account with no home directory and no password, which is appropriate for a service account. Specifying the UID explicitly (1001 here) makes the UID predictable across image rebuilds, which matters when mapping to host-side file permissions or pod securityContext.

### File Ownership with COPY --chown

When COPY places a file into the image, the file is owned by root (UID 0) by default. If your application user needs to read or write those files, you must set ownership at COPY time using the `--chown` flag:

```bash
COPY --chown=appuser:appgrp app.py /app/app.py
```

Setting ownership with `RUN chown -R appuser /app` in a separate layer also works, but it doubles the storage used by the /app directory because the original COPY layer (owned by root) still exists in the image history. The `--chown` flag avoids this by setting ownership in the same layer as the copy operation.

### The Complete Production Dockerfile

```bash
cat > ~/container-images-tutorial/Dockerfile.v4 << 'EOF'
FROM python:3.13-slim

ARG BUILD_DATE="unknown"

LABEL org.opencontainers.image.title="greeting-server"
LABEL org.opencontainers.image.version="1.3"
LABEL org.opencontainers.image.description="A minimal Python HTTP greeting server"
LABEL org.opencontainers.image.created="${BUILD_DATE}"

RUN groupadd -g 1001 appgrp \
    && useradd -r -u 1001 -g appgrp appuser

WORKDIR /app
COPY --chown=appuser:appgrp app.py /app/app.py

USER appuser

ENV APP_NAME="greeting-server"
ENV PORT="8080"

EXPOSE 8080

ENTRYPOINT ["python", "/app/app.py"]
EOF

nerdctl build -f Dockerfile.v4 \
  --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -t tutorial-app:v4 .
```

Verify the running user:

```bash
nerdctl run --rm tutorial-app:v4 whoami
# Expected: appuser

nerdctl run --rm tutorial-app:v4 id -u
# Expected: 1001

nerdctl run --rm tutorial-app:v4 id -g
# Expected: 1001
```

### Dockerfile USER Versus Pod securityContext.runAsUser

The USER directive is baked into the image and is the default identity when nothing in the pod spec says otherwise. The pod spec's `securityContext.runAsUser` field is a runtime override that takes precedence over the image's USER directive. If a pod spec sets `runAsUser: 2000`, the container process runs as UID 2000 regardless of what USER is in the Dockerfile. If neither is set, the container runs as root (UID 0). The Dockerfile USER is the right place to set the default for an application image; the pod securityContext is the right place for an operator to enforce cluster-level identity policy on top of whatever the image specifies.

## Loading Images into kind

Images built with nerdctl live in the containerd image store on your local host. A kind cluster runs its Kubernetes node containers (which have their own embedded containerd instance), and those node containers do not automatically see images from the host's containerd store. To use a locally built image in a kind pod without pushing to a registry, you must:

1. Save the image to a tar archive with nerdctl
2. Load the archive into the kind cluster's node containers with kind load image-archive
3. Set `imagePullPolicy: Never` in the pod spec to prevent Kubernetes from attempting a network pull

```bash
# Step 1: save the image to a tar file
nerdctl save tutorial-app:v4 -o tutorial-app-v4.tar

# Step 2: load the archive into the kind cluster
kind load image-archive tutorial-app-v4.tar

# Verify the image is now visible to kind (optional)
# kind get nodes outputs node names; you can docker/nerdctl exec into one to check
```

The `kind load image-archive` command imports the tar into every node in the cluster. For a single-node cluster there is only one node, so the image becomes available immediately.

### Deploying the Image as a Pod

Now create a pod spec that uses the locally loaded image:

```bash
kubectl apply -f - << 'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: greeting-server
  namespace: tutorial-container-images
spec:
  containers:
  - name: greeting-server
    image: tutorial-app:v4
    imagePullPolicy: Never
    ports:
    - containerPort: 8080
EOF
```

**Field semantics for imagePullPolicy:**

| Value | Behavior |
|---|---|
| `Always` | Always attempt a network pull before starting the container, even if the image is already present on the node |
| `IfNotPresent` | Pull from the network only if the image is not already present on the node |
| `Never` | Never attempt a network pull; fail with ErrImageNeverPull if the image is not already on the node |
| Default when tag is specified (not `:latest`) | `IfNotPresent` |
| Default when tag is `:latest` or omitted | `Always` |

For locally loaded images, `Never` is the correct value. If you use `IfNotPresent`, the behavior depends on whether the image was already cached; for locally built images that have never been pushed to a registry, `IfNotPresent` will attempt a pull if the image is not found in the node's cache, which fails. `Never` makes the intent explicit and fails immediately with a clear error if the image was not loaded.

**Failure mode when imagePullPolicy is misconfigured:**

- `Always` with a locally built image that has not been pushed to a registry: the pod enters `ImagePullBackOff` with events showing "failed to pull image: ... not found."
- `Never` with an image that was not loaded into kind: the pod enters a non-Running state with events showing "ErrImageNeverPull."
- `IfNotPresent` with a locally built image not in any registry: the pod starts correctly if the image was loaded, but fails with `ImagePullBackOff` if the image is present in the host containerd but not loaded into kind nodes.

Verify the pod is running:

```bash
kubectl get pod greeting-server -n tutorial-container-images
# Expected: STATUS=Running

kubectl logs greeting-server -n tutorial-container-images
# Expected: [greeting-server] listening on :8080
```

Test the HTTP endpoint by running a curl command from inside the cluster:

```bash
kubectl exec -n tutorial-container-images greeting-server -- sh -c 'wget -qO- http://localhost:8080'
# Expected: Hello from greeting-server | uid=1001 | pid=1
```

The uid=1001 confirms the process is running as appuser. The pid=1 confirms exec-form ENTRYPOINT is being used (Python is PID 1, not /bin/sh).

## Kubernetes Mapping: command and args

When you deploy an image as a Kubernetes pod, two fields in the container spec affect what command runs:

- `command:` overrides the image's ENTRYPOINT
- `args:` overrides the image's CMD

This naming is the inverse of what many people expect based on the Docker CLI flag names (`--entrypoint` and the positional arguments). The Kubernetes documentation is explicit about this, and it is a common source of confusion.

A concrete mapping table:

| Image ENTRYPOINT | Image CMD | Pod spec command | Pod spec args | What runs |
|---|---|---|---|---|
| `["python", "/app/app.py"]` | (none) | (none) | (none) | `python /app/app.py` |
| `["python", "/app/app.py"]` | (none) | (none) | `["--debug"]` | `python /app/app.py --debug` |
| `["python", "/app/app.py"]` | (none) | `["/bin/sh"]` | `["-c", "echo hi"]` | `/bin/sh -c "echo hi"` (ENTRYPOINT replaced) |
| (none) | `["echo", "hello"]` | (none) | `["world"]` | `echo world` (CMD replaced) |

Setting only `command:` replaces ENTRYPOINT and runs with no arguments. Setting only `args:` keeps the image's ENTRYPOINT but replaces its CMD. Setting both completely defines what runs, ignoring both ENTRYPOINT and CMD from the image.

## Cleanup

Remove the tutorial pod, the namespace, and all tutorial images:

```bash
kubectl delete namespace tutorial-container-images

nerdctl rmi tutorial-app:v1 tutorial-app:v2 tutorial-app:v3 tutorial-app:v4

rm -rf ~/container-images-tutorial/
```

## Reference Commands

### Building and Managing Images

| Command | Description |
|---|---|
| `nerdctl build -t name:tag .` | Build using Dockerfile in current directory |
| `nerdctl build -f Dockerfile.alt -t name:tag .` | Build using a named Dockerfile |
| `nerdctl build --build-arg KEY=VAL -t name:tag .` | Pass a build argument |
| `nerdctl build --no-cache -t name:tag .` | Disable layer cache |
| `nerdctl images` | List all images |
| `nerdctl images name` | List images matching name |
| `nerdctl tag src:tag dest:tag` | Create a new tag alias |
| `nerdctl rmi name:tag` | Remove an image |

### Inspecting Images

| Command | Description |
|---|---|
| `nerdctl image inspect name:tag` | Full image config JSON |
| `nerdctl image inspect name:tag --format '{{json .Config.Env}}'` | Environment variables |
| `nerdctl image inspect name:tag --format '{{json .Config.Labels}}'` | Image labels |
| `nerdctl image inspect name:tag --format '{{json .Config.Entrypoint}}'` | ENTRYPOINT array |
| `nerdctl image inspect name:tag --format '{{json .Config.Cmd}}'` | CMD array |
| `nerdctl image inspect name:tag --format '{{.Config.WorkingDir}}'` | Working directory |
| `nerdctl image inspect name:tag --format '{{.Config.User}}'` | Default user |
| `nerdctl history name:tag` | Layer history with sizes |

### Running Containers Locally

| Command | Description |
|---|---|
| `nerdctl run --rm name:tag` | Run and remove container on exit |
| `nerdctl run --rm name:tag COMMAND` | Override CMD |
| `nerdctl run --rm --entrypoint /bin/sh name:tag -c "..."` | Override ENTRYPOINT |
| `nerdctl run --rm -e KEY=VALUE name:tag` | Set environment variable |
| `nerdctl run --rm name:tag whoami` | Check running user |
| `nerdctl run --rm name:tag id -u` | Check running UID |
| `nerdctl run --rm name:tag env` | List all environment variables |
| `nerdctl run --rm name:tag pwd` | Check working directory |

### Loading into kind

| Command | Description |
|---|---|
| `nerdctl save name:tag -o file.tar` | Export image to tar archive |
| `kind load image-archive file.tar` | Load tar into kind cluster nodes |
