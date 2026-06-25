# Network Policies Tutorial: Advanced Selectors and Isolation

## Introduction

The previous assignment covered Network Policy fundamentals using podSelector to control traffic within a namespace. Real-world applications often span multiple namespaces, and production environments require traffic control with external systems. This tutorial covers the advanced selector types that enable these scenarios: namespaceSelector for cross-namespace control, ipBlock for external IP ranges, and combined selectors for precise targeting.

This tutorial also covers default deny policies, which form the foundation of zero-trust networking, and namespace isolation patterns that are common in multi-tenant clusters. Understanding the additive nature of policies and how to design for least privilege is essential for secure Kubernetes deployments.

## Prerequisites

You need a multi-node cluster with a CNI that enforces NetworkPolicy. Verify Calico is running:

```bash
kubectl get pods -l k8s-app=calico-node -A
# Expected: one calico-node pod per node, all Running
```

For kind cluster setup see `docs/cluster-setup.md#multi-node-with-calico-networkpolicy-support`. Existing kubeadm or bare-metal clusters with Calico work without additional setup.

## Setup

Create the tutorial namespaces and test resources:

```bash
kubectl create namespace tutorial-network-policies
kubectl create namespace tutorial-backend
kubectl create namespace tutorial-monitoring

# Add labels to namespaces
kubectl label namespace tutorial-backend purpose=backend
kubectl label namespace tutorial-monitoring purpose=monitoring

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: tutorial-network-policies
  labels:
    app: frontend
spec:
  containers:
  - name: nginx
    image: nginx:1.25
---
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: tutorial-backend
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
  namespace: tutorial-monitoring
  labels:
    app: prometheus
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
  namespace: tutorial-network-policies
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

kubectl wait --for=condition=Ready pods --all -n tutorial-network-policies --timeout=60s
kubectl wait --for=condition=Ready pods --all -n tutorial-backend --timeout=60s
kubectl wait --for=condition=Ready pods --all -n tutorial-monitoring --timeout=60s
```

## namespaceSelector Mechanics

The `namespaceSelector` field allows you to specify source or destination namespaces using labels.

### Basic namespaceSelector

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        purpose: monitoring
```

This allows ingress from ANY pod in namespaces labeled `purpose=monitoring`.

### Viewing Namespace Labels

Namespaces need labels to be selected:

```bash
kubectl get namespaces --show-labels
```

Kubernetes automatically adds a label to each namespace:

```
kubernetes.io/metadata.name=<namespace-name>
```

You can select by namespace name using this built-in label:

```yaml
namespaceSelector:
  matchLabels:
    kubernetes.io/metadata.name: tutorial-monitoring
```

### Adding Labels to Namespaces

```bash
kubectl label namespace tutorial-backend purpose=backend
```

### Allow From Specific Namespace

```yaml
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-monitoring
  namespace: tutorial-backend
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
```

Test it:

```bash
API_IP=$(kubectl get pod api -n tutorial-backend -o jsonpath='{.status.podIP}')

# From monitoring namespace (should work)
kubectl exec -n tutorial-monitoring prometheus -- wget -qO- --timeout=2 http://$API_IP && echo "monitoring -> api: ALLOWED"

# From tutorial-network-policies namespace (should be blocked)
timeout 3 kubectl exec -n tutorial-network-policies client -- wget -qO- --timeout=2 http://$API_IP || echo "client -> api: BLOCKED"
```

## Combined Selectors (AND Logic)

When you put BOTH podSelector AND namespaceSelector in the SAME from/to entry, they are combined with AND:

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        purpose: monitoring
    podSelector:
      matchLabels:
        app: prometheus
```

This means: pods with `app=prometheus` AND in namespaces with `purpose=monitoring`.

### Difference from OR

Compare with separate entries (OR logic):

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        purpose: monitoring
  - podSelector:
      matchLabels:
        app: prometheus
```

This means: pods in namespaces with `purpose=monitoring` OR pods with `app=prometheus` (in the same namespace as the policy).

The dash `-` before the selector indicates a new entry in the array. Same line means AND, new dash means OR.

### Demonstration

```yaml
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: combined-selectors
  namespace: tutorial-backend
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
      podSelector:
        matchLabels:
          app: prometheus
EOF
```

This allows traffic only from pods that match BOTH conditions: in a monitoring namespace AND labeled `app=prometheus`.

## ipBlock for External Traffic

The `ipBlock` selector allows traffic based on IP address ranges (CIDR notation).

### Basic ipBlock

```yaml
ingress:
- from:
  - ipBlock:
      cidr: 10.0.0.0/8
```

This allows ingress from any IP in the 10.0.0.0/8 range.

### ipBlock with except

```yaml
ingress:
- from:
  - ipBlock:
      cidr: 10.0.0.0/8
      except:
      - 10.1.0.0/16
```

This allows 10.0.0.0/8 EXCEPT for 10.1.0.0/16.

### Use Cases for ipBlock

- Allow traffic from on-premises networks
- Allow traffic from specific external services
- Block known malicious IP ranges
- Allow traffic from load balancer IP ranges

### Important: ipBlock Does Not Mix with Other Selectors

You CANNOT combine ipBlock with podSelector or namespaceSelector in the same from/to entry:

```yaml
# INVALID - will not work as expected
- from:
  - ipBlock:
      cidr: 10.0.0.0/8
    podSelector:
      matchLabels:
        app: web
```

Use separate entries instead:

```yaml
# VALID - separate entries (OR logic)
- from:
  - ipBlock:
      cidr: 10.0.0.0/8
  - podSelector:
      matchLabels:
        app: web
```

## Default Deny Policies

A default deny policy blocks all traffic to selected pods unless explicitly allowed by another policy. This is the foundation of zero-trust networking.

### Deny All Ingress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: tutorial-network-policies
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

The empty podSelector `{}` matches ALL pods. Including Ingress in policyTypes without ingress rules denies all ingress.

### Deny All Egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: tutorial-network-policies
spec:
  podSelector: {}
  policyTypes:
  - Egress
```

**Warning:** This blocks DNS queries (UDP port 53), which breaks service name resolution.

### Deny All Egress with DNS Exception

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress-allow-dns
  namespace: tutorial-network-policies
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
```

This denies all egress except DNS queries to kube-system.

### Deny All Ingress and Egress

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: tutorial-network-policies
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

## Namespace Isolation Patterns

### Complete Namespace Isolation

Block all traffic except internal namespace communication:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: namespace-isolation
  namespace: tutorial-network-policies
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - podSelector: {}
  egress:
  - to:
    - podSelector: {}
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
```

This allows:
- Ingress from pods in the same namespace
- Egress to pods in the same namespace
- Egress to DNS

### Allow Specific Cross-Namespace Traffic

After default deny, add specific allow rules:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-frontend
  namespace: tutorial-backend
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
          kubernetes.io/metadata.name: tutorial-network-policies
      podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 80
```

## Policy Ordering and Additive Behavior

Network Policies are additive. There is no priority or ordering between policies.

### Key Points

1. **No deny rules:** You cannot explicitly deny traffic. Policies only allow.
2. **Multiple policies combine:** If multiple policies match a pod, the union of their rules applies.
3. **More policies = more permissive:** Each policy adds more allowed traffic.
4. **Cannot subtract:** You cannot use one policy to deny what another allows.

### Example

If Policy A allows port 80 from namespace X, and Policy B allows port 443 from namespace Y, a pod matched by both policies allows both.

### Design for Least Privilege

Start with default deny, then add only the specific traffic you need:

```yaml
# Step 1: Default deny all
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: kube-system
    ports:
    - protocol: UDP
      port: 53
---
# Step 2: Allow specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-web-to-api
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
```

## Verification

Test the setup:

```bash
# Namespaces have labels
kubectl get namespaces --show-labels | grep tutorial

# Pods are running
kubectl get pods -n tutorial-network-policies
kubectl get pods -n tutorial-backend
kubectl get pods -n tutorial-monitoring
```

## Cleanup

Delete the tutorial namespaces:

```bash
kubectl delete namespace tutorial-network-policies
kubectl delete namespace tutorial-backend
kubectl delete namespace tutorial-monitoring
```

## Reference Commands

| Task | Command |
|------|---------|
| Label namespace | `kubectl label namespace <name> <key>=<value>` |
| Show namespace labels | `kubectl get namespaces --show-labels` |
| Select by namespace name | Use `kubernetes.io/metadata.name: <name>` |
| List policies | `kubectl get networkpolicy -n <namespace>` |
| Describe policy | `kubectl describe networkpolicy <name> -n <namespace>` |
| Test cross-namespace | `kubectl exec -n <ns1> <pod> -- wget http://<ip>` |
