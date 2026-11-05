# ADR-0001: gates require evidence, never forbid a method

Status: accepted
Date: 2026-11-05

## Context
The bundle's value depends on a future model or tool finishing a job the author did not
foresee. Early packs pinned exact versions and hard-coded paths, so a missing optional
tool aborted an install and a newer model could not use a better route.

## Options considered
- Pin every tool and version; refuse to run outside the tested matrix.
- Probe capability and degrade optional parts.

## Decision
A gate may require evidence (a hash, a test, a recorded verdict); it may not forbid a
method. Version checks are floors where a newer release is acceptable. A missing optional
tool degrades to a fallback. Destructive actions still require confirmation.

## Evidence
Tools resolve env vars, PATH and known install roots before declaring a tool absent; the
Hermes profile migrator skips a profile whose capability is not installed instead of
failing the run; Skyrim skills route to Forge when it is present.

## Consequences
Tests must prove the fallback path, not just the happy path. A new capability cannot
silently become mandatory.

## Revisit when
A provider requires an exact client version for a handshake with no forward-compatible path.
