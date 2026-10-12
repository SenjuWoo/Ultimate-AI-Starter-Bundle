# AI models and harness routing — settled results

## The era rule (most important line on this card)

Only findings produced with frontier-era models count as current evidence. The
operator's working cast as of **2026-10: GPT Astral, GPT Sol 6 / 6.1, Claude
Opus 5.5**. Anything older is historical context, never proof. Model names,
tiers, prices, and context windows rot in weeks — live-search before advising,
even when a line below exists. This pack deliberately ships **no model
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

- **No hot-toggling of project MCPs.** Stop/start per project breaks sessions;
  use one config-merge approach with explicit capability profiles per project
  (see `capability-profiles`).
- Stdio MCP servers: `args: []` and no wrapper indirection where avoidable;
  prove the server boots before blaming config.
- MCP schemas cost context even when unused: keep the enabled set narrow,
  per project.
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
