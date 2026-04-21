#!/usr/bin/env bash
set -euo pipefail

ROOT="/Users/jacob/Developer/src/github/jacobcxdev/cc-skills"
SCRIPT="$ROOT/skills/hopper-analyze/scripts/hopper-analyze.zsh"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"; rm -f /tmp/hopper-ready-test-job /tmp/hopper-notify-test-job.py' EXIT

TEST_BIN="$TMPDIR/dyld_shared_cache_arm64e"
: > "$TEST_BIN"

cat > "$TMPDIR/file" <<'EOF'
#!/usr/bin/env bash
printf '%s: Dyld shared cache version 1 arm64e\n' "$1"
EOF

cat > "$TMPDIR/shasum" <<'EOF'
#!/usr/bin/env bash
printf '1234567890ab  %s\n' "$3"
EOF

cat > "$TMPDIR/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == '-f%z' ]]; then
  printf '1048576\n'
else
  /usr/bin/stat "$@"
fi
EOF

cat > "$TMPDIR/sleep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF

cat > "$TMPDIR/uuidgen" <<'EOF'
#!/usr/bin/env bash
printf 'test-job\n'
EOF

cat > "$TMPDIR/hopper" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$HOPPER_CMD_LOG"
python_script=''
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  if [[ "${args[$i]}" == '-Y' ]]; then
    python_script="${args[$((i+1))]}"
    break
  fi
done
python3 - "$python_script" <<'PY'
import pathlib
import sys
script = sys.argv[1]
class _Doc:
    @staticmethod
    def saveDocumentAt(path):
        pathlib.Path(path).parent.mkdir(parents=True, exist_ok=True)
        pathlib.Path(path).write_text('saved')
class Document:
    @staticmethod
    def getCurrentDocument():
        return _Doc()
namespace = {'Document': Document}
exec(compile(pathlib.Path(script).read_text(), script, 'exec'), namespace)
PY
EOF

chmod +x "$TMPDIR/file" "$TMPDIR/shasum" "$TMPDIR/stat" "$TMPDIR/sleep" "$TMPDIR/uuidgen" "$TMPDIR/hopper"

export PATH="$TMPDIR:$PATH"
export HOPPER_ANALYZE_DIR="$TMPDIR/hopper-store"
export HOPPER_CMD_LOG="$TMPDIR/hopper-cmd.log"

if ! zsh "$SCRIPT" "$TEST_BIN" --dsc-image UIKitCore >/dev/null 2>"$TMPDIR/stderr.txt"; then
  cat "$TMPDIR/stderr.txt" >&2
  exit 1
fi

if [[ ! -f "$HOPPER_CMD_LOG" ]]; then
  printf 'Hopper was not launched\n' >&2
  cat "$TMPDIR/stderr.txt" >&2
  exit 1
fi

CMD="$(cat "$HOPPER_CMD_LOG")"
case "$CMD" in
  *"-l DYLD_ONE -s UIKitCore -a -e $TEST_BIN -Y /tmp/hopper-notify-test-job.py"*)
    ;;
  *)
    printf 'Unexpected Hopper command:\n%s\n' "$CMD" >&2
    exit 1
    ;;
esac

SAVE_PATH="$HOPPER_ANALYZE_DIR/dyld_shared_cache_arm64e/1234567890ab/dyld_shared_cache_arm64e_DYLD_ONE_arm64e_UIKitCore_1234567890ab.hop"
if [[ ! -f "$SAVE_PATH" ]]; then
  printf 'Expected saved hop file missing: %s\n' "$SAVE_PATH" >&2
  exit 1
fi

if [[ -s "$TMPDIR/stderr.txt" ]]; then
  cat "$TMPDIR/stderr.txt" >&2
  exit 1
fi

printf 'PASS\n'
