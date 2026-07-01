# Troubleshooting Assignment 3: Node and Kubelet Troubleshooting

This is the third assignment in the Troubleshooting series, focusing on diagnosing and repairing kubelet failures and node issues. While assignment-1 covered application-layer troubleshooting and assignment-2 tackled control plane component failures, this assignment trains you to identify and fix the failures that cause nodes to become NotReady. You will work with hands-on breaking exercises where every setup command intentionally breaks something on a worker node, and your task is to diagnose the root cause, fix it, and verify the node returns to service. This assignment completes the node-layer troubleshooting skills needed for the CKA exam. Assignment-4 will cover network troubleshooting (Service endpoints, DNS, CNI issues).

## Files

| File | Purpose |
|------|---------|
| `README.md` | This overview |
| `prompt.md` | Generation inputs for the k8s-homework-generator skill |
| `troubleshooting-tutorial.md` | Complete worked example of kubelet failure diagnosis and recovery |
| `troubleshooting-homework.md` | 15 hands-on debugging exercises |
| `troubleshooting-homework-answers.md` | Solutions with full diagnostic workflows |

## Recommended Workflow

Read the tutorial file first to learn the systematic approach for diagnosing kubelet and node failures. The tutorial walks through a complete real-world scenario from detecting a NotReady node through identifying the kubelet service failure, accessing the node, reading systemd and journalctl logs, correcting the configuration, restarting the kubelet, and verifying recovery. Once you understand the diagnostic pattern, work through the 15 exercises in order. Each exercise setup includes commands that break a worker node in a specific way. Your task is to apply the diagnostic workflow, identify the root cause, fix the configuration or service state, and verify the node returns to Ready status. The exercises progress from simple service-stopped failures to complex multi-component issues requiring careful analysis of kubelet configuration files, systemd units, and runtime connectivity.

## Difficulty Progression

Level 1 exercises break kubelet in obvious ways (service stopped, binary path wrong, config file missing) that produce clear error messages in systemctl status output. Level 2 introduces configuration file syntax errors and flag misconfigurations that require reading kubelet config YAML and comparing it to working examples. Level 3 covers certificate and runtime connectivity issues where the kubelet service starts but cannot authenticate to the API server or communicate with containerd. Level 4 presents multi-component failures where you must fix both kubelet configuration and related components (runtime socket, CNI plugins, systemd unit files) in sequence. Level 5 exercises require full diagnostic workflows across multiple nodes, interpreting subtle failure modes, and applying the complete troubleshooting process from detection through verification that pods can schedule on the recovered node.

## Prerequisites

This assignment assumes you have completed 17-cluster-lifecycle/assignment-1 and assignment-2 to understand kubelet architecture, systemd unit structure, and kubeadm cluster setup. You should be comfortable with kubectl describe node output, systemd service management (systemctl status, restart, daemon-reload), and journalctl log reading. The assignment also assumes familiarity with the control plane troubleshooting workflow from 19-troubleshooting/assignment-2, as the diagnostic approach is similar (identify the broken component from cluster-level symptoms, access the node running that component, read service logs, fix the configuration, restart the service, verify recovery). Follow the cluster setup instructions in [docs/cluster-setup.md#multi-node-kind-cluster](../../../docs/cluster-setup.md#multi-node-kind-cluster) to create the required multi-node environment.

## Cluster Requirements

This assignment requires a multi-node kind cluster with 1 control-plane node and 3 worker nodes to allow safely breaking worker nodes without affecting cluster operation. Follow the instructions in [docs/cluster-setup.md#multi-node-kind-cluster](../../../docs/cluster-setup.md#multi-node-kind-cluster) to create the cluster. The exercises access worker nodes using `nerdctl exec kind-worker bash` to run breaking commands and diagnostic steps inside the node container. All exercises break worker nodes only, never the control-plane node, to maintain a stable cluster for verification steps.

## Estimated Time Commitment

Level 1 exercises take 5 to 10 minutes each as the failures are immediately visible in systemctl status output and the fixes are straightforward (restart the service, correct a systemd unit path, restore a config file). Level 2 exercises require 10 to 15 minutes for identifying configuration syntax errors and flag misconfigurations by reading kubelet config YAML and comparing against working examples. Level 3 exercises take 15 to 20 minutes as you must distinguish certificate issues from runtime connectivity problems by analyzing journalctl logs and testing containerd socket availability. Level 4 exercises require 20 to 25 minutes for diagnosing multi-component failures where you must fix the kubelet configuration, restart the runtime service, reload systemd units, and verify that all components are working together. Level 5 exercises take 25 to 35 minutes for complex scenarios involving multiple nodes, subtle failure modes requiring careful log analysis, and full verification that includes scheduling test pods on recovered nodes and confirming they run successfully.

## Scope Boundary and What Comes Next

This assignment covers kubelet service failures, kubelet configuration errors, and runtime connectivity issues that cause nodes to become NotReady. It deliberately does not cover application-layer troubleshooting (pod crashes, container errors, config misconfigurations), which is covered in assignment-1, or control plane component failures (API server, scheduler, controller-manager, etcd), which is covered in assignment-2. Network troubleshooting including Service endpoint issues, CoreDNS failures, CNI plugin problems, and kube-proxy misconfigurations is deferred to assignment-4, the final troubleshooting assignment. Node upgrades and kubeadm cluster lifecycle management are covered in the 17-cluster-lifecycle series and are not repeated here. Real hardware node conditions like MemoryPressure and DiskPressure are covered conceptually in the tutorial but are not hands-on reproducible in kind clusters, so the exercises focus on kubelet service and configuration failures that are realistic for the exam.

## Key Takeaways After Completing This Assignment

After completing this assignment, you should be able to detect NotReady nodes from kubectl output, interpret node conditions and events from kubectl describe node, access worker nodes to run diagnostic commands, identify kubelet service failures using systemctl status and journalctl logs, diagnose kubelet configuration errors by reading /var/lib/kubelet/config.yaml and systemd unit files, distinguish kubelet issues from containerd runtime issues, fix kubelet systemd units and reload the daemon, correct kubelet configuration files and restart the service, verify that nodes return to Ready status after fixes, and confirm that pods can schedule and run on recovered nodes. You should recognize common kubelet failure patterns including wrong binary paths in systemd units (the Simulator B Q6 scenario), missing or incorrect kubeconfig paths, CA certificate path errors, containerd socket path misconfigurations, and config file syntax errors. You should know the complete diagnostic workflow from cluster-level symptom detection through root cause identification, configuration correction, service restart, and verification that the fix resolved the issue.
