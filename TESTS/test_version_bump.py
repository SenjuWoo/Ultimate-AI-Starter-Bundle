"""Regression tests for .github/scripts/check_versions.py --set.

The release bumper is the one script that can leave a tree with mixed version
declarations, so its failure modes are exercised here against a tmp fixture
tree rather than the real repository.
"""

import importlib.util
import os
import re
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "check_versions", ROOT / ".github" / "scripts" / "check_versions.py")
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)

# (file, pattern, label) -- one with a capture group, one deliberately without.
DECLS = [
    ("notes.md", r"^Version (\d+\.\d+\.\d+)$", "notes"),
    ("banner.ps1", r"^# generated banner, no literal version$", "banner"),
    ("app.json", r'"version": "(\d+\.\d+\.\d+)"', "app"),
]


class VersionBump(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="uabs-version-")
        files = {
            "VERSION.txt": "v1.0.0\n",
            "notes.md": "# Notes\nVersion 1.0.0\n",
            "banner.ps1": "# generated banner, no literal version\nWrite-Host ok\n",
            "app.json": '{\n  "version": "1.0.0"\n}\n',
        }
        for name, body in files.items():
            Path(self.tmp, name).write_text(body, encoding="utf-8", newline="")  # keep LF: $ must match
        self._root, self._decls = MOD.ROOT, MOD.DECLARATIONS
        # resolve at call time: tmp is a Windows 8.3 path, os.path.join keeps it
        MOD.ROOT = str(Path(self.tmp))
        MOD.DECLARATIONS = DECLS

    def tearDown(self):
        MOD.ROOT, MOD.DECLARATIONS = self._root, self._decls

    def read(self, name):
        return Path(self.tmp, name).read_text(encoding="utf-8")

    def test_valid_bump_rewrites_every_declaration(self):
        MOD.set_version("2.5.1")
        self.assertEqual(self.read("VERSION.txt").strip(), "v2.5.1")
        self.assertIn("Version 2.5.1", self.read("notes.md"))
        self.assertIn('"version": "2.5.1"', self.read("app.json"))

    def test_versionless_declaration_is_accepted(self):
        # A declaration with no capture group restates nothing; --set used to
        # raise IndexError on exactly this shape.
        MOD.set_version("2.5.1")
        self.assertIn("generated banner", self.read("banner.ps1"))

    def test_repeat_bump_is_idempotent(self):
        MOD.set_version("2.5.1")
        before = {n: self.read(n) for n in ("VERSION.txt", "notes.md", "app.json")}
        MOD.set_version("2.5.1")
        self.assertEqual(before, {n: self.read(n) for n in before})

    def test_invalid_version_is_rejected(self):
        with self.assertRaises(SystemExit):
            MOD.set_version("8")  # V needs at least two dotted parts
        self.assertEqual(self.read("VERSION.txt").strip(), "v1.0.0")

    def test_missing_declaration_fails_without_touching_any_file(self):
        # The last declaration cannot match: the whole bump must be a no-op.
        MOD.DECLARATIONS = DECLS[:2] + [("app.json", r'"absent": "(\d+)"', "app")]
        before = {n: self.read(n) for n in ("VERSION.txt", "notes.md", "banner.ps1", "app.json")}
        with self.assertRaises(SystemExit):
            MOD.set_version("3.0.0")
        after = {n: self.read(n) for n in before}
        self.assertEqual(before, after, "a failed bump left mixed version declarations")

    def test_all_declarations_agree_after_a_bump(self):
        MOD.set_version("4.2.0")
        found = {re.search(p, self.read(f), re.M).group(1)
                 for f, p, _ in DECLS if re.compile(p, re.M).groups}
        self.assertEqual(found, {"4.2.0"})


if __name__ == "__main__":
    unittest.main(verbosity=2)
