"""Read-only legacy skill helper regressions; run directly with Python stdlib.
All destinations are disposable fixtures; no provider homes are inspected.
"""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("install_live_skills", ROOT / "TOOLS/install_live_skills.py")
assert spec is not None and spec.loader is not None
live = importlib.util.module_from_spec(spec)
spec.loader.exec_module(live)


class ReadOnlySkills(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(prefix="uabs live skills ")
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.canon = self.root / "canonical"
        (self.canon / "example").mkdir(parents=True)
        (self.canon / "example/SKILL.md").write_bytes(b"canonical\n")
        self.dest = self.root / "skills"
        self.dest.mkdir()
        overrides = patch.object(live, "OVERRIDES", str(self.root / "skill-overrides.json"))
        overrides.start()
        self.addCleanup(overrides.stop)
        env = patch.dict(os.environ, {"USERPROFILE": str(self.root), "LOCALAPPDATA": str(self.root)})
        env.start()
        self.addCleanup(env.stop)

    @unittest.skipUnless(os.name == "nt", "Windows junction regression")
    def test_write_request_cannot_follow_live_skill_junction(self):
        import _winapi
        target = self.root / "other profile"
        target.mkdir()
        marker = target / "SKILL.md"
        marker.write_bytes(b"native owned\n")
        link = self.dest / "example"
        _winapi.CreateJunction(str(target), str(link))
        notes = []
        refused = False
        try:
            live.install(str(self.canon), str(self.dest), "Hermes", False, notes)
        except ValueError as error:
            self.assertIn("check-only", str(error))
            refused = True
        self.assertEqual(marker.read_bytes(), b"native owned\n", notes)
        self.assertTrue(os.path.isjunction(link))
        self.assertTrue(refused, "write requests must fail explicitly")

    @unittest.skipUnless(os.name == "nt", "Windows junction regression")
    def test_cli_write_request_keeps_unrelated_dangling_junction(self):
        import _winapi
        target = self.root / "missing target"
        target.mkdir()
        link = self.dest / "provider-only-extra"
        _winapi.CreateJunction(str(target), str(link))
        target.rmdir()
        output = io.StringIO()
        with patch.object(live, "HOMES", {"Hermes": str(self.dest)}), \
                patch.object(sys, "argv", [str(ROOT / "TOOLS/install_live_skills.py"), str(self.canon)]), \
                contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            with self.assertRaises(SystemExit) as error:
                live.main()
        self.assertEqual(error.exception.code, 2)
        self.assertIn("check-only", output.getvalue())
        self.assertIn(live.WRITE_GUIDANCE.format(providers="Claude"), output.getvalue())
        self.assertTrue(os.path.lexists(link), "removed unrelated dangling junction before backup")
        self.assertEqual(list(self.root.glob("skills.bak-*")), [])

    def test_api_refuses_writes_before_reading_paths_or_ownership(self):
        Path(live.OVERRIDES).write_text("invalid registry", encoding="ascii")
        with self.assertRaisesRegex(ValueError, "check-only") as error:
            live.install(str(self.root / "absent"), str(self.root / "absent dest"), "Hermes", False, [])
        self.assertIn(live.WRITE_GUIDANCE.format(providers="Hermes"), str(error.exception))
        self.assertFalse((self.root / "absent dest").exists())

    @unittest.skipUnless(os.name == "nt", "Windows junction regression")
    def test_root_and_nested_junction_targets_stay_unchanged(self):
        import _winapi
        for location in ("root", "nested"):
            with self.subTest(location=location):
                target = self.root / (location + " other profile")
                target.mkdir()
                marker = target / "SKILL.md"
                marker.write_bytes(b"owned elsewhere\n")
                if location == "root":
                    (target / "example").mkdir()
                    marker = target / "example/SKILL.md"
                    marker.write_bytes(b"owned elsewhere\n")
                    dest = self.root / "linked root"
                    link = dest
                else:
                    (self.canon / "example/scripts").mkdir()
                    (self.canon / "example/scripts/SKILL.md").write_bytes(b"canonical nested\n")
                    (self.dest / "example").mkdir()
                    dest = self.dest
                    link = dest / "example/scripts"
                _winapi.CreateJunction(str(target), str(link))
                for check in (True, False):
                    if check:
                        live.install(str(self.canon), str(dest), "Hermes", check, [])
                    else:
                        with self.assertRaisesRegex(ValueError, "check-only"):
                            live.install(str(self.canon), str(dest), "Hermes", check, [])
                    self.assertEqual(marker.read_bytes(), b"owned elsewhere\n")
                    self.assertTrue(os.path.isjunction(link))

    def test_check_retains_counts_and_never_copies_files(self):
        (self.dest / "example").mkdir()
        (self.dest / "example/SKILL.md").write_bytes(b"local native skill\n")
        (self.canon / "example/new.ps1").write_bytes(b"\xef\xbb\xbfnew script\r\n")
        (self.canon / "example/same.txt").write_bytes(b"same\n")
        (self.dest / "example/same.txt").write_bytes(b"same\n")
        before = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(live.install(str(self.canon), str(self.dest), "Hermes", True, []), (1, 1, 1, 1, 0))
        after = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob("*") if p.is_file()}
        self.assertEqual(after, before)

    def test_check_still_honors_local_overrides(self):
        Path(live.OVERRIDES).write_text(json.dumps({"providers": {"Hermes": {"example": {}}}}), encoding="utf-8")
        notes = []
        self.assertEqual(live.install(str(self.canon), str(self.dest), "Hermes", True, notes), (0, 0, 0, 0, 1))
        self.assertIn("preserved local override", notes[0])
        self.assertEqual(list(self.dest.iterdir()), [])

    def test_cli_check_retains_report_without_backups(self):
        output = io.StringIO()
        with patch.object(live, "HOMES", {"Hermes": str(self.dest)}), \
                patch.object(sys, "argv", [str(ROOT / "TOOLS/install_live_skills.py"), str(self.canon), "--check"]), \
                contextlib.redirect_stdout(output):
            live.main()
        self.assertIn("+1 new, 0 updated, 0 unchanged  [CHECK ONLY]", output.getvalue())
        self.assertEqual(list(self.dest.iterdir()), [])
        self.assertEqual(list(self.root.glob("skills.bak-*")), [])

    def test_bytecode_is_not_drift(self):
        (self.dest / "example").mkdir()
        (self.dest / "example/SKILL.md").write_bytes(b"canonical\n")
        (self.canon / "example/__pycache__").mkdir()
        (self.canon / "example/__pycache__/x.cpython-314.pyc").write_bytes(b"\x00")
        (self.canon / "example/stray.pyc").write_bytes(b"\x00")
        self.assertEqual(live.install(str(self.canon), str(self.dest), "Hermes", True, []), (0, 0, 1, 1, 0))

    def _state(self, *parts, doc):
        path = self.root.joinpath("Ultimate-AI-Starter-Bundle", *parts)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(doc), encoding="utf-8")

    def test_native_plugin_skills_are_not_expected_as_copies(self):
        self._state("install-state.json", doc={"native_plugins": {"Hermes": {"plugins": {
            "someplugin": {"native": True, "owned": ["example"]}}}}})
        notes = []
        self.assertEqual(live.install(str(self.canon), str(self.dest), "Hermes", True, notes), (0, 0, 0, 0, 1))
        self.assertTrue(any("native plugin" in n for n in notes), notes)

    def test_a_failed_native_install_still_expects_the_copy(self):
        self._state("install-state.json", doc={"native_plugins": {"Hermes": {"plugins": {
            "someplugin": {"native": False, "owned": ["example"]}}}}})
        self.assertEqual(live.install(str(self.canon), str(self.dest), "Hermes", True, []), (1, 0, 0, 1, 0))

    def test_parked_ponytail_is_not_drift(self):
        (self.canon / "ponytail-help").mkdir()
        (self.canon / "ponytail-help/SKILL.md").write_bytes(b"x\n")
        self._state("ponytail-mode", "state.json", doc={"mode": "off"})
        self.assertEqual(live.install(str(self.canon), str(self.dest), "Hermes", True, []), (1, 0, 0, 1, 1))

    def test_real_cli_rejects_default_and_apply_without_inspecting_homes(self):
        for flags in ([], ["--apply"], ["--check", "--apply"]):
            with self.subTest(flags=flags):
                result = subprocess.run(
                    [sys.executable, "-B", str(ROOT / "TOOLS/install_live_skills.py"),
                     str(self.root / "absent canonical"), *flags],
                    capture_output=True, text=True, timeout=15,
                )
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertNotIn("Traceback", result.stderr)


if __name__ == "__main__":
    unittest.main(verbosity=2)
