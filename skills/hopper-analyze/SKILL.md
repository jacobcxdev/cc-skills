---
name: hopper-analyze
description: >
  Open and analyse binaries in Hopper Disassembler via CLI, then query results through Hopper MCP.
  Use when: reverse engineering a binary, disassembling a framework, decompiling procedures,
  examining UIKit/SwiftUI/system framework internals, extracting constants from compiled code,
  or any task requiring Hopper Disassembler. Handles architecture auto-detection for FAT/thin
  Mach-O, ELF, and PE binaries.
---

# Hopper Analyze

Automate opening binaries in Hopper Disassembler with correct loader flags, then query via Hopper MCP tools.

## Workflow

**IMPORTANT:** Run the script for EVERY binary you want to open — it manages the full lifecycle (open existing .hop or detect architecture → launch → analyse → save). Never skip the script or try to use Hopper MCP tools without running it first.

### 0. Check for existing Hopper documents

Before locating or passing a binary, search `HOPPER_ANALYZE_DIR` for pre-existing `.hop` files that match the target. This is faster than finding the binary, computing the hash, and having the script discover the dedup hit itself.

Resolve `HOPPER_ANALYZE_DIR` by reading `~/.config/hopper-analyze/config` (shell-sourceable), falling back to `/tmp/hopper` if absent or unset.

```zsh
# Substitute <binary-name> with the basename you're targeting (e.g. UIKitCore, SpringBoard)
find "${HOPPER_ANALYZE_DIR}/<binary-name>" -name "*.hop" 2>/dev/null | sort
```

**If matching `.hop` files are found**, pick the most appropriate one:
- Prefer an exact `--version` match (version appears as the subdirectory name, e.g. `UIKitCore/23D8133/*.hop`)
- If multiple versions exist and no version was specified, show the list and ask the user which to open
- Pass the chosen `.hop` path directly to the script (step 1) — the script will open it and block until loaded

**If no `.hop` files are found**, proceed to step 1 with the binary path as normal.

### 1. Launch analysis

```zsh
zsh ${CLAUDE_SKILL_DIR}/scripts/hopper-analyze.zsh <binary-path|hop-path> [--version <ver>] [--description <desc>] [--dsc-image <image>] [--save /path/to.hop] [--no-save]
```

If the input path ends in `.hop`, the script opens it directly in Hopper (skipping architecture detection, deduplication, and analysis) and blocks until the document loads.

If the input is a dyld shared cache, pass `--dsc-image <image>` to load one embedded image non-interactively via Hopper's `DYLD_ONE` loader.

Default save path:

```
$HOPPER_ANALYZE_DIR/<binary>/<version>/<binary>_<loader>_<cpu>[_<description>]_<hash>.hop
```

- `HOPPER_ANALYZE_DIR` — base save directory. Resolved in order: env var → `~/.config/hopper-analyze/config` → `/tmp/hopper`. To persist, create the config file:
  ```bash
  mkdir -p ~/.config/hopper-analyze
  echo 'HOPPER_ANALYZE_DIR="$HOME/Developer/misc/hopper"' > ~/.config/hopper-analyze/config
  ```
- `--version <ver>` — groups databases by OS/SDK build tag. Falls back to `<hash>` if omitted.
- `--description <desc>` — human-readable context distinguishing this binary from others with the same version. Optional.
- `--dsc-image <image>` — required for dyld shared cache inputs. Selects one embedded image non-interactively using `-l DYLD_ONE -s <image>`.
- `<loader>` — binary format (`Mach-O`, `FAT`, `ELF`, `WinPE`, `DYLD_ONE`). Auto-detected; omitted from filename if unrecognised.
- `<cpu>` — Hopper CPU family (`aarch64`, `x86_64`, `armv7`, `arm64e`, etc.). Auto-detected; omitted from filename if unrecognised.
- `<hash>` — first 12 chars of the binary's SHA-256.
- **Deduplication**: if a `.hop` matching the same hash exists anywhere under `<binary>/`, the script opens it directly in Hopper (skipping analysis) and blocks until the document loads (timeout: 1 min base + 2s/MB of .hop file).

Use `--save /path/to.hop` to override entirely, or `--no-save` to skip saving.

### Choosing `--version` and `--description`

`--version` should be a **build tag** (e.g. `23D8133`, `24C101`), not a marketing version (e.g. ~~`ios26.3`~~). Build tags are unambiguous identifiers found in paths, system info, and `sw_vers`. `--description` provides human-readable context — what this binary is and where it came from.

| Source | `--version` | `--description` |
|--------|-------------|-----------------|
| Simulator runtime (`/CoreSimulator/Volumes/iOS_22A3354a/...`) | Build tag from path (`22A3354a`) | `ios18.2-sim` (OS version + runtime type) |
| macOS framework (`/System/Library/Frameworks/...`) | `sw_vers -buildVersion` (e.g. `25D2128`) | omit (only one binary per host) |
| Xcode-bundled SDK (`/Xcode.app/.../iPhoneOS.sdk/...`) | Xcode build (`16C5032a`) | `iPhoneOS-sdk` or `AppleTVOS-sdk` |
| App binary (user-built) | app build number or commit hash | `debug` / `release` / scheme name |
| Linux ELF / Windows PE | package version or distro build ID | distro or variant (e.g. `ubuntu24.04`) |

When the build tag isn't obvious from the path, omit `--version` (defaults to the binary's hash).

For dyld shared caches, `--description` is optional — the script appends `--dsc-image` to the saved `.hop` filename automatically so cache-wide analyses for different images do not collide.

The script auto-detects binary format and architecture via `file`/`lipo`, builds the correct Hopper CLI flags (`-l FAT --aarch64 -l Mach-O` for universal ARM64, `-l Mach-O` for thin, `-l DYLD_ONE -s UIKitCore` for a dyld shared cache image, etc.), generates a per-job notification script, and launches Hopper with analysis + ObjC metadata enabled.

### 2. Query via Hopper MCP

The script always uses `-Y` to pass a per-job Python notification script that writes a sentinel file on analysis completion and auto-saves the `.hop` document. It blocks until the sentinel appears (timeout scales with binary size: 2 min base + 10s/MB), then exits. Run it with `Bash(run_in_background: true)` so Claude Code is notified on completion. **Do not set a `timeout` parameter on the Bash call** — the script manages its own timeout internally.

Load MCP tools with `ToolSearch("select:mcp__HopperMCPServer__search_procedures,mcp__HopperMCPServer__list_documents")`. If ToolSearch returns no Hopper MCP tools, **stop and ask the user to reconnect the Hopper MCP server** — do not fall back to other tools or attempt to read Hopper data by other means. Then:

- `list_documents` — verify the document appeared
- `search_procedures` — find procedures by regex
- `procedure_pseudo_code` — decompile to C-like pseudocode
- `procedure_assembly` — get raw disassembly (better for reading constants)
- `procedure_callers` / `procedure_callees` — navigate call graph
- `xrefs` — find cross-references to an address

## Known limitations

- **FAT dialog bypass**: Without `-l FAT --aarch64 -l Mach-O` (or equivalent), Hopper shows a slice-picker dialog that blocks analysis. The script handles this automatically.
- **No `open_document` in MCP**: Hopper MCP only queries already-opened documents. This skill bridges the gap by automating the CLI launch.
- **Large binaries**: Analysis of large frameworks (e.g. UIKitCore at 72MB) can take several minutes. The sentinel fires only after analysis completes.

## Common binary locations

| Binary | Path |
|--------|------|
| UIKitCore (sim) | `/Library/Developer/CoreSimulator/Volumes/iOS_*/...RuntimeRoot/System/Library/PrivateFrameworks/UIKitCore.framework/UIKitCore` |
| SwiftUI (sim) | Same runtime root + `/System/Library/Frameworks/SwiftUI.framework/SwiftUI` |
| System dylibs | Same runtime root + `/usr/lib/` |
| macOS frameworks | `/System/Library/Frameworks/` or `/System/Library/PrivateFrameworks/` |
| Host binaries | `/usr/bin/`, `/usr/lib/` |

Use `find /Library/Developer/CoreSimulator/Volumes -name "<framework>" -type f` to locate simulator runtime binaries.

## dyld shared cache locations

For host macOS binaries stored in the dyld shared cache, prefer these cache locations in order:

1. `/System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_*`
2. `/System/Library/dyld/dyld_shared_cache_*`

On newer macOS releases that moved system content into Cryptexes, the active cache is usually under `Preboot/Cryptexes/OS/...`. On older releases, use `/System/Library/dyld/...`.

Examples:

```zsh
hopper -l DYLD_ONE -s UIKitCore -a -e /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e
zsh ${CLAUDE_SKILL_DIR}/scripts/hopper-analyze.zsh /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_arm64e --dsc-image UIKitCore --version $(sw_vers -buildVersion)
```

To find a cache on the current machine:

```zsh
ls /System/Volumes/Preboot/Cryptexes/OS/System/Library/dyld/dyld_shared_cache_* 2>/dev/null
ls /System/Library/dyld/dyld_shared_cache_* 2>/dev/null
```

When a user asks for a framework or dylib from the host macOS cache, search Cryptex first and fall back to `/System/Library/dyld/` only if Cryptex is absent.

## Decoding assembly constants

Hopper labels common double values (e.g. `double_value_74`). For inline hex constants:

```python
import struct; struct.unpack('d', struct.pack('Q', 0x4052800000000000))[0]  # → 74.0
```

Common values: `0x405e000000000000` = 120.0, `0x4038000000000000` = 24.0, `0x4000000000000000` = 2.0, `0x4020000000000000` = 8.0.
