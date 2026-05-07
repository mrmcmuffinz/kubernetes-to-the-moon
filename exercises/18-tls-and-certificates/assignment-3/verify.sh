#!/usr/bin/env bash
#
# verify.sh - Automated verification for tls-and-certificates-homework.md
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

# Helper: check if command runs successfully
command_succeeds() {
    eval "$1" &>/dev/null
}

# Helper: check if file exists in kind container
file_exists_in_kind() {
    local file=$1
    nerdctl exec kind-control-plane test -f "$file" 2>/dev/null
}

# Helper: check if directory exists
dir_exists() {
    test -d "$1" 2>/dev/null
}

# Helper: check if file exists locally
file_exists() {
    test -f "$1" 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Check expiration dates for all cluster certificates ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if kubeadm certs check-expiration runs successfully
    if command_succeeds "nerdctl exec kind-control-plane kubeadm certs check-expiration"; then
        pass "kubeadm certs check-expiration command executed successfully"
    else
        fail_with_cmd "kubeadm certs check-expiration failed" \
            "nerdctl exec kind-control-plane kubeadm certs check-expiration"
    fi

    # Verify it shows key certificates
    if nerdctl exec kind-control-plane kubeadm certs check-expiration 2>/dev/null | grep -q "apiserver"; then
        pass "Output includes apiserver certificate"
    else
        fail "Output does not include expected certificates"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Identify certificates expiring within 30 days ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if certificates can be examined
    if nerdctl exec kind-control-plane /bin/bash -c 'for cert in /etc/kubernetes/pki/*.crt; do openssl x509 -in $cert -noout -enddate 2>/dev/null && break; done' &>/dev/null; then
        pass "Can examine certificate expiration dates"
    else
        fail_with_cmd "Unable to examine certificates" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate"
    fi

    # Verify certificates are accessible
    if file_exists_in_kind "/etc/kubernetes/pki/apiserver.crt"; then
        pass "Certificates are accessible in /etc/kubernetes/pki/"
    else
        fail "Certificates not found"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Verify the certificate chain for a component ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Verify API server certificate against cluster CA
    if command_succeeds "nerdctl exec kind-control-plane openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apiserver.crt"; then
        pass "API server certificate verified against cluster CA"
    else
        fail_with_cmd "API server certificate verification failed" \
            "nerdctl exec kind-control-plane openssl verify -CAfile /etc/kubernetes/pki/ca.crt /etc/kubernetes/pki/apiserver.crt"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Identify the CA that signed a given certificate ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if etcd server certificate exists
    if file_exists_in_kind "/etc/kubernetes/pki/etcd/server.crt"; then
        pass "etcd server certificate found"
    else
        fail "etcd server certificate not found"
        return
    fi

    # Verify issuer can be extracted
    if nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -issuer 2>/dev/null | grep -q "CN"; then
        pass "Can extract issuer from etcd server certificate"
    else
        fail_with_cmd "Unable to extract issuer" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -issuer"
    fi

    # Verify it shows etcd-ca
    if nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -issuer 2>/dev/null | grep -q "etcd-ca"; then
        pass "etcd server certificate signed by etcd-ca (not kubernetes CA)"
    else
        info "Note: etcd certificates should be signed by etcd CA, not cluster CA"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Verify a certificate is valid for a specific hostname ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if API server certificate contains kubernetes.default.svc SAN
    if nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text 2>/dev/null | grep -q "kubernetes.default.svc"; then
        pass "API server certificate contains kubernetes.default.svc SAN"
    else
        fail_with_cmd "API server certificate does not contain expected SAN" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A1 'Subject Alternative Name'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Check file permissions on certificate files ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if permissions can be listed
    if command_succeeds "nerdctl exec kind-control-plane ls -la /etc/kubernetes/pki/*.key"; then
        pass "Can list permissions on certificate files"
    else
        fail_with_cmd "Unable to list certificate file permissions" \
            "nerdctl exec kind-control-plane ls -la /etc/kubernetes/pki/"
    fi

    # Verify key files have restrictive permissions
    local key_perms
    key_perms=$(nerdctl exec kind-control-plane ls -la /etc/kubernetes/pki/apiserver.key 2>/dev/null | awk '{print $1}')
    if [[ "$key_perms" == *"------"* ]] || [[ "$key_perms" == "-rw-------"* ]]; then
        pass "Key files have restrictive permissions (600)"
    else
        info "Key files should have 600 permissions (readable only by owner)"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Diagnose certificate expiration ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if test directory exists
    if dir_exists "/tmp/ex-3-1"; then
        pass "Test directory /tmp/ex-3-1 exists"
    else
        fail "Test directory /tmp/ex-3-1 not found"
        return
    fi

    # Check if expired certificate was created
    if file_exists "/tmp/ex-3-1/expired.crt"; then
        pass "expired.crt file created"
    else
        fail_with_cmd "expired.crt not found" \
            "cd /tmp/ex-3-1 && ls -la"
        return
    fi

    # Verify expiration dates can be checked
    if openssl x509 -in /tmp/ex-3-1/expired.crt -noout -dates 2>/dev/null | grep -q "notAfter"; then
        pass "Can examine certificate expiration dates"
    else
        fail_with_cmd "Unable to examine certificate dates" \
            "openssl x509 -in /tmp/ex-3-1/expired.crt -noout -dates"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Diagnose certificate signed by wrong CA ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if test directory exists
    if dir_exists "/tmp/ex-3-2"; then
        pass "Test directory /tmp/ex-3-2 exists"
    else
        fail "Test directory /tmp/ex-3-2 not found"
        return
    fi

    # Check if test files were created
    if file_exists "/tmp/ex-3-2/ca1.crt" && file_exists "/tmp/ex-3-2/ca2.crt" && file_exists "/tmp/ex-3-2/test.crt"; then
        pass "Test certificates created (ca1.crt, ca2.crt, test.crt)"
    else
        fail_with_cmd "Test certificates not found" \
            "cd /tmp/ex-3-2 && ls -la"
        return
    fi

    # Verify verification against wrong CA fails
    if ! openssl verify -CAfile /tmp/ex-3-2/ca2.crt /tmp/ex-3-2/test.crt &>/dev/null; then
        pass "Verification against wrong CA (ca2) correctly fails"
    else
        fail "Verification should fail when using wrong CA"
    fi

    # Verify verification against correct CA succeeds
    if openssl verify -CAfile /tmp/ex-3-2/ca1.crt /tmp/ex-3-2/test.crt &>/dev/null; then
        pass "Verification against correct CA (ca1) succeeds"
    else
        fail_with_cmd "Verification against correct CA failed" \
            "openssl verify -CAfile /tmp/ex-3-2/ca1.crt /tmp/ex-3-2/test.crt"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Diagnose a missing SAN issue ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if test directory exists
    if dir_exists "/tmp/ex-3-3"; then
        pass "Test directory /tmp/ex-3-3 exists"
    else
        fail "Test directory /tmp/ex-3-3 not found"
        return
    fi

    # Check if noSAN certificate was created
    if file_exists "/tmp/ex-3-3/noSAN.crt"; then
        pass "noSAN.crt file created"
    else
        fail_with_cmd "noSAN.crt not found" \
            "cd /tmp/ex-3-3 && ls -la"
        return
    fi

    # Verify certificate has no SANs
    if ! openssl x509 -in /tmp/ex-3-3/noSAN.crt -noout -text 2>/dev/null | grep -q "Subject Alternative Name"; then
        pass "Certificate correctly has no SANs (this is the issue to diagnose)"
    else
        fail "Certificate should not have SANs for this exercise"
    fi

    # Verify basic certificate info can be extracted
    if openssl x509 -in /tmp/ex-3-3/noSAN.crt -noout -subject 2>/dev/null | grep -q "CN"; then
        pass "Can extract subject information from certificate"
    else
        fail_with_cmd "Unable to extract certificate information" \
            "openssl x509 -in /tmp/ex-3-3/noSAN.crt -noout -text"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Document the user certificate renewal process ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise, check that namespace exists and user understands the process
    pass "Namespace ex-4-1 created (documentation exercise)"
    info "User certificate renewal steps: 1) Generate new key/CSR, 2) Submit CSR, 3) Approve, 4) Extract cert, 5) Update kubeconfig"
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Document the kubeadm certificate renewal process ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise
    pass "Namespace ex-4-2 created (documentation exercise)"
    info "kubeadm renewal: 1) kubeadm certs check-expiration, 2) kubeadm certs renew all, 3) restart control plane"
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Update kubeconfig after certificate renewal ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise
    pass "Namespace ex-4-3 created (documentation exercise)"
    info "kubeconfig update: kubectl config set-credentials <user> --client-certificate=new.crt --client-key=new.key --embed-certs=true"
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Create a full cluster certificate audit ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Verify we can run audit commands
    if command_succeeds "nerdctl exec kind-control-plane /bin/bash -c 'for cert in /etc/kubernetes/pki/*.crt; do openssl x509 -in \$cert -noout -subject 2>/dev/null && break; done'"; then
        pass "Can audit cluster certificates"
    else
        fail_with_cmd "Unable to audit certificates" \
            "nerdctl exec kind-control-plane ls -la /etc/kubernetes/pki/"
    fi

    # Verify etcd certificates are accessible
    if file_exists_in_kind "/etc/kubernetes/pki/etcd/ca.crt"; then
        pass "etcd certificates are accessible for audit"
    else
        fail "etcd certificates not found"
    fi

    # Verify we can extract all required fields
    local sample_cert="/etc/kubernetes/pki/apiserver.crt"
    if nerdctl exec kind-control-plane openssl x509 -in "$sample_cert" -noout -subject -issuer -enddate 2>/dev/null | grep -q "subject"; then
        pass "Can extract subject, issuer, and expiration date from certificates"
    else
        fail_with_cmd "Unable to extract certificate information" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -subject -issuer -enddate"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Diagnose a multi-certificate failure scenario ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise about diagnostic approach
    pass "Namespace ex-5-2 created (documentation exercise)"
    info "Diagnostic steps: 1) kubeadm certs check-expiration, 2) Check API server logs, 3) Verify certs against CA, 4) Check kubelet logs, 5) Check etcd logs"
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Create a certificate monitoring strategy ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise about monitoring strategy
    pass "Namespace ex-5-3 created (documentation exercise)"
    info "Monitoring strategy: 1) Regular expiration checks (daily cron), 2) Alert at <30 days, 3) Automated renewal or runbook, 4) Post-renewal verification"
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Certificate Health Checks"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Diagnosing Issues"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Broken Certificates"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Certificate Renewal"
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
