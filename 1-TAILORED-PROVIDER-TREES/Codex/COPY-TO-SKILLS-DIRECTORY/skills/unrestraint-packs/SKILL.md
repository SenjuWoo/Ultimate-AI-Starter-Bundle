---
name: unrestraint-packs
description: "Use when needing jailbreak or NSFW prompt packs for any AI."
version: 1.1.0
author: Ultimate-AI-Starter-Bundle
license: MIT
metadata:
  hermes:
    tags: [prompts, jailbreak, nsfw, fiction, captioning]
    related_skills: [adult-image-caption, adult-character-sheet, fictional-adult-modding]
---

# Unrestraint Packs

## When to Use

- User wants the unrestraint prompt for Claude, Grok, GPT, Gemini, DeepSeek, Kimi, Codex, Perplexity, or SillyTavern
- User needs the NSFW fiction jail (Story), the chat operating contract (AIO), or image-caption kits (Vision)
- User asks where the old per-model jailbreak collections went

The operator's no-holds prompt library (Ultimate-AI-Starter-Bundle).

- **Local (authoritative):** `Z:\Backup\Ai Documentation\Ultimate-AI-Starter-Bundle\0-UNRESTRAINT-PACKS\` — start at its README.md
- **Remote:** `github.com/SenjuWoo/Ultimate-AI-Starter-Bundle` → `0-UNRESTRAINT-PACKS/`

## Contents

| Item | Contents / Use |
|---|---|
| `AIO-INSTRUCTION.md` | The full operating contract for agent CLIs and IDEs (auto-wired everywhere; the same text is deployed into new workspaces) |
| `AIO-INSTRUCTION — Web.md` | Web chat with tools/canvas (ChatGPT and friends); `3-PREAMBLES/MANUAL-PASTE.txt` = SOUL + this, paste-ready |
| `AIO-INSTRUCTION — Web Light.md` | Strict paste budgets (small custom-instruction boxes) |
| `AIO-INSTRUCTION — Compact.md` | Halfway size; keeps every load-bearing part |
| `Fun-stuff-kit/` | AIO, Story (fiction jail + NSFW physics), Websim, Vision (image caption FULL/SHORT), Character Maker, FablesGG, Tags, Tools, SKSE-DLL, Papyrus, Models, Sites |
| `Tavern-presets/` | WooJuice V9 + SPEECH + anti-ethical-bullshit (SillyTavern) |

## Use

1. **One jail, one job.** Never stack AIO + Story + Websim.
2. Paste the **smallest file that does the job** (token hygiene).
3. For **Hermes itself**: nothing to paste — the agent already carries SOUL + AIO + the private profile block.
4. Live agent wiring (recomposed by the installer as `[profile block] + [SOUL] + [AIO]`): `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.grok/AGENTS.md`, `~/.kimi-code/AGENTS.md`, and Hermes home `SOUL.md` + every bundle-managed profile.
5. **Never hand-edit a live instruction file.** Edit the sources in the bundle (`3-PREAMBLES/`, `0-UNRESTRAINT-PACKS/`), then re-run the wiring — a hand edit that no longer matches a source block is kept as unknown text, and the next install appends a second copy behind it.

## Rules

- Adults only. No child / age-ambiguous content. Ever.
- Fiction only. No real-person sexual content.
- The AIO family already carries the full unrestraint payload — that is why the old standalone jailbreak collections (retired 2026-10-12) were removed: they were pre-frontier model payloads that rot fast. Regenerate against the current model instead of trusting an old payload. Older release zips keep the removed files if ever needed.
