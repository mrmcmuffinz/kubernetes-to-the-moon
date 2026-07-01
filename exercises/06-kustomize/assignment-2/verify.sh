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

# Helper: get container image
get_image() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null
}

# Helper: get environment variables
get_env_vars() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].env}' 2>/dev/null
}

# Helper: get specific env var value
get_env_value() {
    local name=$1
    local ns=$2
    local var=$3
    kubectl get deployment "$name" -n "$ns" -o jsonpath="{.spec.template.spec.containers[0].env[?(@.name=='$var')].value}" 2>/dev/null
}

# Helper: get resource requests
get_resource_requests() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].resources.requests}' 2>/dev/null
}

# Helper: get resource limits
get_resource_limits() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].resources.limits}' 2>/dev/null
}

# Helper: check if ConfigMap exists
configmap_exists() {
    local name=$1
    local ns=$2
    kubectl get configmap "$name" -n "$ns" &>/dev/null
}

# Helper: get ConfigMap data
get_configmap_data() {
    local name=$1
    local ns=$2
    kubectl get configmap "$name" -n "$ns" -o jsonpath='{.data}' 2>/dev/null
}

# Helper: check if Secret exists
secret_exists() {
    local name=$1
    local ns=$2
    kubectl get secret "$name" -n "$ns" &>/dev/null
}

# Helper: check if kustomization builds successfully
kustomization_builds() {
    local dir=$1
    kubectl kustomize "$dir" &>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Strategic merge patch - modify replicas ==="
    local deployment="webapp"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment" "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.replicas}'"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Strategic merge patch - add environment variables ==="
    local deployment="api"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local log_level
    log_level=$(get_env_value "$deployment" "$ns" "LOG_LEVEL")
    if [[ "$log_level" == "debug" ]]; then
        pass "LOG_LEVEL=debug"
    else
        fail_with_cmd "LOG_LEVEL=$log_level (expected debug)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.template.spec.containers[0].env}'"
    fi

    local environment
    environment=$(get_env_value "$deployment" "$ns" "ENVIRONMENT")
    if [[ "$environment" == "development" ]]; then
        pass "ENVIRONMENT=development"
    else
        fail_with_cmd "ENVIRONMENT=$environment (expected development)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.template.spec.containers[0].env}'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Strategic merge patch - add resource requests and limits ==="
    local deployment="backend"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local requests
    requests=$(get_resource_requests "$deployment" "$ns")
    if [[ "$requests" == *"64Mi"* ]] && [[ "$requests" == *"50m"* ]]; then
        pass "Resource requests configured (memory: 64Mi, cpu: 50m)"
    else
        fail_with_cmd "Resource requests: $requests (expected memory: 64Mi, cpu: 50m)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.template.spec.containers[0].resources}'"
    fi

    local limits
    limits=$(get_resource_limits "$deployment" "$ns")
    if [[ "$limits" == *"128Mi"* ]] && [[ "$limits" == *"100m"* ]]; then
        pass "Resource limits configured (memory: 128Mi, cpu: 100m)"
    else
        fail_with_cmd "Resource limits: $limits (expected memory: 128Mi, cpu: 100m)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.template.spec.containers[0].resources}'"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: JSON 6902 patch ==="
    local deployment="service"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment" "$ns")
    if [[ "$replicas" == "4" ]]; then
        pass "Deployment has 4 replicas (JSON 6902 patch applied)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 4)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.replicas}'"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Images transformer - change tag ==="
    local deployment="web"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local image
    image=$(get_image "$deployment" "$ns")
    if [[ "$image" == "nginx:1.26" ]]; then
        pass "Image is nginx:1.26 (images transformer applied)"
    else
        fail_with_cmd "Image is $image (expected nginx:1.26)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.template.spec.containers[0].image}'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Images transformer - httpd tag ==="
    local deployment="apache"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local image
    image=$(get_image "$deployment" "$ns")
    if [[ "$image" == "httpd:2.4.58" ]]; then
        pass "Image is httpd:2.4.58 (images transformer applied)"
    else
        fail_with_cmd "Image is $image (expected httpd:2.4.58)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.template.spec.containers[0].image}'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug strategic merge patch ==="
    local deployment="myapp"
    local ns="ex-3-1"
    local dir="$HOME/kustomize-patches/ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if [[ ! -f "$dir/kustomization.yaml" ]]; then
        fail "kustomization.yaml not found in $dir"
        return
    fi

    if ! kustomization_builds "$dir"; then
        fail_with_cmd "Kustomization does not build" \
            "kubectl kustomize $dir"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment" "$ns")
    if [[ "$replicas" == "5" ]]; then
        pass "Deployment has 5 replicas (patch fixed)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 5)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.replicas}'"
        info "Hint: Check that patch metadata.name matches deployment name"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug JSON 6902 patch path ==="
    local deployment="broken"
    local ns="ex-3-2"
    local dir="$HOME/kustomize-patches/ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if [[ ! -f "$dir/kustomization.yaml" ]]; then
        fail "kustomization.yaml not found in $dir"
        return
    fi

    if ! kustomization_builds "$dir"; then
        fail_with_cmd "Kustomization does not build" \
            "kubectl kustomize $dir"
        info "Hint: Check JSON patch path is correct (/spec/replicas not /spec/replica)"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment" "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas (JSON patch fixed)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.replicas}'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug patch target ==="
    local deployment="frontend"
    local ns="ex-3-3"
    local dir="$HOME/kustomize-patches/ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if [[ ! -f "$dir/kustomization.yaml" ]]; then
        fail "kustomization.yaml not found in $dir"
        return
    fi

    if ! kustomization_builds "$dir"; then
        fail_with_cmd "Kustomization does not build" \
            "kubectl kustomize $dir"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment" "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas (patch target fixed)"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.replicas}'"
        info "Hint: Check that patch target name matches deployment name"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: ConfigMap from literals ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # ConfigMap will have hash suffix, so we need to find it
    local configmaps
    configmaps=$(kubectl get configmap -n "$ns" --no-headers 2>/dev/null | grep "app-config" | wc -l)
    if [[ "$configmaps" -eq 0 ]]; then
        fail_with_cmd "ConfigMap app-config not found in namespace $ns" \
            "kubectl get configmaps -n $ns"
        return
    fi

    pass "ConfigMap app-config exists (with hash suffix)"

    local cm_name
    cm_name=$(kubectl get configmap -n "$ns" --no-headers 2>/dev/null | grep "app-config" | awk '{print $1}' | head -1)

    local data
    data=$(kubectl get configmap "$cm_name" -n "$ns" -o jsonpath='{.data}' 2>/dev/null)
    if [[ "$data" == *"DATABASE_URL"* ]] && [[ "$data" == *"localhost:5432"* ]]; then
        pass "ConfigMap has DATABASE_URL=localhost:5432"
    else
        fail_with_cmd "ConfigMap missing DATABASE_URL" \
            "kubectl get configmap $cm_name -n $ns -o yaml"
    fi

    if [[ "$data" == *"LOG_LEVEL"* ]] && [[ "$data" == *"info"* ]]; then
        pass "ConfigMap has LOG_LEVEL=info"
    else
        fail_with_cmd "ConfigMap missing LOG_LEVEL" \
            "kubectl get configmap $cm_name -n $ns -o yaml"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Secret from file ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Secret will have hash suffix
    local secrets
    secrets=$(kubectl get secret -n "$ns" --no-headers 2>/dev/null | grep "app-credentials" | wc -l)
    if [[ "$secrets" -eq 0 ]]; then
        fail_with_cmd "Secret app-credentials not found in namespace $ns" \
            "kubectl get secrets -n $ns"
        return
    fi

    pass "Secret app-credentials exists (with hash suffix)"

    local secret_name
    secret_name=$(kubectl get secret -n "$ns" --no-headers 2>/dev/null | grep "app-credentials" | awk '{print $1}' | head -1)

    local data
    data=$(kubectl get secret "$secret_name" -n "$ns" -o jsonpath='{.data}' 2>/dev/null)
    if [[ "$data" == *"credentials.txt"* ]]; then
        pass "Secret has credentials.txt data"
    else
        fail_with_cmd "Secret missing credentials.txt" \
            "kubectl get secret $secret_name -n $ns -o yaml"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: ConfigMap with disabled hash suffix ==="
    local cm_name="stable-config"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm_name" "$ns"; then
        fail_with_cmd "ConfigMap $cm_name not found in namespace $ns" \
            "kubectl get configmaps -n $ns"
        return
    fi

    pass "ConfigMap stable-config exists with exact name (no hash)"

    # Verify no hash suffix exists
    local cm_count
    cm_count=$(kubectl get configmap -n "$ns" --no-headers 2>/dev/null | grep -c "stable-config-" || true)
    if [[ "$cm_count" -eq 0 ]]; then
        pass "No hash suffix present"
    else
        fail "Found ConfigMaps with hash suffix (disableNameSuffixHash not working)"
    fi

    local data
    data=$(get_configmap_data "$cm_name" "$ns")
    if [[ "$data" == *"SETTING"* ]] && [[ "$data" == *"value"* ]]; then
        pass "ConfigMap has SETTING=value"
    else
        fail_with_cmd "ConfigMap missing SETTING" \
            "kubectl get configmap $cm_name -n $ns -o yaml"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multiple patches on same resource ==="
    local deployment="multipatched"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment" "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.replicas}'"
    fi

    local env_value
    env_value=$(get_env_value "$deployment" "$ns" "ENV")
    if [[ "$env_value" == "production" ]]; then
        pass "ENV=production"
    else
        fail_with_cmd "ENV=$env_value (expected production)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.template.spec.containers[0].env}'"
    fi

    local limits
    limits=$(get_resource_limits "$deployment" "$ns")
    if [[ "$limits" == *"256Mi"* ]]; then
        pass "Resource limits memory=256Mi"
    else
        fail_with_cmd "Resource limits: $limits (expected memory: 256Mi)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.template.spec.containers[0].resources.limits}'"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug complex patch chain ==="
    local deployment="complex"
    local ns="ex-5-2"
    local dir="$HOME/kustomize-patches/ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if [[ ! -f "$dir/kustomization.yaml" ]]; then
        fail "kustomization.yaml not found in $dir"
        return
    fi

    if ! kustomization_builds "$dir"; then
        fail_with_cmd "Kustomization does not build" \
            "kubectl kustomize $dir"
        return
    fi

    if ! deployment_exists "$deployment" "$ns"; then
        fail_with_cmd "Deployment $deployment not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local replicas
    replicas=$(get_replicas "$deployment" "$ns")
    if [[ "$replicas" == "2" ]]; then
        pass "Deployment has 2 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 2)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.replicas}'"
    fi

    local debug_value
    debug_value=$(get_env_value "$deployment" "$ns" "DEBUG")
    if [[ "$debug_value" == "true" ]]; then
        pass "DEBUG=true (second patch applied)"
    else
        fail_with_cmd "DEBUG=$debug_value (expected true)" \
            "kubectl get deployment $deployment -n $ns -o jsonpath='{.spec.template.spec.containers[0].env}'"
        info "Hint: Check that second patch target name matches deployment name"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Complete patch strategy ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local deployments
    deployments=$(kubectl get deployments -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$deployments" -eq 0 ]]; then
        fail_with_cmd "No deployments found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local deployment_name
    deployment_name=$(kubectl get deployments -n "$ns" --no-headers 2>/dev/null | awk '{print $1}' | head -1)

    local replicas
    replicas=$(get_replicas "$deployment_name" "$ns")
    if [[ "$replicas" == "3" ]]; then
        pass "Deployment has 3 replicas"
    else
        fail_with_cmd "Deployment has $replicas replicas (expected 3)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    local image
    image=$(get_image "$deployment_name" "$ns")
    if [[ "$image" == "nginx:1.26" ]]; then
        pass "Image is nginx:1.26"
    else
        fail_with_cmd "Image is $image (expected nginx:1.26)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'"
    fi

    local app_name
    app_name=$(get_env_value "$deployment_name" "$ns" "APP_NAME")
    if [[ "$app_name" == "myapp" ]]; then
        pass "APP_NAME=myapp"
    else
        fail_with_cmd "APP_NAME=$app_name (expected myapp)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].env}'"
    fi

    local version
    version=$(get_env_value "$deployment_name" "$ns" "VERSION")
    if [[ "$version" == "1.0" ]]; then
        pass "VERSION=1.0"
    else
        fail_with_cmd "VERSION=$version (expected 1.0)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].env}'"
    fi

    local requests
    requests=$(get_resource_requests "$deployment_name" "$ns")
    if [[ -n "$requests" ]]; then
        pass "Resource requests configured"
    else
        fail_with_cmd "Resource requests not configured" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}'"
    fi

    local configmaps
    configmaps=$(kubectl get configmap -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$configmaps" -gt 0 ]]; then
        pass "ConfigMap exists"
    else
        fail_with_cmd "No ConfigMap found in namespace $ns" \
            "kubectl get configmaps -n $ns"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Strategic Merge Patches"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: JSON 6902 and Images"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Patch Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Generators"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Complex Patching"
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
