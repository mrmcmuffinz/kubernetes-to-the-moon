#!/usr/bin/env bash
#
# verify.sh - Automated verification for ingress-and-gateway-api-homework.md
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

# Helper: check if ingress exists
ingress_exists() {
    local ingress=$1
    local ns=$2
    kubectl get ingress "$ingress" -n "$ns" &>/dev/null
}

# Helper: get IngressClass from Ingress
get_ingress_class() {
    local ingress=$1
    local ns=$2
    kubectl get ingress "$ingress" -n "$ns" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null
}

# Helper: check if Ingress has an ADDRESS
ingress_has_address() {
    local ingress=$1
    local ns=$2
    local address
    address=$(kubectl get ingress "$ingress" -n "$ns" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    [[ -n "$address" ]]
}

# Helper: get number of rules in Ingress
get_rules_count() {
    local ingress=$1
    local ns=$2
    kubectl get ingress "$ingress" -n "$ns" -o jsonpath='{.spec.rules}' 2>/dev/null | grep -o '"host":' | wc -l
}

# Helper: get defaultBackend service name
get_default_backend() {
    local ingress=$1
    local ns=$2
    kubectl get ingress "$ingress" -n "$ns" -o jsonpath='{.spec.defaultBackend.service.name}' 2>/dev/null
}

# Helper: check if Service exists
service_exists() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" &>/dev/null
}

# Helper: check if Service has endpoints
service_has_endpoints() {
    local svc=$1
    local ns=$2
    local endpoints
    endpoints=$(kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[*].addresses}' 2>/dev/null)
    [[ -n "$endpoints" ]]
}

# Helper: test HTTP request with Host header
test_http() {
    local host=$1
    local path=$2
    local expected=$3
    local result
    result=$(curl -s -H "Host: $host" "http://localhost$path" 2>/dev/null || echo "")
    [[ "$result" == *"$expected"* ]]
}

# Helper: test HTTP status code
test_http_status() {
    local host=$1
    local path=$2
    local expected_status=$3
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: $host" "http://localhost$path" 2>/dev/null)
    [[ "$status" == "$expected_status" ]]
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic Ingress creation ==="
    local ingress="hello-ingress"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    local class
    class=$(get_ingress_class "$ingress" "$ns")
    if [[ "$class" == "traefik" ]]; then
        pass "IngressClass is traefik"
    else
        fail_with_cmd "IngressClass is '$class' (expected traefik)" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.ingressClassName}'"
    fi

    sleep 3

    if test_http "hello.example.test" "/" "hello-world"; then
        pass "HTTP request returns hello-world"
    else
        fail_with_cmd "HTTP request failed or wrong response" \
            "curl -s -H 'Host: hello.example.test' http://localhost/"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Two path-based rules ==="
    local ingress="paths-ingress"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    if test_http "paths.example.test" "/a" "a-response"; then
        pass "Path /a returns a-response"
    else
        fail_with_cmd "Path /a failed or wrong response" \
            "curl -s -H 'Host: paths.example.test' http://localhost/a"
    fi

    if test_http "paths.example.test" "/b" "b-response"; then
        pass "Path /b returns b-response"
    else
        fail_with_cmd "Path /b failed or wrong response" \
            "curl -s -H 'Host: paths.example.test' http://localhost/b"
    fi

    if test_http_status "paths.example.test" "/c" "404"; then
        pass "Path /c returns 404"
    else
        fail_with_cmd "Path /c should return 404" \
            "curl -sI -H 'Host: paths.example.test' http://localhost/c"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Ingress with defaultBackend ==="
    local ingress="catchall"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    local backend
    backend=$(get_default_backend "$ingress" "$ns")
    if [[ "$backend" == "fallback" ]]; then
        pass "defaultBackend points to fallback service"
    else
        fail_with_cmd "defaultBackend is '$backend' (expected fallback)" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.defaultBackend.service.name}'"
    fi

    sleep 3

    if test_http "catchall.example.test" "/anywhere" "fallback-served"; then
        pass "Path /anywhere returns fallback-served"
    else
        fail_with_cmd "defaultBackend not serving correctly" \
            "curl -s -H 'Host: catchall.example.test' http://localhost/anywhere"
    fi

    if test_http "catchall.example.test" "/" "fallback-served"; then
        pass "Path / returns fallback-served"
    else
        fail_with_cmd "defaultBackend not serving root path" \
            "curl -s -H 'Host: catchall.example.test' http://localhost/"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Exact path type ==="
    local ingress="exact-ingress"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    if test_http "exact.example.test" "/api" "api-v1"; then
        pass "Exact path /api returns api-v1"
    else
        fail_with_cmd "Exact path /api failed" \
            "curl -s -H 'Host: exact.example.test' http://localhost/api"
    fi

    if test_http_status "exact.example.test" "/api/extra" "404"; then
        pass "Path /api/extra returns 404 (Exact match only)"
    else
        fail_with_cmd "Path /api/extra should return 404 with Exact pathType" \
            "curl -sI -H 'Host: exact.example.test' http://localhost/api/extra"
    fi

    if test_http_status "exact.example.test" "/api/" "404"; then
        pass "Path /api/ returns 404 (Exact match only)"
    else
        fail_with_cmd "Path /api/ should return 404 with Exact pathType" \
            "curl -sI -H 'Host: exact.example.test' http://localhost/api/"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Multiple hosts and paths ==="
    local ingress="multi"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    if test_http "foo.example.test" "/" "foo-app"; then
        pass "Host foo.example.test returns foo-app"
    else
        fail_with_cmd "Host foo.example.test failed" \
            "curl -s -H 'Host: foo.example.test' http://localhost/"
    fi

    if test_http "bar.example.test" "/" "bar-app"; then
        pass "Host bar.example.test returns bar-app"
    else
        fail_with_cmd "Host bar.example.test failed" \
            "curl -s -H 'Host: bar.example.test' http://localhost/"
    fi

    if test_http "shared.example.test" "/foo" "foo-app"; then
        pass "Host shared.example.test path /foo returns foo-app"
    else
        fail_with_cmd "Host shared.example.test path /foo failed" \
            "curl -s -H 'Host: shared.example.test' http://localhost/foo"
    fi

    if test_http "shared.example.test" "/bar" "bar-app"; then
        pass "Host shared.example.test path /bar returns bar-app"
    else
        fail_with_cmd "Host shared.example.test path /bar failed" \
            "curl -s -H 'Host: shared.example.test' http://localhost/bar"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Rules with defaultBackend ==="
    local ingress="with-fallback"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    local backend
    backend=$(get_default_backend "$ingress" "$ns")
    if [[ "$backend" == "default" ]]; then
        pass "defaultBackend points to default service"
    else
        fail_with_cmd "defaultBackend is '$backend' (expected default)" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.defaultBackend.service.name}'"
    fi

    sleep 3

    if test_http "app.example.test" "/" "app-alpha"; then
        pass "Host app.example.test returns app-alpha"
    else
        fail_with_cmd "Host app.example.test failed" \
            "curl -s -H 'Host: app.example.test' http://localhost/"
    fi

    if test_http "other.example.test" "/" "default-fallback"; then
        pass "Unmatched host returns default-fallback"
    else
        fail_with_cmd "defaultBackend not serving unmatched hosts" \
            "curl -s -H 'Host: other.example.test' http://localhost/"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug wrong IngressClass ==="
    local ingress="stuck"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 5

    local class
    class=$(get_ingress_class "$ingress" "$ns")
    if [[ "$class" == "traefik" ]]; then
        pass "IngressClass fixed to traefik"
    else
        fail_with_cmd "IngressClass is '$class' (should be traefik)" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.ingressClassName}'"
        return
    fi

    if test_http "stuck.example.test" "/" "hi-reply"; then
        pass "HTTP request returns hi-reply"
    else
        fail_with_cmd "HTTP request failed after IngressClass fix" \
            "curl -s -H 'Host: stuck.example.test' http://localhost/"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug wrong Service name ==="
    local ingress="ifu"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    if test_http "frontend.example.test" "/" "frontend-ok"; then
        pass "HTTP request returns frontend-ok (Service name fixed)"
    else
        fail_with_cmd "HTTP request failed - check backend Service name" \
            "kubectl describe ingress -n $ns $ingress | grep -A5 Backend"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug path type mismatch ==="
    local ingress="path-bad"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    if test_http "api.example.test" "/api/v1" "api-v1-endpoint"; then
        pass "Path /api/v1 returns api-v1-endpoint (pathType fixed)"
    else
        fail_with_cmd "Path /api/v1 failed - check pathType" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.rules[0].http.paths[0].pathType}'"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Multiple paths with defaultBackend ==="
    local ingress="four-one"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    local backend
    backend=$(get_default_backend "$ingress" "$ns")
    if [[ "$backend" == "svc-default" ]]; then
        pass "defaultBackend points to svc-default"
    else
        fail_with_cmd "defaultBackend is '$backend' (expected svc-default)" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.defaultBackend.service.name}'"
    fi

    sleep 3

    if test_http "app.example.test" "/x" "x-reply"; then
        pass "Path /x returns x-reply"
    else
        fail_with_cmd "Path /x failed" \
            "curl -s -H 'Host: app.example.test' http://localhost/x"
    fi

    if test_http "app.example.test" "/y" "y-reply"; then
        pass "Path /y returns y-reply"
    else
        fail_with_cmd "Path /y failed" \
            "curl -s -H 'Host: app.example.test' http://localhost/y"
    fi

    if test_http "app.example.test" "/z" "default-reply"; then
        pass "Unmatched path /z returns default-reply"
    else
        fail_with_cmd "defaultBackend not serving unmatched paths" \
            "curl -s -H 'Host: app.example.test' http://localhost/z"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Multiple IngressClasses ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    sleep 5

    local traefik_count
    traefik_count=$(kubectl get ingress -n "$ns" -o jsonpath='{.items[?(@.spec.ingressClassName=="traefik")].metadata.name}' 2>/dev/null | wc -w)
    if [[ "$traefik_count" -ge 1 ]]; then
        pass "At least one Ingress with ingressClassName: traefik exists"
    else
        fail_with_cmd "No Ingress with traefik IngressClass found" \
            "kubectl get ingress -n $ns -o jsonpath='{.items[*].spec.ingressClassName}'"
    fi

    local future_count
    future_count=$(kubectl get ingress -n "$ns" -o jsonpath='{.items[?(@.spec.ingressClassName=="future-controller")].metadata.name}' 2>/dev/null | wc -w)
    if [[ "$future_count" -ge 1 ]]; then
        pass "At least one Ingress with ingressClassName: future-controller exists"
    else
        fail "No Ingress with future-controller IngressClass found"
    fi

    if test_http "two-classes.example.test" "/" "present-reply"; then
        pass "HTTP request returns present-reply (traefik Ingress working)"
    else
        fail_with_cmd "HTTP request failed" \
            "curl -s -H 'Host: two-classes.example.test' http://localhost/"
    fi

    local future_address
    future_address=$(kubectl get ingress -n "$ns" -o jsonpath='{.items[?(@.spec.ingressClassName=="future-controller")].status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [[ -z "$future_address" ]]; then
        pass "future-controller Ingress has no ADDRESS (expected)"
    else
        fail "future-controller Ingress should not have ADDRESS (no controller watching it)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Versioned API paths ==="
    local ingress="versioned"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    if test_http "versioned.example.test" "/api/v1" "api-v1-response"; then
        pass "Path /api/v1 returns api-v1-response"
    else
        fail_with_cmd "Path /api/v1 failed" \
            "curl -s -H 'Host: versioned.example.test' http://localhost/api/v1"
    fi

    if test_http "versioned.example.test" "/api/v2" "api-v2-response"; then
        pass "Path /api/v2 returns api-v2-response"
    else
        fail_with_cmd "Path /api/v2 failed" \
            "curl -s -H 'Host: versioned.example.test' http://localhost/api/v2"
    fi

    if test_http_status "versioned.example.test" "/api/v3" "404"; then
        pass "Path /api/v3 returns 404"
    else
        fail_with_cmd "Path /api/v3 should return 404" \
            "curl -sI -H 'Host: versioned.example.test' http://localhost/api/v3"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Complex multi-host routing ==="
    local ingress="webapp"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    local backend
    backend=$(get_default_backend "$ingress" "$ns")
    if [[ "$backend" == "marketing" ]]; then
        pass "defaultBackend points to marketing"
    else
        fail_with_cmd "defaultBackend is '$backend' (expected marketing)" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.defaultBackend.service.name}'"
    fi

    sleep 3

    if test_http "www.webapp.example.test" "/" "marketing-response"; then
        pass "www.webapp.example.test / returns marketing-response"
    else
        fail_with_cmd "www.webapp.example.test / failed" \
            "curl -s -H 'Host: www.webapp.example.test' http://localhost/"
    fi

    if test_http "www.webapp.example.test" "/static" "static-response"; then
        pass "www.webapp.example.test /static returns static-response"
    else
        fail_with_cmd "www.webapp.example.test /static failed" \
            "curl -s -H 'Host: www.webapp.example.test' http://localhost/static"
    fi

    if test_http "api.webapp.example.test" "/" "api-response"; then
        pass "api.webapp.example.test / returns api-response"
    else
        fail_with_cmd "api.webapp.example.test / failed" \
            "curl -s -H 'Host: api.webapp.example.test' http://localhost/"
    fi

    if test_http "admin.webapp.example.test" "/" "admin-response"; then
        pass "admin.webapp.example.test / returns admin-response"
    else
        fail_with_cmd "admin.webapp.example.test / failed" \
            "curl -s -H 'Host: admin.webapp.example.test' http://localhost/"
    fi

    if test_http "health.webapp.example.test" "/healthz" "health-response"; then
        pass "health.webapp.example.test /healthz returns health-response"
    else
        fail_with_cmd "health.webapp.example.test /healthz failed" \
            "curl -s -H 'Host: health.webapp.example.test' http://localhost/healthz"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug compound failure ==="
    local ingress="broken"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    local class
    class=$(get_ingress_class "$ingress" "$ns")
    if [[ "$class" == "traefik" ]]; then
        pass "IngressClass fixed to traefik"
    else
        fail_with_cmd "IngressClass is '$class' (should be traefik)" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.ingressClassName}'"
    fi

    if test_http "cascading.example.test" "/v1/status" "healthy-v1"; then
        pass "HTTP request returns healthy-v1 (all issues fixed)"
    else
        fail_with_cmd "HTTP request failed - check IngressClass and backend Service name" \
            "kubectl describe ingress -n $ns $ingress"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Separate Ingress resources ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    sleep 3

    local ingress_count
    ingress_count=$(kubectl get ingress -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$ingress_count" -eq 3 ]]; then
        pass "Three Ingress resources exist"
    else
        fail_with_cmd "Expected 3 Ingress resources, found $ingress_count" \
            "kubectl get ingress -n $ns"
    fi

    if test_http "company.example.test" "/healthz" "health-v1"; then
        pass "Path /healthz returns health-v1"
    else
        fail_with_cmd "Path /healthz failed" \
            "curl -s -H 'Host: company.example.test' http://localhost/healthz"
    fi

    if test_http "company.example.test" "/api" "api-v1"; then
        pass "Path /api returns api-v1"
    else
        fail_with_cmd "Path /api failed" \
            "curl -s -H 'Host: company.example.test' http://localhost/api"
    fi

    if test_http "company.example.test" "/" "ui-v1"; then
        pass "Path / returns ui-v1"
    else
        fail_with_cmd "Path / failed" \
            "curl -s -H 'Host: company.example.test' http://localhost/"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic Ingress Creation"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Path and Host Routing"
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
    echo "# Level 4: Configuration and Design"
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
