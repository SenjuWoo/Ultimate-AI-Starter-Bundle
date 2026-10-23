# Fresh Windows recovery implementation plan

**Goal:** Make the current Windows installer work with any selected subset of
the six supported providers, preserve personal files/settings, and restore
durable development setup after the owner's PC reset.

**Architecture:** Keep the current installer and reviewed component pins.
Distinguish installed desktop apps from runnable CLIs; share CLI resolution
between detection/bootstrap. Require an explicit choice when nothing is found.
Seed missing workspace files, and preview cleanup instead of deleting by default.

**Tech stack:** Windows PowerShell 5.1/PowerShell 7, Python, Git/GitHub CLI.

The owner authorized sensible assumptions and autonomous repair. Alternatives
considered: install all providers (unwanted software), require manual setup
(repeats the reported problem), or detect only installed/explicitly selected
providers (chosen). No provider authentication or inference is fabricated.

## Tasks and verification

- [x] Reproduce discovery/bootstrap failures with focused regression fixtures;
  fix native/desktop/PATH detection and exercise all 63 nonempty provider sets.
  Files: TOOLS/UABS-Common.ps1, TOOLS/Ensure-Provider-CLIs.ps1 and focused tests.
  Verified 2026-10-23: Test-Pack ran Test-ProviderDetection (masks 1..63) and
  Test-ProviderBootstrap, both PASS on Windows PowerShell 5.1.
- [x] Remove implicit all-provider fallback in INSTALL-AIO.ps1; require explicit
  selection on an empty machine before runtime or provider installation.
- [x] Preserve existing workspace instructions/templates with a seed-only
  helper and a real-file regression; make default cleanup report-only.
  Verified 2026-10-23: Test-WorkspaceSeeding and Test-InstallerPreservation PASS.
- [x] Inspect custom-home and selected-provider hook paths; fix confirmed
  scope violations with regression coverage.
  Verified 2026-10-23: Test-ProviderHookScope PASS. Pre-rename hook commands
  stay recognizable through Get-UabsLegacyHookRoots.
- [x] Restore Git metadata without replacing working files, preserve existing
  Git/Codex choices, and save compact user-wide preferences with backups.
  GitHub CLI auth restored from the existing keyring. Model choices untouched.
- [x] Run release contracts, full pack validation, focused Windows regressions,
  and isolated installer fixtures. Install missing test dependencies in a
  disposable environment, never the shared Python base.
  Verified 2026-10-23: contract 151/0; Test-Pack PASS with -TestPython on a
  disposable venv (mcp==1.30.0, PyYAML==6.0.3). Shared base was not modified.
- [ ] Run the repaired selected-provider installation if validation permits;
  verify installed-state doctor and local startup/MCP results. Record exact
  auth, network, restart or provider-matrix limits in STATE.md and handoff.

## Review focus

No-provider machine must not bootstrap all providers. Stale PATH and desktop-only
apps must be recognized. A one-provider install must leave other homes untouched.
Workspace data, personal hooks, model choices, credentials and backups must
survive. PS5.1 error/stderr behavior and paths containing spaces must be tested.
Current upstream pins are reviewed rather than blindly upgraded. Public releases
and repository settings are separate from a local fix and require verified gates.
