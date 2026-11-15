# Bundle state

## Current work

- Goal: reliable prompt-first capability discovery across providers, preserving
  creative intent and personal settings with small default context.
- Version: `VERSION.txt`; published revisions and recovery points are Git tags.
- Implemented: advisory workflow routing; conservative Ponytail auto classification;
  bounded companion discovery with explicit-owner precedence; moved MCP path
  repair; active launch-path diagnostics; provider-scoped prompt hook wiring;
  stable instruction boundaries; profile overflow handling; retained legacy skill
  backups; deterministic memory indexing of hooks, companions and profiles.
- Architecture: `docs/decisions/0007-advisory-discovery.md`. Prior model-ranking
  claims in ADR-0003 are historical; provider model selection remains operator-owned.
- Recovery: machine inventories, session exports, graph snapshots and deployment
  receipts stay outside the public payload. Private historical exports are not
  live provider configuration. No source or game tree is moved just to rename it.
- Audit fixes: literal Windows task paths, empty evidence, MCP section/comment
  isolation, uncommitted line-ending checks and bounded manifest traversal.
- Architecture review: `docs/decisions/0008-cheap-hooks-and-truthful-roots.md`
  (hook cost, source/runtime discovery, moved folders, awkward paths).
- Validation commands: `python TOOLS/release_gate.py`; installed diagnostics:
  `powershell -NoProfile -ExecutionPolicy Bypass -File TOOLS/Test-Installed-State.ps1`.

## Current verified state

| | |
|---|---|
| Release | `VERSION.txt` and the git tag are the only source; a contract test fails if this row disagrees with `VERSION.txt`. no literal version is kept here on purpose |
| Branch | `main`; verify the exact SHA against the remote before delivery |
| Next version | the next patch after `VERSION.txt`; nothing to edit here |
| Next action | whatever the Done/Next section below lists; this header stores no release fact it could contradict |
| Evidence | `python TESTS/test_release_contract.py`, `python TESTS/test_task_state.py`, `TESTS/Test-Pack.ps1`, `gh run list --commit <sha>` |

- Build: `python TOOLS/build_release.py`. The release workflow verifies the exact
  main SHA, builds twice, compares bytes and verifies downloaded release assets.
- CI and alert convergence: `TOOLS/Wait-External.ps1` and `TOOLS/Get-GitHubFlags.ps1`.
- A path or registration is not execution evidence. MCP handshakes prove transport
  and tool listing; task calls establish capability. Paid model benchmarks remain
  opt-in and are not implied by deterministic tests.
- Re-index a source owner after structural changes, with a consistent database
  backup first. Verify its current root and a source query afterward.
- Next action: use the full gate and exact-SHA CI for maintenance; retain private
  deployment evidence locally and published receipts with the release assets.

## History

8.52.0 (2026-11-15): forges self-register through uabs-companion.json (no bundle
release for a new forge or launcher); TOOLS/field_report.py records a forge defect in
the owner folder (rule in the contract, ai-tooling-stack, forge standard);
MarvelRivals-Forge registered and routed.
8.51.1 (2026-11-15): catalog Unity install command matches 1.11.1; freshness check
recorded (22 current, 3 held, Blender 2.3.0 / Unity 1.11.3 under a day old, not
adopted); installed hooks, settings and six provider skill homes verified live.
8.51.0 (2026-11-15): stop gates honour stop_hook_active (no repeated blocks);
prompts merged into PROMPTS/START-RESUME-UPGRADE.md; docs gate checks Markdown
links per page (41 dead GUIDE links fixed); workspace template states each rule
once; codebase-memory skill split (indexing/install in a reference).
8.50.1 owner audit (2026-11-15): baseline green (gate 23/23, CI, doctor). Fixed:
Claude routing ignored native-plugin skills (Superpowers never suggested); leftover
cleanup exited 0 on failed removals and could edit a provider config whose backup
failed; the local gate lacked ten CI contracts, the Core artifact check and four
orphaned tests (now held by `TESTS/test_gate_parity.py`); duplicated GUIDE/README
markup; six dead PowerShell helpers. Open gap: no uninstaller (documented).
Final audit: the local gate stages and release contracts passed, including
Windows-path, awkward-path launch and MCP parsing regressions. Installed-state
diagnostics passed.
Exact-commit CI and downloadable build receipts remain the release evidence.
8.44.7 audit: install-time cleanup now also removes older-version leftovers
(backups only by retention), and ponytail "off" switches its Claude/Antigravity
plugin off; sandboxed tests no longer reach real provider folders.

Release notes before this trim: `docs/history/STATE-ARCHIVE-2026-11-07.md`. Older releases: `docs/history/V<version>-CHANGELOG.md`.
