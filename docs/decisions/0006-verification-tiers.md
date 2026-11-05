# ADR-0006: three verification tiers, optional linters only

Status: accepted
Date: 2026-11-05

## Context
The pack gate takes minutes. That is correct for release, but it is the wrong
loop for a one-line edit, and adding six linters to the base install would add
runtimes, update churn and failure modes the bundle does not need.

## Options considered
- Make every check mandatory and keep one slow gate.
- Adopt a large lint toolchain and require it.
- Split the loop into FAST / FULL / RELEASE and probe optional tools.

## Decision
FAST checks changed files for PowerShell parse, Python compile and JSON parse,
reusing results by content hash in `.uabs-cache/verify/`. FULL is the existing
`Test-Pack.ps1`. RELEASE is `Refresh-Release-Metadata.ps1` plus FULL, and CI
still runs every mandatory gate on the exact SHA. actionlint, Ruff and
PSScriptAnalyzer are used only when already installed; nothing is vendored and
no install step adds them.

## Evidence
The full gate is 4-6 minutes locally; FAST parses the same changed scripts in
under two seconds and is a cache hit on re-run. The release contract caught
every real regression in 8.30.x with no linter installed.

## Consequences
A clean clone needs only PowerShell and Python. A contributor who installs a
linter gets earlier feedback; a missing linter is a skip line, not a failure.
FAST can never certify a release.

## Revisit when
A regression escapes FULL that a linter would have caught, or the pack adds a
language with a genuine type-checking need.
