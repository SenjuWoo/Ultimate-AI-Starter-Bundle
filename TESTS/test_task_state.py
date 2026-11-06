"""Regression tests for TOOLS/task_state.py. Fixtures only; never touches live state."""

import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "TOOLS" / "task_state.py"
spec = importlib.util.spec_from_file_location("task_state", TOOL)
task_state = importlib.util.module_from_spec(spec)
spec.loader.exec_module(task_state)

PLAN_HEAD = """# Plan

Goal: ship the thing.

| ID | Task | Status | Depends on | Verify | Evidence |
|---|---|---|---|---|---|
"""


def write(root, plan_rows, state=None, files=()):
    root = Path(root)
    (root / "PLAN.md").write_text(PLAN_HEAD + plan_rows, encoding="utf-8")
    if state is not None:
        (root / "STATE.md").write_text(state, encoding="utf-8")
    for name in files:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x", encoding="utf-8")
    return root


STATE_OK = "GOAL: ship\nCURRENT TASK: T2\nNEXT ACTION: run the tests\nSHA: \n"


def run(cmd, root, *extra):
    out = subprocess.run([sys.executable, str(TOOL), cmd, "--root", str(root)] + list(extra),
                         capture_output=True, text=True, timeout=60)
    return out.returncode, out.stdout + out.stderr


class TaskStateTests(unittest.TestCase):
    def test_fresh_project_picks_the_first_ready_task(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | read | complete | - | - | - |\n| T2 | build | pending | T1 | - | - |\n")
            code, out = run("next", root)
            self.assertEqual(code, 0, out)
            self.assertIn("T2", out)

    def test_dependency_order_is_respected(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | pending | T2 | - | - |\n| T2 | b | pending | - | - | - |\n")
            code, out = run("next", root)
            self.assertEqual(code, 0, out)
            self.assertIn("T2", out.splitlines()[0])

    def test_cycle_is_reported(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | pending | T2 | - | - |\n| T2 | b | pending | T1 | - | - |\n")
            code, out = run("status", root)
            self.assertEqual(code, 1, out)
            self.assertIn("cycle", out)

    def test_false_complete_without_evidence_is_flagged(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | build | complete | - | out/app.exe | - |\n")
            code, out = run("status", root)
            self.assertEqual(code, 1, out)
            self.assertIn("complete without evidence: T1", out)

    def test_complete_with_existing_evidence_passes(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | build | complete | - | out/app.exe | - |\n", files=["out/app.exe"])
            code, out = run("status", root)
            self.assertEqual(code, 0, out)

    def test_duplicate_ids_and_unknown_dependency(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | pending | T9 | - | - |\n| T1 | b | pending | - | - | - |\n")
            code, out = run("status", root)
            self.assertEqual(code, 1, out)
            self.assertIn("duplicate task ID T1", out)
            self.assertIn("unknown task T9", out)

    def test_contradictory_state_is_reported_and_fixable(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | - | - |\n| T2 | b | pending | T1 | - | - |\n",
                         state="GOAL: ship\nCURRENT TASK: T7\nNEXT ACTION: x\nSHA: \n")
            code, out = run("resume", root)
            self.assertEqual(code, 1, out)
            self.assertIn("not in PLAN.md", out)
            code, out = run("resume", root, "--fix")
            self.assertIn("STATE.md updated", out)
            self.assertIn("CURRENT TASK: T2", (root / "STATE.md").read_text(encoding="utf-8"))

    def test_missing_plan_exits_two(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("status", Path(d))
            self.assertEqual(code, 2, out)

    def test_handoff_is_compact(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | - | - |\n| T2 | build the thing | pending | T1 | pytest -q | - |\n",
                         state=STATE_OK)
            code, out = run("handoff", root)
            self.assertEqual(code, 0, out)
            self.assertIn("Next task: T2", out)
            self.assertLessEqual(len(out.splitlines()), 10)

    def test_rerun_is_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | - | - |\n| T2 | b | pending | T1 | - | - |\n",
                         state=STATE_OK)
            first = run("resume", root, "--fix")
            second = run("resume", root, "--fix")
            self.assertEqual(first[1].count("STATE.md updated"), second[1].count("STATE.md updated"), first[1])


if __name__ == "__main__":
    unittest.main(verbosity=2)
