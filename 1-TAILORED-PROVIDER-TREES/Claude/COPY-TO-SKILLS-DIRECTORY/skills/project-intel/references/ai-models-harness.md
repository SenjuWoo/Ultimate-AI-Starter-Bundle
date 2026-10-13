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
