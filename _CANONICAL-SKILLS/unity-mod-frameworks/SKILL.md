---
name: unity-mod-frameworks
description: Unity game mods via BepInEx, Harmony, MonoMod, IL2CPP or Mono - Valheim, Subnautica, Lethal Company, Oxygen Not Included, Kerbal Space Program and generic Unity targets. RimWorld and Risk of Rain 2 have their own forges.
---

# Unity / BepInEx / Harmony mod development

Read `game-modding` -> `references/MODDING-LAWS.md` before the first write:
ownership and versioning, evidence ladder, and the never-invent rules apply here too.

Start with `references/OVERVIEW.md` for the shared toolchain, then the
specific reference below.

| Target | Reference |
|---|---|
| Valheim | `references/valheim-jotunn.md` |
| Subnautica | `references/subnautica-nautilus.md` |
| Lethal Company | `references/lethal-company.md` |
| Oxygen Not Included | `references/oxygen-not-included.md` |
| Kerbal Space Program 1 | `references/kerbal-space-program.md` |
| Harmony patch order and safety (cross-game) | `references/dotnet-harmony-patching.md` |

RimWorld and Risk of Rain 2 belong to their forges (RimWorldForge, Risk of Rain 2 Forge): see the forge
registry in `ai-tooling-stack`. Stardew Valley is not Unity: `game-modding`.

Resolve the exact game build, loader, mappings, and framework versions before
implementing. Never invent an API, hook, signature, ID, or asset path.
