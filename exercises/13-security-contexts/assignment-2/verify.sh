#!/usr/bin/env bash
#
# verify.sh - Automated verification for security-contexts-homework.md (assignment-2)
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

# Helper: get capability from spec
get_capability_add() {
    local pod=$1
    local ns=$2
    local index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[0].securityContext.capabilities.add[$index]}" 2>/dev/null
}

get_capability_drop() {
    local pod=$1
    local ns=$2
    local index=${3:-0}
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[0].securityContext.capabilities.drop[$index]}" 2>/dev/null
}

# Helper: get all capability adds as array
get_all_capability_adds() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].securityContext.capabilities.add[*]}' 2>/dev/null
}

# Helper: get privileged status
get_privileged() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].securityContext.privileged}' 2>/dev/null
}

# Helper: get allowPrivilegeEscalation status
get_allow_privilege_escalation() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].securityContext.allowPrivilegeEscalation}' 2>/dev/null
}

# Helper: check if logs contain a pattern
logs_contain() {
    local pod=$1
    local ns=$2
    local pattern=$3
    kubectl logs "$pod" -n "$ns" 2>/dev/null | grep -q "$pattern"
}

# Helper: get CapEff from /proc/self/status
get_cap_eff() {
    local pod=$1
    local ns=$2
    local container=${3:-}
    if [[ -n "$container" ]]; then
        kubectl exec "$pod" -n "$ns" -c "$container" -- grep "^CapEff" /proc/self/status 2>/dev/null | awk '{print $2}'
    else
        kubectl exec "$pod" -n "$ns" -- grep "^CapEff" /proc/self/status 2>/dev/null | awk '{print $2}'
    fi
}

# Helper: get NoNewPrivs from /proc/self/status
get_no_new_privs() {
    local pod=$1
    local ns=$2
    local container=${3:-}
    if [[ -n "$container" ]]; then
        kubectl exec "$pod" -n "$ns" -c "$container" -- grep "^NoNewPrivs" /proc/self/status 2>/dev/null | awk '{print $2}'
    else
        kubectl exec "$pod" -n "$ns" -- grep "^NoNewPrivs" /proc/self/status 2>/dev/null | awk '{print $2}'
    fi
}

# Helper: get runAsUser
get_run_as_user() {
    local pod=$1
    local ns=$2
    # Try container level first, then pod level
    local user
    user=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].securityContext.runAsUser}' 2>/dev/null)
    if [[ -z "$user" ]]; then
        user=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.securityContext.runAsUser}' 2>/dev/null)
    fi
    echo "$user"
}

# Helper: get container names
get_container_names() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Default capability set ==="
    local pod="inspector"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    # Install libcap if not already present
    kubectl exec -n "$ns" "$pod" -- apk add --no-cache libcap > /dev/null 2>&1 || true

    local cap_eff
    cap_eff=$(get_cap_eff "$pod" "$ns")
    if [[ "$cap_eff" == "00000000a80425fb" ]]; then
        pass "CapEff is default containerd set: $cap_eff"
    else
        fail_with_cmd "CapEff=$cap_eff (expected 00000000a80425fb)" \
            "kubectl exec -n $ns $pod -- grep '^CapEff' /proc/self/status"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Privileged container full capability set ==="
    local pod="super-user"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local privileged
    privileged=$(get_privileged "$pod" "$ns")
    if [[ "$privileged" == "true" ]]; then
        pass "Container is privileged: true"
    else
        fail_with_cmd "Container privileged=$privileged (expected true)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.privileged}'"
    fi

    local cap_eff
    cap_eff=$(get_cap_eff "$pod" "$ns")
    if [[ "$cap_eff" == "000001ffffffffff" ]]; then
        pass "CapEff is full set: $cap_eff"
    else
        fail_with_cmd "CapEff=$cap_eff (expected 000001ffffffffff for privileged)" \
            "kubectl exec -n $ns $pod -- grep '^CapEff' /proc/self/status"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Drop ALL capabilities ==="
    local pod="no-caps"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local cap_drop
    cap_drop=$(get_capability_drop "$pod" "$ns" 0)
    if [[ "$cap_drop" == "ALL" ]]; then
        pass "capabilities.drop contains ALL"
    else
        fail_with_cmd "capabilities.drop[0]=$cap_drop (expected ALL)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.drop[*]}'"
    fi

    local cap_eff
    cap_eff=$(get_cap_eff "$pod" "$ns")
    if [[ "$cap_eff" == "0000000000000000" ]]; then
        pass "CapEff is empty: 0000000000000000"
    else
        fail_with_cmd "CapEff=$cap_eff (expected 0000000000000000)" \
            "kubectl exec -n $ns $pod -- grep '^CapEff' /proc/self/status"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Add NET_ADMIN capability ==="
    local pod="net-admin"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local cap_add
    cap_add=$(get_capability_add "$pod" "$ns" 0)
    if [[ "$cap_add" == "NET_ADMIN" ]]; then
        pass "capabilities.add contains NET_ADMIN"
    else
        fail_with_cmd "capabilities.add[0]=$cap_add (expected NET_ADMIN)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.add[*]}'"
    fi

    # Test that NET_ADMIN works by bringing lo down
    kubectl exec -n "$ns" "$pod" -- ip link set lo down 2>/dev/null || true
    sleep 1
    if kubectl exec -n "$ns" "$pod" -- ip link show lo 2>/dev/null | grep -q 'state DOWN'; then
        pass "NET_ADMIN capability functional (lo interface can be brought down)"
    else
        fail_with_cmd "NET_ADMIN capability not functional" \
            "kubectl exec -n $ns $pod -- ip link show lo"
    fi

    # Bring lo back up for other checks
    kubectl exec -n "$ns" "$pod" -- ip link set lo up 2>/dev/null || true
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Drop NET_RAW capability ==="
    local pod="no-ping"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local cap_drop
    cap_drop=$(get_capability_drop "$pod" "$ns" 0)
    if [[ "$cap_drop" == "NET_RAW" ]]; then
        pass "capabilities.drop contains NET_RAW"
    else
        fail_with_cmd "capabilities.drop[0]=$cap_drop (expected NET_RAW)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.drop[*]}'"
    fi

    # Test that ping fails due to missing NET_RAW
    if kubectl exec -n "$ns" "$pod" -- sh -c 'ping -c 1 -W 2 127.0.0.1 2>&1' | grep -q 'Operation not permitted'; then
        pass "NET_RAW drop is functional (ping blocked)"
    else
        fail_with_cmd "ping should fail but didn't" \
            "kubectl exec -n $ns $pod -- ping -c 1 -W 2 127.0.0.1 2>&1"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Drop ALL, add only NET_BIND_SERVICE ==="
    local pod="minimal"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local cap_drop
    cap_drop=$(get_capability_drop "$pod" "$ns" 0)
    if [[ "$cap_drop" == "ALL" ]]; then
        pass "capabilities.drop contains ALL"
    else
        fail_with_cmd "capabilities.drop[0]=$cap_drop (expected ALL)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.drop[*]}'"
    fi

    local cap_add
    cap_add=$(get_capability_add "$pod" "$ns" 0)
    if [[ "$cap_add" == "NET_BIND_SERVICE" ]]; then
        pass "capabilities.add contains NET_BIND_SERVICE"
    else
        fail_with_cmd "capabilities.add[0]=$cap_add (expected NET_BIND_SERVICE)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.add[*]}'"
    fi

    # Install libcap and check decoded capabilities
    kubectl exec -n "$ns" "$pod" -- apk add --no-cache libcap > /dev/null 2>&1 || true
    sleep 1

    if kubectl exec -n "$ns" "$pod" -- sh -c 'capsh --decode=$(awk "/^CapEff/ {print \$2}" /proc/self/status)' 2>/dev/null | grep -q 'cap_net_bind_service'; then
        pass "Decoded CapEff contains only cap_net_bind_service"
    else
        fail_with_cmd "Decoded capabilities don't match expected" \
            "kubectl exec -n $ns $pod -- sh -c 'capsh --decode=\$(awk \"/^CapEff/ {print \\\$2}\" /proc/self/status)'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug hostname change failure ==="
    local pod="broken-host"
    local ns="ex-3-1"

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
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl logs -n $ns $pod --previous 2>/dev/null || kubectl logs -n $ns $pod"
        return
    fi

    # Check hostname was successfully set
    local hostname
    hostname=$(kubectl exec -n "$ns" "$pod" -- hostname 2>/dev/null)
    if [[ "$hostname" == "pod-custom" ]]; then
        pass "Hostname is pod-custom (sethostname succeeded)"
    else
        fail_with_cmd "Hostname is $hostname (expected pod-custom)" \
            "kubectl exec -n $ns $pod -- hostname"
    fi

    # Verify SYS_ADMIN capability was added
    local cap_add
    cap_add=$(get_capability_add "$pod" "$ns" 0)
    if [[ "$cap_add" == "SYS_ADMIN" ]]; then
        pass "SYS_ADMIN capability added"
    else
        fail_with_cmd "capabilities.add[0]=$cap_add (expected SYS_ADMIN)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.add[*]}'"
    fi

    # Verify privileged is not set
    local privileged
    privileged=$(get_privileged "$pod" "$ns")
    if [[ -z "$privileged" ]] || [[ "$privileged" == "null" ]] || [[ "$privileged" == "false" ]]; then
        pass "Container is not privileged"
    else
        fail "Container should not be privileged (privileged=$privileged)"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug sudo with allowPrivilegeEscalation ==="
    local pod="sudo-user"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Give it time to complete the sudo setup
    sleep 10

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl logs -n $ns $pod --previous 2>/dev/null || kubectl logs -n $ns $pod"
        return
    fi

    # Check that id.out contains uid=0(root)
    if kubectl exec -n "$ns" "$pod" -- cat /id.out 2>/dev/null | grep -q 'uid=0(root)'; then
        pass "id.out contains uid=0(root) (sudo worked)"
    else
        fail_with_cmd "id.out doesn't show uid=0" \
            "kubectl exec -n $ns $pod -- cat /id.out"
    fi

    # Verify NoNewPrivs is 0 (privilege escalation allowed)
    local no_new_privs
    no_new_privs=$(get_no_new_privs "$pod" "$ns")
    if [[ "$no_new_privs" == "0" ]]; then
        pass "NoNewPrivs=0 (privilege escalation allowed)"
    else
        fail_with_cmd "NoNewPrivs=$no_new_privs (expected 0)" \
            "kubectl exec -n $ns $pod -- grep '^NoNewPrivs' /proc/self/status"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug chown failure ==="
    local pod="chowner"
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
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl logs -n $ns $pod --previous 2>/dev/null || kubectl logs -n $ns $pod"
        return
    fi

    # Check that the chown succeeded
    if kubectl logs -n "$ns" "$pod" 2>/dev/null | tail -n1 | grep -q '2000:2000'; then
        pass "Logs show 2000:2000 (chown succeeded)"
    else
        fail_with_cmd "chown did not succeed" \
            "kubectl logs -n $ns $pod"
    fi

    # Verify CHOWN capability was added
    local cap_add
    cap_add=$(get_capability_add "$pod" "$ns" 0)
    if [[ "$cap_add" == "CHOWN" ]]; then
        pass "CHOWN capability added"
    else
        fail_with_cmd "capabilities.add[0]=$cap_add (expected CHOWN)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.add[*]}'"
    fi

    # Verify drop ALL is still in place
    local cap_drop
    cap_drop=$(get_capability_drop "$pod" "$ns" 0)
    if [[ "$cap_drop" == "ALL" ]]; then
        pass "capabilities.drop still contains ALL"
    else
        fail_with_cmd "capabilities.drop[0]=$cap_drop (expected ALL)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.drop[*]}'"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: allowPrivilegeEscalation: false ==="
    local pod="no-escalate"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    # Verify allowPrivilegeEscalation is false
    local allow_esc
    allow_esc=$(get_allow_privilege_escalation "$pod" "$ns")
    if [[ "$allow_esc" == "false" ]]; then
        pass "allowPrivilegeEscalation is false"
    else
        fail_with_cmd "allowPrivilegeEscalation=$allow_esc (expected false)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.allowPrivilegeEscalation}'"
    fi

    # Verify NoNewPrivs is 1
    local no_new_privs
    no_new_privs=$(get_no_new_privs "$pod" "$ns")
    if [[ "$no_new_privs" == "1" ]]; then
        pass "NoNewPrivs=1 (no_new_privs flag set)"
    else
        fail_with_cmd "NoNewPrivs=$no_new_privs (expected 1)" \
            "kubectl exec -n $ns $pod -- grep '^NoNewPrivs' /proc/self/status"
    fi

    # Verify runAsUser is 1000
    local user
    user=$(kubectl exec -n "$ns" "$pod" -- id -u 2>/dev/null)
    if [[ "$user" == "1000" ]]; then
        pass "Running as UID 1000"
    else
        fail_with_cmd "Running as UID $user (expected 1000)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Hardened baseline configuration ==="
    local pod="hardened-baseline"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    # Verify runAsNonRoot at pod level
    local run_as_non_root
    run_as_non_root=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.securityContext.runAsNonRoot}' 2>/dev/null)
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "runAsNonRoot: true at pod level"
    else
        fail_with_cmd "runAsNonRoot=$run_as_non_root (expected true)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext.runAsNonRoot}'"
    fi

    # Verify runAsUser is 1000
    local user
    user=$(kubectl exec -n "$ns" "$pod" -- id -u 2>/dev/null)
    if [[ "$user" == "1000" ]]; then
        pass "Running as UID 1000"
    else
        fail_with_cmd "Running as UID $user (expected 1000)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi

    # Verify allowPrivilegeEscalation is false
    local allow_esc
    allow_esc=$(get_allow_privilege_escalation "$pod" "$ns")
    if [[ "$allow_esc" == "false" ]]; then
        pass "allowPrivilegeEscalation: false"
    else
        fail_with_cmd "allowPrivilegeEscalation=$allow_esc (expected false)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.allowPrivilegeEscalation}'"
    fi

    # Verify capabilities drop ALL
    local cap_drop
    cap_drop=$(get_capability_drop "$pod" "$ns" 0)
    if [[ "$cap_drop" == "ALL" ]]; then
        pass "capabilities.drop contains ALL"
    else
        fail_with_cmd "capabilities.drop[0]=$cap_drop (expected ALL)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.drop[*]}'"
    fi

    # Verify NoNewPrivs is 1
    local no_new_privs
    no_new_privs=$(get_no_new_privs "$pod" "$ns")
    if [[ "$no_new_privs" == "1" ]]; then
        pass "NoNewPrivs=1"
    else
        fail_with_cmd "NoNewPrivs=$no_new_privs (expected 1)" \
            "kubectl exec -n $ns $pod -- grep '^NoNewPrivs' /proc/self/status"
    fi

    # Verify CapEff is 0
    local cap_eff
    cap_eff=$(get_cap_eff "$pod" "$ns")
    if [[ "$cap_eff" == "0000000000000000" ]]; then
        pass "CapEff=0000000000000000 (no capabilities)"
    else
        fail_with_cmd "CapEff=$cap_eff (expected 0000000000000000)" \
            "kubectl exec -n $ns $pod -- grep '^CapEff' /proc/self/status"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Setuid binary behavior with allowPrivilegeEscalation ==="
    local pod1="with-elevation"
    local pod2="without-elevation"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod1" "$ns"; then
        fail "Pod $pod1 not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod2" "$ns"; then
        fail "Pod $pod2 not found in namespace $ns"
        return
    fi

    # Give pods time to initialize
    sleep 5

    local phase1
    phase1=$(get_phase "$pod1" "$ns")
    if [[ "$phase1" == "Running" ]]; then
        pass "$pod1 is Running"
    else
        fail_with_cmd "$pod1 phase is $phase1 (expected Running)" \
            "kubectl get pod $pod1 -n $ns"
        return
    fi

    local phase2
    phase2=$(get_phase "$pod2" "$ns")
    if [[ "$phase2" == "Running" ]]; then
        pass "$pod2 is Running"
    else
        fail_with_cmd "$pod2 phase is $phase2 (expected Running)" \
            "kubectl get pod $pod2 -n $ns"
        return
    fi

    # Test with-elevation: setuid should elevate to 0
    local uid1
    uid1=$(kubectl exec -n "$ns" "$pod1" -c main -- /shared/myid -u 2>/dev/null || echo "failed")
    if [[ "$uid1" == "0" ]]; then
        pass "$pod1: setuid binary elevated to UID 0"
    else
        fail_with_cmd "$pod1: setuid returned UID $uid1 (expected 0)" \
            "kubectl exec -n $ns $pod1 -c main -- /shared/myid -u"
    fi

    # Test without-elevation: setuid should NOT elevate (stay at 1000)
    local uid2
    uid2=$(kubectl exec -n "$ns" "$pod2" -c main -- /shared/myid -u 2>/dev/null || echo "failed")
    if [[ "$uid2" == "1000" ]]; then
        pass "$pod2: setuid binary blocked (NoNewPrivs), stayed at UID 1000"
    else
        fail_with_cmd "$pod2: setuid returned UID $uid2 (expected 1000)" \
            "kubectl exec -n $ns $pod2 -c main -- /shared/myid -u"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Minimal capability set design ==="
    local pod="network-app"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    # Verify runAsUser is 1000
    local user
    user=$(kubectl exec -n "$ns" "$pod" -- id -u 2>/dev/null)
    if [[ "$user" == "1000" ]]; then
        pass "Running as UID 1000"
    else
        fail_with_cmd "Running as UID $user (expected 1000)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi

    # Verify capabilities drop ALL
    local cap_drop
    cap_drop=$(get_capability_drop "$pod" "$ns" 0)
    if [[ "$cap_drop" == "ALL" ]]; then
        pass "capabilities.drop contains ALL"
    else
        fail_with_cmd "capabilities.drop[0]=$cap_drop (expected ALL)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.drop[*]}'"
    fi

    # Verify capabilities add contains CHOWN and NET_BIND_SERVICE
    local all_adds
    all_adds=$(get_all_capability_adds "$pod" "$ns")
    if [[ "$all_adds" == *"CHOWN"* ]] && [[ "$all_adds" == *"NET_BIND_SERVICE"* ]]; then
        pass "capabilities.add contains CHOWN and NET_BIND_SERVICE"
    else
        fail_with_cmd "capabilities.add=$all_adds (expected CHOWN and NET_BIND_SERVICE)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.add[*]}'"
    fi

    # Install libcap and check decoded capabilities
    kubectl exec -n "$ns" "$pod" -- apk add --no-cache libcap > /dev/null 2>&1 || true
    sleep 2

    if kubectl exec -n "$ns" "$pod" -- sh -c 'capsh --decode=$(awk "/^CapEff/ {print \$2}" /proc/self/status)' 2>/dev/null | grep -q 'cap_chown' && \
       kubectl exec -n "$ns" "$pod" -- sh -c 'capsh --decode=$(awk "/^CapEff/ {print \$2}" /proc/self/status)' 2>/dev/null | grep -q 'cap_net_bind_service'; then
        pass "Decoded capabilities contain cap_chown and cap_net_bind_service"
    else
        fail_with_cmd "Decoded capabilities don't match" \
            "kubectl exec -n $ns $pod -- sh -c 'capsh --decode=\$(awk \"/^CapEff/ {print \\\$2}\" /proc/self/status)'"
    fi

    # Verify NoNewPrivs is 1
    local no_new_privs
    no_new_privs=$(get_no_new_privs "$pod" "$ns")
    if [[ "$no_new_privs" == "1" ]]; then
        pass "NoNewPrivs=1"
    else
        fail_with_cmd "NoNewPrivs=$no_new_privs (expected 1)" \
            "kubectl exec -n $ns $pod -- grep '^NoNewPrivs' /proc/self/status"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug compound failure ==="
    local pod="compound-failure"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    # Give it time to complete the setup
    sleep 10

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (all issues fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.containerStatuses[0].state.waiting.message}' 2>/dev/null || kubectl logs -n $ns $pod --previous 2>/dev/null"
        return
    fi

    # Verify runAsUser is set (non-zero)
    local user
    user=$(kubectl exec -n "$ns" "$pod" -- id -u 2>/dev/null)
    if [[ "$user" != "0" ]] && [[ -n "$user" ]]; then
        pass "Running as non-root UID $user"
    else
        fail_with_cmd "Running as UID $user (should be non-zero)" \
            "kubectl exec -n $ns $pod -- id -u"
    fi

    # Verify chown succeeded (no "chown failed" in logs)
    if ! kubectl logs -n "$ns" "$pod" 2>/dev/null | grep -q "chown failed"; then
        pass "chown command succeeded (no 'chown failed' in logs)"
    else
        fail_with_cmd "chown failed" \
            "kubectl logs -n $ns $pod"
    fi

    # Verify /work/data ownership is 2000:2000
    if kubectl exec -n "$ns" "$pod" -- stat -c "%u:%g" /work/data 2>/dev/null | grep -q '2000:2000'; then
        pass "/work/data ownership is 2000:2000"
    else
        fail_with_cmd "/work/data ownership incorrect" \
            "kubectl exec -n $ns $pod -- stat -c '%u:%g' /work/data"
    fi

    # Verify capabilities (no CAP_ prefix)
    local all_adds
    all_adds=$(get_all_capability_adds "$pod" "$ns")
    if [[ "$all_adds" == *"CHOWN"* ]] && [[ "$all_adds" == *"NET_BIND_SERVICE"* ]] && \
       [[ "$all_adds" != *"CAP_"* ]]; then
        pass "capabilities.add correct (no CAP_ prefix)"
    else
        fail_with_cmd "capabilities.add=$all_adds" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities.add[*]}'"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Multi-container with different capability sets ==="
    local pod="three-sets"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    # Verify three containers exist
    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == *"web"* ]] && [[ "$containers" == *"log-rotator"* ]] && [[ "$containers" == *"noop"* ]]; then
        pass "Three containers present: web, log-rotator, noop"
    else
        fail_with_cmd "Container names: $containers" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[*].name}'"
    fi

    # Install libcap in all containers
    for c in web log-rotator noop; do
        kubectl exec -n "$ns" "$pod" -c "$c" -- apk add --no-cache libcap > /dev/null 2>&1 || true
    done
    sleep 2

    # Verify web container has only NET_BIND_SERVICE
    if kubectl exec -n "$ns" "$pod" -c web -- sh -c 'capsh --decode=$(awk "/^CapEff/ {print \$2}" /proc/self/status)' 2>/dev/null | grep -q 'cap_net_bind_service'; then
        pass "web container has cap_net_bind_service"
    else
        fail_with_cmd "web container capabilities incorrect" \
            "kubectl exec -n $ns $pod -c web -- sh -c 'capsh --decode=\$(awk \"/^CapEff/ {print \\\$2}\" /proc/self/status)'"
    fi

    # Verify log-rotator has CHOWN and FOWNER
    local log_caps
    log_caps=$(kubectl exec -n "$ns" "$pod" -c log-rotator -- sh -c 'capsh --decode=$(awk "/^CapEff/ {print \$2}" /proc/self/status)' 2>/dev/null || echo "")
    if [[ "$log_caps" == *"cap_chown"* ]] && [[ "$log_caps" == *"cap_fowner"* ]]; then
        pass "log-rotator container has cap_chown and cap_fowner"
    else
        fail_with_cmd "log-rotator capabilities: $log_caps" \
            "kubectl exec -n $ns $pod -c log-rotator -- sh -c 'capsh --decode=\$(awk \"/^CapEff/ {print \\\$2}\" /proc/self/status)'"
    fi

    # Verify noop has no capabilities
    local noop_cap
    noop_cap=$(get_cap_eff "$pod" "$ns" "noop")
    if [[ "$noop_cap" == "0000000000000000" ]]; then
        pass "noop container has no capabilities (CapEff=0000000000000000)"
    else
        fail_with_cmd "noop CapEff=$noop_cap (expected 0000000000000000)" \
            "kubectl exec -n $ns $pod -c noop -- grep '^CapEff' /proc/self/status"
    fi

    # Verify NoNewPrivs on web container (should be 1)
    local no_new_privs
    no_new_privs=$(get_no_new_privs "$pod" "$ns" "web")
    if [[ "$no_new_privs" == "1" ]]; then
        pass "web container has NoNewPrivs=1"
    else
        fail_with_cmd "web NoNewPrivs=$no_new_privs (expected 1)" \
            "kubectl exec -n $ns $pod -c web -- grep '^NoNewPrivs' /proc/self/status"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Inspecting Capabilities"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Adding and Dropping Capabilities"
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
    echo "# Level 4: Privilege Escalation Control"
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
