#!/usr/bin/env bash
#
# verify.sh - Automated verification for storage-homework.md
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

# Helper: check if StorageClass exists
sc_exists() {
    kubectl get sc "$1" &>/dev/null
}

# Helper: get StorageClass provisioner
get_sc_provisioner() {
    local sc=$1
    kubectl get sc "$sc" -o jsonpath='{.provisioner}' 2>/dev/null
}

# Helper: get StorageClass reclaim policy
get_sc_reclaim_policy() {
    local sc=$1
    kubectl get sc "$sc" -o jsonpath='{.reclaimPolicy}' 2>/dev/null
}

# Helper: get StorageClass binding mode
get_sc_binding_mode() {
    local sc=$1
    kubectl get sc "$sc" -o jsonpath='{.volumeBindingMode}' 2>/dev/null
}

# Helper: get StorageClass volume expansion
get_sc_allow_expansion() {
    local sc=$1
    kubectl get sc "$sc" -o jsonpath='{.allowVolumeExpansion}' 2>/dev/null
}

# Helper: check if PVC exists
pvc_exists() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" &>/dev/null
}

# Helper: get PVC status phase
get_pvc_status() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: get PVC storage class
get_pvc_storage_class() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.storageClassName}' 2>/dev/null
}

# Helper: get PVC volume name
get_pvc_volume_name() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.volumeName}' 2>/dev/null
}

# Helper: get PVC capacity
get_pvc_capacity() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.capacity.storage}' 2>/dev/null
}

# Helper: get PVC requested storage
get_pvc_requested_storage() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.resources.requests.storage}' 2>/dev/null
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

# Helper: get PV phase
get_pv_phase() {
    local pv=$1
    kubectl get pv "$pv" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: check if PV exists
pv_exists() {
    local pv=$1
    kubectl get pv "$pv" &>/dev/null
}

# Helper: get default storage class name
get_default_sc() {
    kubectl get sc -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | head -n1
}

# Helper: count default storage classes
count_default_sc() {
    kubectl get sc -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")]}{.metadata.name}{"\n"}{end}' 2>/dev/null | wc -l
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: List StorageClasses and identify default ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local default_sc
    default_sc=$(get_default_sc)
    if [[ "$default_sc" == "standard" ]]; then
        pass "Default StorageClass is 'standard'"
    else
        fail_with_cmd "Default StorageClass is '$default_sc' (expected 'standard')" \
            "kubectl get sc -o jsonpath='{range .items[?(@.metadata.annotations.storageclass\\.kubernetes\\.io/is-default-class==\"true\")]}{.metadata.name}{\"\\n\"}{end}'"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: PVC uses default StorageClass ==="
    local pvc="defaulted"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail "PVC $pvc not found in namespace $ns"
        return
    fi

    local sc
    sc=$(get_pvc_storage_class "$pvc" "$ns")
    if [[ "$sc" == "standard" ]]; then
        pass "PVC storageClassName is 'standard' (defaulted)"
    else
        fail_with_cmd "PVC storageClassName is '$sc' (expected 'standard')" \
            "kubectl get pvc $pvc -n $ns -o jsonpath='{.spec.storageClassName}'"
    fi

    local status
    status=$(get_pvc_status "$pvc" "$ns")
    if [[ "$status" == "Pending" ]] || [[ "$status" == "Bound" ]]; then
        pass "PVC status is $status (acceptable for WaitForFirstConsumer)"
    else
        fail_with_cmd "PVC status is $status (expected Pending or Bound)" \
            "kubectl get pvc $pvc -n $ns -o jsonpath='{.status.phase}'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Verify default StorageClass attributes ==="

    if ! sc_exists "standard"; then
        fail "StorageClass 'standard' does not exist"
        return
    fi

    local provisioner
    provisioner=$(get_sc_provisioner "standard")
    if [[ "$provisioner" == "rancher.io/local-path" ]]; then
        pass "Provisioner is rancher.io/local-path"
    else
        fail_with_cmd "Provisioner is '$provisioner' (expected rancher.io/local-path)" \
            "kubectl get sc standard -o jsonpath='{.provisioner}'"
    fi

    local reclaim_policy
    reclaim_policy=$(get_sc_reclaim_policy "standard")
    if [[ "$reclaim_policy" == "Delete" ]]; then
        pass "Reclaim policy is Delete"
    else
        fail_with_cmd "Reclaim policy is '$reclaim_policy' (expected Delete)" \
            "kubectl get sc standard -o jsonpath='{.reclaimPolicy}'"
    fi

    local binding_mode
    binding_mode=$(get_sc_binding_mode "standard")
    if [[ "$binding_mode" == "WaitForFirstConsumer" ]]; then
        pass "Volume binding mode is WaitForFirstConsumer"
    else
        fail_with_cmd "Volume binding mode is '$binding_mode' (expected WaitForFirstConsumer)" \
            "kubectl get sc standard -o jsonpath='{.volumeBindingMode}'"
    fi

    local allow_expansion
    allow_expansion=$(get_sc_allow_expansion "standard")
    if [[ "$allow_expansion" == "false" ]] || [[ -z "$allow_expansion" ]]; then
        pass "Volume expansion is false (not enabled)"
    else
        fail_with_cmd "Volume expansion is '$allow_expansion' (expected false)" \
            "kubectl get sc standard -o jsonpath='{.allowVolumeExpansion}'"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Dynamic provisioning with standard StorageClass ==="
    local pvc="dyn-claim"
    local pod="dyn-pod"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail "PVC $pvc not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local status
    status=$(get_pvc_status "$pvc" "$ns")
    if [[ "$status" == "Bound" ]]; then
        pass "PVC status is Bound"
    else
        fail_with_cmd "PVC status is '$status' (expected Bound)" \
            "kubectl get pvc $pvc -n $ns -o jsonpath='{.status.phase}'"
    fi

    local volume_name
    volume_name=$(get_pvc_volume_name "$pvc" "$ns")
    if [[ "$volume_name" == pvc-* ]]; then
        pass "PVC volume name starts with 'pvc-' (dynamically provisioned)"
    else
        fail_with_cmd "PVC volume name is '$volume_name' (expected pvc-*)" \
            "kubectl get pvc $pvc -n $ns -o jsonpath='{.spec.volumeName}'"
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is '$phase' (expected Running)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}'"
    fi

    local content
    content=$(kubectl exec -n "$ns" "$pod" -- cat /data/f 2>/dev/null || echo "")
    if [[ "$content" == "dynamic-hello" ]]; then
        pass "Pod wrote 'dynamic-hello' to volume"
    else
        fail_with_cmd "File content is '$content' (expected 'dynamic-hello')" \
            "kubectl exec -n $ns $pod -- cat /data/f"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Compare static and dynamic binding ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "static-claim" "$ns"; then
        fail "PVC static-claim not found in namespace $ns"
        return
    fi

    if ! pvc_exists "dynamic-claim" "$ns"; then
        fail "PVC dynamic-claim not found in namespace $ns"
        return
    fi

    sleep 5

    local static_volume
    static_volume=$(get_pvc_volume_name "static-claim" "$ns")
    if [[ "$static_volume" == "ex-2-2-static" ]]; then
        pass "static-claim bound to ex-2-2-static (static PV)"
    else
        fail_with_cmd "static-claim bound to '$static_volume' (expected ex-2-2-static)" \
            "kubectl get pvc static-claim -n $ns -o jsonpath='{.spec.volumeName}'"
    fi

    local dynamic_volume
    dynamic_volume=$(get_pvc_volume_name "dynamic-claim" "$ns")
    if [[ "$dynamic_volume" == pvc-* ]]; then
        pass "dynamic-claim bound to dynamically provisioned PV ($dynamic_volume)"
    else
        fail_with_cmd "dynamic-claim bound to '$dynamic_volume' (expected pvc-*)" \
            "kubectl get pvc dynamic-claim -n $ns -o jsonpath='{.spec.volumeName}'"
    fi

    if pod_exists "static-app" "$ns"; then
        local static_phase
        static_phase=$(get_phase "static-app" "$ns")
        if [[ "$static_phase" == "Running" ]]; then
            pass "static-app pod is Running"
        else
            fail_with_cmd "static-app phase is '$static_phase' (expected Running)" \
                "kubectl get pod static-app -n $ns"
        fi
    fi

    if pod_exists "dynamic-app" "$ns"; then
        local dynamic_phase
        dynamic_phase=$(get_phase "dynamic-app" "$ns")
        if [[ "$dynamic_phase" == "Running" ]]; then
            pass "dynamic-app pod is Running"
        else
            fail_with_cmd "dynamic-app phase is '$dynamic_phase' (expected Running)" \
                "kubectl get pod dynamic-app -n $ns"
        fi
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Verify reclaim policy differences ==="

    if pv_exists "ex-2-2-static"; then
        local pv_phase
        pv_phase=$(get_pv_phase "ex-2-2-static")
        if [[ "$pv_phase" == "Released" ]] || [[ "$pv_phase" == "Available" ]]; then
            pass "Static PV ex-2-2-static is $pv_phase (Retain policy kept it)"
        else
            fail_with_cmd "Static PV phase is '$pv_phase' (expected Released or Available)" \
                "kubectl get pv ex-2-2-static -o jsonpath='{.status.phase}'"
        fi
    else
        info "Static PV ex-2-2-static not found (check if exercise 2.2 cleanup was run)"
    fi

    local dynamic_pvs
    dynamic_pvs=$(kubectl get pv -o name 2>/dev/null | grep -c "pvc-" || echo "0")
    info "Found $dynamic_pvs dynamic PV(s) (Delete policy should remove them after PVC deletion)"
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix PVC with wrong StorageClass name ==="
    local pvc="typo-class"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail "PVC $pvc not found in namespace $ns"
        return
    fi

    local sc
    sc=$(get_pvc_storage_class "$pvc" "$ns")
    if [[ "$sc" == "standard" ]]; then
        pass "PVC storageClassName fixed to 'standard'"
    else
        fail_with_cmd "PVC storageClassName is '$sc' (expected 'standard' after fix)" \
            "kubectl get pvc $pvc -n $ns -o jsonpath='{.spec.storageClassName}'"
        info "Hint: The original had 'stanrad' (typo)"
        return
    fi

    if pod_exists "probe" "$ns"; then
        sleep 5
        local status
        status=$(get_pvc_status "$pvc" "$ns")
        if [[ "$status" == "Bound" ]]; then
            pass "PVC is Bound (provisioner created volume)"
        else
            fail_with_cmd "PVC status is '$status' (expected Bound after fix)" \
                "kubectl get pvc $pvc -n $ns"
        fi
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix provisioner scaled to zero ==="
    local pvc="no-provisioner"
    local pod="needs-storage"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local provisioner_pods
    provisioner_pods=$(kubectl get pods -n local-path-storage -l app=local-path-provisioner --field-selector=status.phase=Running -o name 2>/dev/null | wc -l)
    if [[ "$provisioner_pods" -ge 1 ]]; then
        pass "local-path-provisioner is running"
    else
        fail_with_cmd "local-path-provisioner has no running pods (expected at least 1)" \
            "kubectl get pods -n local-path-storage"
        info "Hint: Scale deployment back to 1 replica"
        return
    fi

    if pvc_exists "$pvc" "$ns"; then
        sleep 5
        local status
        status=$(get_pvc_status "$pvc" "$ns")
        if [[ "$status" == "Bound" ]]; then
            pass "PVC no-provisioner is Bound"
        else
            fail_with_cmd "PVC status is '$status' (expected Bound after provisioner fix)" \
                "kubectl get pvc $pvc -n $ns"
        fi
    fi

    if pod_exists "$pod" "$ns"; then
        sleep 5
        local phase
        phase=$(get_phase "$pod" "$ns")
        if [[ "$phase" == "Running" ]]; then
            pass "Pod needs-storage is Running"
        else
            fail_with_cmd "Pod phase is '$phase' (expected Running)" \
                "kubectl get pod $pod -n $ns"
        fi
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix PVC with non-existent provisioner ==="
    local pvc="ghost-claim"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail "PVC $pvc not found in namespace $ns"
        return
    fi

    local sc
    sc=$(get_pvc_storage_class "$pvc" "$ns")
    if [[ "$sc" == "standard" ]]; then
        pass "PVC storageClassName fixed to 'standard'"
    else
        fail_with_cmd "PVC storageClassName is '$sc' (expected 'standard' after fix)" \
            "kubectl get pvc $pvc -n $ns -o jsonpath='{.spec.storageClassName}'"
        info "Hint: Original used 'ex-3-3-fake' with provisioner 'example.com/nonexistent'"
        return
    fi

    if pod_exists "hungry" "$ns"; then
        sleep 5
        local status
        status=$(get_pvc_status "$pvc" "$ns")
        if [[ "$status" == "Bound" ]]; then
            pass "PVC is Bound (real provisioner created volume)"
        else
            fail_with_cmd "PVC status is '$status' (expected Bound after fix)" \
                "kubectl get pvc $pvc -n $ns"
        fi
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Create custom StorageClass ==="
    local sc="ex-4-1-custom"

    if ! sc_exists "$sc"; then
        fail "StorageClass $sc does not exist"
        return
    fi

    local provisioner
    provisioner=$(get_sc_provisioner "$sc")
    if [[ "$provisioner" == "rancher.io/local-path" ]]; then
        pass "Provisioner is rancher.io/local-path"
    else
        fail_with_cmd "Provisioner is '$provisioner' (expected rancher.io/local-path)" \
            "kubectl get sc $sc -o jsonpath='{.provisioner}'"
    fi

    local reclaim_policy
    reclaim_policy=$(get_sc_reclaim_policy "$sc")
    if [[ "$reclaim_policy" == "Retain" ]]; then
        pass "Reclaim policy is Retain"
    else
        fail_with_cmd "Reclaim policy is '$reclaim_policy' (expected Retain)" \
            "kubectl get sc $sc -o jsonpath='{.reclaimPolicy}'"
    fi

    local binding_mode
    binding_mode=$(get_sc_binding_mode "$sc")
    if [[ "$binding_mode" == "Immediate" ]]; then
        pass "Volume binding mode is Immediate"
    else
        fail_with_cmd "Volume binding mode is '$binding_mode' (expected Immediate)" \
            "kubectl get sc $sc -o jsonpath='{.volumeBindingMode}'"
    fi

    local allow_expansion
    allow_expansion=$(get_sc_allow_expansion "$sc")
    if [[ "$allow_expansion" == "true" ]]; then
        pass "Volume expansion is true"
    else
        fail_with_cmd "Volume expansion is '$allow_expansion' (expected true)" \
            "kubectl get sc $sc -o jsonpath='{.allowVolumeExpansion}'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Test volume expansion ==="
    local pvc="growable"
    local pod="grower"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail "PVC $pvc not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local requested
    requested=$(get_pvc_requested_storage "$pvc" "$ns")
    if [[ "$requested" == "1Gi" ]]; then
        pass "PVC requested storage expanded to 1Gi"
    else
        info "PVC requested storage is $requested (may still be 500Mi if not expanded yet)"
    fi

    if [[ "$requested" == "1Gi" ]]; then
        sleep 15
        local capacity
        capacity=$(get_pvc_capacity "$pvc" "$ns")
        if [[ "$capacity" == "1Gi" ]]; then
            pass "PVC capacity expanded to 1Gi"
        else
            fail_with_cmd "PVC capacity is '$capacity' (expected 1Gi after expansion)" \
                "kubectl get pvc $pvc -n $ns -o jsonpath='{.status.capacity.storage}'"
        fi
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Contrast WaitForFirstConsumer and Immediate ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "immediately-bound" "$ns"; then
        fail "PVC immediately-bound not found in namespace $ns"
        return
    fi

    if ! pvc_exists "wait-bound" "$ns"; then
        fail "PVC wait-bound not found in namespace $ns"
        return
    fi

    sleep 10

    local immediate_status
    immediate_status=$(get_pvc_status "immediately-bound" "$ns")
    if [[ "$immediate_status" == "Bound" ]]; then
        pass "immediately-bound PVC is Bound (Immediate binding mode)"
    else
        fail_with_cmd "immediately-bound status is '$immediate_status' (expected Bound)" \
            "kubectl get pvc immediately-bound -n $ns -o jsonpath='{.status.phase}'"
    fi

    local wait_status
    wait_status=$(get_pvc_status "wait-bound" "$ns")
    if [[ "$wait_status" == "Pending" ]]; then
        pass "wait-bound PVC is Pending (WaitForFirstConsumer, no pod yet)"
    else
        info "wait-bound status is '$wait_status' (expected Pending; may be Bound if pod was created)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Switch default StorageClass ==="

    local default_count
    default_count=$(count_default_sc)
    if [[ "$default_count" -eq 1 ]]; then
        pass "Exactly one default StorageClass exists"
    else
        fail_with_cmd "Found $default_count default StorageClass(es) (expected 1)" \
            "kubectl get sc | grep '(default)'"
        info "Hint: Only one class should have storageclass.kubernetes.io/is-default-class=true"
    fi

    local default_sc
    default_sc=$(get_default_sc)
    if [[ "$default_sc" == "standard" ]]; then
        pass "Default StorageClass restored to 'standard'"
    else
        info "Default StorageClass is '$default_sc' (expected 'standard' after restoration)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Grow PVC from 500Mi to 2Gi ==="
    local pvc="shrink-happens-later"
    local pod="sizer"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail "PVC $pvc not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local requested
    requested=$(get_pvc_requested_storage "$pvc" "$ns")
    if [[ "$requested" == "2Gi" ]]; then
        pass "PVC requested storage expanded to 2Gi"
    else
        info "PVC requested storage is $requested (may still be 500Mi if not expanded yet)"
    fi

    if [[ "$requested" == "2Gi" ]]; then
        sleep 15
        local capacity
        capacity=$(get_pvc_capacity "$pvc" "$ns")
        if [[ "$capacity" == "2Gi" ]]; then
            pass "PVC capacity expanded to 2Gi"
        else
            fail_with_cmd "PVC capacity is '$capacity' (expected 2Gi after expansion)" \
                "kubectl get pvc $pvc -n $ns -o jsonpath='{.status.capacity.storage}'"
        fi
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Three-tier storage strategy ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Verify StorageClasses exist
    local classes=("ex-5-3-database" "ex-5-3-cache" "ex-5-3-archive")
    for sc in "${classes[@]}"; do
        if sc_exists "$sc"; then
            pass "StorageClass $sc exists"
        else
            fail "StorageClass $sc does not exist"
        fi
    done

    # Verify database StorageClass
    if sc_exists "ex-5-3-database"; then
        local db_reclaim
        db_reclaim=$(get_sc_reclaim_policy "ex-5-3-database")
        if [[ "$db_reclaim" == "Retain" ]]; then
            pass "ex-5-3-database has Retain policy"
        else
            fail_with_cmd "ex-5-3-database reclaim policy is '$db_reclaim' (expected Retain)" \
                "kubectl get sc ex-5-3-database -o jsonpath='{.reclaimPolicy}'"
        fi
    fi

    # Verify cache StorageClass
    if sc_exists "ex-5-3-cache"; then
        local cache_reclaim
        cache_reclaim=$(get_sc_reclaim_policy "ex-5-3-cache")
        if [[ "$cache_reclaim" == "Delete" ]]; then
            pass "ex-5-3-cache has Delete policy"
        else
            fail_with_cmd "ex-5-3-cache reclaim policy is '$cache_reclaim' (expected Delete)" \
                "kubectl get sc ex-5-3-cache -o jsonpath='{.reclaimPolicy}'"
        fi
    fi

    # Verify archive StorageClass
    if sc_exists "ex-5-3-archive"; then
        local archive_reclaim
        archive_reclaim=$(get_sc_reclaim_policy "ex-5-3-archive")
        if [[ "$archive_reclaim" == "Retain" ]]; then
            pass "ex-5-3-archive has Retain policy"
        else
            fail_with_cmd "ex-5-3-archive reclaim policy is '$archive_reclaim' (expected Retain)" \
                "kubectl get sc ex-5-3-archive -o jsonpath='{.reclaimPolicy}'"
        fi

        local archive_expansion
        archive_expansion=$(get_sc_allow_expansion "ex-5-3-archive")
        if [[ "$archive_expansion" == "true" ]]; then
            pass "ex-5-3-archive allows volume expansion"
        else
            fail_with_cmd "ex-5-3-archive allowVolumeExpansion is '$archive_expansion' (expected true)" \
                "kubectl get sc ex-5-3-archive -o jsonpath='{.allowVolumeExpansion}'"
        fi
    fi

    # Verify PVCs
    local pvcs=("db-claim" "cache-claim" "archive-claim")
    for pvc in "${pvcs[@]}"; do
        if pvc_exists "$pvc" "$ns"; then
            local status
            status=$(get_pvc_status "$pvc" "$ns")
            if [[ "$status" == "Bound" ]] || [[ "$status" == "Pending" ]]; then
                pass "PVC $pvc status is $status"
            else
                fail_with_cmd "PVC $pvc status is '$status'" \
                    "kubectl get pvc $pvc -n $ns"
            fi
        fi
    done

    # If PVCs were deleted, check PV reclaim behavior
    if pvc_exists "db-claim" "$ns"; then
        local db_pv
        db_pv=$(get_pvc_volume_name "db-claim" "$ns")
        if [[ -n "$db_pv" ]] && pv_exists "$db_pv"; then
            info "db-claim PV is $db_pv (should be Released after deletion)"
        fi
    fi

    if pvc_exists "archive-claim" "$ns"; then
        local archive_pv
        archive_pv=$(get_pvc_volume_name "archive-claim" "$ns")
        if [[ -n "$archive_pv" ]] && pv_exists "$archive_pv"; then
            info "archive-claim PV is $archive_pv (should be Released after deletion)"
        fi
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: StorageClass Basics"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Dynamic Provisioning"
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
    echo "# Level 4: Advanced Configuration"
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
