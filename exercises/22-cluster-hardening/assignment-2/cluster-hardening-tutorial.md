# etcd Security, Service Account Controls, and Metadata Protection Tutorial

## Introduction

Hardening a Kubernetes cluster does not end with the API server. The API server is the front door, but etcd is the vault: it stores every Kubernetes object, every secret, every certificate, and every piece of cluster state in plaintext (encrypted only if you configure encryption at rest). If etcd accepts unauthenticated connections, anyone with network access to the etcd port can read or write arbitrary cluster state, bypassing RBAC entirely. Similarly, service accounts are the identity mechanism for workloads running inside the cluster, and their default configuration (tokens automounted into every pod, default service accounts with more permissions than most workloads need) creates a large attack surface that is easy to reduce with a few targeted configuration changes.

This tutorial covers four hardening areas that the CKA and CKS exams test in the cluster hardening domain. First, you will verify that etcd requires mutual TLS for all client and peer connections. Second, you will disable service account token automounting at both the ServiceAccount and Pod spec levels, and verify the token is absent from pods that do not need it. Third, you will check and correct kubeconfig file permissions, which is a simple but critical control that prevents local user impersonation. Fourth, you will write a NetworkPolicy egress rule that blocks access to the cloud provider metadata endpoint at 169.254.169.254, the address where cloud platforms like AWS, GCP, and Azure expose instance credentials that could be used to escape the cluster's security boundary.

By the end of this tutorial you will have a systematic approach to auditing and remediating the non-API-server components of cluster hardening: etcd, workload identity, operator credentials, and network egress controls. These controls, combined with the API server hardening from Assignment 1, cover the full cluster hardening baseline.

## Prerequisites

You need a single-node kind cluster with Calico CNI for the NetworkPolicy exercises. The etcd and service account exercises work on the standard kind cluster. See the [single-node kind cluster](../../../docs/cluster-setup.md#single-node-kind-cluster) section for the base cluster, and the [multi-node with Calico NetworkPolicy support](../../../docs/cluster-setup.md#multi-node-with-calico-networkpolicy-support) section for adding Calico (the Calico install steps work on a single-node cluster when applied to a single-node kind config). Confirm your cluster is ready:

```bash
kubectl get nodes
# Expected: one node with STATUS Ready

kubectl get pods -n kube-system
# Expected: all control plane pods Running, including Calico pods if installed
```

## Setup

Create the tutorial namespace:

```bash
kubectl create namespace tutorial-cluster-hardening
```

## Part 1: Verifying etcd TLS Configuration

### Why etcd TLS Matters

etcd communicates over two ports: the client port (default 2379, used by the API server and etcdctl) and the peer port (default 2380, used for etcd-to-etcd replication in multi-node clusters). Both connections should require mutual TLS, meaning the server presents a certificate and requires the client to present one as well. Without `--client-cert-auth=true`, etcd accepts connections from any client that can reach port 2379, bypassing any TLS certificate requirement on the client side.

### Inspecting the etcd Manifest

In a kind cluster, etcd runs as a static pod. Its manifest lives at `/etc/kubernetes/manifests/etcd.yaml` inside the kind control plane container. Check the TLS flags:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep -E 'cert-auth|peer-client' /etc/kubernetes/manifests/etcd.yaml"
```

In a properly configured kubeadm cluster, you should see:

```
- --client-cert-auth=true
- --peer-client-cert-auth=true
```

**Spec field documentation for etcd TLS flags:**

**--client-cert-auth**
- What it does: Requires clients to present a valid TLS certificate signed by the CA specified in `--trusted-ca-file`. If a client does not present a certificate or presents one signed by a different CA, the connection is rejected.
- Valid values: `true` or `false`.
- Default when omitted: `false` in a standalone etcd installation. kubeadm sets it to `true` explicitly.
- Failure mode when set to false: Any client with network access to the etcd port can connect and read or write any key, bypassing all API server authorization.

**--peer-client-cert-auth**
- What it does: Requires peer etcd nodes to authenticate with certificates when forming the peer cluster. Relevant in multi-node etcd deployments.
- Valid values: `true` or `false`.
- Default when omitted: `false` in a standalone etcd installation. kubeadm sets it to `true` explicitly.
- Failure mode when set to false: In a multi-node etcd cluster, a rogue node could join the cluster without authentication.

### Running etcdctl to Verify TLS Enforcement

The `etcdctl` binary is available inside the etcd pod. Use `kubectl exec` to run commands against it:

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')
echo "etcd pod: $ETCD_POD"
```

Test an authenticated connection (should succeed):

```bash
kubectl exec -n kube-system "$ETCD_POD" -- \
  etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
# Expected: https://127.0.0.1:2379 is healthy: successfully committed proposal
```

Test an unauthenticated connection (should fail when client-cert-auth=true):

```bash
kubectl exec -n kube-system "$ETCD_POD" -- \
  etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --insecure-skip-tls-verify \
  endpoint health
# Expected: Error (connection refused or certificate required error)
```

If the unauthenticated connection succeeds, `--client-cert-auth=true` is not enforced and the etcd manifest needs to be corrected.

### Inspecting etcd Data (for Understanding)

With proper credentials, you can read any Kubernetes object from etcd directly. This is useful for understanding what etcd stores and verifying encryption at rest (out of scope for this assignment):

```bash
kubectl exec -n kube-system "$ETCD_POD" -- \
  etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/namespaces/tutorial-cluster-hardening
# Expected: binary content of the namespace object (may show garbled text for protobuf-encoded data)
```

## Part 2: Service Account Token Controls

### Why Token Automounting is a Risk

Every Kubernetes namespace has a `default` service account, and by default, every pod that does not specify a `serviceAccountName` is assigned the `default` service account. Unless explicitly disabled, the API server mounts a token for that service account into every pod at `/var/run/secrets/kubernetes.io/serviceaccount/token`. This token is valid for the entire lifetime of the pod and can be used to authenticate to the Kubernetes API from inside the pod.

If a pod is compromised (container escape, code injection, credential theft), an attacker finds a ready-made Kubernetes API token mounted inside the container. If that token has any permissions at all (even `get pods` in the namespace), it gives the attacker a foothold for further lateral movement. Disabling automounting on service accounts and pods that do not need API access is a low-cost, high-value hardening step.

### Spec field documentation for automountServiceAccountToken:

**automountServiceAccountToken (on ServiceAccount)**
- What it does: Controls whether the Kubernetes API server automatically mounts a token secret for this ServiceAccount into pods that use it.
- Valid values: `true` or `false`. Can also be omitted (the pod-level setting overrides when both are present).
- Default when omitted: `true`. Tokens are mounted automatically.
- Failure mode when set to false: Pods using this SA that need to call the Kubernetes API will fail with authentication errors (no token to present). Any pod that reads files under `/var/run/secrets/kubernetes.io/serviceaccount/` will find those files absent and may crash depending on how it handles the missing token.

**automountServiceAccountToken (on Pod spec)**
- What it does: Overrides the ServiceAccount-level `automountServiceAccountToken` setting for this specific pod. If the pod sets `true` but the SA sets `false`, the token is mounted. If the pod sets `false` but the SA sets `true`, the token is not mounted.
- Valid values: `true` or `false`.
- Default when omitted: Inherits from the ServiceAccount.
- Failure mode: Same as the SA-level flag, but applies only to the specific pod.

### Disabling Automounting at the ServiceAccount Level

Create a service account with automounting disabled:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: restricted-worker
  namespace: tutorial-cluster-hardening
automountServiceAccountToken: false
EOF
```

Create a pod using this service account:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: no-token-pod
  namespace: tutorial-cluster-hardening
spec:
  serviceAccountName: restricted-worker
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF
```

Verify the token is not mounted:

```bash
kubectl wait pod no-token-pod -n tutorial-cluster-hardening \
  --for=condition=Ready --timeout=60s

kubectl exec no-token-pod -n tutorial-cluster-hardening -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Expected: ls: /var/run/secrets/kubernetes.io/serviceaccount/: No such file or directory
```

For comparison, create a pod without the automount restriction to see what the mounted token looks like:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: with-token-pod
  namespace: tutorial-cluster-hardening
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait pod with-token-pod -n tutorial-cluster-hardening \
  --for=condition=Ready --timeout=60s

kubectl exec with-token-pod -n tutorial-cluster-hardening -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/
# Expected: ca.crt  namespace  token
```

The default pod receives three files: the cluster CA certificate, the namespace name, and the JWT token. An attacker inside `with-token-pod` can use the token to call the Kubernetes API.

### Overriding at the Pod Level

If you want most pods using a service account to have no token, but one specific pod needs the token, use the pod-level override:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: needs-token-pod
  namespace: tutorial-cluster-hardening
spec:
  serviceAccountName: restricted-worker
  automountServiceAccountToken: true
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait pod needs-token-pod -n tutorial-cluster-hardening \
  --for=condition=Ready --timeout=60s

kubectl exec needs-token-pod -n tutorial-cluster-hardening -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/
# Expected: ca.crt  namespace  token (token IS present despite SA-level false)
```

### Auditing Service Account Permissions

Before deciding whether a service account's token is risky to mount, you need to know what that token can do. List all permissions for a service account:

```bash
kubectl auth can-i --list \
  --as=system:serviceaccount:tutorial-cluster-hardening:restricted-worker \
  -n tutorial-cluster-hardening
# Expected: mostly "no" entries for a service account with no RoleBindings
```

For the `default` service account in a typical kind cluster:

```bash
kubectl auth can-i --list \
  --as=system:serviceaccount:tutorial-cluster-hardening:default \
  -n tutorial-cluster-hardening
```

The output lists every resource verb combination. If you see `get pods`, `list secrets`, or any other non-trivial permission, that service account has been granted more access than it needs and should be audited.

## Part 3: kubeconfig File Security

### The Risk of a World-Readable kubeconfig

The kubeconfig file at `~/.kube/config` contains the client certificate and key (or a token) that grants cluster-admin access in a typical kind setup. If this file is readable by other local users (permissions `644` or `664`), any user on the same machine can copy the file and use it to impersonate the cluster-admin. This is particularly relevant on shared development servers or CI systems.

Check the current permissions:

```bash
ls -la ~/.kube/config
```

The expected output is:

```
-rw------- 1 username username ... /home/username/.kube/config
```

The permission bits `-rw-------` (octal 600) mean the file is readable and writable only by the owner. If you see `rw-r--r--` (644), other local users can read your cluster credentials.

**Spec field documentation for kubeconfig permissions:**

The kubeconfig file is not a Kubernetes resource but an OS file. Its security is governed by POSIX file permissions. The correct mode is `0600` (owner read/write only). The risk when set to `644`: any local user who can reach the file path (including processes running as other users on the same host) can read the embedded client certificate, key, or token and use it to authenticate to the cluster as the identity in the file. In a kind cluster, this is typically the cluster-admin identity.

Fix the permissions if needed:

```bash
chmod 600 ~/.kube/config
ls -la ~/.kube/config
# Expected: -rw------- ...
```

Verify the context and credentials are certificate-based (not a plaintext token where avoidable):

```bash
kubectl config view --minify
# Look for: certificate-authority-data, client-certificate-data, client-key-data
# These indicate certificate-based credentials (preferred over static tokens)
```

## Part 4: Node Metadata Protection

### What the Metadata Endpoint Is

Cloud providers (AWS, GCP, Azure, and others) expose an instance metadata HTTP endpoint at the link-local address 169.254.169.254. This endpoint provides instance-specific information including, critically, temporary IAM credentials for the cloud provider. A process running inside a pod that can reach 169.254.169.254 can potentially retrieve the EC2 instance profile credentials (on AWS), the GCE service account token (on GCP), or the Azure managed identity token, and use those credentials to access cloud resources outside the cluster's security boundary.

In a kind cluster running on a local machine, 169.254.169.254 is not routable and the endpoint does not exist. However, understanding the concept and knowing how to configure the protection is a CKA and CKS exam objective. The NetworkPolicy you write here is the exact configuration you would apply in a production cloud-hosted cluster.

### Writing the Metadata Protection NetworkPolicy

The protection is a NetworkPolicy that denies egress to 169.254.169.254/32. Create a namespace for testing:

```bash
kubectl create namespace tutorial-cluster-hardening-netpol
```

Create a test pod:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: metadata-test-pod
  namespace: tutorial-cluster-hardening-netpol
spec:
  containers:
  - name: curl
    image: curlimages/curl:8.5.0
    command: ["sleep", "3600"]
EOF

kubectl wait pod metadata-test-pod -n tutorial-cluster-hardening-netpol \
  --for=condition=Ready --timeout=60s
```

Apply the metadata protection NetworkPolicy:

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-metadata-endpoint
  namespace: tutorial-cluster-hardening-netpol
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 169.254.169.254/32
EOF
```

**Spec field documentation for this NetworkPolicy:**

- `podSelector: {}`: Selects all pods in the namespace (an empty selector matches everything).
- `policyTypes: [Egress]`: This policy controls outbound traffic from pods. Ingress traffic is not affected.
- `egress[0].to[0].ipBlock.cidr: 0.0.0.0/0`: Allow egress to any IP...
- `egress[0].to[0].ipBlock.except: [169.254.169.254/32]`: ...except the metadata endpoint.
- Default when field is omitted: Without `policyTypes`, both ingress and egress are evaluated. Without `egress` in the spec, all egress is denied when the policy type includes Egress (making the `except` redundant since nothing would be allowed). The `cidr: 0.0.0.0/0 except: 169.254.169.254/32` pattern is the standard way to allow everything except one specific destination.
- Failure mode when misconfigured: If you omit the `cidr: 0.0.0.0/0` allow rule and only specify the block, all egress (including DNS on port 53) is denied, breaking the pod's ability to resolve hostnames. This is the most common NetworkPolicy mistake in this domain.

Test the block:

```bash
kubectl exec metadata-test-pod -n tutorial-cluster-hardening-netpol -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: curl: (28) Connection timed out after 3000 milliseconds
# (or: curl: (7) Couldn't connect to server -- no route to host)
```

Verify that normal DNS and internet egress still work:

```bash
kubectl exec metadata-test-pod -n tutorial-cluster-hardening-netpol -- \
  curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com
# Expected: 200 (or a redirect code like 301)
```

If DNS does not work (the curl hangs on name resolution), your CNI enforces NetworkPolicy rules strictly and DNS egress to CoreDNS is also being blocked. Add an explicit DNS allow rule:

```bash
COREDNS_IP=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}')
echo "CoreDNS IP: $COREDNS_IP"

kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-metadata-allow-dns
  namespace: tutorial-cluster-hardening-netpol
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - ports:
    - protocol: UDP
      port: 53
    - protocol: TCP
      port: 53
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 169.254.169.254/32
EOF
```

## Cleanup

Delete the tutorial namespace and the netpol test namespace:

```bash
kubectl delete namespace tutorial-cluster-hardening tutorial-cluster-hardening-netpol
```

## Reference Commands

**etcd operations:**

| Command | Purpose |
|---|---|
| `nerdctl exec kind-control-plane bash -c "grep -E 'cert-auth' /etc/kubernetes/manifests/etcd.yaml"` | Check etcd TLS flags |
| `kubectl exec -n kube-system $ETCD_POD -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=... endpoint health` | Test etcd health with certs |
| `kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}'` | Get etcd pod name |

**Service account operations:**

| Command | Purpose |
|---|---|
| `kubectl auth can-i --list --as=system:serviceaccount:NS:SA -n NS` | List SA permissions |
| `kubectl exec POD -n NS -- ls /var/run/secrets/kubernetes.io/serviceaccount/` | Check if token is mounted |
| `kubectl get serviceaccounts -n NS -o yaml` | Show all SA specs in namespace |

**kubeconfig operations:**

| Command | Purpose |
|---|---|
| `ls -la ~/.kube/config` | Check kubeconfig permissions |
| `chmod 600 ~/.kube/config` | Fix permissions |
| `kubectl config view --minify` | Show current context credentials |

**NetworkPolicy verification:**

| Command | Purpose |
|---|---|
| `kubectl get networkpolicy -n NS` | List NetworkPolicies in namespace |
| `kubectl describe networkpolicy POLICY -n NS` | Show full policy spec |
| `kubectl exec POD -- curl -m 3 http://169.254.169.254/ 2>&1` | Test metadata endpoint access |
| `kubectl exec POD -- curl -m 5 -s http://example.com` | Test allowed egress still works |
