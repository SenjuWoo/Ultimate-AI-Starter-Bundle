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


def _git(*args, binary=False, root=None):
    out = subprocess.run(["git", "-C", str(root or ROOT)] + list(args), capture_output=True)
    return out.stdout if binary else out.stdout.decode("utf-8", "replace")


def _changed(mode, base, root):
    if mode == "staged":
        listing = _git("diff", "--cached", "--name-only", root=root)
    elif mode == "base":
        listing = _git("diff", "--name-only", "%s..HEAD" % base, root=root)
    else:
        listing = _git("diff", "--name-only", root=root)
    return [n for n in listing.splitlines() if n.endswith(TEXT)]


def offenders(staged=False, root=None, base=None):
    """Files whose current bytes are LF-only where the comparison revision's were CRLF.

    `root` selects the repository: nothing is read from this checkout unless asked.
    """
    root_path = Path(root or ROOT)
    mode = "staged" if staged else ("base" if base else "tree")
    old_rev = "HEAD" if mode != "base" else base
    bad = []
    for name in _changed(mode, base, root):
        old = _git("show", "%s:%s" % (old_rev, name), binary=True, root=root)
        if b"\r\n" not in old:
            continue  # already LF-only there: not a regression
        if mode == "staged":
            new = _git("show", ":" + name, binary=True, root=root)
        elif mode == "base":
            new = _git("show", "HEAD:" + name, binary=True, root=root)
        else:
            path = root_path / name
            new = path.read_bytes() if path.exists() else b""
        if new and b"\r\n" not in new:
            bad.append(name)
    return bad


def main(argv=None):
    ap = argparse.ArgumentParser(description="Report files that lost their CRLF line endings")
    ap.add_argument("--staged", action="store_true", help="compare the index with HEAD")
    ap.add_argument("--base", metavar="REV",
                    help="compare commits REV..HEAD (what a release would publish)")
    ap.add_argument("--root", help="repository to inspect (defaults to this checkout)")
    args = ap.parse_args(argv)
    if args.staged and args.base:
        ap.error("--staged and --base compare different things; pick one")
    bad = offenders(staged=args.staged, root=args.root, base=args.base)
    for name in bad:
        print("line endings changed to LF: %s" % name)
    if bad:
        print("\nRestore them with: python TOOLS/restore_crlf.py   (adds CRLF, keeps content)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
