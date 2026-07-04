# Assignment Prompt: Container Images — Assignment 1

**Series:** Container Images (1 of 2)
**Assignment number:** 1
**Topic directory:** exercises/21-container-images/assignment-1/
**Topic slug:** container-images

## Metadata

**Domain:** Application Design and Build (CKAD)
**Competencies covered:**
- Define, build, and modify container images
- Understand Dockerfile instruction semantics
- Build images using nerdctl in a kind cluster environment
- Inspect image structure and layers
- Configure non-root user identity at build time

**Prerequisites:**
- exercises/01-pods/assignment-1 (image pull policy, container runtime basics, pod spec command/args)

**Forward references:**
- container-images/assignment-2 (multi-stage builds, layer caching, registry operations)
- 23-supply-chain-security (Dockerfile security hardening, image scanning, signing)
- 13-security-contexts (pod-level runAsUser vs Dockerfile USER)

---

## Scope Declaration

### In scope for this assignment

*Dockerfile instruction set*
- FROM: base image selection, scratch as an option, using digests vs tags in FROM
- RUN: shell form vs exec form, combining RUN commands to reduce layers, apt-get patterns
- COPY: syntax, source/destination, COPY vs ADD (ADD has tar extraction and URL fetch behavior; COPY is preferred for local files)
- ENV: setting environment variables at build time that persist to runtime
- ARG: build-time variables that do not persist to runtime; ARG before FROM for base image parameterization; passing --build-arg at build time
- LABEL: image metadata, OCI annotation conventions
- EXPOSE: declaring ports (documentation only, does not publish); how it relates to containerPort in pod specs
- WORKDIR: setting working directory, creating it if it does not exist, effect on subsequent RUN/COPY/CMD/ENTRYPOINT
- USER: declaring the user to run the container process as; creating the user with RUN useradd/adduser before switching

*ENTRYPOINT and CMD*
- Exec form (JSON array) vs shell form (string wrapped in /bin/sh -c): when to use each, why exec form is preferred for signal handling
- How ENTRYPOINT and CMD combine: ENTRYPOINT sets the executable, CMD provides default arguments; table of all four combinations (no ENTRYPOINT/CMD, only one, both)
- Overriding CMD at runtime with nerdctl run arguments
- Overriding ENTRYPOINT at runtime with nerdctl run --entrypoint
- Mapping to Kubernetes pod spec: `command:` overrides ENTRYPOINT, `args:` overrides CMD; this is the reverse of what most people expect

*Build context and .dockerignore*
- What the build context is: the directory sent to the daemon at build time
- Why context size matters: large contexts slow builds even if the files are never COPYd
- .dockerignore syntax and patterns (similar to .gitignore): excluding node_modules, .git, test fixtures, secrets
- How COPY paths resolve relative to the context root

*Building with nerdctl*
- nerdctl build --tag, --file (non-default Dockerfile name), --build-arg, --no-cache, --target (for multi-stage, preview of assignment-2)
- Reading build output: layer IDs, cache hit/miss indicators, final image ID
- nerdctl images: listing local images, understanding repository/tag/image ID/size columns
- nerdctl tag: tagging an existing image with a new name
- nerdctl rmi: removing images; understanding image vs layer removal

*Image inspection*
- nerdctl inspect <image>: reading the full image config JSON (Entrypoint, Cmd, Env, WorkingDir, User, ExposedPorts, Labels)
- nerdctl history <image>: seeing per-layer commands and sizes; identifying which instructions created layers vs which are zero-size metadata
- Understanding the relationship between Dockerfile instructions and image layers

*Non-root USER directive*
- Why running as root in a container is a security concern even without the Kubernetes security context
- Creating a non-root user in the Dockerfile with RUN useradd -r -u 1001 appuser (or addgroup/adduser on Alpine)
- Switching to the user with USER appuser (or USER 1001)
- Setting ownership of application files (COPY --chown=appuser:appuser)
- The distinction between Dockerfile USER (baked into the image, the default if nothing overrides it) and pod spec securityContext.runAsUser (runtime override that takes precedence)
- Verifying the running user with nerdctl run --rm <image> whoami

### Out of scope for this assignment

- Multi-stage builds and layer caching optimization: deferred to container-images/assignment-2
- Base image selection trade-offs (distroless, alpine, scratch): deferred to container-images/assignment-2
- OCI image format and digest pinning: deferred to container-images/assignment-2
- Registry push/pull operations: deferred to container-images/assignment-2
- Image security scanning (Trivy) and signing (Cosign): deferred to 23-supply-chain-security
- Dockerfile security hardening beyond non-root USER: deferred to 23-supply-chain-security
- Pod securityContext.runAsUser and runtime identity controls: covered in 13-security-contexts

---

## Environment Requirements

**Cluster:** Single-node kind cluster (default kindnet CNI is sufficient)

**Tools required beyond kubectl:**
- nerdctl (available in the dev container environment)
- containerd (used by nerdctl as the container runtime)

**No special kind configuration needed.** All image builds happen locally via nerdctl; exercises do not push to a registry (that is deferred to assignment-2). Images built with nerdctl are available in the containerd image store and can be used directly in kind pods when the kind cluster uses the same containerd instance, OR the tutorial must show how to use `kind load image-archive` to load a locally built image into the kind cluster nodes.

**Important nerdctl note for the tutorial:** The kind cluster uses its own containerd namespaces. Images built with `nerdctl build` live in the default containerd namespace. To use a locally built image in a kind pod without a registry, use:
```
nerdctl save <image> -o image.tar
kind load image-archive image.tar
```
Then set `imagePullPolicy: Never` in the pod spec so Kubernetes does not try to pull from a registry.

---

## Resource Gate

All Kubernetes resources are in scope (this assignment is positioned after all networking topics). In practice, exercises will primarily use Pods and possibly Deployments to test images. The image-building work happens outside Kubernetes via nerdctl.

---

## Topic-specific Conventions

- All Dockerfiles in the tutorial and exercises must use explicit version tags in FROM (never FROM ubuntu or FROM python, always FROM ubuntu:24.04 or FROM python:3.13-slim).
- Application code in tutorial examples should be minimal (a small Go binary, a simple Python script, or a shell script) so the focus stays on the Dockerfile, not the application.
- Use `nerdctl build` consistently throughout, not `docker build`. The environment uses containerd via nerdctl.
- When showing exec form vs shell form, always show both in the tutorial with a clear label for each.
- The ENTRYPOINT/CMD combination table is a required element of the tutorial. Show all four cases.
- For exercises that require loading an image into the kind cluster, include the `nerdctl save` + `kind load image-archive` + `imagePullPolicy: Never` pattern in the tutorial setup section before the exercises use it.

---

## Exercise Distribution Guidance

15 exercises across 5 levels (3 per level):

- **Level 1 (basic fluency):** Write simple Dockerfiles from spec, build them, verify they produce the expected image. Focus on individual instructions: WORKDIR, ENV, LABEL, EXPOSE, COPY.
- **Level 2 (multi-concept):** Combine multiple instructions correctly. ARG vs ENV distinction. ENTRYPOINT + CMD combinations. Non-root USER with proper ownership.
- **Level 3 (debugging):** Broken Dockerfiles or broken pods using images. Bare headings only. Examples: wrong exec/shell form causing signal handling failure, USER set before the user is created, COPY path outside context, ARG used at runtime (not available).
- **Level 4 (production-style build):** Write a complete Dockerfile for a realistic application. Load it into kind. Deploy it as a pod with the correct imagePullPolicy. Verify the process runs as non-root.
- **Level 5 (advanced debugging + comprehensive):** Multi-symptom scenarios combining Dockerfile bugs with pod spec misconfigurations. Example: image built with shell-form ENTRYPOINT causing PID 1 issues + pod command/args override not working as expected because ENTRYPOINT and CMD semantics are misunderstood.
