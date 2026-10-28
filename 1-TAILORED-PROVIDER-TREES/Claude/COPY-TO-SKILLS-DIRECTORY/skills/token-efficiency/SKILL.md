---
name: token-efficiency
description: Use when waiting for CI/builds, reducing repetitive reads, measuring token cost or caching, or choosing MCP/skill scope. Save round trips and irrelevant output without dropping evidence.
---

# Token efficiency

Reduce repetition, not verification. Context size, cached input, output and
reasoning usage are different measurements; fewer bytes are not proof of a
lower bill or unchanged answer quality.

## Where usage actually goes

Measured from one heavy user's local logs (2026-10-10, ~1,100 sessions across
Codex, Claude Code, Hermes and Grok). Run `python TOOLS/usage_report.py` for
your own numbers before changing anything.

- Requests can include substantial prior context. In one historical Codex log
  sample, cumulative input divided by tool-call count was ~124k; this is not a
  measured median request size or an uncached charge. Stable instructions,
  skill indexes, MCP schemas and large outputs can affect subsequent requests;
  caching, deferred loading and compaction determine their actual cost.
  Keep those small; end a phase by updating STATE.md and continue in a fresh
  session instead of one marathon thread.
- Codex approval reviews were ~23% of Codex usage: each escalated command
  started a reviewer that re-read the transcript. Fewer escalations mean fewer
  reviews: work inside the writable roots, batch commands, and let the user
  decide whether to widen `sandbox_workspace_write.writable_roots` for folders
  they always work in. Never change sandbox or approval settings yourself.
- Forked subagents were ~12%: a fork re-reads the parent history. Spawn only for
  independent work and give each a narrow written brief.
- 71 sessions were resumptions after a usage limit. A current STATE.md makes a
  resume a short read instead of a re-investigation (`state-resumption`).

## Wait once, report meaningful changes

Use the host's background/notification mechanism for long builds and CI.
Polling the model repeatedly costs inference even when nothing changes.
Time spent waiting in a process does not itself generate model tokens, though
tool notifications, hosted execution and later model calls may have costs.

For GitHub releases, record the exact pushed SHA, discover its required runs,
and wait with `TOOLS/Wait-External.ps1 -GitHubRun auto -Repo OWNER/REPO -Sha FULL_SHA`.
It reports the explicit verdict for that SHA with bounded polling and failure
tails; `ci-convergence` owns the truth table. Verify every required check
succeeded on that SHA before publishing.
No runs, failed/cancelled runs, or a different SHA are not success.
Respect the host's wait limits and keep the user informed without busy polling.

## Cache evidence, not assumptions

Cache rules and prices depend on the provider, model and billing plan. Do not
apply one API's rates to another API or a subscription quota. For example,
Anthropic's standard API cache writes are 1.25x base input for five minutes
or 2x for one hour, and reads 0.1x; verify current applicable pricing first.
Output is not made free by caching an input prefix.

Keep durable instructions/tool definitions stable and put changing task state
later where the host permits. Prefix changes can reduce cache reuse, but the
exact matching, minimum lengths and invalidation rules are host-dependent.
Use actual usage fields (for example Anthropic `cache_read_input_tokens`) or
provider telemetry before claiming a cache hit or saving. Never schedule
requests just to keep an otherwise unused cache warm.

## Load relevant capabilities

- Keep skill names/descriptions compact; load bodies only when relevant.
- Prefer a sufficient native tool or CLI already available. A dormant CLI adds
  no MCP schema; its instructions, commands and output still consume context.
- Scope optional MCP servers. Claude Code supports deferred Tool Search;
  Codex and Hermes support native tool filters. Respect user-owned servers.
- Advertised schema bytes/4 is only a rough size estimate, not loaded, cached
  or billed tokens. Measure the current provider rather than quoting old totals.
- Do not change models, auxiliary routing or providers merely to save tokens
  without the user's requested quality and configuration constraints.
- Do not route the main model through `openrouter/free`. That router picks a
  free model at random, so model/cache reuse is not predictable. A $0 OpenRouter
  account is 50 requests/day and 20/minute. Cloudflare's free pool is
  10,000 neurons/day and is not a token allowance. Confirmed daily quota
  exhaustion is not a retry fan-out. A 429 can also mean temporary rate limits
  or capacity: inspect the error/reset metadata and honor `Retry-After` with
  bounded backoff. Do not silently switch models or paid routes. Checked 2026-10-07.

Free-route sources:
[OpenRouter limits](https://openrouter.ai/docs/api-reference/limits),
[free router](https://openrouter.ai/openrouter/free),
[Cloudflare pricing](https://developers.cloudflare.com/workers-ai/platform/pricing/),
[Cloudflare error codes](https://developers.cloudflare.com/workers-ai/platform/errors/).

## Batch and bound output

Batch independent reads, reuse evidence already in context, and request only
the fields/lines needed. A workspace map (`WORKSPACE.md`, see
`workspace-organization`) replaces re-exploration: read the map, then update
the row you changed. Check exit codes and truncation. Do not rerun a passing
gate unless its inputs or environment changed. Prefer targeted searches to
dumping entire trees, histories or configuration files.

RTK is lossy and command/version dependent, not a universal 97% saving.
This pack's narrow safe hook covers standalone human-facing status/tests;
exact diffs, search, reads, structured output and pipelines stay raw.
Read [the measured policy](references/shell-output-compression.md) before
changing rewrites. Preserve failures, exit status and access to full output.

Sources checked 2026-09-13:
[Anthropic cache rules](https://platform.claude.com/docs/en/build-with-claude/prompt-caching),
[Claude Code caching](https://code.claude.com/docs/en/prompt-caching).
