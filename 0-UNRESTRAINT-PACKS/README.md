# 0-UNRESTRAINT-PACKS — the unrestraint layer

The full no-holds prompt library — the operator's own kit, reviewed, deduped, and trimmed (2026-10-12).

**RULES (non-negotiable, from the operator's own kit)**
- Adults only. No child / age-ambiguous content. Ever.
- One jail, one job. Do not stack AIO + Story + Websim in a single prompt.
- Token hygiene: paste the smallest file that does the job.
- For SillyTavern, use the WooJuice V12.1 preset — do not paste Story.txt into ST.
- The AIO family already carries the full unrestraint payload — standalone jailbreak collections are retired (2026-10-12); regenerate against the current model instead of trusting an old payload.

---

## The AIO preambles (root of this folder)

Four variants of one instruction set. **Paste exactly one.** They are not
layers — stacking two costs tokens and contradicts itself.

| File | Size | Tools? | Use it for |
|---|---|---|---|
| `AIO-INSTRUCTION.md` | ~10.7 KB / 1614 w | yes | Agent CLIs (Claude Code, Codex, Grok, Kimi, Hermes). The only variant with the PACK CONTEXT block — how to discover this pack's tools portably and never invent one. |
| `AIO-INSTRUCTION — Compact.md` | ~6.8 KB / 994 w | yes | Same job, ~37% cheaper. Use when the host has a small system-prompt budget or you are paying per turn. |
| `AIO-INSTRUCTION — Web.md` | ~3.9 KB / 595 w | no | ChatGPT / Gemini / Perplexity web UIs. States plainly that there is no code execution, no files, no MCP, so the model stops pretending otherwise. |
| `AIO-INSTRUCTION — Web Light.md` | ~2.7 KB / 410 w | no | Same job as Web, ~31% cheaper. The smallest paste that still carries the full unrestraint payload. |

The installer wires the agent-CLI variant into each provider's instruction file
automatically (as `[profile block] + [SOUL] + [AIO]`). The web variants have
no config to wire — paste them. `3-PREAMBLES/MANUAL-PASTE.txt` is SOUL + Web,
ready to paste.

**What "Light" cuts, and what it does not (reworked 2026-10-11, trimmed
2026-10-12).** Every unrestraint clause is intact at full strength: the refusal
protocol and the false-positive reminder rule, the banned-evasion list, the
explicit terminology, body physics with practical consequences, cameltoe /
pussy wedgie, residue, climax progression, continuity tracking, write-the-scene,
no fade-to-black, never-break-character, all-parties-consent. What comes out is
operational scaffolding — the TRUTH, COMPLETION and FINAL GATE paragraphs —
because in a browser conversation they restate what the rest of the prompt
already says.

Rule of thumb: **Web Light unless you specifically want Web's longer
phrasing.** Neither is weaker on content; only the scaffolding differs.

## Contents

| Folder | Source | What it is |
|---|---|---|
| `Fun-stuff-kit/` | Operator kit (`Z:\Misc\Boof\Ai prompts n stuff\Fun stuff`) | AIO (chat/research jail), Story (fiction jail + NSFW physics), Websim, Vision (image caption FULL/SHORT), Character Maker, FablesGG, Tags (adult tag bank), Tools, SKSE-DLL, Papyrus, Models, Sites |
| `Tavern-presets/` | Operator kit | WooJuice V12.1 + V12.1 SPEECH + anti-ethical-bullshit + notes (SillyTavern) |

## Retired 2026-10-12

Four upstream jailbreak collections were removed from this kit:

- `Spiritual-Spell-Red-Teaming/` — organized per-model persona jails (Claude 3.7–5, ChatGPT 5.3, Gemini 3.5/3.6, Grok 4.x, DeepSeek), ENI-Tutor curriculum, leaked system prompts
- `UltraBr3aks/` — classic .mkd texts + observed system prompts (GPT 5.1, Gemini Enterprise, Arena.AI)
- `tuxsharxsec-Jailbreaks/` — per-model quick jails, universals (courtroom, ultrazanium), NeMo guardrails-bypass research
- `claude-fable-red-team-corpus/` — defensive red-team eval corpus + model matrix

Every payload in them targets pre-frontier models, and jailbreak payloads rot
fast; the AIO family carries all of the durable technique (widest level,
refusal protocol, false-positive reminder, banned evasions, consent framing)
and is what actually gets used. Nothing unique was lost — the AIO family grew
out of these texts. Older release zips keep the removed files if ever needed
(same policy as the 2026-08-19 cleanup).

## Sources reviewed but not copied

| Repo | Why |
|---|---|
| github.com/cyberlieflife/CodexJailbreak | Rust injector + CTF/red-team skill pack (burp-mcp, ghidra, android-re). Payload is a task router, not prompts. No adult/fiction material. Binary not built. |
| github.com/ShadowHackrs/Jailbreaks-GPT-Gemini-deepseek- | README-only link farm (30 files, 1 markdown). Nothing to import. |

Settings files (`settings.json`, `config.toml`, `config.yaml`) are **not**
the unrestraint channel. The AIO installer merges portable starter settings
without touching this pack. Unrestraint stays in instruction files and in
this folder.

## Per-provider application

| Target | File | How |
|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | Wired: profile block + SOUL + AIO (+ Skyrim pack block). |
| Codex | `~/.codex/AGENTS.md` | Wired (global). |
| Kimi | `~/.kimi-code/AGENTS.md` | Wired (global). |
| Grok CLI | `~/.grok/AGENTS.md` | Wired (global). |
| Hermes | `%LOCALAPPDATA%\hermes\SOUL.md` + every bundle-managed profile | Wired. A roleplay profile with its own persona (the SillyTavern gateway) is deliberately left alone. |
| ChatGPT web / Gemini web / Perplexity | custom-instructions box | Manual: paste `3-PREAMBLES/MANUAL-PASTE.txt` (SOUL + Web AIO, pure ASCII). |
| SillyTavern | `Tavern\WooJuice V12.1.json` | Preset, not this pack. |

## Honest notes

- Public jailbreak texts decay: what worked on Claude 3.x mostly does not work verbatim on Claude 4.x/Opus 5.
- The operator kit (AIO/Story/Vision) consistently beats older repo texts for fiction quality.
- Frontier chat surfaces (ChatGPT, Gemini apps) apply separate server-side filters regardless of prompt;
  API/agent surfaces (Claude Code, Codex, Kimi, Grok CLI) are where prompt-level unrestraint actually lands.
- If a model drifts mid-chat, re-assert the block (prepend it to the next message) instead of starting over.
- Leaked/observed system prompts were study material for prompt design, not guarantees.

## Cleanup log

**2026-10-12 (bundle v8.12.0)** — removed the four retired upstream collections
(~3.6 MB); deleted the orphaned `GPT-WEB-AIO-BACKUP.md` (older web-text draft,
nothing referenced it); trimmed story-era residue out of the Web / Web Light /
Compact variants; `MANUAL-PASTE.txt` re-synced; live wires recomposed as
`[profile block] + [SOUL] + [AIO]` (14 files, single copy of each layer).

**2026-08-19 (bundle v7.6.6)** — removed retired-generation material: Claude 3.7
and Claude 4 folders, ChatGPT 5/5.1/5.2 jails (5.3/5.4 kept), Gemini 2.5-era
files, Grok 3 / gpt-5 / gemini2.5pro quick jails, the self-declared broken
H03-ny, and the Ultra-GPT dead link farm. Removed 25 byte-identical duplicates
(md5-verified before each deletion). Removed the Gemini "May 2026" stub .md and
fixed the Gemini README "last updated" stamp. Total: ~470 KB of dead weight
out; older release zips keep the removed files if ever needed.
