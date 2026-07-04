# Cluster Hardening Assignment 2 Homework Answers

---

## Exercise 1.1 Solution

Inspect the etcd manifest for the TLS auth flags:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep -E 'cert-auth' /etc/kubernetes/manifests/etcd.yaml"
```

In a kubeadm-provisioned kind cluster both flags should already be present and set to `true`. If either is missing or set to `false`, enter the container, back up the manifest, and correct the flag:

```bash
nerdctl exec -it kind-control-plane bash
cp /etc/kubernetes/manifests/etcd.yaml /tmp/etcd.yaml.bak
vi /etc/kubernetes/manifests/etcd.yaml
# Add or correct:
# - --client-cert-auth=true
# - --peer-client-cert-auth=true
exit
```

Wait for etcd to restart:

```bash
kubectl get pods -n kube-system -l component=etcd -w
```

Verify with etcdctl:

```bash
ETCD_POD=$(kubectl get pods -n kube-system -l component=etcd \
  -o jsonpath='{.items[0].metadata.name}')
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

## Exercise 1.2 Solution

The setup set the kubeconfig to `644`. The fix is:

```bash
chmod 600 ~/.kube/config
```

Verify:

```bash
ls -la ~/.kube/config
# Expected: -rw------- 1 <owner> ...

stat -c "%a" ~/.kube/config
# Expected: 600
```

---

## Exercise 1.3 Solution

Create the ServiceAccount and Pod:

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: no-token-worker
  namespace: ex-1-3
automountServiceAccountToken: false
---
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: ex-1-3
spec:
  serviceAccountName: no-token-worker
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait pod secure-pod -n ex-1-3 --for=condition=Ready --timeout=60s
```

Verify the token is absent:

```bash
kubectl exec secure-pod -n ex-1-3 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Expected: ls: /var/run/secrets/kubernetes.io/serviceaccount/: No such file or directory
```

---

## Exercise 2.1 Solution

Patch the default ServiceAccount to disable automounting:

```bash
kubectl patch serviceaccount default -n ex-2-1 \
  -p '{"automountServiceAccountToken": false}'
```

Create the test pod (it uses the default SA since no serviceAccountName is specified):

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: test-pod-a
  namespace: ex-2-1
spec:
  containers:
  - name: app
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait pod test-pod-a -n ex-2-1 --for=condition=Ready --timeout=60s
```

Verify:

```bash
kubectl exec test-pod-a -n ex-2-1 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Expected: No such file or directory
```

Create the explicit-override pod and verify it gets the token:

```bash
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

## Exercise 2.2 Solution

Create the NetworkPolicy:

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-metadata
  namespace: ex-2-2
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

Verify the policy structure:

```bash
kubectl get networkpolicy block-metadata -n ex-2-2 \
  -o jsonpath='{.spec.egress[0].to[0].ipBlock.except[0]}'
# Expected: 169.254.169.254/32
```

Test the block:

```bash
kubectl exec curl-pod -n ex-2-2 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: Connection timed out or No route to host
```

---

## Exercise 2.3 Solution

Audit current permissions:

```bash
kubectl auth can-i --list \
  --as=system:serviceaccount:ex-2-3:report-reader \
  -n ex-2-3
# You will see a long list of permissions including delete, create -- cluster-admin level
```

Remove the over-privileged binding:

```bash
kubectl delete clusterrolebinding report-reader-admin
```

Create a minimal RoleBinding using the built-in `view` ClusterRole:

```bash
kubectl create rolebinding report-reader-view \
  --clusterrole=view \
  --serviceaccount=ex-2-3:report-reader \
  -n ex-2-3
```

Verify the reduced permissions:

```bash
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

## Exercise 3.1 Solution

**Diagnosis:**

Verify the symptom: the pod should be able to use its SA token but cannot.

```bash
kubectl exec api-client-pod -n ex-3-1 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Output: No such file or directory
```

The token directory is absent. Inspect the ServiceAccount:

```bash
kubectl get serviceaccount configmap-reader -n ex-3-1 \
  -o jsonpath='{.automountServiceAccountToken}'
# Output: false
```

The `configmap-reader` ServiceAccount has `automountServiceAccountToken: false`. The pod uses this SA but needs the token to authenticate. The pod spec does not set `automountServiceAccountToken: true` at the pod level, so it inherits the SA's `false` setting.

**What the bug is and why it happens:**

The `automountServiceAccountToken: false` setting on the ServiceAccount is correct for pods that do not need API access, but this particular pod is designed to call the Kubernetes API. Someone applied the token restriction to the wrong service account, or applied a blanket restriction without considering which pods actually need API credentials. The RBAC Role and RoleBinding are correctly configured; the issue is purely that the token is not being mounted.

**The fix:**

The pod needs the token. The cleanest fix is to enable automounting at the pod level (overriding the SA setting), since the SA-level `false` is appropriate as a default for other pods using the same SA:

```bash
kubectl delete pod api-client-pod -n ex-3-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api-client-pod
  namespace: ex-3-1
spec:
  serviceAccountName: configmap-reader
  automountServiceAccountToken: true
  containers:
  - name: app
    image: curlimages/curl:8.5.0
    command: ["sleep", "3600"]
EOF

kubectl wait pod api-client-pod -n ex-3-1 --for=condition=Ready --timeout=60s
```

Alternatively, enable automounting at the SA level if all pods using `configmap-reader` need the token:

```bash
kubectl patch serviceaccount configmap-reader -n ex-3-1 \
  -p '{"automountServiceAccountToken": true}'
```

Verify:

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

## Exercise 3.2 Solution

**Diagnosis:**

Attempt to resolve a hostname from the pod:

```bash
kubectl exec dns-test-pod -n ex-3-2 -- \
  curl -m 5 http://example.com 2>&1
# Output: curl: (6) Could not resolve host: example.com
# (or: the command hangs and times out)
```

DNS resolution is failing. Inspect the NetworkPolicy:

```bash
kubectl get networkpolicy block-metadata-strict -n ex-3-2 -o yaml
```

The policy allows egress to `0.0.0.0/0` except `169.254.169.254/32` and `10.0.0.0/8`. The `10.0.0.0/8` exclusion is the problem: CoreDNS in a kind cluster typically runs with a ClusterIP in the `10.96.0.0/16` range (which falls within `10.0.0.0/8`). The egress deny for `10.0.0.0/8` is blocking DNS queries to CoreDNS.

**What the bug is and why it happens:**

The intent was probably to block some internal network range for a different reason, but `10.0.0.0/8` is far too broad for a Kubernetes cluster where all services use a `10.x.x.x` ClusterIP range by default. Blocking `10.0.0.0/8` in egress rules will always break CoreDNS access. This is one of the most common NetworkPolicy mistakes: a broad IP block that was not tested against the cluster's internal service addressing.

**The fix:**

Remove the `10.0.0.0/8` exception from the NetworkPolicy. The only address that should be blocked is `169.254.169.254/32`:

```bash
kubectl apply -f - <<EOF
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
EOF
```

Verify:

```bash
kubectl exec dns-test-pod -n ex-3-2 -- \
  curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com
# Expected: 200 or 301

kubectl exec dns-test-pod -n ex-3-2 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: Connection timed out or No route to host
```

---

## Exercise 3.3 Solution

**Diagnosis:**

The API server is struggling or failing. Check its status:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver
# It may show CrashLoopBackOff or multiple restarts, or kubectl may time out
```

Inspect the kube-apiserver.yaml for the etcd certificate flags:

```bash
nerdctl exec kind-control-plane bash -c \
  "grep etcd-cafile /etc/kubernetes/manifests/kube-apiserver.yaml"
# Output: - --etcd-cafile=/etc/kubernetes/pki/etcd/wrong-ca.crt
```

The `--etcd-cafile` flag points to `wrong-ca.crt` instead of `ca.crt`. The API server cannot validate etcd's TLS certificate without the correct CA, causing connection failures to etcd.

**What the bug is and why it happens:**

The etcd CA certificate path tells the API server which CA to trust when validating the certificate that etcd presents during the TLS handshake. An incorrect path means the API server either cannot find the file (causing an immediate startup error) or loads the wrong CA (causing the TLS handshake to fail at runtime). In either case, all requests that require etcd (which is almost everything) will fail. This failure mode is realistic: it can happen when someone edits the etcd certificate paths during a certificate rotation procedure and makes a typo.

**The fix:**

Correct the path to the actual CA certificate:

```bash
nerdctl exec -it kind-control-plane bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Change: - --etcd-cafile=/etc/kubernetes/pki/etcd/wrong-ca.crt
# To:     - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
exit
```

Wait for the API server to restart:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
```

Verify:

```bash
kubectl get nodes
# Expected: control-plane node with STATUS Ready

nerdctl exec kind-control-plane bash -c \
  "grep etcd-cafile /etc/kubernetes/manifests/kube-apiserver.yaml"
# Expected: - --etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
```

---

## Exercise 4.1 Solution

Audit both service accounts:

```bash
kubectl auth can-i --list \
  --as=system:serviceaccount:ex-4-1:batch-processor \
  -n ex-4-1
# This will show full cluster-admin permissions -- everything is allowed

kubectl auth can-i --list \
  --as=system:serviceaccount:ex-4-1:api-client \
  -n ex-4-1
# This will show only get/list/watch on pods -- appropriate
```

Remove the over-privileged binding:

```bash
kubectl delete clusterrolebinding batch-processor-admin-ex41
```

Create a minimal Role and RoleBinding for batch-processor:

```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: job-reader
  namespace: ex-4-1
rules:
- apiGroups: ["batch"]
  resources: ["jobs"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: batch-processor-jobs
  namespace: ex-4-1
subjects:
- kind: ServiceAccount
  name: batch-processor
  namespace: ex-4-1
roleRef:
  kind: Role
  name: job-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

Disable automounting on batch-processor and default SA:

```bash
kubectl patch serviceaccount batch-processor -n ex-4-1 \
  -p '{"automountServiceAccountToken": false}'

kubectl patch serviceaccount default -n ex-4-1 \
  -p '{"automountServiceAccountToken": false}'
```

Verify:

```bash
kubectl auth can-i delete pods \
  --as=system:serviceaccount:ex-4-1:batch-processor \
  -n ex-4-1
# expect: no

kubectl auth can-i list jobs \
  --as=system:serviceaccount:ex-4-1:batch-processor \
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

## Exercise 4.2 Solution

Create the NetworkPolicy with explicit DNS allowance:

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: protect-metadata
  namespace: ex-4-2
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

Verify the block and allowed traffic:

```bash
kubectl exec workload-pod -n ex-4-2 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: Connection timed out or No route to host

kubectl exec workload-pod -n ex-4-2 -- \
  curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com
# Expected: 200 or 301

kubectl get networkpolicy protect-metadata -n ex-4-2 \
  -o jsonpath='{.spec.egress[*].to[*].ipBlock.except[*]}'
# Expected: 169.254.169.254/32
```

---

## Exercise 4.3 Solution

Remove the over-privileged bindings:

```bash
kubectl delete clusterrolebinding monitoring-agent-admin-ex43
kubectl delete clusterrolebinding deploy-manager-admin-ex43
```

Create appropriate bindings for monitoring-agent (cluster-wide read using the `view` ClusterRole):

```bash
kubectl create clusterrolebinding monitoring-agent-view \
  --clusterrole=view \
  --serviceaccount=ex-4-3:monitoring-agent
```

Create a Role and RoleBinding for deploy-manager (namespace-scoped deployment management):

```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: deployment-manager
  namespace: ex-4-3
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deploy-manager-deployments
  namespace: ex-4-3
subjects:
- kind: ServiceAccount
  name: deploy-manager
  namespace: ex-4-3
roleRef:
  kind: Role
  name: deployment-manager
  apiGroup: rbac.authorization.k8s.io
EOF
```

Verify:

```bash
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

Clean up the extra ClusterRoleBinding created for monitoring-agent after verification:

```bash
# Note: kubectl delete clusterrolebinding monitoring-agent-view is NOT needed here;
# the exercise asks you to grant cluster-wide read access intentionally.
```

---

## Exercise 5.1 Solution

**Diagnosis:**

Check the pod's SA token status:

```bash
kubectl exec secure-app-pod -n ex-5-1 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1
# Output: No such file or directory
```

Token is missing. Check the SA:

```bash
kubectl get serviceaccount secure-app -n ex-5-1 \
  -o jsonpath='{.automountServiceAccountToken}'
# Output: false
```

Check the NetworkPolicy:

```bash
kubectl get networkpolicy app-egress -n ex-5-1 -o yaml
```

The NetworkPolicy only allows egress to `192.168.0.0/16`, which does not include DNS or general internet traffic. The metadata endpoint is not explicitly mentioned -- it is blocked because all other destinations are also blocked.

**What the bugs are and why they happen:**

Two separate configuration mistakes: the SA has `automountServiceAccountToken: false` preventing the pod from getting credentials it needs, and the NetworkPolicy has an overly narrow egress allowlist that blocks DNS (pod cannot resolve any hostname). Both are cases of security controls applied too broadly without considering the pod's actual requirements.

**The fix:**

Fix 1: Enable token automounting at the pod level (override the SA setting):

```bash
kubectl delete pod secure-app-pod -n ex-5-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: secure-app-pod
  namespace: ex-5-1
spec:
  serviceAccountName: secure-app
  automountServiceAccountToken: true
  containers:
  - name: app
    image: curlimages/curl:8.5.0
    command: ["sleep", "3600"]
EOF

kubectl wait pod secure-app-pod -n ex-5-1 --for=condition=Ready --timeout=60s
```

Fix 2: Replace the overly narrow NetworkPolicy with one that blocks only the metadata endpoint while allowing DNS and all other egress:

```bash
kubectl apply -f - <<EOF
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

Verify:

```bash
kubectl exec secure-app-pod -n ex-5-1 -- \
  ls /var/run/secrets/kubernetes.io/serviceaccount/
# Expected: ca.crt  namespace  token

kubectl exec secure-app-pod -n ex-5-1 -- \
  curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com
# Expected: 200 or 301

kubectl exec secure-app-pod -n ex-5-1 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: Connection timed out
```

---

## Exercise 5.2 Solution

**Diagnosis:**

Check the NetworkPolicy:

```bash
kubectl get networkpolicy metadata-block-broken -n ex-5-2 -o yaml
```

The policy allows egress only to `169.254.169.254/32` (the metadata endpoint), which is the opposite of the intent. This blocks everything except the metadata endpoint, including DNS. The RBAC issue is visible:

```bash
kubectl auth can-i delete namespaces \
  --as=system:serviceaccount:ex-5-2:app-runner
# Returns: yes -- cluster-admin level access
```

**What the bugs are and why they happen:**

The NetworkPolicy was written backwards: the `to` field specifies the metadata endpoint as the allowed destination, when it should be specified in the `except` block of an allow-all rule. This error is common when someone writes the policy without testing it; the manifest looks vaguely correct but has inverted logic. The cluster-admin binding is the second issue: a service account that only needs to list pods should never have cluster-admin, which grants full control of the entire cluster.

**The fix:**

Fix the NetworkPolicy (replace the inverted policy with the correct pattern):

```bash
kubectl apply -f - <<EOF
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

Fix the RBAC (remove cluster-admin, grant minimal permissions):

```bash
kubectl delete clusterrolebinding app-runner-admin-ex52

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: app-runner-pods
  namespace: ex-5-2
subjects:
- kind: ServiceAccount
  name: app-runner
  namespace: ex-5-2
roleRef:
  kind: ClusterRole
  name: view
  apiGroup: rbac.authorization.k8s.io
EOF
```

Verify:

```bash
kubectl exec app-pod -n ex-5-2 -- \
  curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com
# Expected: 200 or 301

kubectl exec app-pod -n ex-5-2 -- \
  curl -m 3 http://169.254.169.254/ 2>&1
# Expected: Connection timed out

kubectl auth can-i delete namespaces \
  --as=system:serviceaccount:ex-5-2:app-runner
# expect: no
```

---

## Exercise 5.3 Solution

**Diagnosis:**

kubectl is unavailable. Enter the container:

```bash
nerdctl exec -it kind-control-plane bash
```

Check the etcd certificate flags in the kube-apiserver.yaml:

```bash
grep etcd-cert /etc/kubernetes/manifests/kube-apiserver.yaml
# Look for: - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client-WRONG.crt
```

Also check the container logs for the exact error:

```bash
crictl logs $(crictl ps -a | grep kube-apiserver | awk '{print $1}' | head -1) 2>&1 | tail -20
# Expected: TLS handshake error or certificate file not found
```

**What the bug is and why it happens:**

The `--etcd-certfile` flag specifies the client certificate the API server presents to etcd during the mutual TLS handshake. If the file path is wrong, etcd either rejects the connection (file not found at startup) or rejects the handshake (wrong certificate). This is a realistic failure during certificate rotation: someone updated the API server config to point to a new certificate path but made a typo.

**The fix (Part 1 - restore API server):**

```bash
vi /etc/kubernetes/manifests/kube-apiserver.yaml
# Change: - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client-WRONG.crt
# To:     - --etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
exit
```

Wait for the API server to come back:

```bash
kubectl get pods -n kube-system -l component=kube-apiserver -w
# Wait for Running
```

**The fix (Part 2 - restrict RBAC):**

Once the API server is running:

```bash
kubectl delete clusterrolebinding over-privileged-ex53

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: configmap-reader
  namespace: default
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: over-privileged-sa-configmaps
  namespace: default
subjects:
- kind: ServiceAccount
  name: over-privileged-sa
  namespace: default
roleRef:
  kind: Role
  name: configmap-reader
  apiGroup: rbac.authorization.k8s.io
EOF
```

Verify:

```bash
kubectl get clusterrolebinding over-privileged-ex53 2>&1
# Expected: Error from server (NotFound)

kubectl auth can-i delete namespaces \
  --as=system:serviceaccount:default:over-privileged-sa
# expect: no

kubectl auth can-i list configmaps \
  --as=system:serviceaccount:default:over-privileged-sa \
  -n default
# expect: yes
```

---

## Common Mistakes

**1. Disabling automountServiceAccountToken on a service account without auditing which pods need the token.**

Setting `automountServiceAccountToken: false` on a ServiceAccount applies to all pods using that SA, including pods that legitimately need to call the Kubernetes API (operators, controllers, monitoring agents, service meshes). The correct workflow is to audit which pods need API access, disable automounting on the SA as a secure default, and re-enable it at the pod spec level (`automountServiceAccountToken: true`) for the specific pods that require it. Applying a blanket disable without this audit breaks applications silently, because the pod starts successfully but fails when it first tries to authenticate.

**2. Writing a metadata protection NetworkPolicy that blocks DNS by excluding the entire internal IP range.**

The metadata endpoint (169.254.169.254/32) is a link-local address, not part of the cluster's internal service CIDR. A common mistake is excluding `10.0.0.0/8` or the cluster's pod CIDR in the egress except list, which inadvertently blocks DNS queries to CoreDNS. DNS queries go to the CoreDNS ClusterIP (typically in the `10.96.0.0/16` range in kind), so blocking any broad `10.x.x.x` range will silently break hostname resolution. Always write the metadata block as `except: [169.254.169.254/32]` only, and add an explicit DNS allow rule for UDP and TCP port 53 as a defensive measure.

**3. Writing a NetworkPolicy `to` block that allows the metadata endpoint instead of blocking it.**

The egress block pattern uses `cidr: 0.0.0.0/0` with `except: [169.254.169.254/32]`. A common inversion is to write only `to: [{ipBlock: {cidr: 169.254.169.254/32}}]`, which allows egress only to the metadata endpoint and blocks everything else. This is the opposite of the intent. The rule should be: allow everything, except the metadata endpoint. The `cidr`-with-`except` pattern in the `ipBlock` field is the correct construct.

**4. Assuming that deleting a ClusterRoleBinding is enough without creating a replacement.**

When you remove a cluster-admin binding from a service account that legitimately needs some API access, removing the binding alone leaves the SA with no permissions. Pods using that SA will start failing with 403 Forbidden errors when they call the API. The correct workflow is: identify the minimum permissions needed, write a Role or ClusterRole with just those permissions, create the RoleBinding or ClusterRoleBinding for the SA, verify it works, and then delete the over-privileged binding.

**5. Not verifying etcd TLS flags actually prevent unauthenticated connections.**

It is not sufficient to check that `--client-cert-auth=true` appears in the etcd manifest. You should also verify functionally that an unauthenticated etcdctl call fails. If the flag is present but the `--trusted-ca-file` references a non-existent or wrong CA, the TLS setup may not work as expected. Always test with an actual etcdctl command using the correct certs to confirm the healthy endpoint response.

---

## Verification Commands Cheat Sheet

| Goal | Command | Expected Output |
|---|---|---|
| Check etcd client-cert-auth | `nerdctl exec kind-control-plane bash -c "grep client-cert-auth /etc/kubernetes/manifests/etcd.yaml"` | `- --client-cert-auth=true` |
| Check etcd peer-client-cert-auth | `nerdctl exec kind-control-plane bash -c "grep peer-client-cert-auth /etc/kubernetes/manifests/etcd.yaml"` | `- --peer-client-cert-auth=true` |
| Test etcd health with certs | `kubectl exec -n kube-system $ETCD_POD -- etcdctl --endpoints=https://127.0.0.1:2379 --cacert=... endpoint health` | `is healthy: successfully committed proposal` |
| Get etcd pod name | `kubectl get pods -n kube-system -l component=etcd -o jsonpath='{.items[0].metadata.name}'` | pod name |
| Check kubeconfig permissions | `ls -la ~/.kube/config` | `-rw-------` |
| Fix kubeconfig permissions | `chmod 600 ~/.kube/config` | (run once, verify with ls -la) |
| Check SA automount setting | `kubectl get sa SA_NAME -n NS -o jsonpath='{.automountServiceAccountToken}'` | `false` |
| Verify token is absent | `kubectl exec POD -n NS -- ls /var/run/secrets/kubernetes.io/serviceaccount/ 2>&1` | No such file or directory |
| Verify token is present | `kubectl exec POD -n NS -- ls /var/run/secrets/kubernetes.io/serviceaccount/` | ca.crt namespace token |
| Audit SA permissions | `kubectl auth can-i --list --as=system:serviceaccount:NS:SA -n NS` | list of permissions |
| Check specific SA permission | `kubectl auth can-i VERB RESOURCE --as=system:serviceaccount:NS:SA -n NS` | yes or no |
| Test metadata block | `kubectl exec POD -- curl -m 3 http://169.254.169.254/ 2>&1` | Connection timed out |
| Test DNS still works | `kubectl exec POD -- curl -m 5 -s -o /dev/null -w "%{http_code}" http://example.com` | 200 or 301 |
| List NetworkPolicies | `kubectl get networkpolicy -n NS` | policy names |
| Show NetworkPolicy spec | `kubectl describe networkpolicy NAME -n NS` | full policy rules |
| Fix etcd cert path | `nerdctl exec -it kind-control-plane bash` then `vi /etc/kubernetes/manifests/kube-apiserver.yaml` | corrected flag |
