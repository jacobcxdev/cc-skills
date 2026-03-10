# Agent Routing

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When you need to delegate work to a specialized agent, choose between overlapping OMC/ECC agents, select the right model tier, or compose multi-agent workflows.

## Core Guidance

### Agent Selection: OMC vs ECC

OMC agents are the default. They integrate with the team pipeline, model routing, and MCP delegation. Use ECC agents only when they provide unique capability with no OMC equivalent.

**ECC-Unique Agents (no OMC equivalent):**

| Agent | Domain | When to Use | Example Prompt |
|-------|--------|-------------|----------------|
| `python-reviewer` | Python | PEP 8, type hints, Pythonic idioms, async patterns | `"Review auth/handlers.py for Pythonic idioms and type safety"` |
| `go-reviewer` | Go | Idiomatic Go, goroutine/channel patterns, error wrapping | `"Review pkg/worker/pool.go for idiomatic concurrency"` |
| `go-build-resolver` | Go | go build/vet/linter failures, module resolution | `"Fix 'cannot find module' errors in go build output"` |
| `database-reviewer` | SQL | PostgreSQL/Supabase query optimization, index strategy | `"Review this migration for N+1 queries and missing indexes"` |
| `refactor-cleaner` | Any | Dead code removal via knip, depcheck, ts-prune | `"Find and remove unused exports across src/"` |
| `harness-optimizer` | Meta | Agent harness config tuning (prompts, tool lists) | `"Optimize the executor agent's tool permissions"` |
| `chief-of-staff` | Comms | Email/Slack/LINE/Messenger triage and drafting | `"Triage my unread Slack channels and draft replies"` |
| `loop-operator` | Meta | Monitor running agent loops, intervene on stalls | `"Check ralph loop health and restart if stalled"` |

**Duplicate Agents -- Always Prefer OMC:**

| OMC Agent | ECC Equivalent (avoid) | Why OMC Wins |
|-----------|----------------------|--------------|
| `code-reviewer` | `code-reviewer` | Opus model, integrated review lane |
| `security-reviewer` | `security-reviewer` | MCP delegation support |
| `architect` | `architect` | Team pipeline integration |
| `planner` | `planner` | Consensus mode support |
| `test-engineer` | `tdd-guide` | Richer test strategy prompts |
| `build-fixer` | `build-error-resolver` | Model routing awareness |
| `writer` | `doc-updater` | Haiku-optimized for cost |
| `qa-tester` | `e2e-runner` | Interactive CLI/service validation |

### OMC Agent Catalog

**Build/Analysis Lane:**

| Agent | Default Model | Purpose | When to Use | Example Prompt |
|-------|--------------|---------|-------------|----------------|
| `explore` | haiku | Codebase discovery, file/symbol mapping | Starting unfamiliar tasks, broad understanding | `"Map all authentication-related files and their dependencies"` |
| `analyst` | opus | Requirements clarity, acceptance criteria | Ambiguous requirements, hidden constraints | `"Analyze this feature request for missing acceptance criteria"` |
| `planner` | opus | Task sequencing, execution plans, risk flags | Complex features needing phased implementation | `"Create implementation plan for the new billing system"` |
| `architect` | opus | System design, boundaries, interfaces | Structural decisions, API design, data modeling | `"Design the event sourcing architecture for order processing"` |
| `debugger` | sonnet | Root-cause analysis, regression isolation | Bugs, test failures, unexpected behavior | `"Investigate why user session expires after 5 minutes"` |
| `executor` | sonnet | Code implementation, refactoring | Standard feature work, single-module changes | `"Implement the password reset endpoint per the plan"` |
| `deep-executor` | opus | Complex autonomous goal-oriented tasks | Multi-file refactors, cross-cutting changes | `"Refactor the entire auth layer to use JWT with refresh tokens"` |
| `verifier` | sonnet | Completion evidence, claim validation | Checking that work is actually done correctly | `"Verify all endpoints return proper error codes per the spec"` |

**Review Lane:**

| Agent | Default Model | Purpose | Example Prompt |
|-------|--------------|---------|----------------|
| `quality-reviewer` | sonnet | Logic defects, anti-patterns, performance, naming, formatting | `"Review src/api/ for maintainability and performance issues"` |
| `security-reviewer` | sonnet | Vulnerabilities, trust boundaries, authn/authz | `"Security review the new OAuth integration"` |
| `code-reviewer` | opus | Comprehensive cross-concern review, API contracts, versioning | `"Full review of the v2 API changes for backward compat"` |

**Domain Specialists:**

| Agent | Default Model | Purpose | Example Prompt |
|-------|--------------|---------|----------------|
| `test-engineer` | sonnet | Test strategy, coverage, flaky-test hardening | `"Design test strategy for the payment processing module"` |
| `build-fixer` | sonnet | Build/toolchain/type failures | `"Fix the TypeScript compilation errors after the upgrade"` |
| `designer` | sonnet | UX/UI architecture, interaction design | `"Review the onboarding flow for UX issues"` |
| `writer` | haiku | Docs, migration notes, user guidance | `"Write migration guide for the v1 to v2 API change"` |
| `qa-tester` | sonnet | Interactive CLI/service runtime validation | `"Manually test the signup flow in the running service"` |
| `scientist` | sonnet | Data/statistical analysis | `"Analyze the A/B test results for significance"` |
| `document-specialist` | sonnet | External documentation and reference lookup | `"Find the official API docs for Stripe's PaymentIntent"` |

**Coordination:**

| Agent | Default Model | Purpose | Example Prompt |
|-------|--------------|---------|----------------|
| `critic` | opus | Plan/design critical challenge | `"Challenge this architecture for scalability weaknesses"` |

### Executor vs Deep-Executor Decision

| Factor | `executor` (sonnet) | `deep-executor` (opus) |
|--------|---------------------|----------------------|
| Scope | Single module, well-defined task | Cross-cutting, multi-file, autonomous |
| Files touched | 1-5 files | 5-20+ files |
| Ambiguity | Low -- clear spec or plan exists | High -- needs judgment and exploration |
| Duration | Short task, quick turnaround | Extended autonomous work |
| Cost | Lower (sonnet pricing) | Higher (opus pricing) |
| Example | "Add input validation to login endpoint" | "Refactor entire data layer from REST to GraphQL" |

**Rule of thumb:** If you can describe the task in one sentence with a clear deliverable, use `executor`. If the task requires exploration, judgment calls, and touching many files, use `deep-executor`.

### Model Routing Decision Table

| Signal | Model | Rationale |
|--------|-------|-----------|
| File/symbol lookup, quick scan, status check | `haiku` | 3x cheaper, 90% of sonnet capability |
| Standard implementation, debugging, review | `sonnet` | Best coding model, good balance |
| Architecture, deep analysis, complex refactors | `opus` | Deepest reasoning, worth the cost |
| Uncertain complexity | Start `sonnet` | Escalate to `opus` if sonnet struggles |

**Override the default model when warranted:**

```
Task(subagent_type="oh-my-claudecode:explore", model="sonnet",
     prompt="Deep analysis of the module dependency graph")

Task(subagent_type="oh-my-claudecode:verifier", model="haiku",
     prompt="Check that the config file has the new key")
```

### MCP Delegation Mapping

Some agents can be replaced by cheaper/faster MCP calls when they do not need Claude's tool access:

| OMC Agent | MCP Replacement | When to Use MCP | When to Keep Agent |
|-----------|----------------|-----------------|-------------------|
| `architect` | Codex (`agent_role="architect"`) | Read-only architecture review | Needs to create/edit files |
| `planner` | Codex (`agent_role="planner"`) | Plan validation, critique | Needs to write plan files |
| `critic` | Codex (`agent_role="critic"`) | Design challenge | Always suitable for MCP |
| `analyst` | Codex (`agent_role="analyst"`) | Requirements analysis | Needs tool access |
| `code-reviewer` | Codex (`agent_role="code-reviewer"`) | Code review (read-only) | Needs to apply fixes |
| `security-reviewer` | Codex (`agent_role="security-reviewer"`) | Security review | Needs to apply fixes |
| `designer` | Gemini (`agent_role="designer"`) | UI/UX review, visual analysis | Needs to edit code |
| `writer` | Gemini (`agent_role="writer"`) | Prose generation, docs | Needs to write files |
| `document-specialist` | Gemini or Context7 MCP | Documentation lookup | Complex synthesis tasks |

**Agents that always need Claude (tool access required):** `executor`, `deep-executor`, `explore`, `debugger`, `verifier`, `scientist`, `build-fixer`, `qa-tester`, `test-engineer`.

### Team Composition Recipes

**Feature Development:**
```
analyst → planner → executor → test-engineer → quality-reviewer → verifier
```
Standard new feature. Analyst clarifies requirements, planner sequences work, executor implements, test-engineer covers tests, quality-reviewer checks, verifier confirms.

**Bug Investigation:**
```
explore + debugger (parallel) → executor → test-engineer → verifier
```
Explore maps the area while debugger isolates the root cause. Executor fixes, test-engineer adds regression test, verifier confirms.

**Code Review:**
```
quality-reviewer + security-reviewer + code-reviewer (parallel)
```
Three perspectives in parallel. Reconcile findings, address by severity.

**Refactoring:**
```
explore → architect → planner → executor (parallel batches) → quality-reviewer → verifier
```
Understand current state, design target state, plan incremental steps, execute in parallel batches, review quality, verify nothing broke.

**Migration (framework/library upgrade):**
```
document-specialist → analyst → planner → executor → build-fixer → test-engineer → verifier
```
Fetch migration docs first, analyze breaking changes, plan incremental migration, execute, fix build issues, verify tests pass.

**Performance Optimization:**
```
scientist → debugger → architect → executor → verifier
```
Measure baseline (scientist), identify bottlenecks (debugger), design optimization (architect), implement (executor), verify improvement (verifier).

**Security Audit:**
```
security-reviewer → analyst → executor → security-reviewer → verifier
```
Initial scan, analyze findings, fix critical/high issues, re-review, verify fixes.

**Documentation Sprint:**
```
explore → writer (parallel for each area) → quality-reviewer
```
Map what needs documenting, parallelize writing across areas, review for accuracy.

**API Design:**
```
analyst → architect → critic → executor → code-reviewer → verifier
```
Clarify consumers and requirements, design API, challenge the design, implement, review contracts, verify.

**Test Coverage Push:**
```
explore → test-engineer → executor (parallel) → verifier
```
Map untested code, design test strategy, implement tests in parallel, verify coverage target met.

### Agent Interaction Patterns

**Sequential Chain:** Each agent's output feeds the next. Use when each step depends on the previous result.
```
planner output → executor input → verifier input
```

**Parallel Fan-Out:** Independent agents run simultaneously. Use when tasks are independent and you want speed.
```
┌→ quality-reviewer  ─┐
│→ security-reviewer  ─┤→ reconcile
└→ code-reviewer      ─┘
```

**Iterative Loop:** Agent output triggers re-execution. Use for fix-verify cycles.
```
executor → verifier → (fail?) → executor → verifier → (pass?) → done
```

**Staged Pipeline (Team mode):** Formal phase transitions with gates.
```
team-plan → team-prd → team-exec → team-verify → team-fix (loop) → complete
```

## If GSD Is Active

When GSD is already running, agent routing integrates with GSD phases:

| GSD Phase | Recommended Agents |
|-----------|-------------------|
| `plan-phase` | `planner`, `architect`, `analyst` |
| `execute-phase` | `executor`, `deep-executor`, `build-fixer` |
| `verify-phase` | `verifier`, `test-engineer`, `quality-reviewer` |
| `debug` | `debugger` (use `/gsd:debug` which wraps the OMC debugger) |

GSD profiles control Codex reasoning effort for MCP delegation:
- `quality` profile: Codex at `high` effort
- `balanced` profile: Codex at `medium` effort
- `budget` profile: Codex at `low` effort

## Common Mistakes

| Mistake | Why It's Wrong | Correct Approach |
|---------|---------------|-----------------|
| Using ECC `code-reviewer` | Missing OMC team integration | Use OMC `code-reviewer` |
| Spawning `executor` for 20-file refactor | Sonnet may struggle with scope | Use `deep-executor` (opus) |
| Running agents sequentially when independent | Wastes time | Parallel fan-out for independent tasks |
| Using opus for a file lookup | Expensive for simple work | Use `explore` with haiku |
| Skipping `explore` on unfamiliar code | Agents work blind without context | Always explore first in unknown areas |
| Calling MCP for agents that need tool access | MCP models cannot use tools | Keep `executor`, `debugger`, etc. as Claude agents |
| Using `document-specialist` for codebase search | It searches external docs | Use `explore` or native Grep/Glob |
| Spawning `architect` for a config change | Overkill | Just do it directly |

## Quick Reference

```
AGENT SELECTION FLOW:
  Know the answer? → Just do it
  Need to find files/symbols? → explore (haiku)
  Need to understand requirements? → analyst (opus)
  Need implementation plan? → planner (opus)
  Need system design? → architect (opus)
  Need to fix a bug? → debugger (sonnet)
  Need code written (simple)? → executor (sonnet)
  Need code written (complex)? → deep-executor (opus)
  Need work verified? → verifier (sonnet/haiku)
  Need code reviewed? → quality/security/code-reviewer
  Need tests? → test-engineer (sonnet)
  Need build fixed? → build-fixer (sonnet)
  Need external docs? → document-specialist (sonnet)

MODEL OVERRIDE:
  Task(subagent_type="oh-my-claudecode:<agent>", model="<tier>", prompt="...")

MCP SHORTCUT (read-only analysis):
  mcp__x__ask_codex(agent_role="<role>", prompt="...", context_files=[...])
  mcp__g__ask_gemini(agent_role="<role>", prompt="...", files=[...])

LANGUAGE-SPECIFIC (ECC only):
  Python → python-reviewer | Go → go-reviewer / go-build-resolver
  SQL/Postgres → database-reviewer | Dead code → refactor-cleaner
```
