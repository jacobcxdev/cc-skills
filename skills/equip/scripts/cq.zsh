#!/bin/zsh
# cq - AI Usage limit checker
# Check remaining quota for Claude, Codex, and Gemini providers
# Usage: cq [--json] [--refresh] [claude|codex|gemini]

set -o no_monitor

main() {
  local json_mode=0 refresh=0
  local -a providers
  local tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT

  # Cache config
  local cache_dir="$HOME/.cache/cq"
  local ttl=${CQ_TTL:-30}

  for arg in "$@"; do
    case "$arg" in
      --json) json_mode=1 ;;
      --refresh) refresh=1 ;;
      claude|codex|gemini) providers+=("$arg") ;;
      -h|--help)
        echo "Usage: cq [--json] [--refresh] [claude|codex|gemini]"
        echo "Check AI provider usage limits"
        echo "  --refresh  Bypass cache and fetch fresh data"
        echo "  CQ_TTL=N   Cache TTL in seconds (default: 30)"
        return 0 ;;
      *) echo "cq: unknown argument '$arg'" >&2; return 1 ;;
    esac
  done
  (( ${#providers[@]} == 0 )) && providers=(claude codex gemini)

  # Precompute shared values
  local now_epoch=$(date +%s)

  # Ensure cache directory exists
  mkdir -p "$cache_dir" 2>/dev/null

  # Run providers
  if (( ${#providers[@]} > 1 )); then
    for p in "${providers[@]}"; do
      _cq_fetch_or_cache "$p" "$tmpdir" "$cache_dir" "$ttl" "$refresh" "$now_epoch" &
    done
    wait
  else
    _cq_fetch_or_cache "${providers[1]}" "$tmpdir" "$cache_dir" "$ttl" "$refresh" "$now_epoch"
  fi

  # Output
  if (( json_mode )); then
    local parts=()
    for p in "${providers[@]}"; do
      [[ -f "$tmpdir/${p}.json" ]] && parts+=("\"$p\":$(< "$tmpdir/${p}.json")")
    done
    local IFS=","
    if [[ -t 1 ]]; then
      echo "{${parts[*]}}" | jq .
    else
      echo "{${parts[*]}}" | jq -c .
    fi
  else
    echo
    local i=1
    for p in "${providers[@]}"; do
      local last=0
      (( i == ${#providers[@]} )) && last=1
      _cq_display "${(C)p}" "$tmpdir/${p}.json" "$last" "$now_epoch"
      (( i++ ))
    done
  fi
}

# ─── Utilities ────────────────────────────────────────────

_cq_reltime() {
  local target=$1 now=$2
  [[ -z "$target" || "$target" == "0" || "$target" == "null" ]] && { REPLY=""; return 1; }
  _cq_fmt_duration $(( target - now ))
}

# Map window name to period in seconds
_cq_period_s() {
  case "$1" in
    5h) REPLY=18000 ;; 7d) REPLY=604800 ;; *) REPLY=0; return 1 ;;
  esac
}

# Format seconds as human-readable duration (negative → "now")
_cq_fmt_duration() {
  local s=${1:-0}
  (( s <= 0 )) && { REPLY="now"; return; }
  local d=$(( s / 86400 )) h=$(( (s % 86400) / 3600 )) m=$(( (s % 3600) / 60 ))
  if (( d > 0 )); then
    (( h > 0 )) && REPLY="${d}d ${h}h" || REPLY="${d}d"
  elif (( h > 0 )); then
    (( m > 0 )) && REPLY="${h}h ${m}m" || REPLY="${h}h"
  elif (( m > 0 )); then REPLY="${m}m"
  else REPLY="<1m"
  fi
}

# Compute pace: expected remaining % based on time elapsed
# Args: period_s reset_epoch now_epoch
_cq_pace() {
  local period_s=$1 reset_epoch=$2 now_epoch=$3
  local elapsed=$(( period_s - (reset_epoch - now_epoch) ))
  (( elapsed < 0 )) && elapsed=0
  (( elapsed > period_s )) && elapsed=$period_s
  REPLY=$(( 100 - (elapsed * 100 / period_s) ))
}

# Compute seconds until exhaustion at current consumption rate
# Args: period_s reset_epoch now_epoch pct
_cq_burndown() {
  local period_s=$1 reset_epoch=$2 now_epoch=$3 pct=$4
  (( pct <= 0 )) && { REPLY="0"; return; }
  local elapsed=$(( period_s - (reset_epoch - now_epoch) ))
  (( elapsed <= 0 )) && { REPLY=""; return 1; }
  local used=$(( 100 - pct ))
  (( used <= 0 )) && { REPLY=""; return 1; }
  REPLY=$(( pct * elapsed / used ))
}

# Check if cache file is fresh (mtime within TTL)
_cq_cache_fresh() {
  local file=$1 ttl=$2 now=$3
  [[ ! -f "$file" ]] && return 1
  zmodload -F zsh/stat b:zstat 2>/dev/null
  local mtime
  zstat -A mtime +mtime "$file" 2>/dev/null || return 1
  (( now - mtime < ttl ))
}

# Fetch provider data or serve from cache
_cq_fetch_or_cache() {
  local provider=$1 tmpdir=$2 cache_dir=$3 ttl=$4 refresh=$5 now_epoch=$6
  local cache_file="$cache_dir/${provider}.json"
  if (( ! refresh )) && _cq_cache_fresh "$cache_file" "$ttl" "$now_epoch"; then
    cp "$cache_file" "$tmpdir/${provider}.json"
  else
    _cq_$provider "$tmpdir" "$now_epoch"
    [[ -f "$tmpdir/${provider}.json" ]] && cp "$tmpdir/${provider}.json" "$cache_file"
  fi
}

_cq_bar() {
  local pct=${1:-0} width=20 force_color=${2:-} expected_pct=${3:-}
  (( pct > 100 )) && pct=100
  (( pct < 0 )) && pct=0
  local filled=$(( pct * width / 100 ))
  (( filled > width )) && filled=$width
  local color
  if [[ -n "$force_color" ]]; then color="$force_color"
  elif (( pct > 50 )); then color="\033[32m"
  elif (( pct > 20 )); then color="\033[33m"
  else color="\033[31m"
  fi
  # Marker position (-1 = no marker)
  local marker=-1 marker_color=""
  if [[ -n "$expected_pct" ]]; then
    marker=$(( expected_pct * width / 100 ))
    (( marker > width )) && marker=$width
    (( marker < 0 )) && marker=0
    if (( pct >= expected_pct )); then marker_color="\033[32m"
    else marker_color="\033[31m"
    fi
  fi
  local i bar=""
  for (( i = 0; i < width; i++ )); do
    if (( marker >= 0 && i == marker )); then
      bar+="${marker_color}|\033[0m"
    elif (( i < filled )); then
      bar+="${color}━\033[0m"
    else
      bar+="\033[2m╌\033[0m"
    fi
  done
  printf "%b" "$bar"
}

# ─── Provider: Claude ─────────────────────────────────────

_cq_claude() {
  local out="$1/claude.json" now_epoch=$2

  # Read keychain credentials
  local creds
  creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null) || {
    echo '{"status":"error","error":"not configured"}' > "$out"; return
  }

  [[ -z "$creds" ]] && {
    echo '{"status":"error","error":"not configured"}' > "$out"; return
  }

  # Extract auth fields (single jq call)
  local auth_data
  auth_data=$(printf '%s' "$creds" | jq -r '
    .claudeAiOauth | [.accessToken // "", .refreshToken // "", (.expiresAt // 0 | tostring), .subscriptionType // "unknown"] | @tsv
  ' 2>/dev/null) || {
    echo '{"status":"error","error":"parse_error"}' > "$out"; return
  }

  local token refresh_token expires_at plan
  IFS=$'\t' read -r token refresh_token expires_at plan <<< "$auth_data"

  [[ -z "$token" ]] && {
    echo '{"status":"error","error":"no token"}' > "$out"; return
  }

  # Check expiry (milliseconds) — zsh handles 64-bit integers
  local now_ms=$(( now_epoch * 1000 ))
  if (( expires_at > 0 && expires_at < now_ms )) && [[ -n "$refresh_token" ]]; then
    local rr
    rr=$(curl -s --max-time 10 -X POST \
      -H "Content-Type: application/json" \
      --data-raw "$(jq -n --arg rt "$refresh_token" \
        '{grant_type:"refresh_token",refresh_token:$rt,client_id:"9d1c250a-e61b-44d9-88ed-5944d1962f5e"}')" \
      "https://platform.claude.com/v1/oauth/token")
    local new_token
    new_token=$(printf '%s' "$rr" | jq -r '.access_token // empty' 2>/dev/null)
    if [[ -n "$new_token" ]]; then
      token="$new_token"
      local ei
      ei=$(printf '%s' "$rr" | jq -r '.expires_in // 3600' 2>/dev/null)
      local new_rt
      new_rt=$(printf '%s' "$rr" | jq -r '.refresh_token // empty' 2>/dev/null)
      local updated
      updated=$(printf '%s' "$creds" | jq \
        --arg at "$new_token" \
        --argjson exp $(( now_epoch * 1000 + ei * 1000 )) \
        --arg rt "${new_rt:-$refresh_token}" '
        .claudeAiOauth.accessToken = $at
        | .claudeAiOauth.expiresAt = $exp
        | .claudeAiOauth.refreshToken = $rt
      ')
      security add-generic-password -U -s "Claude Code-credentials" -a "jacob" -w "$updated" 2>/dev/null
    else
      echo '{"status":"error","error":"auth_expired"}' > "$out"; return
    fi
  fi

  # Fetch usage data
  local resp http_code body
  resp=$(curl -s --max-time 10 -w '\n%{http_code}' \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: oauth-2025-04-20" \
    "https://api.anthropic.com/api/oauth/usage")

  http_code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"

  if [[ "$http_code" != "200" ]]; then
    echo "{\"status\":\"error\",\"error\":\"api_error\",\"http\":$http_code}" > "$out"
    return
  fi

  echo "$body" | jq --arg plan "$plan" '
    ({}
      + (if .five_hour then {"5h": {
            remaining_pct: (100 - (.five_hour.utilization // 0) | round),
            resets_at: (.five_hour.resets_at // "" | if . != "" then split(".")[0] | gsub("[+]00:00$";"") | . + "Z" else . end)
          }} else {} end)
      + (if .seven_day then {"7d": {
            remaining_pct: (100 - (.seven_day.utilization // 0) | round),
            resets_at: (.seven_day.resets_at // "" | if . != "" then split(".")[0] | gsub("[+]00:00$";"") | . + "Z" else . end)
          }} else {} end)
    ) as $w | {
      status: (if [$w[].remaining_pct] | any(. <= 0) then "exhausted" else "ok" end),
      plan: $plan,
      windows: $w
    }' > "$out" 2>/dev/null || echo '{"status":"error","error":"parse_error"}' > "$out"
}

# ─── Provider: Codex ──────────────────────────────────────

_cq_codex() {
  local out="$1/codex.json" now_epoch=$2
  local auth_file="$HOME/.codex/auth.json"

  if [[ ! -f "$auth_file" ]]; then
    echo '{"status":"error","error":"not configured"}' > "$out"
    return
  fi

  local token account_id refresh_token auth_data
  auth_data=$(jq -r '[.tokens.access_token // "", .tokens.account_id // ""] | @tsv' "$auth_file" 2>/dev/null)
  IFS=$'\t' read -r token account_id <<< "$auth_data"

  if [[ -z "$token" ]]; then
    echo '{"status":"error","error":"no token"}' > "$out"
    return
  fi

  local resp http_code body
  resp=$(curl -s --max-time 10 -w '\n%{http_code}' \
    -H "Authorization: Bearer $token" \
    -H "ChatGPT-Account-Id: $account_id" \
    "https://chatgpt.com/backend-api/wham/usage")
  http_code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"

  # Refresh on 401/403
  if [[ "$http_code" == "401" || "$http_code" == "403" ]]; then
    refresh_token=$(jq -r '.tokens.refresh_token // empty' "$auth_file" 2>/dev/null)
    if [[ -n "$refresh_token" ]]; then
      local rr
      rr=$(curl -s --max-time 10 -X POST "https://auth0.openai.com/oauth/token" \
        -H "Content-Type: application/json" \
        --data-raw "$(jq -n --arg rt "$refresh_token" \
          '{grant_type:"refresh_token",refresh_token:$rt,client_id:"app_EMoamEEZ73f0CkXaXp7hrann"}')")
      local new_token
      new_token=$(echo "$rr" | jq -r '.access_token // empty' 2>/dev/null)
      if [[ -n "$new_token" ]]; then
        token="$new_token"
        local tmp="$auth_file.tmp.$$"
        jq --arg at "$new_token" \
           --arg rt "$(echo "$rr" | jq -r '.refresh_token // empty')" \
           --arg id "$(echo "$rr" | jq -r '.id_token // empty')" \
           --arg lr "$(date -u +%Y-%m-%dT%H:%M:%S.000000Z)" '
           .tokens.access_token = $at
           | if $rt != "" then .tokens.refresh_token = $rt else . end
           | if $id != "" then .tokens.id_token = $id else . end
           | .last_refresh = $lr
        ' "$auth_file" > "$tmp" && mv "$tmp" "$auth_file"

        resp=$(curl -s --max-time 10 -w '\n%{http_code}' \
          -H "Authorization: Bearer $token" \
          -H "ChatGPT-Account-Id: $account_id" \
          "https://chatgpt.com/backend-api/wham/usage")
        http_code="${resp##*$'\n'}"
        body="${resp%$'\n'*}"
      fi
    fi
  fi

  if [[ "$http_code" != "200" ]]; then
    echo "{\"status\":\"error\",\"error\":\"api_error\",\"http\":$http_code}" > "$out"
    return
  fi

  echo "$body" | jq '
    ({}
      + (if .rate_limit.primary_window then {"5h": {
            remaining_pct: (100 - (.rate_limit.primary_window.used_percent // 0)),
            resets_at: (.rate_limit.primary_window.reset_at // null | if . then (. | tonumber | todate) else "" end)
          }} else {} end)
      + (if .rate_limit.secondary_window then {"7d": {
            remaining_pct: (100 - (.rate_limit.secondary_window.used_percent // 0)),
            resets_at: (.rate_limit.secondary_window.reset_at // null | if . then (. | tonumber | todate) else "" end)
          }} else {} end)
    ) as $w | {
      status: (if [$w[].remaining_pct] | any(. <= 0) then "exhausted" else "ok" end),
      plan: (.plan_type // "unknown"),
      windows: $w
    }' > "$out" 2>/dev/null || echo '{"status":"error","error":"parse_error"}' > "$out"
}

# ─── Provider: Gemini ─────────────────────────────────────

_cq_gemini() {
  local out="$1/gemini.json" now_epoch=$2
  local creds_file="$HOME/.gemini/oauth_creds.json"

  if [[ ! -f "$creds_file" ]]; then
    echo '{"status":"error","error":"not configured"}' > "$out"
    return
  fi

  local token expiry_date refresh_token gem_data
  gem_data=$(jq -r '[.access_token // "", .expiry_date // 0, .refresh_token // ""] | @tsv' "$creds_file" 2>/dev/null)
  IFS=$'\t' read -r token expiry_date refresh_token <<< "$gem_data"

  if [[ -z "$token" ]]; then
    echo '{"status":"error","error":"no token"}' > "$out"
    return
  fi

  # Check expiry (expiry_date is milliseconds epoch, may have decimals)
  local now_ms=$(( now_epoch * 1000 ))
  local exp_int=${expiry_date%%.*}
  if (( exp_int > 0 && exp_int < now_ms )); then
    if [[ -n "$refresh_token" ]]; then
      local rr
      # Read OAuth client credentials from environment or Gemini CLI source
      local gcli_id="${GEMINI_CLIENT_ID:-}" gcli_secret="${GEMINI_CLIENT_SECRET:-}"
      if [[ -z "$gcli_id" ]] && command -v gemini >/dev/null 2>&1; then
        local gcli_bin="$(readlink -f "$(which gemini)" 2>/dev/null || which gemini)"
        local gcli_dir="$(dirname "$gcli_bin")"
        if [[ -d "$gcli_dir" ]]; then
          gcli_id=$(rg -o 'client_id.*?([0-9]+-[a-z0-9]+\.apps\.googleusercontent\.com)' -r '$1' --no-filename "$gcli_dir" 2>/dev/null | head -1)
          gcli_secret=$(rg -o 'client_secret.*?(GOCSPX-[A-Za-z0-9_-]+)' -r '$1' --no-filename "$gcli_dir" 2>/dev/null | head -1)
        fi
      fi
      if [[ -z "$gcli_id" || -z "$gcli_secret" ]]; then
        echo '{"status":"error","error":"gemini_oauth_creds_not_found"}' > "$out"; return
      fi
      rr=$(curl -s --max-time 10 -X POST "https://oauth2.googleapis.com/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        --data-urlencode "grant_type=refresh_token" \
        --data-urlencode "refresh_token=$refresh_token" \
        --data-urlencode "client_id=$gcli_id" \
        --data-urlencode "client_secret=$gcli_secret")
      local new_token expires_in
      new_token=$(echo "$rr" | jq -r '.access_token // empty' 2>/dev/null)
      expires_in=$(echo "$rr" | jq -r '.expires_in // 3600' 2>/dev/null)
      if [[ -n "$new_token" ]]; then
        token="$new_token"
        local new_exp=$(( now_epoch * 1000 + expires_in * 1000 ))
        local tmp="$creds_file.tmp.$$"
        jq --arg at "$new_token" \
           --argjson exp "$new_exp" \
           --arg idt "$(echo "$rr" | jq -r '.id_token // empty')" '
           .access_token = $at | .expiry_date = $exp
           | if $idt != "" then .id_token = $idt else . end
        ' "$creds_file" > "$tmp" && mv "$tmp" "$creds_file"
      else
        echo '{"status":"error","error":"auth_expired"}' > "$out"
        return
      fi
    fi
  fi

  # Fire tier + quota curls in parallel
  local tier="unknown"
  curl -s --max-time 5 -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d '{"metadata":{"ideType":"GEMINI_CLI","pluginType":"GEMINI"}}' \
    "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist" > "$1/_tier" 2>/dev/null &
  curl -s --max-time 10 -w '\n%{http_code}' -X POST \
    -H "Authorization: Bearer $token" \
    "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota" > "$1/_quota" 2>/dev/null &
  wait

  # Parse tier (single jq call)
  if [[ -s "$1/_tier" ]]; then
    local tier_ids
    tier_ids=$(jq -r '[.paidTier.id // "", .currentTier.id // ""] | @tsv' "$1/_tier" 2>/dev/null)
    local paid_tier current_tier
    IFS=$'\t' read -r paid_tier current_tier <<< "$tier_ids"
    if [[ -n "$paid_tier" ]]; then tier="paid"
    elif [[ "$current_tier" == "standard-tier" ]]; then tier="paid"
    elif [[ "$current_tier" == "free-tier" ]]; then tier="free"
    elif [[ "$current_tier" == "legacy-tier" ]]; then tier="legacy"
    elif [[ -n "$current_tier" ]]; then tier="$current_tier"
    fi
  fi

  local resp http_code body
  resp=$(< "$1/_quota")
  http_code="${resp##*$'\n'}"
  body="${resp%$'\n'*}"

  if [[ "$http_code" != "200" ]]; then
    echo "{\"status\":\"error\",\"error\":\"api_error\",\"http\":$http_code}" > "$out"
    return
  fi

  # Find most constrained pro model, fallback to overall minimum
  echo "$body" | jq --arg tier "$tier" '
    {quota: {
      remaining_pct: (
        [.buckets[]? | select(.modelId | test("pro"; "i")) | (.remainingFraction * 100 | round)]
        | if length > 0 then min
        else [.buckets[]? | (.remainingFraction * 100 | round)]
             | if length > 0 then min else 100 end
        end
      ),
      resets_at: (
        [.buckets[]? | select(.modelId | test("pro"; "i")) | .resetTime]
        | if length > 0 then .[0]
        else [.buckets[]? | .resetTime]
             | if length > 0 then .[0] else "" end
        end
      ),
      models: ([.buckets[]? | {(.modelId): (.remainingFraction * 100 | round)}] | add // {})
    }} as $w | {
      status: (if [$w[].remaining_pct] | any(. <= 0) then "exhausted" else "ok" end),
      tier: $tier,
      windows: $w
    }' > "$out" 2>/dev/null || echo '{"status":"error","error":"parse_error"}' > "$out"
}

# ─── Display ──────────────────────────────────────────────

# Return ANSI colour for a remaining percentage
_cq_pct_color() {
  local pct=${1:-0}
  if (( pct > 50 )); then REPLY="\033[32m"
  elif (( pct > 20 )); then REPLY="\033[33m"
  else REPLY="\033[31m"
  fi
}

_cq_display() {
  local name=$1 file=$2 is_last=$3 now_epoch=$4
  local -A _icons=( Claude "✻" Codex $'\uf120' Gemini $'\uf51b' )
  local icon="${_icons[$name]:-●}"
  [[ ! -f "$file" ]] && return

  # Single jq call extracts status, plan/tier, and all window rows
  local parsed
  parsed=$(jq -r '
    [.status,
     (if .plan then .plan elif .tier then .tier else "" end),
     ([.windows[].remaining_pct // 0] | min // 100 | tostring),
     (.error // ""),
     (.windows | to_entries[] | "\(.key)\t\(.value.remaining_pct // 0)\t\(.value.resets_at // "" | if . != "" and . != "null" then gsub("\\.[0-9]+Z$";"Z") | fromdate else "" end)")
    ] | .[]' "$file" 2>/dev/null)

  local st plan min_pct err
  { read -r st; read -r plan; read -r min_pct; read -r err; } <<< "$parsed"

  if [[ "$st" != "ok" && "$st" != "exhausted" ]]; then
    [[ -z "$err" ]] && err="unknown"
    printf "  %s  %7s \033[2m%s\033[0m\n" "$icon" "$name" "$err"
    [[ "$is_last" != "1" ]] && echo
    return
  fi

  # Header: icon colour from min_pct
  local icon_color
  if [[ "$st" == "exhausted" ]]; then icon_color="\033[31m"
  elif (( min_pct <= 20 )); then icon_color="\033[33m"
  else icon_color="\033[32m"
  fi
  printf "  ${icon_color}%s\033[0m  \033[1m%7s\033[0m" "$icon" "$name"
  [[ -n "$plan" && "$plan" != "null" ]] && printf " \033[1;2;3m%s\033[0m" "$plan"
  echo

  # Windows
  local win pct reset_epoch rel pace diff burn burn_fmt bar_color="" pct_color pace_color reset_color
  local period_s remaining_pct
  [[ "$st" == "exhausted" ]] && bar_color="\033[31m"

  # Stream remaining lines (window rows) from parsed
  local line_no=0
  while IFS=$'\t' read -r win pct reset_epoch; do
    (( line_no++ ))
    (( line_no <= 4 )) && continue  # skip status/plan/min_pct/err lines
    [[ -z "$win" ]] && continue

    _cq_period_s "$win" && period_s=$REPLY || period_s=0
    [[ "$reset_epoch" == "null" || -z "$reset_epoch" ]] && reset_epoch=""

    # Indent + window name
    printf "       %5s  " "$win"

    # Bar with pace marker
    pace=""
    if (( period_s > 0 )) && [[ -n "$reset_epoch" ]]; then
      _cq_pace "$period_s" "$reset_epoch" "$now_epoch"; pace=$REPLY
    fi
    _cq_bar "$pct" "$bar_color" "$pace"

    # Percentage
    _cq_pct_color "$pct"; pct_color=$REPLY
    [[ -n "$bar_color" ]] && pct_color="\033[2m"
    printf "  ${pct_color}󰪟 %3d%%\033[0m" "$pct"

    # Time until reset
    if [[ -n "$reset_epoch" ]]; then
      _cq_reltime "$reset_epoch" "$now_epoch" && rel=$REPLY || rel=""
      if [[ -n "$rel" ]]; then
        reset_color="\033[2m"
        if (( pct <= 0 )); then
          reset_color="\033[1;31m"
        elif (( period_s > 0 )); then
          remaining_pct=$(( (reset_epoch - now_epoch) * 100 / period_s ))
          (( remaining_pct > 100 )) && remaining_pct=100
          (( remaining_pct < 0 )) && remaining_pct=0
          if (( remaining_pct > 50 )); then reset_color="\033[32m"
          elif (( remaining_pct > 20 )); then reset_color="\033[33m"
          else reset_color="\033[31m"
          fi
          [[ -n "$bar_color" ]] && reset_color="\033[2m"
        fi
        printf "  ${reset_color}󰦖 %-7s\033[0m" "$rel"
      fi
    else
      printf "           "
    fi

    # Pace diff + burndown
    if [[ -n "$pace" ]]; then
      diff=$(( pct - pace ))
      if (( diff >= 0 )); then pace_color="\033[32m"
      elif (( diff >= -5 )); then pace_color="\033[33m"
      else pace_color="\033[31m"
      fi
      [[ -n "$bar_color" ]] && pace_color="\033[2m"
      printf "  ${pace_color}󰓅 %+4d\033[0m" "$diff"
      burn=""
      if (( period_s > 0 )) && [[ -n "$reset_epoch" ]]; then
        _cq_burndown "$period_s" "$reset_epoch" "$now_epoch" "$pct" && burn=$REPLY || burn=""
      fi
      if [[ -n "$burn" ]]; then
        _cq_fmt_duration "$burn"; burn_fmt=$REPLY
        printf "  ${pace_color}󰅒 %-7s\033[0m" "$burn_fmt"
      else
        printf "  ${pace_color}󰅒 %-7s\033[0m" "—"
      fi
    else
      printf "  \033[2m󰓅 %4s  󰅒 %-7s\033[0m" "—" "—"
    fi

    echo
  done <<< "$parsed"

  [[ "$is_last" != "1" ]] && echo
}

# ─── Entry point ──────────────────────────────────────────

main "$@"
