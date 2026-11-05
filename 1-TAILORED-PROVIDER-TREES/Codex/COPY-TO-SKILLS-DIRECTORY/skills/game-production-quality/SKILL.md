---
name: game-production-quality
description: "Use for any game or level work: fidelity, performance, feel, world, systems, assets, playtests."
version: 1.0.0
author: Ultimate-AI-Starter-Bundle
license: MIT
metadata:
  hermes:
    tags: [games, production, performance, level-design, playtesting]
    related_skills: [game-dev-starter, capability-profiles, visual-verification, game-modding]
---

# Game production quality

## When to Use

- Building or reviewing a game, level, mechanic, or asset pipeline in any engine.
- A request sounds visual ("make it look better", "it stutters", "it feels slow") and needs the real cause.
- Deciding what to optimize, what detail to keep, and what to verify.

Engine commands, SDKs and plugin specifics belong to the owning forge: RobloxForge for
Roblox, `unreal-mod-frameworks` for UE, `unity-mod-frameworks` for Unity,
`bethesda-creation-modding` for Fallout/Starfield, and `game-modding` for the rest.
This skill decides *what matters*; the forge supplies *how*.

## Universal rules

- Optimize what is measured. A profile beats a guess; name the frame budget before cutting detail.
- Allocate detail by visibility, screen-space size, interaction and gameplay relevance.
- Keep gameplay simulation alive when an object is not rendered; culling, streaming,
  simulation throttling and network replication are four different switches.
- Prefer the engine's own capability over a custom reimplementation.
- Design to the target device's budget, not the developer's machine.
- A cheaper effect that looks the same wins; measure the difference before adding cost.
- Never trade readable feedback (hit, damage, cooldown, danger) for frame rate.
- Degrade gracefully when an asset is missing or streamed out; test that path.
- Every optimization is measurable and reversible. Record the before and after.
- Never impose an arbitrary polygon, part, draw-call or memory number. Budgets are
  derived from the target device and the frame time, and they are per project.

## Route the question

| Question | Read |
|---|---|
| Looks flat, distant objects pop, LOD or streaming plan | `references/fidelity-and-performance.md` |
| Stutters, low FPS, too many draw calls, memory or loading spikes | `references/fidelity-and-performance.md` |
| Controls feel laggy, hits lack punch, camera or audio feel wrong | `references/feel-world-and-experience.md` |
| Level reads badly, landmarks, lighting, atmosphere, onboarding | `references/feel-world-and-experience.md` |
| State machines, events, saves, data-driven content, networking boundaries | `references/systems-assets-and-playtests.md` |
| Meshes, UVs, materials, rigs, animation, compression, provenance | `references/systems-assets-and-playtests.md` |
| How to prove it works: playtest, benchmark, device matrix, regression | `references/systems-assets-and-playtests.md` |
| Writing a budget, brief, asset acceptance or regression report | `templates/production-templates.md` |
| What an engine forge must expose to be usable here | `references/forge-capability-contract.md` |

Load one reference, not all of them. A question that spans two areas is two passes:
fix the cause, then verify the player-visible result.

## Verification

A quality claim needs evidence: a frame-time capture, a before/after screenshot, a
recorded playtest, or a passing automated scenario. "Should be faster" is not a result.
Pair every visual change with `visual-verification`; pair every performance change with
the same benchmark on the same device and scene. Run the critical player journey after
the change, not only the effect you touched.
