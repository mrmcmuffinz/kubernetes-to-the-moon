# Container Images

**Topic area:** Application design and build
**Certification relevance:** CKAD (Application Design and Build, 20%)
**Assignments in this topic:** 2

---

## Why Two Assignments

The container images topic has 12 distinct subtopics organized around two natural phases
of image work. The first phase is authoring: writing Dockerfiles, understanding how
instructions compose, building images locally, and inspecting the result. The second
phase is optimization and distribution: making images smaller and faster to build, choosing
the right base, understanding the OCI image format, and getting images into and out of
registries. These two phases have different mental models (authoring vs. operations) and
different tooling focus, so splitting them keeps each assignment coherent.

A single dense assignment covering all 12 subtopics would produce exercises that jump
between Dockerfile syntax and registry authentication without a natural throughline.
Two focused assignments let each one build a coherent narrative.

---

## Assignment Summary

| Assignment | Focus | Prerequisites |
|---|---|---|
| assignment-1 | Dockerfile authoring: instruction set, ENTRYPOINT/CMD, build context, nerdctl build, image inspection, non-root USER | pods/assignment-1 (image pull policy and container runtime basics) |
| assignment-2 | Optimization and distribution: multi-stage builds, layer caching, base image selection, OCI format, tagging, registry operations | container-images/assignment-1 |

---

## Assignment 1: Dockerfile Authoring

**Focus:** Writing correct Dockerfiles and understanding how images are built and structured.

Subtopics covered:

- *Instruction set fundamentals:* FROM, RUN, COPY, ADD, ENV, ARG, LABEL, EXPOSE, WORKDIR. What each instruction does, when to use COPY vs ADD, how ARG differs from ENV, and what EXPOSE actually means at runtime.
- *ENTRYPOINT and CMD:* exec form vs shell form, how they combine (ENTRYPOINT sets the executable, CMD provides default arguments), how to override each at `nerdctl run` time, and the CKAD exam pattern of `command:` and `args:` in pod specs mapping to ENTRYPOINT and CMD.
- *Build context and .dockerignore:* what the build context is, why its size matters, using .dockerignore to exclude files from the context, and how context affects COPY paths.
- *Building with nerdctl:* `nerdctl build` flags (--tag, --file, --build-arg, --no-cache), reading build output, tagging at build time vs post-build.
- *Image inspection:* `nerdctl inspect` to read image metadata, `nerdctl history` to see layer breakdown and sizes, understanding which instructions create layers vs which are metadata-only.
- *Non-root USER directive:* creating a user and group in the Dockerfile, switching to non-root with USER, the distinction between Dockerfile USER (build-time identity baked into the image) and pod spec `securityContext.runAsUser` (runtime override).

---

## Assignment 2: Optimization and Distribution

**Focus:** Making images production-ready and working with registries.

Subtopics covered:

- *Multi-stage builds:* using multiple FROM stages in one Dockerfile, naming stages with AS, COPY --from to pull artifacts between stages, separating build-time dependencies from runtime images, and measuring the size reduction.
- *Layer caching:* how Docker/nerdctl caches layers, which instructions invalidate the cache and why, ordering instructions from least-to-most-frequently-changed to maximize cache hits, and practical patterns (install dependencies before copying source).
- *Base image selection:* trade-offs between ubuntu/debian (large, familiar), alpine (small, musl libc), distroless (no shell, minimal attack surface), and scratch (empty, for statically compiled binaries). When to use each and what breaks when you switch.
- *OCI image format:* what OCI is (Open Container Initiative), image manifest structure (config + layers), the difference between a tag and a digest, content-addressable storage, and why digests are immutable while tags are not.
- *Image tagging conventions:* semantic versioning tags, the risks of `:latest`, digest pinning in pod specs (`image@sha256:...`), and tag immutability patterns.
- *Registry operations with nerdctl:* running a local registry container, `nerdctl push` and `nerdctl pull`, configuring kind to use a local registry, basic registry authentication (`nerdctl login`).

---

## Scope Boundaries

**Not covered in this topic:**

- Image security scanning (Trivy) and signing (Cosign): deferred to `exercises/23-supply-chain-security`
- Dockerfile security hardening (dropping capabilities, read-only layers, avoiding secrets in layers): deferred to `exercises/23-supply-chain-security`
- Pod `securityContext.runAsUser` and runtime identity: covered in `exercises/13-security-contexts`
- Image pull policy (Always, IfNotPresent, Never) in pod specs: covered in `exercises/01-pods/assignment-1`
- ENTRYPOINT/CMD equivalence in pod `command:` and `args:` fields: introduced in `exercises/01-pods/assignment-1`, reinforced in assignment-1 of this topic from the Dockerfile perspective
- OPA/Gatekeeper image policy enforcement: deferred to `exercises/25-opa-gatekeeper`

---

## Cluster Requirements

Both assignments use a single-node kind cluster. Assignment-2 additionally requires a
local registry container running alongside the kind cluster so that push/pull exercises
work without an external registry. The tutorial must include setup instructions for the
local registry and the kind cluster configuration that makes it accessible.

No CNI beyond the default kindnet is needed. No special admission controllers required.

---

## Recommended Order

Complete assignment-1 before assignment-2. Assignment-2 builds on the Dockerfile
authoring skills from assignment-1 and extends them into optimization and registry
workflows. The two assignments are designed to be worked through sequentially.
