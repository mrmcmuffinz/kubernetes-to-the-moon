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

# Helper: check if CoreDNS pods are running
coredns_pods_running() {
    local count
    count=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -c "Running" || echo "0")
    [[ "$count" -gt 0 ]]
}

# Helper: get kube-dns service ClusterIP
get_kube_dns_ip() {
    kubectl get svc kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null
}

# Helper: get ConfigMap content
get_corefile() {
    kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null
}

# Helper: check if Corefile contains a pattern
corefile_contains() {
    local pattern=$1
    get_corefile | grep -q "$pattern"
}

# Helper: test DNS resolution from pod
test_dns_from_pod() {
    local pod=$1
    local ns=$2
    local hostname=$3
    kubectl exec -n "$ns" "$pod" -- nslookup "$hostname" &>/dev/null
}

# Helper: test DNS resolution with expected IP
test_dns_ip() {
    local pod=$1
    local ns=$2
    local hostname=$3
    local expected_ip=$4
    kubectl exec -n "$ns" "$pod" -- nslookup "$hostname" 2>/dev/null | grep -q "$expected_ip"
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: List CoreDNS components ==="
    local pod="explorer"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    if coredns_pods_running; then
        pass "CoreDNS pods are running"
    else
        fail_with_cmd "CoreDNS pods are not running" \
            "kubectl get pods -n kube-system -l k8s-app=kube-dns"
    fi

    local kube_dns_ip
    kube_dns_ip=$(get_kube_dns_ip)
    if [[ -n "$kube_dns_ip" ]]; then
        pass "kube-dns service exists with ClusterIP: $kube_dns_ip"
    else
        fail_with_cmd "kube-dns service not found" \
            "kubectl get svc kube-dns -n kube-system"
        return
    fi

    local resolv_conf
    resolv_conf=$(kubectl exec -n "$ns" "$pod" -- cat /etc/resolv.conf 2>/dev/null || echo "")
    if echo "$resolv_conf" | grep -q "$kube_dns_ip"; then
        pass "Pod uses kube-dns IP as nameserver"
    else
        fail_with_cmd "Pod does not use kube-dns IP" \
            "kubectl exec -n $ns $pod -- cat /etc/resolv.conf"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: View CoreDNS ConfigMap ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if kubectl get configmap coredns -n kube-system &>/dev/null; then
        pass "ConfigMap coredns exists in kube-system"
    else
        fail_with_cmd "ConfigMap coredns not found" \
            "kubectl get configmap -n kube-system"
        return
    fi

    if corefile_contains "Corefile"; then
        pass "ConfigMap contains Corefile data"
    else
        fail_with_cmd "Corefile not found in ConfigMap" \
            "kubectl get configmap coredns -n kube-system -o yaml"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Identify plugins ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if corefile_contains "kubernetes"; then
        pass "kubernetes plugin present"
    else
        fail "kubernetes plugin not found in Corefile"
    fi

    if corefile_contains "forward"; then
        pass "forward plugin present"
    else
        fail "forward plugin not found in Corefile"
    fi

    if corefile_contains "cache"; then
        pass "cache plugin present"
    else
        fail "cache plugin not found in Corefile"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Examine kubernetes plugin ==="
    local pod="client"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    if corefile_contains "cluster.local"; then
        pass "cluster.local domain configured"
    else
        fail_with_cmd "cluster.local not found in Corefile" \
            "kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'"
    fi

    sleep 2

    if test_dns_from_pod "$pod" "$ns" "web-svc"; then
        pass "Service resolution works from client pod"
    else
        fail_with_cmd "Service resolution failed" \
            "kubectl exec -n $ns $pod -- nslookup web-svc"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Examine forward plugin ==="
    local pod="external-test"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    if corefile_contains "forward"; then
        pass "forward plugin present"
    else
        fail "forward plugin not found in Corefile"
    fi

    sleep 2

    if test_dns_from_pod "$pod" "$ns" "example.com"; then
        pass "External DNS resolution works"
    else
        fail_with_cmd "External DNS resolution failed" \
            "kubectl exec -n $ns $pod -- nslookup example.com"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: View CoreDNS logs ==="
    local pod="query-maker"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Generate queries as instructed in the exercise
    kubectl exec -n "$ns" "$pod" -- nslookup kubernetes.default &>/dev/null || true
    kubectl exec -n "$ns" "$pod" -- nslookup nonexistent.invalid &>/dev/null || true

    sleep 2

    if kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20 &>/dev/null; then
        pass "CoreDNS logs accessible"
        info "Note: By default, only errors are logged (not successful queries)"
    else
        fail_with_cmd "Cannot access CoreDNS logs" \
            "kubectl logs -n kube-system -l k8s-app=kube-dns --tail=20"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug syntax error ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    info "This exercise intentionally breaks DNS to teach debugging"
    info "The setup introduces a syntax error in the Corefile"
    info "Check CoreDNS pod status and logs to diagnose the issue"

    local pods_ok=0
    kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q "Running" && pods_ok=1 || pods_ok=0

    if [[ $pods_ok -eq 0 ]]; then
        pass "CoreDNS pods show issues (expected for this debugging exercise)"
        info "Look for parse errors in logs indicating missing closing brace"
    else
        info "CoreDNS may still be running with cached config"
    fi

    info "The cleanup step restores working config from backup"
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug broken forward plugin ==="
    local pod="dns-tester"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    info "This exercise uses an invalid upstream DNS (192.0.2.1)"

    sleep 2

    if test_dns_from_pod "$pod" "$ns" "kubernetes.default"; then
        pass "Cluster DNS works (kubernetes.default resolves)"
    else
        fail_with_cmd "Cluster DNS failed" \
            "kubectl exec -n $ns $pod -- nslookup kubernetes.default"
    fi

    # External should fail with bad upstream
    if ! timeout 5 kubectl exec -n "$ns" "$pod" -- nslookup example.com &>/dev/null; then
        pass "External DNS fails as expected (invalid upstream: 192.0.2.1)"
        info "The forward plugin uses TEST-NET-1 IP which does not respond"
    else
        info "External DNS unexpectedly succeeded (may be using cached config)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug missing fallthrough ==="
    local pod="hosts-tester"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 2

    if test_dns_ip "$pod" "$ns" "custom.internal" "10.10.10.10"; then
        pass "Custom hostname resolves to 10.10.10.10"
    else
        fail_with_cmd "Custom hostname does not resolve" \
            "kubectl exec -n $ns $pod -- nslookup custom.internal"
    fi

    # Service DNS should fail without fallthrough
    if ! test_dns_from_pod "$pod" "$ns" "kubernetes.default"; then
        pass "Service DNS fails (expected: hosts plugin missing fallthrough)"
        info "Without fallthrough, hosts plugin stops processing for all queries"
    else
        info "Service DNS unexpectedly works (may be using cached config)"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Add custom DNS entry ==="
    local pod="lookup-pod"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Check if hosts plugin was added to config
    if corefile_contains "legacy-db.internal"; then
        pass "Custom entry legacy-db.internal found in Corefile"
    else
        fail_with_cmd "Custom entry not found in Corefile" \
            "kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'"
        return
    fi

    sleep 15

    if test_dns_ip "$pod" "$ns" "legacy-db.internal" "172.16.0.100"; then
        pass "Custom entry resolves to 172.16.0.100"
    else
        fail_with_cmd "Custom entry does not resolve correctly" \
            "kubectl exec -n $ns $pod -- nslookup legacy-db.internal"
    fi

    if test_dns_from_pod "$pod" "$ns" "app-svc"; then
        pass "Cluster DNS still works (app-svc resolves)"
    else
        fail_with_cmd "Cluster DNS broken (check for fallthrough in hosts plugin)" \
            "kubectl exec -n $ns $pod -- nslookup app-svc"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Enable query logging ==="
    local pod="log-tester"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    if corefile_contains "log"; then
        pass "log plugin added to Corefile"
    else
        fail_with_cmd "log plugin not found in Corefile" \
            "kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'"
        return
    fi

    sleep 15

    # Generate test queries
    kubectl exec -n "$ns" "$pod" -- nslookup kubernetes.default &>/dev/null || true
    kubectl exec -n "$ns" "$pod" -- nslookup example.com &>/dev/null || true
    sleep 5

    local logs
    logs=$(kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50 2>/dev/null || echo "")
    if echo "$logs" | grep -qE "(kubernetes|example)"; then
        pass "DNS queries appear in logs"
    else
        fail_with_cmd "No query logs found (may need more time for reload)" \
            "kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Modify cache TTL ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local cache_config
    cache_config=$(get_corefile | grep -A2 "cache" | head -5)

    if echo "$cache_config" | grep -qE "cache [0-9]+"; then
        pass "cache plugin configured"
    else
        fail_with_cmd "cache plugin configuration not found" \
            "kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' | grep -A2 cache"
        return
    fi

    # Check for TTL of 60 and denial setting
    if echo "$cache_config" | grep -q "60"; then
        pass "Cache TTL set to 60 seconds"
    else
        info "Expected cache TTL of 60 seconds in configuration"
    fi

    if echo "$cache_config" | grep -q "denial"; then
        pass "Negative caching (denial) configured"
    else
        info "Expected denial directive for negative caching"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Configure stub domain ==="
    local pod="enterprise-app"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    if corefile_contains "corp.example.com"; then
        pass "Stub domain corp.example.com configured in Corefile"
    else
        fail_with_cmd "Stub domain not found in Corefile" \
            "kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}'"
        return
    fi

    sleep 15

    if coredns_pods_running; then
        pass "CoreDNS pods still running (config is valid)"
    else
        fail_with_cmd "CoreDNS pods not running (syntax error in config)" \
            "kubectl get pods -n kube-system -l k8s-app=kube-dns"
    fi

    if test_dns_from_pod "$pod" "$ns" "kubernetes.default"; then
        pass "Normal cluster DNS still works"
    else
        fail_with_cmd "Normal DNS broken" \
            "kubectl exec -n $ns $pod -- nslookup kubernetes.default"
    fi

    info "Stub domain forwards to 10.0.0.53 and 10.0.0.54 (example IPs)"
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Troubleshoot custom configuration ==="
    local pod="config-tester"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    if corefile_contains "internal.company"; then
        pass "Custom server block for internal.company found"
    else
        fail "Custom server block not found in Corefile"
        return
    fi

    sleep 15

    if coredns_pods_running; then
        pass "CoreDNS pods running (config is syntactically valid)"
    else
        fail_with_cmd "CoreDNS pods not running" \
            "kubectl get pods -n kube-system -l k8s-app=kube-dns"
    fi

    info "This exercise demonstrates server block matching issues"
    info "The db.internal.company may not resolve due to search domain handling"
    info "Identify why the custom server block isn't matched as expected"
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Design complete configuration ==="
    local pod="requirements-test"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 15

    # Requirement 1: Normal cluster DNS
    if test_dns_from_pod "$pod" "$ns" "kubernetes.default"; then
        pass "Requirement 1: Cluster DNS works"
    else
        fail_with_cmd "Cluster DNS broken" \
            "kubectl exec -n $ns $pod -- nslookup kubernetes.default"
    fi

    # Requirement 2: Query logging
    if corefile_contains "log"; then
        pass "Requirement 2: Query logging enabled"
    else
        fail "log plugin not found in Corefile"
    fi

    # Requirement 3: Custom entry
    if test_dns_ip "$pod" "$ns" "monitoring.internal" "10.20.30.40"; then
        pass "Requirement 3: Custom entry monitoring.internal resolves to 10.20.30.40"
    else
        fail_with_cmd "Custom entry does not resolve" \
            "kubectl exec -n $ns $pod -- nslookup monitoring.internal"
    fi

    # Requirement 4: Cache TTL
    if get_corefile | grep -q "cache 45"; then
        pass "Requirement 4: Cache TTL set to 45 seconds"
    else
        fail "cache 45 not found in Corefile"
    fi

    # Requirement 5: Standard plugins
    local has_health=0
    local has_ready=0
    local has_reload=0
    corefile_contains "health" && has_health=1
    corefile_contains "ready" && has_ready=1
    corefile_contains "reload" && has_reload=1

    if [[ $has_health -eq 1 && $has_ready -eq 1 && $has_reload -eq 1 ]]; then
        pass "Requirement 5: Standard plugins (health, ready, reload) present"
    else
        fail "Missing standard plugins"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: CoreDNS Exploration"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Configuration Basics"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Configuration Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Customization"
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
