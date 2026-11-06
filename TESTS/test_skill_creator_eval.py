"""Skill-creator evaluation must fail honestly when its provider is absent.

The scripts launched `claude -p` unconditionally and read the pipe with
select(), which Windows rejects (OSError 10038). Both are checked here without
needing Claude installed.
"""

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "_CANONICAL-SKILLS" / "skill-creator" / "scripts"


class EvalProviderHonesty(unittest.TestCase):
    def run_script(self, name, *args, path_env=""):
        import os
        env = dict(os.environ)
        env["PATH"] = path_env  # no claude, no npx: provider really absent
        # These scripts import `scripts.utils`, so they run from the skill root.
        # `python -m scripts.<name>` from the skill root: the modules import
        # `scripts.utils`, which only resolves with that root on sys.path.
        module = "scripts." + name[:-3]
        return subprocess.run([sys.executable, "-m", module, *args],
                              capture_output=True, text=True, timeout=180, env=env,
                              cwd=str(SCRIPTS.parent))

    def test_run_eval_reports_the_missing_provider_and_exits_2(self):
        with tempfile.TemporaryDirectory() as tmp:
            skill = Path(tmp) / "demo"
            skill.mkdir()
            (skill / "SKILL.md").write_text(
                "---\nname: demo\ndescription: Use when checking a thing.\n---\n\n# Demo\n",
                encoding="utf-8")
            evals = Path(tmp) / "evals.json"
            evals.write_text('{"queries": [{"query": "check a thing", "should_trigger": true}]}',
                             encoding="utf-8")
            done = self.run_script("run_eval.py", "--eval-set", str(evals),
                                   "--skill-path", str(skill))
            self.assertEqual(2, done.returncode, done.stderr)
            self.assertIn("evaluation unavailable", done.stderr.lower())
            self.assertIn("quick_validate.py", done.stderr, "no offline path offered")

    def test_improve_description_reports_the_missing_provider(self):
        with tempfile.TemporaryDirectory() as tmp:
            skill = Path(tmp) / "demo"
            skill.mkdir()
            (skill / "SKILL.md").write_text(
                "---\nname: demo\ndescription: Use when checking a thing.\n---\n\n# Demo\n",
                encoding="utf-8")
            results = Path(tmp) / "results.json"
            results.write_text('{"description": "x", "results": []}', encoding="utf-8")
            done = self.run_script("improve_description.py", "--eval-results", str(results),
                                   "--skill-path", str(skill), "--model", "x")
            self.assertEqual(2, done.returncode, done.stderr)
            self.assertIn("unavailable", done.stderr.lower())

    def test_no_select_on_the_subprocess_pipe(self):
        # Windows select() only accepts sockets; the reader thread replaced it.
        source = (SCRIPTS / "run_eval.py").read_text(encoding="utf-8")
        self.assertNotIn("select.select", source)
        self.assertIn("threading.Thread", source)

    def test_offline_validator_runs_without_a_model(self):
        with tempfile.TemporaryDirectory() as tmp:
            skill = Path(tmp) / "demo"
            skill.mkdir()
            (skill / "SKILL.md").write_text(
                "---\nname: demo\ndescription: Use when checking a thing.\n---\n\n# Demo\n",
                encoding="utf-8")
            done = self.run_script("quick_validate.py", str(skill))
            self.assertEqual(0, done.returncode, done.stdout + done.stderr)
            (skill / "SKILL.md").write_text("no frontmatter here\n", encoding="utf-8")
            bad = self.run_script("quick_validate.py", str(skill))
            self.assertNotEqual(0, bad.returncode, "a skill without frontmatter passed validation")


if __name__ == "__main__":
    unittest.main(verbosity=2)
