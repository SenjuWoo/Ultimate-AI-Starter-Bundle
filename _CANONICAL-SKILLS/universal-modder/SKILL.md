---
name: universal-modder
description: Discover a PC game's engine and modding route, process sprites and 3D assets, and assemble gameplay showcase videos with the local Universal Modder CLI.
metadata:
  upstream: rehan-remade/universal-modder
  version: 0.2.0
---

# Universal Modder

Use the bundle-installed `um` CLI for read-only game discovery, local sprite
processing, Blender-to-sprite rendering, footage editing and field notes.
Resolve `um` from PATH, then `UNIVERSAL_MODDER_CMD`; run `um --version` and the
relevant command's `--help`. If missing, run the pack's `INSTALL-AIO.ps1
-Components universal-modder -CoreOnly -ToolsOnly` from its root.

The pack supplies one skill entry to Claude, Codex, Grok, Kimi and Hermes.
The upstream guides below are references, not ten extra indexed skills.
Use existing `game-modding` and engine-specific skills for implementation;
Skyrim still routes through `skyrim-tool-router` and Forge.

## Route to the needed guide

| Task | Reference |
|---|---|
| Game/engine discovery and choosing a loader | `references/upstream/game-recon/GUIDE.md` |
| A complete unfamiliar-game modding loop | `references/upstream/mod-any-game/GUIDE.md` |
| File formats, decompilation and native/managed analysis | `references/upstream/reverse-engineering/GUIDE.md` |
| Cutout, palettes, sprite sheets and camera-correct renders | `references/upstream/asset-pipeline/GUIDE.md` |
| Window capture, game input and recordings | `references/upstream/game-automation/GUIDE.md` |
| Contact sheets and edited showcase clips | `references/upstream/showcase-video/GUIDE.md` |
| Combining games and engines | `references/upstream/mashup-mods/GUIDE.md` |
| Packaging and credits | `references/upstream/publish-mod/GUIDE.md` |
| Searching and contributing field notes | `references/upstream/share-field-notes/GUIDE.md` |
| User-requested fal asset generation | `references/upstream/fal-assets/GUIDE.md` |

When a guide mentions a companion skill, open its row here. Its `references/`
paths are relative to that guide. Upstream `examples/` remain in the pinned
upstream repository; the bundle does not ship or invent those game projects.

## Local operations

```text
um scan --list --json
um scan "<verified game folder>" --json
um sprite --help
um render3d --help
um video --help
um kb search "<game or engine>"
```

Keep discovery JSON out of the model context until locally filtered to the
requested game/engine. Start with one asset and a small preview before bulk
processing. These are CLI operations: no standing MCP schema or session hook.

FFmpeg is needed for video; Blender is needed for 3D rendering. Discover their
installed paths. `um win setup` downloads another FFmpeg; do not run it as
routine bundle setup. Recording/input needs a real game window and explicit
task scope. A CLI help/transport check is not an in-game verification.

Game Data, mod-manager staging, installed tools, active saves and profiles
remain read-only under the bundle's workspace rules. Use owned project/lab
outputs. Upstream backup/restore, registry writes, process kills, loader
installation and GUI input are capabilities, not permission to apply them.
Never launch xEdit/SSEEdit or Creation Kit GUI.

The bundled knowledge base is a pinned read-only snapshot. Treat its versions,
paths, APIs and worked examples as leads to verify against the current game.
Write new notes into an owned project knowledge directory, using the command's
root option; do not update the installed package. Public PRs/publications need
the user's authorization.

## Optional cloud assets

`um fal` and the upstream fal MCP require the user's fal account and paid API
usage. The bundle installs the CLI without registering fal, reading credentials
or making cloud calls. Use local art, installed ComfyUI/Blender or existing
image tools when they fit. Only use fal when the user requests that service and
has arranged their own authentication and spending authorization.

Credits/license: upstream MIT, commit
`15d6f9d5fbd32de9b1884f29ddec3be9133bd912`; included fonts are SIL OFL.
