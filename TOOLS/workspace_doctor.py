#!/usr/bin/env python3
"""Analyze a mod or project workspace and propose safe organization moves.

Read-only by default. `--apply` moves only high-confidence, unreferenced,
non-path-dependent entries into canonical folders, with a backup manifest.
It never deletes anything and never moves a FOMOD package root, a version
snapshot, a nested Git repository, or a game/plugin/binary asset.
"""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import shutil
import sys
from pathlib import Path

VERSION_RE = re.compile(r"\b(\d+\.\d+(?:\.\d+)?(?:[-+][0-9A-Za-z.-]+)?)\b")
SNAPSHOT_RE = re.compile(
    r"^(?P<base>.+?)[ _-]+v?(?P<ver>\d+\.\d+(?:\.\d+){0,2}(?:[-+][0-9A-Za-z.-]+)?)$"
)
TEXT_SUFFIXES = {".md", ".txt", ".json", ".ini", ".xml", ".ps1", ".py", ".bat",
                 ".cmd", ".toml", ".yaml", ".yml", ".cfg", ".conf", ".html",
                 ".css", ".js", ".ts", ".cs", ".cpp", ".h", ".hpp", ".c", ".lua"}
IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".tga", ".dds"}
MEDIA_SUFFIXES = IMAGE_SUFFIXES | {".webm", ".mp4", ".mov", ".avi"}
PATH_DEPENDENT_SUFFIXES = {".esp", ".esm", ".esl", ".bsa", ".ba2", ".nif", ".hkx",
                           ".pex", ".dll", ".exe", ".jar", ".uasset", ".pak",
                           ".swf", ".tri", ".kf", ".egm", ".egt", ".lip", ".seq"}
CACHE_NAMES = {"build", "dist", "bin", "obj", "out", "target", "node_modules",
               ".venv", "venv", "vcpkg", "extern", "third_party", ".cache",
               "__pycache__", ".pytest_cache", "forgevault", "forgeworkspaces",
               "ghidra-cache", "ghidra-project", ".gradle", ".vs", ".idea"}
SOURCE_NAMES = {"src", "source", "code", "native", "include", "tests", "test",
                "cmake", "scripts_src"}
PACKAGE_NAMES = {"fomod", "meshes", "textures", "materials", "sound", "music",
                 "scripts", "skse", "seq", "mcm", "interface", "shaders",
                 "lodsettings", "video", "vis", "facegen", "meshes"}
DOC_NAMES = {"docs", "doc", "documentation", "readme.md", "readme.txt",
             "changelog.md", "changelog.txt", "license", "license.md",
             "license.txt", "credits.md", "credits.txt", "contributing.md"}
STATE_NAMES = {"state.md", "plan.md", "decisions.md", "validation.md",
               "workspace_ownership.md", "current.txt", "version", "version.txt",
               "baseline-manifest.json"}
TOOLING_NAMES = {"tools", "tooling", "scripts"}
RESEARCH_NAMES = {"research", "recovery", "pseudocode", "analysis"}
RELEASE_NAMES = {"publication", "release", "releases", "packages"}
KEEP_NAMES = {"readme.md", "readme.txt", "changelog.md", "changelog.txt",
              "license", "license.md", "license.txt", ".gitignore",
              ".gitattributes", ".gitmodules"}


def _now() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _read(path: Path, limit: int = 300_000) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace")[:limit]
    except OSError:
        return ""


def _version_from_text(text: str) -> str:
    m = VERSION_RE.search(text or "")
    return m.group(1) if m else ""


def _dir_size(path: Path, cap: int = 150_000) -> tuple[int, bool]:
    total = 0
    seen = 0
    try:
        for root, dirs, files in os.walk(path):
            dirs[:] = [d for d in dirs if d not in {".git", "node_modules", "__pycache__"}]
            for name in files:
                seen += 1
                if seen > cap:
                    return total, False
                try:
                    total += (Path(root) / name).stat().st_size
                except OSError:
                    pass
    except OSError:
        pass
    return total, True


def _detect_current_version(root: Path) -> tuple[str, str]:
    for name in ("CURRENT.txt", "VERSION", "VERSION.txt"):
        p = root / name
        if p.is_file():
            v = _version_from_text(_read(p, 4000))
            if v:
                return v, name
    info = root / "fomod" / "info.xml"
    if info.is_file():
        m = re.search(r"<Version>\s*([^<]+?)\s*</Version>", _read(info, 20_000), re.I)
        if m:
            return m.group(1).strip(), "fomod/info.xml"
    return "", ""


def _fomod_version(root: Path) -> str:
    info = root / "fomod" / "info.xml"
    if not info.is_file():
        return ""
    m = re.search(r"<Version>\s*([^<]+?)\s*</Version>", _read(info, 20_000), re.I)
    return m.group(1).strip() if m else ""


def _classify(root: Path, path: Path) -> tuple[str, str]:
    """Return (kind, reason)."""
    name = path.name
    low = name.lower()
    if path.is_dir() and (path / ".git").exists():
        return "nested_repo", "nested Git repository; its remote and CI decide where it lives"
    m = SNAPSHOT_RE.match(name)
    if path.is_dir() and m and ((path / "fomod").is_dir() or (path / "VERSION.txt").is_file()):
        return "version_snapshot", "versioned package snapshot"
    if low == "fomod" and (path / "ModuleConfig.xml").is_file():
        return "package_root", "FOMOD package root"
    if path.is_dir() and re.match(r"^\d{2,3}[ _-]", name):
        return "package_content", "numbered FOMOD package folder"
    if low in CACHE_NAMES:
        return "cache", "generated, dependency or cache directory"
    if low in SOURCE_NAMES:
        return "source", "source directory"
    if low in PACKAGE_NAMES:
        return "package_content", "mod package content"
    if low in DOC_NAMES:
        return "docs", "documentation"
    if low in STATE_NAMES or low.endswith(".manifest.json"):
        return "state", "project state or version marker"
    if low in TOOLING_NAMES:
        return "tooling", "project tooling; nested caches are reported separately"
    if low in RESEARCH_NAMES:
        return "research", "research, recovery or analysis material"
    if low in RELEASE_NAMES:
        return "release", "release or publication output"
    if low in KEEP_NAMES:
        return "docs", "standard project document"
    if path.is_dir() and low in {"screenshots", "screenshot", "images", "image",
                                 "gallery", "media", "preview", "previews"}:
        return "media_loose", "loose presentation media"
    if path.is_dir() and low in {"notes", "todo", "ideas", "scratch"}:
        return "notes_loose", "loose working notes"
    if path.is_file() and path.suffix.lower() in PATH_DEPENDENT_SUFFIXES:
        return "path_dependent", "game or binary asset that may rely on its current path"
    if path.is_file() and path.suffix.lower() in MEDIA_SUFFIXES:
        return "media_loose", "loose image or media file"
    if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES:
        return "docs_loose", "loose document"
    return "unknown", "unclassified"


def _text_files(root: Path, limit: int = 400) -> tuple[list[Path], bool]:
    out = []
    skip = {".git", "node_modules", "vcpkg", "build", "dist", "bin", "obj",
            ".venv", "venv", "__pycache__", ".cache"}
    for base, dirs, files in os.walk(root):
        dirs[:] = [d for d in dirs if d not in skip]
        for name in files:
            p = Path(base) / name
            if p.suffix.lower() in TEXT_SUFFIXES:
                try:
                    if p.stat().st_size <= 1_000_000:
                        out.append(p)
                except OSError:
                    pass
            if len(out) >= limit:
                return out, False
    return out, True


def _referenced(name: str, texts: list[Path], root: Path, owner: Path) -> bool:
    needles = {name.lower(), name.replace(" ", "%20").lower()}
    for p in texts:
        if owner == p or owner in p.parents:
            continue
        body = _read(p).lower()
        if any(n in body for n in needles):
            return True
    return False


def analyze(root: Path) -> dict:
    root = root.resolve()
    current, current_src = _detect_current_version(root)
    fomod = _fomod_version(root)
    texts, scan_complete = _text_files(root)
    entries = []
    for child in sorted(root.iterdir(), key=lambda p: p.name.lower()):
        if child.name in {".git"}:
            continue
        kind, reason = _classify(root, child)
        size, complete = _dir_size(child) if child.is_dir() else (child.stat().st_size, True)
        referenced = False
        if kind in {"media_loose", "notes_loose", "docs_loose", "research"}:
            referenced = _referenced(child.name, texts, root, child)
        action, target, confidence, note = "keep", "", "high", reason
        if kind == "cache":
            action, confidence = "ignore", "high"
            note = reason + "; add to .gitignore or move outside the project"
        elif kind == "version_snapshot":
            m = SNAPSHOT_RE.match(child.name)
            ver = m.group("ver") if m else ""
            if current and ver == current:
                action, note = "keep", "current version snapshot"
            else:
                action, target, confidence = "review", "dist/versions/" + child.name, "medium"
                note = "old package snapshot; archive after checking references"
        elif kind == "package_root" and fomod and current and fomod != current:
            action, confidence = "review", "high"
            note = f"stale root FOMOD {fomod}; CURRENT/VERSION says {current}"
        elif kind in {"media_loose", "notes_loose", "docs_loose"}:
            if referenced:
                action, confidence = "review", "high"
                note = reason + "; referenced by a text file, so moving it could break a path"
            else:
                action = "move"
                target = "docs/presentation" if kind == "media_loose" else "docs"
                confidence = "high"
                note = reason + "; unreferenced, safe to move"
        elif kind == "research":
            if referenced:
                action, confidence = "review", "high"
                note = reason + "; referenced by a text file"
            else:
                action, target, confidence = "review", "research/" + child.name, "medium"
                note = reason + "; candidate for research/, review before moving"
        elif kind == "nested_repo":
            action, confidence = "keep", "high"
            note = reason
        elif kind == "release":
            action, confidence = "review", "medium"
            note = reason + "; keep release output out of the source root or under dist/"
        elif kind == "unknown":
            action, confidence = "review", "low"
            note = reason
        if action == "move" and not scan_complete:
            action, confidence = "review", "low"
            note += "; reference scan hit its 400-file cap, review before moving"
        entries.append({
            "name": child.name,
            "path": str(child.relative_to(root)).replace("\\", "/"),
            "kind": kind,
            "action": action,
            "target": target.replace("\\", "/"),
            "confidence": confidence,
            "reason": note,
            "referenced": referenced,
            "size_bytes": size,
            "size_complete": complete,
        })
    nested_caches = []
    for e in entries:
        if e["kind"] not in {"tooling", "nested_repo", "unknown"}:
            continue
        base = root / e["path"]
        try:
            children = sorted(base.iterdir(), key=lambda p: p.name.lower())
        except OSError:
            continue
        for child in children:
            if child.is_dir() and child.name.lower() in CACHE_NAMES:
                size, complete = _dir_size(child)
                nested_caches.append({
                    "path": str(child.relative_to(root)).replace("\\", "/"),
                    "size_bytes": size,
                    "size_complete": complete,
                })
    warnings = []
    if fomod and current and fomod != current:
        warnings.append(f"root FOMOD is {fomod} but CURRENT/VERSION says {current}")
    snapshots = [e for e in entries if e["kind"] == "version_snapshot"]
    if len(snapshots) > 1:
        warnings.append(f"{len(snapshots)} version snapshots share the root; keep one current package")
    if nested_caches:
        warnings.append(f"{len(nested_caches)} nested cache folder(s); ignore or relocate them, never ship them")
    if not scan_complete:
        warnings.append("reference scan hit its 400-file cap; automatic moves are disabled")
    moves = [e for e in entries if e["action"] == "move"]
    reviews = [e for e in entries if e["action"] == "review"]
    ignored = [e for e in entries if e["action"] == "ignore"]
    return {
        "root": str(root),
        "generated_utc": _now(),
        "project": root.name,
        "current_version": current,
        "current_version_source": current_src,
        "fomod_version": fomod,
        "entries": entries,
        "nested_caches": nested_caches,
        "reference_scan_complete": scan_complete,
        "warnings": warnings,
        "summary": {
            "entries": len(entries),
            "safe_moves": len(moves),
            "review": len(reviews),
            "ignored": len(ignored),
            "kept": len([e for e in entries if e["action"] == "keep"]),
        },
    }


def _markdown(report: dict) -> str:
    lines = [f"# Workspace doctor — {report['project']}", "",
             f"Root: `{report['root']}`  ",
             f"Current version: `{report['current_version'] or 'unknown'}`"
             + (f" (from `{report['current_version_source']}`)" if report['current_version_source'] else "")
             + "  ",
             f"Root FOMOD version: `{report['fomod_version'] or 'none'}`", ""]
    for w in report["warnings"]:
        lines.append(f"> **Warning:** {w}")
    if report["warnings"]:
        lines.append("")
    s = report["summary"]
    lines.append(f"**Summary:** {s['entries']} entries; {s['safe_moves']} safe move(s); "
                 f"{s['review']} need review; {s['ignored']} ignored cache(s); {s['kept']} kept.")
    lines.append("")
    moves = [e for e in report["entries"] if e["action"] == "move"]
    lines.append("## Safe moves" + ("" if moves else " — none"))
    lines.append("")
    if moves:
        lines += ["| From | To | Why |", "|---|---|---|"]
        for e in moves:
            lines.append(f"| `{e['path']}` | `{e['target']}` | {e['reason']} |")
        lines += ["", "Apply with `--apply`; a backup manifest is written under `.uabs/workspace-backup/`."]
    else:
        lines.append("No unreferenced, non-path-dependent entries were safe to move automatically.")
    lines.append("")
    reviews = [e for e in report["entries"] if e["action"] == "review"]
    lines.append("## Needs review" + ("" if reviews else " — none"))
    lines.append("")
    if reviews:
        lines += ["| Entry | Kind | Why | Suggested target |", "|---|---|---|---|"]
        for e in reviews:
            lines.append(f"| `{e['path']}` | {e['kind']} | {e['reason']} | `{e['target'] or '-'}` |")
    lines.append("")
    ignored = [e for e in report["entries"] if e["action"] == "ignore"]
    lines.append("## Ignored caches" + ("" if ignored else " — none"))
    lines.append("")
    for e in ignored:
        lines.append(f"- `{e['path']}` — {e['reason']}")
    lines.append("")
    if report.get("nested_caches"):
        lines.append("## Nested caches")
        lines.append("")
        for e in report["nested_caches"]:
            lines.append(f"- `{e['path']}` — {e['size_bytes']} bytes; ignore or relocate, never ship")
        lines.append("")
    return "\n".join(lines)


def apply_moves(report: dict) -> dict:
    root = Path(report["root"])
    moves = [e for e in report["entries"] if e["action"] == "move" and e["confidence"] == "high"]
    stamp = _dt.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = root / ".uabs" / "workspace-backup" / stamp
    backup.mkdir(parents=True, exist_ok=True)
    manifest = {"root": str(root), "created_utc": _now(), "moves": [], "skipped": []}
    for e in moves:
        src = root / e["path"]
        dst = root / e["target"] / Path(e["path"]).name
        if dst.exists():
            manifest["skipped"].append({"from": e["path"], "to": str(dst.relative_to(root)), "reason": "target exists"})
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dst))
        manifest["moves"].append({"from": e["path"], "to": str(dst.relative_to(root)), "size_bytes": e["size_bytes"]})
    (backup / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", nargs="?", default=".", help="project root (default: current folder)")
    ap.add_argument("--apply", action="store_true", help="move high-confidence safe entries")
    ap.add_argument("--json", dest="json_path", help="write the plan JSON here")
    ap.add_argument("--markdown", dest="md_path", help="write the human report here")
    args = ap.parse_args(argv)
    root = Path(args.root)
    if not root.is_dir():
        print(f"Not a folder: {root}", file=sys.stderr)
        return 2
    report = analyze(root)
    text = _markdown(report)
    if args.json_path:
        Path(args.json_path).write_text(json.dumps(report, indent=2), encoding="utf-8")
    if args.md_path:
        Path(args.md_path).write_text(text, encoding="utf-8")
    print(text)
    if args.apply:
        manifest = apply_moves(report)
        print(f"\nApplied {len(manifest['moves'])} move(s); backup manifest: "
              f"{Path(report['root']) / '.uabs' / 'workspace-backup'}")
        for m in manifest["moves"]:
            print(f"  {m['from']} -> {m['to']}")
        for s in manifest["skipped"]:
            print(f"  skipped {s['from']}: {s['reason']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
