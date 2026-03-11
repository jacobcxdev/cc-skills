#!/usr/bin/env zsh
# detect-context.zsh — Analyse current working directory and output structured JSON.
# Collects raw environment signals. No decisions — Claude interprets these.
# Dependencies: git, rg (ripgrep). No jq. Must complete in <1s.
set -euo pipefail

CWD="${1:-.}"
cd "$CWD" 2>/dev/null || cd .

# --- Fast-exit guard ---
# Marker-first: check for project indicators (cheap stats), then blocklist if none found.
_has_marker=false
[ -d .git ] && _has_marker=true
if ! $_has_marker; then
  for _f in Package.swift package.json go.mod Cargo.toml pyproject.toml setup.py \
            Makefile CMakeLists.txt pubspec.yaml Gemfile build.gradle build.gradle.kts; do
    [ -f "$_f" ] && { _has_marker=true; break; }
  done
fi
if ! $_has_marker; then
  local _xc=(*.xcodeproj(N/) *.xcworkspace(N/) *.sln(N))
  [[ ${#_xc[@]} -gt 0 ]] && _has_marker=true
fi

if ! $_has_marker; then
  # Resolve physical paths to handle macOS symlinks (/tmp → /private/tmp, etc.)
  _cwd_real="$(pwd -P)"
  _home_real="$(cd "$HOME" && pwd -P)"
  _skip=false

  # Exact home directory
  [[ "$_cwd_real" == "$_home_real" ]] && _skip=true
  # Known non-project subdirectories of home
  if ! $_skip; then
    for _prefix in Documents Downloads Desktop Library Pictures Music Movies; do
      [[ "$_cwd_real" == "$_home_real/$_prefix"* ]] && { _skip=true; break; }
    done
  fi
  # Temp directories (physical paths on macOS)
  [[ "$_cwd_real" == /private/tmp* || "$_cwd_real" == /private/var/tmp* ]] && _skip=true

  if $_skip; then
    cat <<'ENDJSON'
{
  "fast_exit": true,
  "observations": ["No project context detected. Fast-exit from non-project directory."]
}
ENDJSON
    exit 0
  fi
fi

# --- Helpers ---
json_arr() {
  # Usage: json_arr "a" "b" "c" → ["a","b","c"]
  local out="["
  local first=true
  for item in "$@"; do
    [ -z "$item" ] && continue
    $first && first=false || out+=","
    # Escape backslashes, quotes, and control characters
    item="${item//\\/\\\\}"
    item="${item//\"/\\\"}"
    item="${item//$'\n'/\\n}"
    item="${item//$'\t'/\\t}"
    item="${item//$'\r'/\\r}"
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
has_file '*.java' 5 && langs+=(java)
has_file '*.cpp' || has_file '*.cc' && langs+=(cpp)
has_file '*.c' 2    && langs+=(c)
has_file '*.m' 3    && langs+=(objc)
has_file '*.cs'  3  && langs+=(csharp)
has_file '*.kt'  3  && langs+=(kotlin)
has_file '*.dart' 3 && langs+=(dart)
has_file '*.rb'  2  && langs+=(ruby)
has_file '*.sh'  4 || has_file '*.zsh' 4 && langs+=(shell)

# --- Frameworks ---
frameworks=()
local _xcode_dirs=(*.xcodeproj(N/) *.xcworkspace(N/) */*.xcodeproj(N/) */*.xcworkspace(N/))
[ ${#_xcode_dirs[@]} -gt 0 ] && frameworks+=(xcode)
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
rg -q 'actix-web|axum|rocket' Cargo.toml 2>/dev/null && frameworks+=(rust-web)
# Kotlin/Android
has_file 'AndroidManifest.xml' 4 && frameworks+=(android)
# .NET
has_file '*.sln' 2 || has_file '*.csproj' 3 && frameworks+=(dotnet)
# Dart/Flutter
[ -f pubspec.yaml ] && rg -q 'flutter' pubspec.yaml 2>/dev/null && frameworks+=(flutter)
# PFW (Point-Free)
pfw_pkgs=()
if [[ " ${langs[*]:-} " =~ " swift " ]] && [ -f Package.swift ]; then
  if rg -q 'pointfreeco' Package.swift 2>/dev/null; then
    frameworks+=(pfw)
    local _pfw_map=(
      'swift-composable-architecture:composable-architecture'
      'swift-dependencies:dependencies'
      'swift-case-paths:case-paths'
      'swift-perception:perception'
      'swift-sharing:sharing'
      'swift-snapshot-testing:snapshot-testing'
      'swift-custom-dump:custom-dump'
      'swift-identified-collections:identified-collections'
      'swift-issue-reporting:issue-reporting'
      'swift-macro-testing:macro-testing'
      'swift-navigation:swift-navigation'
      'sqlite-data:sqlite-data'
      'swift-structured-queries:structured-queries'
    )
    for entry in "${_pfw_map[@]}"; do
      local pkg="${entry%%:*}" skill="${entry##*:}"
      rg -q "$pkg" Package.swift 2>/dev/null && pfw_pkgs+=("$skill")
    done
  fi
fi
# Android: source files are deeply nested (app/src/main/java/…); search deeper only if needed
if [[ " ${frameworks[*]:-} " =~ " android " ]]; then
  [[ ! " ${langs[*]:-} " =~ " kotlin " ]] && has_file '*.kt'   10 && langs+=(kotlin)
  [[ ! " ${langs[*]:-} " =~ " java "   ]] && has_file '*.java' 10 && langs+=(java)
fi

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
[[ " ${frameworks[*]:-} " =~ " android " ]] && platforms+=(android)

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
[ -f Gemfile ]        && wf_tools+=(bundler)
[ -f pubspec.yaml ]   && wf_tools+=(pub)
has_file 'build.gradle' 2 || has_file 'build.gradle.kts' 2 && wf_tools+=(gradle)
[ -d .config/azure-pipelines ] || [ -f azure-pipelines.yml ] && wf_tools+=(azure-pipelines)

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
    local _df_out="$(echo "$porcelain" | cut -c4- | head -20)"
    df=()
    [[ -n "$_df_out" ]] && df=("${(@f)_df_out}")
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
  local _rf_out="$(git diff --name-only HEAD~3 2>/dev/null | head -20 || true)"
  rf=()
  [[ -n "$_rf_out" ]] && rf=("${(@f)_rf_out}")
  [ ${#rf[@]} -gt 0 ] && recent_files_json="$(json_arr "${rf[@]}")"

  # Hot directories
  if [ ${#rf[@]} -gt 0 ]; then
    local _hd_out="$(printf '%s\n' "${rf[@]}" | grep '/' | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn | head -5 | awk '{print $2}')"
    hd=()
    [[ -n "$_hd_out" ]] && hd=("${(@f)_hd_out}")
    [ ${#hd[@]} -gt 0 ] && hot_dirs_json="$(json_arr "${hd[@]}")"
  fi

  # Recent commit subjects
  local _rc_out="$(git log --oneline -5 --format='%s' 2>/dev/null || true)"
  rc=()
  [[ -n "$_rc_out" ]] && rc=("${(@f)_rc_out}")
  [ ${#rc[@]} -gt 0 ] && recent_commits_json="$(json_arr "${rc[@]}")"
fi

# --- Workflow signals ---
gsd_active=false;    [ -f .planning/config.json ] && gsd_active=true
ci_detected=false;   [ -d .github/workflows ] || [ -f .gitlab-ci.yml ] || [ -f Jenkinsfile ] || [ -d .config/azure-pipelines ] || [ -f azure-pipelines.yml ] && ci_detected=true
equip_prior=false;   [ -f .claude/equip-session.json ] && equip_prior=true

omc_state="null"
if [ -d .omc/state ]; then
  am="$(rg -l '"active":\s*true' .omc/state/*.json(N) 2>/dev/null | head -1 | sed 's|.*/||;s|-state\.json||' || true)"
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
[ -f pubspec.yaml ]       && test_cmd='"flutter test"'  && build_cmd='"flutter build"'
has_file 'build.gradle' 2 && test_cmd='"./gradlew test"' && build_cmd='"./gradlew build"'
has_file '*.sln' 2        && test_cmd='"dotnet test"'   && build_cmd='"dotnet build"'

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
  [ ${#fw_parts[@]} -gt 0 ] && o="$o with ${(j:, :)fw_parts}"
  [ ${#platforms[@]} -gt 0 ] && o="$o targeting ${(j:, :)platforms}"
  obs+=("$o")
elif [[ " ${langs[*]:-} " =~ " go " ]]; then obs+=("Go project")
elif [[ " ${langs[*]:-} " =~ " rust " ]]; then obs+=("Rust project")
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
elif [[ " ${langs[*]:-} " =~ " swift " ]]; then obs+=("Swift project")
elif [[ " ${langs[*]:-} " =~ " objc " ]]; then obs+=("Objective-C project")
elif [[ " ${langs[*]:-} " =~ " c " ]] || [[ " ${langs[*]:-} " =~ " cpp " ]]; then obs+=("C/C++ project")
elif [[ " ${langs[*]:-} " =~ " kotlin " ]]; then
  o="Kotlin project"
  [[ " ${frameworks[*]:-} " =~ " android " ]] && o="Android project"
  obs+=("$o")
elif [[ " ${langs[*]:-} " =~ " dart " ]]; then
  o="Dart project"
  [[ " ${frameworks[*]:-} " =~ " flutter " ]] && o="Flutter project"
  obs+=("$o")
elif [[ " ${langs[*]:-} " =~ " csharp " ]]; then
  o="C# project"
  [[ " ${frameworks[*]:-} " =~ " dotnet " ]] && o=".NET project"
  obs+=("$o")
elif [[ " ${langs[*]:-} " =~ " ruby " ]]; then obs+=("Ruby project")
elif [[ " ${langs[*]:-} " =~ " shell " ]]; then obs+=("Shell project")
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
[ ${#pfw_pkgs[@]} -gt 0 ]       && obs+=("PFW packages: ${(j:, :)pfw_pkgs}")
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
    "workflow_tools": $(json_arr "${wf_tools[@]}"),
    "pfw_packages": $(json_arr "${pfw_pkgs[@]}")
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
