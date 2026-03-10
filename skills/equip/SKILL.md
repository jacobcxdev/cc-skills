---
name: equip
description: >
  Use at the start of every session or when switching task domains to load
  context-aware tool routing guidance. Detects project environment, infers
  task intent from evidence (branch names, dirty files, recent commits),
  and loads only the reference files relevant to your current work.
  Progressive disclosure: deep guidance loaded on demand, not always-on.
---

# Equip — Context-Aware Tool Routing

Load the right guidance for the right work. Detect → Infer → Load → Go.

## Protocol

### Step 1: Collect environment signals

Run the detection script to capture raw project signals:

```zsh
zsh ${CLAUDE_SKILL_DIR}/scripts/detect-context.zsh
```

Save the JSON output mentally. Present the `observations` array to the user as a brief environment summary.

### Step 2: Check for prior equip state

If `detect-context.zsh` reports `"equip_prior": true`, read the prior state:

```
Read .omc/state/equip-session.json
```

### Step 3: Compute routing signals

Run the plan script to get hash and branch classification:

```zsh
zsh ${CLAUDE_SKILL_DIR}/scripts/plan-equip.zsh /dev/stdin [prior-state-path]
```

Pipe the detect output as stdin. Pass the prior state file path as the second argument if it exists.

### Step 4: Determine action type

Using the detect output, plan output, and your own interpretation of the signals, determine the action type. **You are the brain here** — the scripts collect facts; you interpret them.

#### Action types

| Action | When | What to do |
|--------|------|------------|
| `resume_keep` | Prior state exists AND `hash_changed` is false | Tell user: "Still equipped for [prior summary]. Keep / Switch / Add?" |
| `auto_equip` | You are confident (>=85%) about the task intent with clear gap to alternatives | Announce what you detected with evidence. Load packs immediately. |
| `ask` | Intent is ambiguous — two plausible tasks, or signals are mixed | Ask ONE disambiguating question with evidence-backed options. |
| `re_equip` | Prior state exists AND base packs match but task intent changed | Announce: "Switching from [old] to [new]. Base unchanged." Swap task pack. |
| `drill_down` | After initial equip, you notice a relevant situation pack | Offer: "Also detected [situation]. Load [pack] guidance?" |
| `noop` | No useful signals (empty dir, no git, no project files) | Ask: "What are you working on?" with task options. |

#### Intent scoring heuristics

Use these as starting weights. Combine with your own judgement from the full context.

| Signal | Suggests | Weight |
|--------|----------|--------|
| Branch prefix `fix/`, `bug/`, `hotfix/` | debug | +0.30 |
| Branch prefix `feat/`, `feature/`, `add/` | feature | +0.30 |
| Branch prefix `refactor/`, `cleanup/` | refactor | +0.25 |
| Branch prefix `release/`, tag push | release | +0.20 |
| Test artifacts (`.xcresult`, `test-results/`) | debug or verify | +0.20 |
| Dirty files in test directories | verify | +0.15 |
| Recent commits contain "fix", "bug" | debug | +0.15 |
| Recent commits contain "feat", "add" | feature | +0.10 |
| Branch prefix `test/`, `tests/` | verify | +0.25 |
| Branch prefix `docs/`, `doc/` | feature (docs) | +0.20 |
| Branch prefix `chore/`, `ci/`, `style/` | refactor | +0.15 |
| Clean tree, no recent commits | explore | +0.20 |
| PR template files, review branch | review | +0.15 |
| Merge/rebase in progress | git-risk (situation) | always add |
| Large diff or ahead of remote | git-risk (situation) | always add |
| `.planning/config.json` exists | GSD active | use GSD subsections in loaded refs |

**Important:** GSD is user-initiated only. Never suggest starting GSD. Only activate GSD-specific subsections when `.planning/config.json` already exists.

### Step 5: Select packs

Based on your action type and intent scoring, select packs from three layers:

#### Base packs (stable platform context)

| Pack | Trigger | Reference files |
|------|---------|-----------------|
| `swift-ios` | `.xcodeproj`/`.xcworkspace` or Swift files with Apple targets | `ios-development.md`, `code-search.md` |
| `javascript-ts` | `package.json`, `tsconfig.json`, `.ts`/`.js` files | `code-search.md` |
| `python` | `pyproject.toml`, `setup.py`, `requirements.txt`, `.py` files | `code-search.md` |
| `go` | `go.mod`, `.go` files | `code-search.md` |
| `rust` | `Cargo.toml`, `.rs` files | `code-search.md` |
| `monorepo` | Multiple `package.json` or `go.mod` at different depths | `context-management.md` |
| `gsd` | `.planning/config.json` exists | `planning.md` (with GSD subsections) |

#### Task packs (current work mode)

| Pack | Reference files |
|------|-----------------|
| `explore` | `code-search.md`, `context-history.md` |
| `feature` | `planning.md`, `research.md`, `code-search.md` |
| `debug` | `debugging.md`, `code-search.md`, `context-history.md` |
| `review` | `verification.md`, `agent-routing.md`, `multi-model.md` |
| `verify` | `verification.md`, `multi-model.md` |
| `refactor` | `code-search.md`, `agent-routing.md` |

#### Situation packs (transient — additive)

| Pack | Trigger | Reference files added |
|------|---------|----------------------|
| `git-risk` | Ahead of remote, large diff, merge/rebase in progress | `git-github.md` |
| `delegation` | Complex task spanning >3 files or needing multi-model | `multi-model.md`, `agent-routing.md` |
| `release` | Branch matches `release/`, `main`, or tag push context | `verification.md`, `git-github.md` |
| `generated-files` | `.generated`, `*.pb.swift`, `*.graphql.swift` detected | `context-management.md` |
| `session-resume` | Prior equip state exists | `context-history.md` |

### Step 6: Load reference files

Deduplicate the reference file list across all selected packs. Read each file:

```
Read ${CLAUDE_SKILL_DIR}/references/<filename>.md
```

Read all selected reference files in parallel.

**Quota check:** When loaded references include `verification.md` or `multi-model.md`, check provider quota before any MCP delegation:

```bash
${CLAUDE_SKILL_DIR}/scripts/cq.zsh --json
```

Skip providers with `status: "exhausted"`. Requires `jq` and `zsh`.

### Step 7: Present guidance

After reading the reference files, present a concise summary to the user:
- What you detected (environment + intent)
- What guidance you loaded
- Key decision tables or tool priorities relevant to their inferred task
- Any situation-specific warnings (git risk, large diff, etc.)

Keep it brief — the references are now in your context. Don't regurgitate them.

### Step 8: Persist state

Ensure the directory exists (`mkdir -p .omc/state`), then write the equipped state to `.omc/state/equip-session.json`:

```json
{
  "equipped_at": "<ISO timestamp>",
  "detect_hash": "<from plan-equip.zsh output>",
  "base_packs": ["<selected>"],
  "task_pack": "<selected>",
  "situation_packs": ["<selected>"],
  "reference_files_loaded": ["<list>"],
  "pinned_overrides": {},
  "declined_optional": [],
  "recent_choices": [
    { "timestamp": "<ISO>", "task": "<selected>", "confidence": 0.88 }
  ]
}
```

### Step 9: Offer drill-down

Only after initial equip (not on `resume_keep`):
- If optional situation packs have relevance >= 0.65, offer them
- General-purpose references are always available on request (not auto-loaded by any pack):
  `thinking-frameworks.md`, `learning.md`, `meta-skills.md`, `standalone-tools.md`
- "Need more detail on any area? I can load additional guidance for [topics]."

## Re-invocation

When `/equip` is called again mid-session:
1. Run `detect-context.zsh` again (environment may have changed)
2. Run `plan-equip.zsh` with the new detect output AND prior state file
3. If `hash_changed` is false → `resume_keep`
4. If base packs match but task intent changed → `re_equip` (swap task layer only)
5. If base changed → full `auto_equip` or `ask` flow

## Reference file index

All reference files live in `${CLAUDE_SKILL_DIR}/references/`:

| File | Domain |
|------|--------|
| `_index.md` | Master index with pack associations |
| `code-search.md` | Tool hierarchy, decision flow, anti-patterns |
| `context-history.md` | claude-mem, project_memory, notepad, /note |
| `multi-model.md` | Codex/Gemini delegation, quotas, parallel patterns |
| `verification.md` | Triple-spawn, reconciliation, GSD integration |
| `agent-routing.md` | OMC vs ECC dedup, agent catalog, compositions |
| `planning.md` | Native-first planning, escalation paths |
| `debugging.md` | OMC debugger, debug-like-expert, hypothesis testing |
| `research.md` | 6-step cascade, package registries, search-first |
| `ios-development.md` | XcodeBuildMCP, Axiom, PFW, Swift skills, Sosumi |
| `git-github.md` | gh CLI, commit-commands, git-master, MCP Docker |
| `thinking-frameworks.md` | consider:* skills, Reflexion, OMC analyst/critic |
| `context-management.md` | cozempic, strategic-compact, iterative-retrieval |
| `learning.md` | claude-mem capture, ECC instincts, Reflexion memorize |
| `meta-skills.md` | Taches create-*/audit-*, find-skills, management |
| `standalone-tools.md` | Hopper, SSH, Slack, CodeGraph, /simplify, etc. |
