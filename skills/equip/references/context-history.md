# Context & History Search

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

Before starting any task in a previously-worked project, encountering a familiar-seeming problem, before making architectural decisions, before debugging issues that might have been solved before, or when needing to recall past decisions, conventions, or fixes across sessions.

## Core Guidance

### Memory & Context Tool Hierarchy

| Need | Tool | Layer | Cost |
|------|------|-------|------|
| Past decisions, fixes, patterns | claude-mem 3-layer workflow | Cross-session | Low-Medium |
| Persistent project notes | `project_memory_read` (OMC) | Project-scoped | Very Low |
| Session working memory | `notepad_read` (OMC) | Session-scoped | Very Low |
| Quick session capture | `/note` skill (OMC) | Session-scoped | Negligible |
| Auto-memory | Read `~/.claude/projects/*/memory/MEMORY.md` | Always in context | Zero (already loaded) |
| Web / current info | WebSearch, WebFetch | External | Medium |
| Apple platform docs | `axiom-apple-docs` / `sosumi` MCP | External (deferred) | Medium |
| Library/framework docs | Context7 MCP (`resolve-library-id` then `get-library-docs`) | External (via MCP Docker) | Medium |
| Deep research | Perplexity MCP (`perplexity_research`) / Exa MCP (`web_search_exa`) | External | High |
| Structured research | Taches `research:*` skills | External | High |

### claude-mem 3-Layer Workflow

The primary cross-session memory system. Always use progressive detail -- never fetch full observations without filtering first.

**Layer 1: `search(query)`**
Returns an index of matching observations with IDs. Each result costs ~50-100 tokens. Use scoped terms: filenames, symbols, error messages, feature names.

```
# Good queries (scoped, specific)
search("TokenManager crash iOS")
search("PostgreSQL connection pool timeout")
search("auth middleware refactor decision")
search("CLAUDE.md MCP server config")

# Bad queries (too broad)
search("bug")
search("error")
search("how to fix")
```

**Layer 2: `timeline(anchor=ID)`**
Shows context around interesting hits from Layer 1. Use this to understand the chronological sequence of events around an observation -- what happened before and after.

```
# After search returns observation ID "obs_abc123" about a crash fix:
timeline(anchor="obs_abc123")
# --> Shows: investigation started, root cause found, fix applied, verification passed
```

**Layer 3: `get_observations([IDs])`**
Full details for relevant IDs only. Always batch -- never fetch one-by-one.

```
# After timeline reveals obs_abc123, obs_abc124, obs_abc125 are all relevant:
get_observations(["obs_abc123", "obs_abc124", "obs_abc125"])
# --> Returns full observation text for all three in one call
```

**Discovery sequence for claude-mem tools:**
```
ToolSearch("select:mcp__plugin_claude-mem_mcp-search__search,mcp__plugin_claude-mem_mcp-search__timeline,mcp__plugin_claude-mem_mcp-search__get_observations")
```

**Worked example -- finding a past bug fix:**
```
1. search("TokenManager crash nullability")
   --> Returns:
       obs_001: "TokenManager nil token crash - root cause" (2026-02-15)
       obs_002: "TokenManager fix: guard let before decode" (2026-02-15)
       obs_003: "TokenManager test added for nil case" (2026-02-15)
   --> Cost: ~300 tokens

2. timeline(anchor="obs_002")
   --> Shows chronological context:
       obs_000: "User reported crash on login"
       obs_001: "Root cause: force unwrap on optional token"
       obs_002: "Fix: guard let with early return"
       obs_003: "Test: testTokenManager_nilToken_returnsNil"
   --> Cost: ~400 tokens

3. get_observations(["obs_001", "obs_002", "obs_003"])
   --> Full details including code snippets, file paths, decisions
   --> Cost: ~800 tokens
   --> Total: ~1500 tokens (vs re-investigating from scratch: 10k+ tokens)
```

**Worked example -- checking an architectural decision:**
```
1. search("database migration strategy PostgreSQL")
   --> Returns:
       obs_042: "Decided: use golang-migrate over custom scripts" (2026-01-20)
       obs_043: "Migration naming: YYYYMMDDHHMMSS_description.sql" (2026-01-20)
   --> Already enough to answer the question. No need for Layer 2-3.
```

### Project Memory (OMC)

Persistent project-scoped memory stored at `{worktree}/.omc/project-memory.json`. Survives across sessions. Read with `project_memory_read`, write with `project_memory_write`.

**Discovery sequence:**
```
ToolSearch("select:mcp__plugin_oh-my-claudecode_t__project_memory_read,mcp__plugin_oh-my-claudecode_t__project_memory_write,mcp__plugin_oh-my-claudecode_t__project_memory_add_note,mcp__plugin_oh-my-claudecode_t__project_memory_add_directive")
```

**Section-by-section guide:**

| Section | What It Contains | Example Content | When to Read |
|---------|-----------------|-----------------|--------------|
| `techStack` | Languages, frameworks, runtimes, key dependencies | `{ "language": "TypeScript", "runtime": "Node 22", "framework": "Fastify", "orm": "Drizzle" }` | Session start, before choosing tools/patterns |
| `build` | Build commands, test commands, lint commands | `{ "build": "pnpm build", "test": "pnpm vitest", "lint": "pnpm biome check" }` | Before running build/test/lint |
| `conventions` | Naming, file organisation, patterns in use | `{ "naming": "camelCase for files, PascalCase for components", "imports": "barrel exports via index.ts" }` | Before writing new code |
| `structure` | Project layout, key directories, entry points | `{ "src/": "source code", "src/routes/": "API routes", "src/lib/": "shared utilities" }` | When navigating unfamiliar areas |
| `notes` | Freeform observations, decisions, context | `["Migrated from Express to Fastify in Jan 2026", "Auth uses JWT with refresh tokens"]` | When needing project background |
| `directives` | Standing instructions for this project | `["Always run biome check before committing", "Use result types, never throw"]` | Always -- these are rules to follow |

**Reading specific sections:**
```
project_memory_read(section="conventions")   # Just conventions
project_memory_read(section="all")           # Everything (use sparingly)
```

### Notepad (OMC Session Memory)

Session-scoped memory stored at `{worktree}/.omc/notepad.md`. Three sections with different purposes.

**Discovery sequence:**
```
ToolSearch("select:mcp__plugin_oh-my-claudecode_t__notepad_read,mcp__plugin_oh-my-claudecode_t__notepad_write_priority,mcp__plugin_oh-my-claudecode_t__notepad_write_working,mcp__plugin_oh-my-claudecode_t__notepad_write_manual")
```

| Section | Purpose | Persistence | Max Size | When to Use |
|---------|---------|-------------|----------|-------------|
| `priority` | Critical reminders loaded at session start | Session | 500 chars | "Don't modify auth.ts -- user said it's frozen" |
| `working` | Timestamped progress notes | 7 days (auto-pruned) | Unlimited | "Found bug in line 42 of parser.ts -- off-by-one" |
| `manual` | Permanent notes never auto-pruned | Permanent | Unlimited | "Project uses custom ESLint rule for imports" |

**When to use `/note` vs `notepad_write` directly:**

| Situation | Use |
|-----------|-----|
| Quick capture during research or debugging | `/note` (skill, fastest) |
| Setting a critical reminder for the session | `notepad_write_priority` (appears at session start) |
| Recording timestamped progress on a multi-step task | `notepad_write_working` |
| Documenting a permanent project fact | `notepad_write_manual` |

### Auto-Memory (MEMORY.md)

Located at `~/.claude/projects/*/memory/MEMORY.md`. Always loaded in context -- zero cost to reference. Contains critical mistakes to avoid, environment-specific notes, and project-level reminders. No tool call needed; just reference what's already in your context.

### Research Tool Selection

When codebase tools cannot answer the question (external docs, current events, API references):

| Question Type | Best Tool | Why |
|---------------|-----------|-----|
| "What's the API for X library?" | Context7 MCP (`resolve-library-id` then `get-library-docs`) | Authoritative, versioned library docs |
| "What's the latest version of X?" | WebSearch | Real-time info |
| "How does Apple's new API work?" | `sosumi` MCP (`searchAppleDocumentation` then `fetchAppleDocumentation`) | Authoritative Apple docs |
| "What's the best approach to X?" | Perplexity MCP (`perplexity_research`) | Synthesised research with citations |
| "Find repos that implement X" | Exa MCP (`web_search_exa`) or `gh search repos` | Code-focused web search |
| "Deep analysis of approach X" | Taches `research:deep-dive` | Multi-step structured research |
| "Compare approaches A vs B" | Taches `research:competitive` | Structured comparison |
| "Is X feasible for our use case?" | Taches `research:feasibility` | Risk/benefit analysis |
| "What does this webpage say?" | WebFetch | Direct URL content retrieval |

**Discovery sequences for research tools:**
```
# Context7 (via MCP Docker)
ToolSearch("select:mcp__MCP_DOCKER__resolve-library-id,mcp__MCP_DOCKER__get-library-docs")

# Sosumi (Apple docs)
ToolSearch("select:mcp__sosumi__searchAppleDocumentation,mcp__sosumi__fetchAppleDocumentation")

# Perplexity (via MCP Docker)
ToolSearch("select:mcp__MCP_DOCKER__perplexity_research")

# Exa (via MCP Docker)
ToolSearch("select:mcp__MCP_DOCKER__web_search_exa")
```

### Capture Workflow

During any research or investigation, capture findings immediately -- do not wait until the end.

```
Research/Investigation Flow:
  1. Search for information (any tool)
  2. Find something relevant
  3. --> Immediately: /note "Found that X uses Y pattern because Z"
  4. Continue searching
  5. Find decision point
  6. --> Immediately: /note "Decided to use approach A over B because..."
  7. Complete investigation
  8. --> notepad_write_working (timestamped summary)
  9. If permanent fact: notepad_write_manual
```

This prevents losing details across compactions and long sessions.

## If GSD Is Active

When operating within a GSD workflow:
- During `plan-phase`, always search claude-mem for prior planning decisions before drafting a new plan. Check `project_memory_read(section="notes")` for relevant project history.
- During `execute-phase`, check `project_memory_read(section="conventions")` before writing code to ensure adherence to established patterns.
- During `verify-phase`, search claude-mem for known issues or regressions that verification should specifically check for.
- Use `/note` at each GSD phase boundary to capture phase outcomes. This provides a breadcrumb trail for resume after compaction.
- GSD's `.planning/` artifacts complement but do not replace claude-mem -- `.planning/` is workflow state, claude-mem is knowledge.

## Common Mistakes

| Mistake | Why It's Wrong | Do This Instead |
|---------|---------------|-----------------|
| Fetching all claude-mem observations at once | Token explosion, context pollution | Use 3-layer workflow: search --> filter --> fetch relevant IDs only |
| Fetching observations one-by-one | N round trips instead of 1 | Batch with `get_observations([id1, id2, id3])` |
| Skipping claude-mem search before starting work | Re-derives solutions, re-introduces fixed bugs | Always search at task start for relevant prior context |
| Using broad search terms like "bug" or "error" | Too many irrelevant results | Use scoped terms: filenames, symbols, error text |
| Writing to `priority` notepad for non-critical info | Priority section is size-limited (500 chars) and loaded at session start | Use `working` for progress, `manual` for permanent facts |
| Using WebSearch for library API questions | Web results are noisy and may be outdated | Use Context7 MCP for authoritative versioned docs |
| Re-investigating a problem from scratch | Wastes time and tokens | Search claude-mem and project_memory first |
| Not capturing findings during research | Details lost across compactions | Use `/note` immediately when you find something relevant |
| Reading `project_memory_read(section="all")` routinely | Wastes tokens loading irrelevant sections | Read specific sections as needed |

## Quick Reference

```
SESSION START CHECKLIST:
  1. Check auto-memory (MEMORY.md) -- already in context
  2. project_memory_read(section="directives") -- standing rules
  3. project_memory_read(section="conventions") -- if writing code
  4. search("relevant terms for today's task") -- prior context

CLAUDE-MEM 3-LAYER (always in this order):
  search(query)          --> index with IDs (~50-100 tok/result)
  timeline(anchor=ID)    --> chronological context around a hit
  get_observations([IDs]) --> full details (batch only)

CAPTURE IMMEDIATELY:
  Quick note     --> /note "finding"
  Critical       --> notepad_write_priority (500 char max)
  Progress       --> notepad_write_working (timestamped)
  Permanent fact --> notepad_write_manual

PROJECT MEMORY SECTIONS:
  techStack | build | conventions | structure | notes | directives

RESEARCH TOOL LADDER:
  Library API?     --> Context7 MCP
  Apple API?       --> sosumi MCP
  Current info?    --> WebSearch / WebFetch
  Synthesised?     --> Perplexity MCP
  Code repos?      --> Exa MCP / gh search
  Deep analysis?   --> Taches research:* skills
```
