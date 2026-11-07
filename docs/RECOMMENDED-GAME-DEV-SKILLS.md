# Recommended engine skill packs: awesome-gamedev-agent-skills

An optional, third-party catalogue of engine-specific agent skills. The bundle
**points at it and detects it**; it never installs, updates or executes it, and it
vendors none of its skills.

Reviewed 2026-11-07.

| Field | Value |
|---|---|
| Upstream | [gamedev-skills/awesome-gamedev-agent-skills](https://github.com/gamedev-skills/awesome-gamedev-agent-skills) |
| Pinned revision | `19d93f97c9c1ea0f8b306e77aa81e0d3e352d3e9` (2026-10-28) |
| License | Apache-2.0, with attribution and trademark notes in `NOTICE` |
| Size | 78 `SKILL.md` files (77 skills plus the router), about 4.4 MB |
| Layout | `skills/<category>/<skill>/SKILL.md`, categories `godot` (16), `unity` (8), `unreal` (6), `web-engines` (6), `other-engines` (12), `genres` (9), `disciplines` (15), `workflows` (4), `ebitengine` (1), plus `router/` |
| Tooling | `scripts/validate-skills.py`, `scripts/generate-site.py`, a `tests/` suite and GitHub Actions; no installer, no dependency outside the Python standard library |
| Status | Active (234 commits, pushed 2026-10-28), Apache-2.0, not archived |

## What it is for

Generic engineering guidance per engine: Godot scene and signal patterns, Unity
component and addressables work, Unreal Blueprint/C++ boundaries, web-engine
render loops, plus genre and discipline notes (economy, level design, audio,
narrative pacing). It complements the bundle's own routing instead of replacing
it: the bundle decides *what kind of work this is* and *who owns it*, this pack
supplies engine idioms for the part that belongs to no Forge.

## Why it is not vendored

The bundle's rule is that platform-specific material belongs to its owner. Roblox
skills live in RobloxForge, Skyrim in SkyrimForge, and the canonical set stays at
81 skills so a fresh session never carries an engine catalogue it does not need.
Copying 77 skills into the bundle would duplicate that rule, inflate the manifest
by several megabytes and put an unmaintained snapshot in front of a repository
that ships updates every week.

## Installing it yourself (optional)

```sh
git clone https://github.com/gamedev-skills/awesome-gamedev-agent-skills.git
cd awesome-gamedev-agent-skills
git checkout 19d93f97c9c1ea0f8b306e77aa81e0d3e352d3e9   # the reviewed revision
python scripts/validate-skills.py                        # the project's own gate
```

Then copy only the skills for the engine you actually use into your provider's
skills directory, keeping `NOTICE` and `LICENSE` beside them:

PowerShell, the bundle's main platform, run from the clone's root (Godot only,
into a Claude-style skills directory). Copy the license and notice as two separate
files next to the skills; back up an existing `godot` folder first if you have one:

```powershell
$pack   = (Get-Location).Path
$target = "$HOME\.claude\skills"
New-Item -ItemType Directory -Force -Path $target | Out-Null
# Back up any skill folder this pack is about to replace; nothing is overwritten silently.
Get-ChildItem (Join-Path $pack "skills\godot") -Directory | ForEach-Object {
    $dest = Join-Path $target $_.Name
    if (Test-Path $dest) { Move-Item $dest ($dest + ".backup-" + (Get-Date -Format yyyyMMdd-HHmmss)) }
}
Copy-Item -Path (Join-Path $pack "skills\godot\*") -Destination $target -Recurse -Force
Copy-Item (Join-Path $pack "LICENSE") (Join-Path $target "godot-pack-LICENSE.txt") -Force
Copy-Item (Join-Path $pack "NOTICE")  (Join-Path $target "godot-pack-NOTICE.txt")  -Force
```

On a POSIX shell the same two copies are `cp -r skills/godot/* "$HOME/.claude/skills/"`
followed by a separate `cp LICENSE ...` and `cp NOTICE ...` — one file per command,
because `cp` treats the second path as a directory when given two sources.

Do not copy `router/` into a provider that already has the bundle's routing
skills; two routers answering the same question is the overlap this document
exists to prevent.

## Precedence when guidance disagrees

Applied in this order, first match wins:

1. The project's own `AGENTS.md`, `CLAUDE.md`, `PLAN.md` and existing code.
2. The engine version installed on the machine and its official documentation.
3. The owning Forge — RobloxForge, SkyrimForge, or the project's own forge.
4. This pack's generic skill for the same engine and discipline.
5. The bundle's engine-neutral guidance (`game-dev-starter`, `capability-routing`).

## What the bundle actually does: discovery, not loading

The bundle runs no install step and loads none of these skills. What exists today:

- `BUNDLED-TOOLS/COMPANIONS.json` records the pack under `recommended`, with its
  license, the reviewed revision and the marker files used for detection.
- `python TOOLS/companion_registry.py` reports, per pack:
  - `MARKERS_FOUND` — the marker files exist under a folder named after the
    repository, so this *looks like* a checkout. It says nothing about which
    revision is present, whether the skills were copied anywhere, or whether they
    parse; verify with `git -C <path> rev-parse HEAD` against the pin.
  - `NOT_FOUND` — no such folder in the searched roots.
- That is the whole integration. Reading a skill is still the agent's decision,
  made through `game-dev-starter` and `capability-routing`.

### How the detector finds a manual clone

It searches, in order, and stops at the first folder whose name matches the
repository and which contains the markers (`router/SKILL.md`, `skills`, `LICENSE`):

1. Directories passed with `--roots` (`--roots D:\Tools`).
2. `UABS_TOOL_ROOTS`, split on the platform path separator.
3. `%USERPROFILE%\.uabs\profile\TOOL-ROOTS.txt` — one absolute path per line, `#`
   for comments; the same list the bundle's tool discovery uses.
4. The bundle's default search roots.

A clone anywhere on those roots is found; a clone in an unrelated folder is not,
and the fix is `--roots`, not a drive walk.

## When an agent may read the pack

Nothing here is automatic. If, and only if, the project is a real engine project
and no Forge owns it, an agent may read the pack's skill for that engine:

- The engine is detectable (`project.godot`, `Assets/` + `ProjectSettings/`, an
  `.uproject`, a web-engine `package.json`).
- The task is engine-specific.
- Nothing is read for a non-game task, and nothing is read merely because the pack
  was detected.

## Updating and removing

- Update: `git pull`, re-read the diff, rerun `python scripts/validate-skills.py`,
  then record the new revision here and in `BUNDLED-TOOLS/COMPANIONS.json`. The
  bundle never follows upstream automatically.
- Remove: delete the copied skill directories and their license files. The bundle
  keeps working; the detector reports `NOT_FOUND`.

## Known limitations

- Not tested against the bundle's own contract suite; it is a pointer, not a
  dependency.
- Detection is marker-only and never proves the pinned revision, so re-check the
  clone yourself after an update.
- The pack's router assumes it is the only router. With this bundle installed, the
  bundle's routing skills decide, and the pack supplies content only.
- Roblox skills in its `other-engines` category are generic; RobloxForge remains
  authoritative for Roblox work, including Studio, Rojo and Open Cloud specifics.
- No automatic install, update or rollback: those steps are manual by design, so a
  compromised or broken upstream release cannot reach an installed machine
  through this bundle.
