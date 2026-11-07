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


def _commit(repo, message):
    _git(repo, "add", "-A")
    _git(repo, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", message)


def _repo(tmp, always_lf=None):
    """One CRLF file plus, optionally, a file that was always LF; both committed."""
    repo = Path(tmp)
    _git(repo, "init", "-q")
    (repo / ".gitattributes").write_bytes(b"* -text\r\n")
    (repo / "notes.md").write_bytes(b"one\r\ntwo\r\n")
    if always_lf:
        (repo / always_lf).write_bytes(b"alpha\nbeta\n")
    _commit(repo, "init")
    return repo


def test_working_tree_regression_is_reported_and_fixed():
    with tempfile.TemporaryDirectory() as tmp:
        repo = _repo(tmp)
        assert guard.offenders(root=repo) == []
        (repo / "notes.md").write_bytes(b"one\ntwo\n")
        assert guard.offenders(root=repo) == ["notes.md"], "the working-tree mode missed it"
        assert guard.main(["--root", str(repo)]) == 1
        restore.main(root=repo, base="HEAD")
        assert (repo / "notes.md").read_bytes() == b"one\r\ntwo\r\n"
        assert guard.offenders(root=repo) == []


def test_staged_regression_is_reported_from_the_index():
    with tempfile.TemporaryDirectory() as tmp:
        repo = _repo(tmp)
        (repo / "notes.md").write_bytes(b"one\ntwo\nthree\n")
        _git(repo, "add", "-A")
        assert guard.offenders(staged=True, root=repo) == ["notes.md"]
        assert guard.main(["--staged", "--root", str(repo)]) == 1


def test_a_file_that_was_always_lf_is_not_a_regression():
    with tempfile.TemporaryDirectory() as tmp:
        repo = _repo(tmp, always_lf="feature.md")
        (repo / "feature.md").write_bytes(b"alpha\nbeta\ngamma\n")
        assert guard.offenders(root=repo) == [], "a born-LF file was reported as churn"


def test_a_committed_range_is_what_ci_judges():
    with tempfile.TemporaryDirectory() as tmp:
        repo = _repo(tmp)
        base = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        (repo / "notes.md").write_bytes(b"one\ntwo\n")
        _commit(repo, "convert line endings")
        assert guard.offenders(base=base, root=repo) == ["notes.md"], "the committed range missed it"
        assert guard.main(["--base", base, "--root", str(repo)]) == 1


def test_clean_history_passes_every_mode():
    with tempfile.TemporaryDirectory() as tmp:
        repo = _repo(tmp)
        base = subprocess.run(["git", "-C", str(repo), "rev-parse", "HEAD"],
                              capture_output=True, text=True).stdout.strip()
        (repo / "notes.md").write_bytes(b"one\r\ntwo\r\nthree\r\n")
        _commit(repo, "append a line")
        assert guard.offenders(root=repo) == []
        assert guard.offenders(base=base, root=repo) == []
        assert guard.main(["--base", base, "--root", str(repo)]) == 0


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok   " + name)
    print("\n0 failed")
