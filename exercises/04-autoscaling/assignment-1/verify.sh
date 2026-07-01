#!/usr/bin/env bash
#
# verify.sh - Automated verification for autoscaling-homework.md
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

# Helper: check if HPA exists
hpa_exists() {
    local hpa=$1; local ns=$2
    kubectl get hpa "$hpa" -n "$ns" &>/dev/null
}

# Helper: check if deployment exists
deployment_exists() {
    local deploy=$1; local ns=$2
    kubectl get deployment "$deploy" -n "$ns" &>/dev/null
}

# Helper: check if statefulset exists
statefulset_exists() {
    local sts=$1; local ns=$2
    kubectl get statefulset "$sts" -n "$ns" &>/dev/null
}

# Helper: check if pod exists
pod_exists() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

# Helper: get HPA spec field
get_hpa_spec() {
    local hpa=$1; local ns=$2; local field=$3
    kubectl get hpa "$hpa" -n "$ns" -o jsonpath="{$field}" 2>/dev/null
}

# Helper: get HPA status field
get_hpa_status() {
    local hpa=$1; local ns=$2; local field=$3
    kubectl get hpa "$hpa" -n "$ns" -o jsonpath="{$field}" 2>/dev/null
}

# Helper: get deployment field
get_deployment_field() {
    local deploy=$1; local ns=$2; local field=$3
    kubectl get deployment "$deploy" -n "$ns" -o jsonpath="{$field}" 2>/dev/null
}

# Helper: get pod field
get_pod_field() {
    local pod=$1; local ns=$2; local field=$3
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{$field}" 2>/dev/null
}

# Helper: check HPA condition status
get_hpa_condition() {
    local hpa=$1; local ns=$2; local type=$3
    kubectl get hpa "$hpa" -n "$ns" \
      -o jsonpath="{.status.conditions[?(@.type=='$type')].status}" 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic CPU-based HPA ==="
    local hpa="web-hpa"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail_with_cmd "HPA $hpa not found in namespace $ns" \
            "kubectl get hpa -n $ns"
        return
    fi

    # Check target utilization
    local target
    target=$(get_hpa_spec "$hpa" "$ns" '.spec.metrics[0].resource.target.averageUtilization')
    if [[ "$target" == "50" ]]; then
        pass "CPU target utilization is 50%"
    else
        fail_with_cmd "CPU target utilization is $target (expected 50)" \
            "kubectl get hpa $hpa -n $ns -o jsonpath='{.spec.metrics[0]}'"
    fi

    # Check min/max replicas
    local min max
    min=$(get_hpa_spec "$hpa" "$ns" '.spec.minReplicas')
    max=$(get_hpa_spec "$hpa" "$ns" '.spec.maxReplicas')
    if [[ "$min" == "1" ]] && [[ "$max" == "4" ]]; then
        pass "Replica bounds are min=1, max=4"
    else
        fail "Replica bounds are min=$min, max=$max (expected 1/4)"
    fi

    # Wait for HPA to see metrics
    info "Waiting 30s for metrics..."
    sleep 30

    # Check that HPA has observed metrics
    local current_util
    current_util=$(get_hpa_status "$hpa" "$ns" '.status.currentMetrics[0].resource.current.averageUtilization')
    if [[ -n "$current_util" ]]; then
        pass "HPA has observed current utilization: ${current_util}%"
    else
        fail_with_cmd "HPA has not observed any metrics yet" \
            "kubectl describe hpa $hpa -n $ns | tail -20"
    fi

    # Check conditions
    local able_to_scale scaling_active
    able_to_scale=$(get_hpa_condition "$hpa" "$ns" "AbleToScale")
    scaling_active=$(get_hpa_condition "$hpa" "$ns" "ScalingActive")
    if [[ "$able_to_scale" == "True" ]]; then
        pass "AbleToScale condition is True"
    else
        fail "AbleToScale condition is $able_to_scale (expected True)"
    fi

    if [[ "$scaling_active" == "True" ]]; then
        pass "ScalingActive condition is True"
    else
        fail "ScalingActive condition is $scaling_active (expected True)"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Memory-based HPA ==="
    local hpa="cache-hpa"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail_with_cmd "HPA $hpa not found in namespace $ns" \
            "kubectl get hpa -n $ns"
        return
    fi

    # Check that the metric is memory
    local metric_name target_type target_util
    metric_name=$(get_hpa_spec "$hpa" "$ns" '.spec.metrics[0].resource.name')
    target_type=$(get_hpa_spec "$hpa" "$ns" '.spec.metrics[0].resource.target.type')
    target_util=$(get_hpa_spec "$hpa" "$ns" '.spec.metrics[0].resource.target.averageUtilization')

    if [[ "$metric_name" == "memory" ]]; then
        pass "Metric is memory"
    else
        fail "Metric is $metric_name (expected memory)"
    fi

    if [[ "$target_type" == "Utilization" ]] && [[ "$target_util" == "70" ]]; then
        pass "Target is Utilization=70"
    else
        fail "Target is $target_type=$target_util (expected Utilization=70)"
    fi

    # Check max replicas
    local max
    max=$(get_hpa_spec "$hpa" "$ns" '.spec.maxReplicas')
    if [[ "$max" == "5" ]]; then
        pass "Max replicas is 5"
    else
        fail "Max replicas is $max (expected 5)"
    fi

    info "Waiting 30s for metrics..."
    sleep 30

    # Check that memory metrics are being observed
    local current_metric
    current_metric=$(get_hpa_status "$hpa" "$ns" '.status.currentMetrics[0].resource.name')
    if [[ "$current_metric" == "memory" ]]; then
        pass "HPA is observing memory metrics"
    else
        fail_with_cmd "HPA current metric is $current_metric (expected memory)" \
            "kubectl describe hpa $hpa -n $ns"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: HPA with scale-down stabilization ==="
    local hpa="api-hpa"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail_with_cmd "HPA $hpa not found in namespace $ns" \
            "kubectl get hpa -n $ns"
        return
    fi

    # Check scale-down stabilization window
    local stab_window
    stab_window=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleDown.stabilizationWindowSeconds')
    if [[ "$stab_window" == "120" ]]; then
        pass "Scale-down stabilization window is 120 seconds"
    else
        fail_with_cmd "Scale-down stabilization window is $stab_window (expected 120)" \
            "kubectl get hpa $hpa -n $ns -o jsonpath='{.spec.behavior.scaleDown}'"
    fi

    # Check replica bounds
    local min max
    min=$(get_hpa_spec "$hpa" "$ns" '.spec.minReplicas')
    max=$(get_hpa_spec "$hpa" "$ns" '.spec.maxReplicas')
    if [[ "$min" == "1" ]] && [[ "$max" == "6" ]]; then
        pass "Replica bounds are min=1, max=6"
    else
        fail "Replica bounds are min=$min, max=$max (expected 1/6)"
    fi

    info "Waiting 30s for metrics..."
    sleep 30

    # Check AbleToScale condition
    local able_to_scale
    able_to_scale=$(get_hpa_condition "$hpa" "$ns" "AbleToScale")
    if [[ "$able_to_scale" == "True" ]]; then
        pass "AbleToScale condition is True"
    else
        fail_with_cmd "AbleToScale condition is $able_to_scale (expected True)" \
            "kubectl describe hpa $hpa -n $ns"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: HPA targeting StatefulSet ==="
    local hpa="worker-hpa"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail_with_cmd "HPA $hpa not found in namespace $ns" \
            "kubectl get hpa -n $ns"
        return
    fi

    # Check scaleTargetRef
    local kind name
    kind=$(get_hpa_spec "$hpa" "$ns" '.spec.scaleTargetRef.kind')
    name=$(get_hpa_spec "$hpa" "$ns" '.spec.scaleTargetRef.name')

    if [[ "$kind" == "StatefulSet" ]]; then
        pass "Target kind is StatefulSet"
    else
        fail "Target kind is $kind (expected StatefulSet)"
    fi

    if [[ "$name" == "worker" ]]; then
        pass "Target name is worker"
    else
        fail "Target name is $name (expected worker)"
    fi

    info "Waiting 30s for metrics..."
    sleep 30

    # Check ScalingActive condition
    local scaling_active
    scaling_active=$(get_hpa_condition "$hpa" "$ns" "ScalingActive")
    if [[ "$scaling_active" == "True" ]]; then
        pass "ScalingActive condition is True"
    else
        fail_with_cmd "ScalingActive condition is $scaling_active (expected True)" \
            "kubectl describe hpa $hpa -n $ns"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: In-place CPU resize without restart ==="
    local pod="sizer"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail_with_cmd "Pod $pod not found in namespace $ns" \
            "kubectl get pods -n $ns"
        return
    fi

    # Check CPU request
    local cpu_request
    cpu_request=$(get_pod_field "$pod" "$ns" '.spec.containers[0].resources.requests.cpu')
    if [[ "$cpu_request" == "250m" ]]; then
        pass "CPU request is 250m"
    else
        fail_with_cmd "CPU request is $cpu_request (expected 250m)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources}'"
    fi

    # Check CPU limit
    local cpu_limit
    cpu_limit=$(get_pod_field "$pod" "$ns" '.spec.containers[0].resources.limits.cpu')
    if [[ "$cpu_limit" == "750m" ]]; then
        pass "CPU limit is 750m"
    else
        fail "CPU limit is $cpu_limit (expected 750m)"
    fi

    # Check restart count (should be 0)
    if [[ -f /tmp/ex-2-2-restarts-before.txt ]]; then
        local before after
        before=$(cat /tmp/ex-2-2-restarts-before.txt)
        after=$(get_pod_field "$pod" "$ns" '.status.containerStatuses[0].restartCount')
        if [[ "$before" == "$after" ]]; then
            pass "Container was not restarted (count still $after)"
        else
            fail "Container was restarted (before: $before, after: $after)"
        fi
    else
        info "Restart count baseline file not found, skipping restart check"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: In-place memory resize with restart ==="
    local pod="memsizer"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail_with_cmd "Pod $pod not found in namespace $ns" \
            "kubectl get pods -n $ns"
        return
    fi

    # Check memory request
    local mem_request
    mem_request=$(get_pod_field "$pod" "$ns" '.spec.containers[0].resources.requests.memory')
    if [[ "$mem_request" == "128Mi" ]]; then
        pass "Memory request is 128Mi"
    else
        fail_with_cmd "Memory request is $mem_request (expected 128Mi)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources}'"
    fi

    # Check restart count (should be incremented)
    if [[ -f /tmp/ex-2-3-restarts-before.txt ]]; then
        local before after
        before=$(cat /tmp/ex-2-3-restarts-before.txt)
        after=$(get_pod_field "$pod" "$ns" '.status.containerStatuses[0].restartCount')
        if [[ "$after" -gt "$before" ]]; then
            pass "Container was restarted (before: $before, after: $after)"
        else
            fail "Container was not restarted (before: $before, after: $after)"
        fi
    else
        info "Restart count baseline file not found, skipping restart check"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix HPA unable to compute metrics ==="
    local hpa="svc-hpa"
    local deploy="svc"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail "HPA $hpa not found in namespace $ns"
        return
    fi

    info "Waiting 45s for metrics after fix..."
    sleep 45

    # Check that metrics are now being observed
    local current_util
    current_util=$(get_hpa_status "$hpa" "$ns" '.status.currentMetrics[0].resource.current.averageUtilization')
    if [[ -n "$current_util" ]]; then
        pass "HPA is now observing utilization: ${current_util}%"
    else
        fail_with_cmd "HPA still shows <unknown> utilization" \
            "kubectl describe hpa $hpa -n $ns | grep -A5 Conditions"
    fi

    # Check ScalingActive condition
    local scaling_active scaling_reason
    scaling_active=$(get_hpa_condition "$hpa" "$ns" "ScalingActive")
    scaling_reason=$(get_hpa_status "$hpa" "$ns" ".status.conditions[?(@.type=='ScalingActive')].reason")
    if [[ "$scaling_active" == "True" ]]; then
        pass "ScalingActive condition is True ($scaling_reason)"
    else
        fail_with_cmd "ScalingActive is $scaling_active (reason: $scaling_reason)" \
            "kubectl get deployment $deploy -n $ns -o jsonpath='{.spec.template.spec.containers[0].resources}'"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix HPA scaleTargetRef mismatch ==="
    local hpa="api2-hpa"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail "HPA $hpa not found in namespace $ns"
        return
    fi

    info "Waiting 30s after fix..."
    sleep 30

    # Check AbleToScale condition
    local able_to_scale
    able_to_scale=$(get_hpa_condition "$hpa" "$ns" "AbleToScale")
    if [[ "$able_to_scale" == "True" ]]; then
        pass "AbleToScale condition is True"
    else
        fail_with_cmd "AbleToScale is $able_to_scale (expected True)" \
            "kubectl describe hpa $hpa -n $ns | grep -A5 Conditions"
    fi

    # Check that scaleTargetRef.name is now correct
    local target_name
    target_name=$(get_hpa_spec "$hpa" "$ns" '.spec.scaleTargetRef.name')
    if [[ "$target_name" == "api2" ]]; then
        pass "ScaleTargetRef name is api2 (matches Deployment)"
    else
        fail "ScaleTargetRef name is $target_name (expected api2)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix missing CPU request ==="
    local hpa="load-hpa"
    local deploy="load"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail "HPA $hpa not found in namespace $ns"
        return
    fi

    # Wait for rollout to complete
    info "Waiting for deployment rollout..."
    kubectl rollout status deployment/load -n "$ns" --timeout=60s &>/dev/null || true

    info "Waiting 45s for metrics after fix..."
    sleep 45

    # Check ScalingActive condition
    local scaling_active
    scaling_active=$(get_hpa_condition "$hpa" "$ns" "ScalingActive")
    if [[ "$scaling_active" == "True" ]]; then
        pass "ScalingActive condition is True"
    else
        fail_with_cmd "ScalingActive is $scaling_active (expected True)" \
            "kubectl describe hpa $hpa -n $ns | tail -20"
    fi

    # Check current utilization
    local current_util
    current_util=$(get_hpa_status "$hpa" "$ns" '.status.currentMetrics[0].resource.current.averageUtilization')
    if [[ -n "$current_util" ]]; then
        pass "HPA is observing utilization: ${current_util}%"
    else
        fail "HPA has not observed utilization metrics"
    fi

    # Confirm deployment now has CPU request
    local cpu_request
    cpu_request=$(get_deployment_field "$deploy" "$ns" '.spec.template.spec.containers[0].resources.requests.cpu')
    if [[ -n "$cpu_request" ]]; then
        pass "Deployment pod template has CPU request: $cpu_request"
    else
        fail "Deployment pod template still has no CPU request"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Multi-metric HPA ==="
    local hpa="multi-hpa"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail_with_cmd "HPA $hpa not found in namespace $ns" \
            "kubectl get hpa -n $ns"
        return
    fi

    # Check that there are exactly two metrics
    local metrics_count
    metrics_count=$(kubectl get hpa "$hpa" -n "$ns" -o jsonpath='{range .spec.metrics[*]}{.resource.name}{"\n"}{end}' 2>/dev/null | wc -l)
    if [[ "$metrics_count" -ge 2 ]]; then
        pass "HPA has multiple metrics (count: $metrics_count)"
    else
        fail "HPA has only $metrics_count metric(s) (expected 2)"
    fi

    # Check replica bounds
    local min max
    min=$(get_hpa_spec "$hpa" "$ns" '.spec.minReplicas')
    max=$(get_hpa_spec "$hpa" "$ns" '.spec.maxReplicas')
    if [[ "$min" == "2" ]] && [[ "$max" == "8" ]]; then
        pass "Replica bounds are min=2, max=8"
    else
        fail "Replica bounds are min=$min, max=$max (expected 2/8)"
    fi

    info "Waiting 30s for metrics..."
    sleep 30

    # Check that both metrics are being observed
    local current_metrics
    current_metrics=$(kubectl get hpa "$hpa" -n "$ns" -o jsonpath='{range .status.currentMetrics[*]}{.resource.name}{"\n"}{end}' 2>/dev/null)
    if echo "$current_metrics" | grep -q "cpu" && echo "$current_metrics" | grep -q "memory"; then
        pass "Both CPU and memory metrics are being observed"
    else
        fail_with_cmd "Not all metrics are being observed" \
            "kubectl get hpa $hpa -n $ns -o jsonpath='{.status.currentMetrics}'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: HPA with custom scale-up/down behavior ==="
    local hpa="burst-hpa"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail_with_cmd "HPA $hpa not found in namespace $ns" \
            "kubectl get hpa -n $ns"
        return
    fi

    # Check scale-up stabilization (should be 0)
    local scaleup_stab
    scaleup_stab=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleUp.stabilizationWindowSeconds')
    if [[ "$scaleup_stab" == "0" ]]; then
        pass "Scale-up stabilization is 0 seconds"
    else
        fail "Scale-up stabilization is $scaleup_stab (expected 0)"
    fi

    # Check scale-down stabilization (should be 300)
    local scaledown_stab
    scaledown_stab=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleDown.stabilizationWindowSeconds')
    if [[ "$scaledown_stab" == "300" ]]; then
        pass "Scale-down stabilization is 300 seconds"
    else
        fail "Scale-down stabilization is $scaledown_stab (expected 300)"
    fi

    # Check scale-down policy
    local scaledown_type scaledown_value scaledown_period
    scaledown_type=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleDown.policies[0].type')
    scaledown_value=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleDown.policies[0].value')
    scaledown_period=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleDown.policies[0].periodSeconds')
    if [[ "$scaledown_type" == "Percent" ]] && [[ "$scaledown_value" == "10" ]] && [[ "$scaledown_period" == "60" ]]; then
        pass "Scale-down policy is Percent=10 per 60 seconds"
    else
        fail "Scale-down policy is $scaledown_type=$scaledown_value per $scaledown_period (expected Percent=10/60)"
    fi

    info "Waiting 30s for metrics..."
    sleep 30

    local scaling_active
    scaling_active=$(get_hpa_condition "$hpa" "$ns" "ScalingActive")
    if [[ "$scaling_active" == "True" ]]; then
        pass "ScalingActive condition is True"
    else
        fail "ScalingActive is $scaling_active (expected True)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: HPA with in-place resize ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Find the lowest-ordinal pod
    local target
    target=$(kubectl get pods -n "$ns" -l app=combo -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    if [[ -z "$target" ]]; then
        fail_with_cmd "No combo pods found in namespace $ns" \
            "kubectl get pods -n $ns -l app=combo"
        return
    fi

    info "Checking target pod: $target"

    # Check CPU request
    local cpu_request
    cpu_request=$(get_pod_field "$target" "$ns" '.spec.containers[0].resources.requests.cpu')
    if [[ "$cpu_request" == "200m" ]]; then
        pass "Pod $target has CPU request of 200m"
    else
        fail_with_cmd "Pod $target has CPU request of $cpu_request (expected 200m)" \
            "kubectl get pod $target -n $ns -o jsonpath='{.spec.containers[0].resources}'"
    fi

    # Check restart count (should be 0)
    local restart_count
    restart_count=$(get_pod_field "$target" "$ns" '.status.containerStatuses[0].restartCount')
    if [[ "$restart_count" == "0" ]]; then
        pass "Container was not restarted (count: 0)"
    else
        fail "Container was restarted (count: $restart_count, expected 0)"
    fi

    # Check for HPA scale-up evidence in events
    local scale_events
    scale_events=$(kubectl describe hpa combo-hpa -n "$ns" 2>/dev/null | grep -E 'ScalingReplicaSet|New size' | head -3)
    if [[ -n "$scale_events" ]]; then
        pass "HPA scale-up events found"
    else
        info "No explicit scale-up events found (may not have scaled yet)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: SLA-driven HPA design ==="
    local hpa="sla-hpa"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail_with_cmd "HPA $hpa not found in namespace $ns" \
            "kubectl get hpa -n $ns"
        return
    fi

    # Check replica bounds and target
    local min max target
    min=$(get_hpa_spec "$hpa" "$ns" '.spec.minReplicas')
    max=$(get_hpa_spec "$hpa" "$ns" '.spec.maxReplicas')
    target=$(get_hpa_spec "$hpa" "$ns" '.spec.metrics[0].resource.target.averageUtilization')
    if [[ "$min" == "3" ]] && [[ "$max" == "30" ]] && [[ "$target" == "70" ]]; then
        pass "Bounds are min=3, max=30, target=70%"
    else
        fail "Bounds are min=$min, max=$max, target=$target (expected 3/30/70)"
    fi

    # Check scale-up stabilization and selectPolicy
    local scaleup_stab scaleup_policy
    scaleup_stab=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleUp.stabilizationWindowSeconds')
    scaleup_policy=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleUp.selectPolicy')
    if [[ "$scaleup_stab" == "0" ]]; then
        pass "Scale-up stabilization is 0 seconds"
    else
        fail "Scale-up stabilization is $scaleup_stab (expected 0)"
    fi

    if [[ "$scaleup_policy" == "Max" ]]; then
        pass "Scale-up selectPolicy is Max"
    else
        fail "Scale-up selectPolicy is $scaleup_policy (expected Max)"
    fi

    # Check that scale-up has both Percent and Pods policies
    local policies
    policies=$(kubectl get hpa "$hpa" -n "$ns" -o jsonpath='{range .spec.behavior.scaleUp.policies[*]}{.type}={.value}/{.periodSeconds}{"\n"}{end}' 2>/dev/null | sort)
    if echo "$policies" | grep -q "Percent=100/15" && echo "$policies" | grep -q "Pods=4/15"; then
        pass "Scale-up has both Percent=100/15 and Pods=4/15 policies"
    else
        fail_with_cmd "Scale-up policies are not as expected" \
            "kubectl get hpa $hpa -n $ns -o jsonpath='{.spec.behavior.scaleUp.policies}'"
    fi

    # Check scale-down window and policy
    local scaledown_stab scaledown_policy
    scaledown_stab=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleDown.stabilizationWindowSeconds')
    scaledown_policy=$(kubectl get hpa "$hpa" -n "$ns" -o jsonpath='{.spec.behavior.scaleDown.policies[0].type}={.spec.behavior.scaleDown.policies[0].value}/{.spec.behavior.scaleDown.policies[0].periodSeconds}' 2>/dev/null)
    if [[ "$scaledown_stab" == "300" ]]; then
        pass "Scale-down stabilization is 300 seconds"
    else
        fail "Scale-down stabilization is $scaledown_stab (expected 300)"
    fi

    if [[ "$scaledown_policy" == "Percent=20/60" ]]; then
        pass "Scale-down policy is Percent=20/60"
    else
        fail "Scale-down policy is $scaledown_policy (expected Percent=20/60)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Fix HPA flapping ==="
    local hpa="flap-hpa"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! hpa_exists "$hpa" "$ns"; then
        fail "HPA $hpa not found in namespace $ns"
        return
    fi

    # Check scale-down stabilization (should be >= 180)
    local scaledown_stab
    scaledown_stab=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleDown.stabilizationWindowSeconds')
    if [[ -n "$scaledown_stab" ]] && [[ "$scaledown_stab" -ge 180 ]]; then
        pass "Scale-down stabilization is $scaledown_stab seconds (>= 180)"
    else
        fail "Scale-down stabilization is $scaledown_stab (expected >= 180)"
    fi

    # Check scale-down policy
    local scaledown_policy
    scaledown_policy=$(kubectl get hpa "$hpa" -n "$ns" -o jsonpath='{.spec.behavior.scaleDown.policies[0].type}={.spec.behavior.scaleDown.policies[0].value}/{.spec.behavior.scaleDown.policies[0].periodSeconds}' 2>/dev/null)
    if [[ "$scaledown_policy" == "Percent=10/60" ]]; then
        pass "Scale-down policy is Percent=10/60"
    else
        fail "Scale-down policy is $scaledown_policy (expected Percent=10/60)"
    fi

    # Check scale-up stabilization (should still be 0)
    local scaleup_stab
    scaleup_stab=$(get_hpa_spec "$hpa" "$ns" '.spec.behavior.scaleUp.stabilizationWindowSeconds')
    if [[ "$scaleup_stab" == "0" ]]; then
        pass "Scale-up stabilization remains 0 seconds"
    else
        fail "Scale-up stabilization is $scaleup_stab (expected 0)"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: VPA YAML authoring ==="
    local vpa_file="/tmp/ex-5-3-vpa.yaml"

    if [[ ! -f "$vpa_file" ]]; then
        fail "VPA file $vpa_file does not exist"
        return
    fi

    pass "VPA file exists"

    # Check apiVersion
    if grep -q 'apiVersion: autoscaling.k8s.io/v1' "$vpa_file"; then
        pass "apiVersion is autoscaling.k8s.io/v1"
    else
        fail "apiVersion is not autoscaling.k8s.io/v1"
    fi

    # Check kind
    if grep -q 'kind: VerticalPodAutoscaler' "$vpa_file"; then
        pass "kind is VerticalPodAutoscaler"
    else
        fail "kind is not VerticalPodAutoscaler"
    fi

    # Check updateMode
    if grep -q 'updateMode: "Off"' "$vpa_file" || grep -q "updateMode: 'Off'" "$vpa_file" || grep -q "updateMode: Off" "$vpa_file"; then
        pass "updateMode is Off"
    else
        fail "updateMode is not Off"
    fi

    # Check controlledResources
    if grep -q 'controlledResources' "$vpa_file"; then
        pass "controlledResources field is present"
    else
        fail "controlledResources field is missing"
    fi

    # Dry-run validation
    local dryrun_output
    dryrun_output=$(kubectl apply --dry-run=client --validate=false -f "$vpa_file" 2>&1)
    if echo "$dryrun_output" | grep -q "verticalpodautoscaler.autoscaling.k8s.io/vpa-target-vpa"; then
        pass "VPA passes client-side dry-run validation"
    else
        fail_with_cmd "VPA does not pass dry-run validation" \
            "kubectl apply --dry-run=client --validate=false -f $vpa_file"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: HPA Basics"
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
    echo "# Level 3: Debugging"
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
    echo "# Level 5: Advanced"
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
