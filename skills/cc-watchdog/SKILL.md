---
name: cc-watchdog
description: "Manage cc-watchdog state files that prevent premature Stop events in Claude Code. Use when the user says '/cc-watchdog', 'cc-watchdog', 'start the watchdog', 'stop the watchdog', 'list watchdogs', or asks to keep a session from auto-stopping. Subcommands: start/stop/status/list."
argument-hint: "start|stop|status|list [name] [message]"
allowed-tools:
  - Bash
---

<process>

Invoke the `cc-watchdog` CLI at `${CLAUDE_SKILL_DIR}/scripts/cc-watchdog`. It writes/reads JSON under `${XDG_STATE_HOME:-$HOME/.local/state}/cc-watchdog/` that the Stop hook in `persistent-mode.mjs` reads.

**Parse `$ARGUMENTS` into subcommand + optional name + optional message:**

- First token is the subcommand: `start`, `stop`, `status`, or `list`. Required.
- `start` takes optional `[name]` and optional `[message]` (continuation string injected at Stop). **Default name: `$ZELLIJ_SESSION_NAME` if set, otherwise `"default"`.**
- `stop` takes optional `[name]`. **If name is omitted, it clears every watchdog whose `project_path` matches the current git root / cwd** — confirm with the user before running `stop` without a name if there are multiple active watchdogs.
- `status` takes optional `[name]` (default: `$ZELLIJ_SESSION_NAME` if set, otherwise `"default"`) and dumps the JSON.
- `list` takes no args and prints active watchdog names + project paths.

**Resolve the name before invoking:** read `$ZELLIJ_SESSION_NAME` from the environment (it is always set inside a Zellij pane). Use it as the name whenever the user has not supplied one explicitly.

**Invoke:**

```bash
${CLAUDE_SKILL_DIR}/scripts/cc-watchdog <subcommand> [name] [message]
```

If the user's message is plain English ("start a watchdog to keep working on the migration"), infer the subcommand and a short `message`. Confirm the parsed arguments before running `start` or bare `stop`.

**Unknown subcommand** → the CLI prints the usage line and exits 1. Don't retry; show the usage to the user.

</process>

<notes>
- `start` writes `{name}.json` with `active: true`, the message, current project root (from `git rev-parse --show-toplevel` or `$PWD`), and timestamps.
- Watchdog state is project-scoped via `project_path` — a watchdog started in repo A won't block Stop in repo B.
- Default continuation message if `$3` is omitted: *"Continue working. If you were mid-workflow, re-read the workflow TOC and current step file, then proceed from the current step."*
- Name is sanitised to `[a-zA-Z0-9_-]`; slashes become underscores. Warn if the user's requested name gets mangled.
- `$ZELLIJ_SESSION_NAME` is always present inside a Zellij pane (the `c` launcher creates one per invocation, e.g. `cc-myproject-1234567`). Use it verbatim as the default name — no need to prompt the user.
</notes>
