"""Prove documentation/index failures and conservative real Git branch cleanup.

Standard library only; creates isolated repositories, never edits this checkout.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))
import update_memory_index as memory
import verify_docs


class MaintainerTests(unittest.TestCase):
    def fixture(self, root: Path) -> None:
        (root / "TOOLS").mkdir()
        (root / "BUNDLED-TOOLS").mkdir()
        (root / "_CANONICAL-SKILLS/one").mkdir(parents=True)
        (root / "_CANONICAL-SKILLS/one/SKILL.md").write_text("---\nname: one\ndescription: One precise task.\n---\n", encoding="utf-8")
        (root / "BUNDLED-TOOLS/CATALOG.json").write_text('{"components": []}', encoding="utf-8")
        for name in verify_docs.DOCS:
            (root / name).write_text("`TOOLS/real.py`\n", encoding="utf-8")
        (root / "TOOLS/real.py").write_text('"""Real command."""\n', encoding="utf-8")
        (root / "MEMORY.md").write_text(memory.generate(root), encoding="utf-8")

    def test_missing_documented_command_is_red_then_recovers(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.fixture(root)
            self.assertEqual(verify_docs.verify(root), [])
            (root / "README.md").write_text("Run `TESTS/Test-V7-Pack.ps1`.", encoding="utf-8")
            self.assertTrue(any("Test-V7-Pack" in e for e in verify_docs.verify(root)))
            (root / "README.md").write_text("Run `TOOLS/real.py`.", encoding="utf-8")
            self.assertEqual(verify_docs.verify(root), [])

    def test_command_snippets_root_scripts_and_escape_links_are_checked(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.fixture(root)
            for command in ("`python TOOLS/missing.py`", "`powershell -File MISSING.ps1`",
                            "Run .\\TOOLS\\missing.ps1 -Plan", "[escape](../outside.md)",
                            "Use `.github/workflows/missing.yml`."):
                (root / "README.md").write_text(command, encoding="utf-8")
                self.assertTrue(verify_docs.verify(root), command)
            (root / "TOOLS/with space.ps1").write_text("# Help\n", encoding="utf-8")
            (root / "MEMORY.md").write_text(memory.generate(root), encoding="utf-8")
            (root / "README.md").write_text('Run `powershell -File "TOOLS/with space.ps1" -Plan`.', encoding="utf-8")
            self.assertEqual(verify_docs.verify(root), [])

    def test_index_deterministic_ignores_state_and_rejects_duplicate_ids(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.fixture(root)
            before = memory.generate(root)
            (root / "STATE.md").write_text("private changing progress", encoding="utf-8")
            (root / "MACHINE-MAP.md").write_text("private paths", encoding="utf-8")
            self.assertEqual(before, memory.generate(root))
            (root / "BUNDLED-TOOLS/CATALOG.json").write_text('{"components": [{"id":"dup"},{"id":"dup"}]}', encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "duplicate"):
                memory.generate(root)

    def test_index_drift_is_red_and_spaces_in_documented_paths_work(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            self.fixture(root)
            (root / "TOOLS/with space.ps1").write_text("# A real file\n", encoding="utf-8")
            (root / "README.md").write_text("`TOOLS/with space.ps1`", encoding="utf-8")
            self.assertTrue(any("MEMORY.md stale" in e for e in verify_docs.verify(root)))
            (root / "MEMORY.md").write_text(memory.generate(root), encoding="utf-8")
            self.assertEqual(verify_docs.verify(root), [])

    def test_real_git_cleanup_keeps_unmerged_and_checked_out_branches(self):
        shells = [shutil.which(x) for x in ("powershell.exe", "pwsh.exe")]
        self.assertTrue(any(shells), "Windows PowerShell required")
        for shell in filter(None, shells):
            with self.subTest(shell=shell), tempfile.TemporaryDirectory(prefix="Branch ! ") as td:
                root = Path(td)
                remote, repo = root / "remote.git", root / "checkout"

                def git(*args: str) -> str:
                    proc = subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True, timeout=30)
                    self.assertEqual(proc.returncode, 0, proc.stderr)
                    return proc.stdout.strip()

                subprocess.run(["git", "init", "--bare", str(remote)], capture_output=True, check=True)
                subprocess.run(["git", "init", "-b", "main", str(repo)], capture_output=True, check=True)
                git("config", "user.name", "Fixture")
                git("config", "user.email", "fixture@example.invalid")
                git("commit", "--allow-empty", "-m", "base")
                git("remote", "add", "origin", str(remote))
                git("push", "-u", "origin", "main")
                git("branch", "merged")
                git("push", "origin", "merged")
                git("update-ref", "refs/heads/--tags", "HEAD")
                git("push", "origin", "refs/heads/--tags:refs/heads/--tags")
                git("tag", "retained-tag")
                git("push", "origin", "refs/tags/retained-tag")
                git("update-ref", "-d", "refs/heads/--tags")
                git("checkout", "-b", "unfinished")
                git("commit", "--allow-empty", "-m", "unfinished")
                git("push", "origin", "unfinished")
                git("checkout", "main")
                helper = str(ROOT / "TOOLS/Clean-MergedBranches.ps1").replace("'", "''")
                command = f"& '{helper}' | ConvertTo-Json -Compress"
                report = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command], cwd=repo, capture_output=True, text=True, timeout=30)
                self.assertEqual(report.returncode, 0, report.stderr)
                rows = json.loads(report.stdout)
                self.assertFalse(any(r["deleted"] for r in rows))
                self.assertEqual(next(r["verdict"] for r in rows if r["scope"] == "remote" and r["branch"] == "unfinished"), "needs-review")
                applied = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", f"& '{helper}' -Apply | ConvertTo-Json -Compress"], cwd=repo, capture_output=True, text=True, timeout=60)
                self.assertEqual(applied.returncode, 0, applied.stderr)
                self.assertNotIn("merged", git("branch", "--format=%(refname:short)").splitlines())
                self.assertIn("unfinished", git("branch", "--format=%(refname:short)").splitlines())
                self.assertEqual(git("ls-remote", "--heads", "origin", "merged"), "")
                self.assertEqual(git("ls-remote", "--heads", "origin", "refs/heads/--tags"), "")
                self.assertIn("refs/tags/retained-tag", git("ls-remote", "--tags", "origin"))
                self.assertIn("refs/heads/unfinished", git("ls-remote", "--heads", "origin", "unfinished"))

    def test_remote_delete_lease_preserves_a_tip_changed_after_review(self):
        real_git = shutil.which("git")
        for shell in filter(None, (shutil.which(x) for x in ("powershell.exe", "pwsh.exe"))):
            with self.subTest(shell=shell), tempfile.TemporaryDirectory(prefix="Lease ! ") as td:
                root = Path(td)
                remote, repo = root / "remote.git", root / "checkout"
                subprocess.run([real_git, "init", "--bare", str(remote)], capture_output=True, check=True)
                subprocess.run([real_git, "init", "-b", "main", str(repo)], capture_output=True, check=True)

                def git(*args: str) -> str:
                    return subprocess.run([real_git, "-C", str(repo), *args], capture_output=True, text=True, check=True).stdout.strip()

                git("config", "user.name", "Fixture")
                git("config", "user.email", "fixture@example.invalid")
                git("commit", "--allow-empty", "-m", "base")
                git("remote", "add", "origin", str(remote))
                git("push", "-u", "origin", "main")
                git("branch", "merged")
                git("push", "origin", "merged")
                git("checkout", "-b", "new-work")
                git("commit", "--allow-empty", "-m", "new unmerged work")
                new_tip = git("rev-parse", "HEAD")
                git("push", "origin", "new-work")
                git("checkout", "main")
                shim = root / "bin"
                shim.mkdir()
                # Change the bare ref after ls-remote but before push advertises
                # refs: an ordinary --delete would destroy the new commit here.
                (shim / "git.cmd").write_text('@echo off\nif "%~1"=="push" "%UABS_REAL_GIT%" --git-dir="%UABS_TEST_REMOTE%" update-ref refs/heads/merged "%UABS_TEST_NEW_TIP%"\n"%UABS_REAL_GIT%" %*\n', encoding="ascii")
                env = dict(os.environ, PATH=str(shim) + os.pathsep + os.environ["PATH"], UABS_REAL_GIT=real_git,
                           UABS_TEST_REMOTE=str(remote), UABS_TEST_NEW_TIP=new_tip)
                helper = str(ROOT / "TOOLS/Clean-MergedBranches.ps1")
                result = subprocess.run([shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "-Apply"], cwd=repo, env=env, capture_output=True, text=True, timeout=60)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(new_tip, git("ls-remote", "--heads", "origin", "merged"))

    def test_protection_preserves_app_bindings_reviews_and_restrictions(self):
        required = ["Hermes YAML and physical symlink preservation", "Pack gate (Windows PowerShell 5.1, Python 3.14)",
                    "Pack gate (Windows PowerShell 5.1, Python 3.15)", "MANIFEST verifies against the tree",
                    "Version strings agree", "Bundle installs pinned Forge end to end"]
        for shell in filter(None, (shutil.which(x) for x in ("powershell.exe", "pwsh.exe"))):
            with self.subTest(shell=shell), tempfile.TemporaryDirectory(prefix="Protection ") as td:
                root = Path(td)
                accounts = {"users": [{"login": "alice"}], "teams": [{"slug": "core"}], "apps": [{"slug": "bot"}]}
                existing = {"required_status_checks": {"strict": False, "contexts": ["custom"], "checks": [{"context": "custom", "app_id": 42}]},
                            "required_pull_request_reviews": {"required_approving_review_count": 2, "dismiss_stale_reviews": True,
                                                              "require_code_owner_reviews": True, "require_last_push_approval": True,
                                                              "dismissal_restrictions": accounts, "bypass_pull_request_allowances": accounts},
                            "restrictions": accounts, "required_linear_history": {"enabled": True}}
                (root / "existing.json").write_text(json.dumps(existing), encoding="utf-8")
                (root / "required.json").write_text(json.dumps(required), encoding="utf-8")
                mock = root / "mock.py"
                mock.write_text('''import json, os, pathlib, sys
root = pathlib.Path(__file__).parent
args = sys.argv[1:]
capture = root / "capture.json"
if "--input" in args:
    payload = pathlib.Path(args[args.index("--input") + 1]).read_text(encoding="utf-8")
    fields = json.loads(payload)["required_status_checks"]
    if "contexts" in fields and "checks" in fields:
        raise SystemExit("HTTP 422: contexts/checks are mutually exclusive")
    capture.write_text(payload, encoding="utf-8")
    print("{}")
    raise SystemExit(0)
endpoint = args[-1]
if endpoint.endswith("/commits/main"):
    result = {"sha": "a" * 40}
elif "/check-runs?" in endpoint:
    names = json.loads((root / "required.json").read_text())
    if os.environ.get("UABS_MISSING_CHECK"): names = names[:-1]
    result = {"check_runs": [{"name": name, "conclusion": "success", "app": {"id": 99}} for name in names]}
elif endpoint.endswith("/branches/main"):
    result = {"protected": True}
elif endpoint.endswith("/protection"):
    result = json.loads((root / "existing.json").read_text())
    if capture.exists():
        result = json.loads(capture.read_text())
        result["required_status_checks"]["contexts"] = [x["context"] for x in result["required_status_checks"]["checks"]]
        if os.environ.get("UABS_TAMPER_BINDING"):
            result["required_status_checks"]["checks"][0]["app_id"] = 500
        for key in ("allow_force_pushes", "allow_deletions", "required_linear_history"):
            if key in result: result[key] = {"enabled": result[key]}
        def objects(value):
            return {k: [{"login" if k == "users" else "slug": x} for x in v] for k, v in value.items()}
        result["restrictions"] = objects(result["restrictions"])
        for key in ("dismissal_restrictions", "bypass_pull_request_allowances"):
            result["required_pull_request_reviews"][key] = objects(result["required_pull_request_reviews"][key])
else:
    raise SystemExit("Unexpected API endpoint: " + endpoint)
print(json.dumps(result))
''', encoding="utf-8")
                (root / "gh.cmd").write_text(f'@"{sys.executable}" "{mock}" %*\n', encoding="utf-8")
                env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"])
                helper = str(ROOT / "TOOLS/Set-GitHubProtection.ps1")
                base = [shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "-Repo", "fixture/repo"]
                plan = subprocess.run(base, env=env, capture_output=True, text=True, timeout=60)
                self.assertEqual(plan.returncode, 0, plan.stderr)
                self.assertFalse((root / "capture.json").exists())
                applied = subprocess.run(base + ["-Apply"], env=env, capture_output=True, text=True, timeout=60)
                self.assertEqual(applied.returncode, 0, applied.stderr)
                policy = json.loads((root / "capture.json").read_text())
                self.assertNotIn("contexts", policy["required_status_checks"], "Use the checks variant exclusively")
                bindings = {x["context"]: x["app_id"] for x in policy["required_status_checks"]["checks"]}
                self.assertEqual(bindings["custom"], 42)
                self.assertTrue(all(bindings[name] == 99 for name in required))
                self.assertEqual(policy["required_pull_request_reviews"]["required_approving_review_count"], 2)
                expected_accounts = {"users": ["alice"], "teams": ["core"], "apps": ["bot"]}
                self.assertEqual(policy["required_pull_request_reviews"]["dismissal_restrictions"], expected_accounts)
                self.assertEqual(policy["required_pull_request_reviews"]["bypass_pull_request_allowances"], expected_accounts)
                self.assertEqual(policy["restrictions"], expected_accounts)
                self.assertTrue(policy["required_linear_history"])
                (root / "capture.json").unlink()
                tampered = subprocess.run(base + ["-Apply"], env=dict(env, UABS_TAMPER_BINDING="1"), capture_output=True, text=True, timeout=60)
                self.assertNotEqual(tampered.returncode, 0, "Ignored app binding must fail verification")
                missing = subprocess.run(base, env=dict(env, UABS_MISSING_CHECK="1"), capture_output=True, text=True, timeout=60)
                self.assertNotEqual(missing.returncode, 0, "Never require an unobserved job name")


class SkyrimSkillCounts(unittest.TestCase):
    def test_every_actual_readme_count_mutation_fails(self):
        import importlib.util
        import re
        spec = importlib.util.spec_from_file_location("bundle_versions", ROOT / ".github/scripts/check_versions.py")
        versions = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(versions)
        count = len(json.loads((ROOT / "BUNDLED-TOOLS/PACKS.json").read_text(encoding="utf-8-sig"))["packs"]["skyrim"]["skills"])
        text = (ROOT / "README.md").read_text(encoding="utf-8-sig")
        self.assertEqual(versions.validate_skyrim_claims(text, count), [])
        # Mutate actual published prose/table counts, rather than copying the parser's pattern.
        sites = list(re.finditer(r"(?<![\w.])" + str(count) + r"(?![\w.])", text))
        self.assertTrue(sites, "README no longer identifies its specialist inventory")
        for site in sites:
            with self.subTest(line=text.count("\n", 0, site.start()) + 1):
                changed = text[:site.start()] + str(count + 1) + text[site.end():]
                self.assertTrue(versions.validate_skyrim_claims(changed, count))
        changed = text.replace("126 general", "127 general")
        self.assertEqual(versions.validate_skyrim_claims(changed, count), [], "General counts are a separate inventory")


if __name__ == "__main__":
    unittest.main()
