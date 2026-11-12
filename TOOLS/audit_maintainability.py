"""Report duplication, oversized skills and orphaned tools without failing a build.

Maintenance drift in this pack is mostly invisible: a provider fanout copies every
skill by design, but a second copy of a *tool* or a 900-line SKILL.md is not.
Findings are advisory by default; `--strict` only fails on the rules that have no
legitimate exception (skill ceiling, duplicate non-generated files, broken ADR).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

# Provider trees and archived texts are generated on purpose; comparing them
# would report the fanout itself as waste.
GENERATED = (
    "1-TAILORED-PROVIDER-TREES/",
    "3-PREAMBLES/history/",
    "BUNDLED-TOOLS/packs/skyrim/legacy/",
)
# Vendored plugin sources are upstream files the bundle does not own.
VENDORED = ("BUNDLED-TOOLS/plugins/",)
SKILL_LINE_CEILING = 500
# Known mirrors the pack keeps on purpose: the workspace AIO copy is asserted
# identical by the release contract, and the LICENSE must ship beside the
# vendored toolbox.
ALLOWED_DUPLICATES = {
    ("0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md", "COPY-TO-YOUR-WORKSPACE/AIO-INSTRUCTION.txt"),
    ("BUNDLED-TOOLS/uabs-toolbox/LICENSE", "LICENSE"),
    ("COPY-TO-YOUR-WORKSPACE/AGENTS.md", "COPY-TO-YOUR-WORKSPACE/CLAUDE.md"),
}


def tracked(root: Path) -> list[str]:
    out = subprocess.run(["git", "-C", str(root), "ls-files"],
                         capture_output=True, text=True, check=False)
    if out.returncode != 0:
        return sorted(p.relative_to(root).as_posix() for p in root.rglob("*") if p.is_file())
    return [line for line in out.stdout.splitlines() if line]


def is_generated(path: str) -> bool:
    return path.startswith(GENERATED) or path.startswith(VENDORED)


def duplicate_groups(root: Path, files: list[str]) -> list[dict]:
    seen: dict[str, list[str]] = {}
    for rel in files:
        if is_generated(rel) or rel.startswith("artifacts/"):
            continue
        p = root / rel
        try:
            data = p.read_bytes()
        except OSError:
            continue
        if len(data) < 1024:            # empty files, .gitkeep neighbours
            continue
        seen.setdefault(hashlib.sha256(data).hexdigest(), []).append(rel)
    return [{"sha256": h, "files": group}
            for h, group in seen.items()
            if len(group) > 1 and tuple(sorted(group)) not in ALLOWED_DUPLICATES]


def oversized_skills(root: Path) -> list[dict]:
    out = []
    for skill in sorted((root / "_CANONICAL-SKILLS").glob("*/SKILL.md")):
        lines = len(skill.read_text(encoding="utf-8", errors="ignore").splitlines())
        if lines > SKILL_LINE_CEILING:
            out.append({"skill": skill.parent.name, "lines": lines})
    return out


def orphan_tools(root: Path, files: list[str]) -> list[str]:
    """A tool no installer, doc or test names is a candidate for deletion."""
    tools = [f for f in files if f.startswith("TOOLS/") and f.endswith((".ps1", ".py"))]
    haystack = []
    for rel in files:
        if rel.startswith("TOOLS/") or rel.startswith("artifacts/"):
            continue
        p = root / rel
        if p.suffix.lower() in (".png", ".jpg", ".zip", ".exe", ".dll", ".whl"):
            continue
        try:
            haystack.append(p.read_text(encoding="utf-8", errors="ignore"))
        except OSError:
            pass
    body = "\n".join(haystack)
    return [t for t in tools if Path(t).name not in body]


def todo_markers(root: Path, files: list[str]) -> list[dict]:
    hits = []
    for rel in files:
        if not rel.endswith((".ps1", ".py", ".md")) or is_generated(rel):
            continue
        try:
            text = (root / rel).read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for n, line in enumerate(text.splitlines(), 1):
            if re.search(r"\b(TODO|FIXME|XXX)\b", line):
                hits.append({"path": rel, "line": n, "text": line.strip()[:120]})
    return hits


def adr_problems(root: Path) -> list[str]:
    directory = root / "docs" / "decisions"
    problems = []
    if not directory.is_dir():
        return ["docs/decisions is missing"]
    records = sorted(p for p in directory.glob("[0-9][0-9][0-9][0-9]-*.md"))
    if not records:
        problems.append("no ADR records")
    index = (directory / "README.md").read_text(encoding="utf-8")
    for record in records:
        if record.name not in index:
            problems.append(f"{record.name} is not linked from the ADR index")
        body = record.read_text(encoding="utf-8")
        for heading in ("## Context", "## Decision", "## Evidence",
                        "## Consequences", "## Revisit when"):
            if heading not in body:
                problems.append(f"{record.name} lacks {heading}")
    return problems


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", default=".")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()
    # Windows consoles default to cp1252 and crash on a path or note holding an
    # arrow; the audit is advisory text, not a byte-fidelity artifact.
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass
    root = Path(args.root).resolve()
    files = tracked(root)

    report = {
        "duplicates": duplicate_groups(root, files),
        "oversized_skills": oversized_skills(root),
        "orphan_tools": orphan_tools(root, files),
        "todo_markers": todo_markers(root, files),
        "adr_problems": adr_problems(root),
    }
    hard = bool(report["duplicates"] or report["oversized_skills"] or report["adr_problems"])
    report["strict_failures"] = hard

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(f"files: {len(files)}")
        print(f"duplicate non-generated groups: {len(report['duplicates'])}")
        for group in report["duplicates"][:10]:
            print("  " + " == ".join(group["files"]))
        print(f"skills over {SKILL_LINE_CEILING} lines: {len(report['oversized_skills'])}")
        for row in report["oversized_skills"]:
            print(f"  {row['skill']}: {row['lines']}")
        print(f"tools named nowhere outside TOOLS/: {len(report['orphan_tools'])}")
        for name in report["orphan_tools"]:
            print("  " + name)
        print(f"TODO/FIXME markers: {len(report['todo_markers'])}")
        for row in report["todo_markers"][:10]:
            print(f"  {row['path']}:{row['line']} {row['text']}")
        print("ADR problems: " + (", ".join(report["adr_problems"]) or "none"))
        print("VERDICT: " + ("FAIL (strict)" if hard else "PASS (advisory)"))

    if args.strict and hard:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
