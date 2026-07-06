#!/usr/bin/env bash
#
# check-content.sh - Validates exercise content correctness without a cluster.
#
# Checks:
#   1. File completeness  - every assignment has README, prompt, tutorial, homework, answers
#   2. Em dashes          - no — or – characters in content files
#   3. Prohibited patterns - no grep-q-SUCCESS or timeout-BLOCKED verification patterns
#   4. :latest image tags  - no image: foo:latest in YAML image references
#
# Usage: ./scripts/check-content.sh

set -euo pipefail

ERRORS=0
EXERCISES_DIR="exercises"
SKIP_TOPIC="20-cluster-setup"

err()  { echo "  FAIL: $1"; ERRORS=$((ERRORS + 1)); }
ok()   { echo "  ok:   $1"; }
sep()  { echo ""; echo "-- $1 --"; }

echo "=== Content Check ==="

# -----------------------------------------------------------------------
# 1. File completeness
# -----------------------------------------------------------------------
sep "File completeness"

for dir in "${EXERCISES_DIR}"/*/assignment-*/; do
    [[ -d "$dir" ]] || continue
    topic=$(basename "$(dirname "$dir")")
    [[ "$topic" == "$SKIP_TOPIC" ]] && continue

    label="$topic/$(basename "$dir")"
    missing=()

    [[ -f "${dir}README.md"  ]] || missing+=("README.md")
    [[ -f "${dir}prompt.md"  ]] || missing+=("prompt.md")

    tutorial_count=$(find "$dir" -maxdepth 1 -name "*-tutorial.md" | wc -l)
    homework_count=$(find "$dir" -maxdepth 1 -name "*-homework.md" ! -name "*-answers*" | wc -l)
    answers_count=$(find  "$dir" -maxdepth 1 -name "*-homework-answers.md" | wc -l)

    [[ "$tutorial_count" -ge 1 ]] || missing+=("*-tutorial.md")
    [[ "$homework_count" -ge 1 ]] || missing+=("*-homework.md")
    [[ "$answers_count"  -ge 1 ]] || missing+=("*-homework-answers.md")

    if [[ ${#missing[@]} -gt 0 ]]; then
        err "$label: missing: ${missing[*]}"
    else
        ok "$label"
    fi
done

# -----------------------------------------------------------------------
# 2. Em dash check (— U+2014, – U+2013)
# -----------------------------------------------------------------------
sep "Em dash check"

em_found=0
while IFS= read -r file; do
    if grep -Pq '\x{2014}|\x{2013}' "$file" 2>/dev/null; then
        err "$file: contains em/en dash"
        grep -Pn '\x{2014}|\x{2013}' "$file" | head -3 | sed 's/^/    /'
        em_found=1
    fi
done < <(find "$EXERCISES_DIR" -name "*.md" \
    ! -name "prompt.md" \
    ! -path "*/${SKIP_TOPIC}/*" \
    -type f | sort)

[[ $em_found -eq 0 ]] && ok "No em/en dashes found"

# -----------------------------------------------------------------------
# 3. Prohibited verification patterns
# -----------------------------------------------------------------------
sep "Prohibited verification patterns"

pat_found=0
while IFS= read -r file; do
    if grep -qE \
        'grep -q[^|]*&&[[:space:]]*echo[[:space:]]+(SUCCESS|PASS|PASSED)[^a-zA-Z]|timeout[^|]+\|\|[[:space:]]*echo[[:space:]]+BLOCKED' \
        "$file" 2>/dev/null; then
        err "$file: prohibited verification pattern"
        grep -nE \
            'grep -q[^|]*&&[[:space:]]*echo[[:space:]]+(SUCCESS|PASS|PASSED)[^a-zA-Z]|timeout[^|]+\|\|[[:space:]]*echo[[:space:]]+BLOCKED' \
            "$file" | head -3 | sed 's/^/    /'
        pat_found=1
    fi
done < <(find "$EXERCISES_DIR" -name "*-homework*.md" \
    ! -path "*/${SKIP_TOPIC}/*" \
    -type f | sort)

[[ $pat_found -eq 0 ]] && ok "No prohibited patterns found"

# -----------------------------------------------------------------------
# 4. :latest image tag check (YAML image: references only, not prose)
# -----------------------------------------------------------------------
sep ":latest image tag check"

latest_found=0
while IFS= read -r file; do
    if grep -qP '^\s+image:\s+\S+:latest\b' "$file" 2>/dev/null; then
        err "$file: uses :latest image tag"
        grep -nP '^\s+image:\s+\S+:latest\b' "$file" | head -3 | sed 's/^/    /'
        latest_found=1
    fi
done < <(find "$EXERCISES_DIR" -name "*.md" \
    ! -name "prompt.md" \
    ! -path "*/${SKIP_TOPIC}/*" \
    -type f | sort)

[[ $latest_found -eq 0 ]] && ok "No :latest image tags found"

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------
echo ""
echo "========================================"
if [[ $ERRORS -eq 0 ]]; then
    echo "All checks passed."
    exit 0
else
    echo "$ERRORS error(s) found."
    exit 1
fi
