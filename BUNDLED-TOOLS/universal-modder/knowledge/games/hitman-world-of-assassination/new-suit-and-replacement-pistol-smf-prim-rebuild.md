---
kind: game
title: "A new selectable suit and a replacement default pistol from custom meshes (SMF, rpkg PRIM rebuild)"
game: "HITMAN World of Assassination"
games_also: []
game_version: "Steam PC, HITMAN3.exe from the 2026-08-27 patch (app 1659040)"
platform: windows
engine: unknown
route: data
tools: ["Simple Mod Framework 2.33.42", "rpkg-cli 2.34.0", "HMTextureTools (bundled with SMF)", "GlacierKit 1.12.15", "Peacock 8.9.1", "Blender 5.2", "io_scene_glacier 0.7.2 (reference only)", "fal (trellis-2, hi3d multi-view)", "um win"]
anti_cheat: "none in offline play; tested only under Peacock (offline server)"
status: working
agents: ["Claude Code (Opus 5.5)"]
humans: ["@skurtyyskirts"]
date: 2026-10-10
links: ["https://github.com/atampy25/simple-mod-framework", "https://github.com/glacier-modding/RPKG-Tool", "https://github.com/atampy25/glacierkit", "https://github.com/thepeacockproject/Peacock", "https://github.com/glacier-modding/io_scene_glacier"]
tags: ["glacier-2", "smf", "quickentity", "prim", "rpkg", "textures", "materials", "outfit", "weapons", "peacock"]
---

# A new selectable suit and a replacement default pistol from custom meshes (SMF, rpkg PRIM rebuild)

An SMF content mod for HITMAN World of Assassination adds a new selectable female character suit and replaces
the default concealed pistol (the ICA19) with a custom model. The suit appears in planning with its own image,
renders in missions with its head, hair and clothes, and keeps IOI's facial rig. The pistol equips, aims and fires,
and shows its own name, planning image and HUD icon. Both were checked in game under Peacock (Paris, The
Showstopper). Most of the work was making rpkg-rebuilt PRIMs, textures and materials stop crashing or rendering
black. This note is the list of repairs.

## Setup
- HITMAN WoA, Steam, Windows 11, the 2026-08-27 patch. **SMF 2.33.42** (older SMF says "Unknown game version"),
  **Peacock 8.9.1**, **rpkg-cli 2.34.0**, HMTextureTools from SMF, GlacierKit 1.12.15, Blender 5.2.
- Peacock reads SMF's `deploySummary.json` only at startup: deploy, restart Peacock, then launch.
- **Offline only.** Everything here was tested under Peacock and never against IOI's servers, which hold the
  online profile, inventory and progression. Play the modded install under Peacock only.

## Route and why
`data` through SMF: `.entity.json` / `.entity.patch.json` (QuickEntity), `.repository.json`,
`.unlockables.json`, `.JSON.patch.json` (ORES), and raw `<hash>.<TYPE>` + `.meta` resources for meshes,
textures and materials. No code. Meshes go: model → Blender → GLB with the vanilla PRIM's object names →
`rpkg-cli -rebuild_prim_in` → our repair pass → a new hash, with the meta retargeted to the new material.

## How the game works (what we had to learn)
### A new suit
- A charset (Actor, HeroA, Nude; only HeroA filled), plus a `ZGlobalOutfitKit` patched into globaldata, plus
  repository + unlockables entries, plus an ORES patch adding the token to `PACKAGE_STARTING_PACKAGE`. The suit
  shows in planning with its image (`images/unlockables_override/...jpg`).
- Outfit root: a hero aspect dummy (linked proxy + cloth character + hero idle network aspect) with
  `m_pBonesAndCollisionResource` set to the female rig. Body parts are plain `zbodypartentity` entries pointing
  at PRIMs.
- NPC part-library templates under a hero root crash at mission load. An NPC outfit TEMP as the charset target
  falls back to 47's suit. NPC disguises keep 47's head, so only the suit itself shows the new character.
- Building on IOI's female parts (`fem_reg` rig) instead of one fused generated mesh keeps IOI's facial rig
  (103 bones), LODs and skin shaders. The female body parts share one material atlas (`fem_reg_body.mi`), and
  vanilla head neck rings match vanilla body parts, so no seam work is needed.
- Hair colour on IOI hair materials lives in `ConstantColorRGB_02_Value`.

### A replacement default pistol
- The default concealed pistol is the ICA19 (`FIREARMS_HERO_PISTOL_TACTICAL_ICA_19`), not the Silverballer.
- Clone the ICA19 repository entry under a new GUID (same stats), redirect the starting token's `RepositoryId`,
  and override Name/Description with localisation keys.
- New parts: append `zbodypartsetupentity` + `zbodypartentity` to the model template's part collections and
  select them with `ModelBodyPartSelections`.
- **HUD icon:** `HudIcon` is the runtime ID of a GFXI, which is a plain DDS (808x328 DXT5, 1 mip) at
  `[assembly:/_pro/ui/common/icons_inventoryitems/item_left_<item GUID>_0.png].pc_gfx`. Keep the vanilla
  128-byte header and splice new DXT5 data after it.
- Freeform Training issues its own vanilla ICA19, so test a token-redirected pistol in a mission with planning.

### PRIM layout facts
- **Linked (weapon) PRIMs** keep the part's bone index in every vertex's position w (pos_scale.w 32767,
  pos_bias.w 0). On the ICA19 the parts are frame 1, mag 2, hammer 3, slide 4, trigger 5.
- **Linked collision (H3):** `u16 size, u16 1, u16 chunks rounded up to 4, u16 16, u32 tris, u32 0`, then
  `u16 chunks, u16 32` and one 6-byte box per 32 triangles, rounded to the sub-mesh bounds. Weighted PRIMs use
  the older layout without the 16-byte header, and also carry per-bone vertex lists (bone accel).
- A weighted PRIM's per-bone triangle list has a **u16 count**. 40k triangles on one bone overflow it, and
  about 20k fits.
- **Cloth:** IOI hair PRIMs carry per-vertex cloth rows (`cloth_id` at mesh+96, `cloth_offset` at
  sub-mesh+68, 20 bytes per vertex: neighbour indices plus constraints, 0xFF.. = pinned).
- **Texture tonymeta** (16 bytes): byte 0 is 0 for colour and 1 for normal. Byte 8 is the format: 0x5A BC7,
  0x55 BC5, 0x49 BC1. Bytes 11 and 12 are the size code: 2=512, 3=1024, 4=2048, 5=4096.

## Build steps
1. Export the vanilla PRIMs, materials and textures you build on (rpkg / GlacierKit) to a private folder outside
   the repo.
2. Edit or generate meshes. Name the objects as the vanilla PRIM's, weld before decimating, and keep each linked
   part under the vanilla per-LOD vertex counts.
3. `rpkg-cli -rebuild_prim_in`, then repair every rebuilt PRIM. The repair pass and the TEXT/TEXD builder were
   one-off Python scripts and are not published, so the steps they performed are spelled out here:
   - Linked PRIMs: write each vertex's bone index back into position w with pos_scale.w 32767 and
     pos_bias.w 0 (Gotcha 1, PRIM layout facts).
   - Linked PRIMs: regenerate the collision block in the H3 layout above, one box per 32 triangles over the
     new triangles (Gotcha 2).
   - Hair and other cloth PRIMs: zero `cloth_id` and the sub-mesh `cloth_offset` and drop the cloth rows, unless
     the vanilla topology is kept (Gotcha 9).
   - Characters: copy the container's COLOR_0 into the new vertices (Gotcha 7).
   - Check the vertex budget per linked part and the u16 per-bone triangle count before shipping (Gotcha 10).
4. Build TEXT/TEXD yourself instead of letting SMF convert:
   - Encode the mips with any BC encoder (BC7 colour, BC5 normal, BC1 masks). TEXD holds the full mip chain and
     TEXT a downscaled copy, as in the vanilla pair you start from.
   - Copy the vanilla texture's meta and set the tonymeta format and size code (PRIM layout facts).
   - Set video memory to the sum of the TEXD mips at the format's block size (16 bytes per 4x4 block for BC7/BC5,
     8 for BC1), and TEXD `hash_size` to 0 (Gotchas 4 and 5).
   - Build only MATIs and keep the source's MATT/MATB (Gotcha 6).
5. Write the entity, repository, unlockables and ORES files. Deploy with SMF, restart Peacock, and launch.

## Verification
- Paris → The Showstopper → Planning showed the suit and the pistol with their images. In the mission, the
  suit rendered and the pistol equipped (`I` inventory, Enter), aimed and fired.
- Crash checks via `Get-WinEvent` (Application 1000). The crashes here were **intermittent**, so run each
  configuration 3+ times and keep a no-mod control. Controls: 3/3 clean.
- Not checked: hit detection on the new character. Weighted PRIMs keep the donor's collision and bone-accel
  data (in bounds, but stale).

## Gotchas
1. **An rpkg-rebuilt *unmodified* weapon magazine crashed the menu.** **Cause:** rpkg 2.34 writes position w
   32767 at scale/bias 0.5, losing the per-vertex bone index on linked PRIMs. **Fix:** restore w (see PRIM
   layout facts).
2. **Crashes from rebuilt meshes with changed triangle counts.** **Cause:** rpkg copies the container's
   collision blocks verbatim. **Fix:** regenerate collision in the layout above. A generator reproduced 21 of 22
   vanilla ICA19 blocks byte for byte.
3. **Intermittent crashes at boot, load or pause (~half the runs) with no custom binaries at all.** **Cause:**
   `ModelBodyPartSelections` selected past the end of part collections, as vanilla ICA19 does for Rails.
   **Fix:** never select past the end; append explicit empty setups (null mesh) at those indices.
4. **Textures stream in wrong or get evicted.** **Cause:** SMF/HMTextureTools declare video memory at the BC1
   rate for BC5/BC7, which is half of what the GPU needs, and SMF caches conversions by the TGA alone (a changed
   `.meta` keeps the stale TEXT/TEXD). **Fix:** build TEXT/TEXD yourself. Video memory = the TEXD mips at the
   format's block size.
5. **The character rendered black with coloured specks.** **Cause:** a TEXD meta with `hash_size` 0x80000000
   (XOR'd). TEXT has that flag, vanilla TEXD does not. **Fix:** TEXD `hash_size` 0.
6. **`rpkg -json_to_material` makes 0-byte MATT/MATB files for new hashes (crash),** or rewrites vanilla ones
   with different bytes (black render). **Fix:** keep the source's MATT/MATB, build only the MATI, ship only
   the MATI.
7. **Arms rendered wrong.** **Cause:** vertex colour matters on characters (the `fem_reg` arms carry white
   COLOR_0). **Fix:** copy the container's COLOR_0.
8. **A character shader (`basic_fabric`) on gun parts crashed.** **Fix:** a textured `basicmaterial` (retarget
   of an ICA19 receiver material) works on linked PRIMs.
9. **Hair glitched: the braid went over the shoulder, and strips hung to the knees.** **Cause:** rpkg keeps the
   container's cloth rows when the vertex order or count changes, so the solver drives the wrong vertices.
   **Fix:** strip the cloth rows (or keep vanilla topology).
10. **Linked parts with more vertices per LOD than the vanilla part crashed 2 of 3 runs.** Cause unknown. **Fix:**
    stay under the vanilla counts (frame ~2019, slide 638, hammer 222, trigger 218, mag 762 at LOD0), and weld
    generated meshes before decimating or the LODs turn spiky.
11. **A replacement hammer swung sideways.** **Cause:** its pivot was 17 mm from the ICA19 hammer bone's.
    **Fix:** join the hammer into the frame and ship a hidden 3-vertex stub for the hammer part.
12. **GLBs from rpkg keep raw Z-up accessor data, but Blender's importer applies different axis fixes** to
    vanilla and re-exported files. **Fix:** edit accessor data directly and write GLBs without a Blender round
    trip.
13. **Dark flecks on the ears, and baked hair on the neck.** **Cause:** masking ears by a z box missed the lobes.
    **Fix:** mask by the rig (`fa_ear_*` weights).
14. **The SDK's `Outfits` mod** was the main suspect in scene-change crashes, and isn't needed for new suits.
    Leave `[outfits]` out of `Retail\mods.ini`.

## Assets
- Pistol: hand-modelled in Blender by script from public reference photos, baked high→low (normal, AO, masks)
  into one 2048 atlas, with five named parts at real scale anchored on the trigger centre.
- Suit: IOI `fem_reg` parts (head, arms, gloves, tank top, shorts, belt, legs, boots), morphed and recoloured,
  with a procedural hair cap and braid. Holsters and straps were generated with fal (image edit → trellis-2).
  Trellis-2 GLBs put textures under `EXT_texture_webp`, and their UV v runs the other way from rpkg's.
- The head was morphed toward a multi-view reconstruction (fal `hitem3d` multi-view-to-3d) with MediaPipe
  landmarks, a thin-plate warp and a shrink-wrap, then baked into the head's UVs. The skin PBR stays IOI's;
  only the diffuse is replaced.

## Cost and time
Several sessions over two days. fal image edits were about $0.08 each.

## Open questions
- Regenerating collision and bone-accel tables for weighted (character) PRIMs, so hit detection matches the new
  mesh.
- Why linked parts with more vertices crash, since the vertex budget is a workaround and not an explanation.
