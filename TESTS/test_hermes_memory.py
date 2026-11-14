"""A frozen machine map must leave Hermes memory; everything else must stay.

Runs standalone (`python TESTS/test_hermes_memory.py`) and under pytest.
"""
import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(HERE), "TOOLS"))

import hermes_memory as hm  # noqa: E402

SEP = hm.SEPARATOR
PACK = ["<!-- UABS-PACK:skyrim -->",
        "Skyrim pack: Start every substantial task with the router.",
        "Skyrim pack > Ownership of tooling: doing other work, leave it off. <!-- /UABS-PACK:skyrim -->"]
FROZEN = ["Skyrim pack > Ownership of tooling: <!-- UABS-PROFILE -->",
          "Skyrim pack > Machine map (generated 2026-01-01 by the bundle installer): This bundle: C:\\Old\\Bundle",
          "Skyrim pack > Machine map (generated 2026-01-01 by the bundle installer): Python: C:\\Old\\python.exe",
          "Skyrim pack > Machine map (generated 2026-01-01 by the bundle installer): <!-- /UABS-PROFILE -->"]
AFTER = ["Skyrim pack > Personal working agreements: Inspect the project before editing."]
OWN = ["The user prefers metric units.", "Project Alpha: its build needs the 2022 toolset.\nSecond line."]


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text)
    return path


def read(path):
    with open(path, encoding="utf-8") as handle:
        return handle.read()


class Classify(unittest.TestCase):
    def test_only_the_block_between_the_profile_markers_is_replaced(self):
        kept, dropped = hm.classify(SEP.join(PACK + FROZEN + AFTER + OWN))
        self.assertEqual(dropped, FROZEN)
        self.assertEqual(kept, PACK + [hm.POINTER] + AFTER + OWN)

    def test_the_pointer_names_the_live_file_and_carries_no_marker(self):
        self.assertIn("MACHINE-MAP.md", hm.POINTER)
        self.assertEqual(hm.classify(hm.POINTER)[1], [], "a cleaned file is not found again")

    def test_a_file_without_the_profile_markers_is_never_touched(self):
        text = SEP.join(PACK + AFTER + OWN + ["Machine map: I drew one by hand"])
        kept, dropped = hm.classify(text)
        self.assertEqual(dropped, [])
        self.assertEqual(SEP.join(kept), text)

    def test_a_block_that_never_closes_is_left_alone(self):
        text = SEP.join(PACK + FROZEN[:2] + OWN)
        kept, dropped = hm.classify(text)
        self.assertEqual(dropped, [])
        self.assertEqual(SEP.join(kept), text)


class Fix(unittest.TestCase):
    def test_every_profile_is_fixed_with_a_backup_and_a_second_run_is_quiet(self):
        with tempfile.TemporaryDirectory() as home:
            original = SEP.join(PACK + FROZEN + AFTER) + "\n"
            default = write(os.path.join(home, "memories", "MEMORY.md"), original)
            mixed = write(os.path.join(home, "profiles", "code", "memories", "MEMORY.md"),
                          SEP.join(FROZEN + OWN) + "\n")
            user = write(os.path.join(home, "profiles", "code", "memories", "USER.md"), "Likes short answers.\n")
            self.assertEqual(hm.main(["--home", home]), 1, "a report with findings is not a pass")
            self.assertEqual(hm.main(["--home", home, "--fix"]), 0)
            self.assertEqual(read(default), SEP.join(PACK + [hm.POINTER] + AFTER) + "\n")
            self.assertEqual(read(mixed), SEP.join([hm.POINTER] + OWN) + "\n")
            self.assertEqual(read(user), "Likes short answers.\n")
            self.assertNotIn("C:\\Old", read(default))
            backups = [name for name in os.listdir(os.path.dirname(default)) if ".before-import-cleanup-" in name]
            self.assertEqual(len(backups), 1)
            self.assertEqual(read(os.path.join(os.path.dirname(default), backups[0])), original)
            self.assertEqual(hm.main(["--home", home]), 0)

    def test_hermes_trash_folder_is_never_read_or_fixed(self):
        with tempfile.TemporaryDirectory() as home:
            trashed = write(os.path.join(home, "profiles", ".deleted", "memories", "MEMORY.md"),
                            SEP.join(FROZEN + OWN) + "\n")
            self.assertNotIn(trashed, hm.memory_files(home))

    def test_a_missing_home_is_not_an_error(self):
        self.assertEqual(hm.main(["--home", os.path.join(tempfile.gettempdir(), "no-hermes-here-uabs")]), 0)


if __name__ == "__main__":
    unittest.main(verbosity=1)
