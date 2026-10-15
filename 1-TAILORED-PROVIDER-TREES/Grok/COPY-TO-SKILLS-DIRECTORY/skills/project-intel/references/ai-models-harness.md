# AI models and harness routing — settled results

## Evidence freshness

Check the date, tool version, actual output and reproducibility of a finding.
The model's identity does not certify it or invalidate a reproducible older
result. Model names, tiers, prices and context windows change: verify primary
sources before advising, even when a line below exists. This pack ships **no model
ranking tables**: old rankings were removed from the bundle rather than
relabelled, because they were never controlled benchmarks.

## Routing principles (these do not rot)

- Split by cost class: reasoning-heavy decisions to the strongest model
  available; bulk mechanical work to the cheap frontier tier; never pay
  frontier prices for token-volume work.
- Agent surfaces (Claude Code, Codex, other CLIs) are where repo work gets
  verified; chat surfaces are for thinking, not for "done".
- One harness manages routing; do not let multiple harnesses fight over the
  same config. Model choice is the operator's; preambles never manage models.
- Verify a model claim before citing it: check the provider's current docs or
  changelog, not recall. If acting on a card line, treat it as a hypothesis.

## Harness / MCP wiring (hard-won, stable)

- Use the supported host's scoped config merge and reconnect/restart behavior,
  not repeated blind stop/start cycles. A written entry is not proof of an
  active connection (see `capability-profiles`).
- Stdio MCP servers: `args: []` and no wrapper indirection where avoidable;
  prove the server boots before blaming config.
- MCP schemas can cost context even when unused; native deferred discovery,
  filters and caching affect the actual surface. Keep optional tools scoped;
  advertised bytes are not a bill.
- Python tooling under a desktop app that exports a venv into the environment:
  strip `PYTHONPATH` for child tools; install with `env -u PYTHONPATH` or pip
  will consider venv packages "already satisfied".
- Compression/context settings: be less aggressive when the model has large
  free context — aggressive compression costs recall without saving money
  there. Tune per provider, not globally.
- Free-model tiers: usable for bulk; treat availability as best-effort and
  never wire one into a critical loop without a fallback.
- Token discipline pays more than model choice: prompt-cache locality (stable
  prefix, volatile results late), load only the skill/reference needed, batch
  independent fetches, never restate.

## Cost control (stable)

- The cheapest large saving is not re-reading and not re-searching: check
  project cards and state files first.
- Batch long-running scans; write results to files and read summaries — never
  stream raw dumps into context.

## Verified maintenance lessons (2026-10-13)

- A resume must inspect current source and publication state: another agent
  may have finished the release after the previous handoff. Verified against
  the v8.12.1 tag/assets; don't recreate an obsolete pending release.
- Upstream installs can be another writer for provider skills/configs. REA's
  CLI works without its setup or a full MCP registration; the isolated 6.4.0
  transport advertised 170 tools. Select the operation before the harness.
- Skill auditor success must include real input: missing/empty trees and
  invalid UTF-8 previously passed. Actual CLI regression fixtures now reject
  them. Parsing success still does not certify every instruction's quality.
- Promote history as a dated, scoped claim with proof and a recheck condition.
  Keep private paths local. A recent model assertion is not stronger than a
  reproducible older result; don't auto-import conversation dumps into prompts.

## Workflow-scoped efficiency lessons (2026-10-15)

Each line: workflow -> tried -> result -> cause -> what worked -> evidence -> recheck.

- **One Claude Code thread for a ~27 h cross-engine mod build** -> kept going
  through 4 compactions and ~2,500 assistant messages -> 28.8M effective input
  tokens for 0.78M output (CodeBurn, measured, one machine) -> every turn re-reads
  the cached history, so cost follows thread length, not tool choice -> finish a
  phase, update `STATE.md`, start a fresh session that reads only `STATE.md` and
  the git status. Recheck if cache pricing or compaction behaviour changes.
- **CodeBurn "edits more than reads" (153 reads / 139 edits)** -> read as "blind
  edits" -> in the one transcript checked, Edit failed 1 of 81 times and never for
  edit-before-read (the tool enforces it), while 914 PowerShell/Bash calls did the
  reading the ratio cannot see -> the ratio counts Read/Edit calls only -> treat it
  as a prompt to look, not a verdict. The shell friction that was real: five
  PowerShell commands were blocked by the harness's system-path guard because a
  `Remove-Item` of a lab file shared a command with `C:\Program Files` paths (a
  false positive) -> put a deletion in its own command with only its target.
  Recheck on a pure editing workflow.
- **CodeBurn "low MCP coverage -> `claude mcp remove` six servers"** -> removing
  all six -> two were host-owned (native computer-use is a default-off built-in:
  two permission requests and no actions, because the owner denied input
  automation; the app's own session/sidebar tools), one a desktop extension, one
  this pack's GitHub server, one a tool's own installer entry -> only the last two
  are the pack's to move -> park task-specific servers per project
  (`Set-McpProfile.ps1 -Park`, `-Auto`), leave host-owned ones, skip the GitHub
  server where `gh` is signed in. Size it honestly: unused tool names cost ~$0.02
  over six sessions in the same report; the long-thread line above cost $4.70.
- **Claude Code has no global off switch for a user-scope MCP server** (only a
  per-project disable list) -> moving the entry out of user scope is the only way
  to stop it loading everywhere -> verified against the current MCP docs;
  recheck when Claude Code adds a default-off flag.
- **Chat history after a cleaner run (BleachBits wiped Claude's session folder,
  2026-10-13)** -> relying on the app's history -> older Claude transcripts were
  gone; the Codex thread (which had imported Claude summaries) and exported
  claude.ai chats survived -> keep `STATE.md` in each project, copy transcripts
  to a folder cleaners never touch (`TOOLS/Backup-AiHistory.ps1`), and rebuild
  context from a thread's user messages first (about 65 KB from a 212 MB
  rollout). Claude Code also deletes transcripts after `cleanupPeriodDays`
  (default 30; never set 0). Recheck if the cleaner's rules change.
- **Git Bash `python` on this Windows PC** -> instructions said Python is on PATH
  -> it resolved to the Microsoft Store stub ("Python was not found") while real
  Python was installed -> call `py -3` or the full interpreter path; the durable
  fix is the owner's: turn off the Store app-execution alias or reorder PATH.
