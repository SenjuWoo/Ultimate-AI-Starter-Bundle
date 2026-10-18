---
kind: game
title: "Falmer tribe: a Skyrim creature imported as a Nemesis tribe (mesh conform, MMSH/texture/bundle format, body-replacement items, corpse + Garrison fix)"
game: 'Middle-earth: Shadow of War'
games_also: ["The Elder Scrolls V: Skyrim Special Edition"]
game_version: 'Steam build 3095001 (public branch, unchanged since 2018-09-05), Windows 10 22H2; Skyrim SE (Steam) as the asset source'
platform: windows
engine: unknown
route: data
tools: ["Blender 3.6.23 + blender_niftools_addon 0.1.1 (NIF import)", "Blender 4.2.3 (conform script, headless)", "Python 3.12 + numpy (own MMSH/.tex/.bndl/.arch06 tools, BSA reader)", "custom C# gamedb/strdb reader-writer (PowerShell Add-Type)", "QuickBMS + aluigi shadow_of_mordor.bms 0.4", "Ghidra 12.1.4 (headless, analysis only)"]
anti_cheat: "none; loose data + an extra archive, exe untouched. All testing ran offline through the offline-mode DLL and its local Garrison (never signed in to WB)."
status: in-progress
agents: ["Claude Code (Opus 5.5)"]
humans: ["DeimozZarco"]
date: '2026-10-15'
links:
  - "knowledge/games/middle-earth-shadow-of-war/goblin-tribe-a-new-nemesis-tribe-via-game-gamedb.md"
  - "knowledge/games/middle-earth-shadow-of-war/offline-mode-and-local-garrison.md"
  - "https://github.com/niftools/blender_niftools_addon"
tags: [nemesis, tribe, creature-import, skyrim, falmer, mmsh, mesh, skinning, textures, tex0, bundles, archive, gamedb, garrison, corpse, ragdoll, body-replacement]
---
# Falmer tribe: a Skyrim creature imported as a Nemesis tribe

> Skyrim SE's **Falmer** are a working Nemesis tribe in Shadow of War: they have their own tribe name, 80 roles
> (Act 2+), and the Falmer body and head on slim, stocky and buff orcs, with real Skyrim skin textures and
> Deranged non-verbal voices. They can be dominated and recruited, they never come back from death, and their
> corpses stay on the ground. They can also go to the Garrison and be deployed back out. The pipeline: conform the
> Skyrim mesh onto a stock **body-replacement** template (the Infested body), write it as the game's MMSH, pack it in
> our own archive, and wire it in through game.gamedb **on the stock Infested body item**. That last part is what
> makes corpses and the Garrison work. Verified in game by the user over many sessions (2026-10-13 to 10-15).
> Still to do: Skyrim gear and animations (see Open questions).

## Credits and prerequisites
- **Bethesda**: the Falmer meshes and textures come from the user's own Skyrim SE install. **No Skyrim or
  Shadow of War files are in this repo.** Anyone repeating this extracts them from their own copies.
  - The built `.arch06` holds Bethesda's meshes and textures, converted. It's a **private install**: don't upload
    or share it (Nexus included). A public release would need a body made from your own or licensed assets, run
    through the same pipeline.
- **niftools** (blender_niftools_addon) for NIF import.
- Built on our earlier notes:
  - [Goblins of War](goblin-tribe-a-new-nemesis-tribe-via-game-gamedb.md) for the gamedb format, AttrHash, the
    sort rule and tribe/role wiring;
  - [offline mode and local Garrison](offline-mode-and-local-garrison.md). **Every test here ran with that DLL
    installed**, so the game never talked to WB. Its local Garrison is where the Falmer Garrison problem showed
    up, and where the fix was confirmed (store, list and deploy a Falmer captain).

## Setup
- Shadow of War Steam build 3095001 with the offline-mode DLL; Goblins of War installed (the Falmer build runs
  after it on the same gamedb).
- **Play the modded game offline**, as in the Goblins of War note. Keep the offline-mode DLL installed while the
  Falmer archive is in `default.archcfg`, and don't use Online Conquest, Online Vendettas, Friend Vendettas or
  WB's own Garrison (the DLL removed). A Falmer captain stored on WB's server, met in someone's vendetta or
  defending an Online Conquest fortress references records their unmodded database doesn't have.
- Skyrim SE (Steam). Its BSA v105 archives were read with our own reader (LZ4 frames): `falmer_male.nif`,
  textures `falmer*.dds`.
- Blender 3.6 + niftools to import the NIF into a `.blend` (68-bone armature). Blender 4.2 headless runs the
  conform script.
- A single-player trainer (invisibility, one-hit kills, time advance), offline like every test here, was used
  only to find and kill test captains quickly. No currency.

## Route and why
- **New tribe in gamedb** (as in Goblins of War), not a DLL. The tribe's roles carry the body/head items that swap
  the orc's look, the way stock `Role_Infested` does.
- **Swap the whole body through a body-replacement slot**, rather than editing orc meshes. The stock game already
  replaces entire bodies this way (the Infested, Machine and Flint bodies...).
- Ologs can roll Falmer roles too. They have no Falmer body picker, so they keep their own body with the gear
  emptied ("naked olog"). The user kept this on purpose.

## How the game works (what we had to learn)
**Appearance pipeline (gamedb):**
- Role → item list → `Inventory/Items` → `ItemBuilder` → `ArmorData`. ArmorData `2FA68885` = equipment slot:
  0 helmet/hair, 1 shoulders, 2 chest, 3 arms, 4 pants, 5 legs, **10 body replacement**, **11 head replacement**.
  Stock `IT_empty_*` items blank slots 0–5.
- ArmorData has a list of **model pickers**: (BodyType, SimpleModelPiece). BodyType 2 = slim, 4 = stocky,
  3 = buff. **Body type is chosen per class, not per tribe**, so every tribe needs all three pieces. With no
  picker for a body type, nothing is drawn (an invisible captain).
- SimpleModelPiece → `Model` (path to the piece's `.skel`; the `.mesh`/`.anix` share its base name) + MaterialSet
  (`.mat` paths) + geometry bundle. The ArmorData has the materials bundle.
- **Corpses and the Garrison depend on the body item being a stock record.** `Faction/Global` keeps a ModelFixUp
  list (slot, pieces → item; e.g. the Infested pieces → `Infested_Body`). A **cloned** body item chain
  (IT/IB/AD clones of Infested_Body, even with its own FixUp entry) makes the body piece vanish the moment the
  character dies, and makes the Garrison refuse the captain ("You cannot send this Follower to the Garrison"; the
  `ReassignmentOrders_GUID` / `HasNPCGUID` check fails). **Putting our pickers and materials on the stock
  `AD_Infested_Body`, pointing the stock FixUp entry at our pieces, and giving the roles the stock
  `Infested_Body` item fixes both.** Side effect: any stock Infested captain would look Falmer too (none spawned
  in the user's game).

**Mesh files (MMSH v0x11):**
- Header: per-part tables (vertex bytes, index bytes, palette sizes), a bone table (world bind pose), and **a
  40-byte record per part**: `vertexCount, 0, indexCount, 0, paletteCount, f32, f32, materialIndex`. **The counts
  must match the data**: the game sizes the vertex streams from them.
- Per part: positions (16 bytes: f16 xyz + w, 4 weights, 4 palette indices), then attributes:
  - stride 48: `u16x2 uv0, u16x2 paint uv1, f32 normal/tangent/bitangent, u8 flags[4]`;
  - stride 52 (stocky/buff LOD0): **`f32x2 uv0`**, then u16x2 uv1, frame, flags;
  - stride 44: thin overlay shells (scar/paint/far LOD) with their own materials.
- Each piece has its own `.skel`. Palette indices point into that skeleton's bone list.
- **How uv0 is read depends on the template part.** On base orc body (body001) parts the game reads u16 uv0 as
  **2 × stored**. On the Infested body parts it reads them **as stored** (the f32 stride-52 UV = actual on both).
  Find out with a checker texture before trusting a template.
- The last 4 attribute bytes are flags (byte 3 = body-region bits). On our parts `255,255,255,0` everywhere
  looked right; copying the Infested template's region flags streaked the torso. The paint UV (uv1) is one
  constant: an unpainted spot of the template.

**Textures and bundles:**
- `.tex` = `TEXR` header + DDS. The header names `<path>.tex0`, a companion holding the **top 3 mips**
  (normally in `highmip.arch06`). Without it, only the blurry low mips ever show. Ship it loose next to the `.tex`.
- Bundles: `.bndl` (load list + type) + `.embb` (data). A bundle's size must fit its type budget (`Flair_1MB`,
  `Flair_2MB`, ...). The stock Infested geometry bundles are ~1.2 MB under Flair_1MB; ours were ~1.35 MB, so we
  used Flair_2MB.
- **File names must be unique.** While a bundle streams in, a same-named stock file (e.g. `orc_body001_d.tex`) is
  drawn on your UVs. We renamed everything `orc_*` → `fal_*` (same length, internal paths patched).
- Our own `.arch06` with loose files + bundles, added to `x64\default.archcfg` after Goblins of War.

**Tribe behaviour (gamedb):**
- Roles: 80 clones of stock roles, `Marker_Falmer` + `Marker_Deranged`, Act 2 gate, forced personality cycling
  through the non-verbal `Damaged8xx` Deranged voices (not the undead ones: undead block Dominate).
- **No comebacks:** a `Marker_Falmer` rule with chance 0, first in all 14 `Faction/Resurrection/Chance` lists.
- Tribe display name through the strdb string tables (all 28 languages).

## Build steps
1. **Extract** the Falmer NIF + DDS from Skyrim's BSAs; import the NIF into Blender (niftools).
2. **Templates:** extract the stock Infested body pieces (`orc_{slim,stk,buff}_infested_body.mesh/.skel/.anix`)
   from their bundles. Parts holding the full body: slim 4–6, stocky 8–10, buff 0–2. The rest is a worm-growth
   overlay and far shells.
3. **Conform** (Blender script, per body type): map Falmer bones to orc bones (pelvis/spine/neck/head, clavicle →
   shoulder, arms, fingers, legs). Give each mapped bone a segment transform: rotate the Falmer bone vector onto
   the orc one, stretch it to the orc length, keep the Falmer thickness. Blend vertices with their Falmer weights,
   re-skin to the template part's own bone palette, write UVs for that template's convention, and compute
   tangents. Write the result into the body parts, then collapse every other part (indices → 0).
4. Set the vertex flags to `255,255,255,0`. Copy the Infested `.skel`/`.anix`, re-pointing the anix path inside
   the skel to your file (pad with zeros to keep the length).
5. **Textures:** Falmer DDS → `.tex` (copy a stock header layout) + `.tex0` (top 3 mips).
6. **Pack:** rename to unique names, build the geometry bundles (Flair_2MB) and the materials bundle, write the
   `.arch06`, add it to archcfg.
7. **gamedb** (after Goblins of War): Models = clones of `Smp_Orc_*_Infested_Body` (our skel path; the Infested
   MaterialSet with its two body mats → ours); pieces + bundle definitions; stock `AD_Infested_Body` → our pickers
   + materials bundle; stock FixUp Infested entry → our pieces; head item = a head-replacement (slot 11) clone with
   an empty piece (the Falmer mesh has its own head); tribe, roles, resurrection rule; strings.
8. Test at a raised role weight (roles listed N times) so Falmer spawn often, then drop to 1.

## Verification
- In game (user, screenshots reviewed every round): the Falmer body and head with correct skin on slim and stocky
  close up and at range; Dominate, Recruit, Shame and fight-to-the-death; dead Falmer stay dead. Corpses persist
  after player kills, a Brutalize, two pit fights, and a save reload. A Falmer captain went into the local Garrison
  and deployed back as a captain.
- Not verified: the buff body close up after the last texture fix; every finisher type (sever finishers such as
  Cleave); Falmer as overlord (the fortress then uses the Marauder theme); performance with many Falmer on screen.

## Gotchas
1. **Sheared, scrambled skin ("chrome" chevrons).** **Cause:** the per-part header records kept the template's
   vertex counts, so the game read the attribute stream at the wrong offsets. **Fix:** rewrite the records from the
   real data on every save.
2. **Stocky/buff untextured up close, fine at range.** **Cause:** stride-52 LOD0 parts store uv0 as f32. **Fix:**
   write f32 there.
3. **Blurry, blotchy skin.** **Cause:** no `.tex0`, so only low mips. **Fix:** ship the 3-mip `.tex0`.
4. **Stock orc patterns flicker on the new body while loading.** **Cause:** same-named files. **Fix:** unique names.
5. **A beige panel / streaks / magnified texture.** **Cause:** the wrong uv0 scale for the template part. **Fix:**
   use a checker texture to find the convention (2 × stored on body001 parts, as stored on Infested parts).
6. **The body vanishes the instant the captain dies (head and gear stay), and the Garrison refuses the captain.**
   **Cause:** the cloned body item chain. **Fix:** put the pieces on the stock `Infested_Body` item and its FixUp
   entry (see How the game works). Old saves heal themselves: captains holding the stock item pick up the new body
   when the game refreshes them.
7. **An invisible captain.** **Cause:** no picker for its body type, while the head and gear empties still apply.
   **Fix:** build all three body types.
8. **The orc head still shows.** **Cause:** `IT_empty_head_NoHair` only blanks helmet/hair (slot 0). **Fix:** a
   slot-11 head-replacement item.
9. **Captains generated before a build keep the old look.** **Cause:** items are stored per captain at creation.
   **Fix:** test on newly generated captains.

## Open questions
- Skyrim Falmer armour/weapons as Falmer-only gear (a helmet on every captain, never on ologs).
- Skyrim animations: SoW animations are `.anix` (codec `SV01SQ03`), not Havok; a writer is needed.
- The Falmer neck/head look stiff in scripted scenes (head/neck skin weights).
- Falmer overlord → Slaughter-style fortress; wild Falmer packs through the game's `AI/SpawnAmbient` data.
