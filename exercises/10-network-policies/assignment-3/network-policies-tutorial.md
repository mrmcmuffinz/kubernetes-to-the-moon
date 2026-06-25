# Network Policies Tutorial: Network Policy Debugging

## Introduction

Network Policies can be challenging to debug because traffic failures are silent. A blocked connection simply times out without any error message explaining why. When traffic is unexpectedly allowed, there is no indication which policy permitted it. Effective troubleshooting requires a systematic approach that examines policies, selectors, and network paths methodically.

This tutorial covers the debugging methodology for Network Policy issues. You will learn how to diagnose blocked traffic, identify policies allowing unintended traffic, trace cross-namespace policy interactions, and verify DNS and service connectivity through policies. These skills are essential for production Kubernetes environments where network security meets application requirements.

## Prerequisites

You need a multi-node cluster with a CNI that enforces NetworkPolicy. Verify Calico is running:

```bash
kubectl get pods -l k8s-app=calico-node -A
# Expected: one calico-node pod per node, all Running
```

For kind cluster setup see `docs/cluster-setup.md#multi-node-with-calico-networkpolicy-support`. Existing kubeadm or bare-metal clusters with Calico work without additional setup.

## Setup

Create test namespaces and resources:

```bash
kubectl create namespace tutorial-network-policies
kubectl create namespace tutorial-backend

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: tutorial-network-policies
  labels:
    app: client
spec:
  containers:
  - name: busybox
    image: busybox:1.36
    command: ["sleep", "3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: tutorial-network-policies
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
  namespace: tutorial-network-policies
spec:
  selector:
    app: server
  ports:
  - port: 80
EOF

kubectl wait --for=condition=Ready pods --all -n tutorial-network-policies --timeout=60s
```

## Debugging Methodology

When Network Policy issues arise, follow this systematic approach:

### Step 1: Confirm the Symptom

First, verify the traffic is actually blocked or allowed unexpectedly:

```bash
# Test connectivity
SERVER_IP=$(kubectl get pod server -n tutorial-network-policies -o jsonpath='{.status.podIP}')
kubectl exec -n tutorial-network-policies client -- wget -qO- --timeout=2 http://$SERVER_IP

# Use timeout to avoid long waits for blocked connections
timeout 3 kubectl exec -n tutorial-network-policies client -- wget -qO- --timeout=2 http://$SERVER_IP
```

### Step 2: List Policies in the Target Namespace

Identify all policies that might affect the target pod:

```bash
kubectl get networkpolicy -n tutorial-network-policies
```

### Step 3: Check Which Policies Match the Target Pod

For each policy, check if it selects the target pod:

```bash
kubectl describe networkpolicy <policy-name> -n tutorial-network-policies
```

Look at the `PodSelector` field and compare with the target pod's labels:

```bash
kubectl get pod server -n tutorial-network-policies --show-labels
```

### Step 4: Check the Source Pod Labels and Namespace

Verify the source matches the policy's `from` selector:

```bash
kubectl get pod client -n tutorial-network-policies --show-labels
kubectl get namespace tutorial-network-policies --show-labels
```

### Step 5: Verify Ports

Check if the port in the policy matches the actual port:

```bash
kubectl describe networkpolicy <policy-name> -n tutorial-network-policies | grep -A5 "Allowing ingress"
```

### Step 6: Check for Multiple Policies

Remember policies are additive. Multiple matching policies combine their rules:

```bash
kubectl get networkpolicy -n tutorial-network-policies -o wide
```

## Diagnosing Blocked Traffic

When traffic should be allowed but is blocked:

### Check 1: Is there a policy at all?

If no policy selects the target pod, all traffic is allowed. If a policy does select it, only explicitly allowed traffic is permitted.

```bash
# List policies
kubectl get networkpolicy -n tutorial-network-policies

# Check if any policy selects the server pod
kubectl get pod server -n tutorial-network-policies --show-labels
```

### Check 2: Does the policy allow the source?

The `from` field must match the source pod's labels or namespace:

```yaml
# Policy allows from app=web
from:
- podSelector:
    matchLabels:
      app: web

# But source pod has app=client
# Result: BLOCKED
```

### Check 3: Does the policy allow the port?

```yaml
# Policy allows port 8080
ports:
- port: 8080

# But server listens on port 80
# Result: BLOCKED
```

### Check 4: Cross-namespace policies

For cross-namespace traffic, check:
1. The target namespace has a policy allowing the source namespace
2. The source namespace has the required labels

```bash
kubectl get namespace tutorial-backend --show-labels
```

### Example: Debugging Blocked Traffic

Apply a policy that blocks traffic:

```yaml
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: block-by-mistake
  namespace: tutorial-network-policies
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
          app: web
EOF
```

Debug it:

```bash
# Test shows traffic is blocked
timeout 3 kubectl exec -n tutorial-network-policies client -- wget -qO- --timeout=2 http://$SERVER_IP || echo "BLOCKED"

# Check policy selector matches server
kubectl describe networkpolicy block-by-mistake -n tutorial-network-policies
# PodSelector: app=server - matches server pod

# Check what the policy allows
# Allows from: app=web

# Check client labels
kubectl get pod client -n tutorial-network-policies --show-labels
# app=client - does NOT match app=web

# Root cause: Policy allows app=web but client has app=client
```

## Diagnosing Unexpectedly Allowed Traffic

When traffic should be blocked but is allowed:

### Check 1: Is there actually a policy?

Without policies, all traffic is allowed:

```bash
kubectl get networkpolicy -n tutorial-network-policies
```

### Check 2: Does any policy select the target?

If no policy selects the pod, it has no restrictions:

```bash
kubectl get pod <pod-name> --show-labels
# Compare with policy podSelector
```

### Check 3: Multiple policies additive behavior

If multiple policies match, their rules combine. A permissive policy cannot be overridden:

```yaml
# Policy A: Deny all (no ingress rules)
spec:
  podSelector:
    matchLabels:
      app: server
  policyTypes:
  - Ingress

# Policy B: Allow from app=client
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
          app: client

# Result: Traffic from app=client is ALLOWED because policies are additive
```

### Check 4: CNI not enforcing policies

Verify your CNI supports NetworkPolicy:

```bash
kubectl get pods -l k8s-app=calico-node -A
# If no Calico pods, policies are not enforced
```

## Cross-Namespace Troubleshooting

Cross-namespace policies require checking both ends:

### Source Side

Does the source pod have egress allowed?

```bash
kubectl get networkpolicy -n <source-namespace>
```

### Destination Side

Does the destination allow ingress from the source namespace?

```bash
kubectl get networkpolicy -n <dest-namespace>
kubectl get namespace <source-namespace> --show-labels
```

### Both Must Allow

For traffic to flow:
1. Source namespace must allow egress to destination (or have no egress policy)
2. Destination namespace must allow ingress from source

## DNS and Service Integration

Network Policies affect DNS and service connectivity.

### DNS Requires Egress to kube-system

DNS queries go to the kube-dns service in kube-system on UDP port 53:

```yaml
# Allow DNS
egress:
- to:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: kube-system
  ports:
  - protocol: UDP
    port: 53
```

### Services Still Use Pod IPs

Policies filter traffic to pod IPs, not service IPs. When you connect to a service ClusterIP, the traffic is directed to a backing pod. The policy must allow traffic to those pods.

### Testing DNS Through Policies

```bash
# Test DNS resolution
kubectl exec -n tutorial-network-policies client -- nslookup server-svc

# If DNS fails, check egress to kube-system
```

## Policy Observability Patterns

### Test Pod Method

Create a temporary test pod to isolate issues:

```bash
kubectl run test --rm -it --image=busybox:1.36 -n tutorial-network-policies -- wget -qO- --timeout=2 http://$SERVER_IP
```

### Compare Working and Broken

If one pod works and another does not, compare:
- Labels
- Namespace
- Network Policies affecting each

### Document Expected Flows

Before debugging, document what traffic SHOULD be allowed. Compare with actual policies.

## Verification

Test the setup:

```bash
# Pods running
kubectl get pods -n tutorial-network-policies

# Service exists
kubectl get svc server-svc -n tutorial-network-policies
```

## Cleanup

```bash
kubectl delete namespace tutorial-network-policies
kubectl delete namespace tutorial-backend
```

## Policy Debugging Flowchart

```
Traffic Blocked?
     |
     v
List policies in namespace
     |
     v
Does any policy select target pod?
     |
+----+----+
|         |
No       Yes
|         |
v         v
Traffic    Check policy from/to
should be  |
allowed    v
(no policy Match source labels/namespace?
= allow all)   |
          +----+----+
          |         |
          No       Yes
          |         |
          v         v
      Policy    Check port match
      blocks!       |
                   +----+----+
                   |         |
                   No       Yes
                   |         |
                   v         v
               Port     Traffic should
               blocks!  be allowed!
                        Check for other
                        blocking policies
```

## Reference Commands

| Task | Command |
|------|---------|
| List policies | `kubectl get networkpolicy -n <ns>` |
| Describe policy | `kubectl describe networkpolicy <name> -n <ns>` |
| Get pod labels | `kubectl get pod <name> --show-labels` |
| Get namespace labels | `kubectl get namespace <name> --show-labels` |
| Test connectivity | `timeout 3 kubectl exec -n <ns> <pod> -- wget -qO- --timeout=2 http://<ip>` |
| Test DNS | `kubectl exec -n <ns> <pod> -- nslookup <service>` |
| Quick test pod | `kubectl run test --rm -it --image=busybox:1.36 -- <command>` |
