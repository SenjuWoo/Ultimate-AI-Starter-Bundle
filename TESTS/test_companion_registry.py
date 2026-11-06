"""Registry contract tests: the bundle must never trust a remote manifest blindly.

Runs standalone (`python TESTS/test_companion_registry.py`) and under pytest.
"""
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "TOOLS"))

import companion_registry as reg  # noqa: E402


def _data(**over):
    base = {
        "schema": 1,
        "owner_allowlist": ["github.com/SenjuWoo/"],
        "companions": {
            "demo": {
                "title": "Demo",
                "repo": "https://github.com/SenjuWoo/demo",
                "install": {"kind": "release_zip", "asset": "Demo-*.zip"},
                "markers": ["demo.exe"],
                "platforms": ["windows"],
            }
        },
    }
    base.update(over)
    return base


def test_real_registry_is_valid():
    data = reg.load()
    assert data["companions"], "registry is empty"
    for cid, entry in data["companions"].items():
        assert entry["repo"].startswith("https://github.com/SenjuWoo/"), cid


def test_rejects_foreign_owner():
    data = _data()
    data["companions"]["demo"]["repo"] = "https://github.com/evil/demo"
    try:
        reg.validate(data)
    except reg.RegistryError as exc:
        assert "allowlist" in str(exc)
    else:
        raise AssertionError("a foreign owner was accepted")


def test_rejects_source_only_with_asset():
    data = _data()
    data["companions"]["demo"]["install"] = {"kind": "source_only", "asset": "Demo-*.zip"}
    try:
        reg.validate(data)
    except reg.RegistryError as exc:
        assert "source_only" in str(exc)
    else:
        raise AssertionError("source_only with an asset was accepted")


def test_rejects_unknown_kind():
    data = _data()
    data["companions"]["demo"]["install"] = {"kind": "curl_bash"}
    try:
        reg.validate(data)
    except reg.RegistryError:
        pass
    else:
        raise AssertionError("unknown install kind was accepted")


def test_detects_installed_and_missing():
    with tempfile.TemporaryDirectory() as root:
        installed = os.path.join(root, "Demo")
        os.makedirs(installed)
        open(os.path.join(installed, "demo.exe"), "w").close()
        report = reg.status([root], _data())
        assert report["demo"]["state"] == "INSTALLED", report
        assert report["demo"]["path"] == installed

        empty = tempfile.mkdtemp()
        report = reg.status([empty], _data())
        assert report["demo"]["state"] == "NOT_FOUND", report


def test_partial_folder_is_discovered_not_installed():
    with tempfile.TemporaryDirectory() as root:
        partial = os.path.join(root, "demo")
        os.makedirs(partial)  # name matches, marker missing
        report = reg.status([root], _data())
        assert report["demo"]["state"] == "DISCOVERED", report


def test_registry_is_never_executed():
    """The module exposes no command runner: a registry cannot make the bundle run something."""
    source = open(os.path.join(ROOT, "TOOLS", "companion_registry.py"), encoding="utf-8").read()
    for forbidden in ("subprocess", "os.system", "os.exec", "os.spawn"):
        assert forbidden not in source, "companion_registry must not execute commands (%s)" % forbidden


def test_every_companion_declares_capabilities_and_platforms():
    data = reg.load()
    for cid, entry in data["companions"].items():
        assert entry.get("capabilities"), cid
        assert entry.get("platforms"), cid
        caps = entry["capabilities"]
        assert any(k in caps for k in ("cli", "mcp", "skills", "gui")), cid


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print("ok  ", name)
            except Exception as exc:  # noqa: BLE001
                failures += 1
                print("FAIL", name, "->", exc)
    print("\n%d failed" % failures)
    sys.exit(1 if failures else 0)
