#!/usr/bin/env python3
"""Archive every instruction text this pack ever shipped, so installs can strip it.

Provider instruction files (CLAUDE.md, AGENTS.md, SOUL.md) are user files. The
installer only removes text it can prove the pack wrote: an exact copy of a
shipped version. A machine wired by an older release still carries that older
text, and when the current release no longer ships it, nothing recognised it --
measured 2026-10-10: a Codex AGENTS.md held the V8.0.1 contract (12.5 KB) in
front of the current one, about 3k extra tokens on every Codex request.

Outputs (deterministic, content-addressed names):
  3-PREAMBLES/history/AIO-INSTRUCTION-<sha12>.md   every old AIO contract
  3-PREAMBLES/history/SOUL-<sha12>.md              every old soul
  3-PREAMBLES/history/provider-general-<sha12>.md  general preamble tails of old
                                                   provider-home templates
  BUNDLED-TOOLS/packs/skyrim/legacy/<sha12>.md     Skyrim heads of old provider-
                                                   home templates (replaced by the
                                                   compact Skyrim pack block)

--check exits 1 when an output is missing or stale, without writing.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HIST = ROOT / "3-PREAMBLES" / "history"
LEGACY = ROOT / "BUNDLED-TOOLS" / "packs" / "skyrim" / "legacy"
TEMPLATES = (
    "1-TAILORED-PROVIDER-TREES/Claude/COPY-TO-PROVIDER-HOME/CLAUDE.md",
    "1-TAILORED-PROVIDER-TREES/Codex/COPY-TO-PROVIDER-HOME/AGENTS.md",
    "1-TAILORED-PROVIDER-TREES/Kimi/COPY-TO-PROVIDER-HOME/AGENTS.md",
)
GENERAL_HEAD = re.compile(r"(?m)^# ULTIMATE GENERAL AIO")
MIN_CHARS = 200  # shorter fragments are not provably ours


def norm(raw: bytes) -> str:
    return raw.decode("utf-8", "replace").lstrip("﻿").replace("\r\n", "\n").strip()


def git(*args: str) -> bytes:
    return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, check=True).stdout


def versions(path: str) -> list[str]:
    seen: dict[str, None] = {}
    for commit in git("log", "--all", "--format=%H", "--", path).decode().split():
        try:
            text = norm(git("show", f"{commit}:{path}"))
        except subprocess.CalledProcessError:
            continue  # deleted in that commit
        if text:
            seen.setdefault(text, None)
    return list(seen)


def sha12(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:12]


def planned() -> dict[Path, str]:
    out: dict[Path, str] = {}
    current_aio = norm((ROOT / "0-UNRESTRAINT-PACKS" / "AIO-INSTRUCTION.md").read_bytes())
    current_soul = norm((ROOT / "3-PREAMBLES" / "SOUL.md").read_bytes())
    for text in versions("0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md"):
        if text != current_aio and len(text) >= MIN_CHARS:
            out[HIST / f"AIO-INSTRUCTION-{sha12(text)}.md"] = text
    for text in versions("3-PREAMBLES/SOUL.md"):
        if text != current_soul and len(text) >= MIN_CHARS:
            out[HIST / f"SOUL-{sha12(text)}.md"] = text
    current_templates = {norm((ROOT / t).read_bytes()) for t in TEMPLATES if (ROOT / t).is_file()}
    for template in TEMPLATES:
        for text in versions(template):
            if text in current_templates:
                continue
            match = GENERAL_HEAD.search(text)
            head = text[: match.start()].strip() if match else text
            tail = text[match.start():].strip() if match else ""
            if len(head) >= MIN_CHARS:
                out[LEGACY / f"{sha12(head)}.md"] = head
            if len(tail) >= MIN_CHARS:
                out[HIST / f"provider-general-{sha12(tail)}.md"] = tail
    # Hand-named archives already cover some texts; never write a second copy.
    named = {norm(p.read_bytes()) for p in HIST.glob("*.md") if not re.search(r"-[0-9a-f]{12}\.md$", p.name)}
    return {p: t for p, t in out.items() if t not in named}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    want = planned()
    stale = []
    for path, text in sorted(want.items()):
        data = (text + "\n").encode("utf-8")
        if not path.is_file() or path.read_bytes() != data:
            stale.append(path)
            if not args.check:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(data)
    generated = {p for d in (HIST, LEGACY) for p in d.glob("*.md") if re.search(r"-?[0-9a-f]{12}\.md$", p.name)}
    extra = sorted(generated - set(want))
    if args.check:
        for p in stale + extra:
            print("stale:", p.relative_to(ROOT).as_posix())
        return 1 if stale or extra else 0
    for p in extra:
        p.unlink()
    print(f"{len(want)} archived texts ({len(stale)} written, {len(extra)} removed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
