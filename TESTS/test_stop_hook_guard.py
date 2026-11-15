"""A Stop gate may block a turn once, never again while its own block is in flight.

Claude Code and Codex send `stop_hook_active` (snake_case) on the Stop fire that a
previous block caused. Both bundle gates only read `stopHookActive`, so a finished
turn that still had a finding was blocked again and again until the host's
consecutive-block cap (8 on Claude) ended it: wasted turns and tokens on every
inconsistent repository. Real payloads, real gate processes, temp repositories.
"""

import json
import shutil
import string
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOKS = ROOT / "TOOLS" / "hooks"


def git(cwd, *args):
    subprocess.run(["git", "-c", "core.autocrlf=false", *args], cwd=cwd, check=True,
                   capture_output=True)


def repo(tmp):
    git(tmp, "init", "-q")
    git(tmp, "config", "user.email", "t@example.invalid")
    git(tmp, "config", "user.name", "t")
    git(tmp, "config", "commit.gpgsign", "false")


def stop(gate, cwd, **extra):
    payload = {"hook_event_name": "Stop", "session_id": "t", "cwd": str(cwd), **extra}
    out = subprocess.run([sys.executable, str(HOOKS / gate), "--stop"], cwd=cwd,
                         input=json.dumps(payload), capture_output=True, text=True, timeout=60)
    assert out.returncode == 0, out.stderr
    return out.stdout.strip()


def missing_drive():
    import os
    for letter in reversed(string.ascii_uppercase):
        if not os.path.exists(letter + ":\\"):
            return letter
    raise RuntimeError("every drive letter exists")


def main():
    failures = []
    tmp = Path(tempfile.mkdtemp(prefix="uabs-stop-guard-"))
    try:
        # Completeness gate: a version bump with no changelog entry is a finding.
        rel = tmp / "release"
        rel.mkdir()
        repo(rel)
        (rel / "VERSION.txt").write_text("Thing 1.0.0\n", encoding="utf-8")
        (rel / "CHANGELOG.md").write_text("# Changelog\n\n## 1.0.0\n- first\n", encoding="utf-8")
        (rel / "README.md").write_text("# Thing 1.0.0\n", encoding="utf-8")
        git(rel, "add", "-A")
        git(rel, "commit", "-qm", "init")
        (rel / "VERSION.txt").write_text("Thing 1.1.0\n", encoding="utf-8")
        git(rel, "add", "-A")
        git(rel, "commit", "-qm", "bump")

        # Assumption gate: an uncommitted script naming a drive that does not exist.
        paths = tmp / "paths"
        paths.mkdir()
        repo(paths)
        (paths / "README.md").write_text("x\n", encoding="utf-8")
        git(paths, "add", "-A")
        git(paths, "commit", "-qm", "init")
        (paths / "run.ps1").write_text('copy "%s:\\tools\\x.exe" .\n' % missing_drive(), encoding="utf-8")

        for gate, cwd in (("completeness_gate.py", rel), ("assumption_gate.py", paths)):
            first = stop(gate, cwd, stop_hook_active=False)
            if '"block"' not in first:
                failures.append("%s: fixture produced no first block (%r)" % (gate, first))
            for key in ("stop_hook_active", "stopHookActive"):
                again = stop(gate, cwd, **{key: True})
                if again:
                    failures.append("%s blocked again with %s=true: %s" % (gate, key, again))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    for line in failures:
        print("FAIL: " + line)
    print("stop hook guard: %s" % ("FAIL" if failures else "OK"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
