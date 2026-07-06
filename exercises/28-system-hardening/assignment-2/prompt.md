# Assignment Prompt: System Hardening: Assignment 2

**Series:** System Hardening (2 of 2)
**Topic slug:** system-hardening
**Topic directory:** exercises/28-system-hardening/assignment-2/

## Metadata

**Domain:** CKS: System Hardening (15%)
**Competencies:** Custom seccomp profiles, syscall allow/deny lists, violation debugging, node OS hardening concepts
**Prerequisites:** 13-security-contexts/assignment-3 (introductory seccomp), system-hardening/assignment-1

## Scope: In Scope

*seccomp profile types review*
- Unconfined: no syscall filtering (default if no seccomp profile is specified)
- RuntimeDefault: the container runtime's default seccomp profile (a reasonable baseline, blocks dangerous syscalls)
- Localhost: a custom profile loaded from a file on the node

*Custom seccomp profile JSON format*
- Top-level fields: defaultAction, architectures, syscalls
- defaultAction values: SCMP_ACT_ERRNO (deny with error), SCMP_ACT_ALLOW (allow all not listed), SCMP_ACT_LOG (log but allow), SCMP_ACT_KILL (kill the process)
- architectures: [SCMP_ARCH_X86_64, SCMP_ARCH_X86, SCMP_ARCH_X32]
- syscalls list: each entry has names (list of syscall names) and action
- Two profile strategies: deny-list (defaultAction: SCMP_ACT_ALLOW, deny specific dangerous syscalls) and allow-list (defaultAction: SCMP_ACT_ERRNO, allow only the syscalls the app needs)
- Common dangerous syscalls to deny: ptrace (process tracing), mount (filesystem mounting), unshare (namespace creation), clone with CLONE_NEWUSER, kexec_load

*Profile placement for kind*
- Custom profiles live at /var/lib/kubelet/seccomp/ on each node
- Copying a profile into the kind node: nerdctl cp profile.json kind-control-plane:/var/lib/kubelet/seccomp/profile.json
- The Localhost profile path in pod spec is relative to /var/lib/kubelet/seccomp/: localhostProfile: profile.json

*Writing a custom seccomp profile*
- Starting from RuntimeDefault as a reference point (the docker/default profile)
- Writing a deny-list profile that blocks ptrace, mount, unshare
- Writing an allow-list profile for a known workload (e.g., a simple HTTP server that only needs read, write, open, socket, bind, listen, accept, close, epoll_wait, sendto, recvfrom, exit)
- Testing the profile: does the app still run? Does it block a known-bad syscall?

*Violation debugging with SCMP_ACT_LOG*
- Setting defaultAction: SCMP_ACT_LOG to identify denied syscalls without blocking
- Reading seccomp denials: kernel audit messages (type=SECCOMP in dmesg or journalctl)
- The audit message format: syscall=<number>, comm="<process>", key="<profile>"
- Mapping syscall numbers to names: ausyscall --dump or looking up the number
- Iterating on an allow-list profile: observe what is denied, add the needed syscall, repeat

*Applying custom seccomp profiles to pods*
- securityContext.seccompProfile.type: Localhost
- securityContext.seccompProfile.localhostProfile: the path relative to /var/lib/kubelet/seccomp/
- At pod level vs container level (container level overrides pod level)
- Verifying the profile is active: check dmesg for SCMP_ACT_LOG output, or attempt a blocked syscall

*Node OS hardening concepts*
- Reducing the attack surface by removing unnecessary packages: apt-get remove --purge (conceptual in kind)
- Disabling unnecessary services: systemctl disable, systemctl stop
- Closing open ports: ss -tlnp to list listening services, understanding which are necessary
- Principle of minimal node footprint: only install what the node needs to run Kubernetes
- These are knowledge-level concepts for kind (cannot fully simulate bare-metal OS hardening); exercises describe what to check and what to look for, rather than making system changes

## Scope: Out of Scope

- seccomp at introductory level (RuntimeDefault annotation): covered in 13-security-contexts/assignment-3
- AppArmor profiles: covered in system-hardening/assignment-1
- Capabilities (add/drop at the pod spec level): covered in 13-security-contexts/assignment-2
- Runtime sandboxing (gVisor): covered in 24-runtime-sandboxing

## Environment

Single-node kind cluster. Custom seccomp profiles must be copied to /var/lib/kubelet/seccomp/ inside the kind node. The tutorial must document this workflow. SCMP_ACT_LOG violation debugging requires reading kernel audit messages from within the kind node container.

**Profile placement pattern for kind:**
```
nerdctl cp profile.json kind-control-plane:/var/lib/kubelet/seccomp/profile.json
```

**Reading seccomp denials:**
```
nerdctl exec kind-control-plane dmesg | grep SECCOMP
# or
nerdctl exec kind-control-plane journalctl -k | grep SECCOMP
```

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- All custom seccomp profiles must be valid JSON. Include the architectures field.
- The tutorial must include a working allow-list profile example that the learner can trace through.
- Node OS hardening exercises are knowledge-level: "describe what you would check" or "identify the issue in this ss output" rather than "run apt-get remove on the kind node".
- Tutorial namespace: `tutorial-system-hardening` (same as assignment-1).

## Exercise Distribution

- Level 1: Copy a provided custom seccomp profile to the kind node, apply it to a pod, verify the pod runs correctly; apply RuntimeDefault and compare behavior
- Level 2: Write a deny-list profile blocking ptrace and mount; copy it to the kind node, apply it, verify it does not break a standard nginx pod; attempt ptrace from inside the pod and confirm it fails
- Level 3 (debugging): Bare headings. Broken seccomp setups (profile file not at the expected path, invalid JSON in profile, SCMP_ACT_ERRNO blocking a syscall the app needs, wrong localhostProfile path)
- Level 4: Build an allow-list profile for a known workload using SCMP_ACT_LOG to discover the needed syscalls; iterate until the app runs correctly; switch to SCMP_ACT_ERRNO for the final profile
- Level 5 (debugging): A pod with a seccomp profile is intermittently crashing; the crash only happens under load; diagnose using audit logs that a specific syscall is being denied only when a code path is triggered under concurrent requests; add the syscall to the allow-list and verify stability
