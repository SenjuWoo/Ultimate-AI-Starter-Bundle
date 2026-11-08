"""Ponytail mode for every provider, through Ponytail's own native setting.

Upstream ponytail 5.x resolves its mode as: `PONYTAIL_DEFAULT_MODE` env var, then
`%APPDATA%\\ponytail\\config.json` -> {"defaultMode": ...}, then "full". Its hooks
skip activation entirely at "off" - no rules, no flag, no banner - so the bundle
sets that native value instead of inventing a parallel mode system, and the plugin
(with its /ponytail commands and statusline) stays installed and usable.

Copied skill folders are a second injection path, because skill descriptions
auto-trigger. They are parked on "off" and restored on demand. Parking never
deletes or overwrites anything: each archive carries a hash of its original path,
and a collision is reported instead of resolved by destruction.

`auto` is the third state: a deterministic classifier in TOOLS/hooks/ponytail_auto.py
reads each prompt and decides off/lite/full (never ultra; creative work stays off).
Here it means "native default off, skills kept, hook decides per turn".

    python TOOLS/ponytail_mode.py status            # read-only
    python TOOLS/ponytail_mode.py off               # dry-run: prints the plan
    python TOOLS/ponytail_mode.py lite --apply      # native config + skills
    python TOOLS/ponytail_mode.py init --apply      # install time: off only if never chosen
"""

import argparse
import hashlib
import json
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

LEVELS = ("off", "lite", "full", "ultra", "auto")
SKILL_PREFIX = "ponytail"
STATE = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Ultimate-AI-Starter-Bundle" / "ponytail-mode"
PARKED = STATE / "parked"


def native_config():
    base = os.environ.get("APPDATA") or (Path.home() / "AppData" / "Roaming")
    return Path(base) / "ponytail" / "config.json"


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


def read_state():
    data, _ = read_json(STATE / "state.json")
    return data if isinstance(data, dict) else {}


def status(home=None):
    state = read_state()
    requested = state.get("mode", "off")
    data, err = read_json(native_config())
    configured = None if err else (data or {}).get("defaultMode")
    env_mode = (os.environ.get("PONYTAIL_DEFAULT_MODE") or "").strip().lower() or None
    # Upstream resolution order: env var, then config file, then "full".
    native = env_mode or configured or "full (upstream default)"
    homes = provider_homes(home)
    rows, leaks, mismatches = {}, [], []
    for name, home_dir in homes.items():
        dirs = installed_skill_dirs(home_dir)
        rows[name] = {
            "home": str(home_dir),
            "skills": [p.name for p in dirs],
            "plugin_enabled": claude_enabled(home_dir) if name == "Claude" else None,
        }
        # An enabled plugin emits nothing at off (upstream skips activation), so
        # only loaded skill copies can leak behaviour into a prompt.
        if native == "off" and dirs:
            leaks.append("%s still loads %d ponytail skill(s)" % (name, len(dirs)))
    if err:
        mismatches.append("config.json is not valid JSON: %s" % err)
    if env_mode:
        mismatches.append("PONYTAIL_DEFAULT_MODE=%s overrides the config file" % env_mode)
    if requested in LEVELS and requested != "auto" and native != requested:
        mismatches.append("requested %s but the effective default is %s" % (requested, native))
    if requested == "auto" and (native != "off" or leaks):
        mismatches.append("auto needs the native default at off and no loaded skills")
    effective = "UNKNOWN" if err else native
    if requested == "auto" and native == "off" and not leaks:
        effective = "auto (hook decides per turn; nothing loaded by default)"
    return {"requested": requested, "native": native, "configured": configured,
            "env_override": env_mode, "effective": effective,
            "native_config": str(native_config()), "providers": rows,
            "leaks": leaks, "mismatches": mismatches,
            # A JSON value is configuration, never proof of what a live session got.
            "runtime_verified": False,
            "note": "native config applies to new sessions; a JSON value is not runtime proof"}


def read_json(path):
    """Read JSON without ever treating a broken file as empty and overwriting it."""
    try:
        return json.loads(Path(path).read_text(encoding="utf-8-sig")), None
    except FileNotFoundError:
        return {}, None
    except (OSError, ValueError) as exc:
        return None, str(exc)


def _park_name(src):
    # Original path in the archive name: two profiles can hold different copies of
    # the same skill name, and neither may replace the other.
    return "%s__%s" % (Path(src).name, hashlib.sha256(str(src).encode("utf-8")).hexdigest()[:10])


def _tree_digest(root):
    h = hashlib.sha256()
    for path in sorted(Path(root).rglob("*")):
        h.update(str(path.relative_to(root)).encode())
        if path.is_file():
            h.update(path.read_bytes())
    return h.hexdigest()


def plan(mode, home=None, source_tree=None):
    """Pure: describes what a change would do. Never touches the disk."""
    if mode not in LEVELS:
        raise SystemExit("unknown mode %r (use %s)" % (mode, ", ".join(LEVELS)))
    native_mode = "off" if mode == "auto" else mode
    # AUTO injects through the classifier hook only. Leaving the skill folders in
    # place would let a skill description trigger independently and override the
    # classifier's OFF decision, so every non-manual mode parks them.
    want_skills = mode in ("lite", "full", "ultra")
    actions = []

    data, err = read_json(native_config())
    if err:
        actions.append({"kind": "config_malformed", "path": str(native_config()), "error": err})
    elif (data or {}).get("defaultMode") != native_mode:
        actions.append({"kind": "native_config", "path": str(native_config()),
                        "from": (data or {}).get("defaultMode"), "to": native_mode})

    homes = provider_homes(home)
    if not want_skills:
        for name, home_dir in homes.items():
            for src in installed_skill_dirs(home_dir):
                actions.append({"kind": "park", "provider": name, "src": str(src),
                                "dest": str(PARKED / name.replace("/", "-") / _park_name(src))})
    else:
        for name, home_dir in homes.items():
            present = {p.name for p in installed_skill_dirs(home_dir)}
            archive = PARKED / name.replace("/", "-")
            if archive.is_dir():
                for entry in sorted(archive.iterdir()):
                    original = entry.name.split("__")[0]
                    if entry.is_dir() and original not in present:
                        actions.append({"kind": "restore_parked", "provider": name,
                                        "src": str(entry), "dest": str(home_dir / "skills" / original)})
                        present.add(original)
            if source_tree and Path(source_tree).is_dir():
                for src in sorted(Path(source_tree).iterdir()):
                    if src.is_dir() and src.name.startswith(SKILL_PREFIX) and src.name not in present:
                        actions.append({"kind": "restore_bundle", "provider": name,
                                        "src": str(src), "dest": str(home_dir / "skills" / src.name)})
                        present.add(src.name)
    return actions


def execute(actions, stamp=None):
    """Runs a plan. Never deletes: a collision is reported, both copies stay."""
    stamp = stamp or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    results = []
    for action in actions:
        kind = action["kind"]
        if kind == "config_malformed":
            results.append(dict(action, ok=False,
                                message="config exists but is not valid JSON; left untouched"))
        elif kind == "native_config":
            path = Path(action["path"])
            data, _ = read_json(path)
            data = data if isinstance(data, dict) else {}
            if path.exists():
                shutil.copy2(path, path.with_suffix(".json.bak-ponytail-%s" % stamp))
            data["defaultMode"] = action["to"]
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
            results.append(dict(action, ok=True))
        elif kind == "park":
            src, dest = Path(action["src"]), Path(action["dest"])
            if dest.exists():
                if _tree_digest(src) == _tree_digest(dest):
                    # An identical copy is already archived (a provider re-copied
                    # it); drop the duplicate from the live tree, not the archive.
                    shutil.rmtree(src)
                    results.append(dict(action, ok=True, message="deduped: identical archive exists"))
                else:
                    data_dest = dest.with_name(dest.name + "__" + _tree_digest(src)[:8])
                    if data_dest.exists():
                        results.append(dict(action, ok=False, message="a different copy is already archived"))
                        continue
                    data_dest.parent.mkdir(parents=True, exist_ok=True)
                    shutil.move(str(src), str(data_dest))
                    results.append(dict(action, ok=True, message="parked as %s" % data_dest.name))
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(src), str(dest))
            results.append(dict(action, ok=True))
        elif kind in ("restore_parked", "restore_bundle"):
            src, dest = Path(action["src"]), Path(action["dest"])
            if dest.exists():
                results.append(dict(action, ok=False, message="destination exists; both kept"))
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            if kind == "restore_bundle":
                shutil.copytree(src, dest)
            else:
                shutil.move(str(src), str(dest))
            results.append(dict(action, ok=True))
        else:
            results.append(dict(action, ok=False, message="unknown action"))
    return results


def main(argv=None):
    ap = argparse.ArgumentParser(description="Ponytail mode through Ponytail's native config (default: off)")
    ap.add_argument("mode", nargs="?", default="status", choices=("status", "init") + LEVELS)
    ap.add_argument("--apply", action="store_true", help="execute the plan; without it nothing changes")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--source-tree", help="skills tree to restore from (default: this checkout)")
    args = ap.parse_args(argv)

    if args.mode == "status":
        report = status()
        if args.json:
            print(json.dumps(report, indent=1))
            return 0 if not (report["leaks"] or report["mismatches"]) else 1
        print("requested: %s | native defaultMode: %s | effective: %s"
              % (report["requested"], report["native"], report["effective"]))
        print("native config: %s" % report["native_config"])
        if report["env_override"]:
            print("environment override: PONYTAIL_DEFAULT_MODE=%s" % report["env_override"])
        for name, row in report["providers"].items():
            skills = ", ".join(row["skills"]) or "-"
            plugin = "" if row["plugin_enabled"] is None else " plugin=%s" % row["plugin_enabled"]
            print("  %-16s skills: %s%s" % (name, skills, plugin))
        for leak in report["leaks"]:
            print("  LEAK: %s" % leak)
        for mismatch in report["mismatches"]:
            print("  MISMATCH: %s" % mismatch)
        print(report["note"])
        return 0 if not (report["leaks"] or report["mismatches"]) else 1

    mode = args.mode
    if mode == "init":
        # Installers re-copy skill folders on every run, so init must re-assert the
        # chosen mode rather than only recording it: an idempotent pass parks what
        # the copy step just laid down.
        existing = read_state().get("mode")
        if existing:
            print("existing choice kept: %s" % existing)
            mode = existing
        else:
            mode = "off"

    actions = plan(mode, source_tree=_tree(args))
    if args.json:
        print(json.dumps(actions, indent=1))
    else:
        for action in actions:
            print("  %-15s %s" % (action["kind"], action.get("src") or action.get("path")))
    if not args.apply:
        print("dry-run: nothing changed (add --apply)")
        return 0

    results = execute(actions)
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / "state.json").write_text(json.dumps(
        {"mode": mode, "updated": datetime.now(timezone.utc).isoformat(timespec="seconds")},
        indent=1) + "\n", encoding="utf-8")
    failures = [r for r in results if not r["ok"]]
    for item in failures:
        print("  FAILED %s: %s" % (item["kind"], item.get("message")))
    print("applied %d action(s), %d failure(s); new sessions pick this up"
          % (len(results), len(failures)))
    return 0 if not failures else 1


def _tree(args):
    if args.source_tree:
        return Path(args.source_tree)
    return Path(__file__).resolve().parent.parent / "1-TAILORED-PROVIDER-TREES" / "Claude" / "COPY-TO-SKILLS-DIRECTORY" / "skills"


if __name__ == "__main__":
    sys.exit(main())
