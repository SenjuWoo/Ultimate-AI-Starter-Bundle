# Ponytail Auto

Ponytail's mode is decided **outside the model**. A short deterministic rule set
reads the prompt, the project file and the current session, then either injects
one instruction or nothing at all. No model call is spent on the decision, and
the same prompt always gets the same answer.

Default is **OFF**. Auto only nudges a turn when its signals indicate a
narrow fix or clearly requested simplification; everything else stays silent.

## Where it can run

| Provider | Mechanism | State |
|---|---|---|
| Hermes | `pre_llm_call` shell hook, `{"context": ...}` appended to the user message | **Auto** |
| Claude Code | `UserPromptSubmit` hook, `hookSpecificOutput.additionalContext` | **Auto** |
| Codex, Grok, Kimi, Antigravity, Copilot, Cursor | no reliable prompt-time context injection | **OFF + manual** (`/ponytail lite\|full\|ultra`) |

If a provider cannot inject context before the request, it gets no hook. A hook
that silently never fires is worse than a documented manual command.

## Decision order

The selected native mode is checked first. Only `auto` reaches this decision
order; manual modes use the plugin, and `off` injects nothing.

1. **Explicit request in the prompt** — `stop ponytail`, `normal mode`,
   `ponytail off`, `/ponytail lite|full|ultra`, `be lazy`, `simplest solution`,
   `yagni`. An explicit `off` sticks for the session; so does an explicit level.
2. **This session** — an earlier explicit choice, remembered for 12 hours.
3. **`.ponytail.json`** in the project (nearest one at or above the working
   directory): `{"mode": "lite"}` pins a level, `{"auto": false}` disables
   automatic activation for that project.
4. **Classification** — see below.
5. **Default: OFF.**

`ultra` is only ever produced by an explicit request. `max` in the global
config (`%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\ponytail-auto.json`,
default `full`) caps what classification may choose.

## What classification looks for

| Signal | Result |
|---|---|
| Creative or exploratory words (story, scene, design, brainstorm, write me, logo, mood board, …) | OFF |
| Architecture, a new product, a major rework, or work from scratch | OFF |
| An open question with no artifact (`what`, `why`, `should I`, `how would you`, `fix it`, `make it better`) | OFF |
| Simplification words (simplify, refactor this, dedupe, dead code, over-engineered, reduce complexity) | FULL |
| Maintenance words plus a named artifact or path (changelog, regenerate the manifest, bump version, update the docs) | FULL |
| Fix words plus **proof of a concrete target** — a path, a file extension, `#1234`, `line 12`, a version, a code fence or a stack trace | LITE |
| Everything else | OFF |

The concrete-target test is the part that keeps this honest: "fix the typo in
README.md line 12" is a fix; "fix it" is not, and stays OFF.

## The instruction that is sent

- **LITE** — build exactly what was asked; name a smaller alternative in one
  line; shortest diff; no new abstraction; one small test for non-trivial logic;
  end with what was skipped and any risk.
- **FULL** — the full lazy-senior ruleset: scope the change, take the first
  option that fully works, never cut validation, error handling, security or
  anything the user asked for.
- **ULTRA** — FULL plus "question the request" (explicit only).
- **OFF** — nothing is sent; the model sees the prompt exactly as typed.

## Commands

```powershell
python TOOLS\hooks\ponytail_auto.py explain "fix the typo in README.md line 12"
python TOOLS\hooks\ponytail_auto.py status
python TOOLS\hooks\ponytail_auto.py self-check
python TOOLS\hooks\ponytail_auto.py wire hermes|claude|all [--remove]
```

`Install-Completeness-Gate.ps1` copies the hook to
`%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\hooks\`, runs `self-check`, and wires
every provider that supports it. A failed self-check leaves the hook unwired.

Verification that the real plumbing carries the text:

```powershell
hermes hooks test pre_llm_call          # synthetic prompt "What is the weather?" → contributes nothing
'{"prompt":"simplify the settings loader"}' | python <hooks>\ponytail_auto.py hook   # → {"context": "PONYTAIL MODE: FULL ..."}
```

`TESTS/test_ponytail_auto.py` asserts the decision corpus, the explicit and
session overrides, the project file, the ceiling, the exact text emitted per
mode, the Claude envelope, idempotent wiring and that removal leaves other hooks
untouched.

## Limits

- Keyword families, not understanding. A poetic bug report stays OFF; a terse
  "fix it" stays OFF. Both are deliberate: a wrong LITE on creative work costs
  the operator the thing they asked for.
- The decision is per turn. A task that starts as a fix and turns creative is
  not reclassified mid-task unless the prompt changes.
- Auto never edits upstream Ponytail, and never overrides an explicit command.
- The hook costs one interpreter start per turn; measure timing on the target host. It does no
  network and writes nothing but the session file.
