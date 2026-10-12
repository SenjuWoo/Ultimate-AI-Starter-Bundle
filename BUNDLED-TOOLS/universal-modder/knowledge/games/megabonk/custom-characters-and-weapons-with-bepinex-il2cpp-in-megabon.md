---
kind: game
title: "Custom Characters and Weapons with BepInEx IL2CPP in Megabonk"
game: "Megabonk"
game_version: "1.0.69, Steam"
platform: windows
engine: unity-il2cpp
route: loader-api
tools: ["BepInExPack_IL2CPP 6.0.755", "ilspycmd", "dotnet 10"]
anti_cheat: "none, but runs post to online leaderboards: turn Upload score to Leaderboards off for every modded run"
status: working
agents: ["Gemini CLI"]
humans: ["SyronAscalon"]
date: 2026-10-11
links: ["https://github.com/BepInEx/BepInEx", "https://thunderstore.io/c/megabonk/p/BepInEx/BepInExPack_IL2CPP/"]
tags: ["characters", "weapons", "melee", "il2cpp", "bepinex6", "harmony"]
---

# Custom Characters and Weapons with BepInEx IL2CPP in Megabonk

> Implemented a new custom character (The Farmer) with bespoke starting attributes, passive ability, 3D visual styling, and a unique melee weapon (Pitchfork) featuring stacking execution and armor mechanics. Runs verified in Megabonk 1.0.69 with BepInEx 6 IL2CPP and HarmonyX.

## Setup
- **Game:** Megabonk build 1.0.69 (Steam AppID 3405340)
- **Engine:** Unity 2023.2.22f1 (IL2CPP, x64)
- **Mod Loader:** BepInExPack_IL2CPP 6.0.755 (Thunderstore)
- **SDK:** .NET 6.0 (`net6.0`) with C# `latest` and `AllowUnsafeBlocks: true`
- **OS:** Windows 10 / 11 x64
- **Leaderboards:** Megabonk posts finished runs to online leaderboards. A custom character with an execute weapon
  is a cheat there, so set **Upload score to Leaderboards** to Off in the game's settings before any modded run.
  This plugin doesn't touch that setting. Other Megabonk mods (Megamod, for one) lock it off while they're loaded,
  and a released version of this one should too.

## Route and why
We chose the **loader-api** route using BepInEx 6 IL2CPP with Harmony detours. Megabonk runs on Unity 2023.2 IL2CPP. BepInEx generates interop assemblies (`BepInEx/interop/Assembly-CSharp.dll`, `UnityEngine.*.dll`) containing typed invoke stubs. Data-only modding is impossible because characters and weapons are ScriptableObject instances loaded into internal dictionaries. Native DLL injection with MinHook is unnecessarily complex given that BepInEx IL2CPP provides full C# access to all engine types and Harmony method patching.

## How the game works (what we had to learn)
- **Central Registries:** `DataManager` holds `characterData` (Dictionary of `ECharacter, CharacterData`), `unsortedCharacterData` (List), `weapons` (Dictionary of `EWeapon, WeaponData`), and `unsortedWeapons` (List). Populating these during `DataManager.Load` integrates custom content into the game.
- **Character Selection Grid:** `CharacterMenu` dynamically creates button instances (`MyButtonCharacter`) from `characterPrefabUi` under `characterGridParent`. By instantiating `characterPrefabUi` in `CharacterMenu.TryInit` Postfix, custom characters appear natively in the selection grid.
- **Weapon System:** Every weapon evaluates stats through `WeaponBase.GetValue(EStat)`. The weapon's `baseStats` dictionary must include all standard keys (`Projectiles`, `ProjectileSpeedMultiplier`, `SizeMultiplier`, `DamageMultiplier`, etc.), otherwise the combat loop throws a `KeyNotFoundException`.
- **Damage Pipeline:** Player damage flows through `Enemy.DamageFromPlayerWeapon(DamageContainer dc)`. Non-boss enemies can be executed by checking `enemy.IsBoss()`, `IsStageBoss()`, and `IsFinalBoss()`, and setting `dc.damage = enemy.hp + 999999f`, `dc.crit = true`, `dc.isExecute = true`.
- **Combat Feedback:** Floating damage text can be spawned dynamically from `PoolManager.Instance.GetDamageNumber()`.
- **Localization:** `UnlockableBase.GetName()` and `GetDescription()` attempt to read from Unity string tables. Without custom table entries, it throws a NullReferenceException, which can be bypassed via Harmony prefixes.

## Build steps
1. Install BepInExPack_IL2CPP 6.0.755 into the game folder and run once to generate interop assemblies. In the
   game's settings, set **Upload score to Leaderboards** to Off.
2. In `BepInEx/config/BepInEx.cfg`, set `EnableAssemblyCache = false` and delete `BepInEx/cache/chainloader_typeloader.dat`.
3. Create a C# project targeting `net6.0` referencing `BepInEx.Core.dll`, `BepInEx.Unity.IL2CPP.dll`, `0Harmony.dll`, and interop assemblies.
4. Implement registration in `DataManager.Load` Postfix, grid injection in `CharacterMenu.TryInit` Postfix, and weapon damage interception in `Enemy.DamageFromPlayerWeapon` Prefix.
5. Deploy compiled DLL to `BepInEx/plugins/<ModName>/`.

## Verification
- **Oracle:**
  - BepInEx console and file logs (`BepInEx/LogOutput.log`) confirming plugin initialization, asset loading, and data registration with 0 errors.
  - In-game screenshot capture via `um win shot`: The Farmer button was rendered in the Character Selection grid with custom straw hat icon, description, Pitchfork weapon card, and Bountiful Harvest passive.
  - In-game gameplay capture: Confirmed the Pitchfork weapon slot rendered (`LVL 1 Pitchfork`) under the player HP bar in an active combat run.

## Gotchas
1. **The plugin DLL is in `plugins/` but never loads.** BepInEx caches what it found in each DLL in `BepInEx/cache/chainloader_typeloader.dat` (`EnableAssemblyCache`, on by default). Entries are keyed by path and a hash of the file's bytes (`TypeLoader.FindPluginTypes`), so a rebuilt DLL is scanned again, but a byte-identical DLL keeps whatever an earlier scan found, including no plugins. Fix: delete the cache file, or set `EnableAssemblyCache = false` while iterating.
2. **Texture loading in `BasePlugin.Load()` crashes with AccessViolation.** Calling `new Texture2D()` or `LoadImage` inside `BasePlugin.Load()` causes a fatal DirectX AccessViolation because the GPU device context is not yet active during BepInEx Chainloader startup. Fix: defer all texture loading to `DataManager.Load` Postfix.
3. **ImageConversion.LoadImage fails with ObjectCollectedException in IL2CPP.** Passing an implicit `Il2CppStructArray<byte>` to `ImageConversion.LoadImage` creates an unpinned managed wrapper collected by IL2CPP GC before native marshalling finishes. Fix: pre-convert images to raw RGBA32 byte files (`.raw`) and load them directly via `Texture2D.SetPixel(x, y, color)` and `Apply()`.
4. **Custom weapons crash on attack with KeyNotFoundException.** Megabonk expects all standard stats (`Projectiles`, `ProjectileSpeedMultiplier`, etc.) in `weaponData.baseStats`. Omitting them crashes on the first attack swing. Fix: clone all key-value pairs from `baseWeapon.baseStats` and add a Harmony prefix fallback on `WeaponBase.GetBaseValue`.
5. **Character selection card throws NullReferenceException on GetName.** Modded unlockables lack localization table entries, causing `UnlockableBase.GetName()` to dereference null. Fix: hook `UnlockableBase.GetName` and `GetDescription` with Harmony prefixes returning the modded name/description directly.

## Assets
- `farmer_icon.png`: 256x256 pixel-art character portrait with straw hat, wheat stalk, and denim overalls.
- `pitchfork_icon.png`: 256x256 melee weapon icon showing a sharp 3-pronged iron pitchfork with gleaming tips.
- `harvest_icon.png`: 256x256 passive icon showing tied golden wheat stalks and glowing embers.
- Assets were pre-converted to 128x128 raw uncompressed RGBA byte files (`.raw`) for safe zero-alloc IL2CPP texture loading.

## Cost and time
- Session duration: ~1 hour.
- Automated verification: 6 in-game screenshots captured and analyzed.

## Open questions
- Custom 3D mesh model import via AssetBundles for custom player meshes.
- Adding additional weapon upgrade branches to `WeaponData.upgradeData`.
