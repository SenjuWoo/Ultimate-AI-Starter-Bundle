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

```sh
# example: Godot only, into a Claude-style skills directory
cp -r skills/godot/* "$HOME/.claude/skills/"
cp LICENSE NOTICE "$HOME/.claude/skills/godot-pack-LICENSE.txt" 2>/dev/null || true
```

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

## When it loads

- The project's engine matches a category in the pack (`project.godot`,
  `Assets/` + `ProjectSettings/`, an `.uproject`, a web-engine `package.json`).
- The task is engine-specific and no Forge owns the project.
- Nothing loads for a non-game task, and nothing loads merely because the pack is
  installed.

## Updating and removing

- Update: `git pull`, re-read the diff, rerun `python scripts/validate-skills.py`,
  then record the new revision here and in `BUNDLED-TOOLS/COMPANIONS.json`. The
  bundle never follows upstream automatically.
- Remove: delete the copied skill directories and their license files. The bundle
  keeps working; the detector reports `NOT_FOUND`.

## Known limitations

- Not tested against the bundle's own contract suite; it is a pointer, not a
  dependency.
- The pack's router assumes it is the only router. With this bundle installed, the
  bundle's routing skills decide, and the pack supplies content only.
- Roblox skills in its `other-engines` category are generic; RobloxForge remains
  authoritative for Roblox work, including Studio, Rojo and Open Cloud specifics.
- No automatic install, update or rollback: those steps are manual by design, so a
  compromised or broken upstream release cannot reach an installed machine
  through this bundle.
