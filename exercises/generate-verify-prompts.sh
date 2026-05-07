#!/usr/bin/env bash
#
# generate-verify-prompts.sh - Creates individual prompt files for generating verify scripts
#
# This creates one prompt file per assignment that you can then feed to Claude/AI
#

set -euo pipefail

OUTPUT_DIR="/workspaces/cka-exam-prep/exercises/.prompts"
mkdir -p "$OUTPUT_DIR"

# Define all assignments (topic:count format)
declare -A assignments=(
    ["02-jobs-and-cronjobs"]=1
    ["03-statefulsets"]=1
    ["04-autoscaling"]=1
    ["05-helm"]=3
    ["06-kustomize"]=3
    ["07-storage"]=3
    ["08-services"]=3
    ["09-coredns"]=3
    ["10-network-policies"]=3
    ["11-ingress-and-gateway-api"]=5
    ["12-rbac"]=2
    ["13-security-contexts"]=3
    ["14-pod-security"]=1
    ["15-crds-and-operators"]=3
    ["16-admission-controllers"]=1
    ["17-cluster-lifecycle"]=3
    ["18-tls-and-certificates"]=3
    ["19-troubleshooting"]=4
)

# Generate prompt file for each assignment
for topic in "${!assignments[@]}"; do
    count=${assignments[$topic]}

    for n in $(seq 1 $count); do
        prompt_file="$OUTPUT_DIR/${topic}-${n}.md"

        # Extract topic name without number prefix
        topic_name="${topic#??-}"  # Remove first 2 chars (number prefix)

        cat > "$prompt_file" << EOF
# Verify Script Generation Request

## Task
Generate a verify.sh script for: **${topic}/assignment-${n}**

## Instructions

1. Read the template and reference:
   - \`/workspaces/cka-exam-prep/exercises/verify-script-generator-prompt.md\`
   - \`/workspaces/cka-exam-prep/exercises/01-pods/assignment-1/verify.sh\` (reference implementation)

2. Read the assignment files:
   - \`/workspaces/cka-exam-prep/exercises/${topic}/assignment-${n}/${topic_name}-homework.md\`
   - \`/workspaces/cka-exam-prep/exercises/${topic}/assignment-${n}/${topic_name}-homework-answers.md\`
   - \`/workspaces/cka-exam-prep/exercises/${topic}/assignment-${n}/README.md\`

3. Generate the verify.sh script:
   - Follow the structure from the template
   - Implement verification for every exercise in the homework file
   - Use appropriate helpers for the resource types involved (see template for examples)
   - Add fail_with_cmd for all non-trivial failures
   - Include appropriate sleep times for async operations
   - Make the script executable

4. Output location:
   \`/workspaces/cka-exam-prep/exercises/${topic}/assignment-${n}/verify.sh\`

## Verification After Generation

After generating the script, verify it follows these requirements:
- [ ] Executable permissions set (\`chmod +x\`)
- [ ] All exercises from homework file are covered
- [ ] Helper functions appropriate to resource types
- [ ] Debug commands on failures
- [ ] Level grouping with headers
- [ ] Summary output at end
- [ ] Proper error handling with \`set -euo pipefail\`
- [ ] No \`((var++))\` patterns (use \`var=\$((var + 1))\` instead)

## Testing

Suggest the user test with:
\`\`\`bash
cd /workspaces/cka-exam-prep/exercises/${topic}/assignment-${n}
./verify.sh all
\`\`\`
EOF

        echo "Created: $prompt_file"
    done
done

echo ""
echo "========================================="
echo "Generated $(ls -1 "$OUTPUT_DIR" | wc -l) prompt files in $OUTPUT_DIR"
echo ""
echo "To use these prompts:"
echo "1. Open each .md file in $OUTPUT_DIR"
echo "2. Copy the content"
echo "3. Paste into a new Claude Code conversation"
echo "4. Claude will generate the verify.sh script"
echo ""
echo "Or use them all with me sequentially by saying:"
echo "  'Read @$OUTPUT_DIR/02-jobs-and-cronjobs-1.md and execute the task'"
echo "========================================="
