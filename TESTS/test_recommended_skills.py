"""The optional packs must install, namespace, back up and remove without surprises.

Fixture-only: a fake upstream tree is built in a temp folder, so no network and no
provider directory on the real machine is touched.
"""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))

import recommended_skills as rs  # noqa: E402


def make_tree(base):
    for pack in ("pocock", "addy"):
        for rel in rs.PACKS[pack]["skills"]:
            d = base / "skills" / rel
            d.mkdir(parents=True)
            (d / "SKILL.md").write_text("---\nname: upstream\n---\nbody\n", encoding="utf-8")
    for rel in rs.PACKS["addy"]["root_references"]:
        p = base / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text("# checklist\n", encoding="utf-8")
    (base / "LICENSE").write_text("MIT License\nCopyright (c) upstream\n", encoding="utf-8")
    return base


class RecommendedSkillsTests(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        base = Path(self._tmp.name)
        self.home = base / "home"
        (self.home / ".claude" / "skills").mkdir(parents=True)
        self.tree = make_tree(base / "tree")
        self._saved = (rs.STATE, os.environ.get("CLAUDE_CONFIG_DIR"))
        rs.STATE = base / "state"
        os.environ.pop("CLAUDE_CONFIG_DIR", None)

    def tearDown(self):
        rs.STATE, claude_dir = self._saved
        if claude_dir is None:
            os.environ.pop("CLAUDE_CONFIG_DIR", None)
        else:
            os.environ["CLAUDE_CONFIG_DIR"] = claude_dir
        self._tmp.cleanup()

    def test_plan_is_pure_and_namespaced(self):
        before = sorted(p.name for p in (self.home / ".claude" / "skills").iterdir())
        actions = rs.plan("pocock", "claude", home=self.home, tree=self.tree)
        after = sorted(p.name for p in (self.home / ".claude" / "skills").iterdir())
        self.assertEqual(before, after)
        names = [a["name"] for a in actions if a["kind"] == "skill"]
        self.assertTrue(all(n.startswith("pocock-") for n in names))
        self.assertIn("pocock-domain-modeling", names)

    def test_install_copies_skills_references_and_licence(self):
        results, receipt = rs.install("addy", "claude", home=self.home, tree=self.tree, stamp="T")
        self.assertTrue(all(r["ok"] for r in results))
        claude = self.home / ".claude"
        self.assertTrue((claude / "skills" / "addy-security-and-hardening" / "SKILL.md").is_file())
        # Upstream links `../../references/<file>` from a skill folder: the shared
        # files must sit at <provider>/references for that link to resolve.
        self.assertTrue((claude / "references" / "security-checklist.md").is_file())
        link = (claude / "skills" / "addy-security-and-hardening" / ".." / ".." / "references"
                / "security-checklist.md").resolve()
        self.assertTrue(link.is_file(), "the upstream relative link must resolve after install")
        self.assertTrue((claude / "references" / "addy-LICENSE.txt").is_file(),
                        "the MIT notice must travel with redistributed material")
        self.assertTrue(receipt.is_file())
        data = json.loads(receipt.read_text(encoding="utf-8"))
        self.assertEqual(data["pin"], rs.PACKS["addy"]["pin"])

    def test_frontmatter_name_matches_the_installed_directory(self):
        rs.install("addy", "claude", home=self.home, tree=self.tree, stamp="T")
        text = (self.home / ".claude" / "skills" / "addy-context-engineering" / "SKILL.md").read_text(encoding="utf-8")
        self.assertIn("name: addy-context-engineering", text)
        self.assertIn("license: MIT", text)
        self.assertIn("upstream: addyosmani/agent-skills@", text)
        self.assertIn("body", text, "the instruction body must survive namespacing")

    def test_repeated_install_does_not_nest_backups(self):
        target = self.home / ".claude" / "skills" / "pocock-retro"
        target.mkdir(parents=True)
        (target / "SKILL.md").write_text("mine", encoding="utf-8")
        rs.install("pocock", "claude", home=self.home, tree=self.tree, stamp="T1")
        rs.install("pocock", "claude", home=self.home, tree=self.tree, stamp="T2")
        backups = sorted(p.name for p in (self.home / ".claude" / "skills").glob("*.backup-*"))
        self.assertEqual(backups, ["pocock-retro.backup-T1"],
                         "a reinstall must replace our own copy, not back it up again")
        receipt = json.loads(rs.receipt_path("pocock", "claude", self.home).read_text(encoding="utf-8"))
        self.assertEqual(len(receipt["backups"]), 1)
        self.assertEqual(len(receipt["owned"]), len(rs.PACKS["pocock"]["skills"]) + 1)

    def test_install_install_remove_restores_the_original_state(self):
        target = self.home / ".claude" / "skills" / "pocock-retro"
        target.mkdir(parents=True)
        (target / "SKILL.md").write_text("mine", encoding="utf-8")
        for stamp in ("T1", "T2"):
            rs.install("pocock", "claude", home=self.home, tree=self.tree, stamp=stamp)
        rs.remove("pocock", "claude", home=self.home)
        self.assertEqual((target / "SKILL.md").read_text(encoding="utf-8"), "mine")
        self.assertEqual([p.name for p in (self.home / ".claude" / "skills").iterdir()], ["pocock-retro"])

    def test_interrupted_install_is_still_removable(self):
        rs.install("pocock", "claude", home=self.home, tree=self.tree, stamp="T1")
        import shutil
        shutil.rmtree(self.home / ".claude" / "skills" / "pocock-triage")  # crash midway
        rs.install("pocock", "claude", home=self.home, tree=self.tree, stamp="T2")
        rs.remove("pocock", "claude", home=self.home)
        self.assertEqual([p.name for p in (self.home / ".claude" / "skills").iterdir()], [])

    def test_two_homes_keep_separate_receipts(self):
        other = Path(self._tmp.name) / "home2"
        (other / ".claude" / "skills").mkdir(parents=True)
        rs.install("pocock", "claude", home=self.home, tree=self.tree, stamp="T")
        rs.install("pocock", "claude", home=other, tree=self.tree, stamp="T")
        self.assertNotEqual(rs.receipt_path("pocock", "claude", self.home),
                            rs.receipt_path("pocock", "claude", other))
        rs.remove("pocock", "claude", home=self.home)
        names = [p.name for p in (other / ".claude" / "skills").iterdir()]
        self.assertTrue(names and all(n.startswith("pocock-") for n in names),
                        "removing one home must not touch the other")

    def test_existing_skill_is_backed_up_not_overwritten(self):
        target = self.home / ".claude" / "skills" / "addy-context-engineering"
        target.mkdir(parents=True)
        (target / "SKILL.md").write_text("mine", encoding="utf-8")
        rs.install("addy", "claude", home=self.home, tree=self.tree, stamp="T")
        backups = list((self.home / ".claude" / "skills").glob("*.backup-T"))
        self.assertEqual(len(backups), 1)
        self.assertEqual((backups[0] / "SKILL.md").read_text(encoding="utf-8"), "mine")
        self.assertTrue((target / "SKILL.md").is_file())

    def test_remove_deletes_only_installed_paths_and_restores_backups(self):
        target = self.home / ".claude" / "skills" / "pocock-retro"
        target.mkdir(parents=True)
        (target / "SKILL.md").write_text("mine", encoding="utf-8")
        rs.install("pocock", "claude", home=self.home, tree=self.tree, stamp="T")
        mine = self.home / ".claude" / "skills" / "keep-me"
        mine.mkdir()
        rs.remove("pocock", "claude", home=self.home)
        self.assertFalse((self.home / ".claude" / "skills" / "pocock-domain-modeling").exists())
        self.assertTrue(mine.is_dir(), "a skill this tool never installed must survive")
        self.assertEqual((target / "SKILL.md").read_text(encoding="utf-8"), "mine",
                         "the user's own copy is restored from the backup")
        self.assertFalse(rs.receipt_path("pocock", "claude", self.home).exists())

    def test_remove_without_a_receipt_is_refused(self):
        with self.assertRaises(SystemExit):
            rs.remove("pocock", "grok", home=self.home)

    def test_claude_config_dir_is_honoured(self):
        custom = Path(self._tmp.name) / "claude-custom"
        custom.mkdir()
        os.environ["CLAUDE_CONFIG_DIR"] = str(custom)
        self.assertEqual(rs.provider_dirs(self.home)["claude"], custom / "skills")

    def test_pins_are_full_and_licences_recorded(self):
        for name, spec in rs.PACKS.items():
            self.assertEqual(len(spec["pin"]), 40, name)
            self.assertEqual(spec["license"], "MIT", name)


if __name__ == "__main__":
    unittest.main(verbosity=2)
