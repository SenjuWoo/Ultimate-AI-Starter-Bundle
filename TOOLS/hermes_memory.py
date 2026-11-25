"""Take frozen bundle instructions and the machine map out of Hermes memory.

Hermes can import another agent's setup. When it imports an instruction file
this bundle wrote, the personal profile block lands in `memories/MEMORY.md` as
memory entries, and every profile cloned afterwards inherits them. That block
holds the machine map: the bundle folder, the Python runtime, tool roots. In an
instruction file the installer rewrites it on every run; in memory it is frozen
on the day of the import, so months later every Hermes profile is still told
about folders and interpreters that are gone.

The same import freezes every other block the bundle writes into an
instruction file: the profile (`<!-- UABS-PROFILE -->`), pack blocks
(`<!-- UABS-PACK:name -->`), the preamble and the working-agreements block.
Hermes files each line under the heading it sat below ("Skyrim pack > ...:
text"), so text that followed a marked block in the same section carries the
same heading root. All of it is refreshed live elsewhere (soul, instruction
files, skills); the frozen copy repeats retired wording on every request.

This tool removes each closed marked block and every entry filed under a
heading root one of those blocks used, leaving one entry that points at the
live map. Entries without such a root - the agent's own memories - stay as
they are, and a backup is written beside the file first.

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
# Opening markers the bundle writes into instruction files; each needs its own
# closing marker. A block that never closes is not ours to judge.
OPEN = re.compile(r"<!--\s*(?:(?P<uabs>UABS-[A-Z]+(?::[a-z0-9-]+)?)|(?P<named>personal-working-agreements|agent-team):start)\s*-->")
# "Root > Sub heading: text". `>` separates nested headings; `<` would start a marker.
HEADING = re.compile(r"(?P<path>[^:\n<]{1,240}?): ")
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
        # Dot folders (Hermes keeps removed profiles in `.deleted`) are not profiles.
        folders += [os.path.join(profiles, name, "memories") for name in sorted(os.listdir(profiles))
                    if not name.startswith(".")]
    except OSError:
        pass
    return [os.path.join(folder, name) for folder in folders for name in NAMES
            if os.path.isfile(os.path.join(folder, name))]


def split_entries(text):
    return text.replace("\r\n", "\n").split(SEPARATOR)


def _close_for(opened):
    if opened.group("uabs"):
        return re.compile(r"<!--\s*/" + re.escape(opened.group("uabs")) + r"\s*-->")
    return re.compile(r"<!--\s*" + re.escape(opened.group("named")) + r":end\s*-->")


def _root(entry):
    """Heading root Hermes filed an imported line under; None for the agent's own memories."""
    match = HEADING.match(entry.lstrip())
    return match.group("path").split(" > ")[0].strip() if match else None


def classify(text):
    """(entries to keep, frozen entries). A block that never closes is left alone.

    Closed marked blocks are frozen, and so is every entry filed under a heading
    root one of them used: Hermes files the text that followed a block in the
    same section under the same heading, so it came from the same import.
    """
    entries = split_entries(text)
    frozen, roots, index = set(), set(), 0
    while index < len(entries):
        opened = OPEN.search(entries[index])
        if not opened:
            index += 1
            continue
        close = _close_for(opened)
        tail = entries[index][opened.end():]
        end = index if close.search(tail) else next(
            (j for j in range(index + 1, len(entries)) if close.search(entries[j])), None)
        if end is None:
            index += 1
            continue
        for j in range(index, end + 1):
            frozen.add(j)
            root = _root(entries[j])
            if root:
                roots.add(root)
        index = end + 1
    if not frozen:
        return entries, []
    frozen |= {j for j, entry in enumerate(entries) if entry.strip() != POINTER and _root(entry) in roots}
    kept, dropped = [], []
    pointed = any(entry.strip() == POINTER for entry in entries)
    for j, entry in enumerate(entries):
        if j not in frozen:
            kept.append(entry)
            continue
        dropped.append(entry)
        if not pointed:
            kept.append(POINTER)
            pointed = True
    return kept, dropped


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
            print("%s: %d of %d entries are a frozen copy of bundle instructions (%d bytes)%s"
                  % (row["path"], row["imported"], row["entries"], row["bytes"],
                     "; cleaned, backup " + row["backup"] if args.fix else ""))
        if not affected:
            print("no frozen bundle instructions in Hermes memory")
    return 0 if args.fix or not affected else 1


if __name__ == "__main__":
    sys.exit(main())
