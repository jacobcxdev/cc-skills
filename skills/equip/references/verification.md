# Verification

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

Before claiming any work is complete. Triggers: finishing a feature, completing a bug fix, wrapping up a refactor, merging code, or any point where confidence in correctness matters. Also applies at GSD verify-phase, OMC team-verify stage, and ad-hoc verification checkpoints.

## Core Guidance

### Verification Sizing

Choose verifier weight based on change scope. Over-verifying wastes tokens; under-verifying risks regressions.

| Change Size | Criteria | Verifier Model | Typical Cost |
|-------------|----------|----------------|--------------|
| Small | <5 files, <100 lines changed | `model="haiku"` | ~1-2k tokens |
| Standard | 5-20 files, 100-500 lines changed | `model="sonnet"` | ~3-8k tokens |
| Large | >20 files, or security/architectural significance | `model="opus"` | ~10-25k tokens |

### The Triple-Spawn Pattern

For high-confidence verification, run THREE verifiers in parallel: Claude + Codex + Gemini. This catches issues that any single model might miss.

**Why three models?** Each has different blind spots. Claude excels at agentic verification with tool access. Codex is strongest at finding edge cases and security issues (57.7% SWE-bench Pro). Gemini handles large-context architectural analysis at lowest cost.

**Architecture:**

MCP tool calls are synchronous -- calling Codex or Gemini directly blocks the orchestrator. To achieve true parallelism, wrap each MCP call in a lightweight Sonnet relay subagent.

```
One message with three parallel Task() calls:

Task 1: Claude verifier      (has tool access, runs tests, checks files)
Task 2: Sonnet relay → Codex (advisory analysis, writes to artifact file)
Task 3: Sonnet relay → Gemini (advisory analysis, writes to artifact file)
```

### Artifact Locations

Each verifier writes results to a file, not inline. Location depends on context:

| Context | Artifact Path | Example |
|---------|--------------|---------|
| GSD workflow | `.planning/verification/` | `.planning/verification/verify-auth-refactor-CLAUDE.md` |
| OMC team-verify | `{worktree}/.omc/verification/` | `.omc/verification/verify-auth-refactor-CODEX.md` |
| Ad-hoc / one-off | `/tmp/verification-{timestamp}/` | `/tmp/verification-1741612800/verify-GEMINI.md` |

**Naming convention:** `verify-{description}-{MODEL}.md`
- `{description}`: kebab-case summary of what's being verified
- `{MODEL}`: `CLAUDE`, `CODEX`, or `GEMINI`

### Complete Triple-Spawn Workflow

#### Step 0: Pre-Verification (ECC Verification Loop)

Before spawning the triple verification, optionally run the ECC 6-phase verification loop as a mechanical pre-check. This catches obvious issues before expensive model verification.

| Phase | Tool/Command | What It Catches |
|-------|-------------|-----------------|
| 1. Build | Project build command | Compilation errors, missing deps |
| 2. Type check | `tsc --noEmit`, `mypy`, etc. | Type mismatches, interface violations |
| 3. Lint | `eslint`, `biome`, `ruff`, etc. | Style issues, common bugs |
| 4. Test | `vitest`, `pytest`, `swift test`, etc. | Functional regressions |
| 5. Security | `npm audit`, `bandit`, etc. | Known vulnerability deps |
| 6. Diff review | `git diff` | Unintended changes, debug code left in |

Fix any failures from phases 1-6 before proceeding to the triple spawn. The triple spawn should verify semantics, not catch linting errors.

#### Step 1: Discover MCP Tools

```
ToolSearch("select:mcp__codex-cli__codex,mcp__gemini-cli__ask-gemini")
```

#### Step 2: Check Quota

```bash
${CLAUDE_SKILL_DIR}/scripts/cq.zsh --json
```

Skip any provider with `status: "exhausted"`. Proceed with remaining providers.

#### Step 3: Construct the Verification Prompt

The verification prompt should include:
- What was changed and why
- Files modified (list or diff)
- Specific concerns to check
- Acceptance criteria if available

#### Step 4: Fire Three Parallel Tasks

**Task 1 -- Claude Verifier:**
```
Task(
  subagent_type="oh-my-claudecode:verifier",
  model="sonnet",  # or haiku/opus per sizing
  prompt="Verify the auth middleware refactor. Check:
    1. All tests pass
    2. No regressions in existing behaviour
    3. Error handling is complete
    4. Types are correct
    5. No security regressions
    Write results to {artifact_path}/verify-auth-refactor-CLAUDE.md"
)
```

**Task 2 -- Codex Relay:**
```
Task(
  subagent_type="general-purpose",
  model="sonnet",
  prompt="You are a relay agent. Call the Codex MCP tool to perform verification,
    then write the result to a file.

    1. Discover the tool:
       ToolSearch('select:mcp__codex-cli__codex')

    2. Call Codex:
       mcp__codex-cli__codex(
         prompt='Review the following changes for correctness, edge cases,
           error handling, and security. Be critical -- do not rubber-stamp.

           Changes: [describe changes]
           Files: [list files or paste diff]

           Output a structured report with:
           - PASS/FAIL verdict
           - Issues found (severity: CRITICAL/HIGH/MEDIUM/LOW)
           - Specific line references
           - Suggested fixes',
         config={'model_reasoning_effort': 'high'},
         approval_policy='never',
         sandbox='workspace-write',
         cwd='/path/to/project'
       )

    3. Write the full Codex response to:
       {artifact_path}/verify-auth-refactor-CODEX.md"
)
```

**Task 3 -- Gemini Relay:**
```
Task(
  subagent_type="general-purpose",
  model="sonnet",
  prompt="You are a relay agent. Call the Gemini MCP tool to perform verification,
    then write the result to a file.

    1. Discover the tool:
       ToolSearch('select:mcp__gemini-cli__ask-gemini')

    2. Call Gemini:
       mcp__gemini-cli__ask-gemini(
         prompt='Analyse these changes for architectural correctness,
           cross-module consistency, and potential regressions.

           Focus on:
           - Does the change maintain module boundaries?
           - Are there any cross-cutting concerns missed?
           - Is error propagation consistent?
           - Are there any files that should have been modified but weren\'t?

           @src/auth/ @src/middleware/ @src/types/

           Output a structured report with:
           - PASS/FAIL verdict
           - Issues found (severity: CRITICAL/HIGH/MEDIUM/LOW)
           - Specific file and line references
           - Suggested fixes',
         model='gemini-3.1-pro-preview'
       )

    3. Write the full Gemini response to:
       {artifact_path}/verify-auth-refactor-GEMINI.md"
)
```

#### Step 5: Read Artifacts and Reconcile

After all three tasks complete, read the artifact files from disk.

### Reconciliation Decision Tree

```
Read all three artifacts.

ALL THREE returned results?
  NO --> Did at least one return?
    YES --> Use available results, flag reduced confidence
    NO  --> Retry all. If retry fails, run manual verification.

ANY CRITICAL issues found?
  YES --> Are they mechanical (typos, wrong refs, missing assertions)?
    YES --> Auto-fix immediately. Do not escalate.
    NO  --> Present to user for decision.

ALL THREE agree (same verdict)?
  YES --> Proceed with the consensus verdict.

ALL THREE found issues but with overlap?
  YES --> Merge findings, deduplicate, auto-fix mechanical issues.
         Flag genuinely ambiguous issues for user.

ANY DISAGREEMENT on substance?
  YES --> Present all three reports to user.
         Highlight the specific points of disagreement.
         Do not pick a winner -- let the user decide.
```

**Reconciliation examples:**

| Scenario | Claude Says | Codex Says | Gemini Says | Action |
|----------|------------|------------|-------------|--------|
| Full agreement | PASS | PASS | PASS | Proceed |
| All find same issue | "Missing null check line 42" | "Null dereference line 42" | "Unchecked optional line 42" | Auto-fix: add null check at line 42 |
| Mechanical overlap | PASS | "Typo in error message line 88" | PASS | Auto-fix: correct typo |
| Substantive disagreement | PASS | "Race condition in token refresh" | PASS | Present all reports to user |
| Partial return | PASS | (timeout) | PASS | Use Claude + Gemini, flag reduced confidence |

### Reasoning Effort for Codex Verification

| GSD Profile | Baseline | Shift Up (+1) | Shift Down (-1) |
|-------------|----------|---------------|------------------|
| quality | `high` | Cross-cutting changes, concurrency, security-sensitive | Isolated config, docs, boilerplate |
| balanced | `medium` | Cross-cutting changes, concurrency, security-sensitive | Isolated config, docs, boilerplate |
| budget | `low` | Cross-cutting changes, concurrency, security-sensitive | (already at minimum) |

Clamp to `low`-`high`. Reserve `xhigh` for retry-after-failure only.

### MCP Call Defaults

Always include these parameters:

**Codex:**
```json
{
  "config": { "model_reasoning_effort": "<effort per table above>" },
  "approval_policy": "never",
  "sandbox": "workspace-write",
  "cwd": "<project_root>"
}
```

**Gemini:**
```json
{
  "model": "gemini-3.1-pro-preview"
}
```
Use `@path` syntax in the prompt to include files Gemini needs to read.

### Failure Handling

| Failure | First Response | Second Response |
|---------|---------------|-----------------|
| Verifier returns no output | Retry once | Skip, proceed with remaining verifiers |
| Verifier times out | Retry once | Skip, proceed with remaining verifiers |
| MCP tool not found | Check ToolSearch, retry discovery | Fall back to Claude-only verification |
| All verifiers fail | Retry all once | Fall back to manual verification (run tests, review diff yourself) |

### Dismissed Findings

When a finding is reviewed and dismissed (not a real issue, or deferred intentionally), it must still be captured:
- Record so it surfaces in future planning: GSD → `STATE.md` TODO; OMC → `notepad_write_working`; standalone → project `MEMORY.md` or inline `// TODO:` comment
- This prevents dismissed items from silently disappearing
- Future planning cycles can re-evaluate whether the deferral is still appropriate

### Integration with OMC Team-Verify Stage

In the OMC team pipeline (`team-plan --> team-prd --> team-exec --> team-verify --> team-fix`):

1. `team-verify` stage triggers triple-spawn automatically
2. Artifacts go to `{worktree}/.omc/verification/`
3. If verification finds issues:
   - Mechanical fixes --> auto-fix, stay in `team-verify`
   - Substantive issues --> transition to `team-fix` stage
   - `team-fix` routes to `executor`/`build-fixer`/`debugger` depending on defect type
4. After `team-fix`, transition back to `team-verify` for re-verification
5. Loop is bounded by max attempts; exceeding bound transitions to `failed`

### ECC Verification Loop (Complementary Pre-Check)

The 6-phase ECC verification loop runs mechanical checks before the triple spawn. It is not a replacement -- it is a fast pre-filter.

```
Phase 1: Build      --> catch compilation errors before wasting model tokens
Phase 2: Type check --> catch type mismatches (tsc, mypy, swiftc)
Phase 3: Lint       --> catch style and common bug patterns
Phase 4: Test       --> catch functional regressions
Phase 5: Security   --> catch known vulnerable dependencies
Phase 6: Diff review --> catch unintended changes, debug leftovers

ALL PASS? --> Proceed to triple-spawn verification
ANY FAIL? --> Fix first, then re-run ECC loop, then triple-spawn
```

The triple spawn then focuses on semantic correctness, architectural fit, and edge cases -- things mechanical tools cannot catch.

## If GSD Is Active

When operating within a GSD workflow:
- Triple spawn is mandatory before ANY `Task()` call that spawns `gsd-plan-checker`, `gsd-verifier`, or `gsd-integration-checker`.
- Read the active GSD profile from `.planning/config.json` to determine Codex reasoning effort baseline.
- Artifacts write to `.planning/verification/` following GSD's directory structure.
- GSD profiles control effort: `quality` starts at `high`, `balanced` at `medium`, `budget` at `low`. Apply the shift table above.
- During GSD `verify-phase`, always run the ECC 6-phase loop first, then triple-spawn.
- GSD's `debug` mode can feed findings from failed verification back into the debug cycle.

## Common Mistakes

| Mistake | Why It's Wrong | Do This Instead |
|---------|---------------|-----------------|
| Skipping verification for "small" changes | Small changes cause regressions too | Use `model="haiku"` for small changes -- cheap and fast |
| Running triple-spawn for a typo fix | Overkill; wastes three model calls | Single haiku verifier is sufficient for trivial changes |
| Calling MCP tools directly (not via relay subagent) | Blocks the orchestrator -- no parallelism | Wrap each MCP call in a Sonnet relay subagent |
| Writing verification results inline (not to file) | Bloats conversation context; hard to reconcile | Always write to artifact files, read from disk |
| Auto-fixing ambiguous issues | May introduce wrong fix | Only auto-fix mechanical issues (typos, wrong refs, missing assertions) |
| Dismissing findings without recording them | Lost context; may resurface as bugs | Record dismissed findings (GSD → STATE.md, OMC → notepad, standalone → MEMORY.md/TODO comment) |
| Using `xhigh` Codex effort as default | Wastes quota; reserved for retry-after-failure | Start with profile baseline, escalate only on failure |
| Skipping ECC 6-phase loop before triple-spawn | Wastes expensive model tokens on linting issues | Run mechanical checks first; fix before triple-spawn |
| Not checking quota before spawning relays | Relay fails mid-verification | Always `cq --json` first; skip exhausted providers |
| Picking a winner when models disagree | You are not the arbiter of substantive disputes | Present all reports to user; highlight disagreements |

## Quick Reference

```
VERIFICATION SIZING:
  Small  (<5 files, <100 lines)   --> model="haiku"
  Medium (5-20 files)             --> model="sonnet"
  Large  (>20 files, security)    --> model="opus"

TRIPLE-SPAWN PATTERN:
  1. ToolSearch("select:mcp__codex-cli__codex,mcp__gemini-cli__ask-gemini")
  2. cq --json (check quota)
  3. Three parallel Task() calls:
     - Claude verifier (oh-my-claudecode:verifier)
     - Sonnet relay → Codex (writes to artifact-CODEX.md)
     - Sonnet relay → Gemini (writes to artifact-GEMINI.md)
  4. Read artifacts from disk
  5. Reconcile (agree → proceed; disagree → present to user)

ARTIFACT LOCATIONS:
  GSD:     .planning/verification/
  OMC:     {worktree}/.omc/verification/
  Ad-hoc:  /tmp/verification-{timestamp}/

RECONCILIATION:
  All agree         --> proceed
  Overlap issues    --> merge, deduplicate, auto-fix mechanical
  Disagreement      --> present all to user
  Partial return    --> use available, flag reduced confidence

ECC 6-PHASE PRE-CHECK:
  build → type check → lint → test → security → diff review
  Fix failures BEFORE triple-spawn.

CODEX EFFORT:
  quality → high | balanced → medium | budget → low
  +1 for cross-cutting/security | -1 for config/docs
  xhigh = retry-after-failure ONLY

DISMISSED FINDINGS:
  Record: GSD → STATE.md | OMC → notepad | standalone → MEMORY.md / TODO comment
```
