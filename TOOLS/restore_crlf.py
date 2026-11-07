"""Restore CRLF in files that lost it, compared with a git revision.

    python TOOLS/restore_crlf.py [BASE]      # BASE defaults to HEAD
Writes only files whose base blob used CRLF and whose current bytes use none.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = sys.argv[1] if len(sys.argv) > 1 else "HEAD"
TEXT = (".md", ".py", ".ps1", ".psm1", ".json", ".txt", ".yml", ".yaml", ".cmd", ".bat")


def git(*args, binary=True, root=None):
    out = subprocess.run(["git", "-C", str(root or ROOT)] + list(args), capture_output=True)
    return out.stdout if binary else out.stdout.decode("utf-8", "replace")


def main(root=None, base=None):
    base = base or BASE
    names = [n for n in git("diff", "--name-only", base + "..HEAD" if base != "HEAD" else base,
                            binary=False, root=root).splitlines() if n.endswith(TEXT)]
    if BASE == "HEAD":
        names += [n for n in git("diff", "--name-only", binary=False, root=root).splitlines() if n.endswith(TEXT)]
    converted = []
    for name in dict.fromkeys(names):
        p = Path(root or ROOT) / name
        if not p.is_file():
            continue
        old = git("show", "%s:%s" % (base, name), root=root)
        if b"\r\n" not in old:
            continue
        now = p.read_bytes()
        if b"\r\n" not in now:
            p.write_bytes(now.replace(b"\n", b"\r\n"))
            converted.append(name)
    print("converted:", len(converted))
    for name in converted:
        print("  " + name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
