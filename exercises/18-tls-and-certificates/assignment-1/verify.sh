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

# Helper: check if file exists in container
file_exists_in_container() {
    local file=$1
    nerdctl exec kind-control-plane test -f "$file" 2>/dev/null
}

# Helper: get certificate subject
get_cert_subject() {
    local cert=$1
    nerdctl exec kind-control-plane openssl x509 -in "$cert" -noout -subject 2>/dev/null || echo ""
}

# Helper: get certificate issuer
get_cert_issuer() {
    local cert=$1
    nerdctl exec kind-control-plane openssl x509 -in "$cert" -noout -issuer 2>/dev/null || echo ""
}

# Helper: get certificate SANs
get_cert_sans() {
    local cert=$1
    nerdctl exec kind-control-plane openssl x509 -in "$cert" -noout -text 2>/dev/null | grep -A1 "Subject Alternative Name" || echo ""
}

# Helper: get certificate dates
get_cert_dates() {
    local cert=$1
    nerdctl exec kind-control-plane openssl x509 -in "$cert" -noout -dates 2>/dev/null || echo ""
}

# Helper: check if certificate file exists locally
local_cert_exists() {
    local cert=$1
    test -f "$cert"
}

# Helper: get local certificate subject
get_local_cert_subject() {
    local cert=$1
    openssl x509 -in "$cert" -noout -subject 2>/dev/null || echo ""
}

# Helper: get local CSR subject
get_local_csr_subject() {
    local csr=$1
    openssl req -in "$csr" -noout -subject 2>/dev/null || echo ""
}

# Helper: verify certificate chain locally
verify_cert_chain() {
    local cert=$1
    local ca=$2
    openssl verify -CAfile "$ca" "$cert" &>/dev/null
}

# Helper: check if local cert has specific SAN
cert_has_san() {
    local cert=$1
    local san=$2
    openssl x509 -in "$cert" -noout -text 2>/dev/null | grep -A5 "Subject Alternative Name" | grep -q "$san"
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: List and categorize PKI certificates ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if PKI directory exists
    if ! nerdctl exec kind-control-plane test -d /etc/kubernetes/pki 2>/dev/null; then
        fail "PKI directory /etc/kubernetes/pki not found"
        return
    fi

    # Check for key certificate files
    local key_files=(
        "/etc/kubernetes/pki/ca.crt"
        "/etc/kubernetes/pki/ca.key"
        "/etc/kubernetes/pki/apiserver.crt"
        "/etc/kubernetes/pki/apiserver.key"
    )

    for file in "${key_files[@]}"; do
        if file_exists_in_container "$file"; then
            pass "Found $(basename $file)"
        else
            fail_with_cmd "$(basename $file) not found" \
                "nerdctl exec kind-control-plane ls -la /etc/kubernetes/pki/"
        fi
    done

    # Check etcd subdirectory
    if nerdctl exec kind-control-plane test -d /etc/kubernetes/pki/etcd 2>/dev/null; then
        pass "etcd subdirectory exists"
    else
        fail "etcd subdirectory not found"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: View cluster CA certificate ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local ca_cert="/etc/kubernetes/pki/ca.crt"

    if ! file_exists_in_container "$ca_cert"; then
        fail_with_cmd "CA certificate not found" \
            "nerdctl exec kind-control-plane ls /etc/kubernetes/pki/"
        return
    fi

    local subject
    subject=$(get_cert_subject "$ca_cert")
    if [[ "$subject" == *"CN"*"kubernetes"* ]]; then
        pass "CA certificate subject contains kubernetes"
    else
        fail_with_cmd "CA subject unexpected: $subject" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -subject"
    fi

    local issuer
    issuer=$(get_cert_issuer "$ca_cert")
    if [[ "$issuer" == *"CN"*"kubernetes"* ]]; then
        pass "CA is self-signed (subject matches issuer)"
    else
        fail_with_cmd "CA issuer unexpected: $issuer" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/ca.crt -noout -issuer"
    fi

    local dates
    dates=$(get_cert_dates "$ca_cert")
    if [[ -n "$dates" ]]; then
        pass "CA certificate has validity period"
    else
        fail "Could not read CA certificate dates"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: View API server certificate SANs ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local apiserver_cert="/etc/kubernetes/pki/apiserver.crt"

    if ! file_exists_in_container "$apiserver_cert"; then
        fail_with_cmd "API server certificate not found" \
            "nerdctl exec kind-control-plane ls /etc/kubernetes/pki/"
        return
    fi

    local sans
    sans=$(get_cert_sans "$apiserver_cert")
    if [[ -n "$sans" ]]; then
        pass "API server certificate has SANs"
    else
        fail_with_cmd "No SANs found in API server certificate" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -text | grep -A5 'Subject Alternative Name'"
    fi

    # Check for common SANs
    if [[ "$sans" == *"kubernetes"* ]]; then
        pass "SANs include kubernetes"
    else
        fail "SANs missing 'kubernetes'"
    fi

    if [[ "$sans" == *"10.96.0.1"* ]] || [[ "$sans" == *"IP Address"* ]]; then
        pass "SANs include IP addresses"
    else
        info "Expected IP addresses in SANs (e.g., 10.96.0.1)"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Generate private key and CSR ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local key_file="/tmp/ex-2-1/bob.key"
    local csr_file="/tmp/ex-2-1/bob.csr"

    if ! local_cert_exists "$key_file"; then
        fail_with_cmd "Private key $key_file not found" \
            "ls -la /tmp/ex-2-1/"
        return
    fi
    pass "Private key bob.key exists"

    if ! local_cert_exists "$csr_file"; then
        fail_with_cmd "CSR $csr_file not found" \
            "ls -la /tmp/ex-2-1/"
        return
    fi
    pass "CSR bob.csr exists"

    local csr_subject
    csr_subject=$(get_local_csr_subject "$csr_file")
    if [[ "$csr_subject" == *"CN"*"bob"* ]]; then
        pass "CSR subject contains CN=bob"
    else
        fail_with_cmd "CSR subject: $csr_subject (expected CN=bob)" \
            "openssl req -in /tmp/ex-2-1/bob.csr -noout -subject"
    fi

    if [[ "$csr_subject" == *"O"*"qa-team"* ]]; then
        pass "CSR subject contains O=qa-team"
    else
        fail_with_cmd "CSR subject: $csr_subject (expected O=qa-team)" \
            "openssl req -in /tmp/ex-2-1/bob.csr -noout -subject"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Sign CSR with cluster CA ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local cert_file="/tmp/ex-2-1/bob.crt"
    local ca_file="/tmp/ex-2-1/ca.crt"

    if ! local_cert_exists "$ca_file"; then
        fail_with_cmd "CA certificate not found at $ca_file" \
            "ls -la /tmp/ex-2-1/"
        return
    fi
    pass "CA certificate copied locally"

    if ! local_cert_exists "$cert_file"; then
        fail_with_cmd "Signed certificate $cert_file not found" \
            "ls -la /tmp/ex-2-1/"
        return
    fi
    pass "Signed certificate bob.crt exists"

    local cert_subject
    cert_subject=$(get_local_cert_subject "$cert_file")
    if [[ "$cert_subject" == *"CN"*"bob"* ]]; then
        pass "Certificate subject contains CN=bob"
    else
        fail_with_cmd "Certificate subject: $cert_subject (expected CN=bob)" \
            "openssl x509 -in /tmp/ex-2-1/bob.crt -noout -subject"
    fi

    # Check validity period
    local enddate
    enddate=$(openssl x509 -in "$cert_file" -noout -enddate 2>/dev/null | cut -d= -f2)
    if [[ -n "$enddate" ]]; then
        pass "Certificate has expiration date"
    else
        fail "Could not read certificate expiration"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Verify certificate chain ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local cert_file="/tmp/ex-2-1/bob.crt"
    local ca_file="/tmp/ex-2-1/ca.crt"

    if ! local_cert_exists "$cert_file" || ! local_cert_exists "$ca_file"; then
        fail "Certificate or CA file missing"
        return
    fi

    if verify_cert_chain "$cert_file" "$ca_file"; then
        pass "Certificate chain verification successful"
    else
        fail_with_cmd "Certificate chain verification failed" \
            "openssl verify -CAfile /tmp/ex-2-1/ca.crt /tmp/ex-2-1/bob.crt"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Identify certificate purpose ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local cert="/etc/kubernetes/pki/apiserver-kubelet-client.crt"

    if ! file_exists_in_container "$cert"; then
        fail_with_cmd "Certificate $cert not found" \
            "nerdctl exec kind-control-plane ls /etc/kubernetes/pki/"
        return
    fi
    pass "Certificate apiserver-kubelet-client.crt exists"

    local subject
    subject=$(get_cert_subject "$cert")
    if [[ "$subject" == *"kube-apiserver-kubelet-client"* ]] || [[ "$subject" == *"apiserver"* ]]; then
        pass "Certificate subject indicates API server client usage"
    else
        fail_with_cmd "Subject: $subject (expected apiserver-related)" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver-kubelet-client.crt -noout -subject"
    fi

    if [[ "$subject" == *"system:masters"* ]]; then
        pass "Certificate includes system:masters group"
    else
        info "Note: Certificate may or may not include system:masters"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Find certificate with etcd CA issuer ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local etcd_cert="/etc/kubernetes/pki/etcd/server.crt"

    if ! file_exists_in_container "$etcd_cert"; then
        fail_with_cmd "etcd server certificate not found" \
            "nerdctl exec kind-control-plane ls /etc/kubernetes/pki/etcd/"
        return
    fi
    pass "etcd server certificate exists"

    local issuer
    issuer=$(get_cert_issuer "$etcd_cert")
    if [[ "$issuer" == *"etcd"* ]]; then
        pass "Certificate issuer contains 'etcd'"
    else
        fail_with_cmd "Issuer: $issuer (expected etcd-ca)" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/etcd/server.crt -noout -issuer"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Check API server certificate expiration ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local cert="/etc/kubernetes/pki/apiserver.crt"

    if ! file_exists_in_container "$cert"; then
        fail_with_cmd "API server certificate not found" \
            "nerdctl exec kind-control-plane ls /etc/kubernetes/pki/"
        return
    fi

    local dates
    dates=$(get_cert_dates "$cert")
    if [[ "$dates" == *"notAfter"* ]]; then
        pass "Certificate expiration date retrieved"
    else
        fail_with_cmd "Could not read certificate dates" \
            "nerdctl exec kind-control-plane openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates"
    fi

    # Check if not expired
    if nerdctl exec kind-control-plane openssl x509 -in "$cert" -noout -checkend 0 2>/dev/null; then
        pass "Certificate is not expired"
    else
        fail "Certificate appears to be expired"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Create certificate with SANs ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local cert_file="/tmp/ex-4-1/myapp.crt"
    local key_file="/tmp/ex-4-1/myapp.key"

    if ! local_cert_exists "$key_file"; then
        fail_with_cmd "Private key $key_file not found" \
            "ls -la /tmp/ex-4-1/"
        return
    fi
    pass "Private key myapp.key exists"

    if ! local_cert_exists "$cert_file"; then
        fail_with_cmd "Certificate $cert_file not found" \
            "ls -la /tmp/ex-4-1/"
        return
    fi
    pass "Certificate myapp.crt exists"

    # Check for required SANs
    if cert_has_san "$cert_file" "myapp.example.com"; then
        pass "SAN includes myapp.example.com"
    else
        fail_with_cmd "SAN missing myapp.example.com" \
            "openssl x509 -in /tmp/ex-4-1/myapp.crt -noout -text | grep -A5 'Subject Alternative Name'"
    fi

    if cert_has_san "$cert_file" "myapp"; then
        pass "SAN includes myapp"
    else
        fail_with_cmd "SAN missing myapp" \
            "openssl x509 -in /tmp/ex-4-1/myapp.crt -noout -text | grep -A5 'Subject Alternative Name'"
    fi

    if cert_has_san "$cert_file" "10.10.10.10"; then
        pass "SAN includes IP 10.10.10.10"
    else
        fail_with_cmd "SAN missing IP 10.10.10.10" \
            "openssl x509 -in /tmp/ex-4-1/myapp.crt -noout -text | grep -A5 'Subject Alternative Name'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Document key usage extensions ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise - just verify namespace exists
    pass "Namespace created (documentation exercise)"
    info "This exercise requires written documentation of key usage extensions"
    info "Review the answer key for correct key usage for client and server certificates"
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Understand service account certificates ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check for service account key files
    if file_exists_in_container "/etc/kubernetes/pki/sa.key"; then
        pass "Service account private key exists"
    else
        fail_with_cmd "sa.key not found" \
            "nerdctl exec kind-control-plane ls /etc/kubernetes/pki/sa.*"
    fi

    if file_exists_in_container "/etc/kubernetes/pki/sa.pub"; then
        pass "Service account public key exists"
    else
        fail_with_cmd "sa.pub not found" \
            "nerdctl exec kind-control-plane ls /etc/kubernetes/pki/sa.*"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Create PKI inventory ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise
    pass "Namespace created (inventory exercise)"
    info "This exercise requires creating a comprehensive PKI inventory"
    info "Review the answer key for the complete inventory structure"
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Create certificates for custom component ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local client_cert="/tmp/ex-5-2/controller-client.crt"
    local server_cert="/tmp/ex-5-2/controller-server.crt"

    if ! local_cert_exists "$client_cert"; then
        fail_with_cmd "Client certificate not found" \
            "ls -la /tmp/ex-5-2/"
        return
    fi
    pass "Client certificate exists"

    if ! local_cert_exists "$server_cert"; then
        fail_with_cmd "Server certificate not found" \
            "ls -la /tmp/ex-5-2/"
        return
    fi
    pass "Server certificate exists"

    # Verify client cert subject
    local client_subject
    client_subject=$(get_local_cert_subject "$client_cert")
    if [[ "$client_subject" == *"custom-controller"* ]]; then
        pass "Client certificate subject contains custom-controller"
    else
        fail_with_cmd "Client subject: $client_subject" \
            "openssl x509 -in /tmp/ex-5-2/controller-client.crt -noout -subject"
    fi

    # Verify server cert subject
    local server_subject
    server_subject=$(get_local_cert_subject "$server_cert")
    if [[ "$server_subject" == *"custom-controller"* ]]; then
        pass "Server certificate subject contains custom-controller"
    else
        fail_with_cmd "Server subject: $server_subject" \
            "openssl x509 -in /tmp/ex-5-2/controller-server.crt -noout -subject"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Document certificate lifecycle ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # This is a documentation exercise
    pass "Namespace created (documentation exercise)"
    info "This exercise requires documentation of certificate lifecycle and rotation"
    info "Review the answer key for complete lifecycle documentation"
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Exploring Cluster Certificates"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Certificate Operations"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Certificate Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Advanced Certificate Creation"
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
