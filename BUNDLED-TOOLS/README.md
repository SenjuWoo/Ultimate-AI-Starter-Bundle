# BUNDLED-TOOLS

Offline snapshots + GitHub update path for Ultimate AI Starter Bundle AIO.

## Quick install (new users)

Double-click or run from pack root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\INSTALL-AIO.ps1
```

## Layout

| Path | Purpose |
|---|---|
| `offline\` | Zipped tool snapshots shipped with the pack |
| `plugins\` | Superpowers + Ponytail plugin trees (Claude-friendly) |
| `CATALOG.json` | Component IDs, GitHub repos, install rules |
| `cache\` | Created at runtime for OnlineLatest downloads |

## Modes

| Mode | Behavior |
|---|---|
| `BundledFirst` | Use the evaluated offline payload when present; otherwise fetch its catalog release |
| `OnlineLatest` | Check online sources while respecting measured release pins and compatibility holds |
| `BundledOnly` | Require locally bundled payloads; fail when a required archive is absent |

These modes select component payloads, not a complete disconnected Windows
environment. Missing runtimes, Python/npm dependencies and provider bootstrap
can still need network access. Full-Offline carries the declared archive/wheel
snapshots; it does not contain every upstream dependency cache.

## Update later

```powershell
.\TOOLS\Update-From-GitHub.ps1
.\TOOLS\Update-From-GitHub.ps1 -Components housecarl,codebase-memory
```

## Licenses

Redistributed binaries/zips remain under upstream licenses. See each project's GitHub.
Do not re-upload this pack to Nexus as if you own third-party tools.
