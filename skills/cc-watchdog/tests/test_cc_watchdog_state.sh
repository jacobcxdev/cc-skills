#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRIPT="$ROOT/skills/cc-watchdog/scripts/cc-watchdog"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

chmod +x "$SCRIPT"
export XDG_STATE_HOME="$TMPDIR/state"

"$SCRIPT" start 'test/session' 'Keep going.' >"$TMPDIR/start.out"
STATE_FILE="$XDG_STATE_HOME/cc-watchdog/test_session.json"

if [[ ! -f "$STATE_FILE" ]]; then
  printf 'Expected watchdog state file missing: %s\n' "$STATE_FILE" >&2
  exit 1
fi

python3 - "$STATE_FILE" <<'PY'
import json
import pathlib
import sys

state = json.loads(pathlib.Path(sys.argv[1]).read_text())
assert state["active"] is True
assert state["name"] == "test_session"
assert state["message"] == "Keep going."
assert state["project_path"].endswith("cc-skills")
PY

"$SCRIPT" status 'test/session' >"$TMPDIR/status.out"
if ! grep -Fq '"message": "Keep going."' "$TMPDIR/status.out"; then
  printf 'Expected status to include message. Status:\n%s\n' "$(cat "$TMPDIR/status.out")" >&2
  exit 1
fi

"$SCRIPT" stop 'test/session' >"$TMPDIR/stop.out"
if [[ -f "$STATE_FILE" ]]; then
  printf 'Expected watchdog state file to be removed: %s\n' "$STATE_FILE" >&2
  exit 1
fi

printf 'PASS\n'
