# Operational Skills Supplement

This document contains operational exercises that complement the troubleshooting assignments. These exercises drill command-line skills and operational knowledge that appear in CKA exam simulations but are not traditional debugging scenarios.

---

## Exercise: Event Logging and Container Kill Analysis

**Objective:** Understand the difference between pod deletion events and container kill events, and practice using kubectl events for troubleshooting.

**Prerequisites:** Multi-node kind cluster with a DaemonSet running (kube-proxy is present by default)

### Part 1: Cluster Event Logging

**Task:** Write a command to `/tmp/cluster-events.sh` that shows all cluster events sorted by creation time.

**Solution:**

```bash
cat > /tmp/cluster-events.sh <<'EOF'
#!/bin/bash
kubectl events -A --sort-by=.metadata.creationTimestamp
EOF
chmod +x /tmp/cluster-events.sh
```

**Alternative using kubectl get events:**

```bash
cat > /tmp/cluster-events-alt.sh <<'EOF'
#!/bin/bash
kubectl get events -A --sort-by='.lastTimestamp'
EOF
chmod +x /tmp/cluster-events-alt.sh
```

**Verification:**

```bash
/tmp/cluster-events.sh
# Expected: Events from all namespaces sorted by creation time

# Test with a known event
kubectl -n default run test-event --image=nginx:1.27 --restart=Never
sleep 2
/tmp/cluster-events.sh | grep test-event
# Expected: Scheduled, Pulling, Pulled, Created, Started events for test-event pod
kubectl delete pod test-event -n default
```

### Part 2: Pod Deletion vs Container Kill Events

**Background:** When a pod belonging to a DaemonSet is deleted, the DaemonSet controller notices and recreates the pod, generating a full event chain (pod deletion, controller reconciliation, new pod creation, scheduling, image pull, container start). When only the container inside the pod is killed via `crictl`, the pod object remains intact and the kubelet's restart policy handles the container restart with a smaller event set (no scheduling, no controller involvement).

**Setup:**

```bash
# Identify a kube-proxy pod (part of the kube-proxy DaemonSet)
PROXY_POD=$(kubectl -n kube-system get pods -l k8s-app=kube-proxy -o jsonpath='{.items[0].metadata.name}')
echo "Using kube-proxy pod: $PROXY_POD"
```

**Task 1: Capture pod deletion events**

Delete the entire pod and capture the resulting events:

```bash
kubectl -n kube-system delete pod $PROXY_POD
sleep 5
kubectl events -n kube-system --for pod/$PROXY_POD > /tmp/pod-deletion-events.log 2>&1 || \
  kubectl get events -n kube-system --field-selector involvedObject.name=$PROXY_POD --sort-by='.lastTimestamp' > /tmp/pod-deletion-events.log

# The pod name will change because DaemonSet creates a new pod, so capture new pod events
NEW_PROXY_POD=$(kubectl -n kube-system get pods -l k8s-app=kube-proxy -o jsonpath='{.items[0].metadata.name}')
kubectl get events -n kube-system --field-selector involvedObject.name=$NEW_PROXY_POD --sort-by='.lastTimestamp' >> /tmp/pod-deletion-events.log
```

**Expected events for pod deletion:**
- Pod deletion (Killing event)
- DaemonSet controller creates new pod
- Scheduler assigns node
- Image pull (if not cached)
- Container created
- Container started

**Task 2: Capture container kill events**

Find the worker node where kube-proxy is running and kill the container directly:

```bash
# Get the current kube-proxy pod again (it was recreated)
PROXY_POD=$(kubectl -n kube-system get pods -l k8s-app=kube-proxy -o jsonpath='{.items[0].metadata.name}')
PROXY_NODE=$(kubectl -n kube-system get pod $PROXY_POD -o jsonpath='{.spec.nodeName}')

echo "kube-proxy pod $PROXY_POD is on node $PROXY_NODE"

# On kind, nodes are accessible via nerdctl exec
# Get the container ID
CONTAINER_ID=$(nerdctl exec $PROXY_NODE crictl ps | grep kube-proxy | awk '{print $1}')
echo "Container ID: $CONTAINER_ID"

# Kill the container (not the pod)
nerdctl exec $PROXY_NODE crictl rm --force $CONTAINER_ID

sleep 5

# Capture events for the same pod (pod object still exists, just container restarted)
kubectl get events -n kube-system --field-selector involvedObject.name=$PROXY_POD --sort-by='.lastTimestamp' > /tmp/container-kill-events.log
```

**Expected events for container kill:**
- Container killed (exit code, reason)
- Container started (kubelet restart policy)
- No scheduling events (pod wasn't deleted)
- No DaemonSet controller events (pod object unchanged)

**Analysis:**

Compare the two event logs:

```bash
echo "=== Pod Deletion Events ==="
cat /tmp/pod-deletion-events.log
echo ""
echo "=== Container Kill Events ==="
cat /tmp/container-kill-events.log
```

**Key differences:**
- Pod deletion triggers DaemonSet controller reconciliation (full lifecycle)
- Container kill is handled by kubelet alone (restart in place)
- Event volume: pod deletion produces 6-10 events, container kill produces 2-3 events

### Part 3: Using --previous Logs

**Background:** When a container crashes or is killed, its logs are preserved and accessible via `kubectl logs --previous`. This is critical for debugging CrashLoopBackOff scenarios where the current container hasn't been running long enough to produce useful logs.

**Task:** Create a pod that crashes immediately, then retrieve its previous logs.

```bash
kubectl run crash-test --image=busybox:1.36 --restart=Never -- sh -c "echo 'I will crash now'; exit 1"

# Wait for the crash
sleep 2
kubectl get pod crash-test
# Expected: Status Error or CrashLoopBackOff (if restartPolicy was OnFailure)

# Get previous logs
kubectl logs crash-test --previous
# Expected: "I will crash now"

# Cleanup
kubectl delete pod crash-test
```

**Verification:**

```bash
# Create a pod that crashes after printing diagnostic info
kubectl run diagnostic-crash --image=busybox:1.36 --restart=Never -- sh -c "
echo 'Starting diagnostic...'
echo 'Environment variables:'
env
echo 'Filesystem:'
ls -la /
echo 'FATAL: Configuration error detected'
exit 1
"

sleep 2
kubectl logs diagnostic-crash --previous | grep "FATAL"
# Expected: "FATAL: Configuration error detected"

kubectl delete pod diagnostic-crash
```

---

## Exercise: API Resources Query

**Objective:** List namespaced Kubernetes resources and count resources by type.

### Part 1: List All Namespaced Resources

**Task:** Write all namespaced resource types to a file.

```bash
kubectl api-resources --namespaced -o name > /tmp/namespaced-resources.txt
```

**Verification:**

```bash
cat /tmp/namespaced-resources.txt | head -10
# Expected: pods, services, configmaps, secrets, replicationcontrollers, endpoints, etc.

# Verify pods are in the list (namespaced)
grep -q "^pods$" /tmp/namespaced-resources.txt && echo "pods: namespaced"

# Verify nodes are NOT in the list (cluster-scoped)
grep -q "^nodes$" /tmp/namespaced-resources.txt && echo "ERROR: nodes should not be namespaced" || echo "nodes: cluster-scoped (correct)"
```

### Part 2: Count Resources Across Namespaces

**Task:** Count how many Roles exist in each namespace that starts with "kube-".

```bash
# List all kube-* namespaces
kubectl get namespaces | grep ^kube- | awk '{print $1}' > /tmp/kube-namespaces.txt

# Count Roles in each
while read ns; do
  count=$(kubectl -n $ns get role --no-headers 2>/dev/null | wc -l)
  echo "$ns: $count roles"
done < /tmp/kube-namespaces.txt
```

**Expected output:**
```
kube-node-lease: 0 roles
kube-public: 0 roles
kube-system: X roles (depends on cluster setup)
```

**Alternative: Count all resources of a specific type**

```bash
# Count total number of Services across all namespaces
kubectl get svc -A --no-headers | wc -l

# Count ConfigMaps in a specific namespace
kubectl -n kube-system get cm --no-headers | wc -l
```

### Part 3: Distinguish Namespaced vs Cluster-Scoped Resources

**Task:** For each resource type, determine if it is namespaced or cluster-scoped.

```bash
# Show namespaced status for all resources
kubectl api-resources --namespaced=true -o name | while read resource; do
  echo "$resource: namespaced"
done > /tmp/resource-scope.txt

kubectl api-resources --namespaced=false -o name | while read resource; do
  echo "$resource: cluster-scoped"
done >> /tmp/resource-scope.txt
```

**Verification:**

```bash
# Check specific resources
grep "pods:" /tmp/resource-scope.txt
# Expected: pods: namespaced

grep "nodes:" /tmp/resource-scope.txt
# Expected: nodes: cluster-scoped

grep "persistentvolumes:" /tmp/resource-scope.txt
# Expected: persistentvolumes: cluster-scoped

grep "persistentvolumeclaims:" /tmp/resource-scope.txt
# Expected: persistentvolumeclaims: namespaced
```

---

## Summary

These operational exercises complement the troubleshooting assignments by covering:

1. **Event logging and analysis**: Understanding `kubectl events` vs `kubectl get events`, sorting by creation time, and distinguishing pod deletion from container kill event patterns
2. **Previous container logs**: Using `kubectl logs --previous` to retrieve logs from crashed containers
3. **API resources introspection**: Listing namespaced resources, counting resources across namespaces, and distinguishing resource scope

These skills appear in CKA exam simulations (Simulator B Q15 and Q16) and are essential for operational troubleshooting workflows.
