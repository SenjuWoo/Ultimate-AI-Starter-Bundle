"""Executable index lifecycle and Unicode privacy regressions (stdlib only)."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_tool(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@unittest.skipUnless(os.name == "nt", "Windows PowerShell runtime contract")
class IndexLifecycle(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="uabs index é ")
        self.root = Path(self.temp.name)
        self.project = self.root / "project é"
        self.project.mkdir()

    def tearDown(self):
        self.temp.cleanup()

    def run_index(self, *args):
        return subprocess.run(
            [shutil.which("powershell.exe"), "-NoProfile", "-ExecutionPolicy", "Bypass",
             "-File", str(ROOT / "TOOLS/Setup-CodebaseMemory-Index.ps1"),
             "-Path", str(self.project), *args],
            capture_output=True, text=True, errors="replace", timeout=30,
        )

    def fake_indexer(self, exit_code=0):
        fake = self.root / "indexer.cmd"
        fake.write_text('@echo off\necho {"status":"indexed","nodes":3,"edges":2}\n'
                        f'exit /b {exit_code}\n', encoding="ascii")
        return str(fake)

    def test_index_alone_applies_ignore_rules(self):
        result = self.run_index("-Index", "-CbmExe", self.fake_indexer())
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        ignore = self.project / ".cbmignore"
        self.assertTrue(ignore.is_file(), "-Index indexed before creating scope rules")

    def test_missing_explicit_indexer_fails_before_writing(self):
        result = self.run_index("-Apply", "-Index", "-CbmExe", str(self.root / "absent.exe"))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.project / ".cbmignore").exists(), "preflight failure modified project")

    def test_native_failure_cannot_be_reported_as_indexed(self):
        result = self.run_index("-Apply", "-Index", "-CbmExe", self.fake_indexer(7))
        self.assertNotEqual(result.returncode, 0, "native exit 7 was ignored")
        self.assertNotIn("all 1 indexed", result.stdout)

    def test_dry_run_has_no_side_effects(self):
        result = self.run_index()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.project / ".cbmignore").exists())

    def test_unicode_custom_rules_survive_repeated_apply(self):
        ignore = self.project / ".cbmignore"
        ignore.write_text("# my rule\nprivate-é/\n", encoding="utf-8")
        first = self.run_index("-Apply")
        self.assertEqual(first.returncode, 0, first.stderr)
        content = ignore.read_text(encoding="utf-8-sig")
        self.assertIn("private-é/", content)
        second = self.run_index("-Apply")
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertEqual(ignore.read_text(encoding="utf-8-sig"), content)

    def test_current_version_is_not_a_prefix_of_another_snapshot(self):
        for version in ("a-1.2.30", "b-1.2.3"):
            (self.project / version).mkdir()
        (self.project / "CURRENT.txt").write_text("1.2.3\n", encoding="utf-8")
        result = self.run_index("-Apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        content = (self.project / ".cbmignore").read_text(encoding="utf-8-sig")
        self.assertIn("# active = b-1.2.3\n", content)
        self.assertIn("\na-1.2.30/\n", content)
        self.assertNotIn("\nb-1.2.3/\n", content)

    def test_pack_gate_file_scope_uses_shipped_manifest_not_old_artifacts(self):
        import json
        shipped = self.root / "shipped.ps1"
        shipped.write_text("exit 0", encoding="ascii")
        old = self.root / "artifacts/old.ps1"
        old.parent.mkdir()
        old.write_text("invalid old script", encoding="ascii")
        (self.root / "MANIFEST.json").write_text(
            json.dumps({"files": [{"path": "shipped.ps1"}]}), encoding="utf-8")
        command = (". '" + str(ROOT / "TOOLS/UABS-Common.ps1").replace("'", "''") + "'; "
                   "@(Get-UabsManifestFiles -PackRoot '" + str(self.root).replace("'", "''") +
                   "') | ForEach-Object { $_.Name }")
        result = subprocess.run([shutil.which("powershell.exe"), "-NoProfile", "-Command", command],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.stdout.strip(), "shipped.ps1", result.stderr)
        # Released manifests also use a bare list, including a one-entry list.
        (self.root / "MANIFEST.json").write_text(
            json.dumps([{"path": "shipped.ps1"}]), encoding="utf-8")
        result = subprocess.run([shutil.which("powershell.exe"), "-NoProfile", "-Command", command],
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.stdout.strip(), "shipped.ps1", result.stderr)


class PrivacyCoverage(unittest.TestCase):
    def test_unicode_tracked_filename_is_actually_scanned(self):
        guard = load_tool("privacy_guard", ROOT / "TESTS/test_privacy_boundary.py")
        with tempfile.TemporaryDirectory(prefix="uabs privacy ") as tmp:
            guard.ROOT = Path(tmp)
            subprocess.run(["git", "init", "-q", tmp], check=True)
            (guard.ROOT / ".gitignore").write_text("\n".join(guard.REQUIRED_IGNORES), encoding="utf-8")
            filename = "privé document.md"
            synthetic_address = "private.person" + "@gmail" + ".com"
            (guard.ROOT / filename).write_text("contact: " + synthetic_address, encoding="utf-8")
            subprocess.run(["git", "-C", tmp, "add", "--", ".gitignore", filename], check=True)
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                result = guard.main()
            self.assertEqual(result, 1, "Unicode filename bypassed personal-data scanning")
            self.assertIn("personal e-mail address", output.getvalue())


class UsageAccounting(unittest.TestCase):
    def test_codex_reasoning_is_a_detail_of_output_not_extra_output(self):
        import json
        usage = load_tool("usage_report", ROOT / "TOOLS/usage_report.py")
        with tempfile.TemporaryDirectory(prefix="uabs usage ") as tmp:
            home = Path(tmp)
            logs = home / ".codex/sessions"
            logs.mkdir(parents=True)
            event = {"type": "event_msg", "payload": {"type": "token_count", "info": {
                "total_token_usage": {"input_tokens": 100, "cached_input_tokens": 40,
                                      "output_tokens": 20, "reasoning_output_tokens": 5,
                                      "total_tokens": 120}}}}
            (logs / "fixture.jsonl").write_text(json.dumps(event) + "\n", encoding="utf-8")
            with patch.object(usage, "HOME", home):
                sessions = usage.codex()
            self.assertEqual(len(sessions), 1)
            self.assertEqual(sessions[0]["out"], 20, "reasoning detail counted twice")
            self.assertEqual(sessions[0].weight(), 164)


if __name__ == "__main__":
    unittest.main(verbosity=2)
