# Where AI usage goes, and what this bundle does about it

Measure your own machine first:

```bash
python TOOLS/usage_report.py
```

It reads the session logs Codex, Claude Code, Hermes and Grok already keep on
this PC and prints aggregates only (sessions, tool calls, failed commands, token
totals, overhead shares, costliest workspaces, phrases you retype). Nothing is
uploaded or written.

Codex output includes its reasoning detail; the report counts that output only
once. The historical shares below used the older calculation and are not
revalidated billing measurements. Run the current report for a fresh estimate.
Provider output accounting is defined by the
[Codex protocol](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/protocol.rs).

## Measured on the maintainer machine (2026-10-10, ~1,100 sessions)

| What | Value | Why it matters |
| --- | --- | --- |
| Median per-session cumulative input / tool calls (historical working sessions) | ~124k tokens | A coarse ratio, not individual request sizes or uncached charges; caching and compaction matter. |
| Codex approval-review sessions | 356, ~23% of Codex weight | Each escalated command starts a reviewer that re-reads the transcript. |
| Forked subagent sessions | 95, ~12% of Codex weight | A forked subagent re-reads the parent's history. |
| Sessions resumed after a usage limit | 71 | Without a current STATE.md, each resume re-investigates. |
| Stale V8.0.1 contract still in Codex AGENTS.md | 12.5 KB | ~3k tokens on every Codex request until 8.8.0 stripped it. |
| Folder map retyped by hand | 36 sessions | Now a generated machine map. |

"Weight" is uncached input + 0.1 x cached input + 5 x output: a relative cost,
not a bill. Plans and providers price these differently.

## Measured on the maintainer machine (2026-10-15, CodeBurn + transcripts)

| What | Value | Why it matters |
| --- | --- | --- |
| One ~27 h Claude Code thread (4 compactions, ~2,500 assistant messages) | 28.8M effective input vs 0.78M output (CodeBurn, measured) | Every turn re-reads the cached history: cost follows thread length. Four such sessions were $4.70 measured. |
| Unused MCP tool names left machine-wide (six servers, 0 calls) | ~110.7k tokens over six sessions, ~$0.02 (CodeBurn, estimated) | Real but small, because tool search defers the schemas. They are parked anyway: less noise for tool choice, and providers without deferral pay in full. |
| "Edits more than reads" flag (153 reads / 139 edits) | One session | It counts Read/Edit calls only. The same kind of transcript had 914 shell calls doing the reading and 1 failed Edit in 81. A prompt to look, not a verdict. |
| Native computer-use "0 of 27 tools used" | 2 permission requests, no actions | True, and not removable: it is a host built-in, and the owner had denied input automation. |

## What the bundle does

- **Smaller always-on text.** Skyrim content installs only with the Skyrim
  pack. Old preamble and template copies are stripped exactly. Provider
  templates are a few lines.
- **Machine map.** Paths the agent would otherwise search for are listed once,
  per PC, never shipped.
- **Resumable work.** `state-resumption` and the provider templates make
  "continue" a short read of STATE.md and `git status`.
- **Parked task servers.** A tool's own installer registers its MCP server for
  every chat. `Set-McpProfile.ps1 -Park` moves such entries out (exact copy kept)
  and `-Auto` puts one back for the project whose files match; the GitHub server is
  skipped where `gh` is signed in. The doctor fails while one is still
  machine-wide.
- **Chat history that survives.** `Backup-AiHistory.ps1` copies transcripts to a
  folder cleaners never touch, and Claude's retention is raised from 30 days to 365.
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
