#!/usr/bin/env bash
#
# verify.sh - Automated verification for services-homework.md (assignment 2)
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

# Helper: get target port
get_target_port() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null
}

# Helper: get NodePort
get_nodeport() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null
}

# Helper: get external IP
get_external_ip() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null
}

# Helper: get external name
get_external_name() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.externalName}' 2>/dev/null
}

# Helper: get selector
get_selector() {
    local svc=$1
    local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.selector}' 2>/dev/null
}

# Helper: check endpoints exist
endpoints_exist() {
    local ep=$1
    local ns=$2
    kubectl get endpoints "$ep" -n "$ns" &>/dev/null
}

# Helper: get endpoint count
get_endpoint_count() {
    local ep=$1
    local ns=$2
    local count
    count=$(kubectl get endpoints "$ep" -n "$ns" -o jsonpath='{.subsets[0].addresses}' 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    echo "$count"
}

# Helper: get endpoint IPs
get_endpoint_ips() {
    local ep=$1
    local ns=$2
    kubectl get endpoints "$ep" -n "$ns" -o jsonpath='{.subsets[0].addresses[*].ip}' 2>/dev/null
}

# Helper: check endpointslice exists
endpointslice_exists() {
    local eps=$1
    local ns=$2
    kubectl get endpointslice "$eps" -n "$ns" &>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: NodePort with automatic port allocation ==="
    local svc="app-svc"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    local type
    type=$(get_service_type "$svc" "$ns")
    if [[ "$type" == "NodePort" ]]; then
        pass "Service type is NodePort"
    else
        fail_with_cmd "Service type is $type (expected NodePort)" \
            "kubectl get service $svc -n $ns"
        return
    fi

    local nodeport
    nodeport=$(get_nodeport "$svc" "$ns")
    if [[ -n "$nodeport" ]] && [[ "$nodeport" -ge 30000 ]] && [[ "$nodeport" -le 32767 ]]; then
        pass "NodePort is in valid range: $nodeport"
    else
        fail_with_cmd "NodePort $nodeport is not in valid range (30000-32767)" \
            "kubectl get service $svc -n $ns -o yaml"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: NodePort with specific ports ==="
    local svc="web-svc"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    local nodeport
    nodeport=$(get_nodeport "$svc" "$ns")
    if [[ "$nodeport" == "30180" ]]; then
        pass "NodePort is 30180"
    else
        fail_with_cmd "NodePort is $nodeport (expected 30180)" \
            "kubectl get service $svc -n $ns -o jsonpath='{.spec.ports[0].nodePort}'"
    fi

    local port
    port=$(get_service_port "$svc" "$ns")
    if [[ "$port" == "8080" ]]; then
        pass "Service port is 8080"
    else
        fail_with_cmd "Service port is $port (expected 8080)" \
            "kubectl get service $svc -n $ns -o jsonpath='{.spec.ports[0].port}'"
    fi

    local targetport
    targetport=$(get_target_port "$svc" "$ns")
    if [[ "$targetport" == "80" ]]; then
        pass "Target port is 80"
    else
        fail_with_cmd "Target port is $targetport (expected 80)" \
            "kubectl get service $svc -n $ns -o jsonpath='{.spec.ports[0].targetPort}'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: NodePort accessible from all nodes ==="
    local svc="single-pod"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    local nodeport
    nodeport=$(get_nodeport "$svc" "$ns")
    if [[ -n "$nodeport" ]]; then
        pass "NodePort allocated: $nodeport"
        info "NodePort should be accessible via all node IPs (tested manually)"
    else
        fail_with_cmd "NodePort not allocated" \
            "kubectl get service $svc -n $ns -o yaml"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: LoadBalancer service with metallb ==="
    local svc="lb-svc"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    local type
    type=$(get_service_type "$svc" "$ns")
    if [[ "$type" == "LoadBalancer" ]]; then
        pass "Service type is LoadBalancer"
    else
        fail_with_cmd "Service type is $type (expected LoadBalancer)" \
            "kubectl get service $svc -n $ns"
        return
    fi

    sleep 3  # Wait for metallb to assign IP

    local external_ip
    external_ip=$(get_external_ip "$svc" "$ns")
    if [[ -n "$external_ip" ]] && [[ "$external_ip" != "<pending>" ]]; then
        pass "External IP assigned: $external_ip"
    else
        fail_with_cmd "External IP not assigned (still pending)" \
            "kubectl get service $svc -n $ns; kubectl describe service $svc -n $ns"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: ExternalName service ==="
    local svc="google-dns"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    local type
    type=$(get_service_type "$svc" "$ns")
    if [[ "$type" == "ExternalName" ]]; then
        pass "Service type is ExternalName"
    else
        fail_with_cmd "Service type is $type (expected ExternalName)" \
            "kubectl get service $svc -n $ns"
        return
    fi

    local external_name
    external_name=$(get_external_name "$svc" "$ns")
    if [[ "$external_name" == "dns.google" ]]; then
        pass "External name is dns.google"
    else
        fail_with_cmd "External name is $external_name (expected dns.google)" \
            "kubectl get service $svc -n $ns -o jsonpath='{.spec.externalName}'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Compare service types ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check ClusterIP service
    if service_exists "svc-clusterip" "$ns"; then
        local type
        type=$(get_service_type "svc-clusterip" "$ns")
        if [[ "$type" == "ClusterIP" ]]; then
            pass "svc-clusterip type is ClusterIP"
        else
            fail "svc-clusterip type is $type (expected ClusterIP)"
        fi
    else
        fail "Service svc-clusterip not found"
    fi

    # Check NodePort service
    if service_exists "svc-nodeport" "$ns"; then
        local type
        type=$(get_service_type "svc-nodeport" "$ns")
        if [[ "$type" == "NodePort" ]]; then
            pass "svc-nodeport type is NodePort"
        else
            fail "svc-nodeport type is $type (expected NodePort)"
        fi

        local nodeport
        nodeport=$(get_nodeport "svc-nodeport" "$ns")
        if [[ -n "$nodeport" ]]; then
            pass "svc-nodeport has NodePort allocated: $nodeport"
        else
            fail "svc-nodeport does not have NodePort allocated"
        fi
    else
        fail "Service svc-nodeport not found"
    fi

    # Check LoadBalancer service
    if service_exists "svc-loadbalancer" "$ns"; then
        local type
        type=$(get_service_type "svc-loadbalancer" "$ns")
        if [[ "$type" == "LoadBalancer" ]]; then
            pass "svc-loadbalancer type is LoadBalancer"
        else
            fail "svc-loadbalancer type is $type (expected LoadBalancer)"
        fi

        sleep 3  # Wait for external IP
        local external_ip
        external_ip=$(get_external_ip "svc-loadbalancer" "$ns")
        if [[ -n "$external_ip" ]] && [[ "$external_ip" != "<pending>" ]]; then
            pass "svc-loadbalancer has external IP: $external_ip"
        else
            fail "svc-loadbalancer does not have external IP (still pending)"
        fi
    else
        fail "Service svc-loadbalancer not found"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix LoadBalancer pending issue ==="
    local svc="lb-pending"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    sleep 3  # Wait for metallb

    local external_ip
    external_ip=$(get_external_ip "$svc" "$ns")
    if [[ -n "$external_ip" ]] && [[ "$external_ip" != "<pending>" ]]; then
        pass "External IP assigned (issue fixed): $external_ip"
    else
        fail_with_cmd "External IP still pending (issue not fixed)" \
            "kubectl describe service $svc -n $ns; kubectl get ipaddresspool -n metallb-system"
        info "Hint: Check if loadBalancerIP is outside metallb IP pool"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix NodePort not accessible ==="
    local svc="nodeport-broken"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    local targetport
    targetport=$(get_target_port "$svc" "$ns")
    if [[ "$targetport" == "80" ]]; then
        pass "Target port is 80 (issue fixed)"
    else
        fail_with_cmd "Target port is $targetport (should be 80, not 8080)" \
            "kubectl get service $svc -n $ns -o yaml"
        info "Hint: Check targetPort matches container port"
    fi

    if endpoints_exist "$svc" "$ns"; then
        local count
        count=$(get_endpoint_count "$svc" "$ns")
        if [[ "$count" -gt 0 ]]; then
            pass "Service has $count endpoint(s)"
        else
            fail "Service has no endpoints"
        fi
    else
        fail "Endpoints not found"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix ExternalName DNS issue ==="
    local svc="external-broken"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    local type
    type=$(get_service_type "$svc" "$ns")
    if [[ "$type" == "ExternalName" ]]; then
        pass "Service type is ExternalName"
    else
        fail "Service type is $type (expected ExternalName)"
        return
    fi

    local external_name
    external_name=$(get_external_name "$svc" "$ns")
    # Check if it's a DNS name (not an IP address like 8.8.8.8)
    if [[ "$external_name" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fail_with_cmd "External name is an IP address ($external_name), should be a DNS name" \
            "kubectl get service $svc -n $ns -o jsonpath='{.spec.externalName}'"
        info "Hint: ExternalName must be a DNS name, not an IP address"
    else
        if [[ -n "$external_name" ]]; then
            pass "External name is a DNS name (issue fixed): $external_name"
        else
            fail "External name is not set"
        fi
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Service without selector with manual endpoints ==="
    local svc="manual-svc"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    local selector
    selector=$(get_selector "$svc" "$ns")
    if [[ -z "$selector" ]] || [[ "$selector" == "{}" ]] || [[ "$selector" == "map[]" ]] || [[ "$selector" == "null" ]]; then
        pass "Service has no selector"
    else
        fail_with_cmd "Service has selector: $selector (expected no selector)" \
            "kubectl get service $svc -n $ns -o jsonpath='{.spec.selector}'"
    fi

    if endpoints_exist "$svc" "$ns"; then
        pass "Endpoints resource exists"
    else
        fail_with_cmd "Endpoints resource not found" \
            "kubectl get endpoints -n $ns"
        return
    fi

    local count
    count=$(get_endpoint_count "$svc" "$ns")
    if [[ "$count" == "2" ]]; then
        pass "Endpoints has 2 addresses"
    else
        fail_with_cmd "Endpoints has $count addresses (expected 2)" \
            "kubectl get endpoints $svc -n $ns -o yaml"
    fi

    local ips
    ips=$(get_endpoint_ips "$svc" "$ns")
    if [[ "$ips" == *"10.10.10.1"* ]] && [[ "$ips" == *"10.10.10.2"* ]]; then
        pass "Endpoints include correct IPs (10.10.10.1, 10.10.10.2)"
    else
        fail_with_cmd "Endpoints IPs are: $ips (expected 10.10.10.1 and 10.10.10.2)" \
            "kubectl get endpoints $svc -n $ns -o jsonpath='{.subsets[0].addresses[*].ip}'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: EndpointSlice for selectorless service ==="
    local eps="slice-svc-endpoints"
    local svc="slice-svc"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! endpointslice_exists "$eps" "$ns"; then
        fail_with_cmd "EndpointSlice $eps not found in namespace $ns" \
            "kubectl get endpointslices -n $ns"
        return
    fi

    pass "EndpointSlice exists"

    local count
    count=$(kubectl get endpointslice "$eps" -n "$ns" -o jsonpath='{.endpoints}' 2>/dev/null | jq 'length' 2>/dev/null || echo "0")
    if [[ "$count" == "3" ]]; then
        pass "EndpointSlice has 3 endpoints"
    else
        fail_with_cmd "EndpointSlice has $count endpoints (expected 3)" \
            "kubectl get endpointslice $eps -n $ns -o yaml"
    fi

    local service_label
    service_label=$(kubectl get endpointslice "$eps" -n "$ns" -o jsonpath='{.metadata.labels.kubernetes\.io/service-name}' 2>/dev/null)
    if [[ "$service_label" == "$svc" ]]; then
        pass "EndpointSlice associated with service $svc"
    else
        fail_with_cmd "EndpointSlice not associated with service (label: $service_label)" \
            "kubectl get endpointslice $eps -n $ns -o jsonpath='{.metadata.labels}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Update manual endpoints ==="
    local svc="dynamic-svc"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! endpoints_exist "$svc" "$ns"; then
        fail_with_cmd "Endpoints $svc not found in namespace $ns" \
            "kubectl get endpoints -n $ns"
        return
    fi

    local count
    count=$(get_endpoint_count "$svc" "$ns")
    if [[ "$count" == "3" ]]; then
        pass "Endpoints has 3 addresses (new count)"
    else
        fail_with_cmd "Endpoints has $count addresses (expected 3)" \
            "kubectl get endpoints $svc -n $ns -o yaml"
    fi

    local ips
    ips=$(get_endpoint_ips "$svc" "$ns")

    # Check new IPs are present
    if [[ "$ips" == *"10.0.1.100"* ]]; then
        pass "New IP 10.0.1.100 present"
    else
        fail "New IP 10.0.1.100 not found"
    fi

    if [[ "$ips" == *"10.0.1.101"* ]]; then
        pass "New IP 10.0.1.101 present"
    else
        fail "New IP 10.0.1.101 not found"
    fi

    if [[ "$ips" == *"10.0.1.102"* ]]; then
        pass "New IP 10.0.1.102 present"
    else
        fail "New IP 10.0.1.102 not found"
    fi

    # Check old IPs are removed
    if [[ "$ips" == *"10.0.0.1"* ]]; then
        fail "Old IP 10.0.0.1 still present (should be removed)"
    else
        pass "Old IP 10.0.0.1 removed"
    fi

    if [[ "$ips" == *"10.0.0.2"* ]]; then
        fail "Old IP 10.0.0.2 still present (should be removed)"
    else
        pass "Old IP 10.0.0.2 removed"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: External database services ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check postgres-primary service
    if service_exists "postgres-primary" "$ns"; then
        pass "Service postgres-primary exists"

        local count
        count=$(get_endpoint_count "postgres-primary" "$ns")
        if [[ "$count" == "1" ]]; then
            pass "postgres-primary has 1 endpoint"
        else
            fail_with_cmd "postgres-primary has $count endpoints (expected 1)" \
                "kubectl get endpoints postgres-primary -n $ns -o yaml"
        fi

        local ip
        ip=$(get_endpoint_ips "postgres-primary" "$ns")
        if [[ "$ip" == "10.100.0.10" ]]; then
            pass "postgres-primary endpoint IP is 10.100.0.10"
        else
            fail "postgres-primary endpoint IP is $ip (expected 10.100.0.10)"
        fi
    else
        fail "Service postgres-primary not found"
    fi

    # Check postgres-replicas service
    if service_exists "postgres-replicas" "$ns"; then
        pass "Service postgres-replicas exists"

        local count
        count=$(get_endpoint_count "postgres-replicas" "$ns")
        if [[ "$count" == "2" ]]; then
            pass "postgres-replicas has 2 endpoints"
        else
            fail_with_cmd "postgres-replicas has $count endpoints (expected 2)" \
                "kubectl get endpoints postgres-replicas -n $ns -o yaml"
        fi

        local ips
        ips=$(get_endpoint_ips "postgres-replicas" "$ns")
        if [[ "$ips" == *"10.100.0.11"* ]] && [[ "$ips" == *"10.100.0.12"* ]]; then
            pass "postgres-replicas endpoints include 10.100.0.11 and 10.100.0.12"
        else
            fail "postgres-replicas endpoints are: $ips (expected 10.100.0.11 and 10.100.0.12)"
        fi
    else
        fail "Service postgres-replicas not found"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Migrate from NodePort to LoadBalancer ==="
    local svc="migrate-svc"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! service_exists "$svc" "$ns"; then
        fail_with_cmd "Service $svc not found in namespace $ns" \
            "kubectl get services -n $ns"
        return
    fi

    local type
    type=$(get_service_type "$svc" "$ns")
    if [[ "$type" == "LoadBalancer" ]]; then
        pass "Service type is LoadBalancer (migrated)"
    else
        fail_with_cmd "Service type is $type (expected LoadBalancer)" \
            "kubectl get service $svc -n $ns"
        return
    fi

    local nodeport
    nodeport=$(get_nodeport "$svc" "$ns")
    if [[ "$nodeport" == "30500" ]]; then
        pass "NodePort preserved: 30500"
    else
        fail_with_cmd "NodePort is $nodeport (expected 30500 to be preserved)" \
            "kubectl get service $svc -n $ns -o jsonpath='{.spec.ports[0].nodePort}'"
    fi

    sleep 3  # Wait for external IP

    local external_ip
    external_ip=$(get_external_ip "$svc" "$ns")
    if [[ -n "$external_ip" ]] && [[ "$external_ip" != "<pending>" ]]; then
        pass "External IP assigned: $external_ip"
    else
        fail_with_cmd "External IP not assigned" \
            "kubectl get service $svc -n $ns; kubectl describe service $svc -n $ns"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Multi-tier application external access ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check frontend service
    if service_exists "frontend-svc" "$ns"; then
        local type
        type=$(get_service_type "frontend-svc" "$ns")
        if [[ "$type" == "LoadBalancer" ]]; then
            pass "frontend-svc type is LoadBalancer"
        else
            fail "frontend-svc type is $type (expected LoadBalancer)"
        fi

        sleep 3  # Wait for external IP
        local external_ip
        external_ip=$(get_external_ip "frontend-svc" "$ns")
        if [[ -n "$external_ip" ]] && [[ "$external_ip" != "<pending>" ]]; then
            pass "frontend-svc has external IP: $external_ip"
        else
            fail "frontend-svc does not have external IP"
        fi
    else
        fail "Service frontend-svc not found"
    fi

    # Check API service
    if service_exists "api-svc" "$ns"; then
        local type
        type=$(get_service_type "api-svc" "$ns")
        if [[ "$type" == "ClusterIP" ]]; then
            pass "api-svc type is ClusterIP (internal only)"
        else
            fail "api-svc type is $type (expected ClusterIP)"
        fi
    else
        fail "Service api-svc not found"
    fi

    # Check legacy backend service
    if service_exists "legacy-backend" "$ns"; then
        pass "Service legacy-backend exists"

        local selector
        selector=$(get_selector "legacy-backend" "$ns")
        if [[ -z "$selector" ]] || [[ "$selector" == "{}" ]] || [[ "$selector" == "map[]" ]] || [[ "$selector" == "null" ]]; then
            pass "legacy-backend has no selector (manual endpoints)"
        else
            fail "legacy-backend has selector (expected manual endpoints)"
        fi

        if endpoints_exist "legacy-backend" "$ns"; then
            local ips
            ips=$(get_endpoint_ips "legacy-backend" "$ns")
            if [[ "$ips" == *"10.200.0.50"* ]]; then
                pass "legacy-backend endpoint is 10.200.0.50"
            else
                fail "legacy-backend endpoint is $ips (expected 10.200.0.50)"
            fi
        else
            fail "legacy-backend endpoints not found"
        fi
    else
        fail "Service legacy-backend not found"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: NodePort Services"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: LoadBalancer and ExternalName"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging External Service Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Manual Endpoints"
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
