"""Every declared copy of the pack version must agree with VERSION.txt.

The version is restated in files that cannot read each other: an installer
banner, a JSON catalog, two docs and a validation report. Restating is
unavoidable; drifting silently is not. v7.5.3 shipped with CATALOG.json still
declaring 6.8.0 -- seven minor versions behind -- because nothing checked.

`--set X.Y.Z` rewrites every declaration below in place (one command per
release); the changelog sections stay hand-written and are still checked.

Companion products (Skyrim Forge, Reverse THIS!) release on their own. The
bundle declares only a floor for each, so it must never restate their versions
or skill counts: a restated number is a claim that goes stale on their next
release. Their contracts are tested against the latest release CI fetches.
"""
import io
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
V = r"((?:[0-9]+\.)+[0-9]+)"
# (file, pattern whose group 1 is the bare version, label)
DECLARATIONS = [
    ("README.md", r"^<!-- Ultimate AI Starter Bundle v" + V + r" -->", "README.md (first line)"),
    ("README.md", r"^# Ultimate AI Starter Bundle v" + V, "README.md (title)"),
    ("START-HERE.txt", r"^Ultimate AI Starter Bundle V" + V, "START-HERE.txt"),
    ("INSTALL-AIO.ps1", r"Ultimate AI Starter Bundle v" + V + r" - ALL-IN-ONE INSTALLER", "INSTALL-AIO.ps1 (banner)"),
    ("INSTALL-AIO.ps1", r"version = '" + V + r"'", "INSTALL-AIO.ps1 (state)"),
    # The console title is the first thing a fresh user sees; it sat at v7.8.0
    # for a whole release before it was checked.
    ("START-HERE.bat", r"^title Ultimate AI Starter Bundle v" + V, "START-HERE.bat (title)"),
    ("BUNDLED-TOOLS/CATALOG.json", r'"pack_version":\s*"' + V + '"', "CATALOG.json pack_version"),
    ("BUNDLED-TOOLS/CATALOG.json", r'"catalog_version":\s*"' + V + '"', "CATALOG.json catalog_version"),
    ("BUNDLED-TOOLS/OFFLINE-MANIFEST.json", r'"pack_version":\s*"' + V + '"', "OFFLINE-MANIFEST.json pack_version"),
    # PROFILES.json is a file users open to understand the MCP cost model; it
    # sat at 8.0.0 through 8.6.x because nothing read it. An unread version is
    # still a claim.
    ("BUNDLED-TOOLS/PROFILES.json", r'"pack_version":\s*"' + V + '"', "PROFILES.json pack_version"),
    ("BUNDLED-TOOLS/PROFILES.json", r'"catalog_version":\s*"' + V + '"', "PROFILES.json catalog_version"),
    ("VALIDATION.json", r'"version":\s*"' + V + '"', "VALIDATION.json version"),
    ("VALIDATION.json", r'"release_tag":\s*"v' + V + '"', "VALIDATION.json release_tag"),
]
LIVE_DOCS = ("README.md", "START-HERE.txt", "AIO-GUIDE.md")
COMPANION_VERSION = re.compile(r"\b(Skyrim Forge|Reverse THIS!?)\*{0,2}\s+v?\d+\.\d+(?:\.\d+)?\b")
SKYRIM_COUNT = re.compile(r"\b(\d+)\s+specialist\s+skills\b|\b(\d+)-skill\s+Skyrim\b|"
                          r"\b(\d+)\s+with\s+the\s+Skyrim\s+pack\b|\bskyrim`?\s*\((\d+)\s+skills\b", re.I)


def read(rel):
    with io.open(os.path.join(ROOT, rel), encoding="utf-8-sig") as fh:
        return fh.read()


def validate_skyrim_claims(text):
    """Forge owns its skill count; any number here goes stale on its next release."""
    return ["restates a Skyrim skill count (%s); link Forge instead" % m.group(0) for m in SKYRIM_COUNT.finditer(text)]


def validate_companion_claims(text):
    return ["restates a companion version (%s); Forge and Reverse THIS! release on their own" % m.group(0)
            for m in COMPANION_VERSION.finditer(text)]


def set_version(bare):
    """Rewrite every declaration in place, preserving each file's bytes otherwise."""
    if not re.fullmatch(V, bare):
        raise SystemExit("--set needs a dotted version such as 8.27.0, got %r" % bare)
    for rel in sorted({rel for rel, _, _ in DECLARATIONS} | {"VERSION.txt"}):
        path = os.path.join(ROOT, rel)
        raw = open(path, "rb").read()
        bom = raw.startswith(b"\xef\xbb\xbf")
        text = raw.decode("utf-8-sig")
        if rel == "VERSION.txt":
            text = re.sub(r"v?" + V, "v" + bare, text, count=1)
        for _, pattern, label in (d for d in DECLARATIONS if d[0] == rel):
            text, count = re.subn(pattern, lambda m: m.group(0).replace(m.group(1), bare, 1), text, count=1, flags=re.M)
            if not count:
                raise SystemExit("%s: no declaration matched for %s" % (rel, label))
        open(path, "wb").write((b"\xef\xbb\xbf" if bom else b"") + text.encode("utf-8"))
    print("Declared versions set to %s; add '## %s' to CHANGELOG.md and docs/history/V%s-CHANGELOG.md." % (bare, bare, bare))


def main(argv):
    if len(argv) == 2 and argv[0] == "--set":
        set_version(argv[1].lstrip("vV"))
    version = read("VERSION.txt").strip()          # e.g. "v7.6.2"
    bare = version.lstrip("vV")                    # e.g. "7.6.2"
    print("VERSION.txt declares %s" % version)
    problems = []

    # Versions are dot-separated integers with three or more parts; the declared
    # copy must equal VERSION.txt exactly.
    for rel, pattern, label in DECLARATIONS:
        try:
            found = re.search(pattern, read(rel), re.M)
        except OSError as exc:
            problems.append("%s: unreadable (%s)" % (rel, exc))
            continue
        if not found:
            problems.append("%s: no version declaration matched %r" % (rel, pattern))
            continue
        got = found.group(1)
        print("  %-8s %-38s %s" % ("ok" if got == bare else "MISMATCH", label, got))
        if got != bare:
            problems.append("%s declares %s, expected %s" % (label, got, bare))

    try:
        catalog = json.loads(read("BUNDLED-TOOLS/CATALOG.json"))
        companions = [c for c in catalog["components"] if c.get("install") == "latest-release"]
        if {c["id"] for c in companions} != {"skyrim-forge", "reverse-this"}:
            problems.append("CATALOG.json must track skyrim-forge and reverse-this as latest-release companions")
        for comp in companions:
            pinned = sorted(set(comp) & {"version", "release_tag", "asset", "sha256", "offline_asset"})
            if pinned:
                problems.append("CATALOG.json %s pins %s; an owner release would need a bundle release" % (comp["id"], ", ".join(pinned)))
            if not re.fullmatch(r"\d+\.\d+\.\d+", str(comp.get("min_version", ""))) or "{version}" not in str(comp.get("asset_template", "")):
                problems.append("CATALOG.json %s needs min_version and asset_template" % comp["id"])
        print("  ok       companions track latest releases       %s" % ", ".join(
            "%s>=%s" % (c["id"], c.get("min_version")) for c in companions))
    except Exception as exc:
        problems.append("CATALOG.json unreadable: %s" % exc)
    # Forge's standalone Register-MCP.ps1 defers to the toolbox catalog INSTALL-AIO
    # copies to toolbox-profiles.json; without it each installer undoes the other.
    if "toolbox-profiles.json" not in read("INSTALL-AIO.ps1"):
        problems.append("INSTALL-AIO.ps1 no longer writes toolbox-profiles.json, which Forge Register-MCP.ps1 reads")
    # Skyrim Forge and Reverse THIS! link to this anchor instead of restating the
    # ownership model; renaming it would break their links silently.
    if '<a id="ownership"></a>' not in read("README.md"):
        problems.append("README.md lost the #ownership anchor the companion READMEs link to")
    for rel in LIVE_DOCS:
        text = read(rel)
        problems.extend("%s %s" % (rel, error) for error in validate_skyrim_claims(text) + validate_companion_claims(text))

    changelog = read("CHANGELOG.md")
    if not re.search(r"^## %s\b" % re.escape(bare), changelog, re.M):
        problems.append("CHANGELOG.md has no '## %s' section" % bare)
    else:
        print("  %-8s %-38s ## %s" % ("ok", "CHANGELOG.md", bare))
    history = os.path.join(ROOT, "docs", "history", "V%s-CHANGELOG.md" % bare)
    if not os.path.isfile(history):
        problems.append("docs/history/V%s-CHANGELOG.md is missing" % bare)
    else:
        print("  %-8s %-38s present" % ("ok", "docs/history/V%s-CHANGELOG.md" % bare))

    if problems:
        print("\nVersion drift:")
        for p in problems:
            print("  - %s" % p)
        return 1
    print("\nAll declared versions agree.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
