# v8.19.0 validation

Source, installed state, MCP transport, editor runtime and release bytes are
separate proofs. This file records the checked boundary, not a claim of perfect
one-shot game/mod output.

## Current audit (v8.19.0)

The owner's failed install (final doctor, 63 errors) was reproduced in cause, not
re-run: two overlapping installers, the second recording no plugin ownership. After
the mutex, the `owned` record and the doctor's plugin-tree union, the doctor passes.

`TESTS/test_toolbox.py` drives the real toolbox over stdio against a fixture child
(tool surface, ranking, duplicate suppression, missing-app and project-bound status,
JSON-string arguments, parked env and TOML entries, desktop-control sets that `find`
never starts, crash restart, no secret in output or logs). It passes under the pinned
`mcp==1.30.0`. The offline wheel builds byte-identically twice; a release contract
checks it carries exactly the gated source and matches its manifest row.

On the maintainer machine (2026-10-15) a real `START-HERE.bat` run (no pause,
self-update off) printed 243 console lines, ended `INSTALL COMPLETE`, and its
transcript has no `TerminatingError` or "pipeline has been stopped" line. The
always-on handshake passed for context7, headroom and the toolbox on all five
providers; the doctor reported 0 errors and 0 warnings. Hermes: the toolbox is in
the default and all eight managed named profiles, the bundle GitHub entry left them
(`gh` signed in). Driven like a client, the installed toolbox advertises 2,079
schema bytes for its three tools, lists 18 tool sets (16 startable here), starts the
parked GitHub server on a `find` (47 tools) and returns a real `get_me` result
through `call`, and lists but does not start windows-mcp.

Not certified: provider inference choosing the toolbox unprompted, editor/game
runtime through started servers, billed-token savings.

## Previous audit (v8.14.0)

`TESTS/Test-McpPark.ps1` runs the real `Set-McpProfile.ps1` against a disposable
home: task servers leave the machine-wide Claude and Codex configs, personal and
switched-off entries stay, `UABS_KEEP_GLOBAL_MCP` is honoured, a second park is
byte-for-byte a no-op, no credential reaches the output, the saved copy restores
exactly per project, markers decide where a server comes back, and the GitHub
profile writes only project scope. `TESTS/Test-NpmDuplicate.ps1` failed against
the v8.13.0 cleaner (an older copy in the user npm prefix stayed first on PATH)
and passes after the repair, in both prefix directions, with a byte-checked
recovery copy and an untouched newer personal version.
`TESTS/Test-AiHistoryBackup.ps1` proves copy-only behaviour: changed transcripts
update, deleted sources keep their archive copy, a newer archive copy is never
overwritten, the live Codex SQLite database is skipped and a destination inside a
provider folder is refused.

On the maintainer machine the new doctor check first reported five machine-wide
task servers and the shadowing CodeBurn launcher; after `-Park` and the npm repair
the remaining notes are two Hermes default-profile entries, which are reported and
never edited. No inference, editor, game runtime or billed saving is certified.

## Earlier audit (v8.13.0)

The strict skill-audit CLI regressions reject missing/empty trees and malformed
UTF-8. Grok's legacy Impeccable retirement checks preserve custom handlers and
backups. REA 6.4.0 passed an execution-free JavaScript fixture; its complete
170-tool MCP catalog is measured, not enabled. Context7 4.4.1 and Serena 2.0.0
passed isolated Windows MCP transport probes; all three supported Serena client
contexts were tested with Python 3.13 and the dashboard disabled.

RTK 1.0.0 OSS passed the exact status fixture, four fixed corpus rows and
allowlisted rewrite protocol. Ponytail's refreshed source passed 136 root and
31 pi-extension tests with real Python/Git Bash. Universal Modder source and
offline wheel verification remain separate from live game/asset operation.

## Earlier audit (v8.12.1)

Twelve executable regressions cover safe junction cleanup, private workspace paths, index-only scope application, preflight,
native failure propagation, dry-run, Unicode custom rules, exact snapshot
selection, manifest file scope, Unicode privacy scanning and Codex output
accounting. Universal Modder's reviewed `fe505d8` snapshot passes 103 upstream
tests; four skips are the unshipped OpenCode adapter/session hooks. One upstream
Pillow deprecation warning remains. Existing Windows/offline/privacy patches
are retained. Full source, installed-state, CI and release gates remain separate.

The user-profile gate executes the actual installer instruction section in an
isolated provider home. Oversized private input must preserve the existing block
byte-for-byte without generating a rewrite backup. This was observed failing
before the v8.12.1 repair and passing after it.

The measurements below are historical checks of the named versions, not
current-version transport or billing claims. Current pins live in CATALOG.json;
release identities and archive proof live in GitHub checks and asset records.

## Executable regression gates

Run with Windows PowerShell 5.1 and a real Python 3 interpreter:

```powershell
.\TESTS\Test-Pack.ps1
python TESTS/test_release_contract.py
python TESTS/test_hermes_bootstrap.py
.\TESTS\Test-TaskRecipes.ps1
.\TOOLS\Test-Installed-State.ps1
```

Task-recipe fixtures use disposable homes containing spaces and Unicode, not
the configured developer home. They exercise the real plan/writer, empty new
projects, composition, repeated activation, unknown tasks, Windows opt-in and
personal global/other-project configuration preservation. A native Hermes
migration verifies the actual written profile topology and keeps rollback
snapshots. These do not simulate a completely empty operating system.

## RTK and Ponytail candidates

RTK 0.51.0 official Windows archive: 4,579,791 bytes, SHA-256
`1623e9b45d28b15122d69e7314776e1123a804224885ce07e7182fb40080f05c`.
`python TESTS/test_rtk_candidate.py --rtk <candidate exe>` passed status equivalence
for staged, unstaged, renamed, deleted, Unicode and untracked fixtures and
reproduced the four pinned corpus rows. Candidate safe-hook self-test passed;
standalone test-command rewriting returned the documented success exit 3.
These are output-byte results, not billed-token or quality measurements.

Ponytail v4.10.1 upstream tag commit:
`c6ce46179874ea7368da0eb9e67c1ad5c10f08bc`. Its 16 OpenCode adapter tests and
the retained Cursor adversarial-regex regression passed. Existing Cursor
hardening was not overwritten by the vendor update.

## v8.9.0 additions

The reworked AIO family passes the pack's own gates: preamble source checks
(clean UTF-8, provider-neutral SOUL, marker-free wiring, idempotent re-wire,
history-based replacement), the deployed-artifact ASCII checks for
`MANUAL-PASTE.txt` and `COPY-TO-YOUR-WORKSPACE/AIO-INSTRUCTION.txt`, and
`TOOLS/generate_preamble_history.py --check` after the outgoing texts were
archived. Universal Modder's refresh was verified with the vendored upstream
pytest suite (94 passed / 1 skipped - the skip is the upstream hooks test the
pack does not ship) and `TESTS/test_universal_modder.py` (wheel contents,
`--version`, recon fixtures, catalog pins, all five provider trees).
Impeccable's hold was re-audited against the real engine 0.1.14 binary from
`@impeccable/cli-windows-x64@0.1.14` (`TOOLS/audit-impeccable-engine.py`:
malformed-tag fixtures still leak, control passes) and the vendored CLI 3.6.1
still passes `TESTS/impeccable-security-regressions.mjs`. Prompt-level
unrestraint is not measured here: whether a given consumer surface complies
remains a user-tested boundary.

## Runtime boundaries

Final catalog refresh: GitHub MCP 1.14.0 (47 tools/129,567 bytes), Firecrawl
3.27.3 (25/81,489), Super-MCP Router 2.8.3 (12/12,475) passed unauthenticated
initialize/tools-list. GitHub's official Windows ZIP digest/size matched;
Firecrawl stays credential-gated and router testing used a disposable home.
No OAuth completion, authenticated scraping or child-server dispatch was run.

New Hermes native Blender/Unity/web configuration was applied and verified,
with original configs backed up and existing preferences retained. Godot is
conditional on its runtime prerequisite. Initialize/tools-list transport
checks passed for Blender (36 tools, 46,629 schema bytes), Unity (47 tools,
108,248 bytes) and Playwright (25 tools, 20,286 bytes). These are compact UTF-8
schema sizes, not prompt/billing measurements. Playwright was probed through
Hermes' actual Windows resolver/cached-npx path; raw Python spawning bare `npx`
failed to resolve it and is not native-client connection evidence. Transport
checks do not prove a companion editor/add-on is connected, a GPU operation
works, or generated mods survive gameplay. No audited Unreal editor MCP is
shipped. Open chats may need reload/restart to see new registrations.

## Release gates

The component-list regression first failed against the old installer, then
passed after comma splitting, trimming and deduplication were added. The
provider-detection gate executes the installer's own normalization statement.

Extracted Core testing reproduced a skill-auditor `UnicodeEncodeError` under a
Unicode path and the Windows legacy console. Its new regression first failed,
then passed with printable diagnostics; a malformed BOM-bearing skill still
returns failure. Both archives must be rebuilt from the corrected CI-green
commit before publication.

The release procedure requires the exact pushed commit's terminal CI/security
checks, manifest/version validation, both built/extracted archive gates, and
published-asset size/SHA-256 equality. Publication evidence belongs to the
GitHub checks, tag and asset records; no pending check counts as a pass.
