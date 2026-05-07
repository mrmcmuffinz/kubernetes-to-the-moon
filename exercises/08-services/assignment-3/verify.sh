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

# Helper: get service port count
get_port_count() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports}' 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0"
}

# Helper: get port name by index
get_port_name() {
    local svc=$1
    local ns=$2
    local index=$3
    kubectl get service "$svc" -n "$ns" -o jsonpath="{.spec.ports[$index].name}" 2>/dev/null
}

# Helper: get port number by index
get_port_number() {
    local svc=$1
    local ns=$2
    local index=$3
    kubectl get service "$svc" -n "$ns" -o jsonpath="{.spec.ports[$index].port}" 2>/dev/null
}

# Helper: get protocol by index
get_protocol() {
    local svc=$1
    local ns=$2
    local index=$3
    kubectl get service "$svc" -n "$ns" -o jsonpath="{.spec.ports[$index].protocol}" 2>/dev/null
}

# Helper: get session affinity
get_session_affinity() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.sessionAffinity}' 2>/dev/null
}

# Helper: get session affinity timeout
get_session_affinity_timeout() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.sessionAffinityConfig.clientIP.timeoutSeconds}' 2>/dev/null
}

# Helper: get external traffic policy
get_external_traffic_policy() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.externalTrafficPolicy}' 2>/dev/null
}

# Helper: get NodePort
get_node_port() {
    local svc=$1
    local ns=$2
    local index=${3:-0}
    kubectl get service "$svc" -n "$ns" -o jsonpath="{.spec.ports[$index].nodePort}" 2>/dev/null
}

# Helper: check if endpoints are populated
endpoints_exist() {
    local svc=$1
    local ns=$2
    local count
    count=$(kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0")
    [[ "$count" -gt 0 ]]
}

# Helper: get endpoint count
get_endpoint_count() {
    local svc=$1
    local ns=$2
    kubectl get endpoints "$svc" -n "$ns" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | jq -r 'length' 2>/dev/null || echo "0"
}

# Helper: get ready pod count
get_ready_pod_count() {
    local ns=$1
    local selector=$2
    kubectl get pods -n "$ns" -l "$selector" --no-headers 2>/dev/null | grep -c "1/1" || echo "0"
}

# Helper: get deployment replicas
get_deployment_replicas() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null
}

# Helper: check if deployment has readiness probe
deployment_has_readiness_probe() {
    local name=$1
    local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}' 2>/dev/null | grep -q "httpGet"
}

# Helper: get ClusterIP
get_cluster_ip() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.clusterIP}' 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Multi-port service with named ports ==="
    local svc="web-svc"
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

    local port_count
    port_count=$(get_port_count "$svc" "$ns")
    if [[ "$port_count" -eq 2 ]]; then
        pass "Service has 2 ports"
    else
        fail_with_cmd "Service has $port_count ports (expected 2)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}' | jq"
    fi

    local port0_name
    port0_name=$(get_port_name "$svc" "$ns" 0)
    if [[ "$port0_name" == "http" ]]; then
        pass "First port is named 'http'"
    else
        fail_with_cmd "First port name is '$port0_name' (expected 'http')" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports[0]}' | jq"
    fi

    local port1_name
    port1_name=$(get_port_name "$svc" "$ns" 1)
    if [[ "$port1_name" == "https" ]]; then
        pass "Second port is named 'https'"
    else
        fail_with_cmd "Second port name is '$port1_name' (expected 'https')" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports[1]}' | jq"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Service with TCP and UDP ports ==="
    local svc="dns-svc"
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

    local port_count
    port_count=$(get_port_count "$svc" "$ns")
    if [[ "$port_count" -eq 2 ]]; then
        pass "Service has 2 ports"
    else
        fail_with_cmd "Service has $port_count ports (expected 2)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}' | jq"
    fi

    local has_tcp=false
    local has_udp=false
    for i in 0 1; do
        local protocol
        protocol=$(get_protocol "$svc" "$ns" "$i")
        if [[ "$protocol" == "TCP" ]]; then
            has_tcp=true
        elif [[ "$protocol" == "UDP" ]]; then
            has_udp=true
        fi
    done

    if [[ "$has_tcp" == "true" ]]; then
        pass "Service has TCP port"
    else
        fail_with_cmd "Service missing TCP port" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}' | jq"
    fi

    if [[ "$has_udp" == "true" ]]; then
        pass "Service has UDP port"
    else
        fail_with_cmd "Service missing UDP port" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports}' | jq"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Access different ports of multi-port service ==="
    local svc="multi-svc"
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

    info "Testing multi-port service connectivity"

    # The exercise is about testing access, not creating resources
    # We just verify the service exists and has endpoints
    if endpoints_exist "$svc" "$ns"; then
        pass "Service has endpoints"
    else
        fail_with_cmd "Service has no endpoints" \
            "kubectl get endpoints $svc -n $ns"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Session affinity ==="
    local svc="sticky-svc"
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

    local affinity
    affinity=$(get_session_affinity "$svc" "$ns")
    if [[ "$affinity" == "ClientIP" ]]; then
        pass "Session affinity is ClientIP"
    else
        fail_with_cmd "Session affinity is '$affinity' (expected 'ClientIP')" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.sessionAffinity}'"
    fi

    local timeout
    timeout=$(get_session_affinity_timeout "$svc" "$ns")
    if [[ "$timeout" == "600" ]]; then
        pass "Session affinity timeout is 600 seconds"
    else
        fail_with_cmd "Session affinity timeout is '$timeout' (expected 600)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.sessionAffinityConfig}' | jq"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: External traffic policy Local ==="
    local svc="source-ip-svc"
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

    local svc_type
    svc_type=$(get_service_type "$svc" "$ns")
    if [[ "$svc_type" == "NodePort" ]]; then
        pass "Service type is NodePort"
    else
        fail_with_cmd "Service type is '$svc_type' (expected 'NodePort')" \
            "kubectl get svc $svc -n $ns"
    fi

    local policy
    policy=$(get_external_traffic_policy "$svc" "$ns")
    if [[ "$policy" == "Local" ]]; then
        pass "External traffic policy is Local"
    else
        fail_with_cmd "External traffic policy is '$policy' (expected 'Local')" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.externalTrafficPolicy}'"
    fi

    local nodeport
    nodeport=$(get_node_port "$svc" "$ns")
    if [[ "$nodeport" == "30280" ]]; then
        pass "NodePort is 30280"
    else
        fail_with_cmd "NodePort is '$nodeport' (expected 30280)" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.ports[0].nodePort}'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Compare traffic policies ==="
    local svc1="policy-cluster-svc"
    local svc2="policy-local-svc"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc1" "$ns"; then
        fail_with_cmd "Service $svc1 not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    if ! service_exists "$svc2" "$ns"; then
        fail_with_cmd "Service $svc2 not found in namespace $ns" \
            "kubectl get svc -n $ns"
        return
    fi

    local policy1
    policy1=$(get_external_traffic_policy "$svc1" "$ns")
    if [[ "$policy1" == "Cluster" ]]; then
        pass "policy-cluster-svc has Cluster policy"
    else
        fail_with_cmd "policy-cluster-svc policy is '$policy1' (expected 'Cluster')" \
            "kubectl get svc $svc1 -n $ns -o jsonpath='{.spec.externalTrafficPolicy}'"
    fi

    local policy2
    policy2=$(get_external_traffic_policy "$svc2" "$ns")
    if [[ "$policy2" == "Local" ]]; then
        pass "policy-local-svc has Local policy"
    else
        fail_with_cmd "policy-local-svc policy is '$policy2' (expected 'Local')" \
            "kubectl get svc $svc2 -n $ns -o jsonpath='{.spec.externalTrafficPolicy}'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix selector mismatch ==="
    local svc="selector-svc"
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

    if endpoints_exist "$svc" "$ns"; then
        pass "Service has endpoints (selector fixed)"
    else
        fail_with_cmd "Service has no endpoints (selector still mismatched)" \
            "kubectl get endpoints $svc -n $ns && kubectl get svc $svc -n $ns -o wide && kubectl get pods -n $ns --show-labels"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix targetPort mismatch ==="
    local svc="port-svc"
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

    if endpoints_exist "$svc" "$ns"; then
        pass "Service has endpoints"
    else
        fail_with_cmd "Service has no endpoints" \
            "kubectl get endpoints $svc -n $ns"
        return
    fi

    info "Verify connectivity manually: kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -it -n $ns -- curl -s http://port-svc:8080"
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix readiness probe ==="
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
        fail_with_cmd "$ready_count pods ready (expected 3)" \
            "kubectl get pods -n $ns -l app=ready-app"
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
    echo "=== Exercise 4.1: Fix intermittent failures ==="
    local svc="flaky-svc"
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

    local ready_count
    ready_count=$(get_ready_pod_count "$ns" "app=flaky-app")
    if [[ "$ready_count" -eq 3 ]]; then
        pass "All 3 pods are ready"
    else
        fail_with_cmd "$ready_count pods ready (expected 3 - one pod likely has failing readiness)" \
            "kubectl get pods -n $ns -l app=flaky-app"
    fi

    local endpoint_count
    endpoint_count=$(get_endpoint_count "$svc" "$ns")
    if [[ "$endpoint_count" -eq 3 ]]; then
        pass "Service has 3 endpoints"
    else
        fail_with_cmd "Service has $endpoint_count endpoints (expected 3)" \
            "kubectl get endpoints $svc -n $ns && kubectl describe pods -n $ns -l app=flaky-app | grep -A5 Readiness"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Fix named port reference ==="
    local svc="named-port-svc"
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

    if endpoints_exist "$svc" "$ns"; then
        pass "Service has endpoints"
    else
        fail_with_cmd "Service has no endpoints" \
            "kubectl get endpoints $svc -n $ns"
        return
    fi

    info "Verify connectivity manually: kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -it -n $ns -- curl -s http://named-port-svc"
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Traffic policy effects ==="
    local svc="single-node-svc"
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

    local policy
    policy=$(get_external_traffic_policy "$svc" "$ns")
    if [[ "$policy" == "Cluster" ]]; then
        pass "External traffic policy changed to Cluster (accessible from all nodes)"
        info "Alternative: Policy kept as Local with documentation explaining behavior"
    elif [[ "$policy" == "Local" ]]; then
        info "Policy is still Local - verify documentation explains limited accessibility"
        pass "Policy configuration present (check if documented correctly)"
    else
        fail_with_cmd "External traffic policy is '$policy' (expected 'Cluster' or 'Local')" \
            "kubectl get svc $svc -n $ns -o jsonpath='{.spec.externalTrafficPolicy}'"
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

    # Database tier
    if service_exists "database-svc" "$ns"; then
        local cluster_ip
        cluster_ip=$(get_cluster_ip "database-svc" "$ns")
        if [[ "$cluster_ip" == "None" ]]; then
            pass "Database service is headless (clusterIP: None)"
        else
            fail_with_cmd "Database service clusterIP is '$cluster_ip' (expected 'None' for headless)" \
                "kubectl get svc database-svc -n $ns"
        fi
    else
        fail_with_cmd "Database service not found" \
            "kubectl get svc -n $ns"
    fi

    # Backend tier
    if service_exists "backend-svc" "$ns"; then
        local affinity
        affinity=$(get_session_affinity "backend-svc" "$ns")
        if [[ "$affinity" == "ClientIP" ]]; then
            pass "Backend service has session affinity"
        else
            fail_with_cmd "Backend session affinity is '$affinity' (expected 'ClientIP')" \
                "kubectl get svc backend-svc -n $ns -o jsonpath='{.spec.sessionAffinity}'"
        fi

        local timeout
        timeout=$(get_session_affinity_timeout "backend-svc" "$ns")
        if [[ "$timeout" == "3600" ]]; then
            pass "Backend session affinity timeout is 3600s (1 hour)"
        else
            fail_with_cmd "Backend timeout is '$timeout' (expected 3600)" \
                "kubectl get svc backend-svc -n $ns -o jsonpath='{.spec.sessionAffinityConfig}' | jq"
        fi
    else
        fail_with_cmd "Backend service not found" \
            "kubectl get svc -n $ns"
    fi

    # Frontend tier
    if service_exists "frontend-svc" "$ns"; then
        local svc_type
        svc_type=$(get_service_type "frontend-svc" "$ns")
        if [[ "$svc_type" == "LoadBalancer" ]]; then
            pass "Frontend service is LoadBalancer"
        else
            fail_with_cmd "Frontend service type is '$svc_type' (expected 'LoadBalancer')" \
                "kubectl get svc frontend-svc -n $ns"
        fi
    else
        fail_with_cmd "Frontend service not found" \
            "kubectl get svc -n $ns"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Multi-failure debugging ==="
    local svc="multi-fail-svc"
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
    ready_count=$(get_ready_pod_count "$ns" "app=multi-fail")
    if [[ "$ready_count" -eq 3 ]]; then
        pass "All 3 pods are ready (readiness probe fixed)"
    else
        fail_with_cmd "$ready_count pods ready (expected 3 - check readiness probe path)" \
            "kubectl get pods -n $ns -l app=multi-fail && kubectl describe pods -n $ns -l app=multi-fail | grep -A5 Readiness"
    fi

    if endpoints_exist "$svc" "$ns"; then
        pass "Service has endpoints (selector fixed)"
    else
        fail_with_cmd "Service has no endpoints (selector still mismatched)" \
            "kubectl get endpoints $svc -n $ns && kubectl get svc $svc -n $ns -o wide && kubectl get pods -n $ns --show-labels"
    fi

    info "Verify connectivity manually: kubectl run curl-test --image=curlimages/curl:8.5.0 --rm -it -n $ns -- curl -s http://multi-fail-svc"
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Resilient service design ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Deployment checks
    if kubectl get deployment api-server -n "$ns" &>/dev/null; then
        local replicas
        replicas=$(get_deployment_replicas "api-server" "$ns")
        if [[ "$replicas" == "4" ]]; then
            pass "Deployment has 4 replicas"
        else
            fail_with_cmd "Deployment has $replicas replicas (expected 4)" \
                "kubectl get deployment api-server -n $ns"
        fi

        if deployment_has_readiness_probe "api-server" "$ns"; then
            pass "Deployment has readiness probe"
        else
            fail_with_cmd "Deployment missing readiness probe" \
                "kubectl get deployment api-server -n $ns -o jsonpath='{.spec.template.spec.containers[0]}' | jq"
        fi
    else
        fail_with_cmd "Deployment api-server not found" \
            "kubectl get deployments -n $ns"
    fi

    # Service checks
    if service_exists "api-svc" "$ns"; then
        local svc_type
        svc_type=$(get_service_type "api-svc" "$ns")
        if [[ "$svc_type" == "LoadBalancer" ]]; then
            pass "Service type is LoadBalancer"
        else
            fail_with_cmd "Service type is '$svc_type' (expected 'LoadBalancer')" \
                "kubectl get svc api-svc -n $ns"
        fi

        local affinity
        affinity=$(get_session_affinity "api-svc" "$ns")
        if [[ "$affinity" == "ClientIP" ]]; then
            pass "Service has session affinity"
        else
            fail_with_cmd "Session affinity is '$affinity' (expected 'ClientIP')" \
                "kubectl get svc api-svc -n $ns -o jsonpath='{.spec.sessionAffinity}'"
        fi

        local policy
        policy=$(get_external_traffic_policy "api-svc" "$ns")
        if [[ "$policy" == "Cluster" ]]; then
            pass "External traffic policy is Cluster"
        else
            fail_with_cmd "External traffic policy is '$policy' (expected 'Cluster')" \
                "kubectl get svc api-svc -n $ns -o jsonpath='{.spec.externalTrafficPolicy}'"
        fi

        local ready_count
        ready_count=$(get_ready_pod_count "$ns" "app=api-server")
        if [[ "$ready_count" == "4" ]]; then
            pass "All 4 pods are ready"
        else
            info "$ready_count/4 pods ready (may still be starting)"
        fi
    else
        fail_with_cmd "Service api-svc not found" \
            "kubectl get svc -n $ns"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Multi-Port Services"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Session Affinity and Traffic Policies"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Service Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Advanced Troubleshooting"
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
