# Supply Chain Security: Assignment 2 -- Image Signing and Admission Enforcement

This assignment is the second of two in the Supply Chain Security series. Assignment 1 focused on vulnerability scanning with Trivy; this assignment moves to the downstream half of the supply chain: proving that images are authentic, unmodified, and sourced from approved registries. You will work hands-on with Cosign for key-based image signing, learn how signatures are stored in the OCI registry alongside the images they protect, attach signed attestations that carry metadata like an SBOM, and use Kubernetes ValidatingAdmissionPolicy to enforce image origin and tag requirements at admission time. The assignment finishes with a Level 4 full pipeline exercise that chains every step together and a pair of Level 5 debugging scenarios that require you to diagnose and repair broken admission enforcement setups.

## Files

| File | Description |
|------|-------------|
| `prompt.md` | Generator input: scope, competencies, and exercise distribution for this assignment |
| `README.md` | This file: assignment overview, workflow guidance, and prerequisites |
| `supply-chain-security-tutorial.md` | Hands-on tutorial covering Cosign installation, key-based signing, attestations, and ValidatingAdmissionPolicy |
| `supply-chain-security-homework.md` | 15 progressive exercises across five difficulty levels |
| `supply-chain-security-homework-answers.md` | Complete solutions with diagnostic reasoning for all 15 exercises |

## Recommended Workflow

Read the tutorial file first and work through every command in sequence. The tutorial installs Cosign, builds a tutorial image, signs it, attaches an SBOM attestation, and then creates a ValidatingAdmissionPolicy that rejects images not meeting your registry or tag requirements. Because Cosign interacts with a running OCI registry, you will need the local registry from the container-images assignment running before you start. Once you have completed the tutorial walkthrough and cleaned up the tutorial namespace, move to the homework exercises.

Work the exercises in level order. The Level 1 exercises give you rapid repetitions on generating key pairs and running the sign-and-verify cycle. Level 2 introduces attestations and your first admission policies. Level 3 and Level 5 are debugging exercises with bare headings; resist the temptation to read ahead into the answers file before you have diagnosed the problem yourself, since the diagnostic reasoning is the exam skill you are building. Level 4 exercises are the longest and combine skills from earlier levels into realistic end-to-end scenarios.

## Difficulty Progression

Level 1 builds fluency with the core Cosign workflow: generating a key pair, pushing an image to the local registry, signing it, and running cosign verify. You also observe what failure looks like when you attempt to verify an unsigned image, which anchors your understanding of why the tool exists. These exercises should feel quick once you have the tutorial commands internalized.

Level 2 adds two new concepts. The first is attestations: signed statements attached to an image that carry structured metadata such as an SBOM. The second is ValidatingAdmissionPolicy, the CEL-based admission mechanism built into Kubernetes 1.28 and stable in 1.30. You will write policies that reject pods using the :latest tag and policies that require images to come from an approved registry, then bind those policies and verify they take effect.

Level 3 contains three debugging exercises with bare headings. Each exercise sets up a broken Cosign workflow and asks you to diagnose and repair it. The scenarios are drawn from realistic mistakes: overwriting a registry image after signing it (which silently invalidates the signature), verifying with the wrong public key, and signing the wrong image tag. Read the error output from cosign verify carefully; the messages contain the information you need.

Level 4 exercises are complex build tasks. Exercise 4.1 walks you through a complete supply chain pipeline from Dockerfile to signed, attested, deployed pod. Exercise 4.2 asks you to enforce a two-policy admission setup and validate it against several image scenarios. Exercise 4.3 combines registry policy and deployment with a live verification step.

Level 5 contains three debugging exercises with bare headings. The scenarios involve deployments or pods being rejected by admission policies, or admission policies that are not enforcing as expected. You must identify whether the problem is the image reference, the policy expression, or the policy binding configuration, and then fix all issues so the desired enforcement is in place.

## Prerequisites

This assignment assumes you have completed supply-chain-security/assignment-1 (Trivy scanning and image analysis) and 16-admission-controllers/assignment-1 (built-in admission controllers and ValidatingAdmissionPolicy fundamentals). You should be comfortable with kubectl apply, kubectl describe, and reading admission error messages. The local OCI registry at localhost:5001 is assumed to be running; it was set up in the 21-container-images assignment. See [docs/cluster-setup.md](../../../docs/cluster-setup.md) for the single-node cluster profile used throughout this assignment.

## Cluster Requirements

This assignment uses the single-node kind cluster profile. See [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster) for cluster creation steps. The local registry at localhost:5001 must be running and reachable from both the host (for cosign and nerdctl) and from within the cluster (for pod image pulls). No additional CRDs or controllers are required; ValidatingAdmissionPolicy is a built-in feature of the Kubernetes 1.35 API server used in this assignment.

## Estimated Time Commitment

Level 1 exercises each take roughly 5 to 8 minutes once Cosign is installed. Level 2 exercises range from 10 to 15 minutes; the admission policy exercises require writing YAML and testing two code paths. Level 3 debugging exercises are open-ended but should typically resolve within 10 to 15 minutes if you work methodically through the cosign verify output. Level 4 exercises, especially 4.1, take 20 to 30 minutes because they combine many steps. Level 5 debugging exercises take 15 to 25 minutes depending on how many issues are present. Total time for all 15 exercises is approximately 3 to 4 hours.

## Scope Boundary and What Comes Next

This assignment covers key-based Cosign signing, OCI-native attestations, and CEL-based admission policy enforcement using ValidatingAdmissionPolicy. It does not cover Trivy scanning (supply-chain-security/assignment-1) or general OPA/Gatekeeper constraint templates (covered in 25-opa-gatekeeper, where you will build more sophisticated registry and tag policies using ConstraintTemplate). The assignment treats connecting a Cosign signature check to admission as a conceptual pattern only; a production implementation using a ValidatingWebhook that calls cosign verify at admission time requires a running webhook server and is outside the scope of this exercise set.

## Key Takeaways After Completing This Assignment

After completing this assignment you will be able to generate a Cosign key pair, sign an OCI image stored in a local registry, verify the signature, and explain where the signature artifact is stored in the registry. You will understand why pushing a new image to the same tag after signing silently breaks verification and how to recover. You will be able to create a CycloneDX SBOM attestation and attach it to an image using cosign attest, then verify it with cosign verify-attestation. You will be able to write a ValidatingAdmissionPolicy with a CEL expression and a ValidatingAdmissionPolicyBinding that enforces the policy in a target namespace, and you will know the difference between the Deny, Warn, and Audit validation actions and what happens when each is misconfigured.
