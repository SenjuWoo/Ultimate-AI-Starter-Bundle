# Local modding bench (agent map)

The owner's machine keeps a game-modding tool bench in a `Modding` folder beside
the folder holding this bundle's documentation (~5 GB, inventoried 2026-10-21).
It is reference tooling, not part of this pack and never an install target for
it: resolve a tool from it only when the current task needs one, and prefer the
route below over reinstalling anything.

Resolve the bench root from what the owner says in the current conversation.
It is a hint for one machine, like every path in this skill - never hardcode a
drive letter as authority.

## Which tool for which route

| Route | Bench tools | Notes |
|---|---|---|
| Native code: disassembly, decompilation, PE triage | `ghidra_12.1.4_PUBLIC`, `imhex-1.38.1`, `PE-bear_0.7.2` | Headless Ghidra (`analyzeHeadless`) is scriptable; PE-bear for quick header/import triage |
| Live process work: memory, hooks, instrumentation | `CheatEngine`, `MinHook`, `SafetyHook`, `ReClass.NET` | Injection/instrumentation is for owned single-player sessions only |
| Graphics: capture, shader mods, remastering | `RenderDoc`, `Nvidia Nsight`, `Pix`, `3Dmigoto`, `Reshade`, `RTX Remix/remix-1.5.2` | RenderDoc/PIX for frame capture; 3Dmigoto for DX11 shader/hunting work; RTX Remix for D3D8/9-era titles |
| Unreal assets and runtime | `FModel`, `umodel_win32`, `UAssetAPI-v1.1.0`, `UAssetGUI`, `repak_cli`, `retoc_cli`, `UE4SS_v3.0.1` (+ dev build), `UE-Modding-Tools-main`, `unreal-mcp-ue4` | `umodel_win32` is old 32-bit; prefer UAssetAPI/UAssetGUI for cooked assets and UE4SS for runtime Lua |
| Unity assets and managed code | `AssetRipper`, `UABEANext`, `ILSpy-master`, `BepInEx-master`, `UnityExplorer` | Extract with AssetRipper/UABEA; read managed code with ILSpy; runtime with BepInEx/UnityExplorer |
| Godot | `Godot_v4.7.2-stable_mono_win64`, `LimboAi` | Match the project's exact engine build; mono needed for C# projects |
| 2D fighters and pixel art (MUGEN family) | `Ikemen_GO-v1.0.0`, `Ikemen-forge-master`, `Figher-Factory`, `OpenBOR.v4.0.Build.7533`, `LDtk 1.5.3`, `Pixelorama` | Pick the engine the target already uses - Ikemen, MUGEN and OpenBOR script formats are not interchangeable |
| Frostbite (EA titles) | `FrostyToolsuite-master` | Meshes/textures route only |
| Specific games | Helldivers 2: `HD2Runtime-0.28.1` (runtime/sdk/template/example-projects), `HD2Runtime-ModBuilder-v1.7.1`, `HD2SDK-CommunityEditionV3-11-0`; Risk of Rain 2: `R2API-master`, `RoR2EditorKit-6.1.0`, `RoR2ItemSync-SDK-main`; Noita: `AutoLuaAPI-master`, `NoitaNET-master`, `Spell-Lab-Shugged-main`, `conjurer_reborn-main` (+ a wiki dump); Sleeping Dogs 2: `SDK-theory`, `TheoryEngine-main` | These are the per-game routes the owner validated; start from their READMEs |
| Roblox | `Roblox/Chrono` (a prebuilt `build.rbxm`) | Roblox work itself goes through the `roblox-game-development` skill and RobloxForge, not this folder |
| Mashup passthrough (game A draws game B) | `_downloads`: `reshade` (6.8.0 add-on installer) + `reshade-src`, `ue4ss-exp` (experimental build, zip + cfg) + `ue4ss-src`, `assetstudio-src`, `vsbt` (VS Build Tools); `Game-Mashup-Passthrough/LESSONS.md` | Workflow in the `game-mashup-passthrough` skill, results in the `project-intel` card; the host usually needs the experimental UE4SS plus layout overrides, and the add-on is built from `reshade-src` with CMake + Ninja + MSVC |
| Tool-state snapshot | `Reverse Engineer/snapshot_2026-05-27_12-11/release/` (release notes, `ntstatusdb`, `errordb`, `winconstants`) | Historical evidence from a Gegenbauer tool release, not a live tool |

## Companion tool snapshots (`Tools` folder)

A sibling `Tools` folder holds source snapshots of tools the pack already
covers: `rea-main`, `universal-modder-main`, `reverse-this`, `CLI-Anything`,
`anti-slop`, `jevgrep-main`. They are reference copies, not the install source:
the pack ships its own pinned REA and Universal Modder and installs them from
its catalog. Measured 2026-10-21, the `rea-main` snapshot was 6.5.0 (pack pins
6.7.0) and `universal-modder-main` predated the pinned commit (no `sprixen`
module), so never run or copy a tool from there in place of the pinned one. See
`docs/TOOL-EVALUATIONS.md` for what was checked.

## Rules that keep the bench useful

- Work on an owned copy outside the installed game. Never edit a game install in
  place (pack rule, unchanged) - every tool above assumes a lab copy.
- Memory, hooking and injection tools are for offline single-player sessions the
  owner controls. Never anti-cheat, multiplayer or third-party machines.
- Do not upgrade a tool mid-project. Keep the pinned version in the project's
  notes; UE4SS v3.0.1 and its dev build coexist on purpose.
- Ripped assets and decompiled output stay local evidence: never ship them from a
  project, and never present static output as recovered source.
- Route first, tool second: engine and modding routes come from the
  `universal-modder` guides (recon, engine playbooks, porting). A tool name alone
  is not a plan.
- The bench stays out of the pack and out of game folders; nothing here is
  installed into a project by default.
