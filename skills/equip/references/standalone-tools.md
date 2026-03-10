# Standalone Tools Reference

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When you need to invoke a specific tool that operates independently of multi-agent workflows. Triggers: needing to review code quality after changes, capture context mid-session, manage remote servers, handle PDFs, run browser tests, analyze binary files, or apply structured decision frameworks.

## Core Guidance

### Proactive Tools (Use Without Being Asked)

These tools add value when applied automatically at the right moments. Consider invoking them whenever their trigger conditions are met.

#### `/simplify` -- 3-Agent Parallel Code Review

**What it does:** Spawns three parallel review agents (reuse, quality, efficiency) that analyze recent code changes and auto-fix mechanical issues.

**When to trigger:**
- After writing >100 lines of new code
- After refactoring an existing module
- Before creating a PR (final quality gate)
- After significant feature implementation

**What each agent checks:**

| Agent | Focus | Example Finding |
|-------|-------|-----------------|
| Reuse | Duplicate logic, reinvented utilities | "This date formatting logic duplicates `utils/format.ts:formatDate`" |
| Quality | Naming, readability, anti-patterns, complexity | "Function `process` has cyclomatic complexity 14 -- extract branches" |
| Efficiency | Performance hotspots, unnecessary allocations | "Array is filtered then mapped -- combine into single `reduce`" |

**Auto-fix behavior:** Mechanical issues (imports, naming consistency, simple deduplication) are fixed automatically. Judgment calls (architecture, algorithm choice) are flagged for human review.

**Invocation:**
```
/simplify
```
No arguments needed -- analyzes recent changes in the current working directory.

#### `/note` (OMC) -- Mid-Session Context Capture

**What it does:** Writes a timestamped note to the OMC notepad (`{worktree}/.omc/notepad.md`), which survives compaction.

**When to trigger:**
- After making a design decision ("chose X over Y because Z")
- After discovering a non-obvious fact about the codebase
- Before a long-running operation that might trigger compaction
- When switching context between tasks within a session

**Invocation:**
```
/note "Decided to use event sourcing for billing -- CRUD would require migration of 3 legacy tables"
```

**Notepad sections:**
| Section | Written By | Persistence | Best For |
|---------|-----------|-------------|----------|
| `priority` | `notepad_write_priority` | Loaded at session start (max 500 chars) | Critical context for this session |
| `working` | `notepad_write_working` | Auto-pruned after 7 days | Timestamped decision log |
| `manual` | `notepad_write_manual` | Never auto-pruned | Permanent session notes |

#### `project_memory_read` (OMC) -- Convention Check

**What it does:** Reads project-level persistent memory from `{worktree}/.omc/project-memory.json`.

**When to trigger:** At the start of every session in a previously-worked project.

**Sections:**
| Section | Contains | Example |
|---------|----------|---------|
| `techStack` | Languages, frameworks, versions | `"TypeScript 5.3, Next.js 14, PostgreSQL 15"` |
| `build` | Build commands, CI configuration | `"pnpm build, pnpm test, pnpm lint"` |
| `conventions` | Coding standards, naming rules | `"Use kebab-case for file names, PascalCase for components"` |
| `structure` | Directory layout, module boundaries | `"src/modules/{feature}/ with index.ts barrel exports"` |
| `notes` | Miscellaneous project facts | `"Legacy billing module must not be modified -- frozen for audit"` |
| `directives` | Override instructions | `"Always run type-check before committing"` |

**Invocation:**
```
project_memory_read(section="conventions")
project_memory_read(section="all")
```

#### `/cozempic guard` -- Agent Team State Protection

**What it does:** Protects active agent team state files from being lost during auto-compaction.

**When to trigger:**
- Before starting `TeamCreate` or `/team` workflows
- When running long multi-agent operations
- Any time you have active background agents that must preserve state

**Invocation:**
```
/cozempic guard
```

**Related cozempic commands:**
| Command | Purpose |
|---------|---------|
| `/cozempic` | Diagnose session bloat, show token usage |
| `/cozempic guard` | Protect agent state from compaction |
| `/cozempic treat` | Apply pruning (gentle/standard/aggressive) |

### On-Demand Tools (Invoke When Situation Arises)

#### Hopper MCP + `/hopper-analyze` -- Reverse Engineering

**Trigger situations:** Binary analysis, disassembly review, malware triage, understanding compiled code without source.

**Workflow:**
```
1. /hopper-analyze "path/to/binary"
   --> Opens binary in Hopper, extracts symbols and structure

2. Use Hopper MCP tools to query:
   - Function list and call graph
   - Disassembly for specific functions
   - String references
   - Cross-references
```

#### SSH MCP -- Remote Server Management

**Trigger situations:** Managing remote hosts, deploying, debugging remote issues, port forwarding.

**Discovery:**
```
ToolSearch("select:mcp__ssh__ssh_connect,mcp__ssh__ssh_read_file")
```

**Capabilities:**

| Tool | Purpose | Example |
|------|---------|---------|
| `ssh_connect` | Establish connection | `ssh_connect(host="server", user="deploy")` |
| `ssh_exec` | Run a single command | `ssh_exec(session_id="...", command="systemctl status nginx")` |
| `ssh_exec_batch` | Multiple commands sequentially | Run a deploy script step by step |
| `ssh_exec_parallel` | Commands on multiple hosts | Deploy to all servers simultaneously |
| `ssh_read_file` / `ssh_write_file` | File operations | Read/edit remote config files |
| `ssh_forward_local` | Port forwarding | Access remote database locally |
| `ssh_pty_start` | Interactive PTY | Long-running interactive sessions |
| `ssh_upload` / `ssh_download` | File transfer | Deploy artifacts, fetch logs |

#### MCP Docker -- Multi-Purpose Container & Browser Tool

**Trigger situations:** Docker operations, browser automation, file/archive handling, web research.

**Sub-tool categories:**

| Category | Tools | Example Use |
|----------|-------|-------------|
| Docker | `docker` | Container management, image operations |
| Browser | `browser_navigate`, `browser_click`, `browser_snapshot`, `browser_take_screenshot` | Web scraping, UI testing, form automation |
| File/Archive | `zip_files`, `zip_directory`, `unzip_file` | Package artifacts, extract archives |
| Research | `perplexity_ask`, `perplexity_research`, `web_search_exa` | Deep research, current information |
| Wikipedia | `search_wikipedia`, `get_article`, `get_summary` | Quick factual lookups |
| GitHub | `search_code`, `search_repositories`, `list_pull_requests` | Code search, repo discovery |

#### Slack MCP -- Messaging & Channel Operations

**Trigger situations:** Reading team messages, sending updates, searching conversation history, scheduling messages.

**Discovery:**
```
ToolSearch("select:mcp__claude_ai_Slack__slack_send_message,mcp__claude_ai_Slack__slack_read_channel")
```

**Key tools:**
| Tool | Purpose |
|------|---------|
| `slack_send_message` | Send to channel or DM |
| `slack_read_channel` | Read recent messages from a channel |
| `slack_read_thread` | Read a specific thread |
| `slack_search_public` | Search public channel history |
| `slack_search_public_and_private` | Search all accessible channels |
| `slack_schedule_message` | Schedule a message for later |

#### CodeGraph MCP -- Neo4j Code Graph Analysis

**Trigger situations:** Understanding cross-file relationships, finding dead code, measuring complexity, running custom graph queries.

**Workflow:**
```
1. INDEX: Add code to the graph
   add_code_to_graph(repository_path="/project", language="typescript")
   --> Parses AST, extracts symbols, builds relationship graph

2. ANALYZE: Query the graph
   analyze_code_relationships(repository_path="/project",
     source_symbol="UserService", relationship_type="CALLS")
   --> Returns all symbols called by UserService

3. FIND DEAD CODE:
   find_dead_code(repository_path="/project")
   --> Returns symbols with no incoming references

4. COMPLEXITY:
   find_most_complex_functions(repository_path="/project", limit=10)
   --> Top 10 functions by cyclomatic complexity

5. CUSTOM QUERIES:
   execute_cypher_query(query="MATCH (f:Function)-[:CALLS]->(g:Function)
     WHERE g.name = 'authenticate' RETURN f.name, f.file")
   --> Custom Neo4j Cypher for any relationship query
```

**Maintenance:**
| Tool | Purpose |
|------|---------|
| `watch_directory` | Auto-reindex on file changes |
| `get_repository_stats` | Node/relationship counts, coverage |
| `delete_repository` | Remove a project from the graph |

#### `/loop` -- Recurring Interval Commands

**Trigger situations:** Periodic monitoring, babysitting CI/CD, repeated checks.

**Invocation:**
```
/loop 5m /babysit-prs          # Check PR status every 5 minutes
/loop 30s "git status"         # Watch for file changes
/loop 1h "/cozempic"           # Hourly context health check
```

#### `/pdf` -- PDF Handling

**Trigger situations:** Reading, extracting, or processing PDF documents.

#### `/webapp-testing` -- Playwright Web Testing

**Trigger situations:** E2E testing of web apps, visual regression testing, automated user flow validation.

#### `/claw` (ECC) -- Persistent REPL Sessions

**Trigger situations:** Iterative data analysis, exploratory coding, prototyping. Persistent state across commands (unlike Bash tool calls). History at `~/.claude/claw/`.

#### `/model-matchmaker:effort-config` -- Effort Routing Profiles

**Trigger situations:** Configuring how task complexity maps to model selection and reasoning effort.

#### `/keybindings-help` -- Keyboard Shortcut Reference

**Trigger situations:** Customizing or learning Claude Code keyboard shortcuts.

#### OMC `/project-session-manager` -- Git Worktree + Tmux

**Trigger situations:** Working on multiple branches simultaneously. Manages git worktrees paired with tmux sessions for isolated environments.

#### OMC `/ccg` -- Tri-Model Orchestration

**Trigger situations:** Tasks benefiting from multi-model consensus (Claude + Codex + Gemini).

**What it does:** Dispatches the same analysis task to all three models in parallel, then reconciles their outputs.

**How it differs from manual delegation:**
- Handles discovery, prompt adaptation, and result formatting automatically
- Reconciliation logic: all agree (proceed), overlap (merge), disagreement (present to user)
- Useful for architecture reviews, security audits, and design decisions where diverse perspectives add value

### Reference Patterns (Knowledge Libraries)

These are not tools to invoke directly -- they are knowledge skills loaded when their domain is relevant. They provide patterns, best practices, and decision frameworks.

#### ECC Autonomous Loop Patterns (`/continuous-agent-loop`)

**When to reference:** Building or configuring autonomous agent loops.

**Pattern catalog:**
| Pattern | Description | Use Case |
|---------|-------------|----------|
| Sequential | Single agent, linear task list | Simple automation |
| NanoClaw | Minimal REPL-based loop | Prototyping, exploration |
| Infinite | Unbounded with health checks | Monitoring, continuous processing |
| Continuous-PR | Loop tied to PR lifecycle | Automated PR creation and updates |
| De-sloppify | Quality improvement loop | Iterative code cleanup |
| RFC-DAG | Directed acyclic graph of tasks | Dependency-aware task scheduling |

#### ECC `/verification-loop` -- 6-Phase Verification Gate

**When to reference:** Setting up comprehensive verification before merge or release.

**Phases:**
```
1. Build        --> Compiles successfully?
2. Type check   --> No type errors?
3. Lint          --> Passes lint rules?
4. Test          --> All tests pass?
5. Security      --> No vulnerability findings?
6. Diff review   --> Changes match intent?
```

#### ECC `/eval-harness` -- Eval-Driven Development

**When to reference:** Building capability evals, measuring agent performance, tracking regression.

**Concepts:**
- Capability evals: does the system do X correctly?
- Regression evals: did changes break existing capabilities?
- Pass@k metrics: probability of success in k attempts

#### ECC Knowledge Skills (Language/Framework Patterns)

**When to reference:** Working in a specific language or framework and needing idiomatic patterns.

**Available domains:** `swift-concurrency-6-2`, `swiftui-patterns`, `foundation-models-on-device`, `liquid-glass-design`, `python-patterns`, `golang-patterns`, and more.

**Invocation:** These are loaded by keyword detection when working in the relevant domain. No explicit invocation needed.

#### ECC Workflow Patterns

**Available patterns:**
| Pattern | Domain |
|---------|--------|
| `agent-harness-construction` | Building agent harnesses with proper tool access |
| `cost-aware-llm-pipeline` | Optimizing LLM costs across tiers |
| `content-hash-cache-pattern` | Caching LLM responses by content hash |
| `iterative-retrieval` | 4-phase context retrieval for subagents |
| `strategic-compact` | When and how to compact context deliberately |

#### Taches Decision Frameworks (`consider:*`)

**When to reference:** Facing a specific decision that warrants structured thinking.

| Framework | Invocation | Best For |
|-----------|-----------|----------|
| First Principles | `/consider:first-principles` | Breaking assumptions, novel solutions |
| 5 Whys | `/consider:5-whys` | Root cause analysis |
| SWOT | `/consider:swot` | Evaluating options with trade-offs |
| Pareto (80/20) | `/consider:pareto` | Identifying high-impact actions |
| Inversion | `/consider:inversion` | Avoiding failure modes |
| Via Negativa | `/consider:via-negativa` | Simplifying by subtraction |
| Opportunity Cost | `/consider:opportunity-cost` | Choosing between mutually exclusive paths |
| Eisenhower Matrix | `/consider:eisenhower-matrix` | Prioritizing by urgency vs importance |
| Second-Order | `/consider:second-order` | Anticipating downstream consequences |
| 10-10-10 | `/consider:10-10-10` | Time-horizon perspective |
| Occam's Razor | `/consider:occams-razor` | Simplest sufficient explanation |
| The One Thing | `/consider:one-thing` | Single highest-leverage action |

**When to use:** Not routinely -- only for genuine decisions with meaningful trade-offs.

## If GSD Is Active

When GSD is already running, standalone tools integrate at specific phases:

| GSD Phase | Relevant Tools |
|-----------|---------------|
| `plan-phase` | `project_memory_read` (check conventions), `/note` (capture planning decisions), `consider:*` (for architectural trade-offs) |
| `execute-phase` | `/simplify` (after each implementation batch), `/note` (capture implementation decisions) |
| `verify-phase` | `/simplify` (final quality check), CodeGraph `find_dead_code` (verify no dead code introduced) |
| `debug` | `/cozempic` (check context health), SSH MCP (if debugging remote issues) |

GSD's verification steps pair naturally with `/simplify` -- run it as part of the verification checklist. The `/cozempic guard` is especially important during GSD phases with parallel agents.

## Common Mistakes

| Mistake | Why It's Wrong | Correct Approach |
|---------|---------------|-----------------|
| Never running `/simplify` after large changes | Quality issues compound and get harder to fix later | Run after >100 lines changed or before PR |
| Using `/note` only at end of session | Context already lost to compaction | Write notes as decisions happen |
| Skipping `project_memory_read` in familiar projects | Conventions may have changed since last session | Always check at session start |
| Using CodeGraph without indexing first | Queries return empty results | Run `add_code_to_graph` before querying |
| Using `consider:*` on every small decision | Wastes time on trivial choices | Reserve for decisions with real trade-offs |
| Running `/ccg` for simple tasks | Tri-model overhead not justified | Use single model for straightforward work |
| Forgetting `/cozempic guard` before team workflows | Agent state lost on compaction | Always guard before `TeamCreate` |
| Using SSH MCP for local operations | Unnecessary overhead | Use Bash tool directly for local commands |
| Polling with `/loop` at very short intervals | Wastes resources | Use 5m+ intervals for most monitoring tasks |

## Quick Reference

```
PROACTIVE (auto-trigger):
  /simplify                     After >100 lines changed, before PR
  /note "message"               When making decisions, before compaction risk
  project_memory_read("all")    Start of every project session
  /cozempic guard               Before TeamCreate or /team workflows

ON-DEMAND:
  Hopper: /hopper-analyze "binary"           Reverse engineering
  SSH:    ssh_connect --> ssh_read_file       Remote server ops
  Docker: browser_*, docker, zip_*, ...      Containers, browser, archives
  Slack:  slack_send_message, slack_read_*    Team messaging
  Graph:  add_code_to_graph --> analyze/find  Code relationship analysis
  /loop 5m "command"                         Recurring monitoring
  /pdf                                       PDF processing
  /webapp-testing                            Playwright E2E tests
  /claw                                      Persistent REPL sessions
  /ccg                                       Tri-model consensus
  /project-session-manager                   Worktree + tmux management

REFERENCE PATTERNS (loaded by domain, not invoked):
  /continuous-agent-loop         Autonomous loop architectures
  /verification-loop             6-phase gate (build->type->lint->test->sec->diff)
  /eval-harness                  Eval-driven development
  ECC knowledge skills           Language/framework pattern libraries
  consider:*                     Decision frameworks (12 available)

CODEGRAPH WORKFLOW:
  add_code_to_graph --> analyze_code_relationships / find_dead_code
                    --> find_most_complex_functions / execute_cypher_query
```
