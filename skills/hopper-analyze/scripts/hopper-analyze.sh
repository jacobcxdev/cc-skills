#!/usr/bin/env bash
# hopper-analyze: Open a binary in Hopper Disassembler with auto-detected architecture,
# run analysis, and signal completion via sentinel file.
#
# Usage: hopper-analyze <binary-path> [job-id] [--version <ver>] [--description <desc>] [--save /path/to.hop] [--no-save]
#
# The script:
#   1. Detects binary type (FAT/thin) and architecture via `file`/`lipo`
#   2. Builds correct Hopper CLI flags
#   3. Generates a per-job Python notify script
#   4. Launches Hopper with analysis + ObjC metadata + notification
#   5. Prints sentinel path for the caller to wait on
#
# Default save path:
#   $HOPPER_ANALYZE_DIR/<binary>/<version>/<binary>_<loader>_<cpu>_<description>_<hash>.hop
#   HOPPER_ANALYZE_DIR defaults to /tmp/hopper if unset.
#   <version> groups by release/build (--version, falls back to <hash>).
#   <loader> is the binary format (Mach-O, FAT, ELF, WinPE) — auto-detected.
#   <cpu> is the CPU architecture (aarch64, x86_64, etc.) — auto-detected.
#   <hash> is a short SHA-256 of the binary (12 chars).
#   <description> is a human-readable label (--description, optional).
#   Deduplication: if a file matching *-<hash>.hop already exists
#   anywhere under <binary>/, the script prints its path and exits.
#
# Sentinel: /tmp/hopper-ready-<job-id>
# When the sentinel appears, Hopper MCP tools can query the document.

set -euo pipefail

BINARY="${1:?Usage: hopper-analyze <binary-path> [job-id] [--version <ver>] [--description <desc>] [--save /path/to.hop] [--no-save]}"
JOB_ID="${2:-$(date +%s)}"
SAVE_PATH=""
NO_SAVE=false
VERSION=""
DESCRIPTION=""

# Parse optional flags
shift 2 2>/dev/null || shift 1 2>/dev/null || true
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --description) DESCRIPTION="$2"; shift 2 ;;
        --save) SAVE_PATH="$2"; shift 2 ;;
        --no-save) NO_SAVE=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# Resolve binary to absolute path and verify existence
BINARY="$(cd "$(dirname "$BINARY")" && pwd)/$(basename "$BINARY")"

if [[ ! -f "$BINARY" ]]; then
    echo "Error: Binary not found: $BINARY" >&2
    exit 1
fi

SENTINEL="/tmp/hopper-ready-${JOB_ID}"
NOTIFY_SCRIPT="/tmp/hopper-notify-${JOB_ID}.py"

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
            echo "Skipping analysis. To re-analyse, delete the file first."
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
cat > "$NOTIFY_SCRIPT" << PYEOF
import pathlib
sentinel = pathlib.Path("${SENTINEL}")
sentinel.write_text("done")
PYEOF

if [[ -n "$SAVE_PATH" ]]; then
    cat >> "$NOTIFY_SCRIPT" << PYEOF
doc = Document.getCurrentDocument()
if doc:
    doc.saveHopperFile("${SAVE_PATH}")
PYEOF
fi

# --- Clean previous sentinel ---
rm -f "$SENTINEL"

# --- Ensure single Hopper instance (XPC routing breaks with multiple) ---
if pgrep -x "Hopper Disassembler" >/dev/null 2>&1; then
    echo "Quitting existing Hopper instance(s) for clean XPC state..."
    osascript -e 'tell application "Hopper Disassembler" to quit' 2>/dev/null || true
    # Wait for graceful exit (initial 10s)
    for i in $(seq 1 20); do
        pgrep -x "Hopper Disassembler" >/dev/null 2>&1 || break
        sleep 0.5
    done
    # If still running, a save dialog is likely open — wait for the user
    if pgrep -x "Hopper Disassembler" >/dev/null 2>&1; then
        echo "Hopper has unsaved work — save or discard in the Hopper dialog to continue."
        while pgrep -x "Hopper Disassembler" >/dev/null 2>&1; do
            sleep 1
        done
    fi
    echo "Hopper quit."
fi

# --- Launch Hopper ---
echo "Launching Hopper..."
echo "  Binary:   $BINARY"
echo "  Job ID:   $JOB_ID"
echo "  Sentinel: $SENTINEL"
if [[ -n "$SAVE_PATH" ]]; then
    echo "  Save to:  $SAVE_PATH"
fi

hopper "${LOADER_FLAGS[@]}" -a -o -e "$BINARY" -Y "$NOTIFY_SCRIPT"

# --- Wait for analysis completion (timeout scales with binary size) ---
BINARY_SIZE=$(stat -f%z "$BINARY")
SIZE_MB=$(( (BINARY_SIZE + 1048575) / 1048576 ))
TIMEOUT=$(( 120 + SIZE_MB * 10 ))  # 2 min base + 10s per MB
echo "Waiting for analysis to complete (timeout: ${TIMEOUT}s for ${SIZE_MB}MB)..."
ELAPSED=0
while [ ! -f "$SENTINEL" ]; do
    sleep 2
    ELAPSED=$((ELAPSED + 2))
    if [ "$ELAPSED" -ge "$TIMEOUT" ]; then
        echo "Error: Analysis did not complete within ${TIMEOUT}s" >&2
        exit 1
    fi
done
rm -f "$SENTINEL" "$NOTIFY_SCRIPT"

echo ""
echo "Analysis complete. Query via Hopper MCP tools."
