"""End-to-end gate for the toolbox MCP server (BUNDLED-TOOLS/uabs-toolbox).

Starts the real toolbox over stdio against a disposable state folder, with a
fixture child server standing in for the game/editor tools, and proves:
find lists and starts sets, describe returns schemas, call passes results
through, environment reaches the child but no secret value reaches any output,
project-bound sets need and use the project folder, a crashed child comes back,
parked JSON and TOML entries both load, and a parked copy of a profiled server
is not listed twice. Needs a Python with mcp==1.30.0 (the toolbox's own pin).
Prints TOOLBOX GATE: PASS.
"""

from __future__ import annotations

import json
import os
import shutil
import sys
import tempfile
from pathlib import Path

import anyio
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client

ROOT = Path(__file__).resolve().parent.parent
PKG = ROOT / "BUNDLED-TOOLS" / "uabs-toolbox"
FAKE = PKG / "tests" / "fake_server.py"
# Stands in for a credential in a parked entry: it must reach the server, never output or logs.
PARKED_MARKER = "parked-env-marker-81f2"


def check(cond: bool, message: str) -> None:
    if not cond:
        raise AssertionError(message)


def text_of(result) -> str:
    return "\n".join(getattr(c, "text", "") for c in result.content)


def write_state(state: Path) -> None:
    py = sys.executable
    fake = str(FAKE)
    profiles = {
        "global_scope_guard": {"rules": [
            {"id": "parkedfake", "title": "Parked fixture", "keywords": ["parkedthing"],
             "note": "A server another installer registered machine-wide."},
            {"id": "tomlfake", "title": "TOML fixture", "keywords": ["tomlthing"]},
            {"id": "dupfake", "title": "Duplicate fixture"},
        ]},
        "profiles": [
            {"id": "fixture-profile", "title": "Echo fixture tools", "why": "echo things back",
             "keywords": ["echothing"],
             "servers": [{"id": "fake", "command": py, "args": [fake], "note": "echo fixture"}]},
            {"id": "project-profile", "title": "Project fixture", "keywords": ["projthing"],
             "servers": [{"id": "projfake", "command": py, "args": [fake, "--root", "{project}"],
                          "note": "needs a project"}]},
            {"id": "desk-profile", "title": "Desktop fixture", "keywords": ["deskthing"], "toolbox": "on-request",
             "servers": [{"id": "deskfake", "command": py, "args": [fake, "--desk"]}]},
            {"id": "missing-profile", "title": "Missing editor", "keywords": ["missingthing"],
             "servers": [{"id": "missingfake", "command": py, "args": [fake],
                          "requires": {"any_path": ["%TEMP%\\definitely-not-here-*\\editor.exe"]}}]},
        ],
    }
    (state / "toolbox-profiles.json").write_text(json.dumps(profiles), encoding="utf-8")
    toml_block = (f"[mcp_servers.tomlfake]\ncommand = {json.dumps(py)}\nargs = [{json.dumps(fake)}, \"--toml\"]\n")
    parked = {"schema": 1, "entries": [
        {"provider": "Claude", "id": "parkedfake", "rule": "parkedfake",
         "definition": {"type": "stdio", "command": py, "args": [fake, "--parked"], "env": {"FIXTURE_PARKED_VALUE": PARKED_MARKER}}},
        # Set-McpProfile -Park stores a TOML table as its exact text under "block".
        {"provider": "Codex", "id": "tomlfake", "rule": "tomlfake", "style": "toml", "block": toml_block},
        # Same command and arguments as the profiled "fake": must not appear twice.
        {"provider": "Claude", "id": "dupfake", "rule": "dupfake",
         "definition": {"type": "stdio", "command": py, "args": [fake]}},
    ]}
    (state / "parked-mcp.json").write_text(json.dumps(parked), encoding="utf-8")


async def run_gate(state: Path, project: Path) -> None:
    env = dict(os.environ)
    env.update({"UABS_TOOLBOX_STATE_DIR": str(state), "PYTHONPATH": str(PKG), "UABS_TOOLBOX_DEBUG": "1"})
    params = StdioServerParameters(command=sys.executable, args=["-m", "uabs_toolbox"], env=env)
    seen_text: list[str] = []
    async with stdio_client(params) as (read, write):
        async with ClientSession(read, write) as session:
            init = await session.initialize()
            check("find" in (init.instructions or ""), "server instructions do not explain find")
            tools = {t.name: t for t in (await session.list_tools()).tools}
            check(set(tools) == {"find", "describe", "call"}, f"unexpected tool surface: {sorted(tools)}")
            available = tools["find"].description.split("Available now:")[-1]
            check("parkedfake" in available and "tomlfake" in available, "find does not name the available sets")
            check("missingfake" not in available and "projfake" not in available,
                  "find advertises a set that cannot start without its app or project")
            check("parkedfake" in (init.instructions or ""), "server instructions do not name the available sets")

            listing = text_of(await session.call_tool("find", {"query": ""}))
            seen_text.append(listing)
            for set_id in ("fake", "projfake", "missingfake", "parkedfake", "tomlfake"):
                check(f"- {set_id}:" in listing, f"{set_id} missing from the listing:\n{listing}")
            check("dupfake" not in listing, "a parked copy of a profiled server is listed twice")
            check("missingfake: Missing editor [not available" in listing, "a missing host app is not reported")

            found = text_of(await session.call_tool("find", {"query": "echothing"}))
            seen_text.append(found)
            check("fake.echo:" in found and "[read-only]" in found, f"find did not start and list fake:\n{found}")

            described = json.loads(text_of(await session.call_tool("describe", {"tools": ["fake.echo", "fake.nope"]})))
            check(described["tools"]["fake.echo"]["inputSchema"]["required"] == ["text"], "describe lost the schema")
            check("fake.nope" in described.get("not_found", {}), "describe hid an unknown tool")

            echoed = await session.call_tool("call", {"tool": "fake.echo", "arguments": {"text": "pass-through"}})
            check(not echoed.isError and text_of(echoed) == "pass-through", f"call did not pass through: {echoed}")
            as_string = await session.call_tool("call", {"tool": "fake.echo", "arguments": "{\"text\": \"json-string\"}"})
            check(text_of(as_string) == "json-string", "arguments given as a JSON string were not accepted")

            has = await session.call_tool("call", {"tool": "parkedfake.env_has", "arguments": {"name": "FIXTURE_PARKED_VALUE"}})
            check(text_of(has) == "yes", "a parked entry's env did not reach its server")
            seen_text.append(text_of(await session.call_tool("find", {"query": "parkedthing"})))
            seen_text.append(text_of(await session.call_tool("describe", {"tools": ["parkedfake.env_has"]})))

            desk = text_of(await session.call_tool("find", {"query": "deskthing"}))
            check("controls this PC" in desk and "deskfake.echo:" not in desk,
                  f"find auto-started an on-request (desktop control) set:\n{desk}")
            desk_call = await session.call_tool("call", {"tool": "deskfake.echo", "arguments": {"text": "asked"}})
            check(text_of(desk_call) == "asked", "an explicit call could not start an on-request set")

            toml_found = text_of(await session.call_tool("find", {"query": "tomlthing"}))
            check("tomlfake.echo:" in toml_found, f"a TOML-only parked entry did not start:\n{toml_found}")

            no_project = text_of(await session.call_tool("find", {"query": "projthing"}))
            check("needs a project folder" in no_project, f"project-bound set started without a project:\n{no_project}")
            cwd = await session.call_tool("call", {"tool": "projfake.cwd", "arguments": {}, "project": str(project)})
            check(os.path.normcase(text_of(cwd)) == os.path.normcase(str(project)), f"project cwd not used: {text_of(cwd)}")
            bad = await session.call_tool("call", {"tool": "projfake.cwd", "project": str(project / "missing")})
            check(bad.isError and "project folder not found" in text_of(bad), "a missing project folder was accepted")

            crashed = await session.call_tool("call", {"tool": "fake.crash", "arguments": {}})
            check(crashed.isError, "a crashing tool did not report an error")
            again = await session.call_tool("call", {"tool": "fake.echo", "arguments": {"text": "back"}})
            check(text_of(again) == "back", f"the crashed set did not restart: {again}")

            unknown = await session.call_tool("call", {"tool": "nosuch.thing", "arguments": {}})
            check(unknown.isError and "unknown tool" in text_of(unknown), "an unknown set was not refused")
            unavailable = await session.call_tool("call", {"tool": "missingfake.echo", "arguments": {}})
            check(unavailable.isError and "host application" in text_of(unavailable), "an unavailable set was started")

    joined = "\n".join(seen_text)
    check(PARKED_MARKER not in joined, "a parked credential value reached toolbox output")
    logs = "".join(p.read_text(encoding="utf-8", errors="replace") for p in (state / "logs").glob("*.log"))
    check(PARKED_MARKER not in logs, "a parked credential value reached a toolbox log")


def main() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="uabs toolbox gate "))
    try:
        state = tmp / "state"
        project = tmp / "project with space"
        state.mkdir()
        project.mkdir()
        write_state(state)
        anyio.run(run_gate, state, project)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("TOOLBOX GATE: PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
