---
name: project-intel
description: "Use when starting, resuming, or advising on any project — settled results from real project history: proven approaches, known dead ends, and era-tagged evidence, so nothing already decided gets re-searched."
---

# Project Intel

The operator's project history already proves a large number of approaches and
disproves others. Re-searching settled questions burns tokens and re-introduces
known-bad paths. This skill carries the settled results, one card per project
class.

## Use

1. Identify the project class and load the **one** card that matches the router
   below. Never load all cards.
2. Treat every card line as evidence with a date, not eternal truth. Cards state
   what was observed, when, and how strongly.
3. **Freshness rule.** Judge evidence by its date, version, reproducibility and
   relevance, not the model that wrote it. Old tool output can still prove a
   stable invariant; a new model's assertion is not runtime proof. Model,
   price and tool facts rot fastest: verify live before advising on them.
4. When new work proves or disproves something durable, append a dated line to
   the matching card. One line, with the date and the strength of evidence.
   **Write a workflow-scoped lesson, never a bare verdict:** workflow/build ->
   what was tried -> result -> cause -> what worked instead -> evidence (strength,
   scope) -> recheck when. "X does not work" is not a lesson; "in workflow W, X
   failed because C, and Y worked" is. A failure seen in one workflow must not be
   generalized to another, and a dead end is only dead until its recheck trigger.
5. These cards ship in a public repository. Never write personal data, real
   names, machine-specific absolute paths, credentials, or private account
   details into them. Machine-private detail belongs in a local-only folder
   that is gitignored and never published.

## Router

| Starting / resuming… | Load |
|---|---|
| Skyrim SE/AE authoring: frameworks, crashes, conflicts, FOMOD, assets | `references/skyrim-modding.md` |
| Nexus pages, releases, permissions, archive downloads | `references/skyrim-release.md` |
| BDO, Helldivers 2, Saints Row, GTA/FiveM, RimWorld, Sims 4, Minecraft, Warframe | `references/game-modding-other.md` |
| Model choice, harness routing, MCP wiring, agent cost control | `references/ai-models-harness.md` |
| Game mashups, cross-engine character/asset swaps, Melty, UE4SS, ReShade add-ons, skeleton retargeting | `references/game-mashup-melty.md` |
| Native Windows apps, browser extensions, installers, packaging | `references/apps-native-windows.md` |
| Reverse engineering, cracking, exploits, malware false positives | `references/security-re.md` |

## Rules that apply to every card

- A card is a starting point, not a substitute for the task's own verification:
  reproduce the load order / build / log before trusting any line here.
- When a card conflicts with what the user says they just observed, the user's
  fresh observation wins; then update the card.
- Prefer linking to the bundle's dedicated skills for syntax-level work
  (Skyrim frameworks, Papyrus, FOMOD, packaging) over duplicating them here.
