# Code Search & Context Tool Selection

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

Before searching for code, symbols, files, or patterns in any codebase. Triggers: needing to find a function, trace a dependency, understand file structure, locate a bug, or explore unfamiliar code.

## Core Guidance

### Exploration Tiers (Cheapest to Richest)

Pick the lightest tier that answers the question. Each step up costs more tokens and time.

| Tier | Tools | Token Cost (approx.) | Speed | When to Use |
|------|-------|---------------------|-------|-------------|
| 1. Native | Glob, Grep, Read | ~50-500 tokens/call | Instant | Known files, text patterns, filename patterns |
| 2. AST | `smart_search`, `smart_outline`, `smart_unfold` | ~200-2k tokens/call | Fast | File structure, single symbol extraction from large files |
| 3. LSP | `lsp_hover`, `lsp_goto_definition`, `lsp_find_references`, `lsp_document_symbols`, `lsp_workspace_symbols`, `ast_grep_search`, `lsp_diagnostics` | ~300-3k tokens/call | Fast | Type-aware queries, definition jumps, reference finding |
| 4. Serena | `find_symbol`, `get_symbols_overview`, `find_referencing_symbols`, `search_for_pattern` | ~500-5k tokens/call | Medium | Symbol hierarchy with surrounding code context |
| 5. Graph | `analyze_code_relationships`, `find_dead_code`, `find_most_complex_functions` | ~1k-10k tokens/call | Medium | Cross-file relationships, dependency graphs, dead code |
| 6. Deep | Explore subagent, Gemini MCP (1M context) | ~5k-100k+ tokens | Slow | Multi-round exploration, bulk analysis of many files |

### Token Savings Comparison

| Scenario | Naive Approach | Optimal Approach | Savings |
|----------|---------------|------------------|---------|
| Find one function in a 2000-line file | Read entire file (~12k tokens) | `smart_outline` (~1.5k) then `smart_unfold` (~500) | ~83% |
| Find all references to a symbol | Grep + Read each file (~20k tokens) | `lsp_find_references` (~2k tokens) | ~90% |
| Understand a file's structure | Read entire file (~12k tokens) | `lsp_document_symbols` or `smart_outline` (~1.5k) | ~87% |
| Find files matching a pattern | Bash `find` (unoptimised output) | Glob (sorted, clean output, ~200 tokens) | ~60% |
| Locate dead code across codebase | Manual Grep + analysis (~50k tokens) | `find_dead_code` (~5k tokens) | ~90% |

### Decision Flow

Follow this sequence top-to-bottom. Stop at the first match.

```
1. Know the exact file path?
   YES --> Read(file_path)

2. Know a filename or extension pattern?
   YES --> Glob(pattern) --> Read matching files

3. Know a text/regex pattern?
   YES --> Grep(pattern, glob/type filter) --> Read matching files

4. Need structure of a large file, or one symbol from it?
   YES --> AST: smart_outline(file) --> smart_unfold(symbol)
           Alt: lsp_document_symbols(file) if LSP available

5. Need type-aware answers (what type is this? where is it defined? who calls it?)
   YES --> LSP: lsp_hover / lsp_goto_definition / lsp_find_references

6. Need structural/AST pattern matching (find all if-else without else, find all async functions)?
   YES --> ast_grep_search(pattern)

7. Need symbol hierarchy WITH surrounding code snippets (not just locations)?
   YES --> Serena: find_symbol / find_referencing_symbols

8. Need cross-file dependency graph, dead code analysis, or complexity metrics?
   YES --> CodeGraph: analyze_code_relationships / find_dead_code

9. Broad exploration with unknown scope, or need multiple rounds of discovery?
   YES --> Explore subagent (haiku model)

10. Need to analyse 10+ files simultaneously, or context exceeds 200k tokens?
    YES --> Gemini MCP (1M native context)
```

### Tier Details

#### Tier 1: Native Tools (Always Available)

No discovery needed. Use directly.

| Tool | Use Case | Example |
|------|----------|---------|
| `Glob` | Find files by name/extension | `Glob(pattern="**/*.tsx", path="/project/src")` |
| `Grep` | Find text/regex in files | `Grep(pattern="fetchUser", type="ts", output_mode="content")` |
| `Read` | Read a known file | `Read(file_path="/project/src/auth.ts")` |

**Grep power features:**
- `output_mode="files_with_matches"` -- just file paths (default, cheapest)
- `output_mode="content"` -- matching lines with context
- `output_mode="count"` -- match counts per file
- `-C 3` -- 3 lines of context around matches
- `glob="*.test.ts"` -- filter to specific file patterns
- `type="py"` -- filter to file type

#### Tier 2: AST Tools (Deferred -- claude-mem MCP)

**Discovery sequence:**
```
ToolSearch("select:mcp__plugin_claude-mem_mcp-search__smart_search,mcp__plugin_claude-mem_mcp-search__smart_outline,mcp__plugin_claude-mem_mcp-search__smart_unfold")
```

| Tool | Use Case | Output Size |
|------|----------|-------------|
| `smart_search` | Find symbols across entire codebase | ~100-500 tokens |
| `smart_outline` | File structure overview (classes, functions, imports) | ~1-2k tokens (vs 12k+ for Read) |
| `smart_unfold` | Extract a single symbol's full definition | ~200-1k tokens |

**Worked example -- finding a function in a large file:**
```
1. smart_outline("/project/src/database.ts")
   --> Returns: class DatabaseManager { connect(), query(), disconnect(), migrate() ... }
   --> Cost: ~1.5k tokens (vs ~12k to Read the full file)

2. smart_unfold("/project/src/database.ts", "migrate")
   --> Returns: full function body of migrate()
   --> Cost: ~500 tokens
   --> Total: ~2k tokens (saved ~10k vs Read)
```

#### Tier 3: LSP Tools (Deferred -- OMC MCP)

**Discovery sequence:**
```
ToolSearch("select:mcp__plugin_oh-my-claudecode_t__lsp_hover,mcp__plugin_oh-my-claudecode_t__lsp_goto_definition,mcp__plugin_oh-my-claudecode_t__lsp_find_references,mcp__plugin_oh-my-claudecode_t__lsp_document_symbols,mcp__plugin_oh-my-claudecode_t__lsp_workspace_symbols,mcp__plugin_oh-my-claudecode_t__ast_grep_search,mcp__plugin_oh-my-claudecode_t__lsp_diagnostics")
```

| Tool | Use Case | Example Question |
|------|----------|-----------------|
| `lsp_hover` | Type information at a position | "What type does this variable have?" |
| `lsp_goto_definition` | Jump to where a symbol is defined | "Where is `UserService` defined?" |
| `lsp_find_references` | All usages of a symbol | "Who calls `authenticate()`?" |
| `lsp_document_symbols` | All symbols in one file | "What's in this file?" |
| `lsp_workspace_symbols` | Find symbols across workspace | "Find all classes named `*Repository`" |
| `ast_grep_search` | Structural code patterns | "Find all `try` blocks without `catch`" |
| `lsp_diagnostics` | Type errors, lint issues | "What's wrong with this file?" |

**Worked example -- tracing a type error:**
```
1. lsp_diagnostics("/project/src/api.ts")
   --> Error: "Type 'string' is not assignable to type 'UserId'"

2. lsp_goto_definition(file, line, col)  -- on the UserId type
   --> Jumps to types.ts:42 where UserId is defined as a branded type

3. lsp_find_references(types.ts, 42, col)  -- on UserId
   --> Shows all 12 files that use UserId, revealing the pattern
```

#### Tier 4: Serena (Deferred MCP)

**Discovery sequence:**
```
ToolSearch("select:mcp__plugin_serena_serena__find_symbol,mcp__plugin_serena_serena__get_symbols_overview,mcp__plugin_serena_serena__find_referencing_symbols,mcp__plugin_serena_serena__search_for_pattern")
```

Prefer Serena over LSP when you need **surrounding code context** with references, not just locations.

| Tool | Advantage Over LSP |
|------|-------------------|
| `find_symbol` | Returns full symbol body on demand (not just location) |
| `find_referencing_symbols` | Returns references with surrounding code snippets |
| `get_symbols_overview` | Hierarchical overview of a module's structure |

#### Tier 5: CodeGraph (Deferred MCP)

**Discovery sequence:**
```
ToolSearch("select:mcp__CodeGraphContext__analyze_code_relationships,mcp__CodeGraphContext__find_dead_code,mcp__CodeGraphContext__find_most_complex_functions")
```

Best for questions about the **relationships between** code, not the code itself.

#### Tier 6: Deep Exploration

- **Explore subagent**: `Task(subagent_type="oh-my-claudecode:explore", model="haiku")` -- multi-round discovery with tool access. Use when scope is unknown.
- **Gemini MCP**: Feed 10+ files at once using `@path` syntax. Use when you need cross-file analysis exceeding 200k tokens.

### Combining Tiers

Common multi-tier workflows:

| Goal | Workflow |
|------|----------|
| Find and understand a function | Grep (locate file) --> AST `smart_unfold` (extract function) |
| Trace a bug through call chain | LSP `lsp_find_references` (find callers) --> Read (examine each caller) |
| Understand a module before refactoring | AST `smart_outline` (structure) --> LSP `lsp_find_references` (external dependencies) --> CodeGraph (relationship map) |
| Find all implementations of an interface | LSP `lsp_workspace_symbols` (find interface) --> Serena `find_referencing_symbols` (implementations with context) |
| Audit dead code | CodeGraph `find_dead_code` (candidates) --> Grep (verify no dynamic references) |

## If GSD Is Active

When operating within a GSD workflow:
- During `plan-phase`, use Tier 1-2 for lightweight discovery. Avoid spawning Explore subagents -- keep planning fast.
- During `execute-phase`, use any tier as needed. Prefer LSP/Serena for implementation work where type awareness matters.
- During `verify-phase`, CodeGraph is valuable for confirming no dead code was introduced.
- GSD's `debug` mode pairs well with LSP `lsp_diagnostics` + `lsp_goto_definition` for tracing type errors.

## Common Mistakes

| Mistake | Why It's Wrong | Do This Instead |
|---------|---------------|-----------------|
| Using Bash `grep`, `find`, or `cat` | Dedicated tools have better output handling, permissions, and token efficiency | Use Grep, Glob, Read |
| Reading an entire 2000-line file to find one function | Wastes ~12k tokens | `smart_outline` + `smart_unfold` (~2k tokens) |
| Spawning an Explore subagent for a single symbol lookup | Subagent overhead for a 1-step task | Use Grep or `lsp_goto_definition` |
| Re-searching for something already returned in this session | Wastes tokens and time | Check prior tool call results first |
| Using `Grep` without `glob` or `type` filter | Searches entire repo unnecessarily | Always scope: `Grep(pattern="x", type="ts")` |
| Jumping straight to Tier 6 (Gemini) | Expensive and slow | Exhaust cheaper tiers first |
| Using `lsp_find_references` when you need code context | LSP returns locations, not surrounding code | Use Serena `find_referencing_symbols` instead |
| Calling deferred MCP tools without ToolSearch first | Tools are not loaded until discovered | Always run ToolSearch("select:...") first |

## Quick Reference

```
DECISION SHORTCUT:
  Know the file?          --> Read
  Know the name pattern?  --> Glob --> Read
  Know a text pattern?    --> Grep (with type/glob filter)
  Need file structure?    --> smart_outline (AST)
  Need one symbol?        --> smart_unfold (AST)
  Need type info?         --> lsp_hover / lsp_goto_definition (LSP)
  Need all references?    --> lsp_find_references (LSP, locations only)
                              find_referencing_symbols (Serena, with code context)
  Need structural match?  --> ast_grep_search (LSP)
  Need dependency graph?  --> analyze_code_relationships (CodeGraph)
  Need dead code?         --> find_dead_code (CodeGraph)
  Broad exploration?      --> Explore subagent (haiku)
  Many files at once?     --> Gemini MCP (1M context)

COST HIERARCHY (cheapest first):
  Glob/Grep < AST < LSP < Serena < CodeGraph < Explore/Gemini

DEFERRED TOOL DISCOVERY (run before first use):
  Native:    No discovery needed
  AST:       ToolSearch("select:mcp__plugin_claude-mem_mcp-search__smart_outline")
  LSP:       ToolSearch("select:mcp__plugin_oh-my-claudecode_t__lsp_hover")
  Serena:    ToolSearch("select:mcp__plugin_serena_serena__find_symbol")
  CodeGraph: ToolSearch("select:mcp__CodeGraphContext__analyze_code_relationships")
```
