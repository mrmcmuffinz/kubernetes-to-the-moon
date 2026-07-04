# System Hardening

**Topic area:** OS-level and kernel-level security controls
**Certification relevance:** CKS (System Hardening 15%)
**Assignments in this topic:** 2

---

## Why Two Assignments

System hardening covers two complementary Linux security mechanisms: AppArmor (mandatory access control via path-based profiles) and seccomp (syscall filtering). While both restrict what a container process can do, they operate at different layers (MAC policy vs syscall table) and require different tooling and authoring workflows. Each deserves a focused assignment. Node OS hardening (reducing attack surface, open ports, unnecessary packages) is included in assignment-2 alongside seccomp since both deal with reducing the syscall/resource surface available to workloads.

Note: 13-security-contexts/assignment-3 introduces seccomp at the surface level (RuntimeDefault profile, basic annotations). This topic goes deeper: custom profile authoring, violation debugging, and AppArmor profile writing from scratch.

---

## Assignment Summary

| Assignment | Focus | Prerequisites |
|---|---|---|
| assignment-1 | AppArmor profile authoring, complain vs enforce mode, applying profiles to pods, violation debugging | 13-security-contexts/assignment-1, 01-pods/assignment-1 |
| assignment-2 | Custom seccomp profiles (beyond RuntimeDefault), syscall allow/deny lists, violation debugging, node OS hardening concepts | 13-security-contexts/assignment-3, system-hardening/assignment-1 |

---

## Assignment 1: AppArmor

Subtopics:
- *AppArmor architecture:* kernel module, profiles loaded into the kernel, complain vs enforce mode, aa-status to list loaded profiles
- *Profile syntax:* file rules (read, write, execute permissions on paths), network rules, capability rules, the profile header (profile name, flags)
- *Writing a profile:* starting from deny-all, adding allow rules for required paths (/proc/PID/\*, /tmp/\*, binary paths), the profile development workflow (complain mode first, review logs, convert to enforce)
- *Loading profiles:* apparmor_parser -r to load/reload a profile, profile persistence across reboots
- *Applying profiles to pods:* container.apparmor.security.beta.kubernetes.io/<container> annotation (pre-1.30), securityContext.appArmorProfile field (1.30+), specifying localhost/<profile-name>
- *Verifying enforcement:* kubectl exec into a pod and attempt a restricted operation, observe the AppArmor denial in dmesg or /var/log/syslog
- *Troubleshooting:* profile not loaded (pod stuck in Pending or fails with AppArmor profile not found), complain mode showing what would be denied, reading audit log entries for AppArmor denials

---

## Assignment 2: seccomp Profiles and Node Hardening

Subtopics:
- *seccomp profile types review:* Unconfined, RuntimeDefault, Localhost — establishing the baseline from 13-security-contexts/assignment-3
- *Custom profile JSON format:* defaultAction (SCMP_ACT_ERRNO, SCMP_ACT_ALLOW, SCMP_ACT_LOG), syscalls list with names and action, architectures field
- *Profile placement:* /var/lib/kubelet/seccomp/ on the node, kubelet --seccomp-profile-root, making profiles available in kind by copying to the kind node container
- *Writing a custom profile:* starting from RuntimeDefault, adding specific syscall denials (ptrace, mount), building a minimal allow-list profile for a known workload
- *Violation debugging:* SCMP_ACT_LOG to identify denied syscalls without blocking, reading seccomp denials from audit logs, iterating on a profile
- *Applying custom profiles to pods:* securityContext.seccompProfile.type: Localhost with localhostProfile path, verifying the profile is active
- *Node OS hardening concepts:* disabling unnecessary services (systemctl), removing unneeded packages, closing open ports (ss -tlnp, ufw), principle of minimal node footprint; these concepts are tested at the knowledge level in kind (cannot fully simulate a bare-metal OS)

---

## Scope Boundaries

**Not covered:**
- seccomp at introductory level (RuntimeDefault, basic annotations): covered in 13-security-contexts/assignment-3
- AppArmor at introductory level: this topic is the primary treatment
- Runtime sandbox isolation (gVisor, kata): covered in 24-runtime-sandboxing
- Falco for runtime threat detection: covered in 26-runtime-security

---

## Cluster Requirements

Both assignments require the kind node to support AppArmor (assignment-1) and seccomp (assignment-2). AppArmor requires the host Linux kernel to have the AppArmor module loaded (standard on Ubuntu 24.04). seccomp custom profiles require copying JSON files to /var/lib/kubelet/seccomp/ inside the kind node container. The tutorial must document how to exec into the kind node and place the profile files. Single-node kind cluster is sufficient for all exercises.

---

## Recommended Order

Assignment-1 (AppArmor) before assignment-2 (seccomp + node hardening). Both can function independently but the two assignments reinforce each other as complementary Linux security layers.
