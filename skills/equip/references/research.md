# Research Before Coding

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

Before implementing any new functionality, integrating a library, adopting a pattern, or making an architectural decision. The goal is to find proven solutions before writing new code.

## Core Guidance

### The Research Cascade

Follow this cascade in order. Stop when you find a satisfactory answer. Each level is more expensive in time and tokens than the previous.

#### Level 1: Check Existing Codebase

**Tools:** Grep, Glob, Read

Search your own project first. The pattern you need may already exist.

```
# Find similar patterns by name
Glob: "**/*auth*" or "**/*cache*"

# Find similar implementations by content
Grep: "validateToken" or "class.*Repository"

# Find usage patterns of a library already in the project
Grep: "import.*from 'stripe'" --type=ts
```

**What to look for:**
- Existing utilities that do what you need
- Established patterns to follow for consistency
- Prior implementations that can be extended rather than duplicated

**Decision:** If you find an existing pattern, follow it. Do not introduce a competing pattern without explicit justification.

#### Level 2: Search Memory

**Tools:** claude-mem 3-layer workflow

Search for prior decisions, implementations, or fixes related to your task.

```
# Step 1: Search for relevant observations
search("stripe payment integration")
search("cache invalidation pattern")

# Step 2: Timeline around interesting hits
timeline(anchor=<ID from search>)

# Step 3: Full details for relevant IDs only
get_observations([<relevant IDs>])
```

**What to look for:**
- Past decisions about this exact topic ("we chose X because Y")
- Prior implementations that were completed or abandoned
- Known issues or gotchas documented from past work
- Architectural decisions that constrain current choices

**Decision:** If memory contains a documented decision, follow it unless the user explicitly wants to revisit it.

#### Level 3: Check Package Registries

**Tools:** WebSearch, Bash (npm/pip/cargo search)

Search for battle-tested libraries before writing utility code.

```
# npm
npm search <keyword> --json | head -20
npx npm-check-updates  # check for existing dep updates

# PyPI
pip index versions <package>
pip search <keyword>  # (if available)

# crates.io
cargo search <keyword>

# Or use web search for broader discovery
WebSearch: "best node.js rate limiting library 2025"
```

**Package Evaluation Criteria:**

| Criterion | Good Signal | Red Flag |
|-----------|------------|----------|
| Maintenance | Commits in last 3 months | No commits in 12+ months |
| Downloads | >10k weekly (npm), >1k monthly (PyPI) | <100 weekly |
| Dependencies | Few, well-known deps | Many transitive deps, unknown authors |
| Security | No known CVEs, security policy exists | Open CVEs, no security contact |
| API stability | Semantic versioning, changelog | Frequent breaking changes |
| Bundle size | Reasonable for functionality | Disproportionately large |
| TypeScript | Types included or @types available | No types, outdated DefinitelyTyped |
| License | MIT, Apache 2.0, BSD | GPL (if your project is proprietary), SSPL |

**Decision matrix:**

| Scenario | Action |
|----------|--------|
| Well-maintained, popular, fits need | Adopt it |
| Maintained but heavy for your need | Consider lighter alternative or copy the specific function (with attribution) |
| Unmaintained but perfect fit | Fork it, or find maintained alternative |
| Nothing fits | Write it yourself (proceed to implementation) |

#### Level 4: GitHub Search

**Tools:** Bash (`gh search code`, `gh search repos`)

Search GitHub for existing implementations, templates, and reference code.

**Syntax guide:**

```bash
# Search code by content + language
gh search code "validateJWT" --language=typescript --match=file
gh search code "rate limit middleware" --language=python

# Search repositories by topic
gh search repos "stripe webhook handler" --sort=stars --limit=10
gh search repos "nextjs authentication" --sort=stars --language=typescript

# Search for specific file patterns
gh search code "filename:docker-compose" "postgres redis"

# Search within a specific org/user
gh search code "cache invalidation" --owner=vercel

# Search by file path
gh search code "middleware" --filename=rate-limit

# Combine filters
gh search repos "oauth2 server" --language=go --sort=stars --limit=5
```

**What to look for:**
- Reference implementations with >100 stars
- Skeleton/template projects that match your stack
- How popular projects solve the same problem
- Test patterns for the functionality you are building

**Decision:** If you find a well-starred implementation, study its approach. Adopt patterns, not code (unless the license permits direct use).

#### Level 5: Check MCP/Skills

**Tools:** Check available-deferred-tools list, ToolSearch, skill list

Before building functionality, check if an MCP server or skill already provides it.

**Workflow:**

```
# 1. Check the available-deferred-tools list in the conversation
#    Look for MCP servers that match your need
#    Example: need Slack integration? → mcp__claude_ai_Slack__*

# 2. Search for MCP tools by capability
ToolSearch("slack message")
ToolSearch("docker container")
ToolSearch("browser automation")

# 3. Check the skill list for relevant skills
#    Example: need PDF handling? → /pdf skill
#    Example: need web testing? → /webapp-testing skill

# 4. Discover community skills
/find-skills  # searches npx skills registry
```

**Decision:** If an MCP server or skill exists, use it rather than building from scratch. MCP tools are maintained externally and handle edge cases you would otherwise have to discover.

#### Level 6: Broader Research

**Tools:** Taches `research:*` skills, Perplexity MCP, Exa MCP, WebSearch, Context7 MCP, OMC `document-specialist`

When codebase tools and package registries are not enough.

**Taches Research Skills Catalog:**

| Skill | When to Use | Output |
|-------|------------|--------|
| `research:deep-dive` | Thorough single-topic investigation | Comprehensive report with sources |
| `research:landscape` | Broad ecosystem survey (what exists?) | Overview of options with comparisons |
| `research:feasibility` | "Can we do X?" viability assessment | Go/no-go recommendation with risks |
| `research:technical` | Implementation-focused research | Technical approach with code examples |
| `research:options` | Comparing 2-5 specific alternatives | Comparison matrix with recommendation |
| `research:competitive` | Market/competitive analysis | Feature comparison, positioning |
| `research:open-source` | Library/framework evaluation | Detailed evaluation against criteria |
| `research:history` | Understanding evolution/context | Timeline, decisions, rationale |

**Example usage:**

```
# "What rate limiting libraries exist for Node.js?"
→ research:landscape

# "Can we run ML inference on-device with Core ML?"
→ research:feasibility

# "Redis vs Memcached vs DragonflyDB for our session cache"
→ research:options

# "How does Stripe handle webhook retry logic?"
→ research:technical

# "Evaluate Prisma vs Drizzle vs TypeORM for our stack"
→ research:open-source
```

**Research Tool Selection Guide:**

| Need | Best Tool | Why |
|------|----------|-----|
| Quick factual answer | WebSearch | Fastest, cheapest |
| Current events / recent releases | Perplexity MCP (`perplexity_ask`) | Real-time web access, cited sources |
| Deep research with reasoning | Perplexity MCP (`perplexity_research`) | Multi-step research with synthesis |
| Code examples from the web | Exa MCP (`web_search_exa`) | Code-focused search, returns snippets |
| Official library documentation | Context7 MCP | Authoritative, versioned docs |
| Apple platform documentation | Sosumi MCP / Axiom skills | Apple-specific, includes WWDC transcripts |
| Broad research orchestration | Taches `research:*` skills | Multi-agent, structured output |
| External docs + synthesis | OMC `document-specialist` | Agent with tool access for complex lookups |

**Context7 MCP Workflow (library docs):**

```
# Step 1: Resolve the library ID
resolve-library-id("prisma")
→ Returns: "/prisma/prisma" (or similar identifier)

# Step 2: Query the docs
get-library-docs(library_id="/prisma/prisma", topic="migrations")
→ Returns: official documentation on the topic
```

**Use Context7 before guessing API contracts.** It provides authoritative, versioned documentation that prevents incorrect field names, wrong method signatures, and outdated patterns.

**Perplexity MCP Selection:**

| Tool | Use When |
|------|----------|
| `perplexity_ask` | Quick factual question, need a concise answer |
| `perplexity_reason` | Need step-by-step reasoning about a topic |
| `perplexity_research` | Deep multi-step research with comprehensive output |

### Capturing Research Findings

Use `/note` immediately to capture findings as you research. Do not wait until the end.

```
/note "Evaluated rate limiters: rate-limiter-flexible (best fit, 2k stars,
       active maintenance, supports Redis/Mongo/Postgres backends).
       Alternative: express-rate-limit (simpler but memory-only)."
```

**Why capture immediately:**
- Long research sessions risk compaction, losing earlier findings
- Captured notes survive compaction and are available to subagents
- Prevents re-researching the same topic

### The ECC Search-First Skill

ECC provides a `/search-first` skill as an alternative orchestrator for the research cascade. It automates the cascade:

1. Searches codebase for existing patterns
2. Checks memory for prior decisions
3. Searches GitHub for reference implementations
4. Reports findings with a recommendation

Use when you want the cascade automated rather than running each step manually.

## If GSD Is Active

When GSD is already running, research integrates with GSD phases:

- Research should happen during `/gsd:plan-phase`, not during execution
- Research findings should be captured in GSD planning artifacts
- The GSD profile affects research depth:
  - `quality`: Full cascade, all 6 levels
  - `balanced`: Levels 1-4, broader research only if needed
  - `budget`: Levels 1-3 only, skip broader research for well-known patterns

## Common Mistakes

| Mistake | Why It's Wrong | Correct Approach |
|---------|---------------|-----------------|
| Implementing without searching | May duplicate existing code or reinvent a wheel | Always run levels 1-3 minimum |
| Installing a package for 10 lines of logic | Unnecessary dependency weight and supply chain risk | Write it yourself for trivial utilities |
| Choosing a package by GitHub stars alone | Stars lag; maintenance and security matter more | Evaluate with the full criteria table |
| Using `grep` in Bash instead of Grep tool | Worse output handling, missing context | Use the dedicated Grep tool |
| Searching memory with vague terms | Returns too many irrelevant results | Use specific terms: filenames, symbols, error text |
| Fetching all claude-mem observations at once | Token waste, slow | Use 3-layer workflow: search then timeline then get_observations |
| Skipping Context7 for library APIs | Guessing field names leads to bugs | Always check docs for unfamiliar APIs |
| Using WebSearch for library docs | Returns blog posts, not authoritative docs | Use Context7 MCP or Sosumi (Apple) |
| Deep research for a well-known pattern | Over-engineering the research phase | If you know the answer, just implement it |
| Not capturing findings mid-research | Lost to compaction in long sessions | Use `/note` immediately when you learn something |
| Researching during execution phase | Should be done during planning | Complete research before starting implementation |

## Quick Reference

```
RESEARCH CASCADE (follow in order, stop when satisfied):
  1. CODEBASE:  Grep/Glob for existing patterns
  2. MEMORY:    claude-mem search → timeline → get_observations
  3. PACKAGES:  npm/pip/cargo search + evaluation criteria
  4. GITHUB:    gh search code/repos + reference implementations
  5. MCP/SKILLS: available-deferred-tools + ToolSearch + /find-skills
  6. BROADER:   research:* skills, Perplexity, Exa, Context7, document-specialist

PACKAGE EVALUATION (must-check):
  ✓ Maintained (commits < 3 months)
  ✓ Popular (>10k weekly downloads)
  ✓ Few dependencies
  ✓ No known CVEs
  ✓ Semver + changelog
  ✓ TypeScript support
  ✓ Compatible license

GITHUB SEARCH SYNTAX:
  gh search code "pattern" --language=<lang> --match=file
  gh search repos "topic" --sort=stars --limit=10
  gh search code "pattern" --owner=<org> --filename=<name>

RESEARCH TOOL SELECTION:
  Quick fact          → WebSearch
  Current info        → Perplexity (perplexity_ask)
  Deep research       → Perplexity (perplexity_research)
  Code examples       → Exa MCP (web_search_exa)
  Library docs        → Context7 (resolve-library-id → get-library-docs)
  Apple docs          → Sosumi MCP / Axiom skills
  Ecosystem survey    → research:landscape
  Viability check     → research:feasibility
  Compare options     → research:options
  Library evaluation  → research:open-source

ALWAYS CAPTURE FINDINGS:
  /note "key finding here"
```
