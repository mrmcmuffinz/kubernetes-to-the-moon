# Cluster Hardening Assignment 2 Homework

Work through the tutorial in `cluster-hardening-tutorial.md` before attempting these exercises. The tutorial covers etcd TLS verification, service account token automounting, kubeconfig file security, and the NetworkPolicy egress pattern for blocking cloud metadata endpoints. NetworkPolicy exercises require a CNI that enforces NetworkPolicy rules (see the tutorial for setup). etcd exercises use `kubectl exec` into the etcd pod and require no additional components.

All exercises use the `ex-<level>-<exercise>` namespace pattern. Level 3 and Level 5 exercises include setup commands that put the cluster in a broken or misconfigured state; run those commands exactly as written before starting the task.

---

## Level 1: Verification and Single-Action Configuration

### Exercise 1.1

**Objective:** Verify that etcd is configured to require TLS certificate authentication from clients and peers. If either flag is missing or set to false, correct it in the etcd static pod manifest.

**Setup:**

No additional setup is required. Use the single-node kind cluster.

**Task:**

Inspect `/etc/kubernetes/manifests/etcd.yaml` inside the kind control plane container. Confirm that both `--client-cert-auth=true` and `--peer-client-cert-auth=true` are present and set to `true`. If either flag is absent or set to `false`, add or correct it. After any changes, wait for etcd to restart and verify it is healthy.

**Verification:**

```bash
nerdctl exec kind-control-plane bash -c \
  "grep client-cert-auth /etc/kubernetes/manifests/etcd.yaml"
# Expected: - --client-cert-auth=true

nerdctl exec kind-control-plane bash -c \
  "grep peer-client-cert-auth /etc/kubernetes/manifests/etcd.yaml"
# Expected: - --peer-client-cert-auth=true

kubectl get pods -n kube-system -l component=etcd
# Expected: STATUS Running

ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')
kubectl exec -n kube-system "$ETCD_POD" -- \
  etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint health
# Expected: https://127.0.0.1:2379 is healthy: successfully committed proposal
```

---

### Exercise 1.2

**Objective:** Verify and correct the permissions on the kubeconfig file at `~/.kube/config` so that it is readable only by its owner.

**Setup:**

```bash
# Intentionally widen the permissions to simulate a misconfiguration
chmod 644 ~/.kube/config
ls -la ~/.kube/config
# Expected: -rw-r--r-- (wide open)
```

**Task:**

Inspect the current permissions on `~/.kube/config`. Set the permissions to `600` so the file is readable only by its owner. Verify the corrected permissions.

**Verification:**

```bash
ls -la ~/.kube/config
# Expected: -rw------- 1 <owner> <group> ... /home/<user>/.kube/config

stat -c "%a" ~/.kube/config
# Expected: 600
```

---

### Exercise 1.3

**Objective:** Create a ServiceAccount with token automounting disabled, create a Pod using that ServiceAccount, and verify that no service account token is mounted in the pod.

**Setup:**

```bash
kubectl create namespace ex-1-3
```

**Task:**

In the `ex-1-3` namespace, create a ServiceAccount named `no-token-worker` with `automountServiceAccountToken: false`. Create a Pod named `secure-pod` using `busybox:1.36` with `command: ["sleep", "3600"]` and the `no-token-worker` service account. Wait for the pod to be Running, then verify the service account token directory is absent.

**Verification:**

```bash
kubectl get pod secure-pod -n ex-1-3
# Expected: STATUS Running

kubectl get serviceaccount no-token-worker -n ex-1-3 -o jsonpath='{.automountServiceAccountToken}'
# Expected: false

kubectl exec secure-pod -n ex-1-3 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Expected: ls: /var/run/secrets/kubernetes.io/serviceaccount/: No such file or directory
```

---

## Level 2: Operational Security Controls

### Exercise 2.1

**Objective:** Disable service account token automounting on the `default` service account in a namespace and verify that newly created pods no longer receive the token.

**Setup:**

```bash
kubectl create namespace ex-2-1
```

**Task:**

Patch the `default` ServiceAccount in `ex-2-1` to set `automountServiceAccountToken: false`. Create a Pod named `test-pod-a` in `ex-2-1` using `busybox:1.36` with `command: ["sleep", "3600"]` (no explicit `serviceAccountName` so it uses the default SA). Verify that `test-pod-a` does not have the token mounted. Also verify that a pod explicitly setting `automountServiceAccountToken: true` on its own spec does receive the token.

**Verification:**

```bash
kubectl get serviceaccount default -n ex-2-1 -o jsonpath='{.automountServiceAccountToken}'
# Expected: false

kubectl exec test-pod-a -n ex-2-1 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Expected: ls: /var/run/secrets/kubernetes.io/serviceaccount/: No such file or directory

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: explicit-token-pod
  namespace: ex-2-1
spec:
  automountServiceAccountToken: true
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait pod explicit-token-pod -n ex-2-1 --for=condition=Ready --timeout=60s

kubectl exec explicit-token-pod -n ex-2-1 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/
# Expected: ca.crt  namespace  token
```

---

### Exercise 2.2

**Objective:** Create a NetworkPolicy in a namespace that blocks all pod egress to the cloud metadata endpoint (169.254.169.254/32) while allowing all other egress traffic.

**Setup:**

```bash
kubectl create namespace ex-2-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: curl-pod
  namespace: ex-2-2
spec:
  containers:
  - name: curl
    image: curlimages/curl:8.5.0
    command: ["sleep", "3600"]
EOF

kubectl wait pod curl-pod -n ex-2-2 --for=condition=Ready --timeout=60s
```

**Task:**

Create a NetworkPolicy named `block-metadata` in the `ex-2-2` namespace that:
- Applies to all pods in the namespace (empty podSelector).
- Controls egress traffic.
- Allows egress to all IP addresses except 169.254.169.254/32.

Verify the policy is in place by checking the NetworkPolicy spec. Also verify that the pod can still reach external destinations (DNS resolution or a connection to a known IP).

**Verification:**

```bash
kubectl get networkpolicy block-metadata -n ex-2-2
# Expected: the NetworkPolicy exists

kubectl get networkpolicy block-metadata -n ex-2-2 \
  -o jsonpath='{.spec.egress[0].to[0].ipBlock.except[0]}'
# Expected: 169.254.169.254/32

kubectl exec curl-pod -n ex-2-2 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: curl: (28) Connection timed out after 3000 milliseconds
# (or equivalent connection failure message -- the key result is that it does NOT return an HTTP response)
```

---

### Exercise 2.3

**Objective:** Audit the RBAC permissions of a service account that has been granted too much access. Remove the over-privileged binding and replace it with a minimal RoleBinding.

**Setup:**

```bash
kubectl create namespace ex-2-3
kubectl create serviceaccount report-reader -n ex-2-3

# Grant over-privileged access (cluster-admin is far too much for a report reader)
kubectl create clusterrolebinding report-reader-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=ex-2-3:report-reader
```

**Task:**

Inspect the RBAC permissions of `system:serviceaccount:ex-2-3:report-reader` using `kubectl auth can-i --list`. Identify that the service account has cluster-admin-level access. Remove the `report-reader-admin` ClusterRoleBinding. Create a minimal RoleBinding in the `ex-2-3` namespace that grants `report-reader` only `get` and `list` on `pods` and `pods/log` using the built-in `view` ClusterRole. Verify the reduced permissions.

**Verification:**

```bash
kubectl get clusterrolebinding report-reader-admin 2>&1
# Expected: Error from server (NotFound): ... -- the binding is gone

kubectl auth can-i delete pods \
  --as=system:serviceaccount:ex-2-3:report-reader \
  -n ex-2-3
# expect: no

kubectl auth can-i get pods \
  --as=system:serviceaccount:ex-2-3:report-reader \
  -n ex-2-3
# expect: yes

kubectl auth can-i delete namespaces \
  --as=system:serviceaccount:ex-2-3:report-reader
# expect: no
```

---

## Level 3: Debugging Broken Security Configurations

### Exercise 3.1

**Objective:** A pod in this namespace needs to call the Kubernetes API to list ConfigMaps in its own namespace. The pod is failing to authenticate because the service account token is not available. The configuration has one or more problems. Find and fix whatever is needed so the pod can authenticate to the Kubernetes API.

**Setup:**

```bash
kubectl create namespace ex-3-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: configmap-reader
  namespace: ex-3-1
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: read-configmaps
  namespace: ex-3-1
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: configmap-reader-binding
  namespace: ex-3-1
subjects:
- kind: ServiceAccount
  name: configmap-reader
  namespace: ex-3-1
roleRef:
  kind: Role
  name: read-configmaps
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Pod
metadata:
  name: api-client-pod
  namespace: ex-3-1
spec:
  serviceAccountName: configmap-reader
  containers:
  - name: app
    image: curlimages/curl:8.5.0
    command: ["sleep", "3600"]
EOF

kubectl wait pod api-client-pod -n ex-3-1 --for=condition=Ready --timeout=60s
```

**Task:**

The configuration above has one or more problems. Find and fix whatever is needed so that the `api-client-pod` can authenticate to the Kubernetes API using its service account token. The pod must be able to successfully list ConfigMaps in the `ex-3-1` namespace.

**Verification:**

```bash
kubectl exec api-client-pod -n ex-3-1 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/
# Expected: ca.crt  namespace  token

TOKEN=$(kubectl exec api-client-pod -n ex-3-1 -- \
  cat /var/run/secrets/kubernetes.io/serviceaccount/token)

kubectl exec api-client-pod -n ex-3-1 -- \
  curl -s -k \
  -H "Authorization: Bearer $TOKEN" \
  https://kubernetes.default.svc/api/v1/namespaces/ex-3-1/configmaps \
  | grep -c '"kind":"ConfigMapList"'
# Expected: 1
```

---

### Exercise 3.2

**Objective:** A NetworkPolicy in this namespace is too restrictive and is preventing pods from resolving DNS names. The pods cannot reach any external hostname. The configuration has one or more problems. Find and fix whatever is needed so that DNS resolution works and the metadata endpoint remains blocked.

**Setup:**

```bash
kubectl create namespace ex-3-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: dns-test-pod
  namespace: ex-3-2
spec:
  containers:
  - name: curl
    image: curlimages/curl:8.5.0
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-metadata-strict
  namespace: ex-3-2
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
        - 10.0.0.0/8
EOF

kubectl wait pod dns-test-pod -n ex-3-2 --for=condition=Ready --timeout=60s
```

**Task:**

The configuration above has one or more problems. The pod cannot resolve hostnames. Find the reason DNS resolution is failing, fix the NetworkPolicy so that DNS works and legitimate cluster traffic flows, while still blocking the metadata endpoint at 169.254.169.254/32.

**Verification:**

```bash
kubectl exec dns-test-pod -n ex-3-2 -- \
  curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com
# Expected: 200 or 301

kubectl exec dns-test-pod -n ex-3-2 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: curl: (28) Connection timed out (or similar connection failure)

kubectl get networkpolicy block-metadata-strict -n ex-3-2
# Expected: the NetworkPolicy still exists (not deleted -- fix it, don't remove it)
```

---

### Exercise 3.3

**Objective:** The API server cannot connect to etcd because an etcd certificate path has been misconfigured in the kube-apiserver.yaml manifest. The cluster is partially functional but API requests are failing. The configuration has one or more problems. Find and fix whatever is needed to restore full API server to etcd connectivity.

**Setup:**

```bash
nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex33-a2.bak
  cat > /tmp/fix_ex33_a2.py << 'PYEOF'
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    content = f.read()
content = content.replace(
    '--etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt',
    '--etcd-cafile=/etc/kubernetes/pki/etcd/wrong-ca.crt'
)
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.write(content)
PYEOF
python3 /tmp/fix_ex33_a2.py
"
# Wait for the API server to attempt restart (it will fail to connect to etcd)
sleep 30
```

**Task:**

The configuration above has one or more problems. The API server is failing to establish a TLS connection to etcd because a certificate path in the kube-apiserver.yaml manifest is incorrect. Locate the misconfigured flag, correct it to the proper path, and verify the API server restarts and can reach etcd.

**Verification:**

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

kubectl get nodes
# Expected: control-plane node with STATUS Ready

ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}')
kubectl get pod "$ETCD_POD" -n kube-system
# Expected: STATUS Running (etcd itself is fine)

nerdctl exec kind-control-plane bash -c \
  "grep etcd-cafile /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
```

---

## Level 4: Comprehensive Namespace Hardening

### Exercise 4.1

**Objective:** Apply a complete hardening workflow to a new namespace: audit the service accounts, disable unnecessary token mounts, restrict RBAC permissions, and verify everything is working correctly.

**Setup:**

```bash
kubectl create namespace ex-4-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: batch-processor
  namespace: ex-4-1
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-client
  namespace: ex-4-1
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: batch-processor-admin-ex41
subjects:
- kind: ServiceAccount
  name: batch-processor
  namespace: ex-4-1
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: ex-4-1
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: api-client-pods
  namespace: ex-4-1
subjects:
- kind: ServiceAccount
  name: api-client
  namespace: ex-4-1
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

**Task:**

Perform a full hardening workflow on `ex-4-1`:

1. Audit the RBAC permissions of both service accounts. Identify which one has excessive privileges.
2. Remove the over-privileged ClusterRoleBinding for `batch-processor`. Grant it only `get` and `list` on `jobs` in the `ex-4-1` namespace using a new Role and RoleBinding.
3. Disable `automountServiceAccountToken` on `batch-processor` (it does not need to call the API server; it reads from an external queue).
4. Leave `api-client` with automounting enabled (it legitimately needs to list pods).
5. Disable `automountServiceAccountToken` on the `default` service account in `ex-4-1`.
6. Verify all four controls are in place.

**Verification:**

```bash
kubectl get clusterrolebinding batch-processor-admin-ex41 2>&1
# Expected: Error from server (NotFound)

kubectl auth can-i delete pods \
  --as=system:serviceaccount:ex-4-1:batch-processor \
  -n ex-4-1
# expect: no

kubectl auth can-i list jobs \
  --as=system:serviceaccount:ex-4-1:batch-processor \
  -n ex-4-1
# expect: yes

kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-4-1:api-client \
  -n ex-4-1
# expect: yes

kubectl get serviceaccount batch-processor -n ex-4-1 \
  -o jsonpath='{.automountServiceAccountToken}'
# Expected: false

kubectl get serviceaccount default -n ex-4-1 \
  -o jsonpath='{.automountServiceAccountToken}'
# Expected: false
```

---

### Exercise 4.2

**Objective:** Configure metadata endpoint protection for a namespace and verify that both the block and the allowed traffic behave correctly.

**Setup:**

```bash
kubectl create namespace ex-4-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: workload-pod
  namespace: ex-4-2
spec:
  containers:
  - name: curl
    image: curlimages/curl:8.5.0
    command: ["sleep", "3600"]
EOF

kubectl wait pod workload-pod -n ex-4-2 --for=condition=Ready --timeout=60s
```

**Task:**

Create a NetworkPolicy named `protect-metadata` in `ex-4-2` that:
- Applies to all pods in the namespace.
- Allows all egress except to 169.254.169.254/32.
- Explicitly allows DNS egress (UDP and TCP port 53) so that hostname resolution is not broken.

Verify that the metadata endpoint is blocked and that DNS resolution still works.

**Verification:**

```bash
kubectl get networkpolicy protect-metadata -n ex-4-2
# Expected: the NetworkPolicy exists

kubectl exec workload-pod -n ex-4-2 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: Connection timed out or No route to host

kubectl exec workload-pod -n ex-4-2 -- \
  curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com
# Expected: 200 or 301

kubectl get networkpolicy protect-metadata -n ex-4-2 \
  -o jsonpath='{.spec.egress[*].to[*].ipBlock.except[*]}'
# Expected: includes 169.254.169.254/32
```

---

### Exercise 4.3

**Objective:** Audit service account permissions across a namespace with multiple service accounts and tighten RBAC so that each service account has only the permissions it needs.

**Setup:**

```bash
kubectl create namespace ex-4-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: monitoring-agent
  namespace: ex-4-3
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: deploy-manager
  namespace: ex-4-3
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: monitoring-agent-admin-ex43
subjects:
- kind: ServiceAccount
  name: monitoring-agent
  namespace: ex-4-3
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: deploy-manager-admin-ex43
subjects:
- kind: ServiceAccount
  name: deploy-manager
  namespace: ex-4-3
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF
```

**Task:**

Both service accounts currently have cluster-admin access. Restrict them as follows:

- `monitoring-agent`: should only be able to `get`, `list`, and `watch` pods, nodes, and namespaces cluster-wide. Use the built-in `view` ClusterRole and scope it to a ClusterRoleBinding (the agent needs cluster-wide read access).
- `deploy-manager`: should only be able to manage deployments (get, list, create, update, patch, delete) within the `ex-4-3` namespace. Create a Role and RoleBinding for this.

Remove the existing over-privileged ClusterRoleBindings.

**Verification:**

```bash
kubectl get clusterrolebinding monitoring-agent-admin-ex43 2>&1
# Expected: Error from server (NotFound)

kubectl get clusterrolebinding deploy-manager-admin-ex43 2>&1
# Expected: Error from server (NotFound)

kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-4-3:monitoring-agent \
  -n kube-system
# expect: yes

kubectl auth can-i delete secrets \
  --as=system:serviceaccount:ex-4-3:monitoring-agent \
  -n default
# expect: no

kubectl auth can-i create deployments \
  --as=system:serviceaccount:ex-4-3:deploy-manager \
  -n ex-4-3
# expect: yes

kubectl auth can-i create deployments \
  --as=system:serviceaccount:ex-4-3:deploy-manager \
  -n kube-system
# expect: no
```

---

## Level 5: Multi-Issue Advanced Debugging

### Exercise 5.1

**Objective:** A workload in this namespace is broken due to multiple security misconfigurations applied simultaneously. The configuration has one or more problems. Find and fix all issues so that the pod can authenticate to the Kubernetes API and the namespace is protected against metadata endpoint access.

**Setup:**

```bash
kubectl create namespace ex-5-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: secure-app
  namespace: ex-5-1
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: ex-5-1
rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: secure-app-secrets
  namespace: ex-5-1
subjects:
- kind: ServiceAccount
  name: secure-app
  namespace: ex-5-1
roleRef:
  kind: Role
  name: secret-reader
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: app-egress
  namespace: ex-5-1
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 192.168.0.0/16
---
apiVersion: v1
kind: Pod
metadata:
  name: secure-app-pod
  namespace: ex-5-1
spec:
  serviceAccountName: secure-app
  containers:
  - name: app
    image: curlimages/curl:8.5.0
    command: ["sleep", "3600"]
EOF

kubectl wait pod secure-app-pod -n ex-5-1 --for=condition=Ready --timeout=60s
```

**Task:**

The configuration above has one or more problems. The pod must be able to list Secrets in its namespace using its service account token, and the namespace must allow DNS resolution while blocking the cloud metadata endpoint. Find and fix all problems in this configuration without removing the NetworkPolicy entirely and without granting more RBAC permissions than the service account already has.

**Verification:**

```bash
kubectl exec secure-app-pod -n ex-5-1 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/
# Expected: ca.crt  namespace  token

kubectl exec secure-app-pod -n ex-5-1 -- \
  curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com
# Expected: 200 or 301

kubectl exec secure-app-pod -n ex-5-1 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: Connection timed out or No route to host

kubectl auth can-i list secrets \
  --as=system:serviceaccount:ex-5-1:secure-app \
  -n ex-5-1
# expect: yes
```

---

### Exercise 5.2

**Objective:** This namespace has an over-privileged service account and a NetworkPolicy that is supposed to block the metadata endpoint but is incorrectly configured and blocks cluster DNS instead. The configuration has one or more problems. Fix both issues simultaneously.

**Setup:**

```bash
kubectl create namespace ex-5-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-runner
  namespace: ex-5-2
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: app-runner-admin-ex52
subjects:
- kind: ServiceAccount
  name: app-runner
  namespace: ex-5-2
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: metadata-block-broken
  namespace: ex-5-2
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 169.254.169.254/32
---
apiVersion: v1
kind: Pod
metadata:
  name: app-pod
  namespace: ex-5-2
  labels:
    app: runner
spec:
  serviceAccountName: app-runner
  containers:
  - name: curl
    image: curlimages/curl:8.5.0
    command: ["sleep", "3600"]
EOF

kubectl wait pod app-pod -n ex-5-2 --for=condition=Ready --timeout=60s
```

**Task:**

The configuration above has one or more problems. Fix both: the service account's cluster-admin ClusterRoleBinding is excessive (replace it with a RoleBinding giving only `get` and `list` on `pods` in `ex-5-2`), and the NetworkPolicy allows access only to the metadata endpoint (which is the opposite of the intended behavior). Fix the NetworkPolicy so the metadata endpoint is blocked and all other egress is allowed (including DNS).

**Verification:**

```bash
kubectl get clusterrolebinding app-runner-admin-ex52 2>&1
# Expected: Error from server (NotFound)

kubectl auth can-i delete namespaces \
  --as=system:serviceaccount:ex-5-2:app-runner
# expect: no

kubectl auth can-i list pods \
  --as=system:serviceaccount:ex-5-2:app-runner \
  -n ex-5-2
# expect: yes

kubectl exec app-pod -n ex-5-2 -- \
  curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com
# Expected: 200 or 301

kubectl exec app-pod -n ex-5-2 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: Connection timed out or No route to host
```

---

### Exercise 5.3

**Objective:** The API server has been disconnected from etcd due to a wrong certificate path in the kube-apiserver.yaml manifest, AND a service account in a target namespace is over-privileged with cluster-admin access. The configuration has one or more problems. Restore the API server first, then audit and restrict the service account permissions.

**Setup:**

```bash
# Step 1: Grant a service account cluster-admin (will be cleaned up after restoring API server)
# (Can't pre-create the namespace since API server is going down -- we'll use default ns)
kubectl create serviceaccount over-privileged-sa -n default
kubectl create clusterrolebinding over-privileged-ex53 \
  --clusterrole=cluster-admin \
  --serviceaccount=default:over-privileged-sa

# Step 2: Break the API server's etcd connection
nerdctl exec kind-control-plane bash -c "
  cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver-ex53-a2.bak
  cat > /tmp/fix_ex53_a2.py << 'PYEOF'
with open('/etc/kubernetes/manifests/kube-apiserver.yaml') as f:
    content = f.read()
content = content.replace(
    '--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt',
    '--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client-WRONG.crt'
)
with open('/etc/kubernetes/manifests/kube-apiserver.yaml', 'w') as f:
    f.write(content)
PYEOF
python3 /tmp/fix_ex53_a2.py
"
# API server will stop. This is expected.
```

**Task:**

The configuration above has one or more problems. First, restore API server connectivity to etcd by fixing the certificate path in kube-apiserver.yaml (use `nerdctl exec` since kubectl is unavailable). Once the API server is running, audit the RBAC permissions of `system:serviceaccount:default:over-privileged-sa`, remove the cluster-admin ClusterRoleBinding, and replace it with a minimal RoleBinding giving only `get` and `list` on `configmaps` in the `default` namespace.

**Verification:**

```bash
# After API server is restored:
kubectl get pods -n kube-system -l component=kube-apiserver
# Expected: STATUS Running

nerdctl exec kind-control-plane bash -c \
  "grep etcd-certfile /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt

kubectl get clusterrolebinding over-privileged-ex53 2>&1
# Expected: Error from server (NotFound)

kubectl auth can-i delete namespaces \
  --as=system:serviceaccount:default:over-privileged-sa
# expect: no

kubectl auth can-i list configmaps \
  --as=system:serviceaccount:default:over-privileged-sa \
  -n default
# expect: yes

kubectl version
# Expected: Server Version shown
```

---

## Cleanup

Delete all exercise namespaces and any cluster-scoped resources created during this homework:

```bash
kubectl delete namespace ex-1-3 ex-2-1 ex-2-2 ex-2-3 ex-3-1 ex-3-2 ex-4-1 ex-4-2 ex-4-3 ex-5-1 ex-5-2

kubectl delete clusterrolebinding report-reader-admin 2>/dev/null || true
kubectl delete clusterrolebinding over-privileged-ex53 2>/dev/null || true
kubectl delete clusterrolebinding batch-processor-admin-ex41 2>/dev/null || true
kubectl delete clusterrolebinding monitoring-agent-admin-ex43 2>/dev/null || true
kubectl delete clusterrolebinding deploy-manager-admin-ex43 2>/dev/null || true
kubectl delete clusterrolebinding app-runner-admin-ex52 2>/dev/null || true
kubectl delete serviceaccount over-privileged-sa -n default 2>/dev/null || true

# Restore the API server manifest if exercises 3.3 or 5.3 left it modified
# nerdctl exec kind-control-plane bash -c \
#   "cp /tmp/kube-apiserver-ex53-a2.bak /etc/kubernetes/manifests/kube-apiserver.yaml"

# Restore kubeconfig permissions if exercise 1.2 was not verified
chmod 600 ~/.kube/config
```

---

## Key Takeaways

The exercises in this assignment address the components of cluster hardening that sit outside the API server but are equally critical. etcd TLS authentication prevents unauthorized access to the cluster's data store from any entity that can reach the etcd port. Service account token automounting reduces the attack surface for any compromised pod by eliminating credentials that were never needed in the first place. Kubeconfig permissions prevent local user impersonation on shared systems. NetworkPolicy egress rules block the cloud metadata endpoint as a defense against container escape attacks that attempt to steal cloud credentials. Together with the API server hardening from Assignment 1, these controls define the cluster hardening baseline that CKA and CKS exams test.
