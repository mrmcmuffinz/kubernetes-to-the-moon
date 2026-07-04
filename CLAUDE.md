# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a CKA (Certified Kubernetes Administrator) exam prep repository containing
hands-on homework assignments. Each assignment consists of a tutorial, a set of 15
progressive exercises, and a complete answer key. The material complements the Mumshad
Mannambeth Udemy CKA course and KodeKloud labs.

## Key Files

- `cka-homework-plan.md` is the master plan. It maps every CKA exam competency to an
  assignment, tracks what has been generated, and defines the generation sequence. Read
  this first when deciding what to work on next.
- `README.md` is the public-facing repo overview for learners.
- `docs/audit-findings.md` and `docs/remediation-plan.md` capture the ongoing audit and
  the phased plan for improving the assignment corpus. Read these when deciding what
  work remains and in what sequence.
- `docs/cluster-setup.md` is the single source of truth for kind cluster configurations
  and the component version matrix. Assignment READMEs and tutorials reference sections
  of this document by anchor rather than inlining cluster commands.
- `LICENSE` is Apache 2.0.

## Skills

Two skills in `.claude/skills/` support the assignment generation pipeline.

**IMPORTANT**: The k8s-homework-generator skill MUST be executed via the Agent tool, not by manually generating content inline. See `.claude/AGENT_DELEGATION_GUIDE.md` for the complete decision tree on when to delegate vs do-it-yourself.

### cka-prompt-builder

Produces topic-level README.md files (scoping how many assignments a topic needs) and
assignment-level prompt.md files (detailed specs for each assignment). It knows the CKA
exam curriculum, the Mumshad course structure, and what assignments already exist. Use
it when the user asks to scope out a topic or build a prompt for a specific assignment.

Reference files in `.claude/skills/cka-prompt-builder/references/`:
- `cka-curriculum.md` has the five CKA domains, their competencies, and exam weights.
  Kept current against `github.com/cncf/curriculum` (v1.35 as of 2026-04-18).
- `course-section-map.md` maps Mumshad course sections (S1-S18) to CKA competencies.
- `assignment-registry.md` tracks every existing and planned assignment with its scope,
  deferrals, and cross-references. Update this file after generating a new prompt.

### k8s-homework-generator

Takes a `prompt.md` and produces four content files (README.md, tutorial, homework,
answers). It encodes all structural conventions: difficulty levels, anti-spoiler rules,
exercise format, environment assumptions.

**IMPORTANT: This skill MUST be executed via the Agent tool.** Each assignment generates
5,000-15,000 words across 4 files with complex quality gates. Do not manually write
tutorial/homework content inline - always spawn an agent to invoke the skill.

Reference file in `.claude/skills/k8s-homework-generator/references/`:
- `base-template.md` has the full structural contract for assignment output with hard
  gates on README shape, narrative prose, resource documentation, debugging answer
  structure, Common Mistakes section, verification form, and exercise task types.

### How to Invoke Skills

Skills are invoked using the `/` prefix in Claude Code:

- `/cka-prompt-builder` - Scope a topic or build a prompt for an assignment
- `/k8s-homework-generator` - Generate the four content files from a prompt

Example workflow:
```
User: "Scope out the Network Policies topic"
→ /cka-prompt-builder reads references, produces exercises/10-network-policies/README.md

User: "Generate prompt for Network Policies assignment 1"
→ /cka-prompt-builder produces exercises/10-network-policies/assignment-1/prompt.md

User: "Generate the assignment from that prompt"
→ /k8s-homework-generator produces the 4 content files
```

### Generation Workflow

1. User asks to scope out a topic (for example, "scope out Network Policies").
2. The `cka-prompt-builder` skill reads its reference files and produces a topic-level
   `README.md` at `exercises/<topic>/README.md` that determines how many assignments
   the topic needs and what each covers at a high level.
3. User reviews and approves the scoping.
4. User asks for a prompt for a specific assignment (for example, "generate the prompt
   for Network Policies assignment 1").
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

.claude/skills/                     Claude Code skills for assignment generation
docs/                               Audit, remediation plan, cluster setup recipes
```

Each topic directory contains a topic-level `README.md` that scopes the number of
assignments and what each covers. Each assignment subdirectory contains five files:
`prompt.md` (the generation input), `README.md` (assignment overview for the learner),
`<topic>-tutorial.md`, `<topic>-homework.md`, `<topic>-homework-answers.md`. Every
assignment in the corpus is content-complete as of 2026-04-19. All six remediation
phases are complete and the plan is closed.

## Environment

- Kind cluster with rootless containerd via nerdctl (not Docker)
- Exam target Kubernetes version: v1.35 (per `CKA_Curriculum_v1.35.pdf`)
- Single-node cluster for most topics; multi-node (1 control-plane, 3 workers) for
  scheduling, controllers, networking, and troubleshooting
- All cluster creation commands and component install commands are documented in
  `docs/cluster-setup.md` with pinned versions verified against upstream
  documentation

## Common Tasks

- **Find the next piece of work**: Read `docs/remediation-plan.md` for phase-level
  status and task-level detail, or `cka-homework-plan.md` for the high-level
  coverage matrix.
- **Scope a new topic**: Use `/cka-prompt-builder` with the topic name.
- **Generate an assignment**: First create the prompt (if not present), then run
  `/k8s-homework-generator`.
- **Update the registry**: After generating, edit
  `.claude/skills/cka-prompt-builder/references/assignment-registry.md`.
- **Test an assignment**: Create the required cluster per `docs/cluster-setup.md`.
- **Verify an external component version**: Fetch the project's official releases
  page or documentation; do not rely on general knowledge (per `docs/remediation-plan.md`
  decision D7).

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
  to all CKA resources. This prevents exercises from assuming knowledge the learner
  doesn't yet have.

## Existing Content and Quality Bar

The pod series (assignments 1-7) and RBAC assignment-1 were generated before the skills
existed, using standalone prompts. They follow the conventions the skills now encode
and are the reference quality bar: `01-pods/assignment-1` is named in `base-template.md`
as the canonical reference for README shape, tutorial narrative style, and answer-key
debugging structure. Do not regenerate these through the skills.

All 19 Phase 4 skill-generated assignments (security-contexts/1-3, storage/1-3,
ingress-and-gateway-api/1-5, plus the earlier batch: rbac/2, jobs-and-cronjobs/1,
autoscaling/1, statefulsets/1, admission-controllers/1, pod-security/1,
troubleshooting/2, troubleshooting/4) now satisfy the same hard gates that
`01-pods/assignment-1` set. They are additional reference examples of what the
quality bar looks like when applied by the skill. The remaining skill-generated
assignments (helm/1-3, kustomize/1-3, crds-and-operators/1-3, tls-and-
certificates/1-3, cluster-lifecycle/1-3, services/1-3, coredns/1-3,
network-policies/1-3, troubleshooting/1 and /3) predate the Phase 2 hard gates
and may be regenerated in the future if a quality gap surfaces; none is
currently queued.

## Generation Sequence

The original `cka-homework-plan.md` Generation Sequence is historical; all 38
original-scope assignments were generated under that sequence. The subsequent
plan of work was captured in `docs/remediation-plan.md`. All six phases
(infrastructure fixes, skill strengthening, topic scoping, content generation,
technique weaving, verification and housekeeping) are complete as of
2026-04-19. The remediation plan is closed.
