#!/usr/bin/env python3
"""Remove visible AI attribution lines from text files the operator owns.

This is a formatting filter, not a provenance remover. It cannot touch a
provider's server-side or invisible watermark. By default it reports what it
would change; --apply writes a timestamped .bak beside each changed file and
never follows symlinks or rewrites binary files.

Usage:
  python TOOLS/Strip-AI-Attribution.py PATH [PATH ...]
  python TOOLS/Strip-AI-Attribution.py --apply PATH [PATH ...]
  python TOOLS/Strip-AI-Attribution.py --self-test
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

# Attribution lines, not every mention of AI. Keep this list narrow so a
# legitimate sentence such as "the AI-generated texture" survives.
AI = r"(?:Claude(?:\s+Code)?|ChatGPT|OpenAI|Anthropic|Gemini|Copilot|Grok|Codex)"
PATTERNS = [
    re.compile(rf"^\s*(?:🤖\s*)?(?:Generated|Made|Created|Produced)\s+(?:with|by)\s+\[?{AI}\]?\b.*$", re.I),
    re.compile(rf"^\s*Co-authored-by:\s*{AI}\b.*$", re.I),
    re.compile(rf"^\s*(?:Authored|Written)\s+by\s+{AI}\b.*$", re.I),
    re.compile(rf"^\s*_?(?:Generated|Made)\s+with\s+\[?{AI}\]?(?:_|\s)*$", re.I),
]
TEXT_SUFFIXES = {
    ".md", ".txt", ".rst", ".py", ".ps1", ".js", ".ts", ".tsx", ".jsx",
    ".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".html", ".css",
    ".cs", ".c", ".h", ".cpp", ".hpp", ".rs", ".go", ".java", ".kt",
    ".sh", ".bat", ".cmd", ".xml", ".sql", ".lua",
}


def strip_text(text: str) -> tuple[str, int]:
    kept: list[str] = []
    removed = 0
    for line in text.splitlines(keepends=True):
        if any(p.match(line.rstrip("\r\n")) for p in PATTERNS):
            removed += 1
            continue
        kept.append(line)
    return "".join(kept), removed


def iter_files(paths: list[str]):
    for raw in paths:
        p = Path(raw)
        if p.is_dir():
            for child in p.rglob("*"):
                if child.is_file() and not child.is_symlink() and child.suffix.lower() in TEXT_SUFFIXES:
                    yield child
        elif p.is_file() and not p.is_symlink() and p.suffix.lower() in TEXT_SUFFIXES:
            yield p


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("paths", nargs="*", help="files or directories to scan")
    ap.add_argument("--apply", action="store_true", help="write changes; default is a dry run")
    ap.add_argument("--self-test", action="store_true", help="run the built-in fixture")
    args = ap.parse_args()

    if args.self_test:
        sample = (
            "# Project\n\n"
            "Generated with [Claude Code](https://claude.ai/code)\n\n"
            "Co-authored-by: Claude <noreply@anthropic.com>\n"
            "Real text about AI-generated textures stays.\n"
        )
        out, n = strip_text(sample)
        assert n == 2, n
        assert "Real text about AI-generated textures stays." in out
        print("self-test PASS")
        return 0
    if not args.paths:
        ap.error("give at least one path, or --self-test")

    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    changed = 0
    removed = 0
    for path in iter_files(args.paths):
        try:
            data = path.read_text(encoding="utf-8")
        except (UnicodeDecodeError, OSError):
            continue
        new, n = strip_text(data)
        if not n:
            continue
        changed += 1
        removed += n
        print(f"{'APPLY' if args.apply else 'WOULD'} {path} ({n} line(s))")
        if args.apply:
            shutil.copy2(path, path.with_name(path.name + f".aiattr-{stamp}.bak"))
            path.write_text(new, encoding="utf-8", newline="")
    print(f"{'changed' if args.apply else 'would change'} {changed} file(s), {removed} line(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
