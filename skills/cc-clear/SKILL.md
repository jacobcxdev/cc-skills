---
name: cc-clear
description: "Send /clear plus an optional follow-up prompt to the current Claude Code pane via zellij. Use when the user says '/cc-clear', 'cc-clear', 'queue clear', or asks to reset this session's conversation from inside zellij. Requires ZELLIJ to be set; fails loudly otherwise."
argument-hint: "[\"<next command after clear>\"]"
allowed-tools:
  - Bash
---

<process>

Invoke the `cc-clear` CLI at `${CLAUDE_SKILL_DIR}/scripts/cc-clear` with the arguments the user provided.

**Argument parsing — interpret `$ARGUMENTS` semantically before choosing whether to send `$1`:**

- No arguments → run `cc-clear` (clear only).
- One quoted string → use it as explicit `$1`.
- Unquoted natural language should be treated as intent, not blindly forwarded.
- Treat phrases like `then continue`, `resume`, `keep working on X`, `read Y then continue`, or `after clear` as instructions for the queued follow-up prompt.
- If the user gives broad directions rather than a ready-to-send prompt, rewrite them into a concise post-clear prompt that will make sense in a fresh session.
- Do not queue filler words mechanically. For example, `/cc-clear then continue` should queue something like `Continue with the current task.` rather than the literal text `then continue`.
- If the user is clearly asking only to clear the session with no follow-up, omit `$1`.

**Examples:**

- `/cc-clear` → no `$1`
- `/cc-clear "open the failing test and continue"` → `$1="open the failing test and continue"`
- `/cc-clear then continue` → `$1="Continue with the current task."`
- `/cc-clear read src/foo.py and continue with the parser fix` → `$1` should be rewritten into a compact fresh-session instruction such as `Read src/foo.py, then continue with the parser fix.`

**Invoke:**

```bash
${CLAUDE_SKILL_DIR}/scripts/cc-clear ["<next command>"]
```

The CLI backgrounds a 5-second delay then sends `/clear` via `zellij action write-chars` to the focused pane, then — if `$1` was given — a second 5-second delay and the follow-up prompt. That means it's firing into **this same pane we're running in**: the `/clear` will wipe this conversation mid-response. Warn the user before running.

**If the CLI errors with `Not in zellij`:** don't retry. Surface the error and note the `c` launcher is broken since 2026-03-30 (being replaced by `cg`). They may need to launch via `cg` or type `/clear` manually.

</process>

<notes>
- Unlike `cc-compact`, `/clear` takes no argument of its own — `$1` here is purely the next user message queued after the clear.
- The CLI uses `zellij action write-chars` + a 1-second sleep + `zellij action write 13` (CR) to submit; the double-sleep between messages avoids zellij's bracketed-paste window coalescing them into one submission.
</notes>
