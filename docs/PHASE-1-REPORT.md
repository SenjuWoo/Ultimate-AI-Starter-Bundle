# Phase 1 completion report

Scope: Ponytail default and control, AUTO coordination, global instruction audit,
installation end to end. Phase 2 (Matt Pocock / Addy Osmani) was not started.

## What changed

| Area | Before | After |
| --- | --- | --- |
| Ponytail default | Native mode unset -> upstream `full`; plugin hook injected on every turn | Native `defaultMode: off`; the hook skips activation, `/ponytail` and the statusline stay |
| Control | None outside each provider | `TOOLS/ponytail_mode.py status\|off\|lite\|full\|ultra\|auto\|init` |
| AUTO | Classifier ran whenever wired, ignoring the selection | Reads the selected mode first; silent unless the mode is `auto` |
| Parking | Not present | Copies parked with a path hash, never overwritten or deleted |
| Status | Claimed auto "on", "no leaks" | `selected_mode`, `would_inject`, leaks, mismatches, registered skills |
| Doctor | Would pass a leaky install | Fails when mode is `off` and any provider still loads the skills |

## Evidence

Mode matrix, run through the shipped code paths:

```
== plugin context (its own code, operator config) ==
  operator default -> 0 bytes      lite -> 2914   full -> 2859   ultra -> 2928
== hook output per mode (claude envelope) ==
  off     bugfix=0 creative=0 chat=0 research=0
  lite    bugfix=0 creative=0 chat=0 research=0
  full    bugfix=0 creative=0 chat=0 research=0
  ultra   bugfix=0 creative=0 chat=0 research=0
  auto    bugfix=482 creative=0 chat=0 research=0
  corrupt bugfix=0 creative=0 chat=0 research=0
  missing bugfix=0 creative=0 chat=0 research=0
```

- Live switching on this machine: `lite --apply` -> native `lite`, six skills restored;
  `off --apply` -> native `off`, skills parked; `status` exit 0 both times.
- AUTO corpus, 14 labelled prompts: 12 exactly as intended, the other two resolving to
  FULL for "clean up dead code" and "remove the duplicated validation", which the
  documented rule allows. Creative, game, research, chat, planning and ambiguous prompts
  all stay OFF.
- Tests: `test_ponytail_mode.py` 13, `test_ponytail_integration.py` 10,
  `test_ponytail_auto.py` 14, release contracts 175 - all passing.
- Release gate: PASS (14 checks). CI green on the released SHA, Release published with
  9 assets, Dependabot / code scanning / secret scanning open alerts: 0 / 0 / 0.
- Install: `INSTALL COMPLETE (v8.37.25)`, EXIT=0, doctor PASS, then a second install to
  prove idempotence; the Hermes `config.yaml` hash is compared before and after.

## Context cost, measured on this machine

| File | Bytes |
| --- | --- |
| `SOUL.md` (Hermes) | 22,619 |
| `CLAUDE.md` | 33,393 |
| `AGENTS.md` (Codex) | 31,171 |
| Bundle `MEMORY.md` index | 52,531 |

Ponytail contributes 0 bytes at OFF. Superpowers' startup skill is the remaining
always-on instruction; its switch and the reasoning for keeping it are in
[GLOBAL-INSTRUCTION-AUDIT.md](GLOBAL-INSTRUCTION-AUDIT.md).

## Not verified

- A live conversational turn inside Claude Code or a Hermes chat window. The evidence is
  the exact stdout those providers receive from the same hook command, plus the doctor's
  refusal to pass an install with loaded skills.
- Provider runtimes that do not offer a pre-request hook (Codex, Grok, Kimi,
  Antigravity, Copilot, Cursor) keep the manual `/ponytail` commands only; AUTO is
  documented as unavailable there rather than simulated.
- macOS/Linux paths: the installer and the mode tool were exercised on Windows only.

## Deliberately not built

No second router, classifier service, memory promoter or paid review loop. The existing
FAST/FULL gates, release gate and the deterministic classifier cover the cases found.
