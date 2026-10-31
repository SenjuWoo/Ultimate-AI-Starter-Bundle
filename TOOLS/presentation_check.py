#!/usr/bin/env python3
"""Check a mod's public presentation: images, gallery, README and media.

Read-only. Fails when a public page has no visual proof: a cover, at least
three gallery images, README images with alt text, and kind-specific shots.
"""
from __future__ import annotations

import argparse
import json
import re
import struct
import sys
from pathlib import Path

IMAGE_SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}
MOTION_SUFFIXES = {".gif", ".webm", ".mp4", ".mov"}
COVER_WORDS = ("cover", "hero", "banner", "thumbnail", "thumb")
CHARACTER_WORDS = ("face", "portrait", "closeup", "close-up", "head", "body", "outfit")
ARMOR_WORDS = ("front", "back", "detail", "side")
ENV_WORDS = ("wide", "landscape", "detail", "vista")
TOOL_WORDS = ("install", "menu", "mcm", "config", "settings", "screenshot")
README_IMAGE_RE = re.compile(r"!\[([^\]]*)\]\(([^)]+)\)")


def image_size(path: Path) -> tuple[int, int] | None:
    try:
        with path.open("rb") as f:
            head = f.read(32)
            if head[:8] == b"\x89PNG\r\n\x1a\n" and len(head) >= 24:
                return struct.unpack(">II", head[16:24])
            if head[:6] in (b"GIF87a", b"GIF89a"):
                return struct.unpack("<HH", head[6:10])
            if head[:2] == b"\xff\xd8":
                f.seek(2)
                while True:
                    b = f.read(2)
                    if len(b) < 2 or b[0] != 0xFF:
                        return None
                    marker = b[1]
                    if marker in (0xD8, 0xD9):
                        continue
                    raw = f.read(2)
                    if len(raw) < 2:
                        return None
                    length = struct.unpack(">H", raw)[0]
                    if marker in range(0xC0, 0xC4):
                        data = f.read(5)
                        if len(data) < 5:
                            return None
                        h, w = struct.unpack(">HH", data[1:5])
                        return w, h
                    f.seek(max(0, length - 2), 1)
            if head[:4] == b"RIFF" and head[8:12] == b"WEBP":
                f.seek(12)
                chunk = f.read(18)
                if chunk[:4] == b"VP8X" and len(chunk) >= 14:
                    w = 1 + int.from_bytes(chunk[8:11], "little")
                    h = 1 + int.from_bytes(chunk[11:14], "little")
                    return w, h
                return None
    except OSError:
        return None
    return None


def _collect(root: Path) -> tuple[list[Path], list[str]]:
    dirs = [root / "docs" / "presentation", root / "assets" / "presentation",
            root / "screenshots", root / "images", root / "gallery",
            root / "media", root / "publication"]
    found: list[Path] = []
    labels: list[str] = []
    for base in dirs:
        if not base.is_dir():
            continue
        labels.append(str(base.relative_to(root)).replace("\\", "/"))
        for p in base.rglob("*"):
            if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES | MOTION_SUFFIXES:
                found.append(p)
                if len(found) >= 200:
                    return found, labels
    return found, labels


def check(root: Path, kind: str, min_width: int) -> dict:
    root = root.resolve()
    readme = root / "README.md"
    readme_text = readme.read_text(encoding="utf-8", errors="replace") if readme.is_file() else ""
    refs = []
    for alt, target in README_IMAGE_RE.findall(readme_text):
        target = target.strip().split(" ")[0]
        if target.startswith(("http://", "https://", "data:")):
            refs.append({"alt": alt.strip(), "target": target, "local": False, "exists": True})
            continue
        local = (root / target).resolve()
        refs.append({"alt": alt.strip(), "target": target, "local": True, "exists": local.is_file()})
    images, labels = _collect(root)
    for r in refs:
        if r["local"] and r["exists"]:
            p = (root / r["target"]).resolve()
            if p not in images:
                images.append(p)
    rows = []
    for p in images:
        dims = image_size(p)
        rows.append({
            "path": str(p.relative_to(root)).replace("\\", "/"),
            "width": dims[0] if dims else None,
            "height": dims[1] if dims else None,
            "bytes": p.stat().st_size,
            "motion": p.suffix.lower() in MOTION_SUFFIXES,
        })
    stills = [r for r in rows if not r["motion"]]
    cover = next((r for r in stills if any(w in Path(r["path"]).name.lower() for w in COVER_WORDS)), None)
    if cover is None and stills:
        cover = stills[0]
    gallery = [r for r in stills if r is not cover]
    checks = []

    def add(cid: str, ok: bool, detail: str) -> None:
        checks.append({"id": cid, "status": "pass" if ok else "fail", "detail": detail})

    add("media-present", bool(rows), f"{len(rows)} image/media file(s) in {', '.join(labels) or 'no presentation folder'}")
    add("cover", bool(cover), "cover/hero image found" if cover else "no cover/hero image")
    if cover:
        ratio = (cover["width"] / cover["height"]) if cover["width"] and cover["height"] else 0
        add("cover-16x9", abs(ratio - 16 / 9) <= 0.08, f"aspect {ratio:.2f} (target 1.78)")
        add("cover-width", bool(cover["width"] and cover["width"] >= min_width), f"{cover['width'] or '?'}px wide (min {min_width})")
        add("cover-size", cover["bytes"] <= 6_000_000, f"{cover['bytes']} bytes (max 6 MB)")
    add("gallery", len(gallery) >= 3, f"{len(gallery)} gallery image(s); need 3")
    add("readme-images", len([r for r in refs if r["local"] and r["exists"]]) >= 3,
        f"{len([r for r in refs if r['local'] and r['exists']])} local README image(s); need 3")
    add("readme-alt", all(r["alt"] for r in refs) if refs else False,
        "every README image has alt text" if refs else "no README images")
    bad_refs = [r["target"] for r in refs if r["local"] and not r["exists"]]
    add("readme-paths", not bad_refs, "all README image paths resolve" if not bad_refs else "missing: " + ", ".join(bad_refs[:5]))
    big = [r["path"] for r in rows if r["bytes"] > 10_000_000 and not r["motion"]]
    add("image-size", not big, "all stills <= 10 MB" if not big else "over 10 MB: " + ", ".join(big[:5]))
    names = [Path(r["path"]).name.lower() for r in rows]
    if kind == "character":
        add("character-closeup", any(any(w in n for w in CHARACTER_WORDS) for n in names),
            "face/portrait/close-up shot present" if any(any(w in n for w in CHARACTER_WORDS) for n in names)
            else "character mod needs a face/portrait/close-up shot")
    elif kind == "armor":
        add("armor-angles", any(any(w in n for w in ARMOR_WORDS) for n in names),
            "front/back/detail shot present" if any(any(w in n for w in ARMOR_WORDS) for n in names)
            else "armor mod needs front/back/detail shots")
    elif kind == "environment":
        add("environment-wide", any(any(w in n for w in ENV_WORDS) for n in names),
            "wide/detail shot present" if any(any(w in n for w in ENV_WORDS) for n in names)
            else "environment mod needs a wide or detail shot")
    elif kind == "animation":
        add("motion", any(r["motion"] for r in rows), "motion clip present" if any(r["motion"] for r in rows) else "animation mod needs a GIF/WebM/MP4")
    elif kind == "tool":
        add("tool-shots", len([n for n in names if any(w in n for w in TOOL_WORDS)]) >= 2,
            "installer/menu shots present" if len([n for n in names if any(w in n for w in TOOL_WORDS)]) >= 2
            else "tool mod needs installer/menu screenshots")
    return {
        "root": str(root),
        "kind": kind,
        "presentation_dirs": labels,
        "images": rows,
        "readme_images": refs,
        "checks": checks,
        "ok": all(c["status"] == "pass" for c in checks),
    }


def markdown(report: dict) -> str:
    lines = [f"# Presentation check — {Path(report['root']).name}", "",
             f"Kind: `{report['kind']}`  ",
             f"Media folders: {', '.join(report['presentation_dirs']) or 'none'}", ""]
    lines += ["| Check | Status | Detail |", "|---|---|---|"]
    for c in report["checks"]:
        lines.append(f"| {c['id']} | {'PASS' if c['status'] == 'pass' else 'FAIL'} | {c['detail']} |")
    lines += ["", f"**Result:** {'PASS' if report['ok'] else 'FAIL'}", ""]
    if report["images"]:
        lines += ["## Images", "", "| File | Size | Bytes |", "|---|---|---|"]
        for r in report["images"]:
            lines.append(f"| `{r['path']}` | {r['width'] or '?'}x{r['height'] or '?'} | {r['bytes']} |")
        lines.append("")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("root", nargs="?", default=".", help="mod project root")
    ap.add_argument("--kind", default="auto",
                    choices=["auto", "character", "armor", "environment", "animation", "tool"])
    ap.add_argument("--min-width", type=int, default=1280)
    ap.add_argument("--json", dest="json_path")
    ap.add_argument("--no-fail", action="store_true", help="always exit 0 (report only)")
    args = ap.parse_args(argv)
    root = Path(args.root)
    if not root.is_dir():
        print(f"Not a folder: {root}", file=sys.stderr)
        return 2
    report = check(root, args.kind, args.min_width)
    text = markdown(report)
    print(text)
    if args.json_path:
        Path(args.json_path).write_text(json.dumps(report, indent=2), encoding="utf-8")
    return 0 if report["ok"] or args.no_fail else 1


if __name__ == "__main__":
    raise SystemExit(main())
