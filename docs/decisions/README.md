# Architecture decisions

One record per decision that a future maintainer could otherwise undo by accident.
Format: context, options, decision, evidence, consequences, revisit trigger.

| ADR | Decision |
|---|---|
| [0001](0001-no-hard-blockers.md) | Gates may require evidence, never forbid a method |
| [0002](0002-owner-tooling.md) | The bundle is the foundation; owners keep their tools |
| [0003](0003-planner-worker-routing.md) | Particle works, DeepSeek plans, MoA is on demand |
| [0004](0004-generated-release-metadata.md) | Generated metadata is refreshed before gates |
| [0005](0005-no-bundle-router-or-paid-eval.md) | No bundle-side router or automatic paid evaluation |
| [0006](0006-verification-tiers.md) | FAST/FULL/RELEASE tiers, optional linters only |

New record: copy the shape below, number it next, and add a row above.

```markdown
# ADR-NNNN: title

Status: accepted | superseded by ADR-NNNN
Date: YYYY-MM-DD

## Context
## Options considered
## Decision
## Evidence
## Consequences
## Revisit when
```
