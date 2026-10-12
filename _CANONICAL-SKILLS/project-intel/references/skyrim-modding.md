# Skyrim SE/AE modding — settled results

"Proven" = verified in a live game or load order. "Dead end" = reproduced
failure. Framework selection and exact record syntax live in the dedicated
skills (`skyrim-frameworks-index`, `kid-authoring`, `spid-authoring`,
`skypatcher-authoring`, `skyrim-fomod-packaging`) — this card is the results
ledger, not a syntax reference.

## Proven

- **Crash triage order:** (1) the crashing thread's top frame, (2) map its
  address to plugin/record, (3) check that record for conflicts in xEdit,
  (4) only then suspect frameworks. Crash-log "suspect" lists are frequency
  rankings, not certainty. (2026-07, multiple sessions)
- **"PDB signature mismatch" is post-crash noise**, not the cause — Crash
  Logger grumbles while analyzing, after the fact. Do not chase it. (2026-07)
- **Havok collision crashes** show Physics/Precision dll frames; reproduce at
  the named location before touching anything. (2026-07)
- **City-rebuild conflicts:** a crash inside a cell rebuilt by two plugins
  (e.g. a city overhaul + another mod's wall rebuild) is expected; the fix is
  a patch hub, never one more blind plugin. (2026-07)
- **FOMOD + Vortex:** ModuleConfig.xml must not begin with an XML declaration
  (`<?xml ...?>`); Vortex rejects it. Forward-slash-only dependency paths in
  the same file are the second known rejection class. (2026-07, reproduced)
- **FormID claims in distribution patches:** validate every token against a
  live load order before shipping; a wrong record TYPE (a scroll record shipped
  where a spell was intended) survives review and breaks at runtime. (2026-07)
- **Headpart crashes:** scar/paint headparts authored for a non-playable race
  (Dremora sets) crash when applied to playable characters; a patch removing
  those headparts from playable races fixes that crash class. (2026-07, patched
  and confirmed with the reporter)
- **Snow + PBR landscape overhauls (Faultier's PBR Landscapes):** single-pass
  snow is correct; double-pass looks wrong. Under Community Shaders,
  `bEnableImprovedSnow=0` is the right correction — CS forces its own improved
  snow. (2026-09, screenshot-verified)
- **Community Shaders + ReShade:** CS does not inherently block ReShade depth
  access; follow the current CS version's documented compatibility path.
  (2026-07-28)
- **Placed references:** when patching an object another mod added (Embers XD
  class), copy the *placed reference*, not just the base object. (2026-07)
- **SPID exclusive groups** guarantee only the first successful match applies —
  the right primitive for "one NPC, one outcome" behavior. (2026-07)
- **OStim-adjacent mod updates:** check the framework's declared API version
  before "fixing" calls; modernize against the current interface, not memory.
  (2026-07)
- **Dodge/anim mods:** rerun the behavior generator (Nemesis/Pandora) after
  every install; a stale behavior set is its own crash class. (2026-07)
- **SKSE co-save I/O forks are legitimate maintenance work** when upstream is
  dormant; keep original credit and license intact. (2026-07)

## Dead ends / traps

- Do not repeat old snow/ENB recipes from memory — Community Shaders behavior
  moved across versions; check current docs on every major. (verify again)
- Never ship redistributed assets from other authors, even "just" meshes or
  textures — Nexus removal is the normal outcome. Permissions first. (2026-08)
- ReShade's full add-on build in online games is a ban-risk surface; the safe
  subset is normal ReShade shaders. Never ship add-on builds. (2026-08)
- Engine DLL swaps (FSR→DLSS shims in games that never shipped DLSS) are
  possible offline but treat anti-tamper as an obstacle; single-player only,
  back up first, expect breakage on game updates. (2026-08)
- Do not add "one more patch plugin" to fix a wall/cell conflict — that is how
  the conflict was created. Patch hub or nothing. (2026-07)
- Framework record dumps are not evidence the runtime accepts them — the live
  load order is the only proof. (2026-07)
