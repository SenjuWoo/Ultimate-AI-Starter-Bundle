"""Keep skill listings small without taking a skill away.

Every installed skill puts its name and description in front of every request.
Claude Code caps that listing at a share of the context window and drops what
does not fit, so 180 skills cost tokens on every turn and, on a smaller window,
hide skills outright. Most of that weight is domain families that only matter
for one kind of work: 24 Roblox specialists behind one router, Unity's 35
skills, the 10-step Replica pack.

`BUNDLED-TOOLS/SKILL-SCOPE.json` names those families. This tool applies it:

- Claude: `skillOverrides` set to `name-only` for family members, except the
  entry points the policy keeps described. The skill stays installed and
  callable; only its description leaves the listing.
- Hermes: each named profile disables the families that are not its own
  (`skills.disabled`, through Hermes' own config API). The default profile is
  the generalist and is not changed.

Names matching the policy's `protected` pattern are never touched. A value the
user set is never overwritten, and only entries this tool recorded in its
receipt are ever removed.

    python TOOLS/skill_scope.py              report
    python TOOLS/skill_scope.py --json
    python TOOLS/skill_scope.py --fix        apply (Hermes waits while its gateway runs)
    python TOOLS/skill_scope.py --fix --hermes-live
    python TOOLS/skill_scope.py --undo       remove what this tool added and stay off
"""
import argparse
import datetime
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PACK_ROOT = os.path.dirname(HERE)
POLICY = os.path.join(PACK_ROOT, "BUNDLED-TOOLS", "SKILL-SCOPE.json")
PACKS = os.path.join(PACK_ROOT, "BUNDLED-TOOLS", "PACKS.json")
NAME_ONLY = "name-only"

HERMES_SCRIPT = r'''
import json, os
from hermes_cli.config import load_config
from hermes_cli.skills_config import get_disabled_skills, save_disabled_skills
cfg = load_config()
before = sorted(get_disabled_skills(cfg))
wanted = os.environ.get("UABS_SKILL_SCOPE_SET")
if wanted is not None:
    save_disabled_skills(cfg, set(json.loads(wanted)))
print(json.dumps(before))
'''


# ------------------------------------------------------------------ paths ---
def state_root():
    local = os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(local, "Ultimate-AI-Starter-Bundle")


def receipt_path():
    return os.path.join(state_root(), "skill-scope.json")


def claude_home():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.join(os.path.expanduser("~"), ".claude")


def hermes_root():
    """The Hermes home, never a profile: Hermes desktop exports HERMES_HOME as the active profile."""
    explicit = os.environ.get("HERMES_HOME")
    local = os.environ.get("LOCALAPPDATA")
    path = explicit or (os.path.join(local, "hermes") if local else os.path.join(os.path.expanduser("~"), ".hermes"))
    path = os.path.normpath(path)
    parent = os.path.dirname(path)
    if os.path.basename(parent).lower() == "profiles":
        path = os.path.dirname(parent)
    return path


def hermes_exe(root):
    for candidate in (os.path.join(root, "bin", "hermes.exe"), os.path.join(root, "bin", "hermes"),
                      os.path.join(root, "hermes-agent", "venv", "Scripts", "hermes.exe")):
        if os.path.isfile(candidate):
            return candidate
    return None


# ----------------------------------------------------------------- policy ---
def load_json(path, default=None):
    try:
        with open(path, encoding="utf-8-sig") as handle:
            return json.load(handle)
    except (OSError, ValueError):
        return default


def load_policy(path=POLICY, packs=PACKS):
    policy = load_json(path)
    if not isinstance(policy, dict) or policy.get("schema") != 1:
        raise SystemExit("skill scope policy missing or unreadable: %s" % path)
    pack_doc = load_json(packs, {}) or {}
    for family in policy["families"].values():
        pack = family.get("names_from_pack")
        if pack:
            names = ((pack_doc.get("packs") or {}).get(pack) or {}).get("skills") or []
            family["names"] = sorted(set(family.get("names", [])) | set(names))
    return policy


def members(policy, family_id, installed):
    """Installed skills that belong to a family, without protected names."""
    family = policy["families"][family_id]
    protected = re.compile(policy.get("protected") or r"(?!x)x")
    names = set(family.get("names", []))
    prefixes = tuple(family.get("prefixes", []))
    return {name for name in installed
            if (name in names or (prefixes and name.startswith(prefixes))) and not protected.search(name)}


def installed_skills(folder):
    try:
        return {name for name in os.listdir(folder) if os.path.isfile(os.path.join(folder, name, "SKILL.md"))}
    except OSError:
        return set()


def description_chars(folder, name):
    try:
        with open(os.path.join(folder, name, "SKILL.md"), encoding="utf-8", errors="replace") as handle:
            text = handle.read(20000)
    except OSError:
        return 0
    match = re.search(r"^description:\s*(.*?)(?=^[\w-]+:|^---)", text, re.S | re.M)
    return len(re.sub(r"\s+", " ", match.group(1)).strip(" >|\"'")) if match else 0


# ------------------------------------------------------------- receipt io ---
def read_receipt():
    data = load_json(receipt_path(), {}) or {}
    data.setdefault("schema", 1)
    data.setdefault("claude", {})
    data.setdefault("hermes", {})
    return data


def write_json_atomic(path, data, backup=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if backup and os.path.isfile(path):
        stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%d%H%M%S")
        with open(path, "rb") as handle:
            original = handle.read()
        with open("%s.before-skill-scope-%s.bak" % (path, stamp), "wb") as handle:
            handle.write(original)
    temp = path + ".skill-scope.tmp"
    with open(temp, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(data, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    os.replace(temp, path)


# ----------------------------------------------------------------- claude ---
def claude_plan(policy, receipt, home=None):
    home = home or claude_home()
    folder = os.path.join(home, "skills")
    settings_path = os.path.join(home, "settings.json")
    installed = installed_skills(folder)
    settings = load_json(settings_path, {}) if os.path.isfile(settings_path) else {}
    if not isinstance(settings, dict):
        return {"provider": "claude", "error": "settings.json is not a JSON object", "settings": settings_path}
    current = settings.get("skillOverrides") or {}
    managed = dict((receipt.get("claude") or {}).get("managed") or {})
    desired = {}
    for family_id in (policy.get("claude") or {}).get("name_only", []):
        keep = set(policy["families"][family_id].get("keep_described", []))
        for name in members(policy, family_id, installed) - keep:
            desired[name] = NAME_ONLY
    add, remove, user = {}, [], []
    for name, value in sorted(desired.items()):
        if name not in current:
            add[name] = value
        elif current[name] != value and managed.get(name) != current[name]:
            user.append(name)             # the user chose something else; leave it
    for name, value in managed.items():
        if name not in desired and current.get(name) == value:
            remove.append(name)
    all_chars = sum(description_chars(folder, name) for name in installed)
    hidden = sum(description_chars(folder, name) for name in desired if name not in user)
    return {"provider": "claude", "settings": settings_path, "skills": len(installed),
            "listing_chars": all_chars, "listing_chars_after": all_chars - hidden,
            "add": add, "remove": sorted(remove), "user_overrides": user,
            "managed": sorted((set(managed) | set(add)) - set(remove))}


def claude_apply(plan, receipt, undo=False):
    settings_path = plan["settings"]
    settings = load_json(settings_path, {}) if os.path.isfile(settings_path) else {}
    overrides = dict(settings.get("skillOverrides") or {})
    managed = dict((receipt.get("claude") or {}).get("managed") or {})
    if undo:
        for name, value in list(managed.items()):
            if overrides.get(name) == value:
                overrides.pop(name)
        managed = {}
    else:
        for name in plan["remove"]:
            overrides.pop(name, None)
            managed.pop(name, None)
        for name, value in plan["add"].items():
            overrides[name] = value
            managed[name] = value
    if overrides:
        settings["skillOverrides"] = dict(sorted(overrides.items()))
    else:
        settings.pop("skillOverrides", None)
    write_json_atomic(settings_path, settings, backup=True)
    receipt["claude"] = {"settings": settings_path, "managed": managed}


# ----------------------------------------------------------------- hermes ---
def hermes_runtime(exe):
    """The command Hermes itself uses for a script file (same bootstrap as the bundle's PowerShell)."""
    out = subprocess.run([exe, "--print-runtime-command", "--module", "runpy"], capture_output=True,
                         text=True, timeout=60)
    command = json.loads(out.stdout)
    call = "runpy.run_module('runpy', run_name='__main__', alter_sys=True)"
    if not isinstance(command, list) or len(command) < 2 or call not in command[-1]:
        raise RuntimeError("Hermes runtime bootstrap format changed; skill_scope.py needs review")
    command[-1] = command[-1].replace(call, "runpy.run_path(sys.argv.pop(1), run_name='__main__')")
    return command


def hermes_disabled(runtime, profile_home, wanted=None):
    import tempfile
    env = dict(os.environ, HERMES_HOME=profile_home)
    env.pop("UABS_SKILL_SCOPE_SET", None)
    if wanted is not None:
        env["UABS_SKILL_SCOPE_SET"] = json.dumps(sorted(wanted))
    fd, script = tempfile.mkstemp(prefix="uabs-skill-scope-", suffix=".py")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(HERMES_SCRIPT)
        out = subprocess.run(runtime + [script], capture_output=True, text=True, env=env, timeout=120)
    finally:
        os.remove(script)
    if out.returncode != 0:
        raise RuntimeError((out.stderr or out.stdout).strip()[-400:] or "Hermes config call failed")
    return set(json.loads(out.stdout.strip().splitlines()[-1]))


def gateway_running(exe):
    try:
        text = subprocess.run([exe, "gateway", "status"], capture_output=True, text=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return bool(re.search(r"(?i)running", text)) and not re.search(r"(?i)not running", text)


def hermes_plan(policy, receipt, root=None, read_disabled=None):
    root = root or hermes_root()
    profiles_dir = os.path.join(root, "profiles")
    conf = policy.get("hermes") or {}
    families = conf.get("families", [])
    owned = conf.get("profiles") or {}
    rows = []
    try:
        # Dot folders (Hermes keeps removed profiles in `.deleted`) are not profiles.
        names = sorted(n for n in os.listdir(profiles_dir)
                       if not n.startswith(".") and os.path.isdir(os.path.join(profiles_dir, n)))
    except OSError:
        names = []
    for profile in names:
        home = os.path.join(profiles_dir, profile)
        installed = installed_skills(os.path.join(home, "skills"))
        mine = set(owned.get(profile, []))
        desired = set()
        for family_id in families:
            if family_id not in mine:
                desired |= members(policy, family_id, installed)
        managed = set((receipt.get("hermes") or {}).get(profile, []))
        row = {"profile": profile, "home": home, "skills": len(installed), "desired": sorted(desired),
               "managed": sorted(managed)}
        if read_disabled:
            current = read_disabled(home)
            row["current"] = sorted(current)
            row["add"] = sorted(desired - current)
            row["remove"] = sorted((managed - desired) & current)
        else:
            row["add"], row["remove"] = sorted(desired), []
        rows.append(row)
    return {"provider": "hermes", "root": root, "profiles": rows}


# ------------------------------------------------------------------- main ---
def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--fix", action="store_true")
    parser.add_argument("--undo", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--hermes-live", action="store_true", help="change Hermes profiles while its gateway runs")
    parser.add_argument("--provider", choices=["claude", "hermes", "all"], default="all")
    parser.add_argument("--force", action="store_true", help="apply even after --undo opted out")
    args = parser.parse_args(argv)

    policy = load_policy()
    receipt = read_receipt()
    opted_out = bool(receipt.get("opted_out")) and not args.force
    report = {"policy": POLICY, "opted_out": opted_out, "providers": []}

    if args.provider in ("claude", "all") and os.path.isdir(claude_home()):
        plan = claude_plan(policy, receipt)
        report["providers"].append(plan)
        if "error" not in plan:
            if args.undo:
                claude_apply(plan, receipt, undo=True)
                plan["applied"] = "undone"
            elif args.fix and not opted_out and (plan["add"] or plan["remove"]):
                claude_apply(plan, receipt)
                plan["applied"] = "yes"

    root = hermes_root()
    exe = hermes_exe(root) if args.provider in ("hermes", "all") else None
    if exe and os.path.isdir(os.path.join(root, "profiles")):
        runtime = None
        reader = None
        try:
            runtime = hermes_runtime(exe)
            reader = lambda home: hermes_disabled(runtime, home)  # noqa: E731
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as exc:
            report["hermes_error"] = str(exc)
        plan = hermes_plan(policy, receipt, root, reader)
        report["providers"].append(plan)
        wants_change = args.undo or (args.fix and not opted_out)
        pending = any(row["add"] or row["remove"] or (args.undo and row["managed"]) for row in plan["profiles"])
        if runtime and wants_change and not pending:
            plan["applied"] = "nothing to change"
        elif runtime and wants_change:
            if gateway_running(exe) and not args.hermes_live:
                plan["applied"] = "deferred: the Hermes gateway is running (rerun with --hermes-live, or after it stops)"
            else:
                for row in plan["profiles"]:
                    current = set(row.get("current", []))
                    managed = set(row["managed"])
                    if args.undo:
                        wanted = current - managed
                        kept = set()
                    else:
                        wanted = (current - set(row["remove"])) | set(row["add"])
                        kept = (managed - set(row["remove"])) | set(row["add"])
                    if wanted != current:
                        hermes_disabled(runtime, row["home"], wanted)
                    receipt["hermes"][row["profile"]] = sorted(kept)
                plan["applied"] = "undone" if args.undo else "yes"

    if args.undo:
        receipt["opted_out"] = True
    elif args.fix and args.force:
        receipt.pop("opted_out", None)
    if args.fix or args.undo:
        receipt["updated"] = datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")
        write_json_atomic(receipt_path(), receipt)

    if args.json:
        print(json.dumps(report, indent=2))
        return 0
    if opted_out:
        print("skill scope: turned off with --undo; --fix --force turns it back on")
    for plan in report["providers"]:
        if plan["provider"] == "claude":
            if "error" in plan:
                print("claude: %s (%s)" % (plan["error"], plan["settings"]))
                continue
            print("claude: %d skills, listing ~%d chars -> ~%d with name-only families; add %d, remove %d%s" % (
                plan["skills"], plan["listing_chars"], plan["listing_chars_after"], len(plan["add"]),
                len(plan["remove"]), (", applied" if plan.get("applied") else "")))
            if plan["user_overrides"]:
                print("  left as you set them: " + ", ".join(plan["user_overrides"]))
        else:
            for row in plan["profiles"]:
                if row["add"] or row["remove"] or row["managed"]:
                    print("hermes %-12s %3d skills; disable +%d, re-enable %d, managed %d" % (
                        row["profile"], row["skills"], len(row["add"]), len(row["remove"]), len(row["managed"])))
            if plan.get("applied"):
                print("hermes: " + plan["applied"])
    if report.get("hermes_error"):
        print("hermes: not read (%s)" % report["hermes_error"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
