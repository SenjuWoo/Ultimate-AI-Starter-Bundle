"""Install or remove the two MIT skill packs the bundle recommends, at a pinned revision.

Why an installer instead of vendoring: these are 64 skills between them. Copying them
into every provider would put 64 extra skill descriptions in front of every request and
collide with the bundle's own owners (code review, debugging, TDD, planning). Instead
this installs a curated, namespaced subset on request, keeps upstream's shared
`references/` and sibling files next to the skills that need them, records a receipt,
and can remove exactly what it added.

    python TOOLS/recommended_skills.py list
    python TOOLS/recommended_skills.py plan  pocock --provider claude
    python TOOLS/recommended_skills.py install pocock --provider claude --apply
    python TOOLS/recommended_skills.py remove  pocock --provider claude --apply

Never overwrites a user's skill: it is moved to `<name>.backup-<utc>` and restored by
`remove`. Reinstalling replaces this tool's own previous copy instead of backing it up,
so install -> install -> remove leaves the user's original exactly as found. Receipts are
keyed by destination root and written after every item, so different homes never mix and
an interrupted run is still removable. Downloads use codeload at the pinned SHA; nothing
runs from upstream. Installed frontmatter is rewritten to the namespaced name so the
directory, the model-visible `name` and the router agree, with `license`/`upstream`
provenance, and each pack's LICENSE sits beside the skills.
"""

import argparse
import hashlib
import io
import json
import os
import re
import shutil
import sys
import tarfile
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

PACKS = {
    "pocock": {
        "repo": "mattpocock/skills",
        "pin": "4ae2317ddb22b046e26455e4f9c9b3aaaf62212d",
        "license": "MIT",
        "prefix": "pocock-",
        # Chosen for gaps the bundle does not already own; see
        # docs/RECOMMENDED-SKILLS-PACKS.md for the per-skill decision.
        "skills": [
            "engineering/domain-modeling",
            "engineering/codebase-design",
            "engineering/to-spec",
            "engineering/triage",
            "engineering/retro",
            "productivity/writing-for-agents",
        ],
        "root_references": [],
    },
    "addy": {
        "repo": "addyosmani/agent-skills",
        "pin": "301b02b12bff98e4688e6984af6556802322bbde",
        "license": "MIT",
        "prefix": "addy-",
        "skills": [
            "security-and-hardening",
            "performance-optimization",
            "observability-and-instrumentation",
            "api-and-interface-design",
            "context-engineering",
            "deprecation-and-migration",
        ],
        "root_references": [
            "references/security-checklist.md",
            "references/performance-checklist.md",
            "references/observability-checklist.md",
            "references/definition-of-done.md",
        ],
    },
}

STATE = Path(os.environ.get("LOCALAPPDATA", Path.home())) / "Ultimate-AI-Starter-Bundle" / "recommended-skills"


def provider_dirs(home=None):
    home = Path(home or Path.home())
    local = Path(os.environ.get("LOCALAPPDATA", home / "AppData" / "Local"))
    claude = Path(os.environ.get("CLAUDE_CONFIG_DIR") or (home / ".claude"))
    return {
        "claude": claude / "skills",
        "codex": home / ".agents" / "skills",
        "grok": home / ".grok" / "skills",
        "kimi": home / ".kimi-code" / "skills",
        "hermes": local / "hermes" / "skills",
        "antigravity": home / ".gemini" / "config" / "skills",
    }


def receipt_path(pack, provider, home=None):
    """One receipt per pack+provider+destination root, so homes never share state."""
    dest = provider_dirs(home)[provider]
    digest = hashlib.sha256(str(dest).lower().encode("utf-8")).hexdigest()[:10]
    return STATE / ("%s-%s-%s.json" % (pack, provider, digest))


def fetch_tree(pack, cache=None):
    """Download the pinned tarball and return the extracted root. Cached by SHA."""
    spec = PACKS[pack]
    cache = Path(cache or STATE / "cache" / ("%s-%s" % (pack, spec["pin"][:12])))
    if (cache / ".ok").is_file():
        return cache
    url = "https://codeload.github.com/%s/tar.gz/%s" % (spec["repo"], spec["pin"])
    with urllib.request.urlopen(url, timeout=120) as response:
        blob = response.read()
    cache.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tar:
        root = tar.getmembers()[0].name.split("/")[0]
        for member in tar.getmembers():
            if member.name in (root, root + "/"):
                continue
            member.name = member.name[len(root) + 1:]
            tar.extract(member, cache, filter="data")
    (cache / ".ok").write_text(spec["pin"], encoding="utf-8")
    return cache


def plan(pack, provider, home=None, tree=None):
    """Pure: says what would be copied where. `tree` is a prepared upstream root."""
    spec = PACKS[pack]
    dest_root = provider_dirs(home)[provider]
    actions = []
    for rel in spec["skills"]:
        name = spec["prefix"] + Path(rel).name
        src = Path(tree) / "skills" / rel if tree else None
        actions.append({"kind": "skill", "name": name, "src": str(src) if src else None,
                        "dest": str(dest_root / name), "exists": (dest_root / name).exists()})
    for rel in spec["root_references"]:
        src = Path(tree) / rel if tree else None
        # Upstream links these as `../../references/<file>` from a skill folder, so
        # they belong at <provider>/references, not inside skills/.
        dest = dest_root.parent / "references" / Path(rel).name
        actions.append({"kind": "reference", "name": Path(rel).name,
                        "src": str(src) if src else None,
                        "dest": str(dest), "exists": dest.exists()})
    actions.append({"kind": "license", "name": "%s-LICENSE.txt" % pack,
                    "src": str(Path(tree) / "LICENSE") if tree else None,
                    "dest": str(dest_root.parent / "references" / ("%s-LICENSE.txt" % pack)),
                    "exists": (dest_root.parent / "references" / ("%s-LICENSE.txt" % pack)).exists()})
    return actions


def _load(receipt):
    if not receipt.exists():
        return {"owned": [], "backups": {}}
    data = json.loads(receipt.read_text(encoding="utf-8"))
    data.setdefault("owned", [])
    data.setdefault("backups", {})
    return data


def _save(receipt, data, pack, provider, pin):
    STATE.mkdir(parents=True, exist_ok=True)
    data.update({"pack": pack, "provider": provider, "pin": pin,
                 "updated": datetime.now(timezone.utc).isoformat(timespec="seconds")})
    tmp = receipt.with_suffix(".tmp")
    tmp.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
    os.replace(tmp, receipt)


def _namespaced(md, name, spec):
    """Rewrite only frontmatter name/provenance; the instruction body is untouched."""
    text = md.read_text(encoding="utf-8", errors="replace")
    if not text.lstrip().startswith("---"):
        return
    end = text.find("\n---", 3)
    if end == -1:
        return
    head, rest = text[:end], text[end:]
    head = re.sub(r"(?m)^name:.*$", "name: %s" % name, head, count=1)
    if not re.search(r"(?m)^license:", head):
        head += "\nlicense: %s" % spec["license"]
    if not re.search(r"(?m)^upstream:", head):
        head += "\nupstream: %s@%s" % (spec["repo"], spec["pin"])
    md.write_text(head + rest, encoding="utf-8")


def _recover_pending(data, checkpoint):
    """Resolve a journal left by a crash without ever deleting an unbacked-up skill.

    The journal says whether the destination existed when the transaction opened.
    - No original existed: anything at `dest` is ours or a partial, so it is cleared.
    - An original existed and a backup is on disk: if `dest` is present the swap had
      completed; otherwise the backup is put back.
    - An original existed and there is no backup: the move never happened, so `dest` is
      still the user's skill and is left exactly as it is.
    """
    pending = data.get("pending")
    if not pending:
        return []
    dest = Path(pending["dest"])
    backup = Path(pending["backup"]) if pending.get("backup") else None
    staging = Path(pending["staging"]) if pending.get("staging") else None
    had_dest = bool(pending.get("had_dest", True))
    restored = []
    if staging and staging.exists():
        shutil.rmtree(staging, ignore_errors=True) if staging.is_dir() else staging.unlink()

    if not had_dest:
        if dest.exists():
            shutil.rmtree(dest) if dest.is_dir() else dest.unlink()
    elif backup and backup.exists():
        if dest.exists() and pending.get("stage") != "backed_up":
            pass  # swap completed before the journal cleared; backup stays for `remove`
        else:
            if dest.exists():  # uncommitted replacement (or a partial): discard it
                shutil.rmtree(dest) if dest.is_dir() else dest.unlink()
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(backup), str(dest))
            if data.get("backups", {}).get(str(dest)) == str(backup):
                data["backups"].pop(str(dest), None)
            restored.append(str(dest))
    # else: original existed, no backup yet -> dest is the user's own file; never touch it.
    data.pop("pending", None)
    checkpoint(data)
    return restored


def _place(src, dest, data, stamp, checkpoint):
    """Copy one item through a staging folder, journaling every destructive step.

    The journal records whether a destination existed before we touched it, so recovery
    can always tell an original from a replacement. A failure at any step rolls the item
    back before the caller moves on.
    """
    dest = Path(dest)
    staging = dest.with_name(dest.name + ".staging-" + stamp)
    if staging.exists():
        shutil.rmtree(staging) if staging.is_dir() else staging.unlink()
    try:
        staging.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(src, staging) if src.is_dir() else shutil.copy2(src, staging)
    except Exception:
        if staging.exists():
            shutil.rmtree(staging) if staging.is_dir() else staging.unlink()
        raise

    had_dest = dest.exists()
    ours = str(dest) in set(data["owned"])
    backup = None
    if had_dest and not ours:
        backup = dest.with_name(dest.name + ".backup-" + stamp)
        if backup.exists():
            backup = dest.with_name(dest.name + ".backup-" + stamp + "-2")
    data["pending"] = {"dest": str(dest), "staging": str(staging),
                       "backup": str(backup) if backup else None, "had_dest": had_dest}
    checkpoint(data)
    try:
        if had_dest:
            if ours:
                shutil.rmtree(dest) if dest.is_dir() else dest.unlink()
            else:
                shutil.move(str(dest), str(backup))
                data["backups"][str(dest)] = str(backup)
                data["pending"]["stage"] = "backed_up"
                checkpoint(data)
        shutil.move(str(staging), str(dest))
    except Exception:
        if staging.exists():
            shutil.rmtree(staging) if staging.is_dir() else staging.unlink()
        if backup and backup.exists():
            if dest.exists():
                shutil.rmtree(dest) if dest.is_dir() else dest.unlink()
            shutil.move(str(backup), str(dest))
            data["backups"].pop(str(dest), None)
        elif not had_dest and dest.exists():
            shutil.rmtree(dest) if dest.is_dir() else dest.unlink()
        data.pop("pending", None)
        checkpoint(data)
        raise
    data.pop("pending", None)


def install(pack, provider, home=None, tree=None, stamp=None):
    spec = PACKS[pack]
    stamp = stamp or datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    receipt = receipt_path(pack, provider, home)
    data = _load(receipt)
    checkpoint = lambda d: _save(receipt, d, pack, provider, spec["pin"])  # noqa: E731
    results = []
    for path in _recover_pending(data, checkpoint):
        results.append({"kind": "recovered", "name": Path(path).name, "dest": path,
                        "src": None, "exists": True, "ok": True})
    for action in plan(pack, provider, home, tree):
        src, dest = Path(action["src"]), Path(action["dest"])
        if not src.exists():
            results.append(dict(action, ok=False, message="missing in the upstream tree"))
            continue
        try:
            _place(src, dest, data, stamp, checkpoint)
        except Exception as exc:  # rollback already happened inside _place
            results.append(dict(action, ok=False, message="copy failed: %s" % exc))
            continue
        if str(dest) not in data["owned"]:
            data["owned"].append(str(dest))
        if action["kind"] == "skill":
            md = Path(dest) / "SKILL.md"
            if md.is_file():
                _namespaced(md, action["name"], spec)
        _save(receipt, data, pack, provider, spec["pin"])  # resumable after a crash
        results.append(dict(action, ok=True))
    _save(receipt, data, pack, provider, spec["pin"])
    return results, receipt


def remove(pack, provider, home=None):
    """Delete only what this tool created, then put the user's originals back."""
    receipt = receipt_path(pack, provider, home)
    if not receipt.exists():
        raise SystemExit("no receipt for %s on %s; nothing to remove" % (pack, provider))
    data = _load(receipt)
    _recover_pending(data, lambda d: _save(receipt, d, pack, provider, PACKS[pack]["pin"]))
    removed = []
    for path in data["owned"]:
        target = Path(path)
        if target.exists():
            shutil.rmtree(target) if target.is_dir() else target.unlink()
            removed.append(str(target))
    for dest, backup in data.get("backups", {}).items():
        dest, backup = Path(dest), Path(backup)
        if backup.exists():
            if dest.exists():  # ours; never merge into the user's copy
                shutil.rmtree(dest) if dest.is_dir() else dest.unlink()
            shutil.move(str(backup), str(dest))
    receipt.unlink()
    return removed


def main(argv=None):
    ap = argparse.ArgumentParser(description="Pinned, optional skill packs (MIT) with receipts")
    ap.add_argument("command", choices=("list", "plan", "install", "remove"))
    ap.add_argument("pack", nargs="?", choices=tuple(PACKS))
    ap.add_argument("--provider", default="claude", choices=tuple(provider_dirs()))
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--home")
    ap.add_argument("--tree", help="already-extracted upstream root (skips the download)")
    args = ap.parse_args(argv)

    if args.command == "list":
        for name, spec in PACKS.items():
            print("%-7s %-28s pin=%s skills=%d refs=%d"
                  % (name, spec["repo"], spec["pin"][:12], len(spec["skills"]), len(spec["root_references"])))
        return 0
    if not args.pack:
        ap.error("a pack name is required")

    if args.command == "plan":
        for action in plan(args.pack, args.provider, args.home, args.tree):
            print("  %-9s %s" % (action["kind"], action["dest"]))
        print("dry-run: nothing copied (add --apply)")
        return 0

    if args.command == "remove":
        if not args.apply:
            print("would remove %s from %s (add --apply)" % (args.pack, args.provider))
            return 0
        for path in remove(args.pack, args.provider, args.home):
            print("  removed %s" % path)
        return 0

    if args.command == "install" and not args.apply:
        for action in plan(args.pack, args.provider, args.home, args.tree):
            print("  %-9s %s" % (action["kind"], action["dest"]))
        print("dry-run: nothing copied (add --apply)")
        return 0

    tree = args.tree or str(fetch_tree(args.pack))
    results, receipt = install(args.pack, args.provider, args.home, tree)
    failures = [r for r in results if not r["ok"]]
    for item in failures:
        print("  FAILED %s %s: %s" % (item["kind"], item["name"], item["message"]))
    print("installed %d item(s), %d failure(s); receipt %s"
          % (len(results) - len(failures), len(failures), receipt))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
