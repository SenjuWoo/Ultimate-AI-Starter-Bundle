# Risk of Rain 2

Pin the game build, game-specific BepInEx pack, R2API modules, Harmony/MonoMod,
content catalogs, and network behavior. Do not assume every R2API module is
installed or a client-only mod is multiplayer-safe.

Primary sources:

- https://github.com/BepInEx/BepInEx
- https://github.com/risk-of-thunder/R2API


## Survivors: preflight before the first line of C#

A weaker model reliably skips the same things, and every one of them compiles, validates and plays a solo run.
Treat each item below as a default of the survivor, not an extra. Each was missed in a shipped survivor
(Ultron and Gnar, Nov 2026) and fixed afterwards.

**Tool first.** Use the Risk of Rain 2 Forge (`https://github.com/SenjuWoo/Risk-Of-Rain-2-Forge`; root in
`ROR2_FORGE_ROOT`, else ask or search `UABS_TOOL_ROOTS`). It is a CLI, not an MCP: `forge doctor`, then
`forge guide character|extraction|runtime|audio|thunderstore` and read the ones that apply BEFORE writing code.
Then `symbols`/`inspect` for every API you use, `new`, `audit`, `build --locked`, `package`, `validate`, `bump`.
If it is absent, use the TOOL MISSING template from `tool-discovery` and continue with this list.

| Default | What goes wrong when skipped | The fix |
|---|---|---|
| Item displays | Items you pick up are invisible on the model; nothing errors | Set `CharacterModel.itemDisplayRuleSet`. Share Commando's rule set and parent one adapter per Commando anchor under the matching bone of your rig (rotation frame + height ratio x build factor). Rebuild displays after every rig build and costume swap; skip while `body.inventory` is null. Forge `guide runtime`, "Item displays" |
| Damage source | Skill-keyed items ignore your hits | `damageType = new DamageTypeCombo(type, DamageTypeExtended.Generic, DamageSource.Primary/Secondary/Utility/Special)` on every Bullet/Blast/OverlapAttack |
| Authority | Flight/dash/hover fight the network transform | Gate `CharacterMotor.velocity` and `ForceUnground()` writes on `body.hasEffectiveAuthority`; buffs and heals on `NetworkServer.active` |
| Clone leftovers | Commando's death or bark plays with yours | Clear `SfxLocator.deathSound` and `barkSound` when you play your own |
| Audio | Silence, or a noise burst | Unity audio is disabled in this game. `AudioClip`/`AudioSource` cannot work. Use a Wwise bank (needs the Wwise 2023.1 editor) or the winmm route. On winmm multiply gain by `AudioManager.cvVolumeMaster` x `cvVolumeSfx`, fall off by camera distance, write PCM through the unmanaged buffer, shut down flag -> join thread -> reset -> unprepare -> free -> close, and make every `Play_...` event a key in `events.txt`. Forge `guide audio` |
| Textures | A second CPU copy of every texture | `ImageConversion.LoadImage(tex, bytes, true)`. Only `LoadImage(false)` then `Compress(true)` then `Apply(false, true)` is acceptable |
| Package layout | Assets install as loose files and the plugin dies on a missing path | Everything under `plugins/<Name>/`; leave bake duplicates and unused masks out of the zip; `validate` the zip, never trust a local unzip |
| R2API names | Plugin never loads for users | `using R2API.Utils;` lives in `R2API_Core`; every other `R2API.<Module>` needs its own manifest dependency. The csproj, manifest and plugin constant carry one version |
| Live model | Companion or camera aims at nothing | The spawned model is detached from the body: resolve the live body from `CharacterModel.body`. Aim a companion in `LateUpdate` with mesh +Z via `LookRotation(aim)`, never `-aim`. `CharacterCameraParams.data` is a struct: copy, edit, assign back |
| Stat buffs | Double speed or armor | One stat field per bonus (`moveSpeedMultAdd` or `armorAdd`); never also scale velocity or add vanilla CloakSpeed/ArmorBoost |
| Costumes | T-pose, wrong colors, only some costumes work | Per-skeleton state (bone name -> index maps) is cleared when the mesh changes; rebuild the rig on a costume swap, deferred out of `onSkinApplied`; take costume data from the game's own material files, never guess it; do not clamp the skin index |
| Text | Tooltips lie after a rebalance | Skill text numbers come from the same constants the skills use |

**Done means** more than a green build: `forge audit` with 0 errors and 0 warnings; `forge validate` on the zip;
an autorun that fires all four skills, applies EVERY costume, gives items (`inventory.GiveItemString`) and
screenshots front, side and back, with 0 exceptions from the mod and 0 `Missing texture`; the companion's aim
dot at 1.000 on the live body. Quit-time `GenericPool` and `ClipCursor` errors are not the mod. A played run is the
acceptance test for look, hover and sound; multiplayer is unproven until two real clients ran it. Say which of
those you did not do.

Dead ends already settled: Unity audio, `LookRotation(-aim)`, a second speed multiply, and editing a shipped
version in place (ship a new one).

## Mandatory version snapshot before the first edit

Every new mod starts at a semantic version such as `1.0.0`. Every update creates a new sibling folder by fully copying the current snapshot.

```text
<OwnerRoot>\<Mod Name>\
├── CHANGELOG.md
├── CURRENT.txt
├── WORKSPACE_OWNERSHIP.md
├── <Mod Name> 1.0.0\
│   └── VERSION.md
├── <Mod Name> 1.0.1\
│   └── VERSION.md
└── <Mod Name> 1.1.0\
    └── VERSION.md
```

Before changing a file:

1. Read `CURRENT.txt`, `CHANGELOG.md`, and `WORKSPACE_OWNERSHIP.md`.
2. Choose the semantic bump: patch, minor, or major.
3. Fully duplicate the current snapshot into the new version folder.
4. Update `CURRENT.txt`.
5. Create or update the new snapshot's `VERSION.md`.
6. Start the new changelog entry with the AI application, model, reasoning mode, task, parent version, and intended files.
7. Edit only the new version.
8. Never mark a partial or failed copy as current.

The previous version remains untouched for rollback and binary comparison.



## Non-negotiable laws

- Never edit a deployed game directory, active mod-manager staging folder, save, profile, or framework installation as the project source.
- Resolve the exact game build, storefront, runtime, loader, framework versions, dependency graph, and packaging format before implementation.
- Never invent API names, hook signatures, offsets, asset identifiers, manifest keys, paths, serialization fields, or compiler syntax.
- Prefer official documentation, upstream source, exact installed files, generated SDKs, and known-good local examples.
- A build or parser pass is not runtime proof.
- Preserve the previous working version and make the new version reproducible.
- Record every command, changed file, validation result, unresolved risk, and runtime status.
