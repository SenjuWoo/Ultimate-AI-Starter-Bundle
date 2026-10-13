# Interpreting CodeBurn recommendations

Use this when evaluating `optimize` or dashboard suggestions. Checked against
CodeBurn 0.9.27 source on 2026-10-13; findings are investigation candidates,
not permission to run its apply/remove actions.

| Suggestion | Decision |
| --- | --- |
| Low MCP tool coverage | Check scope and actual host loading first. Keep useful core tools; move optional capabilities to supported task scope. Native deferred discovery/filtering makes full schemas != every-turn usage. Never remove user-owned servers from use counts alone. |
| Reads-to-edits ratio | Inspect relevant code/callers before changing them. No universal 4:1 quota: extra ceremonial reads waste context too. |
| Lower Bash output cap | Use per-command limits, retained complete logs and focused summaries. The cap minus a proposed cap is not measured output or saving. Don't silently truncate compiler errors, diffs or machine-readable data. |
| Unused custom agents | Check ownership, purpose and dependencies; keep specialists on demand. A short observation window is not proof of redundancy. |
| Expensive sessions without edits | Research, reviews and planning can be valid deliverables. Check the requested outcome, retries and actual delivery rather than equating no edit with waste. |
| High input/output ratio | Aggregate effective input includes cache; it is not a measured request size or stale-context diagnosis. Preserve verified handoff/state and start a focused chat at a useful milestone. |
| Cost outlier | Compare like workloads and applicable pricing/quota. Estimated API-equivalent dollars are not a subscription bill. Don't stop after a first patch when the user requested finished work. |
| Repeated reads | Reuse evidence tied to unchanged inputs/SHA. Re-read when files, environment or scope changed; cross-session reads can be necessary. |

The 0.9.27 `detectBashBloat` estimate comes from the difference between configured
and recommended caps, not observed output. Its low-coverage explanation assumes
every advertised schema enters every request; current host behavior can differ.
Do not publish those estimates as measured savings. Use actual cache/input/output
fields and successful task results when evaluating efficiency or quality.

History is a candidate evidence source, not another always-loaded prompt. Keep
dated failure, fix, proof and recheck condition in the owning project's STATE.md
or evidence file. Stable personal choices stay in the private operator profile;
portable verified lessons belong in `project-intel`. No bulk history import,
automatic agent deletion or global Bash cap is needed.

Sources: [CodeBurn](https://github.com/getagentseal/codeburn),
[Claude MCP Tool Search](https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search).
