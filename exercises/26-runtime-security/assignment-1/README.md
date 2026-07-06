# Runtime Security: Assignment 1: Falco Threat Detection

This is the first of two Runtime Security assignments. It focuses on Falco, the open-source runtime security engine that monitors system calls and Kubernetes events in real time. You will install Falco as a DaemonSet using the eBPF probe, explore the built-in ruleset, write custom rules using the Falco condition language, and observe alerts firing when threat behaviors are triggered inside running containers. The second assignment in this series covers Kubernetes audit logging and immutable container patterns.

## Files

| File | Description |
|---|---|
| `README.md` | This overview: prerequisites, workflow, scope, and time estimates |
| `prompt.md` | Generation input used to produce this assignment |
| `runtime-security-tutorial.md` | Step-by-step tutorial building a complete Falco threat-detection workflow |
| `runtime-security-homework.md` | 15 progressive exercises across five difficulty levels |
| `runtime-security-homework-answers.md` | Complete solutions with diagnostic reasoning and a verification cheat sheet |

## Recommended Workflow

Work through the tutorial from start to finish before attempting the homework. The tutorial installs Falco, walks you through the built-in ruleset, and shows you how to write, apply, and verify custom rules against a live cluster. The exercises build on those same skills, so familiarity with the tutorial workflow will let you move through Levels 1 and 2 quickly and focus your time on the debugging and scenario-based exercises in Levels 3 through 5.

## Difficulty Progression

Level 1 exercises give you practice reading Falco alert output and identifying which built-in rules fired and why. Level 2 exercises ask you to write custom rules, modify existing rule priorities, and disable built-in rules that generate noise for your environment. Level 3 is debugging: you are given broken rule configurations and must diagnose why alerts are not firing or why Falco cannot parse the rule file. Level 4 builds a complete custom ruleset for a threat scenario covering process execution, file access, and outbound connections. Level 5 is advanced debugging where a rule fires too broadly and you must tune it to suppress false positives while preserving detection coverage.

## Prerequisites

This assignment assumes you have completed the security contexts series (13-security-contexts/assignment-1) and are comfortable with pod creation, resource YAML, and basic kubectl operations from the pods series (01-pods/assignment-1). Falco installation is covered in the tutorial, so no prior Falco experience is required. See [docs/cluster-setup.md](../../../docs/cluster-setup.md) for how to create the required cluster.

## Cluster Requirements

This assignment uses a single-node kind cluster. Follow the setup instructions at [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster). No additional cluster add-ons (MetalLB, Calico, Gateway API CRDs) are required. Falco is installed via Helm during the tutorial itself; the tutorial covers the install steps.

## Estimated Time Commitment

Level 1 exercises are straightforward log-reading tasks and should take 5 to 8 minutes each. Level 2 rule-writing exercises take 10 to 15 minutes each as you work with the Falco condition language. Level 3 debugging exercises typically run 15 to 20 minutes depending on how quickly you spot the syntax or logic error. Level 4 takes 25 to 35 minutes to design and verify a multi-rule threat scenario. Level 5 requires careful condition analysis and may take 20 to 30 minutes to tune correctly without over-suppressing legitimate alerts.

## Scope Boundary and What Comes Next

This assignment does not cover Kubernetes audit logging, which is the main subject of runtime-security/assignment-2. It also does not cover AppArmor or seccomp profiles (28-system-hardening) or Falco Sidekick for webhook-based alert forwarding. The immutable container pattern is briefly mentioned here in the context of Falco's write-detection rules but is fully developed in runtime-security/assignment-2.

## Key Takeaways After Completing This Assignment

By the end of this assignment you should be able to install Falco as a DaemonSet in a kind cluster using the eBPF probe, explain the architecture of the Falco rules engine and the role of macros and lists, write a syntactically valid custom rule using the Falco condition language with fields such as `evt.type`, `proc.name`, `fd.name`, `container.id`, and `k8s.ns.name`, override and tune built-in rules using `append: true` and `enabled: false`, trigger built-in rules by running specific commands inside containers, and read Falco alert output to identify the rule name, priority, and triggering event.
