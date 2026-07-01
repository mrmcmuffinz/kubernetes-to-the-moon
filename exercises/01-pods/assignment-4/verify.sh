#!/usr/bin/env bash
#
# verify.sh - Automated verification for pod-scheduling-homework.md
#
# Usage:
#   ./verify.sh 1.1      # verify exercise 1.1
#   ./verify.sh all      # verify all exercises
#   ./verify.sh 1        # verify all Level 1 exercises
#

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track overall pass/fail
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper: print pass message
pass() {
    echo -e "${GREEN}✓${NC} $1"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Helper: print fail message
fail() {
    echo -e "${RED}✗${NC} $1"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Helper: print fail message with debug command
fail_with_cmd() {
    echo -e "${RED}✗${NC} $1"
    echo -e "  ${YELLOW}Debug:${NC} $2"
    FAILED_TESTS=$((FAILED_TESTS + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

# Helper: print info message
info() {
    echo -e "${YELLOW}ℹ${NC} $1"
}

# Helper: check if namespace exists
namespace_exists() {
    kubectl get namespace "$1" &>/dev/null
}

# Helper: check if pod exists
pod_exists() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

# Helper: get pod phase
get_phase() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: get node where pod is scheduled
get_node() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.nodeName}' 2>/dev/null
}

# Helper: check if node has label
node_has_label() {
    local node=$1
    local key=$2
    local expected=$3
    local actual
    actual=$(kubectl get node "$node" -o jsonpath="{.metadata.labels.$key}" 2>/dev/null || echo "")
    [[ "$actual" == "$expected" ]]
}

# Helper: check if node has taint
node_has_taint() {
    local node=$1
    local key=$2
    local effect=$3
    kubectl get node "$node" -o jsonpath='{.spec.taints}' 2>/dev/null | grep -q "\"key\":\"$key\"" && \
        kubectl get node "$node" -o jsonpath='{.spec.taints}' 2>/dev/null | grep -q "\"effect\":\"$effect\""
}

# Helper: check if pod has toleration
pod_has_toleration() {
    local pod=$1
    local ns=$2
    local key=$3
    local effect=$4
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.tolerations}' 2>/dev/null | grep -q "\"key\":\"$key\"" && \
        kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.tolerations}' 2>/dev/null | grep -q "\"effect\":\"$effect\""
}

# Helper: check if pod has nodeSelector
pod_has_node_selector() {
    local pod=$1
    local ns=$2
    local key=$3
    local value=$4
    local actual
    actual=$(kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.nodeSelector.$key}" 2>/dev/null || echo "")
    [[ "$actual" == "$value" ]]
}

# Helper: check if pod has node affinity
pod_has_node_affinity() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.affinity.nodeAffinity}' 2>/dev/null | grep -q "requiredDuringSchedulingIgnoredDuringExecution\|preferredDuringSchedulingIgnoredDuringExecution"
}

# Helper: check if pod has pod affinity
pod_has_pod_affinity() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.affinity.podAffinity}' 2>/dev/null | grep -q "requiredDuringSchedulingIgnoredDuringExecution\|preferredDuringSchedulingIgnoredDuringExecution"
}

# Helper: check if pod has pod anti-affinity
pod_has_pod_anti_affinity() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.affinity.podAntiAffinity}' 2>/dev/null | grep -q "requiredDuringSchedulingIgnoredDuringExecution\|preferredDuringSchedulingIgnoredDuringExecution"
}

# Helper: check if pod has topology spread constraints
pod_has_topology_spread() {
    local pod=$1
    local ns=$2
    local result
    result=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.topologySpreadConstraints}' 2>/dev/null || echo "")
    [[ -n "$result" && "$result" != "[]" ]]
}

# Helper: get priority class name from pod
get_priority_class() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.priorityClassName}' 2>/dev/null
}

# Helper: count unique nodes for a label selector
count_unique_nodes() {
    local ns=$1
    local label=$2
    kubectl get pods -n "$ns" -l "$label" -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}' 2>/dev/null | sort -u | wc -l
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: nodeSelector ==="
    local pod="ssd-pod"
    local ns="ex-1-1"
    local target_node="scheduling-lab-worker2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    local node
    node=$(get_node "$pod" "$ns")
    if [[ "$node" == "$target_node" ]]; then
        pass "Pod is on $target_node"
    else
        fail_with_cmd "Pod is on $node (expected $target_node)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    if pod_has_node_selector "$pod" "$ns" "ex-1-1/disktype" "ssd"; then
        pass "Pod has nodeSelector ex-1-1/disktype=ssd"
    else
        fail_with_cmd "Pod does not have correct nodeSelector" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeSelector}'"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: nodeName ==="
    local pod="pinned-pod"
    local ns="ex-1-2"
    local target_node="scheduling-lab-worker3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    local node
    node=$(get_node "$pod" "$ns")
    if [[ "$node" == "$target_node" ]]; then
        pass "Pod is on $target_node (nodeName used)"
    else
        fail_with_cmd "Pod is on $node (expected $target_node)" \
            "kubectl get pod $pod -n $ns -o wide"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Taint and toleration ==="
    local pod="gpu-pod"
    local ns="ex-1-3"
    local target_node="scheduling-lab-worker"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    local node
    node=$(get_node "$pod" "$ns")
    if [[ "$node" == "$target_node" ]]; then
        pass "Pod is on $target_node"
    else
        fail_with_cmd "Pod is on $node (expected $target_node)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    if pod_has_toleration "$pod" "$ns" "ex-1-3/gpu" "NoSchedule"; then
        pass "Pod has toleration for ex-1-3/gpu:NoSchedule"
    else
        fail_with_cmd "Pod does not have correct toleration" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.tolerations}'"
    fi

    if node_has_taint "$target_node" "ex-1-3/gpu" "NoSchedule"; then
        pass "Node has taint ex-1-3/gpu:NoSchedule"
    else
        fail "Node does not have expected taint"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Required and preferred node affinity ==="
    local pod="zone-disk-pod"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    local node
    node=$(get_node "$pod" "$ns")
    if [[ "$node" == "scheduling-lab-worker" || "$node" == "scheduling-lab-worker2" ]]; then
        pass "Pod is on $node (acceptable zone)"
    else
        fail_with_cmd "Pod is on $node (expected worker or worker2)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    if pod_has_node_affinity "$pod" "$ns"; then
        pass "Pod has node affinity"
    else
        fail_with_cmd "Pod does not have node affinity" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.affinity.nodeAffinity}'"
    fi

    # Check for required affinity
    local required
    required=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution}' 2>/dev/null || echo "")
    if [[ -n "$required" ]]; then
        pass "Pod has required node affinity"
    else
        fail "Pod missing required node affinity"
    fi

    # Check for preferred affinity
    local preferred
    preferred=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.affinity.nodeAffinity.preferredDuringSchedulingIgnoredDuringExecution}' 2>/dev/null || echo "")
    if [[ -n "$preferred" ]]; then
        pass "Pod has preferred node affinity"
    else
        fail "Pod missing preferred node affinity"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Dedicated-node pattern ==="
    local pod="ml-worker"
    local ns="ex-2-2"
    local target_node="scheduling-lab-worker3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    local node
    node=$(get_node "$pod" "$ns")
    if [[ "$node" == "$target_node" ]]; then
        pass "Pod is on $target_node (dedicated node)"
    else
        fail_with_cmd "Pod is on $node (expected $target_node)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    if pod_has_toleration "$pod" "$ns" "ex-2-2/dedicated" "NoSchedule"; then
        pass "Pod has toleration for ex-2-2/dedicated:NoSchedule"
    else
        fail_with_cmd "Pod does not have correct toleration" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.tolerations}'"
    fi

    if pod_has_node_affinity "$pod" "$ns"; then
        pass "Pod has node affinity (targeting dedicated node)"
    else
        fail_with_cmd "Pod does not have node affinity" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.affinity.nodeAffinity}'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: NotIn and In operators ==="
    local pod="exclusion-pod"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    local node
    node=$(get_node "$pod" "$ns")
    if [[ "$node" == "scheduling-lab-worker2" || "$node" == "scheduling-lab-worker3" ]]; then
        pass "Pod is on $node (backend node in us-east)"
    else
        fail_with_cmd "Pod is on $node (expected worker2 or worker3)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    # Verify node tier is NOT frontend
    local tier
    tier=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.ex-2-3\/tier}' 2>/dev/null || echo "")
    if [[ "$tier" != "frontend" ]]; then
        pass "Node tier is $tier (not frontend)"
    else
        fail "Node tier is frontend (should be excluded)"
    fi

    # Verify node region is us-east
    local region
    region=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.ex-2-3\/region}' 2>/dev/null || echo "")
    if [[ "$region" == "us-east" ]]; then
        pass "Node region is us-east"
    else
        fail_with_cmd "Node region is $region (expected us-east)" \
            "kubectl get node $node -o jsonpath='{.metadata.labels.ex-2-3\/region}'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug nodeSelector mismatch ==="
    local pod="broken-selector"
    local ns="ex-3-1"
    local target_node="scheduling-lab-worker2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | grep -A 10 Events"
    fi

    local node
    node=$(get_node "$pod" "$ns")
    if [[ "$node" == "$target_node" ]]; then
        pass "Pod is on $target_node"
    else
        fail_with_cmd "Pod is on $node (expected $target_node)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug toleration effect mismatch ==="
    local pod="broken-toleration"
    local ns="ex-3-2"
    local target_node="scheduling-lab-worker3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | grep -A 10 Events"
    fi

    local node
    node=$(get_node "$pod" "$ns")
    if [[ "$node" == "$target_node" ]]; then
        pass "Pod is on $target_node"
    else
        fail_with_cmd "Pod is on $node (expected $target_node)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    if node_has_taint "$target_node" "ex-3-2/workload" "NoSchedule"; then
        pass "Node still has taint (pod was fixed, not node)"
    else
        fail "Node taint was removed (should fix pod, not node)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug pod anti-affinity spread ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check all three pods exist and are Running
    local pods=("spread-a" "spread-b" "spread-c")
    local all_running=true
    for pod in "${pods[@]}"; do
        if ! pod_exists "$pod" "$ns"; then
            fail "Pod $pod not found in namespace $ns"
            all_running=false
        else
            local phase
            phase=$(get_phase "$pod" "$ns")
            if [[ "$phase" != "Running" ]]; then
                fail "Pod $pod is $phase (expected Running)"
                all_running=false
            fi
        fi
    done

    if $all_running; then
        pass "All three pods are Running"
    else
        return
    fi

    # Count unique nodes
    local unique_count
    unique_count=$(count_unique_nodes "$ns" "app=ex-3-3-spread")
    if [[ "$unique_count" -eq 3 ]]; then
        pass "All three pods are on different nodes"
    else
        fail_with_cmd "Pods are spread across $unique_count nodes (expected 3)" \
            "kubectl get pods -n $ns -l app=ex-3-3-spread -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.nodeName}{\"\n\"}{end}'"
    fi

    # Verify required anti-affinity is present
    if pod_has_pod_anti_affinity "spread-a" "$ns"; then
        pass "Pods have pod anti-affinity configured"
    else
        fail_with_cmd "Pods do not have pod anti-affinity" \
            "kubectl get pod spread-a -n $ns -o jsonpath='{.spec.affinity.podAntiAffinity}'"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Dedicated infrastructure node ==="
    local ns="ex-4-1"
    local infra_pod="infra-agent"
    local app_pod="app-web"
    local reserved_node="scheduling-lab-worker"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check infra-agent
    if ! pod_exists "$infra_pod" "$ns"; then
        fail "Pod $infra_pod not found"
        return
    fi

    local phase
    phase=$(get_phase "$infra_pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "infra-agent is Running"
    else
        fail_with_cmd "infra-agent is $phase (expected Running)" \
            "kubectl describe pod $infra_pod -n $ns"
    fi

    local node
    node=$(get_node "$infra_pod" "$ns")
    if [[ "$node" == "$reserved_node" ]]; then
        pass "infra-agent is on $reserved_node (reserved node)"
    else
        fail_with_cmd "infra-agent is on $node (expected $reserved_node)" \
            "kubectl get pod $infra_pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    # Check app-web
    if ! pod_exists "$app_pod" "$ns"; then
        fail "Pod $app_pod not found"
        return
    fi

    phase=$(get_phase "$app_pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "app-web is Running"
    else
        fail_with_cmd "app-web is $phase (expected Running)" \
            "kubectl describe pod $app_pod -n $ns"
    fi

    node=$(get_node "$app_pod" "$ns")
    if [[ "$node" != "$reserved_node" ]]; then
        pass "app-web is on $node (not on reserved node)"
    else
        fail_with_cmd "app-web is on $reserved_node (should not be on reserved node)" \
            "kubectl get pod $app_pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    if pod_has_toleration "$infra_pod" "$ns" "ex-4-1/reserved" "NoSchedule"; then
        pass "infra-agent has toleration for reserved node"
    else
        fail "infra-agent missing toleration"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Topology spread constraints ==="
    local ns="ex-4-2"
    local pods=("replica-1" "replica-2" "replica-3")

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check all pods exist and are Running
    local all_running=true
    for pod in "${pods[@]}"; do
        if ! pod_exists "$pod" "$ns"; then
            fail "Pod $pod not found"
            all_running=false
        else
            local phase
            phase=$(get_phase "$pod" "$ns")
            if [[ "$phase" != "Running" ]]; then
                fail "Pod $pod is $phase (expected Running)"
                all_running=false
            fi
        fi
    done

    if $all_running; then
        pass "All three pods are Running"
    else
        return
    fi

    # Count unique nodes
    local unique_count
    unique_count=$(count_unique_nodes "$ns" "app=ex-4-2-stateful")
    if [[ "$unique_count" -eq 3 ]]; then
        pass "All three pods are on different nodes"
    else
        fail_with_cmd "Pods are spread across $unique_count nodes (expected 3)" \
            "kubectl get pods -n $ns -l app=ex-4-2-stateful -o jsonpath='{range .items[*]}{.metadata.name}: {.spec.nodeName}{\"\n\"}{end}'"
    fi

    # Verify topology spread constraints
    if pod_has_topology_spread "replica-1" "$ns"; then
        pass "Pods have topology spread constraints configured"
    else
        fail_with_cmd "Pods do not have topology spread constraints" \
            "kubectl get pod replica-1 -n $ns -o jsonpath='{.spec.topologySpreadConstraints}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Pod affinity co-location ==="
    local ns="ex-4-3"
    local cache_pod="cache-server"
    local frontend_pod="frontend-server"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check both pods exist
    if ! pod_exists "$cache_pod" "$ns"; then
        fail "Pod $cache_pod not found"
        return
    fi

    if ! pod_exists "$frontend_pod" "$ns"; then
        fail "Pod $frontend_pod not found"
        return
    fi

    # Check both are Running
    local cache_phase
    cache_phase=$(get_phase "$cache_pod" "$ns")
    local frontend_phase
    frontend_phase=$(get_phase "$frontend_pod" "$ns")

    if [[ "$cache_phase" == "Running" && "$frontend_phase" == "Running" ]]; then
        pass "Both pods are Running"
    else
        fail "cache: $cache_phase, frontend: $frontend_phase (expected both Running)"
        return
    fi

    # Check they are on the same node
    local cache_node
    cache_node=$(get_node "$cache_pod" "$ns")
    local frontend_node
    frontend_node=$(get_node "$frontend_pod" "$ns")

    if [[ "$cache_node" == "$frontend_node" ]]; then
        pass "Both pods are on the same node ($cache_node)"
    else
        fail_with_cmd "cache on $cache_node, frontend on $frontend_node (should be same)" \
            "kubectl get pods -n $ns -o wide"
    fi

    # Verify pod affinity is configured
    if pod_has_pod_affinity "$frontend_pod" "$ns"; then
        pass "frontend-server has pod affinity configured"
    else
        fail_with_cmd "frontend-server does not have pod affinity" \
            "kubectl get pod $frontend_pod -n $ns -o jsonpath='{.spec.affinity.podAffinity}'"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Debug complex scheduling issue ==="
    local pod="secure-data-pod"
    local ns="ex-5-1"
    local target_node="scheduling-lab-worker2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | grep -A 10 Events"
        return
    fi

    local node
    node=$(get_node "$pod" "$ns")
    if [[ "$node" == "$target_node" ]]; then
        pass "Pod is on $target_node"
    else
        fail_with_cmd "Pod is on $node (expected $target_node)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    if node_has_taint "$target_node" "ex-5-1/sensitive" "NoSchedule"; then
        pass "Node still has taint (pod toleration was fixed)"
    else
        fail "Node taint was removed (should fix pod toleration)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug multiple pod scheduling issues ==="
    local ns="ex-5-2"
    local pod_a="worker-pod-a"
    local pod_b="worker-pod-b"
    local gpu_node="scheduling-lab-worker"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check worker-pod-a
    if ! pod_exists "$pod_a" "$ns"; then
        fail "Pod $pod_a not found"
        return
    fi

    local phase_a
    phase_a=$(get_phase "$pod_a" "$ns")
    if [[ "$phase_a" == "Running" ]]; then
        pass "worker-pod-a is Running"
    else
        fail_with_cmd "worker-pod-a is $phase_a (expected Running)" \
            "kubectl describe pod $pod_a -n $ns"
    fi

    local node_a
    node_a=$(get_node "$pod_a" "$ns")
    if [[ "$node_a" == "$gpu_node" ]]; then
        pass "worker-pod-a is on $gpu_node (GPU pool)"
    else
        fail_with_cmd "worker-pod-a is on $node_a (expected $gpu_node)" \
            "kubectl get pod $pod_a -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    # Check worker-pod-b
    if ! pod_exists "$pod_b" "$ns"; then
        fail "Pod $pod_b not found"
        return
    fi

    local phase_b
    phase_b=$(get_phase "$pod_b" "$ns")
    if [[ "$phase_b" == "Running" ]]; then
        pass "worker-pod-b is Running"
    else
        fail_with_cmd "worker-pod-b is $phase_b (expected Running)" \
            "kubectl describe pod $pod_b -n $ns"
    fi

    local node_b
    node_b=$(get_node "$pod_b" "$ns")
    if [[ "$node_b" == "scheduling-lab-worker2" || "$node_b" == "scheduling-lab-worker3" ]]; then
        pass "worker-pod-b is on $node_b (general pool)"
    else
        fail_with_cmd "worker-pod-b is on $node_b (expected worker2 or worker3)" \
            "kubectl get pod $pod_b -n $ns -o jsonpath='{.spec.nodeName}'"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Production topology ==="
    local ns="ex-5-3"
    local critical_pod="system-critical"
    local zone_a_pod="app-zone-a"
    local zone_b_pod="app-zone-b"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check system-critical
    if ! pod_exists "$critical_pod" "$ns"; then
        fail "Pod $critical_pod not found"
        return
    fi

    local phase
    phase=$(get_phase "$critical_pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "system-critical is Running"
    else
        fail_with_cmd "system-critical is $phase (expected Running)" \
            "kubectl describe pod $critical_pod -n $ns"
    fi

    local node
    node=$(get_node "$critical_pod" "$ns")
    if [[ "$node" == "scheduling-lab-worker3" ]]; then
        pass "system-critical is on scheduling-lab-worker3 (premium tier)"
    else
        fail_with_cmd "system-critical is on $node (expected worker3)" \
            "kubectl get pod $critical_pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    local priority
    priority=$(get_priority_class "$critical_pod" "$ns")
    if [[ "$priority" == "ex-5-3-high" ]]; then
        pass "system-critical has high priority class"
    else
        fail_with_cmd "system-critical priority is $priority (expected ex-5-3-high)" \
            "kubectl get pod $critical_pod -n $ns -o jsonpath='{.spec.priorityClassName}'"
    fi

    # Check app-zone-a
    if ! pod_exists "$zone_a_pod" "$ns"; then
        fail "Pod $zone_a_pod not found"
        return
    fi

    phase=$(get_phase "$zone_a_pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "app-zone-a is Running"
    else
        fail "app-zone-a is $phase (expected Running)"
    fi

    node=$(get_node "$zone_a_pod" "$ns")
    if [[ "$node" == "scheduling-lab-worker" ]]; then
        pass "app-zone-a is on scheduling-lab-worker (zone-a standard tier)"
    else
        fail_with_cmd "app-zone-a is on $node (expected worker)" \
            "kubectl get pod $zone_a_pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    priority=$(get_priority_class "$zone_a_pod" "$ns")
    if [[ "$priority" == "ex-5-3-low" ]]; then
        pass "app-zone-a has low priority class"
    else
        fail "app-zone-a priority is $priority (expected ex-5-3-low)"
    fi

    # Check app-zone-b
    if ! pod_exists "$zone_b_pod" "$ns"; then
        fail "Pod $zone_b_pod not found"
        return
    fi

    phase=$(get_phase "$zone_b_pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "app-zone-b is Running"
    else
        fail "app-zone-b is $phase (expected Running)"
    fi

    node=$(get_node "$zone_b_pod" "$ns")
    if [[ "$node" == "scheduling-lab-worker2" ]]; then
        pass "app-zone-b is on scheduling-lab-worker2 (zone-b)"
    else
        fail_with_cmd "app-zone-b is on $node (expected worker2)" \
            "kubectl get pod $zone_b_pod -n $ns -o jsonpath='{.spec.nodeName}'"
    fi

    priority=$(get_priority_class "$zone_b_pod" "$ns")
    if [[ "$priority" == "ex-5-3-low" ]]; then
        pass "app-zone-b has low priority class"
    else
        fail "app-zone-b priority is $priority (expected ex-5-3-low)"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic Single-Concept Tasks"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Multi-Concept Tasks"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Broken Configurations"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Complex Real-World Scenarios"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Advanced Debugging and Comprehensive Tasks"
    echo "###############################################"
    verify_5_1
    verify_5_2
    verify_5_3
}

print_summary() {
    echo ""
    echo "========================================"
    if [[ $FAILED_TESTS -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC} ($PASSED_TESTS/$TOTAL_TESTS)"
    else
        echo -e "${RED}Some tests failed.${NC} ($PASSED_TESTS passed, $FAILED_TESTS failed out of $TOTAL_TESTS)"
    fi
    echo "========================================"
}

main() {
    local target="${1:-}"

    if [[ -z "$target" ]]; then
        echo "Usage: $0 <exercise|level|all>"
        echo ""
        echo "Examples:"
        echo "  $0 1.1      # verify exercise 1.1"
        echo "  $0 1        # verify all Level 1 exercises"
        echo "  $0 all      # verify all exercises"
        exit 1
    fi

    case "$target" in
        1.1) verify_1_1 ;;
        1.2) verify_1_2 ;;
        1.3) verify_1_3 ;;
        2.1) verify_2_1 ;;
        2.2) verify_2_2 ;;
        2.3) verify_2_3 ;;
        3.1) verify_3_1 ;;
        3.2) verify_3_2 ;;
        3.3) verify_3_3 ;;
        4.1) verify_4_1 ;;
        4.2) verify_4_2 ;;
        4.3) verify_4_3 ;;
        5.1) verify_5_1 ;;
        5.2) verify_5_2 ;;
        5.3) verify_5_3 ;;
        1) verify_level_1 ;;
        2) verify_level_2 ;;
        3) verify_level_3 ;;
        4) verify_level_4 ;;
        5) verify_level_5 ;;
        all)
            verify_level_1
            verify_level_2
            verify_level_3
            verify_level_4
            verify_level_5
            ;;
        *)
            echo "Unknown target: $target"
            exit 1
            ;;
    esac

    print_summary

    # Exit with error if any tests failed
    [[ $FAILED_TESTS -eq 0 ]]
}

main "$@"
