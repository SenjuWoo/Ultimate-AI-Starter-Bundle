"""Regression tests for TOOLS/task_state.py. Fixtures only; never touches live state."""

import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

TOOL = Path(__file__).resolve().parents[1] / "TOOLS" / "task_state.py"

HEAD = """# Plan

Goal: ship the thing.

| ID | Task | Status | Depends on | Verify | Evidence |
|---|---|---|---|---|---|
"""


def write(root, rows, state=None, files=()):
    root = Path(root)
    (root / "PLAN.md").write_text(HEAD + rows, encoding="utf-8")
    (root / "a.txt").write_text("a", encoding="utf-8")  # convenience evidence file
    if state is not None:
        (root / "STATE.md").write_text(state, encoding="utf-8")
    for name in files:
        path = root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("x", encoding="utf-8")
    return root


def run(cmd, root, *extra):
    out = subprocess.run([sys.executable, str(TOOL), cmd, "--root", str(root)] + list(extra),
                         capture_output=True, text=True, timeout=60)
    return out.returncode, out.stdout + out.stderr


def git_repo(root):
    root = Path(root)
    (root / "a.txt").write_text("a", encoding="utf-8")
    for args in (["init", "-q"], ["add", "-A"], ["-c", "user.email=t@t", "-c", "user.name=t",
                                               "commit", "-qm", "init"]):
        subprocess.run(["git", "-C", str(root)] + args, check=True, capture_output=True)
    return subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()


STATE = "GOAL: ship\nCURRENT TASK: T2\nNEXT ACTION: run the tests\nSHA: \n"


class ValidationTests(unittest.TestCase):
    def test_fresh_project_picks_the_first_ready_task(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("next", write(d, "| T1 | read | complete | - | file:a.txt | - |\n| T2 | build | pending | T1 | - | - |\n"))
            self.assertEqual(code, 0, out)
            self.assertIn("T2", out)

    def test_dependency_order_is_respected(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("next", write(d, "| T1 | a | pending | T2 | - | - |\n| T2 | b | pending | - | - | - |\n"))
            self.assertEqual(code, 0, out)
            self.assertIn("T2", out.splitlines()[0])

    def test_active_task_wins_over_an_earlier_pending_one(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | pending | - | - | - |\n| T2 | b | active | - | - | - |\n")
            code, out = run("next", root)
            self.assertEqual(code, 0, out)
            self.assertIn("T2", out.splitlines()[0])

    def test_cycle_fails_status(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("status", write(d, "| T1 | a | pending | T2 | - | - |\n| T2 | b | pending | T1 | - | - |\n"))
            self.assertEqual(code, 1, out)
            self.assertIn("cycle", out)

    def test_cycle_fails_handoff(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | pending | T2 | - | - |\n| T2 | b | pending | T1 | - | - |\n", state=STATE)
            code, out = run("handoff", root)
            self.assertEqual(code, 1, out)
            self.assertIn("dependency cycle", out)

    def test_invalid_dependency_still_names_the_ready_task_but_fails(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | ready | pending | - | - | - |\n| T2 | broken | pending | T9 | - | - |\n")
            code, out = run("next", root)
            self.assertEqual(code, 1, out)
            self.assertIn("T1", out.splitlines()[0])
            self.assertIn("unknown task T9", out)

    def test_invalid_plan_fails_resume(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | pending | T9 | - | - |\n", state=STATE)
            code, out = run("resume", root)
            self.assertEqual(code, 1, out)
            self.assertIn("unknown task T9", out)

    def test_duplicate_ids_and_unknown_status(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | pending | - | - | - |\n| T1 | b | done | - | - | - |\n")
            code, out = run("status", root)
            self.assertEqual(code, 1, out)
            self.assertIn("duplicate task ID T1", out)
            self.assertIn("unknown status 'done'", out)

    def test_superseded_dependency_is_not_satisfied(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | old | superseded | - | - | - |\n| T2 | new | pending | T1 | - | - |\n")
            code, out = run("status", root)
            self.assertEqual(code, 1, out)
            self.assertIn("T2 depends on superseded T1", out)
            self.assertIn("blocked: T2", out)


class EvidenceTests(unittest.TestCase):
    def test_complete_with_missing_evidence_file_fails(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("status", write(d, "| T1 | build | complete | - | out/app.exe | - |\n"))
            self.assertEqual(code, 1, out)
            self.assertIn("complete but unverified", out)

    def test_complete_with_existing_evidence_file_passes(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | build | complete | - | out/app.exe | - |\n", files=["out/app.exe"])
            code, out = run("status", root)
            self.assertEqual(code, 0, out)

    def test_command_evidence_is_never_run_and_needs_a_recorded_pass(self):
        with tempfile.TemporaryDirectory() as d:
            marker = Path(d) / "ran"
            plan = "| T1 | build | complete | - | cmd:touch %s | - |\n" % marker
            root = write(d, plan)
            code, out = run("status", root)
            self.assertEqual(code, 1, out)
            self.assertIn("command never run", out)
            self.assertFalse(marker.exists(), "the controller executed a plan command")
            verified = "| T1 | build | complete | - | cmd:touch %s | verified@abc123 |\n" % marker
            code, out = run("status", write(d, verified))
            self.assertEqual(code, 0, out)

    def test_complete_without_any_verification_fails(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("status", write(d, "| T1 | done | complete | - | - | - |\n"))
            self.assertEqual(code, 1, out)
            self.assertIn("no verification recorded", out)


class StateTests(unittest.TestCase):
    def test_stale_sha_alone_fails_status(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | file:a.txt | - |\n",
                         state="GOAL: s\nCURRENT TASK: T1\nNEXT ACTION: -\nSHA: deadbeef\n")
            git_repo(root)
            code, out = run("status", root)
            self.assertEqual(code, 1, out)
            self.assertIn("is behind", out)

    def test_contradictory_state_is_reported_and_fixed(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | file:a.txt | - |\n| T2 | b | pending | T1 | - | - |\n",
                         state="GOAL: ship\nCURRENT TASK: T7\nNEXT ACTION: x\nSHA: \n")
            code, out = run("resume", root)
            self.assertEqual(code, 1, out)
            self.assertIn("not in PLAN.md", out)
            run("resume", root, "--fix")
            self.assertIn("CURRENT TASK: T2", (root / "STATE.md").read_text(encoding="utf-8"))

    def test_fix_is_truly_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | file:a.txt | - |\n| T2 | b | pending | T1 | - | - |\n",
                         state="GOAL: ship\nCURRENT TASK: T2\nNEXT ACTION: run the tests\nSHA: \n")
            code1, out1 = run("resume", root, "--fix")
            after_first = (root / "STATE.md").read_bytes()
            stamp = (root / "STATE.md").stat().st_mtime_ns
            time.sleep(0.02)
            code2, out2 = run("resume", root, "--fix")
            after_second = (root / "STATE.md").read_bytes()
            self.assertEqual(code1, 0, out1)
            self.assertEqual(code2, 0, out2)
            self.assertEqual(after_first, after_second, "second repair rewrote the file")
            self.assertEqual(stamp, (root / "STATE.md").stat().st_mtime_ns, "second repair touched mtime")
            self.assertIn("nothing written", out2)

    def test_missing_fields_are_added_once(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | file:a.txt | - |\n| T2 | b | pending | T1 | - | - |\n",
                         state="GOAL: ship\n")
            code, out = run("resume", root, "--fix")
            text = (root / "STATE.md").read_text(encoding="utf-8")
            self.assertIn("CURRENT TASK: T2", text)
            self.assertIn("NEXT ACTION:", text)
            self.assertIn("was missing", out)
            code2, out2 = run("resume", root, "--fix")
            self.assertIn("nothing written", out2)

    def test_two_agents_resuming_converge(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | file:a.txt | - |\n| T2 | b | pending | T1 | - | - |\n",
                         state="GOAL: ship\nCURRENT TASK: T9\nNEXT ACTION: ?\nSHA: \n")
            run("resume", root, "--fix")
            first = (root / "STATE.md").read_bytes()
            run("resume", root, "--fix")
            self.assertEqual(first, (root / "STATE.md").read_bytes())

    def test_missing_plan_exits_two(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("status", Path(d))
            self.assertEqual(code, 2, out)

    def test_handoff_is_compact(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | file:a.txt | - |\n| T2 | build it | pending | T1 | pytest -q | - |\n",
                         state=STATE)
            code, out = run("handoff", root)
            self.assertEqual(code, 0, out)
            self.assertIn("Next task: T2", out)
            self.assertLessEqual(len(out.splitlines()), 10)


if __name__ == "__main__":
    unittest.main(verbosity=2)
