# System Hardening: Assignment 2, Custom Seccomp Profiles

This is the second assignment in the two-part System Hardening series and covers syscall-level filtering with custom seccomp profiles and node OS hardening concepts. Where AppArmor (assignment 1) works at the path and capability level, seccomp works one layer lower: it restricts which Linux system calls a process is allowed to invoke, regardless of what files or network resources those syscalls would access. You will learn to write seccomp profiles in JSON, place them in the kind node for kubelet consumption, apply them to pods, and use the SCMP_ACT_LOG action to discover what syscalls an application actually needs before enforcing a strict allow-list. Node OS hardening is covered at the conceptual level, with exercises framed around inspection and analysis rather than system modification.

## Files

| File | Description |
|------|-------------|
| `README.md` | Assignment overview, prerequisites, workflow, and scope |
| `prompt.md` | Generation input produced by k8s-prompt-builder |
| `system-hardening-tutorial.md` | Step-by-step tutorial covering seccomp profile JSON authoring, deny-list and allow-list strategies, kind node placement, SCMP_ACT_LOG discovery, and node OS hardening concepts |
| `system-hardening-homework.md` | 15 progressive exercises across five difficulty levels |
| `system-hardening-homework-answers.md` | Complete solutions, three-stage debugging walkthroughs, and a verification cheat sheet |

## Recommended Workflow

Read through the tutorial before attempting the exercises. The tutorial explains the JSON profile format in detail, walks through writing both a deny-list and an allow-list profile, and covers the SCMP_ACT_LOG discovery workflow that Level 4 exercises rely on. Node OS hardening concepts are also introduced in the tutorial so you have the vocabulary when Level 4 exercises ask you to analyze and reason about node-level services.

Each exercise includes setup commands that create the namespace and any required baseline resources. For debugging exercises at Levels 3 and 5, the setup installs a broken configuration or a profile with intentional errors. Diagnose the symptoms before consulting the answer key.

## Difficulty Progression

Level 1 builds familiarity with the three seccomp profile types (Unconfined, RuntimeDefault, Localhost) and the mechanics of placing a custom profile on the kind node and applying it to a pod. Level 2 introduces profile authoring: you write a deny-list profile that blocks specific dangerous syscalls and an early allow-list experiment with a simple workload. Level 3 is debugging, where broken seccomp configurations test your ability to identify missing profile files, invalid JSON, and SCMP_ACT_ERRNO blocking a syscall the application actually needs. Level 4 presents the full SCMP_ACT_LOG discovery workflow: you apply a log-only profile to observe what syscalls a workload makes, then convert the findings into a working allow-list with SCMP_ACT_ERRNO as the default action. Level 5 is advanced debugging involving pod crashes tied to syscall denials that are not immediately obvious from the container logs alone.

## Prerequisites

This assignment assumes you have completed 13-security-contexts/assignment-3 (which introduced RuntimeDefault and the basics of seccomp at the pod spec level) and System Hardening assignment 1 (AppArmor profiles). You should understand the difference between complain and enforce modes, the pod spec `securityContext` structure, and the kind cluster nerdctl workflow. A single-node kind cluster is required; setup instructions are referenced below.

## Cluster Requirements

This assignment uses a single-node kind cluster. Follow the setup instructions in [docs/cluster-setup.md](../../../docs/cluster-setup.md#single-node-kind-cluster). Custom seccomp profiles must be placed at `/var/lib/kubelet/seccomp/` inside the kind node container before any pod that references them is created. The kubelet reads profiles from that directory at container start time. No additional cluster components beyond the base kind install are required.

## Estimated Time Commitment

Level 1 exercises take roughly 10 to 15 minutes each since the profiles are provided and the focus is on the placement and application workflow. Level 2 exercises take 15 to 20 minutes because you write JSON profiles from scratch and may need to look up syscall names. Level 3 debugging exercises take 15 to 25 minutes each because JSON syntax errors and wrong profile paths both produce errors that require careful kubectl inspect to distinguish. Level 4 exercises take 25 to 35 minutes because the SCMP_ACT_LOG discovery process requires running the workload, reading dmesg output from the kind node, mapping syscall numbers to names, writing a profile, and iterating. Level 5 advanced debugging takes 30 to 40 minutes because the failures are less immediately visible and require correlating container logs with node-level SECCOMP audit messages.

## Scope Boundary and What Comes Next

This assignment covers custom seccomp profiles and node OS hardening concepts. introductory seccomp (RuntimeDefault and the seccompProfile field) was covered in 13-security-contexts/assignment-3. AppArmor profiles are covered in System Hardening assignment 1. Linux capabilities are covered in 13-security-contexts/assignment-2. Runtime sandboxing with gVisor (which provides much stronger syscall isolation through a user-space kernel) is covered in 24-runtime-sandboxing. Understanding both AppArmor and seccomp gives you the full picture of the kernel-level isolation tools available in a standard Kubernetes cluster.

## Key Takeaways After Completing This Assignment

After completing all 15 exercises you should be able to write a valid seccomp profile JSON file using either the deny-list strategy (defaultAction: SCMP_ACT_ALLOW with specific syscalls denied) or the allow-list strategy (defaultAction: SCMP_ACT_ERRNO with specific syscalls allowed); place a custom profile at the correct path inside the kind node; apply it to a pod using the `securityContext.seccompProfile` field at both the pod and container level; use SCMP_ACT_LOG to discover which syscalls a workload makes before enforcing a strict profile; read SECCOMP audit messages from the kind node's dmesg to identify which syscall is being denied during a crash; and reason about node OS hardening concepts including reducing the node's listening service footprint and removing unnecessary packages.
