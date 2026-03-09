#!/usr/bin/env bash
# hopper-analyze: Open a binary in Hopper Disassembler with auto-detected architecture,
# run analysis, and signal completion via sentinel file.
#
# Usage: hopper-analyze <binary-path> [--version <ver>] [--description <desc>] [--save /path/to.hop] [--no-save]
#
# The script:
#   1. Detects binary type (FAT/thin) and architecture via `file`/`lipo`
#   2. Builds correct Hopper CLI flags
#   3. Generates a per-job Python notify script
#   4. Launches Hopper with analysis + ObjC metadata + notification
#   5. Waits for sentinel (cold launch) or exits immediately (warm launch)
#
# Configuration:
#   HOPPER_ANALYZE_DIR env var sets the base save directory.
#   Falls back to ~/.config/hopper-analyze/config (shell-sourceable), then /tmp/hopper.
#
# Default save path:
#   $HOPPER_ANALYZE_DIR/<binary>/<version>/<binary>_<loader>_<cpu>_<description>_<hash>.hop
#   <version> groups by release/build (--version, falls back to <hash>).
#   <loader> is the binary format (Mach-O, FAT, ELF, WinPE) — auto-detected.
#   <cpu> is the CPU architecture (aarch64, x86_64, etc.) — auto-detected.
#   <hash> is a short SHA-256 of the binary (12 chars).
#   <description> is a human-readable label (--description, optional).
#   Deduplication: if a file matching *_<hash>.hop already exists
#   anywhere under <binary>/, the script opens it and waits for load.
#
# Sentinel: /tmp/hopper-ready-<job-id>
# When the sentinel appears, Hopper MCP tools can query the document.

set -euo pipefail

# --- Helpers ---

quit_hopper() {
    osascript -e 'tell application "Hopper Disassembler" to quit' 2>/dev/null || true
    local i
    for i in $(seq 1 20); do
        pgrep -x "Hopper Disassembler" >/dev/null 2>&1 || break
        sleep 0.5
    done
    if pgrep -x "Hopper Disassembler" >/dev/null 2>&1; then
        echo "Hopper has unsaved work — save or discard in the Hopper dialog to continue."
        while pgrep -x "Hopper Disassembler" >/dev/null 2>&1; do
            sleep 1
        done
    fi
    echo "Hopper quit."
}

escape_for_python() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '%s' "$s"
}

# Wait for sentinel file with timeout. Args: <sentinel> <timeout_seconds> <label>
wait_for_sentinel() {
    local sentinel="$1" timeout="$2" label="$3"
    echo "Waiting for ${label} (timeout: ${timeout}s)..."
    local elapsed=0
    while [ ! -f "$sentinel" ]; do
        sleep 2
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$timeout" ]; then
            echo "Error: ${label} did not complete within ${timeout}s" >&2
            exit 1
        fi
    done
}

# Generate a Python notify script that writes a sentinel file.
# Args: <notify_script_path> <sentinel_path> [save_path]
generate_notify_script() {
    local script="$1" sentinel="$2" save_path="${3:-}"
    local py_sentinel
    py_sentinel="$(escape_for_python "$sentinel")"
    cat > "$script" << PYEOF
import pathlib
sentinel = pathlib.Path("${py_sentinel}")
sentinel.write_text("done")
PYEOF
    if [[ -n "$save_path" ]]; then
        local py_save
        py_save="$(escape_for_python "$save_path")"
        cat >> "$script" << PYEOF
doc = Document.getCurrentDocument()
if doc:
    doc.saveDocumentAt("${py_save}")
PYEOF
    fi
}

# --- Parse arguments ---

SAVE_PATH=""
NO_SAVE=false
VERSION=""
DESCRIPTION=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --save) SAVE_PATH="$2"; shift 2 ;;
        --no-save) NO_SAVE=true; shift ;;
        --) shift; POSITIONAL+=("$@"); break ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

BINARY="${POSITIONAL[0]:?Usage: hopper-analyze <binary-path> [--version <ver>] [--description <desc>] [--save /path/to.hop] [--no-save]}"
JOB_ID="$(uuidgen)"

# Resolve binary to absolute path and verify existence
BINARY="$(cd "$(dirname "$BINARY")" && pwd)/$(basename "$BINARY")"

if [[ ! -f "$BINARY" ]]; then
    echo "Error: Binary not found: $BINARY" >&2
    exit 1
fi

# Pre-flight: ensure hopper CLI is available
if ! command -v hopper >/dev/null 2>&1; then
    echo "Error: 'hopper' command not found. Install Hopper Disassembler and ensure its CLI is on PATH." >&2
    exit 1
fi

SENTINEL="/tmp/hopper-ready-${JOB_ID}"
NOTIFY_SCRIPT="/tmp/hopper-notify-${JOB_ID}.py"

# Cleanup on interruption
trap 'rm -f "$SENTINEL" "$NOTIFY_SCRIPT"' INT TERM

# --- Resolve HOPPER_ANALYZE_DIR ---
_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/hopper-analyze/config"
if [[ -z "${HOPPER_ANALYZE_DIR:-}" && -f "$_CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$_CONFIG_FILE"
fi

# --- Compute default save path (partial — finalised after arch detection) ---
_NEEDS_FINALISE=false
if [[ "$NO_SAVE" == false && -z "$SAVE_PATH" ]]; then
    BASE_DIR="${HOPPER_ANALYZE_DIR:-/tmp/hopper}"
    _BIN_NAME="$(basename "$BINARY")"
    _BIN_HASH="$(shasum -a 256 "$BINARY" | cut -c1-12)"

    # Dedup: search entire <binary>/ tree for this hash (any version subdir)
    BIN_DIR="${BASE_DIR}/${_BIN_NAME}"
    if [[ -d "$BIN_DIR" ]]; then
        EXISTING="$(find "$BIN_DIR" -name "*_${_BIN_HASH}.hop" -print -quit 2>/dev/null)"
        if [[ -n "$EXISTING" ]]; then
            echo "Already analysed: $EXISTING"
            echo "Opening existing database..."

            HOPPER_COUNT=$(pgrep -cx "Hopper Disassembler" 2>/dev/null || echo 0)
            if [[ "$HOPPER_COUNT" -gt 1 ]]; then
                echo "Multiple Hopper instances detected — quitting all for clean XPC state..."
                quit_hopper
            fi

            hopper -d "$EXISTING"

            # -Y doesn't fire for -d (no analysis). Poll System Events window titles instead.
            HOP_SIZE=$(stat -f%z "$EXISTING")
            HOP_MB=$(( (HOP_SIZE + 1048575) / 1048576 ))
            HOP_TIMEOUT=$(( 60 + HOP_MB * 2 ))  # 1 min base + 2s per MB
            HOP_NAME="$(basename "$EXISTING")"
            echo "Waiting for document to load (timeout: ${HOP_TIMEOUT}s)..."
            elapsed=0
            while true; do
                WIN_NAMES=$(osascript -e 'tell application "System Events" to tell process "Hopper Disassembler" to get name of every window' 2>/dev/null || echo "")
                if echo "$WIN_NAMES" | grep -qF "$HOP_NAME"; then
                    break
                fi
                sleep 2
                elapsed=$((elapsed + 2))
                if [ "$elapsed" -ge "$HOP_TIMEOUT" ]; then
                    echo "Error: Document did not load within ${HOP_TIMEOUT}s" >&2
                    exit 1
                fi
            done

            echo "Existing database opened. Query via Hopper MCP tools."
            exit 0
        fi
    fi

    # Version subdirectory (falls back to hash)
    if [[ -z "$VERSION" ]]; then
        VERSION="$_BIN_HASH"
    fi

    _SAVE_DIR="${BIN_DIR}/${VERSION}"
    mkdir -p "$_SAVE_DIR"
    _DESCRIPTION="$DESCRIPTION"
    _NEEDS_FINALISE=true
fi

# --- Detect architecture ---
FILE_INFO="$(file "$BINARY")"

LOADER_FLAGS=()
LOADER_TYPE=""
CPU_TYPE=""

if echo "$FILE_INFO" | grep -q "universal binary"; then
    # FAT binary — pick best slice
    ARCHS="$(lipo -archs "$BINARY" 2>/dev/null || echo "")"
    LOADER_TYPE="FAT"
    echo "FAT binary detected. Slices: $ARCHS"

    if echo "$ARCHS" | grep -qw "arm64e"; then
        LOADER_FLAGS=(-l FAT --aarch64 -l Mach-O)
        CPU_TYPE="aarch64"
        echo "Selected: arm64e (via --aarch64)"
    elif echo "$ARCHS" | grep -qw "arm64"; then
        LOADER_FLAGS=(-l FAT --aarch64 -l Mach-O)
        CPU_TYPE="aarch64"
        echo "Selected: arm64 (via --aarch64)"
    elif echo "$ARCHS" | grep -qw "x86_64"; then
        LOADER_FLAGS=(-l FAT --intel-64 -l Mach-O)
        CPU_TYPE="x86_64"
        echo "Selected: x86_64"
    elif echo "$ARCHS" | grep -qw "armv7s"; then
        LOADER_FLAGS=(-l FAT --armv7s -l Mach-O)
        CPU_TYPE="armv7s"
        echo "Selected: armv7s"
    elif echo "$ARCHS" | grep -qw "armv7"; then
        LOADER_FLAGS=(-l FAT --armv7 -l Mach-O)
        CPU_TYPE="armv7"
        echo "Selected: armv7"
    else
        echo "Warning: Unknown FAT slices ($ARCHS), letting Hopper choose" >&2
    fi
elif echo "$FILE_INFO" | grep -q "Mach-O"; then
    LOADER_TYPE="Mach-O"
    # Thin Mach-O — detect arch from file output
    if echo "$FILE_INFO" | grep -q "arm64e"; then
        LOADER_FLAGS=(-l Mach-O)
        CPU_TYPE="aarch64"
        echo "Thin Mach-O arm64e detected"
    elif echo "$FILE_INFO" | grep -q "arm64"; then
        LOADER_FLAGS=(-l Mach-O)
        CPU_TYPE="aarch64"
        echo "Thin Mach-O arm64 detected"
    elif echo "$FILE_INFO" | grep -q "x86_64"; then
        LOADER_FLAGS=(-l Mach-O)
        CPU_TYPE="x86_64"
        echo "Thin Mach-O x86_64 detected"
    else
        LOADER_FLAGS=(-l Mach-O)
        echo "Thin Mach-O detected (arch auto-detect)"
    fi
elif echo "$FILE_INFO" | grep -q "ELF"; then
    LOADER_FLAGS=(-l ELF)
    LOADER_TYPE="ELF"
    if echo "$FILE_INFO" | grep -q "x86-64"; then
        CPU_TYPE="x86_64"
    elif echo "$FILE_INFO" | grep -q "aarch64\|ARM aarch64"; then
        CPU_TYPE="aarch64"
    elif echo "$FILE_INFO" | grep -q "ARM,"; then
        CPU_TYPE="arm"
    fi
    echo "ELF binary detected${CPU_TYPE:+ ($CPU_TYPE)}"
elif echo "$FILE_INFO" | grep -q "PE32+"; then
    LOADER_FLAGS=(-l WinPE)
    LOADER_TYPE="WinPE"
    CPU_TYPE="x86_64"
    echo "Windows PE64 binary detected"
elif echo "$FILE_INFO" | grep -q "PE32"; then
    LOADER_FLAGS=(-l WinPE)
    LOADER_TYPE="WinPE"
    CPU_TYPE="x86"
    echo "Windows PE32 binary detected"
else
    echo "Warning: Unknown binary format, letting Hopper auto-detect" >&2
    echo "file output: $FILE_INFO" >&2
fi

# --- Finalise save path (needs LOADER_TYPE and CPU_TYPE from detection above) ---
if [[ "$_NEEDS_FINALISE" == true ]]; then
    FNAME="${_BIN_NAME}"
    [[ -n "$LOADER_TYPE" ]] && FNAME="${FNAME}_${LOADER_TYPE}"
    [[ -n "$CPU_TYPE" ]] && FNAME="${FNAME}_${CPU_TYPE}"
    [[ -n "$_DESCRIPTION" ]] && FNAME="${FNAME}_${_DESCRIPTION}"
    FNAME="${FNAME}_${_BIN_HASH}"
    SAVE_PATH="${_SAVE_DIR}/${FNAME}.hop"
fi

# --- Generate per-job Python notify script ---
generate_notify_script "$NOTIFY_SCRIPT" "$SENTINEL" "$SAVE_PATH"

# --- Check existing Hopper instances ---
HOPPER_COUNT=$(pgrep -cx "Hopper Disassembler" 2>/dev/null || echo 0)
WARM_LAUNCH=false

if [[ "$HOPPER_COUNT" -gt 1 ]]; then
    # Multiple instances — XPC routing breaks, must quit all
    echo "Multiple Hopper instances detected ($HOPPER_COUNT) — quitting all for clean XPC state..."
    quit_hopper
elif [[ "$HOPPER_COUNT" -eq 1 ]]; then
    # Single instance already running — reuse it (warm launch)
    WARM_LAUNCH=true
    echo "Hopper already running — opening binary in existing instance."
fi

# --- Launch ---
echo "Launching Hopper..."
echo "  Binary:   $BINARY"
echo "  Job ID:   $JOB_ID"
if [[ -n "$SAVE_PATH" ]]; then
    echo "  Save to:  $SAVE_PATH"
fi

if [[ "$WARM_LAUNCH" == true ]]; then
    # Warm launch: open in existing instance — -Y requires cold launch, so skip sentinel.
    # Loader flags still needed for FAT slice selection.
    hopper ${LOADER_FLAGS[@]+"${LOADER_FLAGS[@]}"} -a -e "$BINARY"
    echo ""
    echo "Binary opened in existing Hopper instance. Analysis is running."
    echo "Poll Hopper MCP list_documents to check when the new document appears."
    if [[ -n "$SAVE_PATH" ]]; then
        echo "Auto-save unavailable on warm launch. Save manually or via MCP if needed."
    fi
    rm -f "$NOTIFY_SCRIPT"
else
    # Cold launch: use -Y notification script + sentinel wait
    rm -f "$SENTINEL"
    hopper ${LOADER_FLAGS[@]+"${LOADER_FLAGS[@]}"} -a -e "$BINARY" -Y "$NOTIFY_SCRIPT"

    # Timeout scales with binary size
    BINARY_SIZE=$(stat -f%z "$BINARY")
    SIZE_MB=$(( (BINARY_SIZE + 1048575) / 1048576 ))
    TIMEOUT=$(( 120 + SIZE_MB * 10 ))  # 2 min base + 10s per MB
    wait_for_sentinel "$SENTINEL" "$TIMEOUT" "analysis (${SIZE_MB}MB)"
    rm -f "$SENTINEL" "$NOTIFY_SCRIPT"

    echo ""
    echo "Analysis complete. Query via Hopper MCP tools."
fi
