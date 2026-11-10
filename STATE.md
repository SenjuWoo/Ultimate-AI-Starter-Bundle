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
- Separate unfinished prompt-pack edits remain local and are not part of this
  maintenance candidate.
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

Release notes before this trim: `docs/history/STATE-ARCHIVE-2026-11-07.md`. Older releases: `docs/history/V<version>-CHANGELOG.md`.
