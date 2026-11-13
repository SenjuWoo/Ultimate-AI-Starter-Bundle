"""Apps and owner forges must answer by name, and fixing that must be safe.

Every test works on a temporary folder and a JSON stand-in for the registry
PATH, so the real PATH is never read or written.

Runs standalone (`python TESTS/test_app_paths.py`) and under pytest.
"""
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, os.path.join(ROOT, "TOOLS"))

import app_paths  # noqa: E402
import companion_registry as reg  # noqa: E402
import uabs_launch  # noqa: E402

BLENDER = ({"id": "blender", "command": "blender", "exe": ("blender.exe",), "env": "BLENDER_EXE",
            "portable": ("blender*/blender.exe",)},)
GODOT = ({"id": "godot", "command": "godot", "exe": ("Godot*_console.exe", "Godot*.exe"),
          "portable": ("godot*/Godot*.exe",)},)


def touch(path, text=""):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="") as handle:
        handle.write(text)
    return path


class Box:
    """One temporary machine: a tools folder, a bin folder on PATH and a PATH store."""

    def __init__(self, case):
        self.temp = tempfile.TemporaryDirectory()
        case.addCleanup(self.temp.cleanup)
        self.root = os.path.realpath(self.temp.name)
        self.tools = os.path.join(self.root, "tools")
        self.bin = os.path.join(self.root, "user bin")
        self.shims = os.path.join(self.root, "state", "bin")
        self.backups = os.path.join(self.root, "state", "backups")
        os.makedirs(self.tools)
        os.makedirs(self.bin)
        self.store_file = os.path.join(self.root, "path.json")
        self.write_store(self.bin)

    def write_store(self, user, env=None):
        with open(self.store_file, "w", encoding="utf-8") as handle:
            json.dump({"user": user, "machine": "", "env": env or {}}, handle)

    def store(self):
        return app_paths.FileStore(self.store_file)

    def machine(self):
        return app_paths.Machine(isolated=True, search_roots=[self.tools])

    def survey(self, apps=BLENDER, registry=None, statuses=None):
        return app_paths.survey(self.store(), self.machine(), self.shims, versions=False, apps=apps,
                                registry=registry or {"companions": {}}, statuses=statuses or {})

    def fix(self, apps=BLENDER, prune=False, registry=None, statuses=None):
        report = self.survey(apps, registry, statuses)
        lines = app_paths.apply(report, self.store(), self.shims, self.backups, prune_dead=prune)
        return report, lines, self.survey(apps, registry, statuses)


class InstalledButNotOnPath(unittest.TestCase):
    def test_the_real_folder_is_added_and_the_old_path_is_saved(self):
        box = Box(self)
        exe = touch(os.path.join(box.tools, "blender-5", "blender.exe"))
        before = box.survey()
        self.assertEqual(before["apps"][0]["status"], "not-on-path")
        self.assertEqual(before["apps"][0]["source"], "portable")
        _, lines, after = box.fix()
        self.assertEqual(after["apps"][0]["status"], "ok")
        self.assertTrue(app_paths.same(after["apps"][0]["resolves_to"], exe))
        self.assertIn(os.path.dirname(exe), app_paths.split_path(box.store().user))
        self.assertEqual(app_paths.split_path(box.store().user)[0], box.bin, "existing entries keep their order")
        saved = [f for f in os.listdir(box.backups) if f.startswith("user-path-")]
        self.assertEqual(len(saved), 1)
        with open(os.path.join(box.backups, saved[0]), encoding="utf-8") as handle:
            self.assertEqual(json.load(handle)["user_path"], box.bin)
        self.assertEqual(after["pending"], 0, "a second run has nothing to do")
        self.assertTrue(any("added to user PATH" in line for line in lines))

    def test_the_program_variable_is_set_once_and_a_valid_one_is_kept(self):
        box = Box(self)
        found = touch(os.path.join(box.tools, "blender-5", "blender.exe"))
        box.fix()
        self.assertTrue(app_paths.same(box.store().env("BLENDER_EXE"), found))
        # The owner points the variable at another copy: it is kept, and the
        # report still names what the bare command starts.
        chosen = touch(os.path.join(box.root, "mine", "blender.exe"))
        box.write_store(box.store().user, {"BLENDER_EXE": chosen})
        report = box.survey()
        self.assertTrue(app_paths.same(report["apps"][0]["path"], found))
        self.assertTrue(any(app_paths.same(other, chosen) for other in report["apps"][0]["others"]))
        self.assertFalse([a for a in report["actions"] if a["kind"] == "env-set"])
        self.assertEqual(report["pending"], 0)

    def test_nothing_installed_means_nothing_to_do(self):
        box = Box(self)
        report = box.survey()
        self.assertEqual(report["apps"][0]["status"], "missing")
        self.assertEqual(report["pending"], 0)


class ShadowedByAWrapper(unittest.TestCase):
    def test_a_profile_wrapper_named_like_the_app_is_moved_aside(self):
        box = Box(self)
        exe = touch(os.path.join(box.tools, "blender-5", "blender.exe"))
        wrapper = touch(os.path.join(box.bin, "blender.bat"), "@echo off\r\nhermes -p blender %*\r\n")
        before = box.survey()
        self.assertEqual(before["apps"][0]["status"], "shadowed")
        self.assertEqual(before["apps"][0]["shadow"]["profile"], "blender")
        _, lines, after = box.fix()
        self.assertFalse(os.path.exists(wrapper))
        self.assertTrue(os.path.isfile(os.path.join(box.bin, "hermes-blender.bat")), "the profile keeps a launcher")
        self.assertEqual(after["apps"][0]["status"], "ok")
        self.assertTrue(app_paths.same(after["apps"][0]["resolves_to"], exe))
        self.assertTrue(any("hermes -p blender" in line for line in lines))

    def test_a_wrapper_that_is_not_a_profile_launcher_is_reported_and_left_alone(self):
        box = Box(self)
        touch(os.path.join(box.tools, "blender-5", "blender.exe"))
        wrapper = touch(os.path.join(box.bin, "blender.cmd"), "@echo off\r\necho my own script\r\n")
        _, _, after = box.fix()
        self.assertTrue(os.path.isfile(wrapper))
        self.assertEqual(after["apps"][0]["status"], "shadowed")
        self.assertIsNone(after["apps"][0]["shadow"]["profile"])

    def test_wrapper_detection_reads_the_command_not_the_name(self):
        box = Box(self)
        self.assertEqual(app_paths.hermes_wrapper(touch(os.path.join(box.bin, "a.bat"), "@echo off\nhermes -p web %*\n")), "web")
        self.assertIsNone(app_paths.hermes_wrapper(touch(os.path.join(box.bin, "b.bat"), "hermes chat\n")))
        self.assertIsNone(app_paths.hermes_wrapper(touch(os.path.join(box.bin, "c.exe"), "hermes -p web %*\n")))


class VersionedProgramName(unittest.TestCase):
    def test_it_gets_a_launcher_because_its_folder_would_not_give_the_name(self):
        box = Box(self)
        touch(os.path.join(box.tools, "godot-4", "Godot_v4.5-stable_win64.exe"))
        console = touch(os.path.join(box.tools, "godot-4", "Godot_v4.5-stable_win64_console.exe"))
        _, _, after = box.fix(GODOT)
        table = uabs_launch.load(box.shims)[1]
        self.assertTrue(app_paths.same(table["godot"]["path"], console), "the console build is the CLI one")
        self.assertEqual(table["godot"]["kind"], "exe")
        for name in ("godot.cmd", "godot", "uabs_launch.py", "launchers.json"):
            self.assertTrue(os.path.isfile(os.path.join(box.shims, name)), name)
        self.assertIn(box.shims, app_paths.split_path(box.store().user))
        self.assertNotIn(os.path.dirname(console), app_paths.split_path(box.store().user))
        self.assertEqual(after["apps"][0]["status"], "ok")
        self.assertEqual(after["pending"], 0)


def _registry(launcher="forge.cmd", name="demo-forge"):
    return {"schema": 1, "owner_allowlist": ["github.com/SenjuWoo/"], "companions": {"demo": {
        "title": "Demo", "repo": "https://github.com/SenjuWoo/demo", "install": {"kind": "source_only"},
        "markers": [launcher], "platforms": ["windows"], "launch": [{"name": name, "launcher": launcher}]}}}


class ForgeLaunchers(unittest.TestCase):
    def test_an_installed_owner_gets_its_name_and_loses_it_when_it_is_gone(self):
        box = Box(self)
        root = os.path.join(box.tools, "Demo forge!")
        launcher = touch(os.path.join(root, "forge.cmd"), "@exit /b 0\r\n")
        statuses = {"demo": {"state": "INSTALLED_UNVERIFIED", "path": root}}
        before = box.survey((), _registry(), statuses)
        self.assertEqual(before["forges"][0]["status"], "needs-launcher")
        _, _, after = box.fix((), registry=_registry(), statuses=statuses)
        self.assertEqual(after["forges"][0]["status"], "ok")
        self.assertTrue(app_paths.same(uabs_launch.load(box.shims)[1]["demo-forge"]["path"], launcher))
        with open(os.path.join(box.shims, "demo-forge.cmd"), encoding="ascii") as handle:
            shim = handle.read()
        self.assertIn("DisableDelayedExpansion", shim)
        self.assertNotIn(root, shim, "no path is embedded in the batch file")
        # The owner is uninstalled: its command goes away with it.
        box.fix((), registry=_registry(), statuses={"demo": {"state": "NOT_FOUND", "path": None}})
        self.assertFalse(os.path.exists(os.path.join(box.shims, "demo-forge.cmd")))
        self.assertEqual(uabs_launch.load(box.shims)[1], {})

    def test_a_name_something_else_already_answers_is_not_overwritten(self):
        box = Box(self)
        root = os.path.join(box.tools, "Demo")
        touch(os.path.join(root, "forge.cmd"), "@exit /b 0\r\n")
        own = touch(os.path.join(box.bin, "demo-forge.cmd"), "@exit /b 0\r\n")
        report = box.survey((), _registry(), {"demo": {"state": "INSTALLED_UNVERIFIED", "path": root}})
        self.assertEqual(report["forges"][0]["status"], "provided")
        self.assertTrue(app_paths.same(report["forges"][0]["provided_by"], own))
        self.assertEqual(report["launchers"], {})

    def test_a_python_launcher_runs_under_the_owners_own_environment(self):
        box = Box(self)
        root = os.path.join(box.tools, "Demo")
        touch(os.path.join(root, "cli.py"))
        venv = touch(os.path.join(root, ".venv", "Scripts", "python.exe"))
        rows = app_paths.forge_launchers(box.machine(), _registry("cli.py"),
                                         {"demo": {"state": "INSTALLED_UNVERIFIED", "path": root}})
        self.assertTrue(app_paths.same(rows[0]["python"], venv))

    def test_registry_rejects_a_launcher_that_leaves_the_owner_or_is_not_a_command_name(self):
        for bad in ({"name": "demo forge", "launcher": "forge.cmd"}, {"name": "demo", "launcher": "../forge.cmd"},
                    {"name": "demo", "launcher": "notes.txt"}, {"name": "demo"}):
            data = _registry()
            data["companions"]["demo"]["launch"] = [bad]
            with self.assertRaises(reg.RegistryError, msg=str(bad)):
                reg.validate(data)
        twice = _registry()
        twice["companions"]["demo"]["launch"] *= 2
        with self.assertRaises(reg.RegistryError):
            reg.validate(twice)

    def test_shipped_registry_launch_names_are_valid_and_unique(self):
        data = reg.load()
        names = [item["name"] for entry in data["companions"].values() for item in entry.get("launch") or []]
        self.assertTrue(names)
        self.assertEqual(len(names), len(set(names)))
        taken = {app["command"] for app in app_paths.APPS}
        self.assertFalse(taken & set(names), "a forge name must not be an app's command")


class PruneDeadEntries(unittest.TestCase):
    def test_gone_and_repeated_folders_are_dropped_only_when_asked(self):
        box = Box(self)
        gone = os.path.join(box.root, "removed-sdk", "bin")
        lazy = os.path.join(os.path.expanduser("~"), ".dotnet", "tools-test-%d" % os.getpid())
        box.write_store(";".join([box.bin, gone, box.bin + os.sep]))
        report = box.survey(())
        self.assertEqual(report["path"]["dead"], [gone])
        self.assertEqual(len(report["path"]["duplicates"]), 1)
        app_paths.apply(report, box.store(), box.shims, box.backups, prune_dead=False)
        self.assertIn(gone, box.store().user, "without the switch PATH is left as found")
        lines = app_paths.apply(report, box.store(), box.shims, box.backups, prune_dead=True)
        self.assertEqual(app_paths.split_path(box.store().user), [box.bin])
        self.assertTrue(any("removed from user PATH" in line for line in lines))
        self.assertFalse(app_paths._is_dead(os.path.join(os.path.expanduser("~"), ".dotnet", "tools")),
                         "a folder a tool creates on first use is not dead")
        self.assertFalse(os.path.exists(lazy))

    def test_an_old_tool_cache_that_only_looks_like_a_lazy_folder_is_dead(self):
        box = Box(self)
        stale = os.path.join(box.root, "old-forge", "cache", ".dotnet", "tools")
        self.assertTrue(app_paths._is_dead(stale))


class CommandLine(unittest.TestCase):
    def test_check_fails_until_fixed(self):
        box = Box(self)
        touch(os.path.join(box.tools, "blender-5", "blender.exe"))
        common = ["--path-store", box.store_file, "--shim-dir", box.shims, "--isolated",
                  "--search-root", box.tools, "--no-version", "--json"]
        run = lambda *extra: subprocess.run([sys.executable, os.path.join(ROOT, "TOOLS", "app_paths.py")] + common + list(extra),
                                            capture_output=True, text=True)
        first = run("--check")
        self.assertEqual(first.returncode, 1, first.stdout + first.stderr)
        fixed = run("--fix")
        self.assertEqual(fixed.returncode, 0, fixed.stdout + fixed.stderr)
        self.assertTrue(json.loads(fixed.stdout)["applied"])
        self.assertEqual(run("--check").returncode, 0)


class Launcher(unittest.TestCase):
    def test_arguments_cmd_would_act_on_are_quoted(self):
        self.assertEqual(uabs_launch.quote("plain"), "plain")
        self.assertEqual(uabs_launch.quote("a b"), '"a b"')
        self.assertEqual(uabs_launch.quote("x&y"), '"x&y"')
        self.assertEqual(uabs_launch.quote(""), '""')
        self.assertEqual(uabs_launch.quote('say "hi"'), '"say \\"hi\\""')
        self.assertEqual(uabs_launch.quote("C:\\dir with space\\"), '"C:\\dir with space\\\\"')

    def test_each_kind_starts_the_right_process(self):
        cmd = uabs_launch.command_for({"path": "C:\\My Tools!\\forge.cmd"}, ["doctor", "a b"])
        self.assertIsInstance(cmd, str)
        self.assertIn('/d /v:off /s /c ""C:\\My Tools!\\forge.cmd" doctor "a b""', cmd)
        ps1 = uabs_launch.command_for({"path": "C:\\t\\run.ps1"}, ["--out", "x"])
        self.assertEqual(ps1[1:], ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "C:\\t\\run.ps1", "--out", "x"])
        self.assertEqual(uabs_launch.command_for({"path": "C:\\t\\cli.py"}, ["x"]), [sys.executable, "C:\\t\\cli.py", "x"])
        self.assertEqual(uabs_launch.command_for({"path": "C:\\t\\app.exe", "kind": "exe"}, []), ["C:\\t\\app.exe"])

    def test_a_missing_target_says_how_to_repair_it(self):
        with tempfile.TemporaryDirectory() as temp:
            with open(os.path.join(temp, "launchers.json"), "w", encoding="utf-8") as handle:
                json.dump({"launchers": {"gone": {"path": os.path.join(temp, "nope.cmd")}}, "repair": "REPAIR-HINT"}, handle)
            import shutil
            shutil.copyfile(os.path.join(ROOT, "TOOLS", "uabs_launch.py"), os.path.join(temp, "uabs_launch.py"))
            run = lambda name: subprocess.run([sys.executable, os.path.join(temp, "uabs_launch.py"), name],
                                              capture_output=True, text=True)
            gone = run("gone")
            self.assertEqual(gone.returncode, 127)
            self.assertIn("REPAIR-HINT", gone.stderr)
            self.assertEqual(run("unknown").returncode, 127)

    @unittest.skipUnless(os.name == "nt", "cmd launchers are a Windows path")
    def test_a_written_launcher_passes_arguments_through_an_awkward_folder(self):
        box = Box(self)
        root = os.path.join(box.tools, "Demo forge! (x86)")
        # The exit code proves each argument arrived whole; console text is not compared.
        touch(os.path.join(root, "forge.cmd"),
              "@echo off\r\nsetlocal DisableDelayedExpansion\r\n"
              "if not \"%~1\"==\"a b\" exit /b 11\r\n"
              "if not \"%~2\"==\"x&y\" exit /b 12\r\n"
              "if not \"%~3\"==\"!z\" exit /b 13\r\n"
              "exit /b 7\r\n")
        box.fix((), registry=_registry(), statuses={"demo": {"state": "INSTALLED_UNVERIFIED", "path": root}})
        env = dict(os.environ, UABS_PYTHON=sys.executable)
        line = uabs_launch.command_for({"path": os.path.join(box.shims, "demo-forge.cmd")}, ["a b", "x&y", "!z"])
        self.assertEqual(subprocess.run(line, env=env, capture_output=True).returncode, 7)


if __name__ == "__main__":
    unittest.main(verbosity=1)
