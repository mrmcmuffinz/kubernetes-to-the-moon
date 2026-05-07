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

# Helper: check if gateway exists
gateway_exists() {
    local gw=$1; local ns=$2
    kubectl get gateway "$gw" -n "$ns" &>/dev/null
}

# Helper: check if httproute exists
httproute_exists() {
    local route=$1; local ns=$2
    kubectl get httproute "$route" -n "$ns" &>/dev/null
}

# Helper: get gateway programmed status
get_gateway_programmed() {
    local gw=$1; local ns=$2
    kubectl get gateway "$gw" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null
}

# Helper: get httproute accepted status
get_httproute_accepted() {
    local route=$1; local ns=$2
    kubectl get httproute "$route" -n "$ns" -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}' 2>/dev/null
}

# Helper: get gatewayclass controller name
get_gatewayclass_controller() {
    local gc=$1
    kubectl get gatewayclass "$gc" -o jsonpath='{.spec.controllerName}' 2>/dev/null
}

# Helper: get nginx-gateway service name
get_ngf_service() {
    kubectl get svc -n nginx-gateway -l app.kubernetes.io/instance=ngf -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Helper: get envoy-gateway service for namespace
get_eg_service() {
    local ns=$1
    kubectl get svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-namespace="$ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Helper: deployment is ready
deployment_ready() {
    local dep=$1; local ns=$2
    local ready
    ready=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    [[ -n "$ready" && "$ready" -gt 0 ]]
}

# Helper: curl with Host header
curl_host() {
    local host=$1; local port=$2; local path=${3:-/}; local extra_args=${4:-}
    curl -s -H "Host: $host" $extra_args "http://localhost:$port$path"
}

# Helper: curl with Host header (headers only)
curl_host_I() {
    local host=$1; local port=$2; local path=${3:-/}; local extra_args=${4:-}
    curl -sI -H "Host: $host" $extra_args "http://localhost:$port$path"
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic NGF HTTPRoute ==="
    local ns="ex-1-1"
    local route="hi-route"
    local gw="gw"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! gateway_exists "$gw" "$ns"; then
        fail "Gateway $gw not found in namespace $ns"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local accepted
    accepted=$(get_httproute_accepted "$route" "$ns")
    if [[ "$accepted" == "True" ]]; then
        pass "HTTPRoute $route is Accepted"
    else
        fail_with_cmd "HTTPRoute $route Accepted=$accepted (expected True)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 10 'status:'"
        return
    fi

    # Port-forward and test
    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9010:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response
    response=$(curl_host "hi.example.test" 9010)
    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response" == *"hi-one-one"* ]]; then
        pass "Response contains 'hi-one-one'"
    else
        fail_with_cmd "Response was: $response (expected hi-one-one)" \
            "kubectl port-forward -n nginx-gateway svc/$svc 9010:80 & sleep 2; curl -H 'Host: hi.example.test' http://localhost:9010/"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: NGF GatewayClass controller ==="
    local gc="nginx"

    local controller
    controller=$(get_gatewayclass_controller "$gc")
    if [[ "$controller" == "gateway.nginx.org/nginx-gateway-controller" ]]; then
        pass "GatewayClass nginx has correct controllerName"
    else
        fail_with_cmd "GatewayClass nginx controllerName=$controller (expected gateway.nginx.org/nginx-gateway-controller)" \
            "kubectl get gatewayclass nginx -o jsonpath='{.spec.controllerName}'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Dual Gateway routing ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check both HTTPRoutes exist
    if ! httproute_exists "r-envoy" "$ns"; then
        fail "HTTPRoute r-envoy not found in namespace $ns"
        return
    fi

    if ! httproute_exists "r-nginx" "$ns"; then
        fail "HTTPRoute r-nginx not found in namespace $ns"
        return
    fi

    # Both should be Accepted
    local accepted_envoy
    accepted_envoy=$(get_httproute_accepted "r-envoy" "$ns")
    if [[ "$accepted_envoy" == "True" ]]; then
        pass "HTTPRoute r-envoy is Accepted"
    else
        fail_with_cmd "HTTPRoute r-envoy Accepted=$accepted_envoy (expected True)" \
            "kubectl get httproute -n $ns r-envoy -o yaml | grep -A 10 'status:'"
    fi

    local accepted_nginx
    accepted_nginx=$(get_httproute_accepted "r-nginx" "$ns")
    if [[ "$accepted_nginx" == "True" ]]; then
        pass "HTTPRoute r-nginx is Accepted"
    else
        fail_with_cmd "HTTPRoute r-nginx Accepted=$accepted_nginx (expected True)" \
            "kubectl get httproute -n $ns r-nginx -o yaml | grep -A 10 'status:'"
    fi

    # Test both endpoints
    local envoy_svc nginx_svc
    envoy_svc=$(get_eg_service "$ns")
    nginx_svc=$(get_ngf_service)

    if [[ -z "$envoy_svc" ]] || [[ -z "$nginx_svc" ]]; then
        fail "Could not find one or both gateway services"
        return
    fi

    kubectl port-forward -n envoy-gateway-system "svc/$envoy_svc" 9020:80 &>/dev/null &
    local pf_pid1=$!
    kubectl port-forward -n nginx-gateway "svc/$nginx_svc" 9021:80 &>/dev/null &
    local pf_pid2=$!
    sleep 3

    local response_envoy response_nginx
    response_envoy=$(curl_host "same.example.test" 9020)
    response_nginx=$(curl_host "same.example.test" 9021)

    kill $pf_pid1 $pf_pid2 2>/dev/null || true
    wait $pf_pid1 $pf_pid2 2>/dev/null || true

    if [[ "$response_envoy" == *"parity"* ]]; then
        pass "Envoy Gateway returns 'parity'"
    else
        fail "Envoy Gateway response was: $response_envoy (expected parity)"
    fi

    if [[ "$response_nginx" == *"parity"* ]]; then
        pass "NGINX Gateway returns 'parity'"
    else
        fail "NGINX Gateway response was: $response_nginx (expected parity)"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Header-based routing ==="
    local ns="ex-2-1"
    local route="tenant-routing"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9030:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response_red response_blue response_none
    response_red=$(curl_host "tenant.example.test" 9030 "/" "-H 'X-Tenant: red'")
    response_blue=$(curl_host "tenant.example.test" 9030 "/" "-H 'X-Tenant: blue'")
    response_none=$(curl_host_I "tenant.example.test" 9030 "/" "" | head -n1)

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response_red" == *"red"* ]]; then
        pass "X-Tenant: red routes to red-app"
    else
        fail_with_cmd "X-Tenant: red response was: $response_red (expected red)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 20 'matches:'"
    fi

    if [[ "$response_blue" == *"blue"* ]]; then
        pass "X-Tenant: blue routes to blue-app"
    else
        fail_with_cmd "X-Tenant: blue response was: $response_blue (expected blue)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 20 'matches:'"
    fi

    if [[ "$response_none" == *"404"* ]]; then
        pass "No X-Tenant header returns 404"
    else
        fail "No X-Tenant header should return 404, got: $response_none"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Query parameter routing ==="
    local ns="ex-2-1"
    local route="query-routing"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9031:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response_prod response_staging
    response_prod=$(curl_host "query.example.test" 9031 "/?env=prod")
    response_staging=$(curl_host "query.example.test" 9031 "/?env=staging")

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response_prod" == *"red"* ]]; then
        pass "env=prod routes to red-app"
    else
        fail "env=prod response was: $response_prod (expected red)"
    fi

    if [[ "$response_staging" == *"blue"* ]]; then
        pass "env=staging routes to blue-app"
    else
        fail "env=staging response was: $response_staging (expected blue)"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Combined path + method + header match ==="
    local ns="ex-2-1"
    local route="combined"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9032:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response_all response_noheader response_get
    response_all=$(curl_host "combined.example.test" 9032 "/api" "-X POST -H 'X-API-Key: admin'")
    response_noheader=$(curl_host_I "combined.example.test" 9032 "/api" "-X POST" | head -n1)
    response_get=$(curl_host_I "combined.example.test" 9032 "/api" "-X GET -H 'X-API-Key: admin'" | head -n1)

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response_all" == *"red"* ]]; then
        pass "All three conditions match -> red-app"
    else
        fail "All conditions match response was: $response_all (expected red)"
    fi

    if [[ "$response_noheader" == *"404"* ]]; then
        pass "Missing header -> 404"
    else
        fail "Missing header should return 404, got: $response_noheader"
    fi

    if [[ "$response_get" == *"404"* ]]; then
        pass "Wrong method -> 404"
    else
        fail "Wrong method should return 404, got: $response_get"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Filter order bug ==="
    local ns="ex-3-1"
    local route="order-bug"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9041:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response
    response=$(curl_host "order.example.test" 9041 "/old/items")

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response" == *"app-got: /new/items"* ]]; then
        pass "URLRewrite applied, backend sees /new/items"
    else
        fail_with_cmd "Response was: $response (expected app-got: /new/items)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 15 'filters:'"
        info "Hint: RequestRedirect is terminal; remove it to let URLRewrite run"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Header case-sensitivity bug ==="
    local ns="ex-3-2"
    local route="case-sensitive"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9042:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response
    response=$(curl_host "case.example.test" 9042 "/" "-H 'X-Env: production'")

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response" == *"case-app"* ]]; then
        pass "Header match fixed (accepts lowercase 'production')"
    else
        fail_with_cmd "Response was: $response (expected case-app)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 10 'headers:'"
        info "Hint: Header values are case-sensitive; ensure match value is 'production' not 'Production'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Traffic split weights bug ==="
    local ns="ex-3-3"
    local route="bad-split"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9043:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local v1=0 v2=0
    for i in $(seq 1 50); do
        local r
        r=$(curl_host "split.example.test" 9043)
        if [[ "$r" == *"v1"* ]]; then
            v1=$((v1 + 1))
        elif [[ "$r" == *"v2"* ]]; then
            v2=$((v2 + 1))
        fi
    done

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    # Expecting 70/30 split, so v1 should be significantly higher than v2
    if [[ $v1 -gt $v2 ]] && [[ $v1 -gt 25 ]]; then
        pass "Traffic split fixed: v1=$v1, v2=$v2 (v1 dominates as expected)"
    else
        fail_with_cmd "Traffic split v1=$v1, v2=$v2 (expected v1 to dominate with 70% weight)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 10 'backendRefs:'"
        info "Hint: Weights should be v1-svc: 70, v2-svc: 30"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: RequestHeaderModifier add ==="
    local ns="ex-4-1"
    local route="add-hdr"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9044:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response
    response=$(curl_host "header.example.test" 9044)

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response" == *"x-source=gateway-filter"* ]]; then
        pass "RequestHeaderModifier adds X-Source header"
    else
        fail_with_cmd "Response was: $response (expected x-source=gateway-filter)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 10 'filters:'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: RequestRedirect HTTP->HTTPS ==="
    local ns="ex-4-2"
    local route="to-https"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9045:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local headers
    headers=$(curl_host_I "insecure.example.test" 9045 "/anywhere")

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if echo "$headers" | grep -q "301"; then
        pass "Returns 301 redirect"
    else
        fail_with_cmd "Expected 301 status, got: $(echo "$headers" | head -n1)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 10 'requestRedirect:'"
    fi

    if echo "$headers" | grep -qi "Location:.*https://secure.example.test/anywhere"; then
        pass "Location header points to https://secure.example.test/anywhere"
    else
        fail_with_cmd "Location header incorrect: $(echo "$headers" | grep -i location)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 10 'requestRedirect:'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: URLRewrite ReplaceFullPath ==="
    local ns="ex-4-3"
    local route="rewrite-all"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9046:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response1 response2
    response1=$(curl_host "rw.example.test" 9046 "/dynamic/path")
    response2=$(curl_host "rw.example.test" 9046 "/another")

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response1" == *"path=/fixed"* ]]; then
        pass "Request to /dynamic/path rewrites to /fixed"
    else
        fail "Response1 was: $response1 (expected path=/fixed)"
    fi

    if [[ "$response2" == *"path=/fixed"* ]]; then
        pass "Request to /another rewrites to /fixed"
    else
        fail "Response2 was: $response2 (expected path=/fixed)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Canary traffic split ==="
    local ns="ex-5-1"
    local route="canary"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9051:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    # Phase 1: 90/10
    local v1=0 v2=0
    for i in $(seq 1 100); do
        local r
        r=$(curl_host "canary.example.test" 9051)
        if [[ "$r" == *"v1"* ]]; then
            v1=$((v1 + 1))
        elif [[ "$r" == *"v2"* ]]; then
            v2=$((v2 + 1))
        fi
    done

    if [[ $v1 -ge 80 ]] && [[ $v1 -le 100 ]] && [[ $v2 -ge 0 ]] && [[ $v2 -le 20 ]]; then
        pass "Phase 1 (90/10): v1=$v1, v2=$v2"
    else
        fail_with_cmd "Phase 1 (90/10): v1=$v1, v2=$v2 (expected ~90/10)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 10 'backendRefs:'"
    fi

    # Patch to 50/50 (user does this in verification, but we'll check that it works)
    info "Patching to 50/50 split..."
    kubectl patch httproute -n "$ns" "$route" --type='json' -p='[
      {"op":"replace","path":"/spec/rules/0/backendRefs/0/weight","value":50},
      {"op":"replace","path":"/spec/rules/0/backendRefs/1/weight","value":50}
    ]' &>/dev/null
    sleep 3

    # Phase 2: 50/50
    v1=0
    v2=0
    for i in $(seq 1 100); do
        local r
        r=$(curl_host "canary.example.test" 9051)
        if [[ "$r" == *"v1"* ]]; then
            v1=$((v1 + 1))
        elif [[ "$r" == *"v2"* ]]; then
            v2=$((v2 + 1))
        fi
    done

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ $v1 -ge 35 ]] && [[ $v1 -le 65 ]] && [[ $v2 -ge 35 ]] && [[ $v2 -le 65 ]]; then
        pass "Phase 2 (50/50): v1=$v1, v2=$v2"
    else
        fail "Phase 2 (50/50): v1=$v1, v2=$v2 (expected both around 50)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Compound filter failure ==="
    local ns="ex-5-2"
    local route="bad-order"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9052:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response
    response=$(curl_host "order.example.test" 9052 "/old-api/data")

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response" == *"final-path=/v2/data"* ]]; then
        pass "URLRewrite applied, backend sees /v2/data"
    else
        fail_with_cmd "Response was: $response (expected final-path=/v2/data)" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 15 'filters:'"
        info "Hint: RequestRedirect before URLRewrite causes redirect; remove redirect"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Production header-based canary with rewrite ==="
    local ns="ex-5-3"
    local route="production"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$route" "$ns"; then
        fail "HTTPRoute $route not found in namespace $ns"
        return
    fi

    local svc
    svc=$(get_ngf_service)
    if [[ -z "$svc" ]]; then
        fail "Could not find nginx-gateway service"
        return
    fi

    kubectl port-forward -n nginx-gateway "svc/$svc" 9053:80 &>/dev/null &
    local pf_pid=$!
    sleep 3

    local response_canary response_stable
    response_canary=$(curl_host "prod.example.test" 9053 "/api/data" "-H 'X-Canary: true'")
    response_stable=$(curl_host "prod.example.test" 9053 "/api/data")

    kill $pf_pid 2>/dev/null || true
    wait $pf_pid 2>/dev/null || true

    if [[ "$response_canary" == *"canary path=/v2/data"* ]]; then
        pass "Canary route (X-Canary: true) rewrites to /v2 and routes to canary"
    else
        fail_with_cmd "Canary response was: $response_canary (expected 'canary path=/v2/data')" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 20 'rules:'"
    fi

    if [[ "$response_stable" == *"stable path=/api/data"* ]]; then
        pass "Stable route (no X-Canary) routes to stable without rewrite"
    else
        fail_with_cmd "Stable response was: $response_stable (expected 'stable path=/api/data')" \
            "kubectl get httproute -n $ns $route -o yaml | grep -A 20 'rules:'"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: NGF Basics"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Advanced Matching"
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
    echo "# Level 4: Filters"
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
