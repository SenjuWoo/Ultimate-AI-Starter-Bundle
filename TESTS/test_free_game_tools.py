"""Probe contract for TOOLS/free_game_tools.py (no network, no install)."""
from __future__ import annotations

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
    assert len(rows) == 16
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
