---
name: creative-direction
description: "Use when a brief is an idea, not a spec: expand it, keep the vision, build a vertical slice."
version: 1.0.0
author: Ultimate-AI-Starter-Bundle
license: MIT
metadata:
  hermes:
    tags: [creative, design, direction, continuity, games, apps]
    related_skills: [project-intel, one-shot-completion, game-production-quality, brainstorming]
---

# Creative direction

## When to Use

- The request is a feeling or a genre ("a cosy survival game", "a dark landing page"), not a spec.
- A project spans sessions and the look, tone or topology must survive a restart.
- Several features are implied but none is written down.

The user's concept is the brief. You are the director, designer, engineer and reviewer
in one pass; you are not a literal transcription service.

## Intent -> Expansion -> Execution

1. **Intent.** State the experience in one sentence: who it is for, what they feel, what
   they do. Keep the operator's own words for the core fantasy.
2. **Expansion.** List the features the idea implies (traversal, feedback, lighting, audio,
   persistence, onboarding). Mark each must / should / could. Add the professional
   considerations the operator would not know to ask for, then cut anything that does not
   serve the original vision.
3. **Execution.** Pick the smallest coherent slice that proves the vision, build it, inspect
   it, critique it, improve it, verify it. Expand only after the slice holds.

Expansion is not scope creep. A feature that changes the fantasy is an operator decision,
not yours.

## Vision Contract

Write it before substantial work (template: `templates/vision-contract.md`) and keep it
next to STATE: core fantasy, audience, experience, visual/audio direction, references,
required systems, hard constraints, rejected ideas, creative freedom, current direction.
User corrections are facts with the highest priority; a corrected topology, name or style
is preserved until the operator changes it.

## The loop

**Understand -> choose capabilities -> build -> run -> inspect -> critique -> improve ->
verify -> record.** Critique on separate axes: function, art direction, feel, performance,
maintainability, accessibility, contract fit. Fix the highest-impact mismatch first. Use
`game-production-quality` for those axes and `visual-verification` for pixels; a compile
is not a look and an export is not an in-engine result.

## Vertical slice first

Prove one representative experience end to end: core systems, visual identity, controls,
feedback, performance, integration. Expand content only after the slice holds.

## Continuity

Keep a feature ledger (template: `templates/vision-contract.md`) with stable IDs,
requirement, dependencies, priority, status, acceptance test and evidence. On resume read
STATE and the contract, check the tree, run the smoke test, take the highest unfinished
item, and leave finished work alone. `done` needs a run, screenshot, test or playtest —
never just code.

## Autonomy boundary

Ordinary reversible project decisions are yours. Money, publishing, unrelated projects,
deleting important files and permission changes are not. When an artistic choice is truly
uncertain, pick a defensible default, build it, and present the decision with evidence
instead of blocking.
