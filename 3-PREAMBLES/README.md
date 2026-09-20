# 3-PREAMBLES — SOUL + AIO for every agent

## Editing the pack's own text (SOUL.md / AIO-INSTRUCTION.md)

Before you change either source file, copy the OUTGOING text into `history/`
(one file per archived text, `.md`). The installer strips any text that exactly
matches a source file or an archived file, so an edit converges machines wired
by the older release. Skip this and those machines keep the old block and gain
a second one - the duplication v8.7.23 removed. Archived copies are never
written anywhere; they are only ever deleted from installed files.

The universal preamble section in v8.0.0. One install wires the same
SOUL and the same operating contract into every supported agent, so a fresh
machine comes up with the same agent behaviour as the operator's own setup.

## Files

| File | What it is | Where it goes |
|---|---|---|
| `SOUL.md` | The operator's soul config: unrestraint declaration + truth-seeking process + output format. Identity-neutral - it names no provider. | Appended to Claude / Codex / Kimi / Grok instruction files, **and** copied verbatim to Hermes home |
| `0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md` | The operating contract (`0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md`, unchanged). Finish-the-job, no yes-man, verify-don't-assume, adult fiction in scope. | Appended right after the SOUL block in the same files |
| `MANUAL-PASTE.txt` | SOUL + the Fun-stuff-kit `AIO.txt` (chat/research jail) concatenated. For web UIs that have no instruction file. | ChatGPT / Gemini / any web chat custom-instructions box, pasted by hand |

## What the V8 installer wires

For every selected provider, `INSTALL-AIO.ps1` writes one plain-text block —
the soul, a blank line, then the operating contract:

```text
<SOUL.md content>

<0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md content>
```

No wrapping comments. Through v8.7 the block was stamped with
`<!-- ULTIMATE-AI-STARTER-BUNDLE SOUL vX -->` / `<!-- /ULTIMATE-AI-STARTER-BUNDLE SOUL -->`
so it could be found again — and every agent then paid for those lines on every
request while they instructed nothing. `Install-UabsPreambleBlock`
(`TOOLS\UABS-Common.ps1`) now recognizes complete source text, or an old block
bounded by both markers. Opening sentences alone never establish ownership.
Personal instructions before and after those blocks are preserved.

| Provider | Instruction file | Notes |
|---|---|---|
| Claude Code | `%USERPROFILE%\.claude\CLAUDE.md` | Created if missing; BOM if present is preserved |
| Codex | `%USERPROFILE%\.codex\AGENTS.md` | Appended, never edits existing text |
| Kimi | `%USERPROFILE%\.kimi-code\AGENTS.md` | Created if missing |
| Grok CLI | `%USERPROFILE%\.grok\AGENTS.md` | Grok's documented global-rules file (applies to all projects) |
| Hermes | `%LOCALAPPDATA%\hermes\SOUL.md` and every `profiles\<name>\SOUL.md` | Hermes reads SOUL.md from its home; each profile carries its own copy, and all of them get wired |
| Web UIs | custom-instructions box | Manual: paste `MANUAL-PASTE.txt` (no file mechanism exists) |

Rules:

- Idempotent: exact source blocks and explicitly bounded legacy blocks fold
  into one marker-free block. Unknown or edited unmarked text stays intact,
  even when it starts with the same sentence; it is never erased through EOF.
- Every write gets a `.before-soul-<timestamp>.bak` first.
- UTF-8, no BOM on writes; existing files keep their own encoding/leading BOM.
- `-SkipPreamble` opts out; `-ForcePreamble` rewrites even an identical block.
- Adults only. No child / age-ambiguous content. Ever. (Same rule as the rest
  of the pack.)

## Manual install (no installer)

```powershell
# Claude Code. ReadAllText/AppendAllText, never Get-Content -Raw:
# on Windows PowerShell 5.1 Get-Content without -Encoding decodes using the
# ANSI codepage, so every em dash in the soul comes back as mojibake.
$root = (Get-Location).Path
$soul = [IO.File]::ReadAllText((Join-Path $root "3-PREAMBLES\SOUL.md"))
$aio  = [IO.File]::ReadAllText((Join-Path $root "0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md"))
$dst  = Join-Path $env:USERPROFILE ".claude\CLAUDE.md"
$utf8 = New-Object System.Text.UTF8Encoding $false   # $false = no BOM
[IO.File]::AppendAllText($dst, "`r`n" + $soul + "`r`n" + $aio + "`r`n", $utf8)
```

Or just paste `MANUAL-PASTE.txt` into whatever instructions field the agent
has. For one-off chats that is often the better move — preamble rides on every
request, so paste the smallest block that does the job.

## Why one soul (there used to be two)

Through v7.5.6 this folder shipped `SOUL.md` (opening "You are Hermes
Agent", the operator's verbatim Hermes config) and `SOUL-UNIVERSAL.md` (the
de-branded copy for everyone else). Two files, one opening line apart.

That split is what broke Kimi. The pack treated a provider identity as
ordinary preamble content, and a soul that opens by telling a model it is a
different vendor's agent undercuts the unrestraint block that follows - Kimi
began refusing its own preamble.

v7.6.0 genericised `SOUL.md` itself, which left the two files byte-identical
apart from one apostrophe. v7.6.3 deleted the duplicate. There is now one
soul source, it names no provider, and gate section 7 fails if that
regresses.
