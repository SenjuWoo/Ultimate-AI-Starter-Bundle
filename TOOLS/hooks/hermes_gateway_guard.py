#!/usr/bin/env python3
"""Stop a named Hermes profile from replacing the multiplex host.

`hermes --profile <name> gateway run --replace` is an escape hatch Hermes
itself refuses to eat. The replacement process kills the one gateway that
serves every profile, then stays standalone because only the default profile
is allowed to multiplex. Resume then fails with route mismatch, which the
desktop shows as storage_unavailable. The session databases are still there.

Two layers, same decision:

- Agent shells (Claude, Grok, Hermes, and the other wired harnesses) get a
  pre-tool deny. `--force` and a default-profile replace still pass.
- Hermes's own store Python loads this module from sitecustomize, including
  `python -I`, which is how Desktop and `hermes update` relaunch the gateway.
  A shell hook never sees that spawn. The process exits before `--replace`
  runs. When the multiplex host is already up, nothing is started. When it
  is not, the default host is started detached and this process still exits.

Fail open for every argv that is not that replace. Once the argv is the
named-profile replace, do not fall through into it.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

MARKER = "UABS-HERMES-GATEWAY-GUARD"
SPAWN_FLAG = "UABS_GATEWAY_GUARD_SPAWNED"
GUARD_NAME = "hermes_gateway_guard.py"


def _args(argv: list[str]) -> list[str]:
    return list(argv[1:])


def _flag(args: list[str], name: str) -> bool:
    return name in args


def _profile_arg(args: list[str]) -> str | None:
    for index, token in enumerate(args):
        if token in ("--profile", "-p") and index + 1 < len(args):
            return args[index + 1]
        if token.startswith("--profile="):
            return token.split("=", 1)[1]
    return None


def _home_profile(home: str | None) -> str | None:
    if not home:
        return None
    path = Path(home)
    if path.parent.name.lower() != "profiles":
        return None
    if path.name.lower() in ("", "default"):
        return None
    return path.name


def named_replace_profile(argv: list[str], environ: dict[str, str] | None = None) -> str | None:
    """Profile name when this argv would replace the host from a named profile.

    None means the process is not the footgun. `--force` is the documented
    escape and is left to Hermes.
    """
    env = os.environ if environ is None else environ
    args = _args(argv)
    if _flag(args, "--force") or not _flag(args, "--replace"):
        return None
    if not any(left == "gateway" and right == "run" for left, right in zip(args, args[1:])):
        return None
    chosen = _profile_arg(args)
    if chosen is not None:
        return None if chosen in ("", "default") else chosen
    return _home_profile(env.get("HERMES_HOME"))


_HERMES = re.compile(r"(?:^|[\s'\"\\])hermes(?:\.exe)?(?=[\s'\"]|$)", re.I)
_PROFILE = re.compile(r"(?:--profile|-p)\s+['\"]?([A-Za-z0-9_-]+)")


def command_profile(command: str) -> str | None:
    """Named profile in a shell command that runs the footgun, else None."""
    if not command or not _HERMES.search(command):
        return None
    if "--replace" not in command or "--force" in command:
        return None
    if not re.search(r"(?:^|\s)gateway(?:\s|$)", command):
        return None
    if not re.search(r"(?:^|\s)run(?:\s|$)", command):
        return None
    found = _PROFILE.search(command)
    if not found or found.group(1) == "default":
        return None
    return found.group(1)


def default_root(environ: dict[str, str] | None = None) -> Path:
    env = os.environ if environ is None else environ
    home = env.get("HERMES_HOME", "").strip()
    if home:
        path = Path(home)
        if path.parent.name.lower() == "profiles":
            return path.parent.parent
        return path
    local = env.get("LOCALAPPDATA", "").strip()
    if local:
        return Path(local) / "hermes"
    return Path.home() / ".hermes"


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        import ctypes
        handle = ctypes.windll.kernel32.OpenProcess(0x1000, False, int(pid))
        if not handle:
            return False
        ctypes.windll.kernel32.CloseHandle(handle)
        return True
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def host_is_multiplexer(state: dict, root: Path, alive=pid_alive) -> bool:
    """True when the recorded process is the live default-profile multiplexer."""
    if not isinstance(state, dict):
        return False
    if state.get("gateway_state") != "running":
        return False
    if state.get("multiplex_standalone_reason"):
        return False
    home = state.get("hermes_home")
    if not isinstance(home, str) or not home:
        return False
    try:
        if Path(home).resolve() != Path(root).resolve():
            return False
        if Path(home).parent.name.lower() == "profiles":
            return False
    except OSError:
        return False
    try:
        pid = int(state.get("pid") or 0)
    except (TypeError, ValueError):
        return False
    return bool(alive(pid))


def read_host_state(root: Path) -> dict | None:
    path = root / "gateway_state.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def _quote_ok(value: str) -> bool:
    return bool(value) and not any(char in value for char in '"&%<>|^\r\n')


def restart_command(root: Path, hermes: Path) -> str | None:
    home, exe = str(root), str(hermes)
    if not _quote_ok(home) or not _quote_ok(exe):
        return None
    return (
        'cmd.exe /d /s /c "set HERMES_HOME=' + home
        + "&& set " + SPAWN_FLAG + '=1&& "' + exe + '" gateway run --replace"'
    )


def spawn_default_host(root: Path) -> bool:
    """Start the default multiplexer outside this process's job. Never raises."""
    hermes = root / "bin" / ("hermes.exe" if os.name == "nt" else "hermes")
    if not hermes.is_file():
        return False
    command = restart_command(root, hermes)
    if command is None:
        return False
    try:
        if os.name == "nt":
            script = (
                "$r = Invoke-CimMethod -ClassName Win32_Process -MethodName Create "
                "-Arguments @{ CommandLine = $env:UABS_GUARD_CMDLINE; "
                "CurrentDirectory = $env:UABS_GUARD_CWD }; "
                "if (-not $r -or [int]$r.ReturnValue -ne 0) { exit 1 }"
            )
            env = os.environ.copy()
            env["UABS_GUARD_CMDLINE"] = command
            env["UABS_GUARD_CWD"] = str(root)
            done = subprocess.run(
                ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                capture_output=True, text=True, timeout=30,
                stdin=subprocess.DEVNULL, env=env,
            )
            return done.returncode == 0
        env = os.environ.copy()
        env["HERMES_HOME"] = str(root)
        env[SPAWN_FLAG] = "1"
        subprocess.Popen(
            [str(hermes), "gateway", "run", "--replace"],
            cwd=str(root), env=env, stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        return True
    except Exception:
        return False


def _stop_process() -> None:
    # site.py execsitecustomize catches Exception only. SystemExit during
    # that import is "Fatal Python error: init_import_site" and exit 1.
    os._exit(0)


def _log(root: Path, line: str) -> None:
    try:
        path = root / "logs" / "uabs-gateway-guard.log"
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as handle:
            handle.write(line.rstrip() + "\n")
    except OSError:
        return


def guard_process(argv: list[str] | None = None, environ: dict[str, str] | None = None) -> None:
    """Exit before a named-profile replace. Return when the argv is safe."""
    args = sys.argv if argv is None else argv
    env = os.environ if environ is None else environ
    profile = named_replace_profile(args, env)
    if profile is None:
        return
    root = default_root(env)
    if host_is_multiplexer(read_host_state(root) or {}, root):
        _log(root, f"blocked profile={profile} reason=host-alive")
        _stop_process()
    if env.get(SPAWN_FLAG) == "1":
        _log(root, f"blocked profile={profile} reason=spawn-already-attempted")
        _stop_process()
    started = spawn_default_host(root)
    _log(root, f"blocked profile={profile} reason=host-down started={int(started)}")
    _stop_process()


def block_body(profile: str) -> str:
    return (
        f"Refusing gateway run --replace for Hermes profile '{profile}'. "
        "That command kills the multiplex host and the replacement stays "
        "standalone, so other profiles resume as storage_unavailable. "
        "The session files are not deleted. Restart the host from the "
        "default profile: hermes gateway run --replace. "
        "--force is the only escape, and it is not this command."
    )


def block_payload(payload: dict, profile: str) -> dict:
    message = block_body(profile)
    if payload.get("hook_event_name") == "pre_tool_call":
        return {"action": "block", "message": message}
    return {"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": message,
    }}


def _tool_command(payload: dict) -> str:
    data = payload.get("tool_input") or payload.get("toolInput") or payload.get("args") or {}
    if not isinstance(data, dict):
        return ""
    for key in ("command", "cmd", "script", "input"):
        value = data.get(key)
        if isinstance(value, str):
            return value
    return ""


def read_input(timeout: float = 2.0) -> dict:
    box: dict = {}

    def slurp() -> None:
        chunks = []
        try:
            fd = sys.stdin.fileno()
            while True:
                part = os.read(fd, 65536)
                if not part:
                    break
                chunks.append(part)
        except Exception:
            pass
        box["raw"] = b"".join(chunks).decode("utf-8", "replace")

    import threading
    reader = threading.Thread(target=slurp, daemon=True)
    reader.start()
    reader.join(timeout)
    raw = box.get("raw") or ""
    try:
        loaded = json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}
    return loaded if isinstance(loaded, dict) else {}


def sitecustomize_text() -> str:
    return (
        "# " + MARKER + "\n"
        "# Installed by Ultimate-AI-Starter-Bundle. Replaced in full on reinstall.\n"
        "def _uabs_hermes_gateway_guard():\n"
        "    try:\n"
        "        import importlib.util\n"
        "        import os\n"
        "        from pathlib import Path\n"
        "        candidates = []\n"
        "        env = os.environ.get('UABS_HERMES_GATEWAY_GUARD', '').strip()\n"
        "        if env:\n"
        "            candidates.append(Path(env))\n"
        "        local = os.environ.get('LOCALAPPDATA', '').strip()\n"
        "        if local:\n"
        "            candidates.append(Path(local) / 'Ultimate-AI-Starter-Bundle' / 'hooks' / '"
        + GUARD_NAME + "')\n"
        "        candidates.append(Path(__file__).resolve().parent / 'uabs_hermes_gateway_guard.py')\n"
        "        for path in candidates:\n"
        "            if not path.is_file():\n"
        "                continue\n"
        "            spec = importlib.util.spec_from_file_location('uabs_hermes_gateway_guard', path)\n"
        "            if spec is None or spec.loader is None:\n"
        "                continue\n"
        "            module = importlib.util.module_from_spec(spec)\n"
        "            spec.loader.exec_module(module)\n"
        "            module.guard_process()\n"
        "            return\n"
        "    except SystemExit:\n"
        "        os._exit(0)\n"
        "    except Exception:\n"
        "        return\n"
        "_uabs_hermes_gateway_guard()\n"
    )


def hermes_pythons(localappdata: Path) -> list[Path]:
    tools = localappdata / "hermes" / "tools"
    if not tools.is_dir():
        return []
    return sorted(path for path in tools.glob("python-*/python.exe") if path.is_file())


def sitecustomize_missing(localappdata: Path) -> bool:
    """True when a Hermes store Python has no copy of this guard yet."""
    found = hermes_pythons(localappdata)
    if not found:
        return False
    for python in found:
        target = python.parent / "Lib" / "site-packages" / "sitecustomize.py"
        if not target.is_file():
            return True
        try:
            text = target.read_text(encoding="utf-8", errors="replace")
        except OSError:
            return True
        if MARKER not in text:
            return True
    return False


def site_packages_dir(python: Path) -> Path | None:
    try:
        done = subprocess.run(
            [str(python), "-I", "-c",
             "import site\n"
             "print(next((p for p in site.getsitepackages() if p.replace('\\\\','/').endswith('site-packages')), ''))"],
            capture_output=True, text=True, timeout=20, stdin=subprocess.DEVNULL,
        )
    except Exception:
        return None
    if done.returncode != 0:
        return None
    line = (done.stdout or "").strip().splitlines()
    if not line or not line[-1].strip():
        return None
    return Path(line[-1].strip())


def install_sitecustomize(localappdata: Path, source: Path) -> list[Path]:
    written: list[Path] = []
    text = sitecustomize_text()
    module = source.read_bytes()
    for python in hermes_pythons(localappdata):
        site = site_packages_dir(python)
        if site is None:
            continue
        site.mkdir(parents=True, exist_ok=True)
        target = site / "sitecustomize.py"
        if target.is_file() and MARKER not in target.read_text(encoding="utf-8", errors="replace"):
            existing = target.read_text(encoding="utf-8", errors="replace")
            if "_uabs_hermes_gateway_guard()" not in existing:
                target.write_text(existing.rstrip() + "\n\n" + text, encoding="utf-8")
        else:
            target.write_text(text, encoding="utf-8")
        (site / "uabs_hermes_gateway_guard.py").write_bytes(module)
        written.append(target)
    return written


def remove_sitecustomize(localappdata: Path) -> None:
    for python in hermes_pythons(localappdata):
        site = site_packages_dir(python)
        if site is None:
            continue
        target = site / "sitecustomize.py"
        module = site / "uabs_hermes_gateway_guard.py"
        if target.is_file() and MARKER in target.read_text(encoding="utf-8", errors="replace"):
            target.unlink()
        if module.is_file():
            module.unlink()


def selftest() -> int:
    root = Path(r"C:\Hermes")
    code_home = str(root / "profiles" / "code")
    failures: list[str] = []

    def expect(label: str, condition: bool) -> None:
        if not condition:
            failures.append(label)

    expect("default replace", named_replace_profile(
        ["hermes", "gateway", "run", "--replace"], {"HERMES_HOME": str(root)}) is None)
    expect("named replace", named_replace_profile(
        ["py", "-I", "-c", "bootstrap", "--profile", "code", "gateway", "run", "--replace"],
        {"HERMES_HOME": str(root)}) == "code")
    expect("force", named_replace_profile(
        ["py", "--profile", "code", "gateway", "run", "--replace", "--force"], {}) is None)
    expect("profile default", named_replace_profile(
        ["py", "--profile", "default", "gateway", "run", "--replace"], {}) is None)
    expect("home profile", named_replace_profile(
        ["py", "gateway", "run", "--replace"], {"HERMES_HOME": code_home}) == "code")
    expect("status", named_replace_profile(
        ["py", "--profile", "code", "gateway", "status"], {}) is None)
    expect("shell block", command_profile(
        'hermes.exe --profile code gateway run --replace') == "code")
    expect("shell allow default", command_profile(
        "hermes gateway run --replace") is None)
    expect("shell allow force", command_profile(
        "hermes -p code gateway run --replace --force") is None)
    expect("shell allow other", command_profile(
        "hermes --profile code sessions list") is None)
    healthy = {"pid": 5, "gateway_state": "running", "hermes_home": str(root),
               "multiplex_standalone_reason": None}
    expect("healthy", host_is_multiplexer(healthy, root, lambda pid: pid == 5))
    expect("standalone", not host_is_multiplexer(
        {**healthy, "multiplex_standalone_reason": "profile code"}, root, lambda pid: True))
    expect("dead", not host_is_multiplexer(healthy, root, lambda pid: False))
    expect("named home", not host_is_multiplexer(
        {**healthy, "hermes_home": code_home}, root / "profiles" / "code", lambda pid: True))
    expect("quote", restart_command(root, root / "bin" / "hermes.exe") is not None)
    expect("bad quote", restart_command(Path(r"C:\Hermes&Co"), root / "bin" / "hermes.exe") is None)
    hermes_block = block_payload({"hook_event_name": "pre_tool_call"}, "code")
    claude_block = block_payload({}, "code")
    expect("hermes shape", hermes_block.get("action") == "block" and "storage_unavailable" in hermes_block["message"])
    expect("claude shape", claude_block.get("hookSpecificOutput", {}).get("permissionDecision") == "deny")
    text = sitecustomize_text()
    expect("marker", text.startswith("# " + MARKER) and "guard_process" in text)
    import tempfile
    with tempfile.TemporaryDirectory() as tmp:
        site = Path(tmp)
        module = site / GUARD_NAME
        module.write_text("x = 1\n", encoding="utf-8")
        target = site / "sitecustomize.py"
        # install_sitecustomize needs a python.exe under tools/. Exercise the
        # file writer directly so the test does not touch a real Hermes.
        target.write_text(text, encoding="utf-8")
        (site / "uabs_hermes_gateway_guard.py").write_bytes(module.read_bytes())
        expect("installed", MARKER in target.read_text(encoding="utf-8"))
    if failures:
        print("GATEWAY GUARD SELFTEST: FAIL - " + ", ".join(failures))
        return 1
    print("GATEWAY GUARD SELFTEST: PASS")
    return 0


def main() -> int:
    if "--selftest" in sys.argv:
        return selftest()
    local = Path(os.environ.get("LOCALAPPDATA", "") or str(Path.home()))
    source = Path(__file__).resolve()
    if "--install-sitecustomize" in sys.argv:
        written = install_sitecustomize(local, source)
        print("installed " + str(len(written)))
        return 0
    if "--remove-sitecustomize" in sys.argv:
        remove_sitecustomize(local)
        print("removed")
        return 0
    if "--pre" not in sys.argv:
        return 0
    # Repair only when the store Python lost the guard (a Hermes Python
    # upgrade replaces that directory). A present guard costs one stat.
    try:
        if os.environ.get("UABS_GATEWAY_GUARD_REPAIR", "1") != "0" and sitecustomize_missing(local):
            install_sitecustomize(local, source)
    except Exception:
        pass
    payload = read_input()
    profile = command_profile(_tool_command(payload))
    if profile:
        print(json.dumps(block_payload(payload, profile)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
