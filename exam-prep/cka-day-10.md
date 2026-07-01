# CKA Day 10 (Wed, July 1) | Verification and Taper Begins

**Exam:** Friday, July 3, 2026 at 10:00 AM Central Time (2 days out)

Goal: Verify the fixes from Days 8-9 held, do light review of both remediation plans, then begin tapering. No new learning today. This is confirmation and mental preparation.

## Block A: Final Verification Checks (1 hour)

Quick confidence checks on the focused work from Days 8-9. These are go/no-go checks, not learning exercises.

**Q17 verification (5 minutes):**
- [ ] Without looking at notes: Explain the difference between a CRD definition file and a CRD instance file in one sentence
- [ ] Timed: Add a new instance to an existing CRD multi-doc YAML file in <3 minutes
- [ ] Result: Pass/Fail (if fail, drill one more time before moving on)

**Q16 verification (3 minutes):**
- [ ] Without looking: What command lists all namespaced resource types?
- [ ] What does that output contain? (type names like "pods", not instance names like "my-pod-xyz")
- [ ] Result: Pass/Fail

**Fixed paths recall (5 minutes):**
- [ ] Write down all 6 paths/patterns from memory:
  - CNI config directory
  - Static pod manifests directory
  - Kubelet PKI directory
  - Kubelet client cert path
  - Kubelet server cert path
  - Static pod suffix format (with or without hyphen?)
- [ ] Check against Day 8 list
- [ ] Result: 6/6 or missed some?

**Read-back habit check (10 minutes):**
- [ ] Build one complex FQDN (pod subdomain DNS) from scratch
- [ ] Did you pause to verify segments before considering it done?
- [ ] Was the pause automatic or did you have to remind yourself?
- [ ] Result: Habit installed / Still forced / Forgot to check

**Cold rebuild speed check (30 minutes, if you did Block F on Day 9):**
- [ ] Rebuild control-plane scheduling pattern from scratch, timed
- [ ] Rebuild 3-container shared volume pattern from scratch, timed
- [ ] Result: Both under target? Which needed docs?

## Block B: Light Review (1 hour)

Read (don't drill, just read) both remediation plans to refresh the key findings:

**From `exam-prep/cka-simulator-b-remediation-plan.md` (first attempt):**
- Q1 DNS_2 typo fix (missing `.svc`) → held on retake
- Q3 certificate distinction (client vs server) → held perfectly (4/4)
- Q6 reading discipline (full systemctl output) → held (2/2)
- Q9 nodeName mechanism → mostly held (9/10, only restart timing missed)
- Time cascade prevention → **completely successful**

**From `exam-prep/cka-simulator-b-remediation-plan-v2.md` (retake):**
- 8-subtask typo cluster (Days 8-9 targeted this)
- Q16 and Q17 gaps (Days 8-9 targeted this)
- 72% on fresh questions (Q12-Q17)
- Arithmetic: fixing typos alone reaches 93.5%

**Key takeaway:** The work done Days 8-9 targets exactly what the retake diagnosed. If those fixes hold Friday, you're at 90%+.

## Block C: Common Mistakes Review (30 minutes)

Read the Common Mistakes sections from these assignment answer keys (just read, don't drill):

- [ ] `exercises/09-coredns/assignment-4/coredns-homework-answers.md`
- [ ] `exercises/01-pods/assignment-1/pod-fundamentals-homework-answers.md`
- [ ] `exercises/19-troubleshooting/assignment-3/troubleshooting-homework-answers.md`
- [ ] `exercises/01-pods/assignment-6/multi-container-patterns-homework-answers.md`
- [ ] `exercises/15-crds-and-operators/assignment-1/crds-and-operators-homework-answers.md`
- [ ] `exercises/15-crds-and-operators/assignment-2/crds-and-operators-homework-answers.md`

Look for mistakes you've personally made this week and flag them mentally.

## Evening: Stop Studying by 6 PM

After the review above, **no more studying today**. 

The taper begins now. Your brain needs downtime to consolidate.

## Tomorrow (Day 11 / Thursday July 2)

Light logistics check only:
- PSI Secure Browser test
- Workspace setup
- ID ready
- Quick kubernetes.io navigation test

**No studying Thursday.**

## The Confidence Check

You're ready if you can answer YES to these by end of today:

1. ✅ Q17: Can add CRD instance in <3 min without confusion
2. ✅ Q16: Know what `kubectl api-resources --namespaced` returns
3. ✅ Read-back: Pause feels automatic (or at least more natural than Day 9)
4. ✅ Fixed paths: Can recall all 6 without looking
5. ✅ Peace with the math: 72% fresh + fixes = likely 80-85% real performance

If yes to all 5: You're ready for Friday.
