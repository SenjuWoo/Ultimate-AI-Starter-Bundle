"""The skill-trigger reader must actually read.

A previous splice left the event handlers inside `except: continue`, so every
valid event was discarded and every skill scored 0% -- with green CI. These
tests feed a fake `claude` process through the real function and assert the
three outcomes that matter: triggered, not triggered, and failed (which must
never be reported as "not triggered").
"""

import importlib.util
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SKILL_ROOT = ROOT / "_CANONICAL-SKILLS" / "skill-creator"


def load_module():
    spec = importlib.util.spec_from_file_location(
        "run_eval_under_test", SKILL_ROOT / "scripts" / "run_eval.py"
    )
    module = importlib.util.module_from_spec(spec)
    sys.path.insert(0, str(SKILL_ROOT))
    spec.loader.exec_module(module)
    return module


class FakeStream:
    def __init__(self, lines):
        self._buf = io.BytesIO("".join(lines).encode("utf-8"))

    def readline(self):
        return self._buf.readline()


class FakeProc:
    """Stands in for `claude -p`, emitting whatever the test built."""

    def __init__(self, builder, returncode, root):
        self.returncode = returncode
        self.project_root = root
        self.killed = False
        self.stdout = FakeStream(builder(self._clean_name()))
        self.stderr = None

    def _clean_name(self):
        # The function names its command file after the skill: read it back.
        cmd_dir = Path(self.project_root) / ".claude" / "commands"
        files = sorted(cmd_dir.glob("*.md"))
        return files[-1].stem if files else ""

    def poll(self):
        return None if self.returncode is None else self.returncode

    def kill(self):
        self.killed = True

    def wait(self):
        return 0


def make_popen(builder, returncode=0):
    root = make_popen.project_root

    def popen(*args, **kwargs):
        return FakeProc(builder, returncode, root)

    return popen


def skill_event(clean_name):
    """The partial-stream shape: start, delta with the name, stop."""
    return [
        json.dumps({
            "type": "stream_event",
            "event": {"type": "content_block_start",
                      "content_block": {"type": "tool_use", "name": "Skill"}},
        }) + "\n",
        json.dumps({
            "type": "stream_event",
            "event": {"type": "content_block_delta",
                      "delta": {"type": "input_json_delta",
                                "partial_json": '{"skill": "%s"}' % clean_name}},
        }) + "\n",
        json.dumps({"type": "stream_event",
                    "event": {"type": "content_block_stop"}}) + "\n",
    ]


def assistant_event(clean_name):
    """The complete-message shape."""
    return [json.dumps({
        "type": "assistant",
        "message": {"content": [{"type": "tool_use", "name": "Skill",
                                 "input": {"skill": clean_name}}]},
    }) + "\n"]


def unrelated_event(_):
    return [json.dumps({
        "type": "assistant",
        "message": {"content": [{"type": "tool_use", "name": "Bash",
                                 "input": {"command": "ls"}}]},
    }) + "\n"]


class TriggerReader(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / ".claude" / "commands").mkdir(parents=True)
        (self.root / ".claude").mkdir(exist_ok=True)
        self.module = load_module()
        make_popen.project_root = self.root
        self._real = self.module.subprocess.Popen

    def tearDown(self):
        self.module.subprocess.Popen = self._real
        self.tmp.cleanup()

    def run_with(self, builder, returncode=0):
        self.module.subprocess.Popen = make_popen(builder, returncode)
        return self.module.run_single_query(
            "check the thing", "demo", "Use when checking a thing.",
            timeout=10, project_root=str(self.root),
        )

    def test_partial_stream_tool_use_triggers(self):
        self.assertTrue(self.run_with(skill_event))

    def test_complete_assistant_message_triggers(self):
        self.assertTrue(self.run_with(assistant_event))

    def test_unrelated_tool_does_not_trigger(self):
        self.assertFalse(self.run_with(unrelated_event))

    def test_malformed_line_is_skipped_not_fatal(self):
        def builder(name):
            return ["{not json\n", json.dumps({"type": "ping"}) + "\n"] + assistant_event(name)

        self.assertTrue(self.run_with(builder))

    def test_failed_process_is_an_error_not_a_negative(self):
        with self.assertRaises(RuntimeError) as caught:
            self.run_with(lambda _: [], returncode=3)
        self.assertIn("exited 3", str(caught.exception))

    def test_queued_output_survives_a_fast_exit(self):
        # A one-shot process that dies immediately must still be read.
        self.assertTrue(self.run_with(assistant_event, returncode=0))


if __name__ == "__main__":
    unittest.main(verbosity=2)
