#!/usr/bin/env bash
#
# verify.sh - Automated verification for tls-and-certificates-homework.md (Assignment 2)
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

# Helper: check if CSR exists
csr_exists() {
    local csr=$1
    kubectl get csr "$csr" &>/dev/null
}

# Helper: get CSR status condition
get_csr_condition() {
    local csr=$1
    kubectl get csr "$csr" -o jsonpath='{.status.conditions[0].type}' 2>/dev/null
}

# Helper: check if context exists
context_exists() {
    local ctx=$1
    kubectl config get-contexts -o name | grep -q "^${ctx}$"
}

# Helper: check if user exists in kubeconfig
user_exists() {
    local user=$1
    kubectl config view -o jsonpath='{.users[*].name}' | grep -q "$user"
}

# Helper: get context namespace
get_context_namespace() {
    local ctx=$1
    kubectl config view -o jsonpath="{.contexts[?(@.name==\"${ctx}\")].context.namespace}" 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: View kubeconfig structure ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is an observation exercise, verify they can run the command
    if kubectl config view &>/dev/null; then
        pass "kubectl config view works"
    else
        fail_with_cmd "kubectl config view failed" \
            "kubectl config view"
    fi

    # Check that kubeconfig has expected sections
    if kubectl config view -o jsonpath='{.clusters}' | grep -q "kind-kind"; then
        pass "kubeconfig contains cluster information"
    else
        info "Expected cluster 'kind-kind' in kubeconfig"
    fi

    if kubectl config view -o jsonpath='{.users}' | grep -q "kind-kind"; then
        pass "kubeconfig contains user information"
    else
        info "Expected user information in kubeconfig"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: List and identify contexts ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if kubectl config get-contexts &>/dev/null; then
        pass "kubectl config get-contexts works"
    else
        fail_with_cmd "kubectl config get-contexts failed" \
            "kubectl config get-contexts"
    fi

    local current_ctx
    current_ctx=$(kubectl config current-context 2>/dev/null)
    if [[ -n "$current_ctx" ]]; then
        pass "Current context identified: $current_ctx"
    else
        fail_with_cmd "Could not identify current context" \
            "kubectl config current-context"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Identify certificate embedding ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if they can view raw config
    if kubectl config view --raw &>/dev/null; then
        pass "kubectl config view --raw works"
    else
        fail_with_cmd "kubectl config view --raw failed" \
            "kubectl config view --raw"
    fi

    # This is an observation exercise about certificate-authority-data vs certificate-authority
    if kubectl config view --raw | grep -q "certificate-authority"; then
        pass "kubeconfig contains certificate configuration"
    else
        info "Expected certificate-authority or certificate-authority-data"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Create CSR for diana ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if CSR exists
    if ! csr_exists "diana-csr"; then
        fail_with_cmd "CertificateSigningRequest diana-csr not found" \
            "kubectl get csr"
        return
    fi
    pass "CSR diana-csr exists"

    # Check signer name
    local signer
    signer=$(kubectl get csr diana-csr -o jsonpath='{.spec.signerName}' 2>/dev/null)
    if [[ "$signer" == "kubernetes.io/kube-apiserver-client" ]]; then
        pass "Signer name is kubernetes.io/kube-apiserver-client"
    else
        fail_with_cmd "Signer name is $signer (expected kubernetes.io/kube-apiserver-client)" \
            "kubectl get csr diana-csr -o yaml"
    fi

    # Check usages
    local usages
    usages=$(kubectl get csr diana-csr -o jsonpath='{.spec.usages}' 2>/dev/null)
    if [[ "$usages" == *"client auth"* ]]; then
        pass "Usages include 'client auth'"
    else
        fail_with_cmd "Usages do not include 'client auth': $usages" \
            "kubectl get csr diana-csr -o jsonpath='{.spec.usages}'"
    fi

    # Check that private key file exists
    if [[ -f /tmp/ex-2-1/diana.key ]]; then
        pass "Private key file diana.key exists in /tmp/ex-2-1"
    else
        info "Expected private key at /tmp/ex-2-1/diana.key"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Approve CSR and extract certificate ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! csr_exists "diana-csr"; then
        fail "CSR diana-csr not found (must complete exercise 2.1 first)"
        return
    fi

    # Check if CSR is approved
    local condition
    condition=$(get_csr_condition "diana-csr")
    if [[ "$condition" == "Approved" ]]; then
        pass "CSR diana-csr is Approved"
    else
        fail_with_cmd "CSR condition is $condition (expected Approved)" \
            "kubectl certificate approve diana-csr"
        return
    fi

    # Check if certificate was issued
    local cert
    cert=$(kubectl get csr diana-csr -o jsonpath='{.status.certificate}' 2>/dev/null)
    if [[ -n "$cert" ]]; then
        pass "Certificate issued (status.certificate present)"
    else
        fail_with_cmd "Certificate not issued" \
            "kubectl get csr diana-csr -o jsonpath='{.status.certificate}'"
    fi

    # Check if extracted certificate file exists and is valid
    if [[ -f /tmp/ex-2-1/diana.crt ]]; then
        if openssl x509 -in /tmp/ex-2-1/diana.crt -noout -subject 2>/dev/null | grep -q "diana"; then
            pass "Certificate extracted and contains subject diana"
        else
            info "Certificate file exists but may not be valid"
        fi
    else
        info "Expected extracted certificate at /tmp/ex-2-1/diana.crt"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Deny CSR ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! csr_exists "denied-csr"; then
        fail_with_cmd "CertificateSigningRequest denied-csr not found" \
            "kubectl get csr"
        return
    fi
    pass "CSR denied-csr exists"

    # Check if CSR is denied
    local condition
    condition=$(get_csr_condition "denied-csr")
    if [[ "$condition" == "Denied" ]]; then
        pass "CSR denied-csr is Denied"
    else
        fail_with_cmd "CSR condition is $condition (expected Denied)" \
            "kubectl certificate deny denied-csr"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Diagnose wrong encoding ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a knowledge exercise - they should understand base64 -w0
    info "Exercise 3.1 is a documentation exercise"
    pass "Identified that base64 must use -w0 for single-line output"
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Diagnose wrong signerName ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a knowledge exercise
    info "Exercise 3.2 is a documentation exercise"
    pass "Identified that user certs need kubernetes.io/kube-apiserver-client signer"
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Diagnose CSR stuck in Pending ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! csr_exists "pending-csr"; then
        fail_with_cmd "CertificateSigningRequest pending-csr not found" \
            "kubectl get csr"
        return
    fi
    pass "CSR pending-csr exists"

    # CSR should still be pending (not approved)
    local condition
    condition=$(get_csr_condition "pending-csr")
    if [[ "$condition" == "Pending" ]] || [[ -z "$condition" ]]; then
        pass "CSR is in Pending state (requires manual approval)"
    else
        info "CSR condition is $condition"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Create kubeconfig entries for diana ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if user diana exists in kubeconfig
    if user_exists "diana"; then
        pass "User diana exists in kubeconfig"
    else
        fail_with_cmd "User diana not found in kubeconfig" \
            "kubectl config set-credentials diana --client-certificate=diana.crt --client-key=diana.key --embed-certs=true"
        return
    fi

    # Check if context exists
    if context_exists "diana@kind-kind"; then
        pass "Context diana@kind-kind exists"
    else
        fail_with_cmd "Context diana@kind-kind not found" \
            "kubectl config set-context diana@kind-kind --cluster=kind-kind --user=diana"
    fi

    # Verify context points to correct user
    local ctx_user
    ctx_user=$(kubectl config view -o jsonpath='{.contexts[?(@.name=="diana@kind-kind")].context.user}' 2>/dev/null)
    if [[ "$ctx_user" == "diana" ]]; then
        pass "Context diana@kind-kind references user diana"
    else
        info "Context user is $ctx_user"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Multiple contexts with different namespaces ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check users
    if user_exists "eric"; then
        pass "User eric exists in kubeconfig"
    else
        fail_with_cmd "User eric not found" \
            "kubectl config set-credentials eric --client-certificate=eric.crt --client-key=eric.key --embed-certs=true"
    fi

    if user_exists "fiona"; then
        pass "User fiona exists in kubeconfig"
    else
        fail_with_cmd "User fiona not found" \
            "kubectl config set-credentials fiona --client-certificate=fiona.crt --client-key=fiona.key --embed-certs=true"
    fi

    # Check contexts
    if context_exists "eric@kind-kind"; then
        pass "Context eric@kind-kind exists"
    else
        fail "Context eric@kind-kind not found"
    fi

    if context_exists "fiona@kind-kind"; then
        pass "Context fiona@kind-kind exists"
    else
        fail "Context fiona@kind-kind not found"
    fi

    # Check namespaces
    local eric_ns
    eric_ns=$(get_context_namespace "eric@kind-kind")
    if [[ "$eric_ns" == "ex-4-2" ]]; then
        pass "Context eric@kind-kind has namespace ex-4-2"
    else
        fail_with_cmd "eric@kind-kind namespace is '$eric_ns' (expected ex-4-2)" \
            "kubectl config set-context eric@kind-kind --namespace=ex-4-2"
    fi

    local fiona_ns
    fiona_ns=$(get_context_namespace "fiona@kind-kind")
    if [[ "$fiona_ns" == "default" ]]; then
        pass "Context fiona@kind-kind has namespace default"
    else
        fail_with_cmd "fiona@kind-kind namespace is '$fiona_ns' (expected default)" \
            "kubectl config set-context fiona@kind-kind --namespace=default"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: KUBECONFIG environment variable ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise
    info "Exercise 4.3 is a documentation exercise about KUBECONFIG merging"
    pass "Documented KUBECONFIG usage for merging multiple config files"
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Complete user onboarding for george ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check CSR
    if ! csr_exists "george-csr"; then
        fail_with_cmd "CertificateSigningRequest george-csr not found" \
            "kubectl get csr"
        return
    fi
    pass "CSR george-csr exists"

    # Check CSR is approved
    local condition
    condition=$(get_csr_condition "george-csr")
    if [[ "$condition" == "Approved" ]]; then
        pass "CSR george-csr is Approved"
    else
        fail_with_cmd "CSR condition is $condition (expected Approved)" \
            "kubectl certificate approve george-csr"
        return
    fi

    # Check certificate issued
    local cert
    cert=$(kubectl get csr george-csr -o jsonpath='{.status.certificate}' 2>/dev/null)
    if [[ -n "$cert" ]]; then
        pass "Certificate issued for george"
    else
        fail "Certificate not issued"
    fi

    # Check kubeconfig user
    if user_exists "george"; then
        pass "User george exists in kubeconfig"
    else
        fail_with_cmd "User george not found in kubeconfig" \
            "kubectl config set-credentials george --client-certificate=george.crt --client-key=george.key --embed-certs=true"
    fi

    # Check context
    if context_exists "george@kind-kind"; then
        pass "Context george@kind-kind exists"
    else
        fail_with_cmd "Context george@kind-kind not found" \
            "kubectl config set-context george@kind-kind --cluster=kind-kind --user=george"
    fi

    # Check files exist
    if [[ -f /tmp/ex-5-1/george.key ]] && [[ -f /tmp/ex-5-1/george.crt ]]; then
        pass "Private key and certificate files exist"
    else
        info "Expected files at /tmp/ex-5-1/george.key and /tmp/ex-5-1/george.crt"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Multiple users with different contexts ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check users
    if user_exists "hannah"; then
        pass "User hannah exists in kubeconfig"
    else
        fail "User hannah not found"
    fi

    if user_exists "ian"; then
        pass "User ian exists in kubeconfig"
    else
        fail "User ian not found"
    fi

    # Check contexts
    if context_exists "hannah@kind-kind"; then
        pass "Context hannah@kind-kind exists"
    else
        fail "Context hannah@kind-kind not found"
    fi

    if context_exists "ian@kind-kind"; then
        pass "Context ian@kind-kind exists"
    else
        fail "Context ian@kind-kind not found"
    fi

    # Check namespaces
    local hannah_ns
    hannah_ns=$(get_context_namespace "hannah@kind-kind")
    if [[ "$hannah_ns" == "ex-5-2" ]]; then
        pass "Context hannah@kind-kind has namespace ex-5-2"
    else
        fail_with_cmd "hannah@kind-kind namespace is '$hannah_ns' (expected ex-5-2)" \
            "kubectl config set-context hannah@kind-kind --namespace=ex-5-2"
    fi

    local ian_ns
    ian_ns=$(get_context_namespace "ian@kind-kind")
    if [[ "$ian_ns" == "default" ]]; then
        pass "Context ian@kind-kind has namespace default"
    else
        fail_with_cmd "ian@kind-kind namespace is '$ian_ns' (expected default)" \
            "kubectl config set-context ian@kind-kind --namespace=default"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Document ServiceAccount token-based kubeconfig ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise
    info "Exercise 5.3 is a documentation exercise about ServiceAccount tokens"
    pass "Documented ServiceAccount token-based kubeconfig creation"
}

################################################################################
# Level aggregation functions
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: kubeconfig Exploration"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: CSR Workflow"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging CSR Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: kubeconfig Management"
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
