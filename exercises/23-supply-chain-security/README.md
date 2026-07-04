# Supply Chain Security

**Topic area:** Container image supply chain integrity
**Certification relevance:** CKS (Supply Chain Security 20%)
**Assignments in this topic:** 2

---

## Why Two Assignments

Supply chain security has two distinct phases: detecting problems in images (scanning and Dockerfile hygiene) and proving image integrity (signing and verification). These require different tools (Trivy vs Cosign), different mental models (vulnerability analysis vs cryptographic provenance), and different workflows. Splitting them keeps each assignment coherent and avoids tool overload in a single session.

---

## Assignment Summary

| Assignment | Focus | Prerequisites |
|---|---|---|
| assignment-1 | Trivy image scanning, Dockerfile security best practices, SBOM basics | 21-container-images/assignment-1 |
| assignment-2 | Cosign image signing and verification, policy enforcement via admission | supply-chain-security/assignment-1, 16-admission-controllers/assignment-1 |

---

## Assignment 1: Image Scanning and Dockerfile Hygiene

Subtopics:
- *Trivy image scanning:* installing Trivy, trivy image <name> output (CVE IDs, severity levels, fixed versions), trivy fs for filesystem scanning, understanding CRITICAL/HIGH/MEDIUM/LOW/UNKNOWN severity, filtering by severity with --severity
- *Interpreting scan results:* what a CVE means, when a vulnerability is exploitable vs theoretical, how to read the fixed-in-version column, updating base images to remediate
- *Dockerfile security anti-patterns:* secrets baked into layers (ENV passwords, COPY of .env files), running as root by default, using :latest tags (unpinned, unscannable), ADD with remote URLs (arbitrary code execution risk)
- *Dockerfile security best practices:* non-root USER (reinforces 21-container-images), minimal base images (distroless, scratch for reduced CVE surface), COPY over ADD, pinning base images by digest in FROM
- *SBOM basics:* what a software bill of materials is, trivy sbom --format cyclonedx or spdx, reading an SBOM to identify components and licenses

---

## Assignment 2: Image Signing and Verification

Subtopics:
- *Cosign architecture:* keyless signing vs key-based signing, how Cosign attaches signatures to OCI registries as additional image tags, transparency logs (Rekor)
- *Key-based signing:* cosign generate-key-pair, cosign sign --key cosign.key <image>, cosign verify --key cosign.pub <image>
- *Keyless signing:* OIDC-based signing with Sigstore, cosign sign with --identity-token (relevant for CI environments)
- *Verifying signatures in admission:* using a ValidatingAdmissionPolicy or an image policy webhook to reject unsigned images, connecting Cosign verification to the admission pipeline
- *Policy enforcement patterns:* requiring images to come from approved registries, requiring signed images, rejecting :latest tags via admission policy
- *Attestations:* cosign attest for attaching SBOMs and scan results as verifiable attestations to images

---

## Scope Boundaries

**Not covered:**
- Dockerfile authoring fundamentals: covered in 21-container-images/assignment-1
- OPA/Gatekeeper for general policy: covered in 25-opa-gatekeeper
- Falco for runtime threat detection: covered in 26-runtime-security
- General admission controllers: covered in 16-admission-controllers

---

## Cluster Requirements

Assignment-1 requires Trivy installed in the environment (or a pod running trivy). A local registry (from 21-container-images/assignment-2) is helpful for scanning locally built images. Assignment-2 requires Cosign installed and a local registry for push/sign/verify workflows. No special kind configuration beyond a local registry is needed.

---

## Recommended Order

Assignment-1 before assignment-2. Scanning identifies what to protect; signing protects it.
