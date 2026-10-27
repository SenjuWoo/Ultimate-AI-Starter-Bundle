---
name: workspace-organization
description: Use before substantive project writes to establish WORKSPACE_OWNERSHIP.md, reuse the source owner and keep new work local/private. WORKSPACE.md is only a multi-project map.
---

# Workspace organization

## Project ownership is a file, not an assumption

Before the first substantive write, locate the authoritative source project and
read `WORKSPACE_OWNERSHIP.md` at its root. If it is missing, create it now with
this skill's `scripts/ensure_ownership.py <settled-project-root>`; do not merely
promise to add it later. `--check` validates without writing. The helper never
creates a Git repository, remote or publication and never overwrites an existing
ownership record. Read any linked legacy ownership evidence before proceeding.

The record identifies the project root, active source/snapshot, established
versioning, read-only references, repository/publication intent, staging/output
paths and recovery commands. Fill project-specific facts from files and the
user's scope; use relative paths where possible. An arbitrary timestamp, folder
name or another agent's private memory is not ownership proof.

`WORKSPACE.md` maps several projects; `STATE.md` records progress; `AGENTS.md`
and `CLAUDE.md` carry instructions. None substitutes for the canonical project
ownership file. Existing `OWNERSHIP.md`/`PROJECT_OWNERSHIP.md` records stay intact;
the canonical file points to them. Conflicting owners require resolution before
editing. Reuse the same owner across providers and sessions.

## Publication is a separate boundary

New work stays local/private. Finishing code, making a mod or preparing a release
candidate does not authorize creating a public repository or uploading it.
Local Git is fine when it fits the project. Create a remote only when requested.
"Put it on GitHub" authorizes a public repository and MIT for original work by
default; respect explicit privacy/licensing choices, third-party rights and
platform terms. Never relicense dependencies or an existing project by assumption.
"Make it public" selects the appropriate distribution site: for Skyrim, normally
Nexus Mods. Mods needing no compilation do not get a GitHub repository by default
merely to duplicate the editable files already shipped in the mod. Other products
likewise publish where users consume them; add source hosting when it serves the
project or the user requests it. Ask only if the destination materially changes
the outcome and context does not settle it.
Preserve an existing repository's remote, visibility and release process.

For an existing-repository update, include appropriate README/changelog/version
maintenance, tests and the scoped commit/push/release work the user requested or
already authorized. Do not ask again for that authority. When publication is not
authorized, finish and validate the local candidate first; ask only at the
concrete publication boundary if publishing is actually part of the request.

## Ask where work lives

If the workspace root is not already established, ask before creating anything.
Offer two or three concrete candidates (a projects drive or an existing folder)
instead of an open question, and never default to the user profile directory
(`C:\Users\<name>`): that is the operating system's home, not a workspace.
Projects there end up inside profile backups, roaming sync and cleanup sweeps
that were never meant to hold them.

Ask once. Record the answer in the workspace memory file, not in chat memory,
so the next session does not ask again. If work must proceed before an answer,
propose one path, label it as a proposal, and keep it easy to move.

## Layout: source, output and scratch apart

```text
<WORKSPACE_ROOT>\
  WORKSPACE.md     optional map when this folder contains several projects
  <Project Name>\
    WORKSPACE_OWNERSHIP.md  mandatory project owner; source metadata only
    src\          source where the stack uses it; Git stays at the project root
    build\        compiled output (git-ignored) - also dist\ or bin\ by stack
    docs\         notes, plans, changelogs
    artifacts\    release zips and release scratch (git-ignored)
```

- A built executable inside the source tree is a defect: it confuses what is
  tracked, what git-ignoring means, and what a cleanup may delete. Build to
  `build\` and reference it from there.
- One project = one folder. Versions are Git tags by default; when a project
  genuinely needs snapshot folders (mod packages, binary drops), use the
  version-folder discipline in `skyrim-versioned-workspace`.
- Paths with `!`, junctions and MSYS quoting are covered by
  `windows-workspace-ops`.
- Temporary work never lands in the workspace at all - see `scratch-hygiene`.

## The workspace memory file

`WORKSPACE.md` at the workspace root is the map the next session reads instead
of re-exploring the tree and re-fetching context it already paid for.

```markdown
# WORKSPACE
root: <absolute path>
projects:
| name | path | stack | build | version scheme | releases |
|---|---|---|---|---|---|
| Example | Example\ | Python | python build.py | semver tag | GitHub Releases |
gotchas:
- <one line each: a path that lies, a command that needs a flag, a slow step>
```

- Read it first when entering the workspace; it is cheaper than discovery.
- Update the row you touched when paths, build commands or release targets move.
- Keep it under one screen. No secrets, tokens or personal data.
- If projects exist and no map does, offer to create one - it is the cheapest
  token saving in the workspace.

## Done means

A fresh session - human or agent - opens the workspace root, reads
`WORKSPACE.md`, and knows where the source is, how it builds, where the output
lands, and how a release happens. If it has to search for any of that, the map
is stale or missing.
