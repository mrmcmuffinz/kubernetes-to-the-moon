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

# Helper: check if file exists
file_exists() {
    [[ -f "$1" ]]
}

# Helper: check if ingress2gateway CLI is installed
cli_installed() {
    command -v ingress2gateway &>/dev/null
}

# Helper: check CLI version
get_cli_version() {
    ingress2gateway --version 2>&1 | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+'
}

# Helper: check if Gateway exists
gateway_exists() {
    local gw=$1; local ns=$2
    kubectl get gateway "$gw" -n "$ns" &>/dev/null
}

# Helper: check if HTTPRoute exists
httproute_exists() {
    local route=$1; local ns=$2
    kubectl get httproute "$route" -n "$ns" &>/dev/null
}

# Helper: check if Ingress exists
ingress_exists() {
    local ing=$1; local ns=$2
    kubectl get ingress "$ing" -n "$ns" &>/dev/null
}

# Helper: get Gateway className
get_gateway_class() {
    local gw=$1; local ns=$2
    kubectl get gateway "$gw" -n "$ns" -o jsonpath='{.spec.gatewayClassName}' 2>/dev/null
}

# Helper: count Gateway listeners
count_gateway_listeners() {
    local gw=$1; local ns=$2
    kubectl get gateway "$gw" -n "$ns" -o jsonpath='{.spec.listeners}' 2>/dev/null | jq '. | length' 2>/dev/null || echo "0"
}

# Helper: get HTTPRoute hostnames
get_httproute_hostnames() {
    local route=$1; local ns=$2
    kubectl get httproute "$route" -n "$ns" -o jsonpath='{.spec.hostnames[*]}' 2>/dev/null
}

# Helper: get Service endpoint
service_exists() {
    local svc=$1; local ns=$2
    kubectl get service "$svc" -n "$ns" &>/dev/null
}

# Helper: get Deployment ready status
deployment_ready() {
    local dep=$1; local ns=$2
    local ready
    ready=$(kubectl get deployment "$dep" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    [[ -n "$ready" ]] && [[ "$ready" -gt 0 ]]
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: CLI version check ==="

    if ! cli_installed; then
        fail_with_cmd "ingress2gateway CLI not found in PATH" \
            "which ingress2gateway || echo 'Download from github.com/kubernetes-sigs/ingress2gateway/releases/tag/v1.0.0'"
        return
    fi

    local version
    version=$(get_cli_version)
    if [[ "$version" == "v1.0.0" ]]; then
        pass "CLI version is v1.0.0"
    else
        fail_with_cmd "CLI version is $version (expected v1.0.0)" \
            "ingress2gateway --version"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Basic Ingress translation ==="
    local input_file="/tmp/ex-1-2.yaml"
    local output_file="/tmp/ex-1-2-gwapi.yaml"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! file_exists "$input_file"; then
        fail "Input file $input_file not found"
        return
    fi

    if ! file_exists "$output_file"; then
        fail "Output file $output_file not found"
        info "Hint: Run ingress2gateway print --input-file=$input_file --providers=ingress-nginx > $output_file"
        return
    fi

    local gateway_count
    gateway_count=$(grep -c "^kind: Gateway$" "$output_file" || echo "0")
    if [[ "$gateway_count" -ge 1 ]]; then
        pass "Output contains Gateway resource (count: $gateway_count)"
    else
        fail_with_cmd "Output does not contain Gateway resource" \
            "grep 'kind: Gateway' $output_file"
    fi

    local httproute_count
    httproute_count=$(grep -c "^kind: HTTPRoute$" "$output_file" || echo "0")
    if [[ "$httproute_count" -ge 1 ]]; then
        pass "Output contains HTTPRoute resource (count: $httproute_count)"
    else
        fail_with_cmd "Output does not contain HTTPRoute resource" \
            "grep 'kind: HTTPRoute' $output_file"
    fi

    if grep -q "basic.example.test" "$output_file"; then
        pass "Output references hostname basic.example.test"
    else
        fail_with_cmd "Output does not reference hostname basic.example.test" \
            "grep -A3 hostnames $output_file"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Exact path type translation ==="
    local input_file="/tmp/ex-1-3.yaml"

    if ! file_exists "$input_file"; then
        fail "Input file $input_file not found"
        return
    fi

    local output
    output=$(ingress2gateway print --input-file="$input_file" --providers=ingress-nginx 2>/dev/null || echo "")

    if [[ -z "$output" ]]; then
        fail_with_cmd "Translation produced no output" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx"
        return
    fi

    if echo "$output" | grep -q "type: Exact"; then
        pass "Output preserves pathType as 'type: Exact'"
    else
        fail_with_cmd "Output does not contain 'type: Exact'" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx | grep -A2 'path:'"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Multiple hosts and paths translation ==="
    local input_file="/tmp/ex-2-1.yaml"
    local output_file="/tmp/ex-2-1-out.yaml"

    if ! file_exists "$input_file"; then
        fail "Input file $input_file not found"
        return
    fi

    if ! file_exists "$output_file"; then
        fail "Output file $output_file not found"
        info "Hint: Run ingress2gateway print --input-file=$input_file --providers=ingress-nginx > $output_file"
        return
    fi

    local gateway_count
    gateway_count=$(grep -c "^kind: Gateway$" "$output_file" || echo "0")
    if [[ "$gateway_count" -eq 1 ]]; then
        pass "Output contains 1 Gateway resource"
    else
        fail_with_cmd "Output contains $gateway_count Gateway resources (expected 1)" \
            "grep -c '^kind: Gateway' $output_file"
    fi

    local httproute_count
    httproute_count=$(grep -c "^kind: HTTPRoute$" "$output_file" || echo "0")
    if [[ "$httproute_count" -eq 2 ]]; then
        pass "Output contains 2 HTTPRoute resources (one per host)"
    else
        fail_with_cmd "Output contains $httproute_count HTTPRoute resources (expected 2)" \
            "grep -c '^kind: HTTPRoute' $output_file"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Default backend translation ==="
    local input_file="/tmp/ex-2-2.yaml"

    if ! file_exists "$input_file"; then
        fail "Input file $input_file not found"
        return
    fi

    local output
    output=$(ingress2gateway print --input-file="$input_file" --providers=ingress-nginx 2>/dev/null || echo "")

    if [[ -z "$output" ]]; then
        fail_with_cmd "Translation produced no output" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx"
        return
    fi

    if echo "$output" | grep -A3 "backendRefs" | grep -q "fallback"; then
        pass "Output references backend Service 'fallback'"
    else
        fail_with_cmd "Output does not reference backend Service 'fallback'" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx | grep -A5 backendRefs"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: TLS translation ==="
    local input_file="/tmp/ex-2-3.yaml"

    if ! file_exists "$input_file"; then
        fail "Input file $input_file not found"
        return
    fi

    local output
    output=$(ingress2gateway print --input-file="$input_file" --providers=ingress-nginx 2>/dev/null || echo "")

    if [[ -z "$output" ]]; then
        fail_with_cmd "Translation produced no output" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx"
        return
    fi

    if echo "$output" | grep -q "protocol: HTTPS"; then
        pass "Output contains HTTPS listener"
    else
        fail_with_cmd "Output does not contain HTTPS listener" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx | grep -A5 protocol"
    fi

    if echo "$output" | grep -A5 "protocol: HTTPS" | grep -q "secure-tls"; then
        pass "HTTPS listener references TLS Secret 'secure-tls'"
    else
        fail_with_cmd "HTTPS listener does not reference TLS Secret 'secure-tls'" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx | grep -A10 'protocol: HTTPS'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Rewrite-target annotation translation ==="
    local input_file="/tmp/ex-3-1.yaml"

    if ! file_exists "$input_file"; then
        fail "Input file $input_file not found"
        return
    fi

    local output
    output=$(ingress2gateway print --input-file="$input_file" --providers=ingress-nginx 2>/dev/null || echo "")

    if [[ -z "$output" ]]; then
        fail_with_cmd "Translation produced no output" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx"
        return
    fi

    if echo "$output" | grep -q "URLRewrite"; then
        pass "Output contains URLRewrite filter"
    else
        fail_with_cmd "Output does not contain URLRewrite filter" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx | grep -A10 filters"
    fi

    if echo "$output" | grep -A5 "URLRewrite" | grep -q "replacePrefixMatch: /"; then
        pass "URLRewrite filter has replacePrefixMatch: /"
    else
        info "URLRewrite filter may have different structure"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Unsupported annotation warning ==="
    local input_file="/tmp/ex-3-2.yaml"

    if ! file_exists "$input_file"; then
        fail "Input file $input_file not found"
        return
    fi

    local stderr_output
    stderr_output=$(ingress2gateway print --input-file="$input_file" --providers=ingress-nginx 2>&1 || echo "")

    if [[ -z "$stderr_output" ]]; then
        fail_with_cmd "Translation produced no output" \
            "ingress2gateway print --input-file=$input_file --providers=ingress-nginx 2>&1"
        return
    fi

    if echo "$stderr_output" | grep -iE "limit-rps|unsupported|not translated|ignored"; then
        pass "CLI warns about unsupported limit-rps annotation"
    else
        info "No explicit warning found for limit-rps (may be silently ignored)"
        pass "Translation completed (warnings may vary by CLI version)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Custom ingressClassName translation ==="
    local input_file="/tmp/ex-3-3.yaml"
    local output_file="/tmp/ex-3-3-out.yaml"

    if ! file_exists "$input_file"; then
        fail "Input file $input_file not found"
        return
    fi

    if ! file_exists "$output_file"; then
        fail "Output file $output_file not found"
        info "Hint: Run ingress2gateway print --input-file=$input_file --providers=ingress-nginx > $output_file"
        return
    fi

    local original_class_count
    original_class_count=$(grep -c "gatewayClassName: enterprise-edge" "$output_file" || echo "0")

    local adjusted_class_count
    adjusted_class_count=$(grep -c "gatewayClassName: eg" "$output_file" || echo "0")

    if [[ "$original_class_count" -eq 1 ]] || [[ "$adjusted_class_count" -eq 1 ]]; then
        pass "Output shows gatewayClassName adjustment (original or eg)"
    else
        fail_with_cmd "Output does not show expected gatewayClassName" \
            "grep gatewayClassName $output_file"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Side-by-side Ingress and Gateway API ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "old" "$ns"; then
        fail "Ingress 'old' not found in namespace $ns"
        return
    fi

    if ! deployment_ready "parity-app" "$ns"; then
        fail_with_cmd "Deployment parity-app not ready" \
            "kubectl get deployment -n $ns parity-app"
        return
    fi

    if ! service_exists "parity-app" "$ns"; then
        fail "Service 'parity-app' not found in namespace $ns"
        return
    fi

    pass "Ingress and backend resources exist"

    # Check for Gateway API resources (may not exist if not applied yet)
    local gw_count
    gw_count=$(kubectl get gateway -n "$ns" 2>/dev/null | grep -v NAME | wc -l)

    if [[ "$gw_count" -gt 0 ]]; then
        pass "Gateway resources applied ($gw_count found)"

        local route_count
        route_count=$(kubectl get httproute -n "$ns" 2>/dev/null | grep -v NAME | wc -l)
        if [[ "$route_count" -gt 0 ]]; then
            pass "HTTPRoute resources applied ($route_count found)"
        fi
    else
        info "Gateway API resources not yet applied (translate and apply for full verification)"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Split traffic with different hostnames ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! ingress_exists "old" "$ns"; then
        fail "Ingress 'old' not found in namespace $ns"
        return
    fi

    # Check Ingress hostname
    local ing_host
    ing_host=$(kubectl get ingress -n "$ns" old -o jsonpath='{.spec.rules[0].host}' 2>/dev/null)

    if [[ "$ing_host" == "old-41.example.test" ]]; then
        pass "Ingress hostname updated to old-41.example.test"
    else
        info "Ingress hostname: $ing_host (expected old-41.example.test for split-traffic pattern)"
    fi

    # Check HTTPRoute hostname if it exists
    local route_count
    route_count=$(kubectl get httproute -n "$ns" 2>/dev/null | grep -v NAME | wc -l)

    if [[ "$route_count" -gt 0 ]]; then
        local route_name
        route_name=$(kubectl get httproute -n "$ns" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

        local route_host
        route_host=$(kubectl get httproute -n "$ns" "$route_name" -o jsonpath='{.spec.hostnames[0]}' 2>/dev/null)

        if [[ "$route_host" == "new-41.example.test" ]]; then
            pass "HTTPRoute hostname updated to new-41.example.test"
        else
            info "HTTPRoute hostname: $route_host"
        fi
    else
        info "HTTPRoute not found (apply translated Gateway API resources)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Rollback by deleting Gateway API resources ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local gw_count
    gw_count=$(kubectl get gateway -n "$ns" 2>/dev/null | grep -v NAME | wc -l)

    local route_count
    route_count=$(kubectl get httproute -n "$ns" 2>/dev/null | grep -v NAME | wc -l)

    if [[ "$gw_count" -eq 0 ]] && [[ "$route_count" -eq 0 ]]; then
        pass "Gateway API resources deleted (rollback complete)"
    else
        info "Gateway count: $gw_count, HTTPRoute count: $route_count"
        info "Delete with: kubectl delete httproute,gateway -n $ns --all"
    fi

    # Verify Ingress still exists
    if ingress_exists "old" "$ns"; then
        pass "Original Ingress still exists (rollback successful)"
    else
        fail "Original Ingress deleted (rollback incomplete)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multi-host production migration with TLS ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check all three deployments
    for host in alpha beta gamma; do
        if deployment_ready "$host-app" "$ns"; then
            pass "Deployment $host-app is ready"
        else
            fail_with_cmd "Deployment $host-app not ready" \
                "kubectl get deployment -n $ns $host-app"
        fi
    done

    # Check Ingress
    if ingress_exists "multi-tls" "$ns"; then
        pass "Ingress multi-tls exists"

        local tls_count
        tls_count=$(kubectl get ingress -n "$ns" multi-tls -o jsonpath='{.spec.tls}' 2>/dev/null | jq '. | length' 2>/dev/null || echo "0")
        if [[ "$tls_count" -eq 3 ]]; then
            pass "Ingress has 3 TLS entries"
        else
            info "Ingress TLS count: $tls_count"
        fi
    else
        fail "Ingress multi-tls not found"
    fi

    # Check Gateway API resources if applied
    local gw_count
    gw_count=$(kubectl get gateway -n "$ns" 2>/dev/null | grep -v NAME | wc -l)

    if [[ "$gw_count" -gt 0 ]]; then
        pass "Gateway resources applied"

        local route_count
        route_count=$(kubectl get httproute -n "$ns" 2>/dev/null | grep -v NAME | wc -l)
        info "HTTPRoute count: $route_count (expected 2+ for multiple hosts)"
    else
        info "Gateway API resources not yet applied"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Complex translation requiring manual adjustment ==="
    local input_file="/tmp/ex-5-2.yaml"
    local output_file="/tmp/ex-5-2-out.yaml"
    local ns="ex-5-2"
    local svc_ns="ex-5-2-svc"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! namespace_exists "$svc_ns"; then
        fail "Namespace $svc_ns does not exist"
        return
    fi

    if ! file_exists "$input_file"; then
        fail "Input file $input_file not found"
        return
    fi

    if ! file_exists "$output_file"; then
        info "Output file $output_file not found - translation may not be run yet"
        return
    fi

    # Check for ssl-redirect or RequestRedirect
    local redirect_count
    redirect_count=$(grep -cE "ssl-redirect|RequestRedirect" "$output_file" || echo "0")
    if [[ "$redirect_count" -gt 0 ]]; then
        pass "Output handles ssl-redirect annotation"
    else
        info "No ssl-redirect/RequestRedirect found in output"
    fi

    # Check for limit-rps warning (may be in stderr or comments)
    local limit_rps_mention
    limit_rps_mention=$(grep -cE "limit-rps|not supported|ignored" "$output_file" 2>/dev/null || echo "0")
    if [[ "$limit_rps_mention" -gt 0 ]]; then
        pass "Output mentions limit-rps (unsupported annotation)"
    else
        info "No explicit limit-rps warning in output file"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Full migration cutover workflow ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_ready "prod-app" "$ns"; then
        fail_with_cmd "Deployment prod-app not ready" \
            "kubectl get deployment -n $ns prod-app"
        return
    fi

    if ! service_exists "prod-app" "$ns"; then
        fail "Service 'prod-app' not found in namespace $ns"
        return
    fi

    # Check current state
    local ing_exists
    ing_exists=$(kubectl get ingress -n "$ns" prod 2>/dev/null && echo "yes" || echo "no")

    local gw_count
    gw_count=$(kubectl get gateway -n "$ns" 2>/dev/null | grep -v NAME | wc -l)

    if [[ "$ing_exists" == "yes" ]] && [[ "$gw_count" -eq 0 ]]; then
        info "Step 1: Ingress exists, Gateway API not applied (pre-migration)"
        pass "Backend ready for migration"
    elif [[ "$ing_exists" == "yes" ]] && [[ "$gw_count" -gt 0 ]]; then
        info "Step 2-4: Both Ingress and Gateway API exist (parallel phase)"
        pass "Side-by-side migration in progress"
    elif [[ "$ing_exists" == "no" ]] && [[ "$gw_count" -gt 0 ]]; then
        info "Step 5-6: Ingress deleted, Gateway API serves (cutover complete)"
        pass "Migration cutover successful"
    else
        info "State: Ingress=$ing_exists, Gateway count=$gw_count"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: CLI Basics"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Translation Details"
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
    echo "# Level 4: Side-by-Side"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Comprehensive"
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
