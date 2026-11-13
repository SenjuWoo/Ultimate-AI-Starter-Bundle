# Free tools to make assets yourself: 3D, textures, images, music, sound, voice

Checked 2026-11-03 against each project's GitHub repository and, for AI models, the Hugging Face model card.
Licenses and repositories move: recheck the one you pick before shipping its output, and record tool, version,
seed and license in `assets/ASSETS.md`.

## Order of preference

1. **Code you write** (deterministic, diffable, no download): Blender Python, Godot `FastNoiseLite`/`SurfaceTool`,
   Three.js `BufferGeometry`, NumPy/Pillow textures, MIDI from Python. Keep the generator; the output is a build product.
2. **Free desktop generators** driven by script or CLI (Blender, Material Maker, FFmpeg, ImageMagick, FluidSynth).
3. **Local open-weight AI models** on the user's GPU. Check VRAM first (`nvidia-smi`); never send work to a paid
   hosted API unless the user chose it.
4. **CC0 libraries** for finished pieces: Kenney, Poly Haven, ambientCG, Quaternius.

Code license and model-weight license are different things. A tool can be MIT while its weights forbid commercial
use. "Gated" means the model page asks the user to accept terms with their own account: say so and let the user
accept; never accept on their behalf.

## By medium

| Make | Tool (repository) | License (code / weights) | Notes |
|---|---|---|---|
| 3D models, scenes, rigs, renders | Blender (`blender/blender`) | GPL (app); your files are yours | `blender --background --python make.py`; headless glTF export |
| 3D in the browser / code-built assets | Three.js (`mrdoob/three.js`) + the `img2threejs` skill | MIT | render-and-compare harness included in `img2threejs` |
| Image to 3D mesh (AI) | TRELLIS / TRELLIS.2 (`microsoft/TRELLIS`, `microsoft/TRELLIS.2`) | MIT / MIT | strongest free option checked; needs a large GPU |
| Image to 3D mesh (AI, light) | TripoSR (`VAST-AI-Research/TripoSR`) | MIT / MIT | fast single-image base mesh; retopologise in Blender |
| Image to 3D (AI) | Hunyuan3D-2 (`Tencent-Hunyuan/Hunyuan3D-2`) | custom / Tencent Hunyuan community license | read the license terms before commercial or regional use |
| PBR materials, procedural textures | Material Maker (`RodZill4/material-maker`) | MIT | node graphs export albedo/normal/roughness maps |
| Pixel art, sprites, tiles | Pixelorama (`Orama-Interactive/Pixelorama`) | MIT | |
| Images (AI), local UI and API | ComfyUI (`Comfy-Org/ComfyUI`), `comfy-cli` | GPL-3.0 | workflows as JSON; see `tool-discovery` -> `references/comfy-cli.md` |
| Images (AI), commercial-friendly weights | FLUX.1-schnell, Qwen-Image, Z-Image-Turbo | Apache-2.0 weights (FLUX.1-schnell is gated) | |
| Images (AI), older and lighter | SDXL base 1.0 | CreativeML OpenRAIL++-M | use-based restrictions; widest LoRA ecosystem |
| Images (AI), restricted | SD 3.5 | Stability AI community license, gated | free below a revenue threshold; read it |
| Music by code | music21 (BSD-3, PyPI `music21`), MIDI -> audio with FluidSynth (`FluidSynth/fluidsynth`, LGPL-2.1) + a free SoundFont | permissive | fully deterministic; the AI can compose, render and listen-check by analysis |
| Music by live code | Sonic Pi (`sonic-pi-net/sonic-pi`), SuperCollider (GPL-3.0) | see repo | Strudel moved off GitHub (archived there) |
| Music, DAW | LMMS (`LMMS/lmms`, GPL-2.0), MuseScore (`musescore/MuseScore`) | free apps; see each repo licence | |
| Music (AI) | ACE-Step 1.5 (`ace-step/ACE-Step-1.5`) | MIT / MIT | songs with lyrics, local |
| Music (AI), non-commercial | MusicGen via `facebookresearch/audiocraft` | MIT / CC-BY-NC-4.0 | not for a commercial release |
| Sound effects | jsfxr (`chr15m/jsfxr`, Unlicense), FFmpeg filters | permissive | retro SFX from parameters; store the parameter string |
| Sound (AI), restricted | Stable Audio Open 1.0 | Stability community license, gated | read it |
| Voice / TTS | Kokoro-82M (`hexgrad/kokoro`) | Apache-2.0 / Apache-2.0 | small, CPU-capable |
| Voice / TTS, cloning | Chatterbox (`resemble-ai/chatterbox`) | MIT / MIT | clone only voices the user has rights to |
| Voice / TTS | Piper (`OHF-Voice/piper1-gpl`; the old `rhasspy/piper` is archived) | GPL-3.0 | voices carry their own licenses |
| Voice (AI), non-commercial | F5-TTS (`SWivid/F5-TTS`) | MIT / CC-BY-NC-4.0 | |
| Convert, resize, atlas, audio/video | FFmpeg, ImageMagick | LGPL/GPL, Apache-style | the glue for every pipeline |

## Tools the AI makes for itself

When no tool fits, build the smallest one: a script in the project (`coding-discipline`), a CLI wrapper
(`capability-routing`), an MCP server when several sessions will reuse it (`build-mcp-server`), or a skill when the
knowledge is reusable (`skill-creator`). Prove it on a real input before relying on it.

## Probe

`python TOOLS/free_game_tools.py` (or `--json`) lists which of the desktop tools above are installed, what each is
for and the official page for each missing one. It installs nothing unless you name a tool: after the user agrees,
`python TOOLS/free_game_tools.py --install ffmpeg` (or `--install core` for Blender, FFmpeg, ImageMagick and Godot)
installs that program from its publisher's winget package and makes its name work.
