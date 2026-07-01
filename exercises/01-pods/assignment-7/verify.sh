#!/usr/bin/env bash
#
# verify.sh - Automated verification for workload-controllers-homework.md
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
    local name=$1; local ns=$2
    kubectl get deployment "$name" -n "$ns" &>/dev/null
}

# Helper: check if daemonset exists
daemonset_exists() {
    local name=$1; local ns=$2
    kubectl get daemonset "$name" -n "$ns" &>/dev/null
}

# Helper: get deployment replicas
get_replicas() {
    local name=$1; local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.status.replicas}' 2>/dev/null
}

# Helper: get deployment ready replicas
get_ready_replicas() {
    local name=$1; local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null
}

# Helper: get deployment available replicas
get_available_replicas() {
    local name=$1; local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.status.availableReplicas}' 2>/dev/null
}

# Helper: get daemonset desired number scheduled
get_ds_desired() {
    local name=$1; local ns=$2
    kubectl get daemonset "$name" -n "$ns" -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null
}

# Helper: get daemonset number ready
get_ds_ready() {
    local name=$1; local ns=$2
    kubectl get daemonset "$name" -n "$ns" -o jsonpath='{.status.numberReady}' 2>/dev/null
}

# Helper: get daemonset number available
get_ds_available() {
    local name=$1; local ns=$2
    kubectl get daemonset "$name" -n "$ns" -o jsonpath='{.status.numberAvailable}' 2>/dev/null
}

# Helper: get pod image
get_pod_image() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null
}

# Helper: count pods with label
count_pods_with_label() {
    local ns=$1; local label=$2
    kubectl get pods -n "$ns" -l "$label" --no-headers 2>/dev/null | wc -l
}

# Helper: get deployment strategy type
get_strategy_type() {
    local name=$1; local ns=$2
    kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.strategy.type}' 2>/dev/null
}

# Helper: get rollout history revision count
get_revision_count() {
    local name=$1; local ns=$2
    kubectl rollout history deployment/"$name" -n "$ns" 2>/dev/null | grep -c "^[0-9]" || echo "0"
}

# Helper: get replicaset count for deployment
get_rs_count() {
    local ns=$1; local label=$2
    kubectl get rs -n "$ns" -l "$label" --no-headers 2>/dev/null | wc -l
}

# Helper: check if rollout is complete
rollout_is_complete() {
    local name=$1; local ns=$2
    kubectl rollout status deployment/"$name" -n "$ns" --timeout=5s &>/dev/null
}

# Helper: get nodes for daemonset pods
get_ds_pod_nodes() {
    local ns=$1; local label=$2
    kubectl get pods -n "$ns" -l "$label" -o wide --no-headers 2>/dev/null | awk '{print $7}' | sort
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Create a Deployment ==="
    local name="web"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$name" "$ns"; then
        fail_with_cmd "Deployment $name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    # Give deployment time to stabilize
    sleep 3

    local ready
    ready=$(get_ready_replicas "$name" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "Deployment has 3 ready replicas"
    else
        fail_with_cmd "Deployment has $ready ready replicas (expected 3)" \
            "kubectl get deployment $name -n $ns"
    fi

    local pod_count
    pod_count=$(count_pods_with_label "$ns" "app=web")
    if [[ "$pod_count" == "3" ]]; then
        pass "Exactly 3 pods are Running"
    else
        fail_with_cmd "Found $pod_count pods (expected 3)" \
            "kubectl get pods -n $ns -l app=web"
    fi

    local rs_count
    rs_count=$(get_rs_count "$ns" "app=web")
    if [[ "$rs_count" -ge "1" ]]; then
        pass "ReplicaSet created by Deployment"
    else
        fail_with_cmd "No ReplicaSet found" \
            "kubectl get rs -n $ns -l app=web"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Scale a Deployment ==="
    local name="scaler"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$name" "$ns"; then
        fail_with_cmd "Deployment $name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    sleep 3

    local ready
    ready=$(get_ready_replicas "$name" "$ns")
    if [[ "$ready" == "5" ]]; then
        pass "Deployment has 5 ready replicas"
    else
        fail_with_cmd "Deployment has $ready ready replicas (expected 5)" \
            "kubectl get deployment $name -n $ns"
    fi

    local pod_count
    pod_count=$(count_pods_with_label "$ns" "app=scaler")
    if [[ "$pod_count" == "5" ]]; then
        pass "Exactly 5 pods are Running"
    else
        fail_with_cmd "Found $pod_count pods (expected 5)" \
            "kubectl get pods -n $ns -l app=scaler"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Create a DaemonSet on worker nodes ==="
    local name="node-reporter"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! daemonset_exists "$name" "$ns"; then
        fail_with_cmd "DaemonSet $name not found in namespace $ns" \
            "kubectl get daemonset -n $ns"
        return
    fi

    sleep 3

    local desired
    desired=$(get_ds_desired "$name" "$ns")
    if [[ "$desired" == "3" ]]; then
        pass "DaemonSet desires 3 pods (one per worker node)"
    else
        fail_with_cmd "DaemonSet desires $desired pods (expected 3)" \
            "kubectl get daemonset $name -n $ns"
    fi

    local ready
    ready=$(get_ds_ready "$name" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "All 3 pods are Ready"
    else
        fail_with_cmd "Only $ready pods are Ready (expected 3)" \
            "kubectl get daemonset $name -n $ns"
    fi

    local nodes
    nodes=$(get_ds_pod_nodes "$ns" "app=node-reporter")
    local expected_nodes=$'kind-worker\nkind-worker2\nkind-worker3'
    if [[ "$nodes" == "$expected_nodes" ]]; then
        pass "Pods are distributed across all three worker nodes"
    else
        fail_with_cmd "Pods are not on expected nodes" \
            "kubectl get pods -n $ns -l app=node-reporter -o wide"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Rolling update and rollback ==="
    local name="roller"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$name" "$ns"; then
        fail_with_cmd "Deployment $name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    sleep 3

    # Check that rollback occurred (should be back to nginx:1.25)
    local all_images
    all_images=$(kubectl get pods -n "$ns" -l app=roller -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null)
    if echo "$all_images" | grep -q "nginx:1.25" && ! echo "$all_images" | grep -q "nginx:1.26-alpine"; then
        pass "After rollback, all pods run nginx:1.25"
    else
        fail_with_cmd "Pods are not running nginx:1.25 after rollback" \
            "kubectl get pods -n $ns -l app=roller -o jsonpath='{.items[*].spec.containers[0].image}'"
    fi

    local rev_count
    rev_count=$(get_revision_count "$name" "$ns")
    if [[ "$rev_count" -ge "2" ]]; then
        pass "Rollout history shows at least 2 revisions"
    else
        fail_with_cmd "Rollout history has $rev_count revisions (expected at least 2)" \
            "kubectl rollout history deployment/$name -n $ns"
    fi

    if rollout_is_complete "$name" "$ns"; then
        pass "Rollout status is complete"
    else
        fail_with_cmd "Rollout is not complete" \
            "kubectl rollout status deployment/$name -n $ns"
    fi

    local rs_count
    rs_count=$(get_rs_count "$ns" "app=roller")
    if [[ "$rs_count" -ge "2" ]]; then
        pass "Two or more ReplicaSets exist"
    else
        fail_with_cmd "Only $rs_count ReplicaSet(s) found (expected 2 or more)" \
            "kubectl get rs -n $ns -l app=roller"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: DaemonSet with targeted node selection ==="
    local name="targeted-agent"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! daemonset_exists "$name" "$ns"; then
        fail_with_cmd "DaemonSet $name not found in namespace $ns" \
            "kubectl get daemonset -n $ns"
        return
    fi

    sleep 3

    # After removing label from kind-worker, should have 1 pod on kind-worker2
    local desired
    desired=$(get_ds_desired "$name" "$ns")
    if [[ "$desired" == "1" ]]; then
        pass "After removing label: DaemonSet desires 1 pod"
    else
        fail_with_cmd "DaemonSet desires $desired pods (expected 1 after label removal)" \
            "kubectl get daemonset $name -n $ns"
    fi

    local nodes
    nodes=$(get_ds_pod_nodes "$ns" "app=targeted-agent")
    if [[ "$nodes" == "kind-worker2" ]]; then
        pass "Remaining pod is on kind-worker2"
    else
        fail_with_cmd "Pod is not on expected node: $nodes" \
            "kubectl get pods -n $ns -l app=targeted-agent -o wide"
    fi

    local available
    available=$(get_ds_available "$name" "$ns")
    if [[ "$available" == "1" ]]; then
        pass "DaemonSet is fully available"
    else
        fail_with_cmd "DaemonSet availability is $available (expected 1)" \
            "kubectl get daemonset $name -n $ns"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Deployment with RollingUpdate parameters ==="
    local name="controlled-roll"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$name" "$ns"; then
        fail_with_cmd "Deployment $name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    sleep 3

    local strategy
    strategy=$(get_strategy_type "$name" "$ns")
    if [[ "$strategy" == "RollingUpdate" ]]; then
        pass "Strategy type is RollingUpdate"
    else
        fail_with_cmd "Strategy type is $strategy (expected RollingUpdate)" \
            "kubectl get deployment $name -n $ns -o jsonpath='{.spec.strategy.type}'"
    fi

    local max_surge
    max_surge=$(kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge}' 2>/dev/null)
    if [[ "$max_surge" == "1" ]]; then
        pass "maxSurge is 1"
    else
        fail_with_cmd "maxSurge is $max_surge (expected 1)" \
            "kubectl get deployment $name -n $ns -o jsonpath='{.spec.strategy.rollingUpdate}'"
    fi

    local max_unavailable
    max_unavailable=$(kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)
    if [[ "$max_unavailable" == "0" ]]; then
        pass "maxUnavailable is 0"
    else
        fail_with_cmd "maxUnavailable is $max_unavailable (expected 0)" \
            "kubectl get deployment $name -n $ns -o jsonpath='{.spec.strategy.rollingUpdate}'"
    fi

    # After rollout, should be running nginx:1.26-alpine
    local all_images
    all_images=$(kubectl get pods -n "$ns" -l app=controlled-roll -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null)
    if echo "$all_images" | grep -q "nginx:1.26-alpine" && ! echo "$all_images" | grep -q "nginx:1.25"; then
        pass "After rollout: all 4 pods run nginx:1.26-alpine"
    else
        fail_with_cmd "Pods are not running nginx:1.26-alpine" \
            "kubectl get pods -n $ns -l app=controlled-roll -o jsonpath='{.items[*].spec.containers[0].image}'"
    fi

    if rollout_is_complete "$name" "$ns"; then
        pass "Rollout completed successfully"
    else
        fail_with_cmd "Rollout is not complete" \
            "kubectl rollout status deployment/$name -n $ns"
    fi

    local ready
    ready=$(get_ready_replicas "$name" "$ns")
    if [[ "$ready" == "4" ]]; then
        pass "Exactly 4 ready replicas"
    else
        fail_with_cmd "Deployment has $ready ready replicas (expected 4)" \
            "kubectl get deployment $name -n $ns"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix broken Deployment selector ==="
    local name="broken-deploy"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$name" "$ns"; then
        fail_with_cmd "Deployment $name not found (fix may require recreating)" \
            "kubectl get deployment -n $ns"
        return
    fi

    sleep 3

    local ready
    ready=$(get_ready_replicas "$name" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "Deployment has 3 ready replicas"
    else
        fail_with_cmd "Deployment has $ready ready replicas (expected 3)" \
            "kubectl get deployment $name -n $ns"
    fi

    local running_count
    running_count=$(kubectl get pods -n "$ns" -l app=broken-deploy --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
    if [[ "$running_count" == "3" ]]; then
        pass "All 3 pods are Running"
    else
        fail_with_cmd "Only $running_count pods are Running (expected 3)" \
            "kubectl get pods -n $ns -l app=broken-deploy"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix stuck rollout with bad image ==="
    local name="stuck-rollout"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$name" "$ns"; then
        fail_with_cmd "Deployment $name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    sleep 3

    if rollout_is_complete "$name" "$ns"; then
        pass "Rollout is complete"
    else
        fail_with_cmd "Rollout is not complete" \
            "kubectl rollout status deployment/$name -n $ns"
    fi

    local ready
    ready=$(get_ready_replicas "$name" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "All 3 pods are Ready"
    else
        fail_with_cmd "Only $ready pods are Ready (expected 3)" \
            "kubectl get deployment $name -n $ns"
    fi

    local image
    image=$(kubectl get pods -n "$ns" -l app=stuck-rollout -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null)
    if [[ "$image" != "nginx:1.25" ]] && [[ "$image" != *"nonexistent"* ]] && [[ "$image" == nginx* ]]; then
        pass "Pods are running a valid, updated image: $image"
    else
        fail_with_cmd "Pods are running $image (should be a valid nginx tag, not 1.25 or nonexistent)" \
            "kubectl get pods -n $ns -l app=stuck-rollout -o jsonpath='{.items[*].spec.containers[0].image}'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix DaemonSet node selector ==="
    local name="broken-ds"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! daemonset_exists "$name" "$ns"; then
        fail_with_cmd "DaemonSet $name not found in namespace $ns" \
            "kubectl get daemonset -n $ns"
        return
    fi

    sleep 3

    local desired
    desired=$(get_ds_desired "$name" "$ns")
    if [[ "$desired" == "3" ]]; then
        pass "DaemonSet desires 3 pods"
    else
        fail_with_cmd "DaemonSet desires $desired pods (expected 3)" \
            "kubectl get daemonset $name -n $ns"
    fi

    local ready
    ready=$(get_ds_ready "$name" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "All 3 pods are Ready"
    else
        fail_with_cmd "Only $ready pods are Ready (expected 3)" \
            "kubectl get daemonset $name -n $ns"
    fi

    local nodes
    nodes=$(get_ds_pod_nodes "$ns" "app=broken-ds")
    local expected_nodes=$'kind-worker\nkind-worker2\nkind-worker3'
    if [[ "$nodes" == "$expected_nodes" ]]; then
        pass "Pods are on the three worker nodes"
    else
        fail_with_cmd "Pods are not on expected nodes" \
            "kubectl get pods -n $ns -l app=broken-ds -o wide"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Production Deployment with rollout and rollback ==="
    local name="prod-web"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$name" "$ns"; then
        fail_with_cmd "Deployment $name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    sleep 3

    local ready
    ready=$(get_ready_replicas "$name" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "Deployment has 3 ready replicas"
    else
        fail_with_cmd "Deployment has $ready ready replicas (expected 3)" \
            "kubectl get deployment $name -n $ns"
    fi

    local strategy_params
    strategy_params=$(kubectl get deployment "$name" -n "$ns" \
        -o jsonpath='{.spec.strategy.rollingUpdate.maxSurge} {.spec.strategy.rollingUpdate.maxUnavailable}' 2>/dev/null)
    if [[ "$strategy_params" == "1 0" ]]; then
        pass "Strategy is correct (maxSurge: 1, maxUnavailable: 0)"
    else
        fail_with_cmd "Strategy params are: $strategy_params (expected 1 0)" \
            "kubectl get deployment $name -n $ns -o jsonpath='{.spec.strategy}'"
    fi

    # After rollback, should be back to nginx:1.25 and version=v1
    local all_images
    all_images=$(kubectl get pods -n "$ns" -l app=prod-web -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null)
    if echo "$all_images" | grep -q "nginx:1.25" && ! echo "$all_images" | grep -q "nginx:1.26-alpine"; then
        pass "After rollback: all pods run nginx:1.25"
    else
        fail_with_cmd "Pods are not running nginx:1.25 after rollback" \
            "kubectl get pods -n $ns -l app=prod-web -o jsonpath='{.items[*].spec.containers[0].image}'"
    fi

    local version_label
    version_label=$(kubectl get deployment "$name" -n "$ns" -o jsonpath='{.spec.template.metadata.labels.version}' 2>/dev/null)
    if [[ "$version_label" == "v1" ]]; then
        pass "After rollback: template version label is v1"
    else
        fail_with_cmd "Template version label is $version_label (expected v1 after rollback)" \
            "kubectl get deployment $name -n $ns -o jsonpath='{.spec.template.metadata.labels}'"
    fi

    local rev_count
    rev_count=$(get_revision_count "$name" "$ns")
    if [[ "$rev_count" -ge "3" ]]; then
        pass "Rollout history has at least 3 revisions"
    else
        fail_with_cmd "Rollout history has $rev_count revisions (expected at least 3)" \
            "kubectl rollout history deployment/$name -n $ns"
    fi

    local readiness_port
    readiness_port=$(kubectl get deployment "$name" -n "$ns" \
        -o jsonpath='{.spec.template.spec.containers[0].readinessProbe.httpGet.port}' 2>/dev/null)
    if [[ "$readiness_port" == "80" ]]; then
        pass "Readiness probe is configured on port 80"
    else
        fail_with_cmd "Readiness probe port is $readiness_port (expected 80)" \
            "kubectl get deployment $name -n $ns -o jsonpath='{.spec.template.spec.containers[0].readinessProbe}'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: DaemonSet on all nodes including control-plane ==="
    local name="cluster-agent"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! daemonset_exists "$name" "$ns"; then
        fail_with_cmd "DaemonSet $name not found in namespace $ns" \
            "kubectl get daemonset -n $ns"
        return
    fi

    sleep 3

    local desired
    desired=$(get_ds_desired "$name" "$ns")
    if [[ "$desired" == "4" ]]; then
        pass "DaemonSet desires 4 pods (all nodes including control-plane)"
    else
        fail_with_cmd "DaemonSet desires $desired pods (expected 4)" \
            "kubectl get daemonset $name -n $ns"
    fi

    local ready
    ready=$(get_ds_ready "$name" "$ns")
    if [[ "$ready" == "4" ]]; then
        pass "All 4 pods are Ready"
    else
        fail_with_cmd "Only $ready pods are Ready (expected 4)" \
            "kubectl get daemonset $name -n $ns"
    fi

    local control_plane_count
    control_plane_count=$(kubectl get pods -n "$ns" -l app=cluster-agent -o wide --no-headers 2>/dev/null | grep control-plane | wc -l)
    if [[ "$control_plane_count" == "1" ]]; then
        pass "One pod is on the control-plane node"
    else
        fail_with_cmd "Found $control_plane_count pods on control-plane (expected 1)" \
            "kubectl get pods -n $ns -l app=cluster-agent -o wide | grep control-plane"
    fi

    local cpu_request
    cpu_request=$(kubectl get ds "$name" -n "$ns" \
        -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' 2>/dev/null)
    if [[ "$cpu_request" == "10m" ]]; then
        pass "CPU request is set to 10m"
    else
        fail_with_cmd "CPU request is $cpu_request (expected 10m)" \
            "kubectl get ds $name -n $ns -o jsonpath='{.spec.template.spec.containers[0].resources}'"
    fi

    local mem_limit
    mem_limit=$(kubectl get ds "$name" -n "$ns" \
        -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' 2>/dev/null)
    if [[ "$mem_limit" == "32Mi" ]]; then
        pass "Memory limit is set to 32Mi"
    else
        fail_with_cmd "Memory limit is $mem_limit (expected 32Mi)" \
            "kubectl get ds $name -n $ns -o jsonpath='{.spec.template.spec.containers[0].resources}'"
    fi

    local nodes
    nodes=$(get_ds_pod_nodes "$ns" "app=cluster-agent")
    local expected_nodes=$'kind-control-plane\nkind-worker\nkind-worker2\nkind-worker3'
    if [[ "$nodes" == "$expected_nodes" ]]; then
        pass "Pods are distributed across all 4 nodes"
    else
        fail_with_cmd "Pods are not on expected nodes" \
            "kubectl get pods -n $ns -l app=cluster-agent -o wide"
    fi

    local component_count
    component_count=$(count_pods_with_label "$ns" "component=monitoring")
    if [[ "$component_count" == "4" ]]; then
        pass "Component label is present on all pods"
    else
        fail_with_cmd "Only $component_count pods have component=monitoring label" \
            "kubectl get pods -n $ns -l component=monitoring"
    fi

    local toleration_key
    toleration_key=$(kubectl get ds "$name" -n "$ns" \
        -o jsonpath='{.spec.template.spec.tolerations[0].key}' 2>/dev/null)
    if [[ "$toleration_key" == "node-role.kubernetes.io/control-plane" ]]; then
        pass "Toleration for control-plane is present"
    else
        fail_with_cmd "Toleration key is $toleration_key (expected node-role.kubernetes.io/control-plane)" \
            "kubectl get ds $name -n $ns -o jsonpath='{.spec.template.spec.tolerations}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Two independent Deployments with label hygiene ==="
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "frontend" "$ns" || ! deployment_exists "backend" "$ns"; then
        fail_with_cmd "One or both Deployments not found" \
            "kubectl get deployment -n $ns"
        return
    fi

    sleep 3

    local fe_ready
    fe_ready=$(get_ready_replicas "frontend" "$ns")
    if [[ "$fe_ready" == "3" ]]; then
        pass "Frontend has 3 ready replicas"
    else
        fail_with_cmd "Frontend has $fe_ready ready replicas (expected 3)" \
            "kubectl get deployment frontend -n $ns"
    fi

    local be_ready
    be_ready=$(get_ready_replicas "backend" "$ns")
    if [[ "$be_ready" == "2" ]]; then
        pass "Backend has 2 ready replicas"
    else
        fail_with_cmd "Backend has $be_ready ready replicas (expected 2)" \
            "kubectl get deployment backend -n $ns"
    fi

    local total_pods
    total_pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$total_pods" == "5" ]]; then
        pass "Total pods in namespace: 5"
    else
        fail_with_cmd "Total pods: $total_pods (expected 5)" \
            "kubectl get pods -n $ns"
    fi

    local fe_component_count
    fe_component_count=$(count_pods_with_label "$ns" "component=frontend")
    if [[ "$fe_component_count" == "3" ]]; then
        pass "Frontend pods have component=frontend label"
    else
        fail_with_cmd "Only $fe_component_count frontend pods found" \
            "kubectl get pods -n $ns -l component=frontend"
    fi

    local be_component_count
    be_component_count=$(count_pods_with_label "$ns" "component=backend")
    if [[ "$be_component_count" == "2" ]]; then
        pass "Backend pods have component=backend label"
    else
        fail_with_cmd "Only $be_component_count backend pods found" \
            "kubectl get pods -n $ns -l component=backend"
    fi

    local app_count
    app_count=$(count_pods_with_label "$ns" "app=myapp")
    if [[ "$app_count" == "5" ]]; then
        pass "Selecting by app=myapp returns all 5 pods"
    else
        fail_with_cmd "Only $app_count pods have app=myapp label" \
            "kubectl get pods -n $ns -l app=myapp"
    fi

    local fe_selector_count
    fe_selector_count=$(count_pods_with_label "$ns" "app=myapp,component=frontend")
    if [[ "$fe_selector_count" == "3" ]]; then
        pass "Frontend selector matches 3 pods only"
    else
        fail_with_cmd "Frontend selector matches $fe_selector_count pods (expected 3)" \
            "kubectl get pods -n $ns -l app=myapp,component=frontend"
    fi

    local be_selector_count
    be_selector_count=$(count_pods_with_label "$ns" "app=myapp,component=backend")
    if [[ "$be_selector_count" == "2" ]]; then
        pass "Backend selector matches 2 pods only"
    else
        fail_with_cmd "Backend selector matches $be_selector_count pods (expected 2)" \
            "kubectl get pods -n $ns -l app=myapp,component=backend"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Fix complex Deployment issues ==="
    local name="complex-deploy"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "$name" "$ns"; then
        fail_with_cmd "Deployment $name not found in namespace $ns" \
            "kubectl get deployment -n $ns"
        return
    fi

    sleep 3

    local ready
    ready=$(get_ready_replicas "$name" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "After fixes: Deployment has 3 ready replicas"
    else
        fail_with_cmd "Deployment has $ready ready replicas (expected 3)" \
            "kubectl get deployment $name -n $ns"
    fi

    # After rollback, should be nginx:1.25
    local all_images
    all_images=$(kubectl get pods -n "$ns" -l app=complex-deploy -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null)
    if echo "$all_images" | grep -q "nginx:1.25" && ! echo "$all_images" | grep -q "nginx:1.26-alpine"; then
        pass "After rollback: all pods run nginx:1.25"
    else
        fail_with_cmd "Pods are not running nginx:1.25 after rollback" \
            "kubectl get pods -n $ns -l app=complex-deploy -o jsonpath='{.items[*].spec.containers[0].image}'"
    fi

    local rev_count
    rev_count=$(get_revision_count "$name" "$ns")
    if [[ "$rev_count" -ge "2" ]]; then
        pass "Rollout history has multiple revisions"
    else
        fail_with_cmd "Rollout history has $rev_count revisions (expected at least 2)" \
            "kubectl rollout history deployment/$name -n $ns"
    fi

    local rs_count
    rs_count=$(get_rs_count "$ns" "app=complex-deploy")
    if [[ "$rs_count" -ge "2" ]]; then
        pass "At least one old ReplicaSet is retained"
    else
        fail_with_cmd "Only $rs_count ReplicaSet(s) found (expected 2 or more)" \
            "kubectl get rs -n $ns -l app=complex-deploy"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Fix complex DaemonSet with taints and affinity ==="
    local name="complex-ds"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! daemonset_exists "$name" "$ns"; then
        fail_with_cmd "DaemonSet $name not found in namespace $ns" \
            "kubectl get daemonset -n $ns"
        return
    fi

    sleep 3

    local desired
    desired=$(get_ds_desired "$name" "$ns")
    if [[ "$desired" == "3" ]]; then
        pass "DaemonSet desires exactly 3 pods"
    else
        fail_with_cmd "DaemonSet desires $desired pods (expected 3)" \
            "kubectl get daemonset $name -n $ns"
    fi

    local ready
    ready=$(get_ds_ready "$name" "$ns")
    if [[ "$ready" == "3" ]]; then
        pass "All 3 pods are Ready"
    else
        fail_with_cmd "Only $ready pods are Ready (expected 3)" \
            "kubectl get daemonset $name -n $ns"
    fi

    local nodes
    nodes=$(get_ds_pod_nodes "$ns" "app=complex-ds")
    local expected_nodes=$'kind-worker\nkind-worker2\nkind-worker3'
    if [[ "$nodes" == "$expected_nodes" ]]; then
        pass "Pods are on the three worker nodes"
    else
        fail_with_cmd "Pods are not on expected nodes" \
            "kubectl get pods -n $ns -l app=complex-ds -o wide"
    fi

    local control_plane_count
    control_plane_count=$(kubectl get pods -n "$ns" -l app=complex-ds -o wide --no-headers 2>/dev/null | grep control-plane | wc -l)
    if [[ "$control_plane_count" == "0" ]]; then
        pass "No pod on the control-plane"
    else
        fail_with_cmd "Found $control_plane_count pods on control-plane (expected 0)" \
            "kubectl get pods -n $ns -l app=complex-ds -o wide | grep control-plane"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Complete application topology with three controllers ==="
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! deployment_exists "fe" "$ns" || ! deployment_exists "be" "$ns" || ! daemonset_exists "log-collector" "$ns"; then
        fail_with_cmd "One or more controllers not found" \
            "kubectl get deployment,daemonset -n $ns"
        return
    fi

    sleep 3

    local fe_ready
    fe_ready=$(get_ready_replicas "fe" "$ns")
    if [[ "$fe_ready" == "3" ]]; then
        pass "Frontend has 3 ready replicas"
    else
        fail_with_cmd "Frontend has $fe_ready ready replicas (expected 3)" \
            "kubectl get deployment fe -n $ns"
    fi

    local be_ready
    be_ready=$(get_ready_replicas "be" "$ns")
    if [[ "$be_ready" == "2" ]]; then
        pass "Backend has 2 ready replicas"
    else
        fail_with_cmd "Backend has $be_ready ready replicas (expected 2)" \
            "kubectl get deployment be -n $ns"
    fi

    local ds_ready
    ds_ready=$(get_ds_ready "log-collector" "$ns")
    if [[ "$ds_ready" == "3" ]]; then
        pass "DaemonSet has 3 ready pods (one per worker)"
    else
        fail_with_cmd "DaemonSet has $ds_ready ready pods (expected 3)" \
            "kubectl get daemonset log-collector -n $ns"
    fi

    # After rollback, fe should be nginx:1.25
    local fe_images
    fe_images=$(kubectl get pods -n "$ns" -l component=frontend -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null)
    if echo "$fe_images" | grep -q "nginx:1.25" && ! echo "$fe_images" | grep -q "nginx:1.26-alpine"; then
        pass "After rollback: frontend pods run nginx:1.25"
    else
        fail_with_cmd "Frontend pods are not running nginx:1.25 after rollback" \
            "kubectl get pods -n $ns -l component=frontend -o jsonpath='{.items[*].spec.containers[0].image}'"
    fi

    # Backend should still be nginx:1.26-alpine (unaffected)
    local be_images
    be_images=$(kubectl get pods -n "$ns" -l component=backend -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null)
    if echo "$be_images" | grep -q "nginx:1.26-alpine" && ! echo "$be_images" | grep -q "nginx:1.25"; then
        pass "Backend pods still run nginx:1.26-alpine (unaffected)"
    else
        fail_with_cmd "Backend pods are not running nginx:1.26-alpine" \
            "kubectl get pods -n $ns -l component=backend -o jsonpath='{.items[*].spec.containers[0].image}'"
    fi

    # DaemonSet should still be busybox:1.36
    local ds_images
    ds_images=$(kubectl get pods -n "$ns" -l component=logging -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null)
    if echo "$ds_images" | grep -q "busybox:1.36"; then
        pass "DaemonSet pods still run busybox:1.36 (unaffected)"
    else
        fail_with_cmd "DaemonSet pods are not running busybox:1.36" \
            "kubectl get pods -n $ns -l component=logging -o jsonpath='{.items[*].spec.containers[0].image}'"
    fi

    local fe_rev_count
    fe_rev_count=$(get_revision_count "fe" "$ns")
    if [[ "$fe_rev_count" -ge "3" ]]; then
        pass "Frontend rollout history has at least 3 revisions"
    else
        fail_with_cmd "Frontend rollout history has $fe_rev_count revisions (expected at least 3)" \
            "kubectl rollout history deployment/fe -n $ns"
    fi

    local be_rev_count
    be_rev_count=$(get_revision_count "be" "$ns")
    if [[ "$be_rev_count" == "1" ]]; then
        pass "Backend rollout history has exactly 1 revision (never updated)"
    else
        fail_with_cmd "Backend rollout history has $be_rev_count revisions (expected 1)" \
            "kubectl rollout history deployment/be -n $ns"
    fi

    local total_pods
    total_pods=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
    if [[ "$total_pods" == "8" ]]; then
        pass "Total pods in namespace: 8 (3 frontend + 2 backend + 3 daemonset)"
    else
        fail_with_cmd "Total pods: $total_pods (expected 8)" \
            "kubectl get pods -n $ns"
    fi

    local fe_selector_count
    fe_selector_count=$(count_pods_with_label "$ns" "app=stack,component=frontend")
    if [[ "$fe_selector_count" == "3" ]]; then
        pass "Frontend selector matches 3 pods only"
    else
        fail_with_cmd "Frontend selector matches $fe_selector_count pods (expected 3)" \
            "kubectl get pods -n $ns -l app=stack,component=frontend"
    fi

    local be_selector_count
    be_selector_count=$(count_pods_with_label "$ns" "app=stack,component=backend")
    if [[ "$be_selector_count" == "2" ]]; then
        pass "Backend selector matches 2 pods only"
    else
        fail_with_cmd "Backend selector matches $be_selector_count pods (expected 2)" \
            "kubectl get pods -n $ns -l app=stack,component=backend"
    fi

    local logging_selector_count
    logging_selector_count=$(count_pods_with_label "$ns" "app=stack,component=logging")
    if [[ "$logging_selector_count" == "3" ]]; then
        pass "Logging selector matches 3 pods only"
    else
        fail_with_cmd "Logging selector matches $logging_selector_count pods (expected 3)" \
            "kubectl get pods -n $ns -l app=stack,component=logging"
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
    echo "# Level 4: Production-Realistic Scenarios"
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
