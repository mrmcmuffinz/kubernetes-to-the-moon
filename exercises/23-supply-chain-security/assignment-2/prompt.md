# Assignment Prompt: Supply Chain Security — Assignment 2

**Series:** Supply Chain Security (2 of 2)
**Topic slug:** supply-chain-security
**Topic directory:** exercises/23-supply-chain-security/assignment-2/

## Metadata

**Domain:** CKS — Supply Chain Security (20%)
**Competencies:** Image signing with Cosign, signature verification, admission enforcement of image policy
**Prerequisites:** supply-chain-security/assignment-1, 16-admission-controllers/assignment-1

## Scope — In Scope

*Cosign key-based signing*
- cosign generate-key-pair: producing cosign.key and cosign.pub
- cosign sign --key cosign.key <registry>/<image>:<tag>: signing an image after pushing to the local registry
- How Cosign stores the signature: as a separate OCI artifact in the same registry (image:sha256-<digest>.sig)
- cosign verify --key cosign.pub <image>: verifying a signature, reading the verification output
- What happens when verification fails: cosign verify on an unsigned image

*Cosign keyless signing*
- How keyless signing works: OIDC token from a provider (GitHub Actions, Google, etc.) used to get a short-lived certificate from Fulcio
- The Rekor transparency log: append-only log of signing events, public audit trail
- cosign sign --identity-token: keyless signing in CI context
- Conceptual understanding of keyless vs key-based trade-offs (no key management, but requires OIDC provider)

*Attestations*
- What an attestation is: a signed statement about an image (SBOM, scan results, build provenance)
- cosign attest --key cosign.key --predicate sbom.json --type cyclonedx <image>: attaching a signed SBOM
- cosign verify-attestation --key cosign.pub --type cyclonedx <image>: verifying the attestation

*Admission enforcement for image policy*
- Using ValidatingAdmissionPolicy (CEL) to enforce image requirements: rejecting pods that use images without a specific registry prefix, rejecting :latest tags
- Connecting Cosign verification to admission: the pattern of a ValidatingWebhook or policy that calls cosign verify before admitting a pod (conceptual; a full webhook implementation is complex, focus on the policy pattern)
- Using OPA/Gatekeeper ConstraintTemplate to enforce registry allowlists and tag policies (conceptual cross-reference to 25-opa-gatekeeper)

*Policy enforcement patterns*
- Require images from approved registries only (localhost:5001 for exercises)
- Require non-:latest tags
- Require signed images (conceptual pattern using a webhook)
- Deny images with CRITICAL CVEs (using an admission webhook that calls Trivy)

## Scope — Out of Scope

- Trivy scanning: covered in supply-chain-security/assignment-1
- General OPA/Gatekeeper: covered in 25-opa-gatekeeper
- General admission controllers: covered in 16-admission-controllers

## Environment

Single-node kind cluster with local registry. Cosign must be installed in the tutorial. All signing and verification exercises use the local registry from 21-container-images/assignment-2. For admission policy exercises, ValidatingAdmissionPolicy (CEL-based, built into Kubernetes 1.26+) is used where possible to avoid requiring a full webhook server.

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- Key-pair files (cosign.key, cosign.pub) live in a dedicated directory during the tutorial; exercises use their own key pairs stored in Kubernetes Secrets or local files.
- The local registry must be running for all signing/verification exercises.
- Tutorial namespace: `tutorial-supply-chain`.

## Exercise Distribution

- Level 1: Generate a key pair, sign an image, verify it; identify what happens when verifying an unsigned image
- Level 2: Attach a signed SBOM attestation to an image, verify the attestation; write a ValidatingAdmissionPolicy rejecting :latest images
- Level 3 (debugging): Bare headings. Broken signing workflows (wrong registry tag format, key mismatch, image pushed after signing so digest changed)
- Level 4: Full supply chain workflow — build an image, scan it, push to local registry, sign, attach SBOM, verify, deploy to cluster
- Level 5 (debugging): A deployment is rejected by an admission policy; diagnose whether the issue is the image tag, the registry, or a missing signature
