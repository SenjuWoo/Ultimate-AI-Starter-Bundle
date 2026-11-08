"""Routing stays single-owner, and the optional packs never load themselves.

The risk Phase 2 introduces is duplicate methodology: two skills that both claim
"review this" or "plan this". These tests pin one owner per scenario and prove the
recommended packs are absent from every provider tree until someone installs them.
"""

import json
import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CANONICAL = ROOT / "_CANONICAL-SKILLS"
COMPANIONS = json.loads((ROOT / "BUNDLED-TOOLS" / "COMPANIONS.json").read_text(encoding="utf-8"))

sys.path.insert(0, str(ROOT / "TOOLS"))
import recommended_skills as rs  # noqa: E402

# One owner per scenario: the skill an agent should reach for, and the files that
# must exist for that claim to be true.
OWNERS = {
    "bugfix": ["systematic-debugging", "diagnosing-superpowers"],
    "feature": ["writing-plans", "executing-plans", "one-shot-completion"],
    "security": ["code-review-skill", "requesting-code-review"],
    "frontend": ["impeccable", "popular-web-designs"],
    "game": ["game-dev-starter", "mod-workspace-organization", "capability-routing"],
    "docs": ["public-copy-durability", "mod-presentation"],
    "autonomous": ["one-shot-completion", "executing-plans", "state-resumption"],
}

PROVIDER_TREES = sorted((ROOT / "1-TAILORED-PROVIDER-TREES").glob("*/COPY-TO-SKILLS-DIRECTORY/skills"))


def desc(name):
    text = (CANONICAL / name / "SKILL.md").read_text(encoding="utf-8-sig", errors="replace")
    m = re.search(r"(?m)^description:\s*(.+)$", text)
    return (m.group(1) if m else "").strip()


class RoutingTests(unittest.TestCase):
    def test_every_scenario_has_its_owner(self):
        for scenario, owners in OWNERS.items():
            found = [o for o in owners if (CANONICAL / o / "SKILL.md").is_file()]
            self.assertTrue(found, "no owner skill for %s" % scenario)

    def test_recommended_packs_are_not_preinstalled(self):
        for tree in PROVIDER_TREES:
            names = [p.name for p in tree.iterdir() if p.is_dir()]
            leaked = [n for n in names if n.startswith(("pocock-", "addy-"))]
            self.assertEqual(leaked, [], "%s already carries optional packs" % tree)

    def test_no_duplicate_skill_names_across_canonical_tree(self):
        names = [p.name.lower() for p in CANONICAL.iterdir() if (p / "SKILL.md").is_file()]
        self.assertEqual(len(names), len(set(names)), "two canonical skills share a name")

    def test_recommended_entries_are_detect_only(self):
        for name, entry in COMPANIONS["recommended"].items():
            for forbidden in ("install", "update", "doctor"):
                self.assertNotIn(forbidden, entry, "%s declares an executable entrypoint" % name)
            self.assertRegex(entry["pin"], r"^[0-9a-f]{40}$", name)
            self.assertTrue(entry.get("docs"), name)
            self.assertTrue((ROOT / entry["docs"]).is_file(), entry["docs"])

    def test_curated_subsets_are_prefixed_and_unique(self):
        seen = set()
        for pack, spec in rs.PACKS.items():
            for rel in spec["skills"]:
                name = spec["prefix"] + Path(rel).name
                self.assertNotIn(name, seen)
                seen.add(name)
                self.assertNotIn(name, [p.name for p in CANONICAL.iterdir()],
                                 "an optional skill must not shadow a bundle skill")

    def test_skill_metadata_is_usable(self):
        # Valid frontmatter and a description short enough to be a pointer rather than
        # a prompt: length is the part a machine can check without judging prose.
        bad = []
        for skill in CANONICAL.iterdir():
            md = skill / "SKILL.md"
            if not md.is_file():
                continue
            text = md.read_text(encoding="utf-8-sig", errors="replace")
            m = re.search(r"(?m)^description:\s*(.+)$", text)
            if not m or not m.group(1).strip() or len(m.group(1)) > 600:
                bad.append(skill.name)
        self.assertEqual(bad, [], "skills with missing or oversized descriptions: %s" % bad)


if __name__ == "__main__":
    unittest.main(verbosity=2)
