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

# Helper: check if volume is emptyDir
has_emptydir_volume() {
    local pod=$1
    local ns=$2
    local result
    result=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.volumes[0].emptyDir}' 2>/dev/null)
    [[ -n "$result" ]]
}

# Helper: get hostPath type
get_hostpath_type() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.volumes[0].hostPath.type}' 2>/dev/null
}

# Helper: check if PV exists
pv_exists() {
    kubectl get pv "$1" &>/dev/null
}

# Helper: get PV phase
get_pv_phase() {
    kubectl get pv "$1" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: get PV capacity
get_pv_capacity() {
    kubectl get pv "$1" -o jsonpath='{.spec.capacity.storage}' 2>/dev/null
}

# Helper: get PV access mode
get_pv_access_mode() {
    kubectl get pv "$1" -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null
}

# Helper: get PV reclaim policy
get_pv_reclaim_policy() {
    kubectl get pv "$1" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}' 2>/dev/null
}

# Helper: get PV storage class
get_pv_storage_class() {
    kubectl get pv "$1" -o jsonpath='{.spec.storageClassName}' 2>/dev/null
}

# Helper: get PV hostPath path
get_pv_hostpath() {
    kubectl get pv "$1" -o jsonpath='{.spec.hostPath.path}' 2>/dev/null
}

# Helper: check if PVC exists
pvc_exists() {
    local pvc=$1
    local ns=$2
    kubectl get pvc "$pvc" -n "$ns" &>/dev/null
}

# Helper: get PVC phase
get_pvc_phase() {
    local pvc=$1
    local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: get PVC bound volume name
get_pvc_volume() {
    local pvc=$1
    local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.volumeName}' 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: emptyDir shared between two containers ==="
    local pod="shared-scratch"
    local ns="ex-1-1"

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

    if has_emptydir_volume "$pod" "$ns"; then
        pass "Volume is emptyDir"
    else
        fail_with_cmd "Volume is not an emptyDir" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.volumes[0]}'"
    fi

    local reader_logs
    reader_logs=$(kubectl logs -n "$ns" "$pod" -c reader 2>/dev/null || echo "")
    if [[ "$reader_logs" == *"hello"* ]]; then
        pass "Reader container logs contain 'hello'"
    else
        fail_with_cmd "Reader logs do not contain 'hello'" \
            "kubectl logs -n $ns $pod -c reader"
    fi

    local writer_content
    writer_content=$(kubectl exec -n "$ns" "$pod" -c writer -- cat /data/message 2>/dev/null || echo "")
    if [[ "$writer_content" == "hello" ]]; then
        pass "Writer container can read /data/message"
    else
        fail_with_cmd "Writer container /data/message content: $writer_content (expected hello)" \
            "kubectl exec -n $ns $pod -c writer -- cat /data/message"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: hostPath mount ==="
    local pod="host-consumer"
    local ns="ex-1-2"

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

    local hostpath_type
    hostpath_type=$(get_hostpath_type "$pod" "$ns")
    if [[ "$hostpath_type" == "Directory" ]]; then
        pass "hostPath type is Directory"
    else
        fail_with_cmd "hostPath type is $hostpath_type (expected Directory)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.volumes[0].hostPath.type}'"
    fi

    local content
    content=$(kubectl exec -n "$ns" "$pod" -- cat /data/content 2>/dev/null || echo "")
    if [[ "$content" == "node-preloaded" ]]; then
        pass "Container reads 'node-preloaded' from hostPath"
    else
        fail_with_cmd "Container /data/content: $content (expected node-preloaded)" \
            "kubectl exec -n $ns $pod -- cat /data/content"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: emptyDir vs hostPath persistence ==="
    local pod="ephemeral-writer"
    local ns="ex-1-3"

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

    # Check emptyDir is empty (mark-A should not exist after recreation)
    local empty_ls
    empty_ls=$(kubectl exec -n "$ns" "$pod" -- ls /empty 2>/dev/null || echo "")
    if [[ -z "$empty_ls" ]]; then
        pass "emptyDir /empty is empty (mark-A does not persist)"
    else
        info "emptyDir /empty contains: $empty_ls (expected empty directory)"
        fail_with_cmd "emptyDir still contains files after pod recreation" \
            "kubectl exec -n $ns $pod -- ls /empty"
    fi

    # Check hostPath still has mark-B
    local host_content
    host_content=$(kubectl exec -n "$ns" "$pod" -- cat /host/mark-B 2>/dev/null || echo "")
    if [[ "$host_content" == "B" ]]; then
        pass "hostPath /host/mark-B persists after pod recreation"
    else
        fail_with_cmd "hostPath /host/mark-B: $host_content (expected B)" \
            "kubectl exec -n $ns $pod -- cat /host/mark-B"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Static PV creation ==="
    local pv="ex-2-1-pv"

    if ! pv_exists "$pv"; then
        fail "PV $pv does not exist"
        return
    fi

    local phase
    phase=$(get_pv_phase "$pv")
    if [[ "$phase" == "Available" ]]; then
        pass "PV phase is Available"
    else
        fail_with_cmd "PV phase is $phase (expected Available)" \
            "kubectl get pv $pv -o jsonpath='{.status.phase}'"
    fi

    local capacity
    capacity=$(get_pv_capacity "$pv")
    if [[ "$capacity" == "2Gi" ]]; then
        pass "PV capacity is 2Gi"
    else
        fail_with_cmd "PV capacity is $capacity (expected 2Gi)" \
            "kubectl get pv $pv -o jsonpath='{.spec.capacity.storage}'"
    fi

    local access_mode
    access_mode=$(get_pv_access_mode "$pv")
    if [[ "$access_mode" == "ReadWriteOnce" ]]; then
        pass "PV access mode is ReadWriteOnce"
    else
        fail_with_cmd "PV access mode is $access_mode (expected ReadWriteOnce)" \
            "kubectl get pv $pv -o jsonpath='{.spec.accessModes[0]}'"
    fi

    local reclaim
    reclaim=$(get_pv_reclaim_policy "$pv")
    if [[ "$reclaim" == "Retain" ]]; then
        pass "PV reclaim policy is Retain"
    else
        fail_with_cmd "PV reclaim policy is $reclaim (expected Retain)" \
            "kubectl get pv $pv -o jsonpath='{.spec.persistentVolumeReclaimPolicy}'"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: PV with ReadOnlyMany ==="
    local pv="ex-2-2-pv"

    if ! pv_exists "$pv"; then
        fail "PV $pv does not exist"
        return
    fi

    local phase
    phase=$(get_pv_phase "$pv")
    if [[ "$phase" == "Available" ]]; then
        pass "PV phase is Available"
    else
        fail_with_cmd "PV phase is $phase (expected Available)" \
            "kubectl get pv $pv"
    fi

    local access_mode
    access_mode=$(get_pv_access_mode "$pv")
    if [[ "$access_mode" == "ReadOnlyMany" ]]; then
        pass "PV access mode is ReadOnlyMany"
    else
        fail_with_cmd "PV access mode is $access_mode (expected ReadOnlyMany)" \
            "kubectl get pv $pv -o jsonpath='{.spec.accessModes[0]}'"
    fi

    local hostpath
    hostpath=$(get_pv_hostpath "$pv")
    if [[ "$hostpath" == "/ex-2-2" ]]; then
        pass "PV hostPath is /ex-2-2"
    else
        fail_with_cmd "PV hostPath is $hostpath (expected /ex-2-2)" \
            "kubectl get pv $pv -o jsonpath='{.spec.hostPath.path}'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: PV inspection with jsonpath ==="
    local pv="ex-2-3-pv"

    if ! pv_exists "$pv"; then
        fail "PV $pv does not exist"
        return
    fi

    local capacity
    capacity=$(get_pv_capacity "$pv")
    if [[ "$capacity" == "750Mi" ]]; then
        pass "PV capacity is 750Mi"
    else
        fail_with_cmd "PV capacity is $capacity (expected 750Mi)" \
            "kubectl get pv $pv -o jsonpath='{.spec.capacity.storage}'"
    fi

    local access_mode
    access_mode=$(get_pv_access_mode "$pv")
    if [[ "$access_mode" == "ReadWriteOnce" ]]; then
        pass "PV access mode is ReadWriteOnce"
    else
        fail "PV access mode is $access_mode (expected ReadWriteOnce)"
    fi

    local reclaim
    reclaim=$(get_pv_reclaim_policy "$pv")
    if [[ "$reclaim" == "Delete" ]]; then
        pass "PV reclaim policy is Delete"
    else
        fail "PV reclaim policy is $reclaim (expected Delete)"
    fi

    local sc
    sc=$(get_pv_storage_class "$pv")
    if [[ "$sc" == "manual" ]]; then
        pass "PV storageClassName is manual"
    else
        fail "PV storageClassName is $sc (expected manual)"
    fi

    local label
    label=$(kubectl get pv "$pv" -o jsonpath='{.metadata.labels.purpose}' 2>/dev/null)
    if [[ "$label" == "inspection" ]]; then
        pass "PV label purpose=inspection"
    else
        fail_with_cmd "PV label purpose=$label (expected inspection)" \
            "kubectl get pv $pv -o jsonpath='{.metadata.labels.purpose}'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug invalid capacity ==="
    local pv="ex-3-1-pv"

    if ! pv_exists "$pv"; then
        fail "PV $pv does not exist (may have failed to apply due to invalid spec)"
        info "Hint: Check capacity format - Kubernetes quantities use Ki/Mi/Gi/Ti"
        return
    fi

    local phase
    phase=$(get_pv_phase "$pv")
    if [[ "$phase" == "Available" ]]; then
        pass "PV phase is Available (issue fixed)"
    else
        fail_with_cmd "PV phase is $phase (expected Available)" \
            "kubectl describe pv $pv"
    fi

    local capacity
    capacity=$(get_pv_capacity "$pv")
    if [[ "$capacity" == "1Gi" ]] || [[ "$capacity" == "1G" ]]; then
        pass "PV capacity is valid: $capacity"
    else
        info "PV capacity is $capacity (expected 1Gi or 1G)"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug PV stuck in Released ==="
    local pv="ex-3-2-pv"

    if ! pv_exists "$pv"; then
        fail "PV $pv does not exist"
        return
    fi

    local phase
    phase=$(get_pv_phase "$pv")
    if [[ "$phase" == "Available" ]]; then
        pass "PV phase is Available (Released issue fixed)"
    else
        fail_with_cmd "PV phase is $phase (expected Available)" \
            "kubectl describe pv $pv | grep -E 'Status|Claim'"
        info "Hint: Remove spec.claimRef to make a Released PV Available again"
    fi

    # Verify data still exists on node
    local node_data
    node_data=$(nerdctl exec kind-control-plane cat /ex-3-2/data 2>/dev/null || echo "")
    if [[ "$node_data" == "keep-me" ]]; then
        pass "Data on node persists: keep-me"
    else
        info "Data on node: $node_data (expected keep-me)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug PVC stuck in Pending ==="
    local pvc="needy"
    local pv="ex-3-3-pv"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail "PVC $pvc not found in namespace $ns"
        return
    fi

    local pvc_phase
    pvc_phase=$(get_pvc_phase "$pvc" "$ns")
    if [[ "$pvc_phase" == "Bound" ]]; then
        pass "PVC phase is Bound (issue fixed)"
    else
        fail_with_cmd "PVC phase is $pvc_phase (expected Bound)" \
            "kubectl describe pvc -n $ns $pvc"
        info "Hint: Check access mode compatibility between PV and PVC"
        return
    fi

    local bound_volume
    bound_volume=$(get_pvc_volume "$pvc" "$ns")
    if [[ "$bound_volume" == "$pv" ]]; then
        pass "PVC bound to $pv"
    else
        fail_with_cmd "PVC bound to $bound_volume (expected $pv)" \
            "kubectl get pvc -n $ns $pvc -o jsonpath='{.spec.volumeName}'"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: PV with node affinity ==="
    local pv="ex-4-1-pv"

    if ! pv_exists "$pv"; then
        fail "PV $pv does not exist"
        return
    fi

    local phase
    phase=$(get_pv_phase "$pv")
    if [[ "$phase" == "Available" ]]; then
        pass "PV phase is Available"
    else
        fail_with_cmd "PV phase is $phase (expected Available)" \
            "kubectl get pv $pv"
    fi

    local local_path
    local_path=$(kubectl get pv "$pv" -o jsonpath='{.spec.local.path}' 2>/dev/null)
    if [[ "$local_path" == "/ex-4-1" ]]; then
        pass "PV local path is /ex-4-1"
    else
        fail_with_cmd "PV local path is $local_path (expected /ex-4-1)" \
            "kubectl get pv $pv -o jsonpath='{.spec.local.path}'"
    fi

    local node_affinity
    node_affinity=$(kubectl get pv "$pv" -o jsonpath='{.spec.nodeAffinity.required.nodeSelectorTerms[0].matchExpressions[0].values[0]}' 2>/dev/null)
    if [[ "$node_affinity" == "kind-control-plane" ]]; then
        pass "PV node affinity targets kind-control-plane"
    else
        fail_with_cmd "PV node affinity value: $node_affinity (expected kind-control-plane)" \
            "kubectl get pv $pv -o yaml | grep -A10 nodeAffinity"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: PV label selectors ==="
    local pvc="want-ssd"
    local ns="ex-4-2"
    local pv_ssd="ex-4-2-ssd"
    local pv_hdd="ex-4-2-hdd"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pvc_exists "$pvc" "$ns"; then
        fail "PVC $pvc not found in namespace $ns"
        return
    fi

    local bound_volume
    bound_volume=$(get_pvc_volume "$pvc" "$ns")
    if [[ "$bound_volume" == "$pv_ssd" ]]; then
        pass "PVC bound to ex-4-2-ssd (label selector worked)"
    else
        fail_with_cmd "PVC bound to $bound_volume (expected ex-4-2-ssd)" \
            "kubectl get pvc -n $ns $pvc -o jsonpath='{.spec.volumeName}'"
    fi

    local ssd_phase
    ssd_phase=$(get_pv_phase "$pv_ssd")
    if [[ "$ssd_phase" == "Bound" ]]; then
        pass "PV ex-4-2-ssd is Bound"
    else
        fail "PV ex-4-2-ssd phase is $ssd_phase (expected Bound)"
    fi

    local hdd_phase
    hdd_phase=$(get_pv_phase "$pv_hdd")
    if [[ "$hdd_phase" == "Available" ]]; then
        pass "PV ex-4-2-hdd is Available (not bound)"
    else
        info "PV ex-4-2-hdd phase is $hdd_phase (expected Available)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Retain vs Delete reclaim policy ==="
    local pv_retain="ex-4-3-retain"
    local pv_delete="ex-4-3-delete"

    if ! pv_exists "$pv_retain"; then
        fail "PV $pv_retain does not exist"
        return
    fi

    local retain_phase
    retain_phase=$(get_pv_phase "$pv_retain")
    if [[ "$retain_phase" == "Released" ]]; then
        pass "PV ex-4-3-retain is Released (Retain policy after PVC deletion)"
    else
        info "PV ex-4-3-retain phase is $retain_phase (expected Released after PVC deletion)"
    fi

    # Check if delete PV exists or is Failed/deleted
    if pv_exists "$pv_delete"; then
        local delete_phase
        delete_phase=$(get_pv_phase "$pv_delete")
        if [[ "$delete_phase" == "Failed" ]]; then
            pass "PV ex-4-3-delete is Failed (hostPath Delete has no deletion semantics)"
        else
            info "PV ex-4-3-delete phase is $delete_phase"
        fi
    else
        info "PV ex-4-3-delete not found (may have been deleted or failed)"
    fi

    # Verify retain data still exists
    local retain_data
    retain_data=$(nerdctl exec kind-control-plane cat /ex-4-3-retain/data 2>/dev/null || echo "")
    if [[ "$retain_data" == "keep" ]]; then
        pass "Retain PV data persists on node"
    else
        info "Retain PV data: $retain_data (expected keep)"
    fi

    # Verify delete data also still exists (hostPath doesn't actually delete)
    local delete_data
    delete_data=$(nerdctl exec kind-control-plane cat /ex-4-3-delete/data 2>/dev/null || echo "")
    if [[ "$delete_data" == "should-go" ]]; then
        pass "Delete PV data still on node (hostPath has no deletion implementation)"
    else
        info "Delete PV data: $delete_data"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multi-PV design with node affinity ==="
    local pv_data="ex-5-1-data"
    local pv_config="ex-5-1-config"

    if ! pv_exists "$pv_data"; then
        fail "PV $pv_data does not exist"
        return
    fi

    if ! pv_exists "$pv_config"; then
        fail "PV $pv_config does not exist"
        return
    fi

    local data_phase
    data_phase=$(get_pv_phase "$pv_data")
    local config_phase
    config_phase=$(get_pv_phase "$pv_config")

    if [[ "$data_phase" == "Available" ]] && [[ "$config_phase" == "Available" ]]; then
        pass "Both PVs are Available"
    else
        fail_with_cmd "PV phases: data=$data_phase config=$config_phase (both should be Available)" \
            "kubectl get pv $pv_data $pv_config"
    fi

    local data_capacity
    data_capacity=$(get_pv_capacity "$pv_data")
    if [[ "$data_capacity" == "2Gi" ]]; then
        pass "Data PV capacity is 2Gi"
    else
        fail "Data PV capacity is $data_capacity (expected 2Gi)"
    fi

    local config_capacity
    config_capacity=$(get_pv_capacity "$pv_config")
    if [[ "$config_capacity" == "100Mi" ]]; then
        pass "Config PV capacity is 100Mi"
    else
        fail "Config PV capacity is $config_capacity (expected 100Mi)"
    fi

    local config_label
    config_label=$(kubectl get pv "$pv_config" -o jsonpath='{.metadata.labels.purpose}' 2>/dev/null)
    if [[ "$config_label" == "config" ]]; then
        pass "Config PV has label purpose=config"
    else
        fail_with_cmd "Config PV label purpose=$config_label (expected config)" \
            "kubectl get pv $pv_config -o jsonpath='{.metadata.labels.purpose}'"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug PV with dangling claimRef ==="
    local pv="ex-5-2-primary"

    if ! pv_exists "$pv"; then
        fail "PV $pv does not exist"
        return
    fi

    local phase
    phase=$(get_pv_phase "$pv")
    if [[ "$phase" == "Available" ]]; then
        pass "PV phase is Available (claimRef issue fixed)"
    else
        fail_with_cmd "PV phase is $phase (expected Available)" \
            "kubectl describe pv $pv | grep -E 'Status|Claim'"
        info "Hint: Remove spec.claimRef pointing to non-existent PVC"
        return
    fi

    local claim_ref
    claim_ref=$(kubectl get pv "$pv" -o jsonpath='{.spec.claimRef}' 2>/dev/null)
    if [[ -z "$claim_ref" ]]; then
        pass "PV claimRef has been removed"
    else
        info "PV still has claimRef: $claim_ref"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Pre-provision PVs for StatefulSet-style workload ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local pvc0="data-app-0"
    local pvc1="data-app-1"
    local pvc2="data-app-2"

    if ! pvc_exists "$pvc0" "$ns"; then
        fail "PVC $pvc0 not found in namespace $ns"
        return
    fi

    if ! pvc_exists "$pvc1" "$ns"; then
        fail "PVC $pvc1 not found in namespace $ns"
        return
    fi

    if ! pvc_exists "$pvc2" "$ns"; then
        fail "PVC $pvc2 not found in namespace $ns"
        return
    fi

    local vol0
    vol0=$(get_pvc_volume "$pvc0" "$ns")
    if [[ "$vol0" == "ex-5-3-pv-0" ]]; then
        pass "PVC data-app-0 bound to ex-5-3-pv-0"
    else
        fail_with_cmd "PVC data-app-0 bound to $vol0 (expected ex-5-3-pv-0)" \
            "kubectl get pvc -n $ns $pvc0 -o jsonpath='{.spec.volumeName}'"
    fi

    local vol1
    vol1=$(get_pvc_volume "$pvc1" "$ns")
    if [[ "$vol1" == "ex-5-3-pv-1" ]]; then
        pass "PVC data-app-1 bound to ex-5-3-pv-1"
    else
        fail_with_cmd "PVC data-app-1 bound to $vol1 (expected ex-5-3-pv-1)" \
            "kubectl get pvc -n $ns $pvc1 -o jsonpath='{.spec.volumeName}'"
    fi

    local vol2
    vol2=$(get_pvc_volume "$pvc2" "$ns")
    if [[ "$vol2" == "ex-5-3-pv-2" ]]; then
        pass "PVC data-app-2 bound to ex-5-3-pv-2"
    else
        fail_with_cmd "PVC data-app-2 bound to $vol2 (expected ex-5-3-pv-2)" \
            "kubectl get pvc -n $ns $pvc2 -o jsonpath='{.spec.volumeName}'"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Volume Types"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: PersistentVolume Creation"
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
    echo "# Level 4: Configuration"
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
