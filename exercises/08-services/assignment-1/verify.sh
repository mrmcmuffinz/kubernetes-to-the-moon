#!/usr/bin/env bash
#
# verify.sh - Automated verification for services-homework.md
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

# Helper: check if service exists
service_exists() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" &>/dev/null
}

# Helper: get service type
get_service_type() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.type}' 2>/dev/null
}

# Helper: get service port
get_service_port() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null
}

# Helper: get service target port
get_service_target_port() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null
}

# Helper: get service node port
get_service_node_port() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null
}

# Helper: get service cluster IP
get_service_cluster_ip() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.clusterIP}' 2>/dev/null
}

# Helper: get service selector
get_service_selector() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.selector}' 2>/dev/null
}

# Helper: get endpoint count
get_endpoint_count() {
    local svc=$1
    local ns=$2
    kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0"
}

# Helper: check if endpoints exist
has_endpoints() {
    local svc=$1
    local ns=$2
    local count
    count=$(get_endpoint_count "$svc" "$ns")
    [[ "$count" -gt 0 ]]
}

# Helper: get pod count by label
get_pod_count() {
    local ns=$1
    local label=$2
    kubectl get pods -n "$ns" -l "$label" --no-headers 2>/dev/null | wc -l
}

# Helper: get ready pod count by label
get_ready_pod_count() {
    local ns=$1
    local label=$2
    kubectl get pods -n "$ns" -l "$label" --no-headers 2>/dev/null | grep -c "1/1" || echo "0"
}

# Helper: test connectivity to a service
test_connectivity() {
    local svc=$1
    local ns=$2
    local port=${3:-80}
    local pattern=${4:-""}

    if [[ -n "$pattern" ]]; then
        kubectl run curl-test-$RANDOM --image=curlimages/curl:8.5.0 --rm -i -n "$ns" --restart=Never -- curl -s --max-time 5 "http://${svc}:${port}" 2>/dev/null | grep -q "$pattern"
    else
        kubectl run curl-test-$RANDOM --image=curlimages/curl:8.5.0 --rm -i -n "$ns" --restart=Never -- curl -s --max-time 5 "http://${svc}:${port}" &>/dev/null
    fi
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic ClusterIP service ==="
    local svc="nginx-app"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local svc_type
    svc_type=$(get_service_type "$svc" "$ns")
    if [[ "$svc_type" == "ClusterIP" ]]; then
        pass "Service type is ClusterIP"
    else
        fail_with_cmd "Service type is $svc_type (expected ClusterIP)" \
            "kubectl get svc $svc -n $ns"
    fi

    if has_endpoints "$svc" "$ns"; then
        local endpoint_count
        endpoint_count=$(get_endpoint_count "$svc" "$ns")
        if [[ "$endpoint_count" -eq 2 ]]; then
            pass "Service has 2 endpoints"
        else
            fail_with_cmd "Service has $endpoint_count endpoints (expected 2)" \
                "kubectl get endpoints $svc -n $ns"
        fi
    else
        fail_with_cmd "Service has no endpoints" \
            "kubectl get endpoints $svc -n $ns -o yaml"
    fi

    if test_connectivity "$svc" "$ns" 80 "Welcome to nginx"; then
        pass "Service connectivity works (nginx welcome page)"
    else
        fail_with_cmd "Service connectivity failed" \
            "kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -it -n $ns -- curl -s http://$svc"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Declarative ClusterIP service with port mapping ==="
    local svc="httpd-svc"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local svc_port
    svc_port=$(get_service_port "$svc" "$ns")
    if [[ "$svc_port" == "8080" ]]; then
        pass "Service port is 8080"
    else
        fail_with_cmd "Service port is $svc_port (expected 8080)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}'"
    fi

    local target_port
    target_port=$(get_service_target_port "$svc" "$ns")
    if [[ "$target_port" == "80" ]]; then
        pass "Target port is 80"
    else
        fail_with_cmd "Target port is $target_port (expected 80)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}'"
    fi

    if has_endpoints "$svc" "$ns"; then
        pass "Service has endpoints"
    else
        fail_with_cmd "Service has no endpoints" \
            "kubectl get endpoints $svc -n $ns"
    fi

    if test_connectivity "$svc" "$ns" 8080 "It works"; then
        pass "Service connectivity works on port 8080"
    else
        fail_with_cmd "Service connectivity failed" \
            "kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -it -n $ns -- curl -s http://$svc:8080"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Endpoint examination ==="
    local svc="web-app"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local endpoint_count
    endpoint_count=$(get_endpoint_count "$svc" "$ns")
    local pod_count
    pod_count=$(get_pod_count "$ns" "app=web-app")

    if [[ "$endpoint_count" -eq "$pod_count" ]]; then
        pass "Endpoint count ($endpoint_count) matches pod count ($pod_count)"
    else
        fail_with_cmd "Endpoint count ($endpoint_count) does not match pod count ($pod_count)" \
            "kubectl get endpoints $svc -n $ns && kubectl get pods -n $ns -l app=web-app"
    fi

    if [[ "$pod_count" -eq 4 ]]; then
        pass "Pod count is 4 as expected"
    else
        fail_with_cmd "Pod count is $pod_count (expected 4)" \
            "kubectl get pods -n $ns -l app=web-app"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: NodePort service ==="
    local svc="nodeport-svc"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local svc_type
    svc_type=$(get_service_type "$svc" "$ns")
    if [[ "$svc_type" == "NodePort" ]]; then
        pass "Service type is NodePort"
    else
        fail_with_cmd "Service type is $svc_type (expected NodePort)" \
            "kubectl get svc $svc -n $ns"
    fi

    local node_port
    node_port=$(get_service_node_port "$svc" "$ns")
    if [[ "$node_port" == "30100" ]]; then
        pass "NodePort is 30100"
    else
        fail_with_cmd "NodePort is $node_port (expected 30100)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}'"
    fi

    if has_endpoints "$svc" "$ns"; then
        pass "Service has endpoints"
    else
        fail_with_cmd "Service has no endpoints" \
            "kubectl get endpoints $svc -n $ns"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Headless service ==="
    local svc="headless-svc"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local cluster_ip
    cluster_ip=$(get_service_cluster_ip "$svc" "$ns")
    if [[ "$cluster_ip" == "None" ]]; then
        pass "Service ClusterIP is None (headless)"
    else
        fail_with_cmd "Service ClusterIP is $cluster_ip (expected None)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.clusterIP}'"
    fi

    local endpoint_count
    endpoint_count=$(get_endpoint_count "$svc" "$ns")
    if [[ "$endpoint_count" -eq 3 ]]; then
        pass "Service has 3 endpoints"
    else
        fail_with_cmd "Service has $endpoint_count endpoints (expected 3)" \
            "kubectl get endpoints $svc -n $ns"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Service discovery ==="
    local svc="backend-app"
    local ns="ex-2-3"
    local test_pod="discovery-test"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    # Check if test pod exists
    if ! kubectl get pod "$test_pod" -n "$ns" &>/dev/null; then
        fail_with_cmd "Test pod $test_pod not found" \
            "kubectl get pods -n $ns"
        info "Hint: Create a pod named discovery-test to test service discovery"
        return
    fi

    # Wait for pod to be ready
    sleep 2

    # Test DNS short name
    if kubectl exec -n "$ns" "$test_pod" -- wget -q -O- "http://$svc" 2>/dev/null | grep -q "nginx"; then
        pass "DNS short name works"
    else
        fail_with_cmd "DNS short name failed" \
            "kubectl exec -n $ns $test_pod -- wget -q -O- http://$svc"
    fi

    # Test DNS FQDN
    if kubectl exec -n "$ns" "$test_pod" -- wget -q -O- "http://$svc.$ns.svc.cluster.local" 2>/dev/null | grep -q "nginx"; then
        pass "DNS FQDN works"
    else
        fail_with_cmd "DNS FQDN failed" \
            "kubectl exec -n $ns $test_pod -- wget -q -O- http://$svc.$ns.svc.cluster.local"
    fi

    # Test environment variables
    if kubectl exec -n "$ns" "$test_pod" -- env 2>/dev/null | grep -q "BACKEND_APP_SERVICE_HOST"; then
        pass "Environment variables exist"
    else
        fail_with_cmd "Environment variables not found" \
            "kubectl exec -n $ns $test_pod -- env | grep BACKEND_APP"
        info "Hint: The pod must be created after the service for env vars to be injected"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug selector mismatch ==="
    local svc="debug-svc"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    if has_endpoints "$svc" "$ns"; then
        pass "Service has endpoints (issue fixed)"
    else
        fail_with_cmd "Service has no endpoints" \
            "kubectl get endpoints $svc -n $ns && kubectl get pods -n $ns --show-labels"
        info "Hint: Check if service selector matches pod labels"
        return
    fi

    if test_connectivity "$svc" "$ns" 80 "Welcome to nginx"; then
        pass "Service connectivity works"
    else
        fail_with_cmd "Service connectivity failed" \
            "kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -it -n $ns -- curl -s http://$svc"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug port mismatch ==="
    local svc="web-svc"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    if has_endpoints "$svc" "$ns"; then
        pass "Service has endpoints"
    else
        fail_with_cmd "Service has no endpoints" \
            "kubectl get endpoints $svc -n $ns"
        return
    fi

    if test_connectivity "$svc" "$ns" 80 "Welcome to nginx"; then
        pass "Service connectivity works (issue fixed)"
    else
        fail_with_cmd "Service connectivity failed" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}' && kubectl get pods -n $ns -o jsonpath='{.items[0].spec.containers[0].ports}'"
        info "Hint: Check if targetPort matches the container's listening port"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug readiness probe ==="
    local svc="ready-svc"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local ready_count
    ready_count=$(get_ready_pod_count "$ns" "app=ready-app")
    if [[ "$ready_count" -eq 3 ]]; then
        pass "All 3 pods are ready"
    else
        fail_with_cmd "Only $ready_count pods are ready (expected 3)" \
            "kubectl get pods -n $ns -l app=ready-app && kubectl describe pod -n $ns -l app=ready-app | grep -A5 Readiness"
        info "Hint: Check readiness probe configuration"
    fi

    local endpoint_count
    endpoint_count=$(get_endpoint_count "$svc" "$ns")
    if [[ "$endpoint_count" -eq 3 ]]; then
        pass "Service has 3 endpoints"
    else
        fail_with_cmd "Service has $endpoint_count endpoints (expected 3)" \
            "kubectl get endpoints $svc -n $ns"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Multi-port service ==="
    local svc="multi-port-svc"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local port_count
    port_count=$(kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports}' 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    if [[ "$port_count" -eq 2 ]]; then
        pass "Service has 2 ports"
    else
        fail_with_cmd "Service has $port_count ports (expected 2)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}'"
    fi

    if kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports[*].name}' 2>/dev/null | grep -q "http"; then
        pass "Port named 'http' exists"
    else
        fail_with_cmd "Port 'http' not found" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}'"
    fi

    if kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports[*].name}' 2>/dev/null | grep -q "metrics"; then
        pass "Port named 'metrics' exists"
    else
        fail_with_cmd "Port 'metrics' not found" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Session affinity ==="
    local svc="affinity-svc"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local session_affinity
    session_affinity=$(kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.sessionAffinity}' 2>/dev/null)
    if [[ "$session_affinity" == "ClientIP" ]]; then
        pass "Session affinity is ClientIP"
    else
        fail_with_cmd "Session affinity is $session_affinity (expected ClientIP)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.sessionAffinity}'"
    fi

    local timeout
    timeout=$(kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.sessionAffinityConfig.clientIP.timeoutSeconds}' 2>/dev/null)
    if [[ "$timeout" == "1800" ]]; then
        pass "Session affinity timeout is 1800 seconds"
    else
        fail_with_cmd "Session affinity timeout is $timeout (expected 1800)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.sessionAffinityConfig}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Service without selector ==="
    local svc="external-db"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local selector
    selector=$(get_service_selector "$svc" "$ns")
    if [[ -z "$selector" || "$selector" == "null" || "$selector" == "{}" ]]; then
        pass "Service has no selector"
    else
        fail_with_cmd "Service has selector: $selector (expected no selector)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.selector}'"
    fi

    local endpoint_count
    endpoint_count=$(get_endpoint_count "$svc" "$ns")
    if [[ "$endpoint_count" -eq 2 ]]; then
        pass "Endpoints has 2 addresses"
    else
        fail_with_cmd "Endpoints has $endpoint_count addresses (expected 2)" \
            "kubectl get endpoints $svc -n $ns -o yaml"
    fi

    if kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null | grep -q "10.0.0.100"; then
        pass "Endpoint IP 10.0.0.100 exists"
    else
        fail_with_cmd "Endpoint IP 10.0.0.100 not found" \
            "kubectl get endpoints $svc -n $ns -o yaml"
    fi

    if kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null | grep -q "10.0.0.101"; then
        pass "Endpoint IP 10.0.0.101 exists"
    else
        fail_with_cmd "Endpoint IP 10.0.0.101 not found" \
            "kubectl get endpoints $svc -n $ns -o yaml"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multi-tier application ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Database headless service
    if service_exists "db-svc" "$ns"; then
        local db_cluster_ip
        db_cluster_ip=$(get_service_cluster_ip "db-svc" "$ns")
        if [[ "$db_cluster_ip" == "None" ]]; then
            pass "Database service is headless (ClusterIP: None)"
        else
            fail_with_cmd "Database service ClusterIP is $db_cluster_ip (expected None)" \
                "kubectl get svc db-svc -n $ns"
        fi
    else
        fail_with_cmd "Database service db-svc not found" \
            "kubectl get svc -n $ns"
    fi

    # Backend ClusterIP service
    if service_exists "backend-svc" "$ns"; then
        local backend_type
        backend_type=$(get_service_type "backend-svc" "$ns")
        if [[ "$backend_type" == "ClusterIP" ]]; then
            pass "Backend service type is ClusterIP"
        else
            fail_with_cmd "Backend service type is $backend_type (expected ClusterIP)" \
                "kubectl get svc backend-svc -n $ns"
        fi

        local backend_endpoints
        backend_endpoints=$(get_endpoint_count "backend-svc" "$ns")
        if [[ "$backend_endpoints" -eq 2 ]]; then
            pass "Backend service has 2 endpoints"
        else
            fail_with_cmd "Backend service has $backend_endpoints endpoints (expected 2)" \
                "kubectl get endpoints backend-svc -n $ns"
        fi
    else
        fail_with_cmd "Backend service backend-svc not found" \
            "kubectl get svc -n $ns"
    fi

    # Frontend NodePort service
    if service_exists "frontend-svc" "$ns"; then
        local frontend_type
        frontend_type=$(get_service_type "frontend-svc" "$ns")
        if [[ "$frontend_type" == "NodePort" ]]; then
            pass "Frontend service type is NodePort"
        else
            fail_with_cmd "Frontend service type is $frontend_type (expected NodePort)" \
                "kubectl get svc frontend-svc -n $ns"
        fi

        local frontend_node_port
        frontend_node_port=$(get_service_node_port "frontend-svc" "$ns")
        if [[ "$frontend_node_port" == "30200" ]]; then
            pass "Frontend NodePort is 30200"
        else
            fail_with_cmd "Frontend NodePort is $frontend_node_port (expected 30200)" \
                "kubectl get svc frontend-svc -n $ns -o jsonpath='{.spec.ports}'"
        fi

        local frontend_endpoints
        frontend_endpoints=$(get_endpoint_count "frontend-svc" "$ns")
        if [[ "$frontend_endpoints" -eq 3 ]]; then
            pass "Frontend service has 3 endpoints"
        else
            fail_with_cmd "Frontend service has $frontend_endpoints endpoints (expected 3)" \
                "kubectl get endpoints frontend-svc -n $ns"
        fi
    else
        fail_with_cmd "Frontend service frontend-svc not found" \
            "kubectl get svc -n $ns"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug multi-issue service ==="
    local svc="api-svc"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local ready_count
    ready_count=$(get_ready_pod_count "$ns" "app=api-server")
    if [[ "$ready_count" -eq 2 ]]; then
        pass "All 2 pods are ready"
    else
        fail_with_cmd "Only $ready_count pods are ready (expected 2)" \
            "kubectl get pods -n $ns -l app=api-server && kubectl describe pod -n $ns -l app=api-server | grep -A5 Readiness"
    fi

    if has_endpoints "$svc" "$ns"; then
        pass "Service has endpoints (selector issue fixed)"
    else
        fail_with_cmd "Service has no endpoints" \
            "kubectl get endpoints $svc -n $ns && kubectl get pods -n $ns --show-labels"
        info "Hint: Check if service selector matches pod labels"
        return
    fi

    if test_connectivity "$svc" "$ns" 80 "nginx"; then
        pass "Service connectivity works (all issues fixed)"
    else
        fail_with_cmd "Service connectivity failed" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}' && kubectl get pods -n $ns -o jsonpath='{.items[0].spec.containers[0].ports}'"
        info "Hint: Check targetPort and readiness probe"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Service migration ==="
    local svc="migrate-app"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local svc_type
    svc_type=$(get_service_type "$svc" "$ns")
    if [[ "$svc_type" == "NodePort" ]]; then
        pass "Service type changed to NodePort"
    else
        fail_with_cmd "Service type is $svc_type (expected NodePort)" \
            "kubectl get svc $svc -n $ns"
    fi

    local node_port
    node_port=$(get_service_node_port "$svc" "$ns")
    if [[ "$node_port" == "30300" ]]; then
        pass "NodePort is 30300"
    else
        fail_with_cmd "NodePort is $node_port (expected 30300)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}'"
    fi

    local cluster_ip
    cluster_ip=$(get_service_cluster_ip "$svc" "$ns")
    if [[ "$cluster_ip" != "None" && -n "$cluster_ip" ]]; then
        pass "ClusterIP still exists ($cluster_ip)"
    else
        fail_with_cmd "ClusterIP is missing or None" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.clusterIP}'"
    fi

    if test_connectivity "$svc" "$ns" 80 "nginx"; then
        pass "Service accessible via ClusterIP"
    else
        fail_with_cmd "ClusterIP connectivity failed" \
            "kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -it -n $ns -- curl -s http://$svc"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic Service Creation"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Service Types and Discovery"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Broken Services"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Multi-Port Services and Advanced Configuration"
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
