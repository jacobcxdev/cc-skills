# Context Management

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When managing session context to prevent bloat, data loss, or degraded performance. Trigger signals:
- Session feels sluggish or responses become less coherent
- Working with multi-agent teams (TeamCreate) that must survive compaction
- About to spawn subagents that need codebase context they can't predict upfront
- Transitioning between major work phases (research -> planning -> implementation)
- Approaching the context window limit
- Planning a long session with multiple phases of work

## Core Guidance

### Tool Priority Order

| Priority | Tool | Purpose | When to Use |
|----------|------|---------|-------------|
| 1 | **cozempic** (`/cozempic`) | Diagnose bloat, apply prescriptions, guard mode | Session health monitoring, protecting agent teams |
| 2 | **`/compact`** | Manual context compaction | Phase boundaries, before large implementations |
| 3 | **Iterative retrieval** | Context bootstrapping for subagents | Spawning agents that need unpredictable codebase context |
| 4 | **Session notepad** (OMC) | Persist critical state through compaction | Decisions, findings, working context that must survive |
| 5 | **claude-mem** | Cross-session persistence | Learnings, decisions, patterns for future sessions |

---

### Cozempic

Cozempic is always active via a guard daemon. It monitors session health and provides tools for diagnosis and treatment.

#### Diagnosis

Use `diagnose_current` to get a token breakdown of the current session:

| Metric | What It Shows |
|--------|---------------|
| Total tokens | Current context window usage |
| Tool results | Tokens consumed by tool call outputs |
| Agent outputs | Tokens from spawned agent responses |
| System context | Tokens from CLAUDE.md, rules, hooks |
| Conversation | Tokens from user/assistant messages |

Use `estimate_tokens` before adding content to predict impact on the context budget.

#### Prescriptions

Three levels of pruning, applied via `treat_session`:

| Level | What It Removes | When to Use |
|-------|----------------|-------------|
| **Gentle** | Old tool results (build logs, test output, file reads from early in session) | First sign of sluggishness; preserves all reasoning |
| **Standard** | Gentle + compressed agent outputs (summaries replace full responses) | Mid-session cleanup; key findings preserved as summaries |
| **Aggressive** | Standard + non-essential context (exploratory reads, superseded plans, intermediate debugging) | Emergency; approaching context limit; only final decisions and active work preserved |

**Selection heuristic:**
- Context usage <60%: no action needed
- Context usage 60-75%: gentle
- Context usage 75-85%: standard
- Context usage >85%: aggressive

#### Guard Mode

Protects agent team state from auto-compaction. Essential when using `TeamCreate`.

**Setup:**
```
/cozempic guard
```

**What it protects:**
- Team task lists and status
- Agent communication state
- Pipeline stage tracking
- Shared context between teammates

**When to enable:**
- Before any `TeamCreate` call
- Before OMC `/team` or `/ralph` workflows
- Any time multiple agents need to coordinate over an extended period

**How it works:** The guard daemon intercepts auto-compaction events and preserves agent coordination state, allowing compaction of other context while keeping team state intact.

---

### Strategic Compaction (`/compact`)

Manual compaction at logical phase boundaries prevents uncontrolled auto-compaction that may lose critical context.

#### When to Compact

| Phase Transition | Why Compact Here |
|-----------------|-----------------|
| After research, before planning | Research outputs (file reads, search results, docs) are bulky; planning needs conclusions, not raw data |
| After planning, before implementation | Plans are finalized; intermediate planning drafts and debates can be compressed |
| After debugging, before fixing | Root cause is identified; stack traces, bisect steps, and exploratory reads are no longer needed |
| After implementation, before testing | Code is written; intermediate edits, failed attempts, and refactoring steps can go |
| Before large implementation | Clear space for the substantial tool output that code generation produces |
| After a subagent-heavy phase | Agent outputs are verbose; compact to preserve conclusions only |

#### When NOT to Compact

| Situation | Why Not |
|-----------|---------|
| Mid-implementation of a multi-file change | Risk losing track of which files were changed and why |
| During active debugging | Symptoms, hypotheses, and eliminated possibilities are all needed |
| While agents are running | May corrupt agent communication state (use guard mode instead) |
| Right after the user gave detailed instructions | The instructions would be compressed and potentially lost |

#### Compact Workflow

1. **Capture first:** write critical state to notepad (`notepad_write_working`) or claude-mem before compacting
2. **Run `/compact`** with a summary hint of what to preserve
3. **Verify:** check that key context survived by reading back notepad or recalling key decisions

---

### Iterative Retrieval Pattern

For subagents that need codebase context they can't predict upfront. The 4-phase pattern prevents over-fetching (wasting context budget) and under-fetching (agent fails due to missing context).

#### Phase 1: Dispatch

Spawn the subagent with **initial context** -- the minimum files and information known to be relevant.

```
Task(subagent_type="oh-my-claudecode:executor", prompt="""
Implement feature X.

Initial context:
- src/auth/handler.ts (entry point)
- src/types/user.ts (User type definition)
- Architecture: Express + TypeScript + Prisma

If you need additional files, list them and explain why.
""")
```

#### Phase 2: Evaluate

The subagent works with initial context. When it encounters unknowns, it:
- Lists specific files it needs and why
- Describes what information is missing
- Returns partial results with clearly marked gaps

#### Phase 3: Refine

The orchestrator fetches the requested files and re-dispatches (or sends a follow-up message):
- Read the requested files
- Provide the content to the subagent
- Include any additional context discovered during the fetch

#### Phase 4: Loop

Repeat phases 2-3 until the subagent has sufficient context to complete the task. Typically converges in 2-3 iterations.

**Budget guard:** set a maximum iteration count (usually 3-4). If the subagent still needs more context after that, it likely needs to be scoped differently.

---

### Context Budget Planning

Before spawning subagents or starting a large phase, estimate context consumption.

#### Per-Activity Token Estimates

| Activity | Approximate Token Cost |
|----------|----------------------|
| Read a source file (200 lines) | 1,500-3,000 tokens |
| Read a source file (800 lines) | 6,000-12,000 tokens |
| `smart_outline` of an 800-line file | 1,000-2,000 tokens |
| Build output (success) | 500-2,000 tokens |
| Build output (failure with errors) | 2,000-8,000 tokens |
| Test suite output | 1,000-10,000 tokens |
| Agent response (focused task) | 2,000-5,000 tokens |
| Agent response (complex analysis) | 5,000-15,000 tokens |
| `git diff` (moderate PR) | 2,000-6,000 tokens |

#### Budget Allocation Strategy

For a session with ~200k usable tokens:

| Phase | Budget | Notes |
|-------|--------|-------|
| System context (CLAUDE.md, rules, hooks) | ~15-20k (fixed) | Cannot reduce; loaded automatically |
| Research/exploration | ~40-50k | Compact after this phase |
| Planning | ~20-30k | Compact after this phase |
| Implementation | ~60-80k | Largest phase; monitor with `diagnose_current` |
| Testing/verification | ~20-30k | Final phase; less room for exploration |
| Buffer for conversation | ~20-30k | User messages, assistant reasoning |

---

### Session Notepad (OMC)

Persists critical information through compaction. Three sections with different lifecycles.

| Section | Method | Lifecycle | Use For |
|---------|--------|-----------|---------|
| **Priority** | `notepad_write_priority` | Permanent, loaded at session start | Active task description, critical constraints (max 500 chars) |
| **Working** | `notepad_write_working` | Timestamped, auto-pruned after 7 days | Current findings, decisions, intermediate state |
| **Manual** | `notepad_write_manual` | Permanent, never auto-pruned | Persistent notes, project-specific knowledge |

**Read with:** `notepad_read(section="all")` or a specific section.

**Key practice:** write to notepad BEFORE compacting, not after. After compaction, the details you wanted to save are already gone.

---

### Claude-Mem for Cross-Session Persistence

For information that must survive across sessions (not just compaction within a session).

**What to persist:**
- Architectural decisions and their rationale
- Bug fixes and their root causes
- Project-specific conventions discovered during work
- Approaches that failed (to avoid repeating)
- Performance characteristics learned

**3-layer retrieval workflow (at session start):**
1. `search(query)` -- scoped terms, returns index with IDs
2. `timeline(anchor=ID)` -- context around interesting hits
3. `get_observations([IDs])` -- full details for relevant IDs only

## If GSD Is Active

When GSD is managing a project:

- **Phase-aligned compaction:** compact at each GSD phase boundary (`plan-phase` -> `execute-phase` -> verify). GSD phases naturally align with the strategic compaction table above
- **GSD config preservation:** `.planning/config.json` and `.planning/state.json` must survive compaction. Write the active phase and key decisions to notepad before compacting
- **Verification budget:** reserve at least 30k tokens for the verification phase. If `diagnose_current` shows less remaining, apply standard or aggressive prescription first
- **GSD profile impact on budget:**
  - `quality` profile uses more context (triple verification, deeper analysis) -- compact more aggressively between phases
  - `budget` profile uses less context (single verifier, lighter analysis) -- gentle prescriptions usually suffice
  - `balanced` profile -- standard prescriptions at phase boundaries
- **Guard mode for GSD teams:** if GSD spawns verification agents (triple spawn pattern), enable guard mode before the verification phase

## Common Mistakes

| Mistake | Correction |
|---------|------------|
| Letting context fill to auto-compaction boundary | Proactively compact at phase boundaries. Auto-compaction is unpredictable about what it preserves |
| Losing critical state to unguarded compaction | Enable cozempic guard mode before TeamCreate. Write key state to notepad before any compaction |
| Over-fetching context for subagents | Use iterative retrieval (dispatch with minimum, let agent request more) instead of pre-loading everything |
| Under-fetching context for subagents | Don't send agents blind. Provide at least entry-point files and type definitions |
| Compacting mid-phase | Only compact at phase boundaries. Mid-phase compaction loses intermediate reasoning that's still needed |
| Not writing to notepad before compacting | Notepad writes must happen BEFORE `/compact`. After compaction, the details are gone |
| Using aggressive prescription when gentle suffices | Start with gentle. Escalate only if insufficient. Aggressive removes exploratory context that might still be useful |
| Ignoring `diagnose_current` output | Check token breakdown to understand WHERE the bloat is. Tool results vs. agent outputs vs. conversation require different prescriptions |
| Spawning many agents without budget planning | Each agent response costs 2-15k tokens. Five agents can consume 50k+ tokens. Plan accordingly |
| Forgetting to re-read notepad after compaction | After `/compact`, explicitly `notepad_read(section="all")` to restore critical context into the active conversation |

## Quick Reference

```
Session health check:
  /cozempic → diagnose_current → check token breakdown

Prescription ladder:
  <60% usage: no action
  60-75%: gentle (old tool results)
  75-85%: standard (+ compress agent outputs)
  >85%: aggressive (+ non-essential context)

Before compacting:
  notepad_write_working (capture state) → /compact → notepad_read (restore)

Protect agent teams:
  /cozempic guard → TeamCreate → ... → TeamDelete → guard off

Subagent context (iterative retrieval):
  dispatch (minimum context) → evaluate (what's missing?) → refine (fetch more) → loop (2-3 iterations max)

Phase-boundary compact points:
  after research | after planning | after debugging | after implementation | before testing

Persistence hierarchy:
  notepad_write_priority  → survives compaction, loaded at start (500 char max)
  notepad_write_working   → survives compaction, auto-pruned 7 days
  notepad_write_manual    → survives compaction, permanent
  claude-mem /memorize    → survives across sessions, searchable

Token budget (rough per-phase for ~200k session):
  system: 15-20k | research: 40-50k | planning: 20-30k | impl: 60-80k | test: 20-30k | buffer: 20-30k
```
