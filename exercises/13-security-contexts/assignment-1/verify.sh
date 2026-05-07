#!/usr/bin/env bash
#
# verify.sh - Automated verification for security-contexts-homework.md
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

# Helper: get runAsUser from pod spec
get_run_as_user() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null
}

# Helper: get runAsGroup from pod spec
get_run_as_group() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.securityContext.runAsGroup}' 2>/dev/null
}

# Helper: get runAsNonRoot from pod spec
get_run_as_non_root() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null
}

# Helper: get fsGroup from pod spec
get_fs_group() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.securityContext.fsGroup}' 2>/dev/null
}

# Helper: get fsGroupChangePolicy from pod spec
get_fs_group_change_policy() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.securityContext.fsGroupChangePolicy}' 2>/dev/null
}

# Helper: get effective UID inside container
get_effective_uid() {
    local pod=$1
    local ns=$2
    local container=${3:-}
    if [[ -n "$container" ]]; then
        kubectl exec -n "$ns" "$pod" -c "$container" -- id -u 2>/dev/null || echo ""
    else
        kubectl exec -n "$ns" "$pod" -- id -u 2>/dev/null || echo ""
    fi
}

# Helper: get effective primary GID inside container
get_effective_gid() {
    local pod=$1
    local ns=$2
    local container=${3:-}
    if [[ -n "$container" ]]; then
        kubectl exec -n "$ns" "$pod" -c "$container" -- id -g 2>/dev/null || echo ""
    else
        kubectl exec -n "$ns" "$pod" -- id -g 2>/dev/null || echo ""
    fi
}

# Helper: get supplementary groups inside container
get_supplementary_groups() {
    local pod=$1
    local ns=$2
    local container=${3:-}
    if [[ -n "$container" ]]; then
        kubectl exec -n "$ns" "$pod" -c "$container" -- id -G 2>/dev/null || echo ""
    else
        kubectl exec -n "$ns" "$pod" -- id -G 2>/dev/null || echo ""
    fi
}

# Helper: get restart count
get_restart_count() {
    local pod=$1
    local ns=$2
    local container=${3:-}
    if [[ -n "$container" ]]; then
        kubectl get pod "$pod" -n "$ns" -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].restartCount}" 2>/dev/null || echo "0"
    else
        kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null || echo "0"
    fi
}

# Helper: check if file/directory exists in container
path_exists() {
    local pod=$1
    local ns=$2
    local path=$3
    local container=${4:-}
    if [[ -n "$container" ]]; then
        kubectl exec -n "$ns" "$pod" -c "$container" -- test -e "$path" 2>/dev/null
    else
        kubectl exec -n "$ns" "$pod" -- test -e "$path" 2>/dev/null
    fi
}

# Helper: get directory/file group ownership
get_path_group() {
    local pod=$1
    local ns=$2
    local path=$3
    local container=${4:-}
    if [[ -n "$container" ]]; then
        kubectl exec -n "$ns" "$pod" -c "$container" -- stat -c "%g" "$path" 2>/dev/null || echo ""
    else
        kubectl exec -n "$ns" "$pod" -- stat -c "%g" "$path" 2>/dev/null || echo ""
    fi
}

# Helper: check logs contain pattern
logs_contain() {
    local pod=$1
    local ns=$2
    local pattern=$3
    local container=${4:-}
    if [[ -n "$container" ]]; then
        kubectl logs "$pod" -n "$ns" -c "$container" 2>/dev/null | grep -q "$pattern"
    else
        kubectl logs "$pod" -n "$ns" 2>/dev/null | grep -q "$pattern"
    fi
}

# Helper: check if pod is in a specific error state
get_container_waiting_reason() {
    local pod=$1
    local ns=$2
    local container=${3:-}
    if [[ -n "$container" ]]; then
        kubectl get pod "$pod" -n "$ns" -o jsonpath="{.status.containerStatuses[?(@.name=='$container')].state.waiting.reason}" 2>/dev/null || echo ""
    else
        kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].state.waiting.reason}' 2>/dev/null || echo ""
    fi
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Run as specific non-root UID ==="
    local pod="uid-only"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 2

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local run_as_user
    run_as_user=$(get_run_as_user "$pod" "$ns")
    if [[ "$run_as_user" == "1001" ]]; then
        pass "Pod spec has runAsUser: 1001"
    else
        fail_with_cmd "Pod spec runAsUser=$run_as_user (expected 1001)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext.runAsUser}'"
    fi

    local effective_uid
    effective_uid=$(get_effective_uid "$pod" "$ns")
    if [[ "$effective_uid" == "1001" ]]; then
        pass "Effective UID inside container is 1001"
    else
        fail_with_cmd "Effective UID=$effective_uid (expected 1001)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi

    local effective_gid
    effective_gid=$(get_effective_gid "$pod" "$ns")
    if [[ "$effective_gid" == "0" ]]; then
        pass "Primary GID is 0 (image default, no runAsGroup set)"
    else
        info "Primary GID is $effective_gid (expected 0 for busybox default)"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Set both UID and GID ==="
    local pod="uid-and-gid"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 2

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local effective_uid
    effective_uid=$(get_effective_uid "$pod" "$ns")
    if [[ "$effective_uid" == "1002" ]]; then
        pass "Effective UID is 1002"
    else
        fail_with_cmd "Effective UID=$effective_uid (expected 1002)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi

    local effective_gid
    effective_gid=$(get_effective_gid "$pod" "$ns")
    if [[ "$effective_gid" == "3002" ]]; then
        pass "Effective primary GID is 3002"
    else
        fail_with_cmd "Primary GID=$effective_gid (expected 3002)" \
            "kubectl exec -n $ns $pod -- id -g"
    fi

    # Check file ownership
    if kubectl exec -n "$ns" "$pod" -- sh -c 'echo hello > /tmp/probe' &>/dev/null; then
        local file_ownership
        file_ownership=$(kubectl exec -n "$ns" "$pod" -- stat -c "%u:%g" /tmp/probe 2>/dev/null)
        if [[ "$file_ownership" == "1002:3002" ]]; then
            pass "File created is owned by 1002:3002"
        else
            fail "File ownership is $file_ownership (expected 1002:3002)"
        fi
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: runAsNonRoot with explicit non-root UID ==="
    local pod="hardened-identity"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local effective_uid
    effective_uid=$(get_effective_uid "$pod" "$ns")
    if [[ "$effective_uid" == "101" ]]; then
        pass "Effective UID is 101 (nginx user)"
    else
        fail_with_cmd "Effective UID=$effective_uid (expected 101)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi

    local run_as_non_root
    run_as_non_root=$(get_run_as_non_root "$pod" "$ns")
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "runAsNonRoot is true"
    else
        fail_with_cmd "runAsNonRoot=$run_as_non_root (expected true)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext.runAsNonRoot}'"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: emptyDir with fsGroup ==="
    local pod="writable-scratch"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 2

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local fs_group
    fs_group=$(get_fs_group "$pod" "$ns")
    if [[ "$fs_group" == "2000" ]]; then
        pass "fsGroup is 2000"
    else
        fail_with_cmd "fsGroup=$fs_group (expected 2000)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext.fsGroup}'"
    fi

    # Test write capability
    if kubectl exec -n "$ns" "$pod" -- sh -c 'touch /scratch/ping && echo created' &>/dev/null; then
        pass "Container can write to /scratch"
    else
        fail_with_cmd "Container cannot write to /scratch" \
            "kubectl exec -n $ns $pod -- sh -c 'touch /scratch/ping'"
    fi

    # Check mount group ownership
    local scratch_group
    scratch_group=$(get_path_group "$pod" "$ns" "/scratch")
    if [[ "$scratch_group" == "2000" ]]; then
        pass "/scratch has group ownership 2000"
    else
        fail_with_cmd "/scratch group is $scratch_group (expected 2000)" \
            "kubectl exec -n $ns $pod -- stat -c '%g' /scratch"
    fi

    # Check setgid bit
    local scratch_mode
    scratch_mode=$(kubectl exec -n "$ns" "$pod" -- stat -c "%A" /scratch 2>/dev/null)
    if [[ "$scratch_mode" == *"s"* ]]; then
        pass "/scratch has setgid bit set"
    else
        info "/scratch mode is $scratch_mode (expected to contain 's' for setgid)"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: fsGroupChangePolicy OnRootMismatch ==="
    local pod="onrootmismatch"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 2

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local policy
    policy=$(get_fs_group_change_policy "$pod" "$ns")
    if [[ "$policy" == "OnRootMismatch" ]]; then
        pass "fsGroupChangePolicy is OnRootMismatch"
    else
        fail_with_cmd "fsGroupChangePolicy=$policy (expected OnRootMismatch)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext.fsGroupChangePolicy}'"
    fi

    # Write a file
    kubectl exec -n "$ns" "$pod" -- sh -c 'echo payload > /data/record' &>/dev/null

    # Check mount group
    local data_group
    data_group=$(get_path_group "$pod" "$ns" "/data")
    if [[ "$data_group" == "2500" ]]; then
        pass "/data has group 2500"
    else
        fail_with_cmd "/data group is $data_group (expected 2500)" \
            "kubectl exec -n $ns $pod -- stat -c '%g' /data"
    fi

    # Check file group
    local record_group
    record_group=$(get_path_group "$pod" "$ns" "/data/record")
    if [[ "$record_group" == "2500" ]]; then
        pass "/data/record has group 2500"
    else
        fail_with_cmd "/data/record group is $record_group (expected 2500)" \
            "kubectl exec -n $ns $pod -- stat -c '%g' /data/record"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: supplementalGroups ==="
    local pod="many-groups"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 2

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local effective_uid
    effective_uid=$(get_effective_uid "$pod" "$ns")
    if [[ "$effective_uid" == "1010" ]]; then
        pass "Effective UID is 1010"
    else
        fail_with_cmd "Effective UID=$effective_uid (expected 1010)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi

    local groups
    groups=$(get_supplementary_groups "$pod" "$ns")
    if [[ "$groups" == *"3010"* ]] && [[ "$groups" == *"4000"* ]] && \
       [[ "$groups" == *"5000"* ]] && [[ "$groups" == *"6000"* ]]; then
        pass "Supplementary groups contain 3010, 4000, 5000, 6000"
    else
        fail_with_cmd "Groups are: $groups (expected to contain 3010 4000 5000 6000)" \
            "kubectl exec -n $ns $pod -- id -G"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug volume write failure ==="
    local pod="broken"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running after fix)" \
            "kubectl get pod $pod -n $ns"
        info "Hint: Check fsGroup setting"
        return
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" -lt 3 ]]; then
        pass "Restart count is low ($restart_count)"
    else
        fail "Restart count is $restart_count (should be 0 or low after fix)"
    fi

    # Check if log file exists and has content
    if path_exists "$pod" "$ns" "/work/log"; then
        if kubectl exec -n "$ns" "$pod" -- test -s /work/log &>/dev/null; then
            pass "/work/log exists and has content"
        else
            fail "/work/log exists but is empty"
        fi
    else
        fail "/work/log does not exist"
    fi

    # Check work directory has non-zero group (fsGroup applied)
    local work_group
    work_group=$(get_path_group "$pod" "$ns" "/work")
    if [[ -n "$work_group" ]] && [[ "$work_group" != "0" ]]; then
        pass "/work has non-root group ownership ($work_group)"
    else
        fail_with_cmd "/work group is $work_group (expected a non-zero GID from fsGroup)" \
            "kubectl exec -n $ns $pod -- stat -c '%u:%g' /work"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug runAsNonRoot error ==="
    local pod="blocked"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running after fix)" \
            "kubectl get pod $pod -n $ns"
        local reason
        reason=$(get_container_waiting_reason "$pod" "$ns")
        info "Waiting reason: $reason"
        info "Hint: Set explicit runAsUser to non-zero UID"
        return
    fi

    local run_as_non_root
    run_as_non_root=$(get_run_as_non_root "$pod" "$ns")
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "runAsNonRoot is still true"
    else
        fail "runAsNonRoot was removed (should still be true)"
    fi

    local effective_uid
    effective_uid=$(get_effective_uid "$pod" "$ns")
    if [[ -n "$effective_uid" ]] && [[ "$effective_uid" != "0" ]]; then
        pass "Effective UID is non-zero ($effective_uid)"
    else
        fail_with_cmd "Effective UID=$effective_uid (should be non-zero)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug multi-container shared volume ==="
    local pod="mismatch"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    # Check reader can read writer's file
    if logs_contain "$pod" "$ns" "content" "reader"; then
        pass "Reader logs show it read 'content'"
    else
        fail_with_cmd "Reader could not read /shared/file" \
            "kubectl logs -n $ns $pod -c reader"
        info "Hint: Add fsGroup at pod level for shared volume access"
    fi

    # Check reader can write
    if kubectl exec -n "$ns" "$pod" -c reader -- sh -c 'echo response > /shared/reply' &>/dev/null; then
        pass "Reader can write to shared volume"
    else
        fail_with_cmd "Reader cannot write to /shared" \
            "kubectl exec -n $ns $pod -c reader -- sh -c 'echo response > /shared/reply'"
    fi

    # Check writer can read reader's file
    if kubectl exec -n "$ns" "$pod" -c writer -- cat /shared/reply &>/dev/null; then
        pass "Writer can read reader's file"
    else
        fail "Writer cannot read /shared/reply"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Override pod-level identity in one container ==="
    local pod="mixed-identity"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 2

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    # Container one: should use pod-level settings
    local one_uid
    one_uid=$(get_effective_uid "$pod" "$ns" "one")
    if [[ "$one_uid" == "1500" ]]; then
        pass "Container 'one' UID is 1500 (pod-level)"
    else
        fail_with_cmd "Container 'one' UID=$one_uid (expected 1500)" \
            "kubectl exec -n $ns $pod -c one -- id -u"
    fi

    local one_gid
    one_gid=$(get_effective_gid "$pod" "$ns" "one")
    if [[ "$one_gid" == "2500" ]]; then
        pass "Container 'one' GID is 2500 (pod-level)"
    else
        fail_with_cmd "Container 'one' GID=$one_gid (expected 2500)" \
            "kubectl exec -n $ns $pod -c one -- id -g"
    fi

    # Container two: should override to different UID/GID
    local two_uid
    two_uid=$(get_effective_uid "$pod" "$ns" "two")
    if [[ "$two_uid" == "7000" ]]; then
        pass "Container 'two' UID is 7000 (override)"
    else
        fail_with_cmd "Container 'two' UID=$two_uid (expected 7000)" \
            "kubectl exec -n $ns $pod -c two -- id -u"
    fi

    local two_gid
    two_gid=$(get_effective_gid "$pod" "$ns" "two")
    if [[ "$two_gid" == "8000" ]]; then
        pass "Container 'two' GID is 8000 (override)"
    else
        fail_with_cmd "Container 'two' GID=$two_gid (expected 8000)" \
            "kubectl exec -n $ns $pod -c two -- id -g"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Three containers, three UIDs, shared volume ==="
    local pod="three-writers"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    # Check container a can read its own file
    local a_txt
    a_txt=$(kubectl exec -n "$ns" "$pod" -c a -- cat /shared/a.txt 2>/dev/null || echo "")
    if [[ "$a_txt" == "hello-a" ]]; then
        pass "Container 'a' wrote hello-a"
    else
        fail "Container 'a' file content is '$a_txt' (expected 'hello-a')"
    fi

    # Check container a can read c's file
    local c_txt
    c_txt=$(kubectl exec -n "$ns" "$pod" -c a -- cat /shared/c.txt 2>/dev/null || echo "")
    if [[ "$c_txt" == "hello-c" ]]; then
        pass "Container 'a' can read c's file"
    else
        fail_with_cmd "Container 'a' cannot read /shared/c.txt" \
            "kubectl exec -n $ns $pod -c a -- cat /shared/c.txt"
        info "Hint: Use fsGroup for shared volume access"
    fi

    # Check container b can read a's file
    local a_txt_b
    a_txt_b=$(kubectl exec -n "$ns" "$pod" -c b -- cat /shared/a.txt 2>/dev/null || echo "")
    if [[ "$a_txt_b" == "hello-a" ]]; then
        pass "Container 'b' can read a's file"
    else
        fail "Container 'b' cannot read /shared/a.txt"
    fi

    # Check file group ownership
    local a_file_group
    a_file_group=$(kubectl exec -n "$ns" "$pod" -c c -- stat -c "%g" /shared/a.txt 2>/dev/null || echo "")
    if [[ "$a_file_group" == "9000" ]]; then
        pass "Files are group-owned by 9000 (fsGroup)"
    else
        fail_with_cmd "File /shared/a.txt group is $a_file_group (expected 9000)" \
            "kubectl exec -n $ns $pod -c c -- stat -c '%g' /shared/a.txt"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Restricted-profile nginx on port 8080 ==="
    local pod="hardened-web"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local effective_uid
    effective_uid=$(get_effective_uid "$pod" "$ns")
    if [[ "$effective_uid" == "101" ]]; then
        pass "Effective UID is 101 (nginx user)"
    else
        fail_with_cmd "Effective UID=$effective_uid (expected 101)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi

    local run_as_non_root
    run_as_non_root=$(get_run_as_non_root "$pod" "$ns")
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "runAsNonRoot is true"
    else
        fail "runAsNonRoot is not set to true"
    fi

    # Test HTTP response on port 8080
    local response
    response=$(kubectl exec -n "$ns" "$pod" -- wget -qO- http://localhost:8080 2>/dev/null || echo "")
    if [[ -n "$response" ]]; then
        pass "nginx responds on port 8080"
    else
        fail_with_cmd "nginx not responding on port 8080" \
            "kubectl exec -n $ns $pod -- wget -qO- http://localhost:8080"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Design security context for documented requirements ==="
    local pod="appserver"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 2

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local effective_uid
    effective_uid=$(get_effective_uid "$pod" "$ns")
    if [[ "$effective_uid" == "1042" ]]; then
        pass "Effective UID is 1042"
    else
        fail_with_cmd "Effective UID=$effective_uid (expected 1042)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi

    local effective_gid
    effective_gid=$(get_effective_gid "$pod" "$ns")
    if [[ "$effective_gid" == "2042" ]]; then
        pass "Primary GID is 2042"
    else
        fail_with_cmd "Primary GID=$effective_gid (expected 2042)" \
            "kubectl exec -n $ns $pod -- id -g"
    fi

    local groups
    groups=$(get_supplementary_groups "$pod" "$ns")
    if [[ "$groups" == *"2042"* ]] && [[ "$groups" == *"3042"* ]]; then
        pass "Supplementary groups contain 2042 and 3042"
    else
        fail_with_cmd "Groups are: $groups (expected to contain 2042 and 3042)" \
            "kubectl exec -n $ns $pod -- id -G"
    fi

    # Check file in /shared has group 3042
    kubectl exec -n "$ns" "$pod" -- sh -c 'echo test > /shared/f' &>/dev/null
    local file_group
    file_group=$(get_path_group "$pod" "$ns" "/shared/f")
    if [[ "$file_group" == "3042" ]]; then
        pass "File in /shared has group 3042 (fsGroup in effect)"
    else
        fail_with_cmd "File group is $file_group (expected 3042)" \
            "kubectl exec -n $ns $pod -- stat -c '%g' /shared/f"
    fi

    local run_as_non_root
    run_as_non_root=$(get_run_as_non_root "$pod" "$ns")
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "runAsNonRoot is true"
    else
        fail "runAsNonRoot is not set to true"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug app and sidecar permission issues ==="
    local pod="app-plus-logs"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 7

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running (issues fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        info "Hint: Remove pod-level runAsUser:0 conflict with runAsNonRoot:true, add fsGroup"
        return
    fi

    local app_uid
    app_uid=$(get_effective_uid "$pod" "$ns" "app")
    if [[ "$app_uid" == "1500" ]]; then
        pass "App container UID is 1500"
    else
        fail_with_cmd "App UID=$app_uid (expected 1500)" \
            "kubectl exec -n $ns $pod -c app -- id -u"
    fi

    local sidecar_uid
    sidecar_uid=$(get_effective_uid "$pod" "$ns" "sidecar")
    if [[ "$sidecar_uid" == "2500" ]]; then
        pass "Sidecar container UID is 2500"
    else
        fail_with_cmd "Sidecar UID=$sidecar_uid (expected 2500)" \
            "kubectl exec -n $ns $pod -c sidecar -- id -u"
    fi

    local app_restart
    app_restart=$(get_restart_count "$pod" "$ns" "app")
    if [[ "$app_restart" == "0" ]]; then
        pass "App container restart count is 0"
    else
        fail "App container restart count is $app_restart (should be 0)"
    fi

    # Check sidecar logs contain date lines
    sleep 3
    if kubectl logs -n "$ns" "$pod" -c sidecar --tail=2 2>/dev/null | grep -q "[0-9]"; then
        pass "Sidecar logs contain date lines from app"
    else
        fail_with_cmd "Sidecar logs do not show app output" \
            "kubectl logs -n $ns $pod -c sidecar --tail=5"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Three-tier pod with different UIDs and shared metrics ==="
    local pod="three-tier"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local frontend_uid
    frontend_uid=$(get_effective_uid "$pod" "$ns" "frontend")
    if [[ "$frontend_uid" == "101" ]]; then
        pass "Frontend UID is 101"
    else
        fail_with_cmd "Frontend UID=$frontend_uid (expected 101)" \
            "kubectl exec -n $ns $pod -c frontend -- id -u"
    fi

    local backend_uid
    backend_uid=$(get_effective_uid "$pod" "$ns" "backend")
    if [[ "$backend_uid" == "1020" ]]; then
        pass "Backend UID is 1020"
    else
        fail_with_cmd "Backend UID=$backend_uid (expected 1020)" \
            "kubectl exec -n $ns $pod -c backend -- id -u"
    fi

    local exporter_uid
    exporter_uid=$(get_effective_uid "$pod" "$ns" "exporter")
    if [[ "$exporter_uid" == "1030" ]]; then
        pass "Exporter UID is 1030"
    else
        fail_with_cmd "Exporter UID=$exporter_uid (expected 1030)" \
            "kubectl exec -n $ns $pod -c exporter -- id -u"
    fi

    sleep 7
    # Check metrics files exist
    local metrics_ls
    metrics_ls=$(kubectl exec -n "$ns" "$pod" -c exporter -- ls /metrics 2>/dev/null || echo "")
    if [[ "$metrics_ls" == *"frontend.ok"* ]] && [[ "$metrics_ls" == *"backend.ok"* ]]; then
        pass "/metrics contains frontend.ok and backend.ok"
    else
        fail_with_cmd "/metrics contents: $metrics_ls" \
            "kubectl exec -n $ns $pod -c exporter -- ls /metrics"
    fi

    # Check exporter logs contain summary
    if kubectl logs -n "$ns" "$pod" -c exporter --tail=1 2>/dev/null | grep -q "frontend.ok"; then
        pass "Exporter logs contain summary"
    else
        fail_with_cmd "Exporter logs missing expected summary" \
            "kubectl logs -n $ns $pod -c exporter --tail=3"
    fi

    local run_as_non_root
    run_as_non_root=$(get_run_as_non_root "$pod" "$ns")
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "runAsNonRoot is true at pod level"
    else
        fail "runAsNonRoot is not set to true"
    fi
}

################################################################################
# Level aggregation functions
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic Identity Controls"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Volumes, fsGroup, and Supplementary Groups"
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
    echo "# Level 4: Precedence and Multi-Container"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Advanced and Comprehensive"
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
