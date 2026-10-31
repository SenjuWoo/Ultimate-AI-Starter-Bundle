---
name: mod-workspace-organization
description: Use when starting, resuming, or tidying a game-mod project so source, package, release, state and caches stay separate and safe to repair.
metadata:
  version: 1.0.0
---

# Mod workspace organization

A mod project is not one folder of files. It has four different kinds of
content that must never be mixed: **source**, **package**, **release** and
**state**. A FOMOD package is a valid package root; it is not automatically the
project root, and it is never the place for caches, old snapshots or notes.

Read `workspace-organization` first for `WORKSPACE_OWNERSHIP.md`, the one owner
and the publication boundary. This skill adds the mod-specific layout and the
safe repair pass.

## Canonical layout

```text
<project>/
  WORKSPACE_OWNERSHIP.md   owner and publication intent
  README.md                public page
  CHANGELOG.md
  LICENSE
  .gitignore
  VERSION                  one current version, or .uabs/state.json
  src/                     source: ESP source, Papyrus, C++, scripts
  assets/                  source art, audio, textures, meshes, blend files
  package/                 clean install tree: fomod/, 00 Core/, 01 ...
  docs/                    notes, plans, decisions, presentation/
  dist/                    release zips and archives (git-ignored)
  .uabs/                   state, build receipts, backups (git-ignored)
  tools/                   project-local build/package scripts
```

A small mod may put the package at the project root (`fomod/`, `00 Core/`,
`01 .../`) and keep `src/`, `docs/`, `dist/` and `.uabs/` beside it. That is
valid only when the root package is the **current** package and nothing else is
dumped there. Version snapshots, caches and old packages belong under
`dist/versions/`, `dist/archive/` or outside the project.

## Classify before you move

| Kind | Examples | Rule |
|---|---|---|
| source | `src/`, `source/`, `scripts/`, C++/Papyrus sources | keep, edit here |
| package | `fomod/`, `00 Core/`, `01 .../`, `meshes/`, `textures/`, `skse/`, `seq/` | ship exactly as installed; do not rename |
| release | `publication/`, `release/`, `dist/`, zips | generated; never edit as source |
| state | `STATE.md`, `PLAN.md`, `DECISIONS.md`, `VALIDATION.md`, `CURRENT.txt`, `VERSION`, `*.manifest.json` | keep one version source; state is not a release |
| research | `RECOVERY/`, `RESEARCH/`, `ghidra-*`, `pseudocode/`, notes | keep out of the package; archive under `research/` |
| cache | `build/`, `obj/`, `vcpkg/`, `extern/`, `ForgeVault/`, `ForgeWorkspaces/`, `.venv/`, `node_modules/` | ignore or relocate; never ship |

**One version source.** `CURRENT.txt` + `VERSION` + `fomod/info.xml` +
`publication/<ver>` is four sources and they will disagree. Keep one `VERSION`
or `.uabs/state.json` as the authority, let the FOMOD and release inherit it,
and put old packages under `dist/versions/<ver>/` only after checking for
references.

**FOMOD paths are relative.** `fomod/ModuleConfig.xml` points at `00 Core/`,
`01 .../` and file names. Moving or renaming those folders breaks the installer
even when the files still exist. Treat a FOMOD root as path-dependent.

## Analyze and repair

Run the analyzer before you reorganize anything:

```text
python TOOLS/workspace_doctor.py <project>
python TOOLS/workspace_doctor.py <project> --json <plan>.json --markdown <plan>.md
```

It reports entries by kind, flags a stale root FOMOD (for example root
`2.0.4` while `CURRENT.txt` says `3.0.0`), counts version snapshots, finds
nested caches such as `github-repo/build` or `TOOLS/vcpkg`, and checks whether a
candidate is referenced by a text file.

`--apply` is deliberately narrow:

- moves only **high-confidence, unreferenced** loose media, notes and docs;
- writes a backup manifest under `.uabs/workspace-backup/<timestamp>/`;
- never deletes anything;
- never moves a FOMOD root, a version snapshot, a nested Git repository, an
  `.esp/.esm/.esl/.bsa/.ba2/.nif/.dds/.hkx/.pex/.dll` asset, or a path-dependent
  file;
- skips a target that already exists instead of overwriting.

So the safe flow is: **analyze → read the review list → move the obvious
clutter → archive old snapshots deliberately → re-run the analyzer**. Do not
force the tool to "fix" a path-dependent package.

## When the workspace is already messy

1. Read `WORKSPACE_OWNERSHIP.md` and `CURRENT.txt`/`VERSION` first. The owner
   record wins over folder names.
2. Run `workspace_doctor.py` and read the warnings. A stale root FOMOD is a
   release blocker, not cosmetic.
3. Pick the current package: the one whose FOMOD version matches `CURRENT.txt`.
   If none matches, stop and reconcile the version before moving anything.
4. Archive old snapshots under `dist/versions/<ver>/` only after grepping the
   project for their names. If a script or README references the old path,
   leave it and record the dependency.
5. Move caches out of the package or add them to `.gitignore`. Never ship
   `build/`, `vcpkg/`, `ForgeVault/` or a Ghidra cache.
6. Re-run the analyzer and the mod ship gate. A cleaner tree that breaks the
   FOMOD is worse than the mess.

## Done means

- one current version source, and the FOMOD/release agree with it;
- one current package root; old snapshots archived, not scattered;
- source, package, release and state are separate;
- caches are ignored or outside the package;
- `workspace_doctor.py` shows no stale-root warning and no unreviewed
  path-dependent move;
- `WORKSPACE_OWNERSHIP.md` and `STATE.md` name the owner, current version and
  next step.

For public presentation, use `mod-presentation`. For Skyrim's version-folder
discipline, use `skyrim-versioned-workspace`; for paths with `!` or junctions,
use `windows-workspace-ops`.
