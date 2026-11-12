"""Real process boundaries through a folder cmd, PowerShell and TOML each find awkward.

The folder name carries the four hazards at once: '!' (eaten by cmd delayed
expansion), a space and parentheses (they break an unquoted or half-quoted
command line) and a non-ASCII letter (it breaks byte-wise handling). Every test
here crosses an actual process or serialization boundary; none is a string
comparison of a path with itself. Standard library only.
"""
import base64
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AWKWARD = "!Sky tools (x) é"
WINDOWS = os.name == "nt"

MCP_STUB = r'''
import json, sys
for line in sys.stdin:
    try:
        message = json.loads(line)
    except ValueError:
        continue
    method, mid = message.get("method"), message.get("id")
    if method == "initialize":
        result = {"protocolVersion": "2025-06-18", "capabilities": {"tools": {}},
                  "serverInfo": {"name": "awkward-stub", "version": "1"}}
    elif method == "tools/list":
        result = {"tools": [{"name": "echo", "inputSchema": {"type": "object"}}]}
    else:
        continue
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": mid, "result": result}) + "\n")
    sys.stdout.flush()
'''


def load_tool(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class AwkwardFolder(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="uabs awkward ")
        # resolve(): the temp root can be an 8.3 short name (RUNNER~1) while a child
        # process reports the long one. The paths under test are then the same string.
        self.folder = Path(self.temp.name).resolve() / AWKWARD
        self.folder.mkdir()

    def tearDown(self):
        self.temp.cleanup()


@unittest.skipUnless(WINDOWS, "cmd.exe launcher contract")
class BatchLaunchers(AwkwardFolder):
    def run_start_here(self, switches):
        pack = self.folder / "pack"
        pack.mkdir()
        shutil.copy2(ROOT / "START-HERE.bat", pack / "START-HERE.bat")
        (pack / "INSTALL-AIO.ps1").write_text(
            "[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'ran.txt'), $PSScriptRoot, "
            "(New-Object Text.UTF8Encoding($false)))\nexit 7\n", encoding="ascii")
        env = dict(os.environ, UABS_NO_PAUSE="1")
        # Launched from its own folder, as a person at a prompt does: the awkward
        # path then reaches the batch file only through %~dp0. The explicit dot
        # prefix is for hosts that set NoDefaultCurrentDirectoryInExePath.
        done = subprocess.run([os.environ["COMSPEC"], "/d"] + switches + ["/c", ".\\START-HERE.bat"],
                              cwd=str(pack), env=env, capture_output=True, text=True,
                              errors="replace", timeout=120)
        marker = pack / "ran.txt"
        ran = marker.read_text(encoding="utf-8") if marker.exists() else None
        return done, ran, str(pack)

    def test_start_here_reaches_its_installer_and_returns_its_exit_code(self):
        done, ran, pack = self.run_start_here([])
        self.assertEqual(ran, pack, done.stdout + done.stderr)
        self.assertEqual(done.returncode, 7, done.stdout + done.stderr)

    def test_start_here_survives_delayed_expansion_being_on(self):
        done, ran, pack = self.run_start_here(["/v:on"])
        self.assertEqual(ran, pack, "delayed expansion ate the '!' in the pack path\n" + done.stdout + done.stderr)
        self.assertEqual(done.returncode, 7, done.stdout + done.stderr)

    def test_bundle_batch_files_disable_delayed_expansion(self):
        for name in ("START-HERE.bat", "INSTALL-REMOTE.bat"):
            raw = (ROOT / name).read_bytes()
            text = raw.decode("ascii")
            self.assertIn("setlocal DisableDelayedExpansion", text, name)
            self.assertNotIn("enabledelayedexpansion", text.lower().replace("disabledelayedexpansion", ""), name)
            self.assertNotRegex(text, r"(?<!\r)\n", name + " has a bare LF, which cmd can misparse")


class ShellCommandLines(unittest.TestCase):
    """Every cmd /c the bundle builds is immune to a delayed-expansion default."""

    SITES = ("TOOLS/Start-CodebaseMemory-UI.ps1", "TOOLS/Measure-McpSchemaCost.ps1",
             "TOOLS/Test-McpHandshake.ps1", "TOOLS/Install-BuildTools.ps1",
             "TOOLS/mcp_handshake.py", "TOOLS/hooks/hermes_gateway_guard.py")

    def test_cmd_invocations_pin_delayed_expansion_off(self):
        launch = re.compile(r"""(?:'/c'|"/c"|\s/c\s+["'])""")
        for rel in self.SITES:
            hits = [line for line in (ROOT / rel).read_text(encoding="utf-8").splitlines()
                    if launch.search(line) and not line.lstrip().startswith("#")]
            self.assertTrue(hits, rel + " no longer builds a cmd /c line; drop it from SITES")
            for line in hits:
                self.assertIn("/v:off", line, rel + ": " + line.strip())


class McpProbe(AwkwardFolder):
    def setUp(self):
        super().setUp()
        self.server = self.folder / "server (stub).py"
        self.server.write_text(MCP_STUB, encoding="utf-8")
        self.probe = load_tool("awkward_mcp_handshake", ROOT / "TOOLS" / "mcp_handshake.py").probe

    def test_argv_launch_from_an_awkward_folder(self):
        result = self.probe(sys.executable, [str(self.server)], 30)
        self.assertTrue(result.get("ok"), result)
        self.assertEqual(result.get("tool_count"), 1, result)

    @unittest.skipUnless(WINDOWS, "shell_command is a Windows command line")
    def test_shell_command_launch_from_an_awkward_folder(self):
        line = '"%s" "%s"' % (sys.executable, self.server)
        result = self.probe(os.environ["COMSPEC"], [], 30, shell_command=line)
        self.assertTrue(result.get("ok"), result)

    def test_cli_spec_round_trips_the_path(self):
        spec = json.dumps({"command": sys.executable, "args": [str(self.server)], "timeout": 30})
        encoded = base64.b64encode(spec.encode("utf-8")).decode("ascii")
        done = subprocess.run([sys.executable, str(ROOT / "TOOLS" / "mcp_handshake.py"), "--spec", encoded],
                              capture_output=True, text=True, errors="replace", timeout=90)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertTrue(json.loads(done.stdout.strip().splitlines()[-1])["ok"], done.stdout)


@unittest.skipUnless(WINDOWS and shutil.which("powershell.exe"), "Windows PowerShell boundary")
class PowerShellBoundary(AwkwardFolder):
    def powershell(self, *args, env=None):
        return subprocess.run([shutil.which("powershell.exe"), "-NoProfile", "-NonInteractive",
                               "-ExecutionPolicy", "Bypass", *args],
                              capture_output=True, env=env, timeout=120)

    def test_script_path_and_argument_arrive_unchanged(self):
        script = self.folder / "echo (args).ps1"
        script.write_text(
            "param([string]$Value)\n"
            "$out = New-Object Text.UTF8Encoding($false)\n"
            "[Console]::OpenStandardOutput().Write($out.GetBytes($PSScriptRoot + \"`n\" + $Value), 0, "
            "$out.GetByteCount($PSScriptRoot + \"`n\" + $Value))\n", encoding="ascii")
        target = self.folder / "inner !dir" / "file (1).txt"
        done = self.powershell("-File", str(script), "-Value", str(target))
        self.assertEqual(done.returncode, 0, done.stderr)
        self.assertEqual(done.stdout.decode("utf-8").split("\n"), [str(self.folder), str(target)])

    def test_mcp_toml_entry_round_trips_through_a_real_parser(self):
        try:
            import tomllib
        except ImportError:  # Python < 3.11
            self.skipTest("tomllib unavailable")
        out = self.folder / "config (codex).toml"
        command = str(self.folder / "server.exe")
        args = ["--root", str(self.folder / "inner !dir"), '{"filter":"a b","n":1}']
        env = dict(os.environ, T_OUT=str(out), T_CMD=command, T_ARGS=json.dumps(args),
                   T_WRITER=str(ROOT / "TOOLS" / "UABS-Mcp-Write.ps1"))
        body = ("$ErrorActionPreference='Stop'; . $env:T_WRITER; "
                "$s=[ordered]@{id='demo';note='fixture';command=$env:T_CMD;"
                "args=[string[]](ConvertFrom-Json $env:T_ARGS);env_static=@{QUOTED='say \"hi\"'}}; "
                "$null=Add-UabsMcpToml -Path $env:T_OUT -Section 'mcp_servers' -Servers @($s) "
                "-Provider 'Codex' -Scope 'global'")
        done = self.powershell("-Command", body, env=env)
        self.assertEqual(done.returncode, 0, done.stdout.decode("utf-8", "replace") + done.stderr.decode("utf-8", "replace"))
        with open(out, "rb") as handle:
            table = tomllib.load(handle)["mcp_servers"]["demo"]
        self.assertEqual(table["command"], command)
        self.assertEqual(table["args"], args)
        self.assertEqual(table["env"]["QUOTED"], 'say "hi"')


if __name__ == "__main__":
    unittest.main(verbosity=2)
