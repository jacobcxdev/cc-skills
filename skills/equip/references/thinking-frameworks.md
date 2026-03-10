# Thinking & Decision Frameworks

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When facing a specific decision, trade-off, or need for structured reflection. These are **not default workflow** -- invoke them when a situation warrants deliberate analysis rather than just acting.

Trigger signals:
- "Should I refactor this or leave it?"
- "Which library/approach should we choose?"
- "What are the risks of this design?"
- "Why does this keep breaking?"
- "Is this plan good enough?"
- Competing options with non-obvious trade-offs
- High-stakes decisions with downstream consequences
- Post-implementation evaluation needed

## Core Guidance

### Framework Selection Guide

Start here. Match the decision type to the right framework(s).

| Decision Type | Primary Framework | Secondary Framework | Example |
|--------------|-------------------|---------------------|---------|
| Root cause analysis | `5-whys` | `first-principles` | "Why does the build keep failing?" |
| Architecture choice | `first-principles` | `second-order` | "Monolith or microservices?" |
| Library/tool selection | `swot` | `pareto` | "Which ORM should we use?" |
| Refactor vs. rewrite | `via-negativa` | `opportunity-cost` | "Should I refactor this module?" |
| Priority / what to do next | `eisenhower-matrix` | `one-thing` | "Which of these 5 tasks matters most?" |
| Risk assessment | `inversion` | `second-order` | "What could go wrong with this migration?" |
| Simplification | `occams-razor` | `via-negativa` | "Is this abstraction necessary?" |
| Time-horizon trade-off | `10-10-10` | `opportunity-cost` | "Ship now with tech debt or fix first?" |
| Feature scoping | `pareto` | `via-negativa` | "What's the 20% that delivers 80% of value?" |
| Focus / clarity | `one-thing` | `eisenhower-matrix` | "What single thing would make everything else easier?" |

---

### Taches `consider:*` Skills -- Per-Framework Guide

Each skill is invoked as `/consider:<framework-name>`.

#### `first-principles`

**What it does:** Strips a problem down to fundamental truths, discarding inherited assumptions.

**When to use:**
- You're following a pattern "because that's how it's done" but it feels wrong
- Designing a new system from scratch
- Existing solutions all seem suboptimal

**Process:** Identify assumptions -> challenge each -> rebuild from ground truth.

**Example:** "We need a database" -> Do we? What are the actual data access patterns? Could a file system, in-memory store, or external API suffice?

---

#### `5-whys`

**What it does:** Iterative root cause analysis by asking "why?" repeatedly.

**When to use:**
- A bug keeps recurring after fixes
- A process keeps failing
- A symptom has unclear origins

**Process:** State the problem -> ask "why?" -> answer -> repeat 5 times (or until you hit root cause).

**Example:**
1. Why did the deploy fail? -- The test suite timed out.
2. Why did it time out? -- A new integration test takes 3 minutes.
3. Why does it take 3 minutes? -- It hits a real external API.
4. Why isn't it mocked? -- No mock infrastructure for that service.
5. Why not? -- The service was added without updating the test guidelines.

Root cause: missing process for adding test infrastructure when integrating new services.

---

#### `swot`

**What it does:** Evaluates Strengths, Weaknesses, Opportunities, Threats of an option.

**When to use:**
- Comparing 2-3 concrete options (libraries, architectures, vendors)
- Evaluating a proposed technical decision

**Process:** For each option, enumerate S/W/O/T in a 2x2 grid -> compare grids.

---

#### `pareto`

**What it does:** Identifies the vital few (20%) that produce most results (80%).

**When to use:**
- Feature scoping under time pressure
- Deciding what to test first
- Prioritizing tech debt items

**Process:** List all items -> estimate impact of each -> rank -> draw the 80/20 line.

---

#### `inversion`

**What it does:** Thinks backwards from failure. "How would I guarantee this fails?"

**When to use:**
- Risk assessment before a migration, launch, or major change
- Security threat modeling
- Designing fault-tolerant systems

**Process:** Define success -> invert to "how to ensure failure" -> list failure modes -> prevent each one.

**Example:** "How would I guarantee this API migration fails?" -> Ship without backward compatibility, skip load testing, don't monitor error rates, deploy on Friday at 5pm. -> Now prevent each.

---

#### `via-negativa`

**What it does:** Improves by removing rather than adding.

**When to use:**
- Code feels over-engineered
- Deciding whether to refactor
- Simplifying an architecture
- "Should I add X?" -- first ask "what should I remove?"

**Process:** List everything present -> for each, ask "does removing this make things worse?" -> remove what doesn't.

**Example:** "Should I refactor this module?" -> First: what can I *delete* from it? Remove dead code, unused abstractions, redundant layers. Then evaluate if refactoring the remainder is still needed.

---

#### `opportunity-cost`

**What it does:** Evaluates what you give up by choosing one option.

**When to use:**
- Time allocation decisions ("spend a week refactoring vs. building feature X")
- Resource trade-offs
- "Is this worth doing?"

**Process:** For each option, list what you gain AND what you forfeit -> compare total value.

---

#### `eisenhower-matrix`

**What it does:** Categorizes by urgency and importance into 4 quadrants.

| | Urgent | Not Urgent |
|---|--------|------------|
| **Important** | Do first | Schedule |
| **Not Important** | Delegate | Eliminate |

**When to use:**
- Overwhelmed with tasks
- Sprint planning
- Deciding what to tackle next

---

#### `second-order`

**What it does:** Traces consequences beyond the immediate effect.

**When to use:**
- Architectural decisions with long-term implications
- API design (can't easily change later)
- Introducing new dependencies

**Process:** First-order effect -> "and then what?" -> second-order -> "and then what?" -> third-order.

**Example:** "Add a caching layer" -> faster reads (1st order) -> stale data bugs (2nd order) -> cache invalidation complexity becomes a maintenance burden (3rd order).

---

#### `10-10-10`

**What it does:** Evaluates impact at three time horizons: 10 minutes, 10 months, 10 years.

**When to use:**
- Tempted to take a shortcut
- Deciding between shipping now vs. doing it right
- Emotional or pressure-driven decisions

**Process:** "How will I feel about this decision in 10 minutes? 10 months? 10 years?"

---

#### `occams-razor`

**What it does:** Prefers the simplest explanation or solution that fits the evidence.

**When to use:**
- Debugging (is it really a race condition, or is it a typo?)
- Architecture (do we really need event sourcing, or is CRUD fine?)
- Choosing between complex and simple approaches

---

#### `one-thing`

**What it does:** Forces identification of the single most important action.

**When to use:**
- Analysis paralysis
- Too many priorities
- Need to cut through noise

**Question:** "What's the ONE thing I can do, such that by doing it, everything else becomes easier or unnecessary?"

---

### Reflexion Skills

#### `/reflect`

**What it does:** Self-evaluation after completing significant work. Uses weighted scoring with bias awareness via Chain-of-Verification and Tree-of-Thought.

**When to use:** After completing a feature, fixing a complex bug, finishing a refactor, or any substantial piece of work.

**Process:**
1. Chain-of-Verification: systematically verify each claim about the work
2. Tree-of-Thought: explore alternative approaches that might have been better
3. Weighted scoring across dimensions (correctness, maintainability, performance, etc.)
4. Bias detection: identify where overconfidence, anchoring, or sunk cost may have influenced decisions
5. Output: structured evaluation with actionable insights

---

#### `/critique`

**What it does:** 3-judge multi-agent debate for high-stakes reviews. Each judge evaluates independently, then they cross-review and reach consensus.

**Judges:**
1. **Requirements Validator** -- does the work meet stated requirements and acceptance criteria?
2. **Solution Architect** -- is the design sound, scalable, and maintainable?
3. **Code Quality Reviewer** -- is the implementation clean, tested, and following conventions?

**When to use:**
- Before merging a large or risky PR
- After architecture decisions
- When confidence in the solution is low
- High-stakes reviews where a single perspective is insufficient

**Process:** Each judge produces an independent evaluation -> cross-review phase where judges challenge each other -> consensus report with agreed findings and dissenting opinions.

---

#### `/memorize`

**What it does:** Persists learnings from `/reflect` or `/critique` to claude-mem for future sessions.

**When to use:** After `/reflect` or `/critique` produces insights worth remembering across sessions.

**What to memorize:** patterns that worked, approaches that failed, project-specific conventions discovered, performance characteristics learned.

---

### OMC Analyst vs. Critic Agents

| Agent | Role | When to Use |
|-------|------|-------------|
| `analyst` (opus) | Requirements clarity, acceptance criteria, hidden constraints | "Are the requirements clear enough to start?" "What are we missing?" |
| `critic` (opus) | Plan/design critical challenge | "Is this plan solid?" "What's wrong with this approach?" |

**Key difference:** `analyst` clarifies and expands (additive), `critic` challenges and pokes holes (adversarial).

**Combination pattern:** use `analyst` first to ensure requirements are clear, then `critic` to stress-test the proposed solution against those requirements.

---

### Worked Examples for Common Decision Types

#### "Should I refactor this?"

1. **`via-negativa`**: what can be deleted outright? Remove dead code, unused abstractions first
2. **`opportunity-cost`**: what else could you build with the time the refactor would take?
3. **`10-10-10`**: will this code cause pain in 10 months if left as-is?
4. **Decision:** if via-negativa didn't fix it, opportunity-cost is favorable, and 10-10-10 says it'll hurt -- refactor. Otherwise, leave it.

#### "Which library should I choose?"

1. **`swot`**: evaluate each candidate's strengths/weaknesses/opportunities/threats
2. **`pareto`**: which features do you actually need? (probably 20% of what the library offers)
3. **`second-order`**: what happens when you need to upgrade, or the library is abandoned?
4. **Decision:** pick the option with the best SWOT profile for your actual Pareto-identified needs, with acceptable second-order risks.

#### "Is this architecture over-engineered?"

1. **`occams-razor`**: what's the simplest design that meets current requirements?
2. **`via-negativa`**: which layers/abstractions can be removed without losing functionality?
3. **`inversion`**: "how would I make this system impossible to maintain?" -- if the current design matches, simplify
4. **Decision:** if Occam's razor produces something significantly simpler and via-negativa confirms removals are safe, simplify.

## If GSD Is Active

When GSD is managing a project:

- **Planning phase:** use `first-principles` or `analyst` to validate that the GSD plan addresses the right problem, not just the stated problem
- **Before execute phase:** use `inversion` to identify failure modes before committing to implementation
- **Verification phase:** use `/critique` (3-judge) for high-stakes verification instead of single-verifier checks
- **Phase boundaries:** use `10-10-10` when tempted to skip a GSD phase ("it's fine, ship it")
- **GSD profile interaction:** `quality` profile warrants more framework usage; `budget` profile should limit to one framework per decision point

## Common Mistakes

| Mistake | Correction |
|---------|------------|
| Using frameworks for every small decision | Reserve for non-obvious trade-offs. Trivial decisions don't need structured analysis |
| Running `/critique` on low-stakes changes | `/critique` spawns 3 agents -- use only for high-stakes reviews. Use `/reflect` for standard self-evaluation |
| Using `5-whys` for forward-looking decisions | `5-whys` is for root cause analysis (backward-looking). Use `inversion` or `second-order` for forward-looking |
| Applying only one framework when two are complementary | See the worked examples above -- many decisions benefit from a primary + secondary framework |
| Skipping `/memorize` after valuable `/reflect` output | Insights are lost across sessions. Always memorize actionable learnings |
| Using `analyst` when you need `critic` | `analyst` clarifies requirements; `critic` challenges solutions. Don't ask `analyst` to poke holes |
| Framework analysis paralysis | Pick one framework, timebox to 5 minutes. If still unclear, pick a second. Don't use more than 3 |

## Quick Reference

```
Root cause:          /consider:5-whys
Architecture:        /consider:first-principles + /consider:second-order
Library choice:      /consider:swot + /consider:pareto
Simplify:            /consider:via-negativa + /consider:occams-razor
Risk assessment:     /consider:inversion + /consider:second-order
Prioritize:          /consider:eisenhower-matrix or /consider:one-thing
Time trade-off:      /consider:10-10-10 + /consider:opportunity-cost
Refactor decision:   /consider:via-negativa + /consider:opportunity-cost

Post-work:           /reflect → /memorize
High-stakes review:  /critique (3-judge debate)
Requirements check:  analyst agent
Plan challenge:      critic agent

Selection heuristic:
  Looking backward (why did X happen)?  → 5-whys, first-principles
  Looking forward (what should I do)?   → inversion, second-order, swot
  Choosing between options?             → swot, pareto, opportunity-cost
  Simplifying?                          → via-negativa, occams-razor
  Prioritizing?                         → eisenhower-matrix, one-thing, pareto
  Time pressure?                        → 10-10-10, opportunity-cost
```
