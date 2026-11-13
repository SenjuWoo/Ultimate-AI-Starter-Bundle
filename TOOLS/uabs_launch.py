"""Run an installed app or owner forge by the name it was registered under.

`app_paths.py --fix` copies this file next to `launchers.json` in the bundle's
command folder and writes one tiny `<name>.cmd` and one `<name>` shell script
per entry. Both call this file, so the real location lives in one JSON table:
a moved checkout is repaired by rewriting the table, and no path is embedded in
a batch file where the console code page or a `!` could damage it.

    python uabs_launch.py <name> [arguments...]
"""
import json
import os
import re
import subprocess
import sys

TABLE = "launchers.json"
_NEEDS_QUOTES = re.compile(r'[\s"&|<>^()]')


def quote(arg):
    """One argument for a cmd.exe command line.

    list2cmdline quotes only on whitespace; cmd also acts on & | < > ^ ( ), so
    an argument holding one of those is quoted too.
    """
    if arg and not _NEEDS_QUOTES.search(arg):
        return arg
    out, slashes = '"', 0
    for ch in arg:
        if ch == "\\":
            slashes += 1
        elif ch == '"':
            out += "\\" * (2 * slashes + 1) + '"'
            slashes = 0
        else:
            out += "\\" * slashes + ch
            slashes = 0
    return out + "\\" * (2 * slashes) + '"'


def kind_of(path, declared=None):
    if declared:
        return declared
    ext = os.path.splitext(path)[1].lower()
    return {".cmd": "cmd", ".bat": "cmd", ".ps1": "ps1", ".py": "py"}.get(ext, "exe")


def command_for(entry, args):
    """The process to start: an argv list, or one string for cmd.exe."""
    path = entry["path"]
    kind = kind_of(path, entry.get("kind"))
    if kind == "cmd":
        # The whole line sits in one extra pair of quotes and /s strips exactly
        # that pair; /v:off keeps a '!' in a path or an argument literal.
        line = " ".join(quote(part) for part in [path] + list(args))
        return '"%s" /d /v:off /s /c "%s"' % (os.environ.get("COMSPEC") or "cmd.exe", line)
    if kind == "ps1":
        shell = entry.get("shell") or "powershell.exe"
        return [shell, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", path] + list(args)
    if kind == "py":
        python = entry.get("python")
        if not python or not os.path.isfile(python):
            python = sys.executable
        return [python, path] + list(args)
    return [path] + list(args)


def load(folder):
    with open(os.path.join(folder, TABLE), encoding="utf-8") as handle:
        table = json.load(handle)
    launchers = table.get("launchers")
    if not isinstance(launchers, dict):
        raise ValueError("no launchers table")
    return table, launchers


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    here = os.path.dirname(os.path.abspath(__file__))
    if not argv:
        print("usage: uabs_launch.py <name> [arguments...]", file=sys.stderr)
        return 2
    name, args = argv[0], argv[1:]
    try:
        table, launchers = load(here)
    except (OSError, ValueError) as exc:
        print("%s: the launcher table is unreadable (%s). Rerun the bundle installer." % (name, exc), file=sys.stderr)
        return 127
    entry = launchers.get(name)
    if not isinstance(entry, dict) or not entry.get("path"):
        print("%s: not a registered command. Known: %s" % (name, ", ".join(sorted(launchers)) or "none"), file=sys.stderr)
        return 127
    if not os.path.isfile(entry["path"]):
        repair = table.get("repair") or "the bundle's TOOLS/app_paths.py --fix"
        print("%s: its target is gone: %s\nIt was moved or removed. Repair the table with: %s"
              % (name, entry["path"], repair), file=sys.stderr)
        return 127
    try:
        return subprocess.call(command_for(entry, args))
    except KeyboardInterrupt:
        return 130
    except OSError as exc:
        print("%s: could not start %s (%s)" % (name, entry["path"], exc), file=sys.stderr)
        return 126


if __name__ == "__main__":
    sys.exit(main())
