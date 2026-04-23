#!/usr/bin/env zsh
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
#   5. Waits for sentinel
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

# Open a .hop file in Hopper and wait until it is fully loaded.
# Two-phase detection: (1) window title appears, (2) CPU settles (deserialisation done).
# Args: <hop_path>
open_hop_document() {
    local hop_path="$1"
    local hop_name hop_size hop_mb hop_timeout elapsed

    echo "Opening: $hop_path"

    hopper -d "$hop_path"

    # -Y doesn't fire for -d (no analysis). Use two-phase readiness detection.
    hop_size=$(stat -f%z "$hop_path")
    hop_mb=$(( (hop_size + 1048575) / 1048576 ))
    hop_timeout=$(( 60 + hop_mb * 2 ))  # 1 min base + 2s per MB
    hop_name="$(basename "$hop_path")"
    elapsed=0

    # Phase 1: Poll System Events until window title appears
    echo "Waiting for window to appear (timeout: ${hop_timeout}s)..."
    while true; do
        WIN_NAMES=$(osascript -e 'tell application "System Events" to tell process "Hopper Disassembler" to get name of every window' 2>/dev/null || echo "")
        if echo "$WIN_NAMES" | grep -qF "$hop_name"; then
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
        if [ "$elapsed" -ge "$hop_timeout" ]; then
            echo "Error: Window did not appear within ${hop_timeout}s" >&2
            exit 1
        fi
    done

    # Phase 2: Wait for CPU to settle (deserialisation complete)
    # Window appears before loading finishes — poll CPU until idle for 3 consecutive checks.
    echo "Window appeared — waiting for document to finish loading..."
    local hopper_pid settle_count=0
    hopper_pid=$(pgrep -x "Hopper Disassembler" | head -1)
    if [[ -n "$hopper_pid" ]]; then
        while [ "$settle_count" -lt 3 ]; do
            sleep 2
            elapsed=$((elapsed + 2))
            if [ "$elapsed" -ge "$hop_timeout" ]; then
                echo "Error: Document did not finish loading within ${hop_timeout}s" >&2
                exit 1
            fi
            local cpu cpu_int
            cpu=$(ps -p "$hopper_pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo "0")
            cpu_int=${cpu%.*}  # truncate decimal
            cpu_int=${cpu_int:-0}
            if [ "$cpu_int" -lt 15 ]; then
                settle_count=$((settle_count + 1))
            else
                settle_count=0
            fi
        done
    fi

    echo "Document loaded. Query via Hopper MCP tools."
}

# --- Parse arguments ---

SAVE_PATH=""
NO_SAVE=false
VERSION=""
DESCRIPTION=""
DSC_IMAGE=""
POSITIONAL=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --dsc-image) DSC_IMAGE="$2"; shift 2 ;;
        --save) SAVE_PATH="$2"; shift 2 ;;
        --no-save) NO_SAVE=true; shift ;;
        --) shift; POSITIONAL+=("$@"); break ;;
        -*) echo "Unknown option: $1" >&2; exit 1 ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

BINARY="${POSITIONAL[1]:?Usage: hopper-analyze <binary-path|hop-path> [--version <ver>] [--description <desc>] [--dsc-image <image>] [--save /path/to.hop] [--no-save]}"
JOB_ID="$(uuidgen)"

# Resolve binary to absolute path and verify existence
BINARY="$(cd "$(dirname "$BINARY")" && pwd)/$(basename "$BINARY")"

if [[ ! -f "$BINARY" ]]; then
    echo "Error: Binary not found: $BINARY" >&2
    exit 1
fi

# --- Direct .hop file input ---
if [[ "$BINARY" == *.hop ]]; then
    if ! command -v hopper >/dev/null 2>&1; then
        echo "Error: 'hopper' command not found. Install Hopper Disassembler and ensure its CLI is on PATH." >&2
        exit 1
    fi
    open_hop_document "$BINARY"
    exit 0
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
            open_hop_document "$EXISTING"
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
    if [[ -n "$DSC_IMAGE" ]]; then
        _DESCRIPTION="${_DESCRIPTION:+${_DESCRIPTION}_}${DSC_IMAGE}"
    fi
    _NEEDS_FINALISE=true
fi

# --- Detect architecture ---
FILE_INFO="$(file "$BINARY")"

LOADER_FLAGS=()
LOADER_TYPE=""
CPU_TYPE=""

if echo "$FILE_INFO" | grep -q "Dyld shared cache"; then
    if [[ -z "$DSC_IMAGE" ]]; then
        echo "Error: dyld shared cache input requires --dsc-image <image>" >&2
        exit 1
    fi
    LOADER_FLAGS=(-l DYLD_ONE -s "$DSC_IMAGE" -l Mach-O)
    LOADER_TYPE="DYLD_ONE"
    if echo "$FILE_INFO" | grep -q "arm64e"; then
        CPU_TYPE="arm64e"
    elif echo "$FILE_INFO" | grep -q "arm64"; then
        CPU_TYPE="arm64"
    elif echo "$FILE_INFO" | grep -q "x86_64"; then
        CPU_TYPE="x86_64"
    fi
    echo "Dyld shared cache detected"
elif echo "$FILE_INFO" | grep -q "universal binary"; then
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

# --- Launch ---
echo "Launching Hopper..."
echo "  Binary:   $BINARY"
echo "  Job ID:   $JOB_ID"
if [[ -n "$SAVE_PATH" ]]; then
    echo "  Save to:  $SAVE_PATH"
fi

rm -f "$SENTINEL"
hopper "${LOADER_FLAGS[@]}" -a -e "$BINARY" -Y "$NOTIFY_SCRIPT"

# Timeout scales with binary size
BINARY_SIZE=$(stat -f%z "$BINARY")
SIZE_MB=$(( (BINARY_SIZE + 1048575) / 1048576 ))
TIMEOUT=$(( 120 + SIZE_MB * 10 ))  # 2 min base + 10s per MB
wait_for_sentinel "$SENTINEL" "$TIMEOUT" "analysis (${SIZE_MB}MB)"
rm -f "$SENTINEL" "$NOTIFY_SCRIPT"

echo ""
echo "Analysis complete. Query via Hopper MCP tools."
