#!/usr/bin/env bash
#
# verify.sh - Automated verification for network-policies-homework.md
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

# Helper: check if NetworkPolicy exists
netpol_exists() {
    local np=$1
    local ns=$2
    kubectl get networkpolicy "$np" -n "$ns" &>/dev/null
}

# Helper: check if pod exists
pod_exists() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

# Helper: get pod IP
get_pod_ip() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.podIP}' 2>/dev/null
}

# Helper: test connectivity from one pod to an IP (returns 0 if allowed, 1 if blocked)
test_connectivity() {
    local source_pod=$1
    local source_ns=$2
    local target_ip=$3
    local port=${4:-80}

    timeout 3 kubectl exec -n "$source_ns" "$source_pod" -- wget -qO- --timeout=2 "http://$target_ip:$port" &>/dev/null
}

# Helper: test TCP connectivity with nc (returns 0 if allowed, 1 if blocked)
test_tcp_connectivity() {
    local source_pod=$1
    local source_ns=$2
    local target_ip=$3
    local port=$4

    timeout 3 kubectl exec -n "$source_ns" "$source_pod" -- nc -zv "$target_ip" "$port" &>/dev/null
}

# Helper: get NetworkPolicy pod selector
get_netpol_selector() {
    local np=$1
    local ns=$2
    kubectl get networkpolicy "$np" -n "$ns" -o jsonpath='{.spec.podSelector.matchLabels}' 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Allow ingress from specific pod ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! netpol_exists "allow-from-allowed" "$ns"; then
        fail_with_cmd "NetworkPolicy allow-from-allowed not found" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    # Wait for pods to be ready
    sleep 2

    local server_ip
    server_ip=$(get_pod_ip "server" "$ns")

    # Test allowed-client can reach server
    if test_connectivity "allowed-client" "$ns" "$server_ip"; then
        pass "allowed-client can reach server (ALLOWED)"
    else
        fail_with_cmd "allowed-client cannot reach server (should be ALLOWED)" \
            "kubectl describe networkpolicy allow-from-allowed -n $ns"
    fi

    # Test blocked-client is blocked
    if ! test_connectivity "blocked-client" "$ns" "$server_ip"; then
        pass "blocked-client is blocked (EXPECTED)"
    else
        fail_with_cmd "blocked-client can reach server (should be BLOCKED)" \
            "kubectl get pod blocked-client -n $ns --show-labels"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Control egress from pod ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! netpol_exists "restrict-egress" "$ns"; then
        fail_with_cmd "NetworkPolicy restrict-egress not found" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    sleep 2

    local target_a_ip target_b_ip
    target_a_ip=$(get_pod_ip "target-a" "$ns")
    target_b_ip=$(get_pod_ip "target-b" "$ns")

    # Test restricted-pod can reach target-a
    if test_connectivity "restricted-pod" "$ns" "$target_a_ip"; then
        pass "restricted-pod can reach target-a (ALLOWED)"
    else
        fail_with_cmd "restricted-pod cannot reach target-a (should be ALLOWED)" \
            "kubectl describe networkpolicy restrict-egress -n $ns"
    fi

    # Test restricted-pod is blocked from target-b
    if ! test_connectivity "restricted-pod" "$ns" "$target_b_ip"; then
        pass "restricted-pod cannot reach target-b (BLOCKED as expected)"
    else
        fail_with_cmd "restricted-pod can reach target-b (should be BLOCKED)" \
            "kubectl get pod target-b -n $ns --show-labels"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Deny all ingress policy ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check for a deny-all policy (name may vary)
    local policy_count
    policy_count=$(kubectl get networkpolicy -n "$ns" -o json | jq -r '.items | length' 2>/dev/null || echo "0")

    if [[ "$policy_count" -eq 0 ]]; then
        fail_with_cmd "No NetworkPolicy found in $ns" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    sleep 2

    local web_ip
    web_ip=$(get_pod_ip "webserver" "$ns")

    # Test tester is blocked from webserver
    if ! test_connectivity "tester" "$ns" "$web_ip"; then
        pass "tester cannot reach webserver (deny-all policy working)"
    else
        fail_with_cmd "tester can still reach webserver (policy should deny all ingress)" \
            "kubectl describe networkpolicy -n $ns"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Multiple label selector ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! netpol_exists "protect-prod" "$ns"; then
        fail_with_cmd "NetworkPolicy protect-prod not found" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    sleep 2

    local prod_ip dev_ip
    prod_ip=$(get_pod_ip "api-prod" "$ns")
    dev_ip=$(get_pod_ip "api-dev" "$ns")

    # Test api-prod is blocked
    if ! test_connectivity "client" "$ns" "$prod_ip"; then
        pass "api-prod is blocked (EXPECTED)"
    else
        fail_with_cmd "client can reach api-prod (should be BLOCKED)" \
            "kubectl describe networkpolicy protect-prod -n $ns"
    fi

    # Test api-dev is still accessible
    if test_connectivity "client" "$ns" "$dev_ip"; then
        pass "api-dev is accessible (ALLOWED)"
    else
        fail_with_cmd "client cannot reach api-dev (should be ALLOWED)" \
            "kubectl get pod api-dev -n $ns --show-labels"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Multiple from entries (OR logic) ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! netpol_exists "backend-access" "$ns"; then
        fail_with_cmd "NetworkPolicy backend-access not found" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    sleep 2

    local backend_ip
    backend_ip=$(get_pod_ip "backend" "$ns")

    # Test web-client is allowed
    if test_connectivity "web-client" "$ns" "$backend_ip"; then
        pass "web-client can reach backend (ALLOWED)"
    else
        fail_with_cmd "web-client cannot reach backend (should be ALLOWED)" \
            "kubectl describe networkpolicy backend-access -n $ns"
    fi

    # Test admin-client is allowed
    if test_connectivity "admin-client" "$ns" "$backend_ip"; then
        pass "admin-client can reach backend (ALLOWED)"
    else
        fail_with_cmd "admin-client cannot reach backend (should be ALLOWED)" \
            "kubectl describe networkpolicy backend-access -n $ns"
    fi

    # Test other-client is blocked
    if ! test_connectivity "other-client" "$ns" "$backend_ip"; then
        pass "other-client is blocked (EXPECTED)"
    else
        fail_with_cmd "other-client can reach backend (should be BLOCKED)" \
            "kubectl get pod other-client -n $ns --show-labels"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Port filtering ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! netpol_exists "http-only" "$ns"; then
        fail_with_cmd "NetworkPolicy http-only not found" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    sleep 2

    local server_ip
    server_ip=$(get_pod_ip "multi-port-server" "$ns")

    # Test port 80 is allowed
    if test_connectivity "client" "$ns" "$server_ip" 80; then
        pass "Port 80 is accessible (ALLOWED)"
    else
        fail_with_cmd "Port 80 is blocked (should be ALLOWED)" \
            "kubectl describe networkpolicy http-only -n $ns"
    fi

    # Test port 6379 is blocked
    if ! test_tcp_connectivity "client" "$ns" "$server_ip" 6379; then
        pass "Port 6379 is blocked (EXPECTED)"
    else
        fail_with_cmd "Port 6379 is accessible (should be BLOCKED)" \
            "kubectl describe networkpolicy http-only -n $ns | grep -A5 ports"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug too restrictive policy ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    sleep 2

    local api_ip
    api_ip=$(get_pod_ip "api-server" "$ns")

    # After fix, frontend should reach api-server
    if test_connectivity "frontend" "$ns" "$api_ip"; then
        pass "frontend can reach api-server (issue fixed)"
    else
        fail_with_cmd "frontend cannot reach api-server (needs label fix)" \
            "kubectl get pod frontend -n $ns --show-labels; kubectl describe networkpolicy api-policy -n $ns"
        info "Hint: Check if frontend pod labels match the policy's from selector"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug selector not matching ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    sleep 2

    local db_ip
    db_ip=$(get_pod_ip "database" "$ns")

    # After fix, backend should be blocked (policy should be protecting database)
    if ! test_connectivity "backend" "$ns" "$db_ip"; then
        pass "Policy is now protecting database (backend blocked)"
    else
        # Policy may not be matching - check if it was fixed
        local selector
        selector=$(get_netpol_selector "db-policy" "$ns")
        if [[ "$selector" == *"mysql"* ]]; then
            pass "Policy selector fixed to match database pod labels"
        else
            fail_with_cmd "Policy podSelector still not matching database pod" \
                "kubectl get pod database -n $ns --show-labels; kubectl describe networkpolicy db-policy -n $ns"
            info "Hint: Database pod has app=mysql, but policy may be selecting app=database"
        fi
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug wrong port ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    sleep 2

    local web_ip
    web_ip=$(get_pod_ip "webserver" "$ns")

    # After fix, client should reach webserver on port 80
    if test_connectivity "client" "$ns" "$web_ip" 80; then
        pass "client can reach webserver on port 80 (port fixed)"
    else
        fail_with_cmd "client cannot reach webserver on port 80 (port mismatch)" \
            "kubectl describe networkpolicy web-policy -n $ns | grep -A5 ports"
        info "Hint: Policy allows port 8080, but webserver listens on port 80"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Combined ingress and egress ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! netpol_exists "api-rules" "$ns"; then
        fail_with_cmd "NetworkPolicy api-rules not found" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    sleep 2

    local api_ip db_ip
    api_ip=$(get_pod_ip "api" "$ns")
    db_ip=$(get_pod_ip "database" "$ns")

    # Test frontend -> api (ingress rule)
    if test_connectivity "frontend" "$ns" "$api_ip"; then
        pass "frontend can reach api (ingress allowed)"
    else
        fail_with_cmd "frontend cannot reach api (ingress should be allowed)" \
            "kubectl describe networkpolicy api-rules -n $ns"
    fi

    # Test api -> database (egress rule)
    if test_connectivity "api" "$ns" "$db_ip"; then
        pass "api can reach database (egress allowed)"
    else
        fail_with_cmd "api cannot reach database (egress should be allowed)" \
            "kubectl describe networkpolicy api-rules -n $ns"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Multiple protocols on same port ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! netpol_exists "dns-access" "$ns"; then
        fail_with_cmd "NetworkPolicy dns-access not found" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    # Check policy has both TCP and UDP for port 53
    local policy_ports
    policy_ports=$(kubectl describe networkpolicy dns-access -n "$ns" 2>/dev/null | grep -A10 "Allowing ingress" || echo "")

    if [[ "$policy_ports" == *"TCP"* ]] && [[ "$policy_ports" == *"53"* ]]; then
        pass "Policy allows TCP port 53"
    else
        fail_with_cmd "Policy does not allow TCP port 53" \
            "kubectl describe networkpolicy dns-access -n $ns"
    fi

    if [[ "$policy_ports" == *"UDP"* ]] && [[ "$policy_ports" == *"53"* ]]; then
        pass "Policy allows UDP port 53"
    else
        fail_with_cmd "Policy does not allow UDP port 53" \
            "kubectl describe networkpolicy dns-access -n $ns"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Named ports ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! netpol_exists "http-access" "$ns"; then
        fail_with_cmd "NetworkPolicy http-access not found" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    sleep 2

    local server_ip
    server_ip=$(get_pod_ip "app-server" "$ns")

    # Test http port (80) is allowed
    if test_connectivity "client" "$ns" "$server_ip" 80; then
        pass "http port (80) is accessible (ALLOWED)"
    else
        fail_with_cmd "http port (80) is blocked (should be ALLOWED)" \
            "kubectl describe networkpolicy http-access -n $ns"
    fi

    # Test https port (443) is blocked
    if ! test_tcp_connectivity "client" "$ns" "$server_ip" 443; then
        pass "https port (443) is blocked (EXPECTED)"
    else
        fail_with_cmd "https port (443) is accessible (should be BLOCKED)" \
            "kubectl describe networkpolicy http-access -n $ns | grep -A5 ports"
    fi

    # Verify named port is used in policy
    local policy_spec
    policy_spec=$(kubectl get networkpolicy http-access -n "$ns" -o yaml 2>/dev/null || echo "")
    if [[ "$policy_spec" == *"port: http"* ]]; then
        pass "Policy uses named port 'http'"
    else
        info "Policy may use port number instead of named port"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multi-tier web application ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check for required policies
    local policy_count
    policy_count=$(kubectl get networkpolicy -n "$ns" -o json | jq -r '.items | length' 2>/dev/null || echo "0")

    if [[ "$policy_count" -lt 1 ]]; then
        fail_with_cmd "No NetworkPolicies found in $ns" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    sleep 2

    local frontend_ip backend_ip
    frontend_ip=$(get_pod_ip "frontend" "$ns")
    backend_ip=$(get_pod_ip "backend" "$ns")

    # Test external -> frontend (should work)
    if test_connectivity "external-client" "$ns" "$frontend_ip"; then
        pass "external-client can reach frontend (ALLOWED)"
    else
        fail_with_cmd "external-client cannot reach frontend (should be ALLOWED)" \
            "kubectl describe networkpolicy -n $ns"
    fi

    # Test frontend -> backend (should work)
    if test_connectivity "frontend" "$ns" "$backend_ip"; then
        pass "frontend can reach backend (ALLOWED)"
    else
        fail_with_cmd "frontend cannot reach backend (should be ALLOWED)" \
            "kubectl describe networkpolicy -n $ns"
    fi

    # Test external -> backend (should be blocked)
    if ! test_connectivity "external-client" "$ns" "$backend_ip"; then
        pass "external-client cannot reach backend directly (BLOCKED as expected)"
    else
        fail_with_cmd "external-client can reach backend directly (should be BLOCKED)" \
            "kubectl describe networkpolicy -n $ns"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug policy blocking expected traffic ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    sleep 2

    local service_a_ip
    service_a_ip=$(get_pod_ip "service-a" "$ns")

    # After fix, service-b should reach service-a
    if test_connectivity "service-b" "$ns" "$service_a_ip"; then
        pass "service-b can reach service-a (label added or policy fixed)"
    else
        fail_with_cmd "service-b cannot reach service-a (needs allowed=true label)" \
            "kubectl get pod service-b -n $ns --show-labels; kubectl describe networkpolicy service-a-policy -n $ns"
        info "Hint: service-b needs the allowed=true label to match policy's from selector"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Three-tier application design ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check for multiple policies
    local policy_count
    policy_count=$(kubectl get networkpolicy -n "$ns" -o json | jq -r '.items | length' 2>/dev/null || echo "0")

    if [[ "$policy_count" -lt 2 ]]; then
        fail_with_cmd "Expected at least 2 NetworkPolicies in $ns (found $policy_count)" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    sleep 2

    local web_ip api_ip db_ip
    web_ip=$(get_pod_ip "web" "$ns")
    api_ip=$(get_pod_ip "api" "$ns")
    db_ip=$(get_pod_ip "db" "$ns")

    # Test tester -> web (should work)
    if test_connectivity "tester" "$ns" "$web_ip"; then
        pass "tester can reach web (ALLOWED)"
    else
        fail_with_cmd "tester cannot reach web (should be ALLOWED)" \
            "kubectl describe networkpolicy -n $ns"
    fi

    # Test web -> api (should work)
    if test_connectivity "web" "$ns" "$api_ip"; then
        pass "web can reach api (ALLOWED)"
    else
        fail_with_cmd "web cannot reach api (should be ALLOWED)" \
            "kubectl describe networkpolicy -n $ns"
    fi

    # Test api -> db (should work)
    if test_connectivity "api" "$ns" "$db_ip"; then
        pass "api can reach db (ALLOWED)"
    else
        fail_with_cmd "api cannot reach db (should be ALLOWED)" \
            "kubectl describe networkpolicy -n $ns"
    fi

    # Test tester -> api (should be blocked)
    if ! test_connectivity "tester" "$ns" "$api_ip"; then
        pass "tester cannot reach api directly (BLOCKED as expected)"
    else
        fail_with_cmd "tester can reach api directly (should be BLOCKED)" \
            "kubectl describe networkpolicy -n $ns"
    fi

    # Test tester -> db (should be blocked)
    if ! test_connectivity "tester" "$ns" "$db_ip"; then
        pass "tester cannot reach db directly (BLOCKED as expected)"
    else
        fail_with_cmd "tester can reach db directly (should be BLOCKED)" \
            "kubectl describe networkpolicy -n $ns"
    fi

    # Test web -> db (should be blocked - must go through api)
    if ! test_connectivity "web" "$ns" "$db_ip"; then
        pass "web cannot reach db directly (BLOCKED as expected)"
    else
        fail_with_cmd "web can reach db directly (should be BLOCKED - must go through api)" \
            "kubectl describe networkpolicy -n $ns"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic Policy Creation"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Pod Selection and Rules"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Policy Effects"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Combined Rules"
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
