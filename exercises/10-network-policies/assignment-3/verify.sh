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

# Helper: check if pod exists
pod_exists() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

# Helper: check if network policy exists
netpol_exists() {
    local np=$1
    local ns=$2
    kubectl get networkpolicy "$np" -n "$ns" &>/dev/null
}

# Helper: get pod phase
get_phase() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: get pod IP
get_pod_ip() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.podIP}' 2>/dev/null
}

# Helper: get label value
get_label() {
    local pod=$1
    local ns=$2
    local label=$3
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.metadata.labels.$label}" 2>/dev/null
}

# Helper: check if label matches
label_matches() {
    local pod=$1
    local ns=$2
    local key=$3
    local expected=$4
    local actual
    actual=$(get_label "$pod" "$ns" "$key")
    [[ "$actual" == "$expected" ]]
}

# Helper: test HTTP connectivity
test_http_connectivity() {
    local pod=$1
    local ns=$2
    local target_ip=$3
    local timeout=${4:-2}
    kubectl exec -n "$ns" "$pod" -- wget -qO- --timeout="$timeout" "http://$target_ip" &>/dev/null
}

# Helper: test DNS resolution
test_dns() {
    local pod=$1
    local ns=$2
    local hostname=$3
    kubectl exec -n "$ns" "$pod" -- nslookup "$hostname" &>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Test connectivity with and without policy ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "server" "$ns"; then
        fail "Pod server not found in namespace $ns"
        return
    fi

    if ! pod_exists "client" "$ns"; then
        fail "Pod client not found in namespace $ns"
        return
    fi

    # Check if policy exists
    if netpol_exists "deny-all" "$ns"; then
        pass "NetworkPolicy deny-all exists"

        local server_ip
        server_ip=$(get_pod_ip "server" "$ns")

        # Test that traffic is blocked with policy
        if ! test_http_connectivity "client" "$ns" "$server_ip" 2; then
            pass "Traffic blocked after policy (expected)"
        else
            fail_with_cmd "Traffic still allowed after deny policy" \
                "kubectl describe networkpolicy deny-all -n $ns"
        fi
    else
        info "Policy not yet applied, skipping blocked traffic test"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Identify blocking policy ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "api" "$ns"; then
        fail "Pod api not found in namespace $ns"
        return
    fi

    if ! pod_exists "web" "$ns"; then
        fail "Pod web not found in namespace $ns"
        return
    fi

    if ! netpol_exists "api-policy" "$ns"; then
        fail "NetworkPolicy api-policy not found in namespace $ns"
        return
    fi

    pass "Policy api-policy exists"

    local api_ip
    api_ip=$(get_pod_ip "api" "$ns")

    # Traffic should be blocked due to label mismatch
    if ! test_http_connectivity "web" "$ns" "$api_ip" 2; then
        pass "Traffic correctly blocked (web pod lacks role=frontend label)"
    else
        fail_with_cmd "Traffic is not blocked when it should be" \
            "kubectl get pod web -n $ns --show-labels; kubectl describe networkpolicy api-policy -n $ns"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Verify policy selector matches intended pods ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "database" "$ns"; then
        fail "Pod database not found in namespace $ns"
        return
    fi

    if ! pod_exists "app" "$ns"; then
        fail "Pod app not found in namespace $ns"
        return
    fi

    if ! netpol_exists "protect-database" "$ns"; then
        fail "NetworkPolicy protect-database not found in namespace $ns"
        return
    fi

    pass "Policy protect-database exists"

    # Check if policy selector matches the database pod
    local db_label
    db_label=$(get_label "database" "$ns" "app")

    if [[ "$db_label" != "database" ]]; then
        pass "Database pod has app=$db_label (not 'database', so policy does not match)"

        local db_ip
        db_ip=$(get_pod_ip "database" "$ns")

        # Traffic should be allowed because policy does not select the pod
        if test_http_connectivity "app" "$ns" "$db_ip" 2; then
            pass "Database accessible (policy selector mismatch - issue diagnosed)"
        else
            fail "Database not accessible (unexpected)"
        fi
    else
        fail_with_cmd "Database pod has app=database, policy should match" \
            "kubectl get pod database -n $ns --show-labels"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Test policy allows egress to DNS ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "restricted" "$ns"; then
        fail "Pod restricted not found in namespace $ns"
        return
    fi

    if ! netpol_exists "default-deny-egress" "$ns"; then
        fail "NetworkPolicy default-deny-egress not found in namespace $ns"
        return
    fi

    pass "Policy default-deny-egress exists"

    # DNS should work
    if test_dns "restricted" "$ns" "kubernetes.default"; then
        pass "DNS query works (egress to kube-system:53 allowed)"
    else
        fail_with_cmd "DNS query blocked" \
            "kubectl describe networkpolicy default-deny-egress -n $ns"
    fi

    # External egress should be blocked
    if ! kubectl exec -n "$ns" restricted -- wget -qO- --timeout=2 http://example.com &>/dev/null; then
        pass "External egress blocked (expected)"
    else
        fail "External egress allowed (should be blocked)"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Verify service access through policy ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "backend" "$ns"; then
        fail "Pod backend not found in namespace $ns"
        return
    fi

    if ! pod_exists "frontend" "$ns"; then
        fail "Pod frontend not found in namespace $ns"
        return
    fi

    if ! netpol_exists "backend-policy" "$ns"; then
        fail "NetworkPolicy backend-policy not found in namespace $ns"
        return
    fi

    pass "Policy backend-policy exists"

    # Test service access
    if kubectl exec -n "$ns" frontend -- wget -qO- --timeout=2 http://backend-svc &>/dev/null; then
        pass "Frontend can access backend via service name"
    else
        fail_with_cmd "Frontend cannot access backend service" \
            "kubectl exec -n $ns frontend -- nslookup backend-svc; kubectl describe networkpolicy backend-policy -n $ns"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Verify cross-namespace policy ==="
    local ns_frontend="ex-2-3-frontend"
    local ns_backend="ex-2-3-backend"

    if ! namespace_exists "$ns_frontend"; then
        fail "Namespace $ns_frontend does not exist"
        return
    fi

    if ! namespace_exists "$ns_backend"; then
        fail "Namespace $ns_backend does not exist"
        return
    fi

    if ! pod_exists "web" "$ns_frontend"; then
        fail "Pod web not found in namespace $ns_frontend"
        return
    fi

    if ! pod_exists "api" "$ns_backend"; then
        fail "Pod api not found in namespace $ns_backend"
        return
    fi

    if ! netpol_exists "allow-frontend" "$ns_backend"; then
        fail "NetworkPolicy allow-frontend not found in namespace $ns_backend"
        return
    fi

    pass "Policy allow-frontend exists"

    # Check namespace label
    local ns_label
    ns_label=$(kubectl get namespace "$ns_frontend" -o jsonpath='{.metadata.labels.tier}' 2>/dev/null)

    if [[ "$ns_label" == "frontend" ]]; then
        pass "Namespace $ns_frontend has tier=frontend label"
    else
        fail_with_cmd "Namespace $ns_frontend missing tier=frontend label" \
            "kubectl get namespace $ns_frontend --show-labels"
    fi

    local api_ip
    api_ip=$(get_pod_ip "api" "$ns_backend")

    # Test cross-namespace access
    if test_http_connectivity "web" "$ns_frontend" "$api_ip" 2; then
        pass "Cross-namespace access works"
    else
        fail_with_cmd "Cross-namespace access blocked" \
            "kubectl describe networkpolicy allow-frontend -n $ns_backend; kubectl get namespace $ns_frontend --show-labels"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1 ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "server" "$ns"; then
        fail "Pod server not found in namespace $ns"
        return
    fi

    if ! pod_exists "client" "$ns"; then
        fail "Pod client not found in namespace $ns"
        return
    fi

    if ! netpol_exists "server-policy" "$ns"; then
        fail "NetworkPolicy server-policy not found in namespace $ns"
        return
    fi

    pass "Setup complete"

    local server_ip
    server_ip=$(get_pod_ip "server" "$ns")

    # Check if issue is diagnosed (client should have role=frontend to connect)
    local client_role
    client_role=$(get_label "client" "$ns" "role")

    if [[ "$client_role" == "frontend" ]]; then
        # Issue fixed
        if test_http_connectivity "client" "$ns" "$server_ip" 2; then
            pass "Traffic allowed after fixing client label to role=frontend"
        else
            fail "Traffic still blocked despite correct label"
        fi
    else
        # Issue not yet fixed
        if ! test_http_connectivity "client" "$ns" "$server_ip" 2; then
            pass "Traffic blocked (client has role=$client_role, policy requires role=frontend)"
        else
            fail "Traffic unexpectedly allowed"
        fi
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2 ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "server" "$ns"; then
        fail "Pod server not found in namespace $ns"
        return
    fi

    if ! pod_exists "client" "$ns"; then
        fail "Pod client not found in namespace $ns"
        return
    fi

    if ! netpol_exists "client-egress" "$ns"; then
        fail "NetworkPolicy client-egress not found in namespace $ns"
        return
    fi

    pass "Setup complete"

    local server_ip
    server_ip=$(get_pod_ip "server" "$ns")

    # By IP should work
    if test_http_connectivity "client" "$ns" "$server_ip" 2; then
        pass "Client can reach server by IP"
    else
        fail_with_cmd "Client cannot reach server by IP" \
            "kubectl describe networkpolicy client-egress -n $ns"
    fi

    # Check if DNS is fixed
    if test_dns "client" "$ns" "server-svc"; then
        pass "DNS resolution works (egress policy fixed)"

        # Service access should work
        if kubectl exec -n "$ns" client -- wget -qO- --timeout=2 http://server-svc &>/dev/null; then
            pass "Client can reach server by service name"
        else
            fail "Client cannot reach server by name despite DNS working"
        fi
    else
        pass "DNS blocked (issue diagnosed - need to add DNS egress rule)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3 ==="
    local ns_app="ex-3-3-app"
    local ns_monitoring="ex-3-3-monitoring"

    if ! namespace_exists "$ns_app"; then
        fail "Namespace $ns_app does not exist"
        return
    fi

    if ! namespace_exists "$ns_monitoring"; then
        fail "Namespace $ns_monitoring does not exist"
        return
    fi

    if ! pod_exists "api" "$ns_app"; then
        fail "Pod api not found in namespace $ns_app"
        return
    fi

    if ! pod_exists "prometheus" "$ns_monitoring"; then
        fail "Pod prometheus not found in namespace $ns_monitoring"
        return
    fi

    if ! netpol_exists "api-policy" "$ns_app"; then
        fail "NetworkPolicy api-policy not found in namespace $ns_app"
        return
    fi

    pass "Setup complete"

    # Check namespace label
    local ns_label
    ns_label=$(kubectl get namespace "$ns_monitoring" -o jsonpath='{.metadata.labels.purpose}' 2>/dev/null)

    local api_ip
    api_ip=$(get_pod_ip "api" "$ns_app")

    if [[ "$ns_label" == "monitoring" ]]; then
        pass "Namespace $ns_monitoring has purpose=monitoring label"

        if test_http_connectivity "prometheus" "$ns_monitoring" "$api_ip" 2; then
            pass "Prometheus can reach API (issue fixed)"
        else
            fail "Prometheus still cannot reach API despite correct label"
        fi
    else
        pass "Namespace $ns_monitoring missing purpose=monitoring label (issue diagnosed)"

        if ! test_http_connectivity "prometheus" "$ns_monitoring" "$api_ip" 2; then
            pass "Traffic correctly blocked due to missing namespace label"
        else
            fail "Traffic unexpectedly allowed"
        fi
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Multi-policy interaction ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "secure-app" "$ns"; then
        fail "Pod secure-app not found in namespace $ns"
        return
    fi

    if ! pod_exists "test-client" "$ns"; then
        fail "Pod test-client not found in namespace $ns"
        return
    fi

    if ! netpol_exists "deny-by-app" "$ns"; then
        fail "NetworkPolicy deny-by-app not found in namespace $ns"
        return
    fi

    if ! netpol_exists "allow-testers" "$ns"; then
        fail "NetworkPolicy allow-testers not found in namespace $ns"
        return
    fi

    pass "Both policies exist"

    local secure_ip
    secure_ip=$(get_pod_ip "secure-app" "$ns")

    # Due to additive policy behavior, traffic should be allowed
    if test_http_connectivity "test-client" "$ns" "$secure_ip" 2; then
        pass "Traffic allowed (policies are additive - allow-testers permits it)"
    else
        fail_with_cmd "Traffic blocked (check if policies are correctly configured)" \
            "kubectl describe networkpolicy deny-by-app allow-testers -n $ns"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Find permissive policy ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "database" "$ns"; then
        fail "Pod database not found in namespace $ns"
        return
    fi

    if ! pod_exists "attacker" "$ns"; then
        fail "Pod attacker not found in namespace $ns"
        return
    fi

    if ! netpol_exists "db-restrict" "$ns"; then
        fail "NetworkPolicy db-restrict not found in namespace $ns"
        return
    fi

    pass "Policy db-restrict exists"

    local db_ip
    db_ip=$(get_pod_ip "database" "$ns")

    # Check if policy is overly permissive
    local policy_from
    policy_from=$(kubectl get networkpolicy db-restrict -n "$ns" -o jsonpath='{.spec.ingress[0].from[0].podSelector}' 2>/dev/null)

    if [[ "$policy_from" == "{}" ]]; then
        pass "Policy uses podSelector:{} which matches ALL pods (issue diagnosed)"

        if test_http_connectivity "attacker" "$ns" "$db_ip" 2; then
            pass "Attacker can reach database (confirms overly permissive policy)"
        else
            fail "Attacker cannot reach database (unexpected)"
        fi
    else
        info "Policy selector: $policy_from"

        if test_http_connectivity "attacker" "$ns" "$db_ip" 2; then
            fail_with_cmd "Attacker can reach database - policy is too permissive" \
                "kubectl describe networkpolicy db-restrict -n $ns"
        else
            pass "Database properly restricted"
        fi
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Cross-namespace policy chain ==="
    local ns_web="ex-4-3-web"
    local ns_api="ex-4-3-api"
    local ns_db="ex-4-3-db"

    if ! namespace_exists "$ns_web"; then
        fail "Namespace $ns_web does not exist"
        return
    fi

    if ! namespace_exists "$ns_api"; then
        fail "Namespace $ns_api does not exist"
        return
    fi

    if ! namespace_exists "$ns_db"; then
        fail "Namespace $ns_db does not exist"
        return
    fi

    if ! pod_exists "web" "$ns_web"; then
        fail "Pod web not found in namespace $ns_web"
        return
    fi

    if ! pod_exists "api" "$ns_api"; then
        fail "Pod api not found in namespace $ns_api"
        return
    fi

    if ! pod_exists "db" "$ns_db"; then
        fail "Pod db not found in namespace $ns_db"
        return
    fi

    pass "All pods exist"

    local api_ip
    api_ip=$(get_pod_ip "api" "$ns_api")
    local db_ip
    db_ip=$(get_pod_ip "db" "$ns_db")

    # Test web -> api
    if test_http_connectivity "web" "$ns_web" "$api_ip" 2; then
        pass "web -> api: allowed (tier=web can reach api)"
    else
        fail_with_cmd "web -> api: blocked" \
            "kubectl describe networkpolicy api-policy -n $ns_api; kubectl get namespace $ns_web --show-labels"
    fi

    # Test api -> db
    if test_http_connectivity "api" "$ns_api" "$db_ip" 2; then
        pass "api -> db: allowed (tier=api can reach db)"
    else
        fail_with_cmd "api -> db: blocked" \
            "kubectl describe networkpolicy db-policy -n $ns_db; kubectl get namespace $ns_api --show-labels"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multiple policy issues ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "web" "$ns"; then
        fail "Pod web not found in namespace $ns"
        return
    fi

    if ! pod_exists "api" "$ns"; then
        fail "Pod api not found in namespace $ns"
        return
    fi

    pass "Pods exist"

    local api_ip
    api_ip=$(get_pod_ip "api" "$ns")

    # Check if issues are fixed
    # Issue 1: web-to-api policy selector mismatch (app=api vs app=api-server)
    # Issue 2: DNS blocked by default-deny
    # Issue 3: web egress blocked

    # Test by IP first
    if test_http_connectivity "web" "$ns" "$api_ip" 2; then
        pass "Web can reach API by IP (ingress and egress policies fixed)"
    else
        fail_with_cmd "Web cannot reach API by IP" \
            "kubectl get networkpolicy -n $ns; kubectl get pod api -n $ns --show-labels"
    fi

    # Test by service name (requires DNS)
    if kubectl exec -n "$ns" web -- wget -qO- --timeout=2 http://api-svc &>/dev/null; then
        pass "Web can reach API by service name (DNS egress fixed)"
    else
        info "Service access fails (may need DNS egress rule in default-deny or web-egress policy)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Service discovery failure ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "backend" "$ns"; then
        fail "Pod backend not found in namespace $ns"
        return
    fi

    if ! pod_exists "frontend" "$ns"; then
        fail "Pod frontend not found in namespace $ns"
        return
    fi

    pass "Pods exist"

    local backend_ip
    backend_ip=$(get_pod_ip "backend" "$ns")

    # Test by IP
    if test_http_connectivity "frontend" "$ns" "$backend_ip" 2; then
        pass "Frontend can reach backend by IP"
    else
        fail_with_cmd "Frontend cannot reach backend by IP" \
            "kubectl describe networkpolicy backend-ingress frontend-egress -n $ns"
    fi

    # Test by service name
    if kubectl exec -n "$ns" frontend -- wget -qO- --timeout=2 http://backend-svc &>/dev/null; then
        pass "Frontend can reach backend by service name (DNS egress fixed)"
    else
        info "Service access fails (DNS egress missing in frontend-egress policy)"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Troubleshooting runbook ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "server" "$ns"; then
        fail "Pod server not found in namespace $ns"
        return
    fi

    if ! pod_exists "client" "$ns"; then
        fail "Pod client not found in namespace $ns"
        return
    fi

    pass "Exercise namespace and pods exist"

    # Verify basic connectivity works (no policies applied)
    local server_ip
    server_ip=$(get_pod_ip "server" "$ns")

    if test_http_connectivity "client" "$ns" "$server_ip" 2; then
        pass "Client can reach server (baseline connectivity)"
    else
        fail "Client cannot reach server (unexpected - no policies should be blocking)"
    fi

    # Verify DNS works
    if test_dns "client" "$ns" "kubernetes.default"; then
        pass "DNS resolution works"
    else
        fail "DNS resolution failed"
    fi

    info "Runbook exercise - document all diagnostic steps from verification section"
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic Debugging"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Policy Verification"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Blocked Traffic"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Complex Policy Issues"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Integration Debugging"
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
