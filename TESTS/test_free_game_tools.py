"""Probe contract for TOOLS/free_game_tools.py (no network, no install)."""
from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "TOOLS" / "free_game_tools.py"


def test_probe_lists_free_choices_and_never_counts_windows_convert() -> None:
    out = subprocess.run(
        [sys.executable, str(TOOL), "--json"],
        check=True, capture_output=True, text=True, timeout=60,
    )
    rows = json.loads(out.stdout)
    by_id = {row["id"]: row for row in rows}
    assert len(rows) == 20
    for required in ("godot", "blender", "material-maker", "pixelorama", "ffmpeg", "python"):
        assert required in by_id
    # Windows' built-in C:\WINDOWS\system32\convert.exe is not ImageMagick.
    magick = by_id["imagemagick"]
    if magick["path"]:
        assert Path(magick["path"]).name.lower() in {"magick", "magick.exe"}


def test_probe_human_output_names_a_missing_free_page() -> None:
    out = subprocess.run(
        [sys.executable, str(TOOL)],
        check=True, capture_output=True, text=True, timeout=60,
    )
    text = out.stdout
    assert "FREE GAME/APP TOOL DISCOVERY" in text
    assert "free: https://" in text
    assert "Missing tools are optional" in text


def test_windows_fallback_does_not_credit_a_different_tool() -> None:
    """A Blender install must not satisfy a missing Godot row."""
    spec = importlib.util.spec_from_file_location("free_game_tools", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    blender = r"C:\Program Files\Blender Foundation\Blender\blender.exe"

    def no_path(_names):
        return None

    def only_blender(_folder, exe):
        if exe.lower() == "blender.exe":
            return blender
        return None

    mod.find_tool = no_path
    mod.find_windows_file = only_blender
    rows = {row["id"]: row for row in mod.collect()}
    assert rows["blender"]["installed"] is True
    assert rows["blender"]["path"] == blender
    assert rows["godot"]["installed"] is False
    assert rows["godot"]["path"] == ""
