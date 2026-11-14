"""Integration: the mode controller and the auto hook must agree on one state.

Unit tests passed while these two shipped as separate worlds - the hook classified
prompts without ever reading the selected mode. These cases drive the pair the way a
provider does: write a mode, ask the hook what it would inject.
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))
sys.path.insert(0, str(ROOT / "TOOLS" / "hooks"))

import ponytail_mode as pm  # noqa: E402
import ponytail_auto as hook  # noqa: E402


class ModeAndHookAgreeTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.home = base / "home"
        for name in (".claude", ".grok"):
            (self.home / name / "skills" / "ponytail").mkdir(parents=True)
        self._saved = (pm.STATE, pm.PARKED, os.environ.get("APPDATA"),
                       hook.STATE, hook.STATE_DIR, hook.MODE_STATE)
        pm.STATE = base / "state" / "ponytail-mode"
        pm.PARKED = pm.STATE / "parked"
        os.environ["APPDATA"] = str(base / "appdata")
        hook.STATE_DIR = base / "state"
        hook.STATE = base / "state" / "ponytail-auto.json"
        hook.MODE_STATE = base / "state" / "ponytail-mode" / "state.json"
        self.base = base

    def tearDown(self):
        pm.STATE, pm.PARKED, appdata, hook.STATE, hook.STATE_DIR, hook.MODE_STATE = self._saved
        if appdata is None:
            os.environ.pop("APPDATA", None)
        else:
            os.environ["APPDATA"] = appdata
        self._tmp.cleanup()

    def _choose(self, mode):
        pm.STATE.mkdir(parents=True, exist_ok=True)
        (pm.STATE / "state.json").write_text(json.dumps({"mode": mode}), encoding="utf-8")

    def _inject(self, prompt):
        return hook.instruction(hook.resolve(prompt, session_id="s1")["mode"])

    def test_off_with_the_hook_wired_injects_nothing(self):
        self._choose("off")
        self.assertEqual(self._inject("fix the crash in app.py line 12"), "")
        self.assertEqual(self._inject("simplify this module"), "")
        self.assertFalse(hook.status()["would_inject"])

    def test_manual_full_is_not_doubled_by_auto(self):
        self._choose("full")
        result = hook.resolve("fix the typo in main.py")
        self.assertEqual(result["mode"], "off", "the plugin injects full; the hook must stand down")
        self.assertEqual(result["source"], "mode")

    def test_auto_is_the_only_mode_that_classifies(self):
        self._choose("auto")
        creative = hook.resolve("design a magic system for my game", session_id="c1")
        self.assertEqual(creative["mode"], "off")
        self.assertEqual(self._inject("design a magic system for my game"), "")
        narrow = hook.resolve("fix the crash in app.py line 12", session_id="c2")
        self.assertEqual(narrow["mode"], "lite")
        self.assertTrue(hook.instruction(narrow["mode"]))

    def test_auto_recognises_a_stack_trace_and_a_build_code(self):
        # Both were false negatives in the first corpus: an exception name and a
        # toolchain code are concrete evidence even without a path.
        self._choose("auto")
        self.assertEqual(hook.classify("TypeError: 'NoneType' object is not subscriptable in loader.py:88")[0], "lite")
        self.assertEqual(hook.classify("the build fails with MSB3073, here is the log")[0], "lite")
        # and they must not drag creative work into a mode
        self.assertEqual(hook.classify("design a magic system for my game")[0], "off")

    def test_auto_never_reaches_ultra(self):
        self._choose("auto")
        for prompt in ("delete everything you can and simplify hard",
                       "make this as small as possible, remove code"):
            self.assertNotEqual(hook.resolve(prompt, session_id="u1")["mode"], "ultra")

    def test_automatic_minimalism_does_not_take_over_architecture(self):
        self._choose("auto")
        for prompt in ("simplify the whole system architecture", "major rework of the installer",
                       "refactor the architecture in app.py", "build a new product from scratch"):
            self.assertEqual(hook.resolve(prompt, session_id="architecture")["mode"], "off", prompt)

    def test_auto_respects_an_explicit_session_override(self):
        self._choose("auto")
        hook.resolve("/ponytail ultra", session_id="s2")
        self.assertEqual(hook.resolve("fix app.py line 3", session_id="s2")["mode"], "ultra")

    def test_missing_state_injects_nothing(self):
        self.assertEqual(hook.selected_mode(), "off")
        self.assertEqual(self._inject("fix the crash in app.py line 12"), "")
        self.assertFalse(hook.status()["would_inject"])

    def test_corrupt_state_injects_nothing(self):
        hook.MODE_STATE.parent.mkdir(parents=True, exist_ok=True)
        hook.MODE_STATE.write_text("{ nonsense", encoding="utf-8")
        self.assertEqual(hook.selected_mode(), "off")
        self.assertEqual(self._inject("fix the crash in app.py line 12"), "")

    def test_reinstall_keeps_the_choice_and_a_fresh_machine_defaults_off(self):
        pm.execute(pm.plan("off", home=self.home))
        pm.STATE.mkdir(parents=True, exist_ok=True)
        (pm.STATE / "state.json").write_text(json.dumps({"mode": "off"}), encoding="utf-8")
        pm.main(["init", "--apply"], home=self.home)   # installer re-runs, sandboxed
        self.assertEqual(json.loads((pm.STATE / "state.json").read_text())["mode"], "off")
        self.assertEqual(hook.selected_mode(), "off")

    def test_status_reports_the_selection_not_just_the_hook(self):
        self._choose("auto")
        report = hook.status()
        self.assertEqual(report["selected_mode"], "auto")
        self.assertTrue(report["would_inject"])
        self._choose("off")
        report = hook.status()
        self.assertEqual(report["selected_mode"], "off")
        self.assertFalse(report["would_inject"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
