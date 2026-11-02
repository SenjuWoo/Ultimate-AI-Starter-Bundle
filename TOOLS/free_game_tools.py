#!/usr/bin/env python3
"""Report which free game/app tools are present on this machine.

No install, no network, no key. The goal is to make the free starter concrete:
the AI can see what already exists before downloading anything, and the human
gets the official project page for whatever is missing.

Usage:
    python TOOLS/free_game_tools.py
    python TOOLS/free_game_tools.py --json
"""
from __future__ import annotations

import json
import os
import shutil
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
]

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
}


def expand(path: str) -> str:
    return os.path.expandvars(os.path.expanduser(path))


def find_tool(names: tuple[str, ...]) -> str | None:
    for name in names:
        hit = shutil.which(name)
        if hit:
            return hit
    return None


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
        rows.append({
            "id": key,
            "label": label,
            "installed": bool(path),
            "path": path or "",
            "free_url": url,
        })
    return rows


def main() -> int:
    rows = collect()
    if "--json" in sys.argv:
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
    missing = [r["label"] for r in rows if not r["installed"]]
    print("=" * 72)
    print(f"{len(rows) - len(missing)}/{len(rows)} present" +
          ("; missing: " + ", ".join(missing) if missing else ""))
    print("Missing tools are optional. Install only the ones the chosen stack needs.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
