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

# Helper: get deployment replicas
get_replicas() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null
}

# Helper: check if file exists
file_exists() {
    [[ -f "$1" ]]
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Render chart templates locally ==="

    # Check both files exist
    if file_exists "default-render.yaml"; then
        pass "default-render.yaml exists"
    else
        fail_with_cmd "default-render.yaml not found" \
            "helm template template-demo bitnami/nginx > default-render.yaml"
        return
    fi

    if file_exists "scaled-render.yaml"; then
        pass "scaled-render.yaml exists"
    else
        fail_with_cmd "scaled-render.yaml not found" \
            "helm template template-demo bitnami/nginx --set replicaCount=3 > scaled-render.yaml"
        return
    fi

    # Check default has replicas: 1
    if grep -q "replicas: 1" default-render.yaml; then
        pass "default-render.yaml has replicas: 1"
    else
        fail_with_cmd "default-render.yaml does not show replicas: 1" \
            "grep 'replicas:' default-render.yaml"
    fi

    # Check scaled has replicas: 3
    if grep -q "replicas: 3" scaled-render.yaml; then
        pass "scaled-render.yaml has replicas: 3"
    else
        fail_with_cmd "scaled-render.yaml does not show replicas: 3" \
            "grep 'replicas:' scaled-render.yaml"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Compare rendered output with different values ==="

    if file_exists "lb-service.yaml"; then
        pass "lb-service.yaml exists"
    else
        fail_with_cmd "lb-service.yaml not found" \
            "helm template lb-demo bitnami/nginx > lb-service.yaml"
        return
    fi

    if file_exists "clusterip-service.yaml"; then
        pass "clusterip-service.yaml exists"
    else
        fail_with_cmd "clusterip-service.yaml not found" \
            "helm template clusterip-demo bitnami/nginx --set service.type=ClusterIP > clusterip-service.yaml"
        return
    fi

    # Check LoadBalancer type
    if grep -q "type: LoadBalancer" lb-service.yaml; then
        pass "lb-service.yaml has type: LoadBalancer"
    else
        fail_with_cmd "lb-service.yaml does not show type: LoadBalancer" \
            "grep 'type:' lb-service.yaml"
    fi

    # Check ClusterIP type
    if grep -q "type: ClusterIP" clusterip-service.yaml; then
        pass "clusterip-service.yaml has type: ClusterIP"
    else
        fail_with_cmd "clusterip-service.yaml does not show type: ClusterIP" \
            "grep 'type:' clusterip-service.yaml"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Validate rendered manifests ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Perform validation
    local validation_result
    validation_result=$(helm template validated-app bitnami/nginx \
        --namespace "$ns" \
        --set service.type=ClusterIP 2>/dev/null | \
        kubectl apply --dry-run=client -f - 2>&1 | grep -c "created\|configured" || echo "0")

    if [[ "$validation_result" -gt 0 ]]; then
        pass "Validation passes (found $validation_result resource(s) would be created/configured)"
    else
        fail_with_cmd "Validation did not show expected output" \
            "helm template validated-app bitnami/nginx --namespace $ns --set service.type=ClusterIP | kubectl apply --dry-run=client -f -"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Use --debug to get verbose output ==="
    local release="debug-app"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found in namespace $ns" \
            "helm install $release bitnami/nginx -n $ns --debug"
        return
    fi

    pass "Release $release is installed in namespace $ns"

    # Verify release can be listed
    if helm list -n "$ns" | grep -q "$release"; then
        pass "Release appears in helm list"
    else
        fail "Release not in helm list output"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Use --dry-run to test installation ==="
    local release="dryrun-app"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check release should NOT exist
    if release_exists "$release" "$ns"; then
        fail "Release $release exists but should not (--dry-run should not create release)"
    else
        pass "Release $release does not exist (correct)"
    fi

    # Check no pods exist
    local pod_count
    pod_count=$(kubectl get pods -n "$ns" 2>/dev/null | grep -c "^" || echo "0")
    if [[ "$pod_count" -le 1 ]]; then
        pass "No pods in namespace $ns (correct for dry-run)"
    else
        fail_with_cmd "Found $pod_count pods, expected 0" \
            "kubectl get pods -n $ns"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Diagnose values error using debug output ==="
    local release="good-redis"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found in namespace $ns" \
            "helm install $release bitnami/redis -n $ns --set architecture=standalone --set auth.enabled=false"
        return
    fi

    pass "Release $release is installed"

    # Check pods are running
    sleep 5
    local running_pods
    running_pods=$(kubectl get pods -n "$ns" 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$running_pods" -gt 0 ]]; then
        pass "Found $running_pods running pod(s)"
    else
        fail_with_cmd "No running pods found" \
            "kubectl get pods -n $ns"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug missing required values ==="
    local release="working-db"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found in namespace $ns" \
            "helm install $release bitnami/postgresql -n $ns --set auth.postgresPassword=mysecret"
        return
    fi

    pass "Release $release is installed"

    # Check that password was set
    if helm get values "$release" -n "$ns" | grep -qi "password"; then
        pass "Password was configured in values"
    else
        fail_with_cmd "Password not found in values" \
            "helm get values $release -n $ns"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug pods not running ==="
    local release="mystery-app"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail "Release $release not found in namespace $ns"
        return
    fi

    # Wait for pods to stabilize
    sleep 10

    # Check pods are running
    if kubectl get pods -n "$ns" | grep -q "Running"; then
        pass "Pods are running (issue fixed)"
    else
        fail_with_cmd "Pods are not running" \
            "kubectl get pods -n $ns; kubectl describe pod -n $ns -l app.kubernetes.io/instance=$release"
    fi

    # Check image is valid (not the nonexistent tag)
    local image
    image=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.template.spec.containers[0].image}' 2>/dev/null)
    if [[ "$image" != *"nonexistent"* ]] && [[ -n "$image" ]]; then
        pass "Image is valid: $image"
    else
        fail_with_cmd "Image is invalid: $image" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].image}'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug dependency-related issues ==="
    local release="blog-app"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found in namespace $ns" \
            "helm install $release bitnami/wordpress -n $ns --set memcached.enabled=false --set mariadb.auth.rootPassword=test"
        return
    fi

    pass "Release $release is installed"

    # Wait for pods
    sleep 10

    # Should have mariadb
    if kubectl get pods -n "$ns" | grep -q "mariadb"; then
        pass "MariaDB pods exist"
    else
        fail_with_cmd "MariaDB pods not found" \
            "kubectl get pods -n $ns"
    fi

    # Should NOT have memcached
    local memcached_count
    memcached_count=$(kubectl get pods -n "$ns" 2>/dev/null | grep -c "memcached" || echo "0")
    if [[ "$memcached_count" -eq 0 ]]; then
        pass "No Memcached pods (memcached.enabled=false)"
    else
        fail_with_cmd "Found $memcached_count Memcached pod(s), expected 0" \
            "kubectl get pods -n $ns | grep memcached"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Understand chart dependencies ==="

    # Check can view dependencies
    if helm show chart bitnami/wordpress 2>/dev/null | grep -q "dependencies"; then
        pass "Can view dependencies in bitnami/wordpress chart"
    else
        fail_with_cmd "Cannot view dependencies" \
            "helm show chart bitnami/wordpress | grep -A30 dependencies"
    fi

    # Render with memcached and count resources
    local with_mem
    with_mem=$(helm template wp bitnami/wordpress \
        --set memcached.enabled=true \
        --set mariadb.auth.rootPassword=test \
        --set wordpressPassword=test 2>/dev/null | grep -c "memcached" || echo "0")

    local without_mem
    without_mem=$(helm template wp bitnami/wordpress \
        --set memcached.enabled=false \
        --set mariadb.auth.rootPassword=test \
        --set wordpressPassword=test 2>/dev/null | grep -c "memcached" || echo "0")

    if [[ "$with_mem" -gt "$without_mem" ]]; then
        pass "Rendered output differs with/without memcached (with: $with_mem references, without: $without_mem)"
    else
        fail "Rendered output does not show expected difference"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Manage chart dependencies ==="

    # Check chart was downloaded
    if [[ -f "/tmp/ex-4-2/wordpress/Chart.yaml" ]]; then
        pass "wordpress chart downloaded and extracted"
    else
        fail_with_cmd "wordpress/Chart.yaml not found at expected location" \
            "cd /tmp/ex-4-2; helm pull bitnami/wordpress --untar; ls -la wordpress/"
        return
    fi

    # Check dependencies directory exists
    if [[ -d "/tmp/ex-4-2/wordpress/charts" ]] && [[ -n "$(ls -A /tmp/ex-4-2/wordpress/charts 2>/dev/null)" ]]; then
        pass "charts/ directory exists with dependency charts"
    else
        fail_with_cmd "charts/ directory empty or missing" \
            "cd /tmp/ex-4-2/wordpress; helm dependency update .; ls -la charts/"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Handle secrets appropriately ==="
    local release="secure-cache"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found in namespace $ns" \
            "helm install $release bitnami/redis -n $ns --set architecture=standalone --set auth.password=mysecret"
        return
    fi

    pass "Release $release is installed"

    # Check password was set in values
    if helm get values "$release" -n "$ns" | grep -q "password"; then
        pass "Password configured in values"
    else
        fail_with_cmd "Password not found in values" \
            "helm get values $release -n $ns"
    fi

    # Check secret exists and is base64 encoded
    if kubectl get secret -n "$ns" -o yaml 2>/dev/null | grep -q "redis-password"; then
        pass "Secret contains redis-password (base64 encoded)"
    else
        fail_with_cmd "Secret not properly configured" \
            "kubectl get secret -n $ns -o yaml"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Complex chart installation with multiple requirements ==="
    local release="production-web"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found in namespace $ns" \
            "helm install $release bitnami/nginx -n $ns --set replicaCount=3 --set service.type=ClusterIP --set resources.requests.memory=128Mi"
        return
    fi

    pass "Release $release is deployed"

    # Wait for deployment
    sleep 5

    # Check replicas
    local replicas
    replicas=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null)
    if [[ "$replicas" == "3" ]]; then
        pass "Replicas set to 3"
    else
        fail_with_cmd "Replicas is $replicas (expected 3)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi

    # Check resources configured
    local resources
    resources=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}' 2>/dev/null)
    if [[ -n "$resources" ]] && [[ "$resources" != "{}" ]]; then
        pass "Resources configured: $resources"
    else
        fail_with_cmd "Resources not configured" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}'"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Audit chart for best practices ==="
    local release="audited-cache"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found in namespace $ns" \
            "helm install $release bitnami/redis -n $ns --set architecture=standalone --set auth.enabled=false"
        return
    fi

    pass "Release $release is deployed"

    # Wait for deployment
    sleep 5

    # Check for standard labels
    if kubectl get deployment -n "$ns" -o jsonpath='{.items[0].metadata.labels}' 2>/dev/null | grep -q "app.kubernetes.io"; then
        pass "Deployment has standard app.kubernetes.io labels"
    else
        fail_with_cmd "Standard labels not found" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].metadata.labels}'"
    fi

    # Check for resource requests
    local requests
    requests=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.template.spec.containers[0].resources.requests}' 2>/dev/null)
    if [[ -n "$requests" ]] && [[ "$requests" != "{}" ]] && [[ "$requests" != "null" ]]; then
        pass "Resource requests configured: $requests"
    else
        fail_with_cmd "Resource requests not configured" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.template.spec.containers[0].resources}'"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Comprehensive deployment documentation ==="
    local release="documented-web"
    local ns="ex-5-3"

    # Check values file exists
    if file_exists "production-nginx.yaml"; then
        pass "production-nginx.yaml exists"
    else
        fail_with_cmd "production-nginx.yaml not found" \
            "cat > production-nginx.yaml <<EOF\n# Production configuration\nreplicaCount: 3\nservice:\n  type: ClusterIP\nEOF"
        return
    fi

    # Check file has comments
    if grep -q "#" production-nginx.yaml; then
        pass "production-nginx.yaml contains documentation comments"
    else
        fail_with_cmd "production-nginx.yaml missing documentation comments" \
            "cat production-nginx.yaml"
    fi

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! release_exists "$release" "$ns"; then
        fail_with_cmd "Release $release not found in namespace $ns" \
            "helm install $release bitnami/nginx -n $ns -f production-nginx.yaml --atomic"
        return
    fi

    pass "Release $release is deployed"

    # Check configuration was applied
    local replicas
    replicas=$(kubectl get deployment -n "$ns" -o jsonpath='{.items[0].spec.replicas}' 2>/dev/null)
    if [[ "$replicas" == "3" ]]; then
        pass "Configuration applied: replicas=$replicas"
    else
        fail_with_cmd "Configuration not applied correctly (replicas=$replicas)" \
            "kubectl get deployment -n $ns -o jsonpath='{.items[0].spec.replicas}'"
    fi
}

################################################################################
# Level aggregation functions
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Template Rendering"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Debugging"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Complex Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Advanced Features"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Production Scenarios"
    echo "###############################################"
    verify_5_1
    verify_5_2
    verify_5_3
}

################################################################################
# Main logic
################################################################################

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
