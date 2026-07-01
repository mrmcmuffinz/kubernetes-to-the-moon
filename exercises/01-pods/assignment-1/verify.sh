#!/usr/bin/env bash
#
# verify.sh - Automated verification for pod-fundamentals-homework.md
#
# Usage:
#   ./verify.sh 1.1      # verify exercise 1.1
#   ./verify.sh all      # verify all exercises
#   ./verify.sh 1        # verify all Level 1 exercises (1.1, 1.2, 1.3)
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

# Helper: get pod image
get_image() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null
}

# Helper: get pod ready count
get_ready() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null
}

# Helper: get restart policy
get_restart_policy() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.restartPolicy}' 2>/dev/null
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

# Helper: get env var from pod
get_env() {
    local pod=$1
    local ns=$2
    local var=$3
    local container=${4:-}
    local result

    if [[ -n "$container" ]]; then
        result=$(kubectl exec "$pod" -n "$ns" -c "$container" -- env 2>/dev/null | grep "^${var}=" | cut -d= -f2 || echo "")
    else
        result=$(kubectl exec "$pod" -n "$ns" -- env 2>/dev/null | grep "^${var}=" | cut -d= -f2 || echo "")
    fi

    echo "$result"
}

# Helper: get label value
get_label() {
    local pod=$1
    local ns=$2
    local label=$3
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.metadata.labels.$label}" 2>/dev/null
}

# Helper: check if label exists with value
label_matches() {
    local pod=$1
    local ns=$2
    local key=$3
    local expected=$4
    local actual
    actual=$(get_label "$pod" "$ns" "$key")
    [[ "$actual" == "$expected" ]]
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

# Helper: get init container terminated reason
get_init_terminated_reason() {
    local pod=$1
    local ns=$2
    local index=$3
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.status.initContainerStatuses[$index].state.terminated.reason}" 2>/dev/null
}

# Helper: get command field
get_command() {
    local pod=$1
    local ns=$2
    local container_index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$container_index].command}" 2>/dev/null
}

# Helper: get args field
get_args() {
    local pod=$1
    local ns=$2
    local container_index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$container_index].args}" 2>/dev/null
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

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic nginx pod ==="
    local pod="web"
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
        fail "Pod phase is $phase (expected Running)"
    fi

    local image
    image=$(get_image "$pod" "$ns")
    if [[ "$image" == "nginx:1.25" ]]; then
        pass "Image is nginx:1.25"
    else
        fail "Image is $image (expected nginx:1.25)"
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
    echo "=== Exercise 1.2: One-shot echo pod ==="
    local pod="greeter"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Give the pod time to complete if it just started
    sleep 2

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Succeeded" ]]; then
        pass "Pod phase is Succeeded"
    else
        fail "Pod phase is $phase (expected Succeeded)"
        info "Hint: Pod should complete and not restart"
    fi

    local restart_policy
    restart_policy=$(get_restart_policy "$pod" "$ns")
    if [[ "$restart_policy" == "Never" ]]; then
        pass "Restart policy is Never"
    else
        fail "Restart policy is $restart_policy (expected Never)"
    fi

    if logs_contain "$pod" "$ns" "hello world"; then
        pass "Logs contain 'hello world'"
    else
        fail "Logs do not contain 'hello world'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Pod with environment variables ==="
    local pod="envpod"
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

    local app_name
    app_name=$(get_env "$pod" "$ns" "APP_NAME" || echo "")
    if [[ "$app_name" == "demo" ]]; then
        pass "APP_NAME=demo"
    else
        fail "APP_NAME=$app_name (expected demo)"
    fi

    local app_tier
    app_tier=$(get_env "$pod" "$ns" "APP_TIER" || echo "")
    if [[ "$app_tier" == "frontend" ]]; then
        pass "APP_TIER=frontend"
    else
        fail "APP_TIER=$app_tier (expected frontend)"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Command/args with labels and restart policy ==="
    local pod="runner"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5  # Allow time for completion

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Succeeded" ]]; then
        pass "Pod phase is Succeeded"
    else
        fail "Pod phase is $phase (expected Succeeded)"
        info "Hint: With restartPolicy OnFailure, clean exits should reach Succeeded"
    fi

    if label_matches "$pod" "$ns" "app" "runner"; then
        pass "Label app=runner"
    else
        fail "Label app is not 'runner'"
    fi

    if label_matches "$pod" "$ns" "tier" "batch"; then
        pass "Label tier=batch"
    else
        fail "Label tier is not 'batch'"
    fi

    if label_matches "$pod" "$ns" "environment" "homework"; then
        pass "Label environment=homework"
    else
        fail "Label environment is not 'homework'"
    fi

    local restart_policy
    restart_policy=$(get_restart_policy "$pod" "$ns")
    if [[ "$restart_policy" == "OnFailure" ]]; then
        pass "Restart policy is OnFailure"
    else
        fail "Restart policy is $restart_policy (expected OnFailure)"
    fi

    if logs_contain "$pod" "$ns" "starting"; then
        pass "Logs contain 'starting'"
    else
        fail "Logs do not contain 'starting'"
    fi

    if logs_contain "$pod" "$ns" "finishing"; then
        pass "Logs contain 'finishing'"
    else
        fail "Logs do not contain 'finishing'"
    fi

    local cmd
    cmd=$(get_command "$pod" "$ns")
    if [[ "$cmd" == *"sh"* ]] && [[ "$cmd" == *"-c"* ]]; then
        pass "Command includes sh -c"
    else
        fail "Command does not appear to use sh -c"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Multi-container pod with shared volume ==="
    local pod="sharers"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5  # Give containers time to coordinate

    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == *"producer"* ]] && [[ "$containers" == *"consumer"* ]]; then
        pass "Two containers: producer and consumer"
    else
        fail "Container names are: $containers (expected producer and consumer)"
    fi

    if logs_contain "$pod" "$ns" "hello from producer" "consumer"; then
        pass "Consumer logs contain 'hello from producer'"
    else
        fail_with_cmd "Consumer logs do not contain producer's message" \
            "kubectl logs $pod -n $ns -c consumer"
        info "Hint: Check volume mount paths and file write location"
    fi

    if has_emptydir_volume "$pod" "$ns"; then
        pass "Volume is emptyDir"
    else
        fail "Volume is not an emptyDir"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Downward API environment variables ==="
    local pod="metapod"
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
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}'"
        return
    fi

    local pod_name
    pod_name=$(get_env "$pod" "$ns" "POD_NAME" || echo "")
    if [[ "$pod_name" == "metapod" ]]; then
        pass "POD_NAME=metapod (from downward API)"
    else
        fail_with_cmd "POD_NAME=$pod_name (expected metapod)" \
            "kubectl exec $pod -n $ns -- env | grep '^POD_NAME='"
    fi

    local pod_ns
    pod_ns=$(get_env "$pod" "$ns" "POD_NAMESPACE" || echo "")
    if [[ "$pod_ns" == "$ns" ]]; then
        pass "POD_NAMESPACE=$ns (from downward API)"
    else
        fail_with_cmd "POD_NAMESPACE=$pod_ns (expected $ns)" \
            "kubectl exec $pod -n $ns -- env | grep '^POD_NAMESPACE='"
    fi

    local node_name
    node_name=$(get_env "$pod" "$ns" "NODE_NAME" || echo "")
    if [[ -n "$node_name" ]]; then
        pass "NODE_NAME=$node_name (from downward API)"
    else
        fail_with_cmd "NODE_NAME is not set" \
            "kubectl exec $pod -n $ns -- env | grep '^NODE_NAME='"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug bad image tag ==="
    local pod="broken-1"
    local ns="ex-3-1"

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
        fail "Pod phase is $phase (expected Running)"
        info "Hint: Check image tag validity"
    fi

    local image
    image=$(get_image "$pod" "$ns")
    if [[ "$image" == nginx:* ]] && [[ "$image" != *"nonexistent"* ]]; then
        pass "Image is a valid nginx tag: $image"
    else
        fail "Image is $image (should be a valid nginx tag)"
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
    echo "=== Exercise 3.2: Debug command format ==="
    local pod="broken-2"
    local ns="ex-3-2"

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
    if [[ "$phase" == "Running" ]] || [[ "$phase" == "Succeeded" ]]; then
        pass "Pod phase is $phase (not crashing)"
    else
        fail "Pod phase is $phase (expected Running or Succeeded)"
        info "Hint: Check command/args format for shell execution"
    fi

    if logs_contain "$pod" "$ns" "hello world"; then
        pass "Logs contain 'hello world'"
    else
        fail "Logs do not contain 'hello world'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug init container failure ==="
    local pod="broken-3"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local status
    status=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null)

    if [[ "$status" != *"Init:Error"* ]] && [[ "$status" != *"Init:CrashLoopBackOff"* ]]; then
        pass "Pod is not stuck in Init error state"
    else
        fail "Pod is in $status"
        info "Hint: Check init container exit code"
        return
    fi

    if logs_contain "$pod" "$ns" "main running" "main"; then
        pass "Main container logs contain 'main running'"
    else
        fail "Main container did not run successfully"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Init container pipeline ==="
    local pod="pipeline"
    local ns="ex-4-1"

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
    if [[ "$phase" == "Succeeded" ]]; then
        pass "Pod phase is Succeeded"
    else
        fail_with_cmd "Pod phase is $phase (expected Succeeded)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}'"
    fi

    local init_names
    init_names=$(get_init_container_names "$pod" "$ns")
    if [[ "$init_names" == *"loader"* ]]; then
        pass "Init container 'loader' exists"
    else
        fail "Init container 'loader' not found"
    fi

    local init_reason
    init_reason=$(get_init_terminated_reason "$pod" "$ns" 0)
    if [[ "$init_reason" == "Completed" ]]; then
        pass "Init container completed successfully"
    else
        fail "Init container reason: $init_reason (expected Completed)"
    fi

    if logs_contain "$pod" "$ns" "record-1" "processor" && \
       logs_contain "$pod" "$ns" "record-2" "processor" && \
       logs_contain "$pod" "$ns" "record-3" "processor"; then
        pass "Processor logs contain all three records"
    else
        fail "Processor logs missing expected records"
    fi

    if label_matches "$pod" "$ns" "app" "pipeline"; then
        pass "Label app=pipeline"
    else
        fail "Label app is missing or incorrect"
    fi

    if has_emptydir_volume "$pod" "$ns"; then
        pass "Volume is emptyDir"
    else
        fail_with_cmd "Volume is not an emptyDir" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.volumes[0]}'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Multi-container with downward API and literals ==="
    local pod="idbox"
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

    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == *"inspector-a"* ]] && [[ "$containers" == *"inspector-b"* ]]; then
        pass "Two containers: inspector-a and inspector-b"
    else
        fail "Container names are: $containers"
    fi

    local pod_name_a
    pod_name_a=$(get_env "$pod" "$ns" "POD_NAME" "inspector-a" || echo "")
    if [[ "$pod_name_a" == "idbox" ]]; then
        pass "inspector-a: POD_NAME=idbox"
    else
        fail_with_cmd "inspector-a: POD_NAME=$pod_name_a (expected idbox)" \
            "kubectl exec $pod -n $ns -c inspector-a -- env | grep '^POD_NAME='"
    fi

    local app_role_a
    app_role_a=$(get_env "$pod" "$ns" "APP_ROLE" "inspector-a" || echo "")
    if [[ "$app_role_a" == "primary" ]]; then
        pass "inspector-a: APP_ROLE=primary"
    else
        fail_with_cmd "inspector-a: APP_ROLE=$app_role_a (expected primary)" \
            "kubectl exec $pod -n $ns -c inspector-a -- env | grep '^APP_ROLE='"
    fi

    local app_role_b
    app_role_b=$(get_env "$pod" "$ns" "APP_ROLE" "inspector-b" || echo "")
    if [[ "$app_role_b" == "secondary" ]]; then
        pass "inspector-b: APP_ROLE=secondary"
    else
        fail_with_cmd "inspector-b: APP_ROLE=$app_role_b (expected secondary)" \
            "kubectl exec $pod -n $ns -c inspector-b -- env | grep '^APP_ROLE='"
    fi

    if label_matches "$pod" "$ns" "app" "idbox"; then
        pass "Label app=idbox"
    else
        fail "Label app is missing or incorrect"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Sequential init containers ==="
    local pod="report"
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
    if [[ "$phase" == "Succeeded" ]]; then
        pass "Pod phase is Succeeded"
    else
        fail "Pod phase is $phase (expected Succeeded)"
    fi

    local init_names
    init_names=$(get_init_container_names "$pod" "$ns")
    if [[ "$init_names" == *"fetcher"* ]] && [[ "$init_names" == *"transformer"* ]]; then
        pass "Init containers: fetcher and transformer"
    else
        fail "Init container names: $init_names"
    fi

    if logs_contain "$pod" "$ns" "ALPHA" "printer" && \
       logs_contain "$pod" "$ns" "BETA" "printer" && \
       logs_contain "$pod" "$ns" "GAMMA" "printer"; then
        pass "Printer logs contain uppercase ALPHA, BETA, GAMMA"
    else
        fail "Printer logs missing expected uppercase content"
        info "Hint: Check transformer logic"
    fi

    if has_emptydir_volume "$pod" "$ns"; then
        pass "Volume is emptyDir"
    else
        fail_with_cmd "Volume is not an emptyDir" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.volumes[0]}'"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multiple bugs to fix ==="
    local pod="multibug"
    local ns="ex-5-1"

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
    if [[ "$phase" == "Running" ]] || [[ "$phase" == "Succeeded" ]]; then
        pass "Pod phase is $phase (working correctly)"
    else
        fail "Pod phase is $phase (expected Running or Succeeded)"
        info "Hint: Check image tag, command format, and label references"
    fi

    local image
    image=$(get_image "$pod" "$ns")
    if [[ "$image" != *"2.99"* ]] && [[ "$image" == busybox* ]]; then
        pass "Image is a valid busybox tag: $image"
    else
        fail "Image is $image (should be valid busybox, not 2.99)"
    fi

    if logs_contain "$pod" "$ns" "starting multibug"; then
        pass "Logs contain 'starting multibug'"
    else
        fail "Logs do not contain 'starting multibug'"
    fi

    if label_matches "$pod" "$ns" "tier" "backend"; then
        pass "Label tier=backend"
    else
        fail "Label tier is missing or incorrect"
    fi

    local app_tier
    app_tier=$(get_env "$pod" "$ns" "APP_TIER" || echo "")
    if [[ "$app_tier" == "backend" ]]; then
        pass "APP_TIER=backend (from downward API)"
    else
        fail_with_cmd "APP_TIER=$app_tier (expected backend)" \
            "kubectl exec $pod -n $ns -- env | grep '^APP_TIER='"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Init container coordination issue ==="
    local pod="coord"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Succeeded" ]]; then
        pass "Pod phase is Succeeded"
    else
        fail "Pod phase is $phase (expected Succeeded)"
    fi

    local init_reason
    init_reason=$(get_init_terminated_reason "$pod" "$ns" 0)
    if [[ "$init_reason" == "Completed" ]]; then
        pass "Init container (preparer) completed"
    else
        fail "Init container reason: $init_reason"
    fi

    if logs_contain "$pod" "$ns" "payload-ready" "consumer" && \
       logs_contain "$pod" "$ns" "consumer done" "consumer"; then
        pass "Consumer logs contain payload-ready and consumer done"
    else
        fail "Consumer logs missing expected output"
        info "Hint: Check where init container writes vs. where it mounts the volume"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Subtle init and restart policy issues ==="
    local pod="subtle"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 35  # Worker sleeps 30s

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Succeeded" ]]; then
        pass "Pod phase is Succeeded"
    else
        fail "Pod phase is $phase (expected Succeeded)"
        info "Hint: Check init container command and restartPolicy"
    fi

    local init_reason
    init_reason=$(get_init_terminated_reason "$pod" "$ns" 0)
    if [[ "$init_reason" == "Completed" ]]; then
        pass "Init container (seed) completed"
    else
        fail "Init container reason: $init_reason"
    fi

    if logs_contain "$pod" "$ns" "found marker: seeded" "worker"; then
        pass "Worker logs contain 'found marker: seeded'"
    else
        fail "Worker logs missing expected marker message"
        info "Hint: Init container command may not be executing the script"
    fi

    local restart_policy
    restart_policy=$(get_restart_policy "$pod" "$ns")
    if [[ "$restart_policy" != "Always" ]]; then
        pass "Restart policy is $restart_policy (not Always)"
    else
        fail "Restart policy is Always (should be Never or OnFailure for completing workload)"
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
