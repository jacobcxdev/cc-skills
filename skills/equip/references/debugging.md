# Debugging

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When you encounter bugs, test failures, unexpected behavior, crashes, performance issues, or memory problems and need a structured approach to diagnosis and resolution.

## Core Guidance

### Debugging Tool Selection

| Situation | Primary Tool | When to Escalate | Escalation Target |
|-----------|-------------|------------------|-------------------|
| Standard bug (known area, clear symptoms) | OMC `debugger` agent | Root cause elusive after 2 iterations | Taches `/debug-like-expert` |
| Complex/mysterious bug (no clear cause) | Taches `/debug-like-expert` | Need multi-model perspective | Multi-model delegation |
| iOS crash | Axiom `crash-analyzer` skill | Non-crash iOS issues | Axiom `ios-performance` |
| iOS memory issue | Axiom `memory-auditor` skill | Need Instruments profiling | Manual Instruments workflow |
| Performance regression | OMC `scientist` + `debugger` | Need architecture-level fix | `architect` agent |
| Build failure | OMC `build-fixer` agent | Toolchain/dependency issue | `document-specialist` for docs |
| Flaky test | OMC `test-engineer` agent | Test infrastructure issue | `debugger` for root cause |

### OMC Debugger Agent Workflow

The OMC `debugger` agent (sonnet) performs structured root-cause analysis with tool access.

**How to invoke:**

```
Task(subagent_type="oh-my-claudecode:debugger", model="sonnet",
     prompt="User reports 500 error on POST /api/orders when cart has >10 items.
             Error log: 'TypeError: Cannot read property map of undefined'
             Relevant files: src/api/orders.ts, src/services/cart.ts")
```

**What the debugger does:**
1. Reads error context (logs, stack traces, error messages)
2. Explores relevant code paths using search tools
3. Identifies the root cause with evidence
4. Proposes a fix with explanation
5. Optionally implements the fix if instructed

**Best practices for debugger prompts:**
- Include the exact error message or unexpected behavior
- Specify which files/modules are likely involved
- Include reproduction steps if known
- Mention what has already been tried

**Example prompts by scenario:**

| Scenario | Prompt |
|----------|--------|
| Runtime error | `"TypeError: Cannot read property 'id' of null in src/handlers/user.ts:42. Happens when user has no profile."` |
| Test failure | `"test/auth.test.ts:15 fails with 'expected 200 got 401'. The test was passing before commit abc123."` |
| Regression | `"User search was returning results in <100ms, now takes >2s. Changed: src/search/index.ts, src/db/queries.ts"` |
| Intermittent | `"POST /api/upload fails ~10% of the time with 'connection reset'. No pattern in timing."` |

### Taches Debug-Like-Expert Protocol

The `/debug-like-expert` skill implements the scientific method for debugging. Use when the OMC debugger fails to find the root cause, or when the bug is complex/mysterious.

**Full protocol:**

#### Phase 1: Observation

Gather all available evidence before forming hypotheses.

- Collect error messages, stack traces, log output
- Note environmental conditions (OS, runtime version, config)
- Identify what changed recently (commits, dependencies, config)
- Document reproduction steps and frequency
- Check if the issue is deterministic or intermittent

#### Phase 2: Hypothesis Formation

Generate multiple competing hypotheses ranked by likelihood.

```
Hypothesis 1 (most likely): Race condition in session middleware
  Evidence for: Intermittent, concurrent requests, shared state
  Evidence against: Single-threaded Node.js event loop
  Test: Add request ID logging, check interleaving

Hypothesis 2: Stale cache returning expired session
  Evidence for: TTL config recently changed, error is "session not found"
  Evidence against: Cache logs show no evictions
  Test: Disable cache, reproduce
```

**Key principle:** Generate at least 3 hypotheses. Rank by likelihood. Test the most likely first, but do not anchor -- be willing to abandon a hypothesis when evidence contradicts it.

#### Phase 3: Experiment Design

For each hypothesis, design a minimal experiment that either confirms or refutes it.

| Hypothesis | Experiment | Expected Result (if true) | Expected Result (if false) |
|-----------|-----------|--------------------------|---------------------------|
| Race condition | Add mutex around session access | Error stops | Error continues |
| Stale cache | Disable cache entirely | Error stops | Error continues |
| Bad input | Add input validation logging | Invalid input logged before error | Valid input logged |

**Rules for experiments:**
- Change one variable at a time
- Make the experiment reversible
- Define success/failure criteria before running
- Set a time limit for each experiment

#### Phase 4: Execution & Analysis

Run experiments, collect data, update hypotheses.

- If hypothesis confirmed: proceed to fix
- If hypothesis refuted: update ranking, test next hypothesis
- If inconclusive: refine experiment or add instrumentation
- After 3 failed hypotheses: step back, re-examine assumptions

#### Phase 5: Domain Expertise Loading

`/debug-like-expert` can load domain-specific expertise for the technology involved:

| Domain | Expertise Loaded | Covers |
|--------|-----------------|--------|
| Node.js/JS | Event loop, async patterns, memory leaks | Callback hell, promise rejection, GC pressure |
| Python | GIL, async/await, import system | Circular imports, thread safety, virtualenv |
| iOS/Swift | ARC, concurrency, UIKit lifecycle | Retain cycles, data races, main thread violations |
| Database | Query plans, locking, connection pools | Deadlocks, N+1, connection exhaustion |
| Network | TCP state, DNS, TLS | Timeouts, certificate errors, connection reuse |

### When to Escalate from Debugger to Debug-Like-Expert

| Signal | Meaning | Action |
|--------|---------|--------|
| Debugger finds cause in 1-2 iterations | Standard bug | Stay with debugger, fix it |
| Debugger proposes fix but it doesn't work | Misidentified root cause | Escalate to `/debug-like-expert` |
| Bug is intermittent / timing-dependent | Likely race condition or external dependency | Start with `/debug-like-expert` |
| Multiple possible causes, none confirmed | Need systematic elimination | Escalate to `/debug-like-expert` |
| Bug spans multiple services or processes | Complex interaction | Start with `/debug-like-expert` |
| Stack trace points nowhere useful | Need deeper instrumentation | Escalate to `/debug-like-expert` |

### Multi-Model Debugging

For particularly stubborn bugs, delegate hypothesis generation to multiple models in parallel:

**Pattern:** Fan out to Codex and Gemini for independent analysis, then reconcile.

```
# Parallel hypothesis generation
1. Claude debugger: analyzes code with tool access
2. Codex relay: "Given this error and these files, what are the top 3 root causes?"
3. Gemini relay: "Analyze these files for the bug described. What could cause [symptom]?"

# Reconciliation
- All agree on cause → high confidence, fix it
- Different causes identified → test each hypothesis
- One model finds something others missed → investigate that angle
```

**When to use multi-model debugging:**
- Bug has persisted through 2+ fix attempts
- Root cause is genuinely unclear after systematic investigation
- The bug is in a critical path (auth, payments, data integrity)

### Crash Log Analysis

#### iOS (Axiom crash-analyzer)

```
# Invoke the Axiom crash-analyzer skill
/axiom:crash-analyzer

# Or directly with the crash log
Task(subagent_type="oh-my-claudecode:debugger", model="sonnet",
     prompt="Analyze this iOS crash log: [paste crash log]
             Focus on: thread that crashed, exception type, last meaningful frame")
```

**What crash-analyzer provides:**
- Exception type interpretation (EXC_BAD_ACCESS, SIGABRT, etc.)
- Thread analysis (which thread crashed, what it was doing)
- Symbolication assistance
- Common cause identification per exception type

#### Other Platforms (Manual Analysis)

1. **Identify the crash type** -- segfault, null pointer, stack overflow, OOM
2. **Find the crashing frame** -- top of stack trace in your code (not library code)
3. **Check recent changes** -- `git log --oneline -20` near the crashing file
4. **Reproduce minimally** -- strip down to smallest reproduction case
5. **Add instrumentation** -- logging/assertions around the crash site

### Memory Debugging

#### iOS (Axiom memory-auditor)

```
/axiom:memory-auditor
```

**Covers:**
- Retain cycle detection (common with closures capturing `self`)
- Allocation tracking patterns
- Autorelease pool sizing
- Instruments profiling workflow guidance

#### General Memory Debugging

| Symptom | Likely Cause | Investigation |
|---------|-------------|---------------|
| Gradual memory growth | Leak (retained references) | Heap snapshots over time, look for growing counts |
| Sudden OOM | Large allocation or unbounded collection | Check loops that append, large file reads, image processing |
| Memory spike then return | Expected but inefficient | Profile peak allocation, consider streaming |
| Stable but too high | Over-caching or redundant data | Audit cache sizes, check for duplicate data structures |

### Performance Debugging Workflow

1. **Measure baseline** -- use `scientist` agent to establish current metrics
2. **Identify bottleneck** -- profiling, flame graphs, slow query logs
3. **Classify the bottleneck:**

| Bottleneck Type | Investigation Tool | Common Fixes |
|----------------|-------------------|-------------|
| CPU-bound | Profiler/flame graph | Algorithm optimization, caching, parallelism |
| I/O-bound | Network/disk profiling | Batching, connection pooling, async I/O |
| Memory-bound | Heap analysis | Streaming, pagination, cache eviction |
| Lock contention | Concurrency profiler | Lock-free structures, finer-grained locks |

4. **Design optimization** -- with `architect` if structural change needed
5. **Implement** -- with `executor`
6. **Verify improvement** -- re-measure with `scientist`, compare to baseline

## If GSD Is Active

When GSD is already running, use `/gsd:debug` which wraps the OMC debugger agent with GSD context:

- Automatically loads the current GSD phase context
- Tracks debugging iterations in GSD state
- Integrates fix verification with the GSD verify phase
- Respects the GSD profile for verification depth:
  - `quality`: Full regression test suite after fix
  - `balanced`: Targeted tests for the affected area
  - `budget`: Minimal smoke test

Use `/gsd:debug` instead of spawning the OMC debugger directly when inside a GSD project. The debugger behavior is the same, but state tracking is integrated.

## Common Mistakes

| Mistake | Why It's Wrong | Correct Approach |
|---------|---------------|-----------------|
| Fixing without reproducing | May fix a symptom, not the cause | Write a failing test first (bug-fix policy) |
| Single hypothesis fixation | Anchoring bias leads to wasted time | Generate 3+ hypotheses, rank, test systematically |
| Changing multiple things at once | Cannot identify which change fixed it | One variable per experiment |
| Ignoring intermittent failures | They indicate real bugs (races, leaks) | Use `/debug-like-expert` with timing analysis |
| Reading entire codebase to find bug | Wastes context window | Use Grep/LSP to narrow to relevant code |
| Skipping memory search | May re-investigate a known bug | Search claude-mem for error text and symptoms |
| Using `print` debugging exclusively | Slow iteration, pollutes code | Use debugger agent with structured analysis |
| Not checking recent git changes | The bug was likely introduced recently | `git log` and `git bisect` narrow the window |
| Fixing the test instead of the code | Hides the real bug | Fix implementation; only fix tests if they are wrong |
| Spending >30 min on one hypothesis | Diminishing returns | Time-box experiments, move to next hypothesis |

## Quick Reference

```
DEBUGGING DECISION FLOW:
  Known area, clear error?     → OMC debugger (sonnet)
  Elusive after 2 iterations?  → /debug-like-expert (scientific method)
  iOS crash?                   → Axiom crash-analyzer
  iOS memory?                  → Axiom memory-auditor
  Performance regression?      → scientist (measure) → debugger (identify) → fix
  Build failure?               → build-fixer agent
  Flaky test?                  → test-engineer agent
  Stubborn (2+ failed fixes)?  → Multi-model (Claude + Codex + Gemini)

SCIENTIFIC METHOD TEMPLATE:
  1. OBSERVE: error, logs, env, recent changes, repro steps
  2. HYPOTHESIZE: 3+ ranked causes with evidence for/against
  3. EXPERIMENT: one variable, reversible, criteria defined
  4. ANALYZE: confirmed → fix | refuted → next | unclear → refine
  5. ITERATE: max 3 hypotheses before re-examining assumptions

BUG-FIX POLICY (mandatory):
  1. Search memory for prior fix
  2. Write failing test that reproduces
  3. Spawn agent to fix + verify test passes

DEBUGGER PROMPT TEMPLATE:
  "Symptom: [exact error/behavior]
   Reproduction: [steps or frequency]
   Relevant files: [paths]
   Recent changes: [commits or PRs]
   Already tried: [what didn't work]"
```
