# Prompt-first task routing

Tell the AI the result you want. The installed contract points every provider to
`capability-profiles`, which joins the existing skills, profiles and CLIs using
one [recipe source](../_CANONICAL-SKILLS/capability-profiles/references/task-recipes.json).
This is agent-directed routing, not a background classifier or a promise that
every host can hot-load tools. No new daemon, paid service or skill-index entry.

Examples: "Make a Godot platformer with readable UI and a playable build";
"Mod this Unity game and include a showcase clip"; "Make this Skyrim mod look
good in-game and prepare its Nexus page". The agent inspects actual project
evidence, selects the route and performs supported scoped setup without asking
you to memorize MCP names. Models and personal settings stay yours.

| Work | Tool/skill combination |
| --- | --- |
| New Unity/Godot game | That engine bridge + coding/testing + rendered verification; Universal Modder for applicable discovery/assets |
| Unreal game | Discovered engine CLI/editor tools + code navigation/testing + visual proof; no audited Unreal MCP shipped |
| Packaged Unity/Unreal game mod | Universal Modder recon + game-modding + exact loader/framework skill; no unrelated editor registration |
| Skyrim mod | Skyrim router + Forge/Spooky + Universal Modder where relevant; houseCARL only for actual installed-list evidence |
| Meshes/rigs/animations | Blender + asset provenance + target-engine import/preview; Skyrim NIF/PBR skills for Skyrim assets |
| Web interface/browser game | Native browser or scoped Playwright/DevTools + Impeccable or image-to-scene skill + visual/tests |
| Repair/research/local models | Debugging/primary-source/runtime evidence first; compose symbol navigation only when useful |
| Publication | Credits/perms + truthful media + durable public copy + repo/security/CI + exact-SHA archive verification |

## The executable route

Usually the agent handles this. For inspection or recovery, run from the pack:

```powershell
.\TOOLS\Set-McpProfile.ps1 -ListTasks
.\TOOLS\Set-McpProfile.ps1 -Task game-unity,assets-3d,publication -Path "<project>" -Plan
.\TOOLS\Set-McpProfile.ps1 -Task game-unity,assets-3d -Path "<project>" -Providers Codex
```

`-Plan` returns read-only JSON. Recipes compose and deduplicate, including on an
empty project before its first marker exists. The agent chooses the relevant
provider; the writer reuses existing prerequisites, backups and Grok budget.
Task activation does not refresh or claim independently configured entries.
Disable only registrations the bundle owns. Windows desktop stays off without
explicit global opt-in. Public publishing still needs approval.

## Honest activation boundaries

Claude/Grok/trusted Codex can receive project registrations. Configuration is
not trust, a handshake is not an editor connection, and neither proves gameplay.
An already-open chat may need reload/restart. Kimi receives identical skills and
CLI routes; it has no established optional project MCP scope here.

Hermes native `blender`, `unity`, `godot`, `web` profiles isolate phases; ordinary
`default` keeps the small core. Existing `creative` stays for deliberate joint
Blender/Unity work. `code`, `roblox`, `skyrim` and personal profiles remain.
The migrator clones the user's default and preserves models/filters/config,
backs up writes, verifies, and rolls back failures. Run installation with
Hermes closed. A task command prints native profile choices but cannot switch
an already-running Hermes chat or invent an editor plugin. Use CLI fallbacks
now and restart in a required native profile only for the remaining live phase.

Hermes' retained Unity backend is [CoplayDev MCP for Unity](https://github.com/CoplayDev/unity-mcp),
`mcpforunityserver@10.2.0`; the project-scoped catalog route uses IvanMurzak's
Unity MCP. These are different editor packages, not interchangeable launchers.
Use the matching companion package and actual discovered tool definitions.

Universal Modder's bundled capability is CLI/skills. Its upstream fal MCP
requires an account and paid usage; it is not silently registered. Blender,
Unity, Godot, browser runtimes, permissions and real project builds still need
their actual prerequisites. No recipe guarantees a perfect one-shot result.
