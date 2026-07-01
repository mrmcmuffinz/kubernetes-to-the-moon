# Network Policies Tutorial: NetworkPolicy Fundamentals

## Introduction

By default, Kubernetes allows all pods to communicate with all other pods in the cluster. This open network model simplifies development but creates security challenges in production. Network Policies provide a way to control traffic flow at the IP address and port level, implementing microsegmentation and defense in depth.

Network Policies work like firewall rules for pods. You define which pods the policy applies to (using a pod selector), what type of traffic to control (ingress, egress, or both), and what sources or destinations to allow. Traffic that does not match an allow rule is denied.

This tutorial covers the NetworkPolicy resource structure, how pod selectors work, basic ingress and egress rules within a namespace, and port-level filtering. These fundamentals prepare you for the more advanced selector types covered in assignment 2.

## Prerequisites

You need a multi-node cluster with a CNI that enforces NetworkPolicy. Calico v3.31.5 or later is the tested option.

**Existing kubeadm or bare-metal cluster with Calico:** Verify that Calico is running and skip the kind setup below.

```bash
kubectl get pods -l k8s-app=calico-node -A
# Expected: one calico-node pod per node, all Running

kubectl get nodes
# Expected: all nodes Ready
```

**kind cluster:** Follow `docs/cluster-setup.md#multi-node-with-calico-networkpolicy-support` to create a multi-node kind cluster with the default CNI disabled and Calico installed. The default kind CNI (kindnet) does NOT enforce NetworkPolicy.

## Setup

Create the tutorial namespace and test pods:

```bash
kubectl create namespace tutorial-network-policies

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: tutorial-network-policies
  labels:
    app: web
    tier: frontend
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
  name: api
  namespace: tutorial-network-policies
  labels:
    app: api
    tier: backend
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
  name: db
  namespace: tutorial-network-policies
  labels:
    app: db
    tier: database
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
  namespace: tutorial-network-policies
  labels:
    role: client
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n tutorial-network-policies --timeout=60s
```

## Testing Connectivity (Before Policies)

Before applying any Network Policies, verify that all pods can communicate:

```bash
# Get pod IPs
WEB_IP=$(kubectl get pod web -n tutorial-network-policies -o jsonpath='{.status.podIP}')
API_IP=$(kubectl get pod api -n tutorial-network-policies -o jsonpath='{.status.podIP}')
DB_IP=$(kubectl get pod db -n tutorial-network-policies -o jsonpath='{.status.podIP}')

echo "Web IP: $WEB_IP"
echo "API IP: $API_IP"
echo "DB IP: $DB_IP"

# Test connectivity from client to all pods
kubectl exec -n tutorial-network-policies client -- wget -qO- --timeout=2 http://$WEB_IP
kubectl exec -n tutorial-network-policies client -- wget -qO- --timeout=2 http://$API_IP
kubectl exec -n tutorial-network-policies client -- wget -qO- --timeout=2 http://$DB_IP
```

All requests should succeed, showing the default nginx welcome page.

## NetworkPolicy Spec Structure

A NetworkPolicy resource has this structure:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: example-policy
  namespace: tutorial-network-policies
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: client
    ports:
    - protocol: TCP
      port: 80
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: api
    ports:
    - protocol: TCP
      port: 80
```

### Key Fields

**spec.podSelector:** Determines which pods the policy applies to. Only pods matching this selector are affected. Pods not matching any policy allow all traffic.

**spec.policyTypes:** Specifies whether the policy controls Ingress, Egress, or both. If you include Ingress in policyTypes but do not define any ingress rules, all ingress is denied. Same for Egress.

**spec.ingress:** List of ingress rules. Each rule can specify sources (from) and ports. Traffic is allowed if it matches any rule.

**spec.egress:** List of egress rules. Each rule can specify destinations (to) and ports. Traffic is allowed if it matches any rule.

## podSelector Mechanics

The podSelector field uses standard Kubernetes label selectors.

### Empty Selector (All Pods)

```yaml
spec:
  podSelector: {}
```

An empty selector `{}` matches ALL pods in the namespace. This is commonly used for default deny policies.

### Label Selector

```yaml
spec:
  podSelector:
    matchLabels:
      app: web
```

Matches only pods with the label `app=web`.

### Multiple Labels (AND)

```yaml
spec:
  podSelector:
    matchLabels:
      app: web
      tier: frontend
```

Matches pods that have BOTH labels (AND logic).

### Important: Unmatched Pods

Pods not matched by any NetworkPolicy allow all traffic. The policy only affects the pods it selects. This means you cannot use policies to deny traffic to pods that are not selected by any policy.

## Basic Ingress Rules

Ingress rules control incoming traffic to the selected pods.

### Allow Specific Pods

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-web
  namespace: tutorial-network-policies
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
```

Apply this policy:

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-allow-web
  namespace: tutorial-network-policies
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
```

Test the effect:

```bash
# From web pod to api (should work)
kubectl exec -n tutorial-network-policies web -- curl -sf --connect-timeout 2 http://$API_IP

# From client pod to api (should fail)
kubectl exec -n tutorial-network-policies client -- wget -qO- --timeout=2 http://$API_IP
# This will timeout
```

The api pod now only accepts ingress from pods with `app=web`.

### Multiple Sources (OR)

Multiple entries in the `from` array are OR-ed together:

```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
  - podSelector:
      matchLabels:
        role: client
```

This allows traffic from pods with `app=web` OR pods with `role=client`.

### Deny All Ingress

An empty ingress array denies all ingress:

```yaml
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Ingress
  ingress: []
```

Or simply include Ingress in policyTypes without defining any ingress rules:

```yaml
spec:
  podSelector:
    matchLabels:
      app: db
  policyTypes:
  - Ingress
```

## Basic Egress Rules

Egress rules control outgoing traffic from the selected pods.

### Allow Specific Destinations

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-egress
  namespace: tutorial-network-policies
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: api
```

This allows the web pod to send traffic only to pods with `app=api`.

### Deny All Egress

```yaml
spec:
  podSelector:
    matchLabels:
      app: web
  policyTypes:
  - Egress
  egress: []
```

**Warning:** Denying all egress also blocks DNS queries. The pod will not be able to resolve service names. We will address this in assignment 2.

## Port-Level Filtering

You can restrict allowed traffic to specific ports and protocols.

### Single Port

```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
  ports:
  - protocol: TCP
    port: 80
```

Only TCP port 80 is allowed. Other ports are denied.

### Multiple Ports

```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
  ports:
  - protocol: TCP
    port: 80
  - protocol: TCP
    port: 443
```

### Port Range

```yaml
ports:
- protocol: TCP
  port: 8000
  endPort: 8080
```

Allows TCP ports 8000 through 8080.

### No Ports Specified

If you do not specify ports, all ports are allowed for that rule:

```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
  # No ports field - all ports allowed from web pods
```

### AND Between from/to and ports

Within a single rule, `from`/`to` and `ports` are combined with AND. Traffic must match both the source/destination AND the port:

```yaml
ingress:
- from:
  - podSelector:
      matchLabels:
        app: web
  ports:
  - port: 80
```

This means: allow traffic from pods with `app=web` AND only to port 80.

## Named Ports

You can reference ports by name instead of number:

```yaml
ports:
- protocol: TCP
  port: http
```

This refers to the port named "http" in the target pod's container spec:

```yaml
containers:
- name: nginx
  ports:
  - containerPort: 80
    name: http
```

Named ports make policies more readable and resilient to port number changes.

## Policy Verification Workflow

Always follow this workflow when working with Network Policies:

1. **Test connectivity before the policy** to establish baseline
2. **Apply the policy**
3. **Test connectivity after the policy** to verify the effect
4. **Use kubectl describe** to verify policy configuration

```bash
kubectl describe networkpolicy api-allow-web -n tutorial-network-policies
```

Output shows:

```
Name:         api-allow-web
Namespace:    tutorial-network-policies
Created on:   ...
Labels:       <none>
Annotations:  <none>
Spec:
  PodSelector:     app=api
  Allowing ingress traffic:
    To Port: <any> (traffic allowed to all ports)
    From:
      PodSelector: app=web
  Not affecting egress traffic
  Policy Types: Ingress
```

## Complete Example: Three-Tier Application

Let us implement a proper three-tier policy: web can reach api, api can reach db.

Clean up previous policies:

```bash
kubectl delete networkpolicy --all -n tutorial-network-policies
```

Apply the policies:

```yaml
kubectl apply -f - <<EOF
# Web tier: allow ingress from anywhere (it's the frontend)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: web-policy
  namespace: tutorial-network-policies
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
  - Ingress
  ingress:
  - {} # Allow all ingress
---
# API tier: only accept from frontend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-policy
  namespace: tutorial-network-policies
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
          tier: frontend
    ports:
    - port: 80
---
# Database tier: only accept from backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: db-policy
  namespace: tutorial-network-policies
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          tier: backend
    ports:
    - port: 80
EOF
```

Test the policies:

```bash
# Web can reach API (frontend to backend)
kubectl exec -n tutorial-network-policies web -- curl -sf --connect-timeout 2 http://$API_IP && echo "web -> api: ALLOWED"

# API can reach DB (backend to database)
kubectl exec -n tutorial-network-policies api -- curl -sf --connect-timeout 2 http://$DB_IP && echo "api -> db: ALLOWED"

# Client cannot reach API (no tier label)
timeout 3 kubectl exec -n tutorial-network-policies client -- wget -qO- --timeout=2 http://$API_IP || echo "client -> api: BLOCKED"

# Web cannot reach DB directly (frontend cannot bypass backend)
timeout 3 kubectl exec -n tutorial-network-policies web -- curl -sf --connect-timeout 2 http://$DB_IP || echo "web -> db: BLOCKED"
```

## Verification

Verify the tutorial setup:

```bash
# All pods are running
kubectl get pods -n tutorial-network-policies

# Policies are in place
kubectl get networkpolicy -n tutorial-network-policies
```

## Cleanup

Delete the tutorial namespace:

```bash
kubectl delete namespace tutorial-network-policies
```

## Reference Commands

| Task | Command |
|------|---------|
| List Network Policies | `kubectl get networkpolicy -n <namespace>` |
| Describe policy | `kubectl describe networkpolicy <name> -n <namespace>` |
| Delete policy | `kubectl delete networkpolicy <name> -n <namespace>` |
| Get pod IPs | `kubectl get pods -n <namespace> -o wide` |
| Test connectivity | `kubectl exec -n <ns> <pod> -- wget -qO- --timeout=2 http://<ip>` |
| Test with curl | `kubectl exec -n <ns> <pod> -- curl -s --connect-timeout 2 http://<ip>` |
| Check pod labels | `kubectl get pod <name> -n <namespace> --show-labels` |
| Apply policy from file | `kubectl apply -f <file.yaml>` |
| Apply policy inline | `kubectl apply -f - <<EOF ... EOF` |
