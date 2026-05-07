#!/usr/bin/env bash
#
# verify.sh - Automated verification for kustomize-homework.md
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

# Helper: check if file exists
file_exists() {
    [[ -f "$1" ]]
}

# Helper: check if kustomization builds
kustomization_builds() {
    local dir=$1
    kubectl kustomize "$dir" &>/dev/null
}

# Helper: get deployment ready replicas
get_deployment_ready_replicas() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"
}

# Helper: check if resource exists in namespace
resource_exists() {
    local kind=$1
    local name=$2
    local ns=$3
    kubectl get "$kind" "$name" -n "$ns" &>/dev/null
}

# Helper: get label value
get_label() {
    local kind=$1
    local name=$2
    local ns=$3
    local label=$4
    kubectl get "$kind" "$name" -n "$ns" -o jsonpath="{.metadata.labels.$label}" 2>/dev/null || echo ""
}

# Helper: get annotation value
get_annotation() {
    local kind=$1
    local name=$2
    local ns=$3
    local annotation=$4
    kubectl get "$kind" "$name" -n "$ns" -o jsonpath="{.metadata.annotations.$annotation}" 2>/dev/null || echo ""
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic kustomization ==="
    local dir=~/kustomize-exercises/ex-1-1
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if ! kustomization_builds "$dir"; then
        fail_with_cmd "kustomization does not build" \
            "kubectl kustomize $dir"
        return
    fi

    local output
    output=$(kubectl kustomize "$dir" 2>/dev/null)

    if echo "$output" | grep -q "kind: Deployment"; then
        pass "Output contains Deployment"
    else
        fail_with_cmd "Output missing Deployment" \
            "kubectl kustomize $dir | grep kind"
    fi

    if echo "$output" | grep -q "image: nginx"; then
        pass "Output contains nginx image"
    else
        fail_with_cmd "Output missing nginx image" \
            "kubectl kustomize $dir | grep image"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Build and view output ==="
    local dir=~/kustomize-exercises/ex-1-2
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if ! file_exists "$dir/rendered.yaml"; then
        fail_with_cmd "rendered.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if grep -q "kind: Deployment" "$dir/rendered.yaml"; then
        pass "rendered.yaml contains Deployment"
    else
        fail_with_cmd "rendered.yaml missing Deployment" \
            "grep kind $dir/rendered.yaml"
    fi

    if grep -q "replicas: 2" "$dir/rendered.yaml"; then
        pass "rendered.yaml shows 2 replicas"
    else
        fail_with_cmd "rendered.yaml missing replicas: 2" \
            "grep replicas $dir/rendered.yaml"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Apply kustomization ==="
    local dir=~/kustomize-exercises/ex-1-3
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if ! resource_exists deployment web "$ns"; then
        fail_with_cmd "Deployment web not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    pass "Deployment web exists in namespace $ns"

    sleep 3

    local pod_count
    pod_count=$(kubectl get pods -n "$ns" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [[ "$pod_count" -ge 1 ]]; then
        pass "Pod is running"
    else
        fail_with_cmd "No running pods found" \
            "kubectl get pods -n $ns"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: namePrefix transformer ==="
    local dir=~/kustomize-exercises/ex-2-1
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if resource_exists deployment dev-api "$ns"; then
        pass "Deployment dev-api exists (namePrefix applied)"
    else
        fail_with_cmd "Deployment dev-api not found" \
            "kubectl get deployment -n $ns"
    fi

    if kubectl get deployment api -n "$ns" &>/dev/null; then
        fail "Deployment 'api' still exists (should be renamed to dev-api)"
    else
        pass "Original name 'api' does not exist"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: commonLabels transformer ==="
    local dir=~/kustomize-exercises/ex-2-2
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if ! resource_exists deployment backend "$ns"; then
        fail_with_cmd "Deployment backend not found" \
            "kubectl get deployment -n $ns"
        return
    fi

    local env_label
    env_label=$(get_label deployment backend "$ns" environment)
    if [[ "$env_label" == "development" ]]; then
        pass "Deployment has label environment=development"
    else
        fail_with_cmd "Deployment missing label environment=development (found: $env_label)" \
            "kubectl get deployment backend -n $ns -o jsonpath='{.metadata.labels}'"
    fi

    local team_label
    team_label=$(get_label deployment backend "$ns" team)
    if [[ "$team_label" == "platform" ]]; then
        pass "Deployment has label team=platform"
    else
        fail_with_cmd "Deployment missing label team=platform (found: $team_label)" \
            "kubectl get deployment backend -n $ns -o jsonpath='{.metadata.labels}'"
    fi

    sleep 2

    local pod_env_label
    pod_env_label=$(kubectl get pods -n "$ns" -o jsonpath='{.items[0].metadata.labels.environment}' 2>/dev/null || echo "")
    if [[ "$pod_env_label" == "development" ]]; then
        pass "Pod has label environment=development"
    else
        fail_with_cmd "Pod missing label environment=development" \
            "kubectl get pods -n $ns -o jsonpath='{.items[0].metadata.labels}'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: namespace transformer ==="
    local dir=~/kustomize-exercises/ex-2-3
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if resource_exists deployment frontend "$ns"; then
        pass "Deployment frontend exists in namespace $ns"
    else
        fail_with_cmd "Deployment frontend not found in namespace $ns" \
            "kubectl get deployment -n $ns"
    fi

    if resource_exists service frontend "$ns"; then
        pass "Service frontend exists in namespace $ns"
    else
        fail_with_cmd "Service frontend not found in namespace $ns" \
            "kubectl get service -n $ns"
    fi

    if kubectl get deployment frontend -n default &>/dev/null; then
        fail "Deployment frontend incorrectly exists in default namespace"
    else
        pass "Deployment not in default namespace"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug incorrect resource path ==="
    local dir=~/kustomize-exercises/ex-3-1
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if ! kustomization_builds "$dir"; then
        fail_with_cmd "kustomization still fails to build" \
            "kubectl kustomize $dir"
        return
    fi

    pass "Kustomization builds successfully"

    if resource_exists deployment myapp "$ns"; then
        pass "Deployment myapp created successfully"
    else
        fail_with_cmd "Deployment myapp not found (apply may have failed)" \
            "kubectl get deployment -n $ns"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug label conflict ==="
    local dir=~/kustomize-exercises/ex-3-2
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if ! resource_exists service webapp "$ns"; then
        fail_with_cmd "Service webapp not found" \
            "kubectl get service -n $ns"
        return
    fi

    sleep 3

    local endpoint_ip
    endpoint_ip=$(kubectl get endpoints webapp -n "$ns" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || echo "")

    if [[ -n "$endpoint_ip" ]]; then
        pass "Service has endpoints (selector matches pods)"
    else
        fail_with_cmd "Service has no endpoints (selector mismatch)" \
            "kubectl get endpoints webapp -n $ns && kubectl get pods -n $ns --show-labels"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug missing apiVersion ==="
    local dir=~/kustomize-exercises/ex-3-3
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if ! kustomization_builds "$dir"; then
        fail_with_cmd "kustomization still fails to build" \
            "kubectl kustomize $dir"
        return
    fi

    pass "Kustomization builds successfully"

    if resource_exists deployment broken "$ns"; then
        pass "Deployment broken created successfully"
    else
        fail_with_cmd "Deployment broken not found" \
            "kubectl get deployment -n $ns"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Multiple transformers ==="
    local dir=~/kustomize-exercises/ex-4-1
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    local deployment_name
    deployment_name=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ "$deployment_name" == prod-* ]]; then
        pass "Deployment name has prefix 'prod-': $deployment_name"
    else
        fail_with_cmd "Deployment name missing prefix (found: $deployment_name)" \
            "kubectl get deployment -n $ns"
    fi

    local tier_label
    tier_label=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.labels.tier}' 2>/dev/null || echo "")
    if [[ "$tier_label" == "frontend" ]]; then
        pass "Deployment has label tier=frontend"
    else
        fail_with_cmd "Deployment missing label tier=frontend" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].metadata.labels}'"
    fi

    local env_label
    env_label=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.labels.env}' 2>/dev/null || echo "")
    if [[ "$env_label" == "production" ]]; then
        pass "Deployment has label env=production"
    else
        fail_with_cmd "Deployment missing label env=production" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].metadata.labels}'"
    fi

    local service_name
    service_name=$(kubectl get service -n "$ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    if [[ "$service_name" == prod-* ]]; then
        pass "Service name has prefix 'prod-': $service_name"
    else
        fail_with_cmd "Service name missing prefix" \
            "kubectl get service -n $ns"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Labels and annotations ==="
    local dir=~/kustomize-exercises/ex-4-2
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    local team_label
    team_label=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.labels.team}' 2>/dev/null || echo "")
    if [[ "$team_label" == "platform" ]]; then
        pass "Deployment has label team=platform"
    else
        fail_with_cmd "Deployment missing label team=platform" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].metadata.labels}'"
    fi

    local owner_annotation
    owner_annotation=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.annotations.owner}' 2>/dev/null || echo "")
    if [[ "$owner_annotation" == "platform-team" ]]; then
        pass "Deployment has annotation owner=platform-team"
    else
        fail_with_cmd "Deployment missing annotation owner=platform-team" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].metadata.annotations}'"
    fi

    local cost_annotation
    cost_annotation=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.annotations.cost-center}' 2>/dev/null || echo "")
    if [[ "$cost_annotation" == "engineering" ]]; then
        pass "Deployment has annotation cost-center=engineering"
    else
        fail_with_cmd "Deployment missing annotation cost-center=engineering" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].metadata.annotations}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Prefix and suffix together ==="
    local dir=~/kustomize-exercises/ex-4-3
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if resource_exists deployment team1-api-v2 "$ns"; then
        pass "Deployment team1-api-v2 exists (prefix and suffix applied)"
    else
        fail_with_cmd "Deployment team1-api-v2 not found" \
            "kubectl get deployment -n $ns"
    fi

    if kubectl get deployment api -n "$ns" &>/dev/null; then
        fail "Original deployment 'api' still exists"
    else
        pass "Original name 'api' does not exist"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multi-service application ==="
    local dir=~/kustomize-exercises/ex-5-1
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    local deployment_count
    deployment_count=$(kubectl get deployment -n "$ns" --no-headers 2>/dev/null | grep -c "myapp-" || echo "0")
    if [[ "$deployment_count" -eq 2 ]]; then
        pass "2 deployments with myapp- prefix exist"
    else
        fail_with_cmd "Expected 2 deployments with myapp- prefix, found $deployment_count" \
            "kubectl get deployment -n $ns"
    fi

    local service_count
    service_count=$(kubectl get service -n "$ns" --no-headers 2>/dev/null | grep -c "myapp-" || echo "0")
    if [[ "$service_count" -eq 2 ]]; then
        pass "2 services with myapp- prefix exist"
    else
        fail_with_cmd "Expected 2 services with myapp- prefix, found $service_count" \
            "kubectl get service -n $ns"
    fi

    local total_deployments
    total_deployments=$(kubectl get deployment -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$total_deployments" -eq 2 ]]; then
        pass "Total deployment count is 2"
    else
        fail_with_cmd "Total deployment count is $total_deployments (expected 2)" \
            "kubectl get deployment -n $ns"
    fi

    local total_services
    total_services=$(kubectl get service -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$total_services" -eq 2 ]]; then
        pass "Total service count is 2"
    else
        fail_with_cmd "Total service count is $total_services (expected 2)" \
            "kubectl get service -n $ns"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug complex kustomization ==="
    local dir=~/kustomize-exercises/ex-5-2
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if ! kustomization_builds "$dir"; then
        fail_with_cmd "kustomization still fails to build" \
            "kubectl kustomize $dir"
        return
    fi

    pass "Kustomization builds successfully"

    local resources_with_prefix
    resources_with_prefix=$(kubectl get deployment,service,configmap -n "$ns" --no-headers 2>/dev/null | grep -c "debug-" || echo "0")
    if [[ "$resources_with_prefix" -eq 3 ]]; then
        pass "All 3 resources exist with debug- prefix"
    else
        fail_with_cmd "Expected 3 resources with debug- prefix, found $resources_with_prefix" \
            "kubectl get deployment,service,configmap -n $ns"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Complete application kustomization ==="
    local dir=~/kustomize-exercises/ex-5-3
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$dir/kustomization.yaml"; then
        fail_with_cmd "kustomization.yaml not found" \
            "ls -la $dir/"
        return
    fi

    if ! kustomization_builds "$dir"; then
        fail_with_cmd "kustomization fails to build" \
            "kubectl kustomize $dir"
        return
    fi

    pass "Kustomization builds successfully"

    local replicas
    replicas=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null || echo "0")
    if [[ "$replicas" -eq 3 ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local labels
    labels=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null || echo "")
    if [[ -n "$labels" ]]; then
        pass "Deployment has labels: $labels"
    else
        fail_with_cmd "Deployment missing labels" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].metadata.labels}'"
    fi

    local annotations
    annotations=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.annotations}' 2>/dev/null || echo "")
    if [[ -n "$annotations" ]]; then
        pass "Deployment has annotations"
    else
        fail_with_cmd "Deployment missing annotations" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].metadata.annotations}'"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic Kustomization"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Common Transformers"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Kustomization Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Multi-Resource Kustomizations"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Application Scenarios"
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
