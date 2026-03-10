#!/usr/bin/env bash
# plan-equip.sh — Thin signal enhancer for equip routing.
# Claude does the heavy lifting (intent scoring, pack selection, evidence synthesis).
# This script handles what bash is better at: hashing, file stats, prior state comparison.
#
# Usage: plan-equip.sh <detect-output.json> [prior-state.json]
# Output: JSON with hash, branch classification, and prior state delta.
set -euo pipefail

DETECT_FILE="${1:--}"
PRIOR_FILE="${2:-}"

# Read detect output
if [ "$DETECT_FILE" = "-" ]; then
  detect="$(cat)"
else
  detect="$(cat "$DETECT_FILE")"
fi

# --- Compute detect hash (for delta detection on re-invocation) ---
detect_hash="$(echo "$detect" | shasum -a 256 | cut -c1-16)"

# --- Branch classification (mechanical pattern matching) ---
branch="$(echo "$detect" | rg -o '"branch":\s*"([^"]*)"' -r '$1' 2>/dev/null | head -1 || true)"
branch_class="unknown"
branch_prefix=""
case "$branch" in
  fix/*|bug/*|hotfix/*)       branch_class="debug";    branch_prefix="${branch%%/*}" ;;
  feat/*|feature/*|add/*)     branch_class="feature";  branch_prefix="${branch%%/*}" ;;
  refactor/*|cleanup/*|chore/*) branch_class="refactor"; branch_prefix="${branch%%/*}" ;;
  release/*|deploy/*)         branch_class="release";  branch_prefix="${branch%%/*}" ;;
  review/*|pr/*)              branch_class="review";   branch_prefix="${branch%%/*}" ;;
  test/*|tests/*)             branch_class="verify";   branch_prefix="${branch%%/*}" ;;
  main|master|develop)        branch_class="trunk";    branch_prefix="$branch" ;;
  "")                         branch_class="none";     branch_prefix="" ;;
esac

# --- Prior state comparison ---
prior_hash=""
prior_task=""
prior_base_json="[]"
has_prior=false
hash_changed=true

if [ -n "$PRIOR_FILE" ] && [ -f "$PRIOR_FILE" ]; then
  has_prior=true
  prior_hash="$(rg -o '"detect_hash":\s*"([^"]*)"' -r '$1' "$PRIOR_FILE" 2>/dev/null | head -1 || true)"
  prior_task="$(rg -o '"task_pack":\s*"([^"]*)"' -r '$1' "$PRIOR_FILE" 2>/dev/null | head -1 || true)"
  prior_base_raw="$(rg -o '"base_packs":\s*\[([^\]]*)\]' -r '$1' "$PRIOR_FILE" 2>/dev/null | head -1 || true)"
  [ -n "$prior_base_raw" ] && prior_base_json="[${prior_base_raw}]"

  if [ "$prior_hash" = "$detect_hash" ]; then
    hash_changed=false
  fi
fi

# --- Quick file counts in hot directories (useful context for Claude) ---
dirty_count="$(echo "$detect" | rg -o '"dirty_count":\s*([0-9]+)' -r '$1' 2>/dev/null | head -1 || echo 0)"
gsd_active="$(echo "$detect" | rg -o '"gsd_active":\s*(true|false)' -r '$1' 2>/dev/null | head -1 || echo false)"

# --- Output ---
cat <<ENDJSON
{
  "detect_hash": "$detect_hash",
  "branch": {
    "name": $(if [ -n "$branch" ]; then b="${branch//\\/\\\\}"; b="${b//\"/\\\"}"; printf '"%s"' "$b"; else printf 'null'; fi),
    "class": "$branch_class",
    "prefix": $(if [ -n "$branch_prefix" ]; then p="${branch_prefix//\\/\\\\}"; p="${p//\"/\\\"}"; printf '"%s"' "$p"; else printf 'null'; fi)
  },
  "prior_state": {
    "exists": $has_prior,
    "hash_changed": $hash_changed,
    "previous_task": $(if [ -n "$prior_task" ]; then t="${prior_task//\\/\\\\}"; t="${t//\"/\\\"}"; printf '"%s"' "$t"; else printf 'null'; fi),
    "previous_base": $prior_base_json
  },
  "summary": {
    "dirty_count": $dirty_count,
    "gsd_active": $gsd_active
  }
}
ENDJSON
