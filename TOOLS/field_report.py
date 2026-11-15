"""Record a defect found in an owner's forge or tool while using it from another project.

The session that hits the defect does not own that code, so it neither patches it
nor drops it: it appends one entry to FIELD-REPORTS.md in the owner's source folder
and carries on with a workaround. The owner's own session reproduces it, fixes it
with a test and deletes the entry.

    python TOOLS/field_report.py roblox-forge --title "doctor fails on a path with a space" \
        --version 0.16.3 --command "rbforge doctor" --expected "exit 0" --actual "traceback ..." \
        --workaround "ran it from a short path" --found-in "a Roblox obby project"
    python TOOLS/field_report.py bundle --title "..."      # a defect in this bundle
    python TOOLS/field_report.py --list [--json]            # open reports on this machine

Owner ids are the ones `python TOOLS/companion_registry.py --verify` prints.
"""

import argparse
import datetime
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import companion_registry  # noqa: E402

INBOX = "FIELD-REPORTS.md"
HEADER = (
    "# Field reports\n\n"
    "Defects an agent hit while using this tool from another project. They are recorded\n"
    "here instead of being patched from outside. Owner: reproduce it, fix it with a test,\n"
    "note it in the changelog, then delete the entry. This file is a local inbox, not\n"
    "release content; it is listed in .git/info/exclude.\n"
)
FIELDS = (("version", "Version"), ("command", "Command"), ("expected", "Expected"),
          ("actual", "Actual"), ("workaround", "Workaround"), ("found_in", "Found while"))


class UnknownOwner(ValueError):
    pass


def _redact(text):
    """Another owner's tree is not the place for this user's home folder."""
    home = os.path.expanduser("~")
    for variant in {home, home.replace("\\", "/"), home.replace("/", "\\")}:
        if variant and variant not in ("~", "/", "\\"):
            text = re.sub(re.escape(variant), "~", text, flags=re.I)
    return re.sub(r"(?i)([A-Z]:[\\/]Users[\\/])[^\\/\s\"']+", r"\1<user>", text)


def _one_line(text):
    return " ".join(str(text).split())


def owner_root(owner, data=None, search_roots=None, bundle_root=None):
    """Where this owner's source lives: its checkout when there is one, else its install."""
    if owner == "bundle":
        return bundle_root or os.path.dirname(HERE)
    data = data or companion_registry.load()
    if owner not in data["companions"]:
        raise UnknownOwner("unknown owner %r; known: bundle, %s" % (owner, ", ".join(sorted(data["companions"]))))
    roots = companion_registry.roots() if search_roots is None else search_roots
    row = companion_registry.status(roots, data)[owner]
    root = row["source_path"] or row["path"]
    if not root:
        raise UnknownOwner("%s was not found on this machine (%s); report it at %s"
                           % (owner, row["state"], row["repo"]))
    return root


def _exclude(root):
    """Keep the inbox out of the owner's commits without touching its tracked files."""
    info = os.path.join(root, ".git", "info")
    if not os.path.isdir(os.path.join(root, ".git")):
        return
    os.makedirs(info, exist_ok=True)
    path = os.path.join(info, "exclude")
    try:
        with open(path, encoding="utf-8") as handle:
            current = handle.read()
    except OSError:
        current = ""
    if INBOX not in current.split():
        with open(path, "a", encoding="utf-8", newline="\n") as handle:
            handle.write(("" if current.endswith("\n") or not current else "\n") + INBOX + "\n")


def _titles(text):
    return [line[3:].strip() for line in text.splitlines() if line.startswith("## ")]


def record(owner, title, data=None, search_roots=None, today=None, bundle_root=None, **fields):
    title = _redact(_one_line(title))
    if not title:
        raise ValueError("a report needs a title")
    root = owner_root(owner, data, search_roots, bundle_root)
    today = today or datetime.date.today().isoformat()
    path = os.path.join(root, INBOX)
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
    except OSError:
        text = HEADER
    known = {t.lower(): t for t in _titles(text)}
    if title.lower() in known:
        # One entry per defect: a repeat adds a date under the existing heading.
        lines = text.split("\n")
        start = lines.index("## " + known[title.lower()])
        end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith("## ")), len(lines))
        while end > start + 1 and not lines[end - 1].strip():
            end -= 1
        lines.insert(end, "- Seen again: %s" % today)
        text, state = "\n".join(lines), "seen-again"
    else:
        entry = ["", "## " + title, "- Reported: %s" % today]
        for key, label in FIELDS:
            value = _redact(_one_line(fields.get(key) or ""))
            if value:
                entry.append("- %s: %s" % (label, "`%s`" % value if key == "command" else value))
        text, state = text.rstrip("\n") + "\n" + "\n".join(entry) + "\n", "recorded"
    temp = path + ".tmp"
    with open(temp, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text if text.endswith("\n") else text + "\n")
    os.replace(temp, path)
    _exclude(root)
    return {"owner": owner, "path": path, "state": state, "title": title}


def open_reports(data=None, search_roots=None, bundle_root=None):
    """Every owner on this machine that has an inbox with at least one entry."""
    data = data or companion_registry.load()
    roots = companion_registry.roots() if search_roots is None else search_roots
    found = {}
    owners = [("bundle", bundle_root)] if bundle_root or search_roots is None else []
    owners += [(cid, None) for cid in sorted(data["companions"])]
    for cid, explicit in owners:
        try:
            root = owner_root(cid, data, roots, explicit)
        except UnknownOwner:
            continue
        path = os.path.join(root, INBOX)
        try:
            with open(path, encoding="utf-8") as handle:
                titles = _titles(handle.read())
        except OSError:
            continue
        if titles:
            found[cid] = {"path": path, "titles": titles}
    return found


def main(argv=None):
    ap = argparse.ArgumentParser(description="Record a defect in the owner's own folder (never patches it)")
    ap.add_argument("owner", nargs="?", help="registry id, or 'bundle'")
    ap.add_argument("--title", help="the defect in one line")
    for key, label in FIELDS:
        ap.add_argument("--" + key.replace("_", "-"), help=label.lower())
    ap.add_argument("--list", action="store_true", help="show the open reports on this machine")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--bundle-root", help=argparse.SUPPRESS)
    args = ap.parse_args(argv)

    if args.list:
        found = open_reports(bundle_root=args.bundle_root)
        if args.owner:
            found = {k: v for k, v in found.items() if k == args.owner}
        if args.json:
            print(json.dumps(found, indent=1))
        else:
            for cid, row in found.items():
                print("%s  (%s)" % (cid, row["path"]))
                for title in row["titles"]:
                    print("  - " + title)
            if not found:
                print("no open field reports")
        return 0
    if not args.owner or not args.title:
        ap.error("give an owner id and --title, or --list")
    try:
        result = record(args.owner, args.title, bundle_root=args.bundle_root,
                        **{key: getattr(args, key) for key, _ in FIELDS})
    except (UnknownOwner, companion_registry.RegistryError) as exc:
        print(json.dumps({"error": str(exc)}) if args.json else str(exc))
        return 2
    print(json.dumps(result, indent=1) if args.json else "%s: %s" % (result["state"], result["path"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
