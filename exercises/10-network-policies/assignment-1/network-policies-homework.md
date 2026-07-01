# Network Policies Homework: NetworkPolicy Fundamentals

Work through these 15 exercises to build practical skills with Kubernetes Network Policies. Complete the tutorial (network-policies-tutorial.md) before starting these exercises. Each level increases in complexity, building on concepts from previous levels.

**Important:** These exercises require a cluster with a CNI that enforces NetworkPolicy (Calico v3.31.5 or later). See the README for setup instructions.

---

## Level 1: Basic Policy Creation

These exercises focus on creating simple Network Policies.

### Exercise 1.1

**Objective:** Create a Network Policy that allows ingress from a specific pod.

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
  name: allowed-client
  namespace: ex-1-1
  labels:
    role: allowed
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: blocked-client
  namespace: ex-1-1
  labels:
    role: blocked
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-1-1 --timeout=60s
```

**Task:** Create a NetworkPolicy named `allow-from-allowed` that allows ingress to the server pod only from pods with `role=allowed`.

**Verification:**

```bash
SERVER_IP=$(kubectl get pod server -n ex-1-1 -o jsonpath='{.status.podIP}')

# allowed-client should reach server
kubectl exec -n ex-1-1 allowed-client -- wget -qO- --timeout=2 http://$SERVER_IP && echo "allowed-client: ALLOWED"

# blocked-client should be blocked
timeout 3 kubectl exec -n ex-1-1 blocked-client -- wget -qO- --timeout=2 http://$SERVER_IP || echo "blocked-client: BLOCKED"
```

---

### Exercise 1.2

**Objective:** Create a Network Policy that controls egress from a pod.

**Setup:**

```bash
kubectl create namespace ex-1-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: target-a
  namespace: ex-1-2
  labels:
    app: target-a
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: target-b
  namespace: ex-1-2
  labels:
    app: target-b
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: restricted-pod
  namespace: ex-1-2
  labels:
    app: restricted
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-1-2 --timeout=60s
```

**Task:** Create a NetworkPolicy named `restrict-egress` that allows the restricted-pod to send egress traffic only to pods with `app=target-a`.

**Note:** Use pod IPs for verification, not Service DNS names. An egress policy blocks all outbound traffic that isn't explicitly allowed -- including UDP/TCP port 53 to CoreDNS. If you expose a Service and try to reach it by hostname, the DNS lookup itself will be silently dropped and the connection will hang. DNS egress is covered in assignment 2.

**Verification:**

```bash
TARGET_A_IP=$(kubectl get pod target-a -n ex-1-2 -o jsonpath='{.status.podIP}')
TARGET_B_IP=$(kubectl get pod target-b -n ex-1-2 -o jsonpath='{.status.podIP}')

# restricted-pod should reach target-a
kubectl exec -n ex-1-2 restricted-pod -- wget -qO- --timeout=2 http://$TARGET_A_IP && echo "to target-a: ALLOWED"

# restricted-pod should NOT reach target-b
timeout 3 kubectl exec -n ex-1-2 restricted-pod -- wget -qO- --timeout=2 http://$TARGET_B_IP || echo "to target-b: BLOCKED"
```

---

### Exercise 1.3

**Objective:** Verify policy effects by testing connectivity before and after applying a policy.

**Setup:**

```bash
kubectl create namespace ex-1-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: webserver
  namespace: ex-1-3
  labels:
    app: web
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: tester
  namespace: ex-1-3
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-1-3 --timeout=60s
```

**Task:** 
1. First verify that tester can reach webserver (before any policy)
2. Apply a NetworkPolicy that denies all ingress to webserver
3. Verify that tester can no longer reach webserver

**Verification:**

```bash
WEB_IP=$(kubectl get pod webserver -n ex-1-3 -o jsonpath='{.status.podIP}')

# Before policy (should work)
echo "Before policy:"
kubectl exec -n ex-1-3 tester -- wget -qO- --timeout=2 http://$WEB_IP && echo "ALLOWED"

# After applying deny policy (should be blocked)
echo "After policy:"
timeout 3 kubectl exec -n ex-1-3 tester -- wget -qO- --timeout=2 http://$WEB_IP || echo "BLOCKED"
```

---

## Level 2: Pod Selection and Rules

These exercises explore pod selectors and rule configurations.

### Exercise 2.1

**Objective:** Create a policy that selects pods by multiple labels.

**Setup:**

```bash
kubectl create namespace ex-2-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api-prod
  namespace: ex-2-1
  labels:
    app: api
    env: prod
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: api-dev
  namespace: ex-2-1
  labels:
    app: api
    env: dev
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ex-2-1
  labels:
    role: client
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-2-1 --timeout=60s
```

**Task:** Create a NetworkPolicy named `protect-prod` that denies all ingress to pods with BOTH `app=api` AND `env=prod`. The api-dev pod should remain accessible.

**Verification:**

```bash
PROD_IP=$(kubectl get pod api-prod -n ex-2-1 -o jsonpath='{.status.podIP}')
DEV_IP=$(kubectl get pod api-dev -n ex-2-1 -o jsonpath='{.status.podIP}')

# api-prod should be blocked
timeout 3 kubectl exec -n ex-2-1 client -- wget -qO- --timeout=2 http://$PROD_IP || echo "api-prod: BLOCKED"

# api-dev should still be accessible
kubectl exec -n ex-2-1 client -- wget -qO- --timeout=2 http://$DEV_IP && echo "api-dev: ALLOWED"
```

---

### Exercise 2.2

**Objective:** Create a policy with multiple from entries (OR logic).

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
kind: Pod
metadata:
  name: web-client
  namespace: ex-2-2
  labels:
    tier: web
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: admin-client
  namespace: ex-2-2
  labels:
    tier: admin
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: other-client
  namespace: ex-2-2
  labels:
    tier: other
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-2-2 --timeout=60s
```

**Task:** Create a NetworkPolicy named `backend-access` that allows ingress to the backend pod from pods with `tier=web` OR `tier=admin`. Pods with other tier values should be blocked.

**Verification:**

```bash
BACKEND_IP=$(kubectl get pod backend -n ex-2-2 -o jsonpath='{.status.podIP}')

# web-client should be allowed
kubectl exec -n ex-2-2 web-client -- wget -qO- --timeout=2 http://$BACKEND_IP && echo "web-client: ALLOWED"

# admin-client should be allowed
kubectl exec -n ex-2-2 admin-client -- wget -qO- --timeout=2 http://$BACKEND_IP && echo "admin-client: ALLOWED"

# other-client should be blocked
timeout 3 kubectl exec -n ex-2-2 other-client -- wget -qO- --timeout=2 http://$BACKEND_IP || echo "other-client: BLOCKED"
```

---

### Exercise 2.3

**Objective:** Create a policy with port filtering.

**Setup:**

```bash
kubectl create namespace ex-2-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: multi-port-server
  namespace: ex-2-3
  labels:
    app: server
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    ports:
    - containerPort: 80
  - name: redis
    image: redis:7.2
    ports:
    - containerPort: 6379
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ex-2-3
  labels:
    role: client
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-2-3 --timeout=60s
```

**Task:** Create a NetworkPolicy named `http-only` that allows ingress to the server pod only on TCP port 80. Port 6379 should be blocked.

**Verification:**

```bash
SERVER_IP=$(kubectl get pod multi-port-server -n ex-2-3 -o jsonpath='{.status.podIP}')

# Port 80 should be allowed
kubectl exec -n ex-2-3 client -- wget -qO- --timeout=2 http://$SERVER_IP:80 && echo "port 80: ALLOWED"

# Port 6379 should be blocked
timeout 3 kubectl exec -n ex-2-3 client -- nc -zv $SERVER_IP 6379 2>&1 || echo "port 6379: BLOCKED"
```

---

## Level 3: Debugging Policy Effects

These exercises present policies with issues to diagnose.

### Exercise 3.1

**Objective:** A policy is too restrictive. Find and fix the issue.

**Setup:**

```bash
kubectl create namespace ex-3-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api-server
  namespace: ex-3-1
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
  name: frontend
  namespace: ex-3-1
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
  name: api-policy
  namespace: ex-3-1
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
EOF

kubectl wait --for=condition=Ready pods --all -n ex-3-1 --timeout=60s
```

**Task:** The frontend pod should be able to reach the api-server but cannot. The configuration has one or more problems. Find and fix whatever is needed so the connection succeeds.

**Verification:**

```bash
API_IP=$(kubectl get pod api-server -n ex-3-1 -o jsonpath='{.status.podIP}')

# Before fix - currently blocked
timeout 3 kubectl exec -n ex-3-1 frontend -- wget -qO- --timeout=2 http://$API_IP || echo "frontend -> api: BLOCKED"

# After fix - should succeed
kubectl exec -n ex-3-1 frontend -- wget -qO- --timeout=2 http://$API_IP && echo "frontend -> api: ALLOWED"
```

---

### Exercise 3.2

**Objective:** A policy selector is not matching the intended pods. Diagnose the issue.

**Setup:**

```bash
kubectl create namespace ex-3-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: database
  namespace: ex-3-2
  labels:
    app: mysql
    tier: database
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: ex-3-2
  labels:
    app: api
    tier: backend
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-policy
  namespace: ex-3-2
spec:
  podSelector:
    matchLabels:
      app: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
EOF

kubectl wait --for=condition=Ready pods --all -n ex-3-2 --timeout=60s
```

**Task:** The policy should protect the database pod but is not working as intended. The configuration has one or more problems. Find and fix whatever is needed so the database pod is properly protected.

**Verification:**

```bash
DB_IP=$(kubectl get pod database -n ex-3-2 -o jsonpath='{.status.podIP}')

# Before fix - backend reaches database (policy not effective)
kubectl exec -n ex-3-2 backend -- wget -qO- --timeout=2 http://$DB_IP && echo "backend -> database: ALLOWED"

# After fix - backend should be blocked
timeout 3 kubectl exec -n ex-3-2 backend -- wget -qO- --timeout=2 http://$DB_IP || echo "backend -> database: BLOCKED"
```

---

### Exercise 3.3

**Objective:** A policy allows connections but on the wrong port. Diagnose and fix.

**Setup:**

```bash
kubectl create namespace ex-3-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: webserver
  namespace: ex-3-3
  labels:
    app: web
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ex-3-3
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
  name: web-policy
  namespace: ex-3-3
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: client
    ports:
    - protocol: TCP
      port: 8080
EOF

kubectl wait --for=condition=Ready pods --all -n ex-3-3 --timeout=60s
```

**Task:** The client should be able to access the webserver on port 80 but the connection fails. The configuration has one or more problems. Find and fix whatever is needed so port 80 is accessible.

**Verification:**

```bash
WEB_IP=$(kubectl get pod webserver -n ex-3-3 -o jsonpath='{.status.podIP}')

# Before fix - currently blocked
timeout 3 kubectl exec -n ex-3-3 client -- wget -qO- --timeout=2 http://$WEB_IP:80 || echo "port 80: BLOCKED"

# After fix - should succeed
kubectl exec -n ex-3-3 client -- wget -qO- --timeout=2 http://$WEB_IP:80 && echo "port 80: ALLOWED"
```

---

## Level 4: Combined Rules

These exercises involve more complex policy configurations.

### Exercise 4.1

**Objective:** Create a policy with both ingress and egress rules.

**Setup:**

```bash
kubectl create namespace ex-4-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ex-4-1
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
  name: database
  namespace: ex-4-1
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
  name: frontend
  namespace: ex-4-1
  labels:
    app: frontend
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-4-1 --timeout=60s
```

**Task:** Create a NetworkPolicy named `api-rules` that:
1. Allows ingress to the api pod only from the frontend pod
2. Allows egress from the api pod only to the database pod

**Verification:**

```bash
API_IP=$(kubectl get pod api -n ex-4-1 -o jsonpath='{.status.podIP}')
DB_IP=$(kubectl get pod database -n ex-4-1 -o jsonpath='{.status.podIP}')

# frontend -> api should work
kubectl exec -n ex-4-1 frontend -- wget -qO- --timeout=2 http://$API_IP && echo "frontend -> api: ALLOWED"

# api -> database should work
kubectl exec -n ex-4-1 api -- curl -sf --connect-timeout 2 http://$DB_IP && echo "api -> database: ALLOWED"
```

---

### Exercise 4.2

**Objective:** Create a policy allowing multiple ports with different protocols.

**Setup:**

```bash
kubectl create namespace ex-4-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: dns-server
  namespace: ex-4-2
  labels:
    app: dns
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ex-4-2
  labels:
    role: client
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-4-2 --timeout=60s
```

**Task:** Create a NetworkPolicy named `dns-access` that allows ingress to the dns-server pod on:
- TCP port 53
- UDP port 53

**Verification:**

```bash
# Verify the policy allows both protocols on port 53
kubectl describe networkpolicy dns-access -n ex-4-2 | grep -A10 "Allowing ingress"
```

---

### Exercise 4.3

**Objective:** Use named ports in a Network Policy.

**Setup:**

```bash
kubectl create namespace ex-4-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: app-server
  namespace: ex-4-3
  labels:
    app: server
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    ports:
    - containerPort: 80
      name: http
    - containerPort: 443
      name: https
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ex-4-3
  labels:
    role: client
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-4-3 --timeout=60s
```

**Task:** Create a NetworkPolicy named `http-access` that allows ingress to the app-server on the named port `http` only. The `https` port should be blocked.

**Verification:**

```bash
SERVER_IP=$(kubectl get pod app-server -n ex-4-3 -o jsonpath='{.status.podIP}')

# http (port 80) should be allowed
kubectl exec -n ex-4-3 client -- wget -qO- --timeout=2 http://$SERVER_IP:80 && echo "http: ALLOWED"

# https (port 443) should be blocked
timeout 3 kubectl exec -n ex-4-3 client -- nc -zv $SERVER_IP 443 2>&1 || echo "https: BLOCKED"
```

---

## Level 5: Application Scenarios

These exercises present realistic application scenarios.

### Exercise 5.1

**Objective:** Implement Network Policies for a web application with frontend and backend pods.

**Setup:**

```bash
kubectl create namespace ex-5-1

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: ex-5-1
  labels:
    app: frontend
    tier: web
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: ex-5-1
  labels:
    app: backend
    tier: api
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: external-client
  namespace: ex-5-1
  labels:
    role: external
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n ex-5-1 --timeout=60s
```

**Task:** Create Network Policies that implement these rules:
1. Frontend accepts ingress from anywhere (external clients)
2. Backend only accepts ingress from frontend on port 80
3. External clients cannot directly access backend

**Verification:**

```bash
FRONTEND_IP=$(kubectl get pod frontend -n ex-5-1 -o jsonpath='{.status.podIP}')
BACKEND_IP=$(kubectl get pod backend -n ex-5-1 -o jsonpath='{.status.podIP}')

# external -> frontend should work
kubectl exec -n ex-5-1 external-client -- wget -qO- --timeout=2 http://$FRONTEND_IP && echo "external -> frontend: ALLOWED"

# frontend -> backend should work
kubectl exec -n ex-5-1 frontend -- curl -sf --connect-timeout 2 http://$BACKEND_IP && echo "frontend -> backend: ALLOWED"

# external -> backend should be blocked
timeout 3 kubectl exec -n ex-5-1 external-client -- wget -qO- --timeout=2 http://$BACKEND_IP || echo "external -> backend: BLOCKED"
```

---

### Exercise 5.2

**Objective:** Debug a policy that is blocking expected traffic.

**Setup:**

```bash
kubectl create namespace ex-5-2

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: service-a
  namespace: ex-5-2
  labels:
    app: service-a
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: service-b
  namespace: ex-5-2
  labels:
    app: service-b
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: service-a-policy
  namespace: ex-5-2
spec:
  podSelector:
    matchLabels:
      app: service-a
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          allowed: "true"
    ports:
    - port: 80
EOF

kubectl wait --for=condition=Ready pods --all -n ex-5-2 --timeout=60s
```

**Task:** service-b should be able to reach service-a, but it is being blocked. The configuration has one or more problems. Find and fix whatever is needed so the connection succeeds.

**Verification:**

```bash
SERVICE_A_IP=$(kubectl get pod service-a -n ex-5-2 -o jsonpath='{.status.podIP}')

# Before fix - blocked
timeout 3 kubectl exec -n ex-5-2 service-b -- wget -qO- --timeout=2 http://$SERVICE_A_IP || echo "BEFORE: BLOCKED"

# After applying your fix - should work
kubectl exec -n ex-5-2 service-b -- wget -qO- --timeout=2 http://$SERVICE_A_IP && echo "AFTER: ALLOWED"
```

---

### Exercise 5.3

**Objective:** Design Network Policies for a multi-tier application.

**Setup:**

```bash
kubectl create namespace ex-5-3

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: ex-5-3
  labels:
    app: web
    tier: frontend
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
  name: db
  namespace: ex-5-3
  labels:
    app: db
    tier: database
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
```

**Task:** Design and implement Network Policies that enforce:
1. Web (frontend) can receive traffic from any source
2. API (backend) only receives traffic from Web (frontend) on port 80
3. DB (database) only receives traffic from API (backend) on port 80
4. No direct access from external pods (tester) to API or DB

**Verification:**

```bash
WEB_IP=$(kubectl get pod web -n ex-5-3 -o jsonpath='{.status.podIP}')
API_IP=$(kubectl get pod api -n ex-5-3 -o jsonpath='{.status.podIP}')
DB_IP=$(kubectl get pod db -n ex-5-3 -o jsonpath='{.status.podIP}')

# tester -> web (should work)
kubectl exec -n ex-5-3 tester -- wget -qO- --timeout=2 http://$WEB_IP && echo "tester -> web: ALLOWED"

# web -> api (should work)
kubectl exec -n ex-5-3 web -- curl -sf --connect-timeout 2 http://$API_IP && echo "web -> api: ALLOWED"

# api -> db (should work)
kubectl exec -n ex-5-3 api -- curl -sf --connect-timeout 2 http://$DB_IP && echo "api -> db: ALLOWED"

# tester -> api (should be blocked)
timeout 3 kubectl exec -n ex-5-3 tester -- wget -qO- --timeout=2 http://$API_IP || echo "tester -> api: BLOCKED"

# tester -> db (should be blocked)
timeout 3 kubectl exec -n ex-5-3 tester -- wget -qO- --timeout=2 http://$DB_IP || echo "tester -> db: BLOCKED"

# web -> db (should be blocked - must go through api)
timeout 3 kubectl exec -n ex-5-3 web -- curl -sf --connect-timeout 2 http://$DB_IP || echo "web -> db: BLOCKED"
```

---

## Cleanup

Remove all exercise namespaces:

```bash
kubectl delete namespace ex-1-1 ex-1-2 ex-1-3
kubectl delete namespace ex-2-1 ex-2-2 ex-2-3
kubectl delete namespace ex-3-1 ex-3-2 ex-3-3
kubectl delete namespace ex-4-1 ex-4-2 ex-4-3
kubectl delete namespace ex-5-1 ex-5-2 ex-5-3
```

---

## Key Takeaways

1. **Network Policies are additive.** Multiple policies matching a pod combine their allow rules. You cannot deny what another policy allows.

2. **Pods without matching policies allow all traffic.** The policy only affects pods its podSelector matches.

3. **Empty podSelector {} matches all pods** in the namespace. Use this for default deny policies.

4. **Multiple from/to entries are OR logic.** Traffic matching ANY entry is allowed.

5. **from/to and ports are AND logic within a rule.** Traffic must match both the source/destination AND the port.

6. **Forgetting DNS egress breaks name resolution.** When adding egress rules, remember to allow UDP 53 to kube-system (covered in assignment 2).

7. **Always test before and after** applying policies to verify the expected effect.
