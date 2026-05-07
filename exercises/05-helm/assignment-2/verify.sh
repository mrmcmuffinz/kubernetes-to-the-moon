#!/usr/bin/env bash
#
# verify.sh - Automated verification for helm-homework.md
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

# Helper: check if release exists
release_exists() {
    local release=$1
    local ns=$2
    helm list -n "$ns" -q | grep -q "^${release}$"
}

# Helper: get replicas from deployment
get_replicas() {
    local ns=$1
    kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0"
}

# Helper: get helm revision count
get_revision_count() {
    local release=$1
    local ns=$2
    helm history "$release" -n "$ns" 2>/dev/null | tail -n +2 | wc -l
}

# Helper: get current revision number
get_current_revision() {
    local release=$1
    local ns=$2
    helm list -n "$ns" -o json | jq -r ".[] | select(.name==\"${release}\") | .revision" 2>/dev/null || echo "0"
}

# Helper: get helm value
get_helm_value() {
    local release=$1
    local ns=$2
    local key=$3
    helm get values "$release" -n "$ns" -o json 2>/dev/null | jq -r ".${key}" 2>/dev/null || echo "null"
}

# Helper: check if file exists
file_exists() {
    [[ -f "$1" ]]
}

# Helper: get resource request
get_resource_request() {
    local ns=$1
    local resource=$2
    kubectl get deployment -n "$ns" -o jsonpath="{.items[0].spec.template.spec.containers[0].resources.requests.${resource}}" 2>/dev/null || echo ""
}

# Helper: get service type
get_service_type() {
    local ns=$1
    kubectl get svc -n "$ns" -o jsonpath='{.items[0].spec.type}' 2>/dev/null || echo ""
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Upgrade with new values ==="
    local release="web-app"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found in namespace $ns" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local revision_count
    revision_count=$(get_revision_count "$release" "$ns")
    if [[ "$revision_count" -ge 2 ]]; then
        pass "Release has $revision_count revisions (at least 2)"
    else
        fail_with_cmd "Release has $revision_count revision(s) (expected at least 2)" \
            "helm history $release -n $ns"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Dry-run preview ==="
    local release="web-app"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment still has 3 replicas (dry-run did not apply)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3, dry-run should not change it)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    info "Note: This exercise verifies that dry-run was used (no actual change applied)"
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: View release history ==="
    local release="web-app"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local revision_count
    revision_count=$(get_revision_count "$release" "$ns")
    if [[ "$revision_count" -ge 2 ]]; then
        pass "Release has $revision_count revisions visible in history"
    else
        fail_with_cmd "Release has only $revision_count revision(s)" \
            "helm history $release -n $ns"
    fi

    info "Note: Review history with: helm history $release -n $ns"
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Values file creation ==="
    local release="values-demo"
    local ns="ex-2-1"
    local values_file="ex-2-1-values.yaml"

    if ! file_exists "$values_file"; then
        fail "Values file $values_file does not exist"
        info "Expected file in current directory: $values_file"
    else
        pass "Values file $values_file exists"
    fi

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "2" ]]; then
        pass "Deployment has 2 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 2)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Override values with --set ==="
    local release="values-demo"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "4" ]]; then
        pass "Deployment has 4 replicas (--set override worked)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 4 from --set override)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local replica_value
    replica_value=$(get_helm_value "$release" "$ns" "replicaCount")
    if [[ "$replica_value" == "4" ]]; then
        pass "Helm values show replicaCount: 4"
    else
        fail_with_cmd "Helm values show replicaCount: $replica_value (expected 4)" \
            "helm get values $release -n $ns"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Multiple values files with precedence ==="
    local release="layered-config"
    local ns="ex-2-3"
    local base_file="base.yaml"
    local overlay_file="overlay.yaml"

    if ! file_exists "$base_file"; then
        fail "Base values file $base_file does not exist"
    else
        pass "Base values file $base_file exists"
    fi

    if ! file_exists "$overlay_file"; then
        fail "Overlay values file $overlay_file does not exist"
    else
        pass "Overlay values file $overlay_file exists"
    fi

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas (from overlay.yaml)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3 from overlay)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local svc_type
    svc_type=$(get_service_type "$ns")
    if [[ "$svc_type" == "ClusterIP" ]]; then
        pass "Service type is ClusterIP (from base.yaml)"
    else
        fail_with_cmd "Service type is $svc_type (expected ClusterIP from base)" \
            "kubectl get svc -n $ns -o jsonpath='{.items[0].spec.type}'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix upgrade with lost resource configuration ==="
    local release="config-app"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local memory
    memory=$(get_resource_request "$ns" "memory")
    if [[ "$memory" == "128Mi" ]]; then
        pass "Memory request is 128Mi"
    else
        fail_with_cmd "Memory request is '$memory' (expected 128Mi)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests.memory}'"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix rollback to wrong revision ==="
    local release="rollback-demo"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas (correct revision)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3 from revision 3)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
        info "Hint: Check helm history and rollback to revision 3"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix --reuse-values issue ==="
    local release="complex-app"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "4" ]]; then
        pass "Deployment has 4 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 4)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local memory
    memory=$(get_resource_request "$ns" "memory")
    if [[ "$memory" == "64Mi" ]]; then
        pass "Memory request is 64Mi (original resource settings preserved)"
    else
        fail_with_cmd "Memory request is '$memory' (expected 64Mi)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests.memory}'"
        info "Hint: Create a complete values file without using --reuse-values"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Rollback to previous revision ==="
    local release="stable-app"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "2" ]]; then
        pass "Deployment has 2 replicas (rolled back)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 2 after rollback)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
        info "Hint: Use 'helm rollback stable-app -n ex-4-1' to rollback to previous revision"
    fi

    local revision_count
    revision_count=$(get_revision_count "$release" "$ns")
    if [[ "$revision_count" -ge 3 ]]; then
        pass "History shows rollback (at least 3 revisions)"
    else
        fail_with_cmd "Only $revision_count revision(s) in history" \
            "helm history $release -n $ns"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Rollback to specific revision ==="
    local release="versioned-app"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "2" ]]; then
        pass "Deployment has 2 replicas (from revision 2)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 2)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
        info "Hint: Rollback to revision 2 with 'helm rollback versioned-app 2 -n ex-4-2'"
    fi

    local current_rev
    current_rev=$(get_current_revision "$release" "$ns")
    if [[ "$current_rev" == "5" ]]; then
        pass "Current revision is 5 (rollback created new revision)"
    else
        fail_with_cmd "Current revision is $current_rev (expected 5)" \
            "helm list -n $ns"
        info "Rollback to revision 2 should create revision 5"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Rollback creates new revision ==="
    local release="versioned-app"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "4" ]]; then
        pass "Deployment has 4 replicas (from revision 4)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 4)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
        info "Hint: Rollback to revision 4 with 'helm rollback versioned-app 4 -n ex-4-2'"
    fi

    local revision_count
    revision_count=$(get_revision_count "$release" "$ns")
    if [[ "$revision_count" == "6" ]]; then
        pass "Total of 6 revisions (second rollback created revision 6)"
    else
        fail_with_cmd "Found $revision_count revisions (expected 6)" \
            "helm history $release -n $ns"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Complete lifecycle management ==="
    local release="full-lifecycle"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "2" ]]; then
        pass "Deployment has 2 replicas (rolled back to revision 2)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 2)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local revision_count
    revision_count=$(get_revision_count "$release" "$ns")
    if [[ "$revision_count" == "4" ]]; then
        pass "Total of 4 revisions (install + 2 upgrades + rollback)"
    else
        fail_with_cmd "Found $revision_count revisions (expected 4)" \
            "helm history $release -n $ns"
    fi

    local memory
    memory=$(get_resource_request "$ns" "memory")
    if [[ -z "$memory" ]]; then
        pass "No custom memory request (revision 2 had none)"
    else
        fail_with_cmd "Memory request is '$memory' (expected none after rollback to revision 2)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}'"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Recover from failed upgrade ==="
    local release="production-app"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "2" ]]; then
        pass "Deployment has 2 replicas (recovered)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 2)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local memory
    memory=$(get_resource_request "$ns" "memory")
    if [[ "$memory" == "128Mi" ]]; then
        pass "Memory request is 128Mi (stable config restored)"
    else
        fail_with_cmd "Memory request is '$memory' (expected 128Mi)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests.memory}'"
    fi

    # Give pods time to stabilize
    sleep 3

    local ready_pods
    ready_pods=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$ready_pods" -ge 1 ]]; then
        pass "At least one pod is running"
    else
        fail_with_cmd "No running pods found" \
            "kubectl get pods -n $ns"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Atomic upgrade strategy ==="
    local release="strategic-app"
    local ns="ex-5-3"
    local production_file="production.yaml"
    local update_file="update.yaml"

    if ! file_exists "$production_file"; then
        fail "Production values file $production_file does not exist"
    else
        pass "Production values file $production_file exists"
    fi

    if ! file_exists "$update_file"; then
        fail "Update values file $update_file does not exist"
    else
        pass "Update values file $update_file exists"
    fi

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found" \
            "helm list -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$ns")
    if [[ "$replicas" == "4" ]]; then
        pass "Deployment has 4 replicas (upgrade succeeded)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 4)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local revision_count
    revision_count=$(get_revision_count "$release" "$ns")
    if [[ "$revision_count" == "2" ]]; then
        pass "Total of 2 revisions (install + upgrade)"
    else
        fail_with_cmd "Found $revision_count revisions (expected 2)" \
            "helm history $release -n $ns"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Upgrade Operations"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Values Files"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Lifecycle Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Rollback Operations"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Complex Lifecycle"
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
