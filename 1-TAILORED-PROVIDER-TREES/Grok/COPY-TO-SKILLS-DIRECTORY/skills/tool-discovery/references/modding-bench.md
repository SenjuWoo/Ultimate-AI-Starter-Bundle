# Local modding bench (agent map)

The owner's machine keeps a game-modding tool bench at
`Z:\Backup\Ai Documentation\Modding` (~5 GB, inventoried 2026-10-16). It is
reference tooling, not part of this pack and never an install target for it:
resolve a tool from it only when the current task needs one, and prefer the
route below over reinstalling anything.

Hardcoding that path as authority is wrong for other machines - it is a hint
for this one, like every path in this skill.

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
| Specific games | Helldivers 2: `HD2Runtime-0.28.1` (runtime/sdk/template), `HD2Runtime-ModBuilder-v1.7.1`, `HD2SDK-CommunityEditionV3-11-0`; Risk of Rain 2: `R2API-master`; Sleeping Dogs 2: `SDK-theory`, `TheoryEngine-main` | These are the per-game routes the owner validated; start from their READMEs |
| Tool-state snapshot | `Reverse Engineer/snapshot_2026-05-27_12-11/release/` (release notes, `ntstatusdb`, `errordb`, `winconstants`) | Historical evidence from a Gegenbauer tool release, not a live tool |

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
