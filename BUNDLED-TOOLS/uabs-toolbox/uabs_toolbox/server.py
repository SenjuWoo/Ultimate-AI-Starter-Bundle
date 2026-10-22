"""The toolbox MCP server: find / describe / call over the switched-off tool sets.

Three small tools stay in every chat. find() matches a task to tool sets and
lists their tools, starting a set on first use; describe() returns a tool's
input schema; call() runs it and returns the tool's own result unchanged. A
started set lives until the chat ends. Nothing is written to any config.

Debug log: UABS_TOOLBOX_DEBUG=1 writes everything to
%LOCALAPPDATA%\\Ultimate-AI-Starter-Bundle\\logs\\toolbox.log; otherwise only
failures go there. Each started server's own stderr goes to toolbox-<id>.log in
the same folder. stdout is the MCP channel and is never written to.
"""

from __future__ import annotations

import json
import logging
import os
import sys
from contextlib import AsyncExitStack, asynccontextmanager

import anyio
import httpx
from mcp import types
from mcp.client.session import ClientSession
from mcp.client.stdio import StdioServerParameters, stdio_client
from mcp.client.streamable_http import streamable_http_client
from mcp.server.lowlevel import Server
from mcp.server.stdio import stdio_server
from mcp.shared.exceptions import McpError

from . import __version__
from .catalog import Catalog, Toolset, ToolboxError, state_dir, words

START_TIMEOUT = float(os.environ.get("UABS_TOOLBOX_START_TIMEOUT", "180"))
LIST_LIMIT = 25
log = logging.getLogger("uabs_toolbox")


# ---- logging: quiet by default, never on stdout --------------------------------

def _log_dir():
    path = state_dir() / "logs"
    path.mkdir(parents=True, exist_ok=True)
    return path


def _setup_logging() -> None:
    debug = os.environ.get("UABS_TOOLBOX_DEBUG") == "1"
    try:
        handler: logging.Handler = logging.FileHandler(_log_dir() / "toolbox.log", encoding="utf-8", delay=True)
    except OSError:
        handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(handler)
    log.setLevel(logging.DEBUG if debug else logging.WARNING)


def _child_errlog(set_id: str):
    """Where a started server's stderr goes: a per-set log, cut at 1 MB."""
    try:
        path = _log_dir() / f"toolbox-{set_id}.log"
        mode = "w" if path.exists() and path.stat().st_size > 1_000_000 else "a"
        return open(path, mode, encoding="utf-8", errors="replace")
    except OSError:
        return open(os.devnull, "w", encoding="utf-8")


# ---- started servers ------------------------------------------------------------

class Child:
    """One started tool set. Its transport is opened and closed in its own task,
    which is what anyio's cancel scopes require."""

    def __init__(self, toolset: Toolset, project: str | None, spec: dict):
        self.toolset, self.project, self.spec = toolset, project, spec
        self.session: ClientSession | None = None
        self.tools: list[types.Tool] = []
        self.instructions = ""
        self.error = ""
        self.dead = False
        self.ready = anyio.Event()
        self.stop = anyio.Event()
        self.cancel_scope: anyio.CancelScope | None = None

    def cancel(self) -> None:
        """Stop an initialized child or cancel one still connecting."""
        self.stop.set()
        if self.cancel_scope is not None:
            self.cancel_scope.cancel()

    async def run(self) -> None:
        # The transport and its cancel scopes stay in this task. Cancelling an
        # unfinished handshake must also close the child process and pipes.
        with anyio.CancelScope() as scope:
            self.cancel_scope = scope
            if self.stop.is_set():
                scope.cancel()
            await self._run_transport()

    async def _run_transport(self) -> None:
        errlog = None
        try:
            async with AsyncExitStack() as stack:
                if self.spec["kind"] == "http":
                    http = await stack.enter_async_context(httpx.AsyncClient(
                        headers=self.spec["headers"], timeout=httpx.Timeout(30.0, read=300.0)))
                    read, write, _ = await stack.enter_async_context(
                        streamable_http_client(self.spec["url"], http_client=http))
                else:
                    errlog = _child_errlog(self.toolset.id)
                    params = StdioServerParameters(command=self.spec["command"], args=self.spec["args"],
                                                   env=self.spec["env"], cwd=self.spec["cwd"])
                    read, write = await stack.enter_async_context(stdio_client(params, errlog=errlog))
                session = await stack.enter_async_context(ClientSession(read, write))
                init = await session.initialize()
                self.instructions = init.instructions or ""
                self.tools = await list_all_tools(session)
                self.session = session
                log.debug("started %s (%d tools)", self.toolset.id, len(self.tools))
                self.ready.set()
                await self.stop.wait()
        except Exception as exc:  # recorded and reported by the caller; never kills the toolbox
            self.error = describe_error(exc)
            log.warning("%s stopped: %s", self.toolset.id, self.error)
        finally:
            self.dead = True
            self.session = None
            self.ready.set()
            if errlog:
                errlog.close()


async def list_all_tools(session: ClientSession) -> list[types.Tool]:
    tools, cursor = [], None
    while True:
        page = await session.list_tools(cursor=cursor)
        tools.extend(page.tools)
        cursor = page.nextCursor
        if not cursor:
            return tools


def describe_error(exc: BaseException) -> str:
    """One readable line, from the first real cause inside any exception group."""
    while isinstance(exc, BaseExceptionGroup) and exc.exceptions:
        exc = exc.exceptions[0]
    text = str(exc).strip().splitlines()[0] if str(exc).strip() else type(exc).__name__
    return text[:300]


class Manager:
    """Starts tool sets on demand and keeps them for the session."""

    def __init__(self, tg: anyio.abc.TaskGroup, catalog: Catalog):
        self.tg, self.catalog = tg, catalog
        self.children: dict[tuple[str, str], Child] = {}
        self.lock = anyio.Lock()

    async def child(self, toolset: Toolset, project: str | None) -> Child:
        key = (toolset.id, os.path.normcase(project or ""))
        async with self.lock:
            child = self.children.get(key)
            if child is None or child.dead:
                child = Child(toolset, project, toolset.launch(project))
                self.children[key] = child
                self.tg.start_soon(child.run)
        with anyio.move_on_after(START_TIMEOUT) as scope:
            await child.ready.wait()
        if scope.cancelled_caught:
            child.cancel()
            raise ToolboxError(f"{toolset.id} did not start within {int(START_TIMEOUT)}s")
        if child.session is None:
            raise ToolboxError(f"{toolset.id} failed to start: {child.error or 'it exited'}"
                               f" (details: {_log_dir() / ('toolbox-' + toolset.id + '.log')})")
        return child

    def close(self) -> None:
        for child in self.children.values():
            child.cancel()


# ---- the three tools ------------------------------------------------------------

PROJECT_ARG = {"type": "string", "description": (
    "Absolute path of the project folder. Needed only by tools that work on one "
    "project (Unity, shadcn, Serena); others ignore it.")}


def ready_ids(catalog: Catalog) -> str:
    """Set ids that can start without a project: short, and the words a tool
    search matches (rimworld, blender, unity, github ...)."""
    return ", ".join(ts.id for ts in catalog.toolsets if ts.status(None) is None)


def tool_list(catalog: Catalog) -> list[types.Tool]:
    available = ready_ids(catalog)
    return [
        types.Tool(
            name="find",
            description=(
                "Find project tools that are switched off to save tokens and start them on demand: "
                "game and mod tools, 3D and game editors, browser automation, code graph, GitHub API, "
                "Melty mashups and more. Give the task in a few words, e.g. 'build my RimWorld mod'. "
                "Returns matching tool sets with their tools; no restart or config change is needed. "
                "Available now: " + (available or "none") + "."),
            inputSchema={"type": "object", "properties": {
                "query": {"type": "string", "description": "The task or tool you need. Empty lists every tool set."},
                "project": PROJECT_ARG}},
            annotations=types.ToolAnnotations(readOnlyHint=True, openWorldHint=False)),
        types.Tool(
            name="describe",
            description="Input schemas for toolbox tools, named as find returned them (set.tool).",
            inputSchema={"type": "object", "required": ["tools"], "properties": {
                "tools": {"type": "array", "items": {"type": "string"}, "minItems": 1, "maxItems": 20},
                "project": PROJECT_ARG}},
            annotations=types.ToolAnnotations(readOnlyHint=True, openWorldHint=False)),
        types.Tool(
            name="call",
            description=("Run one toolbox tool: its name as find returned it (set.tool) and its arguments "
                         "as describe showed them. Returns that tool's own result."),
            inputSchema={"type": "object", "required": ["tool"], "properties": {
                "tool": {"type": "string"},
                # A JSON string is accepted too: models sometimes serialize nested objects.
                "arguments": {"type": ["object", "string"], "description": "The tool's arguments as describe showed them."},
                "project": PROJECT_ARG}},
            annotations=types.ToolAnnotations(openWorldHint=True)),
    ]


def _project(arguments: dict) -> str | None:
    project = arguments.get("project")
    if not project:
        return None
    project = os.path.abspath(str(project))
    if not os.path.isdir(project):
        raise ToolboxError(f"project folder not found: {project}")
    return project


def _first_sentence(text: str | None, limit: int = 140) -> str:
    text = " ".join((text or "").split())
    cut = text.find(". ")
    text = text[: cut + 1] if 0 < cut < limit else text
    return text if len(text) <= limit else text[: limit - 3] + "..."


def _hints(tool: types.Tool) -> str:
    a = tool.annotations
    if not a:
        return ""
    if a.readOnlyHint:
        return " [read-only]"
    if a.destructiveHint:
        return " [changes things]"
    return ""


def _rank_tools(tools: list[types.Tool], query: str) -> list[types.Tool]:
    terms = words(query)
    def score(t: types.Tool) -> int:
        text = (t.name + " " + (t.description or "")).lower()
        return -sum(1 for term in terms if term in text)
    return sorted(tools, key=score)


async def do_find(mgr: Manager, query: str, project: str | None) -> str:
    catalog = mgr.catalog
    catalog.refresh()
    if not query.strip():
        lines = [f"{len(catalog.toolsets)} tool sets (a ready set starts on first use):"]
        for ts in catalog.toolsets:
            reason = ts.status(project)
            lines.append(f"- {ts.id}: {ts.title}" + (f" [not available: {reason}]" if reason else " [ready]"))
        lines.append("Next: find with your task to list a set's tools.")
        return "\n".join(lines)
    ranked = catalog.rank(query)
    if not ranked:
        return (f'No tool set matches "{query}". Sets: '
                + ", ".join(ts.id for ts in catalog.toolsets) + ". Try another word, or find with an empty query.")
    lines, started = [], 0
    top = ranked[0][0]
    # Sets that match less than half as well as the best one only share a
    # generic word ("build", "mod"); listing them is noise.
    ranked = [(score, ts) for score, ts in ranked if score * 2 >= top]
    for score, ts in ranked[:5]:
        reason = ts.status(project)
        if reason:
            lines.append(f"- {ts.id}: {ts.title} [not available: {reason}]")
            continue
        # Start only the best match (and exact ties): a weaker match that shares
        # a word like "build" would otherwise spawn a server nobody asked for.
        if ts.on_request:
            lines.append(f"- {ts.id}: {ts.title} [controls this PC; starts only when you describe or call "
                         f"one of its tools for something the user asked]")
            continue
        if score < top or started == 3:
            lines.append(f"- {ts.id}: {ts.title} [ready; find '{ts.id}' lists its tools]")
            continue
        try:
            child = await mgr.child(ts, project)
        except ToolboxError as exc:
            lines.append(f"- {ts.id}: {ts.title} [could not start: {exc}]")
            continue
        started += 1
        lines.append(f"- {ts.id}: {ts.title} ({len(child.tools)} tools)")
        for tool in _rank_tools(child.tools, query)[:LIST_LIMIT]:
            lines.append(f"  {ts.id}.{tool.name}: {_first_sentence(tool.description)}{_hints(tool)}")
        if len(child.tools) > LIST_LIMIT:
            lines.append(f"  ...and {len(child.tools) - LIST_LIMIT} more; a narrower task ranks them first.")
        if child.instructions:
            lines.append("  Server note: " + _first_sentence(child.instructions, 600))
    lines.append('Next: describe(["<set>.<tool>"]) for its arguments, then call.')
    return "\n".join(lines)


async def _resolve(mgr: Manager, full_name: str, project: str | None) -> tuple[Child, types.Tool]:
    set_id, _, tool_name = str(full_name).partition(".")
    toolset = mgr.catalog.get(set_id)
    if toolset is None or not tool_name:
        raise ToolboxError(f"unknown tool '{full_name}'; use find to get names in set.tool form")
    child = await mgr.child(toolset, project)
    tool = next((t for t in child.tools if t.name == tool_name), None)
    if tool is None and child.session is not None:
        child.tools = await list_all_tools(child.session)
        tool = next((t for t in child.tools if t.name == tool_name), None)
    if tool is None:
        raise ToolboxError(f"{set_id} has no tool '{tool_name}'; use find '{set_id}' to list them")
    return child, tool


async def do_describe(mgr: Manager, names: list, project: str | None) -> str:
    out: dict = {"tools": {}, "not_found": {}}
    for full_name in list(names)[:20]:
        try:
            _, tool = await _resolve(mgr, str(full_name), project)
        except ToolboxError as exc:
            out["not_found"][str(full_name)] = str(exc)
            continue
        entry = {"description": tool.description or "", "inputSchema": tool.inputSchema}
        if tool.annotations:
            entry["annotations"] = tool.annotations.model_dump(exclude_none=True)
        out["tools"][str(full_name)] = entry
    if not out["not_found"]:
        del out["not_found"]
    return json.dumps(out, ensure_ascii=False)


async def do_call(mgr: Manager, full_name: str, arguments: object, project: str | None) -> types.CallToolResult:
    if isinstance(arguments, str):
        try:
            arguments = json.loads(arguments) if arguments.strip() else {}
        except ValueError as exc:
            raise ToolboxError(f"arguments must be an object: {exc}") from None
    if arguments is None:
        arguments = {}
    if not isinstance(arguments, dict):
        raise ToolboxError("arguments must be an object")
    for attempt in (1, 2):
        child, tool = await _resolve(mgr, full_name, project)
        session = child.session
        try:
            if session is None:
                raise anyio.ClosedResourceError
            return await session.call_tool(tool.name, arguments)
        except McpError as exc:
            if exc.error.code != types.CONNECTION_CLOSED:
                raise ToolboxError(f"{full_name}: {exc.error.message}") from None
        except (anyio.ClosedResourceError, anyio.BrokenResourceError):
            pass
        child.dead = True
        child.cancel()
        # Losing a reply is ambiguous: a file write or upload may already have
        # succeeded. Only explicitly read-only tools are safe to repeat.
        if not (tool.annotations and tool.annotations.readOnlyHint is True):
            raise ToolboxError(f"{full_name}: connection lost; outcome unknown. "
                               "Not retried. Check the result before repeating the action.") from None
        if attempt == 2:
            raise ToolboxError(f"{full_name}: its server stopped and did not come back") from None
    raise ToolboxError(f"{full_name}: unreachable")


def _text(message: str, error: bool = False) -> types.CallToolResult:
    return types.CallToolResult(content=[types.TextContent(type="text", text=message)], isError=error)


# ---- server wiring --------------------------------------------------------------

def build_server(catalog: Catalog) -> Server:
    available = ready_ids(catalog)
    instructions = (
        "Project tools kept switched off to save tokens, started here on demand"
        + (f" ({available})" if available else "")
        + ". When a task needs one, call find with the task, then describe and call; "
        "no restart or config change. Prefer a tool the chat already shows directly.")

    @asynccontextmanager
    async def lifespan(_server: Server):
        async with anyio.create_task_group() as tg:
            mgr = Manager(tg, catalog)
            try:
                yield mgr
            finally:
                mgr.close()

    server: Server = Server("toolbox", version=__version__, instructions=instructions, lifespan=lifespan)

    @server.list_tools()
    async def _list_tools() -> list[types.Tool]:
        catalog.refresh()
        return tool_list(catalog)

    @server.call_tool()
    async def _call_tool(name: str, arguments: dict) -> types.CallToolResult:
        mgr: Manager = server.request_context.lifespan_context
        try:
            project = _project(arguments)
            if name == "find":
                return _text(await do_find(mgr, str(arguments.get("query") or ""), project))
            if name == "describe":
                return _text(await do_describe(mgr, list(arguments.get("tools") or []), project))
            if name == "call":
                return await do_call(mgr, str(arguments.get("tool") or ""), arguments.get("arguments"), project)
            return _text(f"unknown toolbox tool '{name}'", error=True)
        except ToolboxError as exc:
            log.info("%s: %s", name, exc)
            return _text(str(exc), error=True)

    return server


async def _serve() -> None:
    catalog = Catalog()
    log.debug("uabs-toolbox %s: %d tool sets from %s", __version__, len(catalog.toolsets), catalog.root)
    server = build_server(catalog)
    async with stdio_server() as (read, write):
        await server.run(read, write, server.create_initialization_options())


def main() -> None:
    if "--version" in sys.argv[1:]:
        sys.stderr.write(f"uabs-toolbox {__version__}\n")
        return
    if "--list" in sys.argv[1:]:
        # Diagnostic only: what this machine can start, written to stderr.
        catalog = Catalog()
        for ts in catalog.toolsets:
            reason = ts.status(None)
            sys.stderr.write(f"{ts.id}\t{'ready' if not reason else reason}\t{ts.source}\n")
        return
    _setup_logging()
    anyio.run(_serve)


if __name__ == "__main__":
    main()
