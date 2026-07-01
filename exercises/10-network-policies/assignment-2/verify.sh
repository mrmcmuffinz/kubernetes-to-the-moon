#!/usr/bin/env bash
#
# verify.sh - Automated verification for network-policies-homework.md (assignment 2)
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

# Helper: check if namespace has label
namespace_has_label() {
    local ns=$1
    local key=$2
    local value=$3
    local actual
    actual=$(kubectl get namespace "$ns" -o jsonpath="{.metadata.labels.$key}" 2>/dev/null || echo "")
    [[ "$actual" == "$value" ]]
}

# Helper: check if pod exists
pod_exists() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

# Helper: check if NetworkPolicy exists
netpol_exists() {
    local np=$1
    local ns=$2
    kubectl get networkpolicy "$np" -n "$ns" &>/dev/null
}

# Helper: get pod IP
get_pod_ip() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.podIP}' 2>/dev/null
}

# Helper: test connectivity (returns 0 if connection succeeds)
test_connectivity() {
    local from_pod=$1
    local from_ns=$2
    local to_ip=$3
    local timeout=${4:-2}

    timeout $((timeout + 1)) kubectl exec -n "$from_ns" "$from_pod" -- wget -qO- --timeout="$timeout" "http://$to_ip" &>/dev/null
}

# Helper: check NetworkPolicy has namespaceSelector
netpol_has_namespace_selector() {
    local np=$1
    local ns=$2
    local json
    json=$(kubectl get networkpolicy "$np" -n "$ns" -o json 2>/dev/null)
    echo "$json" | grep -q "namespaceSelector"
}

# Helper: check NetworkPolicy has ipBlock
netpol_has_ipblock() {
    local np=$1
    local ns=$2
    local cidr=$3
    kubectl get networkpolicy "$np" -n "$ns" -o yaml 2>/dev/null | grep -A2 "ipBlock" | grep -q "$cidr"
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Allow ingress from specific namespace ==="
    local app_ns="ex-1-1-app"
    local mon_ns="ex-1-1-monitoring"

    if ! namespace_exists "$app_ns"; then
        fail "Namespace $app_ns does not exist"
        return
    fi

    if ! namespace_exists "$mon_ns"; then
        fail "Namespace $mon_ns does not exist"
        return
    fi

    if ! namespace_has_label "$mon_ns" "purpose" "monitoring"; then
        fail "Namespace $mon_ns does not have label purpose=monitoring"
        return
    fi

    if ! pod_exists "app" "$app_ns"; then
        fail "Pod app not found in namespace $app_ns"
        return
    fi

    local app_ip
    app_ip=$(get_pod_ip "app" "$app_ns")
    if [[ -z "$app_ip" ]]; then
        fail "Could not get IP for app pod"
        return
    fi

    # Check for NetworkPolicy
    local np_count
    np_count=$(kubectl get networkpolicy -n "$app_ns" -o name 2>/dev/null | wc -l)
    if [[ "$np_count" -eq 0 ]]; then
        fail_with_cmd "No NetworkPolicy found in namespace $app_ns" \
            "kubectl get networkpolicy -n $app_ns"
        return
    fi

    pass "NetworkPolicy exists in $app_ns"

    # Test connectivity from monitoring namespace (should work)
    if test_connectivity "monitor" "$mon_ns" "$app_ip" 3; then
        pass "Monitor pod (in monitoring namespace) can reach app"
    else
        fail_with_cmd "Monitor pod cannot reach app (should be allowed)" \
            "kubectl exec -n $mon_ns monitor -- wget -qO- --timeout=2 http://$app_ip"
    fi

    # Test connectivity from attacker in same namespace (should be blocked)
    if test_connectivity "attacker" "$app_ns" "$app_ip" 3; then
        fail "Attacker pod (in same namespace) can reach app (should be blocked)"
    else
        pass "Attacker pod in same namespace is blocked"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Allow egress to specific namespace ==="
    local frontend_ns="ex-1-2-frontend"
    local backend_ns="ex-1-2-backend"

    if ! namespace_exists "$frontend_ns"; then
        fail "Namespace $frontend_ns does not exist"
        return
    fi

    if ! namespace_exists "$backend_ns"; then
        fail "Namespace $backend_ns does not exist"
        return
    fi

    if ! namespace_has_label "$backend_ns" "tier" "backend"; then
        fail "Namespace $backend_ns does not have label tier=backend"
        return
    fi

    local api_ip other_ip
    api_ip=$(get_pod_ip "api" "$backend_ns")
    other_ip=$(get_pod_ip "other" "$frontend_ns")

    if [[ -z "$api_ip" ]] || [[ -z "$other_ip" ]]; then
        fail "Could not get pod IPs"
        return
    fi

    # Check for NetworkPolicy
    local np_count
    np_count=$(kubectl get networkpolicy -n "$frontend_ns" -o name 2>/dev/null | wc -l)
    if [[ "$np_count" -eq 0 ]]; then
        fail_with_cmd "No NetworkPolicy found in namespace $frontend_ns" \
            "kubectl get networkpolicy -n $frontend_ns"
        return
    fi

    pass "NetworkPolicy exists in $frontend_ns"

    # Test egress to backend (should work)
    if test_connectivity "web" "$frontend_ns" "$api_ip" 3; then
        pass "Web pod can reach API in backend namespace"
    else
        fail_with_cmd "Web pod cannot reach backend (should be allowed)" \
            "kubectl exec -n $frontend_ns web -- wget -qO- --timeout=2 http://$api_ip"
    fi

    # Test egress to same namespace (should be blocked)
    if test_connectivity "web" "$frontend_ns" "$other_ip" 3; then
        fail "Web pod can reach other pod in same namespace (should be blocked)"
    else
        pass "Web pod egress to same namespace is blocked"
    fi

    # Test DNS access
    if kubectl exec -n "$frontend_ns" web -- nslookup kubernetes.default &>/dev/null; then
        pass "DNS access works"
    else
        fail "DNS access blocked (should be allowed)"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Use kubernetes.io/metadata.name label ==="
    local prod_ns="ex-1-3-prod"
    local dev_ns="ex-1-3-dev"

    if ! namespace_exists "$prod_ns"; then
        fail "Namespace $prod_ns does not exist"
        return
    fi

    if ! namespace_exists "$dev_ns"; then
        fail "Namespace $dev_ns does not exist"
        return
    fi

    local service_ip
    service_ip=$(get_pod_ip "service" "$prod_ns")

    if [[ -z "$service_ip" ]]; then
        fail "Could not get service pod IP"
        return
    fi

    # Check for NetworkPolicy using kubernetes.io/metadata.name
    local np_yaml
    np_yaml=$(kubectl get networkpolicy -n "$prod_ns" -o yaml 2>/dev/null)
    if echo "$np_yaml" | grep -q "kubernetes.io/metadata.name"; then
        pass "NetworkPolicy uses kubernetes.io/metadata.name label"
    else
        fail_with_cmd "NetworkPolicy does not use kubernetes.io/metadata.name label" \
            "kubectl get networkpolicy -n $prod_ns -o yaml"
    fi

    # Test connectivity from dev namespace (should work)
    if test_connectivity "dev-client" "$dev_ns" "$service_ip" 3; then
        pass "Dev client can reach service in prod namespace"
    else
        fail_with_cmd "Dev client cannot reach service (should be allowed)" \
            "kubectl exec -n $dev_ns dev-client -- wget -qO- --timeout=2 http://$service_ip"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Combined pod and namespace selectors ==="
    local target_ns="ex-2-1-target"
    local source_ns="ex-2-1-source"

    if ! namespace_exists "$target_ns" || ! namespace_exists "$source_ns"; then
        fail "Required namespaces do not exist"
        return
    fi

    if ! namespace_has_label "$source_ns" "env" "trusted"; then
        fail "Namespace $source_ns does not have label env=trusted"
        return
    fi

    local server_ip
    server_ip=$(get_pod_ip "server" "$target_ns")

    if [[ -z "$server_ip" ]]; then
        fail "Could not get server pod IP"
        return
    fi

    # Check for NetworkPolicy
    local np_count
    np_count=$(kubectl get networkpolicy -n "$target_ns" -o name 2>/dev/null | wc -l)
    if [[ "$np_count" -eq 0 ]]; then
        fail_with_cmd "No NetworkPolicy found in namespace $target_ns" \
            "kubectl get networkpolicy -n $target_ns"
        return
    fi

    pass "NetworkPolicy exists in $target_ns"

    # Test trusted-app (both namespace and pod labels match - should work)
    if test_connectivity "trusted-app" "$source_ns" "$server_ip" 3; then
        pass "Trusted-app (matching both selectors) can reach server"
    else
        fail_with_cmd "Trusted-app cannot reach server (should be allowed)" \
            "kubectl exec -n $source_ns trusted-app -- wget -qO- --timeout=2 http://$server_ip"
    fi

    # Test untrusted-app (namespace matches but pod label doesn't - should be blocked)
    if test_connectivity "untrusted-app" "$source_ns" "$server_ip" 3; then
        fail "Untrusted-app can reach server (should be blocked by AND logic)"
    else
        pass "Untrusted-app is blocked (AND selector working correctly)"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: ipBlock for CIDR ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "external-facing" "$ns"; then
        fail "Pod external-facing not found in namespace $ns"
        return
    fi

    # Check for NetworkPolicy with ipBlock
    local np_count
    np_count=$(kubectl get networkpolicy -n "$ns" -o name 2>/dev/null | wc -l)
    if [[ "$np_count" -eq 0 ]]; then
        fail_with_cmd "No NetworkPolicy found in namespace $ns" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    pass "NetworkPolicy exists in $ns"

    # Check for ipBlock configuration
    if netpol_has_ipblock "$(kubectl get networkpolicy -n "$ns" -o name | head -1 | cut -d/ -f2)" "$ns" "10.0.0.0/8"; then
        pass "NetworkPolicy contains ipBlock with CIDR 10.0.0.0/8"
    else
        fail_with_cmd "NetworkPolicy does not contain expected ipBlock CIDR" \
            "kubectl describe networkpolicy -n $ns | grep -A5 ipBlock"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: ipBlock with except ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "api-server" "$ns"; then
        fail "Pod api-server not found in namespace $ns"
        return
    fi

    # Check for NetworkPolicy with ipBlock and except
    local np_yaml
    np_yaml=$(kubectl get networkpolicy -n "$ns" -o yaml 2>/dev/null)

    if echo "$np_yaml" | grep -q "192.168.0.0/16"; then
        pass "NetworkPolicy contains CIDR 192.168.0.0/16"
    else
        fail_with_cmd "NetworkPolicy does not contain expected CIDR" \
            "kubectl describe networkpolicy -n $ns"
        return
    fi

    if echo "$np_yaml" | grep -A2 "except" | grep -q "192.168.100.0/24"; then
        pass "NetworkPolicy contains except clause for 192.168.100.0/24"
    else
        fail_with_cmd "NetworkPolicy does not contain expected except clause" \
            "kubectl describe networkpolicy -n $ns | grep -A10 ipBlock"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug namespace label issue ==="
    local server_ns="ex-3-1-server"
    local client_ns="ex-3-1-client"

    if ! namespace_exists "$server_ns" || ! namespace_exists "$client_ns"; then
        fail "Required namespaces do not exist"
        return
    fi

    local server_ip
    server_ip=$(get_pod_ip "server" "$server_ns")

    if [[ -z "$server_ip" ]]; then
        fail "Could not get server pod IP"
        return
    fi

    # Check if namespace has been labeled correctly
    if namespace_has_label "$client_ns" "role" "client"; then
        pass "Namespace $client_ns has correct label role=client"
    else
        fail_with_cmd "Namespace $client_ns missing label role=client" \
            "kubectl get namespace $client_ns --show-labels"
        info "Fix: kubectl label namespace $client_ns role=client"
        return
    fi

    # Test connectivity (should work after fix)
    if test_connectivity "client" "$client_ns" "$server_ip" 3; then
        pass "Client can now reach server after namespace label fix"
    else
        fail_with_cmd "Client still cannot reach server" \
            "kubectl exec -n $client_ns client -- wget -qO- --timeout=2 http://$server_ip"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: AND vs OR semantics ==="
    local ns1="ex-3-2-ns1"
    local ns2="ex-3-2-ns2"

    if ! namespace_exists "$ns1" || ! namespace_exists "$ns2"; then
        fail "Required namespaces do not exist"
        return
    fi

    local target_ip
    target_ip=$(get_pod_ip "target" "$ns1")

    if [[ -z "$target_ip" ]]; then
        fail "Could not get target pod IP"
        return
    fi

    # Test client-alpha (in ns1, should work - both conditions in AND match)
    if test_connectivity "client-alpha" "$ns1" "$target_ip" 3; then
        pass "Client-alpha (in ns1, role=tester) can reach target (AND semantics)"
    else
        fail_with_cmd "Client-alpha cannot reach target (should be allowed)" \
            "kubectl exec -n $ns1 client-alpha -- wget -qO- --timeout=2 http://$target_ip"
    fi

    # Test client-beta (in ns2, should be blocked - namespace doesn't match)
    if test_connectivity "client-beta" "$ns2" "$target_ip" 3; then
        fail "Client-beta (in ns2) can reach target (AND selector should block)"
    else
        pass "Client-beta is blocked (correct AND semantics: namespace must match)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug ipBlock except issue ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check the NetworkPolicy configuration
    local np_yaml
    np_yaml=$(kubectl get networkpolicy external-access -n "$ns" -o yaml 2>/dev/null)

    # The original policy has except = cidr, which blocks everything
    # Check if it's been fixed
    if echo "$np_yaml" | grep -A5 "ipBlock" | grep -A2 "except" | grep -q "10.0.0.0/8"; then
        fail "NetworkPolicy still has incorrect except clause (matches entire CIDR)"
        info "Problem: except range 10.0.0.0/8 cancels out cidr 10.0.0.0/8"
        info "Fix: Remove except clause or use a smaller subset"
    else
        pass "NetworkPolicy ipBlock except clause has been fixed"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Default deny with DNS exception ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "app" "$ns"; then
        fail "Pod app not found in namespace $ns"
        return
    fi

    # Check for NetworkPolicy
    local np_count
    np_count=$(kubectl get networkpolicy -n "$ns" -o name 2>/dev/null | wc -l)
    if [[ "$np_count" -eq 0 ]]; then
        fail_with_cmd "No NetworkPolicy found in namespace $ns" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    pass "NetworkPolicy exists in $ns"

    # Check that DNS works
    if kubectl exec -n "$ns" app -- nslookup kubernetes.default &>/dev/null; then
        pass "DNS resolution works (exception in place)"
    else
        fail_with_cmd "DNS is blocked (should have exception)" \
            "kubectl exec -n $ns app -- nslookup kubernetes.default"
    fi

    # Check that external egress is blocked
    if kubectl exec -n "$ns" app -- wget -qO- --timeout=2 http://example.com &>/dev/null; then
        fail "External egress is allowed (should be blocked by default deny)"
    else
        pass "External egress is blocked (default deny working)"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Namespace isolation ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local server_ip
    server_ip=$(get_pod_ip "server" "$ns")

    if [[ -z "$server_ip" ]]; then
        fail "Could not get server pod IP"
        return
    fi

    # Test internal communication (should work)
    if test_connectivity "client" "$ns" "$server_ip" 3; then
        pass "Internal pod-to-pod communication works"
    else
        fail_with_cmd "Internal communication blocked (should be allowed)" \
            "kubectl exec -n $ns client -- wget -qO- --timeout=2 http://$server_ip"
    fi

    # Test DNS
    if kubectl exec -n "$ns" client -- nslookup kubernetes.default &>/dev/null; then
        pass "DNS resolution works"
    else
        fail_with_cmd "DNS is blocked (should have exception)" \
            "kubectl exec -n $ns client -- nslookup kubernetes.default"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Least-privilege three-tier ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local backend_ip db_ip
    backend_ip=$(get_pod_ip "backend" "$ns")
    db_ip=$(get_pod_ip "database" "$ns")

    if [[ -z "$backend_ip" ]] || [[ -z "$db_ip" ]]; then
        fail "Could not get pod IPs"
        return
    fi

    # Check for multiple policies
    local np_count
    np_count=$(kubectl get networkpolicy -n "$ns" -o name 2>/dev/null | wc -l)
    if [[ "$np_count" -lt 3 ]]; then
        fail_with_cmd "Expected multiple NetworkPolicies (got $np_count)" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    pass "Multiple NetworkPolicies exist ($np_count policies)"

    # Test frontend -> backend (should work)
    if test_connectivity "frontend" "$ns" "$backend_ip" 3; then
        pass "Frontend can reach backend"
    else
        fail_with_cmd "Frontend cannot reach backend (should be allowed)" \
            "kubectl exec -n $ns frontend -- wget -qO- --timeout=2 http://$backend_ip"
    fi

    # Test backend -> database (should work)
    if test_connectivity "backend" "$ns" "$db_ip" 3; then
        pass "Backend can reach database"
    else
        fail_with_cmd "Backend cannot reach database (should be allowed)" \
            "kubectl exec -n $ns backend -- wget -qO- --timeout=2 http://$db_ip"
    fi

    # Test frontend -> database (should be blocked)
    if test_connectivity "frontend" "$ns" "$db_ip" 3; then
        fail "Frontend can reach database directly (should be blocked)"
    else
        pass "Frontend to database is blocked (least-privilege working)"
    fi

    # Test DNS
    if kubectl exec -n "$ns" frontend -- nslookup kubernetes.default &>/dev/null; then
        pass "DNS access works for all pods"
    else
        fail "DNS is blocked"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multi-namespace isolation ==="
    local web_ns="ex-5-1-web"
    local api_ns="ex-5-1-api"
    local db_ns="ex-5-1-db"

    if ! namespace_exists "$web_ns" || ! namespace_exists "$api_ns" || ! namespace_exists "$db_ns"; then
        fail "Required namespaces do not exist"
        return
    fi

    local api_ip db_ip
    api_ip=$(get_pod_ip "api" "$api_ns")
    db_ip=$(get_pod_ip "db" "$db_ns")

    if [[ -z "$api_ip" ]] || [[ -z "$db_ip" ]]; then
        fail "Could not get pod IPs"
        return
    fi

    # Check for policies in multiple namespaces
    local api_np_count db_np_count
    api_np_count=$(kubectl get networkpolicy -n "$api_ns" -o name 2>/dev/null | wc -l)
    db_np_count=$(kubectl get networkpolicy -n "$db_ns" -o name 2>/dev/null | wc -l)

    if [[ "$api_np_count" -eq 0 ]] || [[ "$db_np_count" -eq 0 ]]; then
        fail_with_cmd "Missing NetworkPolicies in API or DB namespace" \
            "kubectl get networkpolicy -A | grep ex-5-1"
        return
    fi

    pass "NetworkPolicies exist in API and DB namespaces"

    # Test web -> api (should work)
    if test_connectivity "web" "$web_ns" "$api_ip" 3; then
        pass "Web can reach API"
    else
        fail_with_cmd "Web cannot reach API (should be allowed)" \
            "kubectl exec -n $web_ns web -- wget -qO- --timeout=2 http://$api_ip"
    fi

    # Test api -> db (should work)
    if test_connectivity "api" "$api_ns" "$db_ip" 3; then
        pass "API can reach DB"
    else
        fail_with_cmd "API cannot reach DB (should be allowed)" \
            "kubectl exec -n $api_ns api -- wget -qO- --timeout=2 http://$db_ip"
    fi

    # Test web -> db (should be blocked)
    if test_connectivity "web" "$web_ns" "$db_ip" 3; then
        fail "Web can reach DB directly (should be blocked)"
    else
        pass "Web to DB is blocked (isolation working)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Policy additive behavior ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local server_ip
    server_ip=$(get_pod_ip "secure-server" "$ns")

    if [[ -z "$server_ip" ]]; then
        fail "Could not get server pod IP"
        return
    fi

    # Check that two policies exist
    local np_count
    np_count=$(kubectl get networkpolicy -n "$ns" -o name 2>/dev/null | wc -l)
    if [[ "$np_count" -ne 2 ]]; then
        fail "Expected 2 NetworkPolicies, found $np_count"
        return
    fi

    pass "Two NetworkPolicies exist (policy-a and policy-b)"

    # Test connectivity (should work due to additive behavior)
    if test_connectivity "client" "$ns" "$server_ip" 3; then
        pass "Client can reach server (additive policy behavior working)"
        info "Explanation: policy-b allows traffic even though policy-a has no rules"
    else
        fail_with_cmd "Client cannot reach server" \
            "kubectl exec -n $ns client -- wget -qO- --timeout=2 http://$server_ip"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Zero-trust strategy ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Wait for all pods to be ready
    sleep 5

    local web_ip api_ip db_ip
    web_ip=$(get_pod_ip "web" "$ns")
    api_ip=$(get_pod_ip "api" "$ns")
    db_ip=$(get_pod_ip "db" "$ns")

    if [[ -z "$web_ip" ]] || [[ -z "$api_ip" ]] || [[ -z "$db_ip" ]]; then
        fail "Could not get all pod IPs"
        return
    fi

    # Check for multiple policies (expect at least 5: default-deny + tier-specific)
    local np_count
    np_count=$(kubectl get networkpolicy -n "$ns" -o name 2>/dev/null | wc -l)
    if [[ "$np_count" -lt 5 ]]; then
        fail_with_cmd "Expected at least 5 NetworkPolicies for zero-trust (got $np_count)" \
            "kubectl get networkpolicy -n $ns"
        return
    fi

    pass "Multiple NetworkPolicies exist ($np_count policies)"

    # Test tester -> web (should work - web accepts external)
    if test_connectivity "tester" "$ns" "$web_ip" 3; then
        pass "Tester can reach web tier (external access allowed)"
    else
        fail_with_cmd "Tester cannot reach web (should be allowed)" \
            "kubectl exec -n $ns tester -- wget -qO- --timeout=2 http://$web_ip"
    fi

    # Test web -> api (should work)
    if test_connectivity "web" "$ns" "$api_ip" 3; then
        pass "Web can reach API tier"
    else
        fail_with_cmd "Web cannot reach API (should be allowed)" \
            "kubectl exec -n $ns web -- wget -qO- --timeout=2 http://$api_ip"
    fi

    # Test api -> db (should work)
    if test_connectivity "api" "$ns" "$db_ip" 3; then
        pass "API can reach DB tier"
    else
        fail_with_cmd "API cannot reach DB (should be allowed)" \
            "kubectl exec -n $ns api -- wget -qO- --timeout=2 http://$db_ip"
    fi

    # Test tester -> api (should be blocked)
    if test_connectivity "tester" "$ns" "$api_ip" 3; then
        fail "Tester can reach API tier (should be blocked)"
    else
        pass "Tester to API is blocked (zero-trust working)"
    fi

    # Test DNS
    if kubectl exec -n "$ns" tester -- nslookup kubernetes.default &>/dev/null; then
        pass "DNS access works for all pods"
    else
        fail "DNS is blocked"
    fi
}

################################################################################
# Level aggregation functions
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Cross-Namespace Policies"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Combined Selectors and ipBlock"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Selector Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Default Deny and Isolation"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Complex Isolation"
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
