# Other game modding — settled results

One line per finding. Dates are when it was verified. Re-check version-
sensitive facts (game patches, tool versions) before acting.

## Black Desert Online

- Character appearance presets are local files — exportable, importable,
  shareable. Preset tooling works via file pipelines, not screenshots. (2026-08)
- Ultra settings are effectively a screenshot mode; for gameplay use high with
  targeted options. Heavily restructured between patches — verify per patch.
  (2026-08)
- Texture/AIO patch scope: one shipped body texture reference (e.g.
  `phw_01_nude_0001`) can be referenced by many classes at once — the patch
  must cover every referencing class, not the first one found. (2026-08)
- FSR-only engines: a DLL swap to DLSS-era shims is possible offline but is a
  maintenance treadmill; document it as experiment-grade. (2026-08)

## Helldivers 2

- A toolkit-driven mod factory is viable (archive pipeline + AI workflow);
  scope graphics overhauls honestly — total visual overhauls are months of
  work, not a session. (2026-10)

## Saints Row

- Engine is 32-bit in the classics: ReShade (especially full add-on builds)
  and other injected overlays do not work; use the community packaging tools
  (ThomasJepp class) for archive work. (2026-08)

## GTA / FiveM

- FiveM server modding is its own ecosystem, separate from single-player mod
  stacks; do not mix toolchains. (2026-09)
- Leak-watch/rumor content is not a modding workflow; treat as media, not
  build input. (2026-09)

## RimWorld

- Do not stack multiple AI-integration mods simultaneously (RimTalk + RimMind
  + another integration layer): conflicts and cost multiply. Pick one
  integration layer. (2026-08)
- Performance complaints: read the player log clues (e.g. `Player-prev.log`)
  before believing any single mod is the cause. (2026-08)

## Sims 4

- Culprit-hunting works with mod manager + update timeline; script mods from
  adult-content packs are a common breakage source across patches. Verify
  against the current game patch. (2026-08)

## Minecraft (Java)

- Modern shader path on Fabric: Iris + shader packs (BSL and stronger). Native
  launcher shaders are obsolete guidance. (2026-08)
- AI-generated asset pipelines (skins) work; ship them as apps with a
  retrieval corpus rather than one-shot generators. (2026-08)

## Warframe

- ReShade: normal shader use is common in the community; **full add-on builds
  are a ban-risk surface**. Companion apps (native, read-only data) are fine.
  (2026-06/07)

## Sleeping Dogs

- Surprisingly mod- and AI-agent-friendly for an older open-world title —
  good sandbox for automated modding experiments. (2026-10)

## Cross-game rules

- Clip/visual glitches in engine viewports are often the *editor's* near
  clipping plane (Unity scene view), not the asset. (2026-09)
- When a game ships "no DLSS/FSR only", the honest answer is usually "live
  without it" or a documented experiment — not a shim shipped to users.
  (2026-08)
