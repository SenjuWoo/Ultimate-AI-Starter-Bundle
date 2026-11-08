"""Turn Ponytail on or off for every installed provider, from one place.

Ponytail's default is OFF: fresh installs park it so no minimalism instructions
reach a model until the operator asks. Nothing here edits upstream files - the
plugin stays installed (its UI stays usable) and its copied skills are parked in
the bundle's own folder rather than deleted.

    python TOOLS/ponytail_mode.py status          # what is effective now
    python TOOLS/ponytail_mode.py off|lite|full|ultra [--apply]
    python TOOLS/ponytail_mode.py init            # install-time: OFF only if never chosen

Levels above "off" gate ON; the level itself is set inside the plugin (its own
command, e.g. `/ponytail full`), because that is where upstream reads it.
AUTO is implemented next door, in TOOLS/hooks/ponytail_auto.py: a deterministic
classifier decides off/lite/full from the prompt itself and a prompt-time hook
delivers that instruction. Providers with no reliable prompt hook stay OFF and
keep the manual commands, so "auto" here means "do not park the skills".
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

STATE = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Ultimate-AI-Starter-Bundle" / "ponytail-mode.json"
PARKED = STATE.parent / "parked" / "ponytail"
SKILL_PREFIX = "ponytail"
LEVELS = ("off", "lite", "full", "ultra", "auto")


def provider_homes(home=None):
    home = Path(home or Path.home())
    local = Path(os.environ.get("LOCALAPPDATA", home / "AppData" / "Local"))
    homes = {
        "Claude": home / ".claude",
        "Codex": home / ".agents",
        "Grok": home / ".grok",
        "Kimi": home / ".kimi-code",
        "Antigravity": home / ".gemini" ,
        "Hermes": local / "hermes",
    }
    # Hermes loads skills from the shared root *and* from every profile root.
    profiles = homes["Hermes"] / "profiles"
    if profiles.is_dir():
        for profile in sorted(profiles.iterdir()):
            if (profile / "skills").is_dir():
                homes["Hermes/%s" % profile.name] = profile
    return homes


def _skills_dir(home_dir):
    return (home_dir / "skills") if home_dir.name != "config" else (home_dir / "skills")


def installed_skill_dirs(home_dir):
    """Ponytail* skill folders under a provider home."""
    found, base = [], home_dir / "skills"
    if not base.is_dir():
        return found
    for child in sorted(base.iterdir()):
        if child.is_dir() and child.name.startswith(SKILL_PREFIX):
            found.append(child)
    return found


def claude_enabled(home_dir):
    settings = home_dir / "settings.json"
    if not settings.exists():
        return None
    try:
        data = json.loads(settings.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return None
    for key, value in (data.get("enabledPlugins") or {}).items():
        if SKILL_PREFIX in key.lower():
            return bool(value)
    return None


def read_state(path=None):
    path = Path(path or STATE)
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def status(home=None):
    state = read_state()
    mode = state.get("mode", "off")
    homes = provider_homes(home)
    rows = {}
    for name, home_dir in homes.items():
        rows[name] = {
            "home": str(home_dir),
            "skills": [p.name for p in installed_skill_dirs(home_dir)],
            "plugin_enabled": claude_enabled(home_dir) if name == "Claude" else None,
        }
    effective = mode
    if mode == "auto":
        # Auto parks nothing; whether a turn gets a mode depends on the hook.
        effective = "auto (hook decides per prompt)"
    return {"mode": mode, "effective": effective, "providers": rows}


def _park(dirs, tag):
    tag = tag.replace("/", "-")
    PARKED.mkdir(parents=True, exist_ok=True)
    for src in dirs:
        dest = PARKED / tag / src.parent.name / src.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        if dest.exists():
            shutil.rmtree(dest)
        shutil.move(str(src), str(dest))
        yield f"parked {src}"


def _unpark(source_tree):
    """Copy ponytail* skills back from the bundle tree, if it is reachable."""
    restored = []
    if not source_tree.is_dir():
        return restored
    for src in sorted(source_tree.iterdir()):
        if not (src.is_dir() and src.name.startswith(SKILL_PREFIX)):
            continue
        for home_dir in provider_homes().values():
            skills = home_dir / "skills"
            if not skills.is_dir():
                continue
            dest = skills / src.name
            if not dest.exists():
                shutil.copytree(src, dest)
                restored.append(f"restored {dest}")
    return restored


def apply(mode, home=None, source_tree=None, run=None):
    if mode not in LEVELS:
        raise SystemExit("unknown mode %r (use %s)" % (mode, ", ".join(LEVELS)))
    run = run or (lambda cmd: subprocess.run(cmd, capture_output=True, text=True))
    actions = []
    homes = provider_homes(home)
    want_on = mode in ("lite", "full", "ultra", "auto")

    for name, home_dir in homes.items():
        if name == "Claude":
            settings = home_dir / "settings.json"
            if settings.exists():
                data = json.loads(settings.read_text(encoding="utf-8-sig"))
                changed = False
                for key in list((data.get("enabledPlugins") or {})):
                    if SKILL_PREFIX in key.lower() and bool(data["enabledPlugins"][key]) != want_on:
                        data["enabledPlugins"][key] = want_on
                        changed = True
                if changed:
                    backup = settings.with_suffix(".json.bak-ponytail")
                    shutil.copy2(settings, backup)
                    settings.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
                    actions.append(f"Claude enabledPlugins ponytail -> {want_on} (backup {backup.name})")
            dirs = installed_skill_dirs(home_dir)
            if not want_on and dirs:
                actions.extend(_park(dirs, name))
            elif want_on and not dirs and source_tree:
                for src in sorted(source_tree.iterdir()):
                    if src.is_dir() and src.name.startswith(SKILL_PREFIX):
                        dest = home_dir / "skills" / src.name
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        if not dest.exists():
                            shutil.copytree(src, dest)
                            actions.append(f"restored {dest}")
        elif name == "Hermes":
            exe = shutil.which("hermes") or str(home_dir / "hermes-agent" / ".hermes" / "bin" / "hermes")
            if Path(exe).exists():
                cmd = [exe, "plugins", "enable" if want_on else "disable", SKILL_PREFIX]
                out = run(cmd)
                actions.append("Hermes: " + (" ".join(cmd[1:3]) + " (exit %s)" % out.returncode))
            # Hermes also loads copied skills, and a disabled plugin does not remove
            # them: park the copies the same way as the other skill-based providers.
            dirs = installed_skill_dirs(home_dir)
            if not want_on and dirs:
                actions.extend(_park(dirs, name))
            elif want_on and not dirs and source_tree:
                for src in sorted(source_tree.iterdir()):
                    if src.is_dir() and src.name.startswith(SKILL_PREFIX):
                        dest = home_dir / "skills" / src.name
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        if not dest.exists():
                            shutil.copytree(src, dest)
                            actions.append(f"restored {dest}")
        else:
            dirs = installed_skill_dirs(home_dir)
            if not want_on and dirs:
                actions.extend(_park(dirs, name))
            elif want_on and not dirs and source_tree:
                for src in sorted(source_tree.iterdir()):
                    if src.is_dir() and src.name.startswith(SKILL_PREFIX):
                        dest = home_dir / "skills" / src.name
                        dest.parent.mkdir(parents=True, exist_ok=True)
                        if not dest.exists():
                            shutil.copytree(src, dest)
                            actions.append(f"restored {dest}")

    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps({"mode": mode,
                                 "updated": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                                 "level_source": "plugin command (e.g. /ponytail full)"}, indent=1) + "\n",
                     encoding="utf-8")
    actions.append("state %s -> %s" % (STATE, mode))
    return actions


def main(argv=None):
    ap = argparse.ArgumentParser(description="Ponytail mode for every installed provider (default: off)")
    ap.add_argument("mode", nargs="?", default="status", choices=("status", "init") + LEVELS)
    ap.add_argument("--apply", action="store_true", help="change provider state (init applies off only when never chosen)")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--source-tree", help="skills tree to restore from (default: this checkout)")
    args = ap.parse_args(argv)

    if args.mode == "status":
        report = status()
        if args.json:
            print(json.dumps(report, indent=1))
            return 0
        print("mode: %s (effective %s)" % (report["mode"], report["effective"]))
        for name, row in report["providers"].items():
            skills = ", ".join(row["skills"]) or "-"
            plugin = "" if row["plugin_enabled"] is None else " plugin=%s" % row["plugin_enabled"]
            print("  %-11s skills: %s%s" % (name, skills, plugin))
        return 0

    mode = args.mode
    if mode == "init":
        if read_state().get("mode"):
            print("existing choice kept: %s" % read_state()["mode"])
            return 0
        mode = "off"

    if not args.apply:
        print("would set %s (add --apply)" % mode)
        for line in apply(mode, source_tree=_tree(args), run=lambda c: subprocess.CompletedProcess(c, 0, "", "")):
            print("  " + line)
        return 0

    for line in apply(mode, source_tree=_tree(args)):
        print("  " + line)
    return 0


def _tree(args):
    if args.source_tree:
        return Path(args.source_tree)
    return Path(__file__).resolve().parent.parent / "1-TAILORED-PROVIDER-TREES" / "Claude" / "COPY-TO-SKILLS-DIRECTORY" / "skills"


if __name__ == "__main__":
    sys.exit(main())
