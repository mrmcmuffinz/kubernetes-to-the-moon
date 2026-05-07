#!/usr/bin/env bash
#
# verify.sh - Automated verification for cluster-lifecycle-homework.md (Assignment 2)
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

# Helper: check node exists
node_exists() {
    kubectl get node "$1" &>/dev/null
}

# Helper: check if node is cordoned
node_is_cordoned() {
    local node=$1
    kubectl get node "$node" -o jsonpath='{.spec.unschedulable}' 2>/dev/null | grep -q "true"
}

# Helper: check if node is schedulable
node_is_schedulable() {
    local node=$1
    local unschedulable
    unschedulable=$(kubectl get node "$node" -o jsonpath='{.spec.unschedulable}' 2>/dev/null || echo "")
    [[ "$unschedulable" != "true" ]]
}

# Helper: get pod count on node
get_pod_count_on_node() {
    local node=$1
    local ns=$2
    kubectl get pods -n "$ns" --field-selector="spec.nodeName=$node" --no-headers 2>/dev/null | wc -l
}

# Helper: get running pod count on node
get_running_pod_count_on_node() {
    local node=$1
    local ns=$2
    kubectl get pods -n "$ns" --field-selector="spec.nodeName=$node,status.phase=Running" --no-headers 2>/dev/null | wc -l
}

# Helper: deployment exists
deployment_exists() {
    local deploy=$1
    local ns=$2
    kubectl get deployment "$deploy" -n "$ns" &>/dev/null
}

# Helper: get deployment replica count
get_replicas() {
    local deploy=$1
    local ns=$2
    kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null
}

# Helper: get ready replicas
get_ready_replicas() {
    local deploy=$1
    local ns=$2
    kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"
}

# Helper: check if pod exists
pod_exists() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

# Helper: check if PDB exists
pdb_exists() {
    local pdb=$1
    local ns=$2
    kubectl get pdb "$pdb" -n "$ns" &>/dev/null
}

# Helper: get PDB minAvailable
get_pdb_min_available() {
    local pdb=$1
    local ns=$2
    kubectl get pdb "$pdb" -n "$ns" -o jsonpath='{.spec.minAvailable}' 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Check cluster version using multiple methods ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # Check if kubectl version works
    if kubectl version --short 2>/dev/null || kubectl version &>/dev/null; then
        pass "kubectl version command works"
    else
        fail_with_cmd "kubectl version command failed" \
            "kubectl version"
    fi

    # Check if get nodes works
    if kubectl get nodes -o wide &>/dev/null; then
        pass "kubectl get nodes works"
    else
        fail_with_cmd "kubectl get nodes failed" \
            "kubectl get nodes -o wide"
    fi

    # Check if API version is accessible
    if kubectl get --raw /version &>/dev/null; then
        pass "API /version endpoint accessible"
    else
        fail_with_cmd "API /version endpoint not accessible" \
            "kubectl get --raw /version"
    fi

    info "Exercise 1.1 requires checking versions using multiple methods"
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Understand version skew between components ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # Check if we can get node versions
    if kubectl get nodes -o custom-columns="NAME:.metadata.name,VERSION:.status.nodeInfo.kubeletVersion" &>/dev/null; then
        pass "Can retrieve kubelet versions from nodes"
    else
        fail_with_cmd "Cannot retrieve node versions" \
            "kubectl get nodes -o wide"
    fi

    # Check if API server version is accessible
    if kubectl version 2>/dev/null | grep -q "Server Version"; then
        pass "Can retrieve API server version"
    else
        fail_with_cmd "Cannot retrieve API server version" \
            "kubectl version"
    fi

    info "Exercise 1.2 requires documenting version differences"
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Research upgrade planning ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"
    info "Exercise 1.3 requires creating upgrade planning documentation"
    info "Document should include: version compatibility, available versions, component changes"
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Cordon a node and verify scheduling behavior ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # Check if kind-worker exists
    if ! node_exists "kind-worker"; then
        info "Node kind-worker not found (may be using different node names)"
        return
    fi

    # For this exercise, we just verify the namespace exists
    # The actual cordon/uncordon operations are ephemeral
    info "Exercise 2.1 tests cordon behavior - ensure kind-worker can be cordoned/uncordoned"
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Drain a node and verify pod eviction ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # Check if deployment exists
    if deployment_exists "drain-test" "$ns"; then
        pass "Deployment drain-test exists"

        local ready
        ready=$(get_ready_replicas "drain-test" "$ns")
        if [[ "$ready" -ge 1 ]]; then
            pass "Deployment has $ready ready replicas"
        else
            fail_with_cmd "Deployment has no ready replicas" \
                "kubectl get deployment drain-test -n $ns"
        fi
    else
        info "Deployment drain-test should exist for this exercise"
    fi

    # Check if kind-worker2 exists and is schedulable (should be uncordoned after exercise)
    if node_exists "kind-worker2"; then
        if node_is_schedulable "kind-worker2"; then
            pass "Node kind-worker2 is schedulable (uncordoned)"
        else
            fail_with_cmd "Node kind-worker2 is cordoned" \
                "kubectl uncordon kind-worker2"
        fi
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Uncordon a node and verify scheduling resumes ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # Check if kind-worker3 exists and is schedulable
    if node_exists "kind-worker3"; then
        if node_is_schedulable "kind-worker3"; then
            pass "Node kind-worker3 is schedulable (uncordoned)"
        else
            fail_with_cmd "Node kind-worker3 is still cordoned" \
                "kubectl uncordon kind-worker3"
        fi
    else
        info "Node kind-worker3 not found (may be using different node names)"
    fi

    # Check if deployment exists (may have been deleted after exercise)
    if deployment_exists "uncordon-test" "$ns"; then
        info "Deployment uncordon-test still exists (cleanup may be pending)"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix the blocking drain operation ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # The standalone pod should have been deleted during drain with --force
    if pod_exists "standalone-pod" "$ns"; then
        info "Pod standalone-pod still exists (may need to be drained with --force)"
    else
        pass "Pod standalone-pod was successfully drained (no longer exists)"
    fi

    # Check if kind-worker is schedulable (should be uncordoned after exercise)
    if node_exists "kind-worker"; then
        if node_is_schedulable "kind-worker"; then
            pass "Node kind-worker is schedulable (uncordoned)"
        else
            fail_with_cmd "Node kind-worker is still cordoned" \
                "kubectl uncordon kind-worker"
        fi
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix the blocking drain due to emptyDir ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # Check if emptydir-pod exists
    if pod_exists "emptydir-pod" "$ns"; then
        local node
        node=$(kubectl get pod emptydir-pod -n "$ns" -o jsonpath='{.spec.nodeName}' 2>/dev/null)

        if [[ -n "$node" ]]; then
            info "Pod emptydir-pod is on node $node"

            # Check if that node is schedulable
            if node_is_schedulable "$node"; then
                pass "Node $node is schedulable (uncordoned after drain)"
            else
                fail_with_cmd "Node $node is still cordoned" \
                    "kubectl uncordon $node"
            fi
        fi
    else
        info "Pod emptydir-pod was deleted (drain may have been completed)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Handle drain blocked by PodDisruptionBudget ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # Check if deployment exists
    if deployment_exists "pdb-test" "$ns"; then
        pass "Deployment pdb-test exists"
    else
        info "Deployment pdb-test should exist for this exercise"
        return
    fi

    # Check if PDB exists
    if pdb_exists "pdb-test" "$ns"; then
        pass "PodDisruptionBudget pdb-test exists"

        local min_available
        min_available=$(get_pdb_min_available "pdb-test" "$ns")

        if [[ "$min_available" == "3" ]]; then
            info "PDB minAvailable is still 3 (exercise may not be complete)"
        elif [[ "$min_available" == "1" ]]; then
            pass "PDB minAvailable was lowered to 1 (correct fix)"
        else
            info "PDB minAvailable is $min_available"
        fi
    else
        info "PodDisruptionBudget pdb-test should exist for this exercise"
    fi

    # Check if kind-worker is schedulable
    if node_exists "kind-worker"; then
        if node_is_schedulable "kind-worker"; then
            pass "Node kind-worker is schedulable (uncordoned)"
        else
            fail_with_cmd "Node kind-worker is still cordoned" \
                "kubectl uncordon kind-worker"
        fi
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Document the control plane upgrade workflow ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"
    info "Exercise 4.1 requires creating a control plane upgrade runbook"
    info "Runbook should include: upgrade kubeadm, plan, apply, drain, upgrade kubelet, uncordon"
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Create a multi-node cluster upgrade runbook ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"
    info "Exercise 4.2 requires creating a 4-node cluster upgrade runbook"
    info "Runbook should address: order of operations, draining strategy, verification between nodes"
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Verify component versions match post-upgrade ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"
    info "Exercise 4.3 requires documenting post-upgrade version verification"

    # Verify we can check versions
    if kubectl get nodes -o wide &>/dev/null; then
        pass "Can retrieve node versions"
    else
        fail_with_cmd "Cannot retrieve node versions" \
            "kubectl get nodes -o wide"
    fi

    if kubectl get pods -n kube-system -o custom-columns="NAME:.metadata.name,IMAGE:.spec.containers[0].image" &>/dev/null; then
        pass "Can retrieve control plane component images"
    else
        fail_with_cmd "Cannot retrieve component images" \
            "kubectl get pods -n kube-system -o custom-columns='NAME:.metadata.name,IMAGE:.spec.containers[0].image'"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Rolling node maintenance with workload availability ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # Check if deployment exists
    if deployment_exists "rolling-test" "$ns"; then
        pass "Deployment rolling-test exists"

        local ready
        ready=$(get_ready_replicas "rolling-test" "$ns")
        if [[ "$ready" -ge 4 ]]; then
            pass "Deployment has $ready ready replicas (meets PDB minAvailable=4)"
        else
            fail_with_cmd "Deployment has only $ready ready replicas (expected at least 4)" \
                "kubectl get deployment rolling-test -n $ns"
        fi
    else
        info "Deployment rolling-test should exist for this exercise"
        return
    fi

    # Check if PDB exists
    if pdb_exists "rolling-pdb" "$ns"; then
        pass "PodDisruptionBudget rolling-pdb exists"

        local min_available
        min_available=$(get_pdb_min_available "rolling-pdb" "$ns")
        if [[ "$min_available" == "4" ]]; then
            pass "PDB minAvailable is 4"
        else
            info "PDB minAvailable is $min_available (expected 4)"
        fi
    else
        info "PodDisruptionBudget rolling-pdb should exist for this exercise"
    fi

    # Check all worker nodes are schedulable
    for node in kind-worker kind-worker2 kind-worker3; do
        if node_exists "$node"; then
            if node_is_schedulable "$node"; then
                pass "Node $node is schedulable"
            else
                fail_with_cmd "Node $node is cordoned" \
                    "kubectl uncordon $node"
            fi
        fi
    done
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Handle drain failure and recovery ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"

    # Check if deployment exists
    if deployment_exists "fail-test" "$ns"; then
        pass "Deployment fail-test exists"

        local replicas
        replicas=$(get_replicas "fail-test" "$ns")

        if [[ "$replicas" == "3" ]]; then
            pass "Deployment replicas restored to 3 (original configuration)"
        elif [[ "$replicas" == "4" ]]; then
            info "Deployment replicas is 4 (may have been scaled up to allow drain)"
        else
            info "Deployment replicas is $replicas"
        fi
    else
        info "Deployment fail-test should exist for this exercise"
        return
    fi

    # Check if PDB exists
    if pdb_exists "fail-pdb" "$ns"; then
        pass "PodDisruptionBudget fail-pdb exists"

        local min_available
        min_available=$(get_pdb_min_available "fail-pdb" "$ns")
        if [[ "$min_available" == "3" ]]; then
            pass "PDB minAvailable is 3"
        else
            info "PDB minAvailable is $min_available"
        fi
    else
        info "PodDisruptionBudget fail-pdb should exist for this exercise"
    fi

    # Check if kind-worker is schedulable
    if node_exists "kind-worker"; then
        if node_is_schedulable "kind-worker"; then
            pass "Node kind-worker is schedulable (uncordoned)"
        else
            fail_with_cmd "Node kind-worker is still cordoned" \
                "kubectl uncordon kind-worker"
        fi
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Create upgrade verification checklist ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    pass "Namespace $ns exists"
    info "Exercise 5.3 requires creating a comprehensive post-upgrade verification checklist"
    info "Checklist should include: node versions, control plane pods, DNS, service connectivity, PV/PVC status"
}

################################################################################
# Level aggregation functions
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Version Information and Planning"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Node Maintenance Operations"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Drain Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Upgrade Workflow Simulation"
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
