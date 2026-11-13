"""Make installed apps and owner forges answer by name in every shell.

An agent types `blender`, `ffmpeg` or `assetforge` and expects a program. Three
things break that on a real PC and each one sends the agent off to download a
second copy of something already installed:

  * the app is installed but its folder was never added to PATH (Steam,
    portable and per-user installs do not add it);
  * a wrapper with the same name sits earlier on PATH and starts something else
    (a Hermes profile named `blender` creates `blender.bat`);
  * an owner forge is a checkout with a launcher inside it, so no name reaches it.

This tool finds the real program, reports what typing its name would start, and
with --fix makes the name work: it appends the app's folder to the user PATH,
renames a profile wrapper that shadows a real program to `hermes-<name>`, and
writes launchers for the forges the companion registry finds. Every PATH change
is backed up first and nothing is downloaded or installed.

    python TOOLS/app_paths.py                 report
    python TOOLS/app_paths.py --json          report as JSON (the machine map reads this)
    python TOOLS/app_paths.py --check         exit 1 when --fix would change something
    python TOOLS/app_paths.py --fix           apply
    python TOOLS/app_paths.py --fix --prune-dead    also drop user PATH folders that are gone
"""
import argparse
import fnmatch
import glob
import json
import os
import re
import shutil
import subprocess
import sys
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import companion_registry  # noqa: E402
import uabs_launch  # noqa: E402

IS_WIN = os.name == "nt"
PATHEXT = (".com", ".exe", ".bat", ".cmd")
LAUNCH_NAME = re.compile(r"^[a-z0-9][a-z0-9-]{1,39}$")
LAUNCH_EXT = (".cmd", ".bat", ".ps1", ".py", ".exe")

# Programs an agent starts by name. `exe` may be a pattern when the vendor puts
# a version in the file name; such an app gets a launcher instead of a PATH
# entry. `record_only` apps are listed in the machine map but not put on PATH.
APPS = (
    {"id": "blender", "command": "blender", "exe": ("blender.exe",), "env": "BLENDER_EXE",
     "uninstall": r"^blender\b",
     "globs": (r"%ProgramFiles%\Blender Foundation\*\blender.exe",
               r"%LOCALAPPDATA%\Programs\Blender Foundation\*\blender.exe"),
     "steam": ("Blender",), "portable": ("blender*/blender.exe", "*/blender*/blender.exe", "*/*/blender*/blender.exe"),
     "version": ("--version",)},
    {"id": "ffmpeg", "command": "ffmpeg", "exe": ("ffmpeg.exe",),
     "globs": (r"%LOCALAPPDATA%\Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe",
               r"%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe",
               r"%ProgramFiles%\ffmpeg\bin\ffmpeg.exe", r"%SystemDrive%\ffmpeg\bin\ffmpeg.exe",
               r"%USERPROFILE%\scoop\shims\ffmpeg.exe"),
     "portable": ("ffmpeg*/bin/ffmpeg.exe", "*/ffmpeg*/bin/ffmpeg.exe"), "version": ("-version",)},
    {"id": "godot", "command": "godot", "exe": ("Godot*_console.exe", "Godot*.exe", "godot.windows.*.exe"),
     "globs": (r"%LOCALAPPDATA%\Programs\Godot\Godot*.exe", r"%ProgramFiles%\Godot\Godot*.exe"),
     "steam": ("Godot Engine",), "portable": ("godot*/Godot*.exe", "*/godot*/Godot*.exe"),
     "version": ("--version",)},
    {"id": "gimp", "command": "gimp-console", "exe": ("gimp-console-*.exe", "gimp-console.exe"),
     "uninstall": r"^gimp\b", "subdir": "bin",
     "globs": (r"%ProgramFiles%\GIMP *\bin\gimp-console-*.exe",
               r"%LOCALAPPDATA%\Programs\GIMP *\bin\gimp-console-*.exe"),
     "version": ("--version",)},
    {"id": "krita", "command": "krita", "exe": ("krita.exe",), "uninstall": r"^krita\b", "subdir": "bin",
     "globs": (r"%ProgramFiles%\Krita (x64)\bin\krita.exe",), "version": ()},
    {"id": "inkscape", "command": "inkscape", "exe": ("inkscape.exe",), "uninstall": r"^inkscape\b", "subdir": "bin",
     "globs": (r"%ProgramFiles%\Inkscape\bin\inkscape.exe",), "version": ("--version",)},
    {"id": "imagemagick", "command": "magick", "exe": ("magick.exe",), "uninstall": r"^imagemagick\b",
     "globs": (r"%ProgramFiles%\ImageMagick-*\magick.exe",), "version": ("-version",)},
    {"id": "7zip", "command": "7z", "exe": ("7z.exe",), "uninstall": r"^7-zip\b",
     "globs": (r"%ProgramFiles%\7-Zip\7z.exe",), "version": ()},
    {"id": "unity-cli", "command": "unity", "exe": ("unity.exe",),
     "globs": (r"%LOCALAPPDATA%\Unity\bin\unity.exe",), "version": ("--version",)},
    {"id": "codebase-memory-mcp", "command": "codebase-memory-mcp", "exe": ("codebase-memory-mcp.exe",),
     "env": "CODEBASE_MEMORY_MCP", "env_readonly": True,
     "globs": (r"%LOCALAPPDATA%\Programs\codebase-memory-mcp\codebase-memory-mcp.exe",),
     "version": ("--version",)},
    {"id": "msbuild", "command": "msbuild", "exe": ("MSBuild.exe",), "record_only": True, "vswhere": True,
     "version": ("-version", "-nologo")},
)

# Folders a tool creates the first time it installs something. Missing today is
# not dead, so --prune-dead keeps them.
LAZY_PATH = re.compile(r"(?i)[\\/](\.dotnet[\\/]tools|go[\\/]bin|\.cargo[\\/]bin|npm|\.local[\\/]bin|"
                       r"scoop[\\/]shims|\.bun[\\/]bin|\.deno[\\/]bin|pnpm|WindowsApps)[\\/]?$")
HERMES_WRAPPER = re.compile(r"(?im)^\s*@?\s*hermes(?:\.exe)?\s+-p\s+(\S+)\s+%\*\s*$")


def state_root():
    base = os.environ.get("LOCALAPPDATA") if IS_WIN else os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(base or os.path.expanduser("~"), "Ultimate-AI-Starter-Bundle")


def expand(value):
    return os.path.expanduser(os.path.expandvars(value)) if value else ""


def same(a, b):
    return os.path.normcase(os.path.normpath(a)) == os.path.normcase(os.path.normpath(b))


def split_path(value, sep=";"):
    return [part.strip() for part in (value or "").split(sep) if part.strip()]


# --------------------------------------------------------------- PATH stores ---
class RegistryStore:
    """The PATH new processes get on Windows: machine value, then user value."""
    sep = ";"
    writable = True

    def __init__(self):
        import winreg
        self.reg = winreg
        self.user, self.user_type = self._read(winreg.HKEY_CURRENT_USER, "Environment", "Path")
        self.machine, _ = self._read(winreg.HKEY_LOCAL_MACHINE,
                                     r"SYSTEM\CurrentControlSet\Control\Session Manager\Environment", "Path")

    def _read(self, hive, sub, name):
        try:
            with self.reg.OpenKey(hive, sub) as key:
                value, kind = self.reg.QueryValueEx(key, name)
                return str(value), kind
        except OSError:
            return "", self.reg.REG_EXPAND_SZ

    def env(self, name):
        value, _ = self._read(self.reg.HKEY_CURRENT_USER, "Environment", name)
        return value or os.environ.get(name, "")

    def _write(self, name, value, kind):
        with self.reg.OpenKey(self.reg.HKEY_CURRENT_USER, "Environment", 0, self.reg.KEY_SET_VALUE) as key:
            self.reg.SetValueEx(key, name, 0, kind, value)
        self._announce()

    @staticmethod
    def _announce():
        # Tell running shells and Explorer that the environment changed.
        try:
            import ctypes
            result = ctypes.c_ulong()
            ctypes.windll.user32.SendMessageTimeoutW(0xFFFF, 0x1A, 0, "Environment", 0x2, 5000, ctypes.byref(result))
        except Exception:  # noqa: BLE001 - a missed broadcast only delays pickup until the next sign-in
            pass

    def save_path(self, value):
        # The existing value type is kept: REG_EXPAND_SZ entries hold %VARIABLES%.
        self._write("Path", value, self.user_type)
        self.user = value

    def set_env(self, name, value):
        self._write(name, value, self.reg.REG_SZ)


class FileStore:
    """A JSON stand-in for the registry, so tests never touch the real PATH."""
    sep = ";"
    writable = True

    def __init__(self, path):
        self.path = path
        with open(path, encoding="utf-8") as handle:
            data = json.load(handle)
        self.user, self.machine = data.get("user", ""), data.get("machine", "")
        self.vars = dict(data.get("env") or {})

    def env(self, name):
        return self.vars.get(name, "")

    def _flush(self):
        with open(self.path, "w", encoding="utf-8") as handle:
            json.dump({"user": self.user, "machine": self.machine, "env": self.vars}, handle, indent=1)

    def save_path(self, value):
        self.user = value
        self._flush()

    def set_env(self, name, value):
        self.vars[name] = value
        self._flush()


class ProcessStore:
    """Other systems: report against the process PATH; nothing is rewritten."""
    writable = False

    def __init__(self):
        self.sep = os.pathsep
        self.user, self.machine = os.environ.get("PATH", ""), ""

    def env(self, name):
        return os.environ.get(name, "")

    def save_path(self, value):
        raise OSError("PATH is edited in the shell profile on this system")

    set_env = save_path


def open_store(path_store=None):
    if path_store:
        return FileStore(path_store)
    return RegistryStore() if IS_WIN else ProcessStore()


def path_dirs(store):
    seen, out = set(), []
    for entry in split_path(store.machine, store.sep) + split_path(store.user, store.sep):
        folder = expand(entry)
        key = os.path.normcase(os.path.normpath(folder))
        if key not in seen:
            seen.add(key)
            out.append(folder)
    return out


def resolve(name, dirs):
    """What cmd and PowerShell start for a bare name: first folder, then PATHEXT order."""
    for folder in dirs:
        for ext in PATHEXT:
            candidate = os.path.join(folder, name + ext)
            if os.path.isfile(candidate):
                return candidate
    return None


def resolve_posix(name, dirs):
    """What a POSIX shell (Git Bash) starts: an extensionless script or name.exe."""
    for folder in dirs:
        for candidate in (os.path.join(folder, name), os.path.join(folder, name + ".exe")):
            if os.path.isfile(candidate):
                return candidate
    return None


# ----------------------------------------------------------------- discovery ---
def _uninstall_rows():
    rows = []
    if not IS_WIN:
        return rows
    import winreg
    for hive, sub in ((winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall"),
                      (winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"),
                      (winreg.HKEY_CURRENT_USER, r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall")):
        try:
            root = winreg.OpenKey(hive, sub)
        except OSError:
            continue
        with root:
            for index in range(winreg.QueryInfoKey(root)[0]):
                try:
                    with winreg.OpenKey(root, winreg.EnumKey(root, index)) as key:
                        name = winreg.QueryValueEx(key, "DisplayName")[0]
                        where = winreg.QueryValueEx(key, "InstallLocation")[0]
                except OSError:
                    continue
                if name and where:
                    rows.append((str(name), str(where).strip('"')))
    return rows


def _steam_commons():
    out = []
    if not IS_WIN:
        return out
    import winreg
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Software\Valve\Steam") as key:
            steam = str(winreg.QueryValueEx(key, "SteamPath")[0]).replace("/", "\\")
    except OSError:
        return out
    libraries = [steam]
    try:
        with open(os.path.join(steam, "steamapps", "libraryfolders.vdf"), encoding="utf-8", errors="replace") as handle:
            libraries += [m.replace("\\\\", "\\") for m in re.findall(r'"path"\s+"([^"]+)"', handle.read())]
    except OSError:
        pass
    for library in libraries:
        common = os.path.join(library, "steamapps", "common")
        if os.path.isdir(common) and not any(same(common, known) for known in out):
            out.append(common)
    return out


def _vswhere_msbuild():
    finder = expand(r"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe")
    if not os.path.isfile(finder):
        return []
    try:
        done = subprocess.run([finder, "-latest", "-products", "*", "-requires", "Microsoft.Component.MSBuild",
                               "-find", r"MSBuild\**\Bin\MSBuild.exe"],
                              capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return []
    return [line.strip() for line in done.stdout.splitlines() if line.strip() and os.path.isfile(line.strip())]


class Machine:
    """Where to look. Tests pass isolated=True and their own folders."""

    def __init__(self, isolated=False, search_roots=None, tool_roots=None):
        self.isolated = isolated
        self.search_roots = list(search_roots or [])
        self._uninstall = None
        self._steam = None
        self._tool_roots = tool_roots

    def uninstall(self):
        if self._uninstall is None:
            self._uninstall = [] if self.isolated else _uninstall_rows()
        return self._uninstall

    def steam(self):
        if self._steam is None:
            self._steam = [] if self.isolated else _steam_commons()
        return self._steam

    def tool_roots(self):
        if self._tool_roots is None:
            # The registry's default roots are whole profile folders; portable
            # apps are looked for only where the user keeps tool checkouts.
            declared = [] if self.isolated else [
                root for root in companion_registry.roots()
                if not any(same(root, expand(default)) for default in companion_registry.DEFAULT_ROOTS if default)]
            self._tool_roots = self.search_roots + declared
        return self._tool_roots


def _matches(folder, patterns):
    found = []
    for pattern in patterns:
        found += [p for p in glob.glob(os.path.join(folder, pattern)) if os.path.isfile(p)]
        if found:
            break
    return sorted(found)


def _best(paths):
    """Newest-looking file of a versioned name; a console build wins for CLI use."""
    paths = sorted(set(paths), key=lambda p: os.path.basename(p).lower())
    console = [p for p in paths if "console" in os.path.basename(p).lower()]
    return (console or paths)[-1] if paths else None


def candidates(app, store, machine):
    """Every place this app was found, best first: (path, source)."""
    out = []

    def add(path, source):
        if path and os.path.isfile(path) and not any(same(path, known) for known, _ in out):
            out.append((os.path.normpath(path), source))

    env_name = app.get("env")
    if env_name:
        value = expand(store.env(env_name).strip('"'))
        if value and any(fnmatch.fnmatch(os.path.basename(value).lower(), pat.lower()) for pat in app["exe"]):
            add(value, "environment")
    for folder in path_dirs(store):
        add(_best(_matches(folder, app["exe"])), "path")
    if app.get("vswhere") and not machine.isolated:
        for path in _vswhere_msbuild():
            add(path, "installed")
    if app.get("uninstall"):
        for name, where in machine.uninstall():
            if re.search(app["uninstall"], name, re.I):
                folder = os.path.join(where, app["subdir"]) if app.get("subdir") else where
                add(_best(_matches(folder, app["exe"])), "installed")
    if not machine.isolated:
        for pattern in app.get("globs", ()):
            add(_best([p for p in glob.glob(expand(pattern)) if os.path.isfile(p)]), "installed")
    for common in machine.steam():
        for game in app.get("steam", ()):
            add(_best(_matches(os.path.join(common, game), app["exe"])), "installed")
    for root in machine.tool_roots():
        for pattern in app.get("portable", ()):
            add(_best([p for p in glob.glob(os.path.join(root, pattern)) if os.path.isfile(p)]), "portable")
    return out


def version_of(path, args, timeout=25):
    if not args:
        return None
    try:
        done = subprocess.run([path] + list(args), capture_output=True, text=True, timeout=timeout,
                              stdin=subprocess.DEVNULL, errors="replace")
    except (OSError, subprocess.SubprocessError):
        return None
    match = re.search(r"\d+\.\d+(?:\.\d+)*", (done.stdout or "") + "\n" + (done.stderr or ""))
    return match.group(0) if match else None


def hermes_wrapper(path):
    """The profile name when this file is a Hermes profile wrapper, else None."""
    if os.path.splitext(path)[1].lower() not in (".bat", ".cmd"):
        return None
    try:
        if os.path.getsize(path) > 2048:
            return None
        with open(path, encoding="utf-8", errors="replace") as handle:
            match = HERMES_WRAPPER.search(handle.read())
    except OSError:
        return None
    return match.group(1) if match else None


# -------------------------------------------------------------------- report ---
def forge_launchers(machine, data=None, statuses=None):
    """(name, companion id, launcher path) for every installed owner that declares one."""
    try:
        data = data or companion_registry.load()
    except (OSError, companion_registry.RegistryError):
        return []
    if statuses is None:
        roots = machine.search_roots if machine.isolated else companion_registry.roots(machine.search_roots)
        statuses = companion_registry.status(roots, data)
    out = []
    for cid, entry in sorted(data["companions"].items()):
        root = (statuses.get(cid) or {}).get("path")
        if not root or (statuses.get(cid) or {}).get("state") != "INSTALLED_UNVERIFIED":
            continue
        for launch in entry.get("launch") or []:
            path = os.path.join(root, launch["launcher"].replace("/", os.sep))
            row = {"name": launch["name"], "id": cid, "path": os.path.normpath(path), "root": root,
                   "exists": os.path.isfile(path)}
            if path.lower().endswith(".py"):
                # An owner that ships its own environment runs under that interpreter.
                for relative in (os.path.join(".venv", "Scripts", "python.exe"), os.path.join(".venv", "bin", "python")):
                    own = os.path.join(root, relative)
                    if os.path.isfile(own):
                        row["python"] = own
                        break
            out.append(row)
    return out


def survey(store, machine, shim_dir, versions=True, apps=APPS, registry=None, statuses=None):
    dirs = path_dirs(store)
    report = {"schema": 1, "shim_dir": shim_dir, "apps": [], "forges": [], "actions": [],
              "path": {"dead": [], "duplicates": []}}
    actions = report["actions"]
    add_dirs, launchers = [], {}

    def want_dir(folder):
        if not any(same(folder, known) for known in dirs + add_dirs):
            add_dirs.append(folder)
            actions.append({"kind": "path-add", "dir": folder})

    for app in apps:
        found = candidates(app, store, machine)
        row = {"id": app["id"], "command": app["command"], "path": None, "source": None, "version": None,
               "status": "missing", "others": [path for path, _ in found[1:]]}
        report["apps"].append(row)
        if not found:
            continue
        real, row["source"] = found[0]
        row["path"] = real
        if versions:
            row["version"] = version_of(real, app.get("version") or ())
        if app.get("record_only"):
            row["status"] = "recorded"
            continue
        direct = same(os.path.splitext(os.path.basename(real))[0], app["command"])
        hit = resolve(app["command"], dirs)
        row["resolves_to"] = hit
        shim = os.path.join(shim_dir, app["command"] + ".cmd")
        if hit and (same(hit, real) or same(hit, shim)):
            row["status"] = "ok"
        elif hit and hermes_wrapper(hit):
            row["status"] = "shadowed"
            row["shadow"] = {"path": hit, "profile": hermes_wrapper(hit)}
            actions.append({"kind": "rename-wrapper", "path": hit, "profile": hermes_wrapper(hit),
                            "command": app["command"]})
        elif hit and any(same(hit, other) for other, _ in found):
            row["status"] = "ok"            # another real copy answers; the owner chose it
            row["path"], row["others"] = hit, [p for p, _ in found if not same(p, hit)]
        elif hit:
            row["status"] = "shadowed"      # unknown wrapper: reported, never touched
            row["shadow"] = {"path": hit, "profile": None}
        else:
            row["status"] = "not-on-path"
        if row["status"] != "ok":
            if direct:
                want_dir(os.path.dirname(real))
            else:
                launchers[app["command"]] = {"path": real, "kind": "exe", "owner": app["id"]}
        elif not direct and same(hit, shim):
            launchers[app["command"]] = {"path": real, "kind": "exe", "owner": app["id"]}
        env_name = app.get("env")
        if env_name and not app.get("env_readonly"):
            current = expand(store.env(env_name).strip('"'))
            if not current or not os.path.isfile(current):
                actions.append({"kind": "env-set", "name": env_name, "value": real})

    for forge in forge_launchers(machine, registry, statuses):
        row = dict(forge, status="ok")
        report["forges"].append(row)
        if not forge["exists"]:
            row["status"] = "launcher-missing"
            continue
        hit = resolve(forge["name"], dirs)
        if hit and not same(os.path.dirname(hit), shim_dir):
            row["status"], row["provided_by"] = "provided", hit
            continue
        entry = {"path": forge["path"], "owner": forge["id"]}
        if forge.get("python"):
            entry["python"] = forge["python"]
        launchers[forge["name"]] = entry

    current = read_table(shim_dir)
    if launchers != current or (launchers and not shims_complete(shim_dir, launchers)):
        actions.append({"kind": "launchers", "launchers": launchers,
                        "remove": sorted(set(current) - set(launchers))})
    for row in report["forges"]:
        if row["status"] == "ok" and row["name"] not in current:
            row["status"] = "needs-launcher"
    if launchers:
        want_dir(shim_dir)
    report["launchers"] = launchers

    seen = set()
    for entry in split_path(store.user, store.sep):
        folder = expand(entry)
        key = os.path.normcase(os.path.normpath(folder))
        if key in seen:
            report["path"]["duplicates"].append(entry)
        seen.add(key)
        if _is_dead(folder):
            report["path"]["dead"].append(entry)
    report["pending"] = len(actions)
    return report


def _is_dead(folder):
    """Gone, on a drive that is present. An unplugged drive or a share is not dead."""
    if os.path.isdir(folder) or folder.startswith("\\\\"):
        return False
    home = os.path.normcase(os.path.expanduser("~"))
    if LAZY_PATH.search(folder) and os.path.normcase(folder).startswith(home):
        tail = os.path.normcase(folder)[len(home):].strip("\\/")
        if tail.count(os.sep) <= 3:      # ~/.dotnet/tools, ~/AppData/Roaming/npm: not a cache deep in a project
            return False
    drive = os.path.splitdrive(folder)[0]
    if IS_WIN and (not drive or not os.path.isdir(drive + os.sep)):
        return False
    try:
        os.listdir(os.path.dirname(folder.rstrip("\\/")) or folder)
    except PermissionError:
        return False        # unreadable is not the same as gone
    except OSError:
        pass
    return not os.path.exists(folder)


# --------------------------------------------------------------------- shims ---
def read_table(shim_dir):
    try:
        return uabs_launch.load(shim_dir)[1]
    except (OSError, ValueError):
        return {}


def shims_complete(shim_dir, launchers):
    wanted = [uabs_launch.TABLE, "uabs_launch.py"]
    for name in launchers:
        wanted += [name + ".cmd", name]
    return all(os.path.isfile(os.path.join(shim_dir, item)) for item in wanted)


CMD_SHIM = ("@echo off\r\n"
            "setlocal EnableExtensions DisableDelayedExpansion\r\n"
            "set \"UABS_PY=%UABS_PYTHON%\"\r\n"
            "if not defined UABS_PY set \"UABS_PY=python\"\r\n"
            "\"%UABS_PY%\" -I \"%~dp0uabs_launch.py\" {name} %*\r\n"
            "exit /b %ERRORLEVEL%\r\n")
SH_SHIM = ("#!/bin/sh\n"
           "exec \"${{UABS_PYTHON:-python}}\" -I \"$(dirname \"$0\")/uabs_launch.py\" {name} \"$@\"\n")


def write_launchers(shim_dir, launchers, remove=()):
    os.makedirs(shim_dir, exist_ok=True)
    for name in remove:
        for item in (name + ".cmd", name):
            try:
                os.remove(os.path.join(shim_dir, item))
            except OSError:
                pass
    shutil.copyfile(os.path.join(HERE, "uabs_launch.py"), os.path.join(shim_dir, "uabs_launch.py"))
    table = {"schema": 1, "repair": "python \"%s\" --fix" % os.path.join(HERE, "app_paths.py"),
             "launchers": launchers}
    temp = os.path.join(shim_dir, uabs_launch.TABLE + ".tmp")
    with open(temp, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(table, handle, indent=1, sort_keys=True)
    os.replace(temp, os.path.join(shim_dir, uabs_launch.TABLE))
    for name in launchers:
        with open(os.path.join(shim_dir, name + ".cmd"), "w", encoding="ascii", newline="") as handle:
            handle.write(CMD_SHIM.format(name=name))
        with open(os.path.join(shim_dir, name), "w", encoding="ascii", newline="") as handle:
            handle.write(SH_SHIM.format(name=name))


def rename_wrapper(action, hermes=None):
    """Move a profile wrapper off a real program's name. The profile itself is untouched."""
    path, profile = action["path"], action["profile"]
    target = os.path.join(os.path.dirname(path), "hermes-" + profile + os.path.splitext(path)[1])
    if hermes:
        try:
            subprocess.run([hermes, "profile", "alias", profile, "--remove"], capture_output=True, timeout=60)
            subprocess.run([hermes, "profile", "alias", profile, "--name", "hermes-" + profile],
                           capture_output=True, timeout=60)
        except (OSError, subprocess.SubprocessError):
            pass
    if os.path.isfile(path):
        if os.path.isfile(target):
            os.remove(path)
        else:
            os.replace(path, target)
    return target


def backup_path(store, backup_dir, reason):
    os.makedirs(backup_dir, exist_ok=True)
    name = os.path.join(backup_dir, "user-path-%s.json" % uuid.uuid4().hex)
    with open(name, "w", encoding="utf-8") as handle:
        json.dump({"schema": 1, "user_path": store.user, "reason": reason}, handle, indent=1)
    with open(name, encoding="utf-8") as handle:
        if json.load(handle)["user_path"] != store.user:
            raise OSError("PATH backup did not read back; PATH was left unchanged")
    return name


def apply(report, store, shim_dir, backup_dir, prune_dead=False, hermes=None):
    """Carry out the report's actions. Returns the lines to show."""
    done = []
    if not store.writable:
        return ["PATH is not rewritten on this system; add the folders above to your shell profile."]
    add = [a["dir"] for a in report["actions"] if a["kind"] == "path-add"]
    entries = split_path(store.user, store.sep)
    kept, seen, dropped = [], set(), []
    for entry in entries:
        folder = expand(entry)
        key = os.path.normcase(os.path.normpath(folder))
        if prune_dead and (key in seen or entry in report["path"]["dead"]):
            dropped.append(entry)
            continue
        seen.add(key)
        kept.append(entry)
    updated = store.sep.join(kept + [d for d in add if os.path.normcase(os.path.normpath(d)) not in seen])
    for action in report["actions"]:
        if action["kind"] == "launchers":
            write_launchers(shim_dir, action["launchers"], action.get("remove") or ())
            done.append("launchers written: " + (", ".join(sorted(action["launchers"])) or "none"))
        elif action["kind"] == "rename-wrapper":
            target = rename_wrapper(action, hermes)
            done.append("%s no longer shadows the real program; the Hermes profile '%s' starts with %s (or hermes -p %s)"
                        % (os.path.basename(action["path"]), action["profile"],
                           os.path.splitext(os.path.basename(target))[0], action["profile"]))
        elif action["kind"] == "env-set":
            store.set_env(action["name"], action["value"])
            done.append("%s = %s" % (action["name"], action["value"]))
    if updated != store.user:
        saved = backup_path(store, backup_dir, "app_paths")
        before = store.user
        store.save_path(updated)
        if store.user != updated:
            store.save_path(before)
            raise OSError("PATH did not read back after the change; the original was restored")
        for folder in add:
            done.append("added to user PATH: " + folder)
        for entry in dropped:
            done.append("removed from user PATH (folder is gone or listed twice): " + entry)
        done.append("previous user PATH saved at " + saved)
    return done


# ----------------------------------------------------------------------- cli ---
def render(report):
    lines = []
    for row in report["apps"]:
        if row["status"] == "missing":
            continue
        note = {"ok": "answers by name", "recorded": "not put on PATH; use this path",
                "not-on-path": "installed, not on PATH", "shadowed": "another file answers first: %s"
                % ((row.get("shadow") or {}).get("path") or "?")}[row["status"]]
        lines.append("%-20s %-12s %s  (%s)" % (row["command"], row["version"] or "-", row["path"], note))
    missing = [row["command"] for row in report["apps"] if row["status"] == "missing"]
    if missing:
        lines.append("not installed: " + ", ".join(missing))
    for row in report["forges"]:
        lines.append("%-20s %-12s %s  (%s)" % (row["name"], row["id"], row["path"], row["status"]))
    if report["path"]["dead"]:
        lines.append("user PATH folders that are gone: " + "; ".join(report["path"]["dead"]))
    lines.append("%d change(s) pending" % report["pending"] if report["pending"] else "nothing to change")
    return "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Make installed apps and owner forges answer by name")
    ap.add_argument("--fix", action="store_true", help="apply the changes the report lists")
    ap.add_argument("--check", action="store_true", help="exit 1 when --fix would change something")
    ap.add_argument("--json", action="store_true", help="machine-readable report")
    ap.add_argument("--prune-dead", action="store_true", help="with --fix: drop user PATH folders that no longer exist")
    ap.add_argument("--no-version", action="store_true", help="skip running each app for its version")
    ap.add_argument("--path-store", help="JSON file standing in for the registry PATH (tests)")
    ap.add_argument("--shim-dir", help="command folder (default: the bundle state folder's bin)")
    ap.add_argument("--search-root", action="append", default=[], help="extra folder to search for portable apps and forges")
    ap.add_argument("--isolated", action="store_true", help="search only --search-root (tests)")
    args = ap.parse_args(argv)

    store = open_store(args.path_store)
    shim_dir = args.shim_dir or os.path.join(state_root(), "bin")
    machine = Machine(isolated=args.isolated, search_roots=args.search_root)
    report = survey(store, machine, shim_dir, versions=not args.no_version)
    if args.prune_dead:
        report["pending"] += len(report["path"]["dead"]) + len(report["path"]["duplicates"])
    applied = []
    if args.fix and report["pending"]:
        hermes = None if args.path_store else shutil.which("hermes")
        backup_dir = os.path.join(os.path.dirname(shim_dir), "backups")
        applied = apply(report, store, shim_dir, backup_dir, prune_dead=args.prune_dead, hermes=hermes)
        store = open_store(args.path_store)
        report = survey(store, machine, shim_dir, versions=not args.no_version)
    report["applied"] = applied
    if args.json:
        print(json.dumps(report, indent=1))
    else:
        print(render(report))
        for line in applied:
            print("  " + line)
        if applied:
            print("Restart AI apps and terminals opened before this change; they keep the PATH they started with.")
    return 1 if args.check and report["pending"] else 0


if __name__ == "__main__":
    sys.exit(main())
