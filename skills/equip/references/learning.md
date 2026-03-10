# Cross-Session Learning

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When you need to persist knowledge across sessions, build institutional memory for a project, evolve coding patterns over time, or retrieve past decisions and fixes. Triggers: starting a new session in a previously-worked project, completing a significant debugging session, discovering a reusable pattern, or wanting to avoid repeating past mistakes.

## Core Guidance

### Learning Systems Overview

Four systems capture and evolve knowledge. Each operates at a different scope and persistence level.

| System | Scope | Persistence | Storage | Primary Use |
|--------|-------|-------------|---------|-------------|
| Auto-memory (MEMORY.md) | Project + global | Permanent (until edited) | `~/.claude/projects/*/memory/MEMORY.md` | Always-loaded context, critical facts |
| claude-mem | Cross-session | 7 days (standard) or permanent (priority) | MCP-managed observation store | Searchable history of decisions, fixes, patterns |
| ECC Instincts | Project or global | Permanent (file-based) | `.claude/instincts/` or `~/.claude/instincts/` | Evolved coding patterns and conventions |
| Reflexion `/memorize` | Cross-session | Permanent (via claude-mem) | claude-mem observations | Post-reflection learnings |

### Auto-Memory (MEMORY.md)

**What it is:** A markdown file automatically loaded into every session's context. Located at `~/.claude/projects/{project-hash}/memory/MEMORY.md` for project-scoped memory, or `~/.claude/projects/-Users-jacob/memory/MEMORY.md` for the global home directory scope.

**What belongs here:**
- Critical mistakes to never repeat (with exact error messages)
- Workarounds for known tool/environment bugs
- Host-specific configuration facts (SSH keys, paths, versions)
- Facts that are needed in *every* session (always loaded, so keep it small)

**What does NOT belong here:**
- Transient decisions (use claude-mem instead)
- Large code snippets (link to files instead)
- Things that change frequently (maintenance burden)

**How entries are created:**
```
<remember>SSH key for h1 is at ~/.ssh/h1_ed25519</remember>                    -- standard (7-day)
<remember priority>NEVER manually edit ~/.claude.json for MCP changes</remember> -- permanent
```

**Best practice:** Keep MEMORY.md under ~50 entries. If it grows too large, it wastes context in every session. Move older/less-critical items to claude-mem observations instead.

### claude-mem (Primary Cross-Session Memory)

**What it is:** An MCP-backed observation store that captures decisions, fixes, patterns, and context across sessions. Unlike MEMORY.md, it is *not* automatically loaded -- you search it on demand.

**How observations are created:**

1. **Automatic capture (hooks):** claude-mem hooks run on PostToolUse and Stop events, extracting observations from tool interactions. These are captured passively without explicit action.
2. **Explicit capture:** Use `<remember>` tags to create observations manually:
   ```
   <remember>The billing module uses event sourcing, not CRUD -- see src/billing/events.ts</remember>
   ```
3. **Priority capture:** Use `<remember priority>` for permanent observations that should never expire:
   ```
   <remember priority>Project X requires Node 20+ due to native fetch dependency</remember>
   ```

**What triggers automatic capture:**
- Completing a debugging session (bug root cause, fix applied)
- Making architectural decisions (choice made, rationale, alternatives rejected)
- Discovering project conventions (naming, file structure, patterns)
- Encountering and resolving errors (error message, solution)
- Tool configuration changes (what was changed, why)

**3-Layer Retrieval Workflow (mandatory -- never skip layers):**

```
Layer 1: SEARCH (broad, cheap -- ~50-100 tokens per result)
   search("billing event sourcing migration")
   --> Returns index with observation IDs, timestamps, and summaries
   --> Scan summaries to identify relevant hits

Layer 2: TIMELINE (context around hits -- ~200-500 tokens per anchor)
   timeline(anchor="obs-id-from-search")
   --> Returns chronological observations around the anchor point
   --> Reveals the full story: what led to a decision, what followed

Layer 3: GET (full details for specific IDs only -- batch request)
   get_observations(["obs-42", "obs-47", "obs-51"])
   --> Returns complete observation text for selected IDs
   --> Only fetch IDs confirmed relevant in layers 1-2
```

**Anti-patterns:**
- Calling `get_observations` with all IDs from search (token waste)
- Skipping `timeline` and going straight from search to get (misses context)
- Searching with vague terms like "bug" or "fix" (too broad, noisy results)
- Not searching at all when starting work in a familiar project

**Effective search terms:**
| Need | Good Search Terms | Bad Search Terms |
|------|------------------|-----------------|
| Past fix for a crash | `"TypeError fetchUser null"`, `"auth crash session"` | `"bug"`, `"error"` |
| Architecture decision | `"billing event-sourcing decision"`, `"chose PostgreSQL"` | `"architecture"`, `"design"` |
| Project convention | `"naming convention components"`, `"file structure src"` | `"convention"`, `"pattern"` |
| Tool workaround | `"XcodeBuild simulator timeout"`, `"eslint config fix"` | `"tool"`, `"workaround"` |

### ECC Instinct System

**What it is:** A pattern evolution system that captures coding instincts -- recurring patterns, preferences, and conventions -- and promotes them from project-local to global scope.

**Instinct Lifecycle:**

```
1. OBSERVATION           Pattern noticed during coding
      |                  (e.g., "always use branded types for IDs")
      v
2. CREATION              Instinct file created in .claude/instincts/
      |                  Contains: pattern, rationale, examples
      v
3. EVOLUTION             Pattern refined via /evolve
      |                  (counter-examples found, scope narrowed)
      v
4. EXPORT                /instinct-export saves to portable format
      |
      v
5. IMPORT                /instinct-import loads into new projects
      |
      v
6. PROMOTION             /promote moves from project to global scope
                         (.claude/instincts/ --> ~/.claude/instincts/)
```

**Commands:**

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `/instinct-status` | List all active instincts and their maturity | Start of session, to see what patterns are active |
| `/evolve` | Refine an instinct based on new evidence | After encountering a counter-example or edge case |
| `/instinct-export` | Save instincts to a portable file | Before sharing patterns with another project |
| `/instinct-import` | Load instincts from a file | When starting a new project with known patterns |
| `/promote` | Move instinct from project-local to global | When a pattern proves universally useful |

**Example instinct file (`.claude/instincts/branded-types.md`):**
```markdown
# Branded Types for Domain IDs

## Pattern
Use branded/opaque types for domain identifiers instead of raw strings.

## Rationale
Prevents accidentally passing a UserId where an OrderId is expected.
Caught 3 bugs in the billing module from this pattern.

## Examples
- GOOD: type UserId = string & { readonly __brand: 'UserId' }
- BAD:  function getUser(id: string) -- accepts any string

## Scope
TypeScript projects with domain models. Not needed for simple scripts.

## Maturity
Confirmed (5 positive observations, 0 counter-examples)
```

**When to evolve vs promote:**
- **Evolve** when you find an edge case, a context where the instinct doesn't apply, or a better formulation of the pattern.
- **Promote** when an instinct has been confirmed across 3+ projects with no counter-examples.

### Reflexion `/memorize`

**What it is:** A skill used *after* `/reflect` to persist specific learnings from the reflection into claude-mem as permanent observations.

**Workflow:**

```
1. Complete significant work (feature, debug session, refactor)
      |
      v
2. /reflect
   --> Self-evaluation: what went well, what went wrong, what to improve
   --> Produces structured reflection output
      |
      v
3. /memorize
   --> Extracts key learnings from the reflection
   --> Creates claude-mem observations with priority flag
   --> Learnings become searchable in future sessions
```

**What to memorize:**
- Root causes of bugs that took >10 minutes to find
- Approaches that failed and why (so you don't retry them)
- Tool combinations that worked well for specific tasks
- Project-specific quirks that aren't obvious from the code

**What NOT to memorize:**
- Generic programming knowledge (already in training data)
- Transient state (versions that will change, temporary workarounds)
- Entire code blocks (reference files by path instead)

### ECC `/continuous-learning`

**What it is:** A skill that extracts reusable patterns from completed sessions, identifying what worked and what didn't.

**When to use:** After completing a substantial body of work (not after every small task). Best at end-of-day or end-of-sprint.

**What it extracts:**
- Tool usage patterns (which tools solved problems fastest)
- Debugging strategies that worked (vs ones that wasted time)
- Code patterns that recurred across files
- Agent compositions that were effective

**Evaluation with `/learn-eval`:**
- Reviews extracted patterns for quality and accuracy
- Scores pattern usefulness (keep, refine, discard)
- Identifies patterns that conflict with existing instincts

### Choosing the Right Learning Tool

```
DECISION FLOW:
  Critical fact needed EVERY session?     --> MEMORY.md (<remember priority>)
  Decision/fix to find in future sessions? --> claude-mem (<remember>)
  Recurring coding pattern to evolve?      --> ECC instincts (/instinct-status, /evolve)
  Just finished deep work, want to learn?  --> /reflect then /memorize
  End of sprint, extract patterns?         --> /continuous-learning then /learn-eval
  Quick note during session?               --> /note (OMC notepad, session-scoped)
```

### Building Useful Memory Over Time

**Session start checklist:**
1. `search("project-name recent work")` in claude-mem -- resume context
2. `project_memory_read(section="conventions")` -- check conventions
3. `/instinct-status` -- see active coding patterns
4. Review MEMORY.md (auto-loaded, just scan for relevance)

**During work:**
- Use `/note` to capture decisions as you make them (prevents loss on compaction)
- Use `<remember>` when you solve a non-obvious problem
- Use `<remember priority>` for mistakes that must never recur

**Session end checklist:**
- If significant debugging: `/reflect` then `/memorize`
- If new pattern discovered: consider creating an instinct
- If critical workaround found: add to MEMORY.md with `<remember priority>`

**Maintenance:**
- Review MEMORY.md quarterly -- remove stale entries
- Run `/instinct-status` monthly -- promote mature instincts, archive unused ones
- Run `/continuous-learning` after major project milestones

## If GSD Is Active

When GSD is already running, learning integrates with GSD phases:

| GSD Phase | Learning Action |
|-----------|----------------|
| `plan-phase` | Search claude-mem for prior decisions in this domain before planning |
| `execute-phase` | Use `/note` to capture implementation decisions as they happen |
| `verify-phase` | After verification, `/reflect` on the implementation approach |
| `debug` | Search claude-mem for the error message/symptom before investigating |

GSD verification can trigger `/memorize` automatically when verification discovers patterns worth preserving. The learning is tagged with the GSD project name for easy retrieval.

## Common Mistakes

| Mistake | Why It's Wrong | Correct Approach |
|---------|---------------|-----------------|
| Dumping everything into MEMORY.md | Wastes context tokens every session | Only critical, always-needed facts in MEMORY.md |
| Skipping claude-mem search at session start | Re-derives solutions, re-introduces fixed bugs | Always search before starting work in familiar projects |
| Using `get_observations` on all search results | Fetches full text for irrelevant entries | Use 3-layer workflow: search --> timeline --> get (selected IDs only) |
| Never running `/reflect` | Misses learning opportunities | Reflect after significant debugging or feature work |
| Promoting instincts too early | Pattern may not generalize | Wait for 3+ project confirmations before `/promote` |
| Memorizing generic knowledge | Clutters memory with things already in training data | Only memorize project-specific or non-obvious learnings |
| Not using `/note` during long sessions | Context lost on compaction | Capture decisions and context as you go |
| Searching claude-mem with vague terms | Returns too many irrelevant results | Use specific symbols, error messages, file names |

## Quick Reference

```
MEMORY SYSTEMS:
  MEMORY.md           Always loaded, permanent, small (<50 entries)
  claude-mem          Searchable, 7-day or permanent, unlimited
  ECC instincts       Evolvable patterns, project or global scope
  Reflexion           Post-reflection persistence to claude-mem
  /note (OMC)         Session-scoped, survives compaction

CLAUDE-MEM 3-LAYER RETRIEVAL:
  search("specific terms")  --> index with IDs (~50-100 tok/result)
  timeline(anchor=ID)       --> context around a hit (~200-500 tok)
  get_observations([IDs])   --> full details, batched (~500-2k tok)

INSTINCT LIFECYCLE:
  observe --> create --> /evolve --> /instinct-export
                                --> /instinct-import (new project)
                                --> /promote (project --> global)

CAPTURE SYNTAX:
  <remember>decision or fix</remember>              -- 7-day retention
  <remember priority>critical fact</remember>        -- permanent
  /note "quick session note"                         -- session-scoped

SESSION WORKFLOW:
  Start:  search claude-mem + project_memory_read + /instinct-status
  During: /note for decisions, <remember> for solutions
  End:    /reflect --> /memorize (if significant work done)
```
