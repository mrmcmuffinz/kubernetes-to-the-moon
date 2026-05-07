# Verify Script Generator Prompt

Use this prompt to generate verification scripts for CKA homework assignments.

## Context

You are creating a bash verification script for a Kubernetes (CKA exam prep) homework assignment. The script should automatically verify that exercises have been completed correctly, providing instant pass/fail feedback with debugging commands.

## Reference Implementation

The reference implementation is at `/workspaces/cka-exam-prep/exercises/01-pods/assignment-1/verify.sh`. This script demonstrates:
- Overall structure and helper functions
- Pass/fail reporting with colored output
- Debug command output on failures
- Level-based and individual exercise verification

## Your Task

Create a verification script for the homework assignment located at:
```
/workspaces/cka-exam-prep/exercises/<TOPIC>/assignment-<N>/
```

Where:
- `<TOPIC>` is the topic directory (e.g., `02-jobs-and-cronjobs`, `07-storage`, etc.)
- `<N>` is the assignment number

## Required Inputs

Before generating the script, read these files in the target directory:
1. `<topic>-homework.md` - Contains all exercises, their requirements, and verification commands
2. `<topic>-homework-answers.md` - Contains expected solutions (use for validation logic)
3. `README.md` - Contains assignment overview and any special notes

## Script Structure

### 1. Header and Setup
```bash
#!/usr/bin/env bash
#
# verify.sh - Automated verification for <topic>-homework.md
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
```

### 2. Core Helper Functions (Always Include These)

```bash
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
```

### 3. Resource-Specific Helpers

Add helpers appropriate to the assignment's resources. Common patterns:

**For Pod-based resources (Pods, Deployments, StatefulSets, Jobs, CronJobs):**
```bash
pod_exists() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" &>/dev/null
}

get_phase() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

get_image() {
    local pod=$1; local ns=$2
    kubectl get pod "$pod" -n "$ns" -o jsonpath='{.spec.containers[0].image}' 2>/dev/null
}

logs_contain() {
    local pod=$1; local ns=$2; local pattern=$3; local container=${4:-}
    if [[ -n "$container" ]]; then
        kubectl logs "$pod" -n "$ns" -c "$container" 2>/dev/null | grep -q "$pattern"
    else
        kubectl logs "$pod" -n "$ns" 2>/dev/null | grep -q "$pattern"
    fi
}

get_env() {
    local pod=$1; local ns=$2; local var=$3; local container=${4:-}
    local result
    if [[ -n "$container" ]]; then
        result=$(kubectl exec "$pod" -n "$ns" -c "$container" -- env 2>/dev/null | grep "^${var}=" | cut -d= -f2 || echo "")
    else
        result=$(kubectl exec "$pod" -n "$ns" -- env 2>/dev/null | grep "^${var}=" | cut -d= -f2 || echo "")
    fi
    echo "$result"
}
```

**For Deployments/StatefulSets:**
```bash
get_replicas() {
    local name=$1; local ns=$2; local kind=$3
    kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.status.replicas}' 2>/dev/null
}

get_ready_replicas() {
    local name=$1; local ns=$2; local kind=$3
    kubectl get "$kind" "$name" -n "$ns" -o jsonpath='{.status.readyReplicas}' 2>/dev/null
}
```

**For Services:**
```bash
service_exists() {
    local svc=$1; local ns=$2
    kubectl get service "$svc" -n "$ns" &>/dev/null
}

get_service_type() {
    local svc=$1; local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.type}' 2>/dev/null
}

get_service_port() {
    local svc=$1; local ns=$2
    kubectl get service "$svc" -n "$ns" -o jsonpath='{.spec.ports[0].port}' 2>/dev/null
}
```

**For Storage (PV/PVC):**
```bash
pvc_exists() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" &>/dev/null
}

get_pvc_status() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.status.phase}' 2>/dev/null
}

get_storage_class() {
    local pvc=$1; local ns=$2
    kubectl get pvc "$pvc" -n "$ns" -o jsonpath='{.spec.storageClassName}' 2>/dev/null
}
```

**For RBAC:**
```bash
role_exists() {
    local role=$1; local ns=$2
    kubectl get role "$role" -n "$ns" &>/dev/null
}

rolebinding_exists() {
    local rb=$1; local ns=$2
    kubectl get rolebinding "$rb" -n "$ns" &>/dev/null
}

check_permission() {
    local user=$1; local verb=$2; local resource=$3; local ns=$4
    kubectl auth can-i "$verb" "$resource" --as="$user" -n "$ns" &>/dev/null
}
```

**For Network Policies:**
```bash
netpol_exists() {
    local np=$1; local ns=$2
    kubectl get networkpolicy "$np" -n "$ns" &>/dev/null
}
```

### 4. Exercise Verification Functions

For each exercise in the homework file, create a `verify_X_Y()` function where X is the level and Y is the exercise number.

**Pattern for each function:**
```bash
verify_X_Y() {
    echo ""
    echo "=== Exercise X.Y: <Brief description> ==="
    local resource_name="<name>"
    local ns="ex-X-Y"  # Standard namespace pattern

    # 1. Check namespace exists
    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    # 2. Check primary resource exists
    if ! <resource_check>; then
        fail "<Resource> not found in namespace $ns"
        return
    fi

    # 3. Verify specific requirements
    # For each requirement from the homework file:
    
    local <check_var>
    <check_var>=$(<helper_function>)
    if [[ "$<check_var>" == "<expected>" ]]; then
        pass "<Requirement met message>"
    else
        fail_with_cmd "<Actual>=$<check_var> (expected <expected>)" \
            "<kubectl command to debug this>"
    fi

    # 4. For timing-dependent checks (pod completion, etc.)
    # Add appropriate sleep before checking
    sleep <N>
}
```

**Important patterns:**
- Always check namespace existence first
- Always check resource existence second
- Use `fail_with_cmd` for failures that need debugging
- Include `sleep` commands for async operations (pod startup, job completion, etc.)
- Use `return` after critical failures to skip remaining checks
- Extract the expected values from the homework file's verification section

### 5. Level Aggregation Functions

```bash
verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: <Level Description>"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: <Level Description>"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

# ... continue for all levels
```

### 6. Main Function and Command Routing

```bash
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
        # ... all individual exercises
        1) verify_level_1 ;;
        2) verify_level_2 ;;
        # ... all levels
        all)
            verify_level_1
            verify_level_2
            # ... all levels
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
```

## Key Implementation Guidelines

1. **Extract Requirements from Homework File**
   - Read the "Verification" section of each exercise
   - Convert each verification command into a check in the verify function
   - The verification commands in the homework are your spec

2. **Use fail_with_cmd for Actionable Failures**
   - When checking resource state: include the kubectl get command
   - When checking logs: include the kubectl logs command
   - When checking env vars: include the kubectl exec env command
   - When checking permissions: include the kubectl auth can-i command

3. **Handle Timing Correctly**
   - Pods starting: `sleep 5`
   - Jobs completing: `sleep 10`
   - Long-running operations: `sleep 15-30`
   - Init containers: add time for each init + main

4. **Match Homework Namespace Pattern**
   - Standard pattern: `ex-<level>-<exercise>` (e.g., `ex-1-1`, `ex-2-3`)
   - If homework uses different pattern, match it exactly

5. **Handle Multi-Resource Exercises**
   - Check each resource in the order they're created
   - Dependencies first (e.g., PVC before Pod that uses it)

6. **Debugging Exercises (Level 3 typically)**
   - Check that the issue is fixed, not just that resource exists
   - Look for the "after fix" state mentioned in verification section

7. **Be Lenient Where Appropriate**
   - Accept both Running and Succeeded for one-shot pods (timing-dependent)
   - Accept any valid tag for images when exercise doesn't specify exact version
   - Accept equivalent configurations (e.g., command vs args variations that produce same result)

## Common Pitfalls to Avoid

1. **Don't use `((var++))` with set -e** - Use `var=$((var + 1))` instead
2. **Don't assume resources are ready immediately** - Add sleep for async operations
3. **Don't check only resource existence** - Verify it's in the correct state
4. **Don't forget to handle missing namespaces** - Check and return early
5. **Don't use pod name for multi-pod resources** - Use label selectors or list all pods

## Output Format

The completed script should:
- Be executable (`chmod +x verify.sh`)
- Use consistent formatting and indentation
- Have clear, descriptive pass/fail messages
- Include debug commands for all non-trivial failures
- Match the structure and style of the reference implementation

## Example Usage Pattern

After generating the script, users will run:
```bash
cd /workspaces/cka-exam-prep/exercises/<topic>/assignment-<N>
./verify.sh all       # verify everything
./verify.sh 2         # verify level 2 only
./verify.sh 3.2       # verify exercise 3.2 only
```

## Deliverable

Generate a complete `verify.sh` script that:
1. Follows the structure defined above
2. Implements verification for every exercise in the homework file
3. Uses appropriate helpers for the resource types involved
4. Provides actionable debug commands on failures
5. Groups exercises by level with clear visual separation
6. Exits with appropriate status code (0 for pass, non-zero for failures)
