---
name: k8s-prompt-builder
description: >
  Use this skill whenever the user asks to create, build, draft, or generate a homework
  prompt for a Kubernetes topic, or to scope out how many assignments a topic needs. This
  includes requests like "build me a prompt for Supply Chain Security," "scope out the
  Runtime Security topic," "how many assignments does Cluster Hardening need," "what should
  the OPA/Gatekeeper assignment cover," "generate the next assignment prompt," or any
  reference to creating scoped prompts for new exercises in this repository. Also trigger
  when the user asks which assignment to generate next, what topics are remaining, or how
  a Kubernetes competency maps to an assignment. This skill produces topic-level README.md
  files (scoping) and assignment-level prompt.md files (detailed specs) that the
  k8s-homework-generator skill later consumes. Always read this skill before writing any
  README.md or prompt.md file or advising on assignment scoping.
---

# Kubernetes Prompt Builder

## What This Skill Does

This skill handles two related tasks in the assignment generation pipeline:

1. **Topic scoping:** Produces a topic-level `README.md` at `exercises/<topic>/README.md`
   that determines how many assignments a topic needs and describes what each one covers
   at a high level.

2. **Prompt writing:** Produces detailed `prompt.md` files for individual assignments
   within a topic, specifying exact subtopics, resource gates, and exercise conventions.

The prompt builder does the domain-knowledge work: it knows the existing assignment corpus,
understands the Kubernetes topic landscape (including CKA, CKAD, and CKS material), tracks
what other assignments already exist, and decomposes broad topics into focused,
non-overlapping scopes. The user does not need deep expertise in a topic to get a
well-scoped prompt. They just need to know the topic area and optionally which subtopics
they want emphasized.

## When to Use

Trigger this skill when the user:

- Asks to scope out a topic ("how many assignments does Supply Chain Security need")
- Asks to create or generate a prompt for any Kubernetes topic
- Asks what the next assignment to generate should be
- Asks how to decompose a broad topic into assignment-sized pieces
- Asks which Kubernetes competencies or topic areas are not yet covered
- Wants to review or adjust the scope of a planned assignment before generating it
- References the assignment registry or asks what topics are planned

## Reference Files

Read these before producing any topic README or prompt:

| File | Purpose | When to Read |
|---|---|---|
| `references/assignment-registry.md` | Tracks all existing and planned assignments with scope | Always |
| `references/cka-curriculum.md` | CKA exam domains and competencies; also a useful map of core Kubernetes topics | For topics in exercises 01-19 (original CKA corpus) |
| `references/course-section-map.md` | Maps Mumshad course sections to Kubernetes competencies | For topics covered by the Mumshad CKA course; skip for new CKS/CKAD-specific topics |

## Two-Step Output

### Step 1: Topic README (scoping)

The topic README lives at `exercises/<topic>/README.md` and is the authoritative
document for how a topic is decomposed into assignments. It must be produced (or
confirmed to exist) before any prompt.md is written for that topic.

The topic README must contain:

1. **Topic title and domain mapping** with the specific competencies or skill areas covered
2. **Rationale for the number of assignments** explaining why the topic warrants
   one, two, or more assignments. The rationale should reference the subtopic count,
   the breadth of the competencies involved, and whether natural breakpoints exist in
   the material.
3. **Assignment summary table** listing each assignment with a short description of
   what it covers and its prerequisites
4. **Scope boundaries** stating what is explicitly not covered by this topic and
   which other topic handles it
5. **Cluster requirements** noting whether assignments in this topic need single-node
   or multi-node kind clusters, any special configuration (CNI, ingress controller,
   Falco, Gatekeeper, etc.)
6. **Recommended order** if assignments within the topic build on each other

**Sizing guidance for the decomposition:**

- Each assignment produces 15 exercises across five difficulty levels (3 per level).
- Each distinct subtopic should map to at least 2-3 exercises.
- **Default to 3+ focused assignments per topic** where the scope supports it. The user
  prefers depth over breadth, with each assignment covering 5-6 core subtopics rather
  than cramming 12-15 subtopics into a single dense assignment.
- A topic with 15-18 distinct subtopics should split into three assignments (5-6 subtopics each).
- A topic with 18-24 subtopics should split into four assignments.
- A topic with 8-12 subtopics may warrant two assignments if natural breakpoints exist.
- Very narrow topics (fewer than 8 subtopics) may be single assignments, but this should
  be the exception, not the default.
- Natural breakpoints for progressive learning (fundamentals, advanced patterns, debugging
  or integration) should guide the decomposition.
- When in doubt, prefer more focused assignments over fewer dense ones.

### Step 2: Assignment Prompt (detailed spec)

The prompt lives at `exercises/<topic>/assignment-N/prompt.md` and defines exactly
what a single assignment should cover. The prompt builder writes this only after the
topic README exists and the number of assignments has been determined.

The prompt.md must contain:

1. **Header block** with assignment metadata (series name, assignment number, prerequisites,
   topic domain and competencies covered, any relevant course or certification reference)

2. **Scope declaration** with two clearly separated sections:
   - "In scope for this assignment" listing every subtopic, concept, and kubectl skill
     that exercises should cover, organized by logical grouping
   - "Out of scope" listing related topics explicitly deferred to other assignments,
     with forward references to which assignment covers them

3. **Environment requirements** specifying whether the assignment needs a single-node or
   multi-node kind cluster, any special kind configuration, and any tools beyond kubectl
   (Falco, OPA/Gatekeeper, Trivy, Cosign, gVisor, etc.)

4. **Resource gate** listing which Kubernetes resource types exercises are permitted to
   use. For assignments early in the curriculum (before networking topics), this is a
   restricted list. For later assignments, this is "all Kubernetes resources."

5. **Topic-specific conventions** capturing anything unique to this topic that the
   homework generator needs to know (for example, security topics may need specific kernel
   or node access requirements; supply chain topics may need registry access; runtime
   sandboxing topics need RuntimeClass and node-level configuration)

6. **Cross-references** with backward references to prerequisites ("this assignment
   assumes the learner has completed...") and forward references to future assignments
   ("the following topics are deferred to...")

## Prompt Construction Process

When building a topic README or prompt, follow these steps:

1. Read `assignment-registry.md` to understand the current state of the corpus: what
   exists, what is planned, and what each existing assignment covers.

2. Identify the topic area. For topics in exercises 01-19 (original CKA corpus), consult
   `cka-curriculum.md` to map competencies. For new topics (container images, cluster
   hardening, supply chain security, runtime sandboxing, OPA/Gatekeeper, runtime security,
   secrets management, system hardening), use the topic's own domain knowledge and the
   registry's planned-topic entries as the scope anchor.

3. Check `assignment-registry.md` to see what adjacent assignments already cover. This
   prevents overlap. If a subtopic is already covered elsewhere, defer it explicitly
   with a cross-reference.

4. Consult `course-section-map.md` if the topic is covered by the Mumshad CKA course.
   For new topics beyond the original CKA scope, this file will not have relevant
   entries and can be skipped.

5. **For topic READMEs:** Enumerate all subtopics for the topic, count them, identify
   natural breakpoints, and determine the number of assignments. Write the topic README
   with the rationale and assignment summary.

6. **For prompts:** Decompose the assignment's portion of the topic into subtopics at
   exercise granularity. Each subtopic should map to at least 2-3 exercises across the
   five difficulty levels.

7. Determine the resource gate. If the assignment is early in the curriculum (before
   networking topics), list permitted resources explicitly. If it comes after the
   networking section, state "all Kubernetes resources are in scope."

8. **Scope drift check (prompts only).** Before writing the prompt, compare the
   subtopic list you are about to include against what the topic README scoped for
   this assignment. Count the subtopics. If the count exceeds 7-8 subtopics for a
   single assignment, or includes subtopics that belong to a different assignment
   in the topic's decomposition, stop and flag the drift to the user. Present three
   options:
   - Trim the prompt's scope to fit the topic README's original decomposition (5-6 subtopics)
   - Split the assignment into two (which requires updating the topic README first)
   - Expand the current assignment's scope in the topic README with justification
   Do not write the prompt until the user has chosen an approach and the topic README
   is consistent with the decision.

9. Write the file following the output contract above.

10. After writing, update `assignment-registry.md` to reflect any new information.
    If the topic README was modified in step 8, ensure the assignment registry's
    planned scope entries match the updated decomposition.

## Quality Checks

Before finalizing a topic README, verify:

- The subtopic count justifies the proposed number of assignments
- The assignment summary table accounts for all competencies the topic covers
- Scope boundaries clearly state what is not covered and where it lives
- No overlap with other topic READMEs

Before finalizing a prompt, verify:

- The topic README exists and the prompt is consistent with its assignment summary
- The prompt's subtopic count falls within the topic README's scoped range for this
  assignment. If it does not, the scope drift check in step 8 must have been resolved
  before reaching this point.
- Every competency listed in the header block has at least one matching subtopic
  in the scope declaration
- No subtopic overlaps with an existing assignment's scope (check the registry)
- The resource gate is consistent with the assignment's position in the curriculum
- Forward and backward references point to real assignments that exist or are planned
- The scope targets 5-6 core subtopics (sufficient for 15 exercises across five levels
  with 2-3 exercises per subtopic). Assignments with 8+ subtopics should be flagged for
  potential splitting.
- Topic-specific conventions include everything the homework generator would need to
  know that is not in the base template (environment setup, special tools, gotchas)
- If the topic README was updated during this process, verify the updated README is
  written to disk before the prompt is finalized

## Conventions

- No em dashes anywhere. Use commas, periods, or parentheses.
- Narrative paragraph flow in prose sections, not stacked single-sentence declarations.
- Use the same topic slug for directory names and file prefixes (for example,
  "supply-chain-security" in both the directory path and the file names).
- Subtopic lists in the scope declaration should be grouped logically and use italicized
  group headers, matching the format established in the pod series prompts.
