# v8.7.35 validation

Source, installed state, MCP transport, editor runtime and release bytes are
separate proofs. This file records the checked boundary, not a claim of perfect
one-shot game/mod output.

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
