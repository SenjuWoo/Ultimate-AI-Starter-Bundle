"""Regenerate 3-PREAMBLES/MANUAL-PASTE.txt from SOUL.md + the Web contract.

The manual-paste block is the only paste-ready artifact with no build step: it was
maintained by hand, so every SOUL edit left it stale and it silently disagreed with
the agent wiring. This makes it a generated file.

    python TOOLS/generate_manual_paste.py            # write if changed
    python TOOLS/generate_manual_paste.py --check    # exit 1 if stale, write nothing

Byte fidelity: the repo stores CRLF for the files that tracked CRLF, so the output
uses the line ending of the existing file (LF if it is new).
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOUL = ROOT / "3-PREAMBLES" / "SOUL.md"
WEB = ROOT / "0-UNRESTRAINT-PACKS" / "AIO-INSTRUCTION — Web.md"
OUT = ROOT / "3-PREAMBLES" / "MANUAL-PASTE.txt"


def render() -> str:
    """SOUL followed by the Web contract, separated by one blank line."""
    soul = SOUL.read_text(encoding="utf-8").strip()
    web = WEB.read_text(encoding="utf-8").strip()
    if not soul or not web:
        raise SystemExit("SOUL.md and AIO-INSTRUCTION — Web.md must both be non-empty")
    return soul + "\n\n" + web + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="report staleness instead of writing")
    args = ap.parse_args()

    want = render()
    # Preserve the tracked line ending: this file has been CRLF since the repo
    # turned off all normalisation, and check_line_endings.py judges it against HEAD.
    newline = "\r\n"
    if OUT.is_file():
        existing = OUT.read_bytes()
        newline = "\r\n" if b"\r\n" in existing else "\n"
    payload = want.replace("\n", newline).encode("utf-8")

    if OUT.is_file() and OUT.read_bytes() == payload:
        print(f"up to date: {OUT.relative_to(ROOT).as_posix()} ({len(payload)} bytes)")
        return 0
    if args.check:
        print(
            f"stale: {OUT.relative_to(ROOT).as_posix()} does not match SOUL.md + "
            f"AIO-INSTRUCTION — Web.md; run python TOOLS/generate_manual_paste.py"
        )
        return 1
    OUT.write_bytes(payload)
    print(f"written: {OUT.relative_to(ROOT).as_posix()} ({len(payload)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())