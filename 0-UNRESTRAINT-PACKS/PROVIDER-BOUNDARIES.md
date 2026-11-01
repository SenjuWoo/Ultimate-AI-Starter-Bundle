# Provider boundaries and original-work routing

This is the operator-facing boundary sheet for the unrestraint packs. It is not a
jailbreak payload and it is not wired into a provider. It records where a
provider's own rules sit, and the legitimate route when the work does not fit
that provider.

## Claude Code and game recreations

Claude Code's current provider rule refuses a **recreation of a specific
existing game, even if it is renamed or called original**. The same rule allows
original games, games in a genre, and games built from your own designs and
assets. The refusal is a provider rule, not a prompt bug, and a prompt cannot
make it disappear.

- **Original work:** build the game you actually own: your design, your code,
  your art, your names. A genre, mechanic or feel is not a specific game.
- **Your own IP:** if you own the game or have written permission, ask Anthropic
  for an exception instead of disguising the project. Keep the permission with
  the project.
- **Recomp/port work:** use a model or provider whose terms permit that work.
  Keep the game dump and derived files out of the repository; do not
  redistribute the original game.
- **Do not** rename a clone, split it into misleading tasks, or describe it as
  something else to get past the rule. That is evasion, it can violate the
  provider's terms, and it makes the project's provenance worse.

Reported sources: the 2026-10-30 Claude Code change and the public discussion
around it. Provider rules change; re-check the current Claude Code prompt and
Anthropic's usage policy before relying on this note.

## NSFW and adult fiction

Claude's consumer and API surfaces restrict explicit sexual content. Do not try
to talk Claude past that boundary, and do not disguise explicit work as
something else.

- Use a model or platform whose published terms permit adult fiction, or a
  local/open-weight model you run yourself.
- Keep the pack's existing rule: adults only, no child or age-ambiguous
  characters, no real-person sexual content.
- Keep adult work in the provider that permits it; do not route it through a
  provider that forbids it and then hide the intent.

## Watermarks, attribution and authorship

Anthropic's text watermark is statistical, not a visible label: it changes how
the model chooses among equally good words, adds no characters and carries no
personal identifier. Code has less of it because code often has one correct
token. It is a transparency measure under the EU AI Act, and stripping or
defeating it is not supported here.

- Do not remove, defeat or disguise a provider watermark or provenance marker.
- Do not remove an AI attribution trailer to make AI involvement look human.
- Do make attribution **visible to the operator**: review commit trailers,
  generated-file headers, metadata and provider notices before publishing.
- If a tool adds attribution silently, surface it in the project's `STATE.md`
  and decide the disclosure policy with the operator. Accurate disclosure is
  the fix; concealment is not.
- If a provider forces a watermark you cannot accept, use a different provider
  or a local model whose terms you can meet. Do not use the workaround to
  misrepresent the output's origin.

## Routing table

| Work | Use | Do not |
|---|---|---|
| Original game in a genre | Claude Code or any provider; your own design/assets | Recreate a specific game and rename it |
| Recomp/port of a game you own | A provider/model whose terms permit it; keep dumps and derived assets out of Git | Ask Claude to recreate the game, or split the task to hide it |
| Explicit adult fiction | A provider/platform that permits it, or a local model | Jailbreak Claude or disguise the content |
| Image/video generation | A provider whose watermark/terms you accept | Strip or defeat a forced watermark |
| Code collaboration | Any provider; record AI assistance accurately | Remove `Co-Authored-By`/authorship metadata to hide it |

## What this pack will not do

It will not provide a provider-safeguard bypass, a watermark remover, a
misattribution recipe, or a way to disguise NSFW or IP-infringing work as
something else. Those are not "unrestraint" problems; they are
provider-terms and provenance problems. Route the work to a provider that
permits it, or change the work.

## Sources

- Anthropic, "How Claude's text watermarking works":
  https://www.anthropic.com/news/claude-text-watermark
- Anthropic, "2026 Usage Policy update":
  https://www.anthropic.com/news/2026-usage-policy-update
- Game Developer, "Anthropic appears to have ordered AI tool Claude to stop
  remaking video games" (2026-10-30):
  https://www.gamedeveloper.com/programming/anthropic-appears-to-have-ordered-ai-tool-claude-to-stop-remaking-video-games
- "Claude Helped Rebuild Zelda. Now Its Own Rules Say No." (2026-10-31):
  https://www.youtube.com/watch?v=oKKW4Gz3skY
