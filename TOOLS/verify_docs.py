"""Gate local documentation targets and the generated maintainer index.

Checks repo paths/commands, not remote URLs, installed CLI availability or example outputs.
"""
from __future__ import annotations

import argparse
from pathlib import Path
import re
from urllib.parse import unquote

from update_memory_index import generate

ROOT = Path(__file__).resolve().parent.parent
DOCS = ("README.md", "START-HERE.txt", "AIO-GUIDE.md")
# Repo-root references are unambiguous. Provider-home examples and generated
# output paths (dist/artifacts/configs) are runtime inputs, not shipped files.
PATH = re.compile(r"(?<![\w/\\:])(?:\.?[/\\])?((?:TOOLS|TESTS|BUNDLED-TOOLS|_CANONICAL-SKILLS|\.github|docs|0-UNRESTRAINT-PACKS|1-TAILORED-PROVIDER-TREES|3-PREAMBLES)[/\\][^\s`\"'<>|;,()]+)")
SCRIPT = re.compile(r"(?<![\w./\\:$%~-])(?:\.[/\\])?((?:[A-Za-z0-9_.-]+[/\\])*[A-Za-z0-9_][A-Za-z0-9_.-]*\.(?:ps1|psm1|py|bat|cmd|sh))\b", re.I)
# These are explicitly labelled external/placeholder/non-invocation examples,
# not a blanket exception for unknown filenames or companion repositories.
EXAMPLES = {
    ("README.md", "x.py"),  # generic Python command in the RTK rewrite table
    ("README.md", "Build-Release.ps1"),  # RTK basename-vs-path matching explanation
    ("README.md", "START-HERMES-GATEWAY.bat"),  # generated in the Hermes app home
}


def verify(root: Path) -> list[str]:
    errors = []
    for name in DOCS:
        text = (root / name).read_text(encoding="utf-8-sig")
        # Mask URLs and complete quoted paths before scanning commands; preserve
        # command snippets such as `python TOOLS/missing.py` for the same gate.
        targets = set()
        command_text = re.sub(r"https?://[^\s`\"'<>]+", "", text)
        for match in re.finditer(r"([\"'])([^\"'\n]+\.(?:ps1|psm1|py|bat|cmd|sh))\1", command_text, re.I):
            value = match.group(2)
            if not re.match(r"[A-Za-z]:|[~$%]", value):
                targets.add(value)
                command_text = command_text.replace(match.group(0), "")
        for value in re.findall(r"`([^`\n]+)`", text):
            if re.match(r"^(?:TOOLS|TESTS|BUNDLED-TOOLS|_CANONICAL-SKILLS|\.github|docs|0-UNRESTRAINT-PACKS|1-TAILORED-PROVIDER-TREES|3-PREAMBLES)[/\\]", value) and not re.search(r"\.(?:py|ps1|bat|cmd|psm1)\s+\S", value, re.I):
                targets.add(value)
                command_text = command_text.replace("`" + value + "`", "")
        targets.update(SCRIPT.findall(command_text))
        plain = re.sub(r"`[^`\n]*`", "", text)
        plain = re.sub(r"\[[^\]\n]*\]\([^)]+\)", "", plain)
        targets.update(PATH.findall(plain))
        # Markdown relative links may name root files without a directory.
        for match in re.finditer(r"\[[^\]\n]*\]\(([^)\s]+)\)", text):
            value = unquote(match.group(1)).split("#", 1)[0]
            if value and not re.match(r"[a-zA-Z][\w+.-]*:|^/", value):
                targets.add(value)
        for target in sorted(targets):
            target = target.replace("\\", "/").rstrip(".:*")
            if any(x in target for x in ("$", "%", "*", "{", "...")):
                continue  # explicit parameter/glob examples have no single file
            if (name, target) in EXAMPLES:
                continue
            path = root / target
            if not path.resolve().is_relative_to(root.resolve()):
                errors.append(f"{name}: target escapes repository {target}")
            elif not path.exists():
                errors.append(f"{name}: missing local target {target}")
    try:
        if (root / "MEMORY.md").read_text(encoding="utf-8") != generate(root):
            errors.append("MEMORY.md stale; run TOOLS/Update-MemoryIndex.ps1")
    except (ValueError, OSError, KeyError, SyntaxError) as exc:
        errors.append(str(exc))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    try:
        errors = verify(args.root)
    except OSError as exc:
        errors = [str(exc)]
    for error in errors:
        print(error)
    print(f"DOCS GATE: {'FAIL' if errors else 'PASS'} ({len(errors)} errors)")
    return int(bool(errors))


if __name__ == "__main__":
    raise SystemExit(main())
