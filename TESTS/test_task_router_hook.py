"""The prompt-time hook must speak only when routing changes something, and use real I/O.

These tests run the hook the way a provider does: JSON on stdin, JSON (or nothing) on
stdout. They also prove wiring preserves unrelated settings and is idempotent.
"""

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / "TOOLS" / "hooks" / "task_router_hook.py"


def run_hook(prompt, fmt="claude", env=None):
    payload = json.dumps({"prompt": prompt, "session_id": "t"})
    out = subprocess.run([sys.executable, str(HOOK), "hook", "--format", fmt],
                         input=payload, capture_output=True, text=True, timeout=60,
                         env=env or os.environ.copy())
    return out.stdout.strip(), out.returncode


class HookTests(unittest.TestCase):
    def test_a_trivial_change_stays_silent(self):
        out, code = run_hook("fix the typo in notes.txt")
        self.assertEqual(code, 0)
        self.assertEqual(out, "")

    def test_a_security_change_names_one_workflow(self):
        out, _ = run_hook("add oauth login with tests before merge")
        payload = json.loads(out)
        text = payload["hookSpecificOutput"]["additionalContext"]
        self.assertIn("lifecycle", text)
        self.assertIn("One workflow", text)
        self.assertLessEqual(len(text), 240)

    def test_hermes_shape_is_a_context_field(self):
        out, _ = run_hook("add oauth login with tests before merge", fmt="hermes")
        self.assertIn("context", json.loads(out))

    def test_ai_token_cost_does_not_trigger_security(self):
        out, _ = run_hook("reduce AI token usage in the prompts")
        self.assertEqual(out, "")

    def test_mixed_request_is_security(self):
        out, _ = run_hook("Add OAuth login and reduce LLM token usage.")
        self.assertIn("lifecycle", json.loads(out)["hookSpecificOutput"]["additionalContext"])

    def test_wiring_preserves_foreign_hooks_and_is_idempotent(self):
        with tempfile.TemporaryDirectory() as tmp:
            settings = Path(tmp) / "settings.json"
            settings.write_text(json.dumps({
                "model": "keep-me",
                "hooks": {"UserPromptSubmit": [{"hooks": [{"type": "command", "command": "other"}]}]},
            }), encoding="utf-8")
            env = os.environ.copy()
            env["CLAUDE_CONFIG_DIR"] = tmp
            for _ in range(2):
                out = subprocess.run([sys.executable, str(HOOK), "wire", "claude"],
                                     capture_output=True, text=True, env=env, timeout=60)
                self.assertEqual(out.returncode, 0, out.stderr)
            data = json.loads(settings.read_text(encoding="utf-8"))
            self.assertEqual(data["model"], "keep-me")
            text = json.dumps(data["hooks"]["UserPromptSubmit"])
            self.assertIn("other", text, "an unrelated hook must survive")
            self.assertEqual(text.count("task_router_hook.py"), 1, "wire must not duplicate itself")

    def test_self_check_passes(self):
        out = subprocess.run([sys.executable, str(HOOK), "self-check"],
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("PASS", out.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
