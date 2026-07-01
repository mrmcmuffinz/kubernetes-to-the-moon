# Network Policies Homework: Network Policy Debugging

Work through these 15 exercises to build practical Network Policy debugging skills. Complete the tutorial (network-policies-tutorial.md) before starting these exercises.

---

## Level 1: Basic Debugging

These exercises focus on fundamental debugging techniques.

### Exercise 1.1

**Objective:** Test connectivity with and without a policy.

**Setup:**

```bash
kubectl create namespace ex-1-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: ex-1-1
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
  namespace: ex-1-1
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-1-1 --timeout=60s
```

**Task:** Test connectivity before any policy. Then apply a deny policy and verify traffic is blocked.

**Verification:**

```bash
SERVER_IP=$(kubectl get pod server -n ex-1-1 -o jsonpath='{.status.podIP}')

# Before policy
kubectl exec -n ex-1-1 client -- wget -qO- --timeout=2 http://$SERVER_IP && echo "Before policy: ALLOWED"

# Apply deny policy
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: ex-1-1
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress
EOF

# After policy
timeout 3 kubectl exec -n ex-1-1 client -- wget -qO- --timeout=2 http://$SERVER_IP || echo "After policy: BLOCKED"
```

---

### Exercise 1.2

**Objective:** Identify which policy is blocking traffic.

**Setup:**

```bash
kubectl create namespace ex-1-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ex-1-2
  labels:
    app: api
    tier: backend
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: ex-1-2
  labels:
    app: web
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: ex-1-2
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend
EOF

kubectl wait --for=condition=Ready pods --all -n ex-1-2 --timeout=60s
```

**Task:** The web pod cannot reach the api pod. The configuration has one or more problems. Find and fix whatever is needed so web can reach api.

**Verification:**

```bash
API_IP=$(kubectl get pod api -n ex-1-2 -o jsonpath='{.status.podIP}')

# Before fix - blocked
timeout 3 kubectl exec -n ex-1-2 web -- wget -qO- --timeout=2 http://$API_IP || echo "BLOCKED"

# After fix - should succeed
kubectl exec -n ex-1-2 web -- wget -qO- --timeout=2 http://$API_IP && echo "ALLOWED"
```

---

### Exercise 1.3

**Objective:** Verify a policy selector matches the intended pods.

**Setup:**

```bash
kubectl create namespace ex-1-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: database
  namespace: ex-1-3
  labels:
    app: postgresql
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: app
  namespace: ex-1-3
  labels:
    app: webapp
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: protect-database
  namespace: ex-1-3
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
EOF

kubectl wait --for=condition=Ready pods --all -n ex-1-3 --timeout=60s
```

**Task:** The policy should protect the database pod but is not working. The configuration has one or more problems. Find and fix whatever is needed so the database pod is properly protected.

**Verification:**

```bash
DB_IP=$(kubectl get pod database -n ex-1-3 -o jsonpath='{.status.podIP}')

# Before fix - database is accessible (policy not effective)
kubectl exec -n ex-1-3 app -- wget -qO- --timeout=2 http://$DB_IP && echo "Before fix: accessible"

# After fix - should be blocked
timeout 3 kubectl exec -n ex-1-3 app -- wget -qO- --timeout=2 http://$DB_IP || echo "After fix: BLOCKED"
```

---

## Level 2: Policy Verification

These exercises focus on verifying policies work correctly with DNS and services.

### Exercise 2.1

**Objective:** Test that a policy allows egress to DNS.

**Setup:**

```bash
kubectl create namespace ex-2-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: restricted
  namespace: ex-2-1
  labels:
    app: restricted
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: ex-2-1
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
EOF

kubectl wait --for=condition=Ready pods --all -n ex-2-1 --timeout=60s
```

**Task:** Verify that DNS queries work but other egress is blocked.

**Verification:**

```bash
# DNS should work
kubectl exec -n ex-2-1 restricted -- nslookup kubernetes.default && echo "DNS: OK"

# Other egress should be blocked
timeout 3 kubectl exec -n ex-2-1 restricted -- wget -qO- --timeout=2 http://example.com || echo "External: BLOCKED"
```

---

### Exercise 2.2

**Objective:** Verify service access through a policy.

**Setup:**

```bash
kubectl create namespace ex-2-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: ex-2-2
  labels:
    app: backend
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: ex-2-2
spec:
  selector:
    app: backend
  ports:
  - port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: ex-2-2
  labels:
    app: frontend
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: ex-2-2
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 80
EOF

kubectl wait --for=condition=Ready pods --all -n ex-2-2 --timeout=60s
```

**Task:** Verify the frontend can access the backend through the service.

**Verification:**

```bash
# Test via service name (needs DNS)
kubectl exec -n ex-2-2 frontend -- wget -qO- --timeout=2 http://backend-svc && echo "Service access: OK"
```

---

### Exercise 2.3

**Objective:** Verify cross-namespace policy allows expected traffic.

**Setup:**

```bash
kubectl create namespace ex-2-3-frontend
kubectl create namespace ex-2-3-backend
kubectl label namespace ex-2-3-frontend tier=frontend

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ex-2-3-backend
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
  namespace: ex-2-3-frontend
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: ex-2-3-backend
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tier: frontend
EOF

kubectl wait --for=condition=Ready pods --all -n ex-2-3-frontend --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-2-3-backend --timeout=60s
```

**Task:** Verify cross-namespace access works.

**Verification:**

```bash
API_IP=$(kubectl get pod api -n ex-2-3-backend -o jsonpath='{.status.podIP}')

kubectl exec -n ex-2-3-frontend web -- wget -qO- --timeout=2 http://$API_IP && echo "Cross-namespace: OK"
```

---

## Level 3: Debugging Blocked Traffic

These exercises present broken configurations to diagnose.

### Exercise 3.1

**Objective:** A policy selector does not match the source pod.

**Setup:**

```bash
kubectl create namespace ex-3-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: ex-3-1
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
  namespace: ex-3-1
  labels:
    role: client
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: server-policy
  namespace: ex-3-1
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend
EOF

kubectl wait --for=condition=Ready pods --all -n ex-3-1 --timeout=60s
```

**Task:** Traffic from client to server is blocked. Diagnose why.

**Verification:**

```bash
SERVER_IP=$(kubectl get pod server -n ex-3-1 -o jsonpath='{.status.podIP}')

timeout 3 kubectl exec -n ex-3-1 client -- wget -qO- --timeout=2 http://$SERVER_IP || echo "BLOCKED"

# Diagnose
kubectl get pod client -n ex-3-1 --show-labels
kubectl describe networkpolicy server-policy -n ex-3-1 | grep -A3 "From:"
```

---

### Exercise 3.2

**Objective:** DNS is blocked due to missing egress rule.

**Setup:**

```bash
kubectl create namespace ex-3-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: ex-3-2
  labels:
    app: server
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Service
metadata:
  name: server-svc
  namespace: ex-3-2
spec:
  selector:
    app: server
  ports:
  - port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ex-3-2
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: client-egress
  namespace: ex-3-2
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: server
EOF

kubectl wait --for=condition=Ready pods --all -n ex-3-2 --timeout=60s
```

**Task:** The client can reach the server by IP but not by service name. Diagnose why.

**Verification:**

```bash
SERVER_IP=$(kubectl get pod server -n ex-3-2 -o jsonpath='{.status.podIP}')

# By IP works
kubectl exec -n ex-3-2 client -- wget -qO- --timeout=2 http://$SERVER_IP && echo "By IP: OK"

# By service name fails (DNS blocked)
timeout 3 kubectl exec -n ex-3-2 client -- wget -qO- --timeout=2 http://server-svc || echo "By name: BLOCKED"

# Check DNS directly
timeout 3 kubectl exec -n ex-3-2 client -- nslookup server-svc 2>&1 || echo "DNS query failed"
```

---

### Exercise 3.3

**Objective:** Cross-namespace access fails due to missing namespace label.

**Setup:**

```bash
kubectl create namespace ex-3-3-app
kubectl create namespace ex-3-3-monitoring

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ex-3-3-app
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
  name: prometheus
  namespace: ex-3-3-monitoring
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: ex-3-3-app
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          purpose: monitoring
EOF

kubectl wait --for=condition=Ready pods --all -n ex-3-3-app --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-3-3-monitoring --timeout=60s
```

**Task:** Prometheus cannot reach the API even though it should be allowed. Diagnose why.

**Verification:**

```bash
API_IP=$(kubectl get pod api -n ex-3-3-app -o jsonpath='{.status.podIP}')

timeout 3 kubectl exec -n ex-3-3-monitoring prometheus -- wget -qO- --timeout=2 http://$API_IP || echo "BLOCKED"

# Check namespace labels
kubectl get namespace ex-3-3-monitoring --show-labels
```

---

## Level 4: Complex Policy Issues

These exercises involve multi-policy interactions.

### Exercise 4.1

**Objective:** Debug multi-policy interaction.

**Setup:**

```bash
kubectl create namespace ex-4-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: secure-app
  namespace: ex-4-1
  labels:
    app: secure
    env: prod
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: test-client
  namespace: ex-4-1
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
  name: deny-by-app
  namespace: ex-4-1
spec:
  podSelector:
    matchLabels:
      app: secure
  policyTypes:
  - Ingress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-testers
  namespace: ex-4-1
spec:
  podSelector:
    matchLabels:
      env: prod
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: tester
EOF

kubectl wait --for=condition=Ready pods --all -n ex-4-1 --timeout=60s
```

**Task:** Determine if test-client can reach secure-app. Explain why based on additive policy behavior.

**Verification:**

```bash
SECURE_IP=$(kubectl get pod secure-app -n ex-4-1 -o jsonpath='{.status.podIP}')

kubectl exec -n ex-4-1 test-client -- wget -qO- --timeout=2 http://$SECURE_IP 2>&1 | head -3
```

---

### Exercise 4.2

**Objective:** Find a policy that allows unintended traffic.

**Setup:**

```bash
kubectl create namespace ex-4-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: database
  namespace: ex-4-2
  labels:
    app: database
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: attacker
  namespace: ex-4-2
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-restrict
  namespace: ex-4-2
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector: {}
EOF

kubectl wait --for=condition=Ready pods --all -n ex-4-2 --timeout=60s
```

**Task:** The database should only be accessible from specific apps, but any pod can reach it. Find the policy issue.

**Verification:**

```bash
DB_IP=$(kubectl get pod database -n ex-4-2 -o jsonpath='{.status.podIP}')

# Attacker can reach database (should not be able to)
kubectl exec -n ex-4-2 attacker -- wget -qO- --timeout=2 http://$DB_IP && echo "Database accessible from attacker!"

# Check the policy
kubectl describe networkpolicy db-restrict -n ex-4-2
```

---

### Exercise 4.3

**Objective:** Trace a cross-namespace policy chain.

**Setup:**

```bash
kubectl create namespace ex-4-3-web
kubectl create namespace ex-4-3-api
kubectl create namespace ex-4-3-db
kubectl label namespace ex-4-3-web tier=web
kubectl label namespace ex-4-3-api tier=api

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: ex-4-3-web
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
  namespace: ex-4-3-api
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
  namespace: ex-4-3-db
  labels:
    app: db
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: ex-4-3-api
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tier: web
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-policy
  namespace: ex-4-3-db
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          tier: api
EOF

kubectl wait --for=condition=Ready pods --all -n ex-4-3-web --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-4-3-api --timeout=60s
kubectl wait --for=condition=Ready pods --all -n ex-4-3-db --timeout=60s
```

**Task:** Verify the policy chain: web->api should work, api->db should work.

**Verification:**

```bash
API_IP=$(kubectl get pod api -n ex-4-3-api -o jsonpath='{.status.podIP}')
DB_IP=$(kubectl get pod db -n ex-4-3-db -o jsonpath='{.status.podIP}')

# web -> api
kubectl exec -n ex-4-3-web web -- wget -qO- --timeout=2 http://$API_IP && echo "web->api: OK"

# api -> db
kubectl exec -n ex-4-3-api api -- curl -sf --connect-timeout 2 http://$DB_IP && echo "api->db: OK"
```

---

## Level 5: Integration Debugging

These exercises cover complex integration scenarios.

### Exercise 5.1

**Objective:** Debug an application with multiple policy issues.

**Setup:**

```bash
kubectl create namespace ex-5-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: ex-5-1
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
  namespace: ex-5-1
  labels:
    app: api-server
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Service
metadata:
  name: api-svc
  namespace: ex-5-1
spec:
  selector:
    app: api-server
  ports:
  - port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: ex-5-1
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-to-api
  namespace: ex-5-1
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: web
    ports:
    - port: 80
EOF

kubectl wait --for=condition=Ready pods --all -n ex-5-1 --timeout=60s
```

**Task:** The web pod should reach the api service, but it fails. There are multiple issues. Find and explain them.

**Verification:**

```bash
# By service name
timeout 3 kubectl exec -n ex-5-1 web -- wget -qO- --timeout=2 http://api-svc || echo "FAILED"

# By IP
API_IP=$(kubectl get pod api -n ex-5-1 -o jsonpath='{.status.podIP}')
timeout 3 kubectl exec -n ex-5-1 web -- wget -qO- --timeout=2 http://$API_IP || echo "FAILED"
```

---

### Exercise 5.2

**Objective:** Service discovery failure due to policy.

**Setup:**

```bash
kubectl create namespace ex-5-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: ex-5-2
  labels:
    app: backend
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Service
metadata:
  name: backend-svc
  namespace: ex-5-2
spec:
  selector:
    app: backend
  ports:
  - port: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: ex-5-2
  labels:
    app: frontend
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: ex-5-2
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress
  namespace: ex-5-2
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 80
EOF

kubectl wait --for=condition=Ready pods --all -n ex-5-2 --timeout=60s
```

**Task:** Frontend can reach backend by IP but not by service name. Fix the issue.

**Verification:**

```bash
BACKEND_IP=$(kubectl get pod backend -n ex-5-2 -o jsonpath='{.status.podIP}')

# By IP works
kubectl exec -n ex-5-2 frontend -- wget -qO- --timeout=2 http://$BACKEND_IP && echo "By IP: OK"

# By service name fails
timeout 3 kubectl exec -n ex-5-2 frontend -- wget -qO- --timeout=2 http://backend-svc || echo "By name: FAILED"
```

---

### Exercise 5.3

**Objective:** Create a policy troubleshooting runbook.

**Setup:**

```bash
kubectl create namespace ex-5-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: ex-5-3
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
  namespace: ex-5-3
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-5-3 --timeout=60s
```

**Task:** Document a complete troubleshooting runbook by running through all diagnostic steps. Execute each step and document the output.

**Verification:**

```bash
echo "=== Step 1: List policies ==="
kubectl get networkpolicy -n ex-5-3

echo ""
echo "=== Step 2: Get pod labels ==="
kubectl get pods -n ex-5-3 --show-labels

echo ""
echo "=== Step 3: Test connectivity ==="
SERVER_IP=$(kubectl get pod server -n ex-5-3 -o jsonpath='{.status.podIP}')
kubectl exec -n ex-5-3 client -- wget -qO- --timeout=2 http://$SERVER_IP && echo "Connectivity: OK"

echo ""
echo "=== Step 4: Test DNS ==="
kubectl exec -n ex-5-3 client -- nslookup kubernetes.default && echo "DNS: OK"

echo ""
echo "=== Step 5: Check namespace labels ==="
kubectl get namespace ex-5-3 --show-labels
```

---

## Cleanup

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3
kubectl delete namespace ex-2-1 ex-2-2
kubectl delete namespace ex-2-3-frontend ex-2-3-backend
kubectl delete namespace ex-3-1 ex-3-2
kubectl delete namespace ex-3-3-app ex-3-3-monitoring
kubectl delete namespace ex-4-1 ex-4-2
kubectl delete namespace ex-4-3-web ex-4-3-api ex-4-3-db
kubectl delete namespace ex-5-1 ex-5-2 ex-5-3
```

---

## Key Takeaways

1. **Always test connectivity** before and after applying policies.

2. **Check selector matches** for both target pods and source pods.

3. **DNS requires egress** to kube-system on UDP 53.

4. **Policies are additive.** Multiple matching policies combine rules.

5. **Namespace labels are required** for namespaceSelector to work.

6. **Empty podSelector {} matches all pods** in namespace.

7. **Debug systematically:** list policies, check selectors, verify labels, test connectivity.
