#!/usr/bin/env bash
#
# verify.sh - Automated verification for multi-container-patterns-homework.md
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

# Helper: get container names
get_container_names() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null
}

# Helper: get init container names
get_init_container_names() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.initContainers[*].name}' 2>/dev/null
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

# Helper: check if volume is emptyDir
has_emptydir_volume() {
    local pod=$1
    local ns=$2
    local result
    result=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.volumes[0].emptyDir}' 2>/dev/null)
    # emptyDir returns {} or map[], both indicate it exists
    [[ -n "$result" ]]
}

# Helper: get init container state
get_init_state() {
    local pod=$1
    local ns=$2
    local index=$3
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.status.initContainerStatuses[$index].state}" 2>/dev/null
}

# Helper: check if volume mount is read-only
is_mount_readonly() {
    local pod=$1
    local ns=$2
    local container=$3
    local readonly
    readonly=$(kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[?(@.name==\"$container\")].volumeMounts[0].readOnly}" 2>/dev/null)
    [[ "$readonly" == "true" ]]
}

# Helper: get shareProcessNamespace value
get_share_process_namespace() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.shareProcessNamespace}' 2>/dev/null
}

# Helper: get init container restart policy
get_init_restart_policy() {
    local pod=$1
    local ns=$2
    local init_name=$3
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.initContainers[?(@.name==\"$init_name\")].restartPolicy}" 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Init container writes, main reads ==="
    local pod="init-writer"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 2

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local init_state
    init_state=$(get_init_state "$pod" "$ns" 0)
    if [[ "$init_state" == *"terminated"* ]] && [[ "$init_state" == *"Completed"* ]]; then
        pass "Init container completed"
    else
        fail_with_cmd "Init container state: $init_state" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.initContainerStatuses[0].state}'"
    fi

    if logs_contain "$pod" "$ns" "init-complete" "reader"; then
        pass "Main container logs contain 'init-complete'"
    else
        fail_with_cmd "Main container logs do not contain 'init-complete'" \
            "kubectl logs $pod -c reader -n $ns"
    fi

    if has_emptydir_volume "$pod" "$ns"; then
        pass "Volume is emptyDir"
    else
        fail "Volume is not an emptyDir"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Classical sidecar pattern ==="
    local pod="timestamper"
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
        return
    fi

    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == *"app"* ]] && [[ "$containers" == *"clock"* ]]; then
        pass "Two containers: app and clock"
    else
        fail_with_cmd "Container names: $containers (expected app and clock)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[*].name}'"
    fi

    # Check that timestamp file exists and can be read from app container
    local timestamp
    timestamp=$(kubectl exec "$pod" -c app -n "$ns" -- cat /app-data/timestamp.txt 2>/dev/null || echo "")
    if [[ -n "$timestamp" ]]; then
        pass "Timestamp file exists and is readable from app container"
    else
        fail_with_cmd "Could not read timestamp file from app container" \
            "kubectl exec $pod -c app -n $ns -- cat /app-data/timestamp.txt"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Shared process namespace ==="
    local pod="shared-pids"
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
        return
    fi

    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == *"worker"* ]] && [[ "$containers" == *"inspector"* ]]; then
        pass "Two containers: worker and inspector"
    else
        fail "Container names: $containers (expected worker and inspector)"
    fi

    local share_pids
    share_pids=$(get_share_process_namespace "$pod" "$ns")
    if [[ "$share_pids" == "true" ]]; then
        pass "shareProcessNamespace is true"
    else
        fail_with_cmd "shareProcessNamespace is $share_pids (expected true)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.shareProcessNamespace}'"
    fi

    # Check that inspector can see worker's processes
    local ps_output
    ps_output=$(kubectl exec "$pod" -c inspector -n "$ns" -- ps aux 2>/dev/null || echo "")
    if [[ "$ps_output" == *"sleep"* ]]; then
        pass "Inspector can see processes from other containers"
    else
        fail_with_cmd "Inspector cannot see shared processes" \
            "kubectl exec $pod -c inspector -n $ns -- ps aux"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Three sequential init containers ==="
    local pod="triple-init"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local init_names
    init_names=$(get_init_container_names "$pod" "$ns")
    if [[ "$init_names" == *"stage-a"* ]] && [[ "$init_names" == *"stage-b"* ]] && [[ "$init_names" == *"stage-c"* ]]; then
        pass "Three init containers: stage-a, stage-b, stage-c"
    else
        fail_with_cmd "Init container names: $init_names" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.initContainers[*].name}'"
    fi

    if logs_contain "$pod" "$ns" "ALL STAGES COMPLETE" "verifier"; then
        pass "Verifier logs show ALL STAGES COMPLETE"
    else
        fail_with_cmd "Verifier did not confirm all stages" \
            "kubectl logs $pod -c verifier -n $ns"
    fi

    # Check all three files exist
    local files
    files=$(kubectl exec "$pod" -c verifier -n "$ns" -- ls /pipeline/ 2>/dev/null || echo "")
    if [[ "$files" == *"a.txt"* ]] && [[ "$files" == *"b.txt"* ]] && [[ "$files" == *"c.txt"* ]]; then
        pass "All three stage files exist"
    else
        fail_with_cmd "Missing stage files in /pipeline/" \
            "kubectl exec $pod -c verifier -n $ns -- ls /pipeline/"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Read-only sidecar mount ==="
    local pod="readonly-sidecar"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 10

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    if logs_contain "$pod" "$ns" "log-entry-" "consumer"; then
        pass "Consumer logs contain 'log-entry-'"
    else
        fail_with_cmd "Consumer is not tailing log entries" \
            "kubectl logs $pod -c consumer -n $ns"
    fi

    if is_mount_readonly "$pod" "$ns" "consumer"; then
        pass "Consumer volume mount is read-only"
    else
        fail_with_cmd "Consumer volume mount is not read-only" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[?(@.name==\"consumer\")].volumeMounts[0].readOnly}'"
    fi

    # Try to write to read-only mount (should fail)
    if ! kubectl exec "$pod" -c consumer -n "$ns" -- sh -c 'echo test > /logs/test.txt' 2>/dev/null; then
        pass "Consumer cannot write to read-only mount (expected)"
    else
        fail "Consumer was able to write to read-only mount (should have failed)"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Format adapter pattern ==="
    local pod="format-adapter"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 12

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local raw
    raw=$(kubectl exec "$pod" -c app -n "$ns" -- cat /metrics/raw.txt 2>/dev/null || echo "")
    if [[ "$raw" == *"requests="* ]] && [[ "$raw" == *"errors="* ]]; then
        pass "Raw metrics file contains plain text format"
    else
        fail_with_cmd "Raw metrics not in expected format" \
            "kubectl exec $pod -c app -n $ns -- cat /metrics/raw.txt"
    fi

    if logs_contain "$pod" "$ns" '"requests"' "json-adapter" && logs_contain "$pod" "$ns" '"errors"' "json-adapter"; then
        pass "Adapter outputs JSON format"
    else
        fail_with_cmd "Adapter output does not contain JSON" \
            "kubectl logs $pod -c json-adapter -n $ns"
    fi

    if is_mount_readonly "$pod" "$ns" "json-adapter"; then
        pass "Adapter volume mount is read-only"
    else
        fail "Adapter volume mount is not read-only"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix filename mismatch ==="
    local pod="broken-init"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    if logs_contain "$pod" "$ns" "Greeting: Welcome aboard" "app"; then
        pass "Main container shows the greeting message"
    else
        fail_with_cmd "Main container does not show greeting" \
            "kubectl logs $pod -c app -n $ns"
        info "Hint: Check that init writes and main reads the same filename"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix ambassador port mismatch ==="
    local pod="broken-ambassador"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 8

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    if logs_contain "$pod" "$ns" "Client: got proxied-response" "client"; then
        pass "Client received proxied response"
    else
        fail_with_cmd "Client did not receive proxied response" \
            "kubectl logs $pod -c client -n $ns"
        info "Hint: Check that client connects to the port ambassador listens on"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix read-only mount issue ==="
    local pod="broken-sidecar"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 10

    local ready
    ready=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)
    if [[ "$ready" == "true true true" ]]; then
        pass "All 3 containers are ready"
    else
        fail_with_cmd "Not all containers are ready: $ready" \
            "kubectl get pod $pod -n $ns"
        info "Hint: Check which container is restarting and why"
        return
    fi

    if logs_contain "$pod" "$ns" "app is running" "log-reader"; then
        pass "log-reader is tailing app output"
    else
        fail_with_cmd "log-reader is not showing app output" \
            "kubectl logs $pod -c log-reader -n $ns"
    fi

    local restarts
    restarts=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{range .status.containerStatuses[*]}{.restartCount}{" "}{end}' 2>/dev/null)
    if [[ "$restarts" == "0 0 0" ]]; then
        pass "No containers have restarted"
    else
        fail "Some containers have restarted: $restarts"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Log-shipping sidecar ==="
    local pod="log-shipper"
    local ns="ex-4-1"

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
        return
    fi

    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == *"web"* ]] && [[ "$containers" == *"shipper"* ]]; then
        pass "Two containers: web and shipper"
    else
        fail "Container names: $containers (expected web and shipper)"
    fi

    # Generate traffic
    kubectl exec "$pod" -c web -n "$ns" -- curl -s http://localhost/ > /dev/null 2>&1 || true
    sleep 3

    if logs_contain "$pod" "$ns" "\[SHIPPED\]" "shipper"; then
        pass "Shipper logs contain [SHIPPED] prefix"
    else
        fail_with_cmd "Shipper is not prepending [SHIPPED] tag" \
            "kubectl logs $pod -c shipper -n $ns"
    fi

    if is_mount_readonly "$pod" "$ns" "shipper"; then
        pass "Shipper volume mount is read-only"
    else
        fail "Shipper volume mount is not read-only"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Ambassador with cached responses ==="
    local pod="cache-proxy"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 7

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local init_state
    init_state=$(get_init_state "$pod" "$ns" 0)
    if [[ "$init_state" == *"terminated"* ]] && [[ "$init_state" == *"Completed"* ]]; then
        pass "Init container completed"
    else
        fail "Init container did not complete"
    fi

    if logs_contain "$pod" "$ns" '"status":"fresh"' "app"; then
        pass "App received cached JSON response"
    else
        fail_with_cmd "App did not receive expected response" \
            "kubectl logs $pod -c app -n $ns"
    fi

    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == *"proxy"* ]] && [[ "$containers" == *"app"* ]]; then
        pass "Two containers: proxy and app"
    else
        fail "Container names: $containers"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Native sidecar pattern ==="
    local pod="native-logger"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 10

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local init_names
    init_names=$(get_init_container_names "$pod" "$ns")
    if [[ "$init_names" == *"log-tailer"* ]]; then
        pass "log-tailer is in initContainers"
    else
        fail_with_cmd "log-tailer not found in initContainers" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.initContainers[*].name}'"
        return
    fi

    local restart_policy
    restart_policy=$(get_init_restart_policy "$pod" "$ns" "log-tailer")
    if [[ "$restart_policy" == "Always" ]]; then
        pass "log-tailer has restartPolicy: Always"
    else
        fail_with_cmd "log-tailer restartPolicy is $restart_policy (expected Always)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.initContainers[?(@.name==\"log-tailer\")].restartPolicy}'"
    fi

    if logs_contain "$pod" "$ns" "app event at" "log-tailer"; then
        pass "log-tailer is showing app events"
    else
        fail_with_cmd "log-tailer is not showing app events" \
            "kubectl logs $pod -c log-tailer -n $ns"
    fi

    local init_state
    init_state=$(get_init_state "$pod" "$ns" 0)
    if [[ "$init_state" == *"running"* ]]; then
        pass "Native sidecar is running (not terminated)"
    else
        fail "Native sidecar state: $init_state (expected running)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Fix multiple issues ==="
    local pod="broken-multi"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 15

    local ready
    ready=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)
    if [[ "$ready" == "true true" ]]; then
        pass "All 2 containers are ready"
    else
        fail_with_cmd "Not all containers are ready: $ready" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    if logs_contain "$pod" "$ns" "Config: db_host=postgres.svc" "app"; then
        pass "App shows config from init container"
    else
        fail_with_cmd "App does not show config" \
            "kubectl logs $pod -c app -n $ns"
    fi

    if logs_contain "$pod" "$ns" "processing" "monitor"; then
        pass "Monitor sidecar is showing activity log"
    else
        fail_with_cmd "Monitor is not showing activity" \
            "kubectl logs $pod -c monitor -n $ns"
    fi

    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == *"app"* ]] && [[ "$containers" == *"monitor"* ]]; then
        pass "Two containers with unique names: app and monitor"
    else
        fail "Container names: $containers (should be app and monitor)"
    fi

    local restarts
    restarts=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{range .status.containerStatuses[*]}{.restartCount}{" "}{end}' 2>/dev/null)
    if [[ "$restarts" == "0 0" ]]; then
        pass "No containers have restarted"
    else
        fail "Some containers have restarted: $restarts"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Fix native sidecar placement ==="
    local pod="broken-native"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 10

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local init_names
    init_names=$(get_init_container_names "$pod" "$ns")
    if [[ "$init_names" == *"setup"* ]] && [[ "$init_names" == *"web-monitor"* ]]; then
        pass "Both setup and web-monitor are in initContainers"
    else
        fail_with_cmd "Init containers: $init_names (expected setup and web-monitor)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.initContainers[*].name}'"
    fi

    local restart_policy
    restart_policy=$(get_init_restart_policy "$pod" "$ns" "web-monitor")
    if [[ "$restart_policy" == "Always" ]]; then
        pass "web-monitor has restartPolicy: Always"
    else
        fail_with_cmd "web-monitor restartPolicy is $restart_policy (expected Always)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.initContainers[?(@.name==\"web-monitor\")].restartPolicy}'"
    fi

    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == "web" ]]; then
        pass "Only one regular container: web"
    else
        fail "Regular containers: $containers (expected only web)"
    fi

    if logs_contain "$pod" "$ns" "Web started with: environment=production" "web"; then
        pass "Web container shows config"
    else
        fail_with_cmd "Web container does not show config" \
            "kubectl logs $pod -c web -n $ns"
    fi

    if logs_contain "$pod" "$ns" "request handled" "web-monitor"; then
        pass "web-monitor is showing web log entries"
    else
        fail_with_cmd "web-monitor is not showing log entries" \
            "kubectl logs $pod -c web-monitor -n $ns"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Comprehensive observability stack ==="
    local pod="obs-stack"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 10

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local init_names
    init_names=$(get_init_container_names "$pod" "$ns")
    if [[ "$init_names" == *"html-seed"* ]] && [[ "$init_names" == *"log-forwarder"* ]] && [[ "$init_names" == *"metrics-adapter"* ]]; then
        pass "Three init containers: html-seed, log-forwarder, metrics-adapter"
    else
        fail_with_cmd "Init containers: $init_names" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.initContainers[*].name}'"
    fi

    # Check html-seed completed
    local html_seed_state
    html_seed_state=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.initContainerStatuses[?(@.name=="html-seed")].state}' 2>/dev/null)
    if [[ "$html_seed_state" == *"terminated"* ]] && [[ "$html_seed_state" == *"Completed"* ]]; then
        pass "html-seed init container completed"
    else
        fail "html-seed did not complete"
    fi

    # Check native sidecars have restartPolicy: Always
    local log_forwarder_policy
    log_forwarder_policy=$(get_init_restart_policy "$pod" "$ns" "log-forwarder")
    if [[ "$log_forwarder_policy" == "Always" ]]; then
        pass "log-forwarder has restartPolicy: Always"
    else
        fail "log-forwarder restartPolicy is $log_forwarder_policy (expected Always)"
    fi

    local metrics_adapter_policy
    metrics_adapter_policy=$(get_init_restart_policy "$pod" "$ns" "metrics-adapter")
    if [[ "$metrics_adapter_policy" == "Always" ]]; then
        pass "metrics-adapter has restartPolicy: Always"
    else
        fail "metrics-adapter restartPolicy is $metrics_adapter_policy (expected Always)"
    fi

    # Check web is the only regular container
    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == "web" ]]; then
        pass "Only one regular container: web"
    else
        fail "Regular containers: $containers (expected only web)"
    fi

    # Check index.html content
    local index
    index=$(kubectl exec "$pod" -c web -n "$ns" -- cat /usr/share/nginx/html/index.html 2>/dev/null || echo "")
    if [[ "$index" == *"Built at"* ]]; then
        pass "index.html contains build timestamp"
    else
        fail_with_cmd "index.html missing or incorrect" \
            "kubectl exec $pod -c web -n $ns -- cat /usr/share/nginx/html/index.html"
    fi

    # Generate traffic
    kubectl exec "$pod" -c web -n "$ns" -- curl -s http://localhost/ > /dev/null 2>&1 || true
    sleep 5

    # Check log forwarder output
    if logs_contain "$pod" "$ns" "\[FWD\]" "log-forwarder"; then
        pass "log-forwarder is prepending [FWD] tag"
    else
        fail_with_cmd "log-forwarder is not showing tagged logs" \
            "kubectl logs $pod -c log-forwarder -n $ns"
    fi

    # Check metrics adapter output (should be JSON)
    if logs_contain "$pod" "$ns" '"active_connections"' "metrics-adapter" || logs_contain "$pod" "$ns" "{" "metrics-adapter"; then
        pass "metrics-adapter is outputting JSON"
    else
        fail_with_cmd "metrics-adapter is not outputting JSON" \
            "kubectl logs $pod -c metrics-adapter -n $ns"
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
