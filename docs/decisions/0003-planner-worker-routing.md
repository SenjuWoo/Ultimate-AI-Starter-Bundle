# ADR-0003: cheap worker, selective planner, on-demand MoA

Status: accepted
Date: 2026-11-05

## Context
Particle-1 is an efficient executor; DeepSeek V4.1 Flash is stronger at planning and
research and is cheaper per token on current OpenRouter offers. Always-on Mixture of
Agents doubles calls and defeats the point of a cheap default.

## Options considered
- One premium model for everything.
- Always-on MoA over two models.
- Cheap main model, planner on demand, two delegation routes.

## Decision
`particle-ai/particle-1` is the regular main model. One MoA preset, `deepseek_particle`,
is available through `/moa` only: DeepSeek V4.1 Flash at high effort as the single
reference, Particle-1 at high effort as aggregator, `fanout: user_turn`. Delegation is a
model map with `execute` (Particle, medium, default) and `research` (DeepSeek, high),
concurrency 2. Auxiliary tasks follow the main model; titles and background review are off.

## Evidence
Hermes appends planner advice after the reusable context, so the aggregator prefix stays
cacheable, but each model keeps its own cache. Per-task model pins fragment caches; the
two-route map spends a second model only when delegation is actually used.

## Consequences
A user's own model choice is preserved; the migration fills only an untouched block. No
automatic route reaches GPT, Claude, Gemini, Grok or Crouton Alpha.

## Revisit when
Measured completion-per-dollar data shows a different pair, or Hermes changes MoA caching.
