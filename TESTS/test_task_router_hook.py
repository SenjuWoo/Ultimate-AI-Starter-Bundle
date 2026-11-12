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

    def test_host_traffic_is_not_a_request(self):
        """A finished background task or a local command echo is not a person asking."""
        loud = "audit the whole release pipeline for security problems across all phases and publish"
        self.assertNotEqual(run_hook(loud)[0], "", "the control prompt must speak or this test proves nothing")
        for wrapper in ("[SYSTEM NOTIFICATION - NOT USER INPUT] %s",
                        "<task-notification><summary>%s</summary></task-notification>",
                        "  <local-command-stdout>%s</local-command-stdout>",
                        "<ci-monitor-event>%s</ci-monitor-event>"):
            out, code = run_hook(wrapper % loud)
            self.assertEqual((out, code), ("", 0), wrapper)
        # A person quoting such a tag mid-sentence is still a person.
        self.assertNotEqual(run_hook(loud + " (the log said <task-notification>)")[0], "")

    def test_a_security_change_names_one_workflow(self):
        out, _ = run_hook("add oauth login with tests before merge")
        payload = json.loads(out)
        text = payload["hookSpecificOutput"]["additionalContext"]
        self.assertIn("lifecycle", text)
        self.assertIn("Advisory only", text)
        self.assertNotIn("checkpoints", text)
        self.assertLessEqual(len(text), 240)

    def test_hermes_shape_is_a_context_field(self):
        out, _ = run_hook("add oauth login with tests before merge", fmt="hermes")
        self.assertIn("context", json.loads(out))

    def test_creative_request_with_software_words_stays_quiet(self):
        out, code = run_hook("Write a story about a security guard with a secret password")
        self.assertEqual((out, code), ("", 0))

    def test_wiring_preserves_foreign_sibling_and_invalid_settings(self):
        sys.path.insert(0, str(ROOT / "TOOLS" / "hooks"))
        import ponytail_auto as pa
        with tempfile.TemporaryDirectory() as tmp:
            settings = Path(tmp) / "settings.json"
            settings.write_text(json.dumps({"hooks": {"UserPromptSubmit": [{
                "matcher": "keep", "hooks": [
                    {"type": "command", "command": '"python" "%s" hook --format claude' % HOOK},
                    {"type": "command", "command": "foreign-check"}]}]}}), encoding="utf-8")
            pa.wire_claude_script(HOOK, settings=settings)
            groups = json.loads(settings.read_text())["hooks"]["UserPromptSubmit"]
            self.assertEqual(groups[0]["matcher"], "keep")
            self.assertEqual(groups[0]["hooks"][0]["command"], "foreign-check")
            before = settings.stat().st_mtime_ns
            pa.wire_claude_script(HOOK, settings=settings)
            self.assertEqual(settings.stat().st_mtime_ns, before)
            self.assertEqual(len(list(Path(tmp).glob("*.bak-*"))), 1)
            settings.write_text('{"broken":', encoding="utf-8")
            with self.assertRaises(ValueError):
                pa.wire_claude_script(HOOK, settings=settings)
            self.assertEqual(settings.read_text(), '{"broken":')

    def test_same_basename_personal_hook_is_not_owned(self):
        sys.path.insert(0, str(ROOT / "TOOLS" / "hooks"))
        import ponytail_auto as pa
        with tempfile.TemporaryDirectory() as tmp:
            settings = Path(tmp) / "settings.json"
            command = '"python" "%s" hook --format claude' % (Path(tmp) / HOOK.name)
            settings.write_text(json.dumps({"hooks": {"UserPromptSubmit": [{"hooks": [
                {"type": "command", "command": command}]}]}}), encoding="utf-8")
            pa.wire_claude_script(HOOK, settings=settings)
            self.assertIn(command, [h["command"] for g in json.loads(settings.read_text())["hooks"]["UserPromptSubmit"] for h in g["hooks"]])

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

    def test_hermes_wiring_preserves_foreign_hooks_and_approves(self):
        try:
            import ruamel.yaml  # noqa: F401
        except ImportError:
            self.skipTest("ruamel.yaml not available")
        sys.path.insert(0, str(ROOT / "TOOLS" / "hooks"))
        import ponytail_auto as pa
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "config.yaml"
            cfg.write_text("model:" + chr(10) + "  default: keep" + chr(10) + "hooks:" + chr(10)
                           + "  pre_llm_call:" + chr(10) + "    - command: other-tool" + chr(10),
                           encoding="utf-8")
            for _ in range(2):
                actions = pa.wire_hermes_script(HOOK, enable=True, config=cfg)
                self.assertTrue(actions)
            text = cfg.read_text(encoding="utf-8")
            self.assertIn("keep", text)
            self.assertIn("other-tool", text, "an unrelated hook must survive")
            self.assertEqual(text.count("task_router_hook.py"), 1, "wiring must be idempotent")
            approvals = json.loads((Path(tmp) / "shell-hooks-allowlist.json").read_text(encoding="utf-8"))
            self.assertTrue(any("task_router_hook.py" in a.get("command", "")
                                for a in approvals["approvals"]),
                            "the hook must be approved or Hermes will refuse to run it")
            import time
            approval = next(a for a in approvals["approvals"] if "task_router_hook.py" in a["command"])
            self.assertEqual(approval["script_mtime_at_approval"], time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(HOOK.stat().st_mtime)))
            allowlist = Path(tmp) / "shell-hooks-allowlist.json"
            before = (cfg.stat().st_mtime_ns, allowlist.stat().st_mtime_ns)
            pa.wire_hermes_script(HOOK, config=cfg)
            self.assertEqual(before, (cfg.stat().st_mtime_ns, allowlist.stat().st_mtime_ns))

    def test_self_check_passes(self):
        out = subprocess.run([sys.executable, str(HOOK), "self-check"],
                             capture_output=True, text=True, timeout=60)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)
        self.assertIn("PASS", out.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
