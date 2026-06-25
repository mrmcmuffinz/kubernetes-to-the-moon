# Day Worksheet Style Guide

How the per-day CKA prep worksheets are written. Distilled from the iterative review of
`cka-day-0.md` and `cka-day-1.md`. The WHAT of each day (topics and order) is the per-day
worksheets themselves; speed targets and the gap categorization live in
`cka-simulator-a-remediation-plan.md`, and the corpus mapping lives in `readiness-assessment.md`.
This file is the HOW, and it is the contract for generating the day worksheets.

## Principles (the collected feedback)

1. **Reuse, never reinvent.** If a skill is covered in `exercises/`, point to that homework
   file and use its own exercise numbers (for example "Exercise 1.1"). No parallel
   numbering (no A1/B1), and no paraphrasing of the task that the linked file already states.
2. **Reference the exact homework file**, not the assignment directory.
3. **Be explicit.** Name specific exercise numbers; never "a couple of reps." State quantity
   and any stop-condition. When selecting a subset, let the block header carry the theme so
   the selection is self-evident; do not annotate each number with a description.
4. **Original content only when nothing in the corpus fits.** Then it is a concrete task
   with explicit specs (names, images, labels, ports, keys), an explicit confirm command,
   and a pass condition. Document the setup, never the answer.
5. **Anti-spoiler.** Attempt cold against the exercise's own Verification and Expected
   sections; open the answer key only after a genuine attempt.
6. **Environment-aware.** Name the cluster each exercise needs and point at documented setup
   (`docs/cluster-setup.md` or the corpus tutorial), never reinvented install steps.
   Available environments: single-node kind (throwaway), a 2-node VM kubeadm cluster, a
   3-node Pi kubeadm cluster (2 workers). Multi-node exercises go on the VM or Pi;
   NetworkPolicy needs the Calico cluster; kubeadm upgrade/join stays on killercoda or a
   throwaway; the Pi is a sanctioned practice venue but its comparative-install project is
   off-limits until after the exam.
7. **Prefer the corpus over Killer.sh-mirror scenarios** when the corpus covers the skill
   and runs on the user's own cluster with answer keys. The exact Killer.sh scenarios are
   deferred to the timed Session 2 on Day 5.
8. **Lean and scannable.** Checkbox lists. A short intro (the day's goal, its place in the
   arc, a rough time guide). A `Source:` line then bare exercise numbers, grouped into themed
   blocks. Setup as its own labeled section. A short check-in tied to the day's key skill or
   trap. No em dashes; use prose where prose fits, not stacked single-sentence bullets.

## Per-day file skeleton

- Title: `# CKA Day N (<weekday>, <Month day>) | <topic>`
- Intro: two or three sentences. The day's goal, where it sits in the arc, and the one trap
  or skill that matters most.
- One-time setup (only if needed): documented pointers, not answers.
- Blocks: each a themed group with a `Source:` line and bare exercise numbers. Add a short
  skip-note only when a subset needs explaining, with the reason.
- Original tasks (only when no corpus exercise fits): explicit spec, confirm command, pass
  condition.
- Check-in: the honest question for the day, tied to the skill or trap and the verify bar.

## How to pick the specific exercises

The map in `readiness-assessment.md` is assignment-level. Pick the specific exercise numbers
by reading the homework file's `### Exercise` objectives, the way Day 1 resolved to
assignment-4 Exercises 1.1/2.1/2.2/2.3 rather than the whole file. Note the Q13 correction:
the readiness map called assignment-5 the "direct match" for Q13, but reading it showed it
uses the Ingress2Gateway CLI, so assignment-4's hand-written header matching was the right
target. Always confirm against the file, not the map.

## Sources

- Day topics and order: the `cka-day-0.md` through `cka-day-9.md` worksheets. Speed targets
  and gap categorization: `cka-simulator-a-remediation-plan.md`.
- Corpus mapping and the environment matrix: `readiness-assessment.md`.
- The reference worksheets already in this style: `cka-day-0.md` and `cka-day-1.md`.
