"""Fixture MCP server for the toolbox tests: echo, env/cwd probes and a crash.

Run by the toolbox as a child exactly like a real tool set. It never prints a
value of an environment variable, only whether one is set.
"""

import os
import sys
from pathlib import Path

import anyio
from mcp import types
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server

server = Server("fixture", instructions="Fixture server used by the toolbox tests.")


@server.list_tools()
async def _tools() -> list[types.Tool]:
    obj = {"type": "object"}
    return [
        types.Tool(name="echo", description="Echo the text back. Used to prove a call passes through.",
                   inputSchema={**obj, "properties": {"text": {"type": "string"}}, "required": ["text"]},
                   annotations=types.ToolAnnotations(readOnlyHint=True)),
        types.Tool(name="env_has", description="Report whether an environment variable is set.",
                   inputSchema={**obj, "properties": {"name": {"type": "string"}}, "required": ["name"]}),
        types.Tool(name="cwd", description="Report the working directory.", inputSchema=obj),
        types.Tool(name="write_then_crash", description="Record a mutation and disconnect before replying.",
                   inputSchema={**obj, "properties": {"path": {"type": "string"}}, "required": ["path"]},
                   annotations=types.ToolAnnotations(destructiveHint=True)),
        types.Tool(name="crash", description="Exit the process at once.", inputSchema=obj,
                   annotations=types.ToolAnnotations(destructiveHint=True)),
    ]


@server.call_tool()
async def _call(name: str, arguments: dict) -> list[types.TextContent]:
    if name == "echo":
        text = arguments["text"]
    elif name == "env_has":
        text = "yes" if os.environ.get(arguments["name"]) else "no"
    elif name == "cwd":
        text = os.getcwd()
    elif name == "write_then_crash":
        with Path(arguments["path"]).open("a", encoding="utf-8") as marker:
            marker.write("once\n")
        os._exit(3)
    elif name == "crash":
        os._exit(3)
    else:
        raise ValueError(f"unknown tool {name}")
    return [types.TextContent(type="text", text=text)]


async def _main() -> None:
    if "--hang-start" in sys.argv:
        await anyio.sleep_forever()
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


if __name__ == "__main__":
    sys.exit(anyio.run(_main))
