# Git & GitHub

- [When This Applies](#when-this-applies)
- [Core Guidance](#core-guidance)
- [If GSD Is Active](#if-gsd-is-active)
- [Common Mistakes](#common-mistakes)
- [Quick Reference](#quick-reference)

## When This Applies

When performing any git or GitHub operation: committing, branching, creating PRs, managing issues, searching code on GitHub, resolving merge conflicts, or managing releases.

## Core Guidance

### Tool Priority Order

| Priority | Tool | Purpose | When to Use |
|----------|------|---------|-------------|
| 1 | **`gh` CLI** (Bash) | All GitHub operations | Default for issues, PRs, checks, releases, search |
| 2 | **commit-commands skills** | Structured commit/PR workflow | `/commit` for commits, `/commit-push-pr` for full cycle |
| 3 | **OMC `git-master` agent** | Complex git operations | Rebase, history cleanup, conflict resolution |
| 4 | **MCP Docker GitHub** | GitHub API access | Fallback when `gh` CLI is unavailable |

---

### gh CLI Common Operations

#### Issues

```bash
# List issues
gh issue list --state open --label "bug"

# Create issue
gh issue create --title "Title" --body "Description" --label "bug,priority:high"

# View issue details
gh issue view 123

# Close with comment
gh issue close 123 --comment "Fixed in #456"

# Search issues across repos
gh search issues "memory leak" --repo owner/repo --state open
```

#### Pull Requests

```bash
# Create PR (prefer HEREDOC for body)
gh pr create --title "feat: add user auth" --body "$(cat <<'EOF'
## Summary
- Add JWT-based authentication
- Add login/logout endpoints

## Test plan
- [ ] Unit tests for auth service
- [ ] Integration tests for endpoints
- [ ] Manual test login flow
EOF
)"

# List PRs
gh pr list --state open --author "@me"

# View PR details, diff, checks
gh pr view 123
gh pr diff 123
gh pr checks 123

# Review PR
gh pr review 123 --approve
gh pr review 123 --request-changes --body "Needs input validation"

# Merge PR
gh pr merge 123 --squash --delete-branch

# View PR comments
gh api repos/owner/repo/pulls/123/comments
```

#### Code Search

```bash
# Search code across GitHub
gh search code "pattern" --repo owner/repo
gh search code "func handleAuth" --language go

# Search repositories
gh search repos "template react" --sort stars

# Search commits
gh search commits "fix auth" --repo owner/repo
```

#### Releases & Tags

```bash
# List releases
gh release list

# Create release
gh release create v1.2.0 --title "v1.2.0" --notes "Release notes here"

# View release
gh release view v1.2.0

# Download release assets
gh release download v1.2.0
```

#### Checks & Actions

```bash
# View workflow runs
gh run list --workflow build.yml

# View specific run
gh run view 12345

# Watch a running workflow
gh run watch 12345

# Re-run failed jobs
gh run rerun 12345 --failed
```

---

### Commit-Commands Skills

#### `/commit` Workflow

Stages changes with a structured conventional commit message:

1. Runs `git status` to identify changes
2. Runs `git diff` (staged + unstaged) to analyze what changed
3. Reads recent `git log` to match the repository's commit style
4. Drafts a conventional commit message (type + description)
5. Stages relevant files by name (not `git add -A`)
6. Creates the commit via HEREDOC
7. Runs `git status` to verify success

#### `/commit-push-pr` Workflow

Full cycle from local changes to an open PR:

1. Performs the full `/commit` workflow above
2. Creates a new branch if on main/master
3. Pushes with `-u` flag to set upstream tracking
4. Analyzes full commit history on the branch (`git log`, `git diff base...HEAD`)
5. Creates a PR via `gh pr create` with summary and test plan

---

### Conventional Commit Format

```
<type>: <description>

<optional body>
```

| Type | When to Use |
|------|-------------|
| `feat` | New feature (wholly new functionality) |
| `fix` | Bug fix |
| `refactor` | Code restructuring without behavior change |
| `docs` | Documentation only |
| `test` | Adding or updating tests |
| `chore` | Build scripts, config, dependencies |
| `perf` | Performance improvement |
| `ci` | CI/CD configuration changes |

**Guidelines:**
- Use imperative mood: "add auth" not "added auth" or "adds auth"
- Keep the first line under 72 characters
- Use the body for "why", not "what" (the diff shows what)
- Pass messages via HEREDOC to preserve formatting
- Never skip hooks (`--no-verify`) unless explicitly asked

---

### OMC `git-master` Agent

Delegate to `git-master` for complex git operations that benefit from multi-step reasoning.

| Operation | When to Use git-master |
|-----------|----------------------|
| Interactive rebase simulation | Reordering, squashing, or splitting commits across a branch |
| Cherry-pick across branches | Selecting specific commits from one branch to another |
| History cleanup | Removing sensitive data, rewriting author info, cleaning up messy history |
| Conflict resolution strategy | Multi-file conflicts requiring understanding of both sides' intent |
| Branch surgery | Detaching subtrees, grafting branches, orphan branch creation |
| Bisect guidance | Systematic binary search for regression introduction |

**Invocation:** `Task(subagent_type="oh-my-claudecode:git-master", model="sonnet", prompt="...")`

---

### MCP Docker GitHub Tools

Fallback when `gh` CLI is unavailable. Load via `ToolSearch("select:mcp__MCP_DOCKER__create_pull_request")`.

| Tool | Purpose |
|------|---------|
| `create_pull_request` | Create a PR |
| `list_pull_requests` | List PRs with filters |
| `search_pull_requests` | Search PRs by query |
| `pull_request_read` | Read PR details |
| `merge_pull_request` | Merge a PR |
| `update_pull_request` | Update PR title/body/state |
| `update_pull_request_branch` | Update PR branch (merge base) |
| `create_branch` | Create a new branch |
| `list_branches` | List branches |
| `push_files` | Push file changes |
| `create_or_update_file` | Create or update a single file |
| `get_file_contents` | Read file from a repo |
| `search_code` | Search code in repositories |
| `search_repositories` | Search for repositories |
| `list_issues` | List issues |
| `issue_read` | Read issue details |
| `issue_write` | Create/update issues |
| `list_commits` | List commits |
| `get_commit` | Get commit details |
| `list_tags` | List tags |
| `list_releases` | List releases |
| `get_latest_release` | Get the latest release |

---

### Branch Management

**Naming convention:**
```
<type>/<short-description>
```
Examples: `feat/user-auth`, `fix/login-redirect`, `refactor/api-layer`

**Best practices:**
- Always branch from an up-to-date base branch
- Use `-u` flag on first push to set upstream tracking
- Delete branches after merge (`--delete-branch` with `gh pr merge`)
- Never force-push to `main`/`master` -- warn the user if requested

---

### PR Creation Checklist

1. **Analyze all commits** on the branch, not just the latest
2. **Title:** under 70 characters, imperative mood, no type prefix (the PR label handles that)
3. **Body:** use the template structure:

```markdown
## Summary
- [1-3 bullet points describing what changed and why]

## Test plan
- [ ] [Specific test steps]
- [ ] [Edge cases verified]
- [ ] [CI checks passing]
```

4. **Reviewers:** assign if known
5. **Labels:** add appropriate labels (bug, enhancement, etc.)
6. **Draft:** use `--draft` for work-in-progress PRs

---

### Complex Git Operations

#### Rebase Workflow

```bash
# Update feature branch with latest main
git fetch origin
git rebase origin/main

# If conflicts arise:
# 1. Fix conflicts in the files
# 2. git add <resolved-files>
# 3. git rebase --continue
# 4. Repeat until complete

# Abort if rebase goes wrong
git rebase --abort
```

#### Merge Conflict Resolution

1. Identify conflicting files: `git status` (look for "both modified")
2. Read each conflicting file to understand both sides
3. Resolve by choosing the correct combination (not blindly picking one side)
4. Stage resolved files individually: `git add <file>`
5. Complete the merge/rebase: `git merge --continue` or `git rebase --continue`
6. Verify the resolution: build and test

#### Cherry-Pick

```bash
# Pick a specific commit onto current branch
git cherry-pick <commit-sha>

# Pick without committing (stage only)
git cherry-pick --no-commit <commit-sha>

# Pick a range
git cherry-pick <start-sha>..<end-sha>
```

#### Bisect

```bash
# Start bisect
git bisect start
git bisect bad           # current commit is broken
git bisect good <sha>    # this commit was working

# Git checks out a middle commit; test it, then:
git bisect good   # if this commit works
git bisect bad    # if this commit is broken

# Repeat until the culprit is found
git bisect reset  # return to original state
```

## If GSD Is Active

When GSD is managing a project with git operations:

- **Commit timing:** commit at GSD phase boundaries, not mid-phase. Each phase should produce a coherent, buildable commit
- **Branch strategy:** GSD projects typically use a feature branch per task. Create the branch during the planning phase
- **Verification commits:** after GSD verification passes, commit with a message referencing the phase: `feat: implement auth (gsd:execute-phase complete)`
- **PR creation:** create the PR after the final GSD verification phase. Include GSD phase summaries in the PR body
- **GSD config tracking:** `.planning/` directory should be in `.gitignore` -- it's ephemeral project state, not source code

## Common Mistakes

| Mistake | Correction |
|---------|------------|
| Using `git add -A` or `git add .` | Stage specific files by name to avoid committing secrets or binaries |
| Amending after a hook failure | Hook failure means the commit didn't happen. Create a NEW commit, don't `--amend` |
| Force-pushing to main/master | Never do this. Warn the user and suggest alternatives |
| Skipping `--no-verify` casually | Never skip hooks unless the user explicitly requests it |
| Using `-i` flag (interactive rebase, interactive add) | Interactive mode requires TTY input not available in Claude Code. Delegate to `git-master` agent |
| Creating empty commits when there are no changes | Check `git status` first. If nothing changed, don't commit |
| Not reading recent `git log` before committing | Match the repository's existing commit style |
| PR title duplicating the body content | Keep title short (<70 chars). Details go in the body |
| Committing `.env`, credentials, or secrets | Always check file names before staging. Warn user if they request committing sensitive files |
| Using `git checkout` for both branch switching and file restoration | Use `git switch` for branches and `git restore` for files (modern equivalents) |

## Quick Reference

```
Commit workflow:
  git status → git diff → git log (recent) → git add <files> → git commit -m "$(cat <<'EOF' ... EOF)"

PR workflow:
  git status → git diff base...HEAD → git log base..HEAD → git push -u → gh pr create

Conventional types:
  feat | fix | refactor | docs | test | chore | perf | ci

Branch naming:
  feat/description | fix/description | refactor/description

gh essentials:
  gh issue list/create/view/close
  gh pr list/create/view/diff/checks/merge/review
  gh search code/repos/issues/commits
  gh run list/view/watch/rerun
  gh release list/create/view/download

Complex ops (delegate to git-master):
  rebase, cherry-pick, bisect, history rewrite, conflict resolution strategy
```
