"""Tool sets the toolbox can start, read from the bundle's own state files.

Both files are written by the bundle installer into its state folder
(%LOCALAPPDATA%\\Ultimate-AI-Starter-Bundle, or UABS_TOOLBOX_STATE_DIR):

  toolbox-profiles.json  copy of BUNDLED-TOOLS/PROFILES.json: the servers the
                         bundle knows how to launch (forges, editors, browser,
                         code graph, GitHub ...)
  parked-mcp.json        exact copies of servers a tool's own installer had
                         registered machine-wide (Set-McpProfile.ps1 -Park)

One tool set is one server. Launch specs keep their %VAR% and {project}
templates until the server starts. Credentials (env values, headers) are read
only to launch a server and never appear in any text this module returns.
"""

from __future__ import annotations

import glob
import json
import os
import re
import shutil
import subprocess
import tomllib
from dataclasses import dataclass, field
from pathlib import Path

PROFILES_FILE = "toolbox-profiles.json"
PARKED_FILE = "parked-mcp.json"
# Search words carry no meaning on their own; dropping them keeps "build my
# rimworld mod" from matching every set that mentions building something.
_STOP = {
    "a", "an", "and", "any", "are", "be", "can", "do", "for", "from", "help", "i",
    "in", "is", "it", "me", "my", "need", "of", "on", "or", "please", "some",
    "that", "the", "this", "to", "tool", "tools", "use", "using", "want", "with",
}
_VAR = re.compile(r"%([^%]+)%")


class ToolboxError(Exception):
    """A user-facing reason a tool set cannot be listed, started or called."""


def state_dir() -> Path:
    override = os.environ.get("UABS_TOOLBOX_STATE_DIR")
    if override:
        return Path(override)
    base = os.environ.get("LOCALAPPDATA") or os.environ.get("TEMP") or "."
    return Path(base) / "Ultimate-AI-Starter-Bundle"


def expand(text: object, project: str | None) -> str | None:
    """%VAR% like [Environment]::ExpandEnvironmentVariables, then {project}.

    Returns None when the text needs {project} and no project was given.
    Unset variables stay literal, which a requirement check then reports.
    """
    out = _VAR.sub(lambda m: os.environ.get(m.group(1), m.group(0)), str(text))
    if "{project}" in out:
        if not project:
            return None
        out = out.replace("{project}", project.rstrip("\\/"))
    return out


def words(text: str) -> list[str]:
    return [w for w in re.findall(r"[a-z0-9]+", text.lower()) if w not in _STOP and len(w) > 1]


_PYTHON: list[str] | None = None


def resolve_python() -> list[str] | None:
    """A Python that runs. The python.exe first on PATH is often the Microsoft
    Store stub, so the py launcher goes first and every candidate is run."""
    global _PYTHON
    if _PYTHON is not None:
        return _PYTHON or None
    flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
    for cand in (["py", "-3"], ["python"], ["python3"]):
        exe = shutil.which(cand[0])
        if not exe:
            continue
        try:
            ok = subprocess.run([exe, *cand[1:], "-c", "import sys"], capture_output=True,
                                timeout=20, creationflags=flags).returncode == 0
        except (OSError, subprocess.SubprocessError):
            ok = False
        if ok:
            _PYTHON = [exe, *cand[1:]]
            return _PYTHON
    _PYTHON = []
    return None


def _command_reason(command: str, project: str | None) -> str | None:
    resolved = expand(command, project)
    if not resolved:
        return "needs a project folder (pass project)"
    if resolved.lower() == "python":
        return None if resolve_python() else "no working Python found"
    if re.search(r"[\\/]", resolved):
        return None if os.path.isfile(resolved) else f"not installed ({resolved})"
    return None if shutil.which(resolved) else f"command not found: {resolved}"


@dataclass
class Toolset:
    """One startable server and what the finder knows about it."""

    id: str
    title: str
    note: str
    server: dict
    source: str
    search_text: str = ""
    requires: dict = field(default_factory=dict)
    # "toolbox": "on-request" in its profile: find lists it but never starts it
    # (desktop control); only an explicit describe or call does.
    on_request: bool = False

    @property
    def project_bound(self) -> bool:
        """Cannot start without a project. project_args alone do not count: a
        server with global_args (Serena) runs without one."""
        s = self.server
        text = json.dumps([s.get("command"), s.get("args"), s.get("env"), s.get("url")])
        return "{project}" in text or bool(self.requires.get("project_rel"))

    def status(self, project: str | None) -> str | None:
        """None when the set can start now; otherwise the reason it cannot."""
        req = self.requires
        if self.project_bound and not project:
            return "needs a project folder (pass project)"
        reason = None if self.server.get("url") else _command_reason(str(self.server.get("command", "")), project)
        if reason:
            return reason
        if req.get("command"):
            reason = _command_reason(str(req["command"]), project)
            if reason:
                return reason
        if req.get("any_path"):
            hits = [p for p in (expand(x, project) for x in req["any_path"]) if p and glob.glob(p)]
            if not hits:
                return "its host application is not installed"
        if req.get("env") and not os.environ.get(str(req["env"])):
            return f"{req['env']} is not set"
        if req.get("project_rel"):
            if not project:
                return "needs a project folder (pass project)"
            if not os.path.exists(os.path.join(project, str(req["project_rel"]))):
                return f"this project has no {req['project_rel']}"
        return None

    def launch(self, project: str | None) -> dict:
        """Concrete launch spec. Raises ToolboxError with the missing piece."""
        reason = self.status(project)
        if reason:
            raise ToolboxError(f"{self.id}: {reason}")
        s = self.server
        if s.get("url"):
            url = expand(s["url"], project)
            headers = {str(k): str(expand(v, project)) for k, v in (s.get("headers") or {}).items()}
            return {"kind": "http", "url": url, "headers": headers}
        command = expand(s["command"], project)
        prefix: list[str] = []
        if command.lower() == "python":
            command, *prefix = resolve_python()
        argv = list(s.get("args") or [])
        if project and s.get("project_args"):
            argv += list(s["project_args"])
        elif s.get("global_args"):
            argv += list(s["global_args"])
        extra_env = s.get("extra_args_env")
        if extra_env and os.environ.get(extra_env):
            argv += [str(t).replace("{value}", os.environ[extra_env]) for t in s.get("extra_args_template") or []]
        args = [expand(a, project) for a in argv]
        if any(a is None for a in args):
            raise ToolboxError(f"{self.id}: needs a project folder (pass project)")
        env = dict(os.environ)
        env.update({str(k): str(v) for k, v in (s.get("env_static") or {}).items()})
        env.update({str(k): str(expand(v, project)) for k, v in (s.get("env") or {}).items()})
        cwd = project or s.get("cwd") or None
        return {"kind": "stdio", "command": command, "args": prefix + args, "env": env, "cwd": cwd}

    def identity(self) -> str:
        """What the server launches (command AND arguments, or URL), for spotting
        one server that is both parked and profiled. Two scripts run by the same
        Python are different servers."""
        s = self.server
        if s.get("url"):
            return "url:" + str(s["url"]).strip().lower()
        cmd = expand(s.get("command", ""), None) or str(s.get("command", ""))
        args = [expand(a, None) or str(a) for a in s.get("args") or []]
        return "cmd:" + os.path.normcase(os.path.normpath(cmd)) + "|" + "|".join(args)


def _read_json(path: Path) -> object:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return None


def _parked_definition(entry: dict) -> dict | None:
    """A parked entry's server, normalized: JSON/Hermes entries as-is, a TOML
    table (Codex/Grok, saved as `block`) parsed."""
    d = entry.get("definition")
    if isinstance(d, dict):
        return d
    if not isinstance(d, str):
        d = entry.get("block")
    if not isinstance(d, str):
        return None
    try:
        tables = tomllib.loads(d)
    except tomllib.TOMLDecodeError:
        return None
    for section in ("mcp_servers", "mcpServers"):
        found = (tables.get(section) or {}).get(entry.get("id"))
        if isinstance(found, dict):
            out = dict(found)
            if "http_headers" in out:
                out["headers"] = out.pop("http_headers")
            token_var = out.pop("bearer_token_env_var", None)
            if token_var:
                out.setdefault("headers", {})["Authorization"] = "Bearer %" + str(token_var) + "%"
            return out
    return None


class Catalog:
    """Every tool set, rebuilt when either source file changes."""

    def __init__(self, root: Path | None = None):
        self.root = root or state_dir()
        self._stamp: tuple | None = None
        self.toolsets: list[Toolset] = []
        self.refresh()

    def _files_stamp(self) -> tuple:
        out = []
        for name in (PROFILES_FILE, PARKED_FILE):
            try:
                st = (self.root / name).stat()
                out.append((name, st.st_mtime_ns, st.st_size))
            except OSError:
                out.append((name, 0, 0))
        return tuple(out)

    def refresh(self) -> None:
        stamp = self._files_stamp()
        if stamp == self._stamp:
            return
        self._stamp = stamp
        sets: dict[str, Toolset] = {}
        profiles = _read_json(self.root / PROFILES_FILE) or {}
        rules = {r.get("id"): r for r in ((profiles.get("global_scope_guard") or {}).get("rules") or [])}
        for prof in profiles.get("profiles") or []:
            for srv in prof.get("servers") or []:
                sid = str(srv.get("id") or "")
                if not sid or sid in sets or not (srv.get("command") or srv.get("url")):
                    continue
                text = " ".join(str(x) for x in (
                    sid, prof.get("id"), prof.get("title"), prof.get("why"), srv.get("note"),
                    " ".join(prof.get("keywords") or []), " ".join(srv.get("keywords") or [])))
                sets[sid] = Toolset(
                    id=sid, title=str(prof.get("title") or sid), note=str(srv.get("note") or ""),
                    server=srv, source="profile:" + str(prof.get("id")), search_text=text.lower(),
                    requires=dict(srv.get("requires") or {}),
                    on_request=prof.get("toolbox") == "on-request")
        parked = _read_json(self.root / PARKED_FILE) or {}
        identities = {ts.identity() for ts in sets.values()}
        # Claude/Kimi JSON first: exact copies, no TOML parsing involved.
        order = {"Claude": 0, "Kimi": 1, "Hermes": 2}
        for entry in sorted(parked.get("entries") or [], key=lambda e: order.get(e.get("provider"), 9)):
            rule_id = str(entry.get("rule") or entry.get("id") or "")
            if not rule_id or rule_id in sets:
                continue
            definition = _parked_definition(entry)
            if not definition or not (definition.get("command") or definition.get("url")):
                continue
            rule = rules.get(rule_id) or {}
            ts = Toolset(
                id=rule_id, title=str(rule.get("title") or rule_id), note=str(rule.get("note") or ""),
                server=definition, source="parked:" + str(entry.get("provider")))
            if ts.identity() in identities:
                continue
            ts.search_text = " ".join(str(x) for x in (
                rule_id, ts.title, ts.note, " ".join(rule.get("keywords") or []),
                " ".join(rule.get("match") or []))).lower()
            sets[rule_id] = ts
            identities.add(ts.identity())
        self.toolsets = sorted(sets.values(), key=lambda t: t.id)

    def get(self, set_id: str) -> Toolset | None:
        self.refresh()
        return next((t for t in self.toolsets if t.id == set_id), None)

    def rank(self, query: str) -> list[tuple[int, Toolset]]:
        """Tool sets whose text contains query words, best first."""
        self.refresh()
        terms = words(query)
        ranked = []
        for ts in self.toolsets:
            score = sum(3 if term == ts.id or term in ts.id else 1
                        for term in terms if term in ts.search_text or term in ts.id)
            if score:
                ranked.append((score, ts))
        ranked.sort(key=lambda pair: (-pair[0], pair[1].id))
        return ranked
