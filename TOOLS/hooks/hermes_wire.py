#!/usr/bin/env python3
"""Merge a pack gate into Hermes's real config.yaml.

Two things make this worth a script rather than a text append:

1. **The path is not `~/.hermes/config.yaml`.** Hermes's own documentation says
   it is, but the resolved location honours `HERMES_HOME`, which on this machine
   points at `%LOCALAPPDATA%\\hermes`. Writing to the documented path produced a
   file Hermes never read, and `hermes hooks list` kept reporting nothing while
   looking perfectly installed. The authoritative answer comes from
   `hermes config path`.

2. **The file already holds real user configuration.** Appending text to a YAML
   document that already has structure is how you corrupt it. This parses,
   merges one key, and writes back.

Usage:
    hermes_wire.py <hermes-exe> <python-exe> <gate.py> [--remove] [--all-tools] [--pre-only] [--approve]
"""
from __future__ import annotations

import json
import copy
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

# Set from the gate being wired, so wiring a second gate cannot strip the first.
MARKER = "completeness_gate.py"


def owned_gate_command(command: object, gate: str) -> bool:
    """Only the generated command for this exact owned gate is replaceable."""
    if not isinstance(command, str):
        return False
    match = re.fullmatch(
        r'''\s*(?:&\s+)?(?:"[^"]+"|'[^']+'|[^\s"']+)\s+'''
        r'''(?:"(?P<double>[^"]+)"|'(?P<single>[^']+)'|(?P<plain>[^\s"']+))'''
        r'''\s+--(?:pre|stop)\s*''', command)
    if not match:
        return False
    script = next(value for value in match.groupdict().values() if value)
    actual = Path(script.replace("\\", "/"))
    expected = Path(gate.replace("\\", "/"))
    candidates = [expected]
    # The installer sets this to the retired hooks directory. Recognize a
    # command that still points there so an upgrade can replace it. The
    # folder name stays in the PowerShell helper, not in this file.
    legacy = os.environ.get("UABS_LEGACY_HOOK_ROOT", "").strip()
    if (
        legacy
        and expected.parent.name.lower() == "hooks"
        and expected.parent.parent.name.lower() == "ultimate-ai-starter-bundle"
    ):
        candidates.append(Path(legacy) / expected.name)
    try:
        normalized = os.path.normcase(str(actual.resolve()))
        return any(normalized == os.path.normcase(str(path.resolve())) for path in candidates)
    except (OSError, ValueError):
        return False


def config_path(hermes: str) -> Path | None:
    """Ask Hermes where its config is. Never guess: the docs are wrong here."""
    try:
        out = subprocess.run([hermes, "config", "path"], capture_output=True,
                             text=True, timeout=60)
        line = (out.stdout or "").strip().splitlines()
        if line:
            p = Path(line[0].strip())
            if p.parent.exists():
                return p
    except Exception:
        pass
    return None


def update_allowlist(cfg: Path, command: str, gate: Path, event: str,
                     *, approve: bool) -> bool:
    """Approve/remove one exact installer-owned Hermes hook command."""
    path = cfg.parent / "shell-hooks-allowlist.json"
    if not approve and not path.exists():
        return True
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    try:
        data = json.loads(original) if original else {"approvals": []}
    except Exception:
        print(f"SKIP: {path} is not valid JSON; refusing to touch it.")
        return False
    if not isinstance(data, dict) or not isinstance(data.get("approvals", []), list):
        print(f"SKIP: {path} has an unknown schema; refusing to touch it.")
        return False

    approvals = [entry for entry in data.get("approvals", [])
                 if not (isinstance(entry, dict)
                         and entry.get("event") == event
                         and entry.get("command") == command)]
    if not approve and approvals == data.get("approvals", []):
        return True
    if approve:
        stamp = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
        try:
            mtime = datetime.fromtimestamp(gate.stat().st_mtime, timezone.utc)
            mtime_text = mtime.isoformat().replace("+00:00", "Z")
        except OSError:
            mtime_text = None
        approvals.append({
            "event": event,
            "command": command,
            "approved_at": stamp,
            "script_mtime_at_approval": mtime_text,
        })
    data["approvals"] = approvals

    path.parent.mkdir(parents=True, exist_ok=True)
    if original:
        path.with_suffix(path.suffix + ".bak-gate").write_text(original, encoding="utf-8")
    fd, temp_name = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2, sort_keys=True)
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except OSError:
            pass
        raise
    return True


def selftest() -> int:
    with tempfile.TemporaryDirectory(prefix="uabs-hermes-wire-") as root:
        base = Path(root)
        untouched = base / "untouched" / "config.yaml"
        if not update_allowlist(untouched, '"python" "gate" --pre',
                                base / "missing.py", "pre_tool_call", approve=False):
            print("HERMES WIRE SELFTEST: FAIL - absent remove")
            return 1
        if (untouched.parent / "shell-hooks-allowlist.json").exists():
            print("HERMES WIRE SELFTEST: FAIL - absent remove created state")
            return 1
        cfg = base / "config.yaml"
        gate = base / "rtk_safe_hook.py"
        gate.write_text("pass\n", encoding="utf-8")
        command = f'"python" "{gate.as_posix()}" --pre'
        if not update_allowlist(cfg, command, gate, "pre_tool_call", approve=True):
            print("HERMES WIRE SELFTEST: FAIL - approve")
            return 1
        saved = json.loads((base / "shell-hooks-allowlist.json").read_text(encoding="utf-8"))
        if not any(e.get("command") == command for e in saved["approvals"]):
            print("HERMES WIRE SELFTEST: FAIL - approval absent")
            return 1
        if not update_allowlist(cfg, command, gate, "pre_tool_call", approve=False):
            print("HERMES WIRE SELFTEST: FAIL - remove")
            return 1
        saved = json.loads((base / "shell-hooks-allowlist.json").read_text(encoding="utf-8"))
        if any(e.get("command") == command for e in saved["approvals"]):
            print("HERMES WIRE SELFTEST: FAIL - approval survived removal")
            return 1
        # Exercise the real YAML merge while replacing only vendor path lookup.
        # A same-basename script in a personal folder must survive uninstall.
        import yaml
        from unittest.mock import patch

        personal = '"python" "C:/personal/rtk_safe_hook.py" --pre'
        chained = command + ' && echo personal-followup'
        original = {"personal": "keep", "hooks": {"pre_tool_call": [
            {"command": command}, {"command": personal, "future": "keep"},
            {"command": chained},
        ]}}
        cfg.write_text(yaml.safe_dump(original), encoding="utf-8")
        with patch(__name__ + ".config_path", return_value=cfg), patch.object(
                sys, "argv", [__file__, "unused-hermes", "python", str(gate), "--remove", "--pre-only"]):
            if main() != 0:
                print("HERMES WIRE SELFTEST: FAIL - merge execution")
                return 1
        result = yaml.safe_load(cfg.read_text(encoding="utf-8"))
        if result != {"personal": "keep", "hooks": {"pre_tool_call": [
                {"command": personal, "future": "keep"}, {"command": chained}]}}:
            print("HERMES WIRE SELFTEST: FAIL - custom hook with same basename was removed")
            return 1
        untouched_yaml = b'# Personal comments\r\npersonal: "keep"\r\n'
        untouched_allowlist = b'{ "approvals": [{ "event": "pre_tool_call", "command": "personal" }] }'
        cfg.write_bytes(untouched_yaml)
        (base / "shell-hooks-allowlist.json").write_bytes(untouched_allowlist)
        with patch(__name__ + ".config_path", return_value=cfg), patch.object(
                sys, "argv", [__file__, "unused-hermes", "python", str(gate), "--remove", "--pre-only"]):
            if main() != 0 or cfg.read_bytes() != untouched_yaml or (base / "shell-hooks-allowlist.json").read_bytes() != untouched_allowlist:
                print("HERMES WIRE SELFTEST: FAIL - no-op uninstall rewrote personal configuration")
                return 1
        absent = base / "absent.yaml"
        with patch(__name__ + ".config_path", return_value=absent), patch.object(
                sys, "argv", [__file__, "unused-hermes", "python", str(gate), "--remove", "--pre-only"]):
            if main() != 0 or absent.exists():
                print("HERMES WIRE SELFTEST: FAIL - absent uninstall created config")
                return 1
        legacy_root = base / "retired-hooks"
        legacy_root.mkdir()
        legacy_gate = legacy_root / gate.name
        legacy_gate.write_text("pass\n", encoding="utf-8")
        bundle_gate = base / "Ultimate-AI-Starter-Bundle" / "hooks" / gate.name
        bundle_gate.parent.mkdir(parents=True)
        bundle_gate.write_text("pass\n", encoding="utf-8")
        legacy_command = f'"python" "{legacy_gate.as_posix()}" --pre'
        previous = os.environ.get("UABS_LEGACY_HOOK_ROOT")
        os.environ.pop("UABS_LEGACY_HOOK_ROOT", None)
        try:
            if owned_gate_command(legacy_command, str(bundle_gate)):
                print("HERMES WIRE SELFTEST: FAIL - retired hook owned without the installer root")
                return 1
            os.environ["UABS_LEGACY_HOOK_ROOT"] = str(legacy_root)
            if not owned_gate_command(legacy_command, str(bundle_gate)):
                print("HERMES WIRE SELFTEST: FAIL - retired hook was not replaceable")
                return 1
            if owned_gate_command(personal, str(bundle_gate)):
                print("HERMES WIRE SELFTEST: FAIL - personal hook became owned")
                return 1
        finally:
            if previous is None:
                os.environ.pop("UABS_LEGACY_HOOK_ROOT", None)
            else:
                os.environ["UABS_LEGACY_HOOK_ROOT"] = previous
        # The installer runs this file on Hermes's interpreter, which has no PyYAML.
        real_yaml = sys.modules["yaml"]
        saved_yaml = sys.modules.pop("yaml", None)
        class _Editor:
            def load(self, text):
                loaded = real_yaml.safe_load(text) if str(text).strip() else {}
                return loaded or {}
            def dump(self, data, stream):
                stream.write(real_yaml.safe_dump(data, sort_keys=False, allow_unicode=True, default_flow_style=False))
        class _HermesYaml:
            def roundtrip_yaml(self):
                return _Editor()
            def safe_load(self, stream):
                return real_yaml.safe_load(stream)
        sys.modules["hermes_yaml"] = _HermesYaml()
        import builtins
        real_import = builtins.__import__
        def _block_yaml(name, globals=None, locals=None, fromlist=(), level=0):
            if name == "yaml" or (isinstance(name, str) and name.startswith("yaml.")):
                raise ModuleNotFoundError("No module named 'yaml'")
            return real_import(name, globals, locals, fromlist, level)
        builtins.__import__ = _block_yaml
        try:
            fallback = base / "fallback.yaml"
            fallback.write_text("personal: keep\n# note\n", encoding="utf-8")
            with patch(__name__ + ".config_path", return_value=fallback), patch.object(
                    sys, "argv", [__file__, "unused-hermes", "python", str(gate), "--pre-only", "--approve"]):
                if main() != 0:
                    print("HERMES WIRE SELFTEST: FAIL - hermes_yaml fallback")
                    return 1
            loaded = real_yaml.safe_load(fallback.read_text(encoding="utf-8"))
            if loaded.get("personal") != "keep" or "rtk_safe_hook.py" not in str(loaded.get("hooks")):
                print("HERMES WIRE SELFTEST: FAIL - hermes_yaml fallback merge")
                return 1
        finally:
            builtins.__import__ = real_import
            if saved_yaml is not None:
                sys.modules["yaml"] = saved_yaml
            sys.modules.pop("hermes_yaml", None)
    # Text mode used to turn a mixed ruamel dump into one extra blank per
    # preserved CRLF. The encoder must emit a single ending.
    mixed = "a: 1\r\n# note\r\nb: 2\n"
    encoded = _yaml_bytes(mixed, "\r\n")
    if b"\r\r\n" in encoded or encoded.splitlines() != [b"a: 1", b"# note", b"b: 2"]:
        print("HERMES WIRE SELFTEST: FAIL - newline encoder doubled a CRLF break")
        return 1
    logical = _logical_yaml_text(b"a: 1\r\n# note\r\n\r\nb: 2\r\n")
    if "\r" in logical or logical.splitlines() != ["a: 1", "# note", "", "b: 2"]:
        print("HERMES WIRE SELFTEST: FAIL - logical newlines")
        return 1
    try:
        import hermes_yaml as real_roundtrip
    except ImportError:
        real_roundtrip = None
    if real_roundtrip is not None and hasattr(real_roundtrip, "roundtrip_yaml"):
        from io import StringIO
        raw = b"# comment one\r\n# comment two\r\nkey: 1\r\n# tail\r\nother: 2\r\n"
        editor = real_roundtrip.roundtrip_yaml()
        loaded = editor.load(_logical_yaml_text(raw))
        buffer = StringIO()
        editor.dump(loaded, buffer)
        fixed = _yaml_bytes(buffer.getvalue(), "\r\n")
        if b"\r\r\n" in fixed or len(fixed.splitlines()) != len(raw.splitlines()):
            print("HERMES WIRE SELFTEST: FAIL - CRLF round-trip added blank lines")
            return 1
    print("HERMES WIRE SELFTEST: PASS")
    return 0


def _plain(value):
    """Drop loader-specific node types so a round-trip edit can be compared by value."""
    if isinstance(value, dict):
        return {key: _plain(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_plain(item) for item in value]
    return value


def _logical_yaml_text(raw: bytes) -> str:
    """Strip CR before a round-trip load.

    ruamel keeps the source break inside comment tokens. A CRLF file therefore
    dumps as a mix of ``\\r\\n`` and ``\\n``. Writing that mix in text mode
    turns every preserved ``\\r\\n`` into ``\\r\\r\\n``, which reads back as a
    blank line. One logical newline on the way in keeps the dump clean.
    """
    return raw.decode("utf-8").replace("\r\n", "\n").replace("\r", "\n")


def _yaml_bytes(text: str, newline: str) -> bytes:
    """Encode YAML with one newline style and no doubled CR."""
    normalized = text.replace("\r\n", "\n").replace("\r", "\n")
    if normalized and not normalized.endswith("\n"):
        normalized += "\n"
    return normalized.replace("\n", newline).encode("utf-8")


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    if len(sys.argv) < 4:
        print("usage: hermes_wire.py <hermes-exe> <python-exe> <gate.py> [--remove] [--pre-only] [--approve]")
        return 0
    # Hermes's own interpreter ships ruamel as hermes_yaml, not PyYAML. Returning
    # success on that ImportError left the hooks unwired while the installer passed.
    editor = None
    try:
        import yaml
    except ImportError:
        try:
            import hermes_yaml as yaml
        except ImportError:
            print("SKIP: neither PyYAML nor Hermes YAML is available; refusing to edit Hermes config.")
            return 1
        editor = yaml.roundtrip_yaml()
    hermes, python, gate = sys.argv[1], sys.argv[2], sys.argv[3]
    remove = "--remove" in sys.argv
    pre_only = "--pre-only" in sys.argv

    global MARKER
    MARKER = Path(gate).name  # only ever touch the entries for THIS gate

    cfg = config_path(hermes)
    if cfg is None:
        print("SKIP: could not resolve the Hermes config path.")
        return 0

    original_bytes = cfg.read_bytes() if cfg.exists() else b""
    # Keep the file's existing ending when it is consistent. Mixed or LF
    # sources stay LF so a later text-mode write cannot double a CR.
    newline = "\r\n" if b"\r\n" in original_bytes and b"\n" not in original_bytes.replace(b"\r\n", b"") else "\n"
    text = _logical_yaml_text(original_bytes)
    try:
        if editor is None:
            data = yaml.safe_load(text) or {}
        else:
            data = editor.load(text) if text.strip() else {}
            if data is None:
                data = {}
    except Exception as exc:
        print(f"SKIP: {cfg} is not valid YAML ({type(exc).__name__}); refusing to touch it.")
        return 0
    if not isinstance(data, dict):
        print(f"SKIP: {cfg} is not a mapping; refusing to touch it.")
        return 0
    original_data = copy.deepcopy(data)

    hooks = data.get("hooks") or {}
    if not isinstance(hooks, dict):
        print("SKIP: existing 'hooks' is not a mapping; refusing to touch it.")
        return 0

    def strip(event: str) -> None:
        entries = [e for e in (hooks.get(event) or [])
                   if not (isinstance(e, dict) and owned_gate_command(e.get("command"), gate))]
        if entries:
            hooks[event] = entries
        else:
            hooks.pop(event, None)

    strip("pre_tool_call")
    strip("pre_verify")

    py = python.replace("\\", "/")
    gt = gate.replace("\\", "/")
    pre_command = f'"{py}" "{gt}" --pre'
    stop_command = f'"{py}" "{gt}" --stop'

    if not remove:
        # Forward slashes: they are valid on Windows and survive both YAML
        # quoting and Hermes's shlex.split, where backslashes do not.
        entry = {"command": pre_command, "timeout": 20}
        # A gate that inspects file writes must see every tool, and Hermes's
        # tool names are not something to guess at: omitting the matcher is the
        # documented way to match all of them, and the gate ignores any payload
        # shape it does not recognise anyway.
        if "--all-tools" not in sys.argv:
            entry = {"matcher": "terminal", **entry}
        hooks.setdefault("pre_tool_call", []).append(entry)
        if not pre_only:
            hooks.setdefault("pre_verify", []).append({
                "command": stop_command,
                "timeout": 40,
            })

    if hooks:
        data["hooks"] = hooks
    else:
        data.pop("hooks", None)

    if editor is None:
        changed = data != original_data
    else:
        changed = _plain(data) != _plain(original_data)
    if changed:
        if cfg.exists():
            backup = cfg.with_suffix(cfg.suffix + ".bak-gate")
            backup.write_bytes(original_bytes)
        if editor is None:
            cfg.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True,
                                          default_flow_style=False), encoding="utf-8")
        else:
            from io import StringIO
            buffer = StringIO()
            editor.dump(data, buffer)
            cfg.write_bytes(_yaml_bytes(buffer.getvalue(), newline))

    # Prove it round-trips before claiming success.
    check = yaml.safe_load(cfg.read_text(encoding="utf-8")) if cfg.exists() else data
    ok = isinstance(check, dict) and (remove or MARKER in str(check.get("hooks")))
    approve = "--approve" in sys.argv and not remove
    approval_ok = True
    if approve or remove:
        approval_ok = update_allowlist(cfg, pre_command, Path(gate), "pre_tool_call", approve=approve)
        if not pre_only:
            approval_ok = update_allowlist(cfg, stop_command, Path(gate), "pre_verify", approve=approve) and approval_ok
    ok = ok and approval_ok
    print(f"{'removed from' if remove else 'wired into'} {cfg}: {'OK' if ok else 'VERIFY FAILED'}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
