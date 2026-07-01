#!/usr/bin/env bash
#
# verify.sh - Automated verification for cluster-lifecycle-homework.md (etcd operations)
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

# Helper: check if etcd is accessible in kind container
etcd_accessible() {
    nerdctl exec kind-control-plane /bin/bash -c '
    ETCDCTL_API=3 etcdctl endpoint health \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key
    ' &>/dev/null
}

# Helper: check if etcd backup file exists in kind container
backup_exists() {
    local backup_file=$1
    nerdctl exec kind-control-plane test -f "$backup_file" &>/dev/null
}

# Helper: verify backup file is valid
backup_valid() {
    local backup_file=$1
    nerdctl exec kind-control-plane /bin/bash -c "
    ETCDCTL_API=3 etcdctl snapshot status $backup_file
    " &>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Locate etcd manifest and certificate paths ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if etcd manifest exists
    local manifest_check
    manifest_check=$(nerdctl exec kind-control-plane test -f /etc/kubernetes/manifests/etcd.yaml && echo "exists" || echo "missing")
    if [[ "$manifest_check" == "exists" ]]; then
        pass "etcd manifest exists at /etc/kubernetes/manifests/etcd.yaml"
    else
        fail_with_cmd "etcd manifest not found" \
            "nerdctl exec kind-control-plane ls /etc/kubernetes/manifests/"
        return
    fi

    # Check if certificate paths are present in manifest
    local cert_check
    cert_check=$(nerdctl exec kind-control-plane cat /etc/kubernetes/manifests/etcd.yaml | grep -E "cert|key|ca" || echo "")
    if [[ -n "$cert_check" ]]; then
        pass "Certificate paths found in etcd manifest"
    else
        fail_with_cmd "Certificate paths not found in manifest" \
            "nerdctl exec kind-control-plane cat /etc/kubernetes/manifests/etcd.yaml"
    fi

    # Verify key certificate files exist
    local server_crt
    server_crt=$(nerdctl exec kind-control-plane test -f /etc/kubernetes/pki/etcd/server.crt && echo "exists" || echo "missing")
    if [[ "$server_crt" == "exists" ]]; then
        pass "etcd server certificate exists"
    else
        fail "etcd server certificate missing at /etc/kubernetes/pki/etcd/server.crt"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Verify etcd cluster health ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check etcd health
    if etcd_accessible; then
        pass "etcd endpoint is healthy"
    else
        fail_with_cmd "etcd endpoint health check failed" \
            "nerdctl exec kind-control-plane /bin/bash -c 'ETCDCTL_API=3 etcdctl endpoint health --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: List etcd cluster members ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check member list
    local member_list
    member_list=$(nerdctl exec kind-control-plane /bin/bash -c '
    ETCDCTL_API=3 etcdctl member list \
      --endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key
    ' 2>/dev/null || echo "")

    if [[ -n "$member_list" ]]; then
        pass "etcd member list retrieved successfully"
    else
        fail_with_cmd "Failed to retrieve etcd member list" \
            "nerdctl exec kind-control-plane /bin/bash -c 'ETCDCTL_API=3 etcdctl member list --endpoints=https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key'"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Create etcd snapshot backup ==="
    local ns="ex-2-1"
    local backup_file="/tmp/etcd-snapshot-ex21.db"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Verify ConfigMap was created for testing
    local cm_check
    cm_check=$(kubectl get configmap backup-test -n "$ns" &>/dev/null && echo "exists" || echo "missing")
    if [[ "$cm_check" == "exists" ]]; then
        pass "Test ConfigMap backup-test exists in $ns"
    else
        fail_with_cmd "ConfigMap backup-test not found" \
            "kubectl get configmap -n $ns"
    fi

    # Check if backup file exists
    if backup_exists "$backup_file"; then
        pass "Backup file exists at $backup_file"
    else
        fail_with_cmd "Backup file not found at $backup_file" \
            "nerdctl exec kind-control-plane ls -lh /tmp/etcd-snapshot*"
        return
    fi

    # Verify backup is valid
    if backup_valid "$backup_file"; then
        pass "Backup file is valid (snapshot status check passed)"
    else
        fail_with_cmd "Backup file validation failed" \
            "nerdctl exec kind-control-plane /bin/bash -c 'ETCDCTL_API=3 etcdctl snapshot status $backup_file'"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Verify backup integrity ==="
    local ns="ex-2-2"
    local backup_file="/tmp/etcd-snapshot-ex21.db"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if backup file exists from previous exercise
    if ! backup_exists "$backup_file"; then
        fail "Backup file from Exercise 2.1 not found (prerequisite)"
        info "Exercise 2.2 requires successful completion of Exercise 2.1"
        return
    fi

    # Verify snapshot status command works
    local status_output
    status_output=$(nerdctl exec kind-control-plane /bin/bash -c "
    ETCDCTL_API=3 etcdctl snapshot status $backup_file --write-out=table
    " 2>/dev/null || echo "")

    if [[ -n "$status_output" ]]; then
        pass "Snapshot status command executed successfully"
    else
        fail_with_cmd "Snapshot status command failed" \
            "nerdctl exec kind-control-plane /bin/bash -c 'ETCDCTL_API=3 etcdctl snapshot status $backup_file --write-out=table'"
    fi

    # Check if status output contains expected fields
    if echo "$status_output" | grep -q "HASH"; then
        pass "Snapshot status shows integrity information"
    else
        fail "Snapshot status output missing expected fields"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Document backup procedure ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise - we verify conceptual understanding
    info "Exercise 2.3 is a documentation task"
    info "Runbook should include:"
    info "  - Backup command with full certificate paths"
    info "  - Verification using snapshot status"
    info "  - Storage location and retention policy"
    info "  - Recommended schedule (daily, before upgrades)"
    pass "Namespace created (exercise requires manual verification of runbook)"
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug etcd connection issue ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a debugging/conceptual exercise
    info "Exercise 3.1 tests understanding of certificate requirements"
    info "Issue: Using wrong certificates (API server certs instead of etcd certs)"
    info "Fix: Use /etc/kubernetes/pki/etcd/ certificates, not /etc/kubernetes/pki/"
    pass "Namespace created (exercise requires understanding wrong certificate paths)"
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug endpoint configuration ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a debugging/conceptual exercise
    info "Exercise 3.2 tests understanding of TLS requirements"
    info "Issue: Using http instead of https"
    info "Fix: etcd requires TLS, use https://127.0.0.1:2379"
    pass "Namespace created (exercise requires understanding TLS requirement)"
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug ETCDCTL_API variable ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a debugging/conceptual exercise
    info "Exercise 3.3 tests understanding of etcdctl API versions"
    info "Issue: Missing ETCDCTL_API=3 environment variable"
    info "Fix: etcdctl defaults to v2 API, must set ETCDCTL_API=3 for snapshot commands"
    pass "Namespace created (exercise requires understanding API version requirement)"
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Document restore workflow ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise
    info "Exercise 4.1 is a documentation task"
    info "Workflow should include:"
    info "  1. Stop kube-apiserver (move manifest)"
    info "  2. Restore with --data-dir to new directory"
    info "  3. Update etcd manifest to use new data directory"
    info "  4. Kubelet restarts etcd automatically"
    info "  5. Restore kube-apiserver manifest"
    info "  6. Verify cluster with kubectl"
    pass "Namespace created (exercise requires manual verification of workflow documentation)"
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Understand restore implications ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a conceptual exercise
    info "Exercise 4.2 tests understanding of restore behavior"
    info "Key concepts:"
    info "  - Restore creates new cluster with new cluster ID"
    info "  - Member IDs are regenerated"
    info "  - Cannot restore to same data directory"
    info "  - etcd manifest must be updated with new data-dir path"
    pass "Namespace created (exercise requires understanding restore implications)"
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Create disaster recovery runbook ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise
    info "Exercise 4.3 is a comprehensive documentation task"
    info "Runbook should cover:"
    info "  - Verify backup integrity before restore"
    info "  - Stop all control plane components"
    info "  - Restore etcd to new data directory"
    info "  - Update etcd manifest"
    info "  - Restore control plane manifests"
    info "  - Verify cluster health after restore"
    pass "Namespace created (exercise requires manual verification of DR runbook)"
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Design HA cluster topology ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a design exercise
    info "Exercise 5.1 is an HA design task"
    info "Design should include:"
    info "  - 3 control plane nodes with stacked etcd"
    info "  - 2 worker nodes"
    info "  - etcd quorum requirement: 2 out of 3 members"
    info "  - Load balancer for API server HA"
    info "  - Failure tolerance: 1 control plane node can fail"
    pass "Namespace created (exercise requires manual verification of HA design)"
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Production backup/restore runbook ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a comprehensive documentation exercise
    info "Exercise 5.2 is a production runbook task"
    info "Runbook should include:"
    info "  - Scheduled backup frequency (e.g., every 4 hours)"
    info "  - Retention policy (hourly, daily, monthly)"
    info "  - Off-site storage (S3, GCS, etc.)"
    info "  - Restore testing procedures"
    info "  - Verification checklist post-restore"
    pass "Namespace created (exercise requires manual verification of production runbook)"
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Disaster recovery scenarios ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a comprehensive scenario planning exercise
    info "Exercise 5.3 is a DR scenario planning task"
    info "Should document recovery procedures for:"
    info "  1. Single etcd member failure (remove, replace, re-add member)"
    info "  2. Complete etcd data loss (restore from backup)"
    info "  3. Control plane node failure (provision new, kubeadm join)"
    pass "Namespace created (exercise requires manual verification of DR scenarios)"
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: etcd Exploration"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Backup Operations"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging etcd Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Restore Operations"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: HA Concepts and Complex Scenarios"
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
