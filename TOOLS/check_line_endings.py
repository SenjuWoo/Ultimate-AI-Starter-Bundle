"""Refuse a commit that silently turns CRLF files into LF.

`.gitattributes` sets `* -text`, so git stores bytes exactly as written and a text
editor that "normalises" line endings produces a whole-file diff. This checks the
staged content against the parent commit and reports files that lost their CRLF.

    python TOOLS/check_line_endings.py            # working tree vs HEAD
    python TOOLS/check_line_endings.py --staged   # index vs HEAD (pre-commit)
"""

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEXT = (".md", ".py", ".ps1", ".psm1", ".json", ".txt", ".yml", ".yaml", ".cmd", ".bat")


def git(*args, binary=False, root=None):
    out = subprocess.run(["git", "-C", str(root or ROOT)] + list(args), capture_output=True)
    return out.stdout if binary else out.stdout.decode("utf-8", "replace")


def offenders(staged=False, root=None):
    names = git("diff", "--cached", "--name-only", root=root) if staged else git("diff", "--name-only", root=root)
    bad = []
    for name in [n for n in names.splitlines() if n.endswith(TEXT)]:
        old = git("show", "HEAD:%s" % name, binary=True, root=root)
        if b"\r\n" not in old:
            continue
        new = git("show", ":%s" % name, binary=True) if staged else (ROOT / name).read_bytes() \
            if (ROOT / name).exists() else b""
        if new and b"\r\n" not in new:
            bad.append(name)
    return bad


def main(argv=None):
    ap = argparse.ArgumentParser(description="Report files that lost their CRLF line endings")
    ap.add_argument("--staged", action="store_true", help="compare the index with HEAD")
    args = ap.parse_args(argv)
    bad = offenders(staged=args.staged)
    for name in bad:
        print("line endings changed to LF: %s" % name)
    if bad:
        print("\nRestore them with: python TOOLS/restore_crlf.py   (adds CRLF, keeps content)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
