#!/usr/bin/env bash
#
# verify.sh - Automated verification for pod-security-homework.md
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

# Helper: get namespace label value
get_namespace_label() {
    local ns=$1
    local label=$2
    kubectl get namespace "$ns" -o jsonpath="{.metadata.labels.pod-security\.kubernetes\.io/$label}" 2>/dev/null || echo ""
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

# Helper: get pod image
get_image() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null
}

# Helper: get security context field from pod
get_pod_security_field() {
    local pod=$1
    local ns=$2
    local field=$3
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.securityContext.$field}" 2>/dev/null
}

# Helper: get security context field from container
get_container_security_field() {
    local pod=$1
    local ns=$2
    local field=$3
    kubectl get pod "$pod" -n "$ns" -o jsonpath="{.spec.containers[0].securityContext.$field}" 2>/dev/null
}

# Helper: check if deployment exists
deployment_exists() {
    local deploy=$1
    local ns=$2
    kubectl get deployment "$deploy" -n "$ns" &>/dev/null
}

# Helper: get deployment ready replicas
get_ready_replicas() {
    local deploy=$1
    local ns=$2
    kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"
}

# Helper: get deployment template field
get_deployment_template_field() {
    local deploy=$1
    local ns=$2
    local field=$3
    kubectl get deployment "$deploy" -n "$ns" -o jsonpath="{.spec.template.spec.$field}" 2>/dev/null
}

# Helper: get deployment template container field
get_deployment_container_field() {
    local deploy=$1
    local ns=$2
    local field=$3
    kubectl get deployment "$deploy" -n "$ns" -o jsonpath="{.spec.template.spec.containers[0].$field}" 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Baseline enforcement with compliant pod ==="
    local pod="web"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local enforce_label
    enforce_label=$(get_namespace_label "$ns" "enforce")
    if [[ "$enforce_label" == "baseline" ]]; then
        pass "Namespace labeled with enforce=baseline"
    else
        fail_with_cmd "Namespace enforce label is '$enforce_label' (expected baseline)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'"
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
            "kubectl get pod $pod -n $ns -o jsonpath='{.status.phase}'"
    fi

    local image
    image=$(get_image "$pod" "$ns")
    if [[ "$image" == "nginx:1.25" ]]; then
        pass "Image is nginx:1.25"
    else
        fail_with_cmd "Image is $image (expected nginx:1.25)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].image}'"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Warn-level Restricted (pod not blocked) ==="
    local pod="probe"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local warn_label
    warn_label=$(get_namespace_label "$ns" "warn")
    if [[ "$warn_label" == "restricted" ]]; then
        pass "Namespace labeled with warn=restricted"
    else
        fail_with_cmd "Namespace warn label is '$warn_label' (expected restricted)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/warn}'"
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail_with_cmd "Pod $pod not found (warn mode should not block)" \
            "kubectl get pod $pod -n $ns"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]] || [[ "$phase" == "Pending" ]]; then
        pass "Pod exists and is $phase (warn did not block)"
    else
        fail "Pod phase is $phase (unexpected)"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Enforce Restricted (pod rejected) ==="
    local pod="naive"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local enforce_label
    enforce_label=$(get_namespace_label "$ns" "enforce")
    if [[ "$enforce_label" == "restricted" ]]; then
        pass "Namespace labeled with enforce=restricted"
    else
        fail_with_cmd "Namespace enforce label is '$enforce_label' (expected restricted)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}'"
    fi

    if pod_exists "$pod" "$ns"; then
        fail "Pod $pod exists (should have been rejected by enforce=restricted)"
    else
        pass "Pod $pod does not exist (correctly rejected)"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Multiple modes on one namespace ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local enforce_label
    enforce_label=$(get_namespace_label "$ns" "enforce")
    if [[ "$enforce_label" == "baseline" ]]; then
        pass "Namespace labeled with enforce=baseline"
    else
        fail_with_cmd "Namespace enforce label is '$enforce_label' (expected baseline)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    local audit_label
    audit_label=$(get_namespace_label "$ns" "audit")
    if [[ "$audit_label" == "restricted" ]]; then
        pass "Namespace labeled with audit=restricted"
    else
        fail_with_cmd "Namespace audit label is '$audit_label' (expected restricted)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    local warn_label
    warn_label=$(get_namespace_label "$ns" "warn")
    if [[ "$warn_label" == "restricted" ]]; then
        pass "Namespace labeled with warn=restricted"
    else
        fail_with_cmd "Namespace warn label is '$warn_label' (expected restricted)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Version pinning ==="
    local pod="anchor"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local enforce_label
    enforce_label=$(get_namespace_label "$ns" "enforce")
    if [[ "$enforce_label" == "baseline" ]]; then
        pass "Namespace labeled with enforce=baseline"
    else
        fail_with_cmd "Namespace enforce label is '$enforce_label' (expected baseline)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    local version_label
    version_label=$(get_namespace_label "$ns" "enforce-version")
    if [[ "$version_label" == "v1.30" ]]; then
        pass "Namespace labeled with enforce-version=v1.30"
    else
        fail_with_cmd "Namespace enforce-version label is '$version_label' (expected v1.30)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
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
        fail "Pod phase is $phase (expected Running)"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Restricted-compliant pod ==="
    local pod="hardened"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local run_as_non_root
    run_as_non_root=$(get_pod_security_field "$pod" "$ns" "runAsNonRoot")
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "Pod securityContext.runAsNonRoot=true"
    else
        fail_with_cmd "Pod securityContext.runAsNonRoot=$run_as_non_root (expected true)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext}'"
    fi

    local allow_priv_esc
    allow_priv_esc=$(get_container_security_field "$pod" "$ns" "allowPrivilegeEscalation")
    if [[ "$allow_priv_esc" == "false" ]]; then
        pass "Container securityContext.allowPrivilegeEscalation=false"
    else
        fail_with_cmd "Container securityContext.allowPrivilegeEscalation=$allow_priv_esc (expected false)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext}'"
    fi

    local caps_drop
    caps_drop=$(get_container_security_field "$pod" "$ns" "capabilities.drop[0]")
    if [[ "$caps_drop" == "ALL" ]]; then
        pass "Container capabilities.drop=[ALL]"
    else
        fail_with_cmd "Container capabilities.drop[0]=$caps_drop (expected ALL)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities}'"
    fi

    local seccomp
    seccomp=$(get_pod_security_field "$pod" "$ns" "seccompProfile.type")
    if [[ "$seccomp" == "RuntimeDefault" ]]; then
        pass "Pod securityContext.seccompProfile.type=RuntimeDefault"
    else
        fail_with_cmd "Pod securityContext.seccompProfile.type=$seccomp (expected RuntimeDefault)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext.seccompProfile}'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix Restricted rejection (missing capabilities) ==="
    local pod="broken-1"
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

    local caps_drop
    caps_drop=$(get_container_security_field "$pod" "$ns" "capabilities.drop[0]")
    if [[ "$caps_drop" == "ALL" ]]; then
        pass "Container capabilities.drop=[ALL] (fix applied)"
    else
        fail_with_cmd "Container capabilities.drop[0]=$caps_drop (expected ALL)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext.capabilities}'"
        info "Hint: Restricted requires capabilities.drop: [\"ALL\"]"
    fi

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail "Pod phase is $phase (expected Running)"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix Deployment with hostNetwork violation ==="
    local deploy="broken-2"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deploy" "$ns"; then
        fail "Deployment $deploy not found in namespace $ns"
        return
    fi

    sleep 15

    local ready
    ready=$(get_ready_replicas "$deploy" "$ns")
    if [[ "$ready" == "2" ]]; then
        pass "Deployment has 2 ready replicas"
    else
        fail_with_cmd "Deployment ready replicas: $ready (expected 2)" \
            "kubectl get deployment $deploy -n $ns; kubectl describe rs -n $ns -l app=$deploy"
        info "Hint: Check for hostNetwork violation in ReplicaSet events"
    fi

    local host_network
    host_network=$(get_deployment_template_field "$deploy" "$ns" "hostNetwork")
    if [[ -z "$host_network" ]] || [[ "$host_network" == "false" ]]; then
        pass "Deployment template hostNetwork is false or unset"
    else
        fail_with_cmd "Deployment template hostNetwork=$host_network (should be false or unset)" \
            "kubectl get deployment $deploy -n $ns -o jsonpath='{.spec.template.spec.hostNetwork}'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix all four Restricted violations ==="
    local pod="broken-3"
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

    local run_as_non_root
    run_as_non_root=$(get_pod_security_field "$pod" "$ns" "runAsNonRoot")
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "Pod securityContext.runAsNonRoot=true"
    else
        fail_with_cmd "Pod securityContext.runAsNonRoot=$run_as_non_root (expected true)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.securityContext}'"
    fi

    local allow_priv_esc
    allow_priv_esc=$(get_container_security_field "$pod" "$ns" "allowPrivilegeEscalation")
    if [[ "$allow_priv_esc" == "false" ]]; then
        pass "Container securityContext.allowPrivilegeEscalation=false"
    else
        fail_with_cmd "Container securityContext.allowPrivilegeEscalation=$allow_priv_esc (expected false)" \
            "kubectl get pod $pod -n $ns -o jsonpath='{.spec.containers[0].securityContext}'"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Production namespace with version pinning ==="
    local deploy="api"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local enforce_version
    enforce_version=$(get_namespace_label "$ns" "enforce-version")
    if [[ "$enforce_version" == "v1.35" ]]; then
        pass "Namespace enforce-version=v1.35"
    else
        fail_with_cmd "Namespace enforce-version=$enforce_version (expected v1.35)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    local audit_version
    audit_version=$(get_namespace_label "$ns" "audit-version")
    if [[ "$audit_version" == "v1.35" ]]; then
        pass "Namespace audit-version=v1.35"
    else
        fail_with_cmd "Namespace audit-version=$audit_version (expected v1.35)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    local warn_version
    warn_version=$(get_namespace_label "$ns" "warn-version")
    if [[ "$warn_version" == "v1.35" ]]; then
        pass "Namespace warn-version=v1.35"
    else
        fail_with_cmd "Namespace warn-version=$warn_version (expected v1.35)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    if ! deployment_exists "$deploy" "$ns"; then
        fail "Deployment $deploy not found in namespace $ns"
        return
    fi

    sleep 10

    local ready
    ready=$(get_ready_replicas "$deploy" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "Deployment has 3 ready replicas"
    else
        fail_with_cmd "Deployment ready replicas: $ready (expected 3)" \
            "kubectl get deployment $deploy -n $ns"
    fi

    local run_as_non_root
    run_as_non_root=$(get_deployment_template_field "$deploy" "$ns" "securityContext.runAsNonRoot")
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "Deployment template securityContext.runAsNonRoot=true"
    else
        fail_with_cmd "Deployment template runAsNonRoot=$run_as_non_root (expected true)" \
            "kubectl get deployment $deploy -n $ns -o jsonpath='{.spec.template.spec.securityContext}'"
    fi

    local caps_drop
    caps_drop=$(get_deployment_container_field "$deploy" "$ns" "securityContext.capabilities.drop[0]")
    if [[ "$caps_drop" == "ALL" ]]; then
        pass "Deployment template container capabilities.drop=[ALL]"
    else
        fail_with_cmd "Deployment template capabilities.drop[0]=$caps_drop (expected ALL)" \
            "kubectl get deployment $deploy -n $ns -o jsonpath='{.spec.template.spec.containers[0].securityContext}'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Migration staging (enforce baseline + warn restricted) ==="
    local ns="ex-4-2"
    local pod1="legacy"
    local pod2="probe"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local enforce_label
    enforce_label=$(get_namespace_label "$ns" "enforce")
    if [[ "$enforce_label" == "baseline" ]]; then
        pass "Namespace enforce=baseline (preserved)"
    else
        fail_with_cmd "Namespace enforce=$enforce_label (expected baseline)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    local warn_label
    warn_label=$(get_namespace_label "$ns" "warn")
    if [[ "$warn_label" == "restricted" ]]; then
        pass "Namespace warn=restricted (added)"
    else
        fail_with_cmd "Namespace warn=$warn_label (expected restricted)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    if ! pod_exists "$pod1" "$ns"; then
        fail "Pod $pod1 not found (should remain running)"
        return
    fi

    local phase1
    phase1=$(get_phase "$pod1" "$ns")
    if [[ "$phase1" == "Running" ]]; then
        pass "Pod $pod1 is Running"
    else
        fail "Pod $pod1 phase is $phase1 (expected Running)"
    fi

    if ! pod_exists "$pod2" "$ns"; then
        fail "Pod $pod2 not found (should be created with warnings)"
        return
    fi

    local phase2
    phase2=$(get_phase "$pod2" "$ns")
    if [[ "$phase2" == "Running" ]]; then
        pass "Pod $pod2 is Running (warn did not block)"
    else
        fail "Pod $pod2 phase is $phase2 (expected Running)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Side-by-side baseline vs restricted ==="
    local pod="explorer"
    local ns1="ex-4-3"
    local ns2="ex-4-3-audit"

    if ! namespace_exists "$ns1"; then
        fail "Namespace $ns1 does not exist"
        return
    fi

    if ! namespace_exists "$ns2"; then
        fail "Namespace $ns2 does not exist"
        return
    fi

    local version_label
    version_label=$(get_namespace_label "$ns1" "enforce-version")
    if [[ "$version_label" == "v1.30" ]]; then
        pass "Namespace $ns1 enforce-version=v1.30"
    else
        fail_with_cmd "Namespace $ns1 enforce-version=$version_label (expected v1.30)" \
            "kubectl get namespace $ns1 -o jsonpath='{.metadata.labels}'"
    fi

    if ! pod_exists "$pod" "$ns1"; then
        fail "Pod $pod not found in namespace $ns1 (should be accepted)"
        return
    fi

    local phase
    phase=$(get_phase "$pod" "$ns1")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod $pod in $ns1 is Running (baseline accepted)"
    else
        fail "Pod $pod in $ns1 phase is $phase (expected Running)"
    fi

    if pod_exists "$pod" "$ns2"; then
        fail "Pod $pod exists in namespace $ns2 (should have been rejected by restricted)"
    else
        pass "Pod $pod does not exist in $ns2 (correctly rejected by restricted)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Comprehensive namespace and deployment ==="
    local deploy="secure-api"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    for mode in enforce audit warn; do
        local label
        label=$(get_namespace_label "$ns" "$mode")
        if [[ "$label" == "restricted" ]]; then
            pass "Namespace $mode=restricted"
        else
            fail_with_cmd "Namespace $mode=$label (expected restricted)" \
                "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
        fi
    done

    local enforce_version
    enforce_version=$(get_namespace_label "$ns" "enforce-version")
    if [[ "$enforce_version" == "v1.35" ]]; then
        pass "Namespace enforce-version=v1.35"
    else
        fail_with_cmd "Namespace enforce-version=$enforce_version (expected v1.35)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    local audit_version
    audit_version=$(get_namespace_label "$ns" "audit-version")
    if [[ "$audit_version" == "latest" ]]; then
        pass "Namespace audit-version=latest"
    else
        fail_with_cmd "Namespace audit-version=$audit_version (expected latest)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    local warn_version
    warn_version=$(get_namespace_label "$ns" "warn-version")
    if [[ "$warn_version" == "latest" ]]; then
        pass "Namespace warn-version=latest"
    else
        fail_with_cmd "Namespace warn-version=$warn_version (expected latest)" \
            "kubectl get namespace $ns -o jsonpath='{.metadata.labels}'"
    fi

    if ! deployment_exists "$deploy" "$ns"; then
        fail "Deployment $deploy not found in namespace $ns"
        return
    fi

    sleep 10

    local ready
    ready=$(get_ready_replicas "$deploy" "$ns")
    if [[ "$ready" == "2" ]]; then
        pass "Deployment has 2 ready replicas"
    else
        fail_with_cmd "Deployment ready replicas: $ready (expected 2)" \
            "kubectl get deployment $deploy -n $ns"
    fi

    local run_as_user
    run_as_user=$(get_deployment_template_field "$deploy" "$ns" "securityContext.runAsUser")
    if [[ "$run_as_user" == "101" ]]; then
        pass "Deployment template securityContext.runAsUser=101"
    else
        fail_with_cmd "Deployment template runAsUser=$run_as_user (expected 101)" \
            "kubectl get deployment $deploy -n $ns -o jsonpath='{.spec.template.spec.securityContext}'"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Multiple bugs in Deployment ==="
    local deploy="multibug"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deploy" "$ns"; then
        fail "Deployment $deploy not found in namespace $ns"
        return
    fi

    sleep 15

    local ready
    ready=$(get_ready_replicas "$deploy" "$ns")
    if [[ "$ready" == "2" ]]; then
        pass "Deployment has 2 ready replicas (all bugs fixed)"
    else
        fail_with_cmd "Deployment ready replicas: $ready (expected 2)" \
            "kubectl get deployment $deploy -n $ns; kubectl describe rs -n $ns -l app=$deploy"
        info "Hint: Check for hostNetwork, privileged, capabilities, runAsNonRoot violations"
        return
    fi

    local host_network
    host_network=$(get_deployment_template_field "$deploy" "$ns" "hostNetwork")
    if [[ -z "$host_network" ]] || [[ "$host_network" == "false" ]]; then
        pass "Deployment template hostNetwork removed or false"
    else
        fail "Deployment template hostNetwork=$host_network (should be false or unset)"
    fi

    local run_as_non_root
    run_as_non_root=$(get_deployment_template_field "$deploy" "$ns" "securityContext.runAsNonRoot")
    if [[ "$run_as_non_root" == "true" ]]; then
        pass "Deployment template securityContext.runAsNonRoot=true"
    else
        fail "Deployment template runAsNonRoot=$run_as_non_root (expected true)"
    fi

    local allow_priv_esc
    allow_priv_esc=$(get_deployment_container_field "$deploy" "$ns" "securityContext.allowPrivilegeEscalation")
    if [[ "$allow_priv_esc" == "false" ]]; then
        pass "Deployment template container allowPrivilegeEscalation=false"
    else
        fail "Deployment template allowPrivilegeEscalation=$allow_priv_esc (expected false)"
    fi

    local caps_drop
    caps_drop=$(get_deployment_container_field "$deploy" "$ns" "securityContext.capabilities.drop[0]")
    if [[ "$caps_drop" == "ALL" ]]; then
        pass "Deployment template container capabilities.drop=[ALL]"
    else
        fail "Deployment template capabilities.drop[0]=$caps_drop (expected ALL)"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Subtle runAsUser contradiction ==="
    local deploy="subtle"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deploy" "$ns"; then
        fail "Deployment $deploy not found in namespace $ns"
        return
    fi

    sleep 15

    local ready
    ready=$(get_ready_replicas "$deploy" "$ns")
    if [[ "$ready" == "2" ]]; then
        pass "Deployment has 2 ready replicas (contradiction fixed)"
    else
        fail_with_cmd "Deployment ready replicas: $ready (expected 2)" \
            "kubectl get deployment $deploy -n $ns; kubectl describe rs -n $ns -l app=$deploy"
        info "Hint: Check for runAsNonRoot=true with runAsUser=0 contradiction"
        return
    fi

    local run_as_user
    run_as_user=$(get_deployment_template_field "$deploy" "$ns" "securityContext.runAsUser")
    if [[ "$run_as_user" != "0" ]] && [[ -n "$run_as_user" ]]; then
        pass "Deployment template securityContext.runAsUser=$run_as_user (non-zero)"
    elif [[ -z "$run_as_user" ]]; then
        pass "Deployment template securityContext.runAsUser unset (using image default)"
    else
        fail "Deployment template runAsUser=$run_as_user (should not be 0 when runAsNonRoot=true)"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic Single-Concept Tasks"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Multi-Concept Tasks"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Broken Configurations"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Complex Real-World Scenarios"
    echo "###############################################"
    verify_4_1
    verify_4_2
    verify_4_3
}

verify_level_5() {
    echo ""
    echo "###############################################"
    echo "# Level 5: Advanced Debugging and Comprehensive Tasks"
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
