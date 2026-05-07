#!/usr/bin/env bash
#
# verify.sh - Automated verification for crds-and-operators-homework.md
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

# Helper: get CRD group
get_crd_group() {
    local crd=$1
    kubectl get crd "$crd" -o jsonpath='{.spec.group}' 2>/dev/null
}

# Helper: get CRD scope
get_crd_scope() {
    local crd=$1
    kubectl get crd "$crd" -o jsonpath='{.spec.scope}' 2>/dev/null
}

# Helper: get CRD plural name
get_crd_plural() {
    local crd=$1
    kubectl get crd "$crd" -o jsonpath='{.spec.names.plural}' 2>/dev/null
}

# Helper: check if custom resource exists
custom_resource_exists() {
    local resource=$1
    local name=$2
    local ns=${3:-}
    if [[ -n "$ns" ]]; then
        kubectl get "$resource" "$name" -n "$ns" &>/dev/null
    else
        kubectl get "$resource" "$name" &>/dev/null
    fi
}

# Helper: get custom resource field value
get_cr_field() {
    local resource=$1
    local name=$2
    local jsonpath=$3
    local ns=${4:-}
    if [[ -n "$ns" ]]; then
        kubectl get "$resource" "$name" -n "$ns" -o jsonpath="$jsonpath" 2>/dev/null
    else
        kubectl get "$resource" "$name" -o jsonpath="$jsonpath" 2>/dev/null
    fi
}

# Helper: check if CRD has printer column
crd_has_printer_column() {
    local crd=$1
    local column_name=$2
    local result
    result=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[0].additionalPrinterColumns[*].name}' 2>/dev/null | grep -w "$column_name" || echo "")
    [[ -n "$result" ]]
}

# Helper: get printer column jsonPath
get_printer_column_jsonpath() {
    local crd=$1
    local column_name=$2
    kubectl get crd "$crd" -o json 2>/dev/null | jq -r ".spec.versions[0].additionalPrinterColumns[] | select(.name==\"$column_name\") | .jsonPath" 2>/dev/null || echo ""
}

# Helper: check if CRD has status subresource
crd_has_status_subresource() {
    local crd=$1
    local version=${2:-}
    local result
    if [[ -n "$version" ]]; then
        result=$(kubectl get crd "$crd" -o json 2>/dev/null | jq -r ".spec.versions[] | select(.name==\"$version\") | .subresources.status" 2>/dev/null)
    else
        result=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[0].subresources.status}' 2>/dev/null)
    fi
    [[ -n "$result" ]] && [[ "$result" != "null" ]]
}

# Helper: check if version is storage version
is_storage_version() {
    local crd=$1
    local version=$2
    local result
    result=$(kubectl get crd "$crd" -o json 2>/dev/null | jq -r ".spec.versions[] | select(.name==\"$version\") | .storage" 2>/dev/null)
    [[ "$result" == "true" ]]
}

# Helper: check if version is served
is_served_version() {
    local crd=$1
    local version=$2
    local result
    result=$(kubectl get crd "$crd" -o json 2>/dev/null | jq -r ".spec.versions[] | select(.name==\"$version\") | .served" 2>/dev/null)
    [[ "$result" == "true" ]]
}

################################################################################
# Exercise verification functions
################################################################################

verify_1_1() {
    echo ""
    echo "=== Exercise 1.1: Basic Application CRD ==="
    local crd="applications.apps.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    local group
    group=$(get_crd_group "$crd")
    if [[ "$group" == "apps.example.com" ]]; then
        pass "Group is apps.example.com"
    else
        fail_with_cmd "Group is $group (expected apps.example.com)" \
            "kubectl get crd $crd -o jsonpath='{.spec.group}'"
    fi

    local scope
    scope=$(get_crd_scope "$crd")
    if [[ "$scope" == "Namespaced" ]]; then
        pass "Scope is Namespaced"
    else
        fail_with_cmd "Scope is $scope (expected Namespaced)" \
            "kubectl get crd $crd -o jsonpath='{.spec.scope}'"
    fi

    # Check API resource is registered
    if kubectl api-resources | grep -q "applications.*apps.example.com"; then
        pass "API resource is registered"
    else
        fail_with_cmd "API resource not found in api-resources" \
            "kubectl api-resources | grep applications"
    fi
}

verify_1_2() {
    echo ""
    echo "=== Exercise 1.2: Create Application custom resource ==="
    local crd="applications.apps.example.com"
    local resource_name="webapp"
    local ns="ex-1-2"

    if ! crd_exists "$crd"; then
        fail "CRD $crd does not exist (required from Exercise 1.1)"
        return
    fi

    if ! namespace_exists "$ns"; then
        fail "Namespace $ns does not exist"
        return
    fi

    if ! custom_resource_exists "applications.apps.example.com" "$resource_name" "$ns"; then
        fail_with_cmd "Application $resource_name not found in namespace $ns" \
            "kubectl get applications -n $ns"
        return
    fi
    pass "Application $resource_name exists in namespace $ns"

    local spec_name
    spec_name=$(get_cr_field "applications.apps.example.com" "$resource_name" '{.spec.name}' "$ns")
    if [[ "$spec_name" == "webapp-production" ]]; then
        pass "spec.name is webapp-production"
    else
        fail_with_cmd "spec.name is $spec_name (expected webapp-production)" \
            "kubectl get applications $resource_name -n $ns -o jsonpath='{.spec.name}'"
    fi
}

verify_1_3() {
    echo ""
    echo "=== Exercise 1.3: Add printer columns to Application CRD ==="
    local crd="applications.apps.example.com"

    if ! crd_exists "$crd"; then
        fail "CRD $crd does not exist (required from Exercise 1.1)"
        return
    fi

    if crd_has_printer_column "$crd" "Application-Name"; then
        pass "Printer column 'Application-Name' exists"
    else
        fail_with_cmd "Printer column 'Application-Name' not found" \
            "kubectl get crd $crd -o jsonpath='{.spec.versions[0].additionalPrinterColumns[*].name}'"
        return
    fi

    local jsonpath
    jsonpath=$(get_printer_column_jsonpath "$crd" "Application-Name")
    if [[ "$jsonpath" == ".spec.name" ]]; then
        pass "Printer column jsonPath is .spec.name"
    else
        fail_with_cmd "Printer column jsonPath is $jsonpath (expected .spec.name)" \
            "kubectl get crd $crd -o yaml | grep -A 3 'Application-Name'"
    fi
}

verify_2_1() {
    echo ""
    echo "=== Exercise 2.1: Server CRD with typed properties ==="
    local crd="servers.infrastructure.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    local group
    group=$(get_crd_group "$crd")
    if [[ "$group" == "infrastructure.example.com" ]]; then
        pass "Group is infrastructure.example.com"
    else
        fail "Group is $group (expected infrastructure.example.com)"
    fi

    # Check schema has the required properties
    local properties
    properties=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties}' 2>/dev/null)

    for prop in hostname ip port enabled; do
        if echo "$properties" | grep -q "\"$prop\""; then
            pass "Schema includes property: $prop"
        else
            fail_with_cmd "Schema missing property: $prop" \
                "kubectl get crd $crd -o yaml | grep -A 20 'properties:'"
        fi
    done
}

verify_2_2() {
    echo ""
    echo "=== Exercise 2.2: Database CRD with validation ==="
    local crd="databases.data.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    # Check required fields
    local required
    required=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.required}' 2>/dev/null)
    if echo "$required" | grep -q "name" && echo "$required" | grep -q "engine"; then
        pass "Required fields include name and engine"
    else
        fail_with_cmd "Required fields: $required (expected name and engine)" \
            "kubectl get crd $crd -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.required}'"
    fi

    # Check enum constraint for engine
    local enum_check
    enum_check=$(kubectl get crd "$crd" -o yaml 2>/dev/null | grep -A 5 "engine:" | grep -c "mysql\|postgresql\|mongodb" || echo "0")
    if [[ "$enum_check" -ge 3 ]]; then
        pass "Engine field has enum constraint with mysql, postgresql, mongodb"
    else
        fail_with_cmd "Engine field enum constraint missing or incomplete" \
            "kubectl get crd $crd -o yaml | grep -A 5 'engine:'"
    fi
}

verify_2_3() {
    echo ""
    echo "=== Exercise 2.3: Cluster CRD with nested objects ==="
    local crd="clusters.compute.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    local scope
    scope=$(get_crd_scope "$crd")
    if [[ "$scope" == "Cluster" ]]; then
        pass "Scope is Cluster (not namespaced)"
    else
        fail_with_cmd "Scope is $scope (expected Cluster)" \
            "kubectl get crd $crd -o jsonpath='{.spec.scope}'"
    fi

    # Check nested properties exist
    local yaml_output
    yaml_output=$(kubectl get crd "$crd" -o yaml 2>/dev/null)

    for field in nodes networking count cidr dns; do
        if echo "$yaml_output" | grep -q "$field:"; then
            pass "Schema includes nested field: $field"
        else
            fail_with_cmd "Schema missing nested field: $field" \
                "kubectl get crd $crd -o yaml | grep -E 'nodes:|networking:|count:|cidr:|dns:'"
        fi
    done
}

verify_3_1() {
    echo ""
    echo "=== Exercise 3.1: Fix CRD name format ==="
    local correct_crd="resources.test.example.com"

    # The exercise asks to fix the name, so check if the corrected CRD exists
    if crd_exists "$correct_crd"; then
        pass "CRD $correct_crd exists (name format corrected)"
    else
        fail_with_cmd "CRD $correct_crd not found (should be resources.test.example.com, not myresources.test.example.com)" \
            "kubectl get crd | grep test.example.com"
        return
    fi

    # Verify it follows plural.group format
    local group
    group=$(get_crd_group "$correct_crd")
    if [[ "$group" == "test.example.com" ]]; then
        pass "Group is test.example.com"
    else
        fail "Group is $group (expected test.example.com)"
    fi

    local plural
    plural=$(get_crd_plural "$correct_crd")
    if [[ "$plural" == "resources" ]]; then
        pass "Plural is resources (matches name format)"
    else
        fail "Plural is $plural (expected resources)"
    fi
}

verify_3_2() {
    echo ""
    echo "=== Exercise 3.2: Fix missing schema ==="
    local crd="configs.settings.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found (schema issue not fixed)" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists (schema added)"

    # Check that schema exists
    local schema
    schema=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema}' 2>/dev/null)
    if [[ -n "$schema" ]] && [[ "$schema" != "null" ]]; then
        pass "Version has openAPIV3Schema"
    else
        fail_with_cmd "Version missing openAPIV3Schema" \
            "kubectl get crd $crd -o yaml | grep -A 10 'versions:'"
    fi
}

verify_3_3() {
    echo ""
    echo "=== Exercise 3.3: Fix multiple storage versions ==="
    local crd="jobs.batch.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    # Check v1 is not storage
    if is_storage_version "$crd" "v1"; then
        fail_with_cmd "v1 has storage=true (should be false)" \
            "kubectl get crd $crd -o jsonpath='{range .spec.versions[*]}{.name}: storage={.storage}{\"\\n\"}{end}'"
    else
        pass "v1 has storage=false"
    fi

    # Check v2 is storage
    if is_storage_version "$crd" "v2"; then
        pass "v2 has storage=true"
    else
        fail_with_cmd "v2 does not have storage=true" \
            "kubectl get crd $crd -o jsonpath='{range .spec.versions[*]}{.name}: storage={.storage}{\"\\n\"}{end}'"
    fi
}

verify_4_1() {
    echo ""
    echo "=== Exercise 4.1: Pipeline CRD with status subresource ==="
    local crd="pipelines.ci.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    if crd_has_status_subresource "$crd"; then
        pass "Status subresource is enabled"
    else
        fail_with_cmd "Status subresource not enabled" \
            "kubectl get crd $crd -o jsonpath='{.spec.versions[0].subresources}'"
    fi

    # Check schema has both spec and status fields
    local spec_fields
    spec_fields=$(kubectl get crd "$crd" -o yaml 2>/dev/null | grep -A 10 "spec:" | grep -c "stages\|timeout" || echo "0")
    if [[ "$spec_fields" -ge 2 ]]; then
        pass "Schema includes spec fields (stages, timeout)"
    else
        fail "Schema missing expected spec fields"
    fi

    local status_fields
    status_fields=$(kubectl get crd "$crd" -o yaml 2>/dev/null | grep -A 10 "status:" | grep -c "phase\|startedAt\|completedAt" || echo "0")
    if [[ "$status_fields" -ge 3 ]]; then
        pass "Schema includes status fields (phase, startedAt, completedAt)"
    else
        fail "Schema missing expected status fields"
    fi
}

verify_4_2() {
    echo ""
    echo "=== Exercise 4.2: VirtualMachine CRD with printer columns ==="
    local crd="virtualmachines.virtualization.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    # Check all required printer columns
    local columns
    columns=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[0].additionalPrinterColumns[*].name}' 2>/dev/null)

    for col in Status CPU Memory Age; do
        if echo "$columns" | grep -q "$col"; then
            pass "Printer column '$col' exists"
        else
            fail_with_cmd "Printer column '$col' not found" \
                "kubectl get crd $crd -o jsonpath='{.spec.versions[0].additionalPrinterColumns[*].name}'"
        fi
    done
}

verify_4_3() {
    echo ""
    echo "=== Exercise 4.3: Policy CRD with multiple versions ==="
    local crd="policies.security.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    # Check both versions are available
    if kubectl api-versions 2>/dev/null | grep -q "security.example.com/v1alpha1"; then
        pass "Version v1alpha1 is available"
    else
        fail_with_cmd "Version v1alpha1 not in api-versions" \
            "kubectl api-versions | grep security.example.com"
    fi

    if kubectl api-versions 2>/dev/null | grep -q "security.example.com/v1"; then
        pass "Version v1 is available"
    else
        fail_with_cmd "Version v1 not in api-versions" \
            "kubectl api-versions | grep security.example.com"
    fi

    # Check version settings
    if is_served_version "$crd" "v1alpha1" && ! is_storage_version "$crd" "v1alpha1"; then
        pass "v1alpha1 is served=true, storage=false"
    else
        fail "v1alpha1 version configuration incorrect"
    fi

    if is_served_version "$crd" "v1" && is_storage_version "$crd" "v1"; then
        pass "v1 is served=true, storage=true"
    else
        fail "v1 version configuration incorrect"
    fi
}

verify_5_1() {
    echo ""
    echo "=== Exercise 5.1: BackupJob CRD design ==="
    local crd="backupjobs.backup.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    # Check status subresource
    if crd_has_status_subresource "$crd"; then
        pass "Status subresource is enabled"
    else
        fail_with_cmd "Status subresource not enabled" \
            "kubectl get crd $crd -o jsonpath='{.spec.versions[0].subresources}'"
    fi

    # Check required fields in source
    local source_required
    source_required=$(kubectl get crd "$crd" -o yaml 2>/dev/null | grep -A 15 "source:" | grep "required:" || echo "")
    if echo "$source_required" | grep -q "namespace" && echo "$source_required" | grep -q "resourceType" && echo "$source_required" | grep -q "name"; then
        pass "Source has required fields (namespace, resourceType, name)"
    else
        fail "Source missing required fields"
    fi

    # Check enum for resourceType
    local resource_type_enum
    resource_type_enum=$(kubectl get crd "$crd" -o yaml 2>/dev/null | grep -A 8 "resourceType:" | grep -c "deployment\|statefulset\|configmap" || echo "0")
    if [[ "$resource_type_enum" -ge 3 ]]; then
        pass "ResourceType has enum constraint"
    else
        fail "ResourceType enum constraint missing"
    fi

    # Check printer columns
    local columns
    columns=$(kubectl get crd "$crd" -o jsonpath='{.spec.versions[0].additionalPrinterColumns[*].name}' 2>/dev/null)
    if echo "$columns" | grep -q "LastBackup" && echo "$columns" | grep -q "Status"; then
        pass "Printer columns include LastBackup and Status"
    else
        fail_with_cmd "Missing printer columns (expected LastBackup and Status)" \
            "kubectl get crd $crd -o jsonpath='{.spec.versions[0].additionalPrinterColumns[*].name}'"
    fi
}

verify_5_2() {
    echo ""
    echo "=== Exercise 5.2: Feature CRD version migration ==="
    local crd="features.product.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    # Check both versions are available
    if kubectl api-versions 2>/dev/null | grep -q "product.example.com/v1beta1"; then
        pass "Version v1beta1 is available"
    else
        fail "Version v1beta1 not available"
    fi

    if kubectl api-versions 2>/dev/null | grep -q "product.example.com/v1"; then
        pass "Version v1 is available"
    else
        fail "Version v1 not available"
    fi

    # Check storage versions
    if ! is_storage_version "$crd" "v1beta1"; then
        pass "v1beta1 has storage=false"
    else
        fail_with_cmd "v1beta1 should have storage=false" \
            "kubectl get crd $crd -o jsonpath='{range .spec.versions[*]}{.name}: storage={.storage}{\"\\n\"}{end}'"
    fi

    if is_storage_version "$crd" "v1"; then
        pass "v1 has storage=true (migrated)"
    else
        fail_with_cmd "v1 should have storage=true" \
            "kubectl get crd $crd -o jsonpath='{range .spec.versions[*]}{.name}: storage={.storage}{\"\\n\"}{end}'"
    fi

    # Check v1 schema has priority field
    local priority_field
    priority_field=$(kubectl get crd "$crd" -o yaml 2>/dev/null | grep -A 50 "name: v1" | grep "priority:" || echo "")
    if [[ -n "$priority_field" ]]; then
        pass "v1 schema includes new priority field"
    else
        fail "v1 schema missing priority field"
    fi
}

verify_5_3() {
    echo ""
    echo "=== Exercise 5.3: Comprehensive Tenant CRD ==="
    local crd="tenants.multitenancy.example.com"

    if ! crd_exists "$crd"; then
        fail_with_cmd "CRD $crd not found" \
            "kubectl get crd"
        return
    fi
    pass "CRD $crd exists"

    # Check cluster scope
    local scope
    scope=$(get_crd_scope "$crd")
    if [[ "$scope" == "Cluster" ]]; then
        pass "Scope is Cluster"
    else
        fail_with_cmd "Scope is $scope (expected Cluster)" \
            "kubectl get crd $crd -o jsonpath='{.spec.scope}'"
    fi

    # Check short name
    if kubectl api-resources 2>/dev/null | grep -q "tnt"; then
        pass "Short name 'tnt' is registered"
    else
        fail_with_cmd "Short name 'tnt' not found" \
            "kubectl api-resources | grep tenant"
    fi

    # Check categories
    local categories
    categories=$(kubectl get crd "$crd" -o jsonpath='{.spec.names.categories}' 2>/dev/null)
    if echo "$categories" | grep -q "all"; then
        pass "Categories include 'all'"
    else
        fail_with_cmd "Categories do not include 'all'" \
            "kubectl get crd $crd -o jsonpath='{.spec.names.categories}'"
    fi

    # Check status subresource on storage version
    local storage_version
    storage_version=$(kubectl get crd "$crd" -o json 2>/dev/null | jq -r '.spec.versions[] | select(.storage==true) | .name')
    if crd_has_status_subresource "$crd" "$storage_version"; then
        pass "Status subresource enabled on storage version ($storage_version)"
    else
        fail "Status subresource not enabled on storage version"
    fi

    # Check printer columns
    local columns
    columns=$(kubectl get crd "$crd" -o json 2>/dev/null | jq -r ".spec.versions[] | select(.storage==true) | .additionalPrinterColumns[].name" | tr '\n' ' ')
    for col in Phase Admin Namespaces Age; do
        if echo "$columns" | grep -q "$col"; then
            pass "Printer column '$col' exists"
        else
            fail_with_cmd "Printer column '$col' not found" \
                "kubectl get crd $crd -o json | jq '.spec.versions[] | select(.storage==true) | .additionalPrinterColumns[].name'"
        fi
    done
}

################################################################################
# Main logic
################################################################################

verify_level_1() {
    echo ""
    echo "###############################################"
    echo "# Level 1: Basic CRD Creation"
    echo "###############################################"
    verify_1_1
    verify_1_2
    verify_1_3
}

verify_level_2() {
    echo ""
    echo "###############################################"
    echo "# Level 2: Schema Definition"
    echo "###############################################"
    verify_2_1
    verify_2_2
    verify_2_3
}

verify_level_3() {
    echo ""
    echo "###############################################"
    echo "# Level 3: Debugging CRD Issues"
    echo "###############################################"
    verify_3_1
    verify_3_2
    verify_3_3
}

verify_level_4() {
    echo ""
    echo "###############################################"
    echo "# Level 4: Advanced CRD Features"
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
