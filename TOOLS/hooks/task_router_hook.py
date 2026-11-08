"""Prompt-time workflow selection: one line naming the pipeline, injected without a model call.

Phase 2 shipped `task_route.py` as a CLI, which meant nobody used it. This hook is the
provider-facing half: Claude's `UserPromptSubmit` and Hermes' `pre_llm_call` both pass the
prompt to a command and inject its stdout as context, so the routing decision reaches the
model before it starts work.

It stays quiet on ordinary small work and speaks only when the choice actually changes
something - a lifecycle, an autonomous run, a requirements pass, or a specialist such as
security or game-modding. One line, no methodology prose, no second router.

    python task_router_hook.py hook --format claude   # JSON payload on stdin
    python task_router_hook.py wire all
    python task_router_hook.py self-check
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent))

import task_route as tr  # noqa: E402

HIGH_VALUE = {"security-and-hardening", "capability-routing", "impeccable", "release-checklist",
              "visual-verification", "observability-and-instrumentation"}


def _prompt(payload):
    text = payload.get("prompt") or payload.get("user_message") or ""
    if isinstance(text, list):  # Hermes sends multimodal parts
        text = " ".join(str(p.get("text", "")) if isinstance(p, dict) else str(p) for p in text)
    return str(text)


def line_for(prompt, provider=None):
    """The injection, or '' when the default lightweight path needs no announcement."""
    if not prompt.strip():
        return ""
    result = tr.route(prompt, provider=provider)
    speaks = result["primary"] != "lightweight" or bool(HIGH_VALUE & set(result["specialists"]))
    if not speaks:
        return ""
    parts = ["Routing: %s" % result["primary"]]
    usable = [x["use"] or x["want"] for x in result["resolved"] if x["use"]]
    if usable:
        parts.append("specialists: %s" % ", ".join(usable[:3]))
    if result["checkpoints"] != "none":
        parts.append("checkpoints: %s" % result["checkpoints"])
    return ("; ".join(parts) + ". One workflow; do not start a second methodology.")[:240]


def emit(raw, fmt="hermes"):
    try:
        payload = json.loads(raw or "{}")
    except ValueError:
        return ""
    if not isinstance(payload, dict):
        return ""
    text = line_for(_prompt(payload), provider="claude" if fmt == "claude" else "hermes")
    if not text:
        return ""
    if fmt == "claude":
        return json.dumps({"hookSpecificOutput": {"hookEventName": "UserPromptSubmit",
                                                   "additionalContext": text}})
    return json.dumps({"context": text})


def _python():
    return sys.executable


def _quote(value):
    return '"' + str(value).replace('"', "") + '"'


def _hook_command(fmt):
    return "%s %s hook --format %s" % (_quote(_python()), _quote(Path(__file__).resolve()), fmt)


def _claude_settings():
    import os
    base = Path(os.environ.get("CLAUDE_CONFIG_DIR") or (Path.home() / ".claude"))
    return base / "settings.json"


def _hermes_config():
    try:
        out = subprocess.run(["hermes", "config", "path"], capture_output=True, text=True, timeout=20)
        candidate = Path(out.stdout.strip())
        if candidate.is_file():
            return candidate
    except Exception:
        pass
    import os
    local = Path(os.environ.get("LOCALAPPDATA", Path.home() / "AppData" / "Local"))
    fallback = local / "hermes" / "config.yaml"
    return fallback if fallback.is_file() else None


def wire_claude(enable=True):
    path = _claude_settings()
    data = {}
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            return ["Claude settings.json is not valid JSON; left untouched"]
    hooks = data.setdefault("hooks", {})
    groups = [g for g in (hooks.get("UserPromptSubmit") or [])
              if "task_router_hook.py" not in json.dumps(g)]
    if enable:
        groups.append({"hooks": [{"type": "command", "command": _hook_command("claude"), "timeout": 10}]})
    if groups:
        hooks["UserPromptSubmit"] = groups
    else:
        hooks.pop("UserPromptSubmit", None)
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_file():
        path.with_suffix(".json.bak-task-router").write_text(
            path.read_text(encoding="utf-8"), encoding="utf-8")
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return [("wired" if enable else "removed") + " Claude UserPromptSubmit hook"]


def wire_hermes(enable=True):
    cfg = _hermes_config()
    if not cfg:
        return ["Hermes config not found; hook not wired"]
    try:
        from ruamel.yaml import YAML
        from io import StringIO
    except ImportError:
        return ["ruamel.yaml unavailable; Hermes hook not wired"]
    original = cfg.read_text(encoding="utf-8")
    yaml = YAML(typ="rt")
    yaml.preserve_quotes = True
    yaml.width = 4096
    document = yaml.load(original) or {}
    hooks = document.setdefault("hooks", {})
    current = [e for e in (hooks.get("pre_llm_call") or [])
               if "task_router_hook.py" not in str(e.get("command", ""))]
    if enable:
        current.append({"command": _hook_command("hermes"), "timeout": 10})
    if current:
        hooks["pre_llm_call"] = current
    else:
        hooks.pop("pre_llm_call", None)
    buffer = StringIO()
    yaml.dump(document, buffer)
    updated = buffer.getvalue()
    if updated != original:
        cfg.with_suffix(cfg.suffix + ".bak-task-router").write_text(original, encoding="utf-8")
        cfg.write_text(updated, encoding="utf-8")
        return [("wired" if enable else "removed") + " Hermes pre_llm_call hook"]
    return ["Hermes hook already current"]


def self_check():
    """Prove both directions with real payloads, not by inspecting code."""
    quiet = line_for("fix the typo in notes.txt")
    loud = line_for("add oauth login with tests before merge")
    oauth_quiet = line_for("reduce AI token usage in the prompts")
    ok = quiet == "" and "lifecycle" in loud and oauth_quiet == ""
    print("PASS" if ok else "FAIL: %r / %r / %r" % (quiet, loud, oauth_quiet))
    return 0 if ok else 1


def main(argv=None):
    ap = argparse.ArgumentParser(description="Inject the chosen workflow at prompt time")
    ap.add_argument("command", choices=("hook", "wire", "status", "self-check"))
    ap.add_argument("target", nargs="?", default="all", choices=("all", "claude", "hermes"))
    ap.add_argument("--format", default="hermes", choices=("hermes", "claude"))
    args = ap.parse_args(argv)

    if args.command == "hook":
        sys.stdout.write(emit(sys.stdin.read(), args.format))
        return 0
    if args.command == "self-check":
        return self_check()
    if args.command == "wire":
        actions = []
        if args.target in ("all", "claude"):
            actions += wire_claude()
        if args.target in ("all", "hermes"):
            actions += wire_hermes()
        for action in actions:
            print(action)
        return 0
    print(json.dumps({"claude": str(_claude_settings()), "hermes": str(_hermes_config()),
                      "script": str(Path(__file__).resolve())}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
