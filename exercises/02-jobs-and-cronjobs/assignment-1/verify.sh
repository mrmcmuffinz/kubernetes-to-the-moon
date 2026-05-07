#!/usr/bin/env bash
#
# verify.sh - Automated verification for jobs-and-cronjobs-homework.md
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

# Helper: check if job exists
job_exists() {
    local job=$1
    local ns=$2
    kubectl get job "$job" -n "$ns" &>/dev/null
}

# Helper: check if cronjob exists
cronjob_exists() {
    local cj=$1
    local ns=$2
    kubectl get cronjob "$cj" -n "$ns" &>/dev/null
}

# Helper: get job condition status
get_job_condition() {
    local job=$1
    local ns=$2
    local condition=$3
    kubectl get job "$job" -n "$ns" -o jsonpath="{.status.conditions[?(@.type==\"$condition\")].status}" 2>/dev/null
}

# Helper: get job condition reason
get_job_condition_reason() {
    local job=$1
    local ns=$2
    local condition=$3
    kubectl get job "$job" -n "$ns" -o jsonpath="{.status.conditions[?(@.type==\"$condition\")].reason}" 2>/dev/null
}

# Helper: get job succeeded count
get_job_succeeded() {
    local job=$1
    local ns=$2
    kubectl get job "$job" -n "$ns" -o jsonpath='{.status.succeeded}' 2>/dev/null
}

# Helper: get job failed count
get_job_failed() {
    local job=$1
    local ns=$2
    kubectl get job "$job" -n "$ns" -o jsonpath='{.status.failed}' 2>/dev/null
}

# Helper: get job spec field
get_job_spec() {
    local job=$1
    local ns=$2
    local field=$3
    kubectl get job "$job" -n "$ns" -o jsonpath="{.spec.$field}" 2>/dev/null
}

# Helper: get cronjob spec field
get_cronjob_spec() {
    local cj=$1
    local ns=$2
    local field=$3
    kubectl get cronjob "$cj" -n "$ns" -o jsonpath="{.spec.$field}" 2>/dev/null
}

# Helper: get container image from job
get_job_image() {
    local job=$1
    local ns=$2
    kubectl get job "$job" -n "$ns" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null
}

# Helper: get container image from cronjob
get_cronjob_image() {
    local cj=$1
    local ns=$2
    kubectl get cronjob "$cj" -n "$ns" -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}' 2>/dev/null
}

# Helper: get restart policy from job
get_job_restart_policy() {
    local job=$1
    local ns=$2
    kubectl get job "$job" -n "$ns" -o jsonpath='{.spec.template.spec.restartPolicy}' 2>/dev/null
}

# Helper: get restart policy from cronjob
get_cronjob_restart_policy() {
    local cj=$1
    local ns=$2
    kubectl get cronjob "$cj" -n "$ns" -o jsonpath='{.spec.jobTemplate.spec.template.spec.restartPolicy}' 2>/dev/null
}

# Helper: count pods for a job
count_job_pods() {
    local job=$1
    local ns=$2
    kubectl get pods -n "$ns" -l batch.kubernetes.io/job-name="$job" --no-headers 2>/dev/null | wc -l
}

# Helper: get logs from all job pods
get_job_logs() {
    local job=$1
    local ns=$2
    kubectl logs -n "$ns" -l batch.kubernetes.io/job-name="$job" --tail=-1 2>/dev/null
}

# Helper: count Jobs created by CronJob
count_cronjob_jobs() {
    local cj=$1
    local ns=$2
    kubectl get jobs -n "$ns" -l batch.kubernetes.io/cronjob-name="$cj" --no-headers 2>/dev/null | wc -l
}

# Helper: get cronjob last schedule time
get_cronjob_last_schedule() {
    local cj=$1
    local ns=$2
    kubectl get cronjob "$cj" -n "$ns" -o jsonpath='{.status.lastScheduleTime}' 2>/dev/null
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic Job completion ==="
    local job="greeter"
    local ns="ex-1-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! job_exists "$job" "$ns"; then
        fail_with_cmd "Job $job not found in namespace $ns" \
            "kubectl get jobs -n $ns"
        return
    fi

    # Wait a few seconds for completion
    sleep 5

    local complete_status
    complete_status=$(get_job_condition "$job" "$ns" "Complete")
    if [[ "$complete_status" == "True" ]]; then
        pass "Job reached Complete condition"
    else
        fail_with_cmd "Job Complete condition is not True" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.conditions}'"
    fi

    local succeeded
    succeeded=$(get_job_succeeded "$job" "$ns")
    if [[ "$succeeded" == "1" ]]; then
        pass "Job has 1 successful completion"
    else
        fail_with_cmd "Job succeeded count is $succeeded (expected 1)" \
            "kubectl get job $job -n $ns -o jsonpath='{.status}'"
    fi

    local logs
    logs=$(get_job_logs "$job" "$ns")
    if echo "$logs" | grep -q "hello from homework"; then
        pass "Logs contain 'hello from homework'"
    else
        fail_with_cmd "Logs do not contain 'hello from homework'" \
            "kubectl logs -l batch.kubernetes.io/job-name=$job -n $ns"
    fi

    local restart_policy
    restart_policy=$(get_job_restart_policy "$job" "$ns")
    if [[ "$restart_policy" == "Never" ]] || [[ "$restart_policy" == "OnFailure" ]]; then
        pass "Restart policy is $restart_policy"
    else
        fail_with_cmd "Restart policy is $restart_policy (expected Never or OnFailure)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.template.spec.restartPolicy}'"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Backoff limit ==="
    local job="retrier"
    local ns="ex-1-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! job_exists "$job" "$ns"; then
        fail_with_cmd "Job $job not found in namespace $ns" \
            "kubectl get jobs -n $ns"
        return
    fi

    info "Waiting for backoff retries to complete (up to 120s)..."
    sleep 120

    local failed_status
    failed_status=$(get_job_condition "$job" "$ns" "Failed")
    if [[ "$failed_status" == "True" ]]; then
        pass "Job reached Failed condition"
    else
        fail_with_cmd "Job Failed condition is not True" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.conditions}'"
    fi

    local failed_reason
    failed_reason=$(get_job_condition_reason "$job" "$ns" "Failed")
    if [[ "$failed_reason" == "BackoffLimitExceeded" ]]; then
        pass "Failed reason is BackoffLimitExceeded"
    else
        fail_with_cmd "Failed reason is $failed_reason (expected BackoffLimitExceeded)" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.conditions[?(@.type==\"Failed\")]}'"
    fi

    local backoff_limit
    backoff_limit=$(get_job_spec "$job" "$ns" "backoffLimit")
    if [[ "$backoff_limit" == "2" ]]; then
        pass "backoffLimit is 2"
    else
        fail_with_cmd "backoffLimit is $backoff_limit (expected 2)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.backoffLimit}'"
    fi

    local pod_count
    pod_count=$(count_job_pods "$job" "$ns")
    if [[ "$pod_count" == "3" ]]; then
        pass "Exactly 3 failed pods exist"
    else
        fail_with_cmd "$pod_count pods found (expected 3)" \
            "kubectl get pods -n $ns -l batch.kubernetes.io/job-name=$job"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: CronJob with @hourly schedule ==="
    local cj="hourly-tick"
    local ns="ex-1-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cronjob_exists "$cj" "$ns"; then
        fail_with_cmd "CronJob $cj not found in namespace $ns" \
            "kubectl get cronjobs -n $ns"
        return
    fi

    local schedule
    schedule=$(get_cronjob_spec "$cj" "$ns" "schedule")
    if [[ "$schedule" == "@hourly" ]]; then
        pass "Schedule is @hourly"
    else
        fail_with_cmd "Schedule is $schedule (expected @hourly)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.schedule}'"
    fi

    local image
    image=$(get_cronjob_image "$cj" "$ns")
    if [[ "$image" == "busybox:1.36" ]]; then
        pass "Image is busybox:1.36"
    else
        fail_with_cmd "Image is $image (expected busybox:1.36)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'"
    fi

    local restart_policy
    restart_policy=$(get_cronjob_restart_policy "$cj" "$ns")
    if [[ "$restart_policy" == "Never" ]] || [[ "$restart_policy" == "OnFailure" ]]; then
        pass "Restart policy is $restart_policy"
    else
        fail_with_cmd "Restart policy is $restart_policy (expected Never or OnFailure)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.jobTemplate.spec.template.spec.restartPolicy}'"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Parallel Job with completions ==="
    local job="parallel-adder"
    local ns="ex-2-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! job_exists "$job" "$ns"; then
        fail_with_cmd "Job $job not found in namespace $ns" \
            "kubectl get jobs -n $ns"
        return
    fi

    info "Waiting for Job to complete (up to 120s)..."
    kubectl wait --for=condition=Complete job/"$job" -n "$ns" --timeout=120s &>/dev/null || true
    sleep 5

    local succeeded
    succeeded=$(get_job_succeeded "$job" "$ns")
    if [[ "$succeeded" == "6" ]]; then
        pass "Job has 6 successful completions"
    else
        fail_with_cmd "Job succeeded count is $succeeded (expected 6)" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.succeeded}'"
    fi

    local parallelism
    parallelism=$(get_job_spec "$job" "$ns" "parallelism")
    if [[ "$parallelism" == "3" ]]; then
        pass "Parallelism is 3"
    else
        fail_with_cmd "Parallelism is $parallelism (expected 3)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.parallelism}'"
    fi

    local pod_count
    pod_count=$(count_job_pods "$job" "$ns")
    if [[ "$pod_count" == "6" ]]; then
        pass "6 total pods created"
    else
        fail_with_cmd "$pod_count pods found (expected 6)" \
            "kubectl get pods -n $ns -l batch.kubernetes.io/job-name=$job"
    fi

    local log_count
    log_count=$(get_job_logs "$job" "$ns" | grep -c "worker ready" || echo "0")
    if [[ "$log_count" == "6" ]]; then
        pass "All 6 pods logged 'worker ready'"
    else
        fail_with_cmd "Found $log_count 'worker ready' lines (expected 6)" \
            "kubectl logs -n $ns -l batch.kubernetes.io/job-name=$job --tail=-1 | grep 'worker ready'"
    fi
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Indexed completion mode ==="
    local job="shardwork"
    local ns="ex-2-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! job_exists "$job" "$ns"; then
        fail_with_cmd "Job $job not found in namespace $ns" \
            "kubectl get jobs -n $ns"
        return
    fi

    info "Waiting for Job to complete (up to 120s)..."
    kubectl wait --for=condition=Complete job/"$job" -n "$ns" --timeout=120s &>/dev/null || true
    sleep 5

    local succeeded
    succeeded=$(get_job_succeeded "$job" "$ns")
    if [[ "$succeeded" == "4" ]]; then
        pass "Job has 4 successful completions"
    else
        fail_with_cmd "Job succeeded count is $succeeded (expected 4)" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.succeeded}'"
    fi

    local completion_mode
    completion_mode=$(get_job_spec "$job" "$ns" "completionMode")
    if [[ "$completion_mode" == "Indexed" ]]; then
        pass "Completion mode is Indexed"
    else
        fail_with_cmd "Completion mode is $completion_mode (expected Indexed)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.completionMode}'"
    fi

    # Check each shard logged its index
    local all_shards_ok=true
    for i in 0 1 2 3; do
        local shard_log
        shard_log=$(kubectl logs -n "$ns" -l batch.kubernetes.io/job-completion-index="$i" --tail=1 2>/dev/null || echo "")
        if ! echo "$shard_log" | grep -q "processing shard $i"; then
            all_shards_ok=false
            break
        fi
    done

    if [[ "$all_shards_ok" == "true" ]]; then
        pass "All shards logged their index"
    else
        fail_with_cmd "Not all shards logged correctly" \
            "for i in 0 1 2 3; do kubectl logs -n $ns -l batch.kubernetes.io/job-completion-index=\$i --tail=1; done"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: CronJob with policies and history limits ==="
    local cj="trimmed-nightly"
    local ns="ex-2-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cronjob_exists "$cj" "$ns"; then
        fail_with_cmd "CronJob $cj not found in namespace $ns" \
            "kubectl get cronjobs -n $ns"
        return
    fi

    local schedule
    schedule=$(get_cronjob_spec "$cj" "$ns" "schedule")
    if [[ "$schedule" == "@daily" ]]; then
        pass "Schedule is @daily"
    else
        fail_with_cmd "Schedule is $schedule (expected @daily)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.schedule}'"
    fi

    local concurrency_policy
    concurrency_policy=$(get_cronjob_spec "$cj" "$ns" "concurrencyPolicy")
    if [[ "$concurrency_policy" == "Forbid" ]]; then
        pass "Concurrency policy is Forbid"
    else
        fail_with_cmd "Concurrency policy is $concurrency_policy (expected Forbid)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.concurrencyPolicy}'"
    fi

    local success_limit
    success_limit=$(get_cronjob_spec "$cj" "$ns" "successfulJobsHistoryLimit")
    if [[ "$success_limit" == "2" ]]; then
        pass "Successful jobs history limit is 2"
    else
        fail_with_cmd "Successful jobs history limit is $success_limit (expected 2)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.successfulJobsHistoryLimit}'"
    fi

    local failed_limit
    failed_limit=$(get_cronjob_spec "$cj" "$ns" "failedJobsHistoryLimit")
    if [[ "$failed_limit" == "0" ]]; then
        pass "Failed jobs history limit is 0"
    else
        fail_with_cmd "Failed jobs history limit is $failed_limit (expected 0)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.failedJobsHistoryLimit}'"
    fi
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Debug restartPolicy ==="
    local job="broken-1"
    local ns="ex-3-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! job_exists "$job" "$ns"; then
        fail_with_cmd "Job $job not found in namespace $ns" \
            "kubectl get jobs -n $ns"
        return
    fi

    sleep 5

    local complete_status
    complete_status=$(get_job_condition "$job" "$ns" "Complete")
    if [[ "$complete_status" == "True" ]]; then
        pass "Job reached Complete condition (issue fixed)"
    else
        fail_with_cmd "Job did not reach Complete condition" \
            "kubectl describe job $job -n $ns"
    fi

    local succeeded
    succeeded=$(get_job_succeeded "$job" "$ns")
    if [[ "$succeeded" == "1" ]]; then
        pass "Job has 1 successful completion"
    else
        fail_with_cmd "Job succeeded count is $succeeded (expected 1)" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.succeeded}'"
    fi

    local restart_policy
    restart_policy=$(get_job_restart_policy "$job" "$ns")
    if [[ "$restart_policy" == "Never" ]] || [[ "$restart_policy" == "OnFailure" ]]; then
        pass "Restart policy is now $restart_policy"
    else
        fail_with_cmd "Restart policy is $restart_policy (expected Never or OnFailure)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.template.spec.restartPolicy}'"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Debug invalid cron schedule ==="
    local cj="broken-2"
    local ns="ex-3-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cronjob_exists "$cj" "$ns"; then
        fail_with_cmd "CronJob $cj not found in namespace $ns" \
            "kubectl get cronjobs -n $ns"
        return
    fi

    local schedule
    schedule=$(get_cronjob_spec "$cj" "$ns" "schedule")
    if [[ "$schedule" == "*/5 * * * *" ]]; then
        pass "Schedule is */5 * * * * (every 5 minutes)"
    else
        fail_with_cmd "Schedule is $schedule (expected */5 * * * *)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.schedule}'"
    fi

    local image
    image=$(get_cronjob_image "$cj" "$ns")
    if [[ "$image" == "busybox:1.36" ]]; then
        pass "Image is busybox:1.36"
    else
        fail_with_cmd "Image is $image (expected busybox:1.36)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Debug activeDeadlineSeconds ==="
    local job="broken-3"
    local ns="ex-3-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! job_exists "$job" "$ns"; then
        fail_with_cmd "Job $job not found in namespace $ns" \
            "kubectl get jobs -n $ns"
        return
    fi

    info "Waiting for Job to complete (up to 25s)..."
    sleep 25

    local complete_status
    complete_status=$(get_job_condition "$job" "$ns" "Complete")
    if [[ "$complete_status" == "True" ]]; then
        pass "Job reached Complete condition"
    else
        fail_with_cmd "Job did not reach Complete condition" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.conditions}'"
    fi

    local succeeded
    succeeded=$(get_job_succeeded "$job" "$ns")
    if [[ "$succeeded" == "1" ]]; then
        pass "Job has 1 successful completion"
    else
        fail_with_cmd "Job succeeded count is $succeeded (expected 1)" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.succeeded}'"
    fi

    local logs
    logs=$(get_job_logs "$job" "$ns")
    if echo "$logs" | grep -q "starting" && echo "$logs" | grep -q "finished"; then
        pass "Logs contain both 'starting' and 'finished'"
    else
        fail_with_cmd "Logs missing 'starting' or 'finished'" \
            "kubectl logs -n $ns -l batch.kubernetes.io/job-name=$job --tail=-1"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Shard-map with TTL ==="
    local job="shard-map"
    local ns="ex-4-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! job_exists "$job" "$ns"; then
        fail_with_cmd "Job $job not found in namespace $ns" \
            "kubectl get jobs -n $ns"
        return
    fi

    info "Waiting for Job to complete (up to 120s)..."
    kubectl wait --for=condition=Complete job/"$job" -n "$ns" --timeout=120s &>/dev/null || true
    sleep 5

    local completions
    completions=$(get_job_spec "$job" "$ns" "completions")
    if [[ "$completions" == "5" ]]; then
        pass "Completions is 5"
    else
        fail_with_cmd "Completions is $completions (expected 5)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.completions}'"
    fi

    local parallelism
    parallelism=$(get_job_spec "$job" "$ns" "parallelism")
    if [[ "$parallelism" == "5" ]]; then
        pass "Parallelism is 5"
    else
        fail_with_cmd "Parallelism is $parallelism (expected 5)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.parallelism}'"
    fi

    local completion_mode
    completion_mode=$(get_job_spec "$job" "$ns" "completionMode")
    if [[ "$completion_mode" == "Indexed" ]]; then
        pass "Completion mode is Indexed"
    else
        fail_with_cmd "Completion mode is $completion_mode (expected Indexed)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.completionMode}'"
    fi

    local backoff_limit
    backoff_limit=$(get_job_spec "$job" "$ns" "backoffLimit")
    if [[ "$backoff_limit" == "0" ]]; then
        pass "backoffLimit is 0"
    else
        fail_with_cmd "backoffLimit is $backoff_limit (expected 0)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.backoffLimit}'"
    fi

    local ttl
    ttl=$(get_job_spec "$job" "$ns" "ttlSecondsAfterFinished")
    if [[ "$ttl" == "300" ]]; then
        pass "ttlSecondsAfterFinished is 300"
    else
        fail_with_cmd "ttlSecondsAfterFinished is $ttl (expected 300)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.ttlSecondsAfterFinished}'"
    fi

    local succeeded
    succeeded=$(get_job_succeeded "$job" "$ns")
    if [[ "$succeeded" == "5" ]]; then
        pass "Job has 5 successful completions"
    else
        fail_with_cmd "Job succeeded count is $succeeded (expected 5)" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.succeeded}'"
    fi

    # Check all shards logged
    local logs
    logs=$(get_job_logs "$job" "$ns")
    local unique_count
    unique_count=$(echo "$logs" | grep -E "^shard [0-4] of 5 processed$" | sort -u | wc -l || echo "0")
    if [[ "$unique_count" == "5" ]]; then
        pass "All 5 shards logged their messages"
    else
        fail_with_cmd "Found $unique_count unique shard messages (expected 5)" \
            "kubectl logs -n $ns -l batch.kubernetes.io/job-name=$job --tail=-1 | grep 'shard.*processed'"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: Daily backup CronJob ==="
    local cj="daily-backup"
    local ns="ex-4-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cronjob_exists "$cj" "$ns"; then
        fail_with_cmd "CronJob $cj not found in namespace $ns" \
            "kubectl get cronjobs -n $ns"
        return
    fi

    local schedule
    schedule=$(get_cronjob_spec "$cj" "$ns" "schedule")
    if [[ "$schedule" == "@daily" ]]; then
        pass "Schedule is @daily"
    else
        fail_with_cmd "Schedule is $schedule (expected @daily)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.schedule}'"
    fi

    local timezone
    timezone=$(get_cronjob_spec "$cj" "$ns" "timeZone")
    if [[ "$timezone" == "America/Los_Angeles" ]]; then
        pass "Time zone is America/Los_Angeles"
    else
        fail_with_cmd "Time zone is $timezone (expected America/Los_Angeles)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.timeZone}'"
    fi

    local concurrency_policy
    concurrency_policy=$(get_cronjob_spec "$cj" "$ns" "concurrencyPolicy")
    if [[ "$concurrency_policy" == "Forbid" ]]; then
        pass "Concurrency policy is Forbid"
    else
        fail_with_cmd "Concurrency policy is $concurrency_policy (expected Forbid)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.concurrencyPolicy}'"
    fi

    local success_limit
    success_limit=$(get_cronjob_spec "$cj" "$ns" "successfulJobsHistoryLimit")
    if [[ "$success_limit" == "3" ]]; then
        pass "Successful jobs history limit is 3"
    else
        fail_with_cmd "Successful jobs history limit is $success_limit (expected 3)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.successfulJobsHistoryLimit}'"
    fi

    local failed_limit
    failed_limit=$(get_cronjob_spec "$cj" "$ns" "failedJobsHistoryLimit")
    if [[ "$failed_limit" == "1" ]]; then
        pass "Failed jobs history limit is 1"
    else
        fail_with_cmd "Failed jobs history limit is $failed_limit (expected 1)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.failedJobsHistoryLimit}'"
    fi

    local ttl
    ttl=$(kubectl get cronjob "$cj" -n "$ns" -o jsonpath='{.spec.jobTemplate.spec.ttlSecondsAfterFinished}' 2>/dev/null)
    if [[ "$ttl" == "604800" ]]; then
        pass "Job TTL is 604800 seconds (7 days)"
    else
        fail_with_cmd "Job TTL is $ttl (expected 604800)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.jobTemplate.spec.ttlSecondsAfterFinished}'"
    fi

    local image
    image=$(get_cronjob_image "$cj" "$ns")
    if [[ "$image" == "busybox:1.36" ]]; then
        pass "Image is busybox:1.36"
    else
        fail_with_cmd "Image is $image (expected busybox:1.36)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'"
    fi
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Bounded run with deadline ==="
    local job="bounded-run"
    local ns="ex-4-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! job_exists "$job" "$ns"; then
        fail_with_cmd "Job $job not found in namespace $ns" \
            "kubectl get jobs -n $ns"
        return
    fi

    info "Waiting for deadline to fire (up to 30s)..."
    sleep 30

    local failed_status
    failed_status=$(get_job_condition "$job" "$ns" "Failed")
    if [[ "$failed_status" == "True" ]]; then
        pass "Job reached Failed condition"
    else
        fail_with_cmd "Job Failed condition is not True" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.conditions}'"
    fi

    local failed_reason
    failed_reason=$(get_job_condition_reason "$job" "$ns" "Failed")
    if [[ "$failed_reason" == "DeadlineExceeded" ]]; then
        pass "Failed reason is DeadlineExceeded"
    else
        fail_with_cmd "Failed reason is $failed_reason (expected DeadlineExceeded)" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.conditions[?(@.type==\"Failed\")]}'"
    fi

    local deadline
    deadline=$(get_job_spec "$job" "$ns" "activeDeadlineSeconds")
    if [[ "$deadline" == "20" ]]; then
        pass "activeDeadlineSeconds is 20"
    else
        fail_with_cmd "activeDeadlineSeconds is $deadline (expected 20)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.activeDeadlineSeconds}'"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: Complete CronJob spec ==="
    local cj="complete-spec"
    local ns="ex-5-1"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cronjob_exists "$cj" "$ns"; then
        fail_with_cmd "CronJob $cj not found in namespace $ns" \
            "kubectl get cronjobs -n $ns"
        return
    fi

    local schedule
    schedule=$(get_cronjob_spec "$cj" "$ns" "schedule")
    if [[ "$schedule" == "*/2 * * * *" ]]; then
        pass "Schedule is */2 * * * *"
    else
        fail_with_cmd "Schedule is $schedule (expected */2 * * * *)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.schedule}'"
    fi

    local timezone
    timezone=$(get_cronjob_spec "$cj" "$ns" "timeZone")
    if [[ "$timezone" == "Etc/UTC" ]]; then
        pass "Time zone is Etc/UTC"
    else
        fail_with_cmd "Time zone is $timezone (expected Etc/UTC)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.timeZone}'"
    fi

    local concurrency_policy
    concurrency_policy=$(get_cronjob_spec "$cj" "$ns" "concurrencyPolicy")
    if [[ "$concurrency_policy" == "Replace" ]]; then
        pass "Concurrency policy is Replace"
    else
        fail_with_cmd "Concurrency policy is $concurrency_policy (expected Replace)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.concurrencyPolicy}'"
    fi

    local starting_deadline
    starting_deadline=$(get_cronjob_spec "$cj" "$ns" "startingDeadlineSeconds")
    if [[ "$starting_deadline" == "60" ]]; then
        pass "startingDeadlineSeconds is 60"
    else
        fail_with_cmd "startingDeadlineSeconds is $starting_deadline (expected 60)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.startingDeadlineSeconds}'"
    fi

    local success_limit
    success_limit=$(get_cronjob_spec "$cj" "$ns" "successfulJobsHistoryLimit")
    if [[ "$success_limit" == "5" ]]; then
        pass "Successful jobs history limit is 5"
    else
        fail_with_cmd "Successful jobs history limit is $success_limit (expected 5)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.successfulJobsHistoryLimit}'"
    fi

    local failed_limit
    failed_limit=$(get_cronjob_spec "$cj" "$ns" "failedJobsHistoryLimit")
    if [[ "$failed_limit" == "2" ]]; then
        pass "Failed jobs history limit is 2"
    else
        fail_with_cmd "Failed jobs history limit is $failed_limit (expected 2)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.failedJobsHistoryLimit}'"
    fi

    local suspend
    suspend=$(get_cronjob_spec "$cj" "$ns" "suspend")
    if [[ "$suspend" == "false" ]]; then
        pass "Suspend is false"
    else
        fail_with_cmd "Suspend is $suspend (expected false)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.suspend}'"
    fi

    local container_name
    container_name=$(kubectl get cronjob "$cj" -n "$ns" -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].name}' 2>/dev/null)
    if [[ "$container_name" == "runner" ]]; then
        pass "Container name is runner"
    else
        fail_with_cmd "Container name is $container_name (expected runner)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].name}'"
    fi

    local image
    image=$(get_cronjob_image "$cj" "$ns")
    if [[ "$image" == "busybox:1.36" ]]; then
        pass "Image is busybox:1.36"
    else
        fail_with_cmd "Image is $image (expected busybox:1.36)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'"
    fi

    local restart_policy
    restart_policy=$(get_cronjob_restart_policy "$cj" "$ns")
    if [[ "$restart_policy" == "OnFailure" ]]; then
        pass "Restart policy is OnFailure"
    else
        fail_with_cmd "Restart policy is $restart_policy (expected OnFailure)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.jobTemplate.spec.template.spec.restartPolicy}'"
    fi

    local ttl
    ttl=$(kubectl get cronjob "$cj" -n "$ns" -o jsonpath='{.spec.jobTemplate.spec.ttlSecondsAfterFinished}' 2>/dev/null)
    if [[ "$ttl" == "600" ]]; then
        pass "Job TTL is 600 seconds"
    else
        fail_with_cmd "Job TTL is $ttl (expected 600)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.jobTemplate.spec.ttlSecondsAfterFinished}'"
    fi

    info "Waiting for at least one Job to be created (up to 150s)..."
    sleep 150

    local job_count
    job_count=$(count_cronjob_jobs "$cj" "$ns")
    if [[ "$job_count" -ge 1 ]]; then
        pass "At least one Job was created ($job_count found)"
    else
        fail_with_cmd "No Jobs created yet" \
            "kubectl get jobs -n $ns -l batch.kubernetes.io/cronjob-name=$cj"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Multi-bug Job ==="
    local job="multibug"
    local ns="ex-5-2"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! job_exists "$job" "$ns"; then
        fail_with_cmd "Job $job not found in namespace $ns" \
            "kubectl get jobs -n $ns"
        return
    fi

    info "Waiting for Job to complete (up to 120s)..."
    kubectl wait --for=condition=Complete job/"$job" -n "$ns" --timeout=120s &>/dev/null || true
    sleep 5

    local succeeded
    succeeded=$(get_job_succeeded "$job" "$ns")
    if [[ "$succeeded" == "3" ]]; then
        pass "Job has 3 successful completions"
    else
        fail_with_cmd "Job succeeded count is $succeeded (expected 3)" \
            "kubectl get job $job -n $ns -o jsonpath='{.status.succeeded}'"
    fi

    local restart_policy
    restart_policy=$(get_job_restart_policy "$job" "$ns")
    if [[ "$restart_policy" == "Never" ]] || [[ "$restart_policy" == "OnFailure" ]]; then
        pass "Restart policy is $restart_policy (valid for Job)"
    else
        fail_with_cmd "Restart policy is $restart_policy (expected Never or OnFailure)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.template.spec.restartPolicy}'"
    fi

    local image
    image=$(get_job_image "$job" "$ns")
    if [[ "$image" =~ ^busybox: ]] && [[ "$image" != "busybox:2.99" ]]; then
        pass "Image is a valid busybox tag: $image"
    else
        fail_with_cmd "Image is $image (should be valid busybox, not 2.99)" \
            "kubectl get job $job -n $ns -o jsonpath='{.spec.template.spec.containers[0].image}'"
    fi

    # Check all shards logged
    local all_shards_ok=true
    for i in 0 1 2; do
        local shard_log
        shard_log=$(kubectl logs -n "$ns" -l batch.kubernetes.io/job-completion-index="$i" --tail=1 2>/dev/null || echo "")
        if ! echo "$shard_log" | grep -q "processing shard $i"; then
            all_shards_ok=false
            break
        fi
    done

    if [[ "$all_shards_ok" == "true" ]]; then
        pass "All shards logged their index"
    else
        fail_with_cmd "Not all shards logged correctly" \
            "for i in 0 1 2; do kubectl logs -n $ns -l batch.kubernetes.io/job-completion-index=\$i --tail=1; done"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Silent CronJob ==="
    local cj="silent"
    local ns="ex-5-3"

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! cronjob_exists "$cj" "$ns"; then
        fail_with_cmd "CronJob $cj not found in namespace $ns" \
            "kubectl get cronjobs -n $ns"
        return
    fi

    local suspend
    suspend=$(get_cronjob_spec "$cj" "$ns" "suspend")
    if [[ "$suspend" == "false" ]]; then
        pass "CronJob is not suspended"
    else
        fail_with_cmd "CronJob suspend is $suspend (expected false)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.suspend}'"
        info "Fix: kubectl patch cronjob $cj -n $ns --type=merge -p '{\"spec\":{\"suspend\":false}}'"
        return
    fi

    local schedule
    schedule=$(get_cronjob_spec "$cj" "$ns" "schedule")
    if [[ "$schedule" == "*/1 * * * *" ]]; then
        pass "Schedule is */1 * * * *"
    else
        fail_with_cmd "Schedule is $schedule (expected */1 * * * *)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.schedule}'"
    fi

    local concurrency_policy
    concurrency_policy=$(get_cronjob_spec "$cj" "$ns" "concurrencyPolicy")
    if [[ "$concurrency_policy" == "Forbid" ]]; then
        pass "Concurrency policy is Forbid"
    else
        fail_with_cmd "Concurrency policy is $concurrency_policy (expected Forbid)" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.spec.concurrencyPolicy}'"
    fi

    info "Waiting for at least one Job to be created (up to 150s)..."
    sleep 150

    local job_count
    job_count=$(count_cronjob_jobs "$cj" "$ns")
    if [[ "$job_count" -ge 1 ]]; then
        pass "At least one Job was created ($job_count found)"
    else
        fail_with_cmd "No Jobs created yet" \
            "kubectl get jobs -n $ns -l batch.kubernetes.io/cronjob-name=$cj"
    fi

    local last_schedule
    last_schedule=$(get_cronjob_last_schedule "$cj" "$ns")
    if [[ -n "$last_schedule" ]]; then
        pass "LAST SCHEDULE is populated: $last_schedule"
    else
        fail_with_cmd "LAST SCHEDULE is not populated" \
            "kubectl get cronjob $cj -n $ns -o jsonpath='{.status.lastScheduleTime}'"
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
