# CKA Readiness Assessment: 10 Days Out

**Date:** 2026-06-21
**Exam date:** 2026-07-01 (10 days out, counting exam day)
**Diagnostic:** Killer.sh Simulator A, 53/74 (71.6%), taken 2026-06-20
**Companion docs:** the per-day worksheets `cka-day-0.md` through `cka-day-9.md` (the schedule), `cka-simulator-a-remediation-plan.md` (the gap analysis), `killer-sh-cka-simulator-a-solutions.md` (solutions for post-attempt comparison)

This document answers three questions asked 10 days out: is there enough time, are there
enough exercises, and how to handle being rusty on core kubectl after a stretch on
interview prep. The short version: time is sufficient for the date, the exercise material
is more than sufficient, and the one real adjustment is a short fluency primer to shake
off rust before the targeted drilling starts. That primer is now the Day 0 worksheet,
`cka-day-0.md`.

## Bottom line

Hold July 1. The 71.6% Simulator A score, taken cold after the weeks-off gap, already maps
to a comfortable real-exam pass, because Killer.sh runs harder than the real exam. The
work over the next 10 days is not about reaching a pass, it is about converting three
skipped topics and a handful of correct-but-slow questions into fast, verified solves so
the outcome lands at the 90%+ target rather than a bare pass. The date-reopen decision is
correctly deferred to Day 6, after Session 2 produces real data, and nothing about the
current picture argues for moving it.

## Question 1: Is 10 days enough?

**To pass: yes, with high confidence.** Killer.sh is deliberately harder than the real
exam, so 71.6% on Simulator A is already comfortably above the 66% bar in real-exam terms,
before any remediation. That score was produced after the interview-prep gap, so it is a
rusty baseline, not a peak one, which makes it a reassuring floor rather than a fragile
high-water mark.

**To hit the stated 90%+ target: tight but feasible.** Of the 21 points lost on Simulator
A, 15 came from three outright skips: Gateway API (Q13, 5 points), NetworkPolicy (Q15, 7
points), and CoreDNS (Q16, 3 points). These are attempt-confidence gaps, not deep
conceptual holes, and each carries a sub-12-minute target once drilled. Recovering even
substantially-correct attempts on the three lifts the Killer.sh score into the mid-80s,
which is the green band for a 90%+ real-exam outcome. The remaining six
lost points are retention and typo-class issues with mechanical fixes (read-back of exact
strings, a `--show-labels` confirmation habit).

The binding constraints, all of which the per-day worksheets account for, are the compression
(one buffer day, Day 8), Session 2 on Day 5 needing to be a fair test, and the broad rust
that the plan under-weights. The first two are managed by the plan's own slippage rule
(push Session 2 to Day 6 if Days 1 through 3 run long). The third is what the fluency
primer addresses. The honest risk is not running out of calendar, it is Day 4 being dense
and the speed targets needing to hold on a cold start, which is exactly what the Day 8
cold re-verification exists to confirm.

## Question 2: Are there enough exercises to bridge the gaps?

Yes, and the more accurate worry is the opposite, having more material than 10 days can
absorb. There are two complementary practice layers.

The **per-day worksheets** (`cka-day-0.md` through `cka-day-9.md`) are the targeted drilling
layer: each points at the corpus exercises that build the skill behind its Simulator A
question, attempted cold against the exercise's own verification. This maps one-to-one onto
the actual gaps.

The **`exercises/` corpus** is the teaching layer underneath it: 45 assignments across 19
topics, each with a tutorial, 15 graded exercises, a complete answer key, and a verify
script (49 verify scripts, all complete). Every gap topic has dedicated, answer-keyed
material here. The cross-reference table below says which corpus assignment to open when a
Bank exercise exposes something that needs more than a re-attempt.

The only genuine constraint is environment, not material. About six Bank exercises need
more than a disposable kind cluster, and `cluster-setup/` provides every one of those
environments. The single caveat worth confirming early: NetworkPolicy (E15) needs a
policy-enforcing CNI, so it has to run on a Calico-backed cluster (the Pi or the
two-kubeadm build) or on killercoda, not on default kind unless that kind build is
confirmed to enforce policy.

## Question 3: Re-practicing core kubectl after the rust

This is the one real adjustment to the plan. The per-day schedule drills topic-specific gaps
and assumes the everyday kubectl reflexes are already automatic. After a few weeks on
interview prep, that assumption does not hold, and a rusty baseline on the mechanical
operations would slow every other exercise and would make Session 2 on Day 5 read worse
than the underlying capability.

The fix is a light woven primer, not a separate study block, so the compressed schedule
keeps its buffer. It is the Day 0 worksheet `cka-day-0.md` (today if there is residual time,
otherwise Day 1 morning before Day 1 starts), capped at one to two hours, with no push to
Session 2. It drills the imperative generators and core verbs to muscle memory, sourced from
`exercises/01-pods` if any verb needs a worked-answer refresher.

After the primer, the broad refresh is carried by the full-mark speed blocks on
Days 1 through 4 (E1, E3, E4, E5, E6, E7, E9, E10, E11, E14, and the E8 kubeadm sequence).
Those already span kubeconfig, generators, scaling, `top`, storage, RBAC, certificates,
QoS, DaemonSet, and the kubeadm lifecycle, so they double as the rust-removal pass for the
breadth of kubectl. The cross-reference below is the lookup for any block that exposes a
soft spot.

## Corpus cross-reference

When a Bank exercise needs a deeper refresher than a re-attempt, open the corresponding
corpus assignment for its tutorial, graded exercises, and answer key.

| Bank exercise (Simulator A question) | Corpus assignment(s) for a deeper refresher |
|---|---|
| E13 Gateway API (Q13) | `11-ingress-and-gateway-api/assignment-3,4,5` (assignment-5 is the Ingress-to-Gateway migration, a direct match) |
| E15 NetworkPolicy (Q15) | `10-network-policies/assignment-1,2,3` |
| E16 CoreDNS (Q16) | `09-coredns/assignment-1,2,3` |
| E12 topology spread / anti-affinity (Q12) | `01-pods/assignment-4` (scheduling) |
| E4 QoS / eviction (Q4) | `01-pods/assignment-5` (resources and QoS) |
| E8 kubeadm upgrade and join (Q8) | `17-cluster-lifecycle/assignment-1,2,3` |
| E14 cert check and renew (Q14) | `18-tls-and-certificates/assignment-1,2,3` |
| E5 Kustomize HPA (Q5) | `06-kustomize/assignment-1,2,3`, `04-autoscaling/assignment-1` |
| E6 PV and PVC (Q6) | `07-storage/assignment-1,2,3` |
| E10 RBAC and ServiceAccount (Q10) | `12-rbac/assignment-1,2` |
| E9 API from inside a Pod (Q9) | `12-rbac/assignment-1,2`, `01-pods/assignment-2` |
| E2 cert-manager via Helm (Q2) | `05-helm/assignment-1,2,3`, `15-crds-and-operators/assignment-1,2,3` |
| E3 scale a StatefulSet (Q3) | `03-statefulsets/assignment-1` |
| E11 DaemonSet (Q11) | `01-pods/assignment-7` (workload controllers) |
| E0 fluency primer | `01-pods/assignment-1` through `assignment-7` |
| EP2 kube-proxy iptables | `08-services/assignment-1,2,3` |
| EP3 service CIDR | `08-services/assignment-1,2,3`, `17-cluster-lifecycle/assignment-1,2,3` |
| Cross-domain debugging under time pressure | `19-troubleshooting/assignment-1,2,3,4` |

## Environment matrix

Most of the Bank runs on a disposable kind cluster (see `docs/cluster-setup.md`). These are
the exercises that need something more, and where `cluster-setup/` provides it.

| Bank exercise | Needs | Where |
|---|---|---|
| E8 kubeadm upgrade and join | scratch kubeadm with an older un-joined worker | killercoda cluster-build, or `cluster-setup/vm/two-kubeadm`. Not the Pi cluster. |
| E12 topology spread | exactly two schedulable workers | `cluster-setup/vm/three-kubeadm`, or the Pi cluster (two workers) |
| E13 Gateway API | Gateway API CRDs, a controller, and a Gateway named `main` | killercoda CKA playground (fastest), or NGINX Gateway Fabric on kind |
| E15 NetworkPolicy | a policy-enforcing CNI | `cluster-setup/vm/two-kubeadm` or the Pi cluster (both Calico), or killercoda. Confirm the CNI enforces before relying on default kind. |
| E16 CoreDNS | a kubeadm CoreDNS Deployment and ConfigMap | kind, or any kubeadm cluster |
| E17 crictl | a root shell on a node | kind (`nerdctl exec`), or the Pi cluster (`ssh`) |
| E14, EP1, EP3 | a throwaway kubeadm control plane | killercoda, or `cluster-setup/vm/single-kubeadm` |
| E1 through E7, E9 through E11, EP2 | any cluster (E5 and E7 need metrics-server) | kind, per `docs/cluster-setup.md` |

The Pi comparative-install project stays off-limits until after the exam, and E8
specifically must not use the Pi cluster.
