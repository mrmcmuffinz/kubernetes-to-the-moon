# CKA Homework Assignment Plan (Historical)

> This document is a historical record of the original CKA exam prep corpus. It maps CKA exam
> competencies to the 45 assignments in exercises/01-19. It is no longer the active plan.
> The live registry of all assignments (including new topics beyond CKA) is in
> `.claude/skills/cka-prompt-builder/references/assignment-registry.md`.

**Status:** All 45 assignments content-complete as of 2026-04-19.
**Last updated:** 2026-04-19

---

## Overview

This document maps every CKA exam competency to a homework assignment, tracks which
assignments have been generated, and sequences the remaining work. It serves as the
run sheet for generating new assignments using the two skills in `skills/`.

The CKA exam tests five domains. Each domain has specific competencies published in
the official CNCF curriculum. Every competency must be covered by at least one
assignment. Some competencies are covered by multiple assignments (for example,
pod scheduling appears in both the pod series and the troubleshooting series).

---

## CKA Exam Domains and Weights

| Domain | Weight | Primary Exercise Directories |
|---|---|---|
| Cluster Architecture, Installation & Configuration | 25% | cluster-lifecycle, tls-and-certificates, rbac, crds-and-operators, helm, kustomize, admission-controllers |
| Workloads & Scheduling | 15% | pods (1-7), security-contexts, jobs-and-cronjobs, autoscaling, statefulsets, admission-controllers, pod-security |
| Services & Networking | 20% | services, coredns, network-policies, ingress-and-gateway-api (1-5) |
| Storage | 10% | storage |
| Troubleshooting | 30% | troubleshooting (1-4), plus debugging exercises across all topics |

---

## Assignment Status Summary

**Total assignments as of 2026-04-19:** 45 content-complete. Every assignment
in the corpus has its four content files (README, tutorial, homework, answers)
plus its `prompt.md` input.

- **Original-scope corpus (38):** pods (1-7), rbac (1-2), cluster-lifecycle
  (1-3), tls-and-certificates (1-3), security-contexts (1-3), crds-and-operators
  (1-3), storage (1-3), services (1-3), coredns (1-3), network-policies (1-3),
  ingress-and-gateway-api (1-3 as originally scoped), helm (1-3), kustomize
  (1-3), and troubleshooting (1-4).
- **Ingress expansion (D8, +2):** `11-ingress-and-gateway-api/assignment-4`
  (NGINX Gateway Fabric) and `assignment-5` (Ingress2Gateway migration). The
  topic is now 5 assignments covering controller diversity: Traefik, HAProxy
  Ingress, Envoy Gateway, NGINX Gateway Fabric, plus the migration capstone.
- **New topics (+5):** `autoscaling/1` (HPA, VPA, in-place resize);
  `jobs-and-cronjobs/1`; `statefulsets/1`; `admission-controllers/1` (built-ins
  plus ValidatingAdmissionPolicy); `pod-security/1` (Pod Security Standards
  and Pod Security Admission).

All 19 regenerated Phase 4 assignments (security-contexts/1-3, storage/1-3,
ingress-and-gateway-api/1-5, rbac/2, jobs-and-cronjobs/1, autoscaling/1,
statefulsets/1, admission-controllers/1, pod-security/1, troubleshooting/2,
troubleshooting/4) satisfy the Phase 2 hard gates: 9-section canonical
README, narrative tutorial with per-field spec documentation, 15 build-or-fix
exercises with RBAC-style verification, three-stage debugging answers, and
Common Mistakes sections with 7-8 entries each. Three surgical regens
(P4.6 cluster-lifecycle/1 homework, P4.7 crds-and-operators/1 Level 1
fixes, P4.8 troubleshooting/1 Exercise 1.2 fix) round out Phase 4.

**Assignment distribution:**
- **7-assignment series:** 1 topic (pods)
- **5-assignment topic:** 1 topic (ingress-and-gateway-api, post-expansion)
- **4-assignment topic:** 1 topic (troubleshooting)
- **3-assignment topics:** 10 topics (cluster-lifecycle, tls-and-certificates, security-contexts, crds-and-operators, storage, services, coredns, network-policies, helm, kustomize)
- **2-assignment series:** 1 topic (rbac)
- **1-assignment topics:** 5 (autoscaling, jobs-and-cronjobs, statefulsets, admission-controllers, pod-security)

---

## Generation Sequence (historical)

**Historical record.** All 38 assignments in the table below have been
generated. This section is preserved as the record of the original
generation sequence. For the current plan of work (regeneration,
expansion, and new topics) see `docs/remediation-plan.md`.

The original sequence was aligned with the daily study plan. The "Unlocked After"
column indicated when the relevant course material had been covered.

| Order | Assignment | Unlocked After | Dependencies |
|---|---|---|---|
| 1 | 17-cluster-lifecycle/assignment-1 | Day 6 (S6 complete) | None (kind cluster sufficient for exercises) |
| 2 | 17-cluster-lifecycle/assignment-2 | Day 6 (S6 complete) | 17-cluster-lifecycle/assignment-1 |
| 3 | 17-cluster-lifecycle/assignment-3 | Day 6 (S6 complete) | 17-cluster-lifecycle/assignment-2 (etcd builds on maintenance workflows) |
| 4 | 18-tls-and-certificates/assignment-1 | Day 6 (S7 partial, through KubeConfig) | 17-cluster-lifecycle/assignment-1 (cert concepts build on cluster PKI) |
| 5 | 18-tls-and-certificates/assignment-2 | Day 6 (S7 partial) | 18-tls-and-certificates/assignment-1 (Certificates API builds on manual cert creation) |
| 6 | 18-tls-and-certificates/assignment-3 | Day 6 (S7 partial) | 18-tls-and-certificates/assignment-2 (troubleshooting builds on both manual and API workflows) |
| 7 | 12-rbac/assignment-2 | Day 7 (S7, RBAC section complete) | 12-rbac/assignment-1 (namespace-scoped RBAC as prerequisite), 18-tls-and-certificates/assignment-2 (cert-based auth) |
| 8 | 13-security-contexts/assignment-1 | Day 7 (S7, security contexts section) | 01-pods/assignment-1, 01-pods/assignment-2 (pod spec and volume fundamentals) |
| 9 | 13-security-contexts/assignment-2 | Day 7 (S7, security contexts section) | 13-security-contexts/assignment-1 (capabilities build on user/group foundation) |
| 10 | 13-security-contexts/assignment-3 | Day 7 (S7, security contexts section) | 13-security-contexts/assignment-2 (filesystem constraints complete the security picture) |
| 11 | 15-crds-and-operators/assignment-1 | Day 8 (S7 complete) | None (CRD authoring is foundational) |
| 12 | 15-crds-and-operators/assignment-2 | Day 8 (S7 complete) | 15-crds-and-operators/assignment-1 (custom resources build on CRD foundation) |
| 13 | 15-crds-and-operators/assignment-3 | Day 8 (S7 complete) | 15-crds-and-operators/assignment-2 (operators consume custom resources) |
| 14 | 07-storage/assignment-1 | Day 8 (S8 complete) | None (PV creation is foundational) |
| 15 | 07-storage/assignment-2 | Day 8 (S8 complete) | 07-storage/assignment-1 (PVCs build on PV foundation) |
| 16 | 07-storage/assignment-3 | Day 8 (S8 complete) | 07-storage/assignment-2 (StorageClass automates provisioning) |
| 17 | 08-services/assignment-1 | Day 9 (S9 partial) | 01-pods/assignment-7 (needs Deployments for service targets) |
| 18 | 08-services/assignment-2 | Day 9 (S9 partial) | 08-services/assignment-1 (external types build on ClusterIP foundation) |
| 19 | 08-services/assignment-3 | Day 9 (S9 partial) | 08-services/assignment-2 (advanced patterns build on all service types) |
| 20 | 09-coredns/assignment-1 | Day 10 (S9 complete) | 08-services/assignment-1 (DNS resolves service names) |
| 21 | 09-coredns/assignment-2 | Day 10 (S9 complete) | 09-coredns/assignment-1 (configuration builds on DNS usage) |
| 22 | 09-coredns/assignment-3 | Day 10 (S9 complete) | 09-coredns/assignment-2 (troubleshooting applies configuration knowledge) |
| 23 | 10-network-policies/assignment-1 | Day 10 (S9 complete) | 08-services/assignment-1 (policies filter traffic to/from services) |
| 24 | 10-network-policies/assignment-2 | Day 10 (S9 complete) | 10-network-policies/assignment-1 (advanced selectors build on fundamentals) |
| 25 | 10-network-policies/assignment-3 | Day 10 (S9 complete) | 10-network-policies/assignment-2 (debugging applies advanced pattern knowledge) |
| 26 | 11-ingress-and-gateway-api/assignment-1 | Day 10 (S9 complete) | 08-services/assignment-1 (Ingress routes to backend services) |
| 27 | 11-ingress-and-gateway-api/assignment-2 | Day 10 (S9 complete) | 11-ingress-and-gateway-api/assignment-1 (TLS builds on basic Ingress) |
| 28 | 11-ingress-and-gateway-api/assignment-3 | Day 10 (S9 complete) | 11-ingress-and-gateway-api/assignment-2 (Gateway API is next-generation approach) |
| 29 | 05-helm/assignment-1 | Day 11 (S12 complete) | None (chart consumption is foundational) |
| 30 | 05-helm/assignment-2 | Day 11 (S12 complete) | 05-helm/assignment-1 (lifecycle builds on installation) |
| 31 | 05-helm/assignment-3 | Day 11 (S12 complete) | 05-helm/assignment-2 (templates and debugging build on lifecycle mastery) |
| 32 | 06-kustomize/assignment-1 | Day 12 (S13 complete) | None (basic kustomization is foundational) |
| 33 | 06-kustomize/assignment-2 | Day 12 (S13 complete) | 06-kustomize/assignment-1 (patches build on fundamentals) |
| 34 | 06-kustomize/assignment-3 | Day 12 (S13 complete) | 06-kustomize/assignment-2 (overlays use patches) |
| 35 | 19-troubleshooting/assignment-1 | Day 13 (S14 complete) | All previous assignments (cross-domain application troubleshooting) |
| 36 | 19-troubleshooting/assignment-2 | Day 13 (S14 complete) | cluster-lifecycle, tls-and-certificates (control plane concepts) |
| 37 | 19-troubleshooting/assignment-3 | Day 13 (S14 complete) | cluster-lifecycle (node management concepts) |
| 38 | 19-troubleshooting/assignment-4 | Day 13 (S14 complete) | services, coredns, network-policies (network troubleshooting combines all networking topics) |

---

## Design Decisions

**Progressive resource gating.** Assignments generated early in the course (through Storage,
generation order 1-16) explicitly list which Kubernetes resources are in scope. This prevents
exercises from referencing objects the learner has not yet encountered. Assignments generated
after Networking (generation order 17+) have access to the full set of CKA resources, since by
that point in the course all major resource types have been introduced.

**Troubleshooting as capstone.** The four troubleshooting assignments are generated last
regardless of when S14 is completed in the course. Troubleshooting exercises are inherently
cross-domain (a single scenario might involve a broken Service, a misconfigured PVC, and a
pod with wrong resource limits). Generating them after all other assignments ensures the
prompt builder can reference the full scope of what the learner has practiced.

**3+ focused assignments per topic.** Each topic (except the legacy pod series and RBAC) is
decomposed into 3+ focused assignments with 5-6 core subtopics each. This preference for depth
over breadth allows each assignment to explore its subtopics thoroughly rather than skimming
12-15 subtopics in a single dense assignment. The pod series (7 assignments) predates this
structure. Troubleshooting uses 4 assignments organized by failure layer (application, control
plane, node, network).

**Debugging exercises are distributed, not centralized.** Every assignment includes
debugging exercises at Levels 3 and 5. The troubleshooting series adds cross-domain
debugging scenarios that combine multiple failure modes. This means troubleshooting
practice is woven throughout the entire exercise corpus, not isolated in one section.

**Security is distributed across assignments, not a single series.** The CKA exam does
not have a standalone Security domain (it was consolidated into the other five domains
in the 2025 curriculum update). Security topics are distributed to the domains they
belong to: RBAC and TLS under Cluster Architecture, security contexts under Workloads
& Scheduling, network policies under Services & Networking, and certificate
troubleshooting under Troubleshooting. This matches how the exam tests them.
