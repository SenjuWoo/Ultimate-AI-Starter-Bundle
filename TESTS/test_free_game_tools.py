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
    mod.find_installed_app = lambda _key: None
    rows = {row["id"]: row for row in mod.collect()}
    assert rows["blender"]["installed"] is True
    assert rows["blender"]["path"] == blender
    assert rows["godot"]["installed"] is False
    assert rows["godot"]["path"] == ""


def test_an_install_that_is_not_on_path_still_counts_and_is_keyed_by_tool() -> None:
    """A Steam or portable Blender is installed; it must not make Godot installed."""
    import os
    spec = importlib.util.spec_from_file_location("free_game_tools", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    steam = os.path.join("steam-library", "steamapps", "common", "Blender", "blender.exe")
    mod.find_tool = lambda _names: None
    mod.find_windows_file = lambda _folder, _exe: None
    mod.find_installed_app = lambda key: steam if key == "blender" else None
    rows = {row["id"]: row for row in mod.collect()}
    assert rows["blender"]["installed"] is True and rows["blender"]["path"] == steam
    assert rows["godot"]["installed"] is False


def test_a_profile_wrapper_named_like_a_tool_is_not_the_tool() -> None:
    import os
    import tempfile
    spec = importlib.util.spec_from_file_location("free_game_tools", TOOL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with tempfile.TemporaryDirectory() as folder:
        wrapper = os.path.join(folder, "blender.bat")
        with open(wrapper, "w", encoding="utf-8") as handle:
            handle.write("@echo off\nhermes -p blender %*\n")
        real = os.path.join(folder, "godot.bat")
        with open(real, "w", encoding="utf-8") as handle:
            handle.write("@echo off\necho a real launcher\n")
        mod.shutil.which = lambda name: {"blender": wrapper, "godot": real}.get(name)
        assert mod.find_tool(("blender",)) is None
        assert mod.find_tool(("godot",)) == real

