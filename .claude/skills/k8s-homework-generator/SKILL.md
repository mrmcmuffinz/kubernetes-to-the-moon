---
name: k8s-homework-generator
description: >
  Use this skill whenever the user asks to generate, create, or build a Kubernetes
  homework assignment from a prompt. This includes requests like "generate the
  assignment from this prompt," "create the homework files," "build the tutorial and
  exercises for Network Policies," or any reference to producing the four-file
  assignment output (README, tutorial, homework, answers). Also trigger when the user
  asks to regenerate or update an existing assignment's content files. This skill
  reads a prompt.md file (produced by the k8s-prompt-builder skill) and generates the
  four deliverable files in the same directory. Always read this skill and its base
  template before generating any assignment files.
---

# Kubernetes Homework Generator

## What This Skill Does

This skill takes a scoped prompt (a `prompt.md` file) and produces four structured
files that together form a complete hands-on Kubernetes homework assignment.
The prompt defines what to cover. This skill defines how to structure, format, and
present that content.

## When to Use

Trigger this skill when the user:

- Asks to generate assignment files from an existing prompt.md
- Asks to create a tutorial, homework, or answer key for a Kubernetes topic
- Asks to regenerate or update the content files for an existing assignment
- References the base template, exercise structure, or four-file output format
- Provides a prompt (inline or as a file) and wants the assignment content produced

## Reference Files

Read this before generating any assignment:

| File | Purpose | When to Read |
|---|---|---|
| `references/base-template.md` | Structural conventions, exercise format, difficulty levels, environment setup, formatting rules | Always |

## Input

The generator expects a `prompt.md` file in the target assignment directory. This file
is produced by the `k8s-prompt-builder` skill and contains:

- Assignment metadata (series, number, prerequisites, CKA domain)
- Scope declaration (in-scope subtopics, out-of-scope deferrals)
- Environment requirements (single-node vs multi-node kind cluster)
- Resource gate (which Kubernetes objects exercises may use)
- Topic-specific conventions
- Cross-references to other assignments

If no prompt.md exists, ask the user to run the prompt builder first or provide the
scope inline.

## Output Contract

The generator produces four files in the same directory as the prompt.md:

| File | Purpose |
|---|---|
| `README.md` | Assignment overview, prerequisites, estimated time, recommended workflow |
| `<topic>-tutorial.md` | Step-by-step tutorial teaching one complete real-world workflow |
| `<topic>-homework.md` | 15 progressive exercises across five difficulty levels |
| `<topic>-homework-answers.md` | Complete solutions with explanations |

The `<topic>` slug must match the directory name (for example, `network-policies`
produces `network-policies-tutorial.md`).

## HOW TO EXECUTE THIS SKILL (IMPORTANT)

**CRITICAL: This skill MUST be executed via the Agent tool, not by directly generating files.**

When the user invokes this skill, you MUST:

1. ✅ **DO THIS**: Spawn an agent with the Agent tool to generate all four files
2. ❌ **DO NOT**: Manually write tutorial.md, homework.md, or answers.md yourself
3. ❌ **DO NOT**: Start generating content inline in the conversation

**Why use an agent:**
- The base-template.md is 500+ lines with detailed quality gates
- Each file is 5,000-15,000 words
- Quality checks require comparing across all 4 files
- Agents have the context window to do this properly

**Correct execution pattern:**
```
User: "Generate troubleshooting assignment-3"
You: <invoke Agent with description="Generate troubleshooting assignment-3" 
           and prompt="Generate assignment using k8s-homework-generator skill...">
```

**Incorrect execution pattern:**
```
User: "Generate troubleshooting assignment-3"
You: "Let me generate the tutorial..." <starts writing content inline>
```

If you catch yourself starting to write tutorial/homework content directly, STOP and spawn an agent instead.

## Generation Process

1. Read the base template from `references/base-template.md` to load all structural
   conventions.

2. Read the prompt.md for this assignment to understand scope, resource gate, and
   topic-specific conventions.

3. Generate the four files in this order:
   - README.md (quick to produce, establishes context)
   - Tutorial (teaches the topic, creates the reference material for exercises)
   - Homework (15 exercises, must not conflict with tutorial resources)
   - Answers (solutions for all 15 exercises, common mistakes, cheat sheet)

4. Write all four files to the assignment directory (for example,
   `exercises/10-network-policies/assignment-1/`).

## Quality Checks

Every check below is a hard gate. The generator must not finalize an assignment
unless every gate passes. The detailed definition of each gate lives in
`references/base-template.md` under "Quality Standards"; this list is the
checklist form.

**Structural:**
- [ ] All four files present and non-empty.
- [ ] Tutorial namespace `tutorial-<topic>`, exercise namespaces `ex-<level>-<exercise>`.
- [ ] No resource-name, user-name, or namespace collisions between tutorial and exercises.
- [ ] All container image tags are explicit versions and verified against the registry.
- [ ] All commands are copy-paste ready with no placeholders.

**README (see base-template section "### 1. README.md"):**
- [ ] Follows the canonical 9-section shape.
- [ ] References cluster setup docs by link instead of inlining cluster creation commands.
- [ ] Uses narrative prose, not a metadata header block or tables-only layout.

**Tutorial (see base-template section "### 2. <topic>-tutorial.md"):**
- [ ] Narrative paragraph flow, not stacked one-sentence paragraphs.
- [ ] Every new resource type has spec fields, valid values, defaults, and
      failure-mode-when-misconfigured documented.
- [ ] Imperative and declarative forms shown together where both are realistic.

**Homework (see base-template section "### 3. <topic>-homework.md" and "Exercise task types"):**
- [ ] Every exercise is a build-or-fix task; no reading-only tasks.
- [ ] Debugging exercises have bare headings; objectives do not telegraph bug count or type.
- [ ] Verification commands use RBAC-style `# expect: yes/no` or specific exact outputs.
- [ ] No `grep -q ... && echo SUCCESS` or `timeout N ... || echo BLOCKED` patterns.
- [ ] No exercise uses resources outside the prompt.md resource gate.

**Answer key (see base-template section "### 4. <topic>-homework-answers.md"):**
- [ ] Every Level 3 and Level 5 debugging answer follows the three-stage structure:
      diagnosis (commands + what to look for), bug explanation, fix.
- [ ] Common Mistakes section present with three or more topic-specific entries.
- [ ] No duplicated YAML (display + heredoc of the same config).
- [ ] Verification Commands Cheat Sheet present.

**Formatting:**
- [ ] No em dashes anywhere.
- [ ] Full replacement files on any update.

If any gate fails, fix it before finalizing or flag the specific gap to the
user and ask for a decision. Do not silently ship output that fails a gate.

## Conventions

All conventions are documented in detail in `references/base-template.md`. The key
points are summarized here for quick reference:

- **Difficulty levels:** 5 levels, 3 exercises each, progressive complexity
- **Anti-spoiler:** Bare exercise headings, no bug counts in objectives
- **Environment:** kind cluster with rootless nerdctl (not Docker)
- **Encoding:** `base64 -w0` for Secrets
- **Images:** Explicit version tags, never `:latest`
- **Formatting:** No em dashes, narrative prose over bullet stacks, Markdown only
- **Namespaces:** `tutorial-<topic>` for tutorial, `ex-<level>-<exercise>` for homework
- **File format:** Markdown with fenced code blocks, self-contained per file
