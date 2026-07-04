# Mumshad CKA Course to Exam Competency Map

**Course:** Certified Kubernetes Administrator (CKA) with Practice Tests
**Instructor:** Mumshad Mannambeth / KodeKloud
**Total:** 314 lectures, 26 hours video, 18 sections

---

## Purpose

This file maps each Mumshad course section to the CKA exam competencies it covers.
The prompt builder uses this to:

- Determine which course material the learner has studied before generating a prompt
- Calibrate exercise depth to match the level of instruction received
- Identify when a CKA competency is taught across multiple course sections

---

## Section-to-Competency Map

### S1: Introduction (Lectures 1-5)

Course orientation only. No CKA competencies directly covered.

### S2: Core Concepts (Lectures 6-49)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 6-17 | Cluster architecture, etcd, API server, scheduler, kubelet, kube-proxy | Domain 1: Prepare infrastructure, understand extension interfaces |
| 18-32 | Pods, ReplicaSets, Deployments | Domain 2: Application deployments, self-healing primitives |
| 33-37 | Services (ClusterIP, NodePort, LoadBalancer) | Domain 3: Service types and endpoints |
| 38-40 | Namespaces | Foundation for RBAC, Network Policies |
| 41-49 | Imperative vs declarative, kubectl apply | General exam technique |

### S3: Scheduling (Lectures 50-87)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 50-53 | Manual scheduling | Domain 2: Pod admission and scheduling |
| 54-56 | Labels and selectors | Foundation for services, scheduling, network policies |
| 57-63 | Taints, tolerations, node selectors, node affinity | Domain 2: Pod admission and scheduling |
| 64-68 | Resource requirements and limits | Domain 2: Pod admission and scheduling |
| 69-71 | DaemonSets | Domain 2: Self-healing primitives |
| 72-74 | Static pods | Domain 5: Troubleshoot cluster components |
| 75-76 | Priority classes | Domain 2: Pod admission and scheduling |
| 77-81 | Multiple schedulers, scheduler profiles | Domain 2: Pod admission and scheduling |
| 82-87 | Admission controllers (validating, mutating) | Domain 2: Pod admission and scheduling |

### S4: Logging & Monitoring (Lectures 88-94)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 88-91 | Monitor cluster components (metrics-server, kubectl top) | Domain 5: Monitor resource usage |
| 92-94 | Application logs (kubectl logs) | Domain 5: Container output streams |

### S5: Application Lifecycle Management (Lectures 95-129)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 95-98 | Rolling updates and rollbacks | Domain 2: Application deployments, rolling updates |
| 100-103 | Commands and arguments | Domain 2: Application deployments |
| 104-113 | ConfigMaps, Secrets, encryption at rest | Domain 2: ConfigMaps and Secrets |
| 115-120 | Multi-container pods, init containers | Domain 2: Self-healing primitives |
| 122-129 | Autoscaling (HPA, VPA, in-place resize) | Domain 2: Workload autoscaling |

### S6: Cluster Maintenance (Lectures 130-142)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 130-132 | OS upgrades (drain, cordon, uncordon) | Domain 1: Manage cluster lifecycle |
| 133-137 | Kubernetes version upgrades with kubeadm | Domain 1: Manage cluster lifecycle, kubeadm |
| 138-142 | etcd backup and restore | Domain 1: Manage cluster lifecycle |

### S7: Security (Lectures 143-187)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 143-145 | Security primitives, authentication | Domain 1: RBAC (foundation) |
| 146-159 | TLS (basics, K8s certs, creation, viewing, Certificates API, KubeConfig) | Domain 1: RBAC, Domain 5: Troubleshoot cluster components |
| 160-168 | API groups, authorization, RBAC (Roles, ClusterRoles, bindings) | Domain 1: RBAC |
| 169-171 | Service accounts | Domain 1: RBAC |
| 172-174 | Image security | Domain 1: Prepare infrastructure |
| 175-178 | Security contexts | Domain 2: Pod admission |
| 179-182 | Network policies | Domain 3: Network Policies |
| 184-187 | CRDs, custom controllers, operator framework | Domain 1: CRDs and operators |

### S8: Storage (Lectures 188-203)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 188-192 | Docker/container storage concepts, CSI | Domain 1: Understand extension interfaces (CSI) |
| 193-198 | Volumes, PersistentVolumes, PersistentVolumeClaims | Domain 4: Manage PVs and PVCs |
| 201-203 | Storage classes | Domain 4: Storage classes, dynamic provisioning |

### S9: Networking (Lectures 204-240)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 204-211 | Prerequisites (switching, routing, DNS, namespaces, Docker networking, CNI) | Domain 3: Pod connectivity, Domain 1: CNI |
| 212-222 | Cluster networking, pod networking, CNI in K8s, Weave, IPAM | Domain 3: Pod connectivity |
| 223-226 | Service networking | Domain 3: Service types and endpoints |
| 227-230 | DNS in Kubernetes, CoreDNS | Domain 3: CoreDNS |
| 231-237 | Ingress (controllers, resources, annotations, rewrite-target) | Domain 3: Ingress controllers and resources |
| 238-240 | Gateway API | Domain 3: Gateway API |

### S10: Design and Install a Kubernetes Cluster (Lectures 241-245)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 241-244 | Cluster design, infrastructure choices, HA, etcd in HA | Domain 1: Prepare infrastructure, HA control plane |

### S11: Install Kubernetes the kubeadm way (Lectures 246-251)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 246-251 | kubeadm init, join, cluster deployment | Domain 1: Create and manage clusters with kubeadm |

### S12: Helm Basics (Lectures 252-262)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 252-262 | Helm introduction, charts, values, lifecycle management | Domain 1: Helm |

### S13: Kustomize Basics (Lectures 263-284)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 263-284 | Kustomize ideology, kustomization.yaml, transformers, patches, overlays, components | Domain 1: Kustomize |

### S14: Troubleshooting (Lectures 285-296)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 285-288 | Application failure | Domain 5: All troubleshooting competencies |
| 289-291 | Control plane failure | Domain 5: Troubleshoot cluster components |
| 292-294 | Worker node failure | Domain 5: Troubleshoot clusters and nodes |
| 295-296 | Network troubleshooting | Domain 5: Troubleshoot services and networking |

### S15: Other Topics (Lectures 297-300)

| Lectures | Topic | CKA Competencies |
|---|---|---|
| 297-300 | JSON Path, advanced kubectl commands | General exam technique |

### S16: Lightning Labs (Lectures 301-302)

Integrated practice across multiple domains. Not specific to one competency.

### S17: Mock Exams (Lectures 303-308)

Full exam simulations. Cover all domains.

### S18: Bonus Section (Lectures 309-314)

Course wrap-up. No new CKA competencies.

---

## Study Plan Day to Section Map

This maps the daily study plan to course sections, so the prompt builder can determine
which course material has been covered at any given point.

| Day | Sections Covered | Status |
|---|---|---|
| Day 1 | S1, S2 (through lecture 17) | Complete |
| Day 2 | S2 (lectures 18-32) | Complete |
| Day 3 | S2 (lectures 33-49), S3 (lectures 50-63) | Complete |
| Day 4 | S3 (lectures 64-87), S4 (lectures 88-94) | Complete |
| Day 5 | S5 (lectures 95-129) | Complete |
| Day 6 | S6 (lectures 130-142), S7 (lectures 143-159) | Complete |
| Day 7 | S7 (lectures 160-182) | |
| Day 8 | S7 (lectures 183-187), S8 (lectures 188-203) | |
| Day 9 | S9 (lectures 204-222) | |
| Day 10 | S9 (lectures 223-240) | |
| Day 11 | S10 (lectures 241-245), S11 (lectures 246-251), S12 (lectures 252-262) | |
| Day 12 | S13 (lectures 263-284) | |
| Day 13 | S14 (lectures 285-296), S15 (lectures 297-300), S16 (lectures 301-302) | |
| Day 14 | S17 (lectures 303-308), S18 (lectures 309-314) | |
