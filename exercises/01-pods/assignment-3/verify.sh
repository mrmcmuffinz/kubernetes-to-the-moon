#!/usr/bin/env bash
#
# verify.sh - Automated verification for pod-health-observability-homework.md
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

# Helper: get pod ready status
get_ready() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null
}

# Helper: get restart count
get_restart_count() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null
}

# Helper: check if liveness probe exists (httpGet)
has_http_liveness_probe() {
    local pod=$1
    local ns=$2
    local result
    result=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].livenessProbe.httpGet}' 2>/dev/null)
    [[ -n "$result" ]]
}

# Helper: check if readiness probe exists (exec)
has_exec_readiness_probe() {
    local pod=$1
    local ns=$2
    local result
    result=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].readinessProbe.exec}' 2>/dev/null)
    [[ -n "$result" ]]
}

# Helper: check if startup probe exists
has_startup_probe() {
    local pod=$1
    local ns=$2
    local result
    result=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].startupProbe}' 2>/dev/null)
    [[ -n "$result" ]]
}

# Helper: get probe config value
get_probe_value() {
    local pod=$1
    local ns=$2
    local probe_type=$3  # livenessProbe, readinessProbe, startupProbe
    local field=$4       # periodSeconds, failureThreshold, etc.
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[0].${probe_type}.${field}}" 2>/dev/null
}

# Helper: get terminationGracePeriodSeconds
get_termination_grace() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.terminationGracePeriodSeconds}' 2>/dev/null
}

# Helper: check if preStop hook exists
has_prestop_hook() {
    local pod=$1
    local ns=$2
    local result
    result=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].lifecycle.preStop}' 2>/dev/null)
    [[ -n "$result" ]]
}

# Helper: check if postStart hook exists
has_poststart_hook() {
    local pod=$1
    local ns=$2
    local result
    result=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].lifecycle.postStart}' 2>/dev/null)
    [[ -n "$result" ]]
}

# Helper: get Ready condition status
get_ready_condition() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null
}

# Helper: check for Unhealthy events
has_unhealthy_events() {
    local ns=$1
    kubectl get events -n "$ns" --field-selector reason=Unhealthy 2>/dev/null | grep -q "Unhealthy"
}

# Helper: check logs contain string
logs_contain() {
    local pod=$1
    local ns=$2
    local pattern=$3
    local container=${4:-}

    if [[ -n "$container" ]]; then
        kubectl logs "$pod" -n "$ns" -c "$container" 2>/dev/null | grep -q "$pattern"
    else
        kubectl logs "$pod" -n "$ns" 2>/dev/null | grep -q "$pattern"
    fi
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: HTTP liveness probe ==="
    local pod="web-live"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Wait for probe to run
    sleep 30

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | tail -20"
        return
    fi

    if has_http_liveness_probe "$pod" "$ns"; then
        pass "HTTP liveness probe is configured"
    else
        fail_with_cmd "HTTP liveness probe not found" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].livenessProbe}'"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0 (probe succeeding)"
    else
        fail_with_cmd "restartCount is $restart_count (expected 0)" \
            "kubectl describe pod $pod -n $ns | grep -A 5 'Liveness:'"
    fi

    local ready
    ready=$(get_ready "$pod" "$ns")
    if [[ "$ready" == "true" ]]; then
        pass "Container is ready (1/1)"
    else
        fail "Container is not ready"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Exec readiness probe ==="
    local pod="ready-file"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Check initially not ready (within 15 seconds)
    sleep 5
    local ready_early
    ready_early=$(get_ready "$pod" "$ns")
    if [[ "$ready_early" == "false" ]]; then
        pass "Pod is NOT ready during file creation (0/1)"
    else
        info "Pod became ready faster than expected (timing may vary)"
    fi

    # After 30 seconds, should be ready
    sleep 25
    local ready_late
    ready_late=$(get_ready "$pod" "$ns")
    if [[ "$ready_late" == "true" ]]; then
        pass "Pod is ready after file creation (1/1)"
    else
        fail_with_cmd "Pod is not ready after 30 seconds" \
            "kubectl describe pod $pod -n $ns | tail -20"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0 (readiness failures do not restart)"
    else
        fail_with_cmd "restartCount is $restart_count (expected 0)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.containerStatuses[0]}'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: preStop lifecycle hook ==="
    local pod="graceful-stop"
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
        fail "Pod phase is $phase (expected Running)"
        return
    fi

    if has_prestop_hook "$pod" "$ns"; then
        pass "preStop hook is configured"
    else
        fail_with_cmd "preStop hook not found" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].lifecycle}'"
    fi

    # Delete and check logs
    info "Deleting pod to test preStop hook..."
    kubectl delete pod "$pod" -n "$ns" --wait=false &>/dev/null
    sleep 3

    if logs_contain "$pod" "$ns" "preStop hook executing"; then
        pass "Logs contain 'preStop hook executing'"
    else
        fail_with_cmd "preStop hook message not found in logs" \
            "kubectl logs $pod -n $ns"
    fi

    # Wait for full deletion
    kubectl wait --for=delete pod/"$pod" -n "$ns" --timeout=60s &>/dev/null || true
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Startup probe with liveness probe ==="
    local pod="slow-start"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Wait for startup to complete
    sleep 40

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | tail -20"
    fi

    if has_startup_probe "$pod" "$ns"; then
        pass "Startup probe is configured"
    else
        fail "Startup probe not found"
    fi

    local startup_period
    startup_period=$(get_probe_value "$pod" "$ns" "startupProbe" "periodSeconds")
    if [[ "$startup_period" == "2" ]]; then
        pass "Startup probe periodSeconds is 2"
    else
        fail "Startup probe periodSeconds is $startup_period (expected 2)"
    fi

    local startup_threshold
    startup_threshold=$(get_probe_value "$pod" "$ns" "startupProbe" "failureThreshold")
    if [[ "$startup_threshold" == "20" ]]; then
        pass "Startup probe failureThreshold is 20"
    else
        fail "Startup probe failureThreshold is $startup_threshold (expected 20)"
    fi

    local liveness_period
    liveness_period=$(get_probe_value "$pod" "$ns" "livenessProbe" "periodSeconds")
    if [[ "$liveness_period" == "10" ]]; then
        pass "Liveness probe periodSeconds is 10"
    else
        fail "Liveness probe periodSeconds is $liveness_period (expected 10)"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0"
    else
        fail "restartCount is $restart_count (expected 0)"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Dual probe with tuning ==="
    local pod="dual-probe"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Wait for readiness
    sleep 20

    local ready
    ready=$(get_ready "$pod" "$ns")
    if [[ "$ready" == "true" ]]; then
        pass "Pod is Running and Ready"
    else
        fail_with_cmd "Pod is not ready" \
            "kubectl describe pod $pod -n $ns | tail -20"
    fi

    local liveness_period
    liveness_period=$(get_probe_value "$pod" "$ns" "livenessProbe" "periodSeconds")
    if [[ "$liveness_period" == "15" ]]; then
        pass "Liveness probe periodSeconds is 15"
    else
        fail "Liveness probe periodSeconds is $liveness_period (expected 15)"
    fi

    local liveness_timeout
    liveness_timeout=$(get_probe_value "$pod" "$ns" "livenessProbe" "timeoutSeconds")
    if [[ "$liveness_timeout" == "3" ]]; then
        pass "Liveness probe timeoutSeconds is 3"
    else
        fail "Liveness probe timeoutSeconds is $liveness_timeout (expected 3)"
    fi

    local readiness_success
    readiness_success=$(get_probe_value "$pod" "$ns" "readinessProbe" "successThreshold")
    if [[ "$readiness_success" == "2" ]]; then
        pass "Readiness probe successThreshold is 2"
    else
        fail "Readiness probe successThreshold is $readiness_success (expected 2)"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0"
    else
        fail "restartCount is $restart_count (expected 0)"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: preStop hook with terminationGracePeriodSeconds ==="
    local pod="graceful-shutdown"
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
        fail "Pod phase is $phase (expected Running)"
        return
    fi

    local grace
    grace=$(get_termination_grace "$pod" "$ns")
    if [[ "$grace" == "30" ]]; then
        pass "terminationGracePeriodSeconds is 30"
    else
        fail "terminationGracePeriodSeconds is $grace (expected 30)"
    fi

    if has_prestop_hook "$pod" "$ns"; then
        pass "preStop hook is configured"
    else
        fail "preStop hook not found"
    fi

    # Time the deletion
    info "Deleting pod to test graceful shutdown (will take ~10s)..."
    local start_time=$SECONDS
    kubectl delete pod "$pod" -n "$ns" --timeout=60s &>/dev/null || true
    local elapsed=$((SECONDS - start_time))

    if [[ $elapsed -ge 10 ]]; then
        pass "Deletion took ${elapsed}s (preStop hook completed)"
    else
        fail "Deletion took ${elapsed}s (expected >= 10s for preStop hook)"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug bad liveness probe path ==="
    local pod="broken-web"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 30

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | grep -A 5 'Liveness:'"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0"
    else
        fail_with_cmd "restartCount is $restart_count (expected 0 after fix)" \
            "kubectl get events -n $ns --field-selector reason=Unhealthy"
    fi

    local ready
    ready=$(get_ready "$pod" "$ns")
    if [[ "$ready" == "true" ]]; then
        pass "Container is ready (1/1)"
    else
        fail "Container is not ready"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug slow startup killed by liveness ==="
    local pod="slow-boot"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 60

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | tail -20"
    fi

    if has_startup_probe "$pod" "$ns"; then
        pass "Startup probe is configured (fix applied)"
    else
        info "Startup probe not found (alternative fix may have been used)"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0"
    else
        fail "restartCount is $restart_count (expected 0 after fix)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug preStop hook timeout ==="
    local pod="hook-pod"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local grace
    grace=$(get_termination_grace "$pod" "$ns")
    if [[ "$grace" -ge 20 ]]; then
        pass "terminationGracePeriodSeconds is $grace (>= 20, fix applied)"
    else
        fail "terminationGracePeriodSeconds is $grace (expected >= 20)"
        return
    fi

    # Test the fix by deleting
    info "Deleting pod to test preStop hook completion..."
    kubectl delete pod "$pod" -n "$ns" --wait=false &>/dev/null
    sleep 18

    if logs_contain "$pod" "$ns" "cleanup done"; then
        pass "Logs contain 'cleanup done' (preStop hook completed)"
    else
        fail_with_cmd "preStop hook did not complete" \
            "kubectl logs $pod -n $ns"
    fi

    kubectl wait --for=delete pod/"$pod" -n "$ns" --timeout=60s &>/dev/null || true
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Production-style web server with comprehensive probes ==="
    local pod="prod-web"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 30

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | tail -20"
    fi

    # Startup probe checks
    local startup_period
    startup_period=$(get_probe_value "$pod" "$ns" "startupProbe" "periodSeconds")
    if [[ "$startup_period" == "3" ]]; then
        pass "Startup probe periodSeconds is 3"
    else
        fail "Startup probe periodSeconds is $startup_period (expected 3)"
    fi

    local startup_threshold
    startup_threshold=$(get_probe_value "$pod" "$ns" "startupProbe" "failureThreshold")
    if [[ "$startup_threshold" == "15" ]]; then
        pass "Startup probe failureThreshold is 15"
    else
        fail "Startup probe failureThreshold is $startup_threshold (expected 15)"
    fi

    # Liveness probe checks
    local liveness_period
    liveness_period=$(get_probe_value "$pod" "$ns" "livenessProbe" "periodSeconds")
    if [[ "$liveness_period" == "10" ]]; then
        pass "Liveness probe periodSeconds is 10"
    else
        fail "Liveness probe periodSeconds is $liveness_period (expected 10)"
    fi

    local liveness_threshold
    liveness_threshold=$(get_probe_value "$pod" "$ns" "livenessProbe" "failureThreshold")
    if [[ "$liveness_threshold" == "3" ]]; then
        pass "Liveness probe failureThreshold is 3"
    else
        fail "Liveness probe failureThreshold is $liveness_threshold (expected 3)"
    fi

    # Readiness probe checks
    local readiness_period
    readiness_period=$(get_probe_value "$pod" "$ns" "readinessProbe" "periodSeconds")
    if [[ "$readiness_period" == "5" ]]; then
        pass "Readiness probe periodSeconds is 5"
    else
        fail "Readiness probe periodSeconds is $readiness_period (expected 5)"
    fi

    local readiness_threshold
    readiness_threshold=$(get_probe_value "$pod" "$ns" "readinessProbe" "failureThreshold")
    if [[ "$readiness_threshold" == "2" ]]; then
        pass "Readiness probe failureThreshold is 2"
    else
        fail "Readiness probe failureThreshold is $readiness_threshold (expected 2)"
    fi

    # All timeouts should be 2
    local startup_timeout
    startup_timeout=$(get_probe_value "$pod" "$ns" "startupProbe" "timeoutSeconds")
    if [[ "$startup_timeout" == "2" ]]; then
        pass "All probe timeouts are 2"
    else
        fail "Startup probe timeoutSeconds is $startup_timeout (expected 2)"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0"
    else
        fail "restartCount is $restart_count (expected 0)"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Graceful shutdown with drain simulation ==="
    local pod="drain-pod"
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
        fail "Pod phase is $phase (expected Running)"
        return
    fi

    local grace
    grace=$(get_termination_grace "$pod" "$ns")
    if [[ "$grace" == "35" ]]; then
        pass "terminationGracePeriodSeconds is 35"
    else
        fail "terminationGracePeriodSeconds is $grace (expected 35)"
    fi

    if has_prestop_hook "$pod" "$ns"; then
        pass "preStop hook is configured"
    else
        fail "preStop hook not found"
    fi

    # Time the deletion
    info "Deleting pod to test drain (will take ~20s)..."
    local start_time=$SECONDS
    kubectl delete pod "$pod" -n "$ns" --timeout=60s &>/dev/null || true
    local elapsed=$((SECONDS - start_time))

    if [[ $elapsed -ge 20 ]]; then
        pass "Deletion took ${elapsed}s (drain completed)"
    else
        fail "Deletion took ${elapsed}s (expected >= 20s)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Multi-container with independent health checks ==="
    local pod="multi-health"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Check 1/2 ready state early
    sleep 10
    local ready_count_early
    ready_count_early=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[?(@.ready==true)]}' 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0")
    if [[ "$ready_count_early" == "1" ]]; then
        pass "Pod shows 1/2 containers ready initially"
    else
        info "Ready count early: $ready_count_early (timing may vary)"
    fi

    # After 20 seconds, should be 2/2
    sleep 10
    local ready_count_late
    ready_count_late=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[?(@.ready==true)]}' 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0")
    if [[ "$ready_count_late" == "2" ]]; then
        pass "Pod shows 2/2 containers ready after 20s"
    else
        fail_with_cmd "Ready count: $ready_count_late (expected 2)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{range .status.containerStatuses[*]}{.name}: ready={.ready}{\"\\n\"}{end}'"
    fi

    # Check restart counts for both containers
    local web_restarts
    web_restarts=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[?(@.name=="web")].restartCount}' 2>/dev/null)
    local sidecar_restarts
    sidecar_restarts=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[?(@.name=="sidecar")].restartCount}' 2>/dev/null)

    if [[ "$web_restarts" == "0" ]] && [[ "$sidecar_restarts" == "0" ]]; then
        pass "Both containers have restartCount 0"
    else
        fail "web restarts: $web_restarts, sidecar restarts: $sidecar_restarts (expected 0, 0)"
    fi

    # Check Ready condition
    local ready_condition
    ready_condition=$(get_ready_condition "$pod" "$ns")
    if [[ "$ready_condition" == "True" ]]; then
        pass "Pod Ready condition is True"
    else
        fail "Pod Ready condition is $ready_condition (expected True)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multiple probe issues ==="
    local pod="flaky-app"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Wait for stability
    sleep 120

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (all issues fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | tail -20"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0"
    else
        fail "restartCount is $restart_count (expected 0 after fix)"
    fi

    local ready_condition
    ready_condition=$(get_ready_condition "$pod" "$ns")
    if [[ "$ready_condition" == "True" ]]; then
        pass "Pod Ready condition is True"
    else
        fail "Pod Ready condition is $ready_condition (expected True)"
    fi

    # Check startup probe window is sufficient
    local startup_threshold
    startup_threshold=$(get_probe_value "$pod" "$ns" "startupProbe" "failureThreshold")
    if [[ "$startup_threshold" -ge 15 ]]; then
        pass "Startup probe failureThreshold is $startup_threshold (sufficient for 20s startup)"
    else
        fail "Startup probe failureThreshold is $startup_threshold (expected >= 15)"
    fi

    # Check liveness probe has reasonable failureThreshold
    local liveness_threshold
    liveness_threshold=$(get_probe_value "$pod" "$ns" "livenessProbe" "failureThreshold")
    if [[ "$liveness_threshold" -ge 3 ]]; then
        pass "Liveness probe failureThreshold is $liveness_threshold (not flaky)"
    else
        fail "Liveness probe failureThreshold is $liveness_threshold (expected >= 3)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Multiple probe and termination issues ==="
    local pod="web-complex"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 30

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (all issues fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | tail -20"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0"
    else
        fail "restartCount is $restart_count (expected 0)"
    fi

    # Check liveness probe timeout < period
    local liveness_timeout
    liveness_timeout=$(get_probe_value "$pod" "$ns" "livenessProbe" "timeoutSeconds")
    local liveness_period
    liveness_period=$(get_probe_value "$pod" "$ns" "livenessProbe" "periodSeconds")

    if [[ "$liveness_timeout" -lt "$liveness_period" ]]; then
        pass "Liveness probe timeoutSeconds ($liveness_timeout) < periodSeconds ($liveness_period)"
    else
        fail "Liveness probe timeoutSeconds ($liveness_timeout) >= periodSeconds ($liveness_period)"
    fi

    # Check terminationGracePeriodSeconds >= 25
    local grace
    grace=$(get_termination_grace "$pod" "$ns")
    if [[ "$grace" -ge 25 ]]; then
        pass "terminationGracePeriodSeconds is $grace (>= 25 for preStop hook)"
    else
        fail "terminationGracePeriodSeconds is $grace (expected >= 25)"
    fi

    # Test graceful shutdown
    info "Deleting pod to test graceful shutdown (will take ~20s)..."
    local start_time=$SECONDS
    kubectl delete pod "$pod" -n "$ns" --timeout=60s &>/dev/null || true
    local elapsed=$((SECONDS - start_time))

    if [[ $elapsed -ge 20 ]]; then
        pass "Deletion took ${elapsed}s (preStop hook completed)"
    else
        fail "Deletion took ${elapsed}s (expected >= 20s)"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Comprehensive production pod from scratch ==="
    local pod="prod-app"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 40

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns | tail -20"
    fi

    local ready_condition
    ready_condition=$(get_ready_condition "$pod" "$ns")
    if [[ "$ready_condition" == "True" ]]; then
        pass "Pod Ready condition is True"
    else
        fail "Pod Ready condition is $ready_condition (expected True)"
    fi

    # Check startup probe: 5 * 12 = 60 seconds
    local startup_period
    startup_period=$(get_probe_value "$pod" "$ns" "startupProbe" "periodSeconds")
    local startup_threshold
    startup_threshold=$(get_probe_value "$pod" "$ns" "startupProbe" "failureThreshold")
    if [[ "$startup_period" == "5" ]] && [[ "$startup_threshold" == "12" ]]; then
        pass "Startup probe: periodSeconds=5, failureThreshold=12 (60s window)"
    else
        fail "Startup probe: periodSeconds=$startup_period, failureThreshold=$startup_threshold"
    fi

    # Check liveness probe: 10 * 2 = 20 seconds
    local liveness_period
    liveness_period=$(get_probe_value "$pod" "$ns" "livenessProbe" "periodSeconds")
    local liveness_threshold
    liveness_threshold=$(get_probe_value "$pod" "$ns" "livenessProbe" "failureThreshold")
    if [[ "$liveness_period" == "10" ]] && [[ "$liveness_threshold" == "2" ]]; then
        pass "Liveness probe: periodSeconds=10, failureThreshold=2 (20s detection)"
    else
        fail "Liveness probe: periodSeconds=$liveness_period, failureThreshold=$liveness_threshold"
    fi

    # Check readiness probe: 5 * 2 = 10 seconds
    local readiness_period
    readiness_period=$(get_probe_value "$pod" "$ns" "readinessProbe" "periodSeconds")
    local readiness_threshold
    readiness_threshold=$(get_probe_value "$pod" "$ns" "readinessProbe" "failureThreshold")
    if [[ "$readiness_period" == "5" ]] && [[ "$readiness_threshold" == "2" ]]; then
        pass "Readiness probe: periodSeconds=5, failureThreshold=2 (10s detection)"
    else
        fail "Readiness probe: periodSeconds=$readiness_period, failureThreshold=$readiness_threshold"
    fi

    # Check all timeouts are 2
    local startup_timeout
    startup_timeout=$(get_probe_value "$pod" "$ns" "startupProbe" "timeoutSeconds")
    local liveness_timeout
    liveness_timeout=$(get_probe_value "$pod" "$ns" "livenessProbe" "timeoutSeconds")
    local readiness_timeout
    readiness_timeout=$(get_probe_value "$pod" "$ns" "readinessProbe" "timeoutSeconds")
    if [[ "$startup_timeout" == "2" ]] && [[ "$liveness_timeout" == "2" ]] && [[ "$readiness_timeout" == "2" ]]; then
        pass "All probe timeoutSeconds are 2"
    else
        fail "Probe timeouts: startup=$startup_timeout, liveness=$liveness_timeout, readiness=$readiness_timeout (expected all 2)"
    fi

    # Check postStart hook and lifecycle log
    if has_poststart_hook "$pod" "$ns"; then
        pass "postStart hook is configured"
    else
        fail "postStart hook not found"
    fi

    local lifecycle_log
    lifecycle_log=$(kubectl exec "$pod" -n "$ns" -- cat /tmp/lifecycle.log 2>/dev/null || echo "")
    if [[ "$lifecycle_log" == *"Container started at"* ]]; then
        pass "postStart hook wrote lifecycle.log"
    else
        fail_with_cmd "lifecycle.log not found or empty" \
            "kubectl exec $pod -n $ns -- cat /tmp/lifecycle.log"
    fi

    # Check terminationGracePeriodSeconds
    local grace
    grace=$(get_termination_grace "$pod" "$ns")
    if [[ "$grace" == "30" ]]; then
        pass "terminationGracePeriodSeconds is 30"
    else
        fail "terminationGracePeriodSeconds is $grace (expected 30)"
    fi

    # Check preStop hook
    if has_prestop_hook "$pod" "$ns"; then
        pass "preStop hook is configured"
    else
        fail "preStop hook not found"
    fi

    # Test graceful shutdown
    info "Deleting pod to test graceful shutdown (will take ~15s)..."
    kubectl delete pod "$pod" -n "$ns" --wait=false &>/dev/null
    sleep 2

    if logs_contain "$pod" "$ns" "shutting down"; then
        pass "preStop hook executed (logs contain 'shutting down')"
    else
        fail_with_cmd "preStop hook message not found" \
            "kubectl logs $pod -n $ns"
    fi

    kubectl wait --for=delete pod/"$pod" -n "$ns" --timeout=60s &>/dev/null || true

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns" 2>/dev/null || echo "0")
    if [[ "$restart_count" == "0" ]]; then
        pass "restartCount is 0"
    else
        info "restartCount check skipped (pod deleted)"
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
