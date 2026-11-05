# ADR-0002: the bundle is the foundation; owners keep their tools

Status: accepted
Date: 2026-11-05

## Context
Skyrim Forge, houseCARL, reverse-this and the per-engine forges change independently.
Vendoring them caused drift: the bundle shipped a stale copy while the owner had moved.

## Options considered
- Vendor every companion release into the bundle.
- Detect an installed owner and reuse it; install only the base layer.

## Decision
The bundle installs the general layer and detects companions. Skyrim Forge installs
houseCARL; reverse-this owns its kit and encyclopedia; the engine forges own their skills.
The bundle skips a component whose owner is present and current.

## Evidence
`INSTALL-AIO.ps1` dispatches houseCARL to Forge and skips with a clear line when Forge is
absent. Companion downloads follow latest releases declared in `CATALOG.json`. Provider
skill fanout is one canonical tree, not six hand edits.

## Consequences
A companion bug is fixed at its owner. The bundle must keep its detection current, and a
missing owner must degrade, not abort.

## Revisit when
An owner stops publishing a machine-readable version or installer.
