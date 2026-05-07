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

# Helper: check if Gateway exists
gateway_exists() {
    local gw=$1
    local ns=$2
    kubectl get gateway "$gw" -n "$ns" &>/dev/null
}

# Helper: get Gateway condition status
get_gateway_condition() {
    local gw=$1
    local ns=$2
    local condition=$3
    kubectl get gateway "$gw" -n "$ns" -o jsonpath="{.status.conditions[?(@.type=='$condition')].status}" 2>/dev/null
}

# Helper: check if HTTPRoute exists
httproute_exists() {
    local hr=$1
    local ns=$2
    kubectl get httproute "$hr" -n "$ns" &>/dev/null
}

# Helper: get HTTPRoute parent condition status
get_httproute_parent_condition() {
    local hr=$1
    local ns=$2
    local condition=$3
    local index=${4:-0}
    kubectl get httproute "$hr" -n "$ns" -o jsonpath="{.status.parents[$index].conditions[?(@.type=='$condition')].status}" 2>/dev/null
}

# Helper: check if Deployment exists
deployment_exists() {
    local deploy=$1
    local ns=$2
    kubectl get deployment "$deploy" -n "$ns" &>/dev/null
}

# Helper: check if Service exists
service_exists() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" &>/dev/null
}

# Helper: get ReferenceGrant
referencegrant_exists() {
    local rg=$1
    local ns=$2
    kubectl get referencegrant "$rg" -n "$ns" &>/dev/null
}

# Helper: get Gateway address
get_gateway_address() {
    local gw=$1
    local ns=$2
    kubectl get gateway "$gw" -n "$ns" -o jsonpath='{.status.addresses[0].value}' 2>/dev/null
}

# Helper: get Gateway class name
get_gateway_class() {
    local gw=$1
    local ns=$2
    kubectl get gateway "$gw" -n "$ns" -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null
}

# Helper: get listener allowed routes from
get_allowed_routes_from() {
    local gw=$1
    local ns=$2
    local index=${3:-0}
    kubectl get gateway "$gw" -n "$ns" -o jsonpath="{.spec.listeners[$index].allowedRoutes.namespaces.from}" 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic Gateway with HTTP listener ==="
    local gw="basic-gw"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! gateway_exists "$gw" "$ns"; then
        fail_with_cmd "Gateway $gw not found in namespace $ns" \
            "kubectl get gateway -n $ns"
        return
    fi

    local class
    class=$(get_gateway_class "$gw" "$ns")
    if [[ "$class" == "eg" ]]; then
        pass "Gateway class is eg"
    else
        fail_with_cmd "Gateway class is $class (expected eg)" \
            "kubectl get gateway $gw -n $ns -o yaml | grep gatewayClassName"
    fi

    local allowed_from
    allowed_from=$(get_allowed_routes_from "$gw" "$ns" 0)
    if [[ "$allowed_from" == "All" ]]; then
        pass "AllowedRoutes from: All"
    else
        fail_with_cmd "AllowedRoutes from: $allowed_from (expected All)" \
            "kubectl get gateway $gw -n $ns -o jsonpath='{.spec.listeners[0].allowedRoutes}'"
    fi

    sleep 5
    local programmed
    programmed=$(get_gateway_condition "$gw" "$ns" "Programmed")
    if [[ "$programmed" == "True" ]]; then
        pass "Gateway Programmed: True"
    else
        fail_with_cmd "Gateway Programmed: $programmed (expected True)" \
            "kubectl get gateway $gw -n $ns -o jsonpath='{.status.conditions}'"
    fi

    local address
    address=$(get_gateway_address "$gw" "$ns")
    if [[ -n "$address" ]]; then
        pass "Gateway has address: $address"
    else
        fail_with_cmd "Gateway has no address" \
            "kubectl get gateway $gw -n $ns -o jsonpath='{.status.addresses}'"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Attach HTTPRoute to Gateway ==="
    local hr="app-route"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$hr" "$ns"; then
        fail_with_cmd "HTTPRoute $hr not found in namespace $ns" \
            "kubectl get httproute -n $ns"
        return
    fi

    sleep 5
    local accepted
    accepted=$(get_httproute_parent_condition "$hr" "$ns" "Accepted")
    if [[ "$accepted" == "True" ]]; then
        pass "HTTPRoute Accepted: True"
    else
        fail_with_cmd "HTTPRoute Accepted: $accepted (expected True)" \
            "kubectl get httproute $hr -n $ns -o jsonpath='{.status.parents[0].conditions}'"
    fi

    local resolved
    resolved=$(get_httproute_parent_condition "$hr" "$ns" "ResolvedRefs")
    if [[ "$resolved" == "True" ]]; then
        pass "HTTPRoute ResolvedRefs: True"
    else
        fail_with_cmd "HTTPRoute ResolvedRefs: $resolved (expected True)" \
            "kubectl get httproute $hr -n $ns -o jsonpath='{.status.parents[0].conditions}'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Identify Envoy Gateway GatewayClass ==="

    local result
    result=$(kubectl get gatewayclass -o jsonpath='{range .items[?(@.spec.controllerName=="gateway.envoyproxy.io/gatewayclass-controller")]}{.metadata.name}{"\n"}{end}' 2>/dev/null)

    if [[ "$result" == "eg" ]]; then
        pass "Found GatewayClass: eg"
    else
        fail_with_cmd "GatewayClass result: '$result' (expected eg)" \
            "kubectl get gatewayclass -o yaml | grep -A2 controllerName"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Path-based routing with two Services ==="
    local hr="paths"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$hr" "$ns"; then
        fail_with_cmd "HTTPRoute $hr not found in namespace $ns" \
            "kubectl get httproute -n $ns"
        return
    fi

    if ! service_exists "svc-a" "$ns"; then
        fail "Service svc-a not found"
        return
    fi

    if ! service_exists "svc-b" "$ns"; then
        fail "Service svc-b not found"
        return
    fi

    sleep 5
    local accepted
    accepted=$(get_httproute_parent_condition "$hr" "$ns" "Accepted")
    if [[ "$accepted" == "True" ]]; then
        pass "HTTPRoute Accepted: True"
    else
        fail_with_cmd "HTTPRoute Accepted: $accepted" \
            "kubectl get httproute $hr -n $ns -o jsonpath='{.status.parents[0].conditions}'"
    fi

    local resolved
    resolved=$(get_httproute_parent_condition "$hr" "$ns" "ResolvedRefs")
    if [[ "$resolved" == "True" ]]; then
        pass "HTTPRoute ResolvedRefs: True"
    else
        fail_with_cmd "HTTPRoute ResolvedRefs: $resolved" \
            "kubectl get httproute $hr -n $ns -o jsonpath='{.status.parents[0].conditions}'"
    fi

    # Check number of rules
    local rules
    rules=$(kubectl get httproute "$hr" -n "$ns" -o jsonpath='{.spec.rules}' 2>/dev/null | grep -o "backendRefs" | wc -l)
    if [[ "$rules" -ge 2 ]]; then
        pass "HTTPRoute has multiple rules for path-based routing"
    else
        info "HTTPRoute may need separate rules for /a and /b paths"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Hostname-based routing ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "red-route" "$ns"; then
        fail_with_cmd "HTTPRoute red-route not found" \
            "kubectl get httproute -n $ns"
        return
    fi

    if ! httproute_exists "blue-route" "$ns"; then
        fail_with_cmd "HTTPRoute blue-route not found" \
            "kubectl get httproute -n $ns"
        return
    fi

    sleep 5
    local red_accepted
    red_accepted=$(get_httproute_parent_condition "red-route" "$ns" "Accepted")
    if [[ "$red_accepted" == "True" ]]; then
        pass "red-route Accepted: True"
    else
        fail_with_cmd "red-route Accepted: $red_accepted" \
            "kubectl get httproute red-route -n $ns -o jsonpath='{.status.parents[0].conditions}'"
    fi

    local blue_accepted
    blue_accepted=$(get_httproute_parent_condition "blue-route" "$ns" "Accepted")
    if [[ "$blue_accepted" == "True" ]]; then
        pass "blue-route Accepted: True"
    else
        fail_with_cmd "blue-route Accepted: $blue_accepted" \
            "kubectl get httproute blue-route -n $ns -o jsonpath='{.status.parents[0].conditions}'"
    fi

    # Check hostnames
    local red_host
    red_host=$(kubectl get httproute red-route -n "$ns" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)
    if [[ "$red_host" == "red.example.test" ]]; then
        pass "red-route hostname: red.example.test"
    else
        info "red-route hostname is $red_host"
    fi

    local blue_host
    blue_host=$(kubectl get httproute blue-route -n "$ns" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)
    if [[ "$blue_host" == "blue.example.test" ]]; then
        pass "blue-route hostname: blue.example.test"
    else
        info "blue-route hostname is $blue_host"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Weighted traffic splitting ==="
    local hr="split"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$hr" "$ns"; then
        fail_with_cmd "HTTPRoute $hr not found" \
            "kubectl get httproute -n $ns"
        return
    fi

    sleep 5
    local accepted
    accepted=$(get_httproute_parent_condition "$hr" "$ns" "Accepted")
    if [[ "$accepted" == "True" ]]; then
        pass "HTTPRoute Accepted: True"
    else
        fail_with_cmd "HTTPRoute Accepted: $accepted" \
            "kubectl get httproute $hr -n $ns -o jsonpath='{.status.parents[0].conditions}'"
    fi

    # Check for multiple backendRefs
    local backends
    backends=$(kubectl get httproute "$hr" -n "$ns" -o jsonpath='{.spec.rules[0].backendRefs}' 2>/dev/null)
    if [[ "$backends" == *"v1-app"* ]] && [[ "$backends" == *"v2-app"* ]]; then
        pass "HTTPRoute has backendRefs for both v1-app and v2-app"
    else
        fail_with_cmd "HTTPRoute backendRefs missing v1-app or v2-app" \
            "kubectl get httproute $hr -n $ns -o jsonpath='{.spec.rules[0].backendRefs}'"
    fi

    # Check for weights
    if [[ "$backends" == *"weight"* ]]; then
        pass "HTTPRoute has weight configuration"
    else
        info "HTTPRoute may need explicit weight configuration for 50/50 split"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix HTTPRoute Accepted: False ==="
    local hr="blocked"
    local ns="ex-3-1-other"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$hr" "$ns"; then
        fail_with_cmd "HTTPRoute $hr not found" \
            "kubectl get httproute -n $ns"
        return
    fi

    sleep 5
    local accepted
    accepted=$(get_httproute_parent_condition "$hr" "$ns" "Accepted")
    if [[ "$accepted" == "True" ]]; then
        pass "HTTPRoute Accepted: True (issue fixed)"
    else
        fail_with_cmd "HTTPRoute Accepted: $accepted (expected True after fix)" \
            "kubectl get httproute $hr -n $ns -o yaml | grep -A10 conditions"
        info "Hint: Check Gateway allowedRoutes configuration in ex-3-1"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix HTTPRoute with non-existent backend ==="
    local hr="unresolved"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$hr" "$ns"; then
        fail_with_cmd "HTTPRoute $hr not found" \
            "kubectl get httproute -n $ns"
        return
    fi

    sleep 5
    local resolved
    resolved=$(get_httproute_parent_condition "$hr" "$ns" "ResolvedRefs")
    if [[ "$resolved" == "True" ]]; then
        pass "HTTPRoute ResolvedRefs: True (issue fixed)"
    else
        fail_with_cmd "HTTPRoute ResolvedRefs: $resolved (expected True after fix)" \
            "kubectl get httproute $hr -n $ns -o yaml | grep -A10 conditions"
        info "Hint: Check backendRefs and ensure Service 'real' exists"
    fi

    # Check backend ref points to 'real' service
    local backend
    backend=$(kubectl get httproute "$hr" -n "$ns" -o jsonpath='{.spec.rules[0].backendRefs[0].name}' 2>/dev/null)
    if [[ "$backend" == "real" ]]; then
        pass "HTTPRoute points to Service 'real'"
    else
        info "HTTPRoute backend is $backend (should be 'real')"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix HTTPRoute with wrong namespace reference ==="
    local hr="orphan"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$hr" "$ns"; then
        fail_with_cmd "HTTPRoute $hr not found" \
            "kubectl get httproute -n $ns"
        return
    fi

    sleep 5
    local accepted
    accepted=$(get_httproute_parent_condition "$hr" "$ns" "Accepted")
    if [[ "$accepted" == "True" ]]; then
        pass "HTTPRoute Accepted: True (issue fixed)"
    else
        fail_with_cmd "HTTPRoute Accepted: $accepted (expected True after fix)" \
            "kubectl get httproute $hr -n $ns -o yaml | grep -A10 conditions"
        info "Hint: Add namespace: ex-3-3-gw to parentRefs"
    fi

    # Check parentRefs has namespace specified
    local parent_ns
    parent_ns=$(kubectl get httproute "$hr" -n "$ns" -o jsonpath='{.spec.parentRefs[0].namespace}' 2>/dev/null)
    if [[ "$parent_ns" == "ex-3-3-gw" ]]; then
        pass "HTTPRoute parentRefs specifies namespace ex-3-3-gw"
    else
        info "HTTPRoute parentRefs namespace is '$parent_ns' (expected ex-3-3-gw)"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Gateway with namespace selector ==="
    local gw="platform"
    local gw_ns="ex-4-1-infra"
    local hr="tenant-route"
    local hr_ns="ex-4-1-app"

    if ! namespace_exists "$gw_ns"; then
        fail "Namespace $gw_ns does not exist"
        return
    fi

    if ! namespace_exists "$hr_ns"; then
        fail "Namespace $hr_ns does not exist"
        return
    fi

    if ! gateway_exists "$gw" "$gw_ns"; then
        fail_with_cmd "Gateway $gw not found in $gw_ns" \
            "kubectl get gateway -n $gw_ns"
        return
    fi

    if ! httproute_exists "$hr" "$hr_ns"; then
        fail_with_cmd "HTTPRoute $hr not found in $hr_ns" \
            "kubectl get httproute -n $hr_ns"
        return
    fi

    # Check namespace label
    local label
    label=$(kubectl get namespace "$hr_ns" -o jsonpath='{.metadata.labels.tier}' 2>/dev/null)
    if [[ "$label" == "app" ]]; then
        pass "Namespace $hr_ns has label tier=app"
    else
        info "Namespace $hr_ns label tier is '$label' (expected app)"
    fi

    sleep 5
    local accepted
    accepted=$(get_httproute_parent_condition "$hr" "$hr_ns" "Accepted")
    if [[ "$accepted" == "True" ]]; then
        pass "HTTPRoute Accepted: True"
    else
        fail_with_cmd "HTTPRoute Accepted: $accepted" \
            "kubectl get httproute $hr -n $hr_ns -o jsonpath='{.status.parents[0].conditions}'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Cross-namespace Service with ReferenceGrant ==="
    local hr="xroute"
    local hr_ns="ex-4-2-route"
    local svc_ns="ex-4-2-svc"

    if ! namespace_exists "$hr_ns"; then
        fail "Namespace $hr_ns does not exist"
        return
    fi

    if ! namespace_exists "$svc_ns"; then
        fail "Namespace $svc_ns does not exist"
        return
    fi

    if ! httproute_exists "$hr" "$hr_ns"; then
        fail_with_cmd "HTTPRoute $hr not found in $hr_ns" \
            "kubectl get httproute -n $hr_ns"
        return
    fi

    # Check for ReferenceGrant in svc namespace
    local rg_exists=false
    if kubectl get referencegrant -n "$svc_ns" &>/dev/null; then
        local rg_count
        rg_count=$(kubectl get referencegrant -n "$svc_ns" --no-headers 2>/dev/null | wc -l)
        if [[ "$rg_count" -gt 0 ]]; then
            rg_exists=true
            pass "ReferenceGrant exists in $svc_ns"
        fi
    fi

    if [[ "$rg_exists" == false ]]; then
        fail_with_cmd "No ReferenceGrant found in $svc_ns" \
            "kubectl get referencegrant -n $svc_ns"
        return
    fi

    sleep 5
    local resolved
    resolved=$(get_httproute_parent_condition "$hr" "$hr_ns" "ResolvedRefs")
    if [[ "$resolved" == "True" ]]; then
        pass "HTTPRoute ResolvedRefs: True"
    else
        fail_with_cmd "HTTPRoute ResolvedRefs: $resolved (expected True)" \
            "kubectl get httproute $hr -n $hr_ns -o jsonpath='{.status.parents[0].conditions}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: HTTPRoute with multiple parentRefs ==="
    local hr="both-gateways"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! httproute_exists "$hr" "$ns"; then
        fail_with_cmd "HTTPRoute $hr not found" \
            "kubectl get httproute -n $ns"
        return
    fi

    # Check number of parentRefs
    local parent_count
    parent_count=$(kubectl get httproute "$hr" -n "$ns" -o jsonpath='{.spec.parentRefs}' 2>/dev/null | grep -o "name" | wc -l)
    if [[ "$parent_count" -ge 2 ]]; then
        pass "HTTPRoute has multiple parentRefs"
    else
        fail_with_cmd "HTTPRoute has $parent_count parentRefs (expected 2)" \
            "kubectl get httproute $hr -n $ns -o jsonpath='{.spec.parentRefs}'"
    fi

    sleep 5
    # Check both parents are accepted
    local statuses
    statuses=$(kubectl get httproute "$hr" -n "$ns" -o jsonpath='{.status.parents[*].conditions[?(@.type=="Accepted")].status}' 2>/dev/null)
    if [[ "$statuses" == *"True"*"True"* ]] || [[ "$statuses" == "True True" ]]; then
        pass "Both parent Gateways accepted the HTTPRoute"
    else
        fail_with_cmd "Parent acceptance statuses: $statuses" \
            "kubectl get httproute $hr -n $ns -o jsonpath='{.status.parents}'"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multi-tenant Gateway platform ==="
    local gw="shared"
    local gw_ns="ex-5-1-platform"

    if ! namespace_exists "$gw_ns"; then
        fail "Namespace $gw_ns does not exist"
        return
    fi

    if ! gateway_exists "$gw" "$gw_ns"; then
        fail_with_cmd "Gateway $gw not found in $gw_ns" \
            "kubectl get gateway -n $gw_ns"
        return
    fi

    # Check each team namespace
    for team in api ui admin; do
        local team_ns="ex-5-1-$team"
        if ! namespace_exists "$team_ns"; then
            fail "Namespace $team_ns does not exist"
            continue
        fi

        local label
        label=$(kubectl get namespace "$team_ns" -o jsonpath='{.metadata.labels.gateway-attach}' 2>/dev/null)
        if [[ "$label" == "allowed" ]]; then
            pass "Namespace $team_ns has label gateway-attach=allowed"
        else
            info "Namespace $team_ns label gateway-attach is '$label'"
        fi
    done

    sleep 5
    # Check HTTPRoutes for each team
    for team in api ui admin; do
        local team_ns="ex-5-1-$team"
        if httproute_exists "route" "$team_ns"; then
            local accepted
            accepted=$(get_httproute_parent_condition "route" "$team_ns" "Accepted")
            if [[ "$accepted" == "True" ]]; then
                pass "$team team HTTPRoute Accepted: True"
            else
                fail_with_cmd "$team team HTTPRoute Accepted: $accepted" \
                    "kubectl get httproute route -n $team_ns -o jsonpath='{.status.parents[0].conditions}'"
            fi
        else
            fail "HTTPRoute 'route' not found in $team_ns"
        fi
    done
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Compound failure debugging ==="
    local gw="gw"
    local gw_ns="ex-5-2-gw"
    local hr="three-bugs"
    local hr_ns="ex-5-2-route"
    local svc_ns="ex-5-2-svc"

    if ! namespace_exists "$gw_ns"; then
        fail "Namespace $gw_ns does not exist"
        return
    fi

    if ! namespace_exists "$hr_ns"; then
        fail "Namespace $hr_ns does not exist"
        return
    fi

    if ! gateway_exists "$gw" "$gw_ns"; then
        fail_with_cmd "Gateway $gw not found in $gw_ns" \
            "kubectl get gateway -n $gw_ns"
        return
    fi

    # Check Gateway class is fixed
    local class
    class=$(get_gateway_class "$gw" "$gw_ns")
    if [[ "$class" == "eg" ]]; then
        pass "Gateway class is eg (fixed)"
    else
        fail_with_cmd "Gateway class is $class (should be eg)" \
            "kubectl get gateway $gw -n $gw_ns -o yaml | grep gatewayClassName"
    fi

    # Check allowedRoutes is fixed
    local allowed_from
    allowed_from=$(get_allowed_routes_from "$gw" "$gw_ns" 0)
    if [[ "$allowed_from" == "All" ]]; then
        pass "Gateway allowedRoutes from: All (fixed)"
    else
        fail_with_cmd "Gateway allowedRoutes from: $allowed_from (should be All)" \
            "kubectl get gateway $gw -n $gw_ns -o jsonpath='{.spec.listeners[0].allowedRoutes}'"
    fi

    # Check ReferenceGrant exists
    local rg_exists=false
    if kubectl get referencegrant -n "$svc_ns" &>/dev/null; then
        local rg_count
        rg_count=$(kubectl get referencegrant -n "$svc_ns" --no-headers 2>/dev/null | wc -l)
        if [[ "$rg_count" -gt 0 ]]; then
            rg_exists=true
            pass "ReferenceGrant exists in $svc_ns (fixed)"
        fi
    fi

    if [[ "$rg_exists" == false ]]; then
        fail_with_cmd "No ReferenceGrant found in $svc_ns" \
            "kubectl get referencegrant -n $svc_ns"
    fi

    sleep 5
    local accepted
    accepted=$(get_httproute_parent_condition "$hr" "$hr_ns" "Accepted")
    if [[ "$accepted" == "True" ]]; then
        pass "HTTPRoute Accepted: True"
    else
        fail_with_cmd "HTTPRoute Accepted: $accepted" \
            "kubectl get httproute $hr -n $hr_ns -o jsonpath='{.status.parents[0].conditions}'"
    fi

    local resolved
    resolved=$(get_httproute_parent_condition "$hr" "$hr_ns" "ResolvedRefs")
    if [[ "$resolved" == "True" ]]; then
        pass "HTTPRoute ResolvedRefs: True"
    else
        fail_with_cmd "HTTPRoute ResolvedRefs: $resolved" \
            "kubectl get httproute $hr -n $hr_ns -o jsonpath='{.status.parents[0].conditions}'"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Ingress to Gateway API equivalence ==="
    local gw="modern-gw"
    local hr="modern-route"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! gateway_exists "$gw" "$ns"; then
        fail_with_cmd "Gateway $gw not found" \
            "kubectl get gateway -n $ns"
        return
    fi

    if ! httproute_exists "$hr" "$ns"; then
        fail_with_cmd "HTTPRoute $hr not found" \
            "kubectl get httproute -n $ns"
        return
    fi

    sleep 5
    local programmed
    programmed=$(get_gateway_condition "$gw" "$ns" "Programmed")
    if [[ "$programmed" == "True" ]]; then
        pass "Gateway Programmed: True"
    else
        fail_with_cmd "Gateway Programmed: $programmed" \
            "kubectl get gateway $gw -n $ns -o jsonpath='{.status.conditions}'"
    fi

    local accepted
    accepted=$(get_httproute_parent_condition "$hr" "$ns" "Accepted")
    if [[ "$accepted" == "True" ]]; then
        pass "HTTPRoute Accepted: True"
    else
        fail_with_cmd "HTTPRoute Accepted: $accepted" \
            "kubectl get httproute $hr -n $ns -o jsonpath='{.status.parents[0].conditions}'"
    fi

    # Check hostname matches
    local host
    host=$(kubectl get httproute "$hr" -n "$ns" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)
    if [[ "$host" == "legacy.example.test" ]]; then
        pass "HTTPRoute hostname matches Ingress: legacy.example.test"
    else
        info "HTTPRoute hostname is $host (Ingress uses legacy.example.test)"
    fi

    # Check path matching
    local path
    path=$(kubectl get httproute "$hr" -n "$ns" -o jsonpath='{.spec.rules[0].matches[0].path.value}' 2>/dev/null)
    if [[ "$path" == "/api" ]]; then
        pass "HTTPRoute path matches Ingress: /api"
    else
        info "HTTPRoute path is $path (Ingress uses /api)"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Gateway API Basics"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Routing"
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
    echo "# Level 4: Persona Separation and ReferenceGrant"
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
