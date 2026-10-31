# Presentation plan

**Status: INCOMPLETE until every required row has a real capture from the final
build.** Do not fabricate a screenshot, reuse an older version's image, or
present generated art as gameplay.

| # | Asset | What to capture | What it proves | Alt text |
|---|---|---|---|---|
| 1 | Hero 16:9 | {Best real shot of the core change} | {The hook at a glance} | {Describe the visible action} |
| 2 | Gallery 1 | {Second angle or feature} | {Proof of feature} | {Alt text} |
| 3 | Gallery 2 | {Third angle or feature} | {Proof of feature} | {Alt text} |
| 4 | Kind-specific | {Face/portrait, front/back/detail, wide/detail, installer/menu} | {Proof the feature exists} | {Alt text} |
| 5 | Motion (if animation/combat) | {10-30 s clip} | {Proof of motion, not a still} | {Alt text} |

Rules:

- Final archive, final load order, final settings.
- No HUD, console, debug overlay, desktop, notifications or personal paths.
- Same weather/lighting for before/after; same camera position.
- Disclose ENB/ReShade and composite title overlays.
- Credit third-party assets when their licence asks.
- Put files under `docs/presentation/` and reference them from `README.md`.
- Run `python TOOLS/presentation_check.py <project> --kind <kind>` before upload.
