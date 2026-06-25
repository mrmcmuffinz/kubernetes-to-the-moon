# Network Policies Assignment 3: Network Policy Debugging

This is the third of three assignments covering Network Policies in Kubernetes. This assignment focuses on diagnosing blocked and unexpectedly allowed traffic, policy conflicts, cross-namespace troubleshooting, and integration with services and DNS. Basic and advanced NetworkPolicy mechanics are assumed from assignments 1 and 2.

## Prerequisites

Before starting this assignment, you should have completed:

- exercises/10-10-network-policies/assignment-1 (NetworkPolicy Fundamentals)
- exercises/10-10-network-policies/assignment-2 (Advanced Selectors and Isolation)

You should understand podSelector, namespaceSelector, ipBlock, default deny policies, and policy additive behavior.

## What You Will Learn

This assignment teaches systematic Network Policy troubleshooting. You will learn how to diagnose why traffic is blocked when it should be allowed, why traffic is allowed when it should be blocked, trace policy interactions across namespaces, and verify DNS and service connectivity through policies. These skills are essential for maintaining secure and functional networks in production clusters.

## Estimated Time

4 to 6 hours for the tutorial and all 15 exercises.

## Cluster Requirements

This assignment requires a multi-node cluster with a CNI that enforces NetworkPolicy (Calico v3.31.5 or later). If you have an existing kubeadm or bare-metal cluster with Calico running, it works directly -- verify with `kubectl get pods -l k8s-app=calico-node -A`. For kind, see `docs/cluster-setup.md#multi-node-with-calico-networkpolicy-support`.

## Difficulty Progression

**Level 1 (Exercises 1.1 to 1.3):** Basic debugging including testing connectivity and verifying policy selectors.

**Level 2 (Exercises 2.1 to 2.3):** Policy verification for DNS access, service connectivity, and cross-namespace policies.

**Level 3 (Exercises 3.1 to 3.3):** Debugging blocked traffic scenarios with selector mismatches and DNS issues.

**Level 4 (Exercises 4.1 to 4.3):** Complex policy issues including multi-policy interactions and unintended allows.

**Level 5 (Exercises 5.1 to 5.3):** Integration debugging and creating troubleshooting runbooks.

## Recommended Workflow

1. Read through the tutorial file (network-policies-tutorial.md) completely before starting.

2. For each debugging exercise, follow the systematic approach: test connectivity, check selectors, examine policies, verify DNS.

3. Document your findings as you work through exercises to build troubleshooting skills.

## Files in This Directory

| File | Description |
|------|-------------|
| README.md | This file. Assignment overview and guidance. |
| prompt.md | The generation prompt used to create this assignment. |
| network-policies-tutorial.md | Step-by-step tutorial teaching policy debugging methodology. |
| network-policies-homework.md | 15 progressive exercises across 5 difficulty levels. |
| network-policies-homework-answers.md | Complete solutions with explanations for all exercises. |
