#!/usr/bin/env bash
#
# verify.sh - Automated verification for rbac-homework.md
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

# Helper: check if role exists
role_exists() {
    local role=$1
    local ns=$2
    kubectl get role "$role" -n "$ns" &>/dev/null
}

# Helper: check if rolebinding exists
rolebinding_exists() {
    local rb=$1
    local ns=$2
    kubectl get rolebinding "$rb" -n "$ns" &>/dev/null
}

# Helper: check if clusterrole exists
clusterrole_exists() {
    local cr=$1
    kubectl get clusterrole "$cr" &>/dev/null
}

# Helper: check permission (returns 0 if allowed, 1 if denied)
check_permission() {
    local verb=$1
    local resource=$2
    local ns=$3
    local as_args=$4
    kubectl auth can-i "$verb" "$resource" -n "$ns" $as_args &>/dev/null
}

# Helper: check serviceaccount exists
serviceaccount_exists() {
    local sa=$1
    local ns=$2
    kubectl get serviceaccount "$sa" -n "$ns" &>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: alice read-only pods ==="
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check role and rolebinding exist
    if ! role_exists "pod-reader" "$ns"; then
        fail_with_cmd "Role pod-reader not found in namespace $ns" \
            "kubectl get role -n $ns"
        return
    fi

    if ! rolebinding_exists "alice-pod-reader" "$ns"; then
        fail_with_cmd "RoleBinding alice-pod-reader not found in namespace $ns" \
            "kubectl get rolebinding -n $ns"
        return
    fi

    # Verify alice's permissions
    if check_permission "list" "pods" "$ns" "--as=alice"; then
        pass "alice can list pods in $ns"
    else
        fail_with_cmd "alice cannot list pods in $ns" \
            "kubectl auth can-i list pods -n $ns --as=alice"
    fi

    if check_permission "get" "pod/webapp" "$ns" "--as=alice"; then
        pass "alice can get pod/webapp in $ns"
    else
        fail_with_cmd "alice cannot get pod/webapp in $ns" \
            "kubectl auth can-i get pod/webapp -n $ns --as=alice"
    fi

    if ! check_permission "delete" "pods" "$ns" "--as=alice"; then
        pass "alice cannot delete pods in $ns (correct)"
    else
        fail "alice CAN delete pods in $ns (should be denied)"
    fi

    if ! check_permission "list" "pods" "default" "--as=alice"; then
        pass "alice cannot list pods in default namespace (correct)"
    else
        fail "alice CAN list pods in default namespace (should be denied)"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: bob create deployments only ==="
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if check_permission "create" "deployments" "$ns" "--as=bob"; then
        pass "bob can create deployments in $ns"
    else
        fail_with_cmd "bob cannot create deployments in $ns" \
            "kubectl auth can-i create deployments -n $ns --as=bob"
    fi

    if ! check_permission "list" "deployments" "$ns" "--as=bob"; then
        pass "bob cannot list deployments in $ns (correct)"
    else
        fail "bob CAN list deployments in $ns (should be denied)"
    fi

    if ! check_permission "delete" "deployments" "$ns" "--as=bob"; then
        pass "bob cannot delete deployments in $ns (correct)"
    else
        fail "bob CAN delete deployments in $ns (should be denied)"
    fi

    if ! check_permission "create" "pods" "$ns" "--as=bob"; then
        pass "bob cannot create pods in $ns (correct)"
    else
        fail "bob CAN create pods in $ns (should be denied)"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: carol read-only configmaps ==="
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! role_exists "cm-reader" "$ns"; then
        fail_with_cmd "Role cm-reader not found in namespace $ns" \
            "kubectl get role -n $ns"
        return
    fi

    if ! rolebinding_exists "carol-cm-reader" "$ns"; then
        fail_with_cmd "RoleBinding carol-cm-reader not found in namespace $ns" \
            "kubectl get rolebinding -n $ns"
        return
    fi

    if check_permission "list" "configmaps" "$ns" "--as=carol"; then
        pass "carol can list configmaps in $ns"
    else
        fail_with_cmd "carol cannot list configmaps in $ns" \
            "kubectl auth can-i list configmaps -n $ns --as=carol"
    fi

    if check_permission "get" "cm/app-settings" "$ns" "--as=carol"; then
        pass "carol can get cm/app-settings in $ns"
    else
        fail_with_cmd "carol cannot get cm/app-settings in $ns" \
            "kubectl auth can-i get cm/app-settings -n $ns --as=carol"
    fi

    if ! check_permission "create" "configmaps" "$ns" "--as=carol"; then
        pass "carol cannot create configmaps in $ns (correct)"
    else
        fail "carol CAN create configmaps in $ns (should be denied)"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: dave full deployments, read pods/services ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Full control over deployments
    if check_permission "create" "deployments" "$ns" "--as=dave"; then
        pass "dave can create deployments in $ns"
    else
        fail_with_cmd "dave cannot create deployments in $ns" \
            "kubectl auth can-i create deployments -n $ns --as=dave"
    fi

    if check_permission "delete" "deployments" "$ns" "--as=dave"; then
        pass "dave can delete deployments in $ns"
    else
        fail_with_cmd "dave cannot delete deployments in $ns" \
            "kubectl auth can-i delete deployments -n $ns --as=dave"
    fi

    # Read-only pods and services
    if check_permission "list" "pods" "$ns" "--as=dave"; then
        pass "dave can list pods in $ns"
    else
        fail_with_cmd "dave cannot list pods in $ns" \
            "kubectl auth can-i list pods -n $ns --as=dave"
    fi

    if check_permission "get" "svc/api" "$ns" "--as=dave"; then
        pass "dave can get svc/api in $ns"
    else
        fail_with_cmd "dave cannot get svc/api in $ns" \
            "kubectl auth can-i get svc/api -n $ns --as=dave"
    fi

    if ! check_permission "delete" "pods" "$ns" "--as=dave"; then
        pass "dave cannot delete pods in $ns (correct)"
    else
        fail "dave CAN delete pods in $ns (should be denied)"
    fi

    if ! check_permission "create" "services" "$ns" "--as=dave"; then
        pass "dave cannot create services in $ns (correct)"
    else
        fail "dave CAN create services in $ns (should be denied)"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: eve full configmaps, read secrets ==="
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Full control over configmaps
    if check_permission "create" "configmaps" "$ns" "--as=eve"; then
        pass "eve can create configmaps in $ns"
    else
        fail_with_cmd "eve cannot create configmaps in $ns" \
            "kubectl auth can-i create configmaps -n $ns --as=eve"
    fi

    if check_permission "delete" "configmaps" "$ns" "--as=eve"; then
        pass "eve can delete configmaps in $ns"
    else
        fail_with_cmd "eve cannot delete configmaps in $ns" \
            "kubectl auth can-i delete configmaps -n $ns --as=eve"
    fi

    # Read-only secrets
    if check_permission "list" "secrets" "$ns" "--as=eve"; then
        pass "eve can list secrets in $ns"
    else
        fail_with_cmd "eve cannot list secrets in $ns" \
            "kubectl auth can-i list secrets -n $ns --as=eve"
    fi

    if check_permission "get" "secret/api-key" "$ns" "--as=eve"; then
        pass "eve can get secret/api-key in $ns"
    else
        fail_with_cmd "eve cannot get secret/api-key in $ns" \
            "kubectl auth can-i get secret/api-key -n $ns --as=eve"
    fi

    if ! check_permission "create" "secrets" "$ns" "--as=eve"; then
        pass "eve cannot create secrets in $ns (correct)"
    else
        fail "eve CAN create secrets in $ns (should be denied)"
    fi

    if ! check_permission "delete" "secrets" "$ns" "--as=eve"; then
        pass "eve cannot delete secrets in $ns (correct)"
    else
        fail "eve CAN delete secrets in $ns (should be denied)"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: frank manage workloads, read pods/services ==="
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! role_exists "workload-operator" "$ns"; then
        fail_with_cmd "Role workload-operator not found in namespace $ns" \
            "kubectl get role -n $ns"
        return
    fi

    # Full control over workloads
    if check_permission "create" "deployments" "$ns" "--as=frank"; then
        pass "frank can create deployments in $ns"
    else
        fail_with_cmd "frank cannot create deployments in $ns" \
            "kubectl auth can-i create deployments -n $ns --as=frank"
    fi

    if check_permission "delete" "daemonsets" "$ns" "--as=frank"; then
        pass "frank can delete daemonsets in $ns"
    else
        fail_with_cmd "frank cannot delete daemonsets in $ns" \
            "kubectl auth can-i delete daemonsets -n $ns --as=frank"
    fi

    if check_permission "create" "replicasets" "$ns" "--as=frank"; then
        pass "frank can create replicasets in $ns"
    else
        fail_with_cmd "frank cannot create replicasets in $ns" \
            "kubectl auth can-i create replicasets -n $ns --as=frank"
    fi

    # Read-only pods and services
    if check_permission "list" "pods" "$ns" "--as=frank"; then
        pass "frank can list pods in $ns"
    else
        fail_with_cmd "frank cannot list pods in $ns" \
            "kubectl auth can-i list pods -n $ns --as=frank"
    fi

    if check_permission "get" "svc/web" "$ns" "--as=frank"; then
        pass "frank can get svc/web in $ns"
    else
        fail_with_cmd "frank cannot get svc/web in $ns" \
            "kubectl auth can-i get svc/web -n $ns --as=frank"
    fi

    if ! check_permission "delete" "pods" "$ns" "--as=frank"; then
        pass "frank cannot delete pods in $ns (correct)"
    else
        fail "frank CAN delete pods in $ns (should be denied)"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix grace deployment-reader (broken API group) ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if check_permission "list" "deployments" "$ns" "--as=grace"; then
        pass "grace can list deployments in $ns (issue fixed)"
    else
        fail_with_cmd "grace cannot list deployments in $ns" \
            "kubectl auth can-i list deployments -n $ns --as=grace; kubectl get role deployment-reader -n $ns -o yaml"
        info "Hint: Check the apiGroups field in the Role. Deployments are in 'apps', not core."
    fi

    if check_permission "get" "deployments" "$ns" "--as=grace"; then
        pass "grace can get deployments in $ns"
    else
        fail_with_cmd "grace cannot get deployments in $ns" \
            "kubectl auth can-i get deployments -n $ns --as=grace"
    fi

    if ! check_permission "delete" "deployments" "$ns" "--as=grace"; then
        pass "grace cannot delete deployments in $ns (correct)"
    else
        fail "grace CAN delete deployments in $ns (should be denied)"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix henry pod-reader (broken roleRef) ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if check_permission "list" "pods" "$ns" "--as=henry"; then
        pass "henry can list pods in $ns (issue fixed)"
    else
        fail_with_cmd "henry cannot list pods in $ns" \
            "kubectl auth can-i list pods -n $ns --as=henry; kubectl get rolebinding henry-pod-reader -n $ns -o yaml"
        info "Hint: Check that the RoleBinding's roleRef.name matches the actual Role name."
    fi

    if check_permission "get" "pod/demo" "$ns" "--as=henry"; then
        pass "henry can get pod/demo in $ns"
    else
        fail_with_cmd "henry cannot get pod/demo in $ns" \
            "kubectl auth can-i get pod/demo -n $ns --as=henry"
    fi

    if ! check_permission "delete" "pods" "$ns" "--as=henry"; then
        pass "henry cannot delete pods in $ns (correct)"
    else
        fail "henry CAN delete pods in $ns (should be denied)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix ivy service-reader (invalid verbs) ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if check_permission "list" "services" "$ns" "--as=ivy"; then
        pass "ivy can list services in $ns (issue fixed)"
    else
        fail_with_cmd "ivy cannot list services in $ns" \
            "kubectl auth can-i list services -n $ns --as=ivy; kubectl get role service-reader -n $ns -o yaml"
        info "Hint: Check the verbs field. 'read' and 'view' are not valid RBAC verbs."
    fi

    if check_permission "get" "svc/web" "$ns" "--as=ivy"; then
        pass "ivy can get svc/web in $ns"
    else
        fail_with_cmd "ivy cannot get svc/web in $ns" \
            "kubectl auth can-i get svc/web -n $ns --as=ivy"
    fi

    if ! check_permission "create" "services" "$ns" "--as=ivy"; then
        pass "ivy cannot create services in $ns (correct)"
    else
        fail "ivy CAN create services in $ns (should be denied)"
    fi

    if ! check_permission "delete" "services" "$ns" "--as=ivy"; then
        pass "ivy cannot delete services in $ns (correct)"
    else
        fail "ivy CAN delete services in $ns (should be denied)"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: jack admin in dev, read in prod ==="
    local dev_ns="ex-4-1-dev"
    local prod_ns="ex-4-1-prod"

    if ! namespace_exists "$dev_ns"; then
        fail "Namespace $dev_ns does not exist"
        return
    fi

    if ! namespace_exists "$prod_ns"; then
        fail "Namespace $prod_ns does not exist"
        return
    fi

    # Dev: full control
    if check_permission "create" "deployments" "$dev_ns" "--as=jack"; then
        pass "jack can create deployments in $dev_ns"
    else
        fail_with_cmd "jack cannot create deployments in $dev_ns" \
            "kubectl auth can-i create deployments -n $dev_ns --as=jack"
    fi

    if check_permission "delete" "pods" "$dev_ns" "--as=jack"; then
        pass "jack can delete pods in $dev_ns"
    else
        fail_with_cmd "jack cannot delete pods in $dev_ns" \
            "kubectl auth can-i delete pods -n $dev_ns --as=jack"
    fi

    if check_permission "create" "secrets" "$dev_ns" "--as=jack"; then
        pass "jack can create secrets in $dev_ns"
    else
        fail_with_cmd "jack cannot create secrets in $dev_ns" \
            "kubectl auth can-i create secrets -n $dev_ns --as=jack"
    fi

    # Prod: read-only
    if check_permission "list" "deployments" "$prod_ns" "--as=jack"; then
        pass "jack can list deployments in $prod_ns"
    else
        fail_with_cmd "jack cannot list deployments in $prod_ns" \
            "kubectl auth can-i list deployments -n $prod_ns --as=jack"
    fi

    if check_permission "get" "cm/prod-cfg" "$prod_ns" "--as=jack"; then
        pass "jack can get cm/prod-cfg in $prod_ns"
    else
        fail_with_cmd "jack cannot get cm/prod-cfg in $prod_ns" \
            "kubectl auth can-i get cm/prod-cfg -n $prod_ns --as=jack"
    fi

    if check_permission "list" "secrets" "$prod_ns" "--as=jack"; then
        pass "jack can list secrets in $prod_ns"
    else
        fail_with_cmd "jack cannot list secrets in $prod_ns" \
            "kubectl auth can-i list secrets -n $prod_ns --as=jack"
    fi

    if ! check_permission "create" "deployments" "$prod_ns" "--as=jack"; then
        pass "jack cannot create deployments in $prod_ns (correct)"
    else
        fail "jack CAN create deployments in $prod_ns (should be denied)"
    fi

    if ! check_permission "delete" "pods" "$prod_ns" "--as=jack"; then
        pass "jack cannot delete pods in $prod_ns (correct)"
    else
        fail "jack CAN delete pods in $prod_ns (should be denied)"
    fi

    if ! check_permission "update" "configmaps" "$prod_ns" "--as=jack"; then
        pass "jack cannot update configmaps in $prod_ns (correct)"
    else
        fail "jack CAN update configmaps in $prod_ns (should be denied)"
    fi

    if ! check_permission "list" "pods" "default" "--as=jack"; then
        pass "jack cannot list pods in default namespace (correct)"
    else
        fail "jack CAN list pods in default namespace (should be denied)"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: three-tier team RBAC ==="
    local frontend_ns="ex-4-2-frontend"
    local backend_ns="ex-4-2-backend"
    local data_ns="ex-4-2-data"

    # kate: frontend admin only
    if check_permission "create" "deployments" "$frontend_ns" "--as=kate"; then
        pass "kate can create deployments in $frontend_ns"
    else
        fail_with_cmd "kate cannot create deployments in $frontend_ns" \
            "kubectl auth can-i create deployments -n $frontend_ns --as=kate"
    fi

    if ! check_permission "create" "deployments" "$backend_ns" "--as=kate"; then
        pass "kate cannot create deployments in $backend_ns (correct)"
    else
        fail "kate CAN create deployments in $backend_ns (should be denied)"
    fi

    if ! check_permission "get" "services" "$data_ns" "--as=kate"; then
        pass "kate cannot get services in $data_ns (correct)"
    else
        fail "kate CAN get services in $data_ns (should be denied)"
    fi

    # liam: backend admin, frontend service read
    if check_permission "create" "deployments" "$backend_ns" "--as=liam"; then
        pass "liam can create deployments in $backend_ns"
    else
        fail_with_cmd "liam cannot create deployments in $backend_ns" \
            "kubectl auth can-i create deployments -n $backend_ns --as=liam"
    fi

    if check_permission "delete" "services" "$backend_ns" "--as=liam"; then
        pass "liam can delete services in $backend_ns"
    else
        fail_with_cmd "liam cannot delete services in $backend_ns" \
            "kubectl auth can-i delete services -n $backend_ns --as=liam"
    fi

    if check_permission "list" "services" "$frontend_ns" "--as=liam"; then
        pass "liam can list services in $frontend_ns"
    else
        fail_with_cmd "liam cannot list services in $frontend_ns" \
            "kubectl auth can-i list services -n $frontend_ns --as=liam"
    fi

    if ! check_permission "create" "deployments" "$frontend_ns" "--as=liam"; then
        pass "liam cannot create deployments in $frontend_ns (correct)"
    else
        fail "liam CAN create deployments in $frontend_ns (should be denied)"
    fi

    if ! check_permission "get" "services" "$data_ns" "--as=liam"; then
        pass "liam cannot get services in $data_ns (correct)"
    else
        fail "liam CAN get services in $data_ns (should be denied)"
    fi

    # mia: data admin only
    if check_permission "create" "deployments" "$data_ns" "--as=mia"; then
        pass "mia can create deployments in $data_ns"
    else
        fail_with_cmd "mia cannot create deployments in $data_ns" \
            "kubectl auth can-i create deployments -n $data_ns --as=mia"
    fi

    if check_permission "get" "secret/db-password" "$data_ns" "--as=mia"; then
        pass "mia can get secret/db-password in $data_ns"
    else
        fail_with_cmd "mia cannot get secret/db-password in $data_ns" \
            "kubectl auth can-i get secret/db-password -n $data_ns --as=mia"
    fi

    if ! check_permission "list" "services" "$frontend_ns" "--as=mia"; then
        pass "mia cannot list services in $frontend_ns (correct)"
    else
        fail "mia CAN list services in $frontend_ns (should be denied)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: group and serviceaccount subjects ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! serviceaccount_exists "ci-runner" "$ns"; then
        fail "ServiceAccount ci-runner not found in namespace $ns"
        return
    fi

    # Group-based: noah in auditors
    if check_permission "list" "pods" "$ns" "--as=noah --as-group=auditors"; then
        pass "noah (in auditors) can list pods in $ns"
    else
        fail_with_cmd "noah (in auditors) cannot list pods in $ns" \
            "kubectl auth can-i list pods -n $ns --as=noah --as-group=auditors"
    fi

    if check_permission "list" "deployments" "$ns" "--as=noah --as-group=auditors"; then
        pass "noah (in auditors) can list deployments in $ns"
    else
        fail_with_cmd "noah (in auditors) cannot list deployments in $ns" \
            "kubectl auth can-i list deployments -n $ns --as=noah --as-group=auditors"
    fi

    if ! check_permission "create" "pods" "$ns" "--as=noah --as-group=auditors"; then
        pass "noah (in auditors) cannot create pods in $ns (correct)"
    else
        fail "noah (in auditors) CAN create pods in $ns (should be denied)"
    fi

    # noah NOT in auditors
    if ! check_permission "list" "pods" "$ns" "--as=noah"; then
        pass "noah (not in auditors) cannot list pods in $ns (correct)"
    else
        fail "noah (not in auditors) CAN list pods in $ns (should be denied)"
    fi

    # ServiceAccount-based
    if check_permission "create" "deployments" "$ns" "--as=system:serviceaccount:$ns:ci-runner"; then
        pass "ci-runner SA can create deployments in $ns"
    else
        fail_with_cmd "ci-runner SA cannot create deployments in $ns" \
            "kubectl auth can-i create deployments -n $ns --as=system:serviceaccount:$ns:ci-runner"
    fi

    if check_permission "delete" "deployments" "$ns" "--as=system:serviceaccount:$ns:ci-runner"; then
        pass "ci-runner SA can delete deployments in $ns"
    else
        fail_with_cmd "ci-runner SA cannot delete deployments in $ns" \
            "kubectl auth can-i delete deployments -n $ns --as=system:serviceaccount:$ns:ci-runner"
    fi

    if check_permission "list" "pods" "$ns" "--as=system:serviceaccount:$ns:ci-runner"; then
        pass "ci-runner SA can list pods in $ns"
    else
        fail_with_cmd "ci-runner SA cannot list pods in $ns" \
            "kubectl auth can-i list pods -n $ns --as=system:serviceaccount:$ns:ci-runner"
    fi

    if ! check_permission "create" "configmaps" "$ns" "--as=system:serviceaccount:$ns:ci-runner"; then
        pass "ci-runner SA cannot create configmaps in $ns (correct)"
    else
        fail "ci-runner SA CAN create configmaps in $ns (should be denied)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Fix olivia app-manager (multiple issues) ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Manage deployments
    if check_permission "create" "deployments" "$ns" "--as=olivia"; then
        pass "olivia can create deployments in $ns (issue fixed)"
    else
        fail_with_cmd "olivia cannot create deployments in $ns" \
            "kubectl auth can-i create deployments -n $ns --as=olivia; kubectl get role app-manager -n $ns -o yaml"
        info "Hint: Check resource names (must be plural), apiGroups (core is ''), and subject kind (case-sensitive)."
    fi

    if check_permission "delete" "deployments" "$ns" "--as=olivia"; then
        pass "olivia can delete deployments in $ns"
    else
        fail_with_cmd "olivia cannot delete deployments in $ns" \
            "kubectl auth can-i delete deployments -n $ns --as=olivia"
    fi

    if check_permission "list" "deployments" "$ns" "--as=olivia"; then
        pass "olivia can list deployments in $ns"
    else
        fail_with_cmd "olivia cannot list deployments in $ns" \
            "kubectl auth can-i list deployments -n $ns --as=olivia"
    fi

    # Read pods
    if check_permission "list" "pods" "$ns" "--as=olivia"; then
        pass "olivia can list pods in $ns (issue fixed)"
    else
        fail_with_cmd "olivia cannot list pods in $ns" \
            "kubectl auth can-i list pods -n $ns --as=olivia; kubectl get role app-manager -n $ns -o yaml"
    fi

    if check_permission "get" "pod/helper" "$ns" "--as=olivia"; then
        pass "olivia can get pod/helper in $ns"
    else
        fail_with_cmd "olivia cannot get pod/helper in $ns" \
            "kubectl auth can-i get pod/helper -n $ns --as=olivia"
    fi

    # Should NOT be able to modify pods
    if ! check_permission "delete" "pods" "$ns" "--as=olivia"; then
        pass "olivia cannot delete pods in $ns (correct)"
    else
        fail "olivia CAN delete pods in $ns (should be denied)"
    fi

    if ! check_permission "create" "pods" "$ns" "--as=olivia"; then
        pass "olivia cannot create pods in $ns (correct)"
    else
        fail "olivia CAN create pods in $ns (should be denied)"
    fi

    if ! check_permission "list" "pods" "default" "--as=olivia"; then
        pass "olivia cannot list pods in default namespace (correct)"
    else
        fail "olivia CAN list pods in default namespace (should be denied)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: peter dev/staging/prod with resourceNames ==="
    local dev_ns="ex-5-2-dev"
    local staging_ns="ex-5-2-staging"
    local prod_ns="ex-5-2-prod"

    # Dev: full control
    if check_permission "create" "deployments" "$dev_ns" "--as=peter"; then
        pass "peter can create deployments in $dev_ns"
    else
        fail_with_cmd "peter cannot create deployments in $dev_ns" \
            "kubectl auth can-i create deployments -n $dev_ns --as=peter"
    fi

    if check_permission "delete" "pods" "$dev_ns" "--as=peter"; then
        pass "peter can delete pods in $dev_ns"
    else
        fail_with_cmd "peter cannot delete pods in $dev_ns" \
            "kubectl auth can-i delete pods -n $dev_ns --as=peter"
    fi

    # Staging: deployment admin, pod read-only
    if check_permission "create" "deployments" "$staging_ns" "--as=peter"; then
        pass "peter can create deployments in $staging_ns"
    else
        fail_with_cmd "peter cannot create deployments in $staging_ns" \
            "kubectl auth can-i create deployments -n $staging_ns --as=peter"
    fi

    if check_permission "delete" "deployments" "$staging_ns" "--as=peter"; then
        pass "peter can delete deployments in $staging_ns"
    else
        fail_with_cmd "peter cannot delete deployments in $staging_ns" \
            "kubectl auth can-i delete deployments -n $staging_ns --as=peter"
    fi

    if check_permission "list" "pods" "$staging_ns" "--as=peter"; then
        pass "peter can list pods in $staging_ns"
    else
        fail_with_cmd "peter cannot list pods in $staging_ns" \
            "kubectl auth can-i list pods -n $staging_ns --as=peter"
    fi

    if ! check_permission "delete" "pods" "$staging_ns" "--as=peter"; then
        pass "peter cannot delete pods in $staging_ns (correct)"
    else
        fail "peter CAN delete pods in $staging_ns (should be denied)"
    fi

    # Prod: scoped update of "app" only
    if check_permission "update" "deployment/app" "$prod_ns" "--as=peter"; then
        pass "peter can update deployment/app in $prod_ns"
    else
        fail_with_cmd "peter cannot update deployment/app in $prod_ns" \
            "kubectl auth can-i update deployment/app -n $prod_ns --as=peter; kubectl get role -n $prod_ns -o yaml"
        info "Hint: Use resourceNames field to restrict access to the 'app' deployment."
    fi

    if check_permission "patch" "deployment/app" "$prod_ns" "--as=peter"; then
        pass "peter can patch deployment/app in $prod_ns"
    else
        fail_with_cmd "peter cannot patch deployment/app in $prod_ns" \
            "kubectl auth can-i patch deployment/app -n $prod_ns --as=peter"
    fi

    if check_permission "get" "deployment/app" "$prod_ns" "--as=peter"; then
        pass "peter can get deployment/app in $prod_ns"
    else
        fail_with_cmd "peter cannot get deployment/app in $prod_ns" \
            "kubectl auth can-i get deployment/app -n $prod_ns --as=peter"
    fi

    if ! check_permission "update" "deployment/other-team-app" "$prod_ns" "--as=peter"; then
        pass "peter cannot update deployment/other-team-app in $prod_ns (correct)"
    else
        fail "peter CAN update deployment/other-team-app in $prod_ns (should be denied)"
    fi

    if ! check_permission "create" "deployments" "$prod_ns" "--as=peter"; then
        pass "peter cannot create deployments in $prod_ns (correct)"
    else
        fail "peter CAN create deployments in $prod_ns (should be denied)"
    fi

    if ! check_permission "delete" "deployment/app" "$prod_ns" "--as=peter"; then
        pass "peter cannot delete deployment/app in $prod_ns (correct)"
    else
        fail "peter CAN delete deployment/app in $prod_ns (should be denied)"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: three-tier with cross-namespace service visibility ==="
    local db_ns="ex-5-3-db"
    local api_ns="ex-5-3-api"
    local web_ns="ex-5-3-web"

    # quinn: db admin only
    if check_permission "create" "deployments" "$db_ns" "--as=quinn"; then
        pass "quinn can create deployments in $db_ns"
    else
        fail_with_cmd "quinn cannot create deployments in $db_ns" \
            "kubectl auth can-i create deployments -n $db_ns --as=quinn"
    fi

    if check_permission "get" "secret/db-creds" "$db_ns" "--as=quinn"; then
        pass "quinn can get secret/db-creds in $db_ns"
    else
        fail_with_cmd "quinn cannot get secret/db-creds in $db_ns" \
            "kubectl auth can-i get secret/db-creds -n $db_ns --as=quinn"
    fi

    if check_permission "delete" "services" "$db_ns" "--as=quinn"; then
        pass "quinn can delete services in $db_ns"
    else
        fail_with_cmd "quinn cannot delete services in $db_ns" \
            "kubectl auth can-i delete services -n $db_ns --as=quinn"
    fi

    if ! check_permission "list" "services" "$api_ns" "--as=quinn"; then
        pass "quinn cannot list services in $api_ns (correct)"
    else
        fail "quinn CAN list services in $api_ns (should be denied)"
    fi

    if ! check_permission "list" "services" "$web_ns" "--as=quinn"; then
        pass "quinn cannot list services in $web_ns (correct)"
    else
        fail "quinn CAN list services in $web_ns (should be denied)"
    fi

    # riley: api admin, db service read
    if check_permission "create" "deployments" "$api_ns" "--as=riley"; then
        pass "riley can create deployments in $api_ns"
    else
        fail_with_cmd "riley cannot create deployments in $api_ns" \
            "kubectl auth can-i create deployments -n $api_ns --as=riley"
    fi

    if check_permission "update" "configmaps" "$api_ns" "--as=riley"; then
        pass "riley can update configmaps in $api_ns"
    else
        fail_with_cmd "riley cannot update configmaps in $api_ns" \
            "kubectl auth can-i update configmaps -n $api_ns --as=riley"
    fi

    if check_permission "list" "services" "$db_ns" "--as=riley"; then
        pass "riley can list services in $db_ns"
    else
        fail_with_cmd "riley cannot list services in $db_ns" \
            "kubectl auth can-i list services -n $db_ns --as=riley"
    fi

    if ! check_permission "get" "secret/db-creds" "$db_ns" "--as=riley"; then
        pass "riley cannot get secret/db-creds in $db_ns (correct)"
    else
        fail "riley CAN get secret/db-creds in $db_ns (should be denied)"
    fi

    if ! check_permission "list" "deployments" "$db_ns" "--as=riley"; then
        pass "riley cannot list deployments in $db_ns (correct)"
    else
        fail "riley CAN list deployments in $db_ns (should be denied)"
    fi

    if ! check_permission "list" "services" "$web_ns" "--as=riley"; then
        pass "riley cannot list services in $web_ns (correct)"
    else
        fail "riley CAN list services in $web_ns (should be denied)"
    fi

    # sam: web admin, api service read
    if check_permission "create" "deployments" "$web_ns" "--as=sam"; then
        pass "sam can create deployments in $web_ns"
    else
        fail_with_cmd "sam cannot create deployments in $web_ns" \
            "kubectl auth can-i create deployments -n $web_ns --as=sam"
    fi

    if check_permission "delete" "configmaps" "$web_ns" "--as=sam"; then
        pass "sam can delete configmaps in $web_ns"
    else
        fail_with_cmd "sam cannot delete configmaps in $web_ns" \
            "kubectl auth can-i delete configmaps -n $web_ns --as=sam"
    fi

    if check_permission "list" "services" "$api_ns" "--as=sam"; then
        pass "sam can list services in $api_ns"
    else
        fail_with_cmd "sam cannot list services in $api_ns" \
            "kubectl auth can-i list services -n $api_ns --as=sam"
    fi

    if ! check_permission "list" "deployments" "$api_ns" "--as=sam"; then
        pass "sam cannot list deployments in $api_ns (correct)"
    else
        fail "sam CAN list deployments in $api_ns (should be denied)"
    fi

    if ! check_permission "list" "services" "$db_ns" "--as=sam"; then
        pass "sam cannot list services in $db_ns (correct)"
    else
        fail "sam CAN list services in $db_ns (should be denied)"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Single-Concept Tasks"
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
