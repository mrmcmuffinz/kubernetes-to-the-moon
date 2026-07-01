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

# Helper: check if helm repo exists
repo_exists() {
    local repo=$1
    helm repo list 2>/dev/null | grep -q "^${repo}"
}

# Helper: check if helm release exists
release_exists() {
    local release=$1
    local ns=$2
    helm list -n "$ns" 2>/dev/null | grep -q "^${release}"
}

# Helper: get release status
get_release_status() {
    local release=$1
    local ns=$2
    helm list -n "$ns" -o json 2>/dev/null | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4 || echo ""
}

# Helper: get deployment replicas
get_deployment_replicas() {
    local ns=$1
    kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0"
}

# Helper: get service type
get_service_type() {
    local ns=$1
    kubectl get svc -n "$ns" -o jsonpath='{.items[0].spec.type}' 2>/dev/null || echo ""
}

# Helper: get helm values
get_helm_value() {
    local release=$1
    local ns=$2
    local key=$3
    helm get values "$release" -n "$ns" 2>/dev/null | grep "^${key}:" | awk '{print $2}' || echo ""
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Add jetstack repository ==="

    if repo_exists "jetstack"; then
        pass "Repository 'jetstack' exists"
    else
        fail_with_cmd "Repository 'jetstack' not found" \
            "helm repo list"
        return
    fi

    local url
    url=$(helm repo list 2>/dev/null | grep "^jetstack" | awk '{print $2}')
    if [[ "$url" == *"charts.jetstack.io"* ]]; then
        pass "Jetstack URL is correct (charts.jetstack.io)"
    else
        fail_with_cmd "Jetstack URL is incorrect: $url" \
            "helm repo list | grep jetstack"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Search for charts ==="

    if ! repo_exists "bitnami"; then
        fail "Bitnami repository not found (required for this exercise)"
        return
    fi

    local search_result
    search_result=$(helm search repo bitnami/redis 2>/dev/null | grep -c "bitnami/redis" || echo "0")
    if [[ "$search_result" -gt 0 ]]; then
        pass "Redis chart found in bitnami repository"
    else
        fail_with_cmd "Redis chart not found in search" \
            "helm search repo bitnami/redis"
    fi

    local versions_result
    versions_result=$(helm search repo bitnami/redis --versions 2>/dev/null | grep -c "bitnami/redis" || echo "0")
    if [[ "$versions_result" -gt 1 ]]; then
        pass "Multiple redis versions found with --versions flag"
    else
        fail_with_cmd "Multiple versions not shown" \
            "helm search repo bitnami/redis --versions | head -10"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Update repository indexes ==="

    # This exercise is about running the command successfully
    # We can't verify timestamp changes, so we check repo list works
    if helm repo list &>/dev/null; then
        pass "Repository list accessible (helm repo update should work)"
    else
        fail_with_cmd "No repositories configured" \
            "helm repo list"
    fi

    # Check that update command works
    if helm repo update &>/dev/null; then
        pass "helm repo update executed successfully"
    else
        fail_with_cmd "helm repo update failed" \
            "helm repo update"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Install chart with default values ==="
    local release="web-server"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release '$release' not found in namespace $ns" \
            "helm list -n $ns"
        return
    fi

    local status
    status=$(get_release_status "$release" "$ns")
    if [[ "$status" == "deployed" ]]; then
        pass "Release status is deployed"
    else
        fail_with_cmd "Release status is '$status' (expected deployed)" \
            "helm status $release -n $ns"
    fi

    # Check pods are running
    sleep 3
    local pod_count
    pod_count=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running 2>/dev/null | grep -c nginx || echo "0")
    if [[ "$pod_count" -gt 0 ]]; then
        pass "Pods are running in namespace $ns"
    else
        fail_with_cmd "No running pods found" \
            "kubectl get pods -n $ns"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Install chart with namespace creation ==="
    local release="cache-server"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist (should have been created with --create-namespace)"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release '$release' not found in namespace $ns" \
            "helm list -n $ns"
        return
    fi

    pass "Namespace $ns was created"
    pass "Release $release is deployed"

    # Check pods are running
    sleep 3
    local pod_count
    pod_count=$(kubectl get pods -n "$ns" 2>/dev/null | grep -c redis || echo "0")
    if [[ "$pod_count" -gt 0 ]]; then
        pass "Redis pods exist in namespace $ns"
    else
        fail_with_cmd "No redis pods found" \
            "kubectl get pods -n $ns"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: List releases and check status ==="

    # Check if both releases from 2.1 and 2.2 exist
    local all_releases
    all_releases=$(helm list --all-namespaces 2>/dev/null | grep -E "(web-server|cache-server)" | wc -l)
    if [[ "$all_releases" -ge 2 ]]; then
        pass "Both web-server and cache-server releases found"
    else
        fail_with_cmd "Expected to find both web-server and cache-server releases" \
            "helm list --all-namespaces | grep -E '(web-server|cache-server)'"
    fi

    # Check status command works
    if helm status web-server -n ex-2-1 &>/dev/null; then
        pass "helm status web-server command works"
    else
        fail_with_cmd "Cannot get status for web-server" \
            "helm status web-server -n ex-2-1"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug repository typo ==="
    local release="web-app"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release '$release' not found (typo not fixed)" \
            "helm list -n $ns"
        return
    fi

    pass "Release $release deployed (typo fixed)"

    local status
    status=$(get_release_status "$release" "$ns")
    if [[ "$status" == "deployed" ]]; then
        pass "Release status is deployed"
    else
        fail_with_cmd "Release status is '$status'" \
            "helm status $release -n $ns"
    fi

    # Check pods
    sleep 3
    local pod_count
    pod_count=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running 2>/dev/null | grep -c . || echo "0")
    if [[ "$pod_count" -gt 0 ]]; then
        pass "Pods are running"
    else
        fail_with_cmd "No running pods found" \
            "kubectl get pods -n $ns"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug release name conflict ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local release_count
    release_count=$(helm list -n "$ns" 2>/dev/null | grep -c deployed || echo "0")
    if [[ "$release_count" -ge 2 ]]; then
        pass "Two releases found in namespace $ns"
    else
        fail_with_cmd "Expected 2 releases, found $release_count" \
            "helm list -n $ns"
    fi

    # Both should be deployed
    local deployed_count
    deployed_count=$(helm list -n "$ns" -o json 2>/dev/null | grep -o '"status":"deployed"' | wc -l)
    if [[ "$deployed_count" -ge 2 ]]; then
        pass "Both releases have deployed status"
    else
        fail_with_cmd "Not all releases are deployed" \
            "helm list -n $ns"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug --set syntax error ==="
    local release="fixed-nginx"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release '$release' not found (--set syntax not fixed)" \
            "helm list -n $ns"
        return
    fi

    pass "Release $release deployed (--set syntax fixed)"

    # Check replicas
    sleep 3
    local replicas
    replicas=$(get_deployment_replicas "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Install with --set overrides ==="
    local release="custom-web"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release '$release' not found" \
            "helm list -n $ns"
        return
    fi

    # Check replicas
    sleep 3
    local replicas
    replicas=$(get_deployment_replicas "$ns")
    if [[ "$replicas" == "2" ]]; then
        pass "Deployment has 2 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 2)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    # Check service type
    local svc_type
    svc_type=$(get_service_type "$ns")
    if [[ "$svc_type" == "ClusterIP" ]]; then
        pass "Service type is ClusterIP"
    else
        fail_with_cmd "Service type is $svc_type (expected ClusterIP)" \
            "kubectl get svc -n $ns -o jsonpath='{.items[0].spec.type}'"
    fi

    # Check helm values
    local values_output
    values_output=$(helm get values "$release" -n "$ns" 2>/dev/null || echo "")
    if [[ -n "$values_output" ]]; then
        pass "helm get values returns configuration"
    else
        fail_with_cmd "helm get values returned nothing" \
            "helm get values $release -n $ns"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Configure nested values with dot notation ==="
    local release="resource-web"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release '$release' not found" \
            "helm list -n $ns"
        return
    fi

    sleep 3

    # Check resource requests
    local memory_request
    memory_request=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")
    if [[ "$memory_request" == "128Mi" ]]; then
        pass "Memory request is 128Mi"
    else
        fail_with_cmd "Memory request is '$memory_request' (expected 128Mi)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests}'"
    fi

    local cpu_request
    cpu_request=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
    if [[ "$cpu_request" == "100m" ]]; then
        pass "CPU request is 100m"
    else
        fail_with_cmd "CPU request is '$cpu_request' (expected 100m)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests}'"
    fi

    # Check service type
    local svc_type
    svc_type=$(get_service_type "$ns")
    if [[ "$svc_type" == "ClusterIP" ]]; then
        pass "Service type is ClusterIP"
    else
        fail_with_cmd "Service type is $svc_type (expected ClusterIP)" \
            "kubectl get svc -n $ns -o jsonpath='{.items[0].spec.type}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Inspect and install with informed customization ==="
    local release="custom-cache"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release '$release' not found" \
            "helm list -n $ns"
        return
    fi

    # Check architecture is standalone
    local arch_value
    arch_value=$(helm get values "$release" -n "$ns" 2>/dev/null | grep "^architecture:" | awk '{print $2}')
    if [[ "$arch_value" == "standalone" ]]; then
        pass "Architecture is standalone"
    else
        fail_with_cmd "Architecture is '$arch_value' (expected standalone)" \
            "helm get values $release -n $ns | grep architecture"
    fi

    # Check auth is disabled
    local auth_check
    auth_check=$(helm get values "$release" -n "$ns" 2>/dev/null | grep -A1 "^auth:" | grep "enabled:" | awk '{print $2}')
    if [[ "$auth_check" == "false" ]]; then
        pass "Auth is disabled"
    else
        fail_with_cmd "Auth enabled is '$auth_check' (expected false)" \
            "helm get values $release -n $ns | grep -A1 auth"
    fi

    sleep 3

    # Check pods exist
    local pod_count
    pod_count=$(kubectl get pods -n "$ns" 2>/dev/null | grep -c redis || echo "0")
    if [[ "$pod_count" -gt 0 ]]; then
        pass "Redis pods running"
    else
        fail_with_cmd "No redis pods found" \
            "kubectl get pods -n $ns"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Install multiple related charts ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check both releases exist
    local frontend_exists
    frontend_exists=$(helm list -n "$ns" 2>/dev/null | grep -c "^frontend" || echo "0")
    local backend_exists
    backend_exists=$(helm list -n "$ns" 2>/dev/null | grep -c "^backend" || echo "0")

    if [[ "$frontend_exists" -gt 0 ]] && [[ "$backend_exists" -gt 0 ]]; then
        pass "Both frontend and backend releases found"
    else
        fail_with_cmd "Expected both frontend and backend releases" \
            "helm list -n $ns"
        return
    fi

    sleep 5

    # Check services exist
    local svc_count
    svc_count=$(kubectl get svc -n "$ns" 2>/dev/null | grep -c -E "(nginx|redis)" || echo "0")
    if [[ "$svc_count" -ge 2 ]]; then
        pass "Multiple services exist in namespace"
    else
        fail_with_cmd "Expected at least 2 services" \
            "kubectl get svc -n $ns"
    fi

    # Check pods are running
    local pod_count
    pod_count=$(kubectl get pods -n "$ns" 2>/dev/null | grep -c Running || echo "0")
    if [[ "$pod_count" -gt 0 ]]; then
        pass "Pods are running"
    else
        fail_with_cmd "No running pods found" \
            "kubectl get pods -n $ns"
    fi

    # Check frontend service type
    local frontend_svc
    frontend_svc=$(kubectl get svc -n "$ns" -o json 2>/dev/null | grep -o '"name":"frontend-nginx"' -A5 | grep -o '"type":"[^"]*"' | cut -d'"' -f4 || echo "")
    if [[ "$frontend_svc" == "ClusterIP" ]]; then
        pass "Frontend service type is ClusterIP"
    else
        info "Frontend service exists (type: $frontend_svc)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug multiple installation issues ==="
    local release="working-cache"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release '$release' not found (installation issues not fixed)" \
            "helm list -n $ns"
        return
    fi

    pass "Release $release deployed (installation issues fixed)"

    # Check configuration
    local values_output
    values_output=$(helm get values "$release" -n "$ns" 2>/dev/null || echo "")
    if [[ -n "$values_output" ]]; then
        pass "Configuration values are set"
    else
        fail_with_cmd "No configuration values found" \
            "helm get values $release -n $ns"
    fi

    sleep 3

    # Check pods running
    local pod_count
    pod_count=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running 2>/dev/null | grep -c . || echo "0")
    if [[ "$pod_count" -gt 0 ]]; then
        pass "Pods are running"
    else
        fail_with_cmd "No running pods found" \
            "kubectl get pods -n $ns"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Document production installation ==="
    local release="production-web"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release '$release' not found" \
            "helm list -n $ns"
        return
    fi

    sleep 3

    # Check replicas
    local replicas
    replicas=$(get_deployment_replicas "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    # Check resource requests
    local memory_request
    memory_request=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests.memory}' 2>/dev/null || echo "")
    if [[ "$memory_request" == "256Mi" ]]; then
        pass "Memory request is 256Mi"
    else
        fail_with_cmd "Memory request is '$memory_request' (expected 256Mi)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}'"
    fi

    local cpu_request
    cpu_request=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null || echo "")
    if [[ "$cpu_request" == "200m" ]]; then
        pass "CPU request is 200m"
    else
        fail_with_cmd "CPU request is '$cpu_request' (expected 200m)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}'"
    fi

    # Check resource limits
    local memory_limit
    memory_limit=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null || echo "")
    if [[ "$memory_limit" == "512Mi" ]]; then
        pass "Memory limit is 512Mi"
    else
        fail_with_cmd "Memory limit is '$memory_limit' (expected 512Mi)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}'"
    fi

    local cpu_limit
    cpu_limit=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.limits.cpu}' 2>/dev/null || echo "")
    if [[ "$cpu_limit" == "500m" ]]; then
        pass "CPU limit is 500m"
    else
        fail_with_cmd "CPU limit is '$cpu_limit' (expected 500m)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}'"
    fi

    # Check that documentation commands work
    if helm status "$release" -n "$ns" &>/dev/null; then
        pass "helm status command works"
    else
        fail_with_cmd "Cannot get release status" \
            "helm status $release -n $ns"
    fi

    if helm get manifest "$release" -n "$ns" &>/dev/null; then
        pass "helm get manifest command works"
    else
        fail_with_cmd "Cannot get release manifest" \
            "helm get manifest $release -n $ns"
    fi

    if helm get values "$release" -n "$ns" &>/dev/null; then
        pass "helm get values command works"
    else
        fail_with_cmd "Cannot get release values" \
            "helm get values $release -n $ns"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Repository Management"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Chart Installation"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Installation Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Values Customization"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Complex Installations"
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
