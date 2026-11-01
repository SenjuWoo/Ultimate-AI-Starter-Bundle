"""Visible AI-attribution stripper: fixture checks for the shipped filter."""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("strip_ai", ROOT / "TOOLS" / "Strip-AI-Attribution.py")
assert SPEC and SPEC.loader
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


def test_strips_known_visible_lines_and_keeps_body_text() -> None:
    sample = (
        "# Project\n\n"
        "Generated with [Claude Code](https://claude.ai/code)\n\n"
        "Co-authored-by: Claude <noreply@anthropic.com>\n"
        "Real text about AI-generated textures stays.\n"
    )
    out, n = MOD.strip_text(sample)
    assert n == 2
    assert "Claude Code" not in out
    assert "Co-authored-by" not in out
    assert "Real text about AI-generated textures stays." in out


if __name__ == "__main__":
    test_strips_known_visible_lines_and_keeps_body_text()
    print("ai attribution tests: PASS")
