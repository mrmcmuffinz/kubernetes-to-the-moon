#!/usr/bin/env bash
#
# verify.sh - Automated verification for crds-and-operators-homework.md (assignment-3)
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

# Helper: check if deployment exists
deployment_exists() {
    local deploy=$1; local ns=$2
    kubectl get deployment "$deploy" -n "$ns" &>/dev/null
}

# Helper: check if pod exists
pod_exists() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

# Helper: get deployment ready replicas
get_ready_replicas() {
    local deploy=$1; local ns=$2
    kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0"
}

# Helper: get pod phase
get_phase() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

# Helper: check if CRD exists
crd_exists() {
    local crd=$1
    kubectl get crd "$crd" &>/dev/null
}

# Helper: check if custom resource exists
cr_exists() {
    local kind=$1; local name=$2; local ns=$3
    kubectl get "$kind" "$name" -n "$ns" &>/dev/null
}

# Helper: check if service account exists
sa_exists() {
    local sa=$1; local ns=$2
    kubectl get serviceaccount "$sa" -n "$ns" &>/dev/null
}

# Helper: check if role exists
role_exists() {
    local role=$1; local ns=$2
    kubectl get role "$role" -n "$ns" &>/dev/null
}

# Helper: check if rolebinding exists
rolebinding_exists() {
    local rb=$1; local ns=$2
    kubectl get rolebinding "$rb" -n "$ns" &>/dev/null
}

# Helper: check RBAC permission
check_permission() {
    local user=$1; local verb=$2; local resource=$3; local ns=$4
    kubectl auth can-i "$verb" "$resource" -n "$ns" --as="$user" &>/dev/null
}

# Helper: get owner reference kind
get_owner_kind() {
    local kind=$1; local name=$2; local ns=$3
    kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null
}

# Helper: count pods by label
count_pods_by_label() {
    local label=$1; local ns=$2
    kubectl get pods -n "$ns" -l "$label" --no-headers 2>/dev/null | wc -l
}

# Helper: count replicasets
count_replicasets() {
    local ns=$1
    kubectl get replicasets -n "$ns" --no-headers 2>/dev/null | wc -l
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Identify built-in controllers ==="
    local deploy="web"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deploy" "$ns"; then
        fail_with_cmd "Deployment $deploy not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local ready
    ready=$(get_ready_replicas "$deploy" "$ns")
    if [[ "$ready" == "2" ]]; then
        pass "Deployment has 2/2 ready replicas"
    else
        fail_with_cmd "Deployment has $ready/2 ready replicas" \
            "kubectl get deployment $deploy -n $ns"
    fi

    local rs_count
    rs_count=$(count_replicasets "$ns")
    if [[ "$rs_count" -ge 1 ]]; then
        pass "ReplicaSet exists (count: $rs_count)"
    else
        fail_with_cmd "No ReplicaSet found" \
            "kubectl get replicasets -n $ns"
        return
    fi

    local rs_owner
    rs_owner=$(kubectl get replicasets -n "$ns" -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}' 2>/dev/null)
    if [[ "$rs_owner" == "Deployment" ]]; then
        pass "ReplicaSet owned by Deployment"
    else
        fail_with_cmd "ReplicaSet owner is '$rs_owner' (expected Deployment)" \
            "kubectl get replicasets -n $ns -o yaml"
    fi

    local pod_count
    pod_count=$(count_pods_by_label "app=$deploy" "$ns")
    if [[ "$pod_count" -ge 2 ]]; then
        pass "Pods exist (count: $pod_count)"
    else
        fail_with_cmd "Found $pod_count pods (expected 2)" \
            "kubectl get pods -n $ns"
        return
    fi

    local pod_owner
    pod_owner=$(kubectl get pods -n "$ns" -o jsonpath='{.items[0].metadata.ownerReferences[0].kind}' 2>/dev/null)
    if [[ "$pod_owner" == "ReplicaSet" ]]; then
        pass "Pods owned by ReplicaSet"
    else
        fail_with_cmd "Pod owner is '$pod_owner' (expected ReplicaSet)" \
            "kubectl get pods -n $ns -o yaml | grep -A5 ownerReferences"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Trace Deployment controller reconciliation ==="
    local deploy="demo"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$deploy" "$ns"; then
        fail_with_cmd "Deployment $deploy not found in namespace $ns" \
            "kubectl get deployments -n $ns"
        return
    fi

    local desired
    desired=$(kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null)
    if [[ "$desired" == "3" ]]; then
        pass "Deployment scaled to 3 replicas"
    else
        fail_with_cmd "Deployment replicas is $desired (expected 3)" \
            "kubectl get deployment $deploy -n $ns"
    fi

    sleep 3  # Wait for reconciliation

    local ready
    ready=$(get_ready_replicas "$deploy" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "3/3 replicas ready"
    else
        fail_with_cmd "Ready replicas: $ready/3" \
            "kubectl get deployment $deploy -n $ns"
    fi

    local pod_count
    pod_count=$(count_pods_by_label "app=$deploy" "$ns")
    if [[ "$pod_count" -ge 3 ]]; then
        pass "3 pods running"
    else
        fail_with_cmd "Found $pod_count pods (expected 3)" \
            "kubectl get pods -n $ns -l app=$deploy"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Observe controller manager logs ==="

    # Check if controller-manager pod exists
    local cm_pods
    cm_pods=$(kubectl get pods -n kube-system -l component=kube-controller-manager --no-headers 2>/dev/null | wc -l)

    if [[ "$cm_pods" -ge 1 ]]; then
        pass "Controller manager pod found"
    else
        info "Controller manager pod not found (may be in kube-system with different label)"
        info "This is normal for kind or managed clusters"
        pass "Exercise acknowledged (controller manager may not be accessible)"
        return
    fi

    # Verify logs are accessible
    if kubectl logs -n kube-system -l component=kube-controller-manager --tail=1 &>/dev/null; then
        pass "Controller manager logs are accessible"
    else
        info "Controller manager logs not accessible"
        info "This is normal for some cluster configurations"
        pass "Exercise acknowledged (logs may be restricted)"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Install a simple operator ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! crd_exists "messages.demo.example.com"; then
        fail_with_cmd "CRD messages.demo.example.com not found" \
            "kubectl get crd | grep messages"
        return
    else
        pass "CRD messages.demo.example.com exists"
    fi

    if ! sa_exists "message-operator" "$ns"; then
        fail_with_cmd "ServiceAccount message-operator not found" \
            "kubectl get serviceaccounts -n $ns"
        return
    else
        pass "ServiceAccount message-operator exists"
    fi

    if ! role_exists "message-operator" "$ns"; then
        fail_with_cmd "Role message-operator not found" \
            "kubectl get roles -n $ns"
        return
    else
        pass "Role message-operator exists"
    fi

    if ! rolebinding_exists "message-operator" "$ns"; then
        fail_with_cmd "RoleBinding message-operator not found" \
            "kubectl get rolebindings -n $ns"
        return
    else
        pass "RoleBinding message-operator exists"
    fi

    if ! deployment_exists "message-operator" "$ns"; then
        fail_with_cmd "Deployment message-operator not found" \
            "kubectl get deployments -n $ns"
        return
    else
        pass "Deployment message-operator exists"
    fi

    sleep 3

    local ready
    ready=$(get_ready_replicas "message-operator" "$ns")
    if [[ "$ready" == "1" ]]; then
        pass "Operator deployment is 1/1 Ready"
    else
        fail_with_cmd "Operator deployment is $ready/1 Ready" \
            "kubectl get deployment message-operator -n $ns"
    fi

    local pod_phase
    pod_phase=$(kubectl get pods -n "$ns" -l app=message-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [[ "$pod_phase" == "Running" ]]; then
        pass "Operator pod is Running"
    else
        fail_with_cmd "Operator pod phase is $pod_phase (expected Running)" \
            "kubectl get pods -n $ns -l app=message-operator"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Verify operator installation ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check CRD in api-resources
    if kubectl api-resources | grep -q "messages.*demo.example.com"; then
        pass "CRD appears in api-resources"
    else
        fail_with_cmd "CRD not found in api-resources" \
            "kubectl api-resources | grep messages"
    fi

    # Check service account permissions
    if check_permission "system:serviceaccount:$ns:message-operator" "list" "messages.demo.example.com" "$ns"; then
        pass "ServiceAccount can list messages"
    else
        fail_with_cmd "ServiceAccount cannot list messages" \
            "kubectl auth can-i list messages.demo.example.com -n $ns --as=system:serviceaccount:$ns:message-operator"
    fi

    # Check operator health
    local pod_phase
    pod_phase=$(kubectl get pods -n "$ns" -l app=message-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [[ "$pod_phase" == "Running" ]]; then
        pass "Operator pod is healthy (Running)"
    else
        fail_with_cmd "Operator pod phase is $pod_phase" \
            "kubectl get pods -n $ns -l app=message-operator"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Create custom resource ==="
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cr_exists "message" "hello" "$ns"; then
        fail_with_cmd "Message resource 'hello' not found" \
            "kubectl get messages -n $ns"
        return
    else
        pass "Message resource 'hello' exists"
    fi

    # Check spec.content
    local content
    content=$(kubectl get message hello -n "$ns" -o jsonpath='{.spec.content}' 2>/dev/null)
    if [[ "$content" == "Hello World" ]]; then
        pass "Message spec.content is 'Hello World'"
    else
        fail_with_cmd "Message spec.content is '$content' (expected 'Hello World')" \
            "kubectl describe message hello -n $ns"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug operator pod failure ==="
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "broken-operator" "$ns"; then
        fail_with_cmd "Deployment broken-operator not found" \
            "kubectl get deployments -n $ns"
        return
    fi

    sleep 3

    local pod_phase
    pod_phase=$(kubectl get pods -n "$ns" -l app=broken-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
    if [[ "$pod_phase" == "Running" ]]; then
        pass "Operator pod is Running (issue fixed)"
    else
        fail_with_cmd "Operator pod phase is $pod_phase (expected Running)" \
            "kubectl describe pod -n $ns -l app=broken-operator"
        info "Hint: Check image pull errors"
    fi

    local image
    image=$(kubectl get deployment broken-operator -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null)
    if [[ "$image" == "busybox:1.36" ]]; then
        pass "Image updated to busybox:1.36"
    else
        fail_with_cmd "Image is $image (expected busybox:1.36)" \
            "kubectl get deployment broken-operator -n $ns -o yaml"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix RBAC for custom resource watching ==="
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! crd_exists "configs.settings.example.com"; then
        fail_with_cmd "CRD configs.settings.example.com not found" \
            "kubectl get crd"
        return
    fi

    local sa="system:serviceaccount:$ns:config-operator"

    if check_permission "$sa" "watch" "configs.settings.example.com" "$ns"; then
        pass "ServiceAccount can watch configs"
    else
        fail_with_cmd "ServiceAccount cannot watch configs" \
            "kubectl auth can-i watch configs.settings.example.com -n $ns --as=$sa"
    fi

    if check_permission "$sa" "list" "configs.settings.example.com" "$ns"; then
        pass "ServiceAccount can list configs"
    else
        fail_with_cmd "ServiceAccount cannot list configs" \
            "kubectl auth can-i list configs.settings.example.com -n $ns --as=$sa"
    fi

    # Verify role has correct permissions
    local has_config_perms
    has_config_perms=$(kubectl get role config-operator -n "$ns" -o jsonpath='{.rules[*].resources[*]}' 2>/dev/null | grep -c "configs" || echo "0")
    if [[ "$has_config_perms" -ge 1 ]]; then
        pass "Role includes configs resource"
    else
        fail_with_cmd "Role does not include configs resource" \
            "kubectl get role config-operator -n $ns -o yaml"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Create missing RBAC ==="
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! role_exists "incomplete-operator" "$ns"; then
        fail_with_cmd "Role incomplete-operator not found" \
            "kubectl get roles -n $ns"
        return
    else
        pass "Role incomplete-operator exists"
    fi

    if ! rolebinding_exists "incomplete-operator" "$ns"; then
        fail_with_cmd "RoleBinding incomplete-operator not found" \
            "kubectl get rolebindings -n $ns"
        return
    else
        pass "RoleBinding incomplete-operator exists"
    fi

    local sa="system:serviceaccount:$ns:incomplete-operator"

    # Test pod permissions
    if check_permission "$sa" "create" "pods" "$ns"; then
        pass "ServiceAccount can create pods"
    else
        fail_with_cmd "ServiceAccount cannot create pods" \
            "kubectl auth can-i create pods -n $ns --as=$sa"
    fi

    if check_permission "$sa" "delete" "pods" "$ns"; then
        pass "ServiceAccount can delete pods"
    else
        fail_with_cmd "ServiceAccount cannot delete pods" \
            "kubectl auth can-i delete pods -n $ns --as=$sa"
    fi

    # Test deployment permissions
    if check_permission "$sa" "watch" "deployments" "$ns"; then
        pass "ServiceAccount can watch deployments"
    else
        fail_with_cmd "ServiceAccount cannot watch deployments" \
            "kubectl auth can-i watch deployments -n $ns --as=$sa"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Upgrade operator version ==="
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "versioned-operator" "$ns"; then
        fail_with_cmd "Deployment versioned-operator not found" \
            "kubectl get deployments -n $ns"
        return
    fi

    # Check deployment label
    local deploy_version
    deploy_version=$(kubectl get deployment versioned-operator -n "$ns" -o jsonpath='{.metadata.labels.version}' 2>/dev/null)
    if [[ "$deploy_version" == "2.0" ]]; then
        pass "Deployment label version=2.0"
    else
        fail_with_cmd "Deployment label version=$deploy_version (expected 2.0)" \
            "kubectl get deployment versioned-operator -n $ns -o yaml"
    fi

    sleep 3

    # Check pod label
    local pod_version
    pod_version=$(kubectl get pods -n "$ns" -l app=versioned-operator -o jsonpath='{.items[0].metadata.labels.version}' 2>/dev/null)
    if [[ "$pod_version" == "2.0" ]]; then
        pass "Pod label version=2.0"
    else
        fail_with_cmd "Pod label version=$pod_version (expected 2.0)" \
            "kubectl get pods -n $ns -l app=versioned-operator -o yaml"
    fi

    # Check logs
    if kubectl logs -n "$ns" -l app=versioned-operator 2>/dev/null | grep -q "Operator v2.0"; then
        pass "Logs contain 'Operator v2.0'"
    else
        fail_with_cmd "Logs do not contain 'Operator v2.0'" \
            "kubectl logs -n $ns -l app=versioned-operator"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Clean up operator installation ==="
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check custom resources deleted
    if kubectl get widgets -n "$ns" &>/dev/null; then
        local widget_count
        widget_count=$(kubectl get widgets -n "$ns" --no-headers 2>/dev/null | wc -l)
        if [[ "$widget_count" -eq 0 ]]; then
            pass "No Widget custom resources remain"
        else
            fail_with_cmd "$widget_count Widget(s) still exist (should be deleted first)" \
                "kubectl get widgets -n $ns"
        fi
    else
        pass "Widget CRD or resources cleaned up"
    fi

    # Check deployment deleted
    if deployment_exists "widget-operator" "$ns"; then
        fail_with_cmd "Deployment widget-operator still exists (should be deleted)" \
            "kubectl get deployment widget-operator -n $ns"
    else
        pass "Deployment widget-operator deleted"
    fi

    # Check CRD deleted
    if crd_exists "widgets.cleanup.example.com"; then
        fail_with_cmd "CRD widgets.cleanup.example.com still exists (should be deleted)" \
            "kubectl get crd widgets.cleanup.example.com"
    else
        pass "CRD widgets.cleanup.example.com deleted"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Document operator dependencies ==="

    info "This is a documentation exercise"
    info "Verify by checking that the learner has documented:"
    info "  - CRDs required by the operator"
    info "  - RBAC permissions needed"
    info "  - Other resources (ServiceAccounts, Secrets, ConfigMaps)"
    info "  - Namespace the operator runs in"

    pass "Exercise acknowledged (documentation task)"
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Design and install Application operator ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! crd_exists "applications.mycompany.example.com"; then
        fail_with_cmd "CRD applications.mycompany.example.com not found" \
            "kubectl get crd | grep applications"
        return
    else
        pass "CRD applications.mycompany.example.com exists"
    fi

    # Check CRD has required fields
    local has_name
    has_name=$(kubectl get crd applications.mycompany.example.com -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.name.type}' 2>/dev/null)
    if [[ "$has_name" == "string" ]]; then
        pass "CRD spec includes name field (string)"
    else
        fail_with_cmd "CRD spec missing name field" \
            "kubectl get crd applications.mycompany.example.com -o yaml"
    fi

    local has_replicas
    has_replicas=$(kubectl get crd applications.mycompany.example.com -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.replicas.type}' 2>/dev/null)
    if [[ "$has_replicas" == "integer" ]]; then
        pass "CRD spec includes replicas field (integer)"
    else
        fail_with_cmd "CRD spec missing replicas field" \
            "kubectl get crd applications.mycompany.example.com -o yaml"
    fi

    if ! deployment_exists "application-operator" "$ns"; then
        fail_with_cmd "Deployment application-operator not found" \
            "kubectl get deployments -n $ns"
        return
    else
        pass "Deployment application-operator exists"
    fi

    sleep 3

    local ready
    ready=$(get_ready_replicas "application-operator" "$ns")
    if [[ "$ready" == "1" ]]; then
        pass "Operator deployment is 1/1 Ready"
    else
        fail_with_cmd "Operator deployment is $ready/1 Ready" \
            "kubectl get deployment application-operator -n $ns"
    fi

    # Test RBAC
    local sa="system:serviceaccount:$ns:application-operator"
    if check_permission "$sa" "watch" "applications.mycompany.example.com" "$ns"; then
        pass "ServiceAccount can watch applications"
    else
        fail_with_cmd "ServiceAccount cannot watch applications" \
            "kubectl auth can-i watch applications.mycompany.example.com -n $ns --as=$sa"
    fi

    # Check if test application exists
    if cr_exists "application" "test-app" "$ns"; then
        pass "Test Application 'test-app' created"
    else
        info "Test Application not created yet (optional)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Fix complex RBAC issues ==="
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! crd_exists "databases.data.example.com"; then
        fail_with_cmd "CRD databases.data.example.com not found" \
            "kubectl get crd"
        return
    fi

    local sa="system:serviceaccount:$ns:db-operator"

    # Test database permissions
    if check_permission "$sa" "watch" "databases.data.example.com" "$ns"; then
        pass "ServiceAccount can watch databases"
    else
        fail_with_cmd "ServiceAccount cannot watch databases" \
            "kubectl auth can-i watch databases.data.example.com -n $ns --as=$sa"
    fi

    # Test pod creation
    if check_permission "$sa" "create" "pods" "$ns"; then
        pass "ServiceAccount can create pods"
    else
        fail_with_cmd "ServiceAccount cannot create pods" \
            "kubectl auth can-i create pods -n $ns --as=$sa"
    fi

    # Test pod deletion
    if check_permission "$sa" "delete" "pods" "$ns"; then
        pass "ServiceAccount can delete pods"
    else
        fail_with_cmd "ServiceAccount cannot delete pods" \
            "kubectl auth can-i delete pods -n $ns --as=$sa"
    fi

    # Test event creation
    if check_permission "$sa" "create" "events" "$ns"; then
        pass "ServiceAccount can create events"
    else
        fail_with_cmd "ServiceAccount cannot create events" \
            "kubectl auth can-i create events -n $ns --as=$sa"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Operator adoption strategy ==="

    info "This is a documentation exercise"
    info "Verify by checking that the learner has documented:"
    info "  - Operator evaluation criteria"
    info "  - Safe testing approach"
    info "  - Production monitoring strategy"
    info "  - Upgrade and rollback process"
    info "  - RBAC management practices"

    # Check if strategy ConfigMap exists (optional)
    if kubectl get configmap operator-strategy &>/dev/null; then
        pass "Strategy ConfigMap created"
    else
        info "Strategy ConfigMap not created (optional documentation format)"
        pass "Exercise acknowledged (documentation task)"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Understanding Controllers"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Installing Operators"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging Operator Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Operator Lifecycle"
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
