# CKA Exam Curriculum Reference

**Source:** CNCF official curriculum (github.com/cncf/curriculum)
**Exam version:** Kubernetes v1.35 (CKA_Curriculum_v1.35.pdf published by CNCF)
**Last verified:** 2026-04-18 against github.com/cncf/curriculum

---

## Domain Structure

The CKA exam tests five domains. The weights below determine how many exam tasks come
from each domain. A 30% domain at 17 questions means roughly 5 tasks from that domain.

---

## Domain 1: Cluster Architecture, Installation & Configuration (25%)

This domain covers the infrastructure and configuration layer: how clusters are built,
secured, extended, and maintained.

**Competencies:**

1. **Manage role-based access control (RBAC)**
   - Roles, ClusterRoles, RoleBindings, ClusterRoleBindings
   - Service accounts and their relationship to RBAC
   - Principle of least privilege in permission design
   - Verifying access with `kubectl auth can-i`

2. **Prepare underlying infrastructure for installing a Kubernetes cluster**
   - Node requirements (container runtime, networking, ports, swap disabled)
   - Choosing between kubeadm, managed offerings, or manual installation

3. **Create and manage Kubernetes clusters using kubeadm**
   - `kubeadm init` and `kubeadm join` workflows
   - kubeadm configuration files
   - Adding and removing nodes

4. **Manage the lifecycle of Kubernetes clusters**
   - Cluster version upgrades with kubeadm (`kubeadm upgrade plan`, `kubeadm upgrade apply`)
   - Draining and cordoning nodes during maintenance
   - etcd backup and restore (`etcdctl snapshot save`, `etcdctl snapshot restore`)

5. **Implement and configure a highly available control plane**
   - Stacked vs. external etcd topology
   - Load balancer in front of API servers
   - Multi-master configuration

6. **Use Helm and Kustomize to install cluster components**
   - Helm: chart repositories, installing/upgrading/rolling back releases, values files
   - Kustomize: kustomization.yaml, overlays, patches, transformers

7. **Understand extension interfaces (CNI, CSI, CRI)**
   - What each interface abstracts (networking, storage, container runtime)
   - How plugins are installed and configured
   - Not deep implementation details, but understanding the role of each

8. **Understand CRDs and install and configure operators**
   - Custom Resource Definitions: creating, applying, using custom resources
   - Operator pattern: what operators do, installing existing operators
   - Not writing custom controllers from scratch

---

## Domain 2: Workloads & Scheduling (15%)

This domain covers deploying and managing applications, scaling, configuration
injection, and pod scheduling mechanics.

**Competencies:**

1. **Understand application deployments and perform rolling updates and rollbacks**
   - Deployment strategies: RollingUpdate (maxSurge, maxUnavailable), Recreate
   - `kubectl rollout status`, `kubectl rollout history`, `kubectl rollout undo`
   - Revision history and `--to-revision`

2. **Use ConfigMaps and Secrets to configure applications**
   - Creating from literals, files, and directories
   - Consuming as environment variables and volume mounts
   - Immutable ConfigMaps and Secrets

3. **Configure workload autoscaling**
   - Horizontal Pod Autoscaler (HPA) based on CPU/memory metrics
   - Vertical Pod Autoscaler (VPA) concepts
   - In-place pod resize

4. **Understand primitives for robust, self-healing application deployments**
   - Liveness, readiness, and startup probes
   - Restart policies and pod lifecycle
   - ReplicaSets as the reconciliation mechanism

5. **Configure Pod admission and scheduling (limits, node affinity, etc.)**
   - Resource requests and limits, QoS classes
   - nodeSelector, node affinity/anti-affinity, pod affinity/anti-affinity
   - Taints and tolerations
   - Priority classes and preemption
   - Admission controllers (validating and mutating)
   - Topology spread constraints

---

## Domain 3: Services & Networking (20%)

This domain covers how pods communicate, how services expose applications,
and how traffic is managed and controlled.

**Competencies:**

1. **Understand connectivity between Pods**
   - Pod-to-pod communication within and across nodes
   - The flat network model (every pod gets a routable IP)
   - CNI plugin role in establishing connectivity

2. **Define and enforce Network Policies**
   - Ingress and egress rules
   - Namespace isolation using default deny policies
   - Selectors: podSelector, namespaceSelector, ipBlock/CIDR
   - The requirement for a CNI that supports NetworkPolicy (Calico, Cilium, Weave)

3. **Use ClusterIP, NodePort, LoadBalancer service types and endpoints**
   - ClusterIP as the default internal service
   - NodePort for external access on a static port
   - LoadBalancer for cloud provider integration
   - Endpoints and EndpointSlices
   - Headless services (ClusterIP: None)
   - Service selectors and label matching

4. **Use the Gateway API to manage Ingress traffic** (primary emphasis as of 2026)
   - GatewayClass, Gateway, HTTPRoute resources
   - Relationship to and differences from legacy Ingress
   - Traffic routing, path matching, header-based routing
   - Migration from Ingress to Gateway API (including the `Ingress2Gateway` CLI)
   - **Conformant implementations** (per gateway-api.sigs.k8s.io/implementations/):
     Envoy Gateway, NGINX Gateway Fabric, Cilium, Istio, Traefik, HAProxy,
     kgateway. Partially conformant: Contour, Kong, AWS Load Balancer Controller.
   - The CKA exam's allowed documentation set includes `gateway-api.sigs.k8s.io/`
     as a dedicated URL, which signals Gateway API is a major exam focus.

5. **Know how to use Ingress controllers and Ingress resources**
   - Ingress resource structure (rules, paths, backends)
   - Annotations and rewrite-target
   - TLS termination
   - **Important context (as of 2026):** The Ingress API is frozen; Kubernetes.io
     officially recommends Gateway API for new work. The historically common
     example controller, `ingress-nginx`, is retired as of March 2026. The CKA
     allowed documentation set no longer includes the NGINX Ingress Controller
     guide (that URL is CKS-only now). Ingress v1 resources are still tested,
     but learners should practice with actively maintained controllers such as
     Traefik, HAProxy Ingress, or Contour rather than ingress-nginx.

6. **Understand and use CoreDNS**
   - Service DNS: `<service>.<namespace>.svc.cluster.local`
   - Pod DNS records
   - CoreDNS configuration (Corefile, plugins)
   - DNS debugging workflow (`nslookup`, `dig` from within pods)

---

## Domain 4: Storage (10%)

This domain covers persistent data in Kubernetes: how volumes are provisioned,
claimed, and managed.

**Competencies:**

1. **Implement storage classes and dynamic volume provisioning**
   - StorageClass resources and provisioner field
   - Default StorageClass annotation
   - Dynamic vs. static provisioning

2. **Configure volume types, access modes, and reclaim policies**
   - Volume types: emptyDir, hostPath, PersistentVolumeClaim, projected, configMap, secret
   - Access modes: ReadWriteOnce, ReadOnlyMany, ReadWriteMany, ReadWriteOncePod
   - Reclaim policies: Retain, Delete, Recycle (deprecated)

3. **Manage persistent volumes and persistent volume claims**
   - PersistentVolume spec (capacity, accessModes, storageClassName, persistentVolumeReclaimPolicy)
   - PersistentVolumeClaim spec (resources.requests, accessModes, storageClassName)
   - Binding mechanics (how PVCs match PVs)
   - Using PVCs in pod specs as volume mounts
   - Expanding PVCs (allowVolumeExpansion)

---

## Domain 5: Troubleshooting (30%)

This is the largest domain. It tests the ability to diagnose and resolve problems
across all layers of the stack.

**Competencies:**

1. **Troubleshoot clusters and nodes**
   - Node conditions (Ready, MemoryPressure, DiskPressure, PIDPressure)
   - `kubectl describe node` and interpreting conditions
   - Kubelet status and logs (`systemctl status kubelet`, `journalctl -u kubelet`)
   - Node NotReady diagnosis and recovery

2. **Troubleshoot cluster components**
   - Control plane component health checks
   - Static pod manifests in `/etc/kubernetes/manifests/`
   - API server, scheduler, controller manager logs
   - etcd health and connectivity
   - Certificate expiration and renewal

3. **Monitor cluster and application resource usage**
   - `kubectl top nodes`, `kubectl top pods`
   - Metrics server installation and verification
   - Identifying resource-constrained pods and nodes

4. **Manage and evaluate container output streams**
   - `kubectl logs` (current, previous, specific container, follow, since)
   - Container stdout/stderr conventions
   - Log inspection for crash diagnosis

5. **Troubleshoot services and networking**
   - Service endpoint verification (`kubectl get endpoints`)
   - DNS resolution testing from within pods
   - Network policy diagnosis (unexpected traffic blocking)
   - kube-proxy mode and iptables/ipvs rules
   - Connectivity testing between pods, services, and external endpoints
