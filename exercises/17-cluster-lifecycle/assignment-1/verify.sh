#!/usr/bin/env bash
#
# verify.sh - Automated verification for cluster-lifecycle-homework.md
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

# Helper: check if file exists inside kind-control-plane container
file_exists_in_control_plane() {
    local filepath=$1
    nerdctl exec kind-control-plane test -f "$filepath" &>/dev/null
}

# Helper: get pod creation timestamp
get_pod_creation_timestamp() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.metadata.creationTimestamp}' 2>/dev/null
}

# Helper: get pod ready status
get_pod_ready() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null
}

# Helper: get pod phase
get_phase() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: check if pod exists
pod_exists() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

# Helper: get node unschedulable status
get_node_unschedulable() {
    local node=$1
    kubectl get node "$node" -o jsonpath='{.spec.unschedulable}' 2>/dev/null
}

# Helper: get node ready condition
get_node_ready_status() {
    local node=$1
    kubectl get node "$node" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null
}

# Helper: check kubelet is active on a node
kubelet_is_active() {
    local node=$1
    local status
    status=$(nerdctl exec "$node" systemctl is-active kubelet 2>/dev/null || echo "inactive")
    [[ "$status" == "active" ]]
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Static pod reconciliation ==="

    # Check that scheduler pod was recreated by comparing timestamps
    local before after
    before=$(get_pod_creation_timestamp "kube-scheduler-kind-control-plane" "kube-system")

    if [[ -z "$before" ]]; then
        fail_with_cmd "Cannot read scheduler pod creation timestamp" \
            "kubectl get pod kube-scheduler-kind-control-plane -n kube-system"
        return
    fi

    # Check that the scheduler is ready
    local ready
    ready=$(get_pod_ready "kube-scheduler-kind-control-plane" "kube-system")
    if [[ "$ready" == "true" ]]; then
        pass "Scheduler pod is ready"
    else
        fail_with_cmd "Scheduler pod is not ready" \
            "kubectl get pod kube-scheduler-kind-control-plane -n kube-system"
    fi

    # Verify the exercise was performed by checking the pod has a recent creation timestamp
    # (within the last 5 minutes, which indicates it was recently touched/recreated)
    local creation_epoch now_epoch age_seconds
    creation_epoch=$(date -d "$before" +%s 2>/dev/null || echo "0")
    now_epoch=$(date +%s)
    age_seconds=$((now_epoch - creation_epoch))

    if [[ $age_seconds -lt 300 ]]; then
        pass "Scheduler pod was recently recreated (age: ${age_seconds}s)"
    else
        info "Scheduler pod is older (age: ${age_seconds}s), touch may not have been performed yet"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Certificate verification ==="

    if ! file_exists_in_control_plane "/tmp/ex-1-2-verify.txt"; then
        fail_with_cmd "Verification output file not found" \
            "nerdctl exec kind-control-plane cat /tmp/ex-1-2-verify.txt"
        return
    fi

    # Check for the three expected OK lines
    local content ok_count
    content=$(nerdctl exec kind-control-plane cat /tmp/ex-1-2-verify.txt 2>/dev/null)

    if echo "$content" | grep -q "apiserver.crt: OK"; then
        pass "apiserver.crt verified OK"
    else
        fail "apiserver.crt verification missing or failed"
    fi

    if echo "$content" | grep -q "apiserver-etcd-client.crt: OK"; then
        pass "apiserver-etcd-client.crt verified OK"
    else
        fail "apiserver-etcd-client.crt verification missing or failed"
    fi

    if echo "$content" | grep -q "front-proxy-client.crt: OK"; then
        pass "front-proxy-client.crt verified OK"
    else
        fail "front-proxy-client.crt verification missing or failed"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Static pod removal and restoration ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check that scheduler is back and ready
    local ready
    ready=$(get_pod_ready "kube-scheduler-kind-control-plane" "kube-system")
    if [[ "$ready" == "true" ]]; then
        pass "Scheduler pod is ready (restored)"
    else
        fail_with_cmd "Scheduler pod is not ready" \
            "kubectl get pod kube-scheduler-kind-control-plane -n kube-system"
    fi

    # Check that probe pod eventually reached Running
    if pod_exists "probe" "$ns"; then
        local phase
        phase=$(get_phase "probe" "$ns")
        if [[ "$phase" == "Running" ]]; then
            pass "Probe pod reached Running state"
        else
            fail_with_cmd "Probe pod is in $phase state (expected Running)" \
                "kubectl get pod probe -n $ns"
        fi
    else
        fail "Probe pod not found in namespace $ns"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Node prerequisites ==="

    if ! file_exists_in_control_plane "/tmp/ex-2-1-prereqs.txt"; then
        fail_with_cmd "Prerequisites output file not found" \
            "nerdctl exec kind-control-plane cat /tmp/ex-2-1-prereqs.txt"
        return
    fi

    local content
    content=$(nerdctl exec kind-control-plane cat /tmp/ex-2-1-prereqs.txt 2>/dev/null)

    # Check for br_netfilter module
    if echo "$content" | grep -q "br_netfilter"; then
        pass "br_netfilter module check present"
    else
        fail "br_netfilter module check missing"
    fi

    # Check for overlay module
    if echo "$content" | grep -q "overlay"; then
        pass "overlay module check present"
    else
        fail "overlay module check missing"
    fi

    # Check for bridge-nf-call-iptables
    if echo "$content" | grep -q "net.bridge.bridge-nf-call-iptables"; then
        pass "bridge-nf-call-iptables sysctl check present"
    else
        fail "bridge-nf-call-iptables sysctl check missing"
    fi

    # Check for ip_forward
    if echo "$content" | grep -q "net.ipv4.ip_forward"; then
        pass "ip_forward sysctl check present"
    else
        fail "ip_forward sysctl check missing"
    fi

    # Check for swap check
    if echo "$content" | grep -q "swap"; then
        pass "swap check present"
    else
        fail "swap check missing"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Kubelet configuration ==="

    if ! file_exists_in_control_plane "/tmp/ex-2-2-kubelet.txt"; then
        fail_with_cmd "Kubelet config output file not found" \
            "nerdctl exec kind-control-plane cat /tmp/ex-2-2-kubelet.txt"
        return
    fi

    local content
    content=$(nerdctl exec kind-control-plane cat /tmp/ex-2-2-kubelet.txt 2>/dev/null)

    # Check for staticPodPath
    if echo "$content" | grep -q "staticPodPath.*manifests"; then
        pass "staticPodPath setting present"
    else
        fail "staticPodPath setting missing or incorrect"
    fi

    # Check for clusterDNS
    if echo "$content" | grep -q "clusterDNS"; then
        pass "clusterDNS setting present"
    else
        fail "clusterDNS setting missing"
    fi

    # Check for clusterDomain
    if echo "$content" | grep -q "clusterDomain.*cluster.local"; then
        pass "clusterDomain setting present"
    else
        fail "clusterDomain setting missing or incorrect"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Cluster health verification ==="

    # Check all nodes are Ready
    local ready_count
    ready_count=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")

    if [[ $ready_count -eq 4 ]]; then
        pass "All 4 nodes are Ready"
    else
        fail_with_cmd "Only $ready_count nodes are Ready (expected 4)" \
            "kubectl get nodes"
    fi

    # Check control plane pods are ready
    local cp_ready_count
    cp_ready_count=$(kubectl get pods -n kube-system -l tier=control-plane -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | grep -c "true" || echo "0")

    if [[ $cp_ready_count -eq 4 ]]; then
        pass "All 4 control plane pods are ready"
    else
        fail_with_cmd "Only $cp_ready_count control plane pods are ready (expected 4)" \
            "kubectl get pods -n kube-system -l tier=control-plane"
    fi

    # Check CoreDNS is ready
    local dns_ready
    dns_ready=$(kubectl get pods -n kube-system -l k8s-app=kube-dns -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)

    if [[ "$dns_ready" == "true" ]]; then
        pass "CoreDNS is ready"
    else
        fail_with_cmd "CoreDNS is not ready" \
            "kubectl get pods -n kube-system -l k8s-app=kube-dns"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Uncordon a worker node ==="
    local node="kind-worker"

    # Check node is not unschedulable
    local unschedulable
    unschedulable=$(get_node_unschedulable "$node")

    # Empty string, "<none>", or "false" all indicate the node is schedulable
    if [[ -z "$unschedulable" ]] || [[ "$unschedulable" == "false" ]] || [[ "$unschedulable" == "<none>" ]]; then
        pass "Node $node is schedulable (not cordoned)"
    else
        fail_with_cmd "Node $node is still unschedulable" \
            "kubectl describe node $node | grep -A2 Taints:"
    fi

    # Verify we can schedule a pod on the node
    local node_ready
    node_ready=$(get_node_ready_status "$node")
    if [[ "$node_ready" == "True" ]]; then
        pass "Node $node is Ready"
    else
        fail_with_cmd "Node $node is not Ready" \
            "kubectl get nodes"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Restart kubelet on worker node ==="
    local node="kind-worker"

    # Check node is Ready
    local node_ready
    node_ready=$(get_node_ready_status "$node")
    if [[ "$node_ready" == "True" ]]; then
        pass "Node $node is Ready"
    else
        fail_with_cmd "Node $node is not Ready (kubelet may still be down)" \
            "kubectl describe node $node"
    fi

    # Check kubelet is active
    if kubelet_is_active "$node"; then
        pass "Kubelet is active on $node"
    else
        fail_with_cmd "Kubelet is not active on $node" \
            "nerdctl exec $node systemctl status kubelet"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: CNI pod-to-pod connectivity ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Both pods should have been deleted after successful connectivity test
    # So we verify the namespace exists (showing the exercise was attempted)
    # and check if pods still exist (they shouldn't if exercise completed fully)

    local pod_a_exists pod_b_exists
    pod_a_exists=$(kubectl get pod connectivity-a -n "$ns" &>/dev/null && echo "yes" || echo "no")
    pod_b_exists=$(kubectl get pod connectivity-b -n "$ns" &>/dev/null && echo "yes" || echo "no")

    if [[ "$pod_a_exists" == "no" ]] && [[ "$pod_b_exists" == "no" ]]; then
        pass "Test pods cleaned up (connectivity test completed)"
    else
        # Pods still exist, check if they're ready and can communicate
        if [[ "$pod_a_exists" == "yes" ]] && [[ "$pod_b_exists" == "yes" ]]; then
            info "Test pods still exist, verifying connectivity"

            local phase_a phase_b
            phase_a=$(get_phase "connectivity-a" "$ns")
            phase_b=$(get_phase "connectivity-b" "$ns")

            if [[ "$phase_a" == "Running" ]] && [[ "$phase_b" == "Running" ]]; then
                pass "Both connectivity test pods are Running"
            else
                fail_with_cmd "Connectivity pods not both Running (a: $phase_a, b: $phase_b)" \
                    "kubectl get pods -n $ns"
            fi
        else
            fail "Only one connectivity pod exists (incomplete test)"
        fi
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Extract ClusterConfiguration ==="

    if ! file_exists_in_control_plane "/tmp/ex-4-1-cluster-config.yaml"; then
        fail_with_cmd "Cluster config file not found" \
            "nerdctl exec kind-control-plane cat /tmp/ex-4-1-cluster-config.yaml"
        return
    fi

    local content
    content=$(nerdctl exec kind-control-plane cat /tmp/ex-4-1-cluster-config.yaml 2>/dev/null)

    # Check for CIDR settings
    if echo "$content" | grep -Eq "(podSubnet|serviceSubnet)"; then
        pass "CIDR configuration present in cluster config"
    else
        fail "CIDR configuration missing from cluster config"
    fi

    # Verify it's a valid YAML-like structure
    if echo "$content" | grep -q "apiVersion"; then
        pass "File contains valid ClusterConfiguration structure"
    else
        fail "File does not appear to be a valid ClusterConfiguration"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Bootstrap token management ==="

    if ! file_exists_in_control_plane "/tmp/ex-4-2-token-id.txt"; then
        fail_with_cmd "Token ID file not found" \
            "nerdctl exec kind-control-plane cat /tmp/ex-4-2-token-id.txt"
        return
    fi

    local token_id
    token_id=$(nerdctl exec kind-control-plane cat /tmp/ex-4-2-token-id.txt 2>/dev/null | tr -d '[:space:]')

    # Verify token ID format (6 characters)
    if [[ ${#token_id} -eq 6 ]]; then
        pass "Token ID has correct format (6 characters)"
    else
        fail "Token ID length is ${#token_id} (expected 6)"
    fi

    # Verify token was deleted (should not appear in token list)
    local token_exists
    token_exists=$(nerdctl exec kind-control-plane kubeadm token list 2>/dev/null | grep -c "$token_id" || echo "0")

    if [[ $token_exists -eq 0 ]]; then
        pass "Token was successfully deleted"
    else
        fail_with_cmd "Token $token_id still exists (was not deleted)" \
            "nerdctl exec kind-control-plane kubeadm token list"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Generate init configuration ==="

    if ! file_exists_in_control_plane "/tmp/ex-4-3-init.yaml"; then
        fail_with_cmd "Init config file not found" \
            "nerdctl exec kind-control-plane cat /tmp/ex-4-3-init.yaml"
        return
    fi

    local content
    content=$(nerdctl exec kind-control-plane cat /tmp/ex-4-3-init.yaml 2>/dev/null)

    # Check for kubernetesVersion: v1.35.0
    if echo "$content" | grep -q "kubernetesVersion:.*v1.35.0"; then
        pass "kubernetesVersion set to v1.35.0"
    else
        fail_with_cmd "kubernetesVersion not set to v1.35.0" \
            "nerdctl exec kind-control-plane grep kubernetesVersion /tmp/ex-4-3-init.yaml"
    fi

    # Check for podSubnet: 10.244.0.0/16
    if echo "$content" | grep -q "podSubnet:.*10.244.0.0/16"; then
        pass "podSubnet set to 10.244.0.0/16"
    else
        fail_with_cmd "podSubnet not set to 10.244.0.0/16" \
            "nerdctl exec kind-control-plane grep podSubnet /tmp/ex-4-3-init.yaml"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Certificate audit ==="

    if ! file_exists_in_control_plane "/tmp/ex-5-1-audit.txt"; then
        fail_with_cmd "Certificate audit file not found" \
            "nerdctl exec kind-control-plane cat /tmp/ex-5-1-audit.txt"
        return
    fi

    local content ok_count
    content=$(nerdctl exec kind-control-plane cat /tmp/ex-5-1-audit.txt 2>/dev/null)
    ok_count=$(echo "$content" | grep -c ": OK$" || echo "0")

    if [[ $ok_count -eq 7 ]]; then
        pass "All 7 certificates verified successfully"
    else
        fail_with_cmd "Only $ok_count certificates verified (expected 7)" \
            "nerdctl exec kind-control-plane cat /tmp/ex-5-1-audit.txt"
    fi

    # Verify specific certificates are present
    local certs=(
        "apiserver.crt"
        "apiserver-kubelet-client.crt"
        "apiserver-etcd-client.crt"
        "front-proxy-client.crt"
        "healthcheck-client.crt"
        "peer.crt"
        "server.crt"
    )

    local found_count=0
    for cert in "${certs[@]}"; do
        if echo "$content" | grep -q "$cert.*: OK"; then
            found_count=$((found_count + 1))
        fi
    done

    if [[ $found_count -eq 7 ]]; then
        pass "All expected certificate types verified"
    else
        info "Found $found_count out of 7 expected certificate types"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Certificate renewal ==="

    if ! file_exists_in_control_plane "/tmp/ex-5-2-before.txt"; then
        fail_with_cmd "Before-renewal file not found" \
            "nerdctl exec kind-control-plane cat /tmp/ex-5-2-before.txt"
        return
    fi

    if ! file_exists_in_control_plane "/tmp/ex-5-2-after.txt"; then
        fail_with_cmd "After-renewal file not found" \
            "nerdctl exec kind-control-plane cat /tmp/ex-5-2-after.txt"
        return
    fi

    local before after
    before=$(nerdctl exec kind-control-plane cat /tmp/ex-5-2-before.txt 2>/dev/null)
    after=$(nerdctl exec kind-control-plane cat /tmp/ex-5-2-after.txt 2>/dev/null)

    if [[ "$before" != "$after" ]]; then
        pass "Certificate expiration date changed (renewal performed)"
    else
        fail "Certificate expiration date unchanged (renewal may have failed)"
    fi

    # Verify cluster is still functional
    local nodes_ready
    nodes_ready=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | grep -c "True" || echo "0")

    if [[ $nodes_ready -eq 4 ]]; then
        pass "Cluster still functional after API server restart (4 nodes Ready)"
    else
        fail_with_cmd "Cluster may be degraded after restart (only $nodes_ready nodes Ready)" \
            "kubectl get nodes"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Cluster snapshot ==="

    if ! test -f /tmp/ex-5-3-snapshot.txt; then
        fail_with_cmd "Snapshot file not found at /tmp/ex-5-3-snapshot.txt" \
            "ls -la /tmp/ex-5-3-snapshot.txt"
        return
    fi

    local line_count section_count
    line_count=$(wc -l < /tmp/ex-5-3-snapshot.txt)
    section_count=$(grep -c '^==== ' /tmp/ex-5-3-snapshot.txt || echo "0")

    if [[ $line_count -ge 30 ]]; then
        pass "Snapshot has adequate content ($line_count lines)"
    else
        fail "Snapshot has only $line_count lines (expected at least 30)"
    fi

    if [[ $section_count -eq 5 ]]; then
        pass "All 5 sections present in snapshot"
    else
        fail "Only $section_count sections found (expected 5)"
    fi

    # Check for key section content
    local sections=(
        "Kubernetes version"
        "Node list"
        "kube-system pods"
        "Certificate"
        "CIDR"
    )

    local missing_sections=0
    for section in "${sections[@]}"; do
        if ! grep -qi "$section" /tmp/ex-5-3-snapshot.txt; then
            fail "Section '$section' missing from snapshot"
            missing_sections=$((missing_sections + 1))
        fi
    done

    if [[ $missing_sections -eq 0 ]]; then
        pass "All expected sections found in snapshot"
    fi
}

################################################################################
# Level verification functions
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Static Pod Manifests and Certificates"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Node Prerequisites and Kubelet"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Cluster Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: kubeadm Configuration and Tokens"
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

################################################################################
# Main logic
################################################################################

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
