#!/usr/bin/env bash
#
# verify.sh - Automated verification for pod-resources-qos-homework.md
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

# Helper: get QoS class
get_qos_class() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.qosClass}' 2>/dev/null
}

# Helper: get CPU request
get_cpu_request() {
    local pod=$1
    local ns=$2
    local index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$index].resources.requests.cpu}" 2>/dev/null
}

# Helper: get CPU limit
get_cpu_limit() {
    local pod=$1
    local ns=$2
    local index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$index].resources.limits.cpu}" 2>/dev/null
}

# Helper: get memory request
get_memory_request() {
    local pod=$1
    local ns=$2
    local index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$index].resources.requests.memory}" 2>/dev/null
}

# Helper: get memory limit
get_memory_limit() {
    local pod=$1
    local ns=$2
    local index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$index].resources.limits.memory}" 2>/dev/null
}

# Helper: get ephemeral-storage request
get_ephemeral_request() {
    local pod=$1
    local ns=$2
    local index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$index].resources.requests.ephemeral-storage}" 2>/dev/null
}

# Helper: get ephemeral-storage limit
get_ephemeral_limit() {
    local pod=$1
    local ns=$2
    local index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$index].resources.limits.ephemeral-storage}" 2>/dev/null
}

# Helper: get all resources for a container
get_resources() {
    local pod=$1
    local ns=$2
    local index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$index].resources}" 2>/dev/null
}

# Helper: get restart count
get_restart_count() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null
}

# Helper: check if limitrange exists
limitrange_exists() {
    local lr=$1
    local ns=$2
    kubectl get limitrange "$lr" -n "$ns" &>/dev/null
}

# Helper: check if resourcequota exists
resourcequota_exists() {
    local rq=$1
    local ns=$2
    kubectl get resourcequota "$rq" -n "$ns" &>/dev/null
}

# Helper: get resourcequota used pods
get_quota_used_pods() {
    local rq=$1
    local ns=$2
    kubectl get resourcequota "$rq" -n "$ns" -o jsonpath='{.status.used.pods}' 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Pod with no resources (BestEffort) ==="
    local pod="bare-pod"
    local ns="ex-1-1"

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
            "kubectl get pod $pod -n $ns"
    fi

    local qos
    qos=$(get_qos_class "$pod" "$ns")
    if [[ "$qos" == "BestEffort" ]]; then
        pass "QoS class is BestEffort"
    else
        fail_with_cmd "QoS class is $qos (expected BestEffort)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi

    local resources
    resources=$(get_resources "$pod" "$ns")
    if [[ -z "$resources" ]] || [[ "$resources" == "{}" ]]; then
        pass "Resources field is empty"
    else
        fail_with_cmd "Resources field is not empty: $resources" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources}'"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Pod with memory request and limit (Burstable) ==="
    local pod="mem-pod"
    local ns="ex-1-2"

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
            "kubectl get pod $pod -n $ns"
    fi

    local qos
    qos=$(get_qos_class "$pod" "$ns")
    if [[ "$qos" == "Burstable" ]]; then
        pass "QoS class is Burstable"
    else
        fail_with_cmd "QoS class is $qos (expected Burstable)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi

    local mem_req
    mem_req=$(get_memory_request "$pod" "$ns")
    if [[ "$mem_req" == "128Mi" ]]; then
        pass "Memory request is 128Mi"
    else
        fail_with_cmd "Memory request is $mem_req (expected 128Mi)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.memory}'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Pod with requests == limits (Guaranteed) ==="
    local pod="cpu-equal"
    local ns="ex-1-3"

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
            "kubectl get pod $pod -n $ns"
    fi

    local qos
    qos=$(get_qos_class "$pod" "$ns")
    if [[ "$qos" == "Guaranteed" ]]; then
        pass "QoS class is Guaranteed"
    else
        fail_with_cmd "QoS class is $qos (expected Guaranteed)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi

    local cpu_req
    cpu_req=$(get_cpu_request "$pod" "$ns")
    local cpu_lim
    cpu_lim=$(get_cpu_limit "$pod" "$ns")
    if [[ "$cpu_req" == "250m" ]] && [[ "$cpu_lim" == "250m" ]]; then
        pass "CPU request == CPU limit (250m)"
    else
        fail_with_cmd "CPU request=$cpu_req limit=$cpu_lim (expected both 250m)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources}'"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Limits-only pod (Guaranteed via auto-fill) ==="
    local pod="limits-only"
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
            "kubectl get pod $pod -n $ns"
    fi

    local qos
    qos=$(get_qos_class "$pod" "$ns")
    if [[ "$qos" == "Guaranteed" ]]; then
        pass "QoS class is Guaranteed"
    else
        fail_with_cmd "QoS class is $qos (expected Guaranteed)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi

    local cpu_req
    cpu_req=$(get_cpu_request "$pod" "$ns")
    if [[ "$cpu_req" == "500m" ]]; then
        pass "CPU request is 500m (auto-filled from limit)"
    else
        fail_with_cmd "CPU request is $cpu_req (expected 500m)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.cpu}'"
    fi

    local mem_req
    mem_req=$(get_memory_request "$pod" "$ns")
    if [[ "$mem_req" == "256Mi" ]]; then
        pass "Memory request is 256Mi (auto-filled from limit)"
    else
        fail_with_cmd "Memory request is $mem_req (expected 256Mi)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.memory}'"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Two-container pod with mixed QoS ==="
    local pod="mixed-qos"
    local ns="ex-2-2"

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
            "kubectl get pod $pod -n $ns"
    fi

    local qos
    qos=$(get_qos_class "$pod" "$ns")
    if [[ "$qos" == "Burstable" ]]; then
        pass "QoS class is Burstable (one container has no resources)"
    else
        fail_with_cmd "QoS class is $qos (expected Burstable)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi

    local main_resources
    main_resources=$(get_resources "$pod" "$ns" 0)
    if [[ -n "$main_resources" ]] && [[ "$main_resources" != "{}" ]]; then
        pass "Container 'main' has resources"
    else
        fail_with_cmd "Container 'main' has no resources" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources}'"
    fi

    local helper_resources
    helper_resources=$(get_resources "$pod" "$ns" 1)
    if [[ -z "$helper_resources" ]] || [[ "$helper_resources" == "{}" ]]; then
        pass "Container 'helper' has no resources"
    else
        fail_with_cmd "Container 'helper' has resources (expected none): $helper_resources" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[1].resources}'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Pod with CPU, memory, and ephemeral-storage ==="
    local pod="triple-resource"
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
            "kubectl get pod $pod -n $ns"
    fi

    local qos
    qos=$(get_qos_class "$pod" "$ns")
    if [[ "$qos" == "Burstable" ]]; then
        pass "QoS class is Burstable"
    else
        fail_with_cmd "QoS class is $qos (expected Burstable)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi

    local cpu_req
    cpu_req=$(get_cpu_request "$pod" "$ns")
    if [[ "$cpu_req" == "100m" ]]; then
        pass "CPU request is 100m"
    else
        fail_with_cmd "CPU request is $cpu_req (expected 100m)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.cpu}'"
    fi

    local mem_lim
    mem_lim=$(get_memory_limit "$pod" "$ns")
    if [[ "$mem_lim" == "128Mi" ]]; then
        pass "Memory limit is 128Mi"
    else
        fail_with_cmd "Memory limit is $mem_lim (expected 128Mi)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.memory}'"
    fi

    local eph_req
    eph_req=$(get_ephemeral_request "$pod" "$ns")
    if [[ "$eph_req" == "50Mi" ]]; then
        pass "Ephemeral-storage request is 50Mi"
    else
        fail_with_cmd "Ephemeral-storage request is $eph_req (expected 50Mi)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.ephemeral-storage}'"
    fi

    local eph_lim
    eph_lim=$(get_ephemeral_limit "$pod" "$ns")
    if [[ "$eph_lim" == "100Mi" ]]; then
        pass "Ephemeral-storage limit is 100Mi"
    else
        fail_with_cmd "Ephemeral-storage limit is $eph_lim (expected 100Mi)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.ephemeral-storage}'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix OOMKilled pod ==="
    local pod="broken-app"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5  # Allow time for stability

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local restarts
    restarts=$(get_restart_count "$pod" "$ns")
    if [[ "$restarts" == "0" ]]; then
        pass "Restart count is 0"
    else
        fail_with_cmd "Restart count is $restarts (expected 0)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.containerStatuses[0].restartCount}'"
    fi

    # Wait 60 seconds and verify it's still running
    sleep 60

    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod still Running after 60 seconds"
    else
        fail "Pod phase is $phase after 60 seconds"
    fi

    restarts=$(get_restart_count "$pod" "$ns")
    if [[ "$restarts" == "0" ]]; then
        pass "Restart count still 0 after 60 seconds"
    else
        fail "Restart count is $restarts after 60 seconds"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix LimitRange violation ==="
    local pod="policy-app"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! limitrange_exists "strict-limits" "$ns"; then
        fail "LimitRange strict-limits not found in namespace $ns"
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
            "kubectl get pod $pod -n $ns"
        return
    fi

    local cpu_lim
    cpu_lim=$(get_cpu_limit "$pod" "$ns")
    # Convert to numeric for comparison (remove 'm' suffix)
    local cpu_lim_val="${cpu_lim%m}"
    if [[ -z "$cpu_lim_val" ]]; then
        cpu_lim_val="${cpu_lim%\"}"  # Handle full CPU like "1"
        cpu_lim_val="${cpu_lim_val//[^0-9]/}"
        cpu_lim_val=$((cpu_lim_val * 1000))
    fi

    if [[ "$cpu_lim" == "1" ]] || [[ "$cpu_lim_val" -le 1000 ]]; then
        pass "CPU limit ($cpu_lim) is within LimitRange max (1)"
    else
        fail_with_cmd "CPU limit ($cpu_lim) exceeds LimitRange max (1)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.cpu}'"
    fi

    local mem_lim
    mem_lim=$(get_memory_limit "$pod" "$ns")
    if [[ "$mem_lim" == "512Mi" ]] || [[ "$mem_lim" =~ ^[0-9]+(Mi|M)$ ]]; then
        pass "Memory limit ($mem_lim) is within LimitRange max (512Mi)"
    else
        fail_with_cmd "Memory limit ($mem_lim) may exceed LimitRange max (512Mi)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.memory}'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix ResourceQuota violation ==="
    local pod="team-app"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! resourcequota_exists "team-quota" "$ns"; then
        fail "ResourceQuota team-quota not found in namespace $ns"
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
            "kubectl get pod $pod -n $ns"
        return
    fi

    local cpu_lim
    cpu_lim=$(get_cpu_limit "$pod" "$ns")
    if [[ -n "$cpu_lim" ]]; then
        pass "Pod has CPU limit set ($cpu_lim)"
    else
        fail_with_cmd "Pod missing CPU limit (required by ResourceQuota)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.cpu}'"
    fi

    local mem_lim
    mem_lim=$(get_memory_limit "$pod" "$ns")
    if [[ -n "$mem_lim" ]]; then
        pass "Pod has memory limit set ($mem_lim)"
    else
        fail_with_cmd "Pod missing memory limit (required by ResourceQuota)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.memory}'"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: LimitRange, ResourceQuota, and multiple pods ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! limitrange_exists "ns-limits" "$ns"; then
        fail "LimitRange ns-limits not found in namespace $ns"
        return
    else
        pass "LimitRange ns-limits exists"
    fi

    if ! resourcequota_exists "ns-quota" "$ns"; then
        fail "ResourceQuota ns-quota not found in namespace $ns"
        return
    else
        pass "ResourceQuota ns-quota exists"
    fi

    local default_pod="default-pod"
    if ! pod_exists "$default_pod" "$ns"; then
        fail "Pod $default_pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$default_pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "default-pod is Running"
    else
        fail_with_cmd "default-pod phase is $phase (expected Running)" \
            "kubectl get pod $default_pod -n $ns"
    fi

    local qos
    qos=$(get_qos_class "$default_pod" "$ns")
    if [[ "$qos" == "Burstable" ]]; then
        pass "default-pod QoS is Burstable"
    else
        fail_with_cmd "default-pod QoS is $qos (expected Burstable)" \
            "kubectl get pod $default_pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi

    local explicit_pod="explicit-pod"
    if pod_exists "$explicit_pod" "$ns"; then
        phase=$(get_phase "$explicit_pod" "$ns")
        if [[ "$phase" == "Running" ]]; then
            pass "explicit-pod is Running"
        else
            fail "explicit-pod phase is $phase (expected Running)"
        fi

        qos=$(get_qos_class "$explicit_pod" "$ns")
        if [[ "$qos" == "Burstable" ]]; then
            pass "explicit-pod QoS is Burstable"
        else
            fail "explicit-pod QoS is $qos (expected Burstable)"
        fi
    else
        info "explicit-pod not found (optional)"
    fi

    local over_quota_pod="over-quota-pod"
    if pod_exists "$over_quota_pod" "$ns"; then
        fail "over-quota-pod exists (should have been rejected)"
    else
        pass "over-quota-pod was rejected (as expected)"
    fi

    local used_pods
    used_pods=$(get_quota_used_pods "ns-quota" "$ns")
    if [[ "$used_pods" == "2" ]] || [[ "$used_pods" == "1" ]]; then
        pass "ResourceQuota shows $used_pods pod(s) used"
    else
        info "ResourceQuota shows $used_pods pods used"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Production workload sizing ==="
    local pod="api-server"
    local ns="ex-4-2"

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
            "kubectl get pod $pod -n $ns"
    fi

    local mem_req
    mem_req=$(get_memory_request "$pod" "$ns")
    if [[ "$mem_req" == "400Mi" ]]; then
        pass "Memory request is 400Mi (matches steady-state)"
    else
        fail_with_cmd "Memory request is $mem_req (expected 400Mi for steady-state)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.memory}'"
    fi

    local mem_lim
    mem_lim=$(get_memory_limit "$pod" "$ns")
    if [[ "$mem_lim" == "600Mi" ]]; then
        pass "Memory limit is 600Mi (accommodates burst)"
    else
        fail_with_cmd "Memory limit is $mem_lim (expected 600Mi for burst)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.memory}'"
    fi

    local cpu_req
    cpu_req=$(get_cpu_request "$pod" "$ns")
    if [[ "$cpu_req" == "250m" ]]; then
        pass "CPU request is 250m (matches steady-state)"
    else
        fail_with_cmd "CPU request is $cpu_req (expected 250m for steady-state)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.cpu}'"
    fi

    local cpu_lim
    cpu_lim=$(get_cpu_limit "$pod" "$ns")
    if [[ "$cpu_lim" == "500m" ]]; then
        pass "CPU limit is 500m (accommodates burst)"
    else
        fail_with_cmd "CPU limit is $cpu_lim (expected 500m for burst)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.cpu}'"
    fi

    local qos
    qos=$(get_qos_class "$pod" "$ns")
    if [[ "$qos" == "Burstable" ]] || [[ "$qos" == "Guaranteed" ]]; then
        pass "QoS class is $qos (appropriate for production)"
    else
        fail_with_cmd "QoS class is $qos (expected Burstable or Guaranteed)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Multi-container resource profiles ==="
    local pod="multi-profile"
    local ns="ex-4-3"

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
            "kubectl get pod $pod -n $ns"
    fi

    local web_cpu_req
    web_cpu_req=$(get_cpu_request "$pod" "$ns" 0)
    if [[ "$web_cpu_req" == "200m" ]]; then
        pass "Container 'web' CPU request is 200m"
    else
        fail_with_cmd "Container 'web' CPU request is $web_cpu_req (expected 200m)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.cpu}'"
    fi

    local shipper_cpu_req
    shipper_cpu_req=$(get_cpu_request "$pod" "$ns" 1)
    if [[ "$shipper_cpu_req" == "50m" ]]; then
        pass "Container 'log-shipper' CPU request is 50m"
    else
        fail_with_cmd "Container 'log-shipper' CPU request is $shipper_cpu_req (expected 50m)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[1].resources.requests.cpu}'"
    fi

    local web_mem_lim
    web_mem_lim=$(get_memory_limit "$pod" "$ns" 0)
    if [[ "$web_mem_lim" == "512Mi" ]]; then
        pass "Container 'web' memory limit is 512Mi"
    else
        fail_with_cmd "Container 'web' memory limit is $web_mem_lim (expected 512Mi)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.limits.memory}'"
    fi

    local shipper_mem_lim
    shipper_mem_lim=$(get_memory_limit "$pod" "$ns" 1)
    if [[ "$shipper_mem_lim" == "64Mi" ]]; then
        pass "Container 'log-shipper' memory limit is 64Mi"
    else
        fail_with_cmd "Container 'log-shipper' memory limit is $shipper_mem_lim (expected 64Mi)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[1].resources.limits.memory}'"
    fi

    local qos
    qos=$(get_qos_class "$pod" "$ns")
    if [[ "$qos" == "Burstable" ]]; then
        pass "QoS class is Burstable"
    else
        fail_with_cmd "QoS class is $qos (expected Burstable)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multiple interacting policy issues ==="
    local pod="team-app"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! limitrange_exists "team-limits" "$ns"; then
        fail "LimitRange team-limits not found in namespace $ns"
        return
    else
        pass "LimitRange team-limits exists"
    fi

    if ! resourcequota_exists "team-quota" "$ns"; then
        fail "ResourceQuota team-quota not found in namespace $ns"
        return
    else
        pass "ResourceQuota team-quota exists"
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
            "kubectl get pod $pod -n $ns"
        return
    fi

    local cpu_lim
    cpu_lim=$(get_cpu_limit "$pod" "$ns")
    local cpu_req
    cpu_req=$(get_cpu_request "$pod" "$ns")

    if [[ -n "$cpu_lim" ]] && [[ -n "$cpu_req" ]]; then
        pass "Pod has CPU request ($cpu_req) and limit ($cpu_lim)"
    else
        fail_with_cmd "Pod missing CPU resources" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources}'"
    fi

    local mem_lim
    mem_lim=$(get_memory_limit "$pod" "$ns")
    local mem_req
    mem_req=$(get_memory_request "$pod" "$ns")

    if [[ -n "$mem_lim" ]] && [[ -n "$mem_req" ]]; then
        pass "Pod has memory request ($mem_req) and limit ($mem_lim)"
    else
        fail_with_cmd "Pod missing memory resources" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources}'"
    fi

    local used_pods
    used_pods=$(get_quota_used_pods "team-quota" "$ns")
    if [[ "$used_pods" == "1" ]]; then
        pass "ResourceQuota shows 1 pod used"
    else
        info "ResourceQuota shows $used_pods pods used"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Quota exhaustion with existing pods ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! resourcequota_exists "dev-quota" "$ns"; then
        fail "ResourceQuota dev-quota not found in namespace $ns"
        return
    fi

    if ! pod_exists "existing-1" "$ns"; then
        fail "Pod existing-1 not found"
        return
    fi

    if ! pod_exists "existing-2" "$ns"; then
        fail "Pod existing-2 not found"
        return
    fi

    local phase1
    phase1=$(get_phase "existing-1" "$ns")
    local phase2
    phase2=$(get_phase "existing-2" "$ns")

    if [[ "$phase1" == "Running" ]] && [[ "$phase2" == "Running" ]]; then
        pass "Existing pods still Running"
    else
        fail "Existing pods not Running (existing-1: $phase1, existing-2: $phase2)"
    fi

    if ! pod_exists "new-app" "$ns"; then
        fail "Pod new-app not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "new-app" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "new-app is Running"
    else
        fail_with_cmd "new-app phase is $phase (expected Running)" \
            "kubectl get pod new-app -n $ns"
        return
    fi

    local used_pods
    used_pods=$(get_quota_used_pods "dev-quota" "$ns")
    if [[ "$used_pods" == "3" ]]; then
        pass "ResourceQuota shows 3 pods used"
    else
        fail_with_cmd "ResourceQuota shows $used_pods pods (expected 3)" \
            "kubectl describe resourcequota dev-quota -n $ns"
    fi

    local new_cpu_req
    new_cpu_req=$(get_cpu_request "new-app" "$ns")
    local new_mem_req
    new_mem_req=$(get_memory_request "new-app" "$ns")

    if [[ -n "$new_cpu_req" ]] && [[ -n "$new_mem_req" ]]; then
        pass "new-app has reasonable resources (cpu: $new_cpu_req, mem: $new_mem_req)"
    else
        fail "new-app missing resource declarations"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Complete multi-tenant namespace ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! limitrange_exists "tenant-limits" "$ns"; then
        fail "LimitRange tenant-limits not found in namespace $ns"
        return
    else
        pass "LimitRange tenant-limits exists"
    fi

    if ! resourcequota_exists "tenant-quota" "$ns"; then
        fail "ResourceQuota tenant-quota not found in namespace $ns"
        return
    else
        pass "ResourceQuota tenant-quota exists"
    fi

    local pod="three-tier"
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
            "kubectl get pod $pod -n $ns"
        return
    fi

    local qos
    qos=$(get_qos_class "$pod" "$ns")
    if [[ "$qos" == "Burstable" ]]; then
        pass "QoS class is Burstable"
    else
        fail_with_cmd "QoS class is $qos (expected Burstable)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.qosClass}'"
    fi

    # Check frontend container
    local fe_cpu_req
    fe_cpu_req=$(get_cpu_request "$pod" "$ns" 0)
    if [[ "$fe_cpu_req" == "200m" ]]; then
        pass "Frontend CPU request is 200m"
    else
        fail_with_cmd "Frontend CPU request is $fe_cpu_req (expected 200m)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].resources.requests.cpu}'"
    fi

    # Check backend container
    local be_cpu_req
    be_cpu_req=$(get_cpu_request "$pod" "$ns" 1)
    if [[ "$be_cpu_req" == "500m" ]]; then
        pass "Backend CPU request is 500m"
    else
        fail_with_cmd "Backend CPU request is $be_cpu_req (expected 500m)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[1].resources.requests.cpu}'"
    fi

    # Check cache container
    local cache_cpu_req
    cache_cpu_req=$(get_cpu_request "$pod" "$ns" 2)
    if [[ "$cache_cpu_req" == "100m" ]]; then
        pass "Cache CPU request is 100m"
    else
        fail_with_cmd "Cache CPU request is $cache_cpu_req (expected 100m)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[2].resources.requests.cpu}'"
    fi

    local used_pods
    used_pods=$(get_quota_used_pods "tenant-quota" "$ns")
    if [[ "$used_pods" == "1" ]]; then
        pass "ResourceQuota shows 1 pod used"
    else
        info "ResourceQuota shows $used_pods pods used"
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
