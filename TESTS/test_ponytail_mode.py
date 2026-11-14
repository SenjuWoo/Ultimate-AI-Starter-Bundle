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
        self._saved = (pm.STATE, pm.PARKED, os.environ.get("APPDATA"),
                       os.environ.get("XDG_CONFIG_HOME"), os.environ.get("CLAUDE_CONFIG_DIR"))
        pm.STATE = base / "state" / "ponytail-mode"
        pm.PARKED = pm.STATE / "parked"
        os.environ["APPDATA"] = str(base / "appdata")
        os.environ.pop("XDG_CONFIG_HOME", None)
        os.environ.pop("CLAUDE_CONFIG_DIR", None)

    def tearDown(self):
        pm.STATE, pm.PARKED, appdata, xdg, claude_dir = self._saved
        for key, value in (("APPDATA", appdata), ("XDG_CONFIG_HOME", xdg),
                           ("CLAUDE_CONFIG_DIR", claude_dir)):
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
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
        self.assertEqual(pm.main(["status"], home=self.home), 1, "requested off but native full must fail")

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

    def test_init_keeps_an_explicit_choice_and_re_asserts_it(self):
        pm.STATE.mkdir(parents=True, exist_ok=True)
        (pm.STATE / "state.json").write_text(json.dumps({"mode": "ultra"}), encoding="utf-8")
        self.assertEqual(pm.main(["init", "--apply"], home=self.home), 0)
        self.assertEqual(json.loads((pm.STATE / "state.json").read_text())["mode"], "ultra")
        # An installer re-copies skills, so init must also re-assert the native value
        # instead of only recording the choice.
        self.assertEqual(self._native()["defaultMode"], "ultra")

    def test_off_with_loaded_skills_reports_a_leak(self):
        cfg = Path(os.environ["APPDATA"]) / "ponytail"
        cfg.mkdir(parents=True)
        (cfg / "config.json").write_text('{"defaultMode": "off"}', encoding="utf-8")
        report = pm.status(home=self.home)
        self.assertTrue(report["leaks"], "skills loaded while native mode is off must be a leak")

    def test_off_reports_plugin_skills_separately_from_leaks(self):
        # The plugin registers its bundles skills even at off. That is not injection,
        # but claiming "no leaks" without saying so would overstate the guarantee.
        report = pm.status(home=self.home)
        self.assertIn("plugin_skills", report)
        self.assertIsInstance(report["plugin_skills"], list)

    def test_duplicates_are_never_restored_into_a_provider(self):
        # OFF -> OFF again (a reinstall re-copies skills, creating _duplicates) ->
        # LITE -> OFF. The quarantine folder must never land in a live skills dir.
        pm.execute(pm.plan("off", home=self.home))
        archive = Path(pm.PARKED) / "Grok"
        (archive / "_duplicates" / "ponytail__deadbeef").mkdir(parents=True)
        (archive / "_duplicates" / "ponytail__deadbeef" / "SKILL.md").write_text("x", encoding="utf-8")
        (self.home / ".grok" / "skills" / "ponytail").mkdir(parents=True)
        (self.home / ".grok" / "skills" / "ponytail" / "SKILL.md").write_text("re-copied", encoding="utf-8")
        pm.execute(pm.plan("off", home=self.home))           # reinstall pass
        pm.execute(pm.plan("lite", home=self.home, source_tree=None))
        self.assertFalse((self.home / ".grok" / "skills" / "_duplicates").exists())
        self.assertTrue((self.home / ".grok" / "skills" / "ponytail" / "SKILL.md").is_file())
        self.assertTrue((archive / "_duplicates").is_dir(), "quarantined content must survive")
        pm.execute(pm.plan("off", home=self.home))
        self.assertFalse((self.home / ".grok" / "skills" / "ponytail").exists())

    def test_xdg_config_home_wins_over_appdata(self):
        xdg = Path(self._tmp.name) / "xdg"
        (xdg / "ponytail").mkdir(parents=True)
        (xdg / "ponytail" / "config.json").write_text('{"defaultMode": "lite"}', encoding="utf-8")
        appdata = Path(os.environ["APPDATA"]) / "ponytail"
        appdata.mkdir(parents=True)
        (appdata / "config.json").write_text('{"defaultMode": "full"}', encoding="utf-8")
        os.environ["XDG_CONFIG_HOME"] = str(xdg)
        self.assertEqual(pm.native_config(), xdg / "ponytail" / "config.json")
        report = pm.status(home=self.home)
        self.assertEqual(report["native"], "lite", "XDG outranks APPDATA upstream")
        pm.execute(pm.plan("off", home=self.home))
        self.assertEqual(json.loads((xdg / "ponytail" / "config.json").read_text())["defaultMode"], "off")
        self.assertEqual(json.loads((appdata / "config.json").read_text())["defaultMode"], "full",
                         "the non-authoritative file is left alone")

    def test_claude_config_dir_is_honoured(self):
        custom = Path(self._tmp.name) / "claude-custom"
        (custom / "skills" / "ponytail").mkdir(parents=True)
        (custom / "skills" / "ponytail" / "SKILL.md").write_text("x", encoding="utf-8")
        os.environ["CLAUDE_CONFIG_DIR"] = str(custom)
        self.assertEqual(pm.provider_homes(self.home)["Claude"], custom)
        report = pm.status(home=self.home)
        self.assertIn("ponytail", report["providers"]["Claude"]["skills"])
        pm.execute(pm.plan("off", home=self.home))
        self.assertFalse((custom / "skills" / "ponytail").exists())
        self.assertTrue((self.home / ".claude" / "skills" / "ponytail").exists(),
                        "CLAUDE_CONFIG_DIR replaces ~/.claude; the other folder is out of scope")

    def _claude_settings(self):
        return json.loads((self.home / ".claude" / "settings.json").read_text(encoding="utf-8"))

    def test_off_disables_the_claude_plugin_and_keeps_other_keys(self):
        # skillOverrides cannot hide plugin skills, so an enabled plugin keeps its
        # descriptions in every Claude session; off must switch it off.
        pm.execute(pm.plan("off", home=self.home))
        data = self._claude_settings()
        self.assertIs(data["enabledPlugins"]["ponytail@ponytail"], False)
        self.assertEqual(data["theme"], "dark")
        backups = list((self.home / ".claude").glob("settings.json.bak-ponytail-*"))
        self.assertEqual(len(backups), 1, "the original settings are backed up first")

    def test_manual_level_re_enables_the_claude_plugin(self):
        pm.execute(pm.plan("off", home=self.home))
        pm.execute(pm.plan("lite", home=self.home, source_tree=None))
        self.assertIs(self._claude_settings()["enabledPlugins"]["ponytail@ponytail"], True)

    def test_manual_level_restores_no_copy_beside_an_enabled_plugin(self):
        pm.execute(pm.plan("off", home=self.home))
        tree = ROOT / "1-TAILORED-PROVIDER-TREES" / "Claude" / "COPY-TO-SKILLS-DIRECTORY" / "skills"
        pm.execute(pm.plan("full", home=self.home, source_tree=tree))
        self.assertFalse(pm.installed_skill_dirs(self.home / ".claude"),
                         "the plugin delivers the skills; a copy would list each twice")
        self.assertTrue(pm.installed_skill_dirs(self.home / ".grok"), "a provider without a plugin switch gets its copies back")

    def test_enabled_plugin_at_off_is_a_leak(self):
        cfg = Path(os.environ["APPDATA"]) / "ponytail"
        cfg.mkdir(parents=True)
        (cfg / "config.json").write_text('{"defaultMode": "off"}', encoding="utf-8")
        for name in (".claude", ".grok", ".kimi-code", ".agents"):
            for skill in pm.installed_skill_dirs(self.home / name):
                for f in sorted(skill.rglob("*"), reverse=True):
                    f.unlink() if f.is_file() else f.rmdir()
                skill.rmdir()
        report = pm.status(home=self.home)
        self.assertTrue(any("plugin" in leak for leak in report["leaks"]))

    def test_no_plugin_entry_means_no_settings_write(self):
        (self.home / ".claude" / "settings.json").write_text('{"theme": "dark"}', encoding="utf-8")
        actions = pm.plan("off", home=self.home)
        self.assertFalse([a for a in actions if a["kind"] == "plugin_enable"])

    def test_off_disables_the_antigravity_plugin_and_parks_its_copies(self):
        ag = self.home / ".gemini" / "config"
        (ag / "skills" / "ponytail").mkdir(parents=True)
        (ag / "skills" / "ponytail" / "SKILL.md").write_text("x", encoding="utf-8")
        (ag / "config.json").write_text(json.dumps(
            {"plugins": {"ponytail": {"enabled": True}, "superpowers": {"enabled": True}}}), encoding="utf-8")
        pm.execute(pm.plan("off", home=self.home))
        data = json.loads((ag / "config.json").read_text(encoding="utf-8"))
        self.assertIs(data["plugins"]["ponytail"]["enabled"], False)
        self.assertIs(data["plugins"]["superpowers"]["enabled"], True)
        self.assertFalse(pm.installed_skill_dirs(ag))

    def test_explicit_home_never_reaches_the_real_provider_folders(self):
        homes = pm.provider_homes(self.home)
        for name, path in homes.items():
            self.assertTrue(str(path).startswith(str(self.home)), "%s escaped the sandbox: %s" % (name, path))

    def test_hermes_deleted_folder_is_not_a_profile(self):
        hermes = self.home / "AppData" / "Local" / "hermes" / "profiles"
        (hermes / ".deleted" / "skills").mkdir(parents=True)
        (hermes / "code" / "skills").mkdir(parents=True)
        homes = pm.provider_homes(self.home)
        self.assertIn("Hermes/code", homes)
        self.assertNotIn("Hermes/.deleted", homes)

    def test_unknown_mode_is_refused(self):
        with self.assertRaises(SystemExit):
            pm.plan("turbo", home=self.home)


if __name__ == "__main__":
    unittest.main(verbosity=2)
