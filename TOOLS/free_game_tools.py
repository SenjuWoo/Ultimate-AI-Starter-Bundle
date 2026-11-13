#!/usr/bin/env python3
"""Report which free game/app tools are present on this machine, and install one on request.

The report needs no network and no key: the AI sees what already exists before
downloading anything, what each program is for, and the official page for
whatever is missing. Nothing is installed unless a tool is named with
--install; then only that program is installed, from its publisher's own winget
package.

Usage:
    python TOOLS/free_game_tools.py
    python TOOLS/free_game_tools.py --json
    python TOOLS/free_game_tools.py --install ffmpeg godot
    python TOOLS/free_game_tools.py --install core     (blender, ffmpeg, imagemagick, godot)
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys

# Each entry is (id, label, command candidates, official free page).
TOOLS = [
    ("godot", "Godot 4 (2D/3D engine)", ("godot", "godot4", "Godot"), "https://godotengine.org/download"),
    ("blender", "Blender (3D/procedural)", ("blender", "Blender"), "https://www.blender.org/download/"),
    ("material-maker", "Material Maker (PBR textures)", ("material-maker", "MaterialMaker"), "https://www.materialmaker.org/"),
    ("pixelorama", "Pixelorama (pixel art)", ("pixelorama", "Pixelorama"), "https://pixelorama.org/"),
    ("krita", "Krita (paint/texture)", ("krita", "Krita"), "https://krita.org/en/download/"),
    ("inkscape", "Inkscape (vector/UI)", ("inkscape", "Inkscape"), "https://inkscape.org/release/"),
    ("imagemagick", "ImageMagick (atlas/resize)", ("magick",), "https://imagemagick.org/script/download.php"),
    ("ffmpeg", "FFmpeg (audio/video)", ("ffmpeg",), "https://ffmpeg.org/download.html"),
    ("node", "Node.js (web/desktop app)", ("node", "nodejs"), "https://nodejs.org/en/download"),
    ("npm", "npm (JS packages)", ("npm",), "https://nodejs.org/en/download"),
    ("python", "Python (tools/API)", ("python", "python3", "py"), "https://www.python.org/downloads/"),
    ("uv", "uv (isolated Python tools)", ("uv",), "https://docs.astral.sh/uv/getting-started/installation/"),
    ("dotnet", ".NET SDK (C#/DeBroglie)", ("dotnet",), "https://dotnet.microsoft.com/download"),
    ("cargo", "Rust/Cargo (Bevy)", ("cargo",), "https://rustup.rs/"),
    ("love", "LOVE 11 (2D Lua)", ("love", "lovec"), "https://love2d.org/"),
    ("git", "Git", ("git",), "https://git-scm.com/downloads"),
    ("lmms", "LMMS (music)", ("lmms",), "https://lmms.io/download"),
    ("musescore", "MuseScore (scores/music)", ("mscore", "musescore", "MuseScore4"), "https://musescore.org/en/download"),
    ("audacity", "Audacity (audio edit)", ("audacity",), "https://www.audacityteam.org/download/"),
    ("fluidsynth", "FluidSynth (MIDI to audio)", ("fluidsynth",), "https://github.com/FluidSynth/fluidsynth/releases"),
]

# What each program is for, and the first headless command an agent reaches for.
USES = {
    "godot": ("game engine; run or test a project headless, import-check an exported asset", "godot --headless --path PROJECT --import"),
    "blender": ("3D modelling, rigging, format conversion and renders by script", "blender --background --python make.py"),
    "material-maker": ("procedural PBR materials exported as texture maps", ""),
    "pixelorama": ("pixel art, sprites and tiles", ""),
    "krita": ("painting and textures; kritarunner runs scripts", "kritarunner -s script"),
    "inkscape": ("vector art and UI; SVG to PNG at a size", "inkscape in.svg --export-type=png -w 512"),
    "imagemagick": ("convert and resize images in bulk, contact sheets, atlases, DDS and EXR", "magick in.png -resize 512x512 out.png"),
    "ffmpeg": ("convert audio and video, frames to video, trim; ffprobe reads media facts", "ffmpeg -i in.wav out.ogg"),
    "node": ("JavaScript runtime for web and desktop apps and their build tools", "node --version"),
    "npm": ("JavaScript packages", "npm ci"),
    "python": ("scripts, tools and APIs", "python -m venv .venv"),
    "uv": ("isolated Python tools and environments", "uv venv"),
    "dotnet": ("C# builds and tools", "dotnet build"),
    "cargo": ("Rust builds (Bevy and CLI tools)", "cargo build --release"),
    "love": ("2D games in Lua", "love ."),
    "git": ("version control", "git status"),
    "lmms": ("music production", ""),
    "musescore": ("scores and notation to audio", ""),
    "audacity": ("audio editing", ""),
    "fluidsynth": ("MIDI to audio with a SoundFont", "fluidsynth -F out.wav font.sf2 song.mid"),
}

# The publisher's own winget package for each program this file may install.
# Ids were checked against `winget show`; a tool without one is never installed
# here (Python is the bundle's shared runtime, .NET is versioned per project).
WINGET = {
    "godot": "GodotEngine.GodotEngine", "blender": "BlenderFoundation.Blender",
    "material-maker": "RodZill4.MaterialMaker", "pixelorama": "OramaInteractive.Pixelorama",
    "krita": "KDE.Krita", "inkscape": "Inkscape.Inkscape", "imagemagick": "ImageMagick.ImageMagick",
    "ffmpeg": "Gyan.FFmpeg", "node": "OpenJS.NodeJS.LTS", "npm": "OpenJS.NodeJS.LTS", "uv": "astral-sh.uv",
    "cargo": "Rustlang.Rustup", "love": "Love2d.Love2d", "git": "Git.Git", "lmms": "LMMS.LMMS",
    "musescore": "Musescore.Musescore", "audacity": "Audacity.Audacity",
}

# The four an asset or game task reaches for first. `--install core` and the
# installer's -CreativeTools switch mean exactly these.
CORE = ("blender", "ffmpeg", "imagemagick", "godot")

# Extra Windows locations, keyed by tool id. A shared list credited the first
# hit to whichever catalog row was missing: Godot absent and Blender present
# reported Godot as installed at blender.exe.
WIN_GLOBS = {
    "godot": [
        (r"%LOCALAPPDATA%\Programs\Godot", "godot.exe"),
        (r"%PROGRAMFILES%\Godot", "godot.exe"),
    ],
    "blender": [
        (r"%LOCALAPPDATA%\Programs\Blender Foundation", "blender.exe"),
        (r"%PROGRAMFILES%\Blender Foundation", "blender.exe"),
    ],
    "pixelorama": [
        (r"%LOCALAPPDATA%\Programs\Pixelorama", "pixelorama.exe"),
    ],
    "krita": [
        (r"%PROGRAMFILES%\Krita", "krita.exe"),
    ],
    "inkscape": [
        (r"%PROGRAMFILES%\Inkscape", "inkscape.exe"),
    ],
    "lmms": [
        (r"%PROGRAMFILES%\LMMS", "lmms.exe"),
    ],
    "musescore": [
        (r"%PROGRAMFILES%\MuseScore 4", "MuseScore4.exe"),
    ],
    "audacity": [
        (r"%PROGRAMFILES%\Audacity", "audacity.exe"),
    ],
}


def expand(path: str) -> str:
    return os.path.expandvars(os.path.expanduser(path))


def find_tool(names: tuple[str, ...]) -> str | None:
    for name in names:
        hit = shutil.which(name)
        if hit and not _is_profile_wrapper(hit):
            return hit
    return None


def _app_paths():
    """The bundle's shared app discovery; absent when this file is run on its own."""
    here = os.path.dirname(os.path.abspath(__file__))
    if here not in sys.path:
        sys.path.insert(0, here)
    try:
        import app_paths
    except Exception:  # noqa: BLE001 - the plain PATH probe above still works
        return None
    return app_paths


def _is_profile_wrapper(path: str) -> bool:
    """`blender.bat` that starts a Hermes profile is not Blender."""
    module = _app_paths()
    return bool(module and module.hermes_wrapper(path))


def find_installed_app(key: str) -> str | None:
    """An install that is not on PATH: Steam libraries, the uninstall registry, tool roots."""
    module = _app_paths()
    app = next((row for row in module.APPS if row["id"] == key), None) if module else None
    if not app:
        return None
    try:
        found = module.candidates(app, module.open_store(), module.Machine())
    except Exception:  # noqa: BLE001 - a probe never fails the report
        return None
    return found[0][0] if found else None


def find_windows_file(folder: str, exe: str) -> str | None:
    base = expand(folder)
    if not os.path.isdir(base):
        return None
    for root, dirs, files in os.walk(base):
        for name in files:
            if name.lower() == exe.lower():
                return os.path.join(root, name)
        # Do not descend forever into a large install tree.
        if root.count(os.sep) - base.count(os.sep) > 3:
            dirs[:] = []
    return None


def collect() -> list[dict]:
    rows = []
    for key, label, names, url in TOOLS:
        path = find_tool(names)
        if not path:
            for folder, exe in WIN_GLOBS.get(key, ()):
                path = find_windows_file(folder, exe)
                if path:
                    break
        if not path:
            path = find_installed_app(key)
        use, example = USES.get(key, ("", ""))
        package = WINGET.get(key, "")
        rows.append({
            "id": key,
            "label": label,
            "installed": bool(path),
            "path": path or "",
            "free_url": url,
            "use": use,
            "example": example,
            "core": key in CORE,
            "winget": package,
            "install": ("python TOOLS/free_game_tools.py --install " + key) if package else "",
        })
    return rows


def _winget(command: list[str]) -> int:
    return subprocess.run(command).returncode


def install(ids: list[str], runner=None, winget: str | None = None) -> int:
    """Install the named tools that are missing. Returns 0 only when every one is present afterwards."""
    rows = {row["id"]: row for row in collect()}
    wanted = list(CORE) if ids == ["core"] else list(dict.fromkeys(ids))
    unknown = [key for key in wanted if key not in rows]
    if unknown:
        print("unknown tool id(s): " + ", ".join(unknown) + ". Known: " + ", ".join(rows) + ", or `core`.")
        return 2
    winget = winget if winget is not None else (shutil.which("winget") or "")
    failed, installed = 0, []
    for key in wanted:
        row = rows[key]
        if row["installed"]:
            print(f"OK   {key}: already installed at {row['path']}")
            continue
        package = WINGET.get(key)
        if not package or not winget:
            why = "this tool has no package here" if not package else "winget is not available on this system"
            print(f"--   {key}: not installed ({why}). Official download: {row['free_url']}")
            failed += 1
            continue
        code = (runner or _winget)([winget, "install", "--id", package, "--exact", "--source", "winget", "--silent",
                                    "--accept-package-agreements", "--accept-source-agreements", "--disable-interactivity"])
        if code == 0:
            print(f"OK   {key}: installed from winget package {package}")
            installed.append(key)
        else:
            print(f"FAIL {key}: winget exited {code} for {package}. Official download: {row['free_url']}")
            failed += 1
    module = _app_paths() if installed and runner is None else None
    if module:
        # Make the new names work; a failure here is reported by the next doctor run.
        subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "app_paths.py"),
                        "--fix", "--no-version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("Names repaired. Restart AI apps and terminals opened before this install; they keep the PATH they started with.")
    return 1 if failed else 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Report the free game/app tools on this machine; install one on request")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--install", nargs="+", metavar="ID",
                    help="install these missing tools from their publisher's winget package; `core` means " + ", ".join(CORE))
    args = ap.parse_args(argv)
    if args.install:
        return install(args.install)
    rows = collect()
    if args.json:
        print(json.dumps(rows, indent=2))
        return 0
    print("FREE GAME/APP TOOL DISCOVERY (no paid key, no install)")
    print("=" * 72)
    for row in rows:
        mark = "OK  " if row["installed"] else "--  "
        print(f"{mark}{row['label']}")
        if row["installed"]:
            print(f"      {row['path']}")
        else:
            print(f"      free: {row['free_url']}")
            if row["install"]:
                print(f"      install: {row['install']}")
        if row["use"]:
            print(f"      for: {row['use']}")
    missing = [r["label"] for r in rows if not r["installed"]]
    print("=" * 72)
    print(f"{len(rows) - len(missing)}/{len(rows)} present" +
          ("; missing: " + ", ".join(missing) if missing else ""))
    print("Missing tools are optional. Install only the ones the chosen stack needs, and ask the user first.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
