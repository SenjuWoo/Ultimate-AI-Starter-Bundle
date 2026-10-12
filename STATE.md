# Bundle audit state

## v8.11.1 audit implementation

- Fixed explicit index scope, native failure propagation, Unicode ignore-rule
  preservation and exact active-snapshot selection with executable regressions.
- Closed Unicode tracked-filename privacy coverage; pack scans now use the
  shipped manifest rather than ignored old releases and caches.
- Corrected Codex reasoning double-counting and overstated usage claims.
- Added portable start/resume prompts; project evidence is judged by freshness
  and reproducibility, not the model's name.
- Audited and vendored Universal Modder fe505d8: 193 indexed knowledge notes;
  103 tests passed, four adapter/session-hook tests explicitly skipped.
- Fanout completed for all five provider trees. Personal overrides, model
  choices, compatibility holds and the untracked personal backup are preserved.

## Final verification and publication

- v8.11.1 publication is approved, conditional on all release gates.
- Source pack gate PASS (97 PowerShell scripts); 143 release contracts and
  nine audit regressions PASS. Privacy, versions, preamble history and all
  9,045 manifest entries verify. Hermes bootstrap passes five isolated cases.
- Ownership-aware local sync PASS: all 173 skills accounted for on every
  existing provider, with personal overrides retained. CodeBurn 0.9.27 and
  Universal Modder's audited wheel are active; installed-state doctor PASS.
- All 15 core-MCP initialize/tools-list checks PASS across five providers.
  Scoped stale-state cleanup reports nothing eligible at ten-backup retention.
- Pending: exact-commit CI and GitHub security flags, both extracted archives
  and published-asset byte verification. These are external release records;
  check them before declaring publication complete.
- No paid inference, host-editor interaction or game runtime is certified.

Detailed machine-specific reports remain under ignored `artifacts/`.
