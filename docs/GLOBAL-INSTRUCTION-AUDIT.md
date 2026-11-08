# Global instruction audit (Phase 1, 2026-11-08)

What is injected into every conversation on this machine, measured rather than
assumed, and what was changed or deliberately left alone. This is a read-only audit
of the operator's install; nothing here edits upstream skill text.

## What is always on

| Source | Where | Effect |
| --- | --- | --- |
| Bundle preamble / SOUL | `~/AppData/Local/hermes/SOUL.md`, `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md` | Operator authority, no self-refusal, output integrity, persona continuity. Stable, no workflow mandates. |
| Superpowers | plugin `superpowers`, enabled; `SessionStart` hook | Injects `using-superpowers`, whose text says a skill must be invoked when there is "even a 1% chance" one applies. This is upstream's design and is the main source of mandatory skill discovery before a reply. |
| Ponytail | plugin `ponytail`, enabled; native `defaultMode` | Now `off`, so its activation hook emits nothing. `/ponytail` and the statusline stay available. Verified by `TOOLS/ponytail_mode.py status` exiting 0 with no leaks. |
| Ponytail AUTO | `TOOLS/hooks/ponytail_auto.py`, wired only where a provider can inject before a request | Deterministic classifier; creative/uncertain prompts stay off. Never picks `ultra`. |

## Contradictions and duplication checked

- No forced minimalism remains: the only minimalism source was Ponytail, now off by
  default; `ponytail-auto` is opt-in and cannot choose `ultra`.
- No duplicate planner: the bundle's `writing-plans`, `executing-plans`,
  `task_state.py` and Superpowers' equivalents coexist, but Superpowers is a plugin
  and the bundle skills are `project-intel`-routed; nothing invokes both
  automatically for the same task.
- No duplicate compressor: Hermes compression is the only always-on compressor;
  Headroom is on-demand (`headroom_compress`), not an automatic second pass.
- Memory is not double-injected: the bundle ships `MEMORY.md` as a *file index* for
  the checkout, while Hermes memory lives in its own store. They answer different
  questions and neither promotes a debugging assumption into durable memory.
- Reasoning is not being starved to save tokens: the default route runs
  `reasoning_effort: high` with `max_turns: 150`; empty per-model values inherit the
  route default instead of forcing a lower effort.

## Superpowers: what was decided

Left enabled. The evidence for keeping it: its systematic-debugging, TDD,
verification and review skills are the strongest part of the install, and disabling
the plugin removes them from every provider at once. The cost is the "1% chance"
skill-discovery mandate in the startup skill, which can add a discovery step to
conversational turns.

If that cost ever outweighs the benefit, scope it without touching upstream:

```
hermes plugins disable superpowers        # Hermes only, reversible
```

and toggle the `superpowers@superpowers` entry in `~/.claude/settings.json` for
Claude Code. Both are user decisions; the bundle does not make them.

## How this was verified

The hook contract was exercised the way a provider calls it, not only through
`resolve()` in a test:

```
printf %s '{"prompt":"fix the crash in app.py line 12", ...}' \
  | python TOOLS/hooks/ponytail_auto.py hook --format claude
# OFF (this machine): 0 bytes on stdout, for both --format claude and --format hermes
```

With a temporary `LOCALAPPDATA` holding `{"mode": "auto"}`:

- narrow fix -> a `UserPromptSubmit` envelope carrying `PONYTAIL MODE: LITE`
- "design a magic system for my game" -> 0 bytes
- `status` -> `selected_mode: auto`, `would_inject: true`

On the real machine `status` reports `selected_mode: off`, `would_inject: false`,
and `hermes_hook: on`, `claude_hook: on` - the hook is installed and inert.

Not verified: a live conversational turn inside Claude Code or a Hermes chat window.
That needs a paid model turn in another app, so it was not run; the evidence above is
the exact byte stream those providers would hand the model, and the doctor refuses an
install when any provider still loads the skills.

## Not implemented, deliberately

- No second router, gate, classifier or memory promoter. The existing FAST/FULL
  verification and release gate already cover the failure modes this pass looked at.
- No automatic mode selection for Ponytail beyond the deterministic hook. A paid
  classification call per prompt was rejected on cost.
- No modification of Superpowers skill text, so upstream updates stay mergeable.
