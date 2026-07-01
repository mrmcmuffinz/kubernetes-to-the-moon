# CKA Killer.sh Simulator B: Remediation Plan (Post-Retake)

**Source scores:** First attempt 46/93 (49.5%, Low Score, 2026-06-26). Retake 79/93 (85%, High Score, 2026-06-27).
**This document supersedes `cka-simulator-b-remediation-plan.md`** (the first-attempt plan, five revisions, ending with the missed-the-visible-answer diagnosis on Q6) as the active remediation reference. The first-attempt plan's diagnoses and fixes are not discarded, they're confirmed: every fix it called for (Q1's read-back habit, Q3's certificate distinction, Q6's reading discipline, Q9's nodeName mechanism, Q10/Q11's structural fluency, Q12's nodeSelector approach) either held completely or moved the needle exactly as predicted. This document covers what the retake actually surfaced: the time cascade is gone, and the remaining work is narrower and different in kind.
**Target:** at least 90% on the real CKA exam. The retake landed at 85%, and the arithmetic below shows the gap to 90% is almost entirely typo- and omission-class, not knowledge gaps.
**Companion documents:** `cka-simulator-b-retake-results.md` (this retake's subtask-level transcription with direct account folded in), `cka-simulator-b-results.md` and `cka-simulator-b-remediation-plan.md` (first-attempt artifacts, retained as the historical record of what was fixed), `killer-sh-cka-simulator-b-solutions.md` (official solutions, still the cross-check reference), `cka-pre-exam-daily-plan.md` (the schedule this plan still needs to update).

---

## The Headline Finding: the Cascade Is Solved

Every question from Q12 through Q17 was reached and attempted this time. Six questions that scored a flat zero from never being reached on the first attempt (Q9, Q12, Q13, Q14, Q15, Q16) scored 9/10, 6/6, 10/11, 4/5, 2/3, and 1/2 respectively on the retake. This confirms the first-attempt plan's central hypothesis exactly as stated: fixing the time cost on Q1, Q3, Q6, Q10, and Q11 was the actual lever, not direct work on the cascade topics themselves. That hypothesis held.

This changes what kind of plan this needs to be. The first-attempt plan was about preventing a clock failure. This plan is about closing a small number of specific, now well-understood gaps on a result that's already close to target.

---

## The Arithmetic

| Category | Subtasks | What it means |
|---|---|---|
| Full marks, held or newly closed | 39 | No action needed beyond the fluency check on Q10/Q12 below |
| Typo/omission/procedural misses | 8 | Fixing these alone reaches 87/93 (93.5%) |
| Genuine conceptual gaps | 6 | Q16 (1 subtask) and Q17 (5 subtasks) |
| Current score | 79/93 (85%) | |
| Score if only typo-class fixed | 87/93 (93.5%) | Past target without touching Q16 or Q17 |
| Score if everything fixed | 93/93 (100%) | |

The practical implication: closing Q16 and Q17 is valuable and should happen, since they're real gaps and the real exam won't repeat this exact question set, but they are not what stands between this result and a 90%+ target. The typo-class fixes are. This reverses the first attempt's priority order, where the biggest lever was time allocation; here the biggest lever is care.

---

## Priority 1: The Typo/Omission/Procedural Cluster (8 subtasks, reaches 93.5% alone)

These six items share a structure worth naming once, since the same underlying fix applies to all of them: in every case, the correct mechanism or pattern was demonstrably known and applied, and the specific execution had one small, identifiable defect. This is the same category as the first attempt's Q1 DNS_2 finding (a caught-too-late typo), now showing up more broadly across a full run rather than on one isolated question.

**Q1, DNS_3 and DNS_4 (2 subtasks plus the dependent deployment-values check).** DNS_3 used the correct hostname-and-subdomain *pattern* but misspelled the namespace (`lime-workload` for `lima-workload`) and omitted the `.section` subdomain segment. DNS_4 used the wrong pattern's namespace and suffix entirely. Both are evidence the underlying DNS mechanisms from the first-attempt remediation were learned; the values typed into them were wrong. Fix: the same read-back habit drilled for DNS_2 last round, generalized to every FQDN-constructing subtask, not just the one that previously failed. A useful concrete check: count the dot-separated segments and read each one against the question's stated namespace and resource names before submitting, every time, not just on suspicion.

**Q2, wrong image tag (1 subtask).** `nginx:1` instead of `nginx:1-alpine`. A previously full-mark question. No conceptual content here at all; this is a recall/typing slip on a value that was almost certainly typed correctly many times before in this same prep cycle. Fix: same read-back principle, applied specifically to image tags, since `image:tag` strings are an easy place for a suffix to silently drop.

**Q9, scheduler restart timing (1 subtask).** The manifest-out, manifest-back-in sequence was correct in structure; the wait between the two steps was too short, leaving the scheduler with the same start time as the apiserver. Fix: after moving the manifest out, explicitly wait for the static pod to be confirmed gone (`watch crictl ps` or `kubectl -n kube-system get pod` showing it absent) before moving the manifest back in. Don't move it back on a fixed count or a guess; wait for the confirmation.

**Q13, one missing volumeMount (1 subtask, the largest single point value on this list).** Containers `c2` and `c3` both had the shared volume mounted; `c1` didn't. The likely mechanical cause: `c1` was the original base pod (built via `kubectl run --dry-run=client`) before the multi-container and shared-volume requirements were added, and the volumeMount addition that got applied to `c2` and `c3` as they were added didn't get back-applied to `c1`. Fix: when retrofitting a requirement onto an existing base object plus newly added objects, explicitly check the base object last, since it's the one most likely to be forgotten precisely because it already existed before the new requirement was introduced.

**Q14, missing leading hyphen (1 subtask).** `cka8448` instead of `-cka8448`. This exact detail was named during the first-attempt remediation's review of the official solution and still got missed in live execution. Fix: this is worth flagging as a case where knowing a detail in review doesn't guarantee applying it under pressure; the actual fix is the same read-back habit, applied even to short-answer questions that feel low-stakes enough to rush.

**Q15, alias not expanded inside a script (1 subtask).** `k get events` instead of `kubectl get events` inside `cluster_events.sh`. This is a new and useful general rule, not specific to this question: shell aliases configured for interactive use (`k` for `kubectl`) do not exist inside non-interactively executed scripts. Fix: any command written into a file meant to be run as a script must use the full command name, never the interactive alias, as a blanket rule rather than something to remember per-question.

---

## Priority 2: Genuine Conceptual Gaps (6 subtasks)

These two are real gaps, not typos, and need actual learning rather than a verification habit.

### Q16, misunderstanding what "namespaced resources" means as a deliverable (1 subtask)

**What happened:** `/opt/course/16/resources.txt` was filled with namespace names and pod names rather than namespaced resource *type* names. The question wants `kubectl api-resources --namespaced -o name`, a list of type strings like `pods`, `secrets`, `deployments`, `persistentvolumeclaims`. This is a vocabulary-level miss: "namespaced resources" in Kubernetes terminology means "resource types that are scoped to a namespace" (as opposed to cluster-scoped types like `nodes` or `namespaces` themselves), not "the resources that exist inside a particular namespace."

**Fix:** read the `kubectl api-resources` section of the kubectl reference, specifically the `--namespaced` flag, and drill the distinction between a resource *type* (`pods`, plural, lowercase, no specific instance) and a resource *instance* (an actual Pod named `my-app-xyz` running somewhere). Practice generating the namespaced-type list from a cold start (`kubectl api-resources --namespaced -o name`) until "namespaced resources" reliably triggers "type list," not "things in this namespace." Speed target: under 2 minutes, since this is a single command once the vocabulary is correct.

### Q17, CRD-definition vs. CRD-instance confusion (5 subtasks, the full miss on this question)

**What happened, by direct account:** the RBAC half of this question (adding `list` permission to `operator-role` for the relevant CRDs, then `kubectl rollout restart` on the operator's Deployment so the running pod picks up the new permissions) was correctly understood the whole time. The blocker was the second half: adding a new Student custom-resource instance. This was misread as needing to modify `base/crd.yaml`, the file that defines the Student *type itself* (the `CustomResourceDefinition` schema), when the actual target was `base/students.yaml`, the file holding actual Student *instances*, where three Students already existed as a ready-made template to copy. Time ran out while this confusion was being worked through, before the correct file was identified.

**The distinction to internalize.** A `CustomResourceDefinition` is the schema: it tells the cluster "a kind called `Student` exists, and here's what fields it can have." This is analogous to a class definition in programming, or to the OpenAPI schema for a built-in Kubernetes object like `Pod`. An *instance* of that kind, an actual object with `kind: Student` and a specific `name` and `spec`, is analogous to creating one more object of an already-defined kind, structurally identical to adding a fourth Pod to a list of three existing Pods. Creating a new instance of an existing CRD never requires touching the CRD definition at all, the same way creating a new Pod never requires editing the Pod API's schema.

**The trigger to build:** the question to ask on sight is "am I being asked to make Kubernetes understand a *new kind* of object, or to create *one more object of a kind that already works*?" If three Students already exist and the task is "add a fourth," that's always the second case, and the fix is always: find an existing instance, copy its shape, change the name and spec values, done. The CRD definition is correct and complete already, since it's already successfully validating three working Students; there is no reason to open it.

**Remediation:** on a scratch cluster, deliberately practice this exact pattern at least twice: install or write a simple CRD (or reuse this question's Student/Class CRDs if they're recoverable from the Killer.sh environment), confirm several instances already exist, then add a new instance by copying an existing one's YAML shape into the instances file (not the definition file) and changing only the name and spec values. Do this once with the CRD instances colocated in a single multi-document YAML file (as in this question) and once with each instance in its own file, to confirm the skill generalizes across file layouts. Speed target: under 3 minutes once the instances file is correctly identified, since the actual edit is a copy-paste-and-rename.

---

## Priority 3: A Smaller Finding Worth Tracking (Not a Lost Point, But a Time Cost)

### Q14's CNI config path, found by filesystem search instead of recall

**What happened, by direct account:** time was spent locating the CNI plugin's config file not because the CNI itself was unfamiliar, but because its config path wasn't known directly. The method used, describing a CNI-related pod, reading its volume mounts, and running `ls -l` on each mounted path until the conflist file turned up, is a real and valid debugging technique, but it's slow by construction for something that has one fixed, well-known answer: `/etc/cni/net.d/` is the kubelet's default CNI configuration lookup directory on essentially every cluster setup.

**Why this matters even though it didn't cost a point on this attempt.** This kind of "solve it the hard way because the fast way wasn't memorized" pattern is exactly what fed the original time cascade on the first attempt, just smaller in scale here. It's worth treating as a leading indicator: a few more of these scattered across a real exam attempt, each costing two or three minutes instead of fifteen seconds, could reproduce a version of the original problem without any single dramatic failure pointing at why.

**Fix:** memorize `/etc/cni/net.d/` as the fixed answer to "where does the kubelet look for CNI config" the same way `/etc/kubernetes/manifests/` is already memorized as the fixed answer for static pod manifests. Build a short list of these fixed, no-derivation-needed paths (CNI config, static pod manifests, kubelet PKI directory for certs, kubeadm config) and drill them as a flashcard-style set rather than relying on being able to find them when needed.

---

## Priority 4: Fluency Checks on Full-Mark Questions (Q10, Q12)

Both Q10 (StorageClass/PVC/Job) and Q12 (control-plane-only scheduling) scored full marks on this retake, and both involved a kubernetes.io documentation lookup, by direct account, for PVC creation syntax and node affinity/toleration syntax respectively. This is the same review question already established for the first attempt's `kubectl explain` findings on Q10/Q11: a correct result with a documentation assist is not a problem by itself, since the docs are allowed and free during the real exam, but it's worth checking whether the lookup is still needed or was a one-time refresher.

**Remediation:** rebuild both patterns from a cold start, timed, with no documentation access: a PVC bound to a custom StorageClass mounted into a Job's pod template, and a pod with both a toleration for the control-plane taint and a nodeSelector against the existing control-plane label. If both come out correct and fast without the docs, this is closed. If either still needs a lookup, that's fine to keep relying on during the actual exam (the docs are allowed), but it's worth knowing which one still needs it so time gets budgeted for that lookup deliberately rather than treated as a surprise.

---

## What Changed From the First-Attempt Plan

**The diagnostic categories from the first-attempt plan (coverage gap, retention issue, speed issue, not attempted, time cascade, caught-too-late error, missed-the-visible-answer error) all still apply as a framework, but this retake's misses sort almost entirely into "caught-too-late error" and "typo/omission," with two clean instances of genuine coverage gap (Q16, Q17) and no instances of time cascade at all.** That absence is itself the main finding: the thing the entire first-attempt plan was built to fix, the clock running out before reaching questions, did not happen this time.

**Q17's diagnosis required the same thing every hard-to-explain miss on this whole project has required: direct account, not score-page inference.** The score page rendered no feedback text at all for Q17, the same way it rendered none for most of the first attempt's zero-score questions. Without your account of the `crd.yaml`/`students.yaml` confusion, this would have stayed an unexplained zero. The pattern holds across both sessions now: every "no feedback shown" result on this exam has needed a direct account to actually diagnose, and every time that account has been given, the diagnosis has turned out to be a specific, fixable, narrow thing rather than a broad knowledge gap.

**The remaining work is smaller in scope and different in kind than the first attempt's.** That plan needed a multi-priority structure because it was solving a structural problem (time allocation across an entire exam). This plan is mostly a checklist: read back FQDN and image-tag values before submitting, wait for full pod termination before remanifesting the scheduler, check the base/original object last when retrofitting a new requirement, never use an interactive alias inside a script, learn what "namespaced resources" means, and learn the CRD-definition-versus-instance distinction. None of these require the kind of sequencing or upstream-fix-first logic the time-cascade plan needed.

---

## Suggested Sequencing

1. **The read-back/segment-check habit**, applied generally now rather than to one specific value, since it would have caught Q1's DNS_3/DNS_4, Q2's image tag, and Q14's missing hyphen, three of the eight typo-class misses, in one pass.
2. **Q16's vocabulary fix** (namespaced resource types vs. namespace contents), a single short drill.
3. **Q17's CRD-instance drill**, the one item here that needs actual hands-on practice rather than a habit or a memorized fact, given it's the largest remaining point block (5 subtasks).
4. **The fixed-path flashcard set** (CNI config, static pod manifests, kubelet PKI, kubeadm config), closing the smaller Q14 finding before it can compound into something bigger on a future attempt.
5. **The script-alias rule** (no interactive aliases inside script files), a one-time rule rather than a drill.
6. **Q9's scheduler-restart wait-for-confirmation step**, a one-time procedural correction.
7. **The Q10/Q12 fluency check**, timed cold-start rebuilds without documentation access, to confirm which patterns are genuinely fast versus still doc-assisted.
8. **A third full timed run**, this time testing specifically whether the typo-class misses recur even with no time pressure forcing rushed answers, since if they do, that points at a genuine read-back discipline gap rather than a pressure-induced one.

---

## Notes for Future Sessions

- **A solved time cascade reveals a different, smaller layer of problems underneath it, and that's a sign of progress, not a new setback.** The first attempt's zero-score questions hid whatever was actually going on inside them, since "never attempted" gives no information about what would have happened if they had been attempted. This retake answers that question directly for five of six: mostly solid, with small, specific, fixable defects.
- **Typo-class misses scattered across many questions are a different remediation problem than one typo-class miss on one question.** The first attempt's Q1 DNS_2 finding looked like an isolated case; this retake shows the same underlying pattern (correct mechanism, flawed execution of the specific value) recurring across Q1, Q2, Q9, Q13, Q14, and Q15. The fix doesn't change, but the scope of where to apply it does: every FQDN, every image tag, every exact-string answer, every procedural multi-step sequence, not just the ones that have already failed once.
- **A method that's slower than necessary but produces no scored miss (Q14's CNI search, Q10/Q12's doc lookups) is still worth tracking, since on a real exam with a hard clock, several of these compounding is exactly how a cascade starts.** This retake's near-miss on this front (one CNI search costing real but unscored time) is worth treating as an early-warning signal rather than dismissing because it didn't cost a point this time.
- **Direct account remains more reliable than score-page inference for every "no feedback shown" result, and this has now held across two full attempts.** Q17's zero-with-no-feedback this round and most of the first attempt's zero-score questions last round both needed a direct account to diagnose accurately; guessing from the blank feedback alone would have been wrong or incomplete both times.
- **The arithmetic of "which misses are cheapest to fix" is worth computing explicitly rather than assumed, the same way it was worth computing here.** The session's own instinct (fixing the typos and the one volumeMount would reach 90%) was correct and is exactly the kind of check worth running on every future attempt before deciding where to spend remaining prep time.
