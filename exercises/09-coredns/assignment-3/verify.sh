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

# Helper: check if service exists
service_exists() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" &>/dev/null
}

# Helper: get DNS policy
get_dns_policy() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.dnsPolicy}' 2>/dev/null
}

# Helper: test DNS resolution
dns_resolves() {
    local pod=$1
    local ns=$2
    local lookup=$3
    kubectl exec -n "$ns" "$pod" -- nslookup "$lookup" &>/dev/null
}

# Helper: check resolv.conf contains string
resolv_contains() {
    local pod=$1
    local ns=$2
    local pattern=$3
    kubectl exec -n "$ns" "$pod" -- cat /etc/resolv.conf 2>/dev/null | grep -q "$pattern"
}

# Helper: check if CoreDNS pods are running
coredns_running() {
    local ready_count
    ready_count=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -o "True" | wc -l)
    [[ "$ready_count" -gt 0 ]]
}

# Helper: check if kube-dns service exists
kube_dns_service_exists() {
    kubectl get svc kube-dns -n kube-system &>/dev/null
}

# Helper: check if endpoints exist for kube-dns
kube_dns_has_endpoints() {
    local endpoints
    endpoints=$(kubectl get endpoints kube-dns -n kube-system -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null)
    [[ -n "$endpoints" ]]
}

# Helper: check if NetworkPolicy exists
networkpolicy_exists() {
    local np=$1
    local ns=$2
    kubectl get networkpolicy "$np" -n "$ns" &>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Test DNS resolution ==="
    local pod="tester"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Wait for pod to be ready
    sleep 2

    # Test short name resolution
    if dns_resolves "$pod" "$ns" "backend-svc"; then
        pass "Short name resolution works (backend-svc)"
    else
        fail_with_cmd "Short name resolution failed" \
            "kubectl exec -n $ns $pod -- nslookup backend-svc"
    fi

    # Test FQDN resolution
    if dns_resolves "$pod" "$ns" "backend-svc.ex-1-1.svc.cluster.local"; then
        pass "FQDN resolution works"
    else
        fail_with_cmd "FQDN resolution failed" \
            "kubectl exec -n $ns $pod -- nslookup backend-svc.ex-1-1.svc.cluster.local"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Compare DNS policies ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "pod-clusterfirst" "$ns"; then
        fail "Pod pod-clusterfirst not found"
        return
    fi

    if ! pod_exists "pod-default" "$ns"; then
        fail "Pod pod-default not found"
        return
    fi

    # Check ClusterFirst pod has cluster DNS
    if resolv_contains "pod-clusterfirst" "$ns" "10.96.0.10"; then
        pass "ClusterFirst pod uses cluster DNS (10.96.0.10)"
    else
        fail_with_cmd "ClusterFirst pod does not use cluster DNS" \
            "kubectl exec -n $ns pod-clusterfirst -- cat /etc/resolv.conf"
    fi

    # Check ClusterFirst has search domains
    if resolv_contains "pod-clusterfirst" "$ns" "svc.cluster.local"; then
        pass "ClusterFirst pod has cluster search domains"
    else
        fail_with_cmd "ClusterFirst pod missing cluster search domains" \
            "kubectl exec -n $ns pod-clusterfirst -- cat /etc/resolv.conf"
    fi

    # Check Default pod does NOT have cluster DNS
    if ! resolv_contains "pod-default" "$ns" "10.96.0.10"; then
        pass "Default pod does not use cluster DNS"
    else
        fail_with_cmd "Default pod should not use cluster DNS" \
            "kubectl exec -n $ns pod-default -- cat /etc/resolv.conf"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Verify CoreDNS availability ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check kube-dns service exists
    if kube_dns_service_exists; then
        pass "kube-dns service exists"
    else
        fail_with_cmd "kube-dns service not found" \
            "kubectl get svc -n kube-system"
    fi

    # Check kube-dns has endpoints
    if kube_dns_has_endpoints; then
        pass "kube-dns service has endpoints"
    else
        fail_with_cmd "kube-dns service has no endpoints" \
            "kubectl get endpoints kube-dns -n kube-system"
    fi

    # Check CoreDNS pods are running
    if coredns_running; then
        pass "CoreDNS pods are running"
    else
        fail_with_cmd "CoreDNS pods not running or ready" \
            "kubectl get pods -n kube-system -l k8s-app=kube-dns"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Check CoreDNS pod status ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check CoreDNS pods are running
    if coredns_running; then
        pass "CoreDNS pods are Running and Ready"
    else
        fail_with_cmd "CoreDNS pods not ready" \
            "kubectl get pods -n kube-system -l k8s-app=kube-dns"
    fi

    # Check readiness probe is configured
    local probe
    probe=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.path}' 2>/dev/null)
    if [[ "$probe" == "/ready" ]]; then
        pass "Readiness probe configured correctly (/ready)"
    else
        fail_with_cmd "Readiness probe not configured correctly" \
            "kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}'"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: View CoreDNS logs ==="
    local pod="query-generator"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    # Generate a successful query
    if dns_resolves "$pod" "$ns" "kubernetes.default"; then
        pass "Successful DNS query works"
    else
        fail_with_cmd "Cannot resolve kubernetes.default" \
            "kubectl exec -n $ns $pod -- nslookup kubernetes.default"
    fi

    # Check CoreDNS logs are accessible
    local logs
    logs=$(kubectl logs -n kube-system -l k8s-app=kube-dns --tail=10 2>&1)
    if [[ -n "$logs" ]]; then
        pass "CoreDNS logs are accessible"
    else
        fail_with_cmd "Cannot retrieve CoreDNS logs" \
            "kubectl logs -n kube-system -l k8s-app=kube-dns --tail=30"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Verify endpoints match pod IPs ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Get endpoint IPs
    local endpoint_ips
    endpoint_ips=$(kubectl get endpoints kube-dns -n kube-system -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null | tr ' ' '\n' | sort)

    # Get pod IPs
    local pod_ips
    pod_ips=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[*].status.podIP}' 2>/dev/null | tr ' ' '\n' | sort)

    if [[ -z "$endpoint_ips" ]]; then
        fail_with_cmd "kube-dns service has no endpoints" \
            "kubectl get endpoints kube-dns -n kube-system"
        return
    fi

    if [[ "$endpoint_ips" == "$pod_ips" ]]; then
        pass "Endpoint IPs match CoreDNS pod IPs"
    else
        fail_with_cmd "Endpoint IPs do not match pod IPs" \
            "kubectl get endpoints kube-dns -n kube-system && kubectl get pods -n kube-system -l k8s-app=kube-dns -o wide"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug DNS policy issue ==="
    local pod="broken-client"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    # Check DNS policy has been fixed
    local dns_policy
    dns_policy=$(get_dns_policy "$pod" "$ns")

    if [[ "$dns_policy" == "ClusterFirst" ]]; then
        pass "DNS policy fixed to ClusterFirst"
    elif [[ "$dns_policy" == "None" ]]; then
        # Check if dnsConfig is provided
        local nameserver
        nameserver=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.dnsConfig.nameservers[0]}' 2>/dev/null)
        if [[ "$nameserver" == "10.96.0.10" ]]; then
            pass "DNS policy None with correct dnsConfig"
        else
            fail_with_cmd "DNS policy is None without proper dnsConfig" \
                "kubectl get pod $pod -n $ns -o jsonpath='{.spec.dnsPolicy}' && kubectl exec -n $ns $pod -- cat /etc/resolv.conf"
        fi
    else
        fail_with_cmd "DNS policy not properly configured (current: $dns_policy)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.dnsPolicy}'"
    fi

    # Verify DNS actually works now
    if dns_resolves "$pod" "$ns" "web-svc"; then
        pass "DNS resolution now works"
    else
        fail_with_cmd "DNS still does not resolve" \
            "kubectl exec -n $ns $pod -- nslookup web-svc"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug Network Policy blocking DNS ==="
    local pod="isolated-pod"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    # Check if Network Policy still exists
    if networkpolicy_exists "deny-all-egress" "$ns"; then
        # Policy exists, check if it allows DNS
        local has_dns_rule
        has_dns_rule=$(kubectl get networkpolicy deny-all-egress -n "$ns" -o jsonpath='{.spec.egress[*].ports[?(@.port==53)].port}' 2>/dev/null)

        if [[ -n "$has_dns_rule" ]]; then
            pass "Network Policy updated to allow DNS"
        else
            fail_with_cmd "Network Policy still blocks DNS" \
                "kubectl describe networkpolicy deny-all-egress -n $ns"
        fi
    else
        pass "Blocking Network Policy removed"
    fi

    # Verify DNS works
    if dns_resolves "$pod" "$ns" "app-svc"; then
        pass "DNS resolution now works"
    else
        fail_with_cmd "DNS still times out" \
            "timeout 5 kubectl exec -n $ns $pod -- nslookup app-svc 2>&1 || echo 'DNS lookup timed out'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug cross-namespace DNS ==="
    local pod="frontend"
    local ns="ex-3-3-frontend"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    # Short name should fail (different namespace)
    if ! dns_resolves "$pod" "$ns" "api-service"; then
        pass "Correctly understands short name won't work across namespaces"
    else
        info "Short name unexpectedly works (may have created service in this namespace)"
    fi

    # Namespace-qualified name should work
    if dns_resolves "$pod" "$ns" "api-service.ex-3-3-backend"; then
        pass "Namespace-qualified DNS resolution works"
    else
        fail_with_cmd "Namespace-qualified lookup fails" \
            "kubectl exec -n $ns $pod -- nslookup api-service.ex-3-3-backend"
    fi

    # FQDN should work
    if dns_resolves "$pod" "$ns" "api-service.ex-3-3-backend.svc.cluster.local"; then
        pass "FQDN resolution works"
    else
        fail_with_cmd "FQDN lookup fails" \
            "kubectl exec -n $ns $pod -- nslookup api-service.ex-3-3-backend.svc.cluster.local"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Debug Network Policy missing DNS rule ==="
    local pod="client"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    # Check if Network Policy has been fixed
    local has_dns_rule
    has_dns_rule=$(kubectl get networkpolicy client-egress -n "$ns" -o jsonpath='{.spec.egress[*].ports[?(@.port==53)].port}' 2>/dev/null)

    if [[ -n "$has_dns_rule" ]]; then
        pass "Network Policy updated to allow DNS"
    else
        fail_with_cmd "Network Policy still missing DNS rule" \
            "kubectl describe networkpolicy client-egress -n $ns"
    fi

    # Verify DNS works
    if dns_resolves "$pod" "$ns" "server-svc"; then
        pass "DNS resolution now works"
    else
        fail_with_cmd "DNS still fails" \
            "timeout 5 kubectl exec -n $ns $pod -- nslookup server-svc 2>&1 || echo 'DNS timed out'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Understand DNS caching ==="
    local pod="cache-tester"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    # Check if new-service was created
    if service_exists "new-service" "$ns"; then
        pass "new-service was created"
    else
        fail_with_cmd "new-service not found" \
            "kubectl get svc -n $ns"
        return
    fi

    # Check if DNS resolves (may need to wait for cache expiry)
    if dns_resolves "$pod" "$ns" "new-service"; then
        pass "DNS resolution works for new-service"
    else
        info "DNS may still be cached (NXDOMAIN). Wait 30+ seconds for cache to expire"
        sleep 30
        if dns_resolves "$pod" "$ns" "new-service"; then
            pass "DNS resolution works after cache expiry"
        else
            fail_with_cmd "DNS still fails after cache expiry" \
                "kubectl exec -n $ns $pod -- nslookup new-service"
        fi
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Cross-namespace DNS troubleshooting ==="
    local pod="webapp"
    local ns="ex-4-3-app"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    # Short name should fail
    if ! dns_resolves "$pod" "$ns" "mysql-service"; then
        pass "Short name correctly fails (different namespace)"
    else
        info "Short name unexpectedly works"
    fi

    # Namespace-qualified name should work
    if dns_resolves "$pod" "$ns" "mysql-service.ex-4-3-db"; then
        pass "Namespace-qualified lookup works"
    else
        fail_with_cmd "Namespace-qualified lookup fails" \
            "kubectl exec -n $ns $pod -- nslookup mysql-service.ex-4-3-db"
    fi

    # FQDN should work
    if dns_resolves "$pod" "$ns" "mysql-service.ex-4-3-db.svc.cluster.local"; then
        pass "FQDN lookup works"
    else
        fail_with_cmd "FQDN lookup fails" \
            "kubectl exec -n $ns $pod -- nslookup mysql-service.ex-4-3-db.svc.cluster.local"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Debug DNS policy difference ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "problem-pod" "$ns"; then
        fail "Pod problem-pod not found"
        return
    fi

    if ! pod_exists "normal-pod" "$ns"; then
        fail "Pod normal-pod not found"
        return
    fi

    # Check problem-pod DNS policy has been fixed
    local problem_dns_policy
    problem_dns_policy=$(get_dns_policy "problem-pod" "$ns")

    if [[ "$problem_dns_policy" != "Default" ]]; then
        pass "problem-pod DNS policy fixed (not Default)"
    else
        fail_with_cmd "problem-pod still has dnsPolicy: Default" \
            "kubectl get pod problem-pod -n $ns -o jsonpath='{.spec.dnsPolicy}'"
    fi

    # Verify problem-pod can now resolve services
    if dns_resolves "problem-pod" "$ns" "service-a"; then
        pass "problem-pod can now resolve services"
    else
        fail_with_cmd "problem-pod still cannot resolve services" \
            "kubectl exec -n $ns problem-pod -- nslookup service-a"
    fi

    # Verify normal-pod still works
    if dns_resolves "normal-pod" "$ns" "service-a"; then
        pass "normal-pod can resolve services"
    else
        fail_with_cmd "normal-pod cannot resolve services" \
            "kubectl exec -n $ns normal-pod -- nslookup service-a"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Investigate intermittent DNS failures ==="
    local pod="tester"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    # Run multiple DNS queries
    local success_count=0
    for i in 1 2 3 4 5; do
        if dns_resolves "$pod" "$ns" "target-svc"; then
            success_count=$((success_count + 1))
        fi
        sleep 1
    done

    if [[ $success_count -eq 5 ]]; then
        pass "All 5 DNS queries succeeded"
    elif [[ $success_count -gt 0 ]]; then
        fail "Only $success_count/5 queries succeeded (intermittent failure)"
    else
        fail_with_cmd "All queries failed" \
            "kubectl exec -n $ns $pod -- nslookup target-svc"
    fi

    # Check CoreDNS replica count
    local ready_replicas
    ready_replicas=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null)

    if [[ "$ready_replicas" -ge 2 ]]; then
        pass "CoreDNS has $ready_replicas replicas (HA setup)"
    else
        info "CoreDNS has only $ready_replicas replica (consider scaling for HA)"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: DNS troubleshooting runbook ==="
    local pod="test-pod"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found"
        return
    fi

    # Step 1: CoreDNS pods running
    if coredns_running; then
        pass "Step 1: CoreDNS pods are running"
    else
        fail_with_cmd "Step 1: CoreDNS pods not ready" \
            "kubectl get pods -n kube-system -l k8s-app=kube-dns"
    fi

    # Step 2: kube-dns service and endpoints
    if kube_dns_service_exists && kube_dns_has_endpoints; then
        pass "Step 2: kube-dns service and endpoints exist"
    else
        fail_with_cmd "Step 2: kube-dns service or endpoints missing" \
            "kubectl get svc kube-dns -n kube-system && kubectl get endpoints kube-dns -n kube-system"
    fi

    # Step 3: Pod DNS configuration
    if resolv_contains "$pod" "$ns" "10.96.0.10"; then
        pass "Step 3: Pod has correct DNS configuration"
    else
        fail_with_cmd "Step 3: Pod DNS configuration incorrect" \
            "kubectl exec -n $ns $pod -- cat /etc/resolv.conf"
    fi

    # Step 4: Test DNS from pod
    if dns_resolves "$pod" "$ns" "kubernetes.default"; then
        pass "Step 4: DNS resolution works from pod"
    else
        fail_with_cmd "Step 4: DNS resolution fails" \
            "kubectl exec -n $ns $pod -- nslookup kubernetes.default"
    fi

    # Step 5: Check for Network Policies
    local netpol_count
    netpol_count=$(kubectl get networkpolicy -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$netpol_count" -eq 0 ]]; then
        pass "Step 5: No Network Policies blocking DNS"
    else
        info "Step 5: $netpol_count Network Policy(ies) found (verify they allow DNS)"
    fi

    # Step 6: CoreDNS logs accessible
    local logs
    logs=$(kubectl logs -n kube-system -l k8s-app=kube-dns --tail=10 2>&1)
    if [[ -n "$logs" ]]; then
        pass "Step 6: CoreDNS logs are accessible"
    else
        fail_with_cmd "Step 6: Cannot access CoreDNS logs" \
            "kubectl logs -n kube-system -l k8s-app=kube-dns --tail=30"
    fi
}

################################################################################
# Level aggregation functions
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic DNS Diagnostics"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: CoreDNS Health"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging DNS Failures"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Complex DNS Issues"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Multi-Factor Failures"
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
