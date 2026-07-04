# Container Images: Defining, Building, and Inspecting Images

This is the first of two assignments on container images. It covers the Dockerfile instruction set from the ground up: writing Dockerfiles using FROM, RUN, COPY, ENV, ARG, LABEL, EXPOSE, WORKDIR, and USER; understanding how ENTRYPOINT and CMD interact in exec and shell forms; building and inspecting images with nerdctl; and loading locally built images into a kind cluster for pod deployment. The second assignment in this series picks up with multi-stage builds, layer caching optimization, and registry push and pull operations. Together the two assignments build the image-authoring skills tested by both the CKA and CKAD exams.

## Files

| File | Description |
|---|---|
| `README.md` | This overview |
| `prompt.md` | Generator input used to produce this assignment |
| `container-images-tutorial.md` | Step-by-step tutorial teaching Dockerfile authoring through a worked example |
| `container-images-homework.md` | 15 progressive exercises |
| `container-images-homework-answers.md` | Complete solutions with explanations |

## Recommended Workflow

Work through the tutorial before attempting any exercises. The tutorial builds a Python HTTP server progressively, introducing each Dockerfile instruction family through concrete examples and explaining the tradeoffs at each step. Pay particular attention to the ENTRYPOINT and CMD combination table, the exec versus shell form distinction, and the section covering the nerdctl save plus kind load image-archive pattern, because exercises in Levels 4 and 5 rely on all three. After completing the tutorial, attempt each level on your own before consulting the answers. The debugging exercises in Levels 3 and 5 are designed to be worked through without hints, so treat the objective statement as the only information you have and use the diagnostic commands from the tutorial to investigate.

## Difficulty Progression

Level 1 exercises build single-concept fluency: write a Dockerfile using one or two core instructions, build it with nerdctl, and verify the outcome with nerdctl inspect or nerdctl run. Level 2 exercises combine multiple concepts in a single Dockerfile: the ARG versus ENV distinction at runtime, ENTRYPOINT and CMD together with override semantics, and non-root USER with proper file ownership. Level 3 exercises present broken Dockerfiles or misconfigured pod configurations for you to diagnose and repair; no heading or objective reveals the number or type of problems present, because discovering that is part of the exercise. Level 4 exercises require writing a complete, production-style Dockerfile for a realistic application, loading the resulting image into a kind cluster using nerdctl save and kind load image-archive, and deploying it as a pod. Level 5 exercises combine Dockerfile bugs with pod spec misconfigurations into multi-symptom scenarios; the same anti-spoiler rules apply as in Level 3.

## Prerequisites

This assignment builds on exercises/01-pods/assignment-1, which covers image pull policy, container runtime basics, and the relationship between pod spec command and args and the image's ENTRYPOINT and CMD. You should be comfortable writing a basic pod spec, using kubectl describe to read events, and interpreting container exit codes before starting Level 4. No other Kubernetes concepts beyond the pod are required. The cluster setup for this assignment uses the single-node kind profile documented in [docs/cluster-setup.md](../../../docs/cluster-setup.md#single-node-kind-cluster).

## Cluster Requirements

A single-node kind cluster is sufficient for all exercises. Follow the setup instructions at [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster). No metrics-server, MetalLB, or additional CRDs are needed. Levels 1 through 3 work entirely with local nerdctl builds and do not require a running cluster at all. Levels 4 and 5 load images into kind using the nerdctl save plus kind load image-archive pattern described in the tutorial; no external registry or network pull is required.

## Estimated Time Commitment

Level 1 exercises take five to ten minutes each, mostly spent writing the Dockerfile and running the verification commands. Level 2 exercises take ten to fifteen minutes each because they involve combining multiple Dockerfile concepts and verifying runtime behavior. Level 3 debugging exercises take fifteen to twenty minutes each, assuming you approach them systematically with diagnostic commands rather than guessing. Level 4 exercises take twenty to thirty minutes each, covering Dockerfile authoring, image build, nerdctl save, kind load, pod creation, and multi-step verification. Level 5 exercises take twenty-five to forty minutes each.

## Scope Boundary and What Comes Next

This assignment deliberately excludes multi-stage builds, base image selection tradeoffs between distroless and Alpine and scratch, OCI image format internals, and registry push and pull operations. Those topics are all covered in container-images/assignment-2. Dockerfile security hardening beyond the non-root USER directive and image vulnerability scanning are covered in 23-supply-chain-security. Pod-level security context overrides such as securityContext.runAsUser and runAsNonRoot are covered in 13-security-contexts. The distinction between what the Dockerfile bakes in and what the pod spec overrides at runtime is a recurring theme across those assignments.

## Key Takeaways After Completing This Assignment

After completing this assignment you should be able to write a Dockerfile using the full core instruction set correctly and explain what each instruction does at build time versus runtime. You should understand why exec form is preferred over shell form for ENTRYPOINT and CMD, know how to build and inspect images with nerdctl, create non-root user identity baked into the image with correct file ownership, load a locally built image into a kind cluster without a registry, and correctly predict how Kubernetes pod spec command and args override the image's ENTRYPOINT and CMD. You should also be able to construct a proper .dockerignore file that excludes files from the build context without accidentally breaking the build.
