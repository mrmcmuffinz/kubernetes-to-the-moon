#!/usr/bin/env bash
#
# verify.sh - Automated verification for storage-homework.md (assignment 2)
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

# Helper: check if PVC exists
pvc_exists() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" &>/dev/null
}

# Helper: get PVC status (phase)
get_pvc_status() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: get PVC's bound PV name
get_pvc_volume() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.volumeName}' 2>/dev/null
}

# Helper: get PV status (phase)
get_pv_status() {
    local pv=$1
    kubectl get pv "$pv" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: get storage class from PVC
get_pvc_storage_class() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.storageClassName}' 2>/dev/null
}

# Helper: get PVC capacity (as allocated)
get_pvc_capacity() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.capacity.storage}' 2>/dev/null
}

# Helper: get PVC access modes
get_pvc_access_modes() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.accessModes[0]}' 2>/dev/null
}

# Helper: check if pod exists
pod_exists() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

# Helper: get pod phase
get_phase() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: get pod ready status
get_ready() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null
}

# Helper: check if PV has claimRef
pv_has_claimref() {
    local pv=$1
    local ref
    ref=$(kubectl get pv "$pv" -o jsonpath='{.spec.claimRef}' 2>/dev/null)
    [[ -n "$ref" ]]
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Create matched PV and PVC ==="
    local pv="ex-1-1-pv"
    local pvc="basic-claim"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! kubectl get pv "$pv" &>/dev/null; then
        fail "PV $pv does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    local pvc_phase
    pvc_phase=$(get_pvc_status "$pvc" "$ns")
    if [[ "$pvc_phase" == "Bound" ]]; then
        pass "PVC $pvc is Bound"
    else
        fail_with_cmd "PVC phase is $pvc_phase (expected Bound)" \
            "kubectl describe pvc -n $ns $pvc"
    fi

    local bound_pv
    bound_pv=$(get_pvc_volume "$pvc" "$ns")
    if [[ "$bound_pv" == "$pv" ]]; then
        pass "PVC is bound to $pv"
    else
        fail_with_cmd "PVC is bound to $bound_pv (expected $pv)" \
            "kubectl get pvc -n $ns $pvc -o yaml"
    fi

    local pv_phase
    pv_phase=$(get_pv_status "$pv")
    if [[ "$pv_phase" == "Bound" ]]; then
        pass "PV $pv is Bound"
    else
        fail_with_cmd "PV phase is $pv_phase (expected Bound)" \
            "kubectl describe pv $pv"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Mount PVC in pod and verify data persistence ==="
    local pv="ex-1-2-pv"
    local pvc="app-claim"
    local pod="data-app"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail_with_cmd "Pod $pod not found in namespace $ns" \
            "kubectl get pods -n $ns"
        return
    fi

    sleep 3

    local pvc_phase
    pvc_phase=$(get_pvc_status "$pvc" "$ns")
    if [[ "$pvc_phase" == "Bound" ]]; then
        pass "PVC $pvc is Bound"
    else
        fail_with_cmd "PVC phase is $pvc_phase (expected Bound)" \
            "kubectl describe pvc -n $ns $pvc"
    fi

    local content
    content=$(kubectl exec -n "$ns" "$pod" -- cat /data/marker 2>/dev/null || echo "")
    if [[ "$content" == "kept-forever" ]]; then
        pass "Pod can read 'kept-forever' from /data/marker"
    else
        fail_with_cmd "Expected 'kept-forever', got '$content'" \
            "kubectl exec -n $ns $pod -- cat /data/marker"
    fi

    local host_content
    host_content=$(nerdctl exec kind-control-plane cat /ex-1-2/marker 2>/dev/null || echo "")
    if [[ "$host_content" == "kept-forever" ]]; then
        pass "Data persisted to hostPath /ex-1-2/marker"
    else
        fail_with_cmd "Host file missing or incorrect: '$host_content'" \
            "nerdctl exec kind-control-plane cat /ex-1-2/marker"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: List PVCs with bound PV info ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local pvc_count
    pvc_count=$(kubectl get pvc -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$pvc_count" -eq 3 ]]; then
        pass "Three PVCs exist in namespace $ns"
    else
        fail_with_cmd "$pvc_count PVCs found (expected 3)" \
            "kubectl get pvc -n $ns"
    fi

    local bound_count
    bound_count=$(kubectl get pvc -n "$ns" -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -o Bound | wc -l)
    if [[ "$bound_count" -eq 3 ]]; then
        pass "All three PVCs are Bound"
    else
        fail_with_cmd "Only $bound_count PVCs are Bound (expected 3)" \
            "kubectl get pvc -n $ns"
    fi

    # Verify specific PVCs and their sizes
    local claim_one_size
    claim_one_size=$(get_pvc_capacity "claim-one" "$ns")
    if [[ "$claim_one_size" == "500Mi" ]]; then
        pass "claim-one capacity is 500Mi"
    else
        fail "claim-one capacity is $claim_one_size (expected 500Mi)"
    fi

    local claim_two_size
    claim_two_size=$(get_pvc_capacity "claim-two" "$ns")
    if [[ "$claim_two_size" == "1Gi" ]]; then
        pass "claim-two capacity is 1Gi"
    else
        fail "claim-two capacity is $claim_two_size (expected 1Gi)"
    fi

    local claim_three_size
    claim_three_size=$(get_pvc_capacity "claim-three" "$ns")
    if [[ "$claim_three_size" == "2Gi" ]]; then
        pass "claim-three capacity is 2Gi"
    else
        fail "claim-three capacity is $claim_three_size (expected 2Gi)"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Binder picks smallest matching PV ==="
    local pvc="smallest-fit"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    local pvc_phase
    pvc_phase=$(get_pvc_status "$pvc" "$ns")
    if [[ "$pvc_phase" == "Bound" ]]; then
        pass "PVC $pvc is Bound"
    else
        fail_with_cmd "PVC phase is $pvc_phase (expected Bound)" \
            "kubectl describe pvc -n $ns $pvc"
    fi

    local bound_pv
    bound_pv=$(get_pvc_volume "$pvc" "$ns")
    if [[ "$bound_pv" == "ex-2-1-medium" ]]; then
        pass "PVC is bound to ex-2-1-medium (smallest sufficient PV)"
    else
        fail_with_cmd "PVC is bound to $bound_pv (expected ex-2-1-medium)" \
            "kubectl get pvc -n $ns $pvc -o yaml"
    fi

    local small_phase
    small_phase=$(get_pv_status "ex-2-1-small")
    if [[ "$small_phase" == "Available" ]]; then
        pass "ex-2-1-small PV remains Available (too small)"
    else
        fail "ex-2-1-small phase is $small_phase (expected Available)"
    fi

    local large_phase
    large_phase=$(get_pv_status "ex-2-1-large")
    if [[ "$large_phase" == "Available" ]]; then
        pass "ex-2-1-large PV remains Available (not selected)"
    else
        fail "ex-2-1-large phase is $large_phase (expected Available)"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Use label selector to pick PV ==="
    local pvc="pick-bulk"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    local bound_pv
    bound_pv=$(get_pvc_volume "$pvc" "$ns")
    if [[ "$bound_pv" == "ex-2-2-bulk" ]]; then
        pass "PVC is bound to ex-2-2-bulk (label selector matched)"
    else
        fail_with_cmd "PVC is bound to $bound_pv (expected ex-2-2-bulk)" \
            "kubectl get pvc -n $ns $pvc -o yaml"
    fi

    local fast_phase
    fast_phase=$(get_pv_status "ex-2-2-fast")
    if [[ "$fast_phase" == "Available" ]]; then
        pass "ex-2-2-fast PV remains Available (not selected by label)"
    else
        fail "ex-2-2-fast phase is $fast_phase (expected Available)"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Access mode semantics with multiple modes ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "needs-rwo" "$ns"; then
        fail_with_cmd "PVC needs-rwo not found" \
            "kubectl get pvc -n $ns"
        return
    fi

    if ! pvc_exists "needs-both" "$ns"; then
        fail_with_cmd "PVC needs-both not found" \
            "kubectl get pvc -n $ns"
        return
    fi

    local rwo_phase
    rwo_phase=$(get_pvc_status "needs-rwo" "$ns")
    if [[ "$rwo_phase" == "Bound" ]]; then
        pass "PVC needs-rwo is Bound"
    else
        fail_with_cmd "PVC needs-rwo phase is $rwo_phase (expected Bound)" \
            "kubectl describe pvc -n $ns needs-rwo"
    fi

    local both_phase
    both_phase=$(get_pvc_status "needs-both" "$ns")
    if [[ "$both_phase" == "Pending" ]]; then
        pass "PVC needs-both is Pending (PV already claimed)"
    else
        fail_with_cmd "PVC needs-both phase is $both_phase (expected Pending)" \
            "kubectl describe pvc -n $ns needs-both"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug capacity mismatch ==="
    local pvc="pending-claim"
    local pv="ex-3-1-pv"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    local pvc_phase
    pvc_phase=$(get_pvc_status "$pvc" "$ns")
    if [[ "$pvc_phase" == "Bound" ]]; then
        pass "PVC $pvc is now Bound (issue fixed)"
    else
        fail_with_cmd "PVC phase is $pvc_phase (expected Bound after fixing capacity)" \
            "kubectl describe pvc -n $ns $pvc"
    fi

    local bound_pv
    bound_pv=$(get_pvc_volume "$pvc" "$ns")
    if [[ "$bound_pv" == "$pv" ]]; then
        pass "PVC is bound to $pv"
    else
        fail_with_cmd "PVC is bound to $bound_pv (expected $pv)" \
            "kubectl get pvc -n $ns $pvc -o yaml"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug access mode mismatch ==="
    local pvc="wrong-mode"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    local pvc_phase
    pvc_phase=$(get_pvc_status "$pvc" "$ns")
    if [[ "$pvc_phase" == "Bound" ]]; then
        pass "PVC $pvc is now Bound (access mode fixed)"
    else
        fail_with_cmd "PVC phase is $pvc_phase (expected Bound after fixing access mode)" \
            "kubectl describe pvc -n $ns $pvc"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug label selector mismatch ==="
    local pvc="wrong-tier"
    local pv="ex-3-3-pv"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    local pvc_phase
    pvc_phase=$(get_pvc_status "$pvc" "$ns")
    if [[ "$pvc_phase" == "Bound" ]]; then
        pass "PVC $pvc is now Bound (label selector fixed)"
    else
        fail_with_cmd "PVC phase is $pvc_phase (expected Bound after fixing label selector)" \
            "kubectl describe pvc -n $ns $pvc"
    fi

    local bound_pv
    bound_pv=$(get_pvc_volume "$pvc" "$ns")
    if [[ "$bound_pv" == "$pv" ]]; then
        pass "PVC is bound to $pv"
    else
        fail_with_cmd "PVC is bound to $bound_pv (expected $pv)" \
            "kubectl get pvc -n $ns $pvc -o yaml"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Test Retain reclaim policy ==="
    local pv="ex-4-1-pv"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! kubectl get pv "$pv" &>/dev/null; then
        fail "PV $pv does not exist"
        return
    fi

    # After the PVC is deleted, PV should be Released
    local pv_phase
    pv_phase=$(get_pv_status "$pv")
    if [[ "$pv_phase" == "Released" ]]; then
        pass "PV $pv is Released (Retain policy preserved data)"
    else
        fail_with_cmd "PV phase is $pv_phase (expected Released after PVC deletion)" \
            "kubectl describe pv $pv"
    fi

    # Check data persisted on host
    local host_content
    host_content=$(nerdctl exec kind-control-plane cat /ex-4-1/record 2>/dev/null || echo "")
    if [[ "$host_content" == "payload" ]]; then
        pass "Data 'payload' persisted in /ex-4-1/record"
    else
        fail_with_cmd "Host file missing or incorrect: '$host_content'" \
            "nerdctl exec kind-control-plane cat /ex-4-1/record"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Reuse Released PV ==="
    local pv="ex-4-2-pv"
    local pvc="reuser"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! kubectl get pv "$pv" &>/dev/null; then
        fail "PV $pv does not exist"
        return
    fi

    # PV should not have claimRef anymore
    if pv_has_claimref "$pv"; then
        fail_with_cmd "PV $pv still has claimRef (should be removed)" \
            "kubectl get pv $pv -o jsonpath='{.spec.claimRef}'"
    else
        pass "PV $pv claimRef removed"
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    local bound_pv
    bound_pv=$(get_pvc_volume "$pvc" "$ns")
    if [[ "$bound_pv" == "$pv" ]]; then
        pass "PVC $pvc is bound to reused PV $pv"
    else
        fail_with_cmd "PVC is bound to $bound_pv (expected $pv)" \
            "kubectl get pvc -n $ns $pvc -o yaml"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Delete reclaim policy on hostPath ==="
    local pv="ex-4-3-pv"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # After PVC deletion, Delete policy on hostPath results in Failed
    local pv_phase
    pv_phase=$(get_pv_status "$pv")
    if [[ "$pv_phase" == "Failed" ]]; then
        pass "PV $pv is Failed (Delete policy cannot delete hostPath)"
    else
        fail_with_cmd "PV phase is $pv_phase (expected Failed)" \
            "kubectl describe pv $pv"
    fi

    # Directory should still exist on host
    if nerdctl exec kind-control-plane test -d /ex-4-3 2>/dev/null; then
        pass "Host directory /ex-4-3 still present"
    else
        fail "Host directory /ex-4-3 was removed (unexpected)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multiple pods share PVC with ReadOnlyMany ==="
    local pvc="shared-reader"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    if ! pod_exists "reader-one" "$ns"; then
        fail_with_cmd "Pod reader-one not found in namespace $ns" \
            "kubectl get pods -n $ns"
        return
    fi

    if ! pod_exists "reader-two" "$ns"; then
        fail_with_cmd "Pod reader-two not found in namespace $ns" \
            "kubectl get pods -n $ns"
        return
    fi

    sleep 3

    local pvc_mode
    pvc_mode=$(get_pvc_access_modes "$pvc" "$ns")
    if [[ "$pvc_mode" == "ReadOnlyMany" ]]; then
        pass "PVC $pvc has ReadOnlyMany access mode"
    else
        fail "PVC access mode is $pvc_mode (expected ReadOnlyMany)"
    fi

    local reader_one_logs
    reader_one_logs=$(kubectl logs -n "$ns" reader-one 2>/dev/null || echo "")
    if [[ "$reader_one_logs" == *"shared-content"* ]]; then
        pass "reader-one logs contain 'shared-content'"
    else
        fail_with_cmd "reader-one logs do not contain 'shared-content'" \
            "kubectl logs -n $ns reader-one"
    fi

    local reader_two_logs
    reader_two_logs=$(kubectl logs -n "$ns" reader-two 2>/dev/null || echo "")
    if [[ "$reader_two_logs" == *"shared-content"* ]]; then
        pass "reader-two logs contain 'shared-content'"
    else
        fail_with_cmd "reader-two logs do not contain 'shared-content'" \
            "kubectl logs -n $ns reader-two"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug compound binding failure ==="
    local pvc="compound-fail"
    local pv="ex-5-2-pv"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    local pvc_phase
    pvc_phase=$(get_pvc_status "$pvc" "$ns")
    if [[ "$pvc_phase" == "Bound" ]]; then
        pass "PVC $pvc is now Bound (all three mismatches fixed)"
    else
        fail_with_cmd "PVC phase is $pvc_phase (expected Bound after fixing capacity, access mode, and storage class)" \
            "kubectl describe pvc -n $ns $pvc"
    fi

    local bound_pv
    bound_pv=$(get_pvc_volume "$pvc" "$ns")
    if [[ "$bound_pv" == "$pv" ]]; then
        pass "PVC is bound to $pv"
    else
        fail_with_cmd "PVC is bound to $bound_pv (expected $pv)" \
            "kubectl get pvc -n $ns $pvc -o yaml"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Design PVC strategy for stateful app ==="
    local pv="ex-5-3-pv"
    local pvc="app-storage"
    local primary="primary-app"
    local backup="backup-reader"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! kubectl get pv "$pv" &>/dev/null; then
        fail "PV $pv does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail_with_cmd "PVC $pvc not found in namespace $ns" \
            "kubectl get pvc -n $ns"
        return
    fi

    if ! pod_exists "$primary" "$ns"; then
        fail_with_cmd "Pod $primary not found in namespace $ns" \
            "kubectl get pods -n $ns"
        return
    fi

    if ! pod_exists "$backup" "$ns"; then
        fail_with_cmd "Pod $backup not found in namespace $ns" \
            "kubectl get pods -n $ns"
        return
    fi

    sleep 5

    local primary_content
    primary_content=$(kubectl exec -n "$ns" "$primary" -- cat /data/db 2>/dev/null || echo "")
    if [[ "$primary_content" == "production-data" ]]; then
        pass "Primary pod wrote 'production-data' to /data/db"
    else
        fail_with_cmd "Primary pod content is '$primary_content' (expected 'production-data')" \
            "kubectl exec -n $ns $primary -- cat /data/db"
    fi

    local backup_content
    backup_content=$(kubectl exec -n "$ns" "$backup" -- cat /data/db 2>/dev/null || echo "")
    if [[ "$backup_content" == "production-data" ]]; then
        pass "Backup pod read 'production-data' from /data/db"
    else
        fail_with_cmd "Backup pod content is '$backup_content' (expected 'production-data')" \
            "kubectl exec -n $ns $backup -- cat /data/db"
    fi

    # Verify backup pod cannot write
    local write_error
    write_error=$(kubectl exec -n "$ns" "$backup" -- sh -c 'echo tamper > /data/db 2>&1 || true')
    if [[ "$write_error" == *"Read-only file system"* ]]; then
        pass "Backup pod mount is read-only (write blocked)"
    else
        fail_with_cmd "Backup pod write was not blocked: '$write_error'" \
            "kubectl exec -n $ns $backup -- sh -c 'echo test > /data/db 2>&1 || true'"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic PVC Operations"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Binding Mechanics"
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
    echo "# Level 4: Reclaim and Lifecycle"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Complex Scenarios"
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
