"""Generate the maintainer routing index from source metadata, never machine state.

Run through Update-MemoryIndex.ps1; --check compares without writing.
"""
from __future__ import annotations

import argparse
import ast
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent


def scalar(text: str, key: str) -> str:
    match = re.search(r"(?ms)^" + re.escape(key) + r":\s*([^\n]*(?:\n[ \t]+[^\n]+)*)", text)
    if not match:
        raise ValueError(f"missing frontmatter {key}")
    return " ".join(match.group(1).lstrip(">|").strip().strip("\"'").split())


def generate(root: Path) -> str:
    rows: dict[str, tuple[str, str, str, str, str]] = {}

    def add(name: str, purpose: str, path: str, verify: str, owner: str) -> None:
        if name.casefold() in rows:
            raise ValueError(f"duplicate index identity: {name}")
        if not (root / path).exists():
            raise ValueError(f"missing index source: {path}")
        rows[name.casefold()] = (name, purpose, path, verify, owner)

    skills = {}
    for path in sorted((root / "_CANONICAL-SKILLS").glob("*/SKILL.md")):
        text = path.read_text(encoding="utf-8")
        if not text.startswith("---\n"):
            raise ValueError(f"invalid skill frontmatter: {path}")
        front = text.split("---", 2)[1]
        name = scalar(front, "name")
        if name.casefold() in skills:
            raise ValueError(f"duplicate skill name: {name}")
        skills[name.casefold()] = scalar(front, "description")
        add("skill:" + name, skills[name.casefold()], path.relative_to(root).as_posix(),
            "python TOOLS/audit_skills.py _CANONICAL-SKILLS", name)

    # Ownership is routing metadata, not a second implementation of each contract.
    owners = {"Wait-External.ps1": "ci-convergence", "Clean-MergedBranches.ps1": "ci-convergence",
              "Set-GitHubProtection.ps1": "github-fleet-maintenance",
              "build_release.py": "release-checklist", "Build-Release.ps1": "release-checklist",
              "Update-MemoryIndex.ps1": "reasoning-discipline", "update_memory_index.py": "reasoning-discipline",
              "verify_docs.py": "check-work", "verify_manifest.py": "verification-discipline",
              "verify_product.py": "verification-discipline"}
    tool_paths = list((root / "TOOLS").iterdir()) + list((root / "TOOLS" / "hooks").glob("*.py"))
    for path in sorted(tool_paths):
        if not path.is_file() or path.suffix.lower() not in {".py", ".ps1", ".bat", ".cmd", ".psm1"}:
            continue
        text = path.read_text(encoding="utf-8-sig")
        description = ""
        if path.suffix == ".py":
            description = (ast.get_docstring(ast.parse(text)) or "").split("\n")[0]
        else:
            match = re.search(r"(?im)^\s*(?:#\s*(?!>|<)([^\n]+)|\.SYNOPSIS\s*\n\s*([^\n]+)|rem\s+([^\n]+))", text)
            if match:
                description = next(x.strip() for x in match.groups() if x)
        identity = path.relative_to(root / "TOOLS").as_posix()
        add("tool:" + identity, description or "Maintainer tool; read its parameter/help header.",
            path.relative_to(root).as_posix(), "powershell -NoProfile -ExecutionPolicy Bypass -File TESTS/Test-Pack.ps1",
            owners.get(path.name, "tool-discovery"))

    catalog_path = "BUNDLED-TOOLS/CATALOG.json"
    for component in json.loads((root / catalog_path).read_text(encoding="utf-8-sig"))["components"]:
        name = component["id"]
        purpose = component.get("scope_note") or component.get("note") or component.get("name", name)
        # An index points at the authoritative catalog; it does not copy pins or machine paths.
        add("catalog:" + name, str(purpose).split(". ")[0], catalog_path,
            "python .github/scripts/check_versions.py", component.get("owner", "ai-tooling-stack"))

    # These already own discovery and activation. Index them without copying
    # runtime state or maintaining another capability catalog.
    companion_path = "BUNDLED-TOOLS/COMPANIONS.json"
    companions = json.loads((root / companion_path).read_text(encoding="utf-8-sig"))
    for name, entry in sorted(companions["companions"].items()):
        add("companion:" + name, entry.get("notes") or entry["title"], companion_path,
            "python TOOLS/companion_registry.py --verify", entry["repo"])
    profile_path = "BUNDLED-TOOLS/PROFILES.json"
    for profile in json.loads((root / profile_path).read_text(encoding="utf-8-sig"))["profiles"]:
        add("profile:" + profile["id"], profile["title"], profile_path,
            "powershell -NoProfile -File TOOLS/Set-McpProfile.ps1 -List", "capability-profiles")

    lines = ["# Maintainer memory index", "", "Generated; do not hand-edit. Regenerate: `powershell -NoProfile -ExecutionPolicy Bypass -File TOOLS/Update-MemoryIndex.ps1`.",
             "Source routing only. Progress belongs in STATE.md; machine paths/preferences belong in MACHINE-MAP.md / PROFILE.md.", "",
             "| Question | Source | Command |", "|---|---|---|",
             "| Which gates exist / run the full gate? | TESTS/Test-Pack.ps1 | `powershell -NoProfile -ExecutionPolicy Bypass -File TESTS/Test-Pack.ps1` |",
             "| CI convergence for this commit? | TOOLS/Wait-External.ps1; _CANONICAL-SKILLS/ci-convergence/SKILL.md | `powershell -NoProfile -ExecutionPolicy Bypass -File TOOLS/Wait-External.ps1 -GitHubRun auto -Repo OWNER/REPO -Sha FULL_SHA` |",
             "| Catalog / companion owners? | BUNDLED-TOOLS/CATALOG.json; BUNDLED-TOOLS/COMPANIONS.json | `python TOOLS/companion_registry.py --verify` |",
             "| Docs / index current? | TOOLS/verify_docs.py | `python TOOLS/verify_docs.py` |", "",
             "| Name | What it does | Path | Verify command | Owning skill / project |", "|---|---|---|---|---|"]
    for row in sorted(rows.values()):
        lines.append("| " + " | ".join(str(x).replace("|", "\\|").replace("\n", " ") for x in row) + " |")
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    try:
        content = generate(args.root)
        path = args.root / "MEMORY.md"
        if args.check:
            if not path.exists() or path.read_text(encoding="utf-8") != content:
                raise ValueError("MEMORY.md stale; run TOOLS/Update-MemoryIndex.ps1")
        else:
            # Keep the tracked ending (`* -text` stores bytes as-is): writing LF
            # over the CRLF file turned every regeneration into a whole-file diff.
            ending = "\r\n" if path.exists() and b"\r\n" in path.read_bytes() else "\n"
            path.write_text(content, encoding="utf-8", newline=ending)
        print("MEMORY INDEX: PASS")
        return 0
    except (ValueError, OSError, KeyError, SyntaxError) as exc:
        print(f"MEMORY INDEX: FAIL: {exc}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
