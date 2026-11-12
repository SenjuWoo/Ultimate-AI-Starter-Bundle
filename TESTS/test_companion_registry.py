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
        assert report["demo"]["state"] == "INSTALLED_UNVERIFIED", report
        assert report["demo"]["path"] == installed

        empty = tempfile.mkdtemp()
        report = reg.status([empty], _data())
        assert report["demo"]["state"] == "NOT_FOUND", report


def test_owner_pointer_resolves_the_actual_kit_root():
    with tempfile.TemporaryDirectory() as root:
        owner = os.path.join(root, "kit")
        os.makedirs(os.path.join(owner, "sandbox"))
        for marker in ("VERSION", "Install-Modkit.ps1", os.path.join("sandbox", "installed.json")):
            target = os.path.join(owner, marker)
            os.makedirs(os.path.dirname(target), exist_ok=True)
            open(target, "w").close()
        pointer = os.path.join(root, "kit.json")
        with open(pointer, "w", encoding="utf-8") as fh:
            json.dump({"kit_root": owner}, fh)
        data = _data()
        data["companions"]["demo"]["pointer"] = pointer
        data["companions"]["demo"]["markers"] = ["VERSION", "Install-Modkit.ps1", "sandbox/installed.json"]
        report = reg.status([], data)
        assert report["demo"]["state"] == "INSTALLED_UNVERIFIED", report
        assert report["demo"]["path"] == owner


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


def test_rejects_spoofed_repositories_and_escaping_markers():
    data = _data()
    data["companions"]["demo"]["repo"] = "https://github.com.evil.com/SenjuWoo/demo"
    try:
        reg.validate(data)
    except reg.RegistryError as exc:
        assert "owner" in str(exc).lower() or "repository" in str(exc).lower()
    else:
        raise AssertionError("a spoofed owner was accepted")

    data = _data()
    data["companions"]["demo"]["markers"] = ["../outside.exe"]
    try:
        reg.validate(data)
    except reg.RegistryError as exc:
        assert "escape" in str(exc).lower() or "inside" in str(exc).lower()
    else:
        raise AssertionError("an escaping marker was accepted")


def test_versioned_asset_marker_is_detected_inside_its_owner():
    with tempfile.TemporaryDirectory() as root:
        owner = os.path.join(root, "Demo")
        os.makedirs(owner)
        open(os.path.join(owner, "Demo-1.2.3-STANDALONE.exe"), "w").close()
        data = _data()
        data["companions"]["demo"]["markers"] = ["Demo-*-STANDALONE.exe"]
        report = reg.status([root], data)
        assert report["demo"]["state"] == "INSTALLED_UNVERIFIED", report


def test_recommended_pack_is_data_only_and_detectable():
    """A recommended pack is a pointer: detected, never installed or executed."""
    data = reg.load()
    entry = data["recommended"]["awesome-gamedev-agent-skills"]
    assert entry["license"] == "Apache-2.0"
    assert len(entry["pin"]) == 40
    for banned in ("install", "update", "doctor"):
        assert banned not in entry

    with tempfile.TemporaryDirectory() as tmp:
        root = os.path.join(tmp, "awesome-gamedev-agent-skills")
        os.makedirs(os.path.join(root, "router"))
        os.makedirs(os.path.join(root, "skills"))
        open(os.path.join(root, "router", "SKILL.md"), "w").close()
        open(os.path.join(root, "LICENSE"), "w").close()
        found = reg.recommended_status([tmp], data)["awesome-gamedev-agent-skills"]
        assert found["state"] == "MARKERS_FOUND", (found, "a marker hit must not claim verification")
        assert found["path"].replace("\\", "/").endswith("awesome-gamedev-agent-skills")

        missing = reg.recommended_status([os.path.join(tmp, "nowhere")], data)
        assert missing["awesome-gamedev-agent-skills"]["state"] == "NOT_FOUND"


def test_rejects_a_recommended_entry_that_could_execute():
    data = _data()
    data["recommended"] = {"pack": {"title": "p",
                                    "repo": "https://github.com/gamedev-skills/x",
                                    "pin": "19d93f97c9c1ea0f8b306e77aa81e0d3e352d3e9",
                                    "license": "Apache-2.0",
                                    "markers": ["LICENSE"],
                                    "docs": "docs/X.md",
                                    "install": {"kind": "source_only"}}}
    try:
        reg.validate(data)
    except reg.RegistryError as exc:
        assert "must not declare" in str(exc)
    else:
        raise AssertionError("an executable recommended entry was accepted")

def test_owner_one_level_deeper_is_found_and_a_decoy_is_not():
    """People keep tools in a sub-folder ("Tools/Ai tools"), so a bounded two-level
    search is the difference between "not installed" and the truth."""
    with tempfile.TemporaryDirectory() as root:
        deep = os.path.join(root, "tools", "games", "Demo")
        os.makedirs(deep)
        open(os.path.join(deep, "demo.exe"), "w").close()
        decoy = os.path.join(root, "demo")
        os.makedirs(decoy)  # right name, no marker: not an install
        report = reg.status([root], _data())
        assert report["demo"]["state"] == "INSTALLED_UNVERIFIED", report
        assert report["demo"]["path"] == deep, report


def test_owner_folder_named_after_the_owner_but_empty_is_partial():
    with tempfile.TemporaryDirectory() as root:
        half = os.path.join(root, "Demo")
        os.makedirs(half)
        report = reg.status([root], _data())
        assert report["demo"]["state"] in ("DISCOVERED", "NOT_FOUND"), report


def test_ambiguous_owners_need_a_valid_explicit_pointer():
    from unittest.mock import patch
    with tempfile.TemporaryDirectory() as root:
        owners = [os.path.join(root, group, "Demo") for group in ("live", "archive")]
        for owner in owners:
            os.makedirs(owner)
            open(os.path.join(owner, "demo.exe"), "w").close()
        data = _data()
        data["companions"]["demo"]["root_env"] = "UABS_TEST_DEMO_ROOT"
        with patch.dict(os.environ, {"UABS_TEST_DEMO_ROOT": os.path.join(root, "gone")}):
            row = reg.status([root], data)["demo"]
            assert row["state"] == "AMBIGUOUS" and row["path"] is None, row
        with patch.dict(os.environ, {"UABS_TEST_DEMO_ROOT": owners[0]}):
            row = reg.status([root], data)["demo"]
            assert row["path"] == owners[0] and row["source"] == "environment", row


def test_discovery_does_not_scan_dependencies_or_count_overlapping_roots_twice():
    with tempfile.TemporaryDirectory() as root:
        owner = os.path.join(root, "Demo")
        ignored = os.path.join(root, "node_modules", "Demo")
        for path in (owner, ignored):
            os.makedirs(path)
            open(os.path.join(path, "demo.exe"), "w").close()
        row = reg.status([root, owner], _data())["demo"]
        assert row["state"] == "INSTALLED_UNVERIFIED" and row["candidates"] == [owner], row


# Folder names an owner really lives under: '!' breaks cmd delayed expansion, the
# space and parentheses break unquoted shells, and the accent breaks byte-wise code.
AWKWARD = "!Sky tools (x) \u00e9"


def _owner(parent, name="Demo", checkout=False):
    owner = os.path.join(parent, name)
    os.makedirs(owner)
    open(os.path.join(owner, "demo.exe"), "w").close()
    if checkout:
        os.makedirs(os.path.join(owner, ".git"))
    return owner


def test_checkout_plus_runtime_is_one_owner_not_an_ambiguity():
    with tempfile.TemporaryDirectory() as root:
        source = _owner(os.path.join(root, AWKWARD), checkout=True)
        runtime = _owner(os.path.join(root, "installed"))
        row = reg.status([root], _data())["demo"]
        assert row["state"] == "INSTALLED_UNVERIFIED" and row["path"] == runtime, row
        assert row["source_path"] == source, row


def test_two_checkouts_without_a_runtime_stay_ambiguous():
    with tempfile.TemporaryDirectory() as root:
        first = _owner(os.path.join(root, "a"), checkout=True)
        second = _owner(os.path.join(root, "b"), checkout=True)
        row = reg.status([root], _data())["demo"]
        assert row["state"] == "AMBIGUOUS" and row["path"] is None, row
        assert row["source_path"] is None and sorted(row["source_candidates"]) == [first, second], row


def test_moved_source_is_found_at_its_new_awkward_path():
    """The source follows the folder: no record of the old location is consulted."""
    import shutil
    with tempfile.TemporaryDirectory() as root:
        old = _owner(os.path.join(root, "general tools"), checkout=True)
        new_parent = os.path.join(root, AWKWARD)
        os.makedirs(new_parent)
        moved = shutil.move(old, os.path.join(new_parent, "Demo"))
        row = reg.status([root], _data())["demo"]
        assert row["path"] == moved and row["source_path"] == moved, row


def test_doctor_command_is_argv_with_the_owner_interpreter():
    with tempfile.TemporaryDirectory() as root:
        owner = _owner(os.path.join(root, AWKWARD))
        scripts = os.path.join(owner, ".venv", "Scripts")
        os.makedirs(scripts)
        open(os.path.join(scripts, "python.exe"), "w").close()
        entry = dict(_data()["companions"]["demo"], doctor={"entrypoint": ["python", "-m", "demo", "doctor"]})
        plan = reg.doctor_command(entry, owner)
        assert plan["cwd"] == owner and plan["argv"][1:] == ["-m", "demo", "doctor"], plan
        assert plan["argv"][0] == os.path.join(scripts, "python.exe"), plan
        assert reg.doctor_command(_data()["companions"]["demo"], owner) is None
        assert reg.doctor_command(entry, None) is None


def test_awkward_owner_path_survives_a_real_process_boundary():
    """argv plus cwd must reach a child process byte-for-byte, with no shell in between."""
    import subprocess
    with tempfile.TemporaryDirectory() as root:
        owner = _owner(os.path.join(root, AWKWARD))
        with open(os.path.join(owner, "doctor.py"), "w", encoding="utf-8") as fh:
            fh.write("import os, sys\nsys.stdout.buffer.write(os.getcwd().encode('utf-8'))\n")
        entry = dict(_data()["companions"]["demo"], doctor={"entrypoint": ["python", "doctor.py"]})
        plan = reg.doctor_command(entry, owner)
        argv = [sys.executable] + plan["argv"][1:]
        done = subprocess.run(argv, cwd=plan["cwd"], capture_output=True, timeout=60)
        assert done.returncode == 0, done.stderr
        assert os.path.normcase(done.stdout.decode("utf-8")) == os.path.normcase(os.path.realpath(owner)) \
            or os.path.normcase(done.stdout.decode("utf-8")) == os.path.normcase(owner), done.stdout


def test_print_doctor_handles_an_owner_that_declares_none():
    """An owner without a doctor is written as null or as a null entrypoint; neither may crash."""
    import contextlib
    import io
    from unittest.mock import patch
    for shape in (None, {"entrypoint": None}):
        data = _data()
        data["companions"]["demo"]["doctor"] = shape
        for flags in ([], ["--json"]):
            out = io.StringIO()
            with patch.object(reg, "load", lambda data=data: data), contextlib.redirect_stdout(out):
                assert reg.main(["--print-doctor", "demo"] + flags) == 0
            assert ("no doctor declared" in out.getvalue()) or ('"argv": null' in out.getvalue()), out.getvalue()


if __name__ == "__main__":
    failures = 0
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            try:
                fn()
                print("ok  ", name)
            except Exception as exc:
                failures += 1
                print("FAIL", name, "->", exc)
    print("\n%d failed" % failures)
    sys.exit(1 if failures else 0)
