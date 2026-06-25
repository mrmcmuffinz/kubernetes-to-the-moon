# Network Policies Assignment 2: Advanced Selectors and Isolation

This is the second of three assignments covering Network Policies in Kubernetes. This assignment focuses on namespaceSelector, combined selectors, ipBlock/CIDR for external traffic, default deny policies, namespace isolation, and policy ordering. Basic NetworkPolicy mechanics are assumed from assignment 1. Policy debugging is covered in assignment 3.

## Prerequisites

Before starting this assignment, you should have completed:

- exercises/10-10-network-policies/assignment-1 (NetworkPolicy Fundamentals)

You should understand basic podSelector mechanics, ingress/egress rules, and port filtering.

## What You Will Learn

This assignment covers the advanced selector types that enable cross-namespace policies and external traffic control. You will learn how to use namespaceSelector to control traffic between namespaces, combine pod and namespace selectors, use ipBlock for external IP ranges, implement default deny policies, and design namespace isolation strategies. These skills are essential for implementing zero-trust network security in Kubernetes.

## Estimated Time

4 to 6 hours for the tutorial and all 15 exercises.

## Cluster Requirements

This assignment requires a multi-node cluster with a CNI that enforces NetworkPolicy (Calico v3.31.5 or later). If you have an existing kubeadm or bare-metal cluster with Calico running, it works directly -- verify with `kubectl get pods -l k8s-app=calico-node -A`. For kind, see `docs/cluster-setup.md#multi-node-with-calico-networkpolicy-support`.

## Difficulty Progression

**Level 1 (Exercises 1.1 to 1.3):** Cross-namespace policies using namespaceSelector and namespace labels.

**Level 2 (Exercises 2.1 to 2.3):** Combined selectors and ipBlock for external traffic.

**Level 3 (Exercises 3.1 to 3.3):** Debugging selector issues including missing labels and AND/OR semantics.

**Level 4 (Exercises 4.1 to 4.3):** Default deny and namespace isolation patterns.

**Level 5 (Exercises 5.1 to 5.3):** Complex isolation scenarios and zero-trust network design.

## Recommended Workflow

1. Read through the tutorial file (network-policies-tutorial.md) completely before starting any exercises.

2. Pay special attention to the difference between AND and OR semantics in selectors.

3. When using namespaceSelector, remember that namespaces need labels to be selected.

4. When implementing default deny, always include DNS egress to avoid breaking name resolution.

## Files in This Directory

| File | Description |
|------|-------------|
| README.md | This file. Assignment overview and guidance. |
| prompt.md | The generation prompt used to create this assignment. |
| network-policies-tutorial.md | Step-by-step tutorial teaching advanced selectors. |
| network-policies-homework.md | 15 progressive exercises across 5 difficulty levels. |
| network-policies-homework-answers.md | Complete solutions with explanations for all exercises. |
