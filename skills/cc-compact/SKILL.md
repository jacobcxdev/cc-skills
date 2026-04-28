---
name: cc-compact
description: "Send /compact plus an optional follow-up prompt to the current Claude Code pane via zellij. Use when the user says '/cc-compact', 'cc-compact', 'queue compaction', or otherwise asks to trigger /compact from inside a zellij-hosted session. Requires ZELLIJ to be set; fails loudly otherwise."
argument-hint: "\"<compaction instructions>\" [\"<first prompt after compaction>\"]"
allowed-tools:
  - Bash
---

<process>

Invoke the `cc-compact` CLI at `${CLAUDE_SKILL_DIR}/scripts/cc-compact` with the arguments the user provided.

**Argument parsing — interpret `$ARGUMENTS` semantically before choosing `$1` and `$2`:**

- If the user typed two quoted strings (e.g. `/cc-compact "keep last TODO" "resume from step 3"`), use them as explicit `$1` and `$2`.
- If the user supplied a clear compaction prompt verbatim, use that as `$1`.
- If the user supplied natural language that mixes compaction intent with follow-up intent, infer both fields instead of forwarding the words mechanically.
- Treat phrases like `then continue`, `and keep going`, `resume`, `pick back up`, `continue with X`, or `after compact` as signals that the user wants a queued follow-up prompt (`$2`), not literal text inside the `/compact` command.
- Treat phrases like `retain`, `keep`, `remember`, `preserve`, `focus on`, `drop`, or `discard` as retention guidance for `$1`.
- If the user gave only a continuation instruction (for example `/cc-compact then continue`), synthesise a sensible `$1` that preserves the active objective, relevant files, blockers, and next step, and place the continuation intent in `$2`.
- If the user gave only retention guidance, pass only `$1`.
- If `$ARGUMENTS` is empty, ask the user what to retain/discard before running — the CLI requires `$1`.

**Examples:**

- `/cc-compact "keep auth flow" "resume from failing test"` → `$1="keep auth flow"`, `$2="resume from failing test"`
- `/cc-compact then continue` → synthesise `$1` such as `Retain the current objective, relevant files, unresolved blockers, and the immediate next step.` and `$2` such as `Continue from the current task.`
- `/cc-compact retain the parser bug and then continue with the hook fix` → `$1` summarises what to retain about the parser bug; `$2` continues with the hook fix.

**Invoke:**

```bash
${CLAUDE_SKILL_DIR}/scripts/cc-compact "<instructions>" ["<next prompt>"]
```

The CLI backgrounds a 5-second delay then sends `/compact <instructions>` via `zellij action write-chars` to the focused pane, then — if `$2` was given — a second 5-second delay and the follow-up prompt. That means it's firing into **this same pane we're running in**: the `/compact` will trigger mid-response. Warn the user once that we're about to compact this session.

**If the CLI errors with `Not in zellij`:** don't retry. Surface the error and note that the user's memory records the `c` launcher as broken since 2026-03-30 and being replaced by `cg` (claude-glued). They may need to launch via `cg` or run the compact manually.

</process>

<notes>
- `$1` is an instruction to the compactor ("keep X, drop Y"), not a state summary.
- `$2` is queued as the next user message after compaction — use it to continue work without a round-trip.
- The CLI uses `zellij action write-chars` + a 1-second sleep + `zellij action write 13` (CR) to submit; don't try to replicate that manually.
</notes>
