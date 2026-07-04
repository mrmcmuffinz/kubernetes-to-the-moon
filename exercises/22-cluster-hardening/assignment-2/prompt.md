# Assignment Prompt: Cluster Hardening — Assignment 2

**Series:** Cluster Hardening (2 of 2)
**Topic slug:** cluster-hardening
**Topic directory:** exercises/22-cluster-hardening/assignment-2/

## Metadata

**Domain:** CKS — Cluster Hardening (15%)
**Competencies:** etcd security, service account hardening, kubeconfig security, node metadata protection
**Prerequisites:** cluster-hardening/assignment-1

## Scope — In Scope

*etcd access restriction*
- How etcd communicates: client TLS (API server to etcd), peer TLS (etcd to etcd)
- Verifying etcd is configured with --client-cert-auth=true and --peer-client-cert-auth=true
- Testing that etcd rejects unauthenticated connections: etcdctl without certs should fail
- Confirming the etcd listen address (--listen-client-urls should not bind to 0.0.0.0 in production)

*Service account token controls*
- automountServiceAccountToken: false at the Pod spec level
- automountServiceAccountToken: false at the ServiceAccount level (applies to all pods using that SA)
- Verifying the default token is not mounted: kubectl exec and ls /var/run/secrets/kubernetes.io/serviceaccount/
- The default service account in every namespace: why its permissions should be minimal
- Auditing service account permissions: kubectl auth can-i --list --as=system:serviceaccount:default:default

*kubeconfig file security*
- File permissions on ~/.kube/config: should be 600 (readable only by owner), not 644
- Checking permissions: ls -la ~/.kube/config
- The risk of a world-readable kubeconfig: any local user can impersonate the cluster-admin
- Verifying kubeconfig context credentials are certificate-based (not static token where avoidable)

*RBAC audit for over-privileged accounts*
- kubectl auth can-i --list for various service accounts to find unexpected permissions
- Identifying cluster-admin bindings that should be more restrictive: kubectl get clusterrolebindings -o wide
- The principle of least privilege applied to service accounts

*Node metadata protection*
- The cloud provider instance metadata endpoint (169.254.169.254): what credentials it exposes in cloud environments
- Blocking metadata access with a NetworkPolicy egress rule to 169.254.169.254/32
- Testing the block from within a pod: curl http://169.254.169.254/ should be blocked
- Why this matters even in kind (understanding the concept for production environments)

## Scope — Out of Scope

- API server flag hardening: covered in cluster-hardening/assignment-1
- kube-bench scanning: covered in cluster-hardening/assignment-1
- General NetworkPolicy: covered in 10-network-policies
- etcd backup and restore: covered in 17-cluster-lifecycle/assignment-3

## Environment

Single-node kind cluster. etcd exercises require etcdctl installed and access to etcd certificates (inside the kind control plane container). The tutorial must show how to run etcdctl against the kind cluster etcd using the correct cert flags.

**etcdctl pattern for kind:**
```
nerdctl exec -it kind-control-plane bash
ETCDCTL_API=3 etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/default/mysecret
```

## Resource Gate

All Kubernetes resources are in scope. NetworkPolicy exercises require a CNI that supports NetworkPolicy (Calico or similar; the tutorial must install one if the default kind CNI does not support it).

## Topic-specific Conventions

- All security controls must be verified to be working, not just applied.
- The metadata protection NetworkPolicy exercise should test both that the block works and that legitimate cluster traffic is unaffected.
- Tutorial namespace: `tutorial-cluster-hardening` (same as assignment-1, but exercises use their own ex- namespaces).

## Exercise Distribution

- Level 1: Check etcd TLS flags, check kubeconfig permissions, verify a service account has automount disabled
- Level 2: Disable automountServiceAccountToken on a ServiceAccount, add a NetworkPolicy blocking metadata endpoint, audit a service account's permissions
- Level 3 (debugging): Bare headings. Broken configs (pod failing because it needs the SA token but automount was disabled, NetworkPolicy too broad blocking cluster traffic)
- Level 4: Full hardening workflow — audit a namespace's service accounts, disable unnecessary token mounts, restrict RBAC, verify etcd access
- Level 5 (debugging): Multi-issue scenario combining over-privileged SA, missing NetworkPolicy, and misconfigured etcd cert path
