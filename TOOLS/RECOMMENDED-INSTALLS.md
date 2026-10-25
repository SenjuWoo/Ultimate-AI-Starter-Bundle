# Recommended installs (UABS AIO)

## Easiest

```powershell
.\START-HERE.bat
```

## What you get

| Tool | Bundled offline | GitHub updates |
|---|---|---|
| Skills (all providers) | yes (pack) | pack updates |
| houseCARL | yes zip | Avick3110/houseCARL |
| codebase-memory-mcp | yes zip | DeusData/codebase-memory-mcp |
| Headroom | yes wheel | headroomlabs-ai/headroom |
| Superpowers | yes zip + plugins/ | obra/superpowers |
| Ponytail | yes zip + plugins/ | DietrichGebert/ponytail |
| CodeBurn | npx/npm | getagentseal/codeburn |
| Skyrim Forge 6.0.1 | yes zip | SenjuWoo/SkyrimForge |

## Later updates

```powershell
.\TOOLS\Update-From-GitHub.ps1
.\TOOLS\Ensure-Tools.ps1
```

## Runtimes (installer tries winget)

- .NET 10 Runtime (houseCARL, when the Skyrim pack is active)
- Python 3 (Headroom)
- Node.js LTS (CodeBurn)

## Bundle-managed

Skyrim Forge 6.0.1 is released from `SenjuWoo/SkyrimForge` and is installed, health-checked with `forge doctor`, skill-wired, and MCP-registered by the AIO installer when the Skyrim pack is active. `SKYRIM_FORGE_ROOT` and the per-provider skill descriptor are generated automatically; no manual extraction is part of a fresh install. The install directory never carries a version suffix, so an upgrade cannot disconnect a provider whose MCP command is an absolute path.
