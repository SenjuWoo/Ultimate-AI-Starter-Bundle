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
import glob
import json
import os
import re
import sys
from urllib.parse import urlsplit

HERE = os.path.dirname(os.path.abspath(__file__))
REGISTRY = os.path.join(os.path.dirname(HERE), "BUNDLED-TOOLS", "COMPANIONS.json")

# NOT_FOUND             nothing with this owner's markers on any searched root
# DISCOVERED            the folder exists but a required marker is missing
# INSTALLED_UNVERIFIED  markers are present; no owner doctor has run
# DEGRADED              a declared requirement is missing on this machine
STATES = ("NOT_FOUND", "DISCOVERED", "INSTALLED_UNVERIFIED", "DEGRADED", "AMBIGUOUS")

DEFAULT_ROOTS = (
    os.environ.get("LOCALAPPDATA", os.path.expanduser("~/AppData/Local")),
    os.path.join(os.environ.get("LOCALAPPDATA", os.path.expanduser("~/AppData/Local")), "Skyrim-Tools"),
    os.environ.get("APPDATA", os.path.expanduser("~/AppData/Roaming")),
    os.environ.get("ProgramFiles", ""),
    os.environ.get("ProgramFiles(x86)", ""),
)

# User-declared tool roots live outside the shipped bundle: one absolute path per line, '#' comments.
# The bundle carries no maintainer paths, so a public checkout matches nobody's private layout.
PROFILE_ROOTS = os.path.join(os.environ.get("UABS_PROFILE_ROOT") or
                            os.path.join(os.path.expanduser("~"), ".uabs", "profile"), "TOOL-ROOTS.txt")


class RegistryError(ValueError):
    pass


def load(path=REGISTRY):
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    validate(data)
    return data


def _repo_parts(repo):
    parts = urlsplit(repo)
    if parts.scheme != "https" or parts.netloc.lower() != "github.com":
        raise RegistryError("repo must be https://github.com/<owner>/<repo>, got %r" % repo)
    if parts.query or parts.fragment or parts.username or parts.password or parts.port:
        raise RegistryError("repo URL must not carry credentials, a port, a query or a fragment: %r" % repo)
    segments = [s for s in parts.path.split("/") if s]
    if len(segments) != 2:
        raise RegistryError("repo path must be /<owner>/<repo>, got %r" % repo)
    return segments[0], segments[1][:-4] if segments[1].endswith(".git") else segments[1]


def _check_relative(cid, value, what):
    if not isinstance(value, str) or not value.strip():
        raise RegistryError("%s: %s must be a non-empty string" % (cid, what))
    normal = value.replace("\\", "/")
    if normal.startswith("/") or re.match(r"^[A-Za-z]:", normal) or ".." in normal.split("/"):
        raise RegistryError("%s: %s must stay inside the owner root: %r" % (cid, what, value))


def validate(data):
    """Schema and trust checks. A registry that fails these is never used."""
    if not isinstance(data, dict) or data.get("schema") != 1:
        raise RegistryError("schema must be 1")
    allow = data.get("owner_allowlist") or []
    if not allow:
        raise RegistryError("owner_allowlist is empty - refusing to trust any repository")
    owners = set()
    for value in allow:
        parsed = urlsplit(value if "://" in value else "https://" + value)
        if parsed.scheme != "https" or parsed.hostname != "github.com":
            raise RegistryError("owner_allowlist entries must be HTTPS github.com owners")
        parts = [p for p in parsed.path.split("/") if p]
        if len(parts) != 1:
            raise RegistryError("owner_allowlist entry must be github.com/<owner>/")
        owners.add(parts[0].lower())
    companions = data.get("companions")
    if not isinstance(companions, dict) or not companions:
        raise RegistryError("no companions")
    for cid, entry in companions.items():
        if not isinstance(entry, dict):
            raise RegistryError("%s: not an object" % cid)
        for field in ("title", "repo", "install", "markers", "platforms"):
            if field not in entry:
                raise RegistryError("%s: missing %s" % (cid, field))
        owner, _ = _repo_parts(entry["repo"])
        if owner.lower() not in owners:
            raise RegistryError("%s: owner %r is not on the allowlist" % (cid, owner))
        kind = entry["install"].get("kind")
        if kind not in ("release_zip", "source_zip", "owner_installer", "source_only", "external_app", "gui_app"):
            raise RegistryError("%s: unknown install kind %r" % (cid, kind))
        if kind in ("release_zip", "source_zip", "gui_app") and not entry["install"].get("asset"):
            raise RegistryError("%s: %s needs an asset pattern" % (cid, kind))
        if kind in ("source_only", "owner_installer") and entry["install"].get("asset"):
            raise RegistryError("%s: %s must not advertise a downloadable asset" % (cid, kind))
        if kind == "owner_installer" and not entry["install"].get("entrypoint"):
            raise RegistryError("%s: owner_installer needs an entrypoint" % cid)
        markers = entry["markers"]
        if not isinstance(markers, list) or not markers:
            raise RegistryError("%s: markers must be a non-empty list" % cid)
        for marker in markers:
            _check_relative(cid, marker, "marker")
        cwd = (entry.get("doctor") or {}).get("cwd")
        if cwd is not None:
            _check_relative(cid, cwd, "doctor cwd")
        cmd = (entry.get("doctor") or {}).get("entrypoint")
        if cmd is not None:
            if not isinstance(cmd, list) or not cmd or cmd[0] not in ("python", "python3", "powershell", "pwsh"):
                raise RegistryError("%s: doctor interpreter is not allowed" % cid)
            scripts = [part for part in cmd[1:] if part.endswith((".py", ".ps1"))]
            if len(scripts) > 1 or (not scripts and "-m" not in cmd):
                raise RegistryError("%s: doctor must name one script or a module" % cid)
            for script in scripts:
                _check_relative(cid, script, "doctor script")
    recommended = data.get("recommended") or {}
    if not isinstance(recommended, dict):
        raise RegistryError("recommended must be an object")
    for rid, entry in recommended.items():
        if not isinstance(entry, dict):
            raise RegistryError("%s: recommended entry is not an object" % rid)
        # A recommended pack is a pointer. It is never installed, updated or executed by the
        # bundle, so any executable field is a schema error rather than a silent extra feature.
        for banned in ("install", "update", "doctor", "entrypoint"):
            if banned in entry:
                raise RegistryError("%s: recommended packs must not declare %r" % (rid, banned))
        for field in ("title", "repo", "pin", "license", "markers", "docs"):
            if not entry.get(field):
                raise RegistryError("%s: recommended entry missing %s" % (rid, field))
        parsed = urlsplit(entry["repo"] if "://" in entry["repo"] else "https://" + entry["repo"])
        if parsed.scheme != "https" or parsed.hostname != "github.com":
            raise RegistryError("%s: recommended repo must be HTTPS github.com" % rid)
        if not isinstance(entry["markers"], list) or not entry["markers"]:
            raise RegistryError("%s: recommended markers must be a non-empty list" % rid)
        for marker in entry["markers"]:
            _check_relative(rid, marker, "marker")
        if not all(c in "0123456789abcdef" for c in entry["pin"].lower()) or len(entry["pin"]) < 7:
            raise RegistryError("%s: pin must be a git object id" % rid)
        _check_relative(rid, entry["docs"], "docs")
    return data


def roots(extra=None):
    seen, out = set(), []
    declared = [r.strip() for r in os.environ.get("UABS_TOOL_ROOTS", "").split(os.pathsep) if r.strip()]
    if os.path.exists(PROFILE_ROOTS):
        with open(PROFILE_ROOTS, encoding="utf-8-sig") as fh:
            declared += [line.strip() for line in fh
                         if line.strip() and not line.lstrip().startswith("#")]
    for root in list(extra or []) + declared + list(DEFAULT_ROOTS):
        root = os.path.expanduser(os.path.expandvars(root)) if root else ""
        norm = os.path.normcase(os.path.realpath(root)) if root else ""
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


def pointer_root(entry):
    """Resolve an owner pointer (e.g. Reverse THIS! kit.json) into its root."""
    pointer = entry.get("pointer")
    if not pointer:
        return None
    pointer = os.path.expandvars(pointer)
    try:
        with open(pointer, encoding="utf-8-sig") as fh:
            receipt = json.load(fh)
    except (OSError, ValueError):
        return None
    root = receipt.get("kit_root")
    return root if isinstance(root, str) and os.path.isdir(root) else None


def _children(path):
    try:
        return os.listdir(path)
    except OSError:
        return []


def _marker_present(root, marker):
    if any(ch in marker for ch in "*?["):
        return bool(glob.glob(os.path.join(root, marker)))
    return os.path.exists(os.path.join(root, marker))


SKIP_DIRS = {".git", ".venv", "venv", "node_modules", "__pycache__", "build", "dist",
             "artifacts", "cache", "caches", "local-only", "private-tweaks", "textures", "meshes"}


def _subdirs(root, depth=3):
    """Breadth-first subdirectories, bounded. A moved owner is usually one level
    down; a whole-drive walk is not worth the seconds it costs."""
    level = [root]
    for _ in range(depth):
        nxt = []
        for parent in level:
            for name in sorted(_children(parent)):
                candidate = os.path.join(parent, name)
                if name.lower() not in SKIP_DIRS and os.path.isdir(candidate) and not os.path.islink(candidate):
                    nxt.append(candidate)
        for candidate in nxt:
            yield candidate
        level = nxt


def directory_index(search_roots):
    """One bounded inventory per report, shared by every companion lookup."""
    seen, result = set(), []
    for root in search_roots:
        for candidate in _with_root(root):
            key = os.path.normcase(os.path.realpath(candidate))
            if key in seen:
                continue
            seen.add(key)
            result.append(candidate)
            if len(result) >= 5000:
                return result
    return result


def _with_root(root):
    yield root
    yield from _subdirs(root)


def discover(entry, search_roots, directories=None):
    """A valid explicit owner wins. Otherwise require one unique marker match."""
    markers = entry["markers"]
    env_root = os.environ.get(entry.get("root_env", ""), "")
    if env_root:
        env_root = os.path.expanduser(os.path.expandvars(env_root))
        if all(_marker_present(env_root, m) for m in markers):
            return env_root, [env_root], "environment"
    pointer = pointer_root(entry)
    if pointer and all(_marker_present(pointer, m) for m in markers):
        return pointer, [pointer], "owner-pointer"
    wanted = owner_names(entry)
    directories = directory_index(search_roots) if directories is None else directories
    candidates = [p for p in directories if _norm(os.path.basename(p.rstrip("\\/"))) in wanted
                  and all(_marker_present(p, m) for m in markers)]
    return (candidates[0] if len(candidates) == 1 else None), candidates, "bounded-discovery"


def find(entry, search_roots):
    return discover(entry, search_roots)[0]


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


def status(search_roots, data=None, directories=None):
    data = data or load()
    report = {}
    directories = directory_index(search_roots) if directories is None else directories
    for cid, entry in sorted(data["companions"].items()):
        path, candidates, source = discover(entry, search_roots, directories)
        if path:
            state = "INSTALLED_UNVERIFIED"
        elif len(candidates) > 1:
            state = "AMBIGUOUS"
        else:
            # Only an exact owner-named folder counts as a half-install; the game folder must never
            # be mistaken for its Forge.
            wanted = owner_names(entry)
            path = next((p for p in directories if _norm(os.path.basename(p)) in wanted), None)
            state = "DISCOVERED" if path else "NOT_FOUND"
        report[cid] = {"state": state, "path": path, "title": entry["title"],
                       "repo": entry["repo"], "kind": entry["install"]["kind"],
                       "doctor": (entry.get("doctor") or {}).get("entrypoint"),
                       "ready": False, "evidence": "markers-only", "source": source,
                       "candidates": candidates}
    return report


def recommended_status(search_roots, data=None, directories=None):
    """Detect recommended third-party packs. Nothing here is installed or run by the bundle."""
    data = data or load()
    out = {}
    directories = directory_index(search_roots) if directories is None else directories
    for rid, entry in sorted((data.get("recommended") or {}).items()):
        path, candidates, source = discover(entry, search_roots, directories)
        out[rid] = {"state": "MARKERS_FOUND" if path else "NOT_FOUND", "path": path,
                    "title": entry["title"], "repo": entry["repo"], "pin": entry["pin"],
                    "license": entry["license"], "docs": entry["docs"], "ready": False,
                    "evidence": "markers-only"}
    return out


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

    search_roots = roots(args.roots)
    directories = directory_index(search_roots)
    report = status(search_roots, data, directories)
    rec = recommended_status(search_roots, data, directories)
    if args.json:
        print(json.dumps({"companions": report,
                          "recommended": rec}, indent=1))
        return 0
    for cid, row in report.items():
        print("%-16s %-10s %s" % (cid, row["state"], row["path"] or row["repo"]))
    if rec:
        print()
        for rid, row in rec.items():
            print("%-16s %-10s %s" % (rid, row["state"], row["path"] or row["repo"] + "@" + row["pin"][:7]))
    counts = {}
    for row in report.values():
        counts[row["state"]] = counts.get(row["state"], 0) + 1
    print("\n" + ", ".join("%s=%d" % (k, v) for k, v in sorted(counts.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
