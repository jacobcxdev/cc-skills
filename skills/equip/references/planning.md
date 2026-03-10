# Planning & Execution

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When you need to decide how to approach a task: whether to act directly, create a plan, track progress, or orchestrate multiple agents. Covers the full spectrum from "just do it" to complex phased projects.

## Core Guidance

### Complexity Assessment

Before choosing a planning approach, assess the task:

| Signal | Complexity Level | Indicators |
|--------|-----------------|------------|
| Trivial | None | Single file, clear action, < 5 minutes |
| Low | Minimal | 1-3 files, well-understood pattern, < 30 minutes |
| Medium | Moderate | 3-10 files, some unknowns, requires sequencing |
| High | Significant | 10+ files, cross-cutting concerns, multiple phases |
| Uncertain | Unknown | Vague requirements, unfamiliar codebase, novel problem |

### Planning Approach Selection

| Complexity | Default Approach | When to Escalate | Escalation Target |
|-----------|-----------------|------------------|-------------------|
| Trivial | Just do it | Never | -- |
| Low | Plan mode (`/plan`) | Task grows beyond estimate | TaskList |
| Medium | TaskList (native) | Independent subtasks emerge | TeamCreate |
| High (parallel) | TeamCreate (native) | Need staged pipeline with gates | OMC `/team` |
| High (phased) | OMC `/team` | Need consensus before execution | `/plan --consensus` |
| Uncertain | OMC `/deep-interview` | Clarity achieved | `ralplan` then `autopilot` |
| Doc-heavy | claude-mem `/make-plan` then `/do` | Multi-agent needed | OMC executor/team |

### Approach Details

#### 1. Just Do It

**When:** Single clear action, no ambiguity, no risk of wasted work.

```
User: "Add a .gitignore entry for .env files"
→ Edit the file directly. No plan needed.
```

**Escalation trigger:** You realize the task touches more files than expected or has dependencies.

#### 2. Plan Mode (`/plan`)

**What it does:** Enters a structured planning state that manages permissions, clears irrelevant context, and focuses on step-by-step reasoning before execution.

**When:** You need to think through steps before acting, but the task is self-contained.

```
User: "Refactor the logger to support structured output"
→ /plan
→ Produces: ordered steps, affected files, risk assessment
→ Execute step by step
```

**Key behaviors in plan mode:**
- Permissions are adjusted (read-heavy, write-restricted until execution)
- Context is cleared of irrelevant prior work
- Forces explicit step enumeration before any code changes
- Naturally transitions to execution after plan approval

**Escalation trigger:** Plan reveals 5+ independent steps that could run in parallel.

#### 3. TaskList (Native)

**What it does:** Creates a persistent, ordered checklist that survives context compaction. Tracks status of each step.

**When:** Multi-step work where you need to track progress and show the user what's done vs remaining.

```
User: "Set up the CI pipeline with lint, test, build, and deploy stages"
→ TaskList with 4 items
→ Check off each as completed
→ User sees real-time progress
```

**Advantages over mental tracking:**
- Persists through compaction (critical for long sessions)
- Visible to the user at any time
- Reveals misunderstood requirements early (user can correct the list)

**Escalation trigger:** Multiple items are independent and could run simultaneously.

#### 4. TeamCreate (Native)

**What it does:** Spawns parallel Claude subagents that work independently on separate tasks. Lightweight, no formal pipeline stages.

**When:** 2+ independent tasks that each take >30 seconds. No complex coordination needed.

```
User: "Review the API module for security and performance"
→ TeamCreate
→ Task 1: security-reviewer on src/api/
→ Task 2: quality-reviewer on src/api/
→ Both run in parallel, reconcile results
```

**TeamCreate lifecycle:**
1. `TeamCreate` -- create the team
2. `TaskCreate` x N -- define tasks
3. `Task(team_name, name)` x N -- spawn teammates (parallel)
4. Teammates claim and complete tasks
5. `SendMessage(shutdown_request)` -- signal completion
6. `TeamDelete` -- clean up

**Escalation trigger:** Tasks have dependencies, need stage gates, or require formal verification between phases.

#### 5. OMC Team (`/team`)

**What it does:** Full staged pipeline with formal phase transitions, specialized agent routing per stage, and fix loops.

**When:** Complex projects requiring coordinated phases: plan, specify, execute, verify, fix.

**The staged pipeline:**

```
team-plan → team-prd → team-exec → team-verify → team-fix (loop)
```

| Stage | What Happens | Agents Used |
|-------|-------------|-------------|
| `team-plan` | Explore codebase, create execution plan | `explore` (haiku) + `planner` (opus), optionally `analyst`/`architect` |
| `team-prd` | Define acceptance criteria, scope | `analyst` (opus), optionally `critic` |
| `team-exec` | Implement the plan | `executor` (sonnet) + specialists as needed |
| `team-verify` | Verify work meets acceptance criteria | `verifier` (sonnet) + reviewers as needed |
| `team-fix` | Fix issues found in verification | `executor`/`build-fixer`/`debugger` by defect type |

**Stage transitions:**
- `team-plan` to `team-prd`: planning complete, decomposition done
- `team-prd` to `team-exec`: acceptance criteria explicit
- `team-exec` to `team-verify`: all execution tasks in terminal state
- `team-verify` to `team-fix` or `complete`: verification decides
- `team-fix` to `team-exec` or `team-verify`: fixes feed back (bounded by max attempts)

**Terminal states:** `complete`, `failed`, `cancelled`.

**Team + Ralph:** Combine `/team ralph` for persistent team execution. Team provides multi-agent orchestration; ralph provides the persistence loop. Cancel either cancels both.

#### 6. Plan with Consensus (`/plan --consensus` or `/ralplan`)

**What it does:** Iterative planning with Planner, Architect, and Critic agents until all three agree on the approach.

**When:** High-stakes decisions where a single perspective is insufficient. Architecture changes, major refactors, new system design.

```
User: "We need to redesign the data pipeline for real-time processing"
→ /plan --consensus (or /ralplan)
→ Planner proposes approach
→ Architect evaluates structural implications
→ Critic challenges assumptions
→ Iterate until consensus
→ Execute the agreed plan
```

**Consensus criteria:** All three agents agree on approach, risks are acknowledged, and mitigations are defined.

#### 7. Deep Interview (`/deep-interview`)

**What it does:** Structured interview to extract clarity from vague ideas. Asks probing questions, identifies hidden requirements, surfaces assumptions.

**When:** The user has an idea but hasn't specified what they actually want. Requirements are unclear or contradictory.

```
User: "I want a better notification system"
→ /deep-interview
→ Probing questions: What channels? What triggers? What priority model?
→ Produces: clear requirements document
→ Flows into: ralplan → autopilot
```

**Natural flow:** deep-interview (clarity) then ralplan (consensus plan) then autopilot (execution).

#### 8. Claude-mem Make-Plan (`/make-plan` then `/do`)

**What it does:** Creates a plan document stored in claude-mem, then executes it step by step with `/do`.

**When:** Doc-heavy tasks where the plan itself is a deliverable, or when you want plan persistence across sessions via memory.

```
User: "Create a comprehensive API documentation update plan"
→ /make-plan -- produces structured plan in claude-mem
→ /do -- executes each step, checking off as it goes
```

**Advantage over /plan:** Plan persists in claude-mem across sessions. Good for multi-session work.

### TaskList vs TeamCreate Decision Guide

| Factor | TaskList | TeamCreate |
|--------|----------|------------|
| Task independence | Sequential or loosely ordered | Fully independent |
| Parallelism | None (one at a time) | Full (all run simultaneously) |
| Coordination | Simple checklist | Message passing between agents |
| Overhead | Minimal | Team lifecycle management |
| Visibility | Checklist UI | Task status tracking |
| Best for | Ordered workflows, progress tracking | Independent parallel work |
| Duration per task | Any | Each task > 30 seconds |

**Decision rule:** If tasks must run in order or you just need a checklist, use TaskList. If tasks are independent and each takes meaningful time, use TeamCreate.

### Planning Skill Quick Comparison

| Skill | Input State | Output | Best For |
|-------|------------|--------|----------|
| `/plan` | Clear task | Ordered steps | Structured approach to known work |
| `/plan --consensus` | Complex task | Agreed plan | High-stakes architectural decisions |
| `/plan --review` | Existing plan | Critique | Validating a plan before execution |
| `/ralplan` | Complex task | Consensus plan | Alias for `/plan --consensus` |
| `/deep-interview` | Vague idea | Clear requirements | Extracting clarity from ambiguity |
| `/make-plan` | Any task | Persistent plan doc | Multi-session work, doc-heavy tasks |
| `/critique` | Existing plan/design | Critical analysis | Second opinion on any proposal |

## If GSD Is Active

When GSD is already running, planning integrates with GSD phases:

| GSD Command | Equivalent To | When To Use |
|-------------|--------------|-------------|
| `/gsd:plan-phase` | OMC `/team` team-plan stage | Planning within a GSD project |
| `/gsd:execute-phase` | OMC `/team` team-exec stage | Executing a GSD plan |
| `/gsd:debug` | OMC `debugger` agent | Debugging within GSD context |

**GSD profile affects planning depth:**
- `quality`: Full consensus planning, triple verification
- `balanced`: Standard planning, single verification
- `budget`: Minimal planning, skip verification for low-risk changes

**Do not start GSD for planning.** Use the native approaches above. GSD is a project management wrapper, not a planning tool.

## Common Mistakes

| Mistake | Why It's Wrong | Correct Approach |
|---------|---------------|-----------------|
| Planning a one-line change | Overhead exceeds value | Just do it |
| Using `/plan` for vague requirements | Plan mode assumes clarity | Use `/deep-interview` first |
| Sequential agents when independent | Wastes time on parallelizable work | Use TeamCreate or OMC `/team` |
| Skipping TaskList for 5+ step work | Losing track after compaction | Always use TaskList for multi-step |
| Using TeamCreate for 2 dependent tasks | Tasks will race/conflict | Use TaskList (sequential) |
| Jumping to `/team` for 2 simple parallel tasks | Pipeline overhead is disproportionate | Use TeamCreate (lightweight) |
| Using `/plan --consensus` for routine work | Three opus agents for a simple feature | Use `/plan` (single planner) |
| Not checking for existing plans in memory | Redoing work from a prior session | Search claude-mem first |
| Starting execution without user approval of plan | User may disagree with approach | Present plan, wait for confirmation |

## Quick Reference

```
COMPLEXITY → APPROACH:
  Trivial (1 file, obvious)     → Just do it
  Low (1-3 files, clear)        → /plan
  Medium (3-10 files, sequence) → TaskList
  High (parallel, independent)  → TeamCreate
  High (phased, coordinated)    → OMC /team
  High-stakes design            → /plan --consensus (or /ralplan)
  Vague requirements            → /deep-interview → ralplan → autopilot
  Multi-session doc work        → /make-plan → /do

ESCALATION PATH:
  just do it → /plan → TaskList → TeamCreate → /team → /plan --consensus

TEAM PIPELINE STAGES:
  team-plan → team-prd → team-exec → team-verify → team-fix (loop)

KEY RULES:
  - Independent tasks > 30s each? → Parallel (TeamCreate or /team)
  - Dependent tasks? → Sequential (TaskList or /plan)
  - Vague input? → Interview first, plan second
  - High stakes? → Consensus planning (3 agents agree)
  - Plan persists across sessions? → /make-plan (claude-mem)
```
