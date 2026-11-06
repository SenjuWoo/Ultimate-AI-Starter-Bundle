# Review packet: free tools for agent quality and efficiency

Status: **review only**. Nothing here was installed, wired, or adopted.
Date checked: **2026-11-06**.
Do not treat a row as a bundle decision. A reviewer accepts or drops each row.
Do not publish this file as operator guidance until that review happens.

Scope the operator asked for: free tools that correct an agent's code or
reasoning on the fly, cut overthinking and tool loops, and reduce usage on
Hermes (especially DeepSeek-class models), Claude, Codex/GPT, Antigravity, and
the other wired harnesses. Only gaps. Tools already covered are listed so the
next agent does not research them again.

## Verdict for the reviewer

Do not add another agent, another compressor, or a "think harder" loop.

The pack already hard-stops repeated tool calls, caps tool output, compresses
context, and keeps a measured output filter (RTK) plus on-demand compression
(Headroom). Small models go wrong because they **reason at full effort and then
ignore a warning**. The free fix is the host's own effort dial, plus a
deterministic checker (types, lint, tests) whose output is shorter than another
thinking pass.

Highest-leverage gaps, in order:

1. DeepSeek's own API maps `medium` and `xhigh` to `high`. The Hermes research
   route is already `reasoning_effort: high`. There is no cheaper step on that
   API until the request is `low` or thinking is off. Whether OpenRouter applies
   that map was **not** proven with a live call.
2. Claude Code, Codex, and Antigravity each already have an effort control and
   a context view. Those commands are not written down in this pack's usage
   docs. Document them. Do not install a product to get them.
3. A project-local post-edit check (`ruff`, and `ty` where a Python project
   wants types) is the on-the-fly code corrector. Keep it out of the pack gate.
   The 2026-11-05 tooling matrix already refused to make Ruff or ty a pack
   requirement.
4. Promptfoo is the one new local eval tool worth a later look, and only to
   **measure** an effort change. It spends model calls. It does not sit in the
   live loop.

## Already covered — do not re-research

| Already here | Where | What it already does |
|---|---|---|
| RTK, narrow hook, measured fidelity | `docs/GUIDE.md`, `docs/TOOL-EVALUATIONS.md`, `token-efficiency` | Lossy shell filter. Not a universal saver. `rtk read` saves nothing. |
| Headroom MCP (`compress` / `retrieve` / `stats`) | GUIDE, `headroom` skill | On-demand compression. Not an inference proxy. The Grok wrap path is a known break. |
| CodeBurn, `TOOLS/usage_report.py` | `codeburn` skill, `docs/USAGE-ECONOMY.md` | Local usage measurement. |
| codebase-memory, Serena | GUIDE catalog | Structural search and symbol edits. Serena is the LSP route. |
| Ponytail | vendored plugin | Shorter code. Caveman lost to it on the pack's own benchmark. |
| Superpowers, reasoning-discipline, systematic-debugging, verification skills | canonical skills | Planning and review. A second review loop was measured as slower with no quality gain (Superpowers release notes). |
| Hermes compression | starter `config.yaml`, `docs/HERMES-MODELS.md` | Fires at 320k tokens on a 1M window. Prunes large tool results first. Aborts if the summary fails. |
| Hermes tool-loop guardrails | starter `config.yaml` `tool_loop_guardrails` | Warnings on, **hard stop on**. Upstream's interactive default is warning-only. |
| Hermes tool output cap | `tool_output.max_bytes: 30000`, `max_lines: 1500` | Already bounds what a tool result puts back into context. |
| Hermes verify / stall nudges | `verify_guidance`, `stall_guards`, `max_verify_nudges: 3` | Already a bounded "don't stop early / don't spin" nudge. |
| Skill-creation nudge | `skills.creation_nudge_interval: 0` | Agent-made skills are not being nudged into existence. |
| Planner/worker | `docs/HERMES-MODELS.md` | Ordinary turns are one model. DeepSeek is the on-demand research route, not the main loop. MoA is `/moa` only. |
| Prompt-cache TTL 1h, response cache off | starter config | Response caching can serve a stale answer. Left off on purpose. |
| MCP parking, lean always-on text, STATE resume | GUIDE, `token-efficiency`, `state-resumption` | The measured cost is thread length, not another tool. |
| Caveman, OmniRoute, llmtrim, lean-ctx, ECC, Understand-Anything | `docs/TOOL-EVALUATIONS.md` | Conflicts, trust-boundary proxies, or duplicates. |
| claude-mem | GUIDE, explicit `-WithClaudeMem` only | Memory plugin. Not a default. |
| anti-slop, taste-skill, replica-skill | evaluations | Optional, overlapping, not stacked. |
| Ruff, ty, Biome, ast-grep, prek | `docs/TOOLING-MATRIX.md` (2026-11-05) | Optional or refused **for this pack**. That is not a ban on a project that is actually Python or JS. |

## What the sources say about loops and overthinking

### Hermes already stops the dumb loop

Official docs, fetched 2026-11-06 from the Hermes llms full text
(`https://hermes-agent.nousresearch.com/llms-full.txt`):

- The agent detects a stuck tool loop: the same call failing, the same tool
  failing with different args, or an idempotent call returning the same result.
- Default is a **warning written into the tool result**. Interactive CLI, TUI,
  Desktop, and ACP stay warning-only so a person can interrupt. Gateway and
  cron hard-stop by default.
- Documented knobs: `warnings_enabled`, `hard_stop_enabled` (default false),
  `non_interactive_hard_stop_enabled` (default true), `warn_after`
  (`exact_failure` 2, `same_tool_failure` 3, `idempotent_no_progress` 2),
  `hard_stop_after` (5 / 8 / 5).

The starter at `1-TAILORED-PROVIDER-TREES/Hermes/config.yaml` already sets
`hard_stop_enabled: true`. That is stricter than upstream's interactive
default. A 2026-05-14 upstream issue (`NousResearch/hermes-agent` #25823) says
warning text is not enough: the model keeps retrying until the iteration budget
dies. A later issue (#67829, 2026-07-20) shows the same pattern, 25 identical
memory calls, warning appended, no runtime block. The pack's hard stop is the
response to that class of bug. Do not add a community "loop guard" plugin on
top.

Two Hermes features **spend** tokens. They are not efficiency tools:

- `/goal` keeps going until an auxiliary judge says the reply satisfies the
  goal. The judge fails open: a broken judge means "continue". Default budget
  `goals.max_turns` is 20 continuations. Source:
  `https://hermes-agent.nousresearch.com/docs/user-guide/features/goals`
  (Chinese mirror checked the same day; English page is the feature).
- `/loop` re-runs a prompt on a timer inside the session. Backstop
  `loops.max_ticks` defaults to 100. `--until` uses the same judge.
  Source: `https://hermes-agent.nousresearch.com/docs/user-guide/features/loops`.

`agent.max_turns` defaults to 500 upstream (`HERMES_MAX_ITERATIONS`). The
starter sets `max_turns: null` on purpose: "large one-shot jobs must never be
amputated mid-task." Delegation children are capped at `max_iterations: 50`.
A reviewer who wants a DeepSeek profile cap should add a **profile**, not
change this starter default.

Curator (background skill maintenance) exists so agent-created skills do not
pile up and tax the index. Source:
`https://hermes-agent.nousresearch.com/docs/user-guide/features/curator`.
The pack's 81 canonical skills are not Curator's problem. Do not turn skill
creation nudges back on to "boost" a small model.

Community plugins seen and not recommended:

- `iteration-budget-meter` — desktop status chip. Visibility only.
- `hermes-jev-routing` — rewrites the model per turn. Same class of auto-router
  the pack already refused in Caveman and OmniRoute.

### DeepSeek thinking is on, and "medium" is not medium

Primary: `https://api-docs.deepseek.com/guides/thinking_mode` and the chat
completion reference, both dated 2026-11-05 on the doc site.

- Thinking is **on by default**. Default effort is `high`.
- Native effort values are `none` / `low` / `high` / `max`. `none` turns
  thinking off.
- Compatibility map: `minimal` → `low`; `low` → `low`; `medium` → **high**;
  `high` → `high`; `xhigh` → **high**; `max` and `ultra` → `max`.
- Unset `max_tokens`: non-thinking defaults to 8K output; thinking defaults to
  **64K** (128K at `max`). That output is billed.
- Thinking mode ignores `temperature`, `presence_penalty`, and
  `frequency_penalty`.
- Pricing page the same day: `deepseek-flash` is DeepSeek-V4.1-Flash-1017,
  1M context, cache-hit input far below cache-miss. Off-peak is half of peak.
  Peak hours listed there are 01:00–04:00 and 06:00–10:00 UTC, Monday–Friday,
  excluding Chinese public holidays.

The Hermes research route is `deepseek/deepseek-v4.1-flash-1017` at
`reasoning_effort: high`, through OpenRouter. On DeepSeek's **own** API, setting
that route to `medium` would still be `high`. `low` is the first real step
down, and thinking stays on. Turning thinking off needs `none` or
`thinking.type: disabled`.

Not verified: that OpenRouter forwards those fields unchanged, or that a live
`usage` object shows fewer reasoning tokens at `low`. Check one request before
changing the starter. Particle-1's effort scale is a different provider and
must not be assumed to use this map.

FIM completion is non-thinking only (same pricing page). Hermes does not drive
FIM today. Not a loop fix.

### Claude Code — dials, not a new CLI

Primary pages checked 2026-11-06:

- Effort: `https://code.claude.com/docs/en/model-config`
- Hooks: `https://code.claude.com/docs/en/hooks` and the hooks guide
- Usage habits: `https://support.claude.com/en/articles/14552983-models-usage-and-limits-in-claude-code`
  (updated 2026-10-27) and Anthropic's 2026-08-14 post
  `https://claude.com/blog/maximizing-the-value-of-your-claude-code-sessions`

What those pages actually say:

- `/effort` sets `low`, `medium`, `high`, or `xhigh`. `max` is not a settings
  value. Effort is a behavioral signal, not a hard token budget. Opus 5.5,
  Sonnet 5.5, and Haiku 5.5 default to medium, and their thinking cannot be
  switched off. Lower effort still thinks on a hard problem, just less.
- Changing model or effort mid-conversation can miss the prompt cache. Set
  both at the start. Each model has its own cache.
- `/clear` drops history and keeps project memory. `/compact` summarizes.
  `/context` shows what is loaded (CLAUDE.md, MCP). `/cost` is the session
  bill on API billing. Auto-compact exists; `/autocompact 200k` puts the
  safety net back on a 1M model (needs Claude Code v2.1.221+).
- CLAUDE.md is on every turn. Caching makes later turns cheaper, but the
  bytes still occupy the window. A "Compact instructions" section in
  CLAUDE.md tells the summary what to keep.
- `PreToolUse` can rewrite a tool's input (`updatedInput`) before it runs.
  `PostToolUse` can send a reason back with `continueOnBlock: true` so the
  model sees the failure and continues. A hook that only logs does not
  correct anything. Async hooks cannot block.
- A `SessionStart` hook with matcher `compact` injects stdout into the
  compacted context. Whatever it prints is paid on later turns. Keep it short.

The pack already says: end a phase, write STATE, start a fresh session; park
unused MCP servers; keep instructions stable. It does not name `/effort`,
`/context`, or the post-edit hook pattern. That is a docs gap, not a missing
binary.

Do not add a global Claude hook from this packet. The installer owns provider
settings. A **project** `.claude/settings.json` hook that runs the project's
own checker is the shape to review.

### Codex / GPT

Primary: `https://developers.openai.com/codex/config-reference`,
`config-basic`, `config-sample`, `config-advanced`, and
`https://developers.openai.com/codex/skills`. Sample page carries an older
publish stamp; the key names below were on the reference.

- `model_reasoning_effort`: `minimal | low | medium | high | xhigh`.
- `plan_mode_reasoning_effort` can be higher than the normal turn, including
  `none`. Plan expensive, edit cheaper, without a second product.
- `model_verbosity`: `low | medium | high` on Responses-API GPT-5-family
  models. `low` shortens the answer. It does not by itself shorten reasoning.
- `model_reasoning_summary`: `auto | concise | detailed | none`.
- `tool_output_token_limit`: token budget for one tool result stored in
  history. This is the Codex equivalent of the Hermes `tool_output` cap.
- `model_auto_compact_token_limit` can only be set **lower** than the model
  default. Unset uses the model default.
- Skills index is at most 2% of the window, or 8,000 characters when the
  window size is unknown. Descriptions are shortened first. The full
  SKILL.md is read only when a skill is selected.
- `/goal` exists and is a long-horizon loop. It is off unless
  `features.goals` is enabled. Leave it off for routine work. Same failure
  mode as Hermes `/goal`.

`docs/USAGE-ECONOMY.md` already covers approval reviews (~23% of one measured
Codex corpus) and forked subagents (~12%). Widening writable roots is the
operator's choice. The pack must not edit sandbox settings.

A Chinese secondary writeup of the 90% auto-compact formula was **not** used
as a source. Use the config reference.

### Antigravity

Already wired by the installer: global rules, 81 skills, MCP, with a
24,000-byte file cap and a 20,000-token customization budget so the bundle
stays near 14 KB. That part is in `docs/GUIDE.md`. Do not re-design it.

New, from `https://antigravity.google/docs/` on 2026-11-03 to 2026-11-06:

- `/effort` on the CLI: `low`, `medium`, `high`, plus `xhigh` or `max` only
  when the model publishes them. A fixed-budget model reports that effort is
  not adjustable. `low` is the documented setting for lookups and small edits.
  Source: `https://antigravity.google/docs/cli/commands/effort`.
- `/context` draws rules, skills, subagents, workflows, plugins, and MCP
  schemas as separate rows. Use it before adding another server.
  Source: `https://antigravity.google/docs/cli/commands/context`.
- Changelog (2026-11-03): rules have their **own** 20,000-token budget, so a
  large rules file no longer pushes skills and MCP tools out. A rule over
  budget is listed by path for the agent to open. Gemini 3.8 Flash is
  described there as an everyday agent model whose thinking levels trade
  depth for latency.
- `/learn` proposes a rule or skill from the session and writes only after
  approval. Useful, and it grows the customization budget if accepted every
  time. Prefer updating an existing rule.
- `/boost` and `/teamwork` are on the slash-command table as **paid**
  multi-agent reasoning. They are the opposite of an efficiency tool.
- `/grill-me` is on all plans and interviews one question at a time. That
  lengthens planning. Do not make it a default.

Free-tier model lists and weekly quotas in blog roundups were **not** copied
in. Google's own pricing page was not re-fetched as a table in this pass.
Do not quote a model-removal date from a secondary site.

### Grok

No new tool. Headroom is on-demand MCP, not a wrap. RTK and CodeBurn already
cover output size and cost. A second compressor in front of Grok is how the
pack already broke Grok once (`Ensure-Headroom-Grok.ps1 -Repair`).

## On-the-fly code correction

The pattern that works: after an edit, a **deterministic** tool prints
diagnostics, and the model sees those diagnostics instead of taking another
thinking pass. The model is not the checker.

| Tool | What was checked | Fit | Reviewer action |
|---|---|---|---|
| Ruff | Already an optional probe. MIT. `ruff check` / `--fix` is local and fast. | Pack gate stays without it (`docs/TOOLING-MATRIX.md`). A Python **project** can run it after an edit. | Document the hook shape. Do not add Ruff to `Verify-Fast.ps1`. |
| ty (Astral) | `https://docs.astral.sh/ty/` and `https://github.com/astral-sh/ty`. MIT. Beta. Rust type checker and language server. Astral claims 10x–100x vs mypy/Pyright on home-assistant; that claim was **not** re-benchmarked here. `uvx ty check` needs no install. Official support target is Python 3.10+. | Same decision as the matrix: this pack has no type-check need. A Python project that already wants types can run it. Pre-commit hook lives at `astral-sh/ty-pre-commit`. | Per project. Not a pack dependency. Re-check when it leaves beta if someone wants it in FAST. |
| Biome | Matrix: not adopted, no JS/TS app in the pack. | Same as ty, for a JS project. | No pack change. |
| Semgrep | Standalone MCP repo `semgrep/mcp` was **archived 2025-10-28**. The README says the server moved into the official `semgrep` binary. That repo was MIT. The current binary's license was not re-read. | An always-on MCP repeats the schema-cost mistake. A single `semgrep scan` the agent runs on the files it just edited does not. | CLI only, per project, after reading the current license. No MCP registration. |
| Serena | Already the pack's LSP/symbol path. | Do not add a second language-server MCP. | None. |
| ast-grep | Matrix: rejected as a search tool because it duplicates ripgrep. | A structural **rewrite** is a different job. Not needed for the loop problem. | Leave rejected. |
| Project hook | Claude `PostToolUse` on `Edit\|Write`, `continueOnBlock: true`, command is the project's checker. Hermes already has a pre-tool plugin hook in the agent loop; a checker plugin was not designed here. Codex lifecycle hooks exist (`config-reference` / sample discussion of managed hooks). | This is the actual "correct on the fly" mechanism. | One example in a future doc, project-scoped, off by default in the installer. |

Aider (`https://aider.chat/docs/usage/lint-test.html`,
`https://aider.chat/docs/repomap.html`, docs stamped 2026-04-25):

- `--auto-lint` defaults on. `/lint` and `/test` feed failures back and the
  model tries to fix them. That is a real on-the-fly loop.
- The repo map is a symbol sketch, not the whole file. Aider's own FAQ says
  weaker models get overwhelmed by the map and sometimes try to edit the map
  itself, so the map is often **disabled** for weak models. Forcing it on is
  `--map-tokens 1024`.
- It is a second harness with its own model config, git commits, and prompt
  cache. Stacking it on Hermes or Claude Code doubles the agent.

Reviewer action: **do not bundle**. Someone who wants the lint loop should
use the hook row above inside the harness they already run. Aider's LICENSE
file was **not** opened in this pass.

Promptfoo (`https://github.com/promptfoo/promptfoo`, README read 2026-11-06):

- MIT, still stated as MIT after the OpenAI announcement in that README.
- Evals run locally. Assertions include exact, contains, regex, JSON schema,
  and a JS/Python predicate. Those cost no extra model call.
- `llm-rubric` and model-graded assertions spend another model call. Do not
  use those to police a small model; they recreate the judge loop.
- Useful experiment, once: the same Hermes task at DeepSeek `high` vs `low`,
  scored by tests and a non-model assertion. If `low` passes, the research
  route does not need `high` for that class of task.
- Red-team probe quotas in secondary writeups were not confirmed on
  Promptfoo's own pricing page. Ignore them until that page is read.
- Not an always-on fixer. Do not register it as an MCP.

## Explicit rejects for this goal

| Idea | Why it does not belong |
|---|---|
| Caveman, OmniRoute, llmtrim, any local proxy that holds the API key | Already evaluated. Trust boundary plus a second writer of provider files. |
| lean-ctx as a compressor | Measured 0% on shell output here. Map mode duplicates codebase-memory. 78 MCP tools. |
| ECC, a 300-skill pack, a second planning method (spec-kit, Beads, Taskmaster, BMAD, Gas Town) | Not given a fresh primary-source pass in this packet. They add a planning surface beside Superpowers, writing-plans, and STATE.md. Do not adopt from memory. |
| Cline, Roo, Kilo, Goose, OpenCode, Crush, Continue, a second IDE agent | A second harness. The operator already has Hermes, Claude, Codex, Antigravity, Grok. |
| `/goal`, `/loop`, `/boost`, self-consistency, always-on MoA | More model calls. MoA is already opt-in and should stay that way. |
| Repomix / dumping the repo into one prompt | Increases context. codebase-memory and Serena already answer "where is this". |
| `openrouter/free` or a free-tier stack | `token-efficiency` already forbids it as a default. Random model, no cache reuse. |
| Raising DeepSeek to `max` to stop mistakes | `max` maps to the largest thinking budget and a 128K default output cap. That is the expensive direction. |
| Turning `hard_stop_enabled` back off | Upstream's own bugs say warning text does not stop a small model. |

## Review questions

Answer these before any config edit. None of them is a "go install".

1. **DeepSeek profile, not the starter.** For the research route only, is
   `reasoning_effort: low` acceptable on mechanical investigation, with `high`
   left as a manual override? Prove it with one OpenRouter response's
   reasoning-token field. Do not assume the DeepSeek map applies until that
   field moves.
2. **Can Hermes send thinking-off?** The starter only has `reasoning_effort`.
   Confirm whether `none` is forwarded. If it is not, a small model cannot
   leave thinking mode no matter what the docs promise.
3. **Leave `max_turns: null` on the main starter.** If DeepSeek sessions burn
   the delegation cap of 50, lower `delegation.max_iterations` on a profile
   and write down which job that profile is for.
4. **Claude / Codex / Antigravity usage section.** Add the effort commands,
   `/context` or Codex `tool_output_token_limit`, and the "set effort before
   the first turn" cache note to `docs/USAGE-ECONOMY.md`. That is a doc edit,
   not a tool.
5. **Project hook example.** One Python project, `PostToolUse` or a Hermes
   checker command, running `ruff check` on the edited file and returning
   stderr. Measure tokens before and after on a real edit. If the diagnostic
   is longer than the diff, the hook is not a saving.
6. **ty.** Re-read the beta notice before anyone puts it on PATH for the pack.
   Per-project `uvx ty check` is enough to try it.
7. **Promptfoo.** Only if question 1 needs a repeatable score. Pin a version.
   Use non-model assertions. Do not enable the red-team cloud path.

## Source list

Opened or fetched this pass:

- Hermes agent loop, loops, goals, curator, environment variables, and the
  llms full text on `hermes-agent.nousresearch.com` (pages dated through
  2026-11-06).
- Hermes starter `1-TAILORED-PROVIDER-TREES/Hermes/config.yaml` in this repo.
- DeepSeek thinking-mode guide, chat-completion reference, and pricing page
  (`api-docs.deepseek.com`, doc stamp 2026-11-05).
- Claude Code model config, hooks reference, hooks guide (`code.claude.com`,
  2026-11-06), support article 14552983 (2026-10-27), Anthropic session-value
  post (2026-08-14).
- Codex config reference, config basics, config sample, config advanced, and
  skills page (`developers.openai.com/codex`).
- Antigravity changelog, `/effort`, `/context`, `/learn`, rules, skills,
  slash-command overview (`antigravity.google/docs`, 2026-10-31 through
  2026-11-06).
- ty docs and GitHub (`docs.astral.sh/ty`, `astral-sh/ty`, MIT, beta).
- Aider lint/test, repo map, and FAQ (`aider.chat/docs`, stamp 2026-04-25).
  LICENSE not opened.
- Promptfoo README (`github.com/promptfoo/promptfoo`, MIT statement, local
  evals).
- Semgrep MCP repo README: archived 2025-10-28, server moved into the official
  binary.
- This pack: `docs/GUIDE.md`, `docs/HERMES-MODELS.md`, `docs/USAGE-ECONOMY.md`,
  `docs/TOOLING-MATRIX.md`, `docs/TOOL-EVALUATIONS.md`.

Not used as evidence: vendor benchmarks that were not re-run, secondary
pricing blogs, and the auto-compact percentage claimed outside OpenAI's
config reference.
