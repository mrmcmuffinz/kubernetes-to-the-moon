# Assignment Prompt: System Hardening: Assignment 1

**Series:** System Hardening (1 of 2)
**Topic slug:** system-hardening
**Topic directory:** exercises/28-system-hardening/assignment-1/

## Metadata

**Domain:** CKS: System Hardening (15%)
**Competencies:** AppArmor profile authoring, complain vs enforce mode, applying profiles to pods, violation debugging
**Prerequisites:** 13-security-contexts/assignment-1, 01-pods/assignment-1

## Scope: In Scope

*AppArmor architecture*
- What AppArmor is: a Linux mandatory access control (MAC) system that restricts what a process can do based on a profile, enforced at the kernel level regardless of process privileges
- AppArmor modes: complain (log policy violations but allow), enforce (block policy violations), disabled
- aa-status: listing loaded profiles and their modes
- The distinction between AppArmor (path-based MAC) and seccomp (syscall filtering): they operate at different layers and complement each other

*Profile syntax*
- Profile header: profile <name> flags=(attach_disconnected) { ... }
- File rules: /path/to/file rwmlk (read, write, memory map, link, lock permissions)
- Glob patterns: /tmp/\*\* rw, /proc/\*\*/status r
- Network rules: network inet tcp
- Capability rules: capability net_admin
- Executable rules: /usr/bin/python3 ix (inherit and execute)
- Deny rules: deny /etc/shadow r
- The #include <abstractions/base> shorthand for common allow sets

*Profile development workflow*
- Start in complain mode: profile allows everything, violations are logged
- Load a profile: apparmor_parser -r /etc/apparmor.d/myprofile
- Verifying a profile is loaded: aa-status | grep myprofile
- Reading complain mode logs: /var/log/syslog or journalctl | grep apparmor
- aa-logprof (if available) to suggest rules from audit log
- Converting to enforce: apparmor_parser -r --write-cache with enforce flag, or modify flags=(enforce)
- Iterating: re-run the workload in complain, observe denials, add rules, repeat

*Writing a practical profile*
- Starting from a template that denies everything, building up allow rules
- A profile for a web server: allow reads from /var/www/\*\*, allow writes to /var/log/nginx/\*\*, allow network tcp, deny writes to /etc/\*\*
- A profile for a read-only utility container: allow reads of specific paths, deny all writes, deny network

*Applying AppArmor profiles to Kubernetes pods*
- Pre-1.30 annotation syntax: container.apparmor.security.beta.kubernetes.io/<container-name>: localhost/<profile-name>
- 1.30+ securityContext.appArmorProfile field: type: Localhost, localhostProfile: <profile-name>
- The profile must be loaded on every node where the pod can be scheduled
- Loading the profile into the kind node: copy the profile file into the kind control plane container and run apparmor_parser

*Verifying AppArmor enforcement*
- kubectl exec into a pod and attempt a restricted operation (write to /etc/, read /etc/shadow)
- Observe the permission denied error when in enforce mode
- Observe the allowed operation + audit log entry when in complain mode
- dmesg or journalctl inside the kind control plane for AppArmor audit messages: look for "audit: type=1400" lines

*Troubleshooting AppArmor denials*
- Pod stuck in Pending or failing with AppArmor profile not found: profile not loaded on the node
- AppArmor profile name mismatch between the annotation/field and the loaded profile name
- Too-restrictive profile blocking a legitimate operation: switch to complain, reproduce, read logs, add rule
- kubectl describe pod showing AppArmor-related events

## Scope: Out of Scope

- seccomp profiles: covered in system-hardening/assignment-2
- Capabilities (add/drop): covered in 13-security-contexts/assignment-2
- Runtime sandboxing (gVisor): covered in 24-runtime-sandboxing

## Environment

Single-node kind cluster. AppArmor requires the host Linux kernel to have AppArmor enabled (standard on Ubuntu 24.04). Profile files are loaded into the kind node container via nerdctl exec and apparmor_parser. The tutorial must document the profile loading workflow for the kind environment.

**Profile loading pattern for kind:**
```
# Copy profile to kind node
nerdctl cp myprofile kind-control-plane:/etc/apparmor.d/myprofile
# Load the profile on the kind node
nerdctl exec kind-control-plane apparmor_parser -r /etc/apparmor.d/myprofile
# Verify it is loaded
nerdctl exec kind-control-plane aa-status | grep myprofile
```

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- All profile files used in exercises must be syntactically valid AppArmor profiles.
- The tutorial must show both complain and enforce mode for at least one profile.
- Tutorial namespace: `tutorial-system-hardening`.

## Exercise Distribution

- Level 1: Check which AppArmor profiles are loaded (aa-status), apply a provided profile to a pod using the annotation, verify enforcement
- Level 2: Write a simple AppArmor profile that allows specific file reads and denies writes; load it and apply it to a pod; verify complain mode logging
- Level 3 (debugging): Bare headings. Broken AppArmor setups (profile not loaded on node, wrong profile name in annotation, profile too restrictive causing application crash)
- Level 4: Write a profile for a realistic workload (nginx web server: allow reads from document root, allow writes to log dir, allow network tcp, deny all else); load, apply, verify in enforce mode
- Level 5 (debugging): A pod is crashing with permission errors; diagnose using complain mode logs to identify what access the application needs; write a minimal allow-list profile that fixes the crash without over-permitting
