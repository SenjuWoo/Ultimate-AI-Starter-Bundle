# Creative and media programs an agent drives from the shell

What each program is for, the first command to reach for, and how it gets onto
a machine that lacks it. Read `MACHINE-MAP.md` first: its `Apps on PATH` line
lists the ones already installed here, by the name to type.

| Program | Use it for | First command | Install id |
|---|---|---|---|
| Blender (`blender`) | 3D modelling, rigging, format conversion and renders by script | `blender --background --python make.py` | `blender` |
| Godot 4 (`godot`) | run or test a project headless; import-check an exported asset | `godot --headless --path PROJECT --import` | `godot` |
| FFmpeg (`ffmpeg`, `ffprobe`) | convert audio and video, frames to video, trim, read media facts | `ffmpeg -framerate 24 -i frame_%04d.png -pix_fmt yuv420p out.mp4` | `ffmpeg` |
| ImageMagick (`magick`) | convert and resize in bulk, contact sheets, atlases, DDS and EXR | `magick in.png -resize 512x512 out.png` | `imagemagick` |
| Inkscape (`inkscape`) | vector art and UI; SVG to PNG at a size | `inkscape in.svg --export-type=png -w 512` | `inkscape` |
| Krita (`krita`, `kritarunner`) | painting and textures; scripts through `kritarunner` | `kritarunner -s script` | `krita` |
| GIMP (`gimp-console`) | batch image edits through Script-Fu or Python | `gimp-console -i -b "(gimp-quit 0)"` | not in the installer |
| Material Maker | procedural PBR materials exported as texture maps | open the app; export from the graph | `material-maker` |
| Pixelorama | pixel art, sprites and tiles | open the app | `pixelorama` |
| Audacity, LMMS, MuseScore | audio editing, music and scores | open the app | `audacity`, `lmms`, `musescore` |

`convert.exe` in Windows' System32 is a disk tool, not ImageMagick: use `magick`.
On Windows a console build prints to the terminal; the `godot` and
`gimp-console` commands the bundle writes already point at it.

## When one is missing

1. Check it is really missing: `python TOOLS\free_game_tools.py` lists every
   program with its path, including Steam, registry and portable installs that
   are not on PATH. An installed program that does not answer by name is a PATH
   problem; `python TOOLS\app_paths.py --fix` repairs it.
2. Ask the user before installing. Say which program, what the task needs it
   for and its size class (Blender and Godot are large; FFmpeg and ImageMagick
   are small).
3. Install the named program only:

```text
python TOOLS\free_game_tools.py --install ffmpeg
python TOOLS\free_game_tools.py --install core      blender, ffmpeg, imagemagick, godot
```

   The ids map to the publisher's own package in winget (Blender Foundation,
   Godot Engine, Gyan's FFmpeg builds that ffmpeg.org links to, ImageMagick
   Studio). These were reviewed for this pack, so no separate verdict line is
   needed. A program that is not in the table follows the normal rule: check
   the official source and licence, then record a verdict in `SAFE-TOOLS.md`.
4. The installer then makes the name work (`app_paths.py --fix` runs for you)
   and the next install refreshes `MACHINE-MAP.md`. A running session keeps the
   PATH it started with: use the full path the report prints until the AI app
   restarts.

Without winget (Linux, macOS, a locked-down PC) the command prints the official
download page instead of installing. Never install a creative program the task
does not need, and never as a side effect of something else.
