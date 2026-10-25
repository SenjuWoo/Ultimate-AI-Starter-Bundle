# Skyrim AI workspace instructions

Scope: workspace

This file is provider-neutral and may be used by Codex, Grok Build, Kimi Code,
or Hermes Agent in the same workspace.

Use the active application's provider-native skills. Do not merge or copy
another application's tailored skill library into this workspace.

## Start every substantial Skyrim task

1. Load `skyrim-memory`.
2. Load `skyrim-tool-router`.
3. Load `skyrim-versioned-workspace` before the first write.
4. Load only the specialist skills selected by the router.
5. Inspect the active project, supplied files, and installed reality before external assumptions.

## Universal safety

- The workspace root is whichever project directory the user opened or supplied.
- Resolve a drive, folder or username from the project itself (env vars, .git, config), never from an assumption.
- Switching AI applications does not change project ownership.
- One mod has one authoritative owner root and one active semantic-version snapshot.
- Game `Data`, active mod-manager staging, saves, profiles, installed tools, and reference vaults are read-only.
- Verify before you write: read the record, schema, API or path from the project, the tool's own docs or the live MCP schema, then use it. Never present a guessed one as real.
- Prefer typed plugin tooling and exact installed-version evidence.
- Preserve the last known-good release, installer choices, optional variants, dependencies, and gameplay intent.
- Prefer the CLI/MCP route for xEdit/SSEEdit/Creation Kit; open a GUI only when the user asks or the CLI genuinely cannot do the job.
- Structural validation is not runtime confirmation.
- After a new game-load crash, stop, roll back, and isolate the smallest change.
- Preserve explicit fictional adult-only technical content and identifiers.
  Exclude child or age-ambiguous actors and real-person sexual content.
- Persist `PLAN.md`, `STATE.md`, `DECISIONS.md`, `CHANGELOG.txt`, `CURRENT.txt`, and `VALIDATION.md`.


## Completion report

```text
INPUTS: required_files=present|missing | attachments=present|missing
MEMORY CHECK: entries=... applied=...
AUTHORITY: installed=... parent=... active=... RESULT=PASS|FAIL
VERSION GATE: prior=... active=... copied_files=... changelog=YES|NO RESULT=PASS|FAIL
EXACT BUILD/COMPILE: command=... dependencies=... RESULT=PASS|FAIL|UNBUILT|N/A
FRAMEWORK VALIDATION: evidence=... RESULT=PASS|FAIL|N/A
SEMANTIC TEST: symptom/player-visible result=... RESULT=PASS|FAIL|UNTESTED
SHIP GATE: command=... RESULT=PASS|FAIL|N/A
FINAL ARCHIVE: path=... sha256=... version_strings=PASS|FAIL|N/A
RUNTIME STATUS: user-confirmed-runtime | runtime-evidenced | tool-validated | assistant-claimed | contradicted
SSEEDIT/CK: not launched
UNRESOLVED: none | exact remaining risks
```

## V5 tooling laws

- Load `ai-tooling-stack` when choosing among Forge, houseCARL, and MCP utilities.
- Load `tool-discovery` before assuming any absolute tool path. Never hardcode another machine's drive letters or username.
- If a recommended tool is not installed or its MCP tools are not visible, repair or tell the user how to install/register it before spending tokens on manual workarounds. Do not invent tool results.
- **houseCARL**: live MO2/Vortex load-order truth, conflict trees, reviewable patch ESPs, NIF/BSA inspection and edits, Nexus keyless lookup. FormIDs use `XXXXXX:Plugin.esp`. Requires MCP + .NET 10 runtime + MO2 instance or Vortex shim.
- **Skyrim Forge**: typed automation broker, doctor/capabilities, release and nexus gates when configured.
- **codebase-memory-mcp**: structural code graph; index before query.
- **Headroom**: optional context compression MCP.
- **Superpowers / Ponytail**: process and minimal-diff overlays; bundled markdown works without plugins.
- **CodeBurn**: optional local AI cost analytics (`npx codeburn`).
- Before patching from load-order winners, load `tool-output-awareness` (DynDOLOD, ParallaxGen, Reqtificator, Synthesis, …).
- Prefer exact authoring skills (`spid-authoring`, `kid-authoring`, `skypatcher-authoring`, …) over invented framework tokens.
- Still prefer the CLI/MCP route: open a GUI only when the user asks or the CLI genuinely cannot do the job.
