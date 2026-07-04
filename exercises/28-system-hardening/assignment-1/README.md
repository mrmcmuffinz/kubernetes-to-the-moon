# System Hardening: Assignment 1, AppArmor Profiles

This is the first assignment in the two-part System Hardening series and focuses on Linux mandatory access control through AppArmor. You will learn how to write AppArmor profiles that restrict what processes inside containers can do at the kernel level, how to load those profiles into a kind cluster node using nerdctl, and how to apply them to Kubernetes pods using both the modern `securityContext.appArmorProfile` field and the legacy annotation syntax. This assignment follows 13-security-contexts (which covers container capabilities and runAsUser) and precedes System Hardening assignment 2, which covers custom seccomp profiles and node OS hardening.

## Files

| File | Description |
|------|-------------|
| `README.md` | Assignment overview, prerequisites, workflow, and scope |
| `prompt.md` | Generation input produced by k8s-prompt-builder |
| `system-hardening-tutorial.md` | Step-by-step tutorial covering AppArmor architecture, profile syntax, complain and enforce modes, and pod integration |
| `system-hardening-homework.md` | 15 progressive exercises across five difficulty levels |
| `system-hardening-homework-answers.md` | Complete solutions, three-stage debugging walkthroughs, and a verification cheat sheet |

## Recommended Workflow

Read through the tutorial before attempting any exercises. The tutorial builds a complete AppArmor workflow from scratch: writing a profile in complain mode, loading it into the kind node with nerdctl, applying it to a pod, converting it to enforce mode, and verifying that denied operations actually fail. Understanding this loading cycle is essential because many debugging exercises involve a broken step in exactly this sequence.

Each exercise includes setup commands that create the exercise namespace and any baseline resources. For debugging exercises at Levels 3 and 5, the setup deliberately installs a broken configuration. Run the setup commands first, observe the symptoms as you would in a real troubleshooting scenario, and then diagnose and fix the problem before checking against the answer key.

## Difficulty Progression

Level 1 builds basic fluency: you verify which profiles are loaded on the kind node, apply pre-written profiles to pods using both the modern `securityContext.appArmorProfile` field and the pre-1.30 annotation syntax, and confirm that enforcement is active. Level 2 introduces profile authoring: you write profiles from scratch, configure one in complain mode, and observe audit log output from the kind node. Level 3 is debugging, where the setup creates broken AppArmor configurations and you must diagnose them using kubectl events and node-level commands without hints about the nature of the problem. Level 4 presents realistic production scenarios, including writing a complete nginx web server profile that grants the server the minimum access it needs to operate. Level 5 is advanced debugging: a pod is crashing due to AppArmor enforcement, and you must use complain mode logs to discover what access the application actually needs, then write a corrected profile that fixes the crash without granting unnecessary permissions.

## Prerequisites

This assignment assumes you have completed 01-pods/assignment-1 (pod spec fluency) and 13-security-contexts/assignment-1 (runAsUser, fsGroup, readOnlyRootFilesystem). You do not need the other security-contexts assignments. Basic familiarity with Linux file paths and the concept of kernel-level access control is helpful but not required. You need a single-node kind cluster running with nerdctl; cluster setup instructions are referenced below.

## Cluster Requirements

This assignment uses a single-node kind cluster. Follow the setup instructions in [docs/cluster-setup.md](../../../docs/cluster-setup.md#single-node-kind-cluster). AppArmor must be enabled in the host Linux kernel; it is enabled by default on Ubuntu 24.04 LTS. You can confirm AppArmor support by running `nerdctl exec kind-control-plane aa-status` and verifying it returns a profile list rather than an error. No additional cluster components beyond the base kind install are required. Profiles are loaded into the cluster node using `nerdctl cp` and `nerdctl exec kind-control-plane apparmor_parser`, as documented in the tutorial.

## Estimated Time Commitment

Level 1 exercises take roughly 10 to 15 minutes each, since the profiles are provided and the tasks focus on applying them and confirming behavior. Level 2 exercises take 15 to 25 minutes because you are writing profiles from scratch and may need to iterate on the syntax. Level 3 debugging exercises take 15 to 20 minutes each for someone new to reading AppArmor errors from kubectl events. Level 4 exercises take 20 to 30 minutes because writing a correct profile for a real workload requires understanding what file paths and network access the application actually needs. Level 5 advanced debugging takes 30 to 40 minutes because it requires switching profile modes, reading kernel audit logs from inside the kind node, and iterating on the profile until the application runs cleanly.

## Scope Boundary and What Comes Next

This assignment covers AppArmor exclusively. Custom seccomp profiles (syscall-level filtering with JSON profiles) are covered in System Hardening assignment 2. Linux capability add/drop at the pod spec level is covered in 13-security-contexts/assignment-2. Runtime sandboxing with gVisor is covered in 24-runtime-sandboxing. AppArmor and seccomp complement each other but operate at different kernel layers: AppArmor controls what files, network resources, and capabilities a process can access using path-based rules, while seccomp controls which system calls the process may invoke. Completing both assignments gives you the full picture of how they interact.

## Key Takeaways After Completing This Assignment

After completing all 15 exercises you should be able to write a syntactically correct AppArmor profile that grants a container process the minimum file, network, and capability access it needs; load a profile into a kind node using `nerdctl cp` and `apparmor_parser`; apply a profile to a Kubernetes pod using either the `securityContext.appArmorProfile` field or the pre-1.30 annotation; use complain mode to identify what access a crashing application actually needs before writing a strict enforce-mode profile; and read AppArmor audit messages from the kind node to diagnose enforcement failures. You will also understand why profiles must be loaded on every node where a pod might be scheduled and what happens at the kubelet level when a required profile is missing.
