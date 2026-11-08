"""Ponytail Auto must decide outside the model, and the decision must reach it.

Every case here is deterministic: no model call, no network. The point of the
suite is that a creative or ambiguous request stays OFF, a narrow fix becomes
LITE, only an explicit request can produce ULTRA, and the text emitted for a
mode is the text that mode promises.
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS" / "hooks"))

import ponytail_auto as pa  # noqa: E402


class DecisionTests(unittest.TestCase):
    def setUp(self):
        self._state = pa.STATE
        self._dir = tempfile.TemporaryDirectory()
        pa.STATE = Path(self._dir.name) / "ponytail-auto.json"
        pa.STATE_DIR = Path(self._dir.name)
        # The selected mode is the single authority now, so these classification
        # cases run under AUTO and restore the real setting afterwards.
        self._mode_state = pa.MODE_STATE
        pa.MODE_STATE = Path(self._dir.name) / "ponytail-mode" / "state.json"
        pa.MODE_STATE.parent.mkdir(parents=True, exist_ok=True)
        pa.MODE_STATE.write_text('{"mode": "auto"}', encoding="utf-8")
        self.cwd = Path(self._dir.name)

    def tearDown(self):
        pa.STATE = self._state
        if hasattr(self, "_mode_state"):
            pa.MODE_STATE = self._mode_state
        self._dir.cleanup()

    def decide(self, prompt, **kwargs):
        return pa.resolve(prompt, cwd=self.cwd, global_config={}, **kwargs)

    def test_creative_and_ambiguous_requests_stay_off(self):
        for prompt in (
            "write me a short story about a lighthouse keeper",
            "design a landing page for the app",
            "brainstorm names for this tool",
            "what do you think about Rust vs Go?",
            "how would you structure a game engine?",
            "fix it",
            "make it better",
            "",
        ):
            self.assertEqual(self.decide(prompt)["mode"], "off", prompt)

    def test_narrow_fix_is_lite(self):
        for prompt in (
            "fix the typo in README.md line 12",
            "the build fails with Traceback (most recent call last) in tools/build.py",
            "rename Foo to Bar in src/lib.rs",
            "bug: crash when the cache path has brackets (#4821)",
        ):
            self.assertEqual(self.decide(prompt)["mode"], "lite", prompt)

    def test_simplification_and_defined_maintenance_are_full(self):
        for prompt in (
            "simplify this module",
            "remove the duplication between the two loaders",
            "bump version to 3.4.0 and update the changelog",
            "regenerate the manifest after the docs change",
        ):
            self.assertEqual(self.decide(prompt)["mode"], "full", prompt)

    def test_ultra_only_by_explicit_request(self):
        self.assertEqual(self.decide("/ponytail ultra")["mode"], "ultra")
        self.assertEqual(self.decide("ponytail ultra, please")["mode"], "ultra")
        # A simplification request is not an ULTRA request.
        self.assertEqual(self.decide("simplify everything aggressively")["mode"], "full")

    def test_explicit_off_wins_and_clears_the_session(self):
        self.assertEqual(pa.resolve("fix the typo in a.md", session_id="s1", cwd=self.cwd,
                                    global_config={})["mode"], "lite")
        self.assertEqual(pa.resolve("stop ponytail", session_id="s1", cwd=self.cwd,
                                    global_config={})["mode"], "off")
        self.assertEqual(pa.resolve("now fix the typo in b.md", session_id="s1", cwd=self.cwd,
                                    global_config={})["mode"], "off")

    def test_a_choice_sticks_for_the_session(self):
        self.assertEqual(pa.resolve("/ponytail full", session_id="s2", cwd=self.cwd,
                                    global_config={})["mode"], "full")
        self.assertEqual(pa.resolve("and the tests?", session_id="s2", cwd=self.cwd,
                                    global_config={})["source"], "session")

    def test_project_file_overrides_classification(self):
        (self.cwd / ".ponytail.json").write_text(json.dumps({"mode": "lite"}), encoding="utf-8")
        self.assertEqual(self.decide("simplify this module")["mode"], "lite")
        (self.cwd / ".ponytail.json").write_text(json.dumps({"auto": False}), encoding="utf-8")
        self.assertEqual(self.decide("fix the typo in README.md")["mode"], "off")

    def test_a_ceiling_caps_automatic_modes(self):
        decision = pa.resolve("simplify this module", cwd=self.cwd, global_config={"max": "lite"})
        self.assertEqual(decision["mode"], "lite")
        # An explicit request is the operator's, not the classifier's, and is not capped.
        self.assertEqual(pa.resolve("/ponytail ultra", cwd=self.cwd,
                                    global_config={"max": "lite"})["mode"], "ultra")


class EmissionTests(unittest.TestCase):
    def setUp(self):
        self._state = pa.STATE
        self._dir = tempfile.TemporaryDirectory()
        pa.STATE = Path(self._dir.name) / "ponytail-auto.json"
        pa.STATE_DIR = Path(self._dir.name)
        # The selected mode is the single authority now, so these classification
        # cases run under AUTO and restore the real setting afterwards.
        self._mode_state = pa.MODE_STATE
        pa.MODE_STATE = Path(self._dir.name) / "ponytail-mode" / "state.json"
        pa.MODE_STATE.parent.mkdir(parents=True, exist_ok=True)
        pa.MODE_STATE.write_text('{"mode": "auto"}', encoding="utf-8")

    def tearDown(self):
        pa.STATE = self._state
        if hasattr(self, "_mode_state"):
            pa.MODE_STATE = self._mode_state
        self._dir.cleanup()

    def test_the_text_sent_matches_the_selected_mode(self):
        lite = json.loads(pa.emit(json.dumps({"prompt": "fix the typo in README.md line 12"})))
        self.assertTrue(lite["context"].startswith("PONYTAIL MODE: LITE"))
        self.assertIn("name the smaller alternative", lite["context"])

        full = json.loads(pa.emit(json.dumps({"prompt": "simplify this module"})))
        self.assertTrue(full["context"].startswith("PONYTAIL MODE: FULL"))
        self.assertIn("Never cut validation", full["context"])
        self.assertNotIn("question the request", full["context"])

    def test_an_off_decision_sends_nothing(self):
        self.assertEqual(pa.emit(json.dumps({"prompt": "write a poem about rain"})), "")

    def test_the_claude_shape_wraps_the_same_text(self):
        payload = json.loads(pa.emit(json.dumps({"prompt": "simplify this module"}), fmt="claude"))
        context = payload["hookSpecificOutput"]["additionalContext"]
        self.assertEqual(context, pa.instruction("full"))

    def test_a_broken_payload_cannot_block_a_turn(self):
        self.assertEqual(pa.emit("not json"), "")
        self.assertEqual(pa.emit(""), "")


class WireTests(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        base = Path(self._dir.name)
        self.cfg = base / "config.yaml"
        self.cfg.write_text("model: keep-me\nhooks:\n  pre_tool_call:\n    - command: owner-hook\n", encoding="utf-8")
        self._env = os.environ.get("PONYTAIL_HERMES_CONFIG")
        os.environ["PONYTAIL_HERMES_CONFIG"] = str(self.cfg)
        self._state = pa.STATE
        pa.STATE = base / "ponytail-auto.json"

    def tearDown(self):
        if self._env is None:
            os.environ.pop("PONYTAIL_HERMES_CONFIG", None)
        else:
            os.environ["PONYTAIL_HERMES_CONFIG"] = self._env
        pa.STATE = self._state
        if hasattr(self, "_mode_state"):
            pa.MODE_STATE = self._mode_state
        self._dir.cleanup()

    def test_wiring_is_idempotent_and_preserves_the_owner_config(self):
        pa.wire_hermes(enable=True)
        first = self.cfg.read_text(encoding="utf-8")
        self.assertIn("ponytail_auto.py", first)
        self.assertIn("owner-hook", first)
        self.assertIn("model: keep-me", first)
        pa.wire_hermes(enable=True)
        self.assertEqual(first, self.cfg.read_text(encoding="utf-8"))
        allow = json.loads((Path(self._dir.name) / "shell-hooks-allowlist.json").read_text(encoding="utf-8"))
        self.assertTrue(any(a["event"] == "pre_llm_call" for a in allow["approvals"]))

    def test_removal_leaves_the_other_hooks_untouched(self):
        pa.wire_hermes(enable=True)
        pa.wire_hermes(enable=False)
        text = self.cfg.read_text(encoding="utf-8")
        self.assertNotIn("ponytail_auto.py", text)
        self.assertIn("owner-hook", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
