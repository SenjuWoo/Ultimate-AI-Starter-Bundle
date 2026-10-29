"""Every declared copy of the pack version must agree with VERSION.txt.

The version is restated in files that cannot read each other: an installer
banner, a JSON catalog, two docs and a validation report. Restating is
unavoidable; drifting silently is not. v7.5.3 shipped with CATALOG.json still
declaring 6.8.0 -- seven minor versions behind -- because nothing checked.
"""
import io
import json
import os
import re
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))


def read(rel):
    with io.open(os.path.join(ROOT, rel), encoding="utf-8-sig") as fh:
        return fh.read()


def validate_skyrim_claims(text, expected):
    """Check every public wording against the pinned specialist inventory."""
    pattern = (r"\b(\d+)\s+specialist\s+skills\b|\b(\d+)-skill\s+Skyrim\b|"
               r"\b(\d+)\s+with\s+the\s+Skyrim\s+pack\b|"
               r"\bskyrim`?\s*\((\d+)\s+skills\b")
    problems = []
    for match in re.finditer(pattern, text, re.I):
        count = next(int(value) for value in match.groups() if value is not None)
        if count != expected:
            problems.append("claims %s Skyrim skills; pinned Forge has %s" % (count, expected))
    return problems


def main():
    version = read("VERSION.txt").strip()          # e.g. "v7.6.2"
    bare = version.lstrip("vV")                    # e.g. "7.6.2"
    print("VERSION.txt declares %s" % version)

    problems = []

    def check(rel, pattern, expected, label=None):
        try:
            text = read(rel)
        except OSError as exc:
            problems.append("%s: unreadable (%s)" % (rel, exc))
            return
        found = re.search(pattern, text, re.M)
        if not found:
            problems.append("%s: no version declaration matched %r" % (rel, pattern))
            return
        got = found.group(1)
        status = "ok" if got == expected else "MISMATCH"
        print("  %-8s %-34s %s" % (status, label or rel, got))
        if got != expected:
            problems.append("%s declares %s, expected %s" % (rel, got, expected))

    # Versions are dot-separated integers with three or more parts (3-part
    # normal releases, 4-part point releases such as 7.9.8.5). The declared
    # copy must equal VERSION.txt exactly either way.
    check("README.md", r"^# Ultimate AI Starter Bundle v((?:[0-9]+\.)+[0-9]+)", bare)
    check("START-HERE.txt", r"^Ultimate AI Starter Bundle V((?:[0-9]+\.)+[0-9]+)", bare)
    check("INSTALL-AIO.ps1",
          r"Ultimate AI Starter Bundle v((?:[0-9]+\.)+[0-9]+) - ALL-IN-ONE INSTALLER", bare,
          "INSTALL-AIO.ps1 (banner)")
    check("INSTALL-AIO.ps1", r"version = '((?:[0-9]+\.)+[0-9]+)'", bare,
          "INSTALL-AIO.ps1 (state)")
    # The two console titles are the first thing a fresh user sees. Nothing
    # checked them before 7.9.0, so both sat at v7.8.0 for the whole release.
    check("START-HERE.bat",
          r"^title Ultimate AI Starter Bundle v((?:[0-9]+\.)+[0-9]+)", bare,
          "START-HERE.bat (title)")

    try:
        catalog = json.loads(read("BUNDLED-TOOLS/CATALOG.json"))
        got = catalog.get("pack_version")
        print("  %-8s %-34s %s" % ("ok" if got == bare else "MISMATCH",
                                   "BUNDLED-TOOLS/CATALOG.json", got))
        if got != bare:
            problems.append("CATALOG.json pack_version is %s, expected %s" % (got, bare))
        packs = json.loads(read("BUNDLED-TOOLS/PACKS.json"))["packs"]
        expected_skills = set(packs["skyrim"]["skills"])
        pin = next(c for c in catalog["components"] if c["id"] == "skyrim-forge")
        archive = os.path.join(ROOT, "BUNDLED-TOOLS", "offline", pin["asset"])
        with zipfile.ZipFile(archive) as payload:
            names = {p.split("/skills/", 1)[1].split("/", 1)[0] for p in payload.namelist()
                     if "/integrations/skyrim-pack/skills/" in p and p.endswith("/SKILL.md")
                     and p.split("/skills/", 1)[1].count("/") == 1}
            # Contract, not bytes: INSTALL reads doctor.result and doctor.read_only_ready.
            env = [payload.read(p).decode("utf-8", "replace") for p in payload.namelist()
                   if p.endswith("/skyrim_forge/environment.py")]
            for field in ('"result"', '"read_only_ready"'):
                if not env or field not in env[0]:
                    problems.append("pinned Forge doctor no longer emits %s, which TOOLS/Install-SkyrimForge.ps1 reads" % field)
            # Contract: standalone Forge registration defers to the toolbox catalog INSTALL-AIO copies
            # to toolbox-profiles.json; without it each installer undoes the other's MCP entries.
            reg = [payload.read(p).decode("utf-8-sig", "replace") for p in payload.namelist()
                   if p.endswith("/Register-MCP.ps1") and p.count("/") == 1]
            if not reg or "toolbox-profiles.json" not in reg[0] or "DEFERRED" not in reg[0]:
                problems.append("pinned Forge Register-MCP.ps1 does not defer to the bundle toolbox (toolbox-profiles.json)")
        if "toolbox-profiles.json" not in read("INSTALL-AIO.ps1"):
            problems.append("INSTALL-AIO.ps1 no longer writes toolbox-profiles.json, which Forge Register-MCP.ps1 reads")
        if names != expected_skills:
            problems.append("PACKS.json Skyrim inventory differs from pinned Forge canonical tree")
        for rel in ("README.md", "START-HERE.txt", "AIO-GUIDE.md"):
            problems.extend("%s %s" % (rel, error)
                            for error in validate_skyrim_claims(read(rel), len(names)))
        print("  ok       Skyrim skill inventory             %s" % len(names))
    except Exception as exc:
        problems.append("CATALOG.json unreadable: %s" % exc)

    # PROFILES.json carries its own pack_version/catalog_version. Nothing reads
    # them, which is exactly why they rotted: the file sat at 8.0.0 while the
    # pack shipped through 8.6.x, and it is a file users open to understand the
    # MCP cost model. An unread version string is still a claim.
    try:
        profiles = json.loads(read("BUNDLED-TOOLS/PROFILES.json"))
        for field in ("pack_version", "catalog_version"):
            got = profiles.get(field)
            print("  %-8s %-34s %s" % ("ok" if got == bare else "MISMATCH",
                                       "BUNDLED-TOOLS/PROFILES.json:" + field, got))
            if got != bare:
                problems.append("PROFILES.json %s is %s, expected %s" % (field, got, bare))
    except Exception as exc:
        problems.append("PROFILES.json unreadable: %s" % exc)

    try:
        validation = json.loads(read("VALIDATION.json"))
        got = validation.get("version")
        print("  %-8s %-34s %s" % ("ok" if got == bare else "MISMATCH",
                                   "VALIDATION.json", got))
        if got != bare:
            problems.append("VALIDATION.json version is %s, expected %s" % (got, bare))
        check("VALIDATION.json", r'"release_tag":\s*"([^"]+)"', "v" + bare,
              "VALIDATION.json release_tag")
    except Exception as exc:
        problems.append("VALIDATION.json unreadable: %s" % exc)

    changelog = read("CHANGELOG.md")
    if not re.search(r"^## %s\b" % re.escape(bare), changelog, re.M):
        problems.append("CHANGELOG.md has no '## %s' section" % bare)
    else:
        print("  %-8s %-34s ## %s" % ("ok", "CHANGELOG.md", bare))

    history = os.path.join(ROOT, "docs", "history", "V%s-CHANGELOG.md" % bare)
    if not os.path.isfile(history):
        problems.append("docs/history/V%s-CHANGELOG.md is missing" % bare)
    else:
        print("  %-8s %-34s present" % ("ok", "docs/history/V%s-CHANGELOG.md" % bare))

    if problems:
        print("\nVersion drift:")
        for p in problems:
            print("  - %s" % p)
        return 1
    print("\nAll declared versions agree.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
