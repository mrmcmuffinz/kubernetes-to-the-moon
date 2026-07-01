# Network Policies Homework: Advanced Selectors and Isolation

Work through these 15 exercises to build practical skills with advanced Network Policy selectors and isolation patterns. Complete the tutorial (network-policies-tutorial.md) before starting these exercises.

---

## Level 1: Cross-Namespace Policies

These exercises focus on using namespaceSelector for cross-namespace traffic control.

### Exercise 1.1

**Objective:** Allow ingress from a specific namespace using namespaceSelector.

**Setup:**

```bash
kubectl create namespace ex-1-1-app
kubectl create namespace ex-1-1-monitoring
kubectl label namespace ex-1-1-monitoring purpose=monitoring

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: ex-1-1-app
  labels:
    app: webapp
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: monitor
  namespace: ex-1-1-monitoring
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: attacker
  namespace: ex-1-1-app
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-1-1-app --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-1-1-monitoring --timeout=60s
```

**Task:** Create a NetworkPolicy in ex-1-1-app that allows ingress to the app pod only from namespaces labeled `purpose=monitoring`.

**Verification:**

```bash
APP_IP=$(kubectl get pod app -n ex-1-1-app -o jsonpath='{.status.podIP}')

# From monitoring namespace (should work)
kubectl exec -n ex-1-1-monitoring monitor -- wget -qO- --timeout=2 http://$APP_IP && echo "monitor: ALLOWED"

# From same namespace (should be blocked)
timeout 3 kubectl exec -n ex-1-1-app attacker -- wget -qO- --timeout=2 http://$APP_IP || echo "attacker: BLOCKED"
```

---

### Exercise 1.2

**Objective:** Allow egress to a specific namespace.

**Setup:**

```bash
kubectl create namespace ex-1-2-frontend
kubectl create namespace ex-1-2-backend
kubectl label namespace ex-1-2-backend tier=backend

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ex-1-2-backend
  labels:
    app: api
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: ex-1-2-frontend
  labels:
    app: web
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: other
  namespace: ex-1-2-frontend
spec:
  containers:
  - name: nginx
    image: nginx:1.25
EOF

kubectl wait --for=condition=Ready pods --all -n ex-1-2-backend --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-1-2-frontend --timeout=60s
```

**Task:** Create a NetworkPolicy in ex-1-2-frontend that restricts the web pod egress to only reach namespaces labeled `tier=backend`. Include DNS access.

**Verification:**

```bash
API_IP=$(kubectl get pod api -n ex-1-2-backend -o jsonpath='{.status.podIP}')
OTHER_IP=$(kubectl get pod other -n ex-1-2-frontend -o jsonpath='{.status.podIP}')

# To backend namespace (should work)
kubectl exec -n ex-1-2-frontend web -- wget -qO- --timeout=2 http://$API_IP && echo "to backend: ALLOWED"

# To same namespace (should be blocked)
timeout 3 kubectl exec -n ex-1-2-frontend web -- wget -qO- --timeout=2 http://$OTHER_IP || echo "to other: BLOCKED"
```

---

### Exercise 1.3

**Objective:** Use the built-in namespace name label for selection.

**Setup:**

```bash
kubectl create namespace ex-1-3-prod
kubectl create namespace ex-1-3-dev

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: service
  namespace: ex-1-3-prod
  labels:
    app: service
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: dev-client
  namespace: ex-1-3-dev
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-1-3-prod --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-1-3-dev --timeout=60s
```

**Task:** Create a NetworkPolicy that denies all ingress to the service pod in ex-1-3-prod EXCEPT from the ex-1-3-dev namespace using the `kubernetes.io/metadata.name` label.

**Verification:**

```bash
SERVICE_IP=$(kubectl get pod service -n ex-1-3-prod -o jsonpath='{.status.podIP}')

# From dev namespace (should work)
kubectl exec -n ex-1-3-dev dev-client -- wget -qO- --timeout=2 http://$SERVICE_IP && echo "dev: ALLOWED"
```

---

## Level 2: Combined Selectors and ipBlock

These exercises explore combining selectors and external traffic control.

### Exercise 2.1

**Objective:** Combine pod and namespace selectors (AND logic).

**Setup:**

```bash
kubectl create namespace ex-2-1-target
kubectl create namespace ex-2-1-source
kubectl label namespace ex-2-1-source env=trusted

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: ex-2-1-target
  labels:
    app: server
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: trusted-app
  namespace: ex-2-1-source
  labels:
    role: trusted
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: untrusted-app
  namespace: ex-2-1-source
  labels:
    role: untrusted
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-2-1-target --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-2-1-source --timeout=60s
```

**Task:** Create a NetworkPolicy that allows ingress to the server pod only from pods with `role=trusted` AND in namespaces labeled `env=trusted`.

**Verification:**

```bash
SERVER_IP=$(kubectl get pod server -n ex-2-1-target -o jsonpath='{.status.podIP}')

# trusted-app (both conditions match)
kubectl exec -n ex-2-1-source trusted-app -- wget -qO- --timeout=2 http://$SERVER_IP && echo "trusted: ALLOWED"

# untrusted-app (namespace matches but role does not)
timeout 3 kubectl exec -n ex-2-1-source untrusted-app -- wget -qO- --timeout=2 http://$SERVER_IP || echo "untrusted: BLOCKED"
```

---

### Exercise 2.2

**Objective:** Configure ipBlock for external IP ranges.

**Setup:**

```bash
kubectl create namespace ex-2-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: external-facing
  namespace: ex-2-2
  labels:
    app: external
spec:
  containers:
  - name: nginx
    image: nginx:1.25
EOF

kubectl wait --for=condition=Ready pods --all -n ex-2-2 --timeout=60s
```

**Task:** Create a NetworkPolicy that allows ingress to the external-facing pod from the CIDR 10.0.0.0/8.

**Verification:**

```bash
# Verify policy configuration
kubectl describe networkpolicy -n ex-2-2 | grep -A5 "ipBlock"
```

---

### Exercise 2.3

**Objective:** Use ipBlock.except to carve out IP ranges.

**Setup:**

```bash
kubectl create namespace ex-2-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api-server
  namespace: ex-2-3
  labels:
    app: api
spec:
  containers:
  - name: nginx
    image: nginx:1.25
EOF

kubectl wait --for=condition=Ready pods --all -n ex-2-3 --timeout=60s
```

**Task:** Create a NetworkPolicy that allows ingress from 192.168.0.0/16 EXCEPT 192.168.100.0/24.

**Verification:**

```bash
kubectl describe networkpolicy -n ex-2-3 | grep -A10 "ipBlock"
```

---

## Level 3: Debugging Selector Issues

These exercises present policies with selector problems to diagnose.

### Exercise 3.1

**Objective:** A cross-namespace policy is not working. Diagnose the issue.

**Setup:**

```bash
kubectl create namespace ex-3-1-server
kubectl create namespace ex-3-1-client

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: ex-3-1-server
  labels:
    app: server
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ex-3-1-client
  labels:
    app: client
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-clients
  namespace: ex-3-1-server
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          role: client
EOF

kubectl wait --for=condition=Ready pods --all -n ex-3-1-server --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-3-1-client --timeout=60s
```

**Task:** The client pod cannot reach the server even though the policy should allow it. Diagnose why.

**Verification:**

```bash
SERVER_IP=$(kubectl get pod server -n ex-3-1-server -o jsonpath='{.status.podIP}')

# This fails but should work
timeout 3 kubectl exec -n ex-3-1-client client -- wget -qO- --timeout=2 http://$SERVER_IP || echo "BLOCKED"

# Check namespace labels
kubectl get namespace ex-3-1-client --show-labels
```

---

### Exercise 3.2

**Objective:** Understand AND vs OR semantics in selectors.

**Setup:**

```bash
kubectl create namespace ex-3-2-ns1
kubectl create namespace ex-3-2-ns2
kubectl label namespace ex-3-2-ns1 team=alpha
kubectl label namespace ex-3-2-ns2 team=beta

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: target
  namespace: ex-3-2-ns1
  labels:
    app: target
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: client-alpha
  namespace: ex-3-2-ns1
  labels:
    role: tester
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: client-beta
  namespace: ex-3-2-ns2
  labels:
    role: tester
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: combined-policy
  namespace: ex-3-2-ns1
spec:
  podSelector:
    matchLabels:
      app: target
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          team: alpha
      podSelector:
        matchLabels:
          role: tester
EOF

kubectl wait --for=condition=Ready pods --all -n ex-3-2-ns1 --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-3-2-ns2 --timeout=60s
```

**Task:** The policy uses AND semantics. Modify it to use OR semantics so that both client-alpha and client-beta can reach the target.

**Verification:**

```bash
TARGET_IP=$(kubectl get pod target -n ex-3-2-ns1 -o jsonpath='{.status.podIP}')

# client-alpha (in ns1) -- should reach target
kubectl exec -n ex-3-2-ns1 client-alpha -- wget -qO- --timeout=2 http://$TARGET_IP && echo "client-alpha: ALLOWED"

# client-beta (in ns2) -- should also reach target after fix
kubectl exec -n ex-3-2-ns2 client-beta -- wget -qO- --timeout=2 http://$TARGET_IP && echo "client-beta: ALLOWED"
```

---

### Exercise 3.3

**Objective:** Debug an ipBlock configuration issue.

**Setup:**

```bash
kubectl create namespace ex-3-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: service
  namespace: ex-3-3
  labels:
    app: service
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: external-access
  namespace: ex-3-3
spec:
  podSelector:
    matchLabels:
      app: service
  policyTypes:
  - Ingress
  ingress:
  - from:
    - ipBlock:
        cidr: 10.0.0.0/8
        except:
        - 10.0.0.0/8
EOF

kubectl wait --for=condition=Ready pods --all -n ex-3-3 --timeout=60s
```

**Task:** The ipBlock should allow traffic from 10.0.0.0/8, but no traffic is allowed. Diagnose the issue.

**Verification:**

```bash
kubectl describe networkpolicy external-access -n ex-3-3 | grep -A5 "ipBlock"
```

---

## Level 4: Default Deny and Isolation

These exercises focus on implementing secure default policies.

### Exercise 4.1

**Objective:** Create a default deny all ingress and egress policy with DNS exception.

**Setup:**

```bash
kubectl create namespace ex-4-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: ex-4-1
  labels:
    app: webapp
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-4-1 --timeout=60s
```

**Task:** Create a default deny policy that blocks all ingress and egress for all pods in the namespace, but allows DNS egress to kube-system.

**Verification:**

```bash
# DNS should work
kubectl exec -n ex-4-1 app -- nslookup kubernetes.default 2>&1 | head -5

# Other egress should be blocked
timeout 3 kubectl exec -n ex-4-1 app -- wget -qO- --timeout=2 http://example.com || echo "External egress: BLOCKED"
```

---

### Exercise 4.2

**Objective:** Isolate a namespace while allowing internal communication.

**Setup:**

```bash
kubectl create namespace ex-4-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: ex-4-2
  labels:
    app: server
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ex-4-2
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-4-2 --timeout=60s
```

**Task:** Create a namespace isolation policy that:
1. Allows all ingress/egress between pods in the namespace
2. Blocks all ingress from outside the namespace
3. Allows DNS egress

**Verification:**

```bash
SERVER_IP=$(kubectl get pod server -n ex-4-2 -o jsonpath='{.status.podIP}')

# Internal should work
kubectl exec -n ex-4-2 client -- wget -qO- --timeout=2 http://$SERVER_IP && echo "Internal: ALLOWED"

# DNS should work
kubectl exec -n ex-4-2 client -- nslookup kubernetes.default 2>&1 | head -3
```

---

### Exercise 4.3

**Objective:** Implement least-privilege access with multiple policies.

**Setup:**

```bash
kubectl create namespace ex-4-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: ex-4-3
  labels:
    tier: frontend
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: ex-4-3
  labels:
    tier: backend
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: database
  namespace: ex-4-3
  labels:
    tier: database
spec:
  containers:
  - name: nginx
    image: nginx:1.25
EOF

kubectl wait --for=condition=Ready pods --all -n ex-4-3 --timeout=60s
```

**Task:** Create policies implementing:
1. Default deny all
2. Frontend can reach backend
3. Backend can reach database
4. All pods can access DNS

**Verification:**

```bash
BACKEND_IP=$(kubectl get pod backend -n ex-4-3 -o jsonpath='{.status.podIP}')
DB_IP=$(kubectl get pod database -n ex-4-3 -o jsonpath='{.status.podIP}')

# frontend -> backend
kubectl exec -n ex-4-3 frontend -- wget -qO- --timeout=2 http://$BACKEND_IP && echo "frontend->backend: OK"

# backend -> database
kubectl exec -n ex-4-3 backend -- curl -sf --connect-timeout 2 http://$DB_IP && echo "backend->database: OK"

# frontend -> database (should be blocked)
timeout 3 kubectl exec -n ex-4-3 frontend -- wget -qO- --timeout=2 http://$DB_IP || echo "frontend->database: BLOCKED"
```

---

## Level 5: Complex Isolation

These exercises present complex multi-namespace scenarios.

### Exercise 5.1

**Objective:** Multi-namespace application isolation.

**Setup:**

```bash
kubectl create namespace ex-5-1-web
kubectl create namespace ex-5-1-api
kubectl create namespace ex-5-1-db
kubectl label namespace ex-5-1-web tier=web
kubectl label namespace ex-5-1-api tier=api
kubectl label namespace ex-5-1-db tier=db

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: ex-5-1-web
  labels:
    app: web
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ex-5-1-api
  labels:
    app: api
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: db
  namespace: ex-5-1-db
  labels:
    app: db
spec:
  containers:
  - name: nginx
    image: nginx:1.25
EOF

kubectl wait --for=condition=Ready pods --all -n ex-5-1-web --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-5-1-api --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-5-1-db --timeout=60s
```

**Task:** Implement policies so that:
1. Web namespace can reach API namespace
2. API namespace can reach DB namespace
3. Web cannot directly reach DB
4. Each namespace has default deny ingress

**Verification:**

```bash
API_IP=$(kubectl get pod api -n ex-5-1-api -o jsonpath='{.status.podIP}')
DB_IP=$(kubectl get pod db -n ex-5-1-db -o jsonpath='{.status.podIP}')

# web -> api
kubectl exec -n ex-5-1-web web -- wget -qO- --timeout=2 http://$API_IP && echo "web->api: OK"

# api -> db
kubectl exec -n ex-5-1-api api -- curl -sf --connect-timeout 2 http://$DB_IP && echo "api->db: OK"

# web -> db (blocked)
timeout 3 kubectl exec -n ex-5-1-web web -- wget -qO- --timeout=2 http://$DB_IP || echo "web->db: BLOCKED"
```

---

### Exercise 5.2

**Objective:** Debug policy interaction with additive behavior.

**Setup:**

```bash
kubectl create namespace ex-5-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: secure-server
  namespace: ex-5-2
  labels:
    app: server
    security: high
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ex-5-2
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: policy-a
  namespace: ex-5-2
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: policy-b
  namespace: ex-5-2
spec:
  podSelector:
    matchLabels:
      security: high
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

kubectl wait --for=condition=Ready pods --all -n ex-5-2 --timeout=60s
```

**Task:** The secure-server should not be reachable from the client, but one of the two policies is permitting unwanted access. Find the policy responsible and remove it so the server is properly protected.

**Verification:**

```bash
SERVER_IP=$(kubectl get pod secure-server -n ex-5-2 -o jsonpath='{.status.podIP}')

# Before fix - client can reach server
kubectl exec -n ex-5-2 client -- wget -qO- --timeout=2 http://$SERVER_IP && echo "Before fix: ALLOWED"

# After fix - should be blocked
timeout 3 kubectl exec -n ex-5-2 client -- wget -qO- --timeout=2 http://$SERVER_IP || echo "After fix: BLOCKED"
```

---

### Exercise 5.3

**Objective:** Design a zero-trust network policy strategy.

**Setup:**

```bash
kubectl create namespace ex-5-3
```

**Task:** Design and document (then implement) a zero-trust policy strategy for a namespace with:
1. Default deny all ingress and egress
2. DNS access for all pods
3. Pods labeled `tier=web` can receive external traffic
4. Pods labeled `tier=api` can only receive from `tier=web`
5. Pods labeled `tier=db` can only receive from `tier=api`

Create the policies and test with sample pods.

**Verification:**

```bash
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: ex-5-3
  labels:
    tier: web
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ex-5-3
  labels:
    tier: api
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: db
  namespace: ex-5-3
  labels:
    tier: db
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: tester
  namespace: ex-5-3
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-5-3 --timeout=60s

WEB_IP=$(kubectl get pod web -n ex-5-3 -o jsonpath='{.status.podIP}')
API_IP=$(kubectl get pod api -n ex-5-3 -o jsonpath='{.status.podIP}')
DB_IP=$(kubectl get pod db -n ex-5-3 -o jsonpath='{.status.podIP}')

# tester -> web (should work)
kubectl exec -n ex-5-3 tester -- wget -qO- --timeout=2 http://$WEB_IP && echo "tester->web: OK"

# web -> api (should work)
kubectl exec -n ex-5-3 web -- curl -sf --connect-timeout 2 http://$API_IP && echo "web->api: OK"

# api -> db (should work)
kubectl exec -n ex-5-3 api -- curl -sf --connect-timeout 2 http://$DB_IP && echo "api->db: OK"

# tester -> api (blocked)
timeout 3 kubectl exec -n ex-5-3 tester -- wget -qO- --timeout=2 http://$API_IP || echo "tester->api: BLOCKED"
```

---

## Cleanup

```bash
kubectl delete namespace ex-1-1-app ex-1-1-monitoring
kubectl delete namespace ex-1-2-frontend ex-1-2-backend
kubectl delete namespace ex-1-3-prod ex-1-3-dev
kubectl delete namespace ex-2-1-target ex-2-1-source
kubectl delete namespace ex-2-2 ex-2-3
kubectl delete namespace ex-3-1-server ex-3-1-client
kubectl delete namespace ex-3-2-ns1 ex-3-2-ns2
kubectl delete namespace ex-3-3
kubectl delete namespace ex-4-1 ex-4-2 ex-4-3
kubectl delete namespace ex-5-1-web ex-5-1-api ex-5-1-db
kubectl delete namespace ex-5-2 ex-5-3
```

---

## Key Takeaways

1. **Namespaces need labels** to be selected by namespaceSelector. Use `kubernetes.io/metadata.name` for built-in name selection.

2. **AND vs OR:** Same from/to entry = AND. Separate entries (dash) = OR.

3. **ipBlock cannot combine** with pod/namespace selectors in the same entry.

4. **Default deny is the foundation** of zero-trust. Start with deny, then add specific allows.

5. **Policies are additive.** You cannot deny what another policy allows.

6. **Always include DNS egress** in default deny policies to avoid breaking name resolution.
