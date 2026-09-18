---
name: workspace-organization
description: Use when starting, placing, or scaffolding a project, or entering a workspace with no map — settle the root with the user, keep layout tidy, maintain WORKSPACE.md.
---

# Workspace organization

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
  WORKSPACE.md
  <Project Name>\
    src\          source; the Git repository root when the project is one repo
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
