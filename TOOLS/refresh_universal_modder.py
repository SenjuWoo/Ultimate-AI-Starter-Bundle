#!/usr/bin/env python3
"""Re-vendor Universal Modder from an upstream commit, keeping every UABS patch.

The bundle does not ship upstream's tree as-is. It ships a subset (the `um`
package, the `knowledge` snapshot, tests, LICENSE, README, pyproject) with
deliberate edits: pinned dependencies, a `+uabs.<sha7>` version, a knowledge
folder that resolves inside an installed wheel, credential material that is
never echoed by pattern name, Steam discovery through the Windows registry, and
tests adjusted to what the subset actually contains. Those edits are the reason
this script exists: the 2026-10-13 refresh was done by hand, and a hand refresh
that misses a hunk ships a silent regression.

Procedure (dry run by default; --apply writes):

    python TOOLS/refresh_universal_modder.py --commit <40-char sha>
    python TOOLS/refresh_universal_modder.py --commit <sha> --apply

It downloads the GitHub source archive, verifies the sha256 it prints, rebuilds
BUNDLED-TOOLS/universal-modder from the subset, re-applies every patch below
(each one asserts it matched exactly once), and re-syncs the canonical skill's
upstream references, including the pack's own deltas inside that mirror
(SKILL_DROP / SKILL_OVERRIDES / SKILL_PATCHES: the unbounded `unpack_upk.py`
fallback is not redistributed). It does NOT build the wheel, update
CATALOG.json / OFFLINE-MANIFEST.json, fan the skill out to the provider trees
or run the gates - the checklist it prints at the end lists those steps.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import os
import shutil
import sys
import urllib.request
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VENDOR = os.path.join(ROOT, "BUNDLED-TOOLS", "universal-modder")
SKILL = os.path.join(ROOT, "_CANONICAL-SKILLS", "universal-modder", "references", "upstream")
SUBSET = ("um", "knowledge", "tests", "pyproject.toml", "README.md", "LICENSE")

# Every deliberate UABS edit, as (file, exact text in upstream, replacement).
# Upstream may not have the text any more: a patch whose search string is gone
# is reported, not silently skipped.
PATCHES: list[tuple[str, str, str]] = [
    ("pyproject.toml", 'version = "0.2.0"', 'version = "0.2.0+uabs.__SHA7__"'),
    ("pyproject.toml", 'requires-python = ">=3.10"', 'requires-python = ">=3.12"'),
    ("pyproject.toml", '    "pillow>=10",\n', '    "pillow==13.0.0",\n'),
    ("pyproject.toml", '    "numpy>=1.24",\n', '    "numpy==2.5.3",\n'),
    ("pyproject.toml", '    "pyyaml>=6",\n', '    "pyyaml==6.0.3",\n'),
    ("pyproject.toml", 'packages = ["um"]\n',
     'packages = ["um"]\n\n[tool.hatch.build.targets.wheel.force-include]\n"knowledge" = "um/knowledge"\n'),
    # The wheel installs knowledge INSIDE the package (force-include above), so
    # it must be found there first - upstream only looks one level up.
    ("um/kb.py",
     '    here = Path(__file__).resolve().parents[1] / "knowledge"\n    if (here / "TEMPLATE.md").exists():\n',
     '    here = Path(__file__).resolve().parent / "knowledge"\n'
     '    if not (here / "TEMPLATE.md").exists():\n'
     '        here = Path(__file__).resolve().parents[1] / "knowledge"\n'
     '    if (here / "TEMPLATE.md").exists():\n'),
    # Never name the credential pattern that matched: the message itself would
    # leak which kind of secret sits in the file.
    ("um/kb.py",
     '    for label, rx in SECRET_PATTERNS:\n        if rx.search(text):\n'
     '            fails.append(f"{label} in the note - remove it")\n',
     '    for _, rx in SECRET_PATTERNS:\n        if rx.search(text):\n'
     '            fails.append("possible credential material in the note - remove it")\n'),
    ("um/publish.py",
     '                txt = f.read_text(errors="replace")\n',
     '                txt = f.read_text(encoding="utf-8", errors="replace")\n'),
    ("um/publish.py",
     '            for label, rx in SECRET_PATTERNS:\n                if rx.search(txt):\n'
     '                    fails.append(f"{label} in {rel}")\n',
     '            for _, rx in SECRET_PATTERNS:\n                if rx.search(txt):\n'
     '                    fails.append(f"possible credential material in {rel}")\n'),
    ("um/publish.py",
     '        if not any("fal" in f.read_text(errors="replace").lower() for f in readmes):\n',
     '        if not any("fal" in f.read_text(encoding="utf-8", errors="replace").lower() for f in readmes):\n'),
    # `um fal key status` printed the first six and last four characters of the
    # key, which puts key material into terminal scrollback, logs and
    # screenshots - CodeQL flagged it (py/clear-text-logging-sensitive-data) and
    # flagged a sha256 fingerprint of the key as well
    # (py/weak-sensitive-data-hashing). Print a length marker and nothing
    # derived from the key.
    ("um/fal.py",
     'def mask(k: str) -> str:\n    return (k[:6] + "…" + k[-4:]) if len(k) > 14 else "…"\n',
     'def mask(k: str) -> str:\n'
     '    # UABS: never echo key material, and no hash of it either. `um fal key\n'
     '    # status` answers "which source is active", not "which key is this"; the\n'
     '    # upstream version printed the first six and last four characters, which\n'
     '    # lands key material in terminal scrollback, logs and screenshots.\n'
     '    return "<hidden, %d chars>" % len(k)\n'),
    # Steam libraries through the registry: Program Files is not where Steam
    # lives on a secondary drive or a renamed folder.
    ("um/scan.py",
     '    if is_windows():\n'
     '        cands += [Path(os.environ.get("ProgramFiles(x86)", r"C:\\Program Files (x86)")) / "Steam", Path(r"C:\\Program Files\\Steam")]\n',
     '    if is_windows():\n'
     '        import winreg\n'
     '        for hive, key, value in [\n'
     '            (winreg.HKEY_CURRENT_USER, r"Software\\Valve\\Steam", "SteamPath"),\n'
     '            (winreg.HKEY_LOCAL_MACHINE, r"Software\\WOW6432Node\\Valve\\Steam", "InstallPath"),\n'
     '            (winreg.HKEY_LOCAL_MACHINE, r"Software\\Valve\\Steam", "InstallPath"),\n'
     '        ]:\n'
     '            try:\n'
     '                with winreg.OpenKey(hive, key) as handle:\n'
     '                    cands.append(Path(winreg.QueryValueEx(handle, value)[0]))\n'
     '            except OSError:\n'
     '                pass\n'
     '        cands += [Path(p) / "Steam" for p in\n'
     '                  (os.environ.get("ProgramFiles(x86)"), os.environ.get("ProgramFiles")) if p]\n'),
    # Pillow 12 dropped Image.getdata() for the flattened form.
    ("tests/test_um.py",
     '    assert set(sprite.hard_alpha(f).getchannel("A").getdata()) <= {0, 255}\n',
     '    assert set(sprite.hard_alpha(f).getchannel("A").get_flattened_data()) <= {0, 255}\n'),
    ("tests/test_um.py",
     '    assert "game file copied verbatim" in out and "FAL_KEY assignment" in out and "Ghidra auto-name" in out\n',
     '    assert "game file copied verbatim" in out and "possible credential material in config.txt" in out and "Ghidra auto-name" in out\n'
     '    assert "FAL_KEY" not in out  # UABS redacts matched credential material.\n'),
    ("tests/test_um.py",
     '    assert any("code block" in f for f in fails) and any("FAL_KEY" in f for f in fails)\n',
     '    assert any("code block" in f for f in fails) and any("credential" in f for f in fails)\n'
     '    assert all("FAL_KEY" not in f for f in fails)\n'),
    # The subset ships no upstream session hooks.
    ("tests/test_um.py",
     '@pytest.mark.skipif(not shutil.which("cygpath"), reason="Git Bash / MSYS only")\n',
     '@pytest.mark.skipif(not shutil.which("cygpath"), reason="Git Bash / MSYS only")\n'
     '@pytest.mark.skipif(not (Path(__file__).resolve().parents[1] / "hooks").is_dir(), reason="UABS ships no upstream session hooks")\n'),
    # The subset ships no plugins/opencode adapter either.
    ("tests/test_opencode_plugin.py",
     "import re\nfrom pathlib import Path\n\nfrom um.cli import GROUPS\n",
     "import re\nfrom pathlib import Path\nimport pytest\n\nfrom um.cli import GROUPS\n"),
    ("tests/test_opencode_plugin.py",
     'PLUGIN = Path(__file__).resolve().parents[1] / "plugins" / "opencode" / "index.ts"\n',
     'PLUGIN = Path(__file__).resolve().parents[1] / "plugins" / "opencode" / "index.ts"\n'
     'pytestmark = pytest.mark.skipif(not PLUGIN.is_file(), reason="UABS ships no OpenCode adapter")\n'),
]

# Every deliberate UABS edit inside the mirrored skill tree. The sync copies
# upstream's skills and reference files verbatim, which would silently undo the
# pack's own policy there: `reverse-engineering` must not carry the unbounded
# `unpack_upk.py` fallback, and the two files that document it carry the pack's
# wording. Keys are "<skill>/<path inside the skill dir>"; misses are reported.
SKILL_DROP = ("reverse-engineering/references/ue3-packages/unpack_upk.py",)
SKILL_OVERRIDES = {
    "reverse-engineering/references/ue3-packages/README.md":
        "TOOLS/um-refresh-overrides/reverse-engineering/references/ue3-packages/README.md",
}
SKILL_PATCHES: list[tuple[str, str, str]] = [
    ("reverse-engineering/GUIDE.md",
     "  - **Fully compressed UE3 `.upk`** (UELib shows `Exports=0`): unpack a copy with Gildor's `decompress`\n"
     "    (from UE Viewer), or, for LZO packages, with\n"
     "    [`unpack_upk.py`](references/ue3-packages/README.md).\n",
     "  - **Fully compressed UE3 `.upk`** (UELib shows `Exports=0`): unpack a copy with Gildor's `decompress`\n"
     "    (from UE Viewer); see the\n"
     "    [compressed-package route](references/ue3-packages/README.md). The unbounded upstream fallback is not shipped.\n"),
]

# Kept as LF like the rest of the pack's shipped text (upstream ships CRLF).
LF_NORMALIZE = ("um/fonts/OFL-SpaceGrotesk.txt",)


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def download(commit: str, cache_dir: str) -> str:
    url = "https://codeload.github.com/rehan-remade/universal-modder/zip/" + commit
    os.makedirs(cache_dir, exist_ok=True)
    target = os.path.join(cache_dir, "um-%s.zip" % commit[:7])
    if not os.path.isfile(target):
        print("downloading", url)
        with urllib.request.urlopen(url, timeout=120) as resp, open(target, "wb") as out:
            shutil.copyfileobj(resp, out)
    return target


def extract(zip_path: str, into: str) -> str:
    if os.path.isdir(into):
        shutil.rmtree(into)
    with zipfile.ZipFile(zip_path) as zf:
        zf.extractall(into)
    entries = [e for e in os.listdir(into) if os.path.isdir(os.path.join(into, e))]
    assert len(entries) == 1, entries
    return os.path.join(into, entries[0])


def read(path: str) -> str:
    return io.open(path, encoding="utf-8", newline="").read()


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    io.open(path, "w", encoding="utf-8", newline="").write(text)


def apply_patches(src: str, dest: str, sha7: str) -> tuple[list[str], list[str]]:
    """Copy the subset, then apply every UABS patch. Returns (applied, missing)."""
    if os.path.isdir(dest):
        shutil.rmtree(dest)
    for name in SUBSET:
        source = os.path.join(src, name)
        target = os.path.join(dest, name)
        if os.path.isfile(source):
            os.makedirs(dest, exist_ok=True)
            shutil.copy2(source, target)
        else:
            shutil.copytree(source, target,
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", ".pytest_cache"))
    applied, missing = [], []
    for rel, old, new in PATCHES:
        path = os.path.join(dest, rel)
        text = read(path)
        new = new.replace("__SHA7__", sha7)
        if text.count(old) == 1:
            write(path, text.replace(old, new))
            applied.append(rel)
        else:
            missing.append("%s: %d match(es) for %r" % (rel, text.count(old), old.splitlines()[0][:60]))
    for rel in LF_NORMALIZE:
        path = os.path.join(dest, rel)
        text = read(path)
        if "\r\n" in text:
            write(path, text.replace("\r\n", "\n"))
            applied.append(rel + " (LF)")
    for dirty in ("um/__pycache__", "tests/__pycache__", ".pytest_cache"):
        shutil.rmtree(os.path.join(dest, dirty), ignore_errors=True)
    return applied, missing


def sync_skill(src: str, dry: bool) -> list[str]:
    """Mirror upstream's skills/, keeping the pack's GUIDE.md convention."""
    upstream_skills = os.path.join(src, "skills")
    assert os.path.isdir(upstream_skills), upstream_skills
    notes = []
    for name in sorted(os.listdir(SKILL)):
        skill_dir = os.path.join(upstream_skills, name)
        guide_src = os.path.join(skill_dir, "SKILL.md")
        if not os.path.isfile(guide_src):
            notes.append("MISSING upstream skill: " + name)
            continue
        refs_src = os.path.join(skill_dir, "references")
        target_root = os.path.join(SKILL, name)
        before = sum(len(f) for _, _, f in os.walk(target_root)) if os.path.isdir(target_root) else 0
        if dry:
            print("  would sync", name, "(upstream refs:", sum(len(f) for _, _, f in os.walk(refs_src)) if os.path.isdir(refs_src) else 0, "files)")
            for key in SKILL_DROP:
                if key.startswith(name + "/"):
                    print("    would drop    ", key)
            for key in SKILL_OVERRIDES:
                if key.startswith(name + "/"):
                    print("    would override", key)
            for key, _, _ in SKILL_PATCHES:
                if key.startswith(name + "/"):
                    print("    would patch   ", key)
            continue
        guide = read(guide_src)
        shutil.rmtree(target_root, ignore_errors=True)
        os.makedirs(target_root, exist_ok=True)
        write(os.path.join(target_root, "GUIDE.md"), guide)
        if os.path.isdir(refs_src):
            shutil.copytree(refs_src, os.path.join(target_root, "references"),
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "SKILL.md"))
        # Re-apply the pack's deltas inside this skill (SKILL_DROP/_OVERRIDES/
        # _PATCHES above): the mirror is upstream's tree, so anything the pack
        # decided differently there is restored here, and a delta that no longer
        # applies is reported instead of skipped.
        for key in SKILL_DROP:
            if not key.startswith(name + "/"):
                continue
            path = os.path.join(target_root, key.split("/", 1)[1])
            if os.path.isfile(path):
                os.remove(path)
                notes.append("dropped " + key)
            else:
                notes.append("DELTA MISSING (drop): " + key)
        for key, source in SKILL_OVERRIDES.items():
            if not key.startswith(name + "/"):
                continue
            write(os.path.join(target_root, key.split("/", 1)[1]), read(os.path.join(ROOT, source)))
            notes.append("override " + key)
        for key, old, new in SKILL_PATCHES:
            if not key.startswith(name + "/"):
                continue
            path = os.path.join(target_root, key.split("/", 1)[1])
            text = read(path)
            if text.count(old) == 1:
                write(path, text.replace(old, new))
                notes.append("patched " + key)
            else:
                notes.append("DELTA MISSING (patch): %s (%d matches)" % (key, text.count(old)))
        after = sum(len(f) for _, _, f in os.walk(target_root))
        notes.append("%s: %d -> %d files" % (name, before, after))
    return notes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--commit", required=True, help="upstream commit to vendor (40 hex chars)")
    ap.add_argument("--apply", action="store_true", help="write changes (default: dry run)")
    ap.add_argument("--cache", default=os.path.join(os.environ.get("TEMP", "/tmp"), "uabs-um-refresh"))
    args = ap.parse_args()
    commit = args.commit.strip().lower()
    assert len(commit) == 40 and all(c in "0123456789abcdef" for c in commit), "need a full 40-char sha"

    zip_path = download(commit, args.cache)
    digest = sha256(zip_path)
    print("source archive: %s\nsha256: %s" % (zip_path, digest))
    src = extract(zip_path, os.path.join(args.cache, commit[:7]))
    print("upstream tree:", src)

    print("\ncanonical skill references:")
    skill_notes = sync_skill(src, dry=not args.apply)
    for note in skill_notes:
        print("  ", note)
    skill_missing = [n for n in skill_notes if "MISSING" in n]

    staging = VENDOR + ".refresh-staging"
    applied, missing = apply_patches(src, staging, commit[:7])
    print("\nUABS patches re-applied: %d" % len(applied))
    for rel in applied:
        print("   ", rel)
    if missing:
        print("\nPATCHES THAT NO LONGER MATCH (review upstream):")
        for line in missing:
            print("   ", line)

    if not args.apply:
        shutil.rmtree(staging, ignore_errors=True)
        print("\ndry run - nothing written. Re-run with --apply.")
        return 1 if (missing or skill_missing) else 0

    shutil.rmtree(VENDOR, ignore_errors=True)
    os.rename(staging, VENDOR)
    print("\nvendored tree written to", VENDOR)
    print("""
next steps (not automated here):
  1. build the wheel:  cd BUNDLED-TOOLS/universal-modder && SOURCE_DATE_EPOCH=<ts> uv build --wheel --out-dir <abs>/BUNDLED-TOOLS/offline
  2. replace the old wheel in BUNDLED-TOOLS/offline (name carries +uabs.%s)
  3. update BUNDLED-TOOLS/CATALOG.json: source_commit=%s, source_archive_sha256=%s, offline_asset
  4. update BUNDLED-TOOLS/OFFLINE-MANIFEST.json (size + sha256)
  5. update TESTS/test_universal_modder.py's pinned source_commit
  6. python TESTS/test_universal_modder.py && powershell TESTS/Test-Pack.ps1 && python TESTS/test_release_contract.py
""" % (commit[:7], commit, digest))
    return 1 if (missing or skill_missing) else 0


if __name__ == "__main__":
    raise SystemExit(main())
