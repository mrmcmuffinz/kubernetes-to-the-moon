# Killercoda CKA Scenario Course

Source: https://killercoda.com/cka
Total: 32 scenarios across 5 CKA domains

## Setup / Introduction

1. **Introduction** - Get familiar with the CKA course and the scenario environments
2. **Playground** - Two-node environment with current version of the CKA exam
3. **Playground One Node** - Single-node environment with current version of the CKA exam

## Domain 1: Storage

StorageClasses, dynamic provisioning, volume types, access modes, persistent volumes and persistent volume claims

1. **StorageClass and Dynamic Provisioning** - Create StorageClasses and understand reclaim policies
2. **PV Access Modes** - PV Access Modes for PostgreSQL
3. **Volume Can't Be Mounted** - Troubleshoot volume mount issues after node drain
4. **PVC Data Migration** - Migrate volume data between PVCs with different reclaim policies

## Domain 2: Workloads and Scheduling

Deployments, rolling updates, ConfigMaps, Secrets, autoscaling, and Pod scheduling

1. **Deployment and StatefulSet Rollouts** - Manage rollout history and rollbacks
2. **Init Container and Secret** - Deployment with a broken init container needs more Secrets
3. **DaemonSet HostPath Configurator** - Create a DaemonSet that configures nodes
4. **Node Selector and Scheduling** - Schedule Pods on specific nodes using labels and manual scheduling
5. **Node Taints and Tolerations** - Taint a node to influence scheduling
6. **Scheduling Pod Affinity** - Schedule Pods using pod affinity rules
7. **Scheduling Pod Anti Affinity** - Schedule Pods using pod anti-affinity rules
8. **Scheduling Priority** - Understand PriorityClasses and pod preemption

## Domain 3: Servicing and Networking

Services, NetworkPolicies, the Gateway API, Ingress, and CoreDNS

1. **NetworkPolicy Isolation** - Create default-deny and targeted allow NetworkPolicies
2. **Troubleshoot NetworkPolicies** - Fix broken NetworkPolicies
3. **App Goes Public** - Expose an app with LoadBalancer and autoscale
4. **Gateway API Setup** - Configure Gateway API routes and traffic splitting
5. **CoreDNS Misconfigured** - Fix a broken CoreDNS configuration
6. **TLS Secret and HTTPS** - Create TLS Secret and enforce TLS 1.3

## Domain 4: Troubleshooting

Cluster and node troubleshooting, component debugging, resource monitoring, container logs, and services/networking issues

1. **Apiserver Crash** - Crash that apiserver and check them logs
2. **Apiserver Misconfigured** - Fix a misconfigured kube-apiserver
3. **Deployment Scaling Issue** - Troubleshoot Deployment HPA
4. **Application Multi Container Issue** - Troubleshoot a multi-container Deployment
5. **Applications Misconfigured** - Fix misconfigured Deployments
6. **Components Misconfigured** - Fix misconfigured cluster components

## Domain 5: Cluster Architecture, Installation and Configuration

RBAC, kubeadm, cluster lifecycle, HA, Helm, Kustomize, CRDs, and operators

1. **RBAC for CronJob** - Adjust RBAC for a CronJob
2. **RBAC User Permissions** - Control User permissions using RBAC
3. **Operator Setup and CRD** - Fix operator RBAC and install a CRD
4. **Operator Namespace Creator** - Create an Operator which creates Namespaces
5. **Static Pod Move** - Move a static Pod to another node
6. **Cluster Setup and Node Join** - Setup a Kubeadm cluster, join a node and install a CNI
7. **Cluster Upgrade** - Upgrade a kubeadm cluster
8. **Cluster Certificate Management** - Manage cluster certificates using kubeadm

## Notes

- All scenarios marked with ✓ in the HTML (all 32 scenarios completed)
- Each scenario includes a video walkthrough (avg 11 min, 5.5h total)
- Course by trainer Kim Wüstkamp
- Scenarios can be solved in the Exam Desktop environment
- Use code KILLER30 for 30% off CKA exam purchase
