# Multi-Model Delegation

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When a task would benefit from a different model's strengths -- code review, security analysis, large-context sweeps, scientific reasoning, architecture review, or when parallel verification from multiple models increases confidence. Also applies when choosing whether to keep work in Claude or delegate.

## Core Guidance

### Provider Capabilities

| Provider | Model | Context | Key Strengths | Cost |
|----------|-------|---------|---------------|------|
| **Codex** | GPT-5.4 | 1M tokens | SOTA computer use (75% OSWorld), 57.7% SWE-bench Pro, 47% token savings via tool search, 33% fewer factual errors vs GPT-5.2 | Medium |
| **Gemini** | Gemini 3.1 Pro | 1M native | SOTA GPQA Diamond (94.3%), SOTA ARC-AGI-2 (77.1%), natively multimodal (text/image/audio/video) | Cheapest frontier ($2/$12) |
| **Claude Opus** | Opus 4.6 | 200k | Best agentic goal continuity (80.8% SWE-bench Verified), deep reasoning (26.3% HLE, 91.3% GPQA) | High |
| **Claude Sonnet** | Sonnet 4.6 | 200k | Leads GDPval-AA knowledge work (1633 Elo), best coding model for implementation | Medium |

### Delegation Decision Tree

```
START: Is this task something Claude should keep?

  Code generation / implementation?
    YES --> Keep in Claude (best agentic goal continuity, direct tool access)

  Ambiguous or underspecified task?
    YES --> Keep in Claude (better assumptions, better clarifying questions)

  Requires tool-use loops (edit-test-fix cycles)?
    YES --> Keep in Claude (direct tool access; MCP models are advisory only)

  Deep multi-step logical reasoning?
    YES --> Keep in Claude Opus (26.3% HLE, 91.3% GPQA)

  Knowledge work (writing, analysis, synthesis)?
    YES --> Keep in Claude (Sonnet 1633 Elo, Opus 1606 Elo on GDPval-AA)

  Code review, verification, or critical analysis?
    YES --> Delegate to Codex (57.7% SWE-bench Pro, less likely to rubber-stamp)

  Security review (race conditions, trust boundaries)?
    YES --> Delegate to Codex (33% fewer factual errors, strong at edge cases)

  Large-codebase sweep (>200k tokens)?
    YES --> Delegate to Gemini (cheapest 1M-context model)

  Architecture review across many files?
    YES --> Delegate to Gemini (cross-module detection at scale)

  Scientific reasoning or novel pattern recognition?
    YES --> Delegate to Gemini (SOTA GPQA Diamond 94.3%, ARC-AGI-2 77.1%)

  UI/UX design review?
    YES --> Delegate to Gemini (better visual reasoning)

  Documentation generation?
    YES --> Delegate to Gemini (good prose quality at lowest cost)

  Plan or design critique?
    YES --> Delegate to Codex (strong critical analysis)
```

### Complete Delegation Workflow

#### Step 1: Discover MCP Tools

Run once per session, before the first delegation.

```
ToolSearch("select:mcp__codex-cli__codex,mcp__gemini-cli__ask-gemini")
```

If ToolSearch returns no results, the MCP server is not configured -- fall back to equivalent Claude agent. Never block on unavailable MCP tools.

#### Step 2: Check Provider Quota

Run before every handoff. Do not delegate to an exhausted provider.

```bash
${CLAUDE_SKILL_DIR}/scripts/cq.zsh --json
```

**Example output:**
```json
{
  "providers": {
    "codex": {
      "status": "available",
      "remaining": 847,
      "limit": 1000,
      "resets_at": "2026-03-11T00:00:00Z"
    },
    "gemini": {
      "status": "available",
      "remaining": 1423,
      "limit": 1500,
      "resets_at": "2026-03-11T00:00:00Z"
    }
  }
}
```

**Status values:**
- `"available"` -- proceed with delegation
- `"low"` -- proceed but conserve (avoid background jobs)
- `"exhausted"` -- skip this provider, fall back to Claude agent

#### Step 3: Construct the Delegation Prompt

Include all context the model needs -- MCP models cannot use tools, so they need files and context inline.

**For Codex:**
```
mcp__codex-cli__codex(
  prompt="Review the authentication middleware for security vulnerabilities...",
  config={"model_reasoning_effort": "high"},
  approval_policy="never",
  sandbox="workspace-write",
  cwd="/path/to/project"
)
```

**For Gemini:**
```
mcp__gemini-cli__ask-gemini(
  prompt="Analyse the architecture across these modules for coupling issues... @src/auth/ @src/users/ @src/api/",
  model="gemini-3.1-pro-preview"
)
```

**Gemini `@path` syntax:**
- `@src/auth/` -- include entire directory
- `@src/auth/middleware.ts` -- include specific file
- `@src/auth/*.ts` -- glob pattern
- Multiple paths space-separated in the prompt

#### Step 4: Fire (Parallel When Possible)

For independent concerns, delegate to multiple models simultaneously. Wrap each in a Sonnet relay subagent for true parallelism (MCP calls are synchronous).

```
# Three parallel Task() calls in one message:

Task 1: Claude subagent doing code review
Task 2: Sonnet relay → mcp__codex-cli__codex (security review)
Task 3: Sonnet relay → mcp__gemini-cli__ask-gemini (architecture review)
```

#### Step 5: Reconcile Results

| Outcome | Action |
|---------|--------|
| All models agree | Proceed with confidence |
| All find issues with overlap | Merge, deduplicate, auto-fix mechanical issues |
| Any disagreement on substance | Present all reports to user for decision |
| Only one model returned | Use the result but flag reduced confidence |

### Codex Reasoning Effort Guide

The `model_reasoning_effort` parameter controls depth of analysis. Published benchmarks use `xhigh` -- do not expect benchmark-level performance at lower settings.

| Effort | When to Use | Examples |
|--------|-------------|---------|
| `low` | Boilerplate review, doc checks, simple lookups | "Check if README matches current API" |
| `medium` | Routine code review, standard verification | "Review this CRUD endpoint for issues" |
| `high` | Refactors, security review, complex debugging, architectural analysis | "Review auth middleware for race conditions", "Analyse this refactor for regressions" |
| `xhigh` | **Retry-after-failure only.** When `high` proved insufficient on a previous attempt | Second pass after `high` missed an issue |

**Effort adjustment by GSD profile (if active):**

| Profile | Baseline | Shift Up (+1) For | Shift Down (-1) For |
|---------|----------|-------------------|---------------------|
| quality | `high` | Cross-cutting, concurrency, security, foundational | Isolated config, docs, boilerplate |
| balanced | `medium` | Cross-cutting, concurrency, security, foundational | Isolated config, docs, boilerplate |
| budget | `low` | Cross-cutting, concurrency, security, foundational | (already at minimum) |

Clamp to `low`-`high` range. Reserve `xhigh` for retry-after-failure only.

### Background Job Pattern

For long-running delegations, use background mode to avoid blocking.

```
# Step 1: Spawn with background: true
mcp__codex-cli__codex(
  prompt="Deep security audit of entire auth module...",
  config={"model_reasoning_effort": "high"},
  background=true
)
# --> Returns: job_id = "job_abc123"

# Step 2: Check status (non-blocking)
check_job_status(job_id="job_abc123")
# --> Returns: { "status": "running", "progress": "analysing file 8/23" }

# Step 3: Wait for completion (up to 1 hour)
wait_for_job(job_id="job_abc123")
# --> Returns: full result when complete
```

### Prompt Templates for Common Delegations

**Code Review (Codex):**
```
Review the following code changes for:
1. Logic errors and edge cases
2. Error handling completeness
3. API contract violations
4. Performance regressions
5. Test coverage gaps

Context: [describe what changed and why]

Files to review:
[paste diff or file contents]
```

**Security Review (Codex):**
```
Perform a security review of the following code focusing on:
1. Authentication and authorization flaws
2. Input validation and injection vulnerabilities
3. Race conditions and TOCTOU issues
4. Trust boundary violations
5. Secret/credential exposure
6. Error messages leaking sensitive data

Files:
[paste file contents]
```

**Architecture Review (Gemini):**
```
Analyse the architecture across these modules for:
1. Coupling between modules (tight coupling anti-patterns)
2. Cohesion within modules
3. Dependency direction violations
4. Circular dependencies
5. Single responsibility adherence
6. Interface segregation

@src/module-a/ @src/module-b/ @src/module-c/ @src/shared/
```

**Plan Critique (Codex):**
```
Critically evaluate this implementation plan. Challenge assumptions. Identify:
1. Missing steps or dependencies
2. Underestimated complexity
3. Risk areas not addressed
4. Alternative approaches not considered
5. Testability concerns

Plan:
[paste plan]
```

**Documentation Generation (Gemini):**
```
Generate comprehensive documentation for this module including:
1. Overview and purpose
2. Public API reference with types
3. Usage examples
4. Error handling patterns
5. Configuration options

@src/module/ @src/module/types.ts
```

### Gemini Safety Rule

**Never give Gemini write access.** Gemini is read-only for analysis, review, and sweep tasks. All implementation must remain in Claude or be routed through Codex with appropriate sandbox settings.

## If GSD Is Active

When operating within a GSD workflow:
- GSD profiles (`quality`, `balanced`, `budget`) control the Codex reasoning effort baseline. Read the active profile from `.planning/config.json`.
- During `plan-phase`, use Codex (`high`) for plan critique -- it is less likely to rubber-stamp than other models.
- During `execute-phase`, delegate reviews to Codex but keep implementation in Claude (direct tool access needed).
- During `verify-phase`, the triple-spawn pattern (see `verification.md`) is mandatory. Use GSD profile to set effort levels.
- GSD's `debug` mode can delegate root-cause hypotheses to Codex for a second opinion.

## Common Mistakes

| Mistake | Why It's Wrong | Do This Instead |
|---------|---------------|-----------------|
| Delegating implementation to Codex or Gemini | MCP models are advisory only -- no tool access | Keep implementation in Claude |
| Giving Gemini write access | Safety rule violation | Gemini is read-only; use for analysis and review only |
| Using `xhigh` reasoning effort as default | Wastes quota, reserved for retry-after-failure | Start with appropriate baseline, escalate only on failure |
| Delegating without checking quota first | May fail or exhaust remaining quota | Always run `cq --json` before handoff |
| Calling MCP tools without ToolSearch first | Deferred tools are not loaded until discovered | Run `ToolSearch("select:mcp__codex-cli__codex")` first |
| Expecting benchmark performance at `medium` effort | Published benchmarks use `xhigh` | Adjust expectations per effort level |
| Delegating ambiguous tasks to external models | Claude handles underspecified tasks better | Keep ambiguous work in Claude |
| Sequential delegation when tasks are independent | Wastes time | Use parallel relay subagents |
| Not including file context in MCP prompts | MCP models cannot use tools to read files | Include file contents or use Gemini `@path` syntax |
| Blocking on unavailable MCP tools | Session stalls | Fall back to equivalent Claude agent |

## Quick Reference

```
DELEGATION WORKFLOW:
  1. ToolSearch("select:mcp__codex-cli__codex,mcp__gemini-cli__ask-gemini")
  2. cq --json  (check quota)
  3. Construct prompt (include all context inline)
  4. Fire (parallel relay subagents for independent tasks)
  5. Reconcile (agree → proceed; disagree → escalate to user)

KEEP IN CLAUDE:
  Code generation, ambiguous tasks, tool-use loops, deep reasoning, knowledge work

DELEGATE TO CODEX:
  Code review, security review, plan critique, verification
  Effort: medium (routine) | high (complex) | xhigh (retry only)

DELEGATE TO GEMINI:
  Large-context sweep, architecture review, scientific reasoning, UI/UX review, docs
  Always read-only. Use @path for file inclusion.

GEMINI SAFETY: Never write access. Read-only always.

PARALLEL PATTERN:
  Wrap each MCP call in a Sonnet relay subagent for true parallelism.

QUOTA CHECK:
  cq --json → status: available/low/exhausted
```
