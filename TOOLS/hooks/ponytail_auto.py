"""Decide Ponytail's mode outside the model, deterministically.

The model is not asked to choose a mode, and nothing here calls a model. A short
rule set reads the operator's prompt plus two small config files and emits the
exact instruction the next request will carry, or nothing at all.

Contract, in priority order:

1. An explicit request in the prompt wins ("stop ponytail", "ponytail lite").
2. A choice made earlier in the same session sticks, so a mode does not flip
   between turns of one job.
3. A project file (`.ponytail.json`) wins over classification.
4. Otherwise the classifier runs, and its default answer is OFF.
5. ULTRA is only ever produced by an explicit request.

The classifier is deliberately dull: keyword families plus a "concrete token"
test (a path, a code fence, an error signature, an issue or line number). A
prompt that cannot prove it is a narrow fix stays OFF, because a wrong LITE on a
creative or architectural request costs the operator the thing they wanted.

Hook contract (Hermes `pre_llm_call`, Claude `UserPromptSubmit`): JSON on stdin,
`{"context": "..."}` on stdout. Any error exits 0 with no output, so a broken
install can never block a turn.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

LEVELS = ("off", "lite", "full", "ultra")
AUTO_LEVELS = ("off", "lite", "full")
STATE_DIR = Path(os.environ.get("LOCALAPPDATA") or Path.home() / "AppData" / "Local") / "Ultimate-AI-Starter-Bundle"
STATE = STATE_DIR / "ponytail-auto.json"
SESSION_TTL = 12 * 60 * 60

# One instruction per level. This is the text the model receives; a test asserts
# that the level token and its rule body arrive together.
RULES = {
    "lite": (
        "Build exactly what was asked; name the smaller alternative in one line and let the user pick. "
        "Shortest diff, no new abstraction, option or dependency. Fix the root cause once and check the callers. "
        "One small test or self-check for non-trivial logic. End with one line: what you skipped, and any risk."
    ),
    "full": (
        "Solve the whole problem with the least new code. Read the task and the code it touches; list every place the change must reach "
        "(callers, tests, fixtures, config, exports) and what it could break. Take the first option that fully works: skip what need not exist, "
        "reuse what the codebase has, then the standard library, then an installed dependency, then one line, then the minimum that works. "
        "No abstraction, option or 'for later' code nobody asked for; deletion beats addition; keep the existing structure. "
        "Never cut validation at trust boundaries, error handling that prevents data loss, security, or anything the user asked for. "
        "Lazy code without its check is unfinished: one small test for non-trivial logic. End with one line: what you skipped or did not check, and any risk."
    ),
    "ultra": (
        "As FULL, and also question the request itself: before building, push back on any part the need does not justify."
    ),
}
PREFIX = "PONYTAIL MODE"

# Prompt-level control. Parsed before anything else, case-insensitively.
RE_OFF = re.compile(r"(?:^|[\s.])(?:stop ponytail|ponytail off|normal mode|disable ponytail)\b", re.I)
RE_MODE = re.compile(r"(?:/ponytail|ponytail)\s+(lite|full|ultra)\b", re.I)
RE_LAZY = re.compile(r"\b(be lazy|simplest solution|yagni|smallest change|minimal change)\b", re.I)

RE_CREATIVE = re.compile(
    r"\b(story|stories|poem|scene|chapter|novel|character|characters|dialogue|lore|brainstorm|"
    r"ideas?|design|mockup|mock-up|concept|mood ?board|poster|logo|thumbnail|video|compose|"
    r"write me|write a|draft|marketing|tagline|pitch|essay|article|script for)\b", re.I)
RE_AMBIGUOUS = re.compile(
    r"^\s*(what|why|how|should|can|could|would|is|are|do|does|thoughts|opinions?)\b|"
    r"\bwhat do you think\b|\bshould i\b|\bhow would you\b", re.I)
RE_SIMPLIFY = re.compile(
    r"\b(simplify|refactor (?:this|it|the)|de-?dupe|duplicat(?:e|ed|ion)|dead code|over-?engineer\w*|"
    r"reduce (?:the )?(?:code|complexity|size)|make it (?:smaller|simpler)|clean ?up)\b", re.I)
RE_FIX = re.compile(
    r"\b(fix|fixes|fixed|typo|rename|bump|patch|revert|hotfix|crash(?:es|ed)?|regression|"
    r"broken|fails?|failing|failure|traceback|exception|error|bug)\b", re.I)
RE_ARTIFACT = re.compile(
    r"\b(manifest|changelog|release notes?|readme|docs?|documentation|version|tests?|suite|workflow|installer)\b", re.I)
RE_MAINT = re.compile(
    r"\b(changelog|release notes?|regenerate|refresh the manifest|update the docs|version bump|"
    r"bump (?:the )?version|add (?:the )?missing test|wire up)\b", re.I)

# Proof that the prompt points at something real. Without one, a fix request is
# still ambiguous: "fix it" names no artifact and stays OFF.
RE_PATH = re.compile(r"(?:[A-Za-z]:[\\/]|\.{0,2}/)[\w.\-/\\]+|\b[\w-]+\.(?:ps1|psm1|py|js|ts|tsx|cs|cpp|h|rs|go|md|json|ya?ml|toml|ini|xaml|xaml\.cs|bat|cmd)\b")
RE_ISSUE = re.compile(r"(?:#\d{1,6}|\bline \d+\b|\bcommit [0-9a-f]{7,40}\b|\bv?\d+\.\d+\.\d+\b)", re.I)
RE_FENCE = re.compile(r"```")
RE_STACK = re.compile(r"(?:Traceback \(most recent call last\)|at [\w.$]+\([\w.]+:\d+\)|Exit code:?\s*\d+|\bE[A-Z]{3,}\b)")


def _load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8-sig"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def _project_config(start: Path | None = None) -> dict:
    """Nearest `.ponytail.json` at or above the working directory."""
    here = Path(start or Path.cwd()).resolve()
    for folder in (here, *here.parents):
        candidate = folder / ".ponytail.json"
        if candidate.is_file():
            data = _load_json(candidate)
            data["_path"] = str(candidate)
            return data
    return {}


def _session_state(session_id: str | None, mode: str | None = None) -> dict | None:
    data = _load_json(STATE)
    sessions = data.get("sessions") if isinstance(data.get("sessions"), dict) else {}
    now = time.time()
    sessions = {k: v for k, v in sessions.items() if isinstance(v, dict) and now - float(v.get("ts", 0)) < SESSION_TTL}
    if mode is not None and session_id:
        sessions[session_id] = {"mode": mode, "ts": now}
        data["sessions"] = sessions
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps(data, indent=1) + "\n", encoding="utf-8")
        return None
    return sessions.get(session_id or "")


def _cap(mode: str, ceiling: str) -> str:
    order = {m: i for i, m in enumerate(LEVELS)}
    return mode if order.get(mode, 0) <= order.get(ceiling, 2) else ceiling


def classify(prompt: str) -> tuple[str, str]:
    """The deterministic decision for one prompt. Never returns ultra."""
    text = (prompt or "").strip()
    if not text:
        return "off", "empty prompt"

    concrete = bool(RE_PATH.search(text) or RE_ISSUE.search(text) or RE_FENCE.search(text) or RE_STACK.search(text))
    creative = bool(RE_CREATIVE.search(text))
    simplify = bool(RE_SIMPLIFY.search(text))
    fix = bool(RE_FIX.search(text))
    maint = bool(RE_MAINT.search(text))
    question = bool(RE_AMBIGUOUS.search(text))

    if creative:
        return "off", "creative or exploratory request"
    if question and not (concrete and (fix or maint)):
        return "off", "open question without a concrete target"
    if simplify and not creative:
        return "full", "requested simplification"
    if maint and (concrete or RE_ARTIFACT.search(text)):
        return "full", "well-defined maintenance"
    if fix and concrete:
        return "lite", "narrow fix with a concrete target"
    if fix and not concrete:
        return "off", "fix request with no file, error or issue"
    return "off", "no clear coding task"


MODE_STATE = STATE_DIR / "ponytail-mode" / "state.json"


def selected_mode() -> str:
    """The operator's choice from TOOLS/ponytail_mode.py - the one authority.

    Missing, unreadable or unknown state means OFF: a hook must never invent a
    level the operator did not ask for.
    """
    data = _load_json(MODE_STATE)
    mode = str(data.get("mode", "")).lower()
    return mode if mode in ("off", "lite", "full", "ultra", "auto") else "off"


def resolve(prompt: str, session_id: str | None = None, cwd: Path | None = None,
            global_config: dict | None = None) -> dict:
    """Full decision: selected mode > explicit > session > project > classification."""
    text = prompt or ""
    global_config = _load_json(STATE_DIR / "ponytail-auto.json") if global_config is None else global_config
    project = _project_config(cwd)

    # The chosen mode wins over everything. Only AUTO delegates the decision, and
    # the plugin itself already injects a manual level, so the hook must stay silent
    # there instead of adding a competing instruction.
    chosen = selected_mode()
    if chosen != "auto":
        reason = ("the selected mode is off" if chosen == "off"
                  else "the selected mode is %s; the plugin injects it, the hook does not" % chosen)
        return {"mode": "off", "source": "mode", "reason": reason}

    if RE_OFF.search(text):
        _session_state(session_id, "off")
        return {"mode": "off", "source": "explicit", "reason": "turn-off phrase in the prompt"}

    explicit = RE_MODE.search(text)
    if explicit:
        mode = explicit.group(1).lower()
        _session_state(session_id, mode)
        return {"mode": mode, "source": "explicit", "reason": "requested in the prompt"}
    if RE_LAZY.search(text):
        _session_state(session_id, "full")
        return {"mode": "full", "source": "explicit", "reason": "lazy-mode phrase in the prompt"}

    session = _session_state(session_id)
    if session and session.get("mode") in LEVELS:
        reason = "turned off earlier this session" if session["mode"] == "off" else "kept from this session"
        return {"mode": session["mode"], "source": "session", "reason": reason}

    if project.get("auto") is False or str(project.get("mode", "")).lower() == "off":
        return {"mode": "off", "source": "project", "reason": "project configuration"}

    forced = str(project.get("mode", "")).lower()
    if forced in LEVELS:
        return {"mode": _cap(forced, str(global_config.get("max", "full"))), "source": "project", "reason": "project default"}

    if global_config.get("auto") is False:
        return {"mode": "off", "source": "config", "reason": "automatic activation is off"}

    mode, reason = classify(text)
    return {"mode": _cap(mode, str(global_config.get("max", "full"))), "source": "auto", "reason": reason}


def instruction(mode: str) -> str:
    """The exact text injected for a mode. OFF injects nothing at all."""
    if mode not in RULES:
        return ""
    body = RULES[mode]
    if mode == "lite":
        head = f"{PREFIX}: LITE (narrow fix). "
    elif mode == "full":
        head = f"{PREFIX}: FULL. "
    else:
        head = f"{PREFIX}: ULTRA (explicit request). "
    return f"{head}{body} Stop when the user says \"stop ponytail\" or \"normal mode\"."


def emit(raw: str, fmt: str = "hermes") -> str:
    """Hook entry: read the payload, print the context, or nothing."""
    try:
        payload = json.loads(raw or "{}")
    except ValueError:
        return ""
    if not isinstance(payload, dict):
        return ""
    prompt = payload.get("prompt") or payload.get("user_message") or ""
    if isinstance(prompt, list):  # Hermes passes multimodal content as parts
        prompt = " ".join(str(part.get("text", "")) if isinstance(part, dict) else str(part) for part in prompt)
    decision = resolve(str(prompt), session_id=payload.get("session_id"), cwd=Path.cwd())
    text = instruction(decision["mode"])
    if not text:
        return ""
    if fmt == "claude":
        return json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": text}})
    return json.dumps({"context": text})


def status() -> dict:
    state = _load_json(STATE)
    sessions = len(state.get("sessions") or {})
    chosen = selected_mode()
    config = _load_json(STATE_DIR / "ponytail-auto.json")
    would_inject = chosen == "auto" and config.get("auto") is not False
    return {
        # "auto" here is the hook's own switch; the operator's selected mode decides
        # whether that switch is reachable at all.
        "auto": "on" if would_inject else "off",
        "selected_mode": chosen,
        "would_inject": would_inject,
        "ceiling": str(config.get("max", "full")),
        "sessions": sessions,
        "state": str(STATE),
        "mode_state": str(MODE_STATE),
        "hermes_hook": _wired("hermes"),
        "claude_hook": _wired("claude"),
        "script": str(Path(__file__).resolve()),
    }


def _quote(path: str) -> str:
    return '"' + str(path).replace('"', '') + '"'


def _hook_command(python_exe: str, fmt: str) -> str:
    script = Path(__file__).resolve()
    return f"{_quote(python_exe)} {_quote(str(script))} hook --event pre_llm_call --format {fmt}"


def _hermes_config() -> Path | None:
    override = os.environ.get("PONYTAIL_HERMES_CONFIG")
    if override:
        candidate = Path(override)
        return candidate if candidate.parent.exists() else None
    exe = os.environ.get("HERMES_EXE") or shutil.which("hermes")
    if not exe:
        candidate = Path(os.environ.get("LOCALAPPDATA", "")) / "hermes" / "hermes-agent" / ".hermes" / "bin" / "hermes.exe"
        exe = str(candidate) if candidate.exists() else None
    if not exe:
        return None
    try:
        out = subprocess.run([exe, "config", "path"], capture_output=True, text=True, timeout=60)
        first = (out.stdout or "").strip().splitlines()
        if first:
            path = Path(first[0].strip())
            if path.parent.exists():
                return path
    except Exception:
        return None
    return None


def _wired(provider: str) -> str:
    if provider == "hermes":
        cfg = _hermes_config()
        if not cfg or not cfg.exists():
            return "unknown"
        return "on" if "ponytail_auto.py" in cfg.read_text(encoding="utf-8-sig", errors="ignore") else "off"
    settings = Path.home() / ".claude" / "settings.json"
    if not settings.exists():
        return "missing"
    data = _load_json(settings)
    return "on" if "ponytail_auto.py" in json.dumps(data) else "off"


def wire_hermes(enable: bool = True) -> list[str]:
    """Merge one pre_llm_call hook into Hermes's real config, preserving the file."""
    cfg = _hermes_config()
    if not cfg:
        return ["Hermes config not found (is `hermes` on PATH?)"]
    from ruamel.yaml import YAML

    command = _hook_command(sys.executable, "hermes")
    original = cfg.read_text(encoding="utf-8")
    yaml = YAML(typ="rt")
    yaml.preserve_quotes = True
    yaml.width = 4096
    document = yaml.load(original) or {}
    hooks = document.get("hooks")
    if hooks is None:
        hooks = {}
        document["hooks"] = hooks
    current = hooks.get("pre_llm_call") or []
    kept = [entry for entry in current if "ponytail_auto.py" not in str(entry.get("command", ""))]
    actions = []
    if enable:
        kept.append({"command": command, "timeout": 15})
    hooks["pre_llm_call"] = kept
    if not kept:
        del hooks["pre_llm_call"]

    from io import StringIO
    buffer = StringIO()
    yaml.dump(document, buffer)
    updated = buffer.getvalue()
    if updated == original:
        actions.append("Hermes hook already current")
    else:
        cfg.with_suffix(cfg.suffix + ".bak-ponytail-auto").write_text(original, encoding="utf-8")
        cfg.write_text(updated, encoding="utf-8")
        actions.append(("wired" if enable else "removed") + " Hermes pre_llm_call hook")
    if enable:
        _approve(cfg.parent, "pre_llm_call", command)
        actions.append("approved the hook in shell-hooks-allowlist.json")
    return actions


def _approve(folder: Path, event: str, command: str) -> None:
    path = folder / "shell-hooks-allowlist.json"
    data = _load_json(path) or {"approvals": []}
    approvals = [a for a in data.get("approvals", [])
                 if not (isinstance(a, dict) and a.get("event") == event and a.get("command") == command)]
    approvals.append({
        "event": event,
        "command": command,
        "approved_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "script_mtime_at_approval": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(Path(__file__).stat().st_mtime)),
    })
    data["approvals"] = approvals
    if path.exists():
        path.with_suffix(path.suffix + ".bak-ponytail-auto").write_text(json.dumps(_load_json(path), indent=2), encoding="utf-8")
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def wire_claude(enable: bool = True) -> list[str]:
    """Merge a UserPromptSubmit hook into ~/.claude/settings.json."""
    settings = Path.home() / ".claude" / "settings.json"
    if not settings.exists():
        return ["Claude settings not found"]
    data = _load_json(settings)
    hooks = data.get("hooks") if isinstance(data.get("hooks"), dict) else {}
    groups = [g for g in (hooks.get("UserPromptSubmit") or [])
              if not any("ponytail_auto.py" in str(h.get("command", "")) for h in (g.get("hooks") or []))]
    if enable:
        groups.append({"hooks": [{"type": "command", "command": _hook_command(sys.executable, "claude"), "timeout": 15}]})
    if groups:
        hooks["UserPromptSubmit"] = groups
    else:
        hooks.pop("UserPromptSubmit", None)
    data["hooks"] = hooks
    settings.with_suffix(".json.bak-ponytail-auto").write_text(json.dumps(_load_json(settings), indent=2), encoding="utf-8")
    settings.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return [("wired" if enable else "removed") + " Claude UserPromptSubmit hook"]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Ponytail automatic mode (deterministic, off by default)")
    sub = parser.add_subparsers(dest="command")

    hook = sub.add_parser("hook", help="hook entry: JSON on stdin, context on stdout")
    hook.add_argument("--event", default="pre_llm_call")
    hook.add_argument("--format", default="hermes", choices=("hermes", "claude"))

    explain = sub.add_parser("explain", help="show the decision for a prompt")
    explain.add_argument("prompt", nargs="+")
    explain.add_argument("--json", action="store_true")

    wire = sub.add_parser("wire", help="install the hook where the provider supports it")
    wire.add_argument("provider", choices=("hermes", "claude", "all"))
    wire.add_argument("--remove", action="store_true")

    sub.add_parser("status", help="current configuration")
    sub.add_parser("self-check", help="run the built-in decision corpus")
    sub.add_parser("selftest", help="alias of self-check (installer gate convention)")

    args = parser.parse_args(argv)
    if args.command in (None, "hook"):
        raw = sys.stdin.read() if not sys.stdin.isatty() else ""
        out = emit(raw, fmt=getattr(args, "format", "hermes"))
        if out:
            sys.stdout.write(out + "\n")
        return 0
    if args.command == "wire":
        targets = ("hermes", "claude") if args.provider == "all" else (args.provider,)
        for target in targets:
            for line in (wire_hermes if target == "hermes" else wire_claude)(enable=not args.remove):
                print(f"{target}: {line}")
        return 0
    if args.command == "explain":
        decision = resolve(" ".join(args.prompt))
        if args.json:
            print(json.dumps(decision, indent=1))
        else:
            print(f"{decision['mode']} ({decision['source']}: {decision['reason']})")
        return 0
    if args.command == "status":
        print(json.dumps(status(), indent=1))
        return 0
    if args.command in ("self-check", "selftest"):
        return _self_check()
    parser.print_help()
    return 2


def _self_check() -> int:
    """A tiny corpus so a hook install can prove itself without the test suite."""
    cases = [
        ("write me a short story about a lighthouse", "off"),
        ("refactor the whole app into services", "full"),
        ("fix the typo in README.md line 12", "lite"),
        ("why is the sky blue?", "off"),
        ("/ponytail ultra", "ultra"),
        ("stop ponytail", "off"),
    ]
    bad = 0
    for prompt, want in cases:
        got, reason = classify(prompt)
        if prompt.startswith(("/ponytail", "stop")):
            got = resolve(prompt)["mode"]
        if got != want:
            print(f"FAIL {want}!={got}: {prompt} ({reason})")
            bad += 1
    print("PONYTAIL AUTO SELF-CHECK: " + ("PASS" if not bad else f"FAIL ({bad})"))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
