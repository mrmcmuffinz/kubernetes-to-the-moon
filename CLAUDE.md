# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a hands-on Kubernetes learning repository. Each assignment consists of a tutorial,
a set of 15 progressive exercises, and a complete answer key. Topics cover core Kubernetes
operations through advanced security and cluster hardening. The corpus started as CKA exam
prep (exercises 01-19) and is expanding to cover CKAD and CKS material as additional topics.

## Key Files

- `cka-homework-plan.md` is a historical document capturing the original CKA coverage matrix
  and generation sequence. It is no longer the active plan but is useful for understanding
  what the original 45 assignments cover and how they were sequenced.
- `.claude/skills/cka-prompt-builder/references/assignment-registry.md` is the live registry
  of every existing and planned assignment. Read this when deciding what exists and what to
  add next.
- `README.md` is the public-facing repo overview.
- `LICENSE` is Apache 2.0.

## Skills

Two skills in `.claude/skills/` support the assignment generation pipeline.

**IMPORTANT**: The k8s-homework-generator skill MUST be executed via the Agent tool, not by
manually generating content inline. See `.claude/AGENT_DELEGATION_GUIDE.md` for the complete
decision tree on when to delegate vs do-it-yourself.

### k8s-prompt-builder

Produces topic-level README.md files (scoping how many assignments a topic needs) and
assignment-level prompt.md files (detailed specs for each assignment). It knows the existing
assignment corpus and Kubernetes topic structure across CKA, CKAD, and CKS material. Use it
when scoping a new topic or building a prompt for a specific assignment.

Reference files in `.claude/skills/k8s-prompt-builder/references/`:
- `cka-curriculum.md` has the CKA exam domains and competencies. Also useful as a reference
  for Kubernetes topic coverage even beyond the exam context.
- `course-section-map.md` maps Mumshad course sections (S1-S18) to Kubernetes competencies.
- `assignment-registry.md` tracks every existing and planned assignment with its scope,
  deferrals, and cross-references. Update this file after generating a new prompt.

### k8s-homework-generator

Takes a `prompt.md` and produces four content files (README.md, tutorial, homework, answers).
It encodes all structural conventions: difficulty levels, anti-spoiler rules, exercise format,
environment assumptions.

**IMPORTANT: This skill MUST be executed via the Agent tool.** Each assignment generates
5,000-15,000 words across 4 files with complex quality gates. Do not manually write
tutorial/homework content inline - always spawn an agent to invoke the skill.

Reference file in `.claude/skills/k8s-homework-generator/references/`:
- `base-template.md` has the full structural contract for assignment output with hard gates
  on README shape, narrative prose, resource documentation, debugging answer structure,
  Common Mistakes section, verification form, and exercise task types.

### How to Invoke Skills

Skills are invoked using the `/` prefix in Claude Code:

- `/k8s-prompt-builder` - Scope a topic or build a prompt for an assignment
- `/k8s-homework-generator` - Generate the four content files from a prompt

Example workflow:
```
User: "Scope out the Supply Chain Security topic"
→ /k8s-prompt-builder reads references, produces exercises/22-supply-chain-security/README.md

User: "Generate prompt for Supply Chain Security assignment 1"
→ /k8s-prompt-builder produces exercises/22-supply-chain-security/assignment-1/prompt.md

User: "Generate the assignment from that prompt"
→ /k8s-homework-generator produces the 4 content files
```

### Generation Workflow

1. User asks to scope out a topic.
2. The `cka-prompt-builder` skill reads its reference files and produces a topic-level
   `README.md` at `exercises/<topic>/README.md` that determines how many assignments the
   topic needs and what each covers at a high level.
3. User reviews and approves the scoping.
4. User asks for a prompt for a specific assignment.
5. The `cka-prompt-builder` skill produces a `prompt.md` in the target directory.
6. User reviews and approves the prompt.
7. The `k8s-homework-generator` skill reads the prompt.md and `base-template.md`, then
   produces four files in the same directory.
8. Update `assignment-registry.md` to reflect the new assignment's status.

## Directory Structure

```
exercises/                          Numbered by recommended study order
  01-pods/1-7                       Pod-focused series
  02-jobs-and-cronjobs/1            Batch workloads
  03-statefulsets/1                 Stateful workloads
  04-autoscaling/1                  HPA, VPA, in-place pod resize
  05-helm/1-3                       Chart install, upgrade, rollback, templates
  06-kustomize/1-3                  Overlays, patches, transformers
  07-storage/1-3                    PV, PVC, StorageClass, dynamic provisioning
  08-services/1-3                   ClusterIP, NodePort, LoadBalancer, patterns
  09-coredns/1-3                    DNS, CoreDNS config, debugging
  10-network-policies/1-3           Ingress/egress rules, debugging
  11-ingress-and-gateway-api/1-5    Ingress v1 and Gateway API with controller diversity
  12-rbac/1-2                       RBAC namespace- and cluster-scoped
  13-security-contexts/1-3          Identity, capabilities, seccomp + readOnlyRootFilesystem
  14-pod-security/1                 Pod Security Standards and PSA
  15-crds-and-operators/1-3         CRDs, custom resources, operators
  16-admission-controllers/1        Built-ins and ValidatingAdmissionPolicy
  17-cluster-lifecycle/1-3          kubeadm, upgrades, etcd
  18-tls-and-certificates/1-3       K8s PKI, cert creation, Certificates API
  19-troubleshooting/1-4            Cross-domain capstone series
  20-cluster-setup/                 VM and Raspberry Pi cluster build guides (not assignment-format)
  21+                               New topics: container images, cluster hardening, supply chain
                                    security, runtime sandboxing, OPA/Gatekeeper, runtime security,
                                    secrets management, system hardening

.claude/skills/                     Claude Code skills for assignment generation
```

Each topic directory contains a topic-level `README.md` that scopes the number of assignments
and what each covers. Each assignment subdirectory contains five files: `prompt.md` (the
generation input), `README.md` (assignment overview for the learner), `<topic>-tutorial.md`,
`<topic>-homework.md`, `<topic>-homework-answers.md`. All exercises 01-19 are content-complete.

## Environment

- Kind cluster with rootless containerd via nerdctl (not Docker)
- Target Kubernetes version: v1.35
- Single-node cluster for most topics; multi-node (1 control-plane, 3 workers) for
  scheduling, controllers, networking, and troubleshooting
- Cluster creation commands are in `exercises/20-cluster-setup/` for VM/Pi clusters
  and in individual assignment READMEs for kind clusters

## Common Tasks

- **Find what topics exist**: Read `assignment-registry.md`.
- **Scope a new topic**: Use `/k8s-prompt-builder` with the topic name.
- **Generate an assignment**: First create the prompt (if not present), then run
  `/k8s-homework-generator`.
- **Update the registry**: After generating, edit
  `.claude/skills/cka-prompt-builder/references/assignment-registry.md`.
- **Verify an external component version**: Fetch the project's official releases page or
  documentation; do not rely on general knowledge.

## Quality Bar

The canonical reference for assignment quality is `01-pods/assignment-1`. It sets the
standard for README shape, tutorial narrative style, and answer-key debugging structure.
The `base-template.md` file codifies these conventions as hard gates.

Assignments in exercises 01-14, plus security-contexts/1-3, storage/1-3,
ingress-and-gateway-api/1-5, rbac/2, jobs-and-cronjobs/1, autoscaling/1, statefulsets/1,
admission-controllers/1, pod-security/1, troubleshooting/2, and troubleshooting/4 all
satisfy the full gate set. New assignments generated through the skills pipeline must also
satisfy it.

## Conventions

- No em dashes anywhere. Use commas, periods, or parentheses.
- Narrative paragraph flow in prose, not stacked single-sentence bullets.
- All Markdown, no other document formats.
- Container images use explicit version tags, never `:latest`.
- `base64 -w0` for Secret encoding.
- Exercise namespaces follow `ex-<level>-<exercise>` pattern (for example, `ex-3-2`).
- Tutorial namespaces follow `tutorial-<topic>` pattern.
- Debugging exercise headings are bare (`### Exercise 3.1`) with no descriptive titles
  that would hint at the problem.
- Full file replacements when updating, never patches or diffs.
- **Resource gates** constrain which Kubernetes objects exercises can reference. Early
  assignments (before Networking) use explicit allowlists. Later assignments have access
  to the full resource set. This prevents exercises from assuming knowledge the learner
  does not yet have.
