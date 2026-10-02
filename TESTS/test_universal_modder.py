"""Offline Universal Modder packaging, command discovery and portable recon checks."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VENDOR = ROOT / "BUNDLED-TOOLS/universal-modder"


def main():
    env = dict(os.environ, PYTHONPATH=str(VENDOR), PYTHONUTF8="1")
    for args in [["--version"], *[[group, "--help"] for group in
                ("scan", "sprite", "render3d", "video", "win", "backup", "publish", "kb", "fal")]]:
        result = subprocess.run([sys.executable, "-m", "um", *args], env=env,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0, result.stderr
        if args == ["--version"]:
            assert result.stdout.strip() == "universal-modder 0.2.0"
    sys.path.insert(0, str(VENDOR))
    from um import kb, scan
    assert kb.local_root() == VENDOR / "knowledge"
    with tempfile.TemporaryDirectory(prefix="uabs-um-recon-") as temporary:
        fixture = Path(temporary)
        note = fixture / "unicode-note.md"
        note.write_text("R\u00e9sum\u00e9 \u2013 \u65e5\u672c\u8a9e\n", encoding="utf-8")
        legacy_env = dict(env, PYTHONUTF8="0", PYTHONIOENCODING="cp1252")
        result = subprocess.run([sys.executable, "-m", "um", "kb", "show", note.name,
                                 "--root", str(fixture)], env=legacy_env,
                                capture_output=True, timeout=30)
        assert result.returncode == 0, result.stderr
        assert result.stdout.decode("utf-8").strip() == note.read_text(encoding="utf-8").strip()
        game = fixture / "Game with spaces"
        game.mkdir()
        (game / "UnityPlayer.dll").write_bytes(b"MZ")
        managed = game / "Game_Data/Managed"
        managed.mkdir(parents=True)
        (managed / "Assembly-CSharp.dll").write_bytes(b"MZ")
        hits, _ = scan.detect(scan.Index(game))
        assert hits[0][0] == "unity-mono"
        steam = fixture / "User Steam Library"
        (steam / "steamapps").mkdir(parents=True)

        class RegistryKey:
            def __enter__(self): return self
            def __exit__(self, *_): pass

        registry = SimpleNamespace(HKEY_CURRENT_USER=1, HKEY_LOCAL_MACHINE=2,
                                   OpenKey=lambda *_: RegistryKey(),
                                   QueryValueEx=lambda *_: (str(steam), 1))
        with patch.dict(sys.modules, {"winreg": registry}), \
                patch.dict(os.environ, {"ProgramFiles": str(fixture / "missing-programs"), "ProgramFiles(x86)": str(fixture / "missing-programs-x86")}), \
                patch.object(scan, "is_windows", return_value=True), \
                patch.object(scan, "is_wsl", return_value=False), patch.object(scan, "is_mac", return_value=False):
            assert scan.steam_roots() == [steam.resolve()]

    wheel = ROOT / "BUNDLED-TOOLS/offline/universal_modder-0.2.0-py3-none-any.whl"
    if wheel.exists():
        with zipfile.ZipFile(wheel) as archive:
            assert archive.testzip() is None
            for name in ("um/knowledge/TEMPLATE.md", "um/knowledge/INDEX.md", "um/ps1/WinDrive.ps1",
                         "um/fonts/OFL-SpaceGrotesk.txt", "um/fonts/OFL-JetBrainsMono.txt"):
                assert name in archive.namelist(), name
    catalog = json.loads((ROOT / "BUNDLED-TOOLS/CATALOG.json").read_text(encoding="utf-8-sig"))
    component = next(x for x in catalog["components"] if x["id"] == "universal-modder")
    assert component["source_commit"] == "15d6f9d5fbd32de9b1884f29ddec3be9133bd912"
    assert not component["mcp"] and not component["auto_register"]
    for provider in component["providers"]:
        skill = ROOT / f"1-TAILORED-PROVIDER-TREES/{provider}/COPY-TO-SKILLS-DIRECTORY/skills/universal-modder"
        assert (skill / "SKILL.md").exists(), provider
        assert len(list((skill / "references/upstream").glob("*/GUIDE.md"))) == 10
        assert len(list(skill.rglob("SKILL.md"))) == 1, "reference guides must not enlarge discovery"
    print("Universal Modder offline CLI, recon, wheel and all-provider routing PASS")


if __name__ == "__main__":
    main()
