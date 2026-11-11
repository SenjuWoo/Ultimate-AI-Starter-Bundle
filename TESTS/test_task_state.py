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
    for args in (["init", "-q"], ["add", "-A"], ["-c", "user.email=t@t", "-c", "user.name=t",
                                               "commit", "-qm", "init"]):
        subprocess.run(["git", "-C", str(root)] + args, check=True, capture_output=True)
    return subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                          capture_output=True, text=True).stdout.strip()


STATE = "GOAL: ship\nCURRENT TASK: T2\nNEXT ACTION: run the tests\nSHA: \n"


class ValidationTests(unittest.TestCase):
    def test_empty_verification_targets_are_not_evidence(self):
        for verify in ("file:", "file:   ", "cmd:"):
            with self.subTest(verify=verify), tempfile.TemporaryDirectory() as d:
                code, out = run("status", write(d, "| T1 | ship | complete | - | " + verify + " | - |\n"))
                self.assertEqual(code, 1, out)
                self.assertIn("no verification recorded", out)

    def test_fresh_project_picks_the_first_ready_task(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | read | complete | - | file:a.txt | - |\n| T2 | build | pending | T1 | - | - |\n"
            code, out = run("next", write(d, row))
            self.assertEqual(code, 0, out)
            self.assertIn("T2", out)

    def test_dependency_order_is_respected(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | a | pending | T2 | - | - |\n| T2 | b | pending | - | - | - |\n"
            code, out = run("next", write(d, row))
            self.assertEqual(code, 0, out)
            self.assertIn("T2", out.splitlines()[0])

    def test_active_task_wins_over_an_earlier_pending_one(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | a | pending | - | - | - |\n| T2 | b | active | - | - | - |\n"
            code, out = run("next", write(d, row))
            self.assertEqual(code, 0, out)
            self.assertIn("T2", out.splitlines()[0])

    def test_cycle_fails_status(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | a | pending | T2 | - | - |\n| T2 | b | pending | T1 | - | - |\n"
            code, out = run("status", write(d, row))
            self.assertEqual(code, 1, out)
            self.assertIn("cycle", out)

    def test_cycle_fails_handoff(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("handoff", write(d, "| T1 | a | pending | T2 | - | - |\n| T2 | b | pending | T1 | - | - |\n",
                                             state=STATE))
            self.assertEqual(code, 1, out)
            self.assertIn("dependency cycle", out)

    def test_invalid_dependency_still_names_the_ready_task_but_fails(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | ready | pending | - | - | - |\n| T2 | broken | pending | T9 | - | - |\n"
            code, out = run("next", write(d, row))
            self.assertEqual(code, 1, out)
            self.assertIn("T1", out.splitlines()[0])
            self.assertIn("unknown task T9", out)

    def test_invalid_plan_fails_resume(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("resume", write(d, "| T1 | a | pending | T9 | - | - |\n", state=STATE))
            self.assertEqual(code, 1, out)
            self.assertIn("unknown task T9", out)

    def test_duplicate_ids_and_unknown_status(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | a | pending | - | - | - |\n| T1 | b | done | - | - | - |\n"
            code, out = run("status", write(d, row))
            self.assertEqual(code, 1, out)
            self.assertIn("duplicate task ID T1", out)
            self.assertIn("unknown status 'done'", out)

    def test_superseded_dependency_is_not_satisfied(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | old | superseded | - | - | - |\n| T2 | new | pending | T1 | - | - |\n"
            code, out = run("status", write(d, row))
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
            code, out = run("status", write(d, "| T1 | build | complete | - | out/app.exe | - |\n",
                                            files=["out/app.exe"]))
            self.assertEqual(code, 0, out)

    def test_command_evidence_is_never_run_and_needs_a_record(self):
        with tempfile.TemporaryDirectory() as d:
            marker = Path(d) / "ran"
            plan = "| T1 | build | complete | - | cmd:touch %s | - |\n" % marker
            code, out = run("status", write(d, plan))
            self.assertEqual(code, 1, out)
            self.assertIn("no verification recorded", out)
            self.assertFalse(marker.exists(), "the controller executed a plan command")

    def test_a_matching_record_verifies_the_command(self):
        with tempfile.TemporaryDirectory() as d:
            row = ("| T1 | build | complete | - | cmd:python -m pytest |"
                   " cmd:python -m pytest @ abc1234 exit=0 |\n")
            code, out = run("status", write(d, row))
            self.assertEqual(code, 0, out)

    def test_prose_cannot_claim_a_pass(self):
        for cell in ("not verified; failed", "passed the review", "ok", "verified@"):
            with self.subTest(cell=cell), tempfile.TemporaryDirectory() as d:
                row = "| T1 | build | complete | - | cmd:python -m pytest | %s |\n" % cell
                code, out = run("status", write(d, row))
                self.assertEqual(code, 1, out)
                self.assertIn("unverified", out)

    def test_failure_wording_rejects_a_file_that_exists(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | build | complete | - | file:a.txt | not verified; failed |\n"
            code, out = run("status", write(d, row))
            self.assertEqual(code, 1, out)
            self.assertIn("records a failure", out)

    def test_stale_or_mismatched_records_are_rejected(self):
        cells = ["cmd:other-tool @ abc1234 exit=0", "cmd:cmake --build . @ deadbeef exit=0",
                 "cmd:cmake --build . @ abc1234 exit=1", "ran it, it worked"]
        for cell in cells:
            with self.subTest(cell=cell), tempfile.TemporaryDirectory() as d:
                root = write(d, "| T1 | a | complete | - | file:a.txt | - |\n")
                head = git_repo(root)
                plan = "| T1 | build | complete | - | cmd:cmake --build . | %s |\n" % cell
                code, out = run("status", write(d, plan))
                self.assertEqual(code, 1, (cell, out))
                self.assertIn("unverified", out)

    def test_record_for_the_current_head_passes(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | complete | - | file:a.txt | - |\n")
            head = git_repo(root)
            plan = ("| T1 | build | complete | - | cmd:cmake --build . |"
                    " cmd:cmake --build . @ %s exit=0 |\n" % head[:7])
            code, out = run("status", write(d, plan))
            self.assertEqual(code, 0, out)

    def test_bare_verify_with_spaces_is_ambiguous_not_a_path(self):
        with tempfile.TemporaryDirectory() as d:
            code, out = run("status", write(d, "| T1 | b | complete | - | python -m pytest | - |\n"))
            self.assertEqual(code, 1, out)
            self.assertIn("ambiguous", out)

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
            row = "| T1 | a | complete | - | file:a.txt | - |\n| T2 | b | pending | T1 | - | - |\n"
            root = write(d, row, state="GOAL: ship\nCURRENT TASK: T7\nNEXT ACTION: x\nSHA: \n")
            code, out = run("resume", root)
            self.assertEqual(code, 1, out)
            self.assertIn("not in PLAN.md", out)
            run("resume", root, "--fix")
            self.assertIn("CURRENT TASK: T2", (root / "STATE.md").read_text(encoding="utf-8"))

    def test_fix_is_truly_idempotent(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | a | complete | - | file:a.txt | - |\n| T2 | b | pending | T1 | - | - |\n"
            root = write(d, row, state="GOAL: ship\nCURRENT TASK: T2\nNEXT ACTION: run the tests\nSHA: \n")
            code1, out1 = run("resume", root, "--fix")
            after_first = (root / "STATE.md").read_bytes()
            stamp = (root / "STATE.md").stat().st_mtime_ns
            time.sleep(0.02)
            code2, out2 = run("resume", root, "--fix")
            self.assertEqual(code1, 0, out1)
            self.assertEqual(code2, 0, out2)
            self.assertEqual(after_first, (root / "STATE.md").read_bytes(), "second repair rewrote the file")
            self.assertEqual(stamp, (root / "STATE.md").stat().st_mtime_ns, "second repair touched mtime")
            self.assertIn("nothing written", out2)

    def test_resume_preserves_literal_windows_verification_paths(self):
        for verify in (r"file:C:\Users\operator\artifact.txt",
                       r"cmd:python .\tests\new_case.py"):
            with self.subTest(verify=verify), tempfile.TemporaryDirectory() as d:
                root = write(d, "| T1 | verify | pending | - | " + verify + " | - |\n",
                             state="GOAL: ship\nCURRENT TASK: T1\nNEXT ACTION: old\nSHA: \n")
                code, out = run("resume", root, "--fix")
                self.assertEqual(code, 0, out)
                self.assertIn("NEXT ACTION: " + verify,
                              (root / "STATE.md").read_text(encoding="utf-8").splitlines())
                before = (root / "STATE.md").read_bytes()
                stamp = (root / "STATE.md").stat().st_mtime_ns
                code, out = run("resume", root, "--fix")
                self.assertEqual(code, 0, out)
                self.assertEqual((root / "STATE.md").read_bytes(), before)
                self.assertEqual((root / "STATE.md").stat().st_mtime_ns, stamp)

    def test_invalid_plan_blocks_repair_writes(self):
        with tempfile.TemporaryDirectory() as d:
            root = write(d, "| T1 | a | pending | T9 | - | - |\n", state="GOAL: ship\nCURRENT TASK: T1\n")
            before = (root / "STATE.md").read_bytes()
            code, out = run("resume", root, "--fix")
            self.assertEqual(code, 1, out)
            self.assertIn("left untouched", out)
            self.assertEqual(before, (root / "STATE.md").read_bytes())

    def test_missing_fields_are_added_once(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | a | complete | - | file:a.txt | - |\n| T2 | b | pending | T1 | - | - |\n"
            root = write(d, row, state="GOAL: ship\n")
            code, out = run("resume", root, "--fix")
            text = (root / "STATE.md").read_text(encoding="utf-8")
            self.assertIn("CURRENT TASK: T2", text)
            self.assertIn("NEXT ACTION:", text)
            self.assertIn("was missing", out)
            code2, out2 = run("resume", root, "--fix")
            self.assertIn("nothing written", out2)

    def test_resume_repairs_a_half_written_state_file(self):
        # An interrupted write leaves a file that stops mid-field; repair must not crash.
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | a | complete | - | file:a.txt | - |" + chr(10) + "| T2 | b | pending | T1 | - | - |" + chr(10)
            state = "GOAL: ship" + chr(10) + "CURRENT TASK: T9" + chr(10) + "NEXT AC"
            root = write(d, row, state=state)
            code, out = run("resume", root, "--fix")
            self.assertEqual(code, 1, out)          # the contradiction it just repaired is reported
            self.assertIn("STATE.md updated", out)
            code2, out2 = run("resume", root, "--fix")
            self.assertEqual(code2, 0, out2)        # nothing left to report
            text = (root / "STATE.md").read_text(encoding="utf-8")
            self.assertIn("CURRENT TASK: T2", text)
            self.assertIn("NEXT ACTION:", text)
            self.assertFalse(text.rstrip().endswith("NEXT AC"), text)

    def test_repair_keeps_fields_it_does_not_own(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | a | complete | - | file:a.txt | - |" + chr(10) + "| T2 | b | pending | T1 | - | - |" + chr(10)
            state = ("GOAL: ship" + chr(10) + "CURRENT TASK: T9" + chr(10)
                     + "NOTES: keep me" + chr(10) + "SHA: " + chr(10))
            root = write(d, row, state=state)
            run("resume", root, "--fix")
            text = (root / "STATE.md").read_text(encoding="utf-8")
            self.assertIn("NOTES: keep me", text)
            self.assertIn("CURRENT TASK: T2", text)

    def test_two_agents_resuming_converge(self):
        with tempfile.TemporaryDirectory() as d:
            row = "| T1 | a | complete | - | file:a.txt | - |\n| T2 | b | pending | T1 | - | - |\n"
            root = write(d, row, state="GOAL: ship\nCURRENT TASK: T9\nNEXT ACTION: ?\nSHA: \n")
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
            row = "| T1 | a | complete | - | file:a.txt | - |\n| T2 | build it | pending | T1 | cmd:pytest -q | - |\n"
            code, out = run("handoff", write(d, row, state=STATE))
            self.assertEqual(code, 0, out)
            self.assertIn("Next task: T2", out)
            self.assertLessEqual(len(out.splitlines()), 10)


if __name__ == "__main__":
    unittest.main(verbosity=2)
