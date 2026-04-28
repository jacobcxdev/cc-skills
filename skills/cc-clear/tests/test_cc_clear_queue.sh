#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/skills/cc-clear/scripts/cc-clear"
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

"$SCRIPT" 'Continue with the current task.' >"$TMPDIR/stdout"
for _ in {1..50}; do
  if [[ "$(grep -c '^write' "$TMPDIR/log")" -ge 4 ]]; then
    break
  fi
  /bin/sleep 0.1
done

if ! grep -Fxq $'write-chars\t/clear' "$TMPDIR/log"; then
  printf 'Expected /clear line missing. Log:\n%s\n' "$(cat "$TMPDIR/log")" >&2
  exit 1
fi

if ! grep -Fxq $'write-chars\tContinue with the current task.' "$TMPDIR/log"; then
  printf 'Expected follow-up line missing. Log:\n%s\n' "$(cat "$TMPDIR/log")" >&2
  exit 1
fi

printf 'PASS\n'
