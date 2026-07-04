# Runtime Sandboxing: Assignment 1

This is the only assignment in the runtime sandboxing series. It covers Kubernetes RuntimeClass, gVisor installation and configuration on a kind node, isolation verification, and a conceptual treatment of Kata containers. The assignment builds on the pod fundamentals covered in 01-pods/assignment-1 and the container-level security topics from 13-security-contexts/assignment-1. It is part of the broader Minimize Microservice Vulnerabilities cluster in the curriculum, sitting alongside OPA/Gatekeeper (25), runtime security with Falco (26), and secrets management (27).

## Files

| File | Description |
|---|---|
| `README.md` | This overview |
| `prompt.md` | Generator input used to produce this assignment |
| `runtime-sandboxing-tutorial.md` | Step-by-step tutorial covering gVisor installation, RuntimeClass, and isolation verification |
| `runtime-sandboxing-homework.md` | 15 progressive exercises |
| `runtime-sandboxing-homework-answers.md` | Complete solutions with explanations |

## Recommended Workflow

Work through the tutorial before attempting any exercises. The tutorial installs gVisor on the kind control-plane node, configures containerd, creates a RuntimeClass, and deploys a pod that verifies the sandbox is active. It also covers the containerd runtime handler concept in enough depth that the debugging exercises make sense without additional research. After finishing the tutorial, attempt each exercise on your own. The Level 3 and Level 5 debugging exercises are designed to be worked without hints, so treat the objective statement as the only information you have and use `kubectl describe`, `kubectl get -o yaml`, and `nerdctl exec` into the node to investigate.

## Difficulty Progression

Level 1 exercises build fluency with the RuntimeClass resource itself: creating a RuntimeClass with a named handler, assigning it to a pod via `spec.runtimeClassName`, and verifying the assignment took effect. Level 2 exercises combine RuntimeClass with Deployments and add the containerd configuration layer, requiring you to verify that all replicas are running under the sandbox. Level 3 exercises are debugging tasks with bare headings; the objectives do not reveal the nature or count of problems present, because identifying the failure mode from symptoms is the point. Level 4 exercises simulate the full gVisor setup workflow from binary installation through isolation verification and comparison with a non-sandboxed pod. Level 5 exercises present multi-symptom broken configurations spanning both the containerd handler definition and the RuntimeClass resource; diagnose and fix whatever is needed to make the workload start.

## Prerequisites

This assignment assumes you have completed 01-pods/assignment-1 (pod construction, `kubectl describe` diagnostic workflow, container image fundamentals) and 13-security-contexts/assignment-1 (pod and container security contexts, privilege escalation controls). You should be comfortable writing pod specs from memory and reading `kubectl describe pod` output before starting Level 4. The cluster setup for this assignment uses the single-node kind profile documented in [docs/cluster-setup.md](../../../docs/cluster-setup.md#single-node-kind-cluster), with gVisor installed on the kind node as described in the tutorial.

## Cluster Requirements

A single-node kind cluster is the base for this assignment. Follow the setup instructions at [docs/cluster-setup.md#single-node-kind-cluster](../../../docs/cluster-setup.md#single-node-kind-cluster). Beyond the base cluster, the tutorial walks through installing the gVisor `runsc` binary inside the kind control-plane container and adding the containerd runtime handler configuration. No MetalLB, Gateway API CRDs, or metrics-server are needed. If the host kernel does not support the gVisor installation (because nested virtualization or certain syscall constraints are not available), the tutorial provides fallback notes with expected output so you can follow along conceptually.

## Estimated Time Commitment

The tutorial takes thirty to forty-five minutes, with most of the time spent on the gVisor installation steps and verifying that the runtime is active. Level 1 exercises run five to ten minutes each once gVisor is installed. Level 2 exercises take ten to fifteen minutes each. Level 3 debugging exercises take fifteen to twenty minutes each, because they involve reading containerd configuration errors and correlating them with Kubernetes events. Level 4 exercises take twenty to thirty minutes each, covering the full installation workflow plus isolation comparison. Level 5 exercises take twenty-five to forty minutes each, as they combine multiple failure points across the containerd layer and the Kubernetes RuntimeClass definition.

## Scope Boundary and What Comes Next

This assignment deliberately excludes seccomp profiles (covered in 28-system-hardening/assignment-2), AppArmor (covered in 28-system-hardening/assignment-1), and OPA/Gatekeeper policies that enforce RuntimeClass usage across a namespace (covered in 25-opa-gatekeeper). Pod security contexts and the securityContext fields that control privilege levels are covered in 13-security-contexts and are assumed knowledge here, not re-taught. The assignment treats Kata containers at the knowledge level only: you will understand how Kata differs from gVisor and how a RuntimeClass for Kata would be defined, but no live Kata exercises are included because nested virtualization constraints make Kata unreliable in kind environments.

## Key Takeaways After Completing This Assignment

After completing all 15 exercises you should be able to explain what a RuntimeClass is, how `spec.handler` maps to a containerd runtime handler name, and why that mapping matters for isolation. You should be able to install the gVisor `runsc` binary on a kind node using `nerdctl exec`, add the containerd configuration block that registers the `runsc` handler, restart containerd, and verify the handler is registered. You should be able to create a RuntimeClass, assign it to a pod via `spec.runtimeClassName`, and confirm the pod is running under gVisor by checking `uname -r` output and the pod's runtimeClassName field. You should also be able to diagnose the most common failure modes: handler name mismatch between the RuntimeClass and the containerd config, missing containerd configuration, and RuntimeClass not found errors in pod events.
