"""Recheck an RTK candidate against real status states and the fixed Git corpus."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path


def run(argv, cwd):
    return subprocess.run(argv, cwd=cwd, capture_output=True, timeout=60, check=True).stdout


def verify(rtk, root):
    with tempfile.TemporaryDirectory(prefix="uabs-rtk-") as home:
        p = Path(home)
        git = lambda *args: run(["git", *args], p)
        git("init", "-q")
        git("config", "user.email", "fixture@example.invalid")
        git("config", "user.name", "Fixture")
        for name in ("staged.txt", "unstaged.txt", "deleted.txt", "renamed.txt", "unicode-é.txt"):
            (p / name).write_text("base\n", encoding="utf-8")
        git("add", ".")
        git("commit", "-qm", "fixture")
        (p / "staged.txt").write_text("staged\n", encoding="utf-8")
        git("add", "staged.txt")
        (p / "unstaged.txt").write_text("unstaged\n", encoding="utf-8")
        (p / "deleted.txt").unlink()
        git("mv", "renamed.txt", "new-name.txt")
        (p / "unicode-é.txt").write_text("unicode\n", encoding="utf-8")
        (p / "untracked.txt").write_text("untracked\n", encoding="utf-8")
        for flag in ("--short", "-s"):
            raw = git("status", flag)
            filtered = run([str(rtk), "git", "status", flag], p)
            assert raw.splitlines() == filtered.splitlines(), (flag, raw, filtered)
    rows = []
    for args in (("diff", "v8.6.1..v8.6.5"), ("log", "v8.6.1..v8.6.5"),
                 ("diff", "v8.6.4..v8.6.5"), ("log", "--stat", "-20", "v8.6.5")):
        raw = run(["git", *args], root)
        filtered = run([str(rtk), "git", *args], root)
        rows.append({"args": list(args), "raw_bytes": len(raw), "rtk_bytes": len(filtered)})
    return {"version": run([str(rtk), "--version"], root).decode().strip(),
            "status_fixture": "PASS: staged, unstaged, deleted, renamed, Unicode, untracked",
            "corpus": rows, "basis": "stdout bytes, not losslessness or billed tokens"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--rtk", required=True, type=Path)
    ns = parser.parse_args()
    print(json.dumps(verify(ns.rtk.resolve(), Path(__file__).resolve().parents[1]), indent=2))
