#!/usr/bin/env bash
#
# verify.sh - Automated verification for crds-and-operators-homework.md (assignment-2)
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

# Helper: check if CRD exists
crd_exists() {
    local crd=$1
    kubectl get crd "$crd" &>/dev/null
}

# Helper: check if custom resource exists
cr_exists() {
    local resource=$1
    local name=$2
    local ns=$3
    kubectl get "$resource" "$name" -n "$ns" &>/dev/null
}

# Helper: get custom resource field value
get_cr_field() {
    local resource=$1
    local name=$2
    local ns=$3
    local jsonpath=$4
    kubectl get "$resource" "$name" -n "$ns" -o jsonpath="$jsonpath" 2>/dev/null
}

# Helper: check if Role exists
role_exists() {
    local role=$1
    local ns=$2
    kubectl get role "$role" -n "$ns" &>/dev/null
}

# Helper: check if RoleBinding exists
rolebinding_exists() {
    local rb=$1
    local ns=$2
    kubectl get rolebinding "$rb" -n "$ns" &>/dev/null
}

# Helper: check permissions with kubectl auth can-i
check_permission() {
    local verb=$1
    local resource=$2
    local ns=$3
    local as=$4
    kubectl auth can-i "$verb" "$resource" -n "$ns" --as="$as" &>/dev/null
}

# Helper: check if service account exists
sa_exists() {
    local sa=$1
    local ns=$2
    kubectl get serviceaccount "$sa" -n "$ns" &>/dev/null
}

# Helper: count resources of a type in a namespace
count_resources() {
    local resource=$1
    local ns=$2
    kubectl get "$resource" -n "$ns" --no-headers 2>/dev/null | wc -l
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Create a custom resource instance ==="
    local ns="ex-1-1"
    local cr_name="web-frontend"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cr_exists "application" "$cr_name" "$ns"; then
        fail_with_cmd "Application $cr_name not found in namespace $ns" \
            "kubectl get applications -n $ns"
        return
    fi

    local spec_name
    spec_name=$(get_cr_field "application" "$cr_name" "$ns" '{.spec.name}')
    if [[ "$spec_name" == "Frontend Service" ]]; then
        pass "spec.name is 'Frontend Service'"
    else
        fail_with_cmd "spec.name is '$spec_name' (expected 'Frontend Service')" \
            "kubectl get application $cr_name -n $ns -o jsonpath='{.spec.name}'"
    fi

    local version
    version=$(get_cr_field "application" "$cr_name" "$ns" '{.spec.version}')
    if [[ "$version" == "2.0.0" ]]; then
        pass "spec.version is '2.0.0'"
    else
        fail_with_cmd "spec.version is '$version' (expected '2.0.0')" \
            "kubectl get application $cr_name -n $ns -o jsonpath='{.spec.version}'"
    fi

    local replicas
    replicas=$(get_cr_field "application" "$cr_name" "$ns" '{.spec.replicas}')
    if [[ "$replicas" == "3" ]]; then
        pass "spec.replicas is 3"
    else
        fail_with_cmd "spec.replicas is '$replicas' (expected 3)" \
            "kubectl get application $cr_name -n $ns -o jsonpath='{.spec.replicas}'"
    fi

    local environment
    environment=$(get_cr_field "application" "$cr_name" "$ns" '{.spec.environment}')
    if [[ "$environment" == "prod" ]]; then
        pass "spec.environment is 'prod'"
    else
        fail_with_cmd "spec.environment is '$environment' (expected 'prod')" \
            "kubectl get application $cr_name -n $ns -o jsonpath='{.spec.environment}'"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: List and describe custom resources ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    local count
    count=$(count_resources "applications" "$ns")
    if [[ "$count" -eq 3 ]]; then
        pass "Three applications exist in namespace $ns"
    else
        fail_with_cmd "$count applications found (expected 3)" \
            "kubectl get applications -n $ns"
    fi

    if cr_exists "application" "api-server" "$ns"; then
        pass "Application api-server exists"
    else
        fail "Application api-server not found"
    fi

    if cr_exists "application" "worker" "$ns"; then
        pass "Application worker exists"
    else
        fail "Application worker not found"
    fi

    if cr_exists "application" "scheduler" "$ns"; then
        pass "Application scheduler exists"
    else
        fail "Application scheduler not found"
    fi

    local worker_version
    worker_version=$(get_cr_field "application" "worker" "$ns" '{.spec.version}')
    if [[ "$worker_version" == "1.2.0" ]]; then
        pass "worker version is '1.2.0'"
    else
        fail_with_cmd "worker version is '$worker_version' (expected '1.2.0')" \
            "kubectl get application worker -n $ns -o jsonpath='{.spec.version}'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Update and delete custom resources ==="
    local ns="ex-1-3"
    local cr_name="myapp"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check if resource was deleted (expected final state)
    if ! cr_exists "application" "$cr_name" "$ns"; then
        pass "Application $cr_name was deleted successfully"
    else
        # If it still exists, check if it was at least updated
        local version
        version=$(get_cr_field "application" "$cr_name" "$ns" '{.spec.version}')
        local replicas
        replicas=$(get_cr_field "application" "$cr_name" "$ns" '{.spec.replicas}')

        if [[ "$version" == "1.1.0" ]] && [[ "$replicas" == "4" ]]; then
            info "Application was updated but not deleted yet"
            fail "Application $cr_name should be deleted (current state: version=$version, replicas=$replicas)"
        else
            fail_with_cmd "Application exists but was not properly updated or deleted" \
                "kubectl get application $cr_name -n $ns -o yaml"
        fi
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Create applications in different namespaces ==="
    local ns_dev="ex-2-1-dev"
    local ns_prod="ex-2-1-prod"

    if ! namespace_exists "$ns_dev"; then
        fail "Namespace $ns_dev does not exist"
        return
    fi

    if ! namespace_exists "$ns_prod"; then
        fail "Namespace $ns_prod does not exist"
        return
    fi

    if cr_exists "application" "feature-branch" "$ns_dev"; then
        pass "Application feature-branch exists in $ns_dev"
    else
        fail_with_cmd "Application feature-branch not found in $ns_dev" \
            "kubectl get applications -n $ns_dev"
        return
    fi

    local dev_env
    dev_env=$(get_cr_field "application" "feature-branch" "$ns_dev" '{.spec.environment}')
    if [[ "$dev_env" == "dev" ]]; then
        pass "feature-branch environment is 'dev'"
    else
        fail_with_cmd "feature-branch environment is '$dev_env' (expected 'dev')" \
            "kubectl get application feature-branch -n $ns_dev -o jsonpath='{.spec.environment}'"
    fi

    if cr_exists "application" "release" "$ns_prod"; then
        pass "Application release exists in $ns_prod"
    else
        fail_with_cmd "Application release not found in $ns_prod" \
            "kubectl get applications -n $ns_prod"
        return
    fi

    local prod_env
    prod_env=$(get_cr_field "application" "release" "$ns_prod" '{.spec.environment}')
    if [[ "$prod_env" == "prod" ]]; then
        pass "release environment is 'prod'"
    else
        fail_with_cmd "release environment is '$prod_env' (expected 'prod')" \
            "kubectl get application release -n $ns_prod -o jsonpath='{.spec.environment}'"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Use kubectl api-resources to discover custom resources ==="

    # Verify CRD exists
    if ! crd_exists "applications.apps.example.com"; then
        fail "CRD applications.apps.example.com does not exist"
        return
    fi

    # Check if applications resource is registered
    if kubectl api-resources --api-group=apps.example.com | grep -q "applications"; then
        pass "applications resource is registered in API group apps.example.com"
    else
        fail_with_cmd "applications resource not found in apps.example.com API group" \
            "kubectl api-resources --api-group=apps.example.com"
    fi

    # Check short names
    local api_output
    api_output=$(kubectl api-resources --api-group=apps.example.com -o wide 2>/dev/null | grep applications || echo "")
    if echo "$api_output" | grep -q "app"; then
        pass "Short name 'app' is configured"
    else
        fail "Short name 'app' not found in api-resources output"
    fi

    if echo "$api_output" | grep -q "apps"; then
        pass "Short name 'apps' is configured"
    else
        fail "Short name 'apps' not found in api-resources output"
    fi

    # Check if namespaced
    if echo "$api_output" | grep -q "true"; then
        pass "Resource is namespaced"
    else
        fail "Resource should be namespaced"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Use short names and verify categories ==="
    local ns="ex-2-3"
    local cr_name="demo"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cr_exists "application" "$cr_name" "$ns"; then
        fail_with_cmd "Application $cr_name not found in namespace $ns" \
            "kubectl get applications -n $ns"
        return
    fi

    # Verify short name 'app' works
    if kubectl get app "$cr_name" -n "$ns" &>/dev/null; then
        pass "Short name 'app' works for listing application"
    else
        fail_with_cmd "Short name 'app' does not work" \
            "kubectl get app -n $ns"
    fi

    # Verify short name 'apps' works
    if kubectl get apps "$cr_name" -n "$ns" &>/dev/null; then
        pass "Short name 'apps' works for listing application"
    else
        fail_with_cmd "Short name 'apps' does not work" \
            "kubectl get apps -n $ns"
    fi

    # Check if appears in 'all' category
    if kubectl get all -n "$ns" 2>/dev/null | grep -q "$cr_name"; then
        pass "Application appears in 'kubectl get all'"
    else
        info "Application may not appear in 'kubectl get all' (category configuration)"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug validation failure ==="
    local ns="ex-3-1"
    local cr_name="invalid-app"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cr_exists "application" "$cr_name" "$ns"; then
        fail_with_cmd "Application $cr_name not found (fix and create it)" \
            "kubectl get applications -n $ns"
        return
    fi

    local replicas
    replicas=$(get_cr_field "application" "$cr_name" "$ns" '{.spec.replicas}')
    if [[ "$replicas" -le 10 ]]; then
        pass "replicas is $replicas (within maximum of 10)"
    else
        fail_with_cmd "replicas is $replicas (exceeds maximum of 10)" \
            "kubectl get application $cr_name -n $ns -o jsonpath='{.spec.replicas}'"
    fi

    local environment
    environment=$(get_cr_field "application" "$cr_name" "$ns" '{.spec.environment}')
    if [[ "$environment" == "dev" ]] || [[ "$environment" == "staging" ]] || [[ "$environment" == "prod" ]]; then
        pass "environment is '$environment' (valid enum value)"
    else
        fail_with_cmd "environment is '$environment' (should be dev, staging, or prod)" \
            "kubectl get application $cr_name -n $ns -o jsonpath='{.spec.environment}'"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix RBAC for service account ==="
    local ns="ex-3-2"
    local sa="app-viewer"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! sa_exists "$sa" "$ns"; then
        fail "ServiceAccount $sa does not exist in namespace $ns"
        return
    fi

    # Check read permissions
    if check_permission "list" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "app-viewer can list applications"
    else
        fail_with_cmd "app-viewer cannot list applications" \
            "kubectl auth can-i list applications -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    if check_permission "get" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "app-viewer can get applications"
    else
        fail_with_cmd "app-viewer cannot get applications" \
            "kubectl auth can-i get applications -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    # Check that delete is NOT allowed
    if ! check_permission "delete" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "app-viewer cannot delete applications (correct)"
    else
        fail "app-viewer can delete applications (should only have read access)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Find resource in correct namespace ==="
    local ns="ex-3-3"
    local cr_name="prod-api"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cr_exists "application" "$cr_name" "$ns"; then
        fail_with_cmd "Application $cr_name not found in namespace $ns" \
            "kubectl get applications --all-namespaces | grep $cr_name"
        return
    fi

    local version
    version=$(get_cr_field "application" "$cr_name" "$ns" '{.spec.version}')
    if [[ "$version" == "2.0.0" ]]; then
        pass "Found prod-api in correct namespace with version 2.0.0"
    else
        fail_with_cmd "prod-api version is '$version' (expected '2.0.0')" \
            "kubectl get application $cr_name -n $ns -o jsonpath='{.spec.version}'"
    fi

    # Verify it does not exist in default namespace
    if ! cr_exists "application" "$cr_name" "default"; then
        pass "prod-api does not exist in default namespace (correct)"
    else
        info "prod-api also exists in default namespace (unexpected)"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Create Role allowing specific verbs ==="
    local ns="ex-4-1"
    local sa="app-manager"
    local role="application-manager"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! sa_exists "$sa" "$ns"; then
        fail "ServiceAccount $sa does not exist"
        return
    fi

    if ! role_exists "$role" "$ns"; then
        fail_with_cmd "Role $role does not exist" \
            "kubectl get roles -n $ns"
        return
    fi

    # Check if RoleBinding exists
    if ! rolebinding_exists "app-manager-binding" "$ns" && ! rolebinding_exists "application-manager-binding" "$ns"; then
        fail_with_cmd "RoleBinding not found (expected name like app-manager-binding)" \
            "kubectl get rolebindings -n $ns"
        return
    fi

    # Test permissions
    if check_permission "create" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "app-manager can create applications"
    else
        fail_with_cmd "app-manager cannot create applications" \
            "kubectl auth can-i create applications -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    if check_permission "update" "applications/status" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "app-manager can update applications/status"
    else
        fail_with_cmd "app-manager cannot update applications/status" \
            "kubectl auth can-i update applications/status -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    if ! check_permission "delete" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "app-manager cannot delete applications (correct)"
    else
        fail "app-manager can delete applications (delete not granted)"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Bind role to service account and test permissions ==="
    local ns="ex-4-2"
    local sa="deployer"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! sa_exists "$sa" "$ns"; then
        fail "ServiceAccount $sa does not exist"
        return
    fi

    # Check if RoleBinding exists
    if ! rolebinding_exists "deployer-binding" "$ns"; then
        fail_with_cmd "RoleBinding deployer-binding does not exist" \
            "kubectl get rolebindings -n $ns"
        return
    fi

    # Test create permission
    if check_permission "create" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "deployer can create applications"
    else
        fail_with_cmd "deployer cannot create applications" \
            "kubectl auth can-i create applications -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    # Test update permission
    if check_permission "update" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "deployer can update applications"
    else
        fail_with_cmd "deployer cannot update applications" \
            "kubectl auth can-i update applications -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    # Test delete permission (should be denied)
    if ! check_permission "delete" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "deployer cannot delete applications (correct)"
    else
        fail "deployer can delete applications (should be denied)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Test permissions with kubectl auth can-i ==="
    local ns="ex-4-3"
    local sa="tester"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! sa_exists "$sa" "$ns"; then
        fail "ServiceAccount $sa does not exist"
        return
    fi

    # Test allowed verbs (get, list)
    if check_permission "get" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "tester can get applications"
    else
        fail_with_cmd "tester cannot get applications (should be allowed)" \
            "kubectl auth can-i get applications -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    if check_permission "list" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "tester can list applications"
    else
        fail_with_cmd "tester cannot list applications (should be allowed)" \
            "kubectl auth can-i list applications -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    # Test denied verbs (watch, create, update, patch, delete)
    if ! check_permission "watch" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "tester cannot watch applications (correct)"
    else
        fail "tester can watch applications (should be denied)"
    fi

    if ! check_permission "create" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "tester cannot create applications (correct)"
    else
        fail "tester can create applications (should be denied)"
    fi

    if ! check_permission "update" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "tester cannot update applications (correct)"
    else
        fail "tester can update applications (should be denied)"
    fi

    if ! check_permission "delete" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "tester cannot delete applications (correct)"
    else
        fail "tester can delete applications (should be denied)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Set up multi-user access ==="
    local ns="ex-5-1"
    local sa_dev="developer"
    local sa_op="operator"
    local sa_admin="admin"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Developer permissions (read-only)
    if check_permission "list" "applications" "$ns" "system:serviceaccount:$ns:$sa_dev"; then
        pass "developer can list applications"
    else
        fail_with_cmd "developer cannot list applications" \
            "kubectl auth can-i list applications -n $ns --as=system:serviceaccount:$ns:$sa_dev"
    fi

    if ! check_permission "create" "applications" "$ns" "system:serviceaccount:$ns:$sa_dev"; then
        pass "developer cannot create applications (correct)"
    else
        fail "developer can create applications (should be read-only)"
    fi

    # Operator permissions (create, update but not delete)
    if check_permission "create" "applications" "$ns" "system:serviceaccount:$ns:$sa_op"; then
        pass "operator can create applications"
    else
        fail_with_cmd "operator cannot create applications" \
            "kubectl auth can-i create applications -n $ns --as=system:serviceaccount:$ns:$sa_op"
    fi

    if ! check_permission "delete" "applications" "$ns" "system:serviceaccount:$ns:$sa_op"; then
        pass "operator cannot delete applications (correct)"
    else
        fail "operator can delete applications (should not have delete permission)"
    fi

    # Admin permissions (all verbs including delete)
    if check_permission "delete" "applications" "$ns" "system:serviceaccount:$ns:$sa_admin"; then
        pass "admin can delete applications"
    else
        fail_with_cmd "admin cannot delete applications" \
            "kubectl auth can-i delete applications -n $ns --as=system:serviceaccount:$ns:$sa_admin"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Debug permission denied ==="
    local ns="ex-5-2"
    local sa="broken-sa"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! sa_exists "$sa" "$ns"; then
        fail "ServiceAccount $sa does not exist"
        return
    fi

    # After fix, these should work
    if check_permission "get" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "broken-sa can get applications (issue fixed)"
    else
        fail_with_cmd "broken-sa cannot get applications (check Role apiGroups and resources)" \
            "kubectl get role broken-role -n $ns -o yaml"
    fi

    if check_permission "create" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "broken-sa can create applications (issue fixed)"
    else
        fail_with_cmd "broken-sa cannot create applications (check Role configuration)" \
            "kubectl get role broken-role -n $ns -o yaml"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Design RBAC strategy for controller ==="
    local ns="ex-5-3"
    local sa="controller"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! sa_exists "$sa" "$ns"; then
        fail "ServiceAccount $sa does not exist"
        return
    fi

    # Controller should be able to watch applications
    if check_permission "watch" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "controller can watch applications"
    else
        fail_with_cmd "controller cannot watch applications" \
            "kubectl auth can-i watch applications -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    # Controller should be able to update status
    if check_permission "update" "applications/status" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "controller can update applications/status"
    else
        fail_with_cmd "controller cannot update applications/status" \
            "kubectl auth can-i update applications/status -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    # Controller should NOT be able to update main resource (spec)
    if ! check_permission "update" "applications" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "controller cannot update applications (correct - only status)"
    else
        fail "controller can update applications (should only update status, not spec)"
    fi

    # Controller should be able to create events
    if check_permission "create" "events" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "controller can create events"
    else
        fail_with_cmd "controller cannot create events" \
            "kubectl auth can-i create events -n $ns --as=system:serviceaccount:$ns:$sa"
    fi

    # Controller should be able to get configmaps
    if check_permission "get" "configmaps" "$ns" "system:serviceaccount:$ns:$sa"; then
        pass "controller can get configmaps"
    else
        fail_with_cmd "controller cannot get configmaps" \
            "kubectl auth can-i get configmaps -n $ns --as=system:serviceaccount:$ns:$sa"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic Custom Resource Operations"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Namespacing and Discovery"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Custom Resource Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: RBAC for Custom Resources"
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
