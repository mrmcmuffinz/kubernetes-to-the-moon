#!/usr/bin/env bash
#
# verify.sh - Automated verification for rbac-homework.md (Assignment 2: Cluster-Scoped RBAC)
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

# Helper: check if ClusterRole exists
clusterrole_exists() {
    kubectl get clusterrole "$1" &>/dev/null
}

# Helper: check if ClusterRoleBinding exists
clusterrolebinding_exists() {
    kubectl get clusterrolebinding "$1" &>/dev/null
}

# Helper: check permission for a user
check_permission() {
    local verb=$1
    local resource=$2
    local user=$3
    local ns=${4:-}

    if [[ -n "$ns" ]]; then
        kubectl auth can-i "$verb" "$resource" -n "$ns" --as="$user" &>/dev/null
    else
        kubectl auth can-i "$verb" "$resource" --as="$user" &>/dev/null
    fi
}

# Helper: check permission for a ServiceAccount
check_sa_permission() {
    local verb=$1
    local resource=$2
    local sa_name=$3
    local sa_ns=$4

    kubectl auth can-i "$verb" "$resource" --as="system:serviceaccount:${sa_ns}:${sa_name}" &>/dev/null
}

# Helper: check non-resource URL permission
check_nonresource_permission() {
    local url=$1
    local user=$2

    kubectl auth can-i get "$url" --as="$user" &>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Node viewer ClusterRole ==="
    local user="alice"
    local clusterrole="node-viewer"
    local binding="alice-node-viewer"

    if ! clusterrole_exists "$clusterrole"; then
        fail_with_cmd "ClusterRole $clusterrole not found" \
            "kubectl get clusterrole $clusterrole"
        return
    fi

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    if check_permission list nodes "$user"; then
        pass "alice can list nodes"
    else
        fail_with_cmd "alice cannot list nodes" \
            "kubectl auth can-i list nodes --as=$user"
    fi

    if check_permission get nodes/kind-control-plane "$user"; then
        pass "alice can get specific node"
    else
        fail_with_cmd "alice cannot get specific node" \
            "kubectl auth can-i get nodes/kind-control-plane --as=$user"
    fi

    if check_permission watch nodes "$user"; then
        pass "alice can watch nodes"
    else
        fail_with_cmd "alice cannot watch nodes" \
            "kubectl auth can-i watch nodes --as=$user"
    fi

    if ! check_permission delete nodes "$user"; then
        pass "alice cannot delete nodes (correct)"
    else
        fail "alice can delete nodes (should not be allowed)"
    fi

    if ! check_permission list pods "$user"; then
        pass "alice cannot list pods (correct)"
    else
        fail "alice can list pods (should not be allowed)"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Namespace lifecycle manager ==="
    local user="bob"
    local clusterrole="namespace-lifecycle"
    local binding="bob-namespace-lifecycle"

    if ! clusterrole_exists "$clusterrole"; then
        fail_with_cmd "ClusterRole $clusterrole not found" \
            "kubectl get clusterrole $clusterrole"
        return
    fi

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    if check_permission create namespaces "$user"; then
        pass "bob can create namespaces"
    else
        fail_with_cmd "bob cannot create namespaces" \
            "kubectl auth can-i create namespaces --as=$user"
    fi

    if check_permission delete namespaces "$user"; then
        pass "bob can delete namespaces"
    else
        fail_with_cmd "bob cannot delete namespaces" \
            "kubectl auth can-i delete namespaces --as=$user"
    fi

    if check_permission list namespaces "$user"; then
        pass "bob can list namespaces"
    else
        fail_with_cmd "bob cannot list namespaces" \
            "kubectl auth can-i list namespaces --as=$user"
    fi

    if ! check_permission update namespaces "$user"; then
        pass "bob cannot update namespaces (correct)"
    else
        fail "bob can update namespaces (should not be allowed)"
    fi

    if ! check_permission list pods "$user"; then
        pass "bob cannot list pods (correct)"
    else
        fail "bob can list pods (should not be allowed)"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Built-in view ClusterRole ==="
    local user="charlie"
    local binding="charlie-view"

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    if check_permission list pods "$user"; then
        pass "charlie can list pods cluster-wide"
    else
        fail_with_cmd "charlie cannot list pods cluster-wide" \
            "kubectl auth can-i list pods --all-namespaces --as=$user"
    fi

    if check_permission list services "$user"; then
        pass "charlie can list services cluster-wide"
    else
        fail_with_cmd "charlie cannot list services cluster-wide" \
            "kubectl auth can-i list services --all-namespaces --as=$user"
    fi

    if check_permission get deployments.apps "$user"; then
        pass "charlie can get deployments cluster-wide"
    else
        fail_with_cmd "charlie cannot get deployments cluster-wide" \
            "kubectl auth can-i get deployments.apps --all-namespaces --as=$user"
    fi

    if ! check_permission list secrets "$user"; then
        pass "charlie cannot list secrets (correct)"
    else
        fail "charlie can list secrets (should not be allowed)"
    fi

    if ! check_permission create pods "$user" "ex-1-3"; then
        pass "charlie cannot create pods (correct)"
    else
        fail "charlie can create pods (should not be allowed)"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: PersistentVolume manager ==="
    local user="diana"
    local clusterrole="pv-manager"
    local binding="diana-pv-manager"

    if ! clusterrole_exists "$clusterrole"; then
        fail_with_cmd "ClusterRole $clusterrole not found" \
            "kubectl get clusterrole $clusterrole"
        return
    fi

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    if check_permission list pv "$user"; then
        pass "diana can list PVs"
    else
        fail_with_cmd "diana cannot list PVs" \
            "kubectl auth can-i list pv --as=$user"
    fi

    if check_permission get pv/homework-pv "$user"; then
        pass "diana can get specific PV"
    else
        fail_with_cmd "diana cannot get specific PV" \
            "kubectl auth can-i get pv/homework-pv --as=$user"
    fi

    if check_permission delete pv "$user"; then
        pass "diana can delete PVs"
    else
        fail_with_cmd "diana cannot delete PVs" \
            "kubectl auth can-i delete pv --as=$user"
    fi

    if check_permission create pv "$user"; then
        pass "diana can create PVs"
    else
        fail_with_cmd "diana cannot create PVs" \
            "kubectl auth can-i create pv --as=$user"
    fi

    if ! check_permission list persistentvolumeclaims "$user"; then
        pass "diana cannot list PVCs (correct)"
    else
        fail "diana can list PVCs (should not be allowed)"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: StorageClass admin ==="
    local user="eric"
    local clusterrole="storageclass-admin"
    local binding="eric-storageclass-admin"

    if ! clusterrole_exists "$clusterrole"; then
        fail_with_cmd "ClusterRole $clusterrole not found" \
            "kubectl get clusterrole $clusterrole"
        return
    fi

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    if check_permission list storageclasses "$user"; then
        pass "eric can list storageclasses"
    else
        fail_with_cmd "eric cannot list storageclasses" \
            "kubectl auth can-i list storageclasses --as=$user"
    fi

    if check_permission create storageclasses "$user"; then
        pass "eric can create storageclasses"
    else
        fail_with_cmd "eric cannot create storageclasses" \
            "kubectl auth can-i create storageclasses --as=$user"
    fi

    if check_permission delete storageclasses "$user"; then
        pass "eric can delete storageclasses"
    else
        fail_with_cmd "eric cannot delete storageclasses" \
            "kubectl auth can-i delete storageclasses --as=$user"
    fi

    if check_permission get storageclasses/standard "$user"; then
        pass "eric can get specific storageclass"
    else
        fail_with_cmd "eric cannot get specific storageclass" \
            "kubectl auth can-i get storageclasses/standard --as=$user"
    fi

    if ! check_permission list pv "$user"; then
        pass "eric cannot list PVs (correct)"
    else
        fail "eric can list PVs (should not be allowed)"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: PriorityClass viewer ==="
    local user="fiona"
    local clusterrole="priorityclass-viewer"
    local binding="fiona-priorityclass-viewer"

    if ! clusterrole_exists "$clusterrole"; then
        fail_with_cmd "ClusterRole $clusterrole not found" \
            "kubectl get clusterrole $clusterrole"
        return
    fi

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    if check_permission list priorityclasses "$user"; then
        pass "fiona can list priorityclasses"
    else
        fail_with_cmd "fiona cannot list priorityclasses" \
            "kubectl auth can-i list priorityclasses --as=$user"
    fi

    if check_permission get priorityclass/system-cluster-critical "$user"; then
        pass "fiona can get specific priorityclass"
    else
        fail_with_cmd "fiona cannot get specific priorityclass" \
            "kubectl auth can-i get priorityclass/system-cluster-critical --as=$user"
    fi

    if ! check_permission create priorityclasses "$user"; then
        pass "fiona cannot create priorityclasses (correct)"
    else
        fail "fiona can create priorityclasses (should not be allowed)"
    fi

    if ! check_permission list storageclasses "$user"; then
        pass "fiona cannot list storageclasses (correct)"
    else
        fail "fiona can list storageclasses (should not be allowed)"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug StorageClass API group ==="
    local user="george"

    if check_permission list storageclasses "$user"; then
        pass "george can list storageclasses (issue fixed)"
    else
        fail_with_cmd "george cannot list storageclasses" \
            "kubectl auth can-i list storageclasses --as=$user; kubectl get clusterrole ex-3-1-storageclass-reader -o yaml"
    fi

    if check_permission get storageclasses/standard "$user"; then
        pass "george can get specific storageclass"
    else
        fail_with_cmd "george cannot get specific storageclass" \
            "kubectl auth can-i get storageclasses/standard --as=$user"
    fi

    if ! check_permission create storageclasses "$user"; then
        pass "george cannot create storageclasses (correct)"
    else
        fail "george can create storageclasses (should not be allowed)"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug binding scope for cluster-scoped resource ==="
    local user="hannah"

    if check_permission list nodes "$user"; then
        pass "hannah can list nodes (issue fixed)"
    else
        fail_with_cmd "hannah cannot list nodes" \
            "kubectl auth can-i list nodes --as=$user; kubectl get rolebindings -A -o json | jq -r '.items[] | select(.subjects[]?.name==\"hannah\")'; kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.subjects[]?.name==\"hannah\")'"
    fi

    if check_permission get nodes/kind-control-plane "$user"; then
        pass "hannah can get specific node"
    else
        fail_with_cmd "hannah cannot get specific node" \
            "kubectl auth can-i get nodes/kind-control-plane --as=$user"
    fi

    if ! check_permission delete nodes "$user"; then
        pass "hannah cannot delete nodes (correct)"
    else
        fail "hannah can delete nodes (should not be allowed)"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug non-resource URL binding ==="
    local user="ian"

    if check_nonresource_permission "/healthz" "$user"; then
        pass "ian can access /healthz (issue fixed)"
    else
        fail_with_cmd "ian cannot access /healthz" \
            "kubectl auth can-i get /healthz --as=$user; kubectl get rolebindings -A -o json | jq -r '.items[] | select(.subjects[]?.name==\"ian\")'; kubectl get clusterrolebindings -o json | jq -r '.items[] | select(.subjects[]?.name==\"ian\")'"
    fi

    if check_nonresource_permission "/healthz/etcd" "$user"; then
        pass "ian can access /healthz/etcd"
    else
        fail_with_cmd "ian cannot access /healthz/etcd" \
            "kubectl auth can-i get /healthz/etcd --as=$user"
    fi

    if ! check_nonresource_permission "/metrics" "$user"; then
        pass "ian cannot access /metrics (correct)"
    else
        fail "ian can access /metrics (should not be allowed)"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: ClusterRole with RoleBinding pattern ==="
    local user="karl"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check karl has edit permissions in ex-4-1
    if check_permission create deployments "$user" "$ns"; then
        pass "karl can create deployments in $ns"
    else
        fail_with_cmd "karl cannot create deployments in $ns" \
            "kubectl auth can-i create deployments -n $ns --as=$user; kubectl -n $ns get rolebinding karl-edit -o yaml"
    fi

    if check_permission delete pods "$user" "$ns"; then
        pass "karl can delete pods in $ns"
    else
        fail_with_cmd "karl cannot delete pods in $ns" \
            "kubectl auth can-i delete pods -n $ns --as=$user"
    fi

    if check_permission update configmaps "$user" "$ns"; then
        pass "karl can update configmaps in $ns"
    else
        fail_with_cmd "karl cannot update configmaps in $ns" \
            "kubectl auth can-i update configmaps -n $ns --as=$user"
    fi

    if check_permission get secrets "$user" "$ns"; then
        pass "karl can get secrets in $ns (edit allows this)"
    else
        fail_with_cmd "karl cannot get secrets in $ns" \
            "kubectl auth can-i get secrets -n $ns --as=$user"
    fi

    # Verify scoped to ex-4-1 only
    if ! check_permission create deployments "$user" "ex-4-2"; then
        pass "karl cannot create deployments in ex-4-2 (correct)"
    else
        fail "karl can create deployments in ex-4-2 (should be scoped to ex-4-1 only)"
    fi

    if ! check_permission list pods "$user" "default"; then
        pass "karl cannot list pods in default (correct)"
    else
        fail "karl can list pods in default (should be scoped to ex-4-1 only)"
    fi

    if ! check_permission list nodes "$user"; then
        pass "karl cannot list nodes (correct)"
    else
        fail "karl can list nodes (should have no cluster-scoped access)"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: ClusterRole aggregation ==="
    local user="luna"
    local binding="luna-view"

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    # Check that view ClusterRole has been extended with storageclasses
    if kubectl get clusterrole view -o yaml | grep -q storageclasses; then
        pass "view ClusterRole aggregated storageclasses rule"
    else
        fail_with_cmd "view ClusterRole missing storageclasses rule" \
            "kubectl get clusterrole view -o yaml | grep -E '^\s+- storageclasses'; kubectl get clusterrole view-storageclasses -o yaml"
    fi

    if check_permission list storageclasses "$user"; then
        pass "luna can list storageclasses (aggregated permission)"
    else
        fail_with_cmd "luna cannot list storageclasses" \
            "kubectl auth can-i list storageclasses --as=$user"
    fi

    if check_permission list pods "$user"; then
        pass "luna can list pods (view default permission)"
    else
        fail_with_cmd "luna cannot list pods" \
            "kubectl auth can-i list pods --all-namespaces --as=$user"
    fi

    if ! check_permission list secrets "$user"; then
        pass "luna cannot list secrets (correct, view excludes secrets)"
    else
        fail "luna can list secrets (view should exclude secrets)"
    fi

    if ! check_permission create storageclasses "$user"; then
        pass "luna cannot create storageclasses (correct)"
    else
        fail "luna can create storageclasses (should be read-only)"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: ServiceAccount with ClusterRoleBinding ==="
    local sa_name="metric-scraper"
    local sa_ns="ex-4-3"
    local binding="metric-scraper-view"

    if ! namespace_exists "$sa_ns"; then
        fail "Namespace $sa_ns does not exist"
        return
    fi

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    if check_sa_permission list pods "$sa_name" "$sa_ns"; then
        pass "metric-scraper can list pods cluster-wide"
    else
        fail_with_cmd "metric-scraper cannot list pods cluster-wide" \
            "kubectl auth can-i list pods --all-namespaces --as=system:serviceaccount:$sa_ns:$sa_name; kubectl get clusterrolebinding $binding -o yaml"
    fi

    if check_sa_permission list services "$sa_name" "$sa_ns"; then
        pass "metric-scraper can list services cluster-wide"
    else
        fail_with_cmd "metric-scraper cannot list services cluster-wide" \
            "kubectl auth can-i list services --all-namespaces --as=system:serviceaccount:$sa_ns:$sa_name"
    fi

    if check_sa_permission list deployments.apps "$sa_name" "$sa_ns"; then
        pass "metric-scraper can list deployments cluster-wide"
    else
        fail_with_cmd "metric-scraper cannot list deployments cluster-wide" \
            "kubectl auth can-i list deployments.apps --all-namespaces --as=system:serviceaccount:$sa_ns:$sa_name"
    fi

    if ! check_sa_permission list secrets "$sa_name" "$sa_ns"; then
        pass "metric-scraper cannot list secrets (correct)"
    else
        fail "metric-scraper can list secrets (view should exclude secrets)"
    fi

    if ! kubectl auth can-i create pods -n "$sa_ns" --as="system:serviceaccount:$sa_ns:$sa_name" &>/dev/null; then
        pass "metric-scraper cannot create pods (correct)"
    else
        fail "metric-scraper can create pods (should be read-only)"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Design cluster-operator role ==="
    local user="nina"
    local clusterrole="cluster-operator"
    local binding="nina-cluster-operator"

    if ! clusterrole_exists "$clusterrole"; then
        fail_with_cmd "ClusterRole $clusterrole not found" \
            "kubectl get clusterrole $clusterrole"
        return
    fi

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    if check_permission list nodes "$user"; then
        pass "nina can list nodes"
    else
        fail_with_cmd "nina cannot list nodes" \
            "kubectl auth can-i list nodes --as=$user; kubectl get clusterrole $clusterrole -o yaml"
    fi

    if check_permission list pods "$user"; then
        pass "nina can list pods cluster-wide"
    else
        fail_with_cmd "nina cannot list pods cluster-wide" \
            "kubectl auth can-i list pods --all-namespaces --as=$user"
    fi

    if check_permission get secrets "$user"; then
        pass "nina can get secrets cluster-wide"
    else
        fail_with_cmd "nina cannot get secrets cluster-wide" \
            "kubectl auth can-i get secrets --all-namespaces --as=$user"
    fi

    if check_permission create namespaces "$user"; then
        pass "nina can create namespaces"
    else
        fail_with_cmd "nina cannot create namespaces" \
            "kubectl auth can-i create namespaces --as=$user"
    fi

    if check_permission delete namespaces "$user"; then
        pass "nina can delete namespaces"
    else
        fail_with_cmd "nina cannot delete namespaces" \
            "kubectl auth can-i delete namespaces --as=$user"
    fi

    if ! check_permission create deployments "$user" "ex-5-1"; then
        pass "nina cannot create deployments (correct, read-only for most resources)"
    else
        fail "nina can create deployments (should not have write access)"
    fi

    if kubectl auth can-i bind clusterroles/admin --as="$user" &>/dev/null; then
        pass "nina can bind admin ClusterRole"
    else
        fail_with_cmd "nina cannot bind admin ClusterRole" \
            "kubectl auth can-i bind clusterroles/admin --as=$user; kubectl get clusterrole $clusterrole -o yaml"
    fi

    if ! kubectl auth can-i bind clusterroles/edit --as="$user" &>/dev/null; then
        pass "nina cannot bind edit ClusterRole (correct)"
    else
        fail "nina can bind edit ClusterRole (should only bind admin)"
    fi

    if ! kubectl auth can-i bind clusterroles/cluster-admin --as="$user" &>/dev/null; then
        pass "nina cannot bind cluster-admin ClusterRole (correct)"
    else
        fail "nina can bind cluster-admin ClusterRole (should only bind admin)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Multi-bug debug ==="
    local user="olivia"

    if check_permission list clusterroles "$user"; then
        pass "olivia can list clusterroles (issue fixed)"
    else
        fail_with_cmd "olivia cannot list clusterroles" \
            "kubectl auth can-i list clusterroles --as=$user; kubectl get clusterrole ex-5-2-cluster-support -o yaml"
    fi

    if check_permission create clusterroles "$user"; then
        pass "olivia can create clusterroles"
    else
        fail_with_cmd "olivia cannot create clusterroles" \
            "kubectl auth can-i create clusterroles --as=$user; kubectl get clusterrole ex-5-2-cluster-support -o yaml"
    fi

    if check_permission delete clusterroles "$user"; then
        pass "olivia can delete clusterroles"
    else
        fail_with_cmd "olivia cannot delete clusterroles" \
            "kubectl auth can-i delete clusterroles --as=$user"
    fi

    if check_permission list nodes "$user"; then
        pass "olivia can list nodes (issue fixed)"
    else
        fail_with_cmd "olivia cannot list nodes" \
            "kubectl auth can-i list nodes --as=$user; kubectl get clusterrole ex-5-2-cluster-support -o yaml"
    fi

    if check_permission get nodes/kind-control-plane "$user"; then
        pass "olivia can get specific node"
    else
        fail_with_cmd "olivia cannot get specific node" \
            "kubectl auth can-i get nodes/kind-control-plane --as=$user"
    fi

    if ! check_permission list pods "$user"; then
        pass "olivia cannot list pods (correct)"
    else
        fail "olivia can list pods (should not be allowed)"
    fi

    if ! check_permission create pods "$user" "ex-5-2"; then
        pass "olivia cannot create pods (correct)"
    else
        fail "olivia can create pods (should not be allowed)"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Least-privilege cluster-reader ==="
    local user="priya"
    local clusterrole="cluster-reader"
    local binding="priya-cluster-reader"

    if ! clusterrole_exists "$clusterrole"; then
        fail_with_cmd "ClusterRole $clusterrole not found" \
            "kubectl get clusterrole $clusterrole"
        return
    fi

    if ! clusterrolebinding_exists "$binding"; then
        fail_with_cmd "ClusterRoleBinding $binding not found" \
            "kubectl get clusterrolebinding $binding"
        return
    fi

    # Broad read access
    if check_permission list pods "$user"; then
        pass "priya can list pods cluster-wide"
    else
        fail_with_cmd "priya cannot list pods cluster-wide" \
            "kubectl auth can-i list pods --all-namespaces --as=$user; kubectl get clusterrole $clusterrole -o yaml"
    fi

    if check_permission list services "$user"; then
        pass "priya can list services cluster-wide"
    else
        fail_with_cmd "priya cannot list services cluster-wide" \
            "kubectl auth can-i list services --all-namespaces --as=$user"
    fi

    if check_permission list deployments.apps "$user"; then
        pass "priya can list deployments cluster-wide"
    else
        fail_with_cmd "priya cannot list deployments cluster-wide" \
            "kubectl auth can-i list deployments.apps --all-namespaces --as=$user"
    fi

    if check_permission list ingresses.networking.k8s.io "$user"; then
        pass "priya can list ingresses cluster-wide"
    else
        fail_with_cmd "priya cannot list ingresses cluster-wide" \
            "kubectl auth can-i list ingresses.networking.k8s.io --all-namespaces --as=$user"
    fi

    if check_permission list storageclasses "$user"; then
        pass "priya can list storageclasses"
    else
        fail_with_cmd "priya cannot list storageclasses" \
            "kubectl auth can-i list storageclasses --as=$user"
    fi

    if check_permission list nodes "$user"; then
        pass "priya can list nodes"
    else
        fail_with_cmd "priya cannot list nodes" \
            "kubectl auth can-i list nodes --as=$user"
    fi

    if check_permission list clusterroles "$user"; then
        pass "priya can list clusterroles"
    else
        fail_with_cmd "priya cannot list clusterroles" \
            "kubectl auth can-i list clusterroles --as=$user"
    fi

    # Secrets are off-limits
    if ! check_permission list secrets "$user"; then
        pass "priya cannot list secrets (correct)"
    else
        fail "priya can list secrets (should not be allowed)"
    fi

    if ! check_permission get secret/web-tls "$user" "ex-5-3"; then
        pass "priya cannot get specific secret (correct)"
    else
        fail "priya can get specific secret (should not be allowed)"
    fi

    # No write verbs
    if ! check_permission create pods "$user" "ex-5-3"; then
        pass "priya cannot create pods (correct)"
    else
        fail "priya can create pods (should be read-only)"
    fi

    if ! check_permission delete deployments.apps "$user" "ex-5-3"; then
        pass "priya cannot delete deployments (correct)"
    else
        fail "priya can delete deployments (should be read-only)"
    fi

    if ! check_permission create clusterrolebindings "$user"; then
        pass "priya cannot create clusterrolebindings (correct)"
    else
        fail "priya can create clusterrolebindings (should be read-only)"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: ClusterRole Basics"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Cluster-Scoped Resources"
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
    echo "# Level 4: Advanced Patterns"
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
