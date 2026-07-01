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

# Helper: get pod ready status
get_ready() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null
}

# Helper: get readOnlyRootFilesystem setting
get_readonly_rootfs() {
    local pod=$1
    local ns=$2
    local container=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$container].securityContext.readOnlyRootFilesystem}" 2>/dev/null
}

# Helper: get seccomp profile type from pod level
get_pod_seccomp_type() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.securityContext.seccompProfile.type}' 2>/dev/null
}

# Helper: get seccomp profile type from container level
get_container_seccomp_type() {
    local pod=$1
    local ns=$2
    local container=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$container].securityContext.seccompProfile.type}" 2>/dev/null
}

# Helper: get seccomp localhost profile
get_localhost_profile() {
    local pod=$1
    local ns=$2
    local container=${3:-}
    if [[ -n "$container" ]]; then
        kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[$container].securityContext.seccompProfile.localhostProfile}" 2>/dev/null
    else
        kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.securityContext.seccompProfile.localhostProfile}' 2>/dev/null
    fi
}

# Helper: get restart count
get_restart_count() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null
}

# Helper: get container names
get_container_names() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null
}

# Helper: check if volume exists and is emptyDir
has_emptydir_volume() {
    local pod=$1
    local ns=$2
    local vol_name=$3
    local result
    result=$(kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.volumes[?(@.name=='$vol_name')].emptyDir}" 2>/dev/null)
    [[ -n "$result" ]]
}

# Helper: get volume mount path for a container
get_volume_mount_path() {
    local pod=$1
    local ns=$2
    local container=$3
    local vol_name=$4
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[?(@.name=='$container')].volumeMounts[?(@.name=='$vol_name')].mountPath}" 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Read-only root filesystem basics ==="
    local pod="immutable"
    local ns="ex-1-1"

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
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local readonly_rootfs
    readonly_rootfs=$(get_readonly_rootfs "$pod" "$ns" 0)
    if [[ "$readonly_rootfs" == "true" ]]; then
        pass "readOnlyRootFilesystem is true"
    else
        fail_with_cmd "readOnlyRootFilesystem is $readonly_rootfs (expected true)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.readOnlyRootFilesystem}'"
    fi

    # Test that writes to /tmp fail
    local write_result
    write_result=$(kubectl exec -n "$ns" "$pod" -- sh -c 'echo test > /tmp/file 2>&1 || true')
    if [[ "$write_result" == *"Read-only file system"* ]]; then
        pass "Writes to /tmp fail with Read-only file system"
    else
        fail "Expected Read-only file system error, got: $write_result"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Read-only root with writable /tmp ==="
    local pod="immutable-tmp"
    local ns="ex-1-2"

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
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local readonly_rootfs
    readonly_rootfs=$(get_readonly_rootfs "$pod" "$ns" 0)
    if [[ "$readonly_rootfs" == "true" ]]; then
        pass "readOnlyRootFilesystem is true"
    else
        fail "readOnlyRootFilesystem is $readonly_rootfs (expected true)"
    fi

    # Test that /tmp is writable
    local write_result
    write_result=$(kubectl exec -n "$ns" "$pod" -- sh -c 'echo hello > /tmp/test-file && cat /tmp/test-file' 2>/dev/null || echo "FAILED")
    if [[ "$write_result" == "hello" ]]; then
        pass "/tmp is writable"
    else
        fail_with_cmd "/tmp write failed (expected writable emptyDir)" \
            "kubectl exec -n $ns $pod -- sh -c 'echo test > /tmp/test-file && cat /tmp/test-file'"
    fi

    # Test that other rootfs paths are read-only
    local blocked_result
    blocked_result=$(kubectl exec -n "$ns" "$pod" -- sh -c 'echo blocked > /etc/blocker 2>&1 || true')
    if [[ "$blocked_result" == *"Read-only file system"* ]]; then
        pass "Writes to /etc are blocked"
    else
        fail "Expected rootfs to be read-only outside /tmp"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: nginx with multiple writable paths ==="
    local pod="nginx-immutable"
    local ns="ex-1-3"

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
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    local readonly_rootfs
    readonly_rootfs=$(get_readonly_rootfs "$pod" "$ns" 0)
    if [[ "$readonly_rootfs" == "true" ]]; then
        pass "readOnlyRootFilesystem is true"
    else
        fail "readOnlyRootFilesystem is $readonly_rootfs (expected true)"
    fi

    # Test nginx is serving
    local http_result
    http_result=$(kubectl exec -n "$ns" "$pod" -- wget -qO- http://localhost/ 2>/dev/null | head -c 15)
    if [[ "$http_result" == "<!DOCTYPE html" ]]; then
        pass "nginx is serving HTTP"
    else
        fail_with_cmd "nginx is not responding correctly" \
            "kubectl exec -n $ns $pod -- wget -qO- http://localhost/"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "Container has not restarted (restart count = 0)"
    else
        fail "Container restart count is $restart_count (expected 0)"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: RuntimeDefault seccomp profile ==="
    local pod="runtimedefault"
    local ns="ex-2-1"

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
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local seccomp_type
    seccomp_type=$(get_pod_seccomp_type "$pod" "$ns")
    if [[ "$seccomp_type" == "RuntimeDefault" ]]; then
        pass "seccompProfile.type is RuntimeDefault at pod level"
    else
        fail_with_cmd "seccompProfile.type is $seccomp_type (expected RuntimeDefault)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext.seccompProfile.type}'"
    fi

    # Check Seccomp mode is 2 (SECCOMP_MODE_FILTER)
    local seccomp_mode
    seccomp_mode=$(kubectl exec -n "$ns" "$pod" -- grep "^Seccomp:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$seccomp_mode" == "2" ]]; then
        pass "Seccomp mode is 2 (SECCOMP_MODE_FILTER)"
    else
        fail "Seccomp mode is $seccomp_mode (expected 2)"
    fi

    # Check Seccomp_filters is 1
    local seccomp_filters
    seccomp_filters=$(kubectl exec -n "$ns" "$pod" -- grep "^Seccomp_filters:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$seccomp_filters" == "1" ]]; then
        pass "Seccomp_filters is 1"
    else
        fail "Seccomp_filters is $seccomp_filters (expected 1)"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Unconfined seccomp profile ==="
    local pod="unconfined"
    local ns="ex-2-2"

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
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local seccomp_type
    seccomp_type=$(get_container_seccomp_type "$pod" "$ns" 0)
    if [[ "$seccomp_type" == "Unconfined" ]]; then
        pass "seccompProfile.type is Unconfined"
    else
        fail_with_cmd "seccompProfile.type is $seccomp_type (expected Unconfined)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.seccompProfile.type}'"
    fi

    # Check Seccomp mode is 0 (disabled)
    local seccomp_mode
    seccomp_mode=$(kubectl exec -n "$ns" "$pod" -- grep "^Seccomp:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$seccomp_mode" == "0" ]]; then
        pass "Seccomp mode is 0 (disabled)"
    else
        fail "Seccomp mode is $seccomp_mode (expected 0)"
    fi

    # Check Seccomp_filters is 0
    local seccomp_filters
    seccomp_filters=$(kubectl exec -n "$ns" "$pod" -- grep "^Seccomp_filters:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$seccomp_filters" == "0" ]]; then
        pass "Seccomp_filters is 0"
    else
        fail "Seccomp_filters is $seccomp_filters (expected 0)"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: seccomp blocks clock_settime despite SYS_TIME capability ==="
    local pod="no-clock-change"
    local ns="ex-2-3"

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
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    # Check RuntimeDefault is applied
    local seccomp_mode
    seccomp_mode=$(kubectl exec -n "$ns" "$pod" -- grep "^Seccomp:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$seccomp_mode" == "2" ]]; then
        pass "Seccomp mode is 2 (RuntimeDefault active)"
    else
        fail "Seccomp mode is $seccomp_mode (expected 2)"
    fi

    # Check clock setting is blocked
    local clock_result
    clock_result=$(kubectl exec -n "$ns" "$pod" -- sh -c 'date -s "2030-01-01" 2>&1 || true')
    if [[ "$clock_result" == *"Operation not permitted"* ]]; then
        pass "clock_settime is blocked by seccomp"
    else
        fail "Expected 'Operation not permitted' when setting clock, got: $clock_result"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug PID file write failure ==="
    local pod="pidfile-fail"
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
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    # Verify PID file exists and is non-empty
    local pidfile_check
    pidfile_check=$(kubectl exec -n "$ns" "$pod" -- test -s /var/run/app.pid 2>&1 && echo "EXISTS" || echo "MISSING")
    if [[ "$pidfile_check" == "EXISTS" ]]; then
        pass "PID file /var/run/app.pid exists and is non-empty"
    else
        fail "PID file /var/run/app.pid is missing or empty"
    fi

    local restart_count
    restart_count=$(get_restart_count "$pod" "$ns")
    if [[ "$restart_count" == "0" ]]; then
        pass "Container has not restarted"
    else
        fail "Container restart count is $restart_count (expected 0)"
    fi

    local readonly_rootfs
    readonly_rootfs=$(get_readonly_rootfs "$pod" "$ns" 0)
    if [[ "$readonly_rootfs" == "true" ]]; then
        pass "readOnlyRootFilesystem is still true"
    else
        fail "readOnlyRootFilesystem should remain true"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug blocked syscall in seccomp profile ==="
    local pod="blocked-syscall"
    local ns="ex-3-2"

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
        pass "Pod phase is Running (profile fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get events -n $ns --field-selector involvedObject.name=$pod --sort-by=.lastTimestamp"
        return
    fi

    # Verify unshare is still blocked
    local unshare_result
    unshare_result=$(kubectl exec -n "$ns" "$pod" -- sh -c 'unshare --user echo hi 2>&1 || true')
    if [[ "$unshare_result" == *"Operation not permitted"* ]]; then
        pass "unshare is still blocked"
    else
        fail "unshare should be blocked by the profile"
    fi

    local localhost_profile
    localhost_profile=$(get_localhost_profile "$pod" "$ns")
    if [[ "$localhost_profile" == "deny-unshare.json" ]]; then
        pass "localhostProfile is deny-unshare.json"
    else
        fail "localhostProfile is $localhost_profile (expected deny-unshare.json)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug missing seccomp profile ==="
    local pod="profile-missing"
    local ns="ex-3-3"

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
        pass "Pod phase is Running (profile issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get events -n $ns --field-selector involvedObject.name=$pod"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Custom profile blocking chmod/chown ==="
    local pod="perm-locked"
    local ns="ex-4-1"

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
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local localhost_profile
    localhost_profile=$(get_localhost_profile "$pod" "$ns" 0)
    if [[ "$localhost_profile" == "no-perm-change.json" ]]; then
        pass "localhostProfile is no-perm-change.json"
    else
        fail_with_cmd "localhostProfile is $localhost_profile (expected no-perm-change.json)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.seccompProfile.localhostProfile}'"
    fi

    # Test chmod is blocked
    local chmod_result
    chmod_result=$(kubectl exec -n "$ns" "$pod" -- sh -c 'touch /tmp/probe && chmod 755 /tmp/probe 2>&1 || true')
    if [[ "$chmod_result" == *"Operation not permitted"* ]]; then
        pass "chmod is blocked by seccomp"
    else
        fail "Expected 'Operation not permitted' for chmod, got: $chmod_result"
    fi

    # Verify file permissions remain unchanged
    local perms
    perms=$(kubectl exec -n "$ns" "$pod" -- ls -la /tmp/probe 2>/dev/null | awk '{print $1}')
    if [[ "$perms" == "-rw-r--r--" ]] || [[ "$perms" == "-rw-------" ]]; then
        pass "File permissions unchanged (chmod was blocked)"
    else
        info "File permissions: $perms"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Deny-by-default profile for sleep ==="
    local pod="sleep-only"
    local ns="ex-4-2"

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
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    # Check seccomp filter is applied
    local seccomp_filters
    seccomp_filters=$(kubectl exec -n "$ns" "$pod" -- grep "^Seccomp_filters:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$seccomp_filters" == "1" ]]; then
        pass "Seccomp_filters is 1"
    else
        fail "Seccomp_filters is $seccomp_filters (expected 1)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Pod-level seccomp for multiple containers ==="
    local pod="multi-container"
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
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local pod_profile
    pod_profile=$(get_localhost_profile "$pod" "$ns")
    if [[ "$pod_profile" == "sleep-only.json" ]]; then
        pass "Pod-level localhostProfile is sleep-only.json"
    else
        fail_with_cmd "Pod-level localhostProfile is $pod_profile (expected sleep-only.json)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext.seccompProfile.localhostProfile}'"
    fi

    # Check first container has seccomp filter
    local containers
    containers=$(get_container_names "$pod" "$ns")
    local first_container
    first_container=$(echo "$containers" | awk '{print $1}')

    local seccomp_mode
    seccomp_mode=$(kubectl exec -n "$ns" "$pod" -c "$first_container" -- grep "^Seccomp:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$seccomp_mode" == "2" ]]; then
        pass "First container has Seccomp mode 2 (inherited from pod level)"
    else
        fail "First container Seccomp mode is $seccomp_mode (expected 2)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Fully hardened nginx (Restricted baseline) ==="
    local pod="fully-hardened"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 10

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    # Test nginx is serving
    local http_result
    http_result=$(kubectl exec -n "$ns" "$pod" -- wget -qO- http://localhost:8080 2>/dev/null | head -c 10)
    if [[ -n "$http_result" ]]; then
        pass "nginx is serving HTTP on port 8080"
    else
        fail_with_cmd "nginx is not responding" \
            "kubectl exec -n $ns $pod -- wget -qO- http://localhost:8080"
    fi

    # Check non-root
    local uid
    uid=$(kubectl exec -n "$ns" "$pod" -- id -u 2>/dev/null)
    if [[ "$uid" != "0" ]]; then
        pass "Running as non-root UID ($uid)"
    else
        fail "Running as root (UID 0)"
    fi

    # Check NoNewPrivs
    local nonewprivs
    nonewprivs=$(kubectl exec -n "$ns" "$pod" -- grep "^NoNewPrivs:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$nonewprivs" == "1" ]]; then
        pass "NoNewPrivs is 1 (allowPrivilegeEscalation: false)"
    else
        fail "NoNewPrivs is $nonewprivs (expected 1)"
    fi

    # Check seccomp
    local seccomp_mode
    seccomp_mode=$(kubectl exec -n "$ns" "$pod" -- grep "^Seccomp:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$seccomp_mode" == "2" ]]; then
        pass "Seccomp mode is 2 (RuntimeDefault)"
    else
        fail "Seccomp mode is $seccomp_mode (expected 2)"
    fi

    # Check rootfs is read-only
    local rootfs_result
    rootfs_result=$(kubectl exec -n "$ns" "$pod" -- sh -c 'echo blocked > /usr/share/nginx/blocker 2>&1 || true')
    if [[ "$rootfs_result" == *"Read-only file system"* ]]; then
        pass "Root filesystem is read-only"
    else
        fail "Expected Read-only file system error"
    fi

    # Check capabilities dropped
    local caps_dropped
    caps_dropped=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].securityContext.capabilities.drop[0]}' 2>/dev/null)
    if [[ "$caps_dropped" == "ALL" ]]; then
        pass "Capabilities drop includes ALL"
    else
        fail "Capabilities drop[0] is $caps_dropped (expected ALL)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Compound failure with multiple security layers ==="
    local pod="cascade"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 10

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl logs -n $ns $pod"
        return
    fi

    # Check logs for expected failures/successes
    local logs
    logs=$(kubectl logs -n "$ns" "$pod" 2>/dev/null | head -n 5)

    if [[ "$logs" == *"starting"* ]]; then
        pass "Logs contain 'starting'"
    else
        fail "Logs should start with 'starting'"
    fi

    if [[ "$logs" == *"chmod failed"* ]]; then
        pass "Logs show chmod failed (intended seccomp block)"
    else
        fail "Expected 'chmod failed' in logs"
    fi

    if [[ "$logs" != *"pid write failed"* ]]; then
        pass "PID write succeeded (no 'pid write failed' message)"
    else
        fail "PID write should succeed after fix"
    fi

    if [[ "$logs" != *"data write failed"* ]]; then
        pass "Data write succeeded (no 'data write failed' message)"
    else
        fail "Data write should succeed after fix"
    fi

    # Verify PID file exists
    local pid_check
    pid_check=$(kubectl exec -n "$ns" "$pod" -- test -s /var/run/app.pid 2>&1 && echo "0" || echo "1")
    if [[ "$pid_check" == "0" ]]; then
        pass "PID file exists at /var/run/app.pid"
    else
        fail "PID file is missing or empty"
    fi

    # Verify data file exists
    local data_check
    data_check=$(kubectl exec -n "$ns" "$pod" -- test -e /data/metric 2>&1 && echo "0" || echo "1")
    if [[ "$data_check" == "0" ]]; then
        pass "Data file exists at /data/metric"
    else
        fail "Data file is missing"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Production two-container pod with custom seccomp ==="
    local pod="service-and-metrics"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 15

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl describe pod $pod -n $ns"
        return
    fi

    # Check service container is non-root
    local service_uid
    service_uid=$(kubectl exec -n "$ns" "$pod" -c service -- id -u 2>/dev/null)
    if [[ "$service_uid" != "0" ]]; then
        pass "service container runs as non-root UID ($service_uid)"
    else
        fail "service container runs as root"
    fi

    # Check exporter container is non-root
    local exporter_uid
    exporter_uid=$(kubectl exec -n "$ns" "$pod" -c exporter -- id -u 2>/dev/null)
    if [[ "$exporter_uid" != "0" ]]; then
        pass "exporter container runs as non-root UID ($exporter_uid)"
    else
        fail "exporter container runs as root"
    fi

    # Wait a bit and check export log has content
    sleep 12
    local export_lines
    export_lines=$(kubectl exec -n "$ns" "$pod" -c exporter -- wc -l /shared/export.log 2>/dev/null | awk '{print $1}')
    if [[ "$export_lines" -ge 1 ]]; then
        pass "Export log has $export_lines lines (metrics collection working)"
    else
        fail "Export log has no content"
    fi

    # Check nginx is serving
    local http_result
    http_result=$(kubectl exec -n "$ns" "$pod" -c service -- wget -qO- http://localhost:8080 2>/dev/null | head -c 15)
    if [[ "$http_result" == "<!DOCTYPE html" ]] || [[ "$http_result" == *"service"* ]]; then
        pass "nginx/service is serving HTTP"
    else
        fail_with_cmd "service is not responding correctly" \
            "kubectl exec -n $ns $pod -c service -- wget -qO- http://localhost:8080"
    fi

    # Check seccomp filter on service container
    local seccomp_filters
    seccomp_filters=$(kubectl exec -n "$ns" "$pod" -c service -- grep "^Seccomp_filters:" /proc/self/status 2>/dev/null | awk '{print $2}')
    if [[ "$seccomp_filters" == "1" ]]; then
        pass "service container has seccomp filter"
    else
        fail "service container Seccomp_filters is $seccomp_filters (expected 1)"
    fi

    # Check readOnlyRootFilesystem on service container
    local readonly_rootfs
    readonly_rootfs=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[?(@.name=="service")].securityContext.readOnlyRootFilesystem}' 2>/dev/null)
    if [[ "$readonly_rootfs" == "true" ]]; then
        pass "service container has readOnlyRootFilesystem: true"
    else
        fail "service container readOnlyRootFilesystem is $readonly_rootfs (expected true)"
    fi
}

################################################################################
# Level verification functions
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Read-Only Root Filesystem"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: seccomp Basics"
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
    echo "# Level 4: Custom seccomp Profiles"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Defense in Depth"
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
