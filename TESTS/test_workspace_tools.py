#!/usr/bin/env python3
"""Contract tests for workspace_doctor.py and presentation_check.py."""
from __future__ import annotations

import json
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / "TOOLS"
sys.path.insert(0, str(TOOLS))
import workspace_doctor  # noqa: E402


def png(path: Path, width: int, height: int, rgb: tuple[int, int, int] = (32, 96, 160)) -> None:
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    raw = b"".join(b"\x00" + bytes(rgb) * width for _ in range(height))
    body = (b"\x89PNG\r\n\x1a\n"
            + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9))
            + chunk(b"IEND", b""))
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([sys.executable, *args], text=True, capture_output=True)


def workspace_fixture(tmp: Path) -> Path:
    root = tmp / "FixtureMod"
    (root / "fomod").mkdir(parents=True)
    (root / "fomod" / "info.xml").write_text("<fomod><Version>2.0.4</Version></fomod>", encoding="utf-8")
    (root / "fomod" / "ModuleConfig.xml").write_text("<config/>", encoding="utf-8")
    (root / "CURRENT.txt").write_text("FixtureMod 3.0.0\n", encoding="utf-8")
    (root / "00 Core").mkdir()
    (root / "00 Core" / "mod.esp").write_bytes(b"TES4")
    current = root / "FixtureMod 3.0.0"
    (current / "fomod").mkdir(parents=True)
    (current / "fomod" / "info.xml").write_text("<fomod><Version>3.0.0</Version></fomod>", encoding="utf-8")
    (current / "VERSION.txt").write_text("3.0.0\n", encoding="utf-8")
    (root / "TOOLS" / "vcpkg").mkdir(parents=True)
    (root / "TOOLS" / "vcpkg" / "cache.bin").write_bytes(b"x" * 128)
    (root / "RECOVERY").mkdir()
    (root / "RECOVERY" / "ghidra.log").write_text("analysis", encoding="utf-8")
    (root / "notes").mkdir()
    (root / "notes" / "todo.md").write_text("private notes", encoding="utf-8")
    (root / "screenshots").mkdir()
    png(root / "screenshots" / "hero.png", 160, 90)
    (root / "README.md").write_text(
        "# Fixture\n\n![Hero](screenshots/hero.png)\n", encoding="utf-8")
    (root / "CHANGELOG.txt").write_text("changes", encoding="utf-8")
    return root


def test_workspace_doctor_plans_safely(tmp: Path) -> None:
    root = workspace_fixture(tmp)
    plan = tmp / "plan.json"
    r = run(str(TOOLS / "workspace_doctor.py"), str(root), "--json", str(plan))
    assert r.returncode == 0, r.stderr
    data = json.loads(plan.read_text(encoding="utf-8"))
    by_name = {e["name"]: e for e in data["entries"]}
    assert any("root FOMOD is 2.0.4" in w for w in data["warnings"])
    assert by_name["fomod"]["action"] == "review"
    assert by_name["FixtureMod 3.0.0"]["action"] == "keep"
    assert by_name["TOOLS"]["kind"] == "tooling"
    assert any("TOOLS/vcpkg" == c["path"] for c in data["nested_caches"])
    assert by_name["notes"]["action"] == "move"
    assert by_name["screenshots"]["action"] == "review"  # README references it
    assert by_name["screenshots"]["referenced"] is True

    r = run(str(TOOLS / "workspace_doctor.py"), str(root), "--apply")
    assert r.returncode == 0, r.stderr
    assert (root / "docs" / "notes" / "todo.md").is_file()
    assert not (root / "notes").exists()
    assert (root / "screenshots" / "hero.png").is_file()
    backups = list((root / ".uabs" / "workspace-backup").glob("*/manifest.json"))
    assert backups, "no backup manifest written"
    manifest = json.loads(backups[0].read_text(encoding="utf-8"))
    assert any(m["from"] == "notes" for m in manifest["moves"])


def presentation_fixture(tmp: Path) -> Path:
    root = tmp / "CharacterMod"
    root.mkdir(parents=True)
    png(root / "docs" / "presentation" / "hero.png", 160, 90)
    png(root / "docs" / "presentation" / "gallery-01.png", 160, 90)
    png(root / "docs" / "presentation" / "gallery-02.png", 160, 90)
    png(root / "docs" / "presentation" / "gallery-03.png", 160, 90)
    png(root / "docs" / "presentation" / "face.png", 160, 90)
    (root / "README.md").write_text(
        "# Fixture\n\n"
        "![Hero](docs/presentation/hero.png)\n"
        "![Gallery one](docs/presentation/gallery-01.png)\n"
        "![Gallery two](docs/presentation/gallery-02.png)\n"
        "![Face](docs/presentation/face.png)\n",
        encoding="utf-8")
    return root


def test_presentation_check_requires_visual_proof(tmp: Path) -> None:
    root = presentation_fixture(tmp)
    r = run(str(TOOLS / "presentation_check.py"), str(root), "--kind", "character", "--min-width", "16")
    assert r.returncode == 0, r.stdout + r.stderr
    assert "**Result:** PASS" in r.stdout

    (root / "docs" / "presentation" / "face.png").unlink()
    r = run(str(TOOLS / "presentation_check.py"), str(root), "--kind", "character", "--min-width", "16")
    assert r.returncode == 1
    assert "character-closeup" in r.stdout and "FAIL" in r.stdout


def test_reference_scan_cap_is_reported(tmp: Path) -> None:
    root = workspace_fixture(tmp)
    texts, complete = workspace_doctor._text_files(root, limit=1)
    assert texts and not complete


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="uabs-workspace-tools-") as d:
        tmp = Path(d)
        test_workspace_doctor_plans_safely(tmp / "workspace")
        test_reference_scan_cap_is_reported(tmp / "cap")
        test_presentation_check_requires_visual_proof(tmp / "presentation")
    print("WORKSPACE TOOLS GATE: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
