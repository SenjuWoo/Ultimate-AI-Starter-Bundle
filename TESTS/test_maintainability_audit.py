"""The maintainability audit must report real drift and stay quiet on mirrors."""
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "TOOLS"))

import audit_maintainability as audit  # noqa: E402


class AuditFixture(unittest.TestCase):
    def test_duplicate_detected_and_allowlisted_mirror_ignored(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "a").mkdir()
            (root / "b").mkdir()
            payload = "# same body\n" * 200
            (root / "a/one.md").write_text(payload, encoding="utf-8")
            (root / "b/two.md").write_text(payload, encoding="utf-8")
            self.assertEqual(len(audit.duplicate_groups(root, ["a/one.md", "b/two.md"])), 1)

            real = audit.ALLOWED_DUPLICATES
            try:
                audit.ALLOWED_DUPLICATES = {("a/one.md", "b/two.md")}
                self.assertEqual(audit.duplicate_groups(root, ["a/one.md", "b/two.md"]), [])
            finally:
                audit.ALLOWED_DUPLICATES = real

    def test_oversized_skill_is_reported(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            skill = root / "_CANONICAL-SKILLS" / "fat"
            skill.mkdir(parents=True)
            (skill / "SKILL.md").write_text("\n".join(["x"] * 501), encoding="utf-8")
            self.assertEqual(audit.oversized_skills(root), [{"skill": "fat", "lines": 501}])

    def test_adr_sections_are_enforced(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            d = root / "docs" / "decisions"
            d.mkdir(parents=True)
            (d / "README.md").write_text("index", encoding="utf-8")
            (d / "0001-x.md").write_text("# ADR-0001\n\n## Context\nonly context\n", encoding="utf-8")
            problems = audit.adr_problems(root)
            self.assertTrue(any("lacks ## Decision" in p for p in problems), problems)
            self.assertTrue(any("not linked" in p for p in problems), problems)


class ShippedTree(unittest.TestCase):
    def test_repository_passes_strict(self) -> None:
        report = {
            "duplicates": audit.duplicate_groups(ROOT, audit.tracked(ROOT)),
            "oversized_skills": audit.oversized_skills(ROOT),
            "adr_problems": audit.adr_problems(ROOT),
        }
        self.assertEqual(report["duplicates"], [])
        self.assertEqual(report["oversized_skills"], [])
        self.assertEqual(report["adr_problems"], [])


if __name__ == "__main__":
    unittest.main()
