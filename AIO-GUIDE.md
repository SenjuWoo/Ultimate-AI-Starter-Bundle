# AIO guide: install, discover, activate, verify

Run `START-HERE.bat` from the extracted pack. It selects detected providers,
installs default tools/skills, merges owned settings and checks core MCPs.
Restart affected apps after wiring changes. Installed does not mean connected.
See [quick start](README.md#quick-start) for remote install, modes and recovery.
Web UIs use [MANUAL-PASTE.txt](3-PREAMBLES/MANUAL-PASTE.txt).

## Let the task select the tools

The shared `capability-profiles` recipes compose skills, CLIs and project MCPs
for games/mods, UI, assets, code and publication. Agents can inspect a route with
`TOOLS\Set-McpProfile.ps1 -Task <task IDs> -Path '<project>' -Plan`, then apply it
for the current provider. See [task routing](docs/TASK-ROUTING.md). Personal
entries stay intact; editor prerequisites and host reload requirements are real.

## When an AI cannot find a tool

1. Use `tool-discovery` / `ai-tooling-stack` and `TOOLS\discover_tools.ps1`.
2. If installed but disconnected, inspect project/profile scope; do not reinstall.
3. If absent, use catalog IDs: `INSTALL-AIO.ps1 -ToolsOnly -Components <ids>`.
4. Configure real editor, MO2 or user-supplied credential prerequisites.
5. Restart affected apps and verify initialize/tools-list; never invent results.

From the bundle root, for the actual project folder:

```powershell
.\TOOLS\Set-McpProfile.ps1 -List -Path '<project folder>'
.\TOOLS\Set-McpProfile.ps1 -Detect -Path '<project folder>'
.\TOOLS\Set-McpProfile.ps1 -Auto -Path '<project folder>'
```

Detection is marker-based, not a guess from conversation hints. Unneeded schemas
stay parked. Windows desktop control is opt-in/OFF by default and distinct from
browser automation. Independent servers and user filters are preserved.

## Hermes profiles

The starter has `mcp_servers: {}`; the installer registers Context7, GitHub and
Headroom. The migrator clones the user's default for specialists when prerequisites
exist. Use `hermes -p code`, `hermes -p skyrim` or another existing profile; see
[scope and availability](1-TAILORED-PROVIDER-TREES/Hermes/profiles/README.md).

`TOOLS\Migrate-HermesProfiles.ps1` previews changes; `-Apply` requires Hermes
closed and creates verified rollback backups. Custom models, aliases, timeouts
and filters are retained; exact retired bundle settings are migrated.
[Model guidance](docs/HERMES-MODELS.md) separates compatibility from quality.

## Skyrim tools

Skyrim Forge is included as source and an installed CLI/skill, not an always-on
MCP. Universal Modder and Spooky's toolkit are also CLI capabilities. houseCARL
needs MO2 or a Vortex shim: `TOOLS\Setup-HouseCarl.ps1`; refresh the shim after
load-order changes with `-RefreshOnly`. Structural checks are not gameplay proof.

## Updates and verification

[CATALOG.json](BUNDLED-TOOLS/CATALOG.json) defines pins/holds and component-specific
update strategies. “Latest” does not override holds or guarantee no-network
bootstrap. [Evaluations](docs/TOOL-EVALUATIONS.md) are not default installation.

```powershell
.\TOOLS\Test-Installed-State.ps1
.\TESTS\Test-Pack.ps1
```

These check installed state/ownership and source packaging respectively, not
live game/editor/model inference or a fresh whole-machine installation. Hook
support differs by provider; retired bundle hooks are removed with ownership
checks and backups, not blindly executed.

[Tool notices](BUNDLED-TOOLS/THIRD-PARTY-NOTICES.md) and
[skill notices](_CANONICAL-SKILLS/THIRD-PARTY-NOTICES.md) credit third-party work.
