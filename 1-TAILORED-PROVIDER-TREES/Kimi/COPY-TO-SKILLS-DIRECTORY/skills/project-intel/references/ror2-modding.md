# Risk of Rain 2 modding - settled results

One line per finding: workflow, what was tried, result, cause, what worked, evidence. Dates are when it was
verified on game build 1.5.0 (Nov 2026). Re-check against the installed `RoR2.dll` after a game update.

## Survivors built from another game's assets (runtime-built model, no Unity editor)

- Unity audio: in the shipping game `AudioSettings.outputSampleRate` is 0 and `AudioClip.Create` returns 0
  samples, so `AudioSource` plays nothing. Wwise bank route needs the Wwise 2023.1 editor; the winmm route needs
  no account and costs spatialisation. (2026-10, measured in game, strong)
- Wwise banks extracted from another game do not load: RoR2 is bank version 150, the source game was 145. The
  media files transfer, the banks do not. (2026-11, measured, strong)
- winmm audio ignored the volume sliders and played at full level for every Ultron in range until gain was
  multiplied by `AudioManager.cvVolumeMaster` x `cvVolumeSfx` and attenuated by camera distance. (2026-11,
  fixed in Ultron 1.1.2, code read, not heard)
- Items were invisible on both shipped survivors until an `ItemDisplayRuleSet` was set. Commando's rule set shared
  through per-bone adapters worked on every costume without an editor; pure height scaling left items oversized on
  a slim rig (build factor 0.75 Ultron, 0.9 Gnar). (2026-11, screenshots front/side/back, medium)
- `CharacterModel.SetEquipmentDisplay` throws when the body has no inventory yet; guard it. (2026-11, stack
  trace, strong)
- Attacks tagged only with a `DamageType` enum carry `DamageSource.NoneSpecified`, so skill-keyed items skip
  them. Tag every skill attack with a `DamageTypeCombo`. (2026-11, type read from `RoR2.dll`, strong)
- Costume swap to a smaller skeleton left stale bone indices in the animation driver, threw every frame and froze the
  bind pose (T-pose). Clearing the name -> index map per skeleton fixed it. (2026-11, autorun over all 14 costumes,
  strong)
- Flight and dash wrote the motor on every client; writes belong behind `body.hasEffectiveAuthority`. (2026-11, code
  review, not tested with two clients)
- `ImageConversion.LoadImage(..., false)` kept ~180 MB of CPU texture copies on a 130-texture survivor; `true` frees
  them. DXT `Compress()` needs the pixels, then `Apply(false, true)`. (2026-11, medium)
- `using R2API.Utils;` ships in `R2API_Core`; a checker that demands an `R2API_Utils` package is wrong. (2026-11,
  read from `R2API.Core.dll`, strong)

## Packaging

- Thunderstore empties every top-level folder that is not `plugins`, `patchers`, `config`, `core` or `monomod`, so
  `assets/` beside the DLL installs as loose files and the plugin dies on a missing path. A local unzip hides it.
  (2026-10, validator rule, strong)

## Workflow

- `forge audit` plus `forge validate` plus an autorun that fires every skill, applies every costume and gives items
  caught what a green build and one solo run did not. It is cheap; run it before declaring done. (2026-11)
- Not proven: multiplayer with two real clients, and anything about sound as heard by a person.
