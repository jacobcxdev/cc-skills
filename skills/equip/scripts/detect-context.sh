#!/usr/bin/env bash
# detect-context.sh — Analyse current working directory and output structured JSON.
# Collects raw environment signals. No decisions — Claude interprets these.
# Dependencies: git, rg (ripgrep). No jq. Must complete in <1s.
set -euo pipefail

CWD="${1:-.}"
cd "$CWD" 2>/dev/null || cd .

# --- Helpers ---
json_arr() {
  # Usage: json_arr "a" "b" "c" → ["a","b","c"]
  local out="["
  local first=true
  for item in "$@"; do
    [ -z "$item" ] && continue
    $first && first=false || out+=","
    # Escape quotes and backslashes
    item="${item//\\/\\\\}"
    item="${item//\"/\\\"}"
    out+="\"$item\""
  done
  printf '%s]' "$out"
}

json_str() {
  # Usage: json_str "value" → "value"  |  json_str "" → null
  local v="${1:-}"
  [ -z "$v" ] && { printf 'null'; return; }
  v="${v//\\/\\\\}"
  v="${v//\"/\\\"}"
  printf '"%s"' "$v"
}

has_file() { [ -n "$(rg --files --max-depth "${2:-3}" -g "$1" 2>/dev/null | head -1)" ]; }

# --- Languages ---
langs=()
has_file '*.swift'  && langs+=(swift)
has_file '*.py'     && langs+=(python)
has_file '*.go'     && langs+=(go)
has_file '*.ts'     && langs+=(typescript)
has_file '*.tsx'    && [[ ! " ${langs[*]:-} " =~ " typescript " ]] && langs+=(typescript)
has_file '*.js'     && langs+=(javascript)
has_file '*.jsx'    && [[ ! " ${langs[*]:-} " =~ " javascript " ]] && langs+=(javascript)
has_file '*.rs'     && langs+=(rust)
has_file '*.java'   && langs+=(java)
has_file '*.cpp' || has_file '*.cc' && langs+=(cpp)
has_file '*.c' 1    && langs+=(c)  # depth 1 only to avoid false positives

# --- Frameworks ---
frameworks=()
has_file '*.xcodeproj' 2 || has_file '*.xcworkspace' 2 && frameworks+=(xcode)
[ -f Package.swift ] && {
  rg -q 'SwiftUI'   Package.swift 2>/dev/null && frameworks+=(swiftui)
  rg -q 'UIKit'     Package.swift 2>/dev/null && frameworks+=(uikit)
  rg -q 'Combine'   Package.swift 2>/dev/null && frameworks+=(combine)
  rg -q 'SwiftData' Package.swift 2>/dev/null && frameworks+=(swiftdata)
}
# Check swift imports if Package.swift didn't cover them
if [[ " ${langs[*]:-} " =~ " swift " ]]; then
  for fw in SwiftUI UIKit Combine SwiftData; do
    lc="$(echo "$fw" | tr '[:upper:]' '[:lower:]')"
    [[ " ${frameworks[*]:-} " =~ " $lc " ]] && continue
    rg -q "import $fw" --type swift --max-depth 4 2>/dev/null && frameworks+=("$lc")
  done
fi
# Python
[ -f manage.py ]         && frameworks+=(django)
rg -q 'fastapi' pyproject.toml requirements.txt setup.py 2>/dev/null && frameworks+=(fastapi)
rg -q 'flask'   pyproject.toml requirements.txt setup.py 2>/dev/null && frameworks+=(flask)
# JS/TS
[ -f next.config.js ] || [ -f next.config.ts ] || [ -f next.config.mjs ] && frameworks+=(nextjs)
[ -f package.json ] && {
  rg -q '"react"'   package.json 2>/dev/null && frameworks+=(react)
  rg -q '"vue"'     package.json 2>/dev/null && frameworks+=(vue)
  rg -q '"svelte"'  package.json 2>/dev/null && frameworks+=(svelte)
  rg -q '"angular"' package.json 2>/dev/null && frameworks+=(angular)
}
# Go
rg -q 'gin-gonic' go.mod 2>/dev/null && frameworks+=(gin)
# Rust
rg -q 'actix-web\|axum\|rocket' Cargo.toml 2>/dev/null && frameworks+=(rust-web)

# --- Platforms ---
platforms=()
if [[ " ${frameworks[*]:-} " =~ " xcode " ]] || [[ " ${langs[*]:-} " =~ " swift " ]]; then
  [ -f Package.swift ] && {
    rg -q '\.iOS'      Package.swift 2>/dev/null && platforms+=(ios)
    rg -q '\.macOS'    Package.swift 2>/dev/null && platforms+=(macos)
    rg -q '\.tvOS'     Package.swift 2>/dev/null && platforms+=(tvos)
    rg -q '\.watchOS'  Package.swift 2>/dev/null && platforms+=(watchos)
    rg -q '\.visionOS' Package.swift 2>/dev/null && platforms+=(visionos)
  }
  [ ${#platforms[@]} -eq 0 ] && [[ " ${frameworks[*]:-} " =~ " xcode " ]] && platforms+=(ios)
fi
[ -f Dockerfile ] && platforms+=(docker)

# --- Workflow tools ---
wf_tools=()
[ -f Makefile ]       && wf_tools+=(make)
[ -f justfile ]       && wf_tools+=(just)
[ -d .github/workflows ] && wf_tools+=(github-actions)
[ -f .gitlab-ci.yml ] && wf_tools+=(gitlab-ci)
[ -f Package.swift ]  && wf_tools+=(spm)
[ -f Cargo.toml ]     && wf_tools+=(cargo)
[ -f go.mod ]         && wf_tools+=(go-mod)
[ -f package.json ]   && wf_tools+=(npm)

# --- Git state ---
is_repo=false
branch="" dirty_count=0 staged_count=0 untracked_count=0
ahead=0 behind=0 merge_in_progress=false rebase_in_progress=false
dirty_files_json="[]" recent_files_json="[]" hot_dirs_json="[]" recent_commits_json="[]"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_repo=true
  branch="$(git branch --show-current 2>/dev/null || true)"

  porcelain="$(git status --porcelain 2>/dev/null || true)"
  if [ -n "$porcelain" ]; then
    dirty_count="$(echo "$porcelain" | wc -l | tr -d ' ')"
    staged_count="$(echo "$porcelain"  | rg -c '^[MADRC]'  2>/dev/null || echo 0)"
    untracked_count="$(echo "$porcelain" | rg -c '^\?\?' 2>/dev/null || echo 0)"

    # Dirty file list
    mapfile -t df < <(echo "$porcelain" | cut -c4- | head -20)
    dirty_files_json="$(json_arr "${df[@]}")"
  fi

  if git rev-parse '@{upstream}' >/dev/null 2>&1; then
    ahead="$(git rev-list --count '@{upstream}..HEAD' 2>/dev/null || echo 0)"
    behind="$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)"
  fi

  gd="$(git rev-parse --git-dir 2>/dev/null)"
  [ -f "$gd/MERGE_HEAD" ] && merge_in_progress=true
  { [ -d "$gd/rebase-merge" ] || [ -d "$gd/rebase-apply" ]; } && rebase_in_progress=true

  # Recent files (last 3 commits)
  mapfile -t rf < <(git diff --name-only HEAD~3 2>/dev/null | head -20 || true)
  [ ${#rf[@]} -gt 0 ] && recent_files_json="$(json_arr "${rf[@]}")"

  # Hot directories
  if [ ${#rf[@]} -gt 0 ]; then
    mapfile -t hd < <(printf '%s\n' "${rf[@]}" | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -5 | awk '{print $2}')
    [ ${#hd[@]} -gt 0 ] && hot_dirs_json="$(json_arr "${hd[@]}")"
  fi

  # Recent commit subjects
  mapfile -t rc < <(git log --oneline -5 --format='%s' 2>/dev/null || true)
  [ ${#rc[@]} -gt 0 ] && recent_commits_json="$(json_arr "${rc[@]}")"
fi

# --- Workflow signals ---
gsd_active=false;    [ -f .planning/config.json ] && gsd_active=true
ci_detected=false;   [ -d .github/workflows ] || [ -f .gitlab-ci.yml ] || [ -f Jenkinsfile ] && ci_detected=true
equip_prior=false;   [ -f .omc/state/equip-session.json ] && equip_prior=true

omc_state="null"
if [ -d .omc/state ]; then
  am="$(rg -l '"active":\s*true' .omc/state/*.json 2>/dev/null | head -1 | sed 's|.*/||;s|-state\.json||' || true)"
  [ -n "$am" ] && omc_state="\"$am\""
fi

# Test/build command detection
test_cmd="null" build_cmd="null"
[[ " ${langs[*]:-} " =~ " swift " ]] && test_cmd='"swift test"'
{ [ -f pytest.ini ] || rg -q 'pytest' pyproject.toml 2>/dev/null; } && test_cmd='"pytest"'
[ -f package.json ] && rg -q '"test"' package.json 2>/dev/null && test_cmd='"npm test"'
[ -f go.mod ]       && test_cmd='"go test ./..."'
[ -f Cargo.toml ]   && test_cmd='"cargo test"'

[[ " ${frameworks[*]:-} " =~ " xcode " ]] && build_cmd='"xcodebuild"'
[ -f package.json ] && rg -q '"build"' package.json 2>/dev/null && build_cmd='"npm run build"'
[ -f go.mod ]       && build_cmd='"go build ./..."'
[ -f Cargo.toml ]   && build_cmd='"cargo build"'

# --- Risks ---
large_diff=false
if [ "$is_repo" = true ]; then
  ds="$(git diff --shortstat 2>/dev/null || true)"
  echo "$ds" | rg -q '[0-9]{3,} insertion|[0-9]{3,} deletion' 2>/dev/null && large_diff=true
fi
merge_conflict=false
[ "$is_repo" = true ] && [ -n "$(git ls-files -u 2>/dev/null | head -1)" ] && merge_conflict=true
ahead_of_remote=false; [ "$ahead" -gt 0 ] 2>/dev/null && ahead_of_remote=true
has_test_artifacts=false
has_file '*.xcresult' 3 && has_test_artifacts=true
[ -d test-results ]     && has_test_artifacts=true

# --- Observations (human-readable) ---
obs=()
if [[ " ${frameworks[*]:-} " =~ " xcode " ]]; then
  o="iOS/macOS project"
  fw_parts=()
  for f in swiftui uikit combine swiftdata; do
    [[ " ${frameworks[*]:-} " =~ " $f " ]] && fw_parts+=("$f")
  done
  [ ${#fw_parts[@]} -gt 0 ] && o="$o with $(IFS=', '; echo "${fw_parts[*]}")"
  [ ${#platforms[@]} -gt 0 ] && o="$o targeting $(IFS=', '; echo "${platforms[*]}")"
  obs+=("$o")
elif [[ " ${langs[*]:-} " =~ " python " ]]; then
  o="Python project"
  [[ " ${frameworks[*]:-} " =~ " django " ]]  && o="Django project"
  [[ " ${frameworks[*]:-} " =~ " fastapi " ]] && o="FastAPI project"
  obs+=("$o")
elif [[ " ${langs[*]:-} " =~ " typescript " ]] || [[ " ${langs[*]:-} " =~ " javascript " ]]; then
  o="JavaScript/TypeScript project"
  [[ " ${frameworks[*]:-} " =~ " nextjs " ]] && o="Next.js project"
  [[ " ${frameworks[*]:-} " =~ " react " ]] && o="React project"
  obs+=("$o")
elif [[ " ${langs[*]:-} " =~ " go " ]]; then obs+=("Go project")
elif [[ " ${langs[*]:-} " =~ " rust " ]]; then obs+=("Rust project")
elif [ ${#langs[@]} -eq 0 ]; then obs+=("No recognised project structure detected")
fi

if [ "$is_repo" = true ]; then
  o="On branch ${branch:-<detached>}"
  [ "$dirty_count" -gt 0 ] && o="$o with $dirty_count dirty files"
  obs+=("$o")
  [ "$merge_in_progress" = true ]  && obs+=("Merge in progress")
  [ "$rebase_in_progress" = true ] && obs+=("Rebase in progress")
  [ "$merge_conflict" = true ]     && obs+=("Merge conflicts detected")
  [ "$ahead" -gt 0 ]              && obs+=("$ahead commits ahead of remote")
  [ "$behind" -gt 0 ]             && obs+=("$behind commits behind remote")

  if [ ${#rc[@]} -gt 0 ]; then
    fc="$(printf '%s\n' "${rc[@]}" | rg -ic '^fix|^bug|^hotfix' 2>/dev/null || echo 0)"
    ac="$(printf '%s\n' "${rc[@]}" | rg -ic '^feat|^add' 2>/dev/null || echo 0)"
    [ "$fc" -gt 0 ] && obs+=("Recent commits are bug-fix focused ($fc of last ${#rc[@]})")
    [ "$ac" -gt 0 ] && obs+=("Recent commits are feature-focused ($ac of last ${#rc[@]})")
  fi
fi
[ "$gsd_active" = true ]        && obs+=("GSD project active")
[ "$has_test_artifacts" = true ] && obs+=("Test artifacts present")
[ "$large_diff" = true ]        && obs+=("Large uncommitted diff")
[ "$equip_prior" = true ]       && obs+=("Prior equip state exists")

# --- Output ---
cat <<ENDJSON
{
  "project": {
    "languages": $(json_arr "${langs[@]}"),
    "frameworks": $(json_arr "${frameworks[@]}"),
    "platforms": $(json_arr "${platforms[@]}"),
    "workflow_tools": $(json_arr "${wf_tools[@]}")
  },
  "git": {
    "is_repo": $is_repo,
    "branch": $(json_str "$branch"),
    "dirty_count": $dirty_count,
    "staged_count": $staged_count,
    "untracked_count": $untracked_count,
    "ahead": $ahead,
    "behind": $behind,
    "merge_in_progress": $merge_in_progress,
    "rebase_in_progress": $rebase_in_progress,
    "dirty_files": $dirty_files_json
  },
  "activity": {
    "recent_files": $recent_files_json,
    "hot_directories": $hot_dirs_json,
    "recent_commit_subjects": $recent_commits_json
  },
  "workflow": {
    "gsd_active": $gsd_active,
    "omc_state": $omc_state,
    "ci_detected": $ci_detected,
    "test_command": $test_cmd,
    "build_command": $build_cmd
  },
  "risks": {
    "large_diff": $large_diff,
    "merge_conflict": $merge_conflict,
    "ahead_of_remote": $ahead_of_remote,
    "has_test_artifacts": $has_test_artifacts
  },
  "state": {
    "equip_prior": $equip_prior
  },
  "observations": $(json_arr "${obs[@]}")
}
ENDJSON
