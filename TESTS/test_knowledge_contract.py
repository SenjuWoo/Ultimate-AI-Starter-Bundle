"""The project-memory and vision contracts must stay wired to real files.

These are documentation contracts, so the failure this guards against is silent:
a template loses a file, a skill's pointer rots, or the vision contract stops
recording user corrections. Nothing here calls a model.
"""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "COPY-TO-YOUR-WORKSPACE" / "_PROJECT-TEMPLATE"


class ProjectTemplate(unittest.TestCase):
    def test_memory_contract_names_every_file(self):
        readme = TEMPLATE / "MEMORY" / "README.md"
        self.assertTrue(readme.is_file(), "the memory contract is missing")
        text = readme.read_text(encoding="utf-8")
        for name in ("STATE.md", "DECISIONS.md", "KNOWN-GOOD.md", "FAILED-APPROACHES.md", "CANDIDATES.md"):
            self.assertIn(name, text, f"the contract never mentions {name}")
        for rule in ("Evidence, not vibes", "Supersede, do not sprout", "Retrieval is selective"):
            self.assertIn(rule, text, f"contract rule lost: {rule}")

    def test_memory_files_exist(self):
        for name in ("DECISIONS.md", "KNOWN-GOOD.md", "FAILED-APPROACHES.md", "CANDIDATES.md"):
            self.assertTrue((TEMPLATE / "MEMORY" / name).is_file(), f"{name} missing")

    def test_vision_contract_records_corrections(self):
        vision = TEMPLATE / "VISION.md"
        self.assertTrue(vision.is_file(), "no persistent art-direction source of truth")
        text = vision.read_text(encoding="utf-8")
        self.assertIn("User corrections", text)
        self.assertIn("Approved and rejected", text)
        self.assertIn("still in force", text.lower(), "a correction has no way to stay binding")
        self.assertIn("Text alone cannot replace looking at the result", text)

    def test_state_links_vision_instead_of_duplicating_it(self):
        state = (TEMPLATE / "STATE.md").read_text(encoding="utf-8")
        self.assertIn("VISION.md", state)
        self.assertLess(state.lower().count("art-direction"), 3,
                        "STATE.md is copying the vision contract instead of linking it")

    def test_vision_template_carries_no_live_project_decision(self):
        # A template that ships one project's approved layout applies it to every
        # new project. The corrections table must start empty.
        text = (TEMPLATE / "VISION.md").read_text(encoding="utf-8")
        dated = [l for l in text.splitlines() if l.startswith("| 20")]
        self.assertEqual([], dated, f"a real correction is baked into the template: {dated}")
        self.assertNotIn("tunnel", text.lower(), "a specific game layout leaked into the template")


class SkillPointers(unittest.TestCase):
    def test_code_review_carries_an_advisory_concern_radar(self):
        text = (ROOT / "_CANONICAL-SKILLS" / "code-review-skill" / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("## Concern radar (advisory)", text)
        self.assertIn("not a gate", text, "the radar must never become a blocker")

    def test_skill_creator_points_at_the_capture_checklist(self):
        skill = ROOT / "_CANONICAL-SKILLS" / "skill-creator"
        self.assertTrue((skill / "references" / "learning-capture.md").is_file())
        self.assertIn("references/learning-capture.md", (skill / "SKILL.md").read_text(encoding="utf-8"))

    def test_no_canonical_skill_exceeds_the_ceiling(self):
        over = [p.parent.name for p in (ROOT / "_CANONICAL-SKILLS").glob("*/SKILL.md")
                if len(p.read_text(encoding="utf-8").splitlines()) > 500]
        self.assertEqual([], over, f"skills over 500 lines: {over}")


if __name__ == "__main__":
    unittest.main(verbosity=2)
