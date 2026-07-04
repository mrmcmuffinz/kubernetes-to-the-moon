# Assignment Prompt: Runtime Sandboxing — Assignment 1

**Series:** Runtime Sandboxing (1 of 1)
**Topic slug:** runtime-sandboxing
**Topic directory:** exercises/24-runtime-sandboxing/assignment-1/

## Metadata

**Domain:** CKS — Minimize Microservice Vulnerabilities (20%)
**Competencies:** RuntimeClass resource, gVisor installation and use, kata containers comparison, isolation verification
**Prerequisites:** 01-pods/assignment-1, 13-security-contexts/assignment-1

## Scope — In Scope

*RuntimeClass resource*
- The RuntimeClass resource: spec.handler (maps to a containerd runtime handler name), what "runtime handler" means in the containerd config
- kubectl get runtimeclass: listing available runtime classes
- RuntimeClass scheduling: spec.scheduling.nodeClassSelector for directing pods to nodes with the runtime installed
- How Kubernetes uses RuntimeClass: kubelet reads the runtimeClassName, calls containerd with the matching handler

*gVisor (runsc) installation and configuration*
- What gVisor is: a user-space kernel that intercepts syscalls from the container process, providing an additional isolation layer without a full VM
- Installing runsc on the kind node: download the runsc binary, configure /etc/containerd/config.toml to add a [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc] section, restart containerd
- Creating a RuntimeClass pointing to the runsc handler
- Assigning RuntimeClass to a pod: spec.runtimeClassName: gvisor-sandbox

*Verifying gVisor isolation*
- Running uname -r in a pod with and without RuntimeClass: gVisor reports its own kernel version
- Running dmesg in a gVisor pod (may be restricted) vs a standard pod
- Confirming the process runs under gVisor: /proc/1/exe pointing to runsc internals
- kubectl describe pod showing the runtimeClassName field

*Kata containers*
- What Kata containers are: each pod runs in a lightweight VM (QEMU or Cloud Hypervisor) giving full kernel isolation
- How Kata differs from gVisor: VM-based (full kernel) vs syscall interception (user-space kernel)
- RuntimeClass definition for Kata: spec.handler: kata (same pattern as gVisor)
- Why Kata may not be installable in kind (nested virtualization): if the host does not support KVM nested virt, exercises treat Kata as knowledge-level (describe the setup, no live demo)
- When to choose Kata vs gVisor: Kata for stronger isolation (multi-tenant, untrusted workloads), gVisor for lower overhead with reasonable isolation

*Trade-offs and when to use sandboxing*
- Performance overhead: gVisor has measurable latency for syscall-heavy workloads; Kata has VM startup overhead
- Workload compatibility: some syscalls not supported by gVisor (io_uring, some ioctl variants)
- Complementary relationship with seccomp and AppArmor: sandboxing adds depth, not a replacement
- Use cases: multi-tenant platforms, running untrusted code, PCI/HIPAA regulated workloads

## Scope — Out of Scope

- seccomp profiles: covered in 28-system-hardening/assignment-2
- AppArmor: covered in 28-system-hardening/assignment-1
- OPA/Gatekeeper policy to enforce RuntimeClass: covered in 25-opa-gatekeeper
- Pod security contexts: covered in 13-security-contexts

## Environment

Single-node kind cluster with gVisor installed on the kind node. The tutorial must document installing runsc and configuring containerd inside the kind control plane container, then creating the RuntimeClass. If gVisor installation fails due to host kernel constraints, the tutorial should provide a fallback: a pre-configured kind node image or a note on what the expected output should look like.

**gVisor containerd config snippet (for tutorial):**
```toml
[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
```

## Resource Gate

All Kubernetes resources are in scope.

## Topic-specific Conventions

- All exercises that require a specific RuntimeClass must first verify the RuntimeClass exists before creating the pod.
- Tutorial namespace: `tutorial-runtime-sandboxing`.
- Live exercises focus on gVisor. Kata coverage is conceptual/knowledge-level in exercises.

## Exercise Distribution

- Level 1: List RuntimeClasses in the cluster, create a pod with a given RuntimeClass, verify it is using the sandbox runtime
- Level 2: Install a RuntimeClass for gVisor, assign it to a Deployment, verify all pods use the sandbox
- Level 3 (debugging): Bare headings. Broken RuntimeClass configurations (handler name mismatch, RuntimeClass not found, containerd handler not configured)
- Level 4: Full workflow — install runsc on the kind node, create a RuntimeClass, deploy a workload, verify isolation, compare with a non-sandboxed pod
- Level 5 (debugging): A pod is failing to start with an unknown runtime handler error; diagnose and fix the containerd configuration and RuntimeClass definition
