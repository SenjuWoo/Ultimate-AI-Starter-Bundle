# Where AI usage goes, and what this bundle does about it

Measure your own machine first:

```bash
python TOOLS/usage_report.py
```

It reads the session logs Codex, Claude Code, Hermes and Grok already keep on
this PC and prints aggregates only (sessions, tool calls, failed commands, token
totals, overhead shares, costliest workspaces, phrases you retype). Nothing is
uploaded or written.

## Measured on the maintainer machine (2026-10-10, ~1,100 sessions)

| What | Value | Why it matters |
| --- | --- | --- |
| Median context per Codex tool call (working sessions) | ~124k tokens | Every call re-sends the whole context; anything always loaded is paid on every call. |
| Codex approval-review sessions | 356, ~23% of Codex weight | Each escalated command starts a reviewer that re-reads the transcript. |
| Forked subagent sessions | 95, ~12% of Codex weight | A forked subagent re-reads the parent's history. |
| Sessions resumed after a usage limit | 71 | Without a current STATE.md, each resume re-investigates. |
| Stale V8.0.1 contract still in Codex AGENTS.md | 12.5 KB | ~3k tokens on every Codex request until 8.8.0 stripped it. |
| Folder map retyped by hand | 36 sessions | Now a generated machine map. |

"Weight" is uncached input + 0.1 x cached input + 5 x output: a relative cost,
not a bill. Plans and providers price these differently.

## What the bundle does

- **Smaller always-on text.** Skyrim content installs only with the Skyrim
  pack. Old preamble and template copies are stripped exactly. Provider
  templates are a few lines.
- **Machine map.** Paths the agent would otherwise search for are listed once,
  per PC, never shipped.
- **Resumable work.** `state-resumption` and the provider templates make
  "continue" a short read of STATE.md and `git status`.
- **Release ritual.** `release-checklist` ends with the paste-ready changelog
  and payload-only archive, so a release is not a second conversation.

## What only you can decide

- **Codex approvals.** Fewer escalations mean fewer reviews. If you always work
  in the same folders, adding them to `[sandbox_workspace_write] writable_roots`
  in `~/.codex/config.toml` avoids an approval round per write there. That
  widens what Codex may write without asking; the bundle never changes it.
- **Reasoning effort.** Higher effort spends more output tokens per turn. Use
  the highest setting for hard debugging, not as the default for routine edits.
- **Subagents.** Spawn them for independent work with a narrow brief; a full
  fork costs a full re-read.
- **Session length.** End a phase by updating STATE.md and start a fresh
  session for the next one instead of one marathon thread.
