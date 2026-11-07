---
name: img2threejs
description: >
  Turn an object or character reference image into a quality-gated, animation-ready
  procedural Three.js model built in code. Use for image-to-3D reconstruction and
  detail-accurate rebuilds. Install the pinned upstream skill first; this file is a
  pointer, not the tool.
license: Apache-2.0
version: 1.5.1
---

# img2threejs (pointer)

The tool is **not vendored in this bundle** any more. It lives in its own
repository so one owner updates it:

- Upstream: `https://github.com/img2threejs/img2threejs`
- Pinned tag **v1.5.1**, commit `dede5909be4e494b228c801a55dda47439143932`

Install it beside your skills (clone once, then it works offline):

```bash
git clone --branch v1.5.1 --depth 1 https://github.com/img2threejs/img2threejs
```

Copy the clone into the harness skills directory as `img2threejs`, or point the
agent at it. Then follow its `SKILL.md`: `forge/next.py` drives the pipeline,
`forge/state.py` records evidence, `grimoire/` holds the contracts. Windows users
run `forge/...` through `scripts/uabs-python.ps1` for UTF-8.

When the repository is unavailable and the task needs it, say so and continue with
a plain Three.js factory or a GLB; never fake a reconstruction.

## When to reach for it

Use it at the start of game or app asset work when there is **no model to
import**: a concept image, a screenshot, or a written description becomes a
procedural Three.js object you can edit in code.

- Good: props, furniture, vehicles, buildings, level dressing, stylised
  characters, and prototyping silhouette and scale before real modelling.
- Output: a factory or GLB you own outright, so no external asset licence.
- Not it: rigging, animation authoring, texture baking, hero assets. Take its
  base mesh into Blender or the engine for those.
- Check `MACHINE-MAP.md` for an existing checkout before cloning again.
