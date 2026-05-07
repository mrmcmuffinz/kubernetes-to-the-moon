#!/usr/bin/env bash
#
# verify.sh - Automated verification for coredns-homework.md
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

# Helper: check if pod is ready
is_pod_ready() {
    local pod=$1
    local ns=$2
    local ready
    ready=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    [[ "$ready" == "True" ]]
}

# Helper: check if service exists
service_exists() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" &>/dev/null
}

# Helper: check DNS resolution via nslookup
dns_resolves() {
    local pod=$1
    local ns=$2
    local name=$3
    kubectl exec -n "$ns" "$pod" -- nslookup "$name" 2>/dev/null | grep -q "Address"
}

# Helper: check if DNS does NOT resolve
dns_does_not_resolve() {
    local pod=$1
    local ns=$2
    local name=$3
    ! kubectl exec -n "$ns" "$pod" -- nslookup "$name" 2>/dev/null | grep -q "Address"
}

# Helper: get DNS policy
get_dns_policy() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.dnsPolicy}' 2>/dev/null
}

# Helper: check if resolv.conf contains a pattern
resolv_contains() {
    local pod=$1
    local ns=$2
    local pattern=$3
    kubectl exec -n "$ns" "$pod" -- cat /etc/resolv.conf 2>/dev/null | grep -q "$pattern"
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Service DNS short name lookup ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "backend-svc" "$ns"; then
        fail "Service backend-svc not found in namespace $ns"
        return
    fi

    if ! pod_exists "client" "$ns"; then
        fail "Pod client not found in namespace $ns"
        return
    fi

    if ! is_pod_ready "client" "$ns"; then
        fail "Pod client is not ready"
        return
    fi

    if dns_resolves "client" "$ns" "backend-svc"; then
        pass "Short name 'backend-svc' resolves from client pod"
    else
        fail_with_cmd "Service name 'backend-svc' does not resolve" \
            "kubectl exec -n $ns client -- nslookup backend-svc"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Service DNS FQDN lookup ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "database-svc" "$ns"; then
        fail "Service database-svc not found in namespace $ns"
        return
    fi

    if ! pod_exists "lookup" "$ns"; then
        fail "Pod lookup not found in namespace $ns"
        return
    fi

    if ! is_pod_ready "lookup" "$ns"; then
        fail "Pod lookup is not ready"
        return
    fi

    if dns_resolves "lookup" "$ns" "database-svc.ex-1-2.svc.cluster.local"; then
        pass "FQDN 'database-svc.ex-1-2.svc.cluster.local' resolves from lookup pod"
    else
        fail_with_cmd "FQDN does not resolve" \
            "kubectl exec -n $ns lookup -- nslookup database-svc.ex-1-2.svc.cluster.local"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Cross-namespace service lookup ==="
    local frontend_ns="ex-1-3-frontend"
    local backend_ns="ex-1-3-backend"

    if ! namespace_exists "$frontend_ns"; then
        fail "Namespace $frontend_ns does not exist"
        return
    fi

    if ! namespace_exists "$backend_ns"; then
        fail "Namespace $backend_ns does not exist"
        return
    fi

    if ! service_exists "api-service" "$backend_ns"; then
        fail "Service api-service not found in namespace $backend_ns"
        return
    fi

    if ! pod_exists "frontend" "$frontend_ns"; then
        fail "Pod frontend not found in namespace $frontend_ns"
        return
    fi

    if ! is_pod_ready "frontend" "$frontend_ns"; then
        fail "Pod frontend is not ready"
        return
    fi

    if dns_resolves "frontend" "$frontend_ns" "api-service.ex-1-3-backend"; then
        pass "Cross-namespace lookup 'api-service.ex-1-3-backend' resolves"
    else
        fail_with_cmd "Cross-namespace DNS does not resolve" \
            "kubectl exec -n $frontend_ns frontend -- nslookup api-service.ex-1-3-backend"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Pod DNS record ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "target-pod" "$ns"; then
        fail "Pod target-pod not found in namespace $ns"
        return
    fi

    if ! pod_exists "lookup-pod" "$ns"; then
        fail "Pod lookup-pod not found in namespace $ns"
        return
    fi

    if ! is_pod_ready "lookup-pod" "$ns"; then
        fail "Pod lookup-pod is not ready"
        return
    fi

    # Get the target pod IP and construct its DNS name
    local pod_ip
    pod_ip=$(kubectl get pod -n "$ns" target-pod -o jsonpath='{.status.podIP}' 2>/dev/null)

    if [[ -z "$pod_ip" ]]; then
        fail "Could not get IP for target-pod"
        return
    fi

    local pod_dns
    pod_dns=$(echo "$pod_ip" | tr '.' '-')
    local full_dns="${pod_dns}.${ns}.pod.cluster.local"

    if dns_resolves "lookup-pod" "$ns" "$full_dns"; then
        pass "Pod DNS name '$full_dns' resolves to $pod_ip"
    else
        fail_with_cmd "Pod DNS name does not resolve" \
            "kubectl exec -n $ns lookup-pod -- nslookup $full_dns"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: DNS policy comparison ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "web-svc" "$ns"; then
        fail "Service web-svc not found in namespace $ns"
        return
    fi

    if ! pod_exists "pod-clusterfirst" "$ns"; then
        fail "Pod pod-clusterfirst not found in namespace $ns"
        return
    fi

    if ! pod_exists "pod-default" "$ns"; then
        fail "Pod pod-default not found in namespace $ns"
        return
    fi

    if ! is_pod_ready "pod-clusterfirst" "$ns"; then
        fail "Pod pod-clusterfirst is not ready"
        return
    fi

    if ! is_pod_ready "pod-default" "$ns"; then
        fail "Pod pod-default is not ready"
        return
    fi

    # ClusterFirst should resolve service names
    if dns_resolves "pod-clusterfirst" "$ns" "web-svc"; then
        pass "ClusterFirst pod can resolve service name 'web-svc'"
    else
        fail_with_cmd "ClusterFirst pod cannot resolve service name" \
            "kubectl exec -n $ns pod-clusterfirst -- nslookup web-svc"
    fi

    # Default should NOT resolve service names
    if dns_does_not_resolve "pod-default" "$ns" "web-svc"; then
        pass "Default policy pod cannot resolve service name (expected behavior)"
    else
        fail "Default policy pod unexpectedly resolves service name"
        info "Hint: Default policy uses node DNS, not cluster DNS"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Examine resolv.conf ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "examine-pod" "$ns"; then
        fail "Pod examine-pod not found in namespace $ns"
        return
    fi

    if ! is_pod_ready "examine-pod" "$ns"; then
        fail "Pod examine-pod is not ready"
        return
    fi

    # Check for nameserver line
    if resolv_contains "examine-pod" "$ns" "nameserver"; then
        pass "resolv.conf contains nameserver line"
    else
        fail_with_cmd "resolv.conf missing nameserver line" \
            "kubectl exec -n $ns examine-pod -- cat /etc/resolv.conf"
    fi

    # Check for namespace search domain
    if resolv_contains "examine-pod" "$ns" "ex-2-3.svc.cluster.local"; then
        pass "resolv.conf contains namespace search domain"
    else
        fail_with_cmd "resolv.conf missing namespace search domain" \
            "kubectl exec -n $ns examine-pod -- cat /etc/resolv.conf"
    fi

    # Check for ndots option
    if resolv_contains "examine-pod" "$ns" "ndots"; then
        pass "resolv.conf contains ndots option"
    else
        fail_with_cmd "resolv.conf missing ndots option" \
            "kubectl exec -n $ns examine-pod -- cat /etc/resolv.conf"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug DNS policy issue ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "broken-client" "$ns"; then
        fail "Pod broken-client not found in namespace $ns"
        return
    fi

    local dns_policy
    dns_policy=$(get_dns_policy "broken-client" "$ns")

    if [[ "$dns_policy" == "Default" ]]; then
        info "Exercise setup: DNS policy is Default (service resolution will fail)"
        pass "Diagnosis: Pod uses dnsPolicy: Default which cannot resolve cluster services"
    else
        fail "Expected DNS policy 'Default' but got '$dns_policy'"
    fi

    # Verify the failure exists (setup should have Default policy)
    if dns_does_not_resolve "broken-client" "$ns" "server-svc" 2>/dev/null; then
        pass "Confirmed: service name does not resolve with Default policy"
    else
        info "Note: If DNS now resolves, the issue may have been fixed"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug cross-namespace DNS ==="
    local app_ns="ex-3-2-app"
    local db_ns="ex-3-2-db"

    if ! namespace_exists "$app_ns"; then
        fail "Namespace $app_ns does not exist"
        return
    fi

    if ! namespace_exists "$db_ns"; then
        fail "Namespace $db_ns does not exist"
        return
    fi

    if ! pod_exists "app" "$app_ns"; then
        fail "Pod app not found in namespace $app_ns"
        return
    fi

    if ! is_pod_ready "app" "$app_ns"; then
        fail "Pod app is not ready"
        return
    fi

    # Short name should fail
    if dns_does_not_resolve "app" "$app_ns" "mysql-svc" 2>/dev/null; then
        pass "Short name 'mysql-svc' does not resolve from different namespace (expected)"
    else
        info "Note: Short name unexpectedly resolves"
    fi

    # Namespace-qualified name should work
    if dns_resolves "app" "$app_ns" "mysql-svc.ex-3-2-db"; then
        pass "Namespace-qualified name 'mysql-svc.ex-3-2-db' resolves correctly"
    else
        fail_with_cmd "Namespace-qualified DNS does not resolve" \
            "kubectl exec -n $app_ns app -- nslookup mysql-svc.ex-3-2-db"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Search domain expansion behavior ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "external-test" "$ns"; then
        fail "Pod external-test not found in namespace $ns"
        return
    fi

    if ! is_pod_ready "external-test" "$ns"; then
        fail "Pod external-test is not ready"
        return
    fi

    # Check if dig is available (should be installed by setup)
    if kubectl exec -n "$ns" external-test -- which dig &>/dev/null; then
        pass "dig command is available in pod"
    else
        fail "dig command not found in pod (setup may be incomplete)"
        info "Setup should run: kubectl exec -n ex-3-3 external-test -- apk add --no-cache bind-tools"
        return
    fi

    # Query without trailing dot should trigger search expansion
    local query_result
    query_result=$(kubectl exec -n "$ns" external-test -- dig example.com +short 2>/dev/null | head -1)

    if [[ -n "$query_result" ]]; then
        pass "Query 'example.com' resolves (search domains applied)"
    else
        info "Query 'example.com' may have failed or returned no records"
    fi

    # Query with trailing dot should be faster (direct query)
    query_result=$(kubectl exec -n "$ns" external-test -- dig example.com. +short 2>/dev/null | head -1)

    if [[ -n "$query_result" ]]; then
        pass "Query 'example.com.' (with trailing dot) resolves directly"
    else
        info "Query 'example.com.' may have failed or returned no records"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Custom search domain with dnsConfig ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "custom-search" "$ns"; then
        fail "Pod custom-search not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "custom-search" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod custom-search is running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod -n $ns custom-search -o jsonpath='{.status.phase}'"
        return
    fi

    # Check for custom search domain
    if resolv_contains "custom-search" "$ns" "internal.company.local"; then
        pass "Custom search domain 'internal.company.local' present in resolv.conf"
    else
        fail_with_cmd "Custom search domain not found in resolv.conf" \
            "kubectl exec -n $ns custom-search -- cat /etc/resolv.conf"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Custom ndots value ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "low-ndots" "$ns"; then
        fail "Pod low-ndots not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "low-ndots" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod low-ndots is running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod -n $ns low-ndots -o jsonpath='{.status.phase}'"
        return
    fi

    # Check for ndots:1
    if resolv_contains "low-ndots" "$ns" "ndots:1"; then
        pass "ndots:1 is set in resolv.conf"
    else
        fail_with_cmd "ndots:1 not found in resolv.conf" \
            "kubectl exec -n $ns low-ndots -- cat /etc/resolv.conf"
    fi

    # Verify service resolution still works
    if dns_resolves "low-ndots" "$ns" "webapi-svc"; then
        pass "Service resolution 'webapi-svc' still works with ndots:1"
    else
        fail_with_cmd "Service resolution failed with ndots:1" \
            "kubectl exec -n $ns low-ndots -- nslookup webapi-svc"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: dnsPolicy None with full custom config ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "fully-custom" "$ns"; then
        fail "Pod fully-custom not found in namespace $ns"
        return
    fi

    local dns_policy
    dns_policy=$(get_dns_policy "fully-custom" "$ns")
    if [[ "$dns_policy" == "None" ]]; then
        pass "Pod has dnsPolicy: None"
    else
        fail_with_cmd "DNS policy is '$dns_policy' (expected None)" \
            "kubectl get pod -n $ns fully-custom -o jsonpath='{.spec.dnsPolicy}'"
    fi

    # Verify service resolution works with custom config
    if dns_resolves "fully-custom" "$ns" "target-svc"; then
        pass "Service resolution 'target-svc' works with custom DNS config"
    else
        fail_with_cmd "Service resolution failed with custom DNS config" \
            "kubectl exec -n $ns fully-custom -- nslookup target-svc"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multi-tier cross-namespace service discovery ==="
    local web_ns="ex-5-1-web"
    local api_ns="ex-5-1-api"
    local db_ns="ex-5-1-db"

    if ! namespace_exists "$web_ns"; then
        fail "Namespace $web_ns does not exist"
        return
    fi

    if ! namespace_exists "$api_ns"; then
        fail "Namespace $api_ns does not exist"
        return
    fi

    if ! namespace_exists "$db_ns"; then
        fail "Namespace $db_ns does not exist"
        return
    fi

    if ! pod_exists "web-frontend" "$web_ns"; then
        fail "Pod web-frontend not found in namespace $web_ns"
        return
    fi

    if ! is_pod_ready "web-frontend" "$web_ns"; then
        fail "Pod web-frontend is not ready"
        return
    fi

    # Web to API
    if dns_resolves "web-frontend" "$web_ns" "api-svc.ex-5-1-api"; then
        pass "Web to API DNS resolution works"
    else
        fail_with_cmd "Web to API DNS resolution failed" \
            "kubectl exec -n $web_ns web-frontend -- nslookup api-svc.ex-5-1-api"
    fi

    # Web to DB
    if dns_resolves "web-frontend" "$web_ns" "postgres-svc.ex-5-1-db"; then
        pass "Web to DB DNS resolution works"
    else
        fail_with_cmd "Web to DB DNS resolution failed" \
            "kubectl exec -n $web_ns web-frontend -- nslookup postgres-svc.ex-5-1-db"
    fi

    # API to DB (need nslookup in nginx)
    if pod_exists "api-server" "$api_ns" && is_pod_ready "api-server" "$api_ns"; then
        # Check if nslookup is available (may need apt-get update first)
        if kubectl exec -n "$api_ns" api-server -- which nslookup &>/dev/null; then
            if dns_resolves "api-server" "$api_ns" "postgres-svc.ex-5-1-db"; then
                pass "API to DB DNS resolution works"
            else
                info "API to DB DNS check: nslookup failed"
            fi
        else
            info "API to DB DNS check: nslookup not available in nginx pod"
        fi
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Host network DNS policy ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "hostnet-wrong" "$ns"; then
        fail "Pod hostnet-wrong not found in namespace $ns"
        return
    fi

    if ! pod_exists "hostnet-correct" "$ns"; then
        fail "Pod hostnet-correct not found in namespace $ns"
        return
    fi

    if ! is_pod_ready "hostnet-wrong" "$ns"; then
        fail "Pod hostnet-wrong is not ready"
        return
    fi

    if ! is_pod_ready "hostnet-correct" "$ns"; then
        fail "Pod hostnet-correct is not ready"
        return
    fi

    # Check DNS policies
    local policy_wrong
    policy_wrong=$(get_dns_policy "hostnet-wrong" "$ns")
    if [[ "$policy_wrong" == "ClusterFirst" ]]; then
        pass "hostnet-wrong has dnsPolicy: ClusterFirst (will not work with hostNetwork)"
    else
        info "hostnet-wrong has dnsPolicy: $policy_wrong"
    fi

    local policy_correct
    policy_correct=$(get_dns_policy "hostnet-correct" "$ns")
    if [[ "$policy_correct" == "ClusterFirstWithHostNet" ]]; then
        pass "hostnet-correct has dnsPolicy: ClusterFirstWithHostNet"
    else
        fail "hostnet-correct has dnsPolicy: $policy_correct (expected ClusterFirstWithHostNet)"
    fi

    # Verify correct pod can resolve service names
    if dns_resolves "hostnet-correct" "$ns" "test-svc.ex-5-2"; then
        pass "hostnet-correct can resolve service names"
    else
        fail_with_cmd "hostnet-correct cannot resolve service names" \
            "kubectl exec -n $ns hostnet-correct -- nslookup test-svc.ex-5-2"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Optimized DNS strategy ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "optimized-app" "$ns"; then
        fail "Pod optimized-app not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "optimized-app" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod optimized-app is running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod -n $ns optimized-app -o jsonpath='{.status.phase}'"
        return
    fi

    # Check for custom domain
    if resolv_contains "optimized-app" "$ns" "internal.corp"; then
        pass "Custom domain 'internal.corp' present in resolv.conf"
    else
        fail_with_cmd "Custom domain 'internal.corp' not found in resolv.conf" \
            "kubectl exec -n $ns optimized-app -- cat /etc/resolv.conf"
    fi

    # Check for ndots:2
    if resolv_contains "optimized-app" "$ns" "ndots:2"; then
        pass "ndots:2 is set in resolv.conf"
    else
        fail_with_cmd "ndots:2 not found in resolv.conf" \
            "kubectl exec -n $ns optimized-app -- cat /etc/resolv.conf"
    fi

    # Verify cluster DNS still works
    if dns_resolves "optimized-app" "$ns" "kubernetes.default"; then
        pass "Cluster DNS resolution 'kubernetes.default' works"
    else
        fail_with_cmd "Cluster DNS resolution failed" \
            "kubectl exec -n $ns optimized-app -- nslookup kubernetes.default"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Service DNS"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Pod DNS and Policies"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging DNS Queries"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: DNS Configuration"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Complex Scenarios"
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
