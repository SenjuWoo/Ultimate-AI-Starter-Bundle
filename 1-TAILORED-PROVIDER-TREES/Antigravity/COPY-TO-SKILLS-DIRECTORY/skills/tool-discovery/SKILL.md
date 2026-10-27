---
name: tool-discovery
description: Resolve optional AI tooling on the current machine without assuming drive letters or usernames. Use at session start, when a tool path is unknown, or before recommending install.
metadata:
  version: 6.0.0
---

# Tool discovery (portable)

Use the working user `python` on PATH (`UABS_PYTHON` when set). Probe it before
installing anything; a WindowsApps alias may be the working Python install
manager. Reuse this base for venv/uv dependencies with runtime downloads off.
If a package rejects its version, report that compatibility conflict instead
of silently downloading another interpreter. App-owned embedded runtimes stay
with their app and do not become the shared Python.


For browser work, use native tools first; the optional shell fallback is
[Playwright CLI](references/browser-cli.md), installed without an MCP schema
or a second skill-directory writer.

For local image/video workflows, discover ComfyUI first and consult the
optional [ComfyUI CLI](references/comfy-cli.md). It adds no standing MCP schemas.

For Xmake, common compilers and project-local Nx/Turbo/Vite/webpack, read
[shared build tool ownership](references/build-tools.md). Reuse the project lock.

For binary/app analysis or unfamiliar-game reverse engineering, use
[the RE routes](references/reverse-engineering.md): Universal Modder for recon,
the existing Reverse THIS! bench for tools, REA CLI for structured evidence.

For game modding on the owner's bench, use the
[local modding bench map](references/modding-bench.md): which engine route each
installed tool serves, and the rules that keep the game install and the bench
untouched.

Never hardcode `C:\Users\<name>`, `S:\Apps`, or `Z:\Backup` as authority. Those may appear only as **example** paths on the pack author's machine.

Treat pasted roots as hints. When the user says a path is "just suggestions" and pastes a game folder or a tools root, those are step-5 conversation candidates, not install authority. Resolve via env, `PATH`, and the conversation path. Do not hardcode them as a game or tool root.

## Resolution order (every tool)

1. Environment variable listed for that tool (if set and path exists).
2. Provider skill-local descriptor (`INSTALLATION.json` beside the skill) when present.
3. Well-known defaults under `%USERPROFILE%` and `%LOCALAPPDATA%`.
4. `PATH` / `where.exe` / `Get-Command`.
5. User-supplied absolute path from the current conversation.
6. **If the binary EXISTS but its MCP tools are not callable, stop — this is
   not necessarily an install problem.** Check scope, trust, filters and the
   real handshake first. Most MCP servers here are registered per project, so
   "installed" and "enabled here" are different states. Recommending an install
   here tells the user to install something they already have.
7. Only if the binary is genuinely absent from disk → **install it with the
   pack's installer or the owning repository's installer** (a fake or assumed
   install is still forbidden), then run it. Only when no supported install
   exists, say so plainly.

## Two different failures, two different answers

| What you see | State | Response template |
|---|---|---|
| MCP tool search returns 0 results; binary present on disk | installed, **not enabled for this project** | NOT ENABLED (below) |
| Binary absent from every path in the resolution order | not installed | TOOL MISSING (below) |

### NOT ENABLED response template

```text
TOOL PRESENT BUT NOT ENABLED HERE: <name>
WHY:   task MCP servers stay out of every chat until a task needs one
NOW:   toolbox `find` "<what you need>" (project: "<project>") -> `describe` -> `call`
       It starts the server in THIS chat. Nothing for the user to type or restart.
ELSE:  only when no toolbox is connected, run it yourself:
       TOOLS\Set-McpProfile.ps1 -Auto -Path "<project>"   (or -Enable <profile>; -Detect shows what applies)
       Native wiring reaches the next chat in that project: a running session does
       not pick up a new MCP server, so say the AI app needs a restart only then.
```

Profiles worth naming: `code-intel` (codebase-memory + serena), `web`
(Chrome DevTools/shadcn when relevant; Playwright CLI is separate), and the
game/engine profiles (`game-*`, `engine-*`) that activate a game's own Forge or
editor MCP only inside a matching project. `-List` marks each server
`REGISTERED for the project above` or `ready, but NOT registered`; the second
one is always one command away, on providers with project scope. Kimi needs
explicit global opt-in; Hermes uses native named profiles. See
`capability-profiles` for supported activation.

### Missing-tool response template

```text
TOOL MISSING: <name>
WHY NEEDED: <one sentence>
INSTALL: <official URL, pack section, or the owning repository>
VERIFY: <one command that must succeed>
OPTIONAL: continue without it using <fallback>
```

Only recommend tools that help the active task. Do not nag about every optional tool every turn.

## Game-specific tools are not bundled

Game toolchains (Skyrim Forge and houseCARL, RimWorldForge, RobloxForge,
SaintsRowForge, AvatarForge ...) live in their own repositories and install
themselves; the bundle only knows how to *activate* an installed one per
project (`game-*` profiles, parked-server rules). When a game tool is absent,
say which repository owns it and use the TOOL MISSING template; for Skyrim that
is `https://github.com/SenjuWoo/SkyrimForge`
(`Install-AI-Bridge.ps1 -Provider All -WithHouseCarl`). Look for the tool's own
environment variable first (for example `SKYRIM_FORGE_ROOT`,
`HOUSECARL_MCP`, `ROBLOX_FORGE_ROOT`) and its skill-local `INSTALLATION.json`.

## Environment variables (optional, user-set)

| Variable | Tool |
|---|---|
| `CODEBASE_MEMORY_MCP` | Full path to `codebase-memory-mcp.exe` |
| `HEADROOM_CMD` | `headroom` executable or `python -m headroom` entry |
| `UABS_TOOLBOX_CMD` | `uabs-toolbox` executable |
| `UABS_PYTHON` | The shared user Python the bundle reuses |
| `UABS_TOOL_ROOTS` | `;`-separated extra folders where the user keeps tool checkouts |

## Discovery script

Run the bundled script when available:

```text
tool-discovery\scripts\discover_tools.ps1
tool-discovery\scripts\discover_tools.ps1 -Json
```

It prints FOUND / MISSING for each general tool and never modifies the system.

## Per-tool checks (Windows)

### codebase-memory-mcp

- Env: `CODEBASE_MEMORY_MCP`
- Default search:  
  `%LOCALAPPDATA%\Programs\codebase-memory-mcp\codebase-memory-mcp.exe`
- Verify: `codebase-memory-mcp.exe --version`
- Install: https://github.com/DeusData/codebase-memory-mcp  
  PowerShell installer from upstream `install.ps1` (optionally `--ui`)
- Provider wiring: MCP server entry must point at the **exe** with adequate startup timeout (Grok often needs 90s+)
- Grok repair helper ships in pack: `TOOLS\Fix-Grok-Codebase-Memory-Direct.ps1` (edit paths first)
- Fallback: ripgrep / codebase explore without graph

### Headroom

- Env: `HEADROOM_CMD`
- Verify: `headroom --help` or `python -m headroom --help`
- Install: https://github.com/headroomlabs-ai/headroom  
  `pip install "headroom-ai[mcp]"` or `"headroom-ai[proxy]"` then `headroom mcp install` where supported
- Tools (when MCP up): compress / retrieve / session stats
- Fallback: work without compression; warn on large contexts

### Superpowers

- Process skills under provider skills or Claude plugin cache
- Install: https://github.com/obra/superpowers
- If missing: follow pack-bundled copies of the skill markdown; recommend plugin install for hooks/automation

### Ponytail

- Skills: `ponytail`, `ponytail-review`, `ponytail-audit`, …
- Install: https://github.com/DietrichGebert/ponytail
- If missing: use bundled skill text; recommend plugin for native `/ponytail` UX

### CodeBurn

- Verify: `npx codeburn --help` or `codeburn --help`
- Install: https://github.com/getagentseal/codeburn — `npx codeburn` or `npm i -g codeburn` (Node 22.13+)
- Purpose: local AI token/cost dashboards and waste scans — not a build tool
- Fallback: skip cost analytics

## Provider MCP config pointers

| App | Typical config |
|---|---|
| Claude Code | Plugin / `.mcp.json` / Claude settings |
| Codex | `%CODEX_HOME%\config.toml` or Codex MCP UI |
| Grok Build | `%USERPROFILE%\.grok\config.toml` → `[mcp_servers.<name>]` |
| Cursor | MCP settings JSON |
| Others | Follow that app's MCP docs |

After editing MCP config: **fully restart** the AI application.

## Safety

- Discovery is read-only.
- Never copy another user's absolute paths into a shareable release.
- Never write to a game's live `Data`, mod-manager overwrite, or saves while "just checking tools".

---

## AIO installer (pack)

New users and missing-tool recovery:

```powershell
# Pack root
.\INSTALL-AIO.ps1
.\INSTALL-AIO.ps1 -Mode OnlineLatest
.\TOOLS\Ensure-Tools.ps1
.\TOOLS\Update-From-GitHub.ps1
```

Offline snapshots live in `BUNDLED-TOOLS\offline\`. Component registry: `BUNDLED-TOOLS\CATALOG.json`.
After MCP changes the user must **fully restart** the AI application.
