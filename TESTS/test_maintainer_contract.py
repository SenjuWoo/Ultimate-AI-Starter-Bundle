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

    def test_tool_roots_hint_is_read_and_missing_folders_dropped(self):
        # UABS_TOOL_ROOTS is the shared ';'-separated "extra tool folders" hint that
        # Forge and Reverse THIS! read too; the machine map lists what it resolves.
        with tempfile.TemporaryDirectory(prefix="Tool roots ") as td:
            present = Path(td) / "my tools"
            present.mkdir()
            missing = Path(td) / "gone"
            script = "; ".join([
                ". '%s'" % (ROOT / "TOOLS" / "UABS-Common.ps1"),
                "(Get-UabsSkyrimToolDirectories) -join '|'",
            ])
            env = dict(os.environ, UABS_TOOL_ROOTS="%s;%s;" % (missing, present))
            result = subprocess.run(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", script],
                                    env=env, capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stderr)
            found = [Path(p) for p in result.stdout.strip().split("|") if p]
            self.assertIn(present, found, "an existing UABS_TOOL_ROOTS folder was not read")
            self.assertNotIn(missing, found, "a missing UABS_TOOL_ROOTS folder was reported")

    def test_rulesets_block_rewrites_for_everyone_and_gate_only_merges(self):
        required = ["Pack gate (Windows PowerShell 5.1, Python 3.14)", "Version strings agree"]
        mock_source = r'''import json, os, pathlib, sys
root = pathlib.Path(__file__).parent
state_path = root / "state.json"
state = json.loads(state_path.read_text())
args = sys.argv[1:]
method = args[args.index("-X") + 1] if "-X" in args else "GET"
endpoint = [a for a in args if a.startswith("repos/")][0]
body = json.loads(pathlib.Path(args[args.index("--input") + 1]).read_text()) if "--input" in args else None
def save(): state_path.write_text(json.dumps(state))
def out(value): print(json.dumps(value)); raise SystemExit(0)
base = "repos/fixture/repo"
if endpoint == base: out({"default_branch": "main"})
if endpoint == base + "/commits/main": out({"sha": "a" * 40})
if "/check-runs?" in endpoint:
    names = state["observed"]
    out({"check_runs": [{"name": n, "conclusion": "success", "app": {"id": 99}} for n in names]})
if endpoint == base + "/branches/main/protection":
    if method == "DELETE":
        state["classic"] = None; save(); out({})
    if not state["classic"]:
        sys.stderr.write("gh: Branch not protected (HTTP 404)"); raise SystemExit(1)
    out(state["classic"])
if endpoint == base + "/rulesets":
    if method == "POST":
        body["id"] = len(state["rulesets"]) + 100; state["rulesets"].append(body); state["writes"].append(body["name"]); save(); out(body)
    out([{"id": r["id"], "name": r["name"], "target": r["target"]} for r in state["rulesets"]])
if endpoint.startswith(base + "/rulesets/"):
    rid = int(endpoint.rsplit("/", 1)[1])
    match = [r for r in state["rulesets"] if r["id"] == rid][0]
    if method == "PUT":
        body["id"] = rid; state["rulesets"] = [body if r["id"] == rid else r for r in state["rulesets"]]; state["writes"].append(body["name"]); save(); out(body)
    out(match)
if endpoint == base + "/rules/branches/main":
    rules = [dict(rule, ruleset_id=r["id"]) for r in state["rulesets"] if r.get("enforcement") == "active" for rule in r["rules"]]
    if os.environ.get("UABS_DROP_RULE"): rules = [x for x in rules if x["type"] != "non_fast_forward"]
    out(rules)
raise SystemExit("Unexpected API call: " + method + " " + endpoint)
'''
        unrelated = {"id": 7, "name": "tags", "target": "tag", "enforcement": "active", "rules": [{"type": "deletion"}], "bypass_actors": []}
        for shell in filter(None, (shutil.which(x) for x in ("powershell.exe", "pwsh.exe"))):
            with self.subTest(shell=shell), tempfile.TemporaryDirectory(prefix="Protection ") as td:
                root = Path(td)
                (root / "mock.py").write_text(mock_source, encoding="utf-8")
                (root / "gh.cmd").write_text(f'@"{sys.executable}" "{root / "mock.py"}" %*\n', encoding="utf-8")
                env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ["PATH"])
                helper = str(ROOT / "TOOLS/Set-GitHubProtection.ps1")
                base = [shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", helper, "-Repo", "fixture/repo", "-Checks", ";".join(required)]

                def run(state, *extra, **more):
                    (root / "state.json").write_text(json.dumps(state), encoding="utf-8")
                    result = subprocess.run(base + list(extra), env=dict(env, **more), capture_output=True, text=True, timeout=120)
                    return result, json.loads((root / "state.json").read_text(encoding="utf-8"))

                fresh = {"observed": required, "classic": {"required_status_checks": {"strict": True}}, "rulesets": [unrelated], "writes": []}
                plan, after = run(fresh)
                self.assertEqual(plan.returncode, 0, plan.stdout + plan.stderr)
                self.assertEqual(after["writes"], [], "Plan mode must not write")
                wanted = {r["name"]: r for r in json.loads(plan.stdout)}
                self.assertEqual(wanted["integrity"]["bypass_actors"], [], "Force-push/deletion must bind every actor")
                self.assertEqual({r["type"] for r in wanted["integrity"]["rules"]}, {"deletion", "non_fast_forward"})
                self.assertEqual([a["actor_type"] for a in wanted["checks"]["bypass_actors"]], ["RepositoryRole"])
                checks = wanted["checks"]["rules"][0]["parameters"]["required_status_checks"]
                self.assertEqual({(c["context"], c["integration_id"]) for c in checks}, {(n, 99) for n in required})

                applied, after = run(fresh, "-Apply")
                self.assertEqual(applied.returncode, 0, applied.stdout + applied.stderr)
                self.assertIn("PROTECTION: PASS", applied.stdout)
                self.assertIsNone(after["classic"], "Compatible classic protection was not retired")
                self.assertIn(unrelated, after["rulesets"], "An unrelated ruleset was changed")
                again, after = run(after, "-Apply")
                self.assertEqual(again.returncode, 0, again.stdout + again.stderr)
                self.assertEqual(sorted(r["name"] for r in after["rulesets"]), ["checks", "integrity", "tags"], "Re-apply duplicated a ruleset")

                reviewed = dict(fresh, classic={"required_pull_request_reviews": {"required_approving_review_count": 1}})
                refused, after = run(reviewed, "-Apply")
                self.assertNotEqual(refused.returncode, 0, "Reviewer policy would be silently dropped")
                self.assertEqual(after["writes"], [])
                missing, _ = run(dict(fresh, observed=required[:-1]))
                self.assertNotEqual(missing.returncode, 0, "Never require an unobserved job name")
                tampered, _ = run(fresh, "-Apply", UABS_DROP_RULE="1")
                self.assertNotEqual(tampered.returncode, 0, "Verification must read the effective rules")

class CompanionClaims(unittest.TestCase):
    def test_restated_companion_numbers_fail_the_version_gate(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("bundle_versions", ROOT / ".github/scripts/check_versions.py")
        versions = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(versions)
        # Forge and Reverse THIS! release on their own: the README states neither their
        # versions nor Forge's skill count, and putting one back fails the gate.
        text = (ROOT / "README.md").read_text(encoding="utf-8-sig")
        self.assertEqual(versions.validate_skyrim_claims(text), [])
        self.assertEqual(versions.validate_companion_claims(text), [])
        for claim in ("plus 48 with the Skyrim pack", "its 48 specialist skills", "a 48-skill Skyrim pack", "`skyrim` (48 skills"):
            with self.subTest(claim=claim):
                self.assertTrue(versions.validate_skyrim_claims(text + "\n" + claim))
        for claim in ("**Skyrim Forge 6.4.2**", "Reverse THIS! 1.6.1", "Skyrim Forge v7.0",
                      "Skyrim Forge is downloaded from its pinned GitHub release",
                      "[SenjuWoo/SkyrimForge](https://github.com/SenjuWoo/SkyrimForge) and pinned by digest",
                      "Skyrim skills install only when Skyrim is found on this PC"):
            with self.subTest(claim=claim):
                self.assertTrue(versions.validate_companion_claims(text + "\n" + claim))
        changed = text.replace("126 general", "127 general")
        self.assertEqual(versions.validate_skyrim_claims(changed), [], "General counts are a separate inventory")

if __name__ == "__main__":
    unittest.main()
