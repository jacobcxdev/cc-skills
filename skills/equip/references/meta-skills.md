# Skill Creation & Management

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When you need to create new slash commands, subagents, hooks, or skills, audit existing ones for quality, discover community skills, or manage the ECC plugin configuration. Triggers: building reusable workflows, extending Claude Code capabilities, improving existing skill quality, or organizing your skill inventory.

## Core Guidance

### Taches `create-*` Catalog

Taches provides scaffolding commands for every extensible surface in Claude Code. Each creates a properly structured file with best-practice defaults.

| Command | Creates | Output Location | When to Use |
|---------|---------|-----------------|-------------|
| `create-slash-command` | New `/command` | `.claude/commands/` | Reusable user-invokable workflows |
| `create-subagent` | Agent definition | `~/.claude/agents/` | Specialized agent with custom system prompt |
| `create-hook` | Hook handler | `.claude/hooks/` or `~/.claude/hooks/` | Pre/PostToolUse or Stop event handlers |
| `create-agent-skill` | SKILL.md-based skill | `skills/` directory | Portable, shareable skill packages |
| `create-mcp-servers` | MCP server scaffold | Project root | New tool providers (stdio or HTTP) |
| `create-plan` | Planning document | `.planning/` or `.claude/plans/` | Structured implementation plans |
| `create-prompt` | Reusable prompt | `.claude/prompts/` | Templated prompts for common tasks |
| `create-meta-prompt` | Prompt generator | `.claude/meta-prompts/` | Prompts that generate other prompts |

#### Slash Commands (`create-slash-command`)

**What it creates:** A markdown file in `.claude/commands/` that defines a user-invokable `/command`.

**Example invocation:**
```
/create-slash-command "deploy-preview"
```

**Generated structure (`.claude/commands/deploy-preview.md`):**
```markdown
---
name: deploy-preview
description: Deploy current branch to preview environment
arguments:
  - name: environment
    description: Target preview environment (staging, dev)
    required: false
    default: staging
---

# Deploy Preview

## Steps
1. Run build validation
2. Push to preview branch
3. Trigger deployment webhook
4. Verify deployment health
```

**When to create a slash command vs a skill:**
- **Slash command:** Simple workflow, project-specific, no complex state management
- **Skill:** Portable across projects, needs SKILL.md metadata, publishable to ecosystem

#### Subagents (`create-subagent`)

**What it creates:** An agent definition file in `~/.claude/agents/` with a system prompt tailored to a specific role.

**Example invocation:**
```
/create-subagent "api-contract-checker"
```

**Generated structure (`~/.claude/agents/api-contract-checker.md`):**
```markdown
---
name: api-contract-checker
description: Validates API endpoint contracts against OpenAPI specs
model: sonnet
---

# API Contract Checker

You are a specialized agent that validates REST API implementations
against their OpenAPI/Swagger specifications.

## Responsibilities
- Compare endpoint signatures with spec definitions
- Validate request/response schemas
- Check error code coverage
- Flag undocumented endpoints

## Process
1. Read the OpenAPI spec file
2. Enumerate all defined endpoints
3. For each endpoint, verify implementation matches spec
4. Report discrepancies with severity levels
```

#### Hooks (`create-hook`)

**What it creates:** A hook configuration in `.claude/hooks/` (project) or `~/.claude/hooks/` (global).

**Hook types:**

| Type | Trigger | Common Uses |
|------|---------|-------------|
| `PreToolUse` | Before any tool call | Validation, parameter modification, logging |
| `PostToolUse` | After any tool call | Auto-formatting, checks, observation capture |
| `Stop` | Session ends | Final verification, cleanup, summary generation |

**Example invocation:**
```
/create-hook "auto-format-on-save" --type PostToolUse --tool Write
```

**Important constraints:**
- Hooks cannot read Claude's responses -- they only see tool inputs/outputs
- Hook input uses snake_case fields: `tool_name`, `tool_input`, `tool_response`
- Kill switches: `DISABLE_OMC` (all hooks), `OMC_SKIP_HOOKS=hook1,hook2` (specific)

#### MCP Servers (`create-mcp-servers`)

**What it creates:** A scaffold for a new MCP (Model Context Protocol) server.

**Example invocation:**
```
/create-mcp-servers "project-metrics" --transport stdio
```

**Generates:**
- Server entry point with tool definitions
- TypeScript/Python handler stubs
- Configuration for `claude mcp add`
- Test harness for tool validation

**Transport options:**
- `stdio` -- standard input/output (local, most common)
- `http` -- HTTP server (remote, multi-client)

#### Other Creators

| Command | Example | Output |
|---------|---------|--------|
| `create-plan` | `/create-plan "auth-migration"` | Structured planning doc with phases, risks, milestones |
| `create-prompt` | `/create-prompt "code-review-checklist"` | Reusable prompt template with variables |
| `create-meta-prompt` | `/create-meta-prompt "generate-agent"` | Prompt that generates agent definitions from requirements |

### Taches Audit & Heal Workflow

Audit commands check existing skills, commands, and subagents against best practices. Heal auto-fixes discovered issues.

**Audit commands:**

| Command | Target | What It Checks |
|---------|--------|----------------|
| `audit-slash-command` | `.claude/commands/*.md` | Frontmatter validity, argument definitions, step clarity |
| `audit-subagent` | `~/.claude/agents/*.md` | System prompt quality, model appropriateness, scope definition |
| `audit-skill` | `skills/*/SKILL.md` | Metadata completeness, example quality, trigger patterns |

**Audit workflow:**
```
1. /audit-skill "my-skill"
   --> Checks: metadata fields, description quality, trigger patterns,
       example coverage, edge case handling, documentation completeness
   --> Output: scored report with PASS/WARN/FAIL per criterion

2. Review findings (focus on FAIL items first)

3. /heal-skill "my-skill"
   --> Auto-fixes: missing metadata fields, malformed frontmatter,
       missing examples, inconsistent naming
   --> Manual fixes flagged: unclear descriptions, logic issues,
       missing edge case handling
```

**Example audit output:**
```
AUDIT: my-skill
  [PASS] Metadata: all required fields present
  [WARN] Triggers: only 1 trigger pattern (recommend 3+)
  [FAIL] Examples: no usage examples provided
  [PASS] Description: clear and specific
  [WARN] Edge cases: no error handling guidance
  Score: 3/5 -- run /heal-skill to fix auto-fixable issues
```

### `/find-skills` -- Ecosystem Discovery

Search the open skill ecosystem for community-created skills.

**Usage:**
```bash
npx skills find "deployment"        # Search by keyword
npx skills find "react testing"     # Multi-keyword search
npx skills add "package-name"       # Install a discovered skill
```

**When to search before building:**
- Before creating any new skill, search the ecosystem first
- Community skills are battle-tested and maintained
- Even if not a perfect fit, they can serve as a starting template

**Evaluation criteria for community skills:**
| Factor | Check |
|--------|-------|
| Maintenance | Last updated within 6 months? |
| Quality | Has examples, tests, documentation? |
| Fit | Solves 80%+ of your need? |
| Adaptation cost | How much modification needed? |

**Decision: create vs find vs adapt:**
```
1. /find-skills "keyword"
   Found a match?
     YES, perfect fit     --> npx skills add "package"
     YES, close fit       --> Install, then modify locally
     NO matches           --> Create new with /create-agent-skill
```

### CLAUDE.md Management

Two tools for maintaining `CLAUDE.md` files (project-level and global instructions):

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `/claude-md-management:revise-claude-md` | Structured revision with section targeting | Adding/updating specific sections, reorganizing |
| `claude-md-improver` | Quality improvement pass | Removing redundancy, improving clarity, tightening prose |

**`revise-claude-md` workflow:**
```
1. /claude-md-management:revise-claude-md
   --> Reads current CLAUDE.md
   --> Prompts for target section and desired change
   --> Applies change while preserving overall structure
   --> Validates no conflicting instructions introduced
```

**When to revise CLAUDE.md:**
- After discovering a new project convention that should persist
- When an instruction is causing repeated wrong behavior
- After adding new tools/MCP servers that need documentation
- When sections have grown stale or contradictory

**Best practices:**
- Keep CLAUDE.md focused on *instructions that override defaults*
- Move reference material to separate files (link from CLAUDE.md)
- Use sections with clear headers for easy targeting
- Test changes by starting a new session and checking behavior

### ECC Skill Management

ECC provides its own skill management tools, complementary to Taches:

| Command | Purpose | When to Use |
|---------|---------|-------------|
| `/skill-create` | Create ECC-formatted skills | When building skills that use ECC patterns (instincts, loops) |
| `/configure-ecc` | Adjust ECC plugin settings | Changing default behaviors, enabling/disabling features |
| `/skill-stocktake` | Full inventory of installed skills | Periodic cleanup, finding duplicates, identifying gaps |

**`/skill-stocktake` output:**
```
SKILL INVENTORY:
  Slash commands:  23 (12 project, 11 global)
  Subagents:       8 (3 project, 5 global)
  Skills:          15 (7 project, 8 global)
  Hooks:           6 (2 project, 4 global)

  Duplicates found: 2
    - /review (project) conflicts with /code-review (global)
    - test-runner (agent) overlaps with qa-tester (OMC)

  Unused (no invocation in 30 days): 4
    - /deploy-canary, /perf-test, db-migrator, cache-inspector
```

**ECC vs Taches for skill creation:**
| Factor | Taches `create-*` | ECC `/skill-create` |
|--------|-------------------|---------------------|
| Best for | General skills, commands, hooks | Skills using ECC patterns |
| Integration | Standalone | Instinct system, learning loops |
| Ecosystem | `npx skills` registry | ECC plugin ecosystem |
| Use when | Building general-purpose tools | Building pattern-aware, evolving skills |

### When to Create vs Find vs Adapt

```
DECISION FLOW:
  1. Do I need this capability?
     Search: /find-skills "keyword"
     Search: Grep in ~/.claude/agents/ and .claude/commands/

  2. Found existing?
     Perfect match     --> Use as-is (npx skills add, or just invoke)
     80%+ match        --> Install/copy, then adapt locally
     <80% match        --> Use as reference, create new

  3. Creating new -- which tool?
     Simple workflow            --> /create-slash-command
     Specialized agent role     --> /create-subagent
     Event-driven automation    --> /create-hook
     Portable, shareable        --> /create-agent-skill
     New tool provider          --> /create-mcp-servers
     ECC pattern integration    --> /skill-create

  4. After creation:
     /audit-skill (or audit-slash-command, audit-subagent)
     Fix issues found
     /heal-skill for auto-fixable problems
```

## If GSD Is Active

When GSD is already running, skill management integrates with GSD phases:

| GSD Phase | Relevant Action |
|-----------|----------------|
| `plan-phase` | Search for existing skills before planning custom implementation |
| `execute-phase` | Use `create-*` to scaffold new skills as part of execution |
| `verify-phase` | Run `audit-*` on newly created skills to validate quality |

GSD projects may include skill creation as a deliverable. When they do, the skill should be audited as part of verification and the audit score included in the verification report.

## Common Mistakes

| Mistake | Why It's Wrong | Correct Approach |
|---------|---------------|-----------------|
| Creating a new skill without searching first | May duplicate existing work | `/find-skills` and Grep existing commands first |
| Building a slash command when a skill is needed | Commands aren't portable or shareable | Use `/create-agent-skill` for reusable, publishable tools |
| Putting tool reference docs in CLAUDE.md | Bloats always-loaded context | Use separate reference files, link from CLAUDE.md |
| Skipping audit after creation | Quality issues go unnoticed | Always run `audit-*` then `heal-skill` |
| Creating hooks without kill switches | No way to disable if they misbehave | Document `OMC_SKIP_HOOKS` for every hook |
| Using ECC `/skill-create` for simple commands | Over-engineered for the task | Use Taches `create-slash-command` for simple workflows |
| Never running `/skill-stocktake` | Duplicates and dead skills accumulate | Run quarterly to clean up inventory |
| Creating subagents that overlap OMC agents | Fragmented agent ecosystem | Check OMC agent catalog first (see agent-routing.md) |

## Quick Reference

```
CREATION TOOLS:
  /create-slash-command "name"     Simple user-invokable workflow
  /create-subagent "name"          Specialized agent with system prompt
  /create-hook "name" --type X     Event-driven automation
  /create-agent-skill "name"       Portable, shareable skill package
  /create-mcp-servers "name"       New MCP tool provider
  /create-plan "name"              Structured planning document
  /create-prompt "name"            Reusable prompt template
  /create-meta-prompt "name"       Prompt that generates prompts

QUALITY TOOLS:
  /audit-slash-command "name"      Check command quality
  /audit-subagent "name"           Check agent definition quality
  /audit-skill "name"              Check skill quality
  /heal-skill "name"               Auto-fix audit findings

DISCOVERY:
  npx skills find "keyword"        Search open ecosystem
  npx skills add "package"         Install community skill
  /skill-stocktake                 Full inventory + duplicates + unused

CLAUDE.MD:
  /claude-md-management:revise-claude-md    Structured revision
  claude-md-improver                        Quality improvement pass

DECISION:
  Need it? --> Search first (/find-skills, Grep existing)
  Found?   --> Use or adapt
  Not found? --> Create (pick lightest tool that fits)
  Created? --> Audit --> Heal --> Ship
```
