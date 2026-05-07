#!/usr/bin/env bash
#
# verify.sh - Automated verification for pod-config-injection-homework.md
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

# Helper: get pod ready status
get_ready() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null
}

# Helper: check logs contain string
logs_contain() {
    local pod=$1
    local ns=$2
    local pattern=$3
    local container=${4:-}

    if [[ -n "$container" ]]; then
        kubectl logs "$pod" -n "$ns" -c "$container" 2>/dev/null | grep -q "$pattern"
    else
        kubectl logs "$pod" -n "$ns" 2>/dev/null | grep -q "$pattern"
    fi
}

# Helper: get env var from pod
get_env() {
    local pod=$1
    local ns=$2
    local var=$3
    local container=${4:-}
    local result

    if [[ -n "$container" ]]; then
        result=$(kubectl exec "$pod" -n "$ns" -c "$container" -- env 2>/dev/null | grep "^${var}=" | cut -d= -f2 || echo "")
    else
        result=$(kubectl exec "$pod" -n "$ns" -- env 2>/dev/null | grep "^${var}=" | cut -d= -f2 || echo "")
    fi

    echo "$result"
}

# Helper: get container names
get_container_names() {
    local pod=$1
    local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[*].name}' 2>/dev/null
}

# Helper: check if ConfigMap exists
configmap_exists() {
    local cm=$1
    local ns=$2
    kubectl get configmap "$cm" -n "$ns" &>/dev/null
}

# Helper: check if Secret exists
secret_exists() {
    local secret=$1
    local ns=$2
    kubectl get secret "$secret" -n "$ns" &>/dev/null
}

# Helper: get ConfigMap data key
get_configmap_key() {
    local cm=$1
    local ns=$2
    local key=$3
    kubectl get configmap "$cm" -n "$ns" -o jsonpath="{.data.${key}}" 2>/dev/null
}

# Helper: get Secret data key (base64 decoded)
get_secret_key() {
    local secret=$1
    local ns=$2
    local key=$3
    kubectl get secret "$secret" -n "$ns" -o jsonpath="{.data.${key}}" 2>/dev/null | base64 -d
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: ConfigMap with bulk envFrom ==="
    local cm="app-settings"
    local pod="greeter"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail "ConfigMap $cm not found in namespace $ns"
        return
    fi

    local greeting
    greeting=$(get_configmap_key "$cm" "$ns" "GREETING")
    if [[ "$greeting" == "hello" ]]; then
        pass "ConfigMap key GREETING=hello"
    else
        fail_with_cmd "ConfigMap key GREETING=$greeting (expected hello)" \
            "kubectl -n $ns get configmap $cm -o jsonpath='{.data}'"
    fi

    local audience
    audience=$(get_configmap_key "$cm" "$ns" "AUDIENCE")
    if [[ "$audience" == "world" ]]; then
        pass "ConfigMap key AUDIENCE=world"
    else
        fail_with_cmd "ConfigMap key AUDIENCE=$audience (expected world)" \
            "kubectl -n $ns get configmap $cm -o jsonpath='{.data}'"
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    if logs_contain "$pod" "$ns" "hello, world"; then
        pass "Logs contain 'hello, world'"
    else
        fail_with_cmd "Logs do not contain 'hello, world'" \
            "kubectl -n $ns logs $pod"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Secret with single env var ==="
    local secret="api-creds"
    local pod="api-consumer"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! secret_exists "$secret" "$ns"; then
        fail "Secret $secret not found in namespace $ns"
        return
    fi

    local api_key
    api_key=$(get_secret_key "$secret" "$ns" "API_KEY")
    if [[ "$api_key" == "sk-test-9f8e7d6c5b4a3210" ]]; then
        pass "Secret key API_KEY has correct value"
    else
        fail_with_cmd "Secret key API_KEY=$api_key (expected sk-test-9f8e7d6c5b4a3210)" \
            "kubectl -n $ns get secret $secret -o jsonpath='{.data.API_KEY}' | base64 -d"
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    if logs_contain "$pod" "$ns" "key length: 24"; then
        pass "Logs contain 'key length: 24'"
    else
        fail_with_cmd "Logs do not contain expected output" \
            "kubectl -n $ns logs $pod"
    fi

    local pod_api_key
    pod_api_key=$(get_env "$pod" "$ns" "API_KEY")
    if [[ "$pod_api_key" == "sk-test-9f8e7d6c5b4a3210" ]]; then
        pass "Pod env var API_KEY has correct value"
    else
        fail_with_cmd "Pod env var API_KEY=$pod_api_key" \
            "kubectl -n $ns exec $pod -- printenv API_KEY"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: ConfigMap volume mount ==="
    local cm="server-config"
    local pod="config-reader"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail "ConfigMap $cm not found in namespace $ns"
        return
    fi

    local config
    config=$(get_configmap_key "$cm" "$ns" "server.conf")
    if [[ "$config" == *"listen 0.0.0.0:8080"* ]]; then
        pass "ConfigMap contains server.conf data"
    else
        fail_with_cmd "ConfigMap server.conf data is incorrect" \
            "kubectl -n $ns get configmap $cm -o jsonpath='{.data.server\\.conf}'"
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/server/server.conf 2>/dev/null; then
        pass "File /etc/server/server.conf exists in pod"
    else
        fail_with_cmd "File /etc/server/server.conf not found" \
            "kubectl -n $ns exec $pod -- ls -la /etc/server"
    fi

    if logs_contain "$pod" "$ns" "listen 0.0.0.0:8080"; then
        pass "Logs contain config file contents"
    else
        fail_with_cmd "Logs do not contain expected config" \
            "kubectl -n $ns logs $pod"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: ConfigMap and Secret envFrom ==="
    local cm="web-config"
    local secret="web-creds"
    local pod="web"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail "ConfigMap $cm not found in namespace $ns"
        return
    fi

    if ! secret_exists "$secret" "$ns"; then
        fail "Secret $secret not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    local server_name
    server_name=$(get_env "$pod" "$ns" "SERVER_NAME")
    if [[ "$server_name" == "webapp.example.com" ]]; then
        pass "SERVER_NAME=webapp.example.com"
    else
        fail_with_cmd "SERVER_NAME=$server_name (expected webapp.example.com)" \
            "kubectl -n $ns exec $pod -- printenv SERVER_NAME"
    fi

    local log_level
    log_level=$(get_env "$pod" "$ns" "LOG_LEVEL")
    if [[ "$log_level" == "debug" ]]; then
        pass "LOG_LEVEL=debug"
    else
        fail_with_cmd "LOG_LEVEL=$log_level (expected debug)" \
            "kubectl -n $ns exec $pod -- printenv LOG_LEVEL"
    fi

    local db_user
    db_user=$(get_env "$pod" "$ns" "DB_USER")
    if [[ "$db_user" == "webuser" ]]; then
        pass "DB_USER=webuser"
    else
        fail_with_cmd "DB_USER=$db_user (expected webuser)" \
            "kubectl -n $ns exec $pod -- printenv DB_USER"
    fi

    local db_password
    db_password=$(get_env "$pod" "$ns" "DB_PASSWORD")
    if [[ "$db_password" == "correct-horse-battery-staple" ]]; then
        pass "DB_PASSWORD=correct-horse-battery-staple"
    else
        fail_with_cmd "DB_PASSWORD=$db_password (expected correct-horse-battery-staple)" \
            "kubectl -n $ns exec $pod -- printenv DB_PASSWORD"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Selective ConfigMap volume mount ==="
    local cm="nginx-config"
    local pod="nginx-sel"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail "ConfigMap $cm not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/nginx/selected/default.conf 2>/dev/null; then
        pass "File default.conf exists"
    else
        fail_with_cmd "File default.conf not found" \
            "kubectl -n $ns exec $pod -- ls /etc/nginx/selected"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/nginx/selected/tls.conf 2>/dev/null; then
        pass "File tls.conf exists"
    else
        fail_with_cmd "File tls.conf not found" \
            "kubectl -n $ns exec $pod -- ls /etc/nginx/selected"
    fi

    if kubectl exec "$pod" -n "$ns" -- test ! -f /etc/nginx/selected/proxy.conf 2>/dev/null; then
        pass "File proxy.conf correctly excluded"
    else
        fail "File proxy.conf should not be present"
    fi

    if kubectl exec "$pod" -n "$ns" -- test ! -f /etc/nginx/selected/cache.conf 2>/dev/null; then
        pass "File cache.conf correctly excluded"
    else
        fail "File cache.conf should not be present"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: subPath mount with Secret env var ==="
    local cm="app-config"
    local secret="app-secret"
    local pod="app-pod"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail "ConfigMap $cm not found in namespace $ns"
        return
    fi

    if ! secret_exists "$secret" "$ns"; then
        fail "Secret $secret not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/nginx/app.yaml 2>/dev/null; then
        pass "File /etc/nginx/app.yaml exists"
    else
        fail_with_cmd "File /etc/nginx/app.yaml not found" \
            "kubectl -n $ns exec $pod -- ls /etc/nginx"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/nginx/nginx.conf 2>/dev/null; then
        pass "Original nginx.conf still exists (not shadowed)"
    else
        fail_with_cmd "nginx.conf was shadowed by volume mount" \
            "kubectl -n $ns exec $pod -- ls /etc/nginx"
    fi

    local app_token
    app_token=$(get_env "$pod" "$ns" "APP_TOKEN")
    if [[ "$app_token" == "tok-abc-123-xyz-789" ]]; then
        pass "APP_TOKEN=tok-abc-123-xyz-789"
    else
        fail_with_cmd "APP_TOKEN=$app_token (expected tok-abc-123-xyz-789)" \
            "kubectl -n $ns exec $pod -- printenv APP_TOKEN"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug ConfigMap key mismatch ==="
    local pod="billing"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns describe pod $pod | grep -A5 Events"
        return
    fi

    local app_name
    app_name=$(get_env "$pod" "$ns" "APP_NAME")
    if [[ "$app_name" == "billing" ]]; then
        pass "APP_NAME=billing"
    else
        fail_with_cmd "APP_NAME=$app_name (expected billing)" \
            "kubectl -n $ns exec $pod -- printenv APP_NAME"
    fi

    local app_env
    app_env=$(get_env "$pod" "$ns" "APP_ENV")
    if [[ "$app_env" == "prod" ]]; then
        pass "APP_ENV=prod"
    else
        fail_with_cmd "APP_ENV=$app_env (expected prod)" \
            "kubectl -n $ns exec $pod -- printenv APP_ENV"
    fi

    local max_conns
    max_conns=$(get_env "$pod" "$ns" "MAX_CONNS")
    if [[ "$max_conns" == "100" ]]; then
        pass "MAX_CONNS=100"
    else
        fail_with_cmd "MAX_CONNS=$max_conns (expected 100)" \
            "kubectl -n $ns exec $pod -- printenv MAX_CONNS"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug Secret base64 encoding ==="
    local secret="app-secret"
    local pod="consumer"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! secret_exists "$secret" "$ns"; then
        fail "Secret $secret not found in namespace $ns (may be part of the issue)"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns describe pod $pod | grep -A5 Events"
        return
    fi

    local db_url
    db_url=$(get_env "$pod" "$ns" "DATABASE_URL")
    if [[ "$db_url" == "postgres://user:pass@db.internal:5432/billing" ]]; then
        pass "DATABASE_URL has correct decoded value"
    else
        fail_with_cmd "DATABASE_URL=$db_url (expected postgres://user:pass@db.internal:5432/billing)" \
            "kubectl -n $ns exec $pod -- printenv DATABASE_URL"
    fi

    local api_token
    api_token=$(get_env "$pod" "$ns" "API_TOKEN")
    if [[ "$api_token" == "tok-42069" ]]; then
        pass "API_TOKEN=tok-42069"
    else
        fail_with_cmd "API_TOKEN=$api_token (expected tok-42069)" \
            "kubectl -n $ns exec $pod -- printenv API_TOKEN"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug volume items path ==="
    local pod="filereader"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns (may be part of the issue)"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/app/main.conf 2>/dev/null; then
        pass "File /etc/app/main.conf exists"
    else
        fail_with_cmd "File /etc/app/main.conf not found" \
            "kubectl -n $ns exec $pod -- ls /etc/app"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/app/logs.conf 2>/dev/null; then
        pass "File /etc/app/logs.conf exists"
    else
        fail_with_cmd "File /etc/app/logs.conf not found" \
            "kubectl -n $ns exec $pod -- ls /etc/app"
    fi

    if logs_contain "$pod" "$ns" "mode=production"; then
        pass "Logs contain main.conf contents"
    else
        fail_with_cmd "Logs missing expected config" \
            "kubectl -n $ns logs $pod"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Nginx conf.d pattern ==="
    local cm="nginx-sites"
    local pod="nginx-pod"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail "ConfigMap $cm not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 5

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/nginx/conf.d/default.conf 2>/dev/null; then
        pass "File default.conf exists"
    else
        fail_with_cmd "File default.conf not found" \
            "kubectl -n $ns exec $pod -- ls /etc/nginx/conf.d"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/nginx/conf.d/api.conf 2>/dev/null; then
        pass "File api.conf exists"
    else
        fail_with_cmd "File api.conf not found" \
            "kubectl -n $ns exec $pod -- ls /etc/nginx/conf.d"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/nginx/conf.d/admin.conf 2>/dev/null; then
        pass "File admin.conf exists"
    else
        fail_with_cmd "File admin.conf not found" \
            "kubectl -n $ns exec $pod -- ls /etc/nginx/conf.d"
    fi

    local restart_count
    restart_count=$(kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.containerStatuses[0].restartCount}' 2>/dev/null)
    if [[ "$restart_count" == "0" ]]; then
        pass "Container has not restarted (restart count: 0)"
    else
        fail "Container restart count is $restart_count (expected 0)"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Projected volume ==="
    local cm="app-cfg"
    local secret="app-secrets"
    local pod="app"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail "ConfigMap $cm not found in namespace $ns"
        return
    fi

    if ! secret_exists "$secret" "$ns"; then
        fail "Secret $secret not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/app/config/app.yaml 2>/dev/null; then
        pass "File /etc/app/config/app.yaml exists"
    else
        fail_with_cmd "File /etc/app/config/app.yaml not found" \
            "kubectl -n $ns exec $pod -- find /etc/app -type f"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/app/secrets/db-password 2>/dev/null; then
        pass "File /etc/app/secrets/db-password exists"
    else
        fail_with_cmd "File /etc/app/secrets/db-password not found" \
            "kubectl -n $ns exec $pod -- find /etc/app -type f"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/app/secrets/api-key 2>/dev/null; then
        pass "File /etc/app/secrets/api-key exists"
    else
        fail_with_cmd "File /etc/app/secrets/api-key not found" \
            "kubectl -n $ns exec $pod -- find /etc/app -type f"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/app/pod/name 2>/dev/null; then
        pass "File /etc/app/pod/name exists"
    else
        fail_with_cmd "File /etc/app/pod/name not found" \
            "kubectl -n $ns exec $pod -- find /etc/app -type f"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/app/pod/namespace 2>/dev/null; then
        pass "File /etc/app/pod/namespace exists"
    else
        fail_with_cmd "File /etc/app/pod/namespace not found" \
            "kubectl -n $ns exec $pod -- find /etc/app -type f"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/app/pod/labels 2>/dev/null; then
        pass "File /etc/app/pod/labels exists"
    else
        fail_with_cmd "File /etc/app/pod/labels not found" \
            "kubectl -n $ns exec $pod -- find /etc/app -type f"
    fi

    local log_level
    log_level=$(get_env "$pod" "$ns" "LOG_LEVEL")
    if [[ "$log_level" == "info" ]]; then
        pass "LOG_LEVEL=info"
    else
        fail_with_cmd "LOG_LEVEL=$log_level (expected info)" \
            "kubectl -n $ns exec $pod -- printenv LOG_LEVEL"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Multi-container selective mounts ==="
    local cm="shared-cfg"
    local pod="duo"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail "ConfigMap $cm not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    local containers
    containers=$(get_container_names "$pod" "$ns")
    if [[ "$containers" == *"writer"* ]] && [[ "$containers" == *"reader"* ]]; then
        pass "Two containers: writer and reader"
    else
        fail "Container names: $containers (expected writer and reader)"
    fi

    if kubectl exec "$pod" -n "$ns" -c writer -- test -f /etc/writer/role.conf 2>/dev/null; then
        pass "Writer: role.conf exists"
    else
        fail_with_cmd "Writer: role.conf not found" \
            "kubectl -n $ns exec $pod -c writer -- ls /etc/writer"
    fi

    if kubectl exec "$pod" -n "$ns" -c writer -- test -f /etc/writer/common.conf 2>/dev/null; then
        pass "Writer: common.conf exists"
    else
        fail_with_cmd "Writer: common.conf not found" \
            "kubectl -n $ns exec $pod -c writer -- ls /etc/writer"
    fi

    if kubectl exec "$pod" -n "$ns" -c reader -- test -f /etc/reader/role.conf 2>/dev/null; then
        pass "Reader: role.conf exists"
    else
        fail_with_cmd "Reader: role.conf not found" \
            "kubectl -n $ns exec $pod -c reader -- ls /etc/reader"
    fi

    if kubectl exec "$pod" -n "$ns" -c reader -- test -f /etc/reader/common.conf 2>/dev/null; then
        pass "Reader: common.conf exists"
    else
        fail_with_cmd "Reader: common.conf not found" \
            "kubectl -n $ns exec $pod -c reader -- ls /etc/reader"
    fi

    if kubectl exec "$pod" -n "$ns" -c writer -- test ! -f /etc/writer/unused.conf 2>/dev/null; then
        pass "Writer: unused.conf correctly excluded"
    else
        fail "Writer: unused.conf should not be present"
    fi

    if kubectl exec "$pod" -n "$ns" -c reader -- test ! -f /etc/reader/writer.conf 2>/dev/null; then
        pass "Reader: writer.conf correctly excluded"
    else
        fail "Reader: writer.conf should not be present"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Multiple issues (immutable, base64, conflict) ==="
    local cm="runtime-cfg"
    local secret="runtime-creds"
    local pod="runtime"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "$cm" "$ns"; then
        fail "ConfigMap $cm not found in namespace $ns"
        return
    fi

    local mode
    mode=$(get_configmap_key "$cm" "$ns" "mode")
    if [[ "$mode" == "production" ]]; then
        pass "ConfigMap mode=production"
    else
        fail_with_cmd "ConfigMap mode=$mode (expected production)" \
            "kubectl -n $ns get configmap $cm -o jsonpath='{.data.mode}'"
    fi

    if ! secret_exists "$secret" "$ns"; then
        fail "Secret $secret not found in namespace $ns"
        return
    fi

    local username
    username=$(get_secret_key "$secret" "$ns" "username")
    if [[ "$username" == "operator" ]]; then
        pass "Secret username=operator"
    else
        fail_with_cmd "Secret username=$username (expected operator)" \
            "kubectl -n $ns get secret $secret -o jsonpath='{.data.username}' | base64 -d"
    fi

    local password
    password=$(get_secret_key "$secret" "$ns" "password")
    if [[ "$password" == "s3cret-pw" ]]; then
        pass "Secret password=s3cret-pw"
    else
        fail_with_cmd "Secret password=$password (expected s3cret-pw)" \
            "kubectl -n $ns get secret $secret -o jsonpath='{.data.password}' | base64 -d"
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns describe pod $pod | grep -A5 Events"
        return
    fi

    if logs_contain "$pod" "$ns" "MODE=production"; then
        pass "Logs contain MODE=production"
    else
        fail_with_cmd "Logs missing expected output" \
            "kubectl -n $ns logs $pod"
    fi

    if logs_contain "$pod" "$ns" "USER=operator"; then
        pass "Logs contain USER=operator"
    else
        fail_with_cmd "Logs missing expected output" \
            "kubectl -n $ns logs $pod"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Projected volume issues (absolute path, duplicate) ==="
    local pod="combined"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns (may be part of the issue)"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running (issue fixed)"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/combined/app.properties 2>/dev/null; then
        pass "File /etc/combined/app.properties exists"
    else
        fail_with_cmd "File /etc/combined/app.properties not found" \
            "kubectl -n $ns exec $pod -- ls /etc/combined"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/combined/region 2>/dev/null; then
        pass "File /etc/combined/region exists"
    else
        fail_with_cmd "File /etc/combined/region not found" \
            "kubectl -n $ns exec $pod -- ls /etc/combined"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/combined/db-password 2>/dev/null; then
        pass "File /etc/combined/db-password exists"
    else
        fail_with_cmd "File /etc/combined/db-password not found" \
            "kubectl -n $ns exec $pod -- ls /etc/combined"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/combined/api-token 2>/dev/null; then
        pass "File /etc/combined/api-token exists"
    else
        fail_with_cmd "File /etc/combined/api-token not found" \
            "kubectl -n $ns exec $pod -- ls /etc/combined"
    fi

    local file_count
    file_count=$(kubectl exec "$pod" -n "$ns" -- sh -c 'ls /etc/combined | wc -l' 2>/dev/null)
    if [[ "$file_count" == "4" ]]; then
        pass "Exactly 4 files in /etc/combined"
    else
        fail_with_cmd "Found $file_count files (expected 4)" \
            "kubectl -n $ns exec $pod -- ls /etc/combined"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Three-tier comprehensive configuration ==="
    local pod="orders-web"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! configmap_exists "base-config" "$ns"; then
        fail "ConfigMap base-config not found in namespace $ns"
        return
    fi

    if ! configmap_exists "env-overrides-prod" "$ns"; then
        fail "ConfigMap env-overrides-prod not found in namespace $ns"
        return
    fi

    if ! configmap_exists "component-web" "$ns"; then
        fail "ConfigMap component-web not found in namespace $ns"
        return
    fi

    if ! secret_exists "creds-db" "$ns"; then
        fail "Secret creds-db not found in namespace $ns"
        return
    fi

    if ! secret_exists "creds-external-api" "$ns"; then
        fail "Secret creds-external-api not found in namespace $ns"
        return
    fi

    if ! pod_exists "$pod" "$ns"; then
        fail "Pod $pod not found in namespace $ns"
        return
    fi

    sleep 3

    local phase
    phase=$(get_phase "$pod" "$ns")
    if [[ "$phase" == "Running" ]]; then
        pass "Pod phase is Running"
    else
        fail_with_cmd "Pod phase is $phase (expected Running)" \
            "kubectl -n $ns get pod $pod -o jsonpath='{.status.phase}'"
        return
    fi

    local app_name
    app_name=$(get_env "$pod" "$ns" "APP_NAME")
    if [[ "$app_name" == "orders" ]]; then
        pass "APP_NAME=orders"
    else
        fail_with_cmd "APP_NAME=$app_name (expected orders)" \
            "kubectl -n $ns exec $pod -- printenv APP_NAME"
    fi

    local region
    region=$(get_env "$pod" "$ns" "REGION")
    if [[ "$region" == "us-east-1" ]]; then
        pass "REGION=us-east-1"
    else
        fail_with_cmd "REGION=$region (expected us-east-1)" \
            "kubectl -n $ns exec $pod -- printenv REGION"
    fi

    local log_level
    log_level=$(get_env "$pod" "$ns" "LOG_LEVEL")
    if [[ "$log_level" == "warn" ]]; then
        pass "LOG_LEVEL=warn"
    else
        fail_with_cmd "LOG_LEVEL=$log_level (expected warn)" \
            "kubectl -n $ns exec $pod -- printenv LOG_LEVEL"
    fi

    local workers
    workers=$(get_env "$pod" "$ns" "WORKERS")
    if [[ "$workers" == "16" ]]; then
        pass "WORKERS=16"
    else
        fail_with_cmd "WORKERS=$workers (expected 16)" \
            "kubectl -n $ns exec $pod -- printenv WORKERS"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/orders/web/web.yaml 2>/dev/null; then
        pass "File /etc/orders/web/web.yaml exists"
    else
        fail_with_cmd "File /etc/orders/web/web.yaml not found" \
            "kubectl -n $ns exec $pod -- find /etc/orders -type f"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/orders/secrets/db/username 2>/dev/null; then
        pass "File /etc/orders/secrets/db/username exists"
    else
        fail_with_cmd "File /etc/orders/secrets/db/username not found" \
            "kubectl -n $ns exec $pod -- find /etc/orders -type f"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/orders/secrets/db/password 2>/dev/null; then
        pass "File /etc/orders/secrets/db/password exists"
    else
        fail_with_cmd "File /etc/orders/secrets/db/password not found" \
            "kubectl -n $ns exec $pod -- find /etc/orders -type f"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/orders/secrets/external-api/token 2>/dev/null; then
        pass "File /etc/orders/secrets/external-api/token exists"
    else
        fail_with_cmd "File /etc/orders/secrets/external-api/token not found" \
            "kubectl -n $ns exec $pod -- find /etc/orders -type f"
    fi

    if kubectl exec "$pod" -n "$ns" -- test -f /etc/orders/pod/labels 2>/dev/null; then
        pass "File /etc/orders/pod/labels exists"
    else
        fail_with_cmd "File /etc/orders/pod/labels not found" \
            "kubectl -n $ns exec $pod -- find /etc/orders -type f"
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
