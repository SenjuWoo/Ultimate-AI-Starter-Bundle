"""Drift reporting must classify without ever writing or fetching when offline."""

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))

import check_upstream_drift as drift  # noqa: E402

REGISTRY = {"recommended": {"pack": {"title": "p", "repo": "https://github.com/o/p",
                                     "pin": "19d93f97c9c1ea0f8b306e77aa81e0d3e352d3e9",
                                     "license": "Apache-2.0", "markers": ["LICENSE"],
                                     "docs": "docs/X.md"}},
            "companions": {"owner": {"title": "O", "repo": "https://github.com/o/r",
                                     "install": {"kind": "source_only"}, "markers": ["VERSION"],
                                     "platforms": ["windows"]}}}


def rows(tmp_path=None):
    path = ROOT / "TESTS" / "_drift_fixture.json"
    path.write_text(json.dumps(REGISTRY), encoding="utf-8")
    try:
        return drift.load(path)
    finally:
        path.unlink()


def test_offline_marks_nothing_as_checked():
    out = drift.report(rows(), offline=True)
    assert {r["state"] for r in out} == {"unknown", "tracks-latest"}
    assert all(r["head"] is None for r in out)


def test_matching_head_is_current_and_a_different_one_drifts():
    same = drift.report(rows(), fetch=lambda url: "19d93f97c9c1ea0f8b306e77aa81e0d3e352d3e9")
    assert [r["state"] for r in same if r["id"] == "pack"] == ["current"]
    moved = drift.report(rows(), fetch=lambda url: "ffffffffffffffffffffffffffffffffffffffff")
    assert [r["state"] for r in moved if r["id"] == "pack"] == ["drifted"]


def test_a_missing_network_is_unknown_not_a_failure():
    out = drift.report(rows(), fetch=lambda url: None)
    assert [r["state"] for r in out if r["id"] == "pack"] == ["unknown"]


def test_the_tool_never_runs_git_pull_or_writes():
    source = (ROOT / "TOOLS" / "check_upstream_drift.py").read_text(encoding="utf-8")
    for banned in ("git pull", "git fetch", "write_text(", "subprocess.run([\"git\""):
        assert banned not in source, banned


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_"):
            fn()
            print("ok   " + name)
    print("\n0 failed")
