# Assignment Prompt: Supply Chain Security — Assignment 1

**Series:** Supply Chain Security (1 of 2)
**Topic slug:** supply-chain-security
**Topic directory:** exercises/23-supply-chain-security/assignment-1/

## Metadata

**Domain:** CKS — Supply Chain Security (20%)
**Competencies:** Image vulnerability scanning, Dockerfile security hygiene, SBOM generation
**Prerequisites:** 21-container-images/assignment-1

## Scope — In Scope

*Trivy image scanning*
- Installing Trivy (binary or as a pod)
- trivy image <name>: reading CVE ID, package name, installed version, fixed version, severity (CRITICAL/HIGH/MEDIUM/LOW/UNKNOWN)
- Filtering by severity: --severity CRITICAL,HIGH
- trivy image --exit-code 1 for CI-style fail on findings
- trivy fs . for scanning a local Dockerfile and filesystem
- trivy config . for scanning Kubernetes manifests for misconfigurations
- Understanding when a CVE is exploitable vs theoretical (context: not all HIGH CVEs are immediately actionable)
- Remediating by updating the base image to a version where the package is fixed

*Interpreting and acting on scan results*
- Reading the fixed-in column and updating FROM to the fixed base image version
- Re-scanning after an update to verify remediation
- Understanding that some CVEs have no fix yet (informational only)

*Dockerfile security anti-patterns*
- Secrets in build args and ENV: ENV DB_PASSWORD=secret baked into the image (visible in nerdctl inspect); ARG PASSWORD passed via --build-arg (visible in image history)
- COPY of credential files: copying .env, id_rsa, or AWS credentials into an image
- Running as root by default: no USER directive means processes run as UID 0
- Using ADD with remote URLs: arbitrary remote code execution risk; COPY is preferred
- :latest tags in FROM: unpredictable, cannot be scanned for a specific version, fails reproducibility

*Dockerfile security best practices*
- Non-root USER with a specific UID (reinforces 21-container-images/assignment-1)
- Minimal base images to reduce CVE surface: distroless, alpine, slim variants
- Pinning FROM by digest: FROM ubuntu:24.04@sha256:<digest>
- .dockerignore to prevent secrets and unnecessary files from entering the build context
- Multi-stage builds to exclude build tools from the runtime image (reinforces 21-container-images/assignment-2 and reduces attack surface)

*SBOM basics*
- What an SBOM is: a machine-readable inventory of components, versions, and licenses in an image
- trivy sbom --format cyclonedx <image>: generating a CycloneDX SBOM
- trivy sbom --format spdx-json <image>: generating an SPDX SBOM
- Reading an SBOM: identifying packages, versions, licenses
- Why SBOMs matter: rapid identification of affected images when a new CVE is published for a component

## Scope — Out of Scope

- Image signing and verification (Cosign): deferred to supply-chain-security/assignment-2
- Admission policies enforcing image requirements: deferred to supply-chain-security/assignment-2
- OPA/Gatekeeper policies: covered in 25-opa-gatekeeper
- Dockerfile authoring fundamentals: covered in 21-container-images/assignment-1

## Environment

Single-node kind cluster. Trivy must be installed in the tutorial. A local registry (from 21-container-images/assignment-2) is used for scanning locally built images. All images used in exercises must be pullable without external authentication.

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- All scan exercises use real images with known CVEs at the time of writing (pin to specific versions). Do not use fabricated CVE data.
- For Dockerfile anti-pattern exercises, supply a broken Dockerfile for the learner to identify and fix — do not ask the learner to create the anti-pattern themselves.
- Tutorial namespace: `tutorial-supply-chain`.

## Exercise Distribution

- Level 1: Scan a given image with Trivy, identify all CRITICAL findings, identify the fixed-in version
- Level 2: Update a Dockerfile to fix CVEs by bumping the base image, re-scan to verify; generate an SBOM for an image
- Level 3 (debugging): Bare headings. Broken Dockerfiles with security anti-patterns to identify and fix (secret in ENV, COPY of credentials, running as root)
- Level 4: Full Dockerfile security audit — given a multi-stage Dockerfile with multiple issues, identify all problems and produce a corrected version; scan the result
- Level 5 (debugging): Image in a deployment is failing CIS checks and leaking credentials; diagnose from scan output and image history, rebuild correctly
