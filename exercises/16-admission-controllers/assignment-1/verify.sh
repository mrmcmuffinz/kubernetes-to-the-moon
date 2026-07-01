#!/usr/bin/env bash
#
# verify.sh - Automated verification for admission-controllers-homework.md
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

# Helper: check if ValidatingAdmissionPolicy exists
policy_exists() {
    local policy=$1
    kubectl get validatingadmissionpolicy "$policy" &>/dev/null
}

# Helper: check if ValidatingAdmissionPolicyBinding exists
binding_exists() {
    local binding=$1
    kubectl get validatingadmissionpolicybinding "$binding" &>/dev/null
}

# Helper: get policy match apiGroups
get_policy_apigroups() {
    local policy=$1
    kubectl get validatingadmissionpolicy "$policy" \
      -o jsonpath='{.spec.matchConstraints.resourceRules[0].apiGroups[0]}' 2>/dev/null || echo ""
}

# Helper: get policy match resources
get_policy_resources() {
    local policy=$1
    kubectl get validatingadmissionpolicy "$policy" \
      -o jsonpath='{.spec.matchConstraints.resourceRules[0].resources[0]}' 2>/dev/null || echo ""
}

# Helper: get policy match operations
get_policy_operations() {
    local policy=$1
    kubectl get validatingadmissionpolicy "$policy" \
      -o jsonpath='{range .spec.matchConstraints.resourceRules[0].operations[*]}{.}{" "}{end}' 2>/dev/null || echo ""
}

# Helper: get binding validation actions
get_binding_actions() {
    local binding=$1
    kubectl get validatingadmissionpolicybinding "$binding" \
      -o jsonpath='{range .spec.validationActions[*]}{.}{" "}{end}' 2>/dev/null || echo ""
}

# Helper: get binding policyName
get_binding_policy() {
    local binding=$1
    kubectl get validatingadmissionpolicybinding "$binding" \
      -o jsonpath='{.spec.policyName}' 2>/dev/null || echo ""
}

# Helper: get policy expression count
get_validation_count() {
    local policy=$1
    kubectl get validatingadmissionpolicy "$policy" \
      -o jsonpath='{range .spec.validations[*]}{.expression}{"\n"}{end}' 2>/dev/null | wc -l
}

# Helper: check if ConfigMap exists
configmap_exists() {
    local cm=$1
    local ns=$2
    kubectl get configmap "$cm" -n "$ns" &>/dev/null
}

# Helper: get deployment replicas
get_deployment_replicas() {
    local deploy=$1
    local ns=$2
    kubectl get deployment "$deploy" -n "$ns" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo ""
}

# Helper: check if deployment exists
deployment_exists() {
    local deploy=$1
    local ns=$2
    kubectl get deployment "$deploy" -n "$ns" &>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Image prefix policy ==="
    local policy="ex-1-1-image-prefix"
    local binding="ex-1-1-image-prefix-binding"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    if ! binding_exists "$binding"; then
        fail_with_cmd "ValidatingAdmissionPolicyBinding $binding not found" \
            "kubectl get validatingadmissionpolicybindings"
        return
    fi

    pass "Policy and binding exist"

    local apigroup
    apigroup=$(get_policy_apigroups "$policy")
    if [[ "$apigroup" == "" ]]; then
        pass "Policy targets core API group (pods)"
    else
        fail_with_cmd "Policy apiGroups=$apigroup (expected \"\" for core group)" \
            "kubectl get validatingadmissionpolicy $policy -o yaml | grep -A5 matchConstraints"
    fi

    local actions
    actions=$(get_binding_actions "$binding")
    if [[ "$actions" == *"Deny"* ]]; then
        pass "Binding has Deny action"
    else
        fail_with_cmd "Binding actions=$actions (expected Deny)" \
            "kubectl get validatingadmissionpolicybinding $binding -o jsonpath='{.spec.validationActions}'"
    fi

    # Test that a non-conforming pod is rejected
    local test_result
    test_result=$(kubectl run probe-fail -n "$ns" --image=nginx:1.27 --restart=Never 2>&1 || true)
    if [[ "$test_result" == *"denied"* ]] || [[ "$test_result" == *"$policy"* ]]; then
        pass "Non-conforming pod is rejected"
        kubectl delete pod probe-fail -n "$ns" --ignore-not-found &>/dev/null
    else
        fail_with_cmd "Non-conforming pod was not rejected" \
            "kubectl run probe-fail -n $ns --image=nginx:1.27 --restart=Never"
        kubectl delete pod probe-fail -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test that other namespaces are unaffected
    kubectl run probe-allowed -n default --image=nginx:1.27 --restart=Never &>/dev/null || true
    if kubectl get pod probe-allowed -n default &>/dev/null; then
        pass "Other namespaces are unaffected"
        kubectl delete pod probe-allowed -n default &>/dev/null
    else
        fail "Policy incorrectly affects default namespace"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Replica cap policy ==="
    local policy="ex-1-2-replica-cap"
    local binding="ex-1-2-replica-cap-binding"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    if ! binding_exists "$binding"; then
        fail_with_cmd "ValidatingAdmissionPolicyBinding $binding not found" \
            "kubectl get validatingadmissionpolicybindings"
        return
    fi

    pass "Policy and binding exist"

    local apigroup
    apigroup=$(get_policy_apigroups "$policy")
    if [[ "$apigroup" == "apps" ]]; then
        pass "Policy targets apps API group"
    else
        fail_with_cmd "Policy apiGroups=$apigroup (expected apps)" \
            "kubectl get validatingadmissionpolicy $policy -o yaml | grep -A5 matchConstraints"
    fi

    local resource
    resource=$(get_policy_resources "$policy")
    if [[ "$resource" == "deployments" ]]; then
        pass "Policy targets deployments resource"
    else
        fail_with_cmd "Policy resources=$resource (expected deployments)" \
            "kubectl get validatingadmissionpolicy $policy -o yaml | grep -A5 matchConstraints"
    fi

    # Test small deployment is accepted
    kubectl create deployment small -n "$ns" --image=nginx:1.27 --replicas=3 &>/dev/null || true
    if deployment_exists small "$ns"; then
        pass "Small deployment (3 replicas) is accepted"
        kubectl delete deployment small -n "$ns" &>/dev/null
    else
        fail "Small deployment was rejected"
    fi

    # Test large deployment is rejected
    local test_result
    test_result=$(kubectl create deployment big -n "$ns" --image=nginx:1.27 --replicas=10 2>&1 || true)
    if [[ "$test_result" == *"denied"* ]] || [[ "$test_result" == *"$policy"* ]]; then
        pass "Large deployment (10 replicas) is rejected"
    else
        fail_with_cmd "Large deployment was not rejected" \
            "kubectl create deployment big -n $ns --image=nginx:1.27 --replicas=10"
        kubectl delete deployment big -n "$ns" --ignore-not-found &>/dev/null
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Required label policy ==="
    local policy="ex-1-3-team-label"
    local binding="ex-1-3-team-label-binding"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    if ! binding_exists "$binding"; then
        fail_with_cmd "ValidatingAdmissionPolicyBinding $binding not found" \
            "kubectl get validatingadmissionpolicybindings"
        return
    fi

    pass "Policy and binding exist"

    # Test pod without label is rejected
    local test_result
    test_result=$(kubectl run no-label -n "$ns" --image=nginx:1.27 --restart=Never 2>&1 || true)
    if [[ "$test_result" == *"denied"* ]] || [[ "$test_result" == *"$policy"* ]]; then
        pass "Pod without team label is rejected"
    else
        fail_with_cmd "Pod without team label was not rejected" \
            "kubectl run no-label -n $ns --image=nginx:1.27 --restart=Never"
        kubectl delete pod no-label -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test pod with label is accepted
    kubectl run with-label -n "$ns" --image=nginx:1.27 --restart=Never --labels=team=platform &>/dev/null || true
    if kubectl get pod with-label -n "$ns" &>/dev/null; then
        pass "Pod with team label is accepted"
        kubectl delete pod with-label -n "$ns" &>/dev/null
    else
        fail "Pod with team label was rejected"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Warn action policy ==="
    local policy="ex-2-1-warn-bare-images"
    local binding="ex-2-1-warn-binding"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    if ! binding_exists "$binding"; then
        fail_with_cmd "ValidatingAdmissionPolicyBinding $binding not found" \
            "kubectl get validatingadmissionpolicybindings"
        return
    fi

    pass "Policy and binding exist"

    local actions
    actions=$(get_binding_actions "$binding")
    if [[ "$actions" == *"Warn"* ]] && [[ "$actions" != *"Deny"* ]]; then
        pass "Binding uses Warn action (not Deny)"
    else
        fail_with_cmd "Binding actions=$actions (expected Warn only)" \
            "kubectl get validatingadmissionpolicybinding $binding -o jsonpath='{.spec.validationActions}'"
    fi

    # Test bare image triggers warning but is accepted
    local test_result
    test_result=$(kubectl run warned -n "$ns" --image=nginx --restart=Never 2>&1 || true)
    if [[ "$test_result" == *"Warning"* ]] && kubectl get pod warned -n "$ns" &>/dev/null; then
        pass "Bare image triggers warning but pod is created"
        kubectl delete pod warned -n "$ns" &>/dev/null
    else
        fail "Bare image did not trigger warning or pod was not created"
        kubectl delete pod warned -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test tagged image has no warning
    local test_result2
    test_result2=$(kubectl run tagged -n "$ns" --image=nginx:1.27 --restart=Never 2>&1 || true)
    if [[ "$test_result2" != *"Warning"* ]] && kubectl get pod tagged -n "$ns" &>/dev/null; then
        pass "Tagged image produces no warning"
        kubectl delete pod tagged -n "$ns" &>/dev/null
    else
        fail "Tagged image incorrectly triggered warning"
        kubectl delete pod tagged -n "$ns" --ignore-not-found &>/dev/null
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Combined Deny and Audit actions ==="
    local policy="ex-2-2-privileged-block"
    local binding="ex-2-2-privileged-binding"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    if ! binding_exists "$binding"; then
        fail_with_cmd "ValidatingAdmissionPolicyBinding $binding not found" \
            "kubectl get validatingadmissionpolicybindings"
        return
    fi

    pass "Policy and binding exist"

    local actions
    actions=$(get_binding_actions "$binding")
    if [[ "$actions" == *"Deny"* ]] && [[ "$actions" == *"Audit"* ]]; then
        pass "Binding has both Deny and Audit actions"
    else
        fail_with_cmd "Binding actions=$actions (expected Deny and Audit)" \
            "kubectl get validatingadmissionpolicybinding $binding -o jsonpath='{.spec.validationActions}'"
    fi

    # Test privileged pod is rejected
    local test_result
    test_result=$(cat <<'EOF' | kubectl apply -f - 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: priv-pod
  namespace: ex-2-2
spec:
  containers:
    - name: bad
      image: nginx:1.27
      securityContext:
        privileged: true
EOF
)
    if [[ "$test_result" == *"denied"* ]] || [[ "$test_result" == *"$policy"* ]]; then
        pass "Privileged pod is rejected"
    else
        fail_with_cmd "Privileged pod was not rejected" \
            "kubectl get validatingadmissionpolicy $policy -o yaml"
        kubectl delete pod priv-pod -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test non-privileged pod is accepted
    kubectl run ok -n "$ns" --image=nginx:1.27 --restart=Never &>/dev/null || true
    if kubectl get pod ok -n "$ns" &>/dev/null; then
        pass "Non-privileged pod is accepted"
        kubectl delete pod ok -n "$ns" &>/dev/null
    else
        fail "Non-privileged pod was rejected"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Multiple validations ==="
    local policy="ex-2-3-multi"
    local binding="ex-2-3-multi-binding"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    if ! binding_exists "$binding"; then
        fail_with_cmd "ValidatingAdmissionPolicyBinding $binding not found" \
            "kubectl get validatingadmissionpolicybindings"
        return
    fi

    pass "Policy and binding exist"

    local val_count
    val_count=$(get_validation_count "$policy")
    if [[ "$val_count" -ge 2 ]]; then
        pass "Policy has at least 2 validations"
    else
        fail_with_cmd "Policy has $val_count validations (expected at least 2)" \
            "kubectl get validatingadmissionpolicy $policy -o yaml | grep -A3 validations"
    fi

    # Test pod with wrong image is rejected
    local test_result
    test_result=$(kubectl run no-env -n "$ns" --image=nginx:1.27 --restart=Never 2>&1 || true)
    if [[ "$test_result" == *"denied"* ]]; then
        pass "Pod with wrong image is rejected"
    else
        fail "Pod with wrong image was not rejected"
        kubectl delete pod no-env -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test pod with correct image but wrong env label
    local test_result2
    test_result2=$(kubectl run wrong-env -n "$ns" --image=registry.example.com/nginx:1.27 \
      --restart=Never --labels=env=testing 2>&1 || true)
    if [[ "$test_result2" == *"denied"* ]]; then
        pass "Pod with wrong env label is rejected"
    else
        fail "Pod with wrong env label was not rejected"
        kubectl delete pod wrong-env -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test pod passing both validations
    kubectl run correct -n "$ns" --image=registry.example.com/nginx:1.27 \
      --restart=Never --labels=env=prod &>/dev/null 2>&1 || true
    if kubectl get pod correct -n "$ns" &>/dev/null; then
        pass "Pod passing both validations is accepted (admission layer)"
        kubectl delete pod correct -n "$ns" &>/dev/null
    else
        info "Pod may have been rejected (check if both validations pass)"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug hostNetwork policy ==="
    local policy="ex-3-1-no-host-network"
    local binding="ex-3-1-no-host-network-binding"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail "ValidatingAdmissionPolicy $policy not found"
        return
    fi

    pass "Policy exists"

    # The bug in the setup is apiGroups: ["apps"] instead of [""]
    local apigroup
    apigroup=$(get_policy_apigroups "$policy")
    if [[ "$apigroup" == "" ]]; then
        pass "Policy fixed: apiGroups is core (empty string)"
    else
        fail_with_cmd "Policy still has wrong apiGroups=$apigroup (expected \"\")" \
            "kubectl patch validatingadmissionpolicy $policy --type=json --patch '[{\"op\":\"replace\",\"path\":\"/spec/matchConstraints/resourceRules/0/apiGroups\",\"value\":[\"\"]}]'"
    fi

    # Test that hostNetwork pods are rejected
    local test_result
    test_result=$(cat <<'EOF' | kubectl apply -f - 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: hn-fail
  namespace: ex-3-1
spec:
  hostNetwork: true
  containers:
    - name: nginx
      image: nginx:1.27
EOF
)
    if [[ "$test_result" == *"denied"* ]] || [[ "$test_result" == *"$policy"* ]]; then
        pass "hostNetwork pod is rejected after fix"
    else
        fail_with_cmd "hostNetwork pod was not rejected" \
            "kubectl get validatingadmissionpolicy $policy -o yaml | grep -A5 matchConstraints"
        kubectl delete pod hn-fail -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test regular pod is accepted
    kubectl run regular -n "$ns" --image=nginx:1.27 --restart=Never &>/dev/null || true
    if kubectl get pod regular -n "$ns" &>/dev/null; then
        pass "Regular pod is accepted"
        kubectl delete pod regular -n "$ns" &>/dev/null
    else
        fail "Regular pod was rejected"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug label requirement binding ==="
    local policy="ex-3-2-label-req"
    local binding="ex-3-2-label-req-binding"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail "ValidatingAdmissionPolicy $policy not found"
        return
    fi

    if ! binding_exists "$binding"; then
        fail "ValidatingAdmissionPolicyBinding $binding not found"
        return
    fi

    pass "Policy and binding exist"

    # The bug is binding policyName is "ex-3-2-label-requirement" instead of "ex-3-2-label-req"
    local policy_name
    policy_name=$(get_binding_policy "$binding")
    if [[ "$policy_name" == "$policy" ]]; then
        pass "Binding fixed: policyName matches policy name"
    else
        fail_with_cmd "Binding policyName=$policy_name (expected $policy)" \
            "kubectl patch validatingadmissionpolicybinding $binding --type=merge --patch '{\"spec\":{\"policyName\":\"$policy\"}}'"
    fi

    # Test pod without cost-center is rejected
    local test_result
    test_result=$(kubectl run no-cc -n "$ns" --image=nginx:1.27 --restart=Never 2>&1 || true)
    if [[ "$test_result" == *"denied"* ]] || [[ "$test_result" == *"cost-center"* ]]; then
        pass "Pod without cost-center label is rejected after fix"
    else
        fail_with_cmd "Pod without cost-center was not rejected" \
            "kubectl get validatingadmissionpolicybinding $binding -o jsonpath='{.spec.policyName}'"
        kubectl delete pod no-cc -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test pod with cost-center is accepted
    kubectl run ok -n "$ns" --image=nginx:1.27 --restart=Never --labels=cost-center=platform &>/dev/null || true
    if kubectl get pod ok -n "$ns" &>/dev/null; then
        pass "Pod with cost-center label is accepted"
        kubectl delete pod ok -n "$ns" &>/dev/null
    else
        fail "Pod with cost-center was rejected"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug replica cap apiGroups ==="
    local policy="ex-3-3-replica-cap"
    local binding="ex-3-3-replica-cap-binding"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail "ValidatingAdmissionPolicy $policy not found"
        return
    fi

    pass "Policy exists"

    # The bug is apiGroups: [""] instead of ["apps"]
    local apigroup
    apigroup=$(get_policy_apigroups "$policy")
    if [[ "$apigroup" == "apps" ]]; then
        pass "Policy fixed: apiGroups is apps"
    else
        fail_with_cmd "Policy apiGroups=$apigroup (expected apps)" \
            "kubectl patch validatingadmissionpolicy $policy --type=json --patch '[{\"op\":\"replace\",\"path\":\"/spec/matchConstraints/resourceRules/0/apiGroups\",\"value\":[\"apps\"]}]'"
    fi

    # Test oversized deployment is rejected
    local test_result
    test_result=$(kubectl create deployment big -n "$ns" --image=nginx:1.27 --replicas=10 2>&1 || true)
    if [[ "$test_result" == *"denied"* ]] || [[ "$test_result" == *"$policy"* ]]; then
        pass "Oversized deployment is rejected after fix"
    else
        fail_with_cmd "Oversized deployment was not rejected" \
            "kubectl get validatingadmissionpolicy $policy -o yaml | grep -A5 matchConstraints"
        kubectl delete deployment big -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test small deployment is accepted
    kubectl create deployment small -n "$ns" --image=nginx:1.27 --replicas=2 &>/dev/null || true
    if deployment_exists small "$ns"; then
        pass "Small deployment is accepted"
        kubectl delete deployment small -n "$ns" &>/dev/null
    else
        fail "Small deployment was rejected"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Parameter-driven policy ==="
    local policy="ex-4-1-param-cap"
    local binding_small="ex-4-1-param-cap-small"
    local binding_large="ex-4-1-param-cap-large"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    pass "Policy exists"

    if ! configmap_exists "caps-small" "$ns"; then
        fail_with_cmd "ConfigMap caps-small not found in $ns" \
            "kubectl get configmaps -n $ns"
        return
    fi

    if ! configmap_exists "caps-large" "$ns"; then
        fail_with_cmd "ConfigMap caps-large not found in $ns" \
            "kubectl get configmaps -n $ns"
        return
    fi

    pass "Parameter ConfigMaps exist"

    if ! binding_exists "$binding_small" || ! binding_exists "$binding_large"; then
        fail_with_cmd "One or both bindings not found" \
            "kubectl get validatingadmissionpolicybindings | grep ex-4-1"
        return
    fi

    pass "Both bindings exist"

    # Test small-tier with 2 replicas: allowed
    kubectl create deployment s1 -n "$ns" --image=nginx:1.27 --replicas=2 &>/dev/null || true
    kubectl label deployment s1 -n "$ns" tier=small --overwrite &>/dev/null || true
    if deployment_exists s1 "$ns"; then
        pass "Small-tier deployment with 2 replicas is accepted"
        kubectl delete deployment s1 -n "$ns" &>/dev/null
    else
        fail "Small-tier deployment with 2 replicas was rejected"
    fi

    # Test small-tier with 10 replicas: should be rejected
    local test_result
    test_result=$(cat <<'EOF' | kubectl apply -f - 2>&1 || true
apiVersion: apps/v1
kind: Deployment
metadata:
  name: s10
  namespace: ex-4-1
  labels:
    tier: small
spec:
  replicas: 10
  selector:
    matchLabels:
      app: s10
  template:
    metadata:
      labels:
        app: s10
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
EOF
)
    if [[ "$test_result" == *"denied"* ]] || [[ "$test_result" == *"$policy"* ]]; then
        pass "Small-tier deployment with 10 replicas is rejected"
    else
        fail "Small-tier deployment with 10 replicas was not rejected"
        kubectl delete deployment s10 -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test large-tier with 10 replicas: allowed
    cat <<'EOF' | kubectl apply -f - &>/dev/null || true
apiVersion: apps/v1
kind: Deployment
metadata:
  name: l10
  namespace: ex-4-1
  labels:
    tier: large
spec:
  replicas: 10
  selector:
    matchLabels:
      app: l10
  template:
    metadata:
      labels:
        app: l10
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
EOF
    if deployment_exists l10 "$ns"; then
        pass "Large-tier deployment with 10 replicas is accepted"
        kubectl delete deployment l10 -n "$ns" &>/dev/null
    else
        fail "Large-tier deployment with 10 replicas was rejected"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Immutable serviceAccountName on UPDATE ==="
    local policy="ex-4-2-sa-immutable"
    local binding="ex-4-2-sa-binding"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    if ! binding_exists "$binding"; then
        fail_with_cmd "ValidatingAdmissionPolicyBinding $binding not found" \
            "kubectl get validatingadmissionpolicybindings"
        return
    fi

    pass "Policy and binding exist"

    local operations
    operations=$(get_policy_operations "$policy")
    if [[ "$operations" == *"UPDATE"* ]] && [[ "$operations" != *"CREATE"* ]]; then
        pass "Policy matches UPDATE only (not CREATE)"
    else
        fail_with_cmd "Policy operations=$operations (expected UPDATE only)" \
            "kubectl get validatingadmissionpolicy $policy -o yaml | grep -A5 matchConstraints"
    fi

    # Create test service accounts
    kubectl create serviceaccount alpha -n "$ns" &>/dev/null || true
    kubectl create serviceaccount beta  -n "$ns" &>/dev/null || true

    # Create deployment with alpha SA
    cat <<'EOF' | kubectl apply -f - &>/dev/null || true
apiVersion: apps/v1
kind: Deployment
metadata:
  name: immutable-sa
  namespace: ex-4-2
spec:
  replicas: 1
  selector:
    matchLabels:
      app: immutable-sa
  template:
    metadata:
      labels:
        app: immutable-sa
    spec:
      serviceAccountName: alpha
      containers:
        - name: nginx
          image: nginx:1.27
EOF

    sleep 3

    if deployment_exists immutable-sa "$ns"; then
        pass "Deployment created with serviceAccountName=alpha"
    else
        fail "Deployment creation failed"
        return
    fi

    # Try to change SA via patch
    local test_result
    test_result=$(kubectl patch deployment immutable-sa -n "$ns" --type=merge --patch '
spec:
  template:
    spec:
      serviceAccountName: beta
' 2>&1 || true)

    if [[ "$test_result" == *"denied"* ]] || [[ "$test_result" == *"immutable"* ]]; then
        pass "Attempt to change serviceAccountName is rejected"
    else
        fail_with_cmd "serviceAccountName change was not rejected" \
            "kubectl get validatingadmissionpolicy $policy -o yaml"
    fi

    # Benign patch should succeed
    kubectl label deployment immutable-sa -n "$ns" purpose=demo --overwrite &>/dev/null || true
    local label_result
    label_result=$(kubectl get deployment immutable-sa -n "$ns" -o jsonpath='{.metadata.labels.purpose}' 2>/dev/null || echo "")
    if [[ "$label_result" == "demo" ]]; then
        pass "Benign patch (label change) is allowed"
    else
        fail "Benign patch was rejected"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Dynamic messageExpression ==="
    local policy="ex-4-3-dynamic-msg"
    local binding="ex-4-3-dynamic-binding"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    if ! binding_exists "$binding"; then
        fail_with_cmd "ValidatingAdmissionPolicyBinding $binding not found" \
            "kubectl get validatingadmissionpolicybindings"
        return
    fi

    pass "Policy and binding exist"

    # Test pod with one untagged container
    local test_result
    test_result=$(cat <<'EOF' | kubectl apply -f - 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: mixed
  namespace: ex-4-3
spec:
  containers:
    - name: good
      image: nginx:1.27
    - name: bad
      image: nginx
EOF
)
    if [[ "$test_result" == *"denied"* ]] && [[ "$test_result" == *"bad"* ]]; then
        pass "Pod rejected with dynamic message naming offending container"
    else
        fail_with_cmd "Pod not rejected or message did not name container 'bad'" \
            "kubectl get validatingadmissionpolicy $policy -o yaml | grep messageExpression"
        kubectl delete pod mixed -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test fully-tagged pod
    kubectl run all-good -n "$ns" --image=nginx:1.27 --restart=Never &>/dev/null || true
    if kubectl get pod all-good -n "$ns" &>/dev/null; then
        pass "Fully-tagged pod is accepted"
        kubectl delete pod all-good -n "$ns" &>/dev/null
    else
        fail "Fully-tagged pod was rejected"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Cluster guardrail set (4 requirements) ==="
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # Check that multiple policies exist with ex-5-1- prefix
    local policy_count
    policy_count=$(kubectl get validatingadmissionpolicies -o name | grep -c '^validatingadmissionpolicy.admissionregistration.k8s.io/ex-5-1-' || echo 0)

    if [[ "$policy_count" -ge 4 ]]; then
        pass "At least 4 policies exist with ex-5-1- prefix"
    else
        fail_with_cmd "Only $policy_count policies found (expected at least 4)" \
            "kubectl get validatingadmissionpolicies | grep ex-5-1"
    fi

    # Test pod that violates all four: should be rejected
    local test_result
    test_result=$(cat <<'EOF' | kubectl apply -f - 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: bad-all
  namespace: ex-5-1
spec:
  hostNetwork: true
  containers:
    - name: nginx
      image: nginx:1.27
      securityContext:
        runAsUser: 0
EOF
)
    if [[ "$test_result" == *"denied"* ]]; then
        pass "Pod violating all requirements is rejected"
    else
        fail_with_cmd "Pod violating requirements was not rejected" \
            "kubectl get validatingadmissionpolicies | grep ex-5-1"
        kubectl delete pod bad-all -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test pod that passes all four
    cat <<'EOF' | kubectl apply -f - &>/dev/null 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: good-all
  namespace: ex-5-1
  labels:
    team: platform
    env: prod
spec:
  containers:
    - name: nginx
      image: registry.example.com/nginx:1.27
      securityContext:
        runAsUser: 1000
EOF
    if kubectl get pod good-all -n "$ns" &>/dev/null; then
        pass "Pod passing all requirements is accepted (admission layer)"
        kubectl delete pod good-all -n "$ns" &>/dev/null
    else
        info "Pod may have been rejected (verify all 4 policies are correctly scoped)"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Multi-bug guardrail fix ==="
    local policy="ex-5-2-guardrail"
    local binding="ex-5-2-guardrail-binding"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail "ValidatingAdmissionPolicy $policy not found"
        return
    fi

    if ! binding_exists "$binding"; then
        fail "ValidatingAdmissionPolicyBinding $binding not found"
        return
    fi

    pass "Policy and binding exist"

    # Check fix 1: resources should be "pods" (plural)
    local resource
    resource=$(get_policy_resources "$policy")
    if [[ "$resource" == "pods" ]]; then
        pass "Fix 1: resources is 'pods' (plural)"
    else
        fail_with_cmd "resources=$resource (expected 'pods')" \
            "kubectl patch validatingadmissionpolicy $policy --type=json --patch '[{\"op\":\"replace\",\"path\":\"/spec/matchConstraints/resourceRules/0/resources\",\"value\":[\"pods\"]}]'"
    fi

    # Check fix 2: operations should include UPDATE
    local operations
    operations=$(get_policy_operations "$policy")
    if [[ "$operations" == *"CREATE"* ]] && [[ "$operations" == *"UPDATE"* ]]; then
        pass "Fix 2: operations include both CREATE and UPDATE"
    else
        fail_with_cmd "operations=$operations (expected CREATE and UPDATE)" \
            "kubectl patch validatingadmissionpolicy $policy --type=json --patch '[{\"op\":\"replace\",\"path\":\"/spec/matchConstraints/resourceRules/0/operations\",\"value\":[\"CREATE\",\"UPDATE\"]}]'"
    fi

    # Check fix 3: validation should cover all containers (check via test)
    local test_result
    test_result=$(cat <<'EOF' | kubectl apply -f - 2>&1 || true
apiVersion: v1
kind: Pod
metadata:
  name: multi-bad
  namespace: ex-5-2
spec:
  containers:
    - name: a
      image: registry.example.com/app:1.0
    - name: b
      image: nginx:1.27
EOF
)
    if [[ "$test_result" == *"denied"* ]]; then
        pass "Fix 3: validation covers all containers (multi-container pod rejected)"
    else
        fail "Multi-container pod with bad second container was not rejected"
        kubectl delete pod multi-bad -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Check fix 4: binding should have Deny action
    local actions
    actions=$(get_binding_actions "$binding")
    if [[ "$actions" == *"Deny"* ]]; then
        pass "Fix 4: binding has Deny action"
    else
        fail_with_cmd "binding actions=$actions (expected Deny)" \
            "kubectl patch validatingadmissionpolicybinding $binding --type=merge --patch '{\"spec\":{\"validationActions\":[\"Deny\"]}}'"
    fi

    # Final test: non-conforming pod should be rejected
    local final_test
    final_test=$(kubectl run bad -n "$ns" --image=nginx:1.27 --restart=Never 2>&1 || true)
    if [[ "$final_test" == *"denied"* ]]; then
        pass "Non-conforming pod is now rejected after all fixes"
    else
        fail "Non-conforming pod was not rejected"
        kubectl delete pod bad -n "$ns" --ignore-not-found &>/dev/null
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Production-style prod-* deployment policy ==="
    local policy="ex-5-3-prod"
    local binding="ex-5-3-prod-binding"
    local cm="ex-5-3-params"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! policy_exists "$policy"; then
        fail_with_cmd "ValidatingAdmissionPolicy $policy not found" \
            "kubectl get validatingadmissionpolicies"
        return
    fi

    if ! binding_exists "$binding"; then
        fail_with_cmd "ValidatingAdmissionPolicyBinding $binding not found" \
            "kubectl get validatingadmissionpolicybindings"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail_with_cmd "ConfigMap $cm not found in $ns" \
            "kubectl get configmaps -n $ns"
        return
    fi

    pass "Policy, binding, and parameter ConfigMap exist"

    local val_count
    val_count=$(get_validation_count "$policy")
    if [[ "$val_count" -ge 2 ]]; then
        pass "Policy has at least 2 validations (replicas and image)"
    else
        fail "Policy has $val_count validations (expected at least 2)"
    fi

    # Test non-prod deployment: allowed
    kubectl create deployment staging-app -n "$ns" --image=nginx:1.27 --replicas=1 &>/dev/null || true
    if deployment_exists staging-app "$ns"; then
        pass "Non-prod deployment (staging-app) is accepted"
        kubectl delete deployment staging-app -n "$ns" &>/dev/null
    else
        fail "Non-prod deployment was rejected"
    fi

    # Test prod- with 1 replica: rejected (replica-count validation)
    local test_result
    test_result=$(kubectl create deployment prod-web -n "$ns" --image=registry.example.com/nginx:1.27 --replicas=1 2>&1 || true)
    if [[ "$test_result" == *"denied"* ]]; then
        pass "prod-web with 1 replica is rejected"
    else
        fail "prod-web with 1 replica was not rejected"
        kubectl delete deployment prod-web -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test prod- with 5 replicas and wrong image: rejected (image validation)
    local test_result2
    test_result2=$(cat <<'EOF' | kubectl apply -f - 2>&1 || true
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-api
  namespace: ex-5-3
spec:
  replicas: 5
  selector:
    matchLabels:
      app: prod-api
  template:
    metadata:
      labels:
        app: prod-api
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
EOF
)
    if [[ "$test_result2" == *"denied"* ]]; then
        pass "prod-api with wrong image is rejected"
    else
        fail "prod-api with wrong image was not rejected"
        kubectl delete deployment prod-api -n "$ns" --ignore-not-found &>/dev/null
    fi

    # Test prod- with 5 replicas and correct image: accepted
    cat <<'EOF' | kubectl apply -f - &>/dev/null || true
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-ok
  namespace: ex-5-3
spec:
  replicas: 5
  selector:
    matchLabels:
      app: prod-ok
  template:
    metadata:
      labels:
        app: prod-ok
    spec:
      containers:
        - name: nginx
          image: registry.example.com/nginx:1.27
EOF
    if deployment_exists prod-ok "$ns"; then
        pass "prod-ok with 5 replicas and correct image is accepted"
        kubectl delete deployment prod-ok -n "$ns" &>/dev/null
    else
        fail "prod-ok with correct configuration was rejected"
    fi
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basics"
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
    echo "# Level 3: Debugging"
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
    echo "# Level 5: Advanced"
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
