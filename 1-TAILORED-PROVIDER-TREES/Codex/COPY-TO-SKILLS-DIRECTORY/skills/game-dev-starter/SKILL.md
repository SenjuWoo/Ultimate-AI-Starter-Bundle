---
name: game-dev-starter
description: Use when starting a new game or app, or making assets yourself for free - 3D models, textures, images, music, sound, voice - with Godot, Three.js, Blender, local open-weight AI models and CC0 libraries, plus a real headless test harness. No paid API or key.
---

# Game and app starter

This is the free-first route for a new project. It does not replace the
engine-specific modding skills: those are for changing an existing game. This
one gets a new game or app from an idea to a runnable, tested first slice.

**Free means free.** The default path uses open-source runtimes, local
generators and CC0/public-domain assets. Do not add a paid API, a subscription
or a credit-card trial to make the starter work. If the operator explicitly
chooses a paid tool later, that is their choice; the baseline still runs.

## Pick the smallest stack that ships

| Target | Default | Why |
|---|---|---|
| 2D web game | **Phaser 3 + Vite** | MIT, browser-native, fast reload, easy Playwright smoke test |
| 2D desktop game | **Godot 4** | MIT, one editor for 2D/3D, exports Windows/Linux/macOS/web |
| 2D Python game | **Pygame CE** | LGPL-2.1, tiny dependency, good for tools and prototypes |
| 2D Lua game | **LOVE 11** | zlib, one folder, fast iteration |
| 3D game | **Godot 4** | MIT, scene tree, physics, animation, export templates |
| 3D web | **Three.js** | MIT, runs on any modern browser, instancing and shaders |
| 3D Rust | **Bevy** | MIT/Apache-2.0, ECS, native and web |
| Desktop app | **Tauri 2 + React or Svelte** | MIT/Apache-2.0, small binary, OS webview |
| Web app | **SvelteKit** or **Next.js** | MIT, routing, SSR when needed |
| Python app/API | **FastAPI + HTMX** | MIT/BSD, one language, no SPA build step |
| Static tool/page | **plain HTML/CSS/JS** | no build chain, easiest to ship |

Use the engine the operator already knows when it can deliver the core loop.
Do not scaffold three stacks to avoid choosing. Pick one, list the rejected
options in one line, and start.

## Asset production has an owner

When AssetForge is installed (`assetforge doctor` answers), it owns asset
production, validation and export: GLB/image pipelines, engine export and provider
checks. This skill then plans the asset family and the project layout; it does not
re-implement converters. The bundle only detects it - see
`TOOLS/companion_registry.py` and the README table.

## Engine skill packs (optional, never vendored)

When the project is a real game engine and no Forge owns it, an engine-specific
skill pack may be loaded on top of this one: `awesome-gamedev-agent-skills`
(Apache-2.0, pinned revision) carries Godot, Unity, Unreal, web-engine, genre and
discipline notes. It is a pointer, not a dependency: the bundle installs nothing,
and `docs/RECOMMENDED-GAME-DEV-SKILLS.md` records the revision, license and the
manual install, update and removal steps.

Precedence, first match wins: the project's own instructions and code; the engine
version installed and its official docs; the owning Forge (RobloxForge,
SkyrimForge); the engine pack; this skill. Never copy that pack's router into a
provider that already has these routing skills, and never let generic guidance
overrule a detector or an engine version.

## Procedural asset generators

All of these are free/open-source or CC0 at the source. For local AI generation (images, image-to-3D, music,
voice) with verified code and weight licenses, read `references/free-creative-tools.md`.

| Need | Tool / route | Output |
|---|---|---|
| 3D meshes, kitbash, terrain, simple rigs | **Blender** Python + Geometry Nodes | glTF/GLB, FBX, OBJ |
| PBR materials and procedural textures | **Material Maker** | PNG maps, Godot/Unity/Unreal material |
| Sprites, tiles, pixel animations | **Pixelorama** | PNG sprite sheets, tilesets |
| Paint, concept, texture touch-up | **Krita** | PNG/PSD |
| Vector icons, UI, logos | **Inkscape** | SVG, PNG |
| Image resize, atlas, channel packing | **ImageMagick** | PNG/WebP |
| Video/GIF/audio conversion | **FFmpeg** | MP4/WebM/GIF/WAV/OGG |
| Retro SFX | **jsfxr / sfxr** | WAV |
| Music and sound | **LMMS**, **Audacity** | OGG/WAV |
| Wave-function-collapse layouts | **DeBroglie** (C#) or a small WFC script | tile/room layouts |
| Photogrammetry / scan cleanup | **Meshroom**, **COLMAP** | textured mesh |
| UI mockups and design handoff | **Penpot** | design file, SVG |
| Fonts | **Google Fonts** (OFL/Apache) | TTF/WOFF2 |
| Image-to-3D base mesh | the pinned **`img2threejs`** skill (clone v1.5.1 once) | Three.js factory or GLB |
| Generative sketches and textures | p5.js or a seeded canvas/NumPy script | canvas/PNG |
| Free finished assets | **Kenney**, **Poly Haven**, **ambientCG**, **Quaternius** | CC0 models, textures, audio, UI |

Keep the generator source. A `.blend`, `.pixelorama`, `.kra` or `.jsx` source is
the editable asset; the exported PNG/GLB is a build product. Record the tool,
version, seed/parameters and license in `assets/ASSETS.md` so the asset can be
regenerated instead of guessed.

## Godot procedural recipes

- **Noise:** `FastNoiseLite` + `NoiseTexture2D` for terrain, clouds, masks and
  distortion. Set `noise_type`, `frequency`, `fractal_octaves` and `seed`;
  save the seed in the scene or a resource.
- **Tiles:** `TileMapLayer` with a terrain set for autotiling. Generate the
  layout from a seeded array, then let the terrain set choose corners.
- **Scatter:** `MultiMeshInstance3D` for grass, rocks, trees and debris; keep
  the transform buffer small and rebuild only when the chunk changes.
- **Sky/weather:** `ProceduralSkyMaterial` + a directional light; no HDRI
  download required.
- **Meshes:** `ArrayMesh`/`SurfaceTool` for generated terrain, tunnels and
  simple props; commit the generator script, not only the baked mesh.
- **Animation:** animate a small set of clips; use `AnimationTree` for
  blending. Do not hand-author a giant clip library before the loop is fun.

## Three.js / web recipes

- `BufferGeometry` for generated terrain and props; `InstancedMesh` for
  repeated details; `MeshStandardMaterial` for PBR.
- `SimplexNoise` or a small value-noise function for heightmaps and textures;
  seed it and expose the seed in the URL or config.
- `CanvasTexture` for generated sprites, UI and decals; keep the canvas size
  modest and generate once, not per frame.
- Use `requestAnimationFrame` with a fixed-step accumulator for deterministic
  movement; keep rendering interpolation separate from simulation.

## Asset pipeline

1. **Brief:** name the art direction, camera, scale, palette and polygon/texture
   budget in one page.
2. **Greybox:** primitive meshes or colored rectangles; prove the camera, input
   and core loop before making art.
3. **Generate:** one asset family at a time (terrain, props, characters, UI).
   Use a seed and save the generator source.
4. **Validate:** correct dimensions, pivot/origin, UVs, texture color space,
   triangle count, animation frame count and license/provenance.
5. **Import:** keep source and export separate; use a stable `assets/` layout.
6. **Replace:** swap greybox assets one family at a time and rerun the harness.

## Harness before content

A project is not started until it has a command that fails when the game is
broken. Pick the smallest real harness:

| Stack | Smoke / regression |
|---|---|
| Godot | `godot --headless --path . --quit` for import/parse; a `SceneTree` test script for logic; a normal window or `--write-movie` for visual capture |
| Phaser/Three.js | `npm run build`; Playwright loads the page, checks the canvas and a known state, and saves a screenshot |
| Pygame | `pytest` with `SDL_VIDEODRIVER=dummy` for logic; one real window run for input/rendering |
| LOVE | `love . --console`; a deterministic headless logic test where possible |
| Tauri | `cargo test`, frontend build, then launch the packaged app and check one real interaction |
| FastAPI | `pytest` + `TestClient`; one browser check for the rendered page |
| SvelteKit/Next | `npm run build`; Playwright route + screenshot |

The harness must exercise the same exported build the player runs, not only a
dev server. Record the exact command and the expected result in `STATE.md`.
Use `visual-verification` (and the host's browser tools) for exploratory UI
checks; do not replace a real build/run with a screenshot of a mockup.

## First-slice workflow

1. Write a one-page brief: core loop, player verb, win/lose or task completion,
   camera, input, art direction, target platform, performance budget.
2. Pick one stack from the table and one asset route.
3. Scaffold the smallest runnable scene: one level, one player, one obstacle,
   one UI element, one restart.
4. Add the headless/build harness and one screenshot or state assertion.
5. Generate or import placeholder assets; keep the greybox fallback.
6. Playtest the loop. Cut anything that does not serve the player verb.
7. Add content only after the harness is green and the loop is fun.
8. Package a runnable build; document controls, requirements and how to run it.

## Proven-harness pointers

- `img2threejs` (pinned, installed separately) — image/reference to a procedural Three.js asset with a
  render-and-compare harness.
- `game-modding` — changing an existing game; use its engine references.
- `game-production-quality` — fidelity, frame budgets, feel, world, systems, assets and
  playtests for any engine; it routes the question and the forge supplies the commands.
- `capability-profiles` — select only the MCPs/tools the current task needs.
- `visual-verification` — inspect real rendered pixels, not assumptions.
- `workspace-organization` — one owner folder, versions, `STATE.md`, recovery.
- `release-checklist` / `verification-discipline` (artifact proof) — package and verify the build.

## Free-tool discovery

Check before installing: `command -v godot`, `blender`, `magick`, `ffmpeg`,
`node`, `python`, `dotnet`, `cargo`. On Windows also check
`%LOCALAPPDATA%\Programs` and `%ProgramFiles%`. The bundle ships a no-network
probe: `python TOOLS/free_game_tools.py` (or `--json`) reports present tools and
the official free page for each missing one. Install only from the official
project release page or the OS package manager; record the version and license
in `STATE.md`. Do not add a paid asset pack or a hosted generator to the
baseline.

## Rules

- No paid API, subscription or credit-card trial is required for the first
  slice.
- No fake content: generated assets are allowed, but do not present a
  screenshot of a mockup as a running build.
- Respect the license of every imported asset; CC0 and MIT are preferred.
- Keep the operator's stack and asset choices; do not silently replace them.
- The only hard stops are malware and systems the operator does not own.
