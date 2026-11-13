"""Take a frozen machine map out of Hermes memory.

Hermes can import another agent's setup. When it imports an instruction file
this bundle wrote, the personal profile block lands in `memories/MEMORY.md` as
memory entries, and every profile cloned afterwards inherits them. That block
holds the machine map: the bundle folder, the Python runtime, tool roots. In an
instruction file the installer rewrites it on every run; in memory it is frozen
on the day of the import, so months later every Hermes profile is still told
about folders and interpreters that are gone.

The block is recognisable by the markers the bundle wraps it in
(`<!-- UABS-PROFILE -->` ... `<!-- /UABS-PROFILE -->`). This tool replaces the
entries from the opening marker to the closing one with a single entry that
points at the live map. Every other entry, imported or not, is left as it is,
and a backup is written beside the file first.

    python TOOLS/hermes_memory.py            report
    python TOOLS/hermes_memory.py --json
    python TOOLS/hermes_memory.py --fix      back up and replace the frozen block
"""
import argparse
import datetime
import json
import os
import re
import sys

SEPARATOR = "\n§\n"
OPEN = re.compile(r"<!--\s*UABS-PROFILE\s*-->")
CLOSE = re.compile(r"<!--\s*/UABS-PROFILE\s*-->")
NAMES = ("MEMORY.md", "USER.md")
POINTER = ("Machine paths: read MACHINE-MAP.md and PROFILE.md in %USERPROFILE%\\.uabs\\profile before writing a "
           "path. The bundle installer regenerates the map on every run; it lists the apps and owner forges that "
           "answer by name. Do not trust a path remembered from an earlier session over that file.")


def hermes_home():
    explicit = os.environ.get("HERMES_HOME")
    if explicit:
        return explicit
    local = os.environ.get("LOCALAPPDATA")
    candidates = ([os.path.join(local, "hermes")] if local else []) + [os.path.join(os.path.expanduser("~"), ".hermes")]
    return next((path for path in candidates if os.path.isdir(path)), candidates[0])


def memory_files(home):
    folders = [os.path.join(home, "memories")]
    profiles = os.path.join(home, "profiles")
    try:
        folders += [os.path.join(profiles, name, "memories") for name in sorted(os.listdir(profiles))]
    except OSError:
        pass
    return [os.path.join(folder, name) for folder in folders for name in NAMES
            if os.path.isfile(os.path.join(folder, name))]


def split_entries(text):
    return text.replace("\r\n", "\n").split(SEPARATOR)


def classify(text):
    """(entries to keep, frozen entries). A block that never closes is left alone."""
    kept, dropped, pending, inside = [], [], [], False
    for entry in split_entries(text):
        if not inside and not OPEN.search(entry):
            kept.append(entry)
            continue
        inside = True
        pending.append(entry)
        if CLOSE.search(entry):
            dropped += pending
            kept.append(POINTER)
            pending, inside = [], False
    return kept + pending, dropped


def inspect(path):
    with open(path, encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    kept, dropped = classify(text)
    return {"path": path, "bytes": len(text.encode("utf-8")), "entries": len(kept) + len(dropped) - (1 if dropped else 0),
            "imported": len(dropped), "kept": len([entry for entry in kept if entry.strip()]) - (1 if dropped else 0),
            "_kept": kept}


def clean(row, stamp=None):
    stamp = stamp or datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = "%s.before-import-cleanup-%s.bak" % (row["path"], stamp)
    with open(row["path"], "rb") as handle:
        original = handle.read()
    with open(backup, "wb") as handle:
        handle.write(original)
    with open(backup, "rb") as handle:
        if handle.read() != original:
            raise OSError("backup did not read back; %s was left unchanged" % row["path"])
    kept = [entry for entry in row["_kept"] if entry.strip()]
    text = SEPARATOR.join(entry.strip("\n") for entry in kept)
    temp = row["path"] + ".tmp"
    with open(temp, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(text + ("\n" if text else ""))
    os.replace(temp, row["path"])
    return backup


def main(argv=None):
    ap = argparse.ArgumentParser(description="Report or replace a frozen machine map in Hermes memory")
    ap.add_argument("--home", help="Hermes home (default: HERMES_HOME, then the usual folders)")
    ap.add_argument("--fix", action="store_true", help="back up each affected file and replace the frozen block with a pointer to the live map")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    home = args.home or hermes_home()
    rows = [inspect(path) for path in memory_files(home)] if os.path.isdir(home) else []
    affected = [row for row in rows if row["imported"]]
    if args.fix:
        for row in affected:
            row["backup"] = clean(row)
    for row in rows:
        row.pop("_kept", None)
    if args.json:
        print(json.dumps({"home": home, "files": rows, "affected": len(affected), "fixed": bool(args.fix)}, indent=1))
    else:
        for row in affected:
            print("%s: %d of %d entries are a frozen copy of the machine map (%d bytes)%s"
                  % (row["path"], row["imported"], row["entries"], row["bytes"],
                     "; cleaned, backup " + row["backup"] if args.fix else ""))
        if not affected:
            print("no frozen machine map in Hermes memory")
    return 0 if args.fix or not affected else 1


if __name__ == "__main__":
    sys.exit(main())
