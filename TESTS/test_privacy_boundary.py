#!/usr/bin/env python3
"""Personal-data boundary guard for a public repository.

This repository ships as a public artifact. Chat exports, account records,
real names, personal e-mail addresses, machine home paths and local-only
notes must never be committed. This test scans every tracked file and fails
listing what it found, so a leak is caught before a push.

Policy lives in SECURITY.md ("Personal data boundary"). Run:

    python TESTS/test_privacy_boundary.py
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# Markers of the maintainer's private environment. Test files that define
# these as regex guards are exempt; nothing else is.
MARKERS = [
    (re.compile(r"\bkarlo\b", re.I), "maintainer account name"),
    (re.compile(r"[A-Za-z]:[\\/]{1,2}Users[\\/]{1,2}karlo", re.I), "machine home path"),
    (re.compile(r"[\w.+-]+@(?:gmail|outlook|hotmail|yahoo|icloud)\.[a-z]{2,}", re.I), "personal e-mail address"),
    (re.compile(r"\bMoncton\b", re.I), "maintainer locality"),
    (re.compile(r"\bZ:[\\/]{1,2}Backup[\\/]{1,2}(?:Ai[ _-]+(?:Documentation|Games)|!Skyrim AE)", re.I), "maintainer workspace path"),
]
ALLOW_FILES = {
    "TESTS/test_privacy_boundary.py",   # this file defines the markers
    "TESTS/test_release_contract.py",   # pre-existing guards use the same literals
}

# Paths that mark an export / private stash, whatever their content.
FORBIDDEN_PATH_PARTS = ("LOCAL-ONLY", "Ai History", "zExport", "/memories/")
FORBIDDEN_FILE_NAMES = ("conversations.json", "users.json", "login_history.json", "chat.html")

# The .gitignore must keep blocking the personal-data classes even when this
# test is not run. Substrings, checked case-sensitively against the file.
REQUIRED_IGNORES = ("/LOCAL-ONLY/", "conversations*.json", "users.json", "login_history.json", "memories/", "*.local.md", "*.local.json")


def tracked_files() -> list[str]:
    out = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files", "-z"],
        capture_output=True, check=True,
    )
    return out.stdout.decode("utf-8").split("\0")[:-1]


def main() -> int:
    fails: list[str] = []

    gi = (ROOT / ".gitignore").read_text(encoding="utf-8", errors="replace")
    for pat in REQUIRED_IGNORES:
        if pat not in gi:
            fails.append(f".gitignore no longer blocks {pat!r}")

    for rel in tracked_files():
        posix = rel.replace("\\", "/")
        if posix in ALLOW_FILES:
            continue
        if ("/" + posix).find("/" + "LOCAL-ONLY") >= 0 or posix.startswith("LOCAL-ONLY"):
            fails.append(f"{rel}: tracked file under a local-only path")
            continue
        if any(part in "/" + posix + "/" for part in FORBIDDEN_PATH_PARTS):
            fails.append(f"{rel}: tracked file under a private path")
            continue
        if any(posix.endswith("/" + name) or posix == name for name in FORBIDDEN_FILE_NAMES):
            fails.append(f"{rel}: tracked export/account file name")
            continue
        try:
            text = (ROOT / rel).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for rx, label in MARKERS:
            m = rx.search(text)
            if m:
                line = text.count("\n", 0, m.start()) + 1
                fails.append(f"{rel}:{line}: {label} ({m.group(0)[:60]!r})")

    if fails:
        print("PRIVACY BOUNDARY: FAIL (%d finding(s))" % len(fails))
        for f in fails[:40]:
            print("  " + f)
        if len(fails) > 40:
            print("  ... and %d more" % (len(fails) - 40))
        return 1
    print("PRIVACY BOUNDARY: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
