"""Domain skill families leave the listing, never the machine; a user's choice always wins.

Runs standalone (`python TESTS/test_skill_scope.py`) and under pytest.
"""
import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "TOOLS"))

import skill_scope as ss  # noqa: E402

POLICY = {
    "schema": 1,
    "protected": "(?i)adult|sexlab",
    "families": {
        "roblox": {"prefixes": ["roblox-"], "keep_described": ["roblox-game-development"]},
        "skyrim": {"prefixes": ["skyrim-"], "names": ["spid-authoring", "fictional-adult-modding"],
                   "keep_described": []},
    },
    "claude": {"name_only": ["roblox"]},
    "hermes": {"families": ["roblox", "skyrim"], "profiles": {"roblox": ["roblox"], "skyrim": ["skyrim"]}},
}


def skill(root, name, description="does one thing"):
    folder = os.path.join(root, name)
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "SKILL.md"), "w", encoding="utf-8") as handle:
        handle.write("---\nname: %s\ndescription: %s\n---\nbody\n" % (name, description))


class Box:
    def __init__(self, case):
        self.temp = tempfile.TemporaryDirectory()
        case.addCleanup(self.temp.cleanup)
        self.root = self.temp.name
        self.claude = os.path.join(self.root, "claude")
        self.local = os.path.join(self.root, "local")
        for name in ("roblox-game-development", "roblox-ui", "roblox-data-stores", "skyrim-nif",
                     "adult-roblox-thing", "code-review"):
            skill(os.path.join(self.claude, "skills"), name, "x" * 50)
        patcher = mock.patch.dict(os.environ, {"CLAUDE_CONFIG_DIR": self.claude, "LOCALAPPDATA": self.local})
        patcher.start()
        case.addCleanup(patcher.stop)

    def settings(self):
        with open(os.path.join(self.claude, "settings.json"), encoding="utf-8") as handle:
            return json.load(handle)

    def write_settings(self, data):
        os.makedirs(self.claude, exist_ok=True)
        with open(os.path.join(self.claude, "settings.json"), "w", encoding="utf-8") as handle:
            json.dump(data, handle)


def run(*args):
    with mock.patch.object(ss, "load_policy", lambda *a, **k: json.loads(json.dumps(POLICY))), \
            mock.patch.object(ss, "hermes_exe", lambda root: None):
        with contextlib.redirect_stdout(io.StringIO()):
            return ss.main(list(args) + ["--provider", "claude", "--json"])


class Claude(unittest.TestCase):
    def test_specialists_go_name_only_and_the_router_keeps_its_description(self):
        box = Box(self)
        box.write_settings({"theme": "dark", "skillOverrides": {"roblox-ui": "off"}})
        run("--fix")
        overrides = box.settings()["skillOverrides"]
        self.assertEqual(overrides["roblox-data-stores"], "name-only")
        self.assertNotIn("roblox-game-development", overrides)
        self.assertNotIn("adult-roblox-thing", overrides, "protected names are never touched")
        self.assertNotIn("skyrim-nif", overrides, "families outside the Claude policy stay described")
        self.assertEqual(overrides["roblox-ui"], "off", "the user's own value wins")
        self.assertEqual(box.settings()["theme"], "dark")
        backups = [n for n in os.listdir(box.claude) if n.startswith("settings.json.before-skill-scope-")]
        self.assertTrue(backups)

    def test_undo_removes_only_what_it_added_and_stays_off(self):
        box = Box(self)
        box.write_settings({"skillOverrides": {"code-review": "user-invocable-only"}})
        run("--fix")
        run("--undo")
        self.assertEqual(box.settings()["skillOverrides"], {"code-review": "user-invocable-only"})
        run("--fix")
        self.assertNotIn("roblox-data-stores", box.settings()["skillOverrides"], "--undo is remembered")
        run("--fix", "--force")
        self.assertEqual(box.settings()["skillOverrides"]["roblox-data-stores"], "name-only")

    def test_a_skill_that_leaves_the_family_is_given_back(self):
        box = Box(self)
        box.write_settings({})
        run("--fix")
        import shutil
        shutil.rmtree(os.path.join(box.claude, "skills", "roblox-ui"))
        run("--fix")
        self.assertNotIn("roblox-ui", box.settings()["skillOverrides"])


class Hermes(unittest.TestCase):
    def test_each_profile_disables_the_families_that_are_not_its_own(self):
        with tempfile.TemporaryDirectory() as root:
            for profile in ("roblox", "skyrim", "web"):
                for name in ("roblox-ui", "skyrim-nif", "spid-authoring", "fictional-adult-modding", "web-dev"):
                    skill(os.path.join(root, "profiles", profile, "skills"), name)
            state = {os.path.join(root, "profiles", "web"): {"spid-authoring", "mine"}}
            plan = ss.hermes_plan(json.loads(json.dumps(POLICY)), {"hermes": {}}, root,
                                  lambda home: set(state.get(home, set())))
            rows = {row["profile"]: row for row in plan["profiles"]}
            self.assertEqual(rows["roblox"]["add"], ["skyrim-nif", "spid-authoring"])
            self.assertEqual(rows["skyrim"]["add"], ["roblox-ui"])
            self.assertEqual(rows["web"]["add"], ["roblox-ui", "skyrim-nif"], "already disabled is not re-added")
            for row in rows.values():
                self.assertNotIn("fictional-adult-modding", row["add"])
                self.assertNotIn("web-dev", row["add"])

    def test_profile_scoped_home_resolves_to_the_root(self):
        with mock.patch.dict(os.environ, {"HERMES_HOME": os.path.join("C:\\", "h", "profiles", "skyrim")}):
            self.assertEqual(os.path.normcase(ss.hermes_root()), os.path.normcase(os.path.join("C:\\", "h")))


class Policy(unittest.TestCase):
    def test_shipped_policy_loads_and_protects_adult_skills(self):
        policy = ss.load_policy()
        installed = {"fictional-adult-modding", "skyrim-sexlab-to-ostim-modernization", "spid-authoring",
                     "adult-character-sheet", "roblox-ui", "replica-recon", "replica-diff"}
        skyrim = ss.members(policy, "skyrim", installed)
        self.assertIn("spid-authoring", skyrim)
        self.assertNotIn("fictional-adult-modding", skyrim)
        self.assertNotIn("skyrim-sexlab-to-ostim-modernization", skyrim)
        for family in policy["families"]:
            self.assertNotIn("adult-character-sheet", ss.members(policy, family, installed))
        self.assertIn("replica-recon", policy["families"]["replica"]["keep_described"])


if __name__ == "__main__":
    unittest.main()
