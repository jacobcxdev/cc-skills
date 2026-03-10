# Equip Reference Index

Master index of all reference files with their pack associations.

## Reference Files

| File | Domain | Base Packs | Task Packs | Situation Packs |
|------|--------|-----------|------------|-----------------|
| code-search.md | Tool hierarchy & decision flow | swift-ios, javascript-ts, python, go, rust | explore, feature, debug, refactor | — |
| context-history.md | Memory & history search | — | explore, debug | session-resume |
| multi-model.md | Codex/Gemini delegation | — | review, verify | delegation |
| verification.md | Triple-spawn & reconciliation | — | review, verify | release |
| agent-routing.md | OMC vs ECC agent selection | — | review, refactor | delegation |
| planning.md | Planning approaches & escalation | gsd | feature | — |
| debugging.md | Debug tools & workflows | — | debug | — |
| research.md | Research cascade & package eval | — | feature | — |
| ios-development.md | Apple platform tooling | swift-ios | — | — |
| git-github.md | Git operations & GitHub | — | — | git-risk, release |
| thinking-frameworks.md | Decision models & reflection | — | — | — |
| context-management.md | Session bloat & context budget | monorepo | — | generated-files |
| learning.md | Cross-session learning | — | — | — |
| meta-skills.md | Skill creation & management | — | — | — |
| standalone-tools.md | Individual tool reference | — | — | — |

## Pack → Reference Mapping

### Base Packs
- **swift-ios**: code-search.md, ios-development.md
- **javascript-ts**: code-search.md
- **python**: code-search.md
- **go**: code-search.md
- **rust**: code-search.md
- **monorepo**: context-management.md
- **gsd**: planning.md

### Task Packs
- **explore**: code-search.md, context-history.md
- **feature**: planning.md, research.md, code-search.md
- **debug**: debugging.md, code-search.md, context-history.md
- **review**: verification.md, agent-routing.md, multi-model.md
- **verify**: verification.md, multi-model.md
- **refactor**: code-search.md, agent-routing.md

### Situation Packs
- **git-risk**: git-github.md
- **delegation**: multi-model.md, agent-routing.md
- **release**: verification.md, git-github.md
- **generated-files**: context-management.md
- **session-resume**: context-history.md
