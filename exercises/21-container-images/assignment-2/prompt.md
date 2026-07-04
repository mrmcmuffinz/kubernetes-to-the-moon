# Assignment Prompt: Container Images — Assignment 2

**Series:** Container Images (2 of 2)
**Assignment number:** 2
**Topic directory:** exercises/21-container-images/assignment-2/
**Topic slug:** container-images

## Metadata

**Domain:** Application Design and Build (CKAD)
**Competencies covered:**
- Optimize container images using multi-stage builds
- Understand and exploit layer caching for faster builds
- Choose appropriate base images for different workload types
- Understand OCI image format, manifests, and content addressing
- Apply image tagging conventions and digest pinning
- Push and pull images using a local registry with nerdctl and kind

**Prerequisites:**
- container-images/assignment-1 (Dockerfile authoring, nerdctl build, image inspection)

**Forward references:**
- 23-supply-chain-security (Trivy scanning, Cosign signing, image policy enforcement)
- 25-opa-gatekeeper (enforcing registry and tag policies via admission)

---

## Scope Declaration

### In scope for this assignment

*Multi-stage builds*
- The problem multi-stage builds solve: build dependencies (compilers, test tools) inflating runtime images
- Syntax: multiple FROM instructions in one Dockerfile, each starting a new stage
- Naming stages with AS (FROM golang:1.22 AS builder)
- COPY --from=<stage> to pull artifacts from a previous stage into the current one
- COPY --from=<image> to pull from an external image (not just a prior stage)
- Measuring the size difference: nerdctl images showing the final stage vs a naive single-stage build
- Common patterns: Go binary built in golang image, copied into distroless/static; Node.js app built with node:slim, production image uses node:alpine with only node_modules from a clean install

*Layer caching*
- How caching works: each instruction produces a layer; if the instruction and all prior layers are unchanged, Docker/nerdctl reuses the cached layer
- What invalidates a cache layer: any change to an instruction's content, or any change to files referenced by COPY/ADD
- Ordering instructions for maximum cache reuse: copy dependency manifests (package.json, go.mod, requirements.txt) and install dependencies before copying application source code
- The RUN apt-get pattern: combining update + install in one RUN to avoid stale cache; using --no-install-recommends
- Practical demonstration: rebuild with source change only vs. dependency change, showing which layers are rebuilt

*Base image selection*
- ubuntu/debian: large, full OS tooling, familiar, good for debugging
- alpine: small (5MB), musl libc (may cause issues with glibc-linked binaries), BusyBox shell
- slim variants (python:3.13-slim, node:22-slim): Debian-based with non-essential packages removed
- distroless (gcr.io/distroless/...): no shell, no package manager, minimal attack surface; debugging requires ephemeral debug containers or a debug variant
- scratch: truly empty; only for statically compiled binaries (e.g., Go with CGO_ENABLED=0)
- Decision framework: start with what works, then reduce; understand the trade-off between debuggability and attack surface

*OCI image format*
- What OCI is: Open Container Initiative specification governing image format and runtime
- Image components: image manifest (JSON listing config and layer digests), image config (JSON with Entrypoint, Cmd, Env, Labels, history), layers (compressed tarballs of filesystem changes)
- Content-addressable storage: each layer identified by its SHA256 digest; shared layers stored once
- The difference between a tag and a digest: tags are mutable pointers (latest can point to different images over time); digests are immutable content hashes (SHA256 of the manifest)
- nerdctl image inspect --format json to see manifest and config; nerdctl images --digests to show digest column

*Image tagging conventions*
- Semantic versioning tags: major.minor.patch (v1.2.3), why this is better than :latest for reproducibility
- The :latest problem: it changes silently, breaks reproducibility, makes rollbacks unclear
- Digest pinning in pod specs: image: nginx@sha256:<digest> guarantees the exact image regardless of tag mutation
- Immutable tag patterns: once a version tag is pushed, never overwrite it; use new version numbers for updates
- nerdctl tag to create additional tags for an existing image

*Registry operations with nerdctl*
- Running a local registry: nerdctl run -d -p 5001:5000 registry:2 (or equivalent)
- Configuring kind to use an insecure local registry: kind cluster config with containerdConfigPatches for the registry mirror
- Tagging an image for a local registry: nerdctl tag myimage localhost:5001/myimage:v1.0.0
- nerdctl push to the local registry
- nerdctl pull from the local registry
- Verifying registry contents: nerdctl pull + nerdctl images
- imagePullPolicy: Always vs IfNotPresent behavior when using a local registry
- The difference between this workflow and the assignment-1 pattern of nerdctl save + kind load image-archive: push/pull via registry is the production-realistic approach

### Out of scope for this assignment

- Image vulnerability scanning and signing: deferred to 23-supply-chain-security
- OPA/Gatekeeper policies enforcing registry or tag rules: deferred to 25-opa-gatekeeper
- Dockerfile security hardening (secrets in layers, privilege escalation): deferred to 23-supply-chain-security
- Kubernetes ImagePolicyWebhook admission: deferred to 23-supply-chain-security

---

## Environment Requirements

**Cluster:** Single-node kind cluster configured to use a local registry.

**Local registry setup required.** The tutorial must include:
1. Starting a local registry container: `nerdctl run -d --name registry -p 5001:5000 registry:2`
2. Creating the kind cluster with a containerdConfigPatches block that points the registry host (localhost:5001 or a named host) to the local registry container, so kind nodes can pull images pushed there.
3. Verifying the setup before exercises begin.

The kind+local registry setup pattern from the official kind documentation should be followed. Include the full setup in the tutorial's environment section so it is self-contained.

**Tools required beyond kubectl:**
- nerdctl (image building, tagging, push, pull)
- kind (cluster management, including the local registry integration)

---

## Resource Gate

All Kubernetes resources are in scope. Exercises will primarily use Pods and Deployments to validate that images pulled from the local registry work correctly in the cluster.

---

## Topic-specific Conventions

- All base images must use explicit version tags in FROM. No FROM ubuntu, FROM golang, or FROM node without a version.
- The multi-stage build tutorial example must show a statically compiled Go binary or a similar compiled language so the final stage can use distroless/static or scratch. This makes the size reduction dramatic and concrete.
- Layer cache demonstrations must show actual build output (with CACHED labels visible) in the tutorial to make the concept tangible.
- The local registry setup in the tutorial must be fully scripted and verifiable before exercises begin. Do not rely on an external registry (Docker Hub, ghcr.io) for any exercise — all images must come from the local registry or be pre-loaded into kind.
- When showing digest pinning, use a real digest obtained by running nerdctl images --digests after pushing an image to the local registry. Do not fabricate example digests.

---

## Exercise Distribution Guidance

15 exercises across 5 levels (3 per level):

- **Level 1 (basic fluency):** Single-concept exercises on the new topics: tag an image for the local registry and push it; convert a single-stage Dockerfile to multi-stage by adding a second FROM; identify which instructions in a given Dockerfile create layers.
- **Level 2 (multi-concept):** Reorder Dockerfile instructions to maximize cache hits; choose the right base image for a given workload description and justify it; pin an image by digest in a pod spec and verify the running container uses the correct image.
- **Level 3 (debugging):** Broken builds or broken pod deployments. Bare headings. Examples: multi-stage Dockerfile with COPY --from referencing a stage name that does not exist; pod spec using digest pinning with a corrupted digest; registry push failing because the image tag is not prefixed with the registry host.
- **Level 4 (production-style build):** Build a multi-stage image for a realistic app (Go or Python), push it to the local registry, deploy it to the kind cluster, verify the container is running the correct version, then update the image and do a rolling update using the new tag.
- **Level 5 (advanced debugging + comprehensive):** Multi-symptom scenarios: an image pulled from the registry behaves differently than when built locally (musl vs glibc issue with alpine base); a pod stuck in ImagePullBackOff because the local registry is not configured in the kind containerd config; a multi-stage build that compiles successfully but the runtime image crashes because a shared library is missing in the minimal base.
