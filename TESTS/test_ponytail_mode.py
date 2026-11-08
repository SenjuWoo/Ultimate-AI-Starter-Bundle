"""Ponytail must be off unless asked, and every change must be reversible.

All cases run against a disposable home and a disposable APPDATA, so nothing here
can touch the operator's real provider folders. The properties under test are the
ones that were wrong in the first draft: a dry run must write nothing, parking must
never delete a copy it did not create, and a round trip must give back the exact
original bytes instead of a fresh bundle copy.
"""

import hashlib
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))

import ponytail_mode as pm  # noqa: E402


def _digest(root):
    h = hashlib.sha256()
    for path in sorted(Path(root).rglob("*")):
        h.update(str(path.relative_to(root)).encode())
        if path.is_file():
            h.update(path.read_bytes())
    return h.hexdigest()


def _home(tmp):
    home = Path(tmp) / "home"
    for name in (".claude", ".grok", ".kimi-code", ".agents"):
        skills = home / name / "skills"
        (skills / "ponytail").mkdir(parents=True)
        (skills / "ponytail" / "SKILL.md").write_text("---\nname: ponytail\n---\nbody\n", encoding="utf-8")
        (skills / "ponytail-audit").mkdir(parents=True)
    (home / ".claude" / "settings.json").write_text(
        json.dumps({"enabledPlugins": {"ponytail@ponytail": True}, "theme": "dark"}), encoding="utf-8")
    return home


class PonytailModeTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.home = _home(base)
        self._saved = (pm.STATE, pm.PARKED, os.environ.get("APPDATA"))
        pm.STATE = base / "state" / "ponytail-mode"
        pm.PARKED = pm.STATE / "parked"
        os.environ["APPDATA"] = str(base / "appdata")

    def tearDown(self):
        pm.STATE, pm.PARKED, appdata = self._saved
        if appdata is None:
            os.environ.pop("APPDATA", None)
        else:
            os.environ["APPDATA"] = appdata
        self._tmp.cleanup()

    def _native(self):
        return json.loads((Path(os.environ["APPDATA"]) / "ponytail" / "config.json").read_text())

    def test_dry_run_writes_nothing(self):
        before = _digest(self.home)
        actions = pm.plan("off", home=self.home)
        self.assertTrue(actions)
        self.assertEqual(_digest(self.home), before)
        self.assertFalse(pm.STATE.exists())

    def test_apply_off_sets_native_config_and_parks_skills(self):
        pm.execute(pm.plan("off", home=self.home))
        self.assertEqual(self._native()["defaultMode"], "off")
        self.assertFalse(pm.installed_skill_dirs(self.home / ".grok"))

    def test_parking_never_overwrites_an_existing_archive(self):
        first = pm.plan("off", home=self.home)
        pm.execute(first)
        archive = Path(next(a["dest"] for a in first if a["kind"] == "park"))
        (archive / "note.txt").write_text("kept", encoding="utf-8")
        again = pm.execute(pm.plan("off", home=self.home))
        self.assertTrue(all(r["ok"] for r in again), "a second pass over a parked set is a no-op")
        self.assertEqual((archive / "note.txt").read_text(encoding="utf-8"), "kept")

    def test_round_trip_restores_the_original_bytes(self):
        original = (self.home / ".grok" / "skills" / "ponytail" / "SKILL.md").read_text(encoding="utf-8")
        pm.execute(pm.plan("off", home=self.home))
        tree = ROOT / "1-TAILORED-PROVIDER-TREES" / "Claude" / "COPY-TO-SKILLS-DIRECTORY" / "skills"
        pm.execute(pm.plan("full", home=self.home, source_tree=tree))
        restored = (self.home / ".grok" / "skills" / "ponytail" / "SKILL.md").read_text(encoding="utf-8")
        self.assertEqual(restored, original, "the parked copy wins over a fresh bundle copy")
        self.assertEqual(self._native()["defaultMode"], "full")

    def test_other_config_keys_survive_the_write(self):
        cfg = Path(os.environ["APPDATA"]) / "ponytail"
        cfg.mkdir(parents=True)
        (cfg / "config.json").write_text(json.dumps({"defaultMode": "lite", "statusline": True}), encoding="utf-8")
        pm.execute(pm.plan("off", home=self.home))
        data = self._native()
        self.assertEqual(data["defaultMode"], "off")
        self.assertTrue(data["statusline"])

    def test_malformed_config_is_reported_and_left_alone(self):
        cfg = Path(os.environ["APPDATA"]) / "ponytail"
        cfg.mkdir(parents=True)
        (cfg / "config.json").write_text("{not json", encoding="utf-8")
        results = pm.execute(pm.plan("off", home=self.home))
        self.assertTrue(any(r["kind"] == "config_malformed" and not r["ok"] for r in results))
        self.assertEqual((cfg / "config.json").read_text(encoding="utf-8"), "{not json")

    def test_auto_parks_skills_so_only_the_hook_can_inject(self):
        # AUTO is implemented in TOOLS/hooks/ponytail_auto.py. It must be the only
        # path that can inject, otherwise a skill description could fire on a
        # creative prompt and defeat the classifier's OFF decision.
        pm.execute(pm.plan("auto", home=self.home))
        pm.STATE.mkdir(parents=True, exist_ok=True)
        (pm.STATE / "state.json").write_text(json.dumps({"mode": "auto"}), encoding="utf-8")
        self.assertFalse(pm.installed_skill_dirs(self.home / ".grok"))
        self.assertEqual(self._native()["defaultMode"], "off")
        report = pm.status(home=self.home)
        self.assertIn("auto", report["effective"])
        self.assertEqual(report["leaks"], [])
        self.assertEqual(report["mismatches"], [])

    def test_status_fails_when_the_native_value_disagrees(self):
        pm.STATE.mkdir(parents=True, exist_ok=True)
        (pm.STATE / "state.json").write_text(json.dumps({"mode": "off"}), encoding="utf-8")
        cfg = Path(os.environ["APPDATA"]) / "ponytail"
        cfg.mkdir(parents=True)
        (cfg / "config.json").write_text('{"defaultMode": "full"}', encoding="utf-8")
        self.assertEqual(pm.main(["status"]), 1, "requested off but native full must fail")

    def test_environment_override_is_reported_and_fails(self):
        pm.STATE.mkdir(parents=True, exist_ok=True)
        (pm.STATE / "state.json").write_text(json.dumps({"mode": "off"}), encoding="utf-8")
        cfg = Path(os.environ["APPDATA"]) / "ponytail"
        cfg.mkdir(parents=True)
        (cfg / "config.json").write_text('{"defaultMode": "off"}', encoding="utf-8")
        os.environ["PONYTAIL_DEFAULT_MODE"] = "ultra"
        try:
            report = pm.status(home=self.home)
        finally:
            os.environ.pop("PONYTAIL_DEFAULT_MODE", None)
        self.assertEqual(report["native"], "ultra")
        self.assertTrue(any("PONYTAIL_DEFAULT_MODE" in m for m in report["mismatches"]))
        self.assertFalse(report["runtime_verified"])

    def test_init_keeps_an_explicit_choice(self):
        pm.STATE.mkdir(parents=True, exist_ok=True)
        (pm.STATE / "state.json").write_text(json.dumps({"mode": "ultra"}), encoding="utf-8")
        self.assertEqual(pm.main(["init", "--apply"]), 0)
        self.assertEqual(json.loads((pm.STATE / "state.json").read_text())["mode"], "ultra")
        self.assertFalse((Path(os.environ["APPDATA"]) / "ponytail" / "config.json").exists())

    def test_off_with_loaded_skills_reports_a_leak(self):
        cfg = Path(os.environ["APPDATA"]) / "ponytail"
        cfg.mkdir(parents=True)
        (cfg / "config.json").write_text('{"defaultMode": "off"}', encoding="utf-8")
        report = pm.status(home=self.home)
        self.assertTrue(report["leaks"], "skills loaded while native mode is off must be a leak")

    def test_unknown_mode_is_refused(self):
        with self.assertRaises(SystemExit):
            pm.plan("turbo", home=self.home)


if __name__ == "__main__":
    unittest.main(verbosity=2)
