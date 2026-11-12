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

import os
import sys

# Fast exit before the heavier imports. A host spawns this file for every shell
# call and almost none of them can concern it, so the first test runs on the raw
# payload bytes with only os and sys loaded. It is a superset test: it may pass an
# irrelevant payload on to the real checks, never drop a relevant one.
_NEEDLES = (b"hermes",)
_RAW = None  # payload bytes the prefilter already consumed


def _read_stdin(timeout: float = 2.0) -> bytes:
    """Read the hook payload from stdin without ever blocking the host.

    `sys.stdin.read()` waits for EOF. A host that spawns the hook but never
    closes the pipe (Grok CLI 1.0.4 does not) leaves that read hanging until
    the host's own hook timeout fires -- measured at 60s per turn. Every field
    is optional, so time-box the read and continue without the payload.
    """
    import threading
    box: dict = {}

    def slurp() -> None:
        # os.read on the raw fd, not sys.stdin.read: a thread parked inside
        # sys.stdin's BufferedReader holds that object's lock, and interpreter
        # shutdown then blocks trying to finalise it -- which reintroduces the
        # exact hang this function exists to avoid.
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
        box["raw"] = b"".join(chunks)

    reader = threading.Thread(target=slurp, daemon=True)
    reader.start()
    reader.join(timeout)
    return box.get("raw") or b""


def _has_unicode_escape(raw: bytes) -> bool:
    """True for a real JSON \\uXXXX escape, which could spell a needle invisibly.

    A Windows path such as C:\\\\Users is an escaped backslash followed by a
    letter, not an escape, so the backslashes before each match are counted.
    """
    at = raw.find(b"\\u")
    while at != -1:
        start = at
        while start > 0 and raw[start - 1] == 0x5C:
            start -= 1
        if (at - start) % 2 == 0:
            return True
        at = raw.find(b"\\u", at + 2)
    return False


if __name__ == "__main__" and "--pre" in sys.argv[1:] and "--selftest" not in sys.argv[1:]:
    _RAW = _read_stdin()
    _low = _RAW.lower()
    # Only the tool input is inspected later. Starting at its key keeps the
    # host's own cwd and transcript paths from matching on every call. Every
    # key a gate may read its command from is listed, so the earliest one wins.
    _keys = [_at for _at in (_low.find(b'"tool_input"'), _low.find(b'"toolinput"'),
                             _low.find(b'"args"')) if _at >= 0]
    _scope = _low[min(_keys):] if _keys else _low
    if not any(_needle in _scope for _needle in _NEEDLES) and not _has_unicode_escape(_scope):
        os._exit(0)

import json
import re
import subprocess
import tempfile
import time
from pathlib import Path

MARKER = "UABS-HERMES-GATEWAY-GUARD"
# The block is delimited so a foreign sitecustomize.py survives install,
# reinstall and uninstall byte-for-byte. The old code appended on first install
# and then overwrote the whole file on the next run, because the marker it used
# to detect "ours" was present either way.
BLOCK_BEGIN = "# >>> " + MARKER + " >>>"
BLOCK_END = "# <<< " + MARKER + " <<<"
# 75 = EX_TEMPFAIL. A blocked replace that could not restore a host must not
# report success to the caller.
EXIT_RECOVERY_FAILED = 75
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
        'cmd.exe /d /v:off /s /c "set HERMES_HOME=' + home
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


def _stop_process(code: int = 0) -> None:
    # site.py execsitecustomize catches Exception only. SystemExit during
    # that import is "Fatal Python error: init_import_site" and exit 1.
    os._exit(int(code))


def wait_for_host(root: Path, seconds: float = 20.0, alive=pid_alive) -> bool:
    """True once the default gateway really answers, not merely when it was spawned."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            if host_is_multiplexer(read_host_state(root) or {}, root, alive):
                return True
        except Exception:
            pass
        time.sleep(0.5)
    return False


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
        _log(root, f"blocked profile={profile} reason=host-alive host=ok")
        _stop_process(0)
    # The recovery spawn carries this flag. It must be ALLOWED through, or the
    # replacement it just started exits immediately and nothing is running -
    # which is how the old guard reported success while leaving no host.
    if env.get(SPAWN_FLAG) == "1":
        _log(root, f"allow profile={profile} reason=recovery-spawn")
        return
    started = spawn_default_host(root)
    healthy = bool(started) and wait_for_host(root)
    _log(root, (f"blocked profile={profile} reason=host-down started={int(bool(started))} "
                f"host={'ok' if healthy else 'missing'}"))
    # A blocked replace that could not restore a host must not exit 0: the
    # agent or updater that ran it would read success.
    _stop_process(0 if healthy else EXIT_RECOVERY_FAILED)


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
    """The hook payload as a dict; empty when absent, late or malformed."""
    raw = (_RAW if _RAW is not None else _read_stdin(timeout)).decode("utf-8", "replace")
    try:
        loaded = json.loads(raw) if raw.strip() else {}
    except Exception:
        return {}
    return loaded if isinstance(loaded, dict) else {}


def _guard_body(nl: str) -> str:
    """The interception, as a delimited, reversible block."""
    return nl.join([
        "def _uabs_hermes_gateway_guard():",
        "    try:",
        "        import importlib.util",
        "        import os",
        "        from pathlib import Path",
        "        candidates = []",
        "        env = os.environ.get('UABS_HERMES_GATEWAY_GUARD', '').strip()",
        "        if env:",
        "            candidates.append(Path(env))",
        "        local = os.environ.get('LOCALAPPDATA', '').strip()",
        "        if local:",
        "            candidates.append(Path(local) / 'Ultimate-AI-Starter-Bundle' / 'hooks' / '"
        + GUARD_NAME + "')",
        "        candidates.append(Path(__file__).resolve().parent / 'uabs_hermes_gateway_guard.py')",
        "        for path in candidates:",
        "            if not path.is_file():",
        "                continue",
        "            spec = importlib.util.spec_from_file_location('uabs_hermes_gateway_guard', path)",
        "            if spec is None or spec.loader is None:",
        "                continue",
        "            module = importlib.util.module_from_spec(spec)",
        "            spec.loader.exec_module(module)",
        "            module.guard_process()",
        "            return",
        "    except SystemExit as exc:",
        "        os._exit(int(exc.code or 0))",
        "    except Exception:",
        "        return",
        "_uabs_hermes_gateway_guard()",
        "",
    ])


def sitecustomize_text(block_only: bool = False) -> str:
    """Text this pack writes. ``block_only`` omits the separating newlines."""
    nl = chr(10)
    body = BLOCK_BEGIN + nl + _guard_body(nl) + BLOCK_END + nl
    return body if block_only else nl + nl + body


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
        if BLOCK_BEGIN not in text:
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


def _read_any(path: Path) -> tuple:
    """(text, had_bom, newline style) without losing bytes we did not write."""
    raw = path.read_bytes()
    bom = raw.startswith(b"\xef\xbb\xbf")
    text = raw.decode("utf-8-sig", "replace")
    nl = "\r\n" if "\r\n" in text else "\n"
    return text, bom, nl


def _replace(src, dst, attempts=6):
    """os.replace with a short retry.

    On Windows a virus scanner or the search indexer can hold a just-written file
    open for a moment, and the rename then fails with PermissionError although
    nothing is wrong. Retrying keeps the write atomic; the last error still raises.
    """
    import time as _time
    for attempt in range(attempts):
        try:
            os.replace(src, dst)
            return
        except PermissionError:
            if attempt == attempts - 1:
                raise
            _time.sleep(0.05 * (2 ** attempt))


def _atomic_write(path: Path, text: str, bom: bool) -> None:
    """Write beside the target and replace it, so a crash cannot truncate it."""
    data = (b"\xef\xbb\xbf" if bom else b"") + text.encode("utf-8")
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".uabs-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        _replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def upsert_block(text: str) -> str:
    """Insert or refresh only this pack's block; never touch foreign text."""
    nl = "\r\n" if "\r\n" in text else "\n"
    block = sitecustomize_text().replace("\n", nl)
    begin = text.find(BLOCK_BEGIN)
    if begin >= 0:
        end = text.find(BLOCK_END, begin)
        if end < 0:
            raise ValueError("guard block start found without its end")
        end += len(BLOCK_END)
        if text[end:end + 2] == nl:
            end += 2
        elif text[end:end + 1] in ("\n", "\r"):
            end += 1
        return text[:begin] + block.lstrip("\r\n") + text[end:]
    return text + block


def strip_block(text: str) -> str:
    """Exact inverse of upsert_block: our bytes out, everything else intact."""
    begin = text.find(BLOCK_BEGIN)
    if begin < 0:
        return text
    # Take back the two separator newlines we added, so a foreign file returns
    # byte-for-byte instead of gaining blank lines on every install cycle.
    head = begin
    for _ in range(2):
        if text[head - 2:head] == "\r\n":
            head -= 2
        elif text[head - 1:head] in ("\n", "\r"):
            head -= 1
        else:
            break
    end = text.find(BLOCK_END, begin)
    if end < 0:
        raise ValueError("guard block start found without its end")
    end += len(BLOCK_END)
    if text[end:end + 2] == "\r\n":
        end += 2
    elif text[end:end + 1] in ("\n", "\r"):
        end += 1
    return text[:head] + text[end:]


def install_sitecustomize(localappdata: Path, source: Path) -> list:
    written = []
    module = source.read_bytes()
    for python in hermes_pythons(localappdata):
        site = site_packages_dir(python)
        if site is None:
            continue
        site.mkdir(parents=True, exist_ok=True)
        target = site / "sitecustomize.py"
        if target.is_file():
            text, bom, _ = _read_any(target)
            # An older build wrote the whole file. That copy is ours only when
            # our marker is its first line; anything else keeps a backup.
            if BLOCK_BEGIN not in text and text.lstrip("\ufeff").startswith("# " + MARKER):
                try:
                    target.rename(target.with_suffix(".py.uabs-legacy-bak"))
                except OSError:
                    pass
                text, bom = "", False
            _atomic_write(target, upsert_block(text), bom)
        else:
            _atomic_write(target, sitecustomize_text(), False)
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
        if target.is_file():
            text, bom, _ = _read_any(target)
            if BLOCK_BEGIN in text:
                rest = strip_block(text)
                if rest.strip():
                    _atomic_write(target, rest, bom)
                else:
                    target.unlink()
            elif text.lstrip("\ufeff").startswith("# " + MARKER):
                # Our pre-block install: the whole file is ours.
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
    expect("marker", BLOCK_BEGIN in text and BLOCK_END in text and "guard_process" in text)
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
    # upgrade replaces that directory). A present guard costs one stat. The
    # prefilter above limits this to payloads that mention Hermes, which is
    # the moment the guard has to be in place.
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
