"""The line-ending guard must catch exactly the regression that shipped three times.

Uses a throwaway git repository so it can create a real CRLF file, rewrite it with
LF, and prove the checker reports it and the restore tool repairs it.
"""

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))

import check_line_endings as guard  # noqa: E402
import restore_crlf as restore  # noqa: E402


def _git(repo, *args):
    return subprocess.run(["git", "-C", str(repo)] + list(args), capture_output=True)


def _make_repo(tmp):
    repo = Path(tmp)
    _git(repo, "init", "-q")
    (repo / ".gitattributes").write_bytes(b"* -text\r\n")
    (repo / "notes.md").write_bytes(b"one\r\ntwo\r\n")
    _git(repo, "add", "-A")
    _git(repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init")
    return repo


def test_the_guard_flags_a_file_that_lost_its_crlf():
    with tempfile.TemporaryDirectory() as tmp:
        repo = _make_repo(tmp)
        old_root = guard.ROOT
        guard.ROOT = repo
        try:
            assert guard.offenders() == []
            (repo / "notes.md").write_bytes(b"one\ntwo\n")
            assert guard.offenders() == ["notes.md"]
            assert guard.main([]) == 1
        finally:
            guard.ROOT = old_root


def test_restore_puts_the_crlf_back_and_keeps_content():
    with tempfile.TemporaryDirectory() as tmp:
        repo = _make_repo(tmp)
        (repo / "notes.md").write_bytes(b"one\ntwo\nthree\n")
        restore.main(root=repo, base="HEAD")
        data = (repo / "notes.md").read_bytes()
        assert data.count(b"\r\n") == 3, data
        assert b"three" in data


def test_a_feature_file_is_left_alone():
    with tempfile.TemporaryDirectory() as tmp:
        repo = _make_repo(tmp)
        (repo / "notes.md").write_bytes(b"one\ntwo\n")     # a file that was always LF
        assert guard.offenders(root=repo) == []


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok   " + name)
    print("\n0 failed")
