# ADR-0004: generated metadata is refreshed before gates

Status: accepted
Date: 2026-11-05

## Context
`MANIFEST.json` decides what `build_release.py` packages, and a local install or a test
run can write a preamble or legacy archive after the manifest was generated. That produced
repeated red CI runs on `test_manifest_covers_every_tracked_file`.

## Options considered
- Keep the manifest manual and rely on the maintainer to regenerate it.
- Generate it inside `build_release.py` only.
- Refresh it at the start of CI and add a pre-push guard.

## Decision
CI regenerates the preamble archive and the manifest before the gates, then verifies the
hashes. `TOOLS/Refresh-Release-Metadata.ps1` runs every generated-artifact check locally,
and `TOOLS/Install-GitHooks.ps1` installs a pre-push hook that refuses a changed manifest.
The release still builds from the exact SHA.

## Evidence
The 8.30.5 run failed only because three archives were written after the manifest; a
regenerated manifest passed, and a real hash mismatch still fails `verify_manifest.py`.

## Consequences
A stale committed manifest can no longer red the run, but an artifact built outside CI
must still run the refresh tool. The pre-push hook is optional for contributors.

## Revisit when
The release build starts generating the manifest itself from a clean tree.
