#!/usr/bin/env python3
"""Where your AI usage goes, measured from the session logs already on this PC.

Reads (read-only) the local logs of Codex (~/.codex/sessions), Claude Code
(~/.claude/projects), Hermes (state.db, profiles) and Grok (~/.grok/sessions).
Prints aggregates only: sessions, tool calls, failed commands, token totals,
the share spent on Codex approval reviews and forked subagents, how often a
session had to be resumed after a usage limit, the costliest workspaces, and
phrases you retype across sessions (candidates for your PROFILE.md).

Nothing leaves the machine and nothing is written unless you pass --json.
Token figures are what each app recorded; "weight" is a rough relative cost
(uncached input + 0.1 x cached input + 5 x output), not a bill.
"""
from __future__ import annotations

import argparse
import collections
import glob
import json
import os
import re
import sqlite3
import sys
from pathlib import Path

HOME = Path.home()
LOCAL = Path(os.environ.get("LOCALAPPDATA", HOME / "AppData" / "Local"))
REVIEW = ("The following is the Codex agent history", "The Codex agent has requested")
RESUME = re.compile(r"(?i)\b(hit|reached|ran out of) (my |the |a )?(usage|weekly|daily)? ?limit|usage (limit )?(has )?reset|out of usage")
SKIP = ("<environment_context", "# AGENTS.md", "<user_instructions", "<command-", "<local-command",
        "<system-reminder", "Caveat:", "This session is being continued", "[IMPORTANT:", "<task-notification",
        "<user_info>", "[SYSTEM", "[Request interrupted", "<")
EXIT = re.compile(r'(?:Exit code:|"exit_code":)\s*(-?\d+)')


class Session(dict):
    def __init__(self, provider: str, sid: str):
        super().__init__(provider=provider, session=sid, cwd="", model="", start="", user=[], tools=0,
                         fails=0, inp=0, cache=0, out=0)

    def weight(self) -> float:
        uncached = max(self["inp"] - self["cache"], 0) if self["provider"] == "codex" else self["inp"]
        return uncached + 0.1 * self["cache"] + 5 * self["out"]


def lines(path: str):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            for line in fh:
                try:
                    yield json.loads(line)
                except ValueError:
                    continue
    except OSError:
        return


def add_user(s: Session, text) -> None:
    text = (text or "").strip() if isinstance(text, str) else ""
    if text and not text.startswith(SKIP):
        s["user"].append(text)


def codex() -> list[Session]:
    out = []
    files = glob.glob(str(HOME / ".codex" / "sessions" / "**" / "*.jsonl"), recursive=True)
    files += glob.glob(str(HOME / ".codex" / "archived_sessions" / "**" / "*.jsonl"), recursive=True)
    for f in files:
        s = Session("codex", Path(f).stem[-36:])
        usage = None
        for d in lines(f):
            t, p = d.get("type"), d.get("payload") or {}
            pt = p.get("type")
            s["start"] = s["start"] or d.get("timestamp", "")
            if t in ("session_meta", "turn_context"):
                s["cwd"] = p.get("cwd") or s["cwd"]
                s["model"] = p.get("model") or s["model"]
            elif t == "event_msg" and pt == "user_message":
                add_user(s, p.get("message"))
            elif t == "response_item" and pt == "message" and p.get("role") == "user":
                add_user(s, "\n".join(c.get("text", "") for c in p.get("content") or [] if c.get("type") == "input_text"))
            elif t == "event_msg" and pt == "token_count":
                usage = (p.get("info") or {}).get("total_token_usage") or usage
            elif t == "response_item" and pt in ("function_call", "custom_tool_call", "local_shell_call"):
                s["tools"] += 1
            elif t == "response_item" and pt in ("function_call_output", "custom_tool_call_output"):
                o = p.get("output")
                m = EXIT.search((o if isinstance(o, str) else json.dumps(o))[:4000])
                if m and m.group(1) != "0":
                    s["fails"] += 1
        if usage:
            s["inp"], s["cache"] = usage.get("input_tokens", 0), usage.get("cached_input_tokens", 0)
            # Codex reports reasoning as a detail within output_tokens, not an
            # additional charge. See TokenUsage::blended_total in its protocol.
            s["out"] = usage.get("output_tokens", 0)
        s["user"] = list(dict.fromkeys(s["user"]))
        out.append(s)
    return out


def claude() -> list[Session]:
    out = []
    for f in glob.glob(str(HOME / ".claude" / "projects" / "**" / "*.jsonl"), recursive=True):
        sub = os.sep + "subagents" + os.sep in f
        s = Session("claude-subagent" if sub else "claude", Path(f).stem)
        for d in lines(f):
            s["cwd"] = d.get("cwd") or s["cwd"]
            s["start"] = s["start"] or d.get("timestamp", "")
            m = d.get("message") or {}
            if d.get("type") == "user" and not d.get("isMeta") and not sub:
                c = m.get("content")
                if isinstance(c, str):
                    add_user(s, c)
                for part in c if isinstance(c, list) else []:
                    if part.get("type") == "text":
                        add_user(s, part.get("text"))
                    elif part.get("type") == "tool_result" and part.get("is_error"):
                        s["fails"] += 1
            elif d.get("type") == "assistant":
                s["model"] = m.get("model") or s["model"]
                u = m.get("usage") or {}
                s["inp"] += u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0)
                s["cache"] += u.get("cache_read_input_tokens", 0)
                s["out"] += u.get("output_tokens", 0)
                s["tools"] += sum(1 for part in m.get("content") or [] if isinstance(part, dict) and part.get("type") == "tool_use")
        out.append(s)
    return out


def hermes() -> list[Session]:
    out = []
    home = Path(os.environ.get("HERMES_HOME") or LOCAL / "hermes")
    for db in [home / "state.db", *sorted(home.glob("profiles/*/state.db"))]:
        if not db.is_file():
            continue
        prof = db.parent.name if db.parent.parent.name == "profiles" else "default"
        try:
            con = sqlite3.connect(f"file:{db.as_posix()}?mode=ro", uri=True)
            sessions = {}
            for r in con.execute("select id, source, model, started_at, tool_call_count, input_tokens, "
                                 "output_tokens, cache_read_tokens from sessions"):
                s = Session("hermes:" + prof, r[0])
                s.update(cwd=r[1] or "", model=r[2] or "", start=str(r[3] or ""), tools=r[4] or 0,
                         inp=r[5] or 0, out=r[6] or 0, cache=r[7] or 0)
                sessions[r[0]] = s
            for sid, text in con.execute("select session_id, content from messages where role='user'"):
                if sid in sessions:
                    add_user(sessions[sid], text)
            out += sessions.values()
        except sqlite3.Error as exc:
            print(f"  (Hermes {db} skipped: {exc})", file=sys.stderr)
    return out


def grok() -> list[Session]:
    out = []
    uq = re.compile(r"<user_query>(.*?)</user_query>", re.S)
    for f in glob.glob(str(HOME / ".grok" / "sessions" / "*" / "*" / "chat_history.jsonl")):
        s = Session("grok", Path(f).parent.name)
        for d in lines(f):
            if d.get("type") == "user":
                c = d.get("content")
                for part in c if isinstance(c, list) else [{"type": "text", "text": c}]:
                    if isinstance(part, dict) and part.get("type") == "text":
                        for q in uq.findall(part.get("text") or ""):
                            add_user(s, q)
            elif d.get("type") == "assistant":
                s["tools"] += len(d.get("tool_calls") or [])
        out.append(s)
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--top", type=int, default=8, help="rows in each ranking")
    ap.add_argument("--json", type=Path, help="also write the aggregates to this file")
    a = ap.parse_args()
    sessions = codex() + claude() + hermes() + grok()
    if not sessions:
        print("No local AI session logs found.")
        return 0
    reviews = {s["session"] for s in sessions if s["provider"] == "codex" and any(u.startswith(REVIEW) for u in s["user"])}
    total = sum(s.weight() for s in sessions) or 1
    print("Usage by app (weight = uncached input + 0.1 x cached + 5 x output; relative, not a bill)")
    by = collections.defaultdict(lambda: collections.Counter())
    for s in sessions:
        b = by[s["provider"]]
        b["sessions"] += 1; b["tools"] += s["tools"]; b["fails"] += s["fails"]
        b["inp"] += s["inp"]; b["cache"] += s["cache"]; b["out"] += s["out"]; b["w"] += s.weight()
    for p, b in sorted(by.items(), key=lambda kv: -kv[1]["w"]):
        print(f"  {p:18s} sessions {b['sessions']:5d}  tool calls {b['tools']:7d}  failed cmds {b['fails']:5d}  "
              f"input {b['inp']/1e6:8.1f}M (cached {b['cache']/1e6:8.1f}M)  output {b['out']/1e6:6.1f}M  weight {100*b['w']/total:5.1f}%")

    cx = [s for s in sessions if s["provider"] == "codex"]
    if cx:
        cxw = sum(s.weight() for s in cx) or 1
        rv = sum(s.weight() for s in cx if s["session"] in reviews)
        firsts = collections.defaultdict(list)
        for s in cx:
            if s["session"] not in reviews and s["user"]:
                firsts[s["user"][0][:400]].append(s)
        forks = [s for group in firsts.values() if len(group) > 1 for s in sorted(group, key=lambda x: x["start"])[1:]]
        print("\nCodex overhead")
        print(f"  approval reviews: {len(reviews)} sessions, {100*rv/cxw:.1f}% of Codex weight "
              "(fewer escalations = fewer reviews: keep work inside writable roots, batch commands)")
        print(f"  forked subagents: {len(forks)} sessions, {100*sum(s.weight() for s in forks)/cxw:.1f}% "
              "(each re-reads the parent history; prefer narrow briefs)")
        calls = [(s["inp"] / s["tools"]) for s in cx if s["tools"] >= 20 and s["session"] not in reviews]
        if calls:
            calls.sort()
            print(f"  context per tool call in working sessions: median {calls[len(calls)//2]/1e3:.0f}k tokens")

    resumes = sum(1 for s in sessions for u in s["user"][:3] if RESUME.search(u[:300]))
    print(f"\nSessions resumed after a usage limit: {resumes}  (cheap resumes need a current STATE.md)")

    work = collections.Counter()
    for s in sessions:
        if s["session"] in reviews:
            continue
        cwd = (s["cwd"] or "(unknown)").replace("/", "\\")
        work["\\".join(cwd.split("\\")[:4])] += s.weight()
    print("\nCostliest workspaces")
    for cwd, w in work.most_common(a.top):
        print(f"  {100*w/total:5.1f}%  {cwd}")

    grams = collections.defaultdict(set)
    for s in sessions:
        if s["session"] in reviews:
            continue
        for u in s["user"]:
            if RESUME.search(u[:300]):
                continue
            words = re.findall(r"[a-z0-9']+", u[:3000].lower())
            for i in range(len(words) - 6):
                grams[" ".join(words[i:i + 7])].add(s["session"])
    repeated = [(len(v), g) for g, v in grams.items() if len(v) >= 5]
    repeated.sort(reverse=True)
    shown, out_rows = set(), []
    for n, g in repeated:
        if any(g[:20] in x or x[:20] in g for x in shown):
            continue
        shown.add(g); out_rows.append((n, g))
        if len(out_rows) >= a.top:
            break
    if out_rows:
        print("\nPhrases you retype across sessions (put the lasting ones in PROFILE.md once)")
        for n, g in out_rows:
            print(f"  {n:4d} sessions  \"{g} ...\"")
    if a.json:
        a.json.write_text(json.dumps({"by_app": {k: dict(v) for k, v in by.items()}, "codex_reviews": len(reviews),
                                      "resumes": resumes, "workspaces": work.most_common(a.top)}, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
