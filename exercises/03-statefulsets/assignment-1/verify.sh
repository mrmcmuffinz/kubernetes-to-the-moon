#!/usr/bin/env bash
#
# verify.sh - Automated verification for statefulsets-homework.md
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

# Helper: check if StatefulSet exists
statefulset_exists() {
    local sts=$1
    local ns=$2
    kubectl get statefulset "$sts" -n "$ns" &>/dev/null
}

# Helper: check if Service exists
service_exists() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" &>/dev/null
}

# Helper: get StatefulSet replicas
get_replicas() {
    local sts=$1
    local ns=$2
    kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.status.replicas}' 2>/dev/null
}

# Helper: get StatefulSet ready replicas
get_ready_replicas() {
    local sts=$1
    local ns=$2
    kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null
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

# Helper: get Service clusterIP
get_cluster_ip() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.clusterIP}' 2>/dev/null
}

# Helper: get PVC status
get_pvc_status() {
    local pvc=$1
    local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: check if PVC exists
pvc_exists() {
    local pvc=$1
    local ns=$2
    kubectl get pvc "$pvc" -n "$ns" &>/dev/null
}

# Helper: get StatefulSet serviceName
get_service_name() {
    local sts=$1
    local ns=$2
    kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.spec.serviceName}' 2>/dev/null
}

# Helper: get StatefulSet podManagementPolicy
get_pod_management_policy() {
    local sts=$1
    local ns=$2
    kubectl get statefulset "$sts" -n "$ns" -o jsonpath='{.spec.podManagementPolicy}' 2>/dev/null
}

# Helper: get pod label value
get_label() {
    local pod=$1
    local ns=$2
    local label=$3
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.metadata.labels.$label}" 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic StatefulSet with headless Service ==="
    local sts="app"
    local svc="app-hdr"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local cluster_ip
    cluster_ip=$(get_cluster_ip "$svc" "$ns")
    if [[ "$cluster_ip" == "None" ]]; then
        pass "Service $svc is headless (clusterIP: None)"
    else
        fail_with_cmd "Service $svc clusterIP is $cluster_ip (expected None)" \
            "kubectl get svc $svc -n $ns -o yaml | grep clusterIP"
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail_with_cmd "StatefulSet $sts not found in namespace $ns" \
            "kubectl get statefulset -n $ns"
        return
    fi

    sleep 10  # Allow time for StatefulSet to roll out

    local ready
    ready=$(get_ready_replicas "$sts" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "StatefulSet has 3 ready replicas"
    else
        fail_with_cmd "StatefulSet has $ready ready replicas (expected 3)" \
            "kubectl get statefulset $sts -n $ns"
    fi

    if pod_exists "$sts-0" "$ns"; then
        pass "Pod $sts-0 exists"
    else
        fail "Pod $sts-0 does not exist"
        return
    fi

    local pod_index
    pod_index=$(get_label "$sts-0" "$ns" "apps.kubernetes.io/pod-index")
    if [[ "$pod_index" == "0" ]]; then
        pass "Pod $sts-0 has pod-index label = 0"
    else
        fail "Pod $sts-0 pod-index label is '$pod_index' (expected 0)"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: StatefulSet with volumeClaimTemplates ==="
    local sts="store"
    local svc="store-hdr"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail "Service $svc not found in namespace $ns"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    sleep 10

    local ready
    ready=$(get_ready_replicas "$sts" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "StatefulSet has 3 ready replicas"
    else
        fail_with_cmd "StatefulSet has $ready ready replicas (expected 3)" \
            "kubectl get statefulset $sts -n $ns"
    fi

    for i in 0 1 2; do
        local pvc="data-$sts-$i"
        if pvc_exists "$pvc" "$ns"; then
            local status
            status=$(get_pvc_status "$pvc" "$ns")
            if [[ "$status" == "Bound" ]]; then
                pass "PVC $pvc is Bound"
            else
                fail_with_cmd "PVC $pvc status is $status (expected Bound)" \
                    "kubectl get pvc $pvc -n $ns"
            fi
        else
            fail "PVC $pvc does not exist"
        fi
    done
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: StatefulSet with Parallel podManagementPolicy ==="
    local sts="fleet"
    local svc="fleet-hdr"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail "Service $svc not found in namespace $ns"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    sleep 10

    local policy
    policy=$(get_pod_management_policy "$sts" "$ns")
    if [[ "$policy" == "Parallel" ]]; then
        pass "StatefulSet podManagementPolicy is Parallel"
    else
        fail_with_cmd "StatefulSet podManagementPolicy is '$policy' (expected Parallel)" \
            "kubectl get statefulset $sts -n $ns -o jsonpath='{.spec.podManagementPolicy}'"
    fi

    local ready
    ready=$(get_ready_replicas "$sts" "$ns")
    if [[ "$ready" == "4" ]]; then
        pass "StatefulSet has 4 ready replicas"
    else
        fail_with_cmd "StatefulSet has $ready ready replicas (expected 4)" \
            "kubectl get statefulset $sts -n $ns"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Per-pod storage persistence ==="
    local sts="files"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    sleep 5

    # Check that marker files exist for all pods
    for i in 0 1 2; do
        if pod_exists "$sts-$i" "$ns"; then
            local marker
            marker=$(kubectl -n "$ns" exec "$sts-$i" -- cat /usr/share/nginx/html/marker.txt 2>/dev/null || echo "")
            if [[ "$marker" == "$sts-$i" ]]; then
                pass "Pod $sts-$i marker file contains '$sts-$i'"
            else
                fail_with_cmd "Pod $sts-$i marker file contains '$marker' (expected '$sts-$i')" \
                    "kubectl -n $ns exec $sts-$i -- cat /usr/share/nginx/html/marker.txt"
            fi
        else
            fail "Pod $sts-$i does not exist"
        fi
    done
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Partitioned rolling update ==="
    local sts="service"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    sleep 5

    # Check that all 5 pods eventually run the final image nginx:1.27.3
    local all_updated=true
    for i in 0 1 2 3 4; do
        if pod_exists "$sts-$i" "$ns"; then
            local image
            image=$(get_image "$sts-$i" "$ns")
            if [[ "$image" != "nginx:1.27.3" ]]; then
                all_updated=false
                break
            fi
        else
            all_updated=false
            break
        fi
    done

    if [[ "$all_updated" == "true" ]]; then
        pass "All 5 pods run nginx:1.27.3 (partition lowered to 0)"
    else
        info "Not all pods updated yet; check partition value and rollout status"
        fail_with_cmd "Some pods not yet on nginx:1.27.3" \
            "kubectl get pods -n $ns -l app=service -o jsonpath='{range .items[*]}{.metadata.name}:{.spec.containers[0].image}{\"\n\"}{end}'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: OnDelete update strategy ==="
    local sts="workers"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    sleep 5

    # Check that workers-1 was updated to nginx:1.27.3 while workers-0 and workers-2 remain on nginx:1.27
    local w0_image w1_image w2_image
    w0_image=$(get_image "$sts-0" "$ns" || echo "")
    w1_image=$(get_image "$sts-1" "$ns" || echo "")
    w2_image=$(get_image "$sts-2" "$ns" || echo "")

    if [[ "$w1_image" == "nginx:1.27.3" ]]; then
        pass "Pod workers-1 runs nginx:1.27.3"
    else
        fail_with_cmd "Pod workers-1 runs $w1_image (expected nginx:1.27.3)" \
            "kubectl get pod workers-1 -n $ns -o jsonpath='{.spec.containers[0].image}'"
    fi

    if [[ "$w0_image" == "nginx:1.27" ]] && [[ "$w2_image" == "nginx:1.27" ]]; then
        pass "Pods workers-0 and workers-2 still run nginx:1.27 (OnDelete strategy)"
    else
        info "Expected workers-0 and workers-2 on nginx:1.27; got $w0_image and $w2_image"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix broken StorageClass ==="
    local sts="vault"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    sleep 10

    local ready
    ready=$(get_ready_replicas "$sts" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "StatefulSet has 3 ready replicas (issue fixed)"
    else
        fail_with_cmd "StatefulSet has $ready ready replicas (expected 3)" \
            "kubectl get statefulset $sts -n $ns"
        info "Hint: Check StorageClass name in volumeClaimTemplates"
    fi

    for i in 0 1 2; do
        local pvc="data-$sts-$i"
        if pvc_exists "$pvc" "$ns"; then
            local status
            status=$(get_pvc_status "$pvc" "$ns")
            if [[ "$status" == "Bound" ]]; then
                pass "PVC $pvc is Bound"
            else
                fail_with_cmd "PVC $pvc status is $status (expected Bound)" \
                    "kubectl describe pvc $pvc -n $ns | tail -10"
            fi
        else
            fail "PVC $pvc does not exist"
        fi
    done
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix non-headless Service ==="
    local sts="discovery"
    local svc="discovery-svc"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail "Service $svc not found in namespace $ns"
        return
    fi

    local cluster_ip
    cluster_ip=$(get_cluster_ip "$svc" "$ns")
    if [[ "$cluster_ip" == "None" ]]; then
        pass "Service $svc is headless (clusterIP: None)"
    else
        fail_with_cmd "Service $svc clusterIP is $cluster_ip (expected None)" \
            "kubectl get svc $svc -n $ns -o yaml | grep clusterIP"
        info "Hint: Service must have clusterIP: None for per-pod DNS"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    sleep 5

    local ready
    ready=$(get_ready_replicas "$sts" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "StatefulSet has 3 ready replicas"
    else
        fail "StatefulSet has $ready ready replicas (expected 3)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix serviceName mismatch ==="
    local sts="members"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    local service_name
    service_name=$(get_service_name "$sts" "$ns")

    if [[ -z "$service_name" ]]; then
        fail "StatefulSet $sts has no serviceName set"
        return
    fi

    if service_exists "$service_name" "$ns"; then
        pass "StatefulSet serviceName '$service_name' references an existing Service"
    else
        fail_with_cmd "StatefulSet serviceName '$service_name' does not reference an existing Service" \
            "kubectl get svc -n $ns"
        info "Hint: Create Service named '$service_name' or fix StatefulSet serviceName"
        return
    fi

    local cluster_ip
    cluster_ip=$(get_cluster_ip "$service_name" "$ns")
    if [[ "$cluster_ip" == "None" ]]; then
        pass "Service $service_name is headless"
    else
        fail "Service $service_name is not headless (clusterIP: $cluster_ip)"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Multi-tier application with StatefulSet database ==="
    local db_sts="db"
    local db_svc="db-hdr"
    local primary_svc="db-primary"
    local app_deploy="app"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$db_svc" "$ns"; then
        fail "Headless Service $db_svc not found"
        return
    fi

    if ! statefulset_exists "$db_sts" "$ns"; then
        fail "StatefulSet $db_sts not found"
        return
    fi

    sleep 10

    local ready
    ready=$(get_ready_replicas "$db_sts" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "StatefulSet $db_sts has 3 ready replicas"
    else
        fail_with_cmd "StatefulSet $db_sts has $ready ready replicas (expected 3)" \
            "kubectl get statefulset $db_sts -n $ns"
    fi

    # Check per-pod content
    for i in 0 1 2; do
        if pod_exists "$db_sts-$i" "$ns"; then
            local content
            content=$(kubectl -n "$ns" exec "$db_sts-$i" -- cat /usr/share/nginx/html/index.html 2>/dev/null || echo "")
            local expected
            case $i in
                0) expected="primary" ;;
                1) expected="replica-a" ;;
                2) expected="replica-b" ;;
            esac
            if [[ "$content" == "$expected" ]]; then
                pass "Pod $db_sts-$i serves '$expected'"
            else
                fail_with_cmd "Pod $db_sts-$i serves '$content' (expected '$expected')" \
                    "kubectl -n $ns exec $db_sts-$i -- cat /usr/share/nginx/html/index.html"
            fi
        fi
    done

    if service_exists "$primary_svc" "$ns"; then
        pass "Service $primary_svc exists"
    else
        fail "Service $primary_svc not found"
    fi

    # Check that Deployment app exists and is running
    if kubectl get deployment "$app_deploy" -n "$ns" &>/dev/null; then
        pass "Deployment $app_deploy exists"
    else
        fail "Deployment $app_deploy not found"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Staged rollout with partition ==="
    local sts="web"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    sleep 10

    # Check that all 6 pods eventually run nginx:1.27.3
    local all_updated=true
    for i in 0 1 2 3 4 5; do
        if pod_exists "$sts-$i" "$ns"; then
            local image
            image=$(get_image "$sts-$i" "$ns")
            if [[ "$image" != "nginx:1.27.3" ]]; then
                all_updated=false
                break
            fi
        else
            all_updated=false
            break
        fi
    done

    if [[ "$all_updated" == "true" ]]; then
        pass "All 6 pods run nginx:1.27.3 (full rollout complete)"
    else
        info "Not all pods updated yet; ensure partition=0"
        fail_with_cmd "Some pods not yet on nginx:1.27.3" \
            "kubectl get pods -n $ns -l app=web -o jsonpath='{range .items[*]}{.metadata.name}:{.spec.containers[0].image}{\"\n\"}{end}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Scale-down and scale-up preserve PVCs ==="
    local sts="shard"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found in namespace $ns"
        return
    fi

    sleep 10

    # Check that all 4 pods are back and have their original markers
    local ready
    ready=$(get_ready_replicas "$sts" "$ns")
    if [[ "$ready" == "4" ]]; then
        pass "StatefulSet scaled back to 4 replicas"
    else
        fail_with_cmd "StatefulSet has $ready ready replicas (expected 4)" \
            "kubectl get statefulset $sts -n $ns"
        info "Ensure you scaled back to 4 replicas"
    fi

    for i in 0 1 2 3; do
        if pod_exists "$sts-$i" "$ns"; then
            local marker
            marker=$(kubectl -n "$ns" exec "$sts-$i" -- cat /usr/share/nginx/html/marker.txt 2>/dev/null || echo "")
            local expected="data for $sts-$i"
            if [[ "$marker" == "$expected" ]]; then
                pass "Pod $sts-$i marker preserved: '$expected'"
            else
                fail_with_cmd "Pod $sts-$i marker is '$marker' (expected '$expected')" \
                    "kubectl -n $ns exec $sts-$i -- cat /usr/share/nginx/html/marker.txt"
            fi
        fi
    done
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Peer-discoverable clustered application ==="
    local sts="cluster"
    local svc="cluster-hdr"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail "Service $svc not found"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found"
        return
    fi

    sleep 10

    local ready
    ready=$(get_ready_replicas "$sts" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "StatefulSet has 3 ready replicas"
    else
        fail_with_cmd "StatefulSet has $ready ready replicas (expected 3)" \
            "kubectl get statefulset $sts -n $ns"
    fi

    # Check role assignment
    if pod_exists "$sts-0" "$ns"; then
        local role
        role=$(kubectl -n "$ns" exec "$sts-0" -- cat /usr/share/nginx/html/role 2>/dev/null || echo "")
        if [[ "$role" == "leader" ]]; then
            pass "Pod cluster-0 role is 'leader'"
        else
            fail_with_cmd "Pod cluster-0 role is '$role' (expected 'leader')" \
                "kubectl -n $ns exec cluster-0 -- cat /usr/share/nginx/html/role"
        fi
    fi

    for i in 1 2; do
        if pod_exists "$sts-$i" "$ns"; then
            local role
            role=$(kubectl -n "$ns" exec "$sts-$i" -- cat /usr/share/nginx/html/role 2>/dev/null || echo "")
            if [[ "$role" == "follower" ]]; then
                pass "Pod cluster-$i role is 'follower'"
            else
                fail_with_cmd "Pod cluster-$i role is '$role' (expected 'follower')" \
                    "kubectl -n $ns exec cluster-$i -- cat /usr/share/nginx/html/role"
            fi
        fi
    done
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Fix multiple bugs ==="
    local sts="broker"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found"
        return
    fi

    sleep 15

    local ready
    ready=$(get_ready_replicas "$sts" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "StatefulSet has 3 ready replicas (all bugs fixed)"
    else
        fail_with_cmd "StatefulSet has $ready ready replicas (expected 3)" \
            "kubectl get statefulset $sts -n $ns"
        info "Hint: Check StorageClass, serviceName, and Service headless status"
    fi

    for i in 0 1 2; do
        local pvc="data-$sts-$i"
        if pvc_exists "$pvc" "$ns"; then
            local status
            status=$(get_pvc_status "$pvc" "$ns")
            if [[ "$status" == "Bound" ]]; then
                pass "PVC $pvc is Bound"
            else
                fail "PVC $pvc status is $status (expected Bound)"
            fi
        else
            fail "PVC $pvc does not exist"
        fi
    done

    local service_name
    service_name=$(get_service_name "$sts" "$ns")
    if [[ -n "$service_name" ]] && service_exists "$service_name" "$ns"; then
        local cluster_ip
        cluster_ip=$(get_cluster_ip "$service_name" "$ns")
        if [[ "$cluster_ip" == "None" ]]; then
            pass "Service $service_name is headless and referenced by StatefulSet"
        else
            fail "Service $service_name is not headless"
        fi
    else
        fail "StatefulSet serviceName '$service_name' does not reference an existing Service"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Canary rollout with rollback and recovery ==="
    local sts="api"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! statefulset_exists "$sts" "$ns"; then
        fail "StatefulSet $sts not found"
        return
    fi

    sleep 15

    # Check that all 5 pods eventually run nginx:1.27.3
    local all_updated=true
    for i in 0 1 2 3 4; do
        if pod_exists "$sts-$i" "$ns"; then
            local image
            image=$(get_image "$sts-$i" "$ns")
            if [[ "$image" != "nginx:1.27.3" ]]; then
                all_updated=false
                break
            fi
        else
            all_updated=false
            break
        fi
    done

    if [[ "$all_updated" == "true" ]]; then
        pass "All 5 pods run nginx:1.27.3 (full rollout complete after recovery)"
    else
        info "Not all pods on nginx:1.27.3; ensure full canary sequence completed"
        fail_with_cmd "Some pods not yet on nginx:1.27.3" \
            "kubectl get pods -n $ns -l app=api -o jsonpath='{range .items[*]}{.metadata.name}:{.spec.containers[0].image}{\"\n\"}{end}'"
    fi

    # Check that rollout history exists
    local history
    history=$(kubectl rollout history statefulset/"$sts" -n "$ns" 2>/dev/null | wc -l || echo "0")
    if [[ "$history" -gt 3 ]]; then
        pass "Rollout history exists (multiple revisions)"
    else
        info "Rollout history may be incomplete; expected multiple revisions"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basics"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Multi-Concept"
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
