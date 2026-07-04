# Assignment Registry

**Last updated:** 2026-07-04

---

## Purpose

This file tracks every homework assignment in this repository: what exists, what each
assignment covers, and what it explicitly defers. The prompt builder consults this registry
before writing any new prompt to prevent scope overlap and to generate accurate
cross-references.

When a new assignment is generated, update this file with its scope summary and
cross-references.

---

## Status Summary

**Exercises 01-19:** 45 assignments content-complete as of 2026-04-19.

- pods 1-7, rbac 1-2, tls-and-certificates 1-3, security-contexts 1-3, cluster-lifecycle 1-3,
  helm 1-3, kustomize 1-3, crds-and-operators 1-3, services 1-3, ingress-and-gateway-api 1-5,
  coredns 1-3, network-policies 1-3, storage 1-3, troubleshooting 1-4, autoscaling/1,
  jobs-and-cronjobs/1, statefulsets/1, admission-controllers/1, pod-security/1

**Exercise 20:** `exercises/20-cluster-setup/` contains VM and Raspberry Pi cluster build
guides. Not structured as assignments (no tutorial/homework/answers files).

**Exercises 21+:** Planned topics listed at the bottom of this file. None have content yet.

---

## Assignments

### exercises/01-pods/assignment-1: Pod Fundamentals

**Series:** Pod-focused (1 of 7)
**CKA domain:** Workloads & Scheduling
**Cluster:** Single-node kind

**Covers:**
- Pod spec structure and required fields
- Single-container pod construction (imperative and declarative)
- Multi-container pods (basic mechanics only, not named patterns)
- Container commands and arguments (command vs args, Docker ENTRYPOINT/CMD equivalence)
- Environment variables as literal values
- Environment variables via downward API (fieldRef, resourceFieldRef)
- Restart policy (Always, OnFailure, Never)
- Image pull policy (Always, IfNotPresent, Never)
- Labels and annotations on pods
- Basic init containers (sequential execution, blocking main containers)
- Pod phases and container statuses
- kubectl describe and kubectl logs for pod inspection

**Defers to:**
- Assignment 2: ConfigMaps and Secrets as env vars or volume mounts
- Assignment 3: Probes, lifecycle hooks, terminationGracePeriodSeconds
- Assignment 4: Node selectors, affinity, taints, tolerations, topology spread
- Assignment 5: Resource requests and limits, QoS classes
- Assignment 6: Sidecar, ambassador, adapter patterns, native sidecars
- Assignment 7: ReplicaSets, Deployments, DaemonSets
- security-contexts: runAsUser, capabilities, readOnlyRootFilesystem

---

### exercises/01-pods/assignment-2: Pod Configuration Injection

**Series:** Pod-focused (2 of 7)
**CKA domain:** Workloads & Scheduling
**Cluster:** Single-node kind

**Covers:**
- ConfigMaps (create from literals, files, directories; consume as env vars and volumes)
- Secrets (create, consume, types, base64 encoding)
- Projected volumes (combining ConfigMap, Secret, downward API, serviceAccountToken)
- Downward API (fieldRef, resourceFieldRef as env vars and volume files)
- Immutable ConfigMaps and Secrets

**Defers to:**
- Assignment 3: How probes interact with configuration changes
- Storage assignment: PersistentVolumes (projected volumes are in-memory only)

---

### exercises/01-pods/assignment-3: Pod Health and Observability

**Series:** Pod-focused (3 of 7)
**CKA domain:** Workloads & Scheduling
**Cluster:** Single-node kind

**Covers:**
- Liveness probes (httpGet, tcpSocket, exec)
- Readiness probes (same three types, effect on service endpoints)
- Startup probes (for slow-starting containers)
- Probe parameters (initialDelaySeconds, periodSeconds, failureThreshold, successThreshold)
- Lifecycle hooks (postStart, preStop)
- terminationGracePeriodSeconds and SIGTERM/SIGKILL behavior
- Diagnostic workflow for unhealthy pods (events, logs, describe)

**Defers to:**
- Assignment 4: How probes interact with scheduling decisions
- Services assignment: How readiness affects service endpoint membership

---

### exercises/01-pods/assignment-4: Pod Scheduling and Placement

**Series:** Pod-focused (4 of 7)
**CKA domain:** Workloads & Scheduling
**Cluster:** Multi-node kind (1 control-plane, 3 workers, introduced in this assignment)

**Covers:**
- nodeSelector
- Node affinity (requiredDuringSchedulingIgnoredDuringExecution, preferredDuringSchedulingIgnoredDuringExecution)
- Pod affinity and anti-affinity
- Taints and tolerations (NoSchedule, PreferNoSchedule, NoExecute)
- Topology spread constraints
- Priority classes and preemption

**Defers to:**
- Assignment 5: How resource requests interact with scheduling
- Workload Controllers: How DaemonSets bypass normal scheduling

---

### exercises/01-pods/assignment-5: Pod Resources and QoS

**Series:** Pod-focused (5 of 7)
**CKA domain:** Workloads & Scheduling
**Cluster:** Multi-node kind

**Covers:**
- CPU and memory requests and limits
- QoS class assignment (Guaranteed, Burstable, BestEffort)
- OOMKill behavior and CPU throttling
- LimitRange (default requests/limits per namespace)
- ResourceQuota (aggregate limits per namespace)
- How resource requests affect scheduling decisions

**Defers to:**
- Assignment 7: How Deployment replicas interact with ResourceQuota
- HPA/VPA: Covered within this assignment as part of autoscaling

---

### exercises/01-pods/assignment-6: Multi-Container Patterns

**Series:** Pod-focused (6 of 7)
**CKA domain:** Workloads & Scheduling
**Cluster:** Multi-node kind

**Covers:**
- Sidecar pattern (log shipping, config reload, TLS proxy)
- Ambassador pattern (proxy for external services)
- Adapter pattern (format conversion, metric normalization)
- Native sidecars (init containers with restartPolicy: Always)
- Shared process namespace (shareProcessNamespace: true)
- Shared volumes between containers (emptyDir for inter-container communication)

**Defers to:**
- Services assignment: How multi-container pods interact with services
- Network Policies: Traffic rules apply at the pod level, not container level

---

### exercises/01-pods/assignment-7: Workload Controllers

**Series:** Pod-focused (7 of 7)
**CKA domain:** Workloads & Scheduling
**Cluster:** Multi-node kind

**Covers:**
- ReplicaSet spec (replicas, selector, template, selector-matches-template contract)
- ReplicaSet reconciliation, adoption of orphaned pods, scaling
- Deployments (spec, RollingUpdate vs Recreate strategy, maxSurge, maxUnavailable)
- Rollout workflow (status, history, undo, pause, resume, --to-revision)
- DaemonSets (spec, scheduling behavior, tolerations for control-plane nodes)
- Revision history and revisionHistoryLimit

**Defers to:**
- Helm: Deployment lifecycle managed via Helm releases
- Services: How Deployments are exposed via services
- Troubleshooting: Diagnosing failed rollouts and stuck deployments

---

### exercises/12-rbac/assignment-1: RBAC (namespace-scoped)

**Series:** RBAC (1 of 2)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind

**Covers:**
- Roles and RoleBindings (namespace-scoped)
- Service accounts
- User certificate creation for kind clusters
- kubeconfig context conventions (user@cluster format)
- kubectl auth can-i verification
- Permission design patterns for namespace-scoped access

**Defers to:**
- rbac/assignment-2: ClusterRoles, ClusterRoleBindings, cluster-scoped resources, aggregated ClusterRoles
- CRDs and Operators: RBAC for custom resources
- tls-and-certificates: Certificate creation and management in depth

---

### exercises/17-cluster-lifecycle/assignment-1: Cluster Installation

**Series:** Cluster Lifecycle (1 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Multi-node kind
**Generation order:** 1

**Scope:**
- Node prerequisites and preparation (container runtime, networking, ports, swap disabled)
- kubeadm init workflow and configuration
- kubeadm join for worker nodes
- Control plane component verification
- Extension interfaces (CNI, CSI, CRI) at conceptual level
- Cluster health checks

**Prerequisites:** None (foundational topic)
**Adjacent assignments:** tls-and-certificates (certificates build on cluster PKI understanding)

---

### exercises/17-cluster-lifecycle/assignment-2: Cluster Upgrades and Maintenance

**Series:** Cluster Lifecycle (2 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Multi-node kind
**Generation order:** 2

**Scope:**
- Upgrade planning (kubeadm upgrade plan, version compatibility)
- Control plane node upgrade workflow
- Worker node upgrade workflow
- Node drain best practices and scenarios
- Node cordon and uncordon
- Post-upgrade verification

**Prerequisites:** cluster-lifecycle/assignment-1
**Adjacent assignments:** cluster-lifecycle/assignment-3 (etcd operations build on maintenance workflows)

---

### exercises/17-cluster-lifecycle/assignment-3: etcd Operations and High Availability

**Series:** Cluster Lifecycle (3 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Multi-node kind (may need custom kind config for etcd exercises)
**Generation order:** 3

**Scope:**
- etcd architecture in Kubernetes
- etcd backup with etcdctl snapshot save
- etcd restore with etcdctl snapshot restore
- etcd health and data integrity verification
- HA control plane with stacked etcd
- HA control plane with external etcd

**Prerequisites:** cluster-lifecycle/assignment-2
**Adjacent assignments:** troubleshooting/assignment-2 (etcd failures as control plane troubleshooting)

---

### exercises/18-tls-and-certificates/assignment-1: TLS Fundamentals and Certificate Creation

**Series:** TLS and Certificates (1 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 4

**Scope:**
- Kubernetes PKI overview
- Certificate anatomy (subject, issuer, validity, key usage)
- Creating certificates with openssl (keys, CSRs, signing)
- Viewing certificate details with openssl x509
- Certificate file locations on control plane nodes
- Certificate validation and trust chains

**Prerequisites:** cluster-lifecycle/assignment-1 (understanding of control plane components)
**Adjacent assignments:** tls-and-certificates/assignment-2 (Certificates API builds on manual cert creation)

---

### exercises/18-tls-and-certificates/assignment-2: Certificates API and kubeconfig

**Series:** TLS and Certificates (2 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 5

**Scope:**
- CertificateSigningRequest resource
- CSR creation and submission
- CSR approval and denial workflow
- kubeconfig structure (clusters, users, contexts)
- Certificate-based authentication in kubeconfig
- kubeconfig context management

**Prerequisites:** tls-and-certificates/assignment-1
**Adjacent assignments:** rbac (authentication feeds authorization)

---

### exercises/18-tls-and-certificates/assignment-3: Certificate Troubleshooting

**Series:** TLS and Certificates (3 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 6

**Scope:**
- Diagnosing certificate expiration
- Certificate subject/issuer mismatches
- Wrong CA in certificate chain
- Certificate permission issues
- Component certificate rotation
- User certificate renewal patterns

**Prerequisites:** tls-and-certificates/assignment-2
**Adjacent assignments:** troubleshooting/assignment-2 (cert expiration as control plane failure)

---

### exercises/12-rbac/assignment-2: RBAC (cluster-scoped)

**Series:** RBAC (2 of 2)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 7

**Scope:**
- ClusterRoles and ClusterRoleBindings
- Cluster-scoped resources (nodes, namespaces, PersistentVolumes, clusterroles themselves)
- Aggregated ClusterRoles (aggregationRule with matchLabels)
- Default ClusterRoles (cluster-admin, admin, edit, view) and when to use them vs custom
- Granting cross-namespace access (ClusterRole + RoleBinding for namespace-scoped effect)
- Service account permissions at cluster scope
- kubectl auth can-i with --all-namespaces and non-resource URLs

**Prerequisites:** rbac/assignment-1 (namespace-scoped RBAC fundamentals), tls-and-certificates/assignment-2 (certificate-based authentication)
**Adjacent assignments:** crds-and-operators (RBAC for custom resources)

---

### exercises/13-security-contexts/assignment-1: User and Group Security

**Series:** Security Contexts (1 of 3)
**CKA domain:** Workloads & Scheduling
**Cluster:** Single-node kind
**Generation order:** 8

**Scope:**
- Pod-level securityContext (runAsUser, runAsGroup, fsGroup, supplementalGroups)
- Container-level securityContext (runAsUser, runAsNonRoot)
- fsGroup interaction with volumes and mounted storage
- Volume ownership and permission propagation
- Security context precedence (container overrides pod)
- Verification via exec (checking uid/gid inside containers)

**Prerequisites:** pods/assignment-1, pods/assignment-2
**Adjacent assignments:** security-contexts/assignment-2 (capabilities build on user/group foundation)

---

### exercises/13-security-contexts/assignment-2: Capabilities and Privilege Control

**Series:** Security Contexts (2 of 3)
**CKA domain:** Workloads & Scheduling
**Cluster:** Single-node kind
**Generation order:** 9

**Scope:**
- Linux capabilities overview
- Adding capabilities (NET_ADMIN, SYS_TIME, SYS_ADMIN)
- Dropping capabilities (CAP_NET_RAW, CAP_SETUID)
- Default capabilities from container runtime
- allowPrivilegeEscalation flag and implications
- Privilege escalation prevention patterns

**Prerequisites:** security-contexts/assignment-1
**Adjacent assignments:** security-contexts/assignment-3 (filesystem constraints complete the security picture)

---

### exercises/13-security-contexts/assignment-3: Filesystem and seccomp Profiles

**Series:** Security Contexts (3 of 3)
**CKA domain:** Workloads & Scheduling
**Cluster:** Single-node kind
**Generation order:** 10

**Scope:**
- readOnlyRootFilesystem flag
- Combining readOnlyRootFilesystem with writable emptyDir mounts
- seccomp profiles (RuntimeDefault, Localhost, Unconfined)
- Creating custom seccomp profiles
- seccomp profile debugging
- Security context best practices and defense in depth

**Prerequisites:** security-contexts/assignment-2
**Adjacent assignments:** storage (fsGroup affects mounted volume permissions)

---

### exercises/15-crds-and-operators/assignment-1: Custom Resource Definitions

**Series:** CRDs and Operators (1 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 11

**Scope:**
- CRD spec structure (group, versions, scope, names)
- CRD schema definition (OpenAPI v3)
- CRD versioning strategies
- Creating and applying CRDs
- CRD validation rules
- CRD status subresources

**Prerequisites:** None
**Adjacent assignments:** crds-and-operators/assignment-2 (custom resources build on CRD foundation)

---

### exercises/15-crds-and-operators/assignment-2: Custom Resources and RBAC

**Series:** CRDs and Operators (2 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 12

**Scope:**
- Custom resource CRUD operations
- Custom resource namespacing vs cluster-scoping
- RBAC for custom resources (Roles referencing CR types)
- Custom resource discovery (kubectl api-resources)
- Custom resource categories and short names
- kubectl integration with custom resources

**Prerequisites:** crds-and-operators/assignment-1
**Adjacent assignments:** rbac (RBAC fundamentals), crds-and-operators/assignment-3 (operators consume custom resources)

---

### exercises/15-crds-and-operators/assignment-3: Operators and Controllers

**Series:** CRDs and Operators (3 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 13

**Scope:**
- Custom controller concept (watch-reconcile loop)
- Operator pattern overview
- Installing existing operators
- Operator lifecycle (install, upgrade, uninstall)
- Troubleshooting operator installations
- Operator best practices and when to use them

**Prerequisites:** crds-and-operators/assignment-2
**Adjacent assignments:** helm (operators often installed via Helm)

---

### exercises/07-storage/assignment-1: Volumes and PersistentVolumes

**Series:** Storage (1 of 3)
**CKA domain:** Storage
**Cluster:** Single-node kind
**Generation order:** 14

**Scope:**
- Volume types overview (emptyDir, hostPath, PVC)
- PersistentVolume spec (capacity, accessModes, persistentVolumeReclaimPolicy)
- PV lifecycle phases (Available, Bound, Released, Failed)
- Static PV provisioning
- PV label selectors and node affinity
- Inspecting PVs (kubectl describe, status fields)

**Prerequisites:** None
**Adjacent assignments:** storage/assignment-2 (PVCs build on PV foundation)

---

### exercises/07-storage/assignment-2: PersistentVolumeClaims and Binding

**Series:** Storage (2 of 3)
**CKA domain:** Storage
**Cluster:** Single-node kind
**Generation order:** 15

**Scope:**
- PVC spec (resources.requests.storage, accessModes, storageClassName)
- PV-to-PVC binding mechanics (capacity, access mode, storage class matching)
- Using PVCs in pod specs (volumes, volumeMounts)
- Access modes (ReadWriteOnce, ReadOnlyMany, ReadWriteMany, ReadWriteOncePod)
- Reclaim policies (Retain, Delete)
- Troubleshooting binding failures

**Prerequisites:** storage/assignment-1
**Adjacent assignments:** storage/assignment-3 (StorageClass automates provisioning)

---

### exercises/07-storage/assignment-3: StorageClasses and Dynamic Provisioning

**Series:** Storage (3 of 3)
**CKA domain:** Storage
**Cluster:** Single-node kind
**Generation order:** 16

**Scope:**
- StorageClass resources and provisioner field
- Dynamic provisioning workflow
- Default StorageClass annotation
- StorageClass parameters and provisioner-specific options
- Volume expansion (allowVolumeExpansion)
- VolumeBindingMode (Immediate vs WaitForFirstConsumer)

**Prerequisites:** storage/assignment-2
**Adjacent assignments:** security-contexts (fsGroup affects mounted volume permissions)

---

### exercises/08-services/assignment-1: ClusterIP Services

**Series:** Services (1 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind
**Generation order:** 17

**Scope:**
- ClusterIP service type (default, internal access)
- Service selectors and label matching
- Endpoints and EndpointSlices
- Service creation (imperative vs declarative)
- Service discovery via environment variables
- Headless services (ClusterIP: None)

**Prerequisites:** pods/assignment-7
**Adjacent assignments:** services/assignment-2 (external service types build on ClusterIP foundation)

---

### exercises/08-services/assignment-2: External Service Types

**Series:** Services (2 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind
**Generation order:** 18

**Scope:**
- NodePort services (external access on static port)
- NodePort port allocation and kube-proxy behavior
- LoadBalancer services (cloud provider integration)
- LoadBalancer vs NodePort in kind clusters
- ExternalName services (DNS CNAME mapping)
- Services without selectors (manual endpoint management)

**Prerequisites:** services/assignment-1
**Adjacent assignments:** services/assignment-3 (advanced patterns and troubleshooting)

---

### exercises/08-services/assignment-3: Service Patterns and Troubleshooting

**Series:** Services (3 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind
**Generation order:** 19

**Scope:**
- Multi-port services
- Session affinity (ClientIP)
- Service topology and traffic policies
- Troubleshooting empty endpoints
- Troubleshooting selector mismatches
- Service readiness and endpoint removal

**Prerequisites:** services/assignment-2
**Adjacent assignments:** coredns (DNS resolves service names), network-policies (policies filter service traffic)

---

### exercises/09-coredns/assignment-1: DNS Fundamentals

**Series:** CoreDNS (1 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind
**Generation order:** 20

**Scope:**
- Service DNS format (<service>.<namespace>.svc.cluster.local)
- Pod DNS records
- DNS policies in pod spec (ClusterFirst, Default, None, ClusterFirstWithHostNet)
- Service discovery via DNS
- DNS lookup workflow and resolv.conf
- DNS queries from pods (nslookup, dig)

**Prerequisites:** services/assignment-1
**Adjacent assignments:** coredns/assignment-2 (CoreDNS configuration builds on DNS usage)

---

### exercises/09-coredns/assignment-2: CoreDNS Configuration

**Series:** CoreDNS (2 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind
**Generation order:** 21

**Scope:**
- CoreDNS Deployment in kube-system
- CoreDNS ConfigMap and Corefile structure
- CoreDNS plugins (kubernetes, forward, cache, errors, health)
- CoreDNS configuration customization
- CoreDNS logging and verbosity
- CoreDNS performance tuning

**Prerequisites:** coredns/assignment-1
**Adjacent assignments:** coredns/assignment-3 (DNS troubleshooting applies configuration knowledge)

---

### exercises/09-coredns/assignment-3: DNS Troubleshooting

**Series:** CoreDNS (3 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind
**Generation order:** 22

**Scope:**
- Diagnosing DNS resolution failures
- CoreDNS pod failures
- DNS policy misconfigurations
- Network policies blocking DNS traffic
- DNS caching issues
- Service DNS not resolving

**Prerequisites:** coredns/assignment-2
**Adjacent assignments:** troubleshooting/assignment-4 (cross-domain network troubleshooting)

---

### exercises/10-network-policies/assignment-1: NetworkPolicy Fundamentals

**Series:** Network Policies (1 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind (needs CNI with NetworkPolicy support)
**Generation order:** 23

**Scope:**
- NetworkPolicy spec structure (apiVersion, kind, metadata, spec)
- podSelector mechanics for targeting pods in the same namespace
- Basic ingress rules (from.podSelector within namespace)
- Basic egress rules (to.podSelector within namespace)
- Port-level filtering (ports field with protocol and port)
- Policy verification workflow (testing connectivity, kubectl describe)

**Prerequisites:** services/assignment-1
**Adjacent assignments:** network-policies/assignment-2 (advanced selectors build on fundamentals)

**Kind cluster note:** The default kind CNI (kindnet) does not support NetworkPolicy.
Assignment-1 tutorial must include instructions for installing Calico on kind clusters.

---

### exercises/10-network-policies/assignment-2: Advanced Selectors and Isolation

**Series:** Network Policies (2 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind (CNI already configured in assignment-1)
**Generation order:** 24

**Scope:**
- namespaceSelector mechanics for cross-namespace rules
- Combined selectors (podSelector + namespaceSelector, AND vs OR semantics)
- ipBlock and CIDR selectors for external traffic control
- except field within ipBlock for carve-outs
- Default deny policies (deny-all-ingress, deny-all-egress, combined deny-all)
- Namespace isolation patterns (isolate namespace, allow specific ingress/egress)
- Policy ordering and additive behavior (multiple policies union their rules)

**Prerequisites:** network-policies/assignment-1
**Adjacent assignments:** network-policies/assignment-3 (debugging applies advanced pattern knowledge)

---

### exercises/10-network-policies/assignment-3: Network Policy Debugging

**Series:** Network Policies (3 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind
**Generation order:** 25

**Scope:**
- Diagnosing blocked traffic (expected communication fails, policy too restrictive)
- Diagnosing unexpectedly allowed traffic (security gaps, missing policies)
- Multi-policy conflict resolution (overlapping policies, rule interaction)
- Cross-namespace troubleshooting (namespaceSelector issues, label mismatches)
- Integration debugging (policies affecting service access, DNS queries)
- Policy observability patterns (logging, testing, validation)

**Prerequisites:** network-policies/assignment-2
**Adjacent assignments:** troubleshooting/assignment-4 (cross-domain network troubleshooting)

---

### exercises/11-ingress-and-gateway-api/assignment-1: Ingress Fundamentals

**Series:** Ingress and Gateway API (1 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind (needs ingress controller installed)
**Generation order:** 26

**Scope:**
- Ingress resource spec (rules, paths, backends, defaultBackend)
- Ingress controller deployment (nginx-ingress)
- Path types (Prefix, Exact, ImplementationSpecific)
- Host-based routing
- Ingress creation and verification
- Basic troubleshooting (backend not found)

**Prerequisites:** services/assignment-1
**Adjacent assignments:** ingress-and-gateway-api/assignment-2 (advanced Ingress patterns)

---

### exercises/11-ingress-and-gateway-api/assignment-2: Advanced Ingress and TLS

**Series:** Ingress and Gateway API (2 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind
**Generation order:** 27

**Scope:**
- Ingress annotations and rewrite-target
- TLS termination with Ingress
- Certificate management for Ingress
- Multi-host and multi-path rules
- Default backend configuration
- Ingress controller customization

**Prerequisites:** ingress-and-gateway-api/assignment-1
**Adjacent assignments:** ingress-and-gateway-api/assignment-3 (Gateway API is next-generation approach)

---

### exercises/11-ingress-and-gateway-api/assignment-3: Gateway API

**Series:** Ingress and Gateway API (3 of 3)
**CKA domain:** Services & Networking
**Cluster:** Multi-node kind
**Generation order:** 28

**Scope:**
- Gateway API resources (GatewayClass, Gateway, HTTPRoute)
- Gateway API vs Ingress comparison
- Traffic routing with HTTPRoute
- Header-based routing
- Gateway API path matching
- Gateway API troubleshooting

**Prerequisites:** ingress-and-gateway-api/assignment-2
**Adjacent assignments:** troubleshooting/assignment-4 (external access troubleshooting)

---

### exercises/05-helm/assignment-1: Helm Basics

**Series:** Helm (1 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 29

**Scope:**
- Helm architecture and concepts (charts, releases, revisions)
- Chart repositories (add, search, update, list)
- Installing charts (helm install, release naming)
- Values customization (--set flag)
- Inspecting charts (helm show)

**Prerequisites:** None
**Adjacent assignments:** helm/assignment-2 (lifecycle management builds on installation)

---

### exercises/05-helm/assignment-2: Helm Lifecycle Management

**Series:** Helm (2 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 30

**Scope:**
- Upgrading releases (helm upgrade)
- Values files (-f values.yaml)
- Reusing values (--reuse-values vs --reset-values)
- Rolling back releases (helm rollback)
- Release history (helm history)
- Uninstalling releases (helm uninstall)

**Prerequisites:** helm/assignment-1
**Adjacent assignments:** helm/assignment-3 (templates and debugging)

---

### exercises/05-helm/assignment-3: Helm Templates and Debugging

**Series:** Helm (3 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 31

**Scope:**
- Template rendering (helm template)
- Debugging chart installations
- Helm hooks (pre-install, post-install)
- Chart dependencies
- Helm secrets and sensitive data
- Helm best practices

**Prerequisites:** helm/assignment-2
**Adjacent assignments:** kustomize (alternative manifest management)

---

### exercises/06-kustomize/assignment-1: Kustomize Fundamentals

**Series:** Kustomize (1 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 32

**Scope:**
- kustomization.yaml structure and purpose
- Resource references (resources field)
- Managing directories (bases)
- Common transformers (namePrefix, nameSuffix)
- commonLabels and commonAnnotations
- Building and applying kustomizations

**Prerequisites:** None
**Adjacent assignments:** kustomize/assignment-2 (patches build on fundamentals)

---

### exercises/06-kustomize/assignment-2: Patches and Transformers

**Series:** Kustomize (2 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 33

**Scope:**
- Strategic merge patches
- JSON 6902 patches
- Inline patches
- Image transformers
- ConfigMap and Secret generators
- Patch targets and selectors

**Prerequisites:** kustomize/assignment-1
**Adjacent assignments:** kustomize/assignment-3 (overlays use patches)

---

### exercises/06-kustomize/assignment-3: Overlays and Components

**Series:** Kustomize (3 of 3)
**CKA domain:** Cluster Architecture, Installation & Configuration
**Cluster:** Single-node kind
**Generation order:** 34

**Scope:**
- Base and overlay directory structure
- Environment-specific configurations (dev, staging, prod)
- Components (reusable partial configurations)
- Kustomization composition
- Namespace transformers
- Kustomize best practices

**Prerequisites:** kustomize/assignment-2
**Adjacent assignments:** helm (alternative manifest management)

---

### exercises/19-troubleshooting/assignment-1: Application Troubleshooting

**Series:** Troubleshooting (1 of 4)
**CKA domain:** Troubleshooting
**Cluster:** Multi-node kind
**Generation order:** 35

**Scope:**
- Pod failure states (CrashLoopBackOff, ImagePullBackOff, ErrImagePull, CreateContainerError)
- Diagnosing crashes from logs and events
- Resource exhaustion (OOMKilled, CPU throttling, eviction)
- Incorrect commands, arguments, or environment variables causing failures
- Missing or misconfigured ConfigMaps and Secrets
- Volume mount failures (wrong path, missing PVC, access mode mismatch)
- Service selector mismatches (endpoints empty)

**Cross-domain scenarios:** These exercises intentionally combine failures from multiple
topic areas (broken deployment + wrong service selector + missing configmap).

---

### exercises/19-troubleshooting/assignment-2: Control Plane Troubleshooting

**Series:** Troubleshooting (2 of 4)
**CKA domain:** Troubleshooting
**Cluster:** Multi-node kind
**Generation order:** 36

**Scope:**
- API server failures (static pod manifest errors, certificate issues, port conflicts)
- Scheduler failures (not running, misconfigured)
- Controller manager failures (not running, RBAC issues)
- etcd failures (not running, data corruption, connectivity)
- Static pod manifest debugging in /etc/kubernetes/manifests/
- Certificate expiration and verification
- Control plane component logs (kubectl logs for kube-system pods, crictl for static pods)

**Kind cluster note:** Some control plane failure scenarios may be limited in kind.
The prompt should identify which scenarios work in kind and which are conceptual.

---

### exercises/19-troubleshooting/assignment-3: Node and Kubelet Troubleshooting

**Series:** Troubleshooting (3 of 4)
**CKA domain:** Troubleshooting
**Cluster:** Multi-node kind
**Generation order:** 37

**Scope:**
- Node NotReady diagnosis (kubectl describe node, conditions)
- Kubelet not running (systemctl status kubelet, journalctl -u kubelet)
- Container runtime issues
- Node conditions (MemoryPressure, DiskPressure, PIDPressure)
- Taints applied automatically by node conditions
- Node drain and recovery
- Kubelet configuration issues

**Kind cluster note:** Kind nodes are containers, so kubelet management differs from
bare-metal. The prompt should note where kind behavior diverges from real clusters.

---

### exercises/19-troubleshooting/assignment-4: Network Troubleshooting

**Series:** Troubleshooting (4 of 4)
**CKA domain:** Troubleshooting
**Cluster:** Multi-node kind (with policy-capable CNI)
**Generation order:** 38

**Scope:**
- Service not reachable (empty endpoints, selector mismatch, wrong port)
- DNS resolution failures (CoreDNS not running, misconfigured, pod DNS policy)
- Network policy blocking expected traffic
- kube-proxy issues (not running, wrong mode)
- Pod-to-pod connectivity failures
- Cross-namespace connectivity issues
- External access failures (NodePort not reachable, Ingress misconfigured)

**Cross-domain scenarios:** These exercises combine networking failures with application
and service configuration issues.

---

## Planned Topics (Exercises 21+)

None of these topics have content files yet. Scope each with `/k8s-prompt-builder` before
generating assignments. The numbering below is a starting point; adjust if topics are added
out of order.

### exercises/21-container-images (CKAD gap)

**Status:** Topic README written (2026-07-04). Two assignments scoped. No prompt.md or content files yet.
**Origin:** CKAD-specific material not covered in the CKA corpus

**Assignment 1: Dockerfile Authoring**
- Instruction set (FROM, RUN, COPY, ADD, ENV, ARG, LABEL, EXPOSE, WORKDIR, USER)
- ENTRYPOINT vs CMD (exec/shell form, override behavior, pod spec mapping)
- Build context and .dockerignore
- nerdctl build flags and usage
- Image inspection (nerdctl inspect, nerdctl history, layer breakdown)
- Non-root USER directive (build-time vs runtime identity distinction)

**Assignment 2: Optimization and Distribution**
- Multi-stage builds (multiple FROM, COPY --from, size reduction)
- Layer caching (ordering instructions, cache invalidation)
- Base image selection (ubuntu, alpine, distroless, scratch trade-offs)
- OCI image format (manifest, config, layers, digests vs tags)
- Image tagging conventions (semver, :latest risks, digest pinning)
- Registry operations (local registry with nerdctl, push/pull, kind integration)

**Defers to:**
- supply-chain-security (image scanning with Trivy, signing with Cosign, Dockerfile hardening)
- security-contexts (pod-level runAsUser vs Dockerfile USER)
- opa-gatekeeper (image policy enforcement)

---

### exercises/22-cluster-hardening (CKS)

**Status:** Planned, not started
**Origin:** CKS domain: Cluster Setup and Cluster Hardening

**Planned scope:**
- kube-bench and CIS Kubernetes Benchmark
- API server hardening flags (anonymous auth, authorization modes, admission plugins)
- Disabling insecure ports and unused features
- Restricting access to etcd
- Node metadata protection (restricting instance metadata service access)
- Service account token automounting controls
- Restricting kubeconfig permissions

**Defers to:** rbac (already covered in 12-rbac), tls-and-certificates (already covered in 18)

---

### exercises/23-supply-chain-security (CKS)

**Status:** Planned, not started
**Origin:** CKS domain: Supply Chain Security

**Planned scope:**
- Trivy image scanning (vulnerabilities, misconfigurations)
- Dockerfile best practices (non-root user, no secrets in layers, minimal base)
- Image signing with Cosign
- Signature verification with Cosign and policy enforcement
- SBOM basics (generating and reading a software bill of materials)
- Admission control for image policy (using OPA/Gatekeeper or ImagePolicyWebhook)

**Defers to:** opa-gatekeeper (policy enforcement detail), container-images (Dockerfile writing)

---

### exercises/24-runtime-sandboxing (CKS)

**Status:** Planned, not started
**Origin:** CKS domain: Minimize Microservice Vulnerabilities

**Planned scope:**
- RuntimeClass resource (definition, scheduling)
- gVisor (runsc) installation and configuration as a RuntimeClass handler
- Kata Containers as an alternative sandbox runtime
- Assigning RuntimeClass to pods
- Trade-offs: performance overhead vs. isolation guarantees
- Verifying sandbox isolation

**Defers to:** system-hardening (kernel-level hardening without sandboxing)

---

### exercises/25-opa-gatekeeper (CKS)

**Status:** Planned, not started
**Origin:** CKS domain: Minimize Microservice Vulnerabilities

**Planned scope:**
- OPA/Gatekeeper architecture (controller, audit, webhook)
- ConstraintTemplate authoring (Rego basics for Kubernetes policies)
- Constraint resources (enforcement action: deny, dryrun, warn)
- Audit mode and violation reporting
- Common policy patterns (require labels, disallow privileged, restrict registries)
- Mutation policies (assign default values, inject labels)

**Defers to:** admission-controllers (built-in admission already covered in 16)

---

### exercises/26-runtime-security (CKS)

**Status:** Planned, not started
**Origin:** CKS domain: Monitoring, Logging and Runtime Security

**Planned scope:**
- Falco architecture (kernel module/eBPF probe, rules engine, outputs)
- Writing and customizing Falco rules
- Falco alerts and output channels
- Kubernetes audit logging (audit policy, log backends)
- Audit policy rule authoring (level, resources, verbs)
- Detecting runtime threats from audit logs and Falco alerts
- Immutable container patterns (readOnlyRootFilesystem, no shell)

**Defers to:** system-hardening (AppArmor/seccomp as complementary controls)

---

### exercises/27-secrets-management (CKS)

**Status:** Planned, not started
**Origin:** CKS domain: Minimize Microservice Vulnerabilities

**Planned scope:**
- etcd encryption at rest (EncryptionConfiguration, aescbc, secretbox providers)
- Verifying encryption (etcdctl get to confirm ciphertext)
- Kubernetes ExternalSecret and SecretStore resources (external-secrets operator)
- HashiCorp Vault basics for Kubernetes (agent injector, Vault CSI driver)
- Secret rotation patterns
- Avoiding secrets in environment variables vs. volume mounts

**Defers to:** rbac (secret access control already covered in 12-rbac)

---

### exercises/28-system-hardening (CKS)

**Status:** Planned, not started
**Origin:** CKS domain: System Hardening

**Planned scope:**
- AppArmor profile authoring (complain vs enforce mode, profile syntax)
- Applying AppArmor profiles to pods (annotations and securityContext)
- Diagnosing AppArmor violations (kernel logs, audit)
- seccomp profiles in depth (custom profiles beyond RuntimeDefault, syscall allow/deny lists)
- seccomp violation debugging
- Reducing node OS attack surface (unnecessary packages, services, open ports)
- Kernel hardening concepts (namespaces, cgroups, capabilities model)

**Note:** Surface-level seccomp and AppArmor are touched in 13-security-contexts/assignment-3.
This topic goes deeper: profile authoring, violation debugging, and real-world hardened workloads.
Scope must be carefully bounded to avoid overlap with assignment-3's introductory coverage.
