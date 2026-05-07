#!/usr/bin/env bash
#
# verify.sh - Automated verification for ingress-and-gateway-api-homework.md (assignment 2)
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

# Helper: get ingress class
get_ingress_class() {
    local ingress=$1
    local ns=$2
    kubectl get ingress "$ingress" -n "$ns" -o jsonpath='{.spec.ingressClassName}' 2>/dev/null
}

# Helper: get ingress annotation
get_annotation() {
    local ingress=$1
    local ns=$2
    local annotation=$3
    kubectl get ingress "$ingress" -n "$ns" -o jsonpath="{.metadata.annotations.${annotation}}" 2>/dev/null
}

# Helper: get secret type
get_secret_type() {
    local secret=$1
    local ns=$2
    kubectl get secret "$secret" -n "$ns" -o jsonpath='{.type}' 2>/dev/null
}

# Helper: check if deployment is ready
deployment_ready() {
    local deployment=$1
    local ns=$2
    local ready
    ready=$(kubectl get deployment "$deployment" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    [[ "$ready" -gt 0 ]]
}

# Helper: test HTTP response
test_http() {
    local host=$1
    local path=$2
    local port=${3:-8080}
    curl -s -H "Host: $host" "http://localhost:$port$path" 2>/dev/null
}

# Helper: test HTTPS response
test_https() {
    local host=$1
    local path=$2
    local port=${3:-8443}
    curl -sk --resolve "$host:$port:127.0.0.1" "https://$host:$port$path" 2>/dev/null
}

# Helper: test HTTP redirect
test_redirect() {
    local host=$1
    local path=$2
    local port=${3:-8080}
    local status
    status=$(curl -sI -H "Host: $host" "http://localhost:$port$path" 2>/dev/null | head -n1 | awk '{print $2}')
    [[ "$status" == "301" || "$status" == "302" ]]
}

# Helper: get TLS certificate subject
get_tls_subject() {
    local host=$1
    local port=${2:-8443}
    curl -sk --resolve "$host:$port:127.0.0.1" -v "https://$host:$port/" 2>&1 | grep "subject:" | head -n1
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic HAProxy Ingress ==="
    local ingress="ex-1-1-ing"
    local ns="ex-1-1"

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
    if [[ "$class" == "haproxy" ]]; then
        pass "Ingress class is haproxy"
    else
        fail_with_cmd "Ingress class is '$class' (expected haproxy)" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.ingressClassName}'"
    fi

    local response
    response=$(test_http "one.example.test" "/")
    if [[ "$response" == *"level-1-1"* ]]; then
        pass "HTTP response contains 'level-1-1'"
    else
        fail_with_cmd "HTTP response: '$response' (expected 'level-1-1')" \
            "curl -s -H 'Host: one.example.test' http://localhost:8080/"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Rate-limit annotation ==="
    local ingress="api-rate-limited"
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

    local annotation
    annotation=$(get_annotation "$ingress" "$ns" "haproxy-ingress\.github\.io/rate-limit-rpm")
    if [[ "$annotation" == "120" ]]; then
        pass "Rate-limit annotation is '120'"
    else
        fail_with_cmd "Rate-limit annotation: '$annotation' (expected '120')" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.metadata.annotations}'"
    fi

    local response
    response=$(test_http "api.example.test" "/")
    if [[ "$response" == *"api-limited"* ]]; then
        pass "HTTP response contains 'api-limited'"
    else
        fail_with_cmd "HTTP response: '$response' (expected 'api-limited')" \
            "curl -s -H 'Host: api.example.test' http://localhost:8080/"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: HAProxy controller logs ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist (reuses ex-1-2)"
        return
    fi

    local log_count
    log_count=$(kubectl logs -n haproxy-ingress -l app.kubernetes.io/name=haproxy-ingress --tail=100 2>/dev/null | grep -c "api-rate-limited" || echo "0")

    if [[ "$log_count" -gt 0 ]]; then
        pass "HAProxy logs contain 'api-rate-limited' ($log_count occurrences)"
    else
        fail_with_cmd "HAProxy logs do not contain 'api-rate-limited'" \
            "kubectl logs -n haproxy-ingress -l app.kubernetes.io/name=haproxy-ingress --tail=100 | grep api-rate-limited"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Rewrite-target annotation ==="
    local ingress="rewrite"
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

    local annotation
    annotation=$(get_annotation "$ingress" "$ns" "haproxy-ingress\.github\.io/rewrite-target")
    if [[ "$annotation" == "/" ]]; then
        pass "Rewrite-target annotation is '/'"
    else
        fail_with_cmd "Rewrite-target annotation: '$annotation' (expected '/')" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.metadata.annotations}'"
    fi

    local response
    response=$(test_http "echo.example.test" "/strip/hello")
    if [[ "$response" == *"you-sent: /"* ]]; then
        pass "Rewrite works: '/strip/hello' -> '/'"
    else
        fail_with_cmd "Response: '$response' (expected 'you-sent: /')" \
            "curl -s -H 'Host: echo.example.test' http://localhost:8080/strip/hello"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Response headers annotation ==="
    local ingress="with-headers"
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

    local annotation
    annotation=$(get_annotation "$ingress" "$ns" "haproxy-ingress\.github\.io/response-headers")
    if [[ "$annotation" == *"X-App-Name"* ]]; then
        pass "Response-headers annotation includes 'X-App-Name'"
    else
        fail_with_cmd "Response-headers annotation: '$annotation' (expected 'X-App-Name: example')" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.metadata.annotations}'"
    fi

    local headers
    headers=$(curl -sI -H "Host: headers.example.test" http://localhost:8080/ 2>/dev/null)
    if [[ "$headers" == *"X-App-Name: example"* ]]; then
        pass "Response headers include 'X-App-Name: example'"
    else
        fail_with_cmd "Response headers do not include expected header" \
            "curl -sI -H 'Host: headers.example.test' http://localhost:8080/"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Same backend on two controllers ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    sleep 3

    # Test Traefik (port 80)
    local traefik_response
    traefik_response=$(curl -s -H "Host: both.example.test" http://localhost/ 2>/dev/null)
    if [[ "$traefik_response" == *"both-served"* ]]; then
        pass "Traefik (port 80) serves 'both-served'"
    else
        fail_with_cmd "Traefik response: '$traefik_response' (expected 'both-served')" \
            "curl -s -H 'Host: both.example.test' http://localhost/"
    fi

    # Test HAProxy (port 8080)
    local haproxy_response
    haproxy_response=$(curl -s -H "Host: both.example.test" http://localhost:8080/ 2>/dev/null)
    if [[ "$haproxy_response" == *"both-served"* ]]; then
        pass "HAProxy (port 8080) serves 'both-served'"
    else
        fail_with_cmd "HAProxy response: '$haproxy_response' (expected 'both-served')" \
            "curl -s -H 'Host: both.example.test' http://localhost:8080/"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Wrong annotation for controller ==="
    local ingress="wrong-annotation"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    # Check that HAProxy annotation is present
    local annotation
    annotation=$(get_annotation "$ingress" "$ns" "haproxy-ingress\.github\.io/rewrite-target")
    if [[ "$annotation" == "/" ]]; then
        pass "HAProxy rewrite-target annotation is present"
    else
        fail_with_cmd "HAProxy rewrite-target annotation missing (found: '$annotation')" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.metadata.annotations}'"
    fi

    # Verify rewrite works
    local response
    response=$(test_http "wrong.example.test" "/wrong/anything")
    if [[ "$response" == *"got: /"* ]]; then
        pass "Rewrite works: backend sees '/'"
    else
        fail_with_cmd "Response: '$response' (expected 'got: /')" \
            "curl -s -H 'Host: wrong.example.test' http://localhost:8080/wrong/anything"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: TLS Secret type mismatch ==="
    local secret="wrong-secret"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local secret_type
    secret_type=$(get_secret_type "$secret" "$ns")
    if [[ "$secret_type" == "kubernetes.io/tls" ]]; then
        pass "Secret type is 'kubernetes.io/tls'"
    else
        fail_with_cmd "Secret type: '$secret_type' (expected 'kubernetes.io/tls')" \
            "kubectl get secret -n $ns $secret -o jsonpath='{.type}'"
    fi

    sleep 3

    # Verify TLS handshake with correct CN
    local subject
    subject=$(get_tls_subject "secure.example.test" 8443)
    if [[ "$subject" == *"CN=secure.example.test"* ]]; then
        pass "TLS certificate CN is 'secure.example.test'"
    else
        fail_with_cmd "TLS subject: '$subject' (expected CN=secure.example.test)" \
            "curl -sk --resolve secure.example.test:8443:127.0.0.1 -v https://secure.example.test:8443/ 2>&1 | grep subject"
    fi

    # Verify content
    local response
    response=$(test_https "secure.example.test" "/" 8443)
    if [[ "$response" == *"secure"* ]]; then
        pass "HTTPS response contains 'secure'"
    else
        fail_with_cmd "HTTPS response: '$response' (expected 'secure')" \
            "curl -sk --resolve secure.example.test:8443:127.0.0.1 https://secure.example.test:8443/"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Missing ingressClassName ==="
    local ingress="stuck"
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

    local class
    class=$(get_ingress_class "$ingress" "$ns")
    if [[ "$class" == "haproxy" ]]; then
        pass "Ingress class is 'haproxy'"
    else
        fail_with_cmd "Ingress class: '$class' (expected 'haproxy')" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.spec.ingressClassName}'"
    fi

    local response
    response=$(test_http "stuck.example.test" "/")
    if [[ "$response" == *"dangling"* ]]; then
        pass "HTTP response contains 'dangling'"
    else
        fail_with_cmd "HTTP response: '$response' (expected 'dangling')" \
            "curl -s -H 'Host: stuck.example.test' http://localhost:8080/"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: TLS termination ==="
    local ingress="one-secure"
    local secret="one-tls"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    local secret_type
    secret_type=$(get_secret_type "$secret" "$ns")
    if [[ "$secret_type" == "kubernetes.io/tls" ]]; then
        pass "TLS Secret type is correct"
    else
        fail_with_cmd "Secret type: '$secret_type' (expected 'kubernetes.io/tls')" \
            "kubectl get secret -n $ns $secret -o jsonpath='{.type}'"
    fi

    sleep 3

    local response
    response=$(test_https "one-tls.example.test" "/" 8443)
    if [[ "$response" == *"one-tls-payload"* ]]; then
        pass "HTTPS response contains 'one-tls-payload'"
    else
        fail_with_cmd "HTTPS response: '$response' (expected 'one-tls-payload')" \
            "curl -sk --resolve one-tls.example.test:8443:127.0.0.1 https://one-tls.example.test:8443/"
    fi

    local subject
    subject=$(get_tls_subject "one-tls.example.test" 8443)
    if [[ "$subject" == *"CN=one-tls.example.test"* ]]; then
        pass "TLS certificate CN is 'one-tls.example.test'"
    else
        fail_with_cmd "TLS subject: '$subject' (expected CN=one-tls.example.test)" \
            "curl -sk --resolve one-tls.example.test:8443:127.0.0.1 -v https://one-tls.example.test:8443/ 2>&1 | grep subject"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Multi-host TLS with SNI ==="
    local ingress="multi"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    # Test site-a
    local response_a
    response_a=$(test_https "site-a.example.test" "/" 8443)
    if [[ "$response_a" == *"site-a"* ]]; then
        pass "site-a HTTPS response contains 'site-a'"
    else
        fail_with_cmd "site-a response: '$response_a' (expected 'site-a')" \
            "curl -sk --resolve site-a.example.test:8443:127.0.0.1 https://site-a.example.test:8443/"
    fi

    local subject_a
    subject_a=$(get_tls_subject "site-a.example.test" 8443)
    if [[ "$subject_a" == *"CN=site-a.example.test"* ]]; then
        pass "site-a TLS certificate CN is correct"
    else
        fail_with_cmd "site-a TLS subject: '$subject_a' (expected CN=site-a.example.test)" \
            "curl -sk --resolve site-a.example.test:8443:127.0.0.1 -v https://site-a.example.test:8443/ 2>&1 | grep subject"
    fi

    # Test site-b
    local response_b
    response_b=$(test_https "site-b.example.test" "/" 8443)
    if [[ "$response_b" == *"site-b"* ]]; then
        pass "site-b HTTPS response contains 'site-b'"
    else
        fail_with_cmd "site-b response: '$response_b' (expected 'site-b')" \
            "curl -sk --resolve site-b.example.test:8443:127.0.0.1 https://site-b.example.test:8443/"
    fi

    local subject_b
    subject_b=$(get_tls_subject "site-b.example.test" 8443)
    if [[ "$subject_b" == *"CN=site-b.example.test"* ]]; then
        pass "site-b TLS certificate CN is correct"
    else
        fail_with_cmd "site-b TLS subject: '$subject_b' (expected CN=site-b.example.test)" \
            "curl -sk --resolve site-b.example.test:8443:127.0.0.1 -v https://site-b.example.test:8443/ 2>&1 | grep subject"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: HTTP-to-HTTPS redirect ==="
    local ingress="redir"
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

    # Test redirect
    if test_redirect "redir.example.test" "/" 8080; then
        pass "HTTP redirects to HTTPS (301 or 302)"
    else
        fail_with_cmd "HTTP does not redirect" \
            "curl -sI -H 'Host: redir.example.test' http://localhost:8080/"
    fi

    # Test HTTPS content
    local response
    response=$(test_https "redir.example.test" "/" 8443)
    if [[ "$response" == *"redirected-payload"* ]]; then
        pass "HTTPS response contains 'redirected-payload'"
    else
        fail_with_cmd "HTTPS response: '$response' (expected 'redirected-payload')" \
            "curl -sk --resolve redir.example.test:8443:127.0.0.1 https://redir.example.test:8443/"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Production stack (TLS + redirect + rewrite) ==="
    local ingress="production"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    sleep 3

    # Test HTTP redirect
    if test_redirect "production.example.test" "/api/v2/things" 8080; then
        pass "HTTP redirects to HTTPS"
    else
        fail_with_cmd "HTTP does not redirect" \
            "curl -sI -H 'Host: production.example.test' http://localhost:8080/api/v2/things"
    fi

    # Test HTTPS with rewrite
    local response
    response=$(test_https "production.example.test" "/api/v2/things" 8443)
    if [[ "$response" == *"v2-served for /things"* ]]; then
        pass "HTTPS + rewrite works: backend sees '/things'"
    else
        fail_with_cmd "Response: '$response' (expected 'v2-served for /things')" \
            "curl -sk --resolve production.example.test:8443:127.0.0.1 https://production.example.test:8443/api/v2/things"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Multiple TLS issues ==="
    local ingress="multi-issue"
    local secret="bad-secret"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "$ingress" "$ns"; then
        fail "Ingress $ingress not found in namespace $ns"
        return
    fi

    # Check annotation is HAProxy, not Traefik
    local annotation
    annotation=$(get_annotation "$ingress" "$ns" "haproxy-ingress\.github\.io/ssl-redirect")
    if [[ "$annotation" == "true" ]]; then
        pass "HAProxy ssl-redirect annotation is present"
    else
        fail_with_cmd "HAProxy annotation missing (found: '$annotation')" \
            "kubectl get ingress -n $ns $ingress -o jsonpath='{.metadata.annotations}'"
    fi

    # Check Secret type
    local secret_type
    secret_type=$(get_secret_type "$secret" "$ns")
    if [[ "$secret_type" == "kubernetes.io/tls" ]]; then
        pass "Secret type is 'kubernetes.io/tls'"
    else
        fail_with_cmd "Secret type: '$secret_type' (expected 'kubernetes.io/tls')" \
            "kubectl get secret -n $ns $secret -o jsonpath='{.type}'"
    fi

    sleep 3

    # Test HTTP redirect
    if test_redirect "five-two.example.test" "/" 8080; then
        pass "HTTP redirects to HTTPS"
    else
        fail_with_cmd "HTTP does not redirect" \
            "curl -sI -H 'Host: five-two.example.test' http://localhost:8080/"
    fi

    # Test HTTPS content
    local response
    response=$(test_https "five-two.example.test" "/" 8443)
    if [[ "$response" == *"backend-served"* ]]; then
        pass "HTTPS response contains 'backend-served'"
    else
        fail_with_cmd "HTTPS response: '$response' (expected 'backend-served')" \
            "curl -sk --resolve five-two.example.test:8443:127.0.0.1 https://five-two.example.test:8443/"
    fi

    # Test TLS certificate CN
    local subject
    subject=$(get_tls_subject "five-two.example.test" 8443)
    if [[ "$subject" == *"CN=five-two.example.test"* ]]; then
        pass "TLS certificate CN is correct"
    else
        fail_with_cmd "TLS subject: '$subject' (expected CN=five-two.example.test)" \
            "curl -sk --resolve five-two.example.test:8443:127.0.0.1 -v https://five-two.example.test:8443/ 2>&1 | grep subject"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Multi-tenant TLS with health endpoint ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    sleep 3

    # Test tenant t1 with TLS and rewrite
    local response_t1
    response_t1=$(test_https "t1.example.test" "/api/items" 8443)
    if [[ "$response_t1" == *"t1 serves: /items"* ]]; then
        pass "t1 HTTPS + rewrite works: backend sees '/items'"
    else
        fail_with_cmd "t1 response: '$response_t1' (expected 't1 serves: /items')" \
            "curl -sk --resolve t1.example.test:8443:127.0.0.1 https://t1.example.test:8443/api/items"
    fi

    local subject_t1
    subject_t1=$(get_tls_subject "t1.example.test" 8443)
    if [[ "$subject_t1" == *"CN=t1.example.test"* ]]; then
        pass "t1 TLS certificate CN is correct"
    else
        fail_with_cmd "t1 TLS subject: '$subject_t1' (expected CN=t1.example.test)" \
            "curl -sk --resolve t1.example.test:8443:127.0.0.1 -v https://t1.example.test:8443/ 2>&1 | grep subject"
    fi

    # Test tenant t2 with TLS and rewrite
    local response_t2
    response_t2=$(test_https "t2.example.test" "/api/items" 8443)
    if [[ "$response_t2" == *"t2 serves: /items"* ]]; then
        pass "t2 HTTPS + rewrite works: backend sees '/items'"
    else
        fail_with_cmd "t2 response: '$response_t2' (expected 't2 serves: /items')" \
            "curl -sk --resolve t2.example.test:8443:127.0.0.1 https://t2.example.test:8443/api/items"
    fi

    local subject_t2
    subject_t2=$(get_tls_subject "t2.example.test" 8443)
    if [[ "$subject_t2" == *"CN=t2.example.test"* ]]; then
        pass "t2 TLS certificate CN is correct"
    else
        fail_with_cmd "t2 TLS subject: '$subject_t2' (expected CN=t2.example.test)" \
            "curl -sk --resolve t2.example.test:8443:127.0.0.1 -v https://t2.example.test:8443/ 2>&1 | grep subject"
    fi

    # Test HTTP-only health endpoint
    local health_response
    health_response=$(test_http "status.example.test" "/healthz" 8080)
    if [[ "$health_response" == *"OK"* ]]; then
        pass "Health endpoint returns 'OK'"
    else
        fail_with_cmd "Health response: '$health_response' (expected 'OK')" \
            "curl -s -H 'Host: status.example.test' http://localhost:8080/healthz"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: HAProxy Basics"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Annotations and Rewrite"
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
    echo "# Level 4: TLS"
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
