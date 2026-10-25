# v8.22.1 validation

- Published `SenjuWoo/SkyrimForge` `v6.1.0` (`4a200b1913dd0300873b81df4c91619e678be857`): rebuilt `SkyrimForge.Native 6.1.0 go` for Windows x64 and Linux x64, updated `README.md`, `CHANGELOG.md`, `CHANGELOG.txt`, `STATE.md`, `PLAN.md`, `DECISIONS.md`, and `VALIDATION.md`, wired `Install-AI-Bridge.ps1` -> `Install-Skyrim-Pack.ps1` with `managed-skills/*.json` digest synchronization and Codex `~/.agents/skills` resolution, and connected the local `Skyrim-Forge` workspace to `origin/main`. Two-pass `validate_repository.py --scope full --write-reports` PASS (`errors=0`); GitHub Actions `CI` (`40227438934`, 10/10 jobs), `CodeQL` (`40227438862`), `Dependency Graph` (`40227444859`), `Release` (`40227557944`), and security flags (`clean`) PASS.
- Pinned `Skyrim-Forge-6.1.0.zip` (`5,098,608` bytes, `sha256: 7220f17a67e7d5828d9ad887d85ab970d5d5c2959e2e2a7d7e6f6f3b8d1ab2ec`) in `Ultimate-AI-Starter-Bundle` `v8.22.1` and updated `TOOLS/Install-SkyrimForge.ps1` so a newer parallel `Skyrim-Forge` installation is never downgraded and its newer `Install-Skyrim-Pack.ps1` is executed to keep newer Skyrim skills active.
- Fanned out `_CANONICAL-SKILLS/skyrim-forge/SKILL.md` (`# Skyrim Forge 6.1`) across all 6 provider trees; `check_versions.py`, `verify_manifest.py`, and `TESTS/test_release_contract.py` (`151 passed, 0 failed`) PASS.
- Live `v8.22.1` installer (`INSTALL-AIO.ps1 -Mode BundledFirst -SkipSelfUpdate -SkipNativePlugins`): exit `0`, upgraded `Skyrim Forge` to `6.1.0`, verified fifteen core MCP checks (`context7`, `headroom`, `toolbox`) across Claude, Codex, Grok, Hermes, and Antigravity, and `installed-state-doctor.json` PASS.

# v8.22.0 validation

- Updated `PROMPTS/START-AND-RESUME.md` and synchronized all preamble files (`0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md`, `0-UNRESTRAINT-PACKS/AIO-INSTRUCTION — Compact.md`, `COPY-TO-YOUR-WORKSPACE/AIO-INSTRUCTION.txt`, `BUNDLED-TOOLS/PREAMBLE-HISTORY.json`); `python TOOLS/generate_preamble_history.py --check` PASS.
- Retired `spookys-automod-toolkit` (`spooky`) and `.NET 8 SDK`, updated `skyrim-nif` and `skyrim-audio` to route through `houseCARL 2.1.1` and `Skyrim Forge 6.0.1`, regenerated `BUNDLED-TOOLS/RETIRED-SKILLS.json` (`173` current skills, `74` retired), and fanned out `1,287` files per provider across all 6 provider trees.
- Published `SenjuWoo/SkyrimForge` `v6.0.1` (`34f6947c9b766601d35e2400c4a63536e47ee08b`) owning `integrations/skyrim-pack/` (48 Skyrim skills, `Setup-HouseCarl.ps1`, `discover_tools.ps1`, `Install-Skyrim-Pack.ps1`); CI (`40223406469`), CodeQL (`40223406317`), Release (`40223408045`), and GitHub security flags (`clean`) PASS.
- Upgraded `uabs-toolbox` to `1.0.3` (`TESTS/test_toolbox.py` PASS), `housecarl` to `2.1.1` (`21` MCP tools, `.NET 10`), `rtk` to `1.1.0`, `blender-mcp` to `2.2.4`, and `rea` to `6.8.0` (`python TOOLS/audit_catalog_versions.py --fail-on-stale`: `current=23, held=5, stale=0, error=0`).
- Full Windows pack gate (`TESTS/Test-Pack.ps1`) PASS across all 19 sections; release contracts (`TESTS/test_release_contract.py`) `151 passed, 0 failed`; manifest (`10,332` files) and version consistency (`check_versions.py`) PASS.
- Live `v8.22.0` installer (`INSTALL-AIO.ps1 -Mode BundledFirst -SkipSelfUpdate -SkipNativePlugins`): exit `0`, retired `spookys-automod-toolkit` removed across Claude, Codex, Grok, Hermes, and Antigravity, external `houseCARL 2.1.1` recognized and preserved (`v2.1.1`), `Skyrim Forge 6.0.1`, `rtk 1.1.0`, and `uabs-toolbox 1.0.3` installed and verified, fifteen core MCP checks (`context7`, `headroom`, `toolbox`) answered across all five installed providers, and `installed-state-doctor.json` PASS (`logs/install-20261025-160710.log`).

# v8.21.3 validation

Independent review corrected the v8.21.2 handoff's preservation claim: matching
only top-level model IDs missed nested vendor defaults and permitted custom
presets/providers to be overwritten. Whole-block equality against the installed
vendor baseline now controls migration. Hash-directory discovery and replacement
both require a complete path segment; repair resolves custom Hermes homes.

Focused profile regressions PASS (Windows PowerShell 5.1, shared Python 3.14.9).
Fixtures execute the actual config-read Python script, reject custom presets,
providers and slot settings, preserve longer hash-like names, and verify module
and trust paths in a custom home. HERMES_HOME is explicitly isolated in tests.
Final full-gate, installed-state, CI and archive receipts are recorded in
`artifacts/recovery/resume-8213-final.local.json` and STATE.md as they complete.

Release contracts: 151 passed, 0 failed. Actual installed Hermes runtime:
inherited-default recognition and personal-preset protection PASS on disposable
configs. Frozen v8.21.2 source is rejected by the new fixtures. Live v8.21.3
installer: exit 0, fifteen core MCP checks answered, installed-state doctor PASS;
thirteen model/permission/MoA fingerprints unchanged after exact config backups.
Log: `logs/install-20261024-180827.log` under the installed state root.

Full Windows pack gate PASS. Reviewed implementation SHA `8392ed8`: CI
40133328203 and CodeQL 40133326481 PASS, including source and extracted-Core
gates on Windows Python 3.14/3.15 and physical symlink preservation on Linux.
Candidate Core/Full-Offline archives built identically twice. Extracted manifest,
preservation fixtures and hook self-test PASS; batch entrypoint rejects invalid
selection with exit 1 and no provider writes. Final release-source CI and
downloaded-byte receipts: `artifacts/recovery/release-8213-final.local.json`.
The public tag and release checksum files are the durable delivery record.

# v8.21.2 validation

Resumed review verified the v8.21.1 public archive bytes and exact-SHA CI,
then fixed the remaining required-dependency and false-success paths.

- Windows PowerShell 5.1 `TESTS/Test-Pack.ps1 -TestPython <disposable-venv>`:
  PASS. Release contracts: 151 passed, 0 failed. Manifest: 10,362 verified,
  zero missing/mismatch. Version consistency: PASS.
- Negative fixtures: solo-provider missing Git/failing installation; missing
  or invalid cached Python; malformed hooks and failed required self-tests.
- Pinned real ruamel 0.18.16 and the actual installed Hermes adapter: alias,
  schema 1.1, CRLF comment, exact backup and idempotent-retry checks PASS.
  Windows file-symlink creation lacks privilege locally; guard coverage is
  supplemented by a required physical-symlink CI job on Linux.
- Live v8.21.2 install: exit 0, doctor PASS, fifteen core MCP checks across
  five installed providers. Eleven model/permission fingerprints unchanged.
  Native plugins were reused; absent Kimi was not installed.
- Second pass, Hermes profile recovery: `Repair-McpPaths.ps1` now scans every
  `profiles/*/config.yaml` and repoints hash-keyed runtime folders, not just
  the default config. Applied live: 15 dead file paths plus 6 dead folder
  references repaired (Codex runtime `2b841c3d44b123ec` -> `1fb7137c46617d50`),
  with a backup beside each config. Report-only now resolves clean.
- `Get-MoaMigrationPlan` materializes Hermes Mixture-of-Agents OFF for the
  vendor-default fingerprint only (Opus 4.8 aggregator, gpt-5.5 /
  deepseek-v4-pro advisors), using the profile's acting model as aggregator
  and cheap OpenRouter advisors. Applied live to skyrim, blender and unity;
  all four managed profiles read `enabled=false` with the deepseek aggregator.
  `MCP PROFILE GATE: PASS`, including ambiguity refusal and four fingerprint
  cases; release contracts remain 151/0.
- `HERMES_HOME` is the active profile in a Hermes session. The migrator now
  walks it back to the real home and INSTALL-AIO passes that root explicitly,
  so an installer started from inside a session cannot create profiles inside
  a profile.
- Exact pushed SHA, remote CI and candidate package receipts:
  `artifacts/recovery/resume-final.local.json` (local-only). v8.21.2 was
  published on 2026-10-24 from
  `f89b17eb3c5a4f90b8b149473fc1d36e99c0c967`; CI run 40116264364 and CodeQL
  run 40116263912 succeeded on that SHA and GitHub flags were clean. Core
  sha256 `09450030...96257a`, Full-Offline sha256 `35d98154...c33e3e`; the
  downloaded assets match the local build and the published `.sha256` files.

Not certified: provider inference, absent provider/editor/game integrations,
or Hermes native-plugin activation under its copied-skills fallback.

Current audit evidence and limits: [whole-bundle audit](docs/AUDIT-2026-10-22.md).

# v8.20.0 validation

Source, installed state, MCP transport, editor runtime and release bytes are
separate proofs. This file records the checked boundary, not a claim of perfect
one-shot game/mod output.

## Current audit (v8.20.0)

Review of the owner's new `Tools` and `Modding` folders (read-only; no bench tool was
executed). Result: one upstream refresh, one new skill, documentation for the rest.

- Universal Modder `6a8865a` -> `c1dff21` (28 commits, 130 files; 9 changed Python/test
  files read, the new `um voidless` key handling confirmed to use the pack's patched
  hidden-key helper). `TOOLS/refresh_universal_modder.py --apply` re-applied all 20 pack
  patches; the wheel (3,618,451 B) built byte-identically twice;
  `TESTS/test_universal_modder.py` PASS with the new pin.
- New canonical skill `game-mashup-passthrough` (174 skills; 125 general per AI) and an
  extended `project-intel` mashup card. A contract checks both ship in every provider tree
  and carry no drive paths, `%LOCALAPPDATA%` or launch URIs.
- Companion currency on 2026-10-21: CLI-Anything v0.4.0, anti-slop v3.2.21, jevgrep v0.8.0,
  REA 6.7.0 and Reverse THIS! v1.2.1 are each the latest release; the local `rea-main`
  snapshot (6.5.0) and `universal-modder-main` snapshot lag the pack's pins.
- Not certified: the new skill's wording was not exercised in a live mashup session; the
  lessons it carries are the project's own record of one lab build, verified in game there.

## Previous audit (v8.19.2)

A review of v8.15.0..v8.19.1 (installer, shared helpers, Hermes migrator, MCP
writers) plus profiling of the last real install (5 min 24 s on a six-app machine)
found install time dominated by repeated work, and four defects.

- Hermes migration: `hermes config get` costs ~4.2 s per call and was called per
  key per profile. The migrator now reads every key of a profile in one process
  through Hermes' `load_config`. Measured on this machine: a read of 7 keys x 12
  profile names took 6.6 s against 279.6 s through the CLI with identical values
  for every real profile; a full plan-only run took 7.6 s against 152.0 s, and the
  two plans were line-identical. The CLI masks credential-shaped values and the MCP
  map it returned was written back whole; reads are now raw (this machine's
  profiles held no masked value, checked by key name only).
- Skill fingerprints: one reused SHA-256 replaces `Get-FileHash` per file; digests
  identical on 321 trees in both sort modes, 4.8x faster.
- Plugin-owned skills (63 over Claude, Codex, Kimi) are skipped by the copy when
  the last run recorded the plugin native, and restored if it is not native now.
- Spooky in-place update stamps `.uabs-version` and copies from the `.sln` folder;
  the `--version` probe closes stdin and stops at 10 s. `TESTS/Test-VersionProbes.ps1`
  covers compare, stamp, stdin-waiting and hung tools.
- blender-mcp 2.2.2: Windows initialize/tools-list PASS, 9 tools, 15,754 bytes.
- Starter settings: 15 `hermes config get` probes replaced by one `load_config` pass
  (65.5 s -> 10.2 s, same "already present" result; a missing key is reported missing by
  both). The doctor failed the install on a hand-installed REA 6.5.0 the bundle never
  installs; it now fails only on bundle-installed npm copies.
- `install_live_skills.py` ignored `skill-overrides.json`; the first real install after the
  v8.19.1 sync stopped at "override changed" for Claude/impeccable. The preserved 4.3.1
  copies were restored from that sync's backups (ordinal digests equal the registry in all
  three apps) and the tool now skips preserved skills.

Real `START-HERE.bat` run on this tree (no pause, self-update off, six apps):
`INSTALL COMPLETE` in 265 s (324 s before), no `TerminatingError` in the transcript,
always-on handshakes on all six apps, doctor PASS; 0 errors and 0 warnings once the
hand-installed REA was moved to the pinned 6.7.0. Not certified: provider inference,
editor/game runtime, billed-token savings.

## Earlier audit (v8.15.0)

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
