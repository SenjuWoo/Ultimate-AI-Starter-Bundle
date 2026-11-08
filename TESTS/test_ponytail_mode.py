"""Ponytail must be off unless asked, and a deliberate choice must survive reruns.

Every case builds a disposable home so nothing here can touch the operator's real
provider folders.
"""

import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))

import ponytail_mode as pm  # noqa: E402


def _home(tmp):
    home = Path(tmp)
    for name in (".claude", ".grok", ".kimi-code", ".agents"):
        skills = home / name / "skills"
        (skills / "ponytail").mkdir(parents=True)
        (skills / "ponytail" / "SKILL.md").write_text("---\nname: ponytail\n---\n", encoding="utf-8")
        (skills / "ponytail-audit").mkdir(parents=True)
    settings = home / ".claude" / "settings.json"
    settings.write_text(json.dumps({"enabledPlugins": {"ponytail@ponytail": True}}), encoding="utf-8")
    return home


def _quiet(_cmd):
    class R:
        returncode = 0
        stdout = ""
    return R()


class PonytailModeTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.home = _home(self._tmp.name)
        self._state, self._parked = pm.STATE, pm.PARKED
        pm.STATE = self.home / "state" / "ponytail-mode.json"
        pm.PARKED = self.home / "state" / "parked"

    def tearDown(self):
        pm.STATE, pm.PARKED = self._state, self._parked
        self._tmp.cleanup()

    def test_off_parks_skills_and_disables_the_claude_flag(self):
        pm.apply("off", home=self.home, run=_quiet)
        self.assertFalse(pm.installed_skill_dirs(self.home / ".grok"))
        self.assertFalse(pm.claude_enabled(self.home / ".claude"))
        self.assertEqual(pm.read_state()["mode"], "off")

    def test_on_restores_from_the_bundle_tree(self):
        pm.apply("off", home=self.home, run=_quiet)
        tree = ROOT / "1-TAILORED-PROVIDER-TREES" / "Claude" / "COPY-TO-SKILLS-DIRECTORY" / "skills"
        pm.apply("full", home=self.home, source_tree=tree, run=_quiet)
        self.assertTrue(pm.claude_enabled(self.home / ".claude"))
        self.assertTrue(pm.installed_skill_dirs(self.home / ".grok"))
        self.assertEqual(pm.read_state()["mode"], "full")

    def test_a_deliberate_choice_survives_init(self):
        pm.apply("ultra", home=self.home, run=_quiet)
        pm.apply("init", home=self.home, run=_quiet) if False else None
        # init is a CLI path; emulate its rule: it only writes when no choice exists.
        before = pm.read_state()["mode"]
        self.assertEqual(before, "ultra")
        argv = ["init", "--apply"]
        pm.STATE.parent.mkdir(parents=True, exist_ok=True)
        pm.STATE.write_text(json.dumps({"mode": "ultra"}), encoding="utf-8")
        pm.main(argv)
        self.assertEqual(pm.read_state()["mode"], "ultra", "init overwrote an explicit choice")

    def test_auto_parks_nothing_and_leaves_the_choice_to_the_hook(self):
        # AUTO is implemented in TOOLS/hooks/ponytail_auto.py; here it must only mean
        # "do not park the skills", so the hook has instructions to inject.
        pm.apply("auto", home=self.home, run=_quiet)
        self.assertTrue(pm.installed_skill_dirs(self.home / ".grok"))
        report = pm.status(home=self.home)
        self.assertIn("hook decides", report["effective"])

    def test_unknown_mode_is_refused(self):
        with self.assertRaises(SystemExit):
            pm.apply("turbo", home=self.home, run=_quiet)


if __name__ == "__main__":
    unittest.main(verbosity=2)
