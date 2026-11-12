---
name: ai-tooling-stack
description: Which tool or owner forge to use for a task - general AI, compiler and workspace tools, plus the forges for Skyrim, Risk of Rain 2, Roblox, Minecraft, RimWorld, Saints Row, VRChat avatars, reverse engineering, asset production (AssetForge), ComfyUI images (comfy-forge) and Koikatsu/Honey Select 2 cards (illusion-forge), and the standard a new or upgraded forge must meet. Discover installs before installing.
metadata:
  version: 7.2.0
---

# AI tooling stack

Pick the smallest tool set that does the job. Resolve real paths with `tool-discovery`; a table entry is not
proof that a tool is installed, enabled or healthy. Preserve models, reasoning, trust, credentials and settings.

## General work (owned by this bundle)

| Task | First route |
|---|---|
| AI setup, workspace hygiene, settled project results | `project-intel`, `capability-profiles`, `tool-discovery` |
| Source navigation and impact | `codebase-memory`; index source, never asset or dependency trees |
| Current library/API documentation | Context7, else the vendor's primary docs |
| Context and token management | `headroom`, `token-efficiency`; measure real usage, not schema bytes as billed tokens |
| Coding, tests, releases | `coding-discipline`, `check-work`, `release-checklist`, authenticated `gh` |
| Compilers, shared Python/Node | the bundle's prerequisite installer; reuse current tools, keep project pins |
| Free procedural assets: 3D, textures, images, music, sound, games | `game-dev-starter` (`references/free-creative-tools.md`), `img2threejs`; AssetForge and comfy-forge when installed |
| Unknown game: engine recon, sprites, gameplay video | `universal-modder` (`um`), then the engine skill (`unity-`/`unreal-mod-frameworks`, `game-modding`) |

## Specialist forges (separate public repositories)

Each forge ships its own skill, tools and updates. When a task is in its domain, use the forge's skill and CLI;
the bundle keeps no second copy. If the forge is absent, say which repository owns it (TOOL MISSING template in
`tool-discovery`), install it with its own installer when the user's task needs it, then use it.

| Domain | Repository (github.com/SenjuWoo/...) | Start | Find it |
|---|---|---|---|
| Skyrim SE/AE records, Papyrus, assets, load order | `SkyrimForge` (+ houseCARL) | bundle `START-HERE.bat -Packs skyrim`, or the Forge's `START-HERE.bat`; then skills `skyrim-memory`, `skyrim-tooling-stack` (Forge vs houseCARL vs MCP), `skyrim-tool-router` | `SKYRIM_FORGE_ROOT`, `HOUSECARL_MCP` |
| Skyrim RaceMenu face from a photo / follower without the Creation Kit | `FaceForge` / `FollowerForge` | release download | the user's install |
| Risk of Rain 2 survivors, items, Thunderstore packages | `Risk-Of-Rain-2-Forge` | `forge.cmd doctor`, `forge guide`; skill `ror2-forge` | `ROR2_FORGE_ROOT` if set, else `UABS_TOOL_ROOTS` |
| Roblox games, Luau, Studio | `RobloxForge` | `Install.ps1` (installs `roblox-game-development` and `roblox-docs` into your agents), `rbforge doctor`, `rbforge docs search` | `ROBLOX_FORGE_ROOT` |
| Minecraft Java on NeoForge | `Minecraft-Forge` | `Minecraft-Forge.ps1 doctor` (or `python -m mcforge doctor` in its folder); read its `AGENTS.md`, no global install | `UABS_TOOL_ROOTS` |
| RimWorld 1.6 | `RimWorldForge` | `START-HERE.bat`, `rwforge doctor`, `rwforge capabilities`; skill `rimworld-forge` | `UABS_TOOL_ROOTS` |
| Saints Row: The Third / IV | `SaintsRowForge` | `START-HERE.bat`; `srforge doctor`; `AI-INTEGRATION.md`, `knowledge/` | `%LOCALAPPDATA%\SaintsRowForge` |
| VRChat avatar from Blender/XPS/MMD/VRM/Source | `AvatarForge` | release ZIP, `INSTALL-TOOLS.bat`; skill `avatarforge` | the user's install |
| Binary/app reverse engineering, game hooks, website API reconstruction | `reverse-this` (Reverse THIS!) | `Install-Modkit.ps1 -Doctor`; skill `reverse-engineering`; `reverse-api-engineer.cmd` for private web APIs | installed kit manifest |
| 2D/3D asset production, validation, game-ready meshes, engine export | `AssetForge` | release ZIP, `Install.ps1`; `assetforge doctor` | `UABS_TOOL_ROOTS` |
| Anima images on ComfyUI/SwarmUI, checkpoint merges, LoRA captions, image-to-3D | `comfy-forge` | `TOOLS\image-stack.ps1 status`, then `install` / `generate`; finished `.glb` goes to AssetForge via `TOOLS\game-ready.ps1` | `UABS_TOOL_ROOTS` |
| Koikatsu / Honey Select 2 character cards from a prompt | `illusion-forge` | `Install.ps1`, `forge.cmd doctor`; skill `illusion-forge`; MCP `illusionforge mcp` scoped to the task | `UABS_TOOL_ROOTS`; games via `ILLUSION_KK_ROOT` / `ILLUSION_HS2_ROOT` |

Building a forge, or bringing an older one up to date: `references/forge-standard.md` is the bar (doctor,
routing, evidence tiers, reproducible release). Read it before designing the forge's CLI.

Minecraft Fabric/Quilt and other loaders have no forge: use their official docs (docs.fabricmc.net,
quiltmc.org) and `game-modding`'s laws. A game with no forge uses `game-modding`.

## Rules

The bundle is the general entry point; forges own their catalogs and updates and run independently. Read owner
receipts before downloading another copy. App venvs and pinned project SDKs are legitimate isolation; reuse a
compatible base runtime. Never overwrite an unknown external version or an edited payload to hide uncertainty.
Load only the task's profile and MCP. Diagnose a broken tool first; report a required host restart honestly.
