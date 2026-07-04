# Kubernetes to the Moon

Hands-on Kubernetes learning material organized as a series of topic-focused assignments. Each assignment consists of a tutorial that teaches a topic end-to-end, a homework set with 15 progressive exercises, and a complete answer key. The goal is to build real operational fluency with Kubernetes, not just conceptual familiarity.

## What's Here

The repository covers core Kubernetes operations, networking, storage, security, cluster infrastructure, and more advanced topics like supply chain security and runtime threat detection. Assignments build progressively: early topics establish fundamentals (pods, workloads, configuration), later topics go deeper into security hardening, extensibility, and cluster internals.

All content assumes a kind cluster running rootless containerd via nerdctl. A single-node cluster is sufficient for most topics; assignments covering scheduling, controllers, networking, and troubleshooting require a multi-node cluster (1 control-plane plus 3 workers). Cluster setup instructions live in `docs/cluster-setup.md`.

For learners who want to understand how Kubernetes works at the infrastructure level, `exercises/20-cluster-setup/` contains guides for building clusters from scratch on QEMU/KVM virtual machines and on Raspberry Pi hardware.

## How to Work Through an Assignment

Each assignment follows the same three-phase workflow.

First, read the tutorial end-to-end with a cluster open in a terminal. The tutorial teaches one or more worked examples from start to finish, and the real value comes from running the commands as you read rather than just reading them. Every tutorial uses a dedicated namespace (`tutorial-<topic>`) so it won't conflict with the homework exercises. Clean up the tutorial namespace before moving to homework.

Second, work through the homework without looking at the answers. The 15 exercises are organized into five levels: Levels 1 and 2 build basic and multi-concept fluency, Level 3 is debugging broken configurations, Level 4 is realistic production-style build tasks, and Level 5 is advanced debugging and comprehensive tasks. Each exercise is self-contained with its own setup and verification commands. Debugging exercises include the broken configuration in the setup so you don't have to type it; your job is to identify and fix the problem from the symptoms.

Third, compare your solutions to the answer key. The answers file includes a common-mistakes section that captures the specific traps a topic tends to produce, and a verification cheat sheet worth internalizing. For debugging exercises, the answer key explains not just what was broken but how to diagnose it from kubectl output.

## Repository Layout

```
exercises/                          Numbered by recommended study order
  01-pods/                          Pod spec, config, probes, scheduling, resources, controllers (1-7)
  02-jobs-and-cronjobs/             Batch workloads
  03-statefulsets/                  Stateful workloads, stable identity, headless services
  04-autoscaling/                   HPA, VPA, in-place pod resize
  05-helm/                          Chart install, upgrade, rollback, templates (1-3)
  06-kustomize/                     Overlays, patches, transformers, components (1-3)
  07-storage/                       PV, PVC, StorageClass, dynamic provisioning (1-3)
  08-services/                      ClusterIP, NodePort, LoadBalancer, endpoints (1-3)
  09-coredns/                       DNS resolution, CoreDNS config, debugging (1-3)
  10-network-policies/              Ingress/egress rules, namespace isolation (1-3)
  11-ingress-and-gateway-api/       Ingress v1 and Gateway API with controller diversity (1-5)
  12-rbac/                          Namespace-scoped and cluster-scoped access control (1-2)
  13-security-contexts/             Identity, capabilities, seccomp (1-3)
  14-pod-security/                  Pod Security Standards and Pod Security Admission
  15-crds-and-operators/            CRDs, custom resources, operator pattern (1-3)
  16-admission-controllers/         Built-ins and ValidatingAdmissionPolicy
  17-cluster-lifecycle/             kubeadm, upgrades, etcd backup/restore (1-3)
  18-tls-and-certificates/          Kubernetes PKI, cert creation, Certificates API (1-3)
  19-troubleshooting/               Cross-domain capstone series (1-4)
  20-cluster-setup/                 VM and Raspberry Pi cluster build guides

docs/                               Cluster setup recipes and supporting documentation
.claude/skills/                     Assignment generation pipeline (Claude Code)
```

## Conventions

**Namespace isolation.** Every exercise uses its own namespace, typically `ex-<level>-<exercise>` (for example, `ex-3-2`). Tutorial content uses `tutorial-<topic>`. This prevents accidental interaction between exercises and makes cleanup straightforward.

**No latest tags.** Container images always use explicit version tags. The `latest` tag is avoided because it breaks rollout demonstrations and creates reproducibility problems across runs.

**Imperative and declarative both, honestly labeled.** Where imperative kubectl commands are realistic, they are shown alongside the declarative YAML. Where they are not, the tutorial is explicit that declarative is the only practical path.

**Anti-spoiler debugging exercises.** Exercise headings are bare (`### Exercise 3.1`) rather than titled. This prevents headings from leaking hints about what is broken.

**base64 encoding.** Secret values use `base64 -w0` (one step, no line wrapping).

**No em dashes anywhere.** Commas, periods, or parentheses instead.

**Prose over fragmented bullets.** Explanatory sections use narrative paragraphs. Bullet lists appear where lists genuinely belong.

## Prerequisites

A working local Kubernetes cluster created with kind using the rootless nerdctl provider, a current kubectl client, and familiarity with basic Linux shell usage. The single-node cluster command:

```bash
KIND_EXPERIMENTAL_PROVIDER=nerdctl kind create cluster
```

Multi-node setup (required from exercises/01-pods/assignment-4 onward) is documented in `docs/cluster-setup.md`.

## License

Apache License, Version 2.0. See `LICENSE` for the full text. The prompts, tutorials, homework exercises, and answer keys are all covered by this license and can be reused, modified, and redistributed with attribution.
