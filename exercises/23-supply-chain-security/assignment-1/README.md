# Supply Chain Security, Assignment 1: Image Scanning, Dockerfile Hygiene, and SBOMs

This assignment is the first of two in the Supply Chain Security series, covering the techniques you need to evaluate and harden the software artifacts that enter your Kubernetes cluster. You will install and use Trivy to scan container images for known vulnerabilities, interpret CVE data to make remediation decisions, identify and correct common Dockerfile security anti-patterns, and generate Software Bills of Materials (SBOMs) in standard formats. The assignment assumes you have completed the Container Images assignment (21-container-images/assignment-1) and are comfortable building and pushing images with nerdctl to a local registry. Assignment 2 in this series covers image signing with Cosign and admission-time enforcement.

## Files

| File | Description |
|------|-------------|
| `README.md` | This file. Overview, workflow, difficulty guide, and scope. |
| `prompt.md` | The generation prompt used to produce this assignment. |
| `supply-chain-security-tutorial.md` | Complete walkthrough of Trivy installation, image scanning, Dockerfile hygiene, and SBOM generation with narrative explanation of each concept. |
| `supply-chain-security-homework.md` | 15 progressive exercises across five difficulty levels covering scanning, remediation, Dockerfile fixing, and SBOM workflows. |
| `supply-chain-security-homework-answers.md` | Complete solutions for all 15 exercises, debugging diagnostic reasoning, common mistakes, and a verification cheat sheet. |

## Recommended Workflow

Work through the tutorial in full before touching the homework. The tutorial installs Trivy, walks through a real scan against a known-vulnerable image, and demonstrates every command pattern the homework exercises build on. Skimming the tutorial and jumping to exercises will slow you down, because each exercise assumes you understand not just the commands but why you are running them. After finishing the tutorial, start the homework at Level 1 and proceed in order. Level 1 exercises establish baseline fluency with the scanning workflow; Level 3 and Level 5 are debugging exercises where you must diagnose problems without hints, and the diagnostic reasoning you build in Levels 1 and 2 is what you will draw on there.

Use the answer key only after a genuine attempt at each exercise. For debugging exercises, try to work through the diagnosis phase systematically (scan the image, inspect the Dockerfile, trace the build history) before looking at the solution, because that diagnostic sequence is exactly what the CKA exam environment tests.

## Difficulty Progression

Level 1 exercises build scanning fluency by having you run Trivy against known-vulnerable images, read the output, and locate specific data points such as which packages carry CRITICAL findings and what the fixed version is. These exercises are deliberately narrow: a single command, a single output to interpret. Level 2 exercises step up to remediation and SBOM workflows. You will update a base image to reduce CVE exposure, rebuild the image, re-scan to confirm the improvement, and generate SBOMs in CycloneDX and SPDX formats. The work combines Trivy scanning with nerdctl image builds and exercises your ability to verify that a change actually improved the security posture. Level 3 exercises present broken Dockerfiles with realistic security anti-patterns and ask you to find and fix the problems. Headings are bare and objectives do not name the bug type or count; you must read the Dockerfile carefully and apply what the tutorial covered about anti-patterns. Level 4 exercises require a complete security audit of a complex multi-stage Dockerfile, producing a corrected version that satisfies all the best practices introduced in the tutorial. The scope is broader, the issues are layered, and the verification requires building and scanning the corrected image. Level 5 exercises are advanced debugging scenarios involving deployed Kubernetes workloads whose images have security problems that must be diagnosed from Trivy scan output and image history, then corrected by rebuilding the image and redeploying.

## Prerequisites

This assignment assumes you have completed 21-container-images/assignment-1 and are comfortable building images with `nerdctl build`, pushing to `localhost:5001`, and using `kubectl apply` to deploy workloads. You should also have completed the Mumshad CKA course sections covering pod specification and deployment management. Cluster setup instructions are in `docs/cluster-setup.md`; the local registry setup from the Container Images assignment must be running before you begin the exercises. Trivy installation is covered step by step in the tutorial, so no prior Trivy experience is needed.

## Cluster Requirements

This assignment uses a single-node kind cluster. Refer to [`docs/cluster-setup.md#single-node-kind-cluster`](../../../docs/cluster-setup.md#single-node-kind-cluster) for the complete cluster creation procedure. No additional components beyond the base cluster and the local registry at `localhost:5001` are required for this assignment.

## Estimated Time Commitment

Plan roughly 45 minutes to work through the tutorial attentively, including actually running the Trivy scans and inspecting the output on your own cluster. Level 1 exercises should each take 5 to 10 minutes; they are primarily about reading and interpreting scan output correctly. Level 2 exercises take 10 to 15 minutes each because they involve building images and generating SBOM files. Level 3 debugging exercises take 10 to 20 minutes each depending on how carefully you read the Dockerfile. Level 4 exercises take 20 to 30 minutes each given the scope of the audit and the rebuilding step. Level 5 exercises are the most involved, typically 25 to 35 minutes each, because they require diagnosing a running deployment, pulling apart the build history, and performing a full rebuild-and-redeploy cycle.

## Scope Boundary and What Comes Next

This assignment covers vulnerability scanning, Dockerfile hygiene, and SBOM generation. It does not cover image signing with Cosign, signature verification policies, OPA/Gatekeeper admission enforcement, or Kyverno policy integration; those topics are the subject of Supply Chain Security assignment 2. Runtime security tools such as Falco and seccomp profiling are covered in the Security Contexts series (13-security-contexts). Network-level supply chain controls such as egress policies that restrict where images can be pulled from are covered in the Network Policies series (10-network-policies).

## Key Takeaways After Completing This Assignment

By the end of all 15 exercises you should be able to install Trivy and run `trivy image`, `trivy fs`, and `trivy config` confidently; filter scan results by severity and configure `--exit-code 1` for CI pipeline enforcement; read a CVE finding and extract the package name, installed version, fixed version, and severity; update a base image to remediate CVE exposure and re-scan to verify the improvement; identify every major Dockerfile anti-pattern covered in the tutorial (secrets in ENV or ARG, COPY of credential files, ADD with URLs, root user, untagged or unpinned base images) and produce a corrected Dockerfile; generate CycloneDX and SPDX-JSON SBOMs for an image and confirm the SBOM contains expected component entries; and diagnose a running Kubernetes workload whose image has security problems using scan output and `nerdctl image history`.
