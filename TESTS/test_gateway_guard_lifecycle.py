"""Regression tests for the Hermes gateway guard's file and exit contracts.

The guard writes into site-packages of the Hermes store Python. A foreign
sitecustomize.py there belongs to someone else, and the previous build replaced
or deleted it; these tests pin the byte-preserving behaviour and the exit codes
that tell a caller whether a host was really restored.
"""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
GUARD = ROOT / "TOOLS" / "hooks" / "hermes_gateway_guard.py"

SPEC = importlib.util.spec_from_file_location("uabs_guard", GUARD)
guard = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(guard)

FOREIGN = (
    "# sitecustomize installed by some other package\n"
    "import os\n"
    "\n"
    "os.environ.setdefault('SOME_PACKAGE_HOME', 'C:/tools/some')\n"
)


class SitecustomizeLifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uabs-guard-")
        self.site = Path(self.tmp) / "site-packages"
        self.site.mkdir()
        self.python = Path(self.tmp) / "python.exe"
        self.python.write_text("", encoding="utf-8")
        self._hp, self._sp = guard.hermes_pythons, guard.site_packages_dir
        guard.hermes_pythons = lambda localappdata: [self.python]
        guard.site_packages_dir = lambda python: self.site
        self.target = self.site / "sitecustomize.py"
        self.module = self.site / "uabs_hermes_gateway_guard.py"

    def tearDown(self):
        guard.hermes_pythons, guard.site_packages_dir = self._hp, self._sp

    def install(self):
        return guard.install_sitecustomize(Path(self.tmp), GUARD)

    def test_clean_install_reinstall_uninstall(self):
        self.install()
        self.assertIn(guard.BLOCK_BEGIN, self.target.read_text(encoding="utf-8"))
        first = self.target.read_bytes()
        self.install()
        self.assertEqual(first, self.target.read_bytes(), "reinstall was not idempotent")
        guard.remove_sitecustomize(Path(self.tmp))
        self.assertFalse(self.target.exists())
        self.assertFalse(self.module.exists())

    def test_foreign_file_is_preserved_byte_for_byte(self):
        self.target.write_bytes(FOREIGN.encode("utf-8"))
        self.install()
        self.assertIn("SOME_PACKAGE_HOME", self.target.read_text(encoding="utf-8"))
        self.install()
        guard.remove_sitecustomize(Path(self.tmp))
        self.assertEqual(FOREIGN.encode("utf-8"), self.target.read_bytes(),
                         "a foreign sitecustomize.py did not survive install/uninstall")

    def test_content_on_both_sides_of_the_block_survives(self):
        self.install()
        text = self.target.read_text(encoding="utf-8")
        self.target.write_text("# before\n" + text + "# after\n", encoding="utf-8")
        self.install()
        guard.remove_sitecustomize(Path(self.tmp))
        self.assertEqual("# before\n# after\n", self.target.read_text(encoding="utf-8"))

    def test_marker_lookalike_elsewhere_is_foreign(self):
        lookalike = "# a comment mentioning UABS-HERMES-GATEWAY-GUARD\nHANDLER = 1\n"
        self.target.write_bytes(lookalike.encode("utf-8"))
        self.install()
        guard.remove_sitecustomize(Path(self.tmp))
        self.assertEqual(lookalike.encode("utf-8"), self.target.read_bytes())

    def test_legacy_whole_file_install_is_migrated_with_a_backup(self):
        legacy = "# " + guard.MARKER + "\n# old whole-file install\ndef _uabs_hermes_gateway_guard():\n    pass\n"
        self.target.write_text(legacy, encoding="utf-8")
        self.install()
        self.assertTrue(self.target.with_suffix(".py.uabs-legacy-bak").exists(), "no recovery copy")
        guard.remove_sitecustomize(Path(self.tmp))
        self.assertFalse(self.target.exists(), "legacy file stayed behind")

    def test_bom_and_crlf_are_preserved(self):
        foreign = "# foreign\r\nimport os\r\n"
        self.target.write_bytes(b"\xef\xbb\xbf" + foreign.encode("utf-8"))
        self.install()
        self.assertTrue(self.target.read_bytes().startswith(b"\xef\xbb\xbf"), "BOM dropped")
        # read_text() hides CRLF through universal newlines; the bytes are the fact.
        self.assertIn(b"\r\n", self.target.read_bytes(), "line endings were rewritten to LF")
        guard.remove_sitecustomize(Path(self.tmp))
        self.assertEqual(b"\xef\xbb\xbf" + foreign.encode("utf-8"), self.target.read_bytes())

    def test_install_without_hermes_store_is_a_no_op(self):
        guard.hermes_pythons = lambda localappdata: []
        self.assertEqual([], self.install())
        guard.remove_sitecustomize(Path(self.tmp))
        self.assertFalse(self.module.exists())


class ExitCodes(unittest.TestCase):
    """A blocked replace must not report success when no host came back."""

    def run_guard(self, args, env_extra):
        home = tempfile.mkdtemp(prefix="uabs-host-")
        env = {"HERMES_HOME": home, "LOCALAPPDATA": home, "PATH": "",
               "SYSTEMROOT": os.environ.get("SYSTEMROOT", "C:\\Windows")}
        env.update(env_extra)
        code = (
            "import importlib.util, sys\n"
            "spec = importlib.util.spec_from_file_location('g', sys.argv[1])\n"
            "m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)\n"
            "m.guard_process(sys.argv[2:], dict(__import__('os').environ))\n"
            "print('allowed-through')\n"
        )
        return subprocess.run([sys.executable, "-I", "-c", code, str(GUARD)] + args,
                              capture_output=True, text=True, timeout=120, env=env)

    def test_dead_host_and_no_recovery_exits_nonzero(self):
        done = self.run_guard(["py", "--profile", "code", "gateway", "run", "--replace"], {})
        self.assertEqual(guard.EXIT_RECOVERY_FAILED, done.returncode,
                         "a failed recovery exited like a success: " + done.stdout + done.stderr)

    def test_recovery_spawn_is_allowed_through(self):
        done = self.run_guard(["py", "--profile", "code", "gateway", "run", "--replace"],
                              {guard.SPAWN_FLAG: "1"})
        self.assertEqual(0, done.returncode)
        self.assertIn("allowed-through", done.stdout)

    def test_default_profile_replace_is_untouched(self):
        done = self.run_guard(["hermes", "gateway", "run", "--replace"], {})
        self.assertEqual(0, done.returncode)
        self.assertIn("allowed-through", done.stdout)


if __name__ == "__main__":
    unittest.main(verbosity=2)
