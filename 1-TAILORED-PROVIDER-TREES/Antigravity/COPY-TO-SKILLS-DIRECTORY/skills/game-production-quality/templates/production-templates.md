# Production templates

Copy the block, fill it, keep it short. Templates are checklists, not documentation.

## Game design and core-loop brief

```
Pillars (max 3):
Core loop: act -> reward -> cost -> repeat
Session target: __ min     First meaningful action: __ s
Fail state / recovery:
Win state / mastery:
Out of scope for this slice:
```

## Technical performance budget

```
Target device / OS:            Frame target: __ ms (__ fps)
Game logic: __ ms   Physics: __ ms   Animation: __ ms   Render CPU: __ ms
GPU: __ ms   Memory: __ MB   Streaming budget: __ MB/s
Measured with: <profiler / build / scene>
```

## Visual fidelity and asset importance tiers

```
Tier      Screen size   LODs   Shadows   Update    Cull dist
Hero      >20%          3-4    yes       full      __
Gameplay  5-20%         2-3    near      full      __
Background <5%          1-2    no        half      __
Dressing  any           billboard no    slow      __
```

## Gameplay experience checklist

```
[ ] Input latency measured on the lowest device
[ ] Hit feedback: sound + visual + camera, scaled by weight
[ ] Every action answers within 2 frames
[ ] Camera, recoil and shake recoverable; intensity setting exists
[ ] Remappable controls; gamepad/touch where supported
[ ] Critical state readable without colour alone
```

## Level design and immersion review

```
[ ] One dominant landmark per sightline
[ ] Route readable without the map
[ ] Reveal earned, not accidental
[ ] One environmental story per space
[ ] Lighting directs attention; weather does not hide affordances
[ ] Indoor/outdoor audio transition audible
[ ] Material scale coherent per biome
```

## Asset acceptance checklist

```
[ ] Scale and pivot match the project convention
[ ] Normals clean; no hidden faces
[ ] Material count within budget; master material instance
[ ] Texture sizes and colour space correct; mipmaps on
[ ] LOD chain present and tested at distance
[ ] Collision matches visual intent
[ ] Source file and licence recorded
```

## Automated playtest scenario

```
Scenario: boot -> <action> -> <assert> -> quit
Setup: fresh save | previous save
Steps: 1.__ 2.__ 3.__
Assert: state / value / file, not a pixel, unless UI-only
Fail artefact: log + screenshot + build id
```

## Performance regression report

```
Build / commit:        Device:        Scene:
Before: median __ ms / worst __ ms    After: median __ ms / worst __ ms
Change: <one line>
Measured with: <tool>                  Runs: 3
Gameplay preserved: <checklist / playtest>
Reversible: <flag / revert path>
```
