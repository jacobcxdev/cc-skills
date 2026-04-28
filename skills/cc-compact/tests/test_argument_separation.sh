#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/skills/cc-compact/scripts/cc-compact"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/zellij" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
LOG="${ZELLIJ_TEST_LOG:?}"
SCREEN="${ZELLIJ_TEST_SCREEN:?}"

if [[ "$1" != "action" ]]; then
  printf 'unexpected command: %s\n' "$*" >&2
  exit 1
fi
shift
case "$1" in
  list-panes)
    printf '[{"id":1,"is_focused":true,"is_plugin":false}]\n'
    ;;
  focus-pane-id)
    exit 0
    ;;
  dump-screen)
    path=''
    while (($#)); do
      if [[ "$1" == "--path" ]]; then
        path="$2"
        break
      fi
      shift
    done
    cp "$SCREEN" "$path"
    ;;
  write-chars)
    line="$2"
    printf 'write-chars\t%s\n' "$line" >> "$LOG"
    printf '%s\n' "$line" >> "$SCREEN"
    ;;
  write)
    printf 'write\t%s\n' "$2" >> "$LOG"
    ;;
  *)
    printf 'unexpected action: %s\n' "$1" >&2
    exit 1
    ;;
esac
EOF

cat > "$TMPDIR/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

chmod +x "$TMPDIR/zellij" "$TMPDIR/sleep" "$SCRIPT"
: > "$TMPDIR/log"
: > "$TMPDIR/screen"

export PATH="$TMPDIR:$PATH"
export ZELLIJ=1
export ZELLIJ_TEST_LOG="$TMPDIR/log"
export ZELLIJ_TEST_SCREEN="$TMPDIR/screen"
export CC_WRAPPER_INITIAL_DELAY_SECONDS=0
export CC_WRAPPER_SUBMIT_SETTLE_SECONDS=0
export CC_WRAPPER_ACK_POLL_INTERVAL_SECONDS=0
export CC_WRAPPER_ACK_MAX_ATTEMPTS=1

run_case() {
  local name="$1"
  local input="$2"
  local expected_compact="$3"
  local expected_next="$4"

  : > "$TMPDIR/log"
  : > "$TMPDIR/screen"

  "$SCRIPT" "$input" >"$TMPDIR/stdout"
  for _ in {1..50}; do
    if [[ "$(grep -c '^write' "$TMPDIR/log")" -ge 4 ]]; then
      break
    fi
    /bin/sleep 0.1
  done

  if ! grep -Fxq $'write-chars\t/compact '"$expected_compact" "$TMPDIR/log"; then
    printf '%s: expected compact line missing. Log:\n%s\n' "$name" "$(cat "$TMPDIR/log")" >&2
    exit 1
  fi

  if ! grep -Fxq $'write-chars\t'"$expected_next" "$TMPDIR/log"; then
    printf '%s: expected continuation line missing. Log:\n%s\n' "$name" "$(cat "$TMPDIR/log")" >&2
    exit 1
  fi

  if grep -Fq "$expected_next" <(grep -F $'write-chars\t/compact ' "$TMPDIR/log"); then
    printf '%s: continuation was included in /compact line. Log:\n%s\n' "$name" "$(cat "$TMPDIR/log")" >&2
    exit 1
  fi
}

run_case \
  'capitalised continue marker' \
  'Completed advisor research for phase 4. Continue discuss-phase from step 11. Read: /Users/jacob/.claude/get-shit-done/workflows/discuss-phase/11-discuss-areas.md' \
  'Completed advisor research for phase 4.' \
  'Continue discuss-phase from step 11. Read: /Users/jacob/.claude/get-shit-done/workflows/discuss-phase/11-discuss-areas.md'

run_case \
  'lowercase then continue marker' \
  'Retain parser bug context and then continue with the hook fix' \
  'Retain parser bug context' \
  'continue with the hook fix'

run_case \
  'earliest marker wins' \
  'Summary. Read: /tmp/context.md. Continue task.' \
  'Summary.' \
  'Read: /tmp/context.md. Continue task.'

printf 'PASS\n'
