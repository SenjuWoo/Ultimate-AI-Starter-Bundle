---
kind: technique
title: "Crysis Remastered data: paks, CryEngine 2 .chr 0x745, nanosuit shader modes and suit values"
game: "Crysis Remastered"
games_also: []
game_version: "Steam appid 1715130, files on disk 2026-10-17 (Bin64\\CrysisRemastered.exe 34,582,872 bytes, SHA-256 336c95e1c2d1...)"
platform: windows
engine: cryengine
route: asset-only
tools: ["Python 3.12 (uv), stdlib zipfile/struct + numpy + Pillow", "ffmpeg (MPEG-1 Layer II decode)", "Blender 5.1 (glTF import check)", "cgf-converter 2.0.0 (tried, see Gotcha 3)", "Ghidra 12 (exe section check only)"]
anti_cheat: "none (single player). The exe is wrapped in Steam DRM with an encrypted .text; it was not unpacked or modified, and every value here comes from shipped plain-text files"
status: working
agents: ["Claude Code (Opus 5.5)"]
humans: ["ovROG"]
date: 2026-10-18
links: ["https://github.com/Markemp/Cryengine-Converter"]
tags: [cryengine2, crysis, crysis-remastered, pak, zip, chr, cgf, cdf, mtl, chunk-file, skinning, morph-targets, gltf, split-dds, fsb4, fmod, cfx, shaders, nanosuit, cvars, lua]
---

# Crysis Remastered data: paks, CryEngine 2 .chr 0x745, nanosuit shader modes and suit values

> How to read Crysis Remastered's own files offline, from your own Steam install: the `.pak` archives, the
> CryEngine 2 skinned-model chunk files (`.chr`, version 0x745) with bones, skin weights and facial morphs, split
> DDS textures, the FSB4 sound banks and suit voice lines, how the nanosuit's mode looks are made (shader passes in
> `Cloth.cfx`, not textures), and the suit's balance numbers from the shipped cfg/Lua. Use it when you want the
> nanosuit (or any Crysis character, sound or texture) as source data for a mod, a converter or a port, without
> touching the DRM-wrapped exe.

## When to use it
- You want a Crysis Remastered character model as glTF (skinned, with UVs, materials and selected facial morphs).
- You need the suit voice lines, suit SFX or HUD icons as WAV/PNG.
- You want the nanosuit's mode looks (strength red, speed yellow, armor metallic, cloak) on an engine that can't run
  CryEngine shaders, so you have to bake them.
- You need the suit's numbers (energy, recharge, armor absorption, cloak and sprint costs).

Everything here reads files from your own install and writes outside the game folder. Nothing extracted may be
redistributed; a tool built on this should extract at install time from the player's own copy.

## How

### Install layout
- `Bin64\CrysisRemastered.exe` (x64, 34.6 MB) is the only binary; CryGame is linked into it. Sections are
  `.text .rdata .data .pdata _RDATA .rsrc .reloc .bind`; the entry point is in `.bind` (Steam DRM). See Gotcha 5.
- `Game\*.pak` and `Game\Localized\<language>.pak` hold the data. `Engine\Config\*.cfg`, `Game\Config\diff_*.cfg`
  and `Game\Levels\**\*.cfg` are loose plain-text cvar files.
- Where things are (all verified on the 2026-10-17 Steam files):

  | What | Pak | Path inside |
  |---|---|---|
  | Lua scripts | `scripts.pak` | `scripts/...` (GameRules, Entities/actor, Entities/Items/XML) |
  | FP nanosuit arms | `objectsw.pak` | `objects/weapons/Arms_Global/arms_nanosuit_us.chr` (+ `.mtl` and per-mode `.mtl`) |
  | Nomad body | `objectsch.pak` | `objects/characters/Human/US/NanoSuit/NanoSuit_us.chr`, `NanoSuit_Helm_simple.chr`, `nanosuit_us.cdf` |
  | Skeleton | `objectsch.pak` | `objects/characters/human/generic/skeleton_male.chr` |
  | Prophet | `objectsch.pak` | `objects/characters/Human/story/Laurence_Barnes/*.cdf`, `objects/characters/Heads/Story/Laurence_Barnes/Barnes.chr`, `NanoSuit_Helm_neck_Barnes.chr`, `objects/characters/Heads/eyes/Eye_generic_04.cgf` |
  | Suit voice | `Localized/<lang>.pak` | `languages/dialog/suit/male\|female/suit_*.mp2` |
  | Suit / menu SFX | `sounds.pak` | `sounds/interface/interface_combined.fsb` + `interface.fev` |
  | HUD icons, sprites | `textures.pak` | `textures/HUD/HUD_QuickMenu_{Armour,Strength,Speed,Cloak}`, `textures/Sprites/...` |
  | Suit shader | (engine shaders) | `Engine\Shaders\HWScripts\CryFX\Cloth.cfx` |

### Paks
Plain zip, deflate. The central directory stores `/` but each local header stores `\`, so Python's `zipfile`
rejects every member (Gotcha 1). Index members by name with `\` turned into `/` and lowercased, and on the
mismatch error retry the read with the backslash form of the name. Paks over 700 MB were skipped and not checked
(Warhead's `level.pak` files use a non-standard method 6, see the Warhead note under Seen in).

### Chunk files (`.chr`, `.cgf`), version 0x745
All little-endian.
- **File header:** `"CryTek\0\0"`, u32 file type `0xFFFF0000`, u32 version `0x745`, u32 chunk table offset.
- **Chunk table:** u32 count, then 20-byte entries `{u32 type, u32 version, u32 offset, u32 id, u32 size}`.
  A v0x800 chunk repeats the first 16 bytes of its entry at its offset; its data follows. Detect that by checking
  whether the first u32 at the offset equals the type.
- Chunks used, each version 0x800:

  | Type | Chunk | Layout |
  |---|---|---|
  | `0xCCCC0000` | Mesh | i32 flags, flags2, nVerts, nIndices, nSubsets, subsetsChunkId, vertAnimChunkId; i32[16] stream chunk ids, indexed by stream type; i32[4] physics chunk ids; f32[3] bbox min, f32[3] bbox max |
  | `0xCCCC0016` | DataStream | u32 flags, type, count, elemSize, 2 reserved; then `count × elemSize` bytes. Types: 0 positions f32×3, 1 normals f32×3, 2 UVs f32×2, 3 colours u8×4, 5 indices u16 or u32 (by elemSize), 6 tangents, 8 shape deformation, 9 bone mapping |
  | `0xCCCC0017` | MeshSubsets | i32 flags, count, 2 reserved; `count × 36` bytes `{i32 firstIndex, numIndices, firstVertex, numVertices, matId; f32 radius; f32[3] center}`; if `flags & 2`, then per subset `{i32 n, u16 boneIds[128]}` (260 bytes) |
  | `0xACDC0000` | CompiledBones | 32 reserved bytes, then 584-byte bones: u32 controllerId @0, 2 × 104-byte physics @4, f32 mass @212, Matrix34 world→bone @216, Matrix34 bone→world @264 (row-major 3×4), char name[256] @312, i32 limbId @568, i32 parent offset @572 (relative, in bones; 0 = root), u32 numChildren @576, i32 children offset @580 |
  | `0xCCCC0014` | MtlName | flags, flags2, char name[128] @8, physType @136, i32 nSubMtls @140, i32 subMtl chunk ids @144 |
  | `0xACDC0002` | CompiledMorphTargets (also 0x801) | u32 count; per target `{u32 meshId, nameLen, nInt, nExt}`, name (e.g. `#Jaw_dropper_01`), `nInt × {u32 vertex, f32 delta[3]}`, `nExt × {u32 vertex, f32 delta[3]}` |

- **Skin weights.** Bone mapping is 8 bytes (u8×4 ids + u8×4 weights) or 12 bytes (u16×4 ids + u8×4 weights).
  The ids are **local to the subset's bone table** (MeshSubsets flag 2), not skeleton indices (Gotcha 2). Map
  each vertex through the table of the subset whose vertex range contains it, and divide the u8 weights by
  their sum.
- **Morphs.** The "ext" list indexes render vertices and holds offsets from the bind pose; that is the list to
  use. A parse that ends exactly at the chunk's end is a good check.
- **Materials.** The first MtlName chunk is the library. A subset's `matId` indexes its sub-material list, which
  is the order of `<SubMaterials>` in the `.mtl` XML. Sub-materials with `Shader="Nodraw"` are helpers; drop them.
- **Coordinates.** CryEngine is Z-up. For glTF, map `(x, y, z) → (x, z, −y)`; Blender's importer maps it back to
  the original Crysis coordinates. Joint locals are `parentB2W⁻¹ · B2W`; inverse bind matrices were taken as the
  rigid inverse of bone→world (the stored world→bone was not used, see Gotcha 4).
- **`.cdf`** (XML CharacterDefinition) assembles a character. `CA_BONE` attachments give `BoneName`, plus
  `Position` and `Rotation` (w, x, y, z) as a model-space bind transform; a static `.cgf` (same Mesh/DataStream
  chunks, no bones) is placed there and rigidly skinned to that bone.
- **What the files contain:**

  | File | Bones | Vertices / triangles | Notes |
  |---|---|---|---|
  | `arms_nanosuit_us.chr` | 59 (custom, FP pose) | 4154 / 6904 | DXT5 diffuse 8192² |
  | `NanoSuit_us.chr` | 74 (Bip01) | 6015 / 9219 | DXT5 diffuse 8192×4096 |
  | `NanoSuit_Helm_simple.chr` | | 2575 v | `nanosuit_us.cdf` = body + this helmet on `skeleton_male.chr` |
  | `Barnes.chr` (Prophet's head) | only Spine3 / Head | | 89 facial morph targets, no face bones |

  `Laurence_Barnes.cdf` = suit body + `Barnes.chr` + `NanoSuit_Helm_neck_Barnes.chr` + two `Eye_generic_04.cgf`
  attached on `Bip01 Head`. The face only moves by morphs; usable ones are `Jaw_dropper_*` and
  `Brow_*_raiser_*`, and a bone-driven face can derive jaw and brow weights from them.
- **Material hints.** Diffuse alpha is a gloss mask, not opacity (Gotcha 6). Real alpha: teeth alpha test
  0.723, eyeball alpha test 0.49, lashes blended. The iris is tinted by `PublicParams IrisColor` when the
  material's `StringGenMask` contains `IRIS`. The suit diffuse is very dark (mean 38/255); the relief lives in
  the `_ddn` normal map.

### Split DDS textures
A texture is stored in parts: `<name>.dds` (or `.dds.0`) holds the 128-byte DDS header plus the smallest mips;
`<name>.dds.1` … `.dds.N` hold the bigger mips, with `.dds.N` being mip 0. A standard DDS is the header, then
parts N, N−1 … 1, then the rest of the first part after its header. Check the joined size against the sum of
the mip sizes. Diffuse and spec are DXT5, `_ddn` is DXT1, up to 8192².

### Sounds
- **Voice lines** are raw MPEG-1 Layer II streams (`.mp2`, 44.1 kHz stereo, 96 kbit/s); ffmpeg decodes them
  directly. Mode lines are `suit_maximum_armor`, `suit_maximum_speed`, `suit_maximum_strength`, and
  `suit_modification_engaged` for the cloak (Gotcha 8). The only energy line is `suit_energy_critical`.
- **`interface_combined.fsb`** is an FMOD FSB4 bank: a 48-byte header (`"FSB4"`, sample count, sample-header
  size, data size, version, mode, ...), then one variable-size header per sample (u16 size, name, sample count,
  compressed size, loop start/end, mode, frequency, channels at +62). Sample data starts after the headers and
  each sample is 32-byte aligned. Every sample is MPEG-1 Layer II (mode 0x40200). Walk the MPEG frame headers and
  keep only whole frames before decoding, so the alignment padding is dropped. Sample names are cut to 29
  characters (Gotcha 9). `interface.fev` maps FMOD events (`suit:suit_armor_activate`, `suit:suit_strength_punch`
  ...) to these sample names.

### Nanosuit mode looks are shader passes
There are no per-mode suit textures. Each mode has its own `.mtl` next to the model (`nanosuit_us` is the default
and is what armor mode shows in Crysis 1; then `_strength`, `_speed`, `_cloak`, and separately `_invulnerability`).
They keep the same textures and switch on `%NANOSUIT_EFFECTS` in `Cloth.cfx` through `StringGenMask`. That flag
adds:
- an additive pass of moving energy bands: a sine of the object-space position (lightly offset by the bump
  normal) scrolling over time, sharpened with a power and multiplied by fresnel, a colour and the **diffuse
  alpha**, so it only shows on the armour plates. Its parameters are `SparksColor`, `SparksMultiplier`,
  `SparksPow`, `SparksPhase` and `SparksFrequency` in the material's `PublicParams` (red for strength, yellow for
  speed);
- a metallic environment reflection scaled by `MetallicAmount`, fresnel and diffuse alpha, which is non-zero only
  in `_invulnerability`.

Cloak mode instead darkens the material (`Diffuse` 0.282) and the engine draws its cloak layer on top. To get the
looks without CryEngine, bake them per texel: rasterise each triangle's object-space position into UV space
(keeping each sub-material's own Sparks parameters), evaluate the band term at one moment and as a time average,
replace fresnel by its hemisphere average (`FresnelBias + FresnelScale / (FresnelPower + 1)`), and add it onto the
diffuse. Armor and cloak have to be emulated (a metallic sheen with an assumed environment colour; a cool
blue-grey tint), since their real look comes from environment maps and the cloak layer.

### Suit values from cfg and Lua
The suit cvars are registered in code with their defaults, and that code is encrypted on disk (Gotcha 5). The
plain-text cfg files set most of them at start-up or level load, so these are the values the player gets. Read
from the shipped files:

| Value | Source |
|---|---|
| Max suit energy 200 | `scripts/GameRules/SinglePlayer.lua` (`suitMaxEnergy = 200.0`, with a comment to keep it in step with the suit) |
| Player health 200 | `g_playerHealthValue` in every `Game\Config\diff_*.cfg` |
| Energy: full recharge in 4 s (also in armor, standing or moving) after a 2.5 s delay | `g_playerSuitEnergyRechargeTime*`, `g_playerSuitEnergyRechargeDelay` in `Engine\Config\common.cfg` |
| Health: full regen in 6 s after a 5 s delay | `g_playerSuitHealthRegenTime`, `g_playerSuitHealthRegenDelay` in `common.cfg` |
| Armor: a full bar soaks 125 HP (1.6 energy per HP); at least 30% of every hit is absorbed, even at 0 energy; armor mode drains 4 energy/s | `g_suitArmorHealthValue`, `g_suitArmorModeEnergyDrain` in `common.cfg`; the absorption rule in `SinglePlayer.lua` (mode 3 = armor) |
| Speed sprint: 24 energy/s (20 on Fleet), ×3 speed (×1.8 when empty), ramp 3/s | `g_suitSpeedEnergyConsumption`, `g_suitSprintMultiplier_speedMode_*`, `g_suitSprintAcceleration` in `Game\Levels\LevelDefaults.cfg` and `Levels\fleet\level.cfg` |
| Power melee ×1.4 (full and low energy alike) | `g_suitPowerMeleeScaleDamageWhenFullEnergy` / `...LowEnergy` in `common.cfg` |
| Cloak: 10 energy/s base drain for the player's cloak type 1 | `cloakEnergyCost` in `scripts/Entities/actor/BasicActor.lua`; the player picks type 1 in `player.lua` |
| Cloak energy drained per damage taken: 33 (Normal, Hard), 1 (Easy), 50 (Delta) | `g_suitCloakEnergyDrainWhenDamaged` in `diff_*.cfg` (unit unclear, see Open questions) |
| AI cloak detection: Easy 2/4, Normal 2.5/4.5, Hard 3/5, Delta 3/5.5 m | `ai_CloakMinDist` / `ai_CloakMaxDist` in `diff_*.cfg` |
| Base punch: 245 damage (player), 30 for AI | `scripts/Entities/Items/XML/Weapons/Fists.xml` |

The cvar names and their help texts are plain strings in `.rdata`, which tells you what exists even where no
value is set. Remastered has a `ClassicSuit` variant of several cvars (`cl_classicSuit = 0` in the default
profile picks the new controls). Not in any cfg or Lua, so unknown: power-jump force and cost, power-melee cost,
recoil cost in strength mode, the cloak drain adjuster and its moving factor, the non-speed sprint multipliers,
and every classic-suit value.

## Gotchas
1. **Python `zipfile` refuses every pak member** ("File name in directory ... and header ... differ").
   **Cause:** local headers store `\`, the central directory stores `/`. **Fix:** on that error, set the entry's
   `orig_filename` to the backslash form and read again; normalise names to `/` for lookups.
2. **Skinned mesh came out with weights on the wrong bones.** **Cause:** bone-mapping ids index the owning
   subset's 128-entry bone table, not the skeleton. **Fix:** find the subset whose vertex range holds the vertex
   and map ids through its table (only present when MeshSubsets `flags & 2`).
3. **cgf-converter 2.0.0 converts `arms_nanosuit_us.chr` but crashes on `NanoSuit_us.chr`** (an
   ArgumentOutOfRangeException inside its CompiledBones 0x800 reader), and drops UVs unless a material file is
   passed (`-mtl`, with `-objectdir` pointing at the extracted tree). **Fix:** a small own reader for the chunks
   above, about 450 lines of pure Python with a glTF writer.
4. **Inverse bind matrices.** The bone→world matrix was used, and its rigid inverse taken; the stored world→bone
   matrix was not relied on. The Warhead note found W2B and B2W are not always exact inverses, so keep the
   donor's matrices unchanged if you write `.chr` files back.
5. **The exe on disk can't be disassembled for cvar defaults.** **Cause:** it is wrapped in Steam DRM: the entry
   point sits in `.bind`, `.text` is encrypted on disk (byte frequencies are flat across the first 26 MB, no normal
   x64 prologue patterns, and no references to the 90 suit cvar name strings in `.rdata`). **Fix:** leave the file
   as installed. Take the effective values from the shipped cfg/Lua (table above), and read what only lives in
   code from the running game's console (Open questions). The code is readable in the running process, from
   memory or a private dump kept outside any repo (CONTRIBUTING, DRM-wrapped executables); that wasn't tried here.
6. **Holes or see-through patches in the converted suit.** **Cause:** diffuse alpha is a gloss/effect mask.
   **Fix:** drop alpha from the diffuse on export, except for the few materials with an `AlphaTest` or `Opacity`
   (teeth, eyeballs, lashes).
7. **No per-mode suit textures anywhere in the paks.** **Cause:** the looks are the `%NANOSUIT_EFFECTS` passes in
   `Cloth.cfx`, switched on by the mode `.mtl` files. **Fix:** bake them (see above) or recreate the shader in the
   target engine from the `PublicParams`.
8. **"Cloak engaged" is not called `suit_cloak_*`.** The line the game plays is `suit_modification_engaged`;
   `suit_full_cloak_off` exists but the game doesn't use it. The strength activate event
   (`suit:suit_strength_activate`) plays a blank sample, so take `suit_strength_activate_04` from the bank for a
   sound.
9. **An FSB4 sample isn't found by its full name.** **Cause:** names in the sample headers are cut to 29
   characters. **Fix:** match by prefix, or truncate your lookup names to 29 characters.

## Seen in
- Related CryEngine 2 notes: [Warhead build 711 static analysis and level PAK method 6](../games/crysis-warhead/build-711-static-analysis-and-level-pak-method-6.md)
  and [Black Ops Zombies in Warhead](../games/crysis-warhead/black-ops-zombies-native-animation-and-runtime.md)
  (writing `.chr` files back).

## Verification
- **Reader:** parsed all three nanosuit `.chr`, `Barnes.chr`, `NanoSuit_Helm_neck_Barnes.chr` and
  `Eye_generic_04.cgf` with hard checks: each stream type matches its slot, parent indices are in range, morph
  vertex ids are below the vertex count, and the morph chunk parses to exactly its last byte. Counts match the
  table above.
- **glTF:** imported into Blender 5.1. Mesh, UVs, skeleton and weights looked right, and Prophet's head, helmet
  neck and eyes landed in place from the `.cdf` transforms.
- **Audio and textures:** every WAV was checked for duration, peak and RMS. Joined split DDS files matched their
  expected size; icons were looked at.
- **Mode bakes:** rendered on the model in Blender and checked by eye by a human.
- **Not verified:**
  - the suit values in the running Crysis Remastered (nothing was probed live);
  - the inferred formulas (for example "recharge time = seconds for a full bar");
  - any other chunk types or versions (CompiledBones other than 0x800, physics, `.cga`, `.caf` animations);
  - paks over 700 MB, and whether Remastered's level paks use the same method 6 as Warhead.

## Open questions
- Read the unset cvars from the running game's console (typing a cvar name prints its value; `name ?` prints its
  help), with no file changes. That would settle power-jump force/cost, power-melee and recoil costs, the cloak
  adjuster and the classic-suit values.
- `g_suitCloakEnergyDrainWhenDamaged` = 33 per damage point would empty the bar on almost any hit, so its real
  unit (perhaps a percentage) is unknown.
- Whether the speed multiplier ×3 replaces or stacks with the base `sprintMultiplier` 1.5 in `player.lua`.
- A standalone public release of the reader.
