# ADR-0005: no bundle-side model router, no automatic paid evaluation

Status: accepted
Date: 2026-11-05

## Context
A proposal asked for a measured adaptive model router and a cross-provider agent
evaluation framework. The bundle already configures Hermes' native routing (delegation
model map, provider sorting, MoA) and ships 160 release contracts plus a pack gate. A
second router would duplicate Hermes and drift from its schema; an automatic live eval
would spend the user's credits on every install.

## Options considered
- Build a routing daemon and an always-on cross-provider eval in the bundle.
- Keep routing in the host; keep evaluation deterministic and offline by default.

## Decision
No bundle-side router. Routing stays in Hermes configuration, documented in
`docs/HERMES-MODELS.md`. Evaluation stays deterministic: the contract suite and pack gate
are the shipped eval layer. A live cross-provider comparison is an optional, explicit,
budget-limited experiment run by the operator; nothing installs or triggers it.

## Evidence
`hermes delegation config` and MoA presets are already the routing surface; duplicating
them would mean reimplementing provider adapters and cache accounting. The existing gates
caught every regression in this release.

## Consequences
A future model can add an opt-in eval runner without changing install behavior. Savings
claims require billing evidence, which the bundle does not fabricate.

## Revisit when
Hermes exposes a stable routing API, or a deterministic multi-provider harness appears
that needs no paid calls.
