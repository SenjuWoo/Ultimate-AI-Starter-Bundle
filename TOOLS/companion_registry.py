"""Companion registry: detect, plan and report — never install.

The bundle coordinates owners; it does not become a second package manager. This module reads
`BUNDLED-TOOLS/COMPANIONS.json`, validates it against the owner allowlist, and reports what is
present on this machine. It does not run a single command from the registry: `--print-doctor`
shows the owner's own entrypoint so the user (or an agent) can run it deliberately.

    python TOOLS/companion_registry.py --verify
    python TOOLS/companion_registry.py --verify --json
    python TOOLS/companion_registry.py --roots "D:/Tools" --print-doctor roblox-forge
"""
import argparse
import json
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REGISTRY = os.path.join(os.path.dirname(HERE), "BUNDLED-TOOLS", "COMPANIONS.json")

# NOT_FOUND     nothing with this owner's markers on any searched root
# DISCOVERED    the folder exists but a required marker is missing
# INSTALLED     every marker is present
# DEGRADED      installed, but a declared requirement is missing on this machine
STATES = ("NOT_FOUND", "DISCOVERED", "INSTALLED", "DEGRADED")

DEFAULT_ROOTS = (
    os.path.join(os.environ.get("USERPROFILE", ""), "AppData", "Local"),
    os.path.join(os.environ.get("USERPROFILE", ""), "AppData", "Local", "Skyrim-Tools"),
    os.path.join(os.environ.get("USERPROFILE", ""), "AppData", "Roaming"),
    "Z:/Backup/Ai documentation/Tools/Ai tools",
    "Z:/Backup/Ai documentation/Tools",
    "Z:/Backup/!Skyrim/Skyrim tools",
    "C:/Program Files",
    "C:/Program Files (x86)",
    "Z:/Backup/Ai apps",
    "Z:/Backup/Ai documentation/Tools/Ai tools",
    "S:/Apps",
)


class RegistryError(ValueError):
    pass


def load(path=REGISTRY):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    validate(data)
    return data


def validate(data):
    """Schema and trust checks. A registry that fails these is never used."""
    if not isinstance(data, dict) or data.get("schema") != 1:
        raise RegistryError("schema must be 1")
    allow = data.get("owner_allowlist") or []
    if not allow:
        raise RegistryError("owner_allowlist is empty - refusing to trust any repository")
    companions = data.get("companions")
    if not isinstance(companions, dict) or not companions:
        raise RegistryError("no companions")
    for cid, entry in companions.items():
        if not isinstance(entry, dict):
            raise RegistryError("%s: not an object" % cid)
        for field in ("title", "repo", "install", "markers", "platforms"):
            if field not in entry:
                raise RegistryError("%s: missing %s" % (cid, field))
        repo = entry["repo"]
        if not any(allowed in repo for allowed in allow):
            raise RegistryError("%s: repo %r is not on the owner allowlist" % (cid, repo))
        if not repo.startswith("https://"):
            raise RegistryError("%s: repo must be an https URL" % cid)
        kind = entry["install"].get("kind")
        if kind not in ("release_zip", "owner_installer", "source_only", "external_app", "gui_app"):
            raise RegistryError("%s: unknown install kind %r" % (cid, kind))
        if kind == "release_zip" and not entry["install"].get("asset"):
            raise RegistryError("%s: a release_zip needs an asset pattern" % cid)
        if kind == "source_only" and entry["install"].get("asset"):
            raise RegistryError("%s: source_only must not advertise a downloadable asset" % cid)
        markers = entry["markers"]
        if not isinstance(markers, list) or not markers:
            raise RegistryError("%s: markers must be a non-empty list" % cid)
    return data


def roots(extra=None):
    seen, out = set(), []
    for root in list(extra or []) + [r for r in os.environ.get("UABS_TOOL_ROOTS", "").split(os.pathsep) if r] + list(DEFAULT_ROOTS):
        norm = os.path.normcase(os.path.abspath(root)) if root else ""
        if root and norm not in seen and os.path.isdir(root):
            seen.add(norm)
            out.append(root)
    return out


def _norm(name):
    return "".join(ch for ch in name.lower() if ch.isalnum())


def owner_names(entry):
    """Folder names this owner legitimately installs under (repo name, and title without spaces)."""
    repo = entry["repo"].rstrip("/").split("/")[-1]
    return {_norm(repo), _norm(entry.get("title", ""))}


def find(entry, search_roots):
    """First directory containing every marker, or None."""
    markers = entry["markers"]
    for root in search_roots:
        try:
            children = os.listdir(root)
        except OSError:
            continue
        for name in children:
            candidate = os.path.join(root, name)
            if not os.path.isdir(candidate) or _norm(name) not in owner_names(entry):
                continue  # another owner's folder must never satisfy this entry
            if all(os.path.exists(os.path.join(candidate, m)) for m in markers):
                return candidate
    return None


def find_partial(entry, search_roots):
    """A folder named exactly like this owner that lacks a marker: a half-install, not the game."""
    wanted = owner_names(entry)
    for root in search_roots:
        try:
            children = os.listdir(root)
        except OSError:
            continue
        for name in children:
            candidate = os.path.join(root, name)
            if os.path.isdir(candidate) and _norm(name) in wanted:
                return candidate
    return None


def status(search_roots, data=None):
    data = data or load()
    report = {}
    for cid, entry in sorted(data["companions"].items()):
        path = find(entry, search_roots)
        if path:
            state = "INSTALLED"
        else:
            # Only an exact owner-named folder counts as a half-install; the game folder must never
            # be mistaken for its Forge.
            path = find_partial(entry, search_roots)
            state = "DISCOVERED" if path else "NOT_FOUND"
        report[cid] = {"state": state, "path": path, "title": entry["title"],
                       "repo": entry["repo"], "kind": entry["install"]["kind"],
                       "doctor": entry.get("doctor", {}).get("entrypoint")}
    return report


def main(argv=None):
    ap = argparse.ArgumentParser(description="Detect installed companion owners (never installs)")
    ap.add_argument("--verify", action="store_true", help="report every companion's state")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--roots", action="append", default=[], help="extra directory to search")
    ap.add_argument("--print-doctor", metavar="ID", help="show the owner's own doctor command")
    args = ap.parse_args(argv)

    try:
        data = load()
    except (OSError, RegistryError) as exc:
        print("registry invalid: %s" % exc)
        return 2

    if args.print_doctor:
        entry = data["companions"].get(args.print_doctor)
        if not entry:
            print("unknown companion %r" % args.print_doctor)
            return 2
        cmd = entry.get("doctor", {}).get("entrypoint")
        print(" ".join(cmd) if isinstance(cmd, list) else (cmd or "no doctor declared"))
        return 0

    report = status(roots(args.roots), data)
    if args.json:
        print(json.dumps(report, indent=1))
        return 0
    for cid, row in report.items():
        print("%-16s %-10s %s" % (cid, row["state"], row["path"] or row["repo"]))
    counts = {}
    for row in report.values():
        counts[row["state"]] = counts.get(row["state"], 0) + 1
    print("\n" + ", ".join("%s=%d" % (k, v) for k, v in sorted(counts.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
