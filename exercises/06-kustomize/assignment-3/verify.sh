#!/usr/bin/env bash
#
# verify.sh - Automated verification for kustomize-homework.md (Assignment 3: Overlays and Components)
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

# Helper: check if deployment exists
deployment_exists() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" &>/dev/null
}

# Helper: get deployment replicas
get_replicas() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null
}

# Helper: get deployment label
get_deployment_label() {
    local name=$1
    local ns=$2
    local label=$3
    kubectl get deployment "$name" -n "$ns" -o jsonpath="{.metadata.labels.$label}" 2>/dev/null
}

# Helper: get deployment annotation
get_deployment_annotation() {
    local name=$1
    local ns=$2
    local annotation=$3
    kubectl get deployment "$name" -n "$ns" -o jsonpath="{.metadata.annotations.$annotation}" 2>/dev/null
}

# Helper: get pod template annotation
get_pod_template_annotation() {
    local name=$1
    local ns=$2
    local annotation=$3
    kubectl get deployment "$name" -n "$ns" -o jsonpath="{.spec.template.metadata.annotations.$annotation}" 2>/dev/null
}

# Helper: get environment variable from deployment
get_env_from_deployment() {
    local name=$1
    local ns=$2
    local varname=$3
    kubectl get deployment "$name" -n "$ns" -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='$varname')].value}" 2>/dev/null
}

# Helper: get resource limits
get_resource_limits() {
    local name=$1
    local ns=$2
    local resource=$3
    kubectl get deployment "$name" -n "$ns" -o jsonpath="{.spec.template.spec.containers[0].resources.limits.$resource}" 2>/dev/null
}

# Helper: get security context field
get_security_context() {
    local name=$1
    local ns=$2
    local field=$3
    kubectl get deployment "$name" -n "$ns" -o jsonpath="{.spec.template.spec.securityContext.$field}" 2>/dev/null
}

# Helper: check if service exists
service_exists() {
    local name=$1
    local ns=$2
    kubectl get service "$name" -n "$ns" &>/dev/null
}

# Helper: check if kustomization builds
kustomize_builds() {
    local path=$1
    kubectl kustomize "$path" &>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Create a base kustomization ==="
    local base_path=~/kustomize-overlays/ex-1-1/base

    if [[ ! -d "$base_path" ]]; then
        fail "Base directory does not exist at $base_path"
        return
    fi

    if ! kustomize_builds "$base_path"; then
        fail_with_cmd "Base kustomization does not build" \
            "kubectl kustomize $base_path"
        return
    fi

    local output
    output=$(kubectl kustomize "$base_path" 2>/dev/null)

    if echo "$output" | grep -q "kind: Deployment"; then
        pass "Base includes Deployment"
    else
        fail_with_cmd "Base does not include Deployment" \
            "kubectl kustomize $base_path | grep -A5 'kind: Deployment'"
    fi

    if echo "$output" | grep -q "kind: Service"; then
        pass "Base includes Service"
    else
        fail_with_cmd "Base does not include Service" \
            "kubectl kustomize $base_path | grep -A5 'kind: Service'"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Create a dev overlay ==="
    local ns="ex-1-2-dev"
    local overlay_path=~/kustomize-overlays/ex-1-1/overlays/dev

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if [[ ! -d "$overlay_path" ]]; then
        fail "Overlay directory does not exist at $overlay_path"
        return
    fi

    if ! kustomize_builds "$overlay_path"; then
        fail_with_cmd "Dev overlay does not build" \
            "kubectl kustomize $overlay_path"
        return
    fi

    # Check for deployment with dev- prefix
    local deployments
    deployments=$(kubectl get deployment -n "$ns" -o name 2>/dev/null | grep "dev-" || echo "")

    if [[ -n "$deployments" ]]; then
        pass "Deployment with dev- prefix exists in namespace $ns"
    else
        fail_with_cmd "No deployment with dev- prefix found in namespace $ns" \
            "kubectl get deployment -n $ns"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Create base and overlay in one exercise ==="
    local ns="ex-1-3"
    local base_path=~/kustomize-overlays/ex-1-3/base
    local overlay_path=~/kustomize-overlays/ex-1-3/overlays/dev

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if [[ ! -d "$base_path" ]] || [[ ! -d "$overlay_path" ]]; then
        fail "Base or overlay directory missing"
        return
    fi

    if ! kustomize_builds "$overlay_path"; then
        fail_with_cmd "Overlay does not build" \
            "kubectl kustomize $overlay_path"
        return
    fi

    # Find the deployment (name may vary)
    local deployment_name
    deployment_name=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$deployment_name" ]]; then
        fail_with_cmd "No deployment found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    local tier_label
    tier_label=$(get_deployment_label "$deployment_name" "$ns" "tier")

    if [[ "$tier_label" == "frontend" ]]; then
        pass "Deployment has label tier=frontend"
    else
        fail_with_cmd "Deployment label tier=$tier_label (expected frontend)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.metadata.labels}'"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Create dev and prod overlays with different settings ==="
    local dev_ns="ex-2-1-dev"
    local prod_ns="ex-2-1-prod"

    if ! namespace_exists "$dev_ns"; then
        fail "Dev namespace $dev_ns does not exist"
        return
    fi

    if ! namespace_exists "$prod_ns"; then
        fail "Prod namespace $prod_ns does not exist"
        return
    fi

    # Check dev deployment
    local dev_deployment
    dev_deployment=$(kubectl get deployment -n "$dev_ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$dev_deployment" ]]; then
        local dev_replicas
        dev_replicas=$(get_replicas "$dev_deployment" "$dev_ns")

        if [[ "$dev_replicas" == "1" ]]; then
            pass "Dev deployment has 1 replica"
        else
            fail_with_cmd "Dev deployment has $dev_replicas replicas (expected 1)" \
                "kubectl get deployment $dev_deployment -n $dev_ns -o jsonpath='{.spec.replicas}'"
        fi
    else
        fail "No deployment found in dev namespace"
    fi

    # Check prod deployment
    local prod_deployment
    prod_deployment=$(kubectl get deployment -n "$prod_ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -n "$prod_deployment" ]]; then
        local prod_replicas
        prod_replicas=$(get_replicas "$prod_deployment" "$prod_ns")

        if [[ "$prod_replicas" == "3" ]]; then
            pass "Prod deployment has 3 replicas"
        else
            fail_with_cmd "Prod deployment has $prod_replicas replicas (expected 3)" \
                "kubectl get deployment $prod_deployment -n $prod_ns -o jsonpath='{.spec.replicas}'"
        fi
    else
        fail "No deployment found in prod namespace"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Configure environment-specific namespaces ==="
    local dev_ns="webapp-dev"
    local prod_ns="webapp-prod"
    local deployment_name="webapp"

    if ! namespace_exists "$dev_ns"; then
        fail "Dev namespace $dev_ns does not exist"
        return
    fi

    if ! namespace_exists "$prod_ns"; then
        fail "Prod namespace $prod_ns does not exist"
        return
    fi

    if deployment_exists "$deployment_name" "$dev_ns"; then
        pass "Deployment $deployment_name exists in $dev_ns"
    else
        fail_with_cmd "Deployment $deployment_name not found in $dev_ns" \
            "kubectl get deployment -n $dev_ns"
    fi

    if deployment_exists "$deployment_name" "$prod_ns"; then
        pass "Deployment $deployment_name exists in $prod_ns"
    else
        fail_with_cmd "Deployment $deployment_name not found in $prod_ns" \
            "kubectl get deployment -n $prod_ns"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Layer patches in overlay ==="
    local ns="ex-2-3"
    local deployment_name
    deployment_name=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if [[ -z "$deployment_name" ]]; then
        fail_with_cmd "No deployment found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment_name" "$ns")

    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.replicas}'"
    fi

    local env_value
    env_value=$(get_env_from_deployment "$deployment_name" "$ns" "ENVIRONMENT")

    if [[ "$env_value" == "production" ]]; then
        pass "Environment variable ENVIRONMENT=production"
    else
        fail_with_cmd "ENVIRONMENT=$env_value (expected production)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.template.spec.containers[0].env}'"
    fi

    local memory_limit
    memory_limit=$(get_resource_limits "$deployment_name" "$ns" "memory")

    if [[ -n "$memory_limit" ]]; then
        pass "Resource limits are set (memory: $memory_limit)"
    else
        fail_with_cmd "Resource limits not set" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.template.spec.containers[0].resources.limits}'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug a base path issue ==="
    local ns="ex-3-1"
    local overlay_path=~/kustomize-overlays/ex-3-1/overlays/dev

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! kustomize_builds "$overlay_path"; then
        fail_with_cmd "Overlay does not build (path issue not fixed)" \
            "kubectl kustomize $overlay_path"
        return
    else
        pass "Overlay builds successfully"
    fi

    if deployment_exists "app" "$ns"; then
        pass "Deployment app exists in namespace $ns"
    else
        fail_with_cmd "Deployment app not found in namespace $ns" \
            "kubectl get deployment -n $ns"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug a patch not applying in overlay ==="
    local ns="ex-3-2"
    local deployment_name="webapp"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment_name" "$ns"; then
        fail_with_cmd "Deployment $deployment_name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment_name" "$ns")

    if [[ "$replicas" == "5" ]]; then
        pass "Deployment has 5 replicas (patch applied correctly)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 5, patch may not be applied)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.replicas}'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug a namespace conflict ==="
    local ns="correct-ns"
    local deployment_name="namespaced"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if deployment_exists "$deployment_name" "$ns"; then
        pass "Deployment $deployment_name exists in namespace $ns"
    else
        fail_with_cmd "Deployment $deployment_name not found in $ns (namespace transformer issue)" \
            "kubectl get deployment -n $ns; kubectl kustomize ~/kustomize-overlays/ex-3-3/overlays/dev | grep namespace"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Create a reusable component ==="
    local ns="ex-4-1"
    local deployment_name="app"
    local component_path=~/kustomize-overlays/ex-4-1/components/logging

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if [[ ! -d "$component_path" ]]; then
        fail "Component directory does not exist at $component_path"
        return
    fi

    if ! deployment_exists "$deployment_name" "$ns"; then
        fail_with_cmd "Deployment $deployment_name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    local logging_annotation
    logging_annotation=$(get_deployment_annotation "$deployment_name" "$ns" "logging.enabled")

    if [[ "$logging_annotation" == "true" ]]; then
        pass "Logging annotation logging.enabled=true exists"
    else
        fail_with_cmd "Logging annotation logging.enabled=$logging_annotation (expected true)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.metadata.annotations}'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Include multiple components in overlay ==="
    local ns="ex-4-2"
    local deployment_name="secure-app"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment_name" "$ns"; then
        fail_with_cmd "Deployment $deployment_name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    local metrics_annotation
    metrics_annotation=$(get_deployment_annotation "$deployment_name" "$ns" "metrics.enabled")

    if [[ "$metrics_annotation" == "true" ]]; then
        pass "Metrics annotation metrics.enabled=true exists"
    else
        fail_with_cmd "Metrics annotation metrics.enabled=$metrics_annotation (expected true)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.metadata.annotations}'"
    fi

    local security_annotation
    security_annotation=$(get_deployment_annotation "$deployment_name" "$ns" "security.hardened")

    if [[ "$security_annotation" == "true" ]]; then
        pass "Security annotation security.hardened=true exists"
    else
        fail_with_cmd "Security annotation security.hardened=$security_annotation (expected true)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.metadata.annotations}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Combine component with patches ==="
    local ns="ex-4-3"
    local deployment_name="webapp"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment_name" "$ns"; then
        fail_with_cmd "Deployment $deployment_name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment_name" "$ns")

    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas (from HA component)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3 from HA component)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.replicas}'"
    fi

    local ha_annotation
    ha_annotation=$(get_deployment_annotation "$deployment_name" "$ns" "ha.enabled")

    if [[ "$ha_annotation" == "true" ]]; then
        pass "HA annotation ha.enabled=true exists"
    else
        fail_with_cmd "HA annotation ha.enabled=$ha_annotation (expected true)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.metadata.annotations}'"
    fi

    local env_value
    env_value=$(get_env_from_deployment "$deployment_name" "$ns" "ENVIRONMENT")

    if [[ "$env_value" == "production" ]]; then
        pass "Environment variable ENVIRONMENT=production (from overlay patch)"
    else
        fail_with_cmd "ENVIRONMENT=$env_value (expected production)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.template.spec.containers[0].env}'"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Design a multi-environment structure ==="
    local dev_ns="myapp-dev"
    local prod_ns="myapp-prod"
    local deployment_name="webapp"

    if ! namespace_exists "$dev_ns"; then
        fail "Dev namespace $dev_ns does not exist"
        return
    fi

    if ! namespace_exists "$prod_ns"; then
        fail "Prod namespace $prod_ns does not exist"
        return
    fi

    if deployment_exists "$deployment_name" "$dev_ns"; then
        pass "Dev deployment exists"
    else
        fail_with_cmd "Dev deployment not found" \
            "kubectl get deployment -n $dev_ns"
    fi

    if deployment_exists "$deployment_name" "$prod_ns"; then
        local prod_replicas
        prod_replicas=$(get_replicas "$deployment_name" "$prod_ns")

        if [[ "$prod_replicas" == "3" ]]; then
            pass "Prod deployment has 3 replicas"
        else
            fail_with_cmd "Prod deployment has $prod_replicas replicas (expected 3)" \
                "kubectl get deployment $deployment_name -n $prod_ns -o jsonpath='{.spec.replicas}'"
        fi
    else
        fail_with_cmd "Prod deployment not found" \
            "kubectl get deployment -n $prod_ns"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug a complex overlay chain ==="
    local ns="ex-5-2"
    local deployment_name="complex"
    local overlay_path=~/kustomize-overlays/ex-5-2/overlays/prod

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! kustomize_builds "$overlay_path"; then
        fail_with_cmd "Overlay does not build (issues not fixed)" \
            "kubectl kustomize $overlay_path"
        return
    else
        pass "Overlay builds successfully"
    fi

    if ! deployment_exists "$deployment_name" "$ns"; then
        fail_with_cmd "Deployment $deployment_name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment_name" "$ns")

    if [[ "$replicas" == "5" ]]; then
        pass "Deployment has 5 replicas (component patch applied correctly)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 5)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.replicas}'"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Create a production-ready kustomization structure ==="
    local ns="production"
    local deployment_name
    deployment_name=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if [[ -z "$deployment_name" ]]; then
        fail_with_cmd "No deployment found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment_name" "$ns")

    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.replicas}'"
    fi

    local prometheus_annotation
    prometheus_annotation=$(get_pod_template_annotation "$deployment_name" "$ns" "prometheus.io/scrape")

    if [[ "$prometheus_annotation" == "true" ]]; then
        pass "Prometheus scrape annotation exists"
    else
        fail_with_cmd "Prometheus annotation prometheus.io/scrape=$prometheus_annotation (expected true)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.template.metadata.annotations}'"
    fi

    local security_context
    security_context=$(get_security_context "$deployment_name" "$ns" "runAsNonRoot")

    if [[ "$security_context" == "true" ]]; then
        pass "Security context runAsNonRoot=true exists"
    else
        fail_with_cmd "Security context runAsNonRoot=$security_context (expected true)" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.template.spec.securityContext}'"
    fi

    local memory_limit
    memory_limit=$(get_resource_limits "$deployment_name" "$ns" "memory")

    if [[ -n "$memory_limit" ]]; then
        pass "Resource limits are set (memory: $memory_limit)"
    else
        fail_with_cmd "Resource limits not set" \
            "kubectl get deployment $deployment_name -n $ns -o jsonpath='{.spec.template.spec.containers[0].resources.limits}'"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Base and Overlays"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Environment Configurations"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Overlay Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Components"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Complete Application Structure"
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
