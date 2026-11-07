"""Read a project's PLAN.md and STATE.md and answer "what next" without a model.

Deterministic only: parses the task table, computes the dependency-ready next
task, finds cycles and duplicate IDs, compares the recorded SHA with the real
repository, and flags tasks claimed complete whose verification is not recorded.

Verification convention in the `Verify` column:
  `file:<path>` or a bare path -> the controller checks the file exists
  `cmd:<command>`              -> never executed; the task counts as unverified
                                  until `Evidence` records the result
An empty value, `-`, or a command with no recorded pass means unverified.

    python TOOLS/task_state.py next      [--root DIR]
    python TOOLS/task_state.py status    [--root DIR]
    python TOOLS/task_state.py resume    [--root DIR] [--fix]
    python TOOLS/task_state.py handoff   [--root DIR]

Exit codes: 0 ok, 1 the project needs repair (cycle, invalid dependency,
contradictory or unverified state), 2 no PLAN.md.
"""

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

STATUSES = {"pending", "active", "complete", "failed", "blocked", "superseded"}
# Only a completed task satisfies a dependency. A superseded task is retired, not
# done: its dependents must be repointed at whatever replaced it.
SATISFIES = {"complete"}
# Evidence is a record, not prose. `cmd:<command> @ <sha> exit=<n>` is the only
# form this tool can re-check. `verified@<sha>` only reports a claim.
RECORD = re.compile(r"(?i)^cmd:(?P<cmd>.+?)\s+@\s*(?P<sha>[0-9a-f]{7,40})\s+exit=(?P<code>\d+)$")
REPORTED = re.compile(r"(?i)^verified@(?P<sha>[0-9a-f]{7,40})$")
FAIL_WORDS = re.compile(r"(?i)(^|\W)(fail|failed|failure|not verified|unverified|broken)($|\W)")


class Task:
    __slots__ = ("tid", "text", "status", "deps", "verify", "evidence")

    def __init__(self, tid, text, status, deps, verify, evidence):
        self.tid, self.text, self.status = tid, text, status
        self.deps, self.verify, self.evidence = deps, verify, evidence


def split_row(line):
    return [c.strip().strip("`") for c in line.strip().strip("|").split("|")]


def parse_plan(path):
    """Return (goal, tasks, errors). Any markdown table with ID+Status columns counts."""
    text = path.read_text(encoding="utf-8-sig")
    m = re.search(r"(?mi)^goal:\s*(.+)$", text)
    goal = m.group(1).strip() if m else ""
    errors, tasks = [], []
    rows = text.splitlines()
    i = 0
    while i < len(rows):
        line = rows[i]
        if line.strip().startswith("|") and i + 1 < len(rows) and re.match(r"^\s*\|[\s:|-]+\|\s*$", rows[i + 1]):
            header = [c.lower() for c in split_row(line)]
            if "id" in header and "status" in header:
                col = {name: header.index(name) for name in header}
                j = i + 2
                while j < len(rows) and rows[j].strip().startswith("|"):
                    cells = split_row(rows[j])
                    get = lambda n: cells[col[n]] if n in col and col[n] < len(cells) else ""
                    tid, status = get("id"), (get("status") or "pending").lower()
                    deps = [d.strip() for d in re.split(r"[,;]", get("depends on"))
                            if d.strip() not in ("", "-", "\u2013")]
                    if not tid:
                        errors.append("row %d has no task ID" % (j + 1))
                    else:
                        tasks.append(Task(tid, get("task"), status, deps, get("verify"), get("evidence")))
                        if status not in STATUSES:
                            errors.append("%s: unknown status %r" % (tid, status))
                    j += 1
                i = j
                continue
        i += 1
    ids = [t.tid for t in tasks]
    for dup in sorted({x for x in ids if ids.count(x) > 1}):
        errors.append("duplicate task ID %s" % dup)
    known = set(ids)
    for t in tasks:
        for dep in t.deps:
            if dep not in known:
                errors.append("%s depends on unknown task %s" % (t.tid, dep))
    return goal, tasks, errors


def find_cycle(tasks):
    graph = {t.tid: [d for d in t.deps if d in {x.tid for x in tasks}] for t in tasks}
    state, stack = {}, []

    def visit(node):
        if state.get(node) == 1:
            return stack[stack.index(node):] + [node]
        if state.get(node) == 2:
            return None
        state[node] = 1
        stack.append(node)
        for nxt in graph.get(node, []):
            hit = visit(nxt)
            if hit:
                return hit
        stack.pop()
        state[node] = 2
        return None

    for node in graph:
        hit = visit(node)
        if hit:
            return hit
    return None


def plan_problems(tasks, errors):
    """One validation path: every command reports the same structural verdict."""
    problems = []
    cycle = find_cycle(tasks)
    if cycle:
        problems.append("dependency cycle: %s" % " -> ".join(cycle))
    problems.extend(errors)
    return problems


def parse_state(path):
    fields = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            m = re.match(r"^([A-Z][A-Z ]+):\s*(.*)$", line.strip())
            if m:
                fields[m.group(1).strip()] = m.group(2).strip()
    return fields


def git_sha(root):
    try:
        out = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                             capture_output=True, text=True, timeout=10)
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def verify_of(task):
    """(kind, value): file, cmd, ambiguous or none. Never a shell call.

    A bare value is a path only when it cannot be a command; anything with a
    space or a shell character must be declared, so nothing is guessed.
    """
    raw = (task.verify or "").strip()
    if raw in ("", "-", "–"):
        return "none", ""
    low = raw.lower()
    if low.startswith("cmd:"):
        return "cmd", raw[4:].strip()
    if low.startswith("file:"):
        return "file", raw[5:].strip()
    if re.search(r"[\s|&;<>$`\"']", raw):
        return "ambiguous", raw
    return "file", raw


def evidence_state(task, root, head):
    """(verified, note). True only for a check this tool can repeat itself."""
    if task.status != "complete":
        return True, ""
    kind, value = verify_of(task)
    cell = (task.evidence or "").strip()
    if kind == "none":
        return False, "no verification recorded"
    if kind == "ambiguous":
        return False, "Verify is ambiguous (%s) - use file:<path> or cmd:<command>" % value
    if FAIL_WORDS.search(cell):
        return False, "evidence records a failure (%s)" % cell[:60]
    if kind == "file":
        if not (root / value).exists():
            return False, "artifact missing (%s)" % value
        return True, "artifact exists; contents not checked"
    record = RECORD.match(cell)
    if record:
        if record.group("cmd").strip() != value.strip():
            return False, "evidence names a different command (%s)" % record.group("cmd").strip()[:50]
        if int(record.group("code")) != 0:
            return False, "recorded exit=%s" % record.group("code")
        sha = record.group("sha")
        if head and not head.startswith(sha):
            return False, "stale evidence @%s (HEAD is %s)" % (sha[:12], head[:12])
        return True, "command exit=0 @%s" % sha[:12]
    if cell in ("", "-", "–"):
        return False, "no verification recorded"
    reported = REPORTED.match(cell)
    if reported:
        return False, "reported only (verified@%s) - rerun and record cmd:%s @ <sha> exit=0" % (
            reported.group("sha")[:12], value[:40])
    return False, "evidence is not a record (%s) - expected cmd:<command> @ <sha> exit=0" % (cell[:50] or "empty")


def actionable(tasks):
    done = {t.tid for t in tasks if t.status in SATISFIES}
    ready = [t for t in tasks if t.status in ("pending", "active")
             and all(d in done for d in t.deps)]
    ready.sort(key=lambda t: t.status != "active")  # an active task wins over a pending one
    blocked = [t for t in tasks if t.status in ("pending", "active")
               and any(d not in done for d in t.deps)]
    return ready, blocked


def superseded_deps(tasks):
    sup = {t.tid for t in tasks if t.status == "superseded"}
    return ["%s depends on superseded %s - repoint it or complete the replacement"
            % (t.tid, d) for t in tasks if t.status in ("pending", "active")
            for d in t.deps if d in sup]


def report(root, tasks, problems, state=None, sha=None):
    """Shared verdict: the exit code every command must agree on."""
    unverified = []
    for t in tasks:
        ok, note = evidence_state(t, root, sha or "")
        if not ok:
            unverified.append((t.tid, note))
    for tid, why in unverified:
        print("problem: %s complete but unverified - %s" % (tid, why))
    problems = problems + superseded_deps(tasks)
    for problem in problems:
        print("problem: %s" % problem)
    stale = bool(sha) and bool(state and state.get("SHA")) and not sha.startswith(state["SHA"][:7])
    if stale:
        print("problem: STATE.md SHA %s is behind %s" % (state["SHA"][:7], sha[:7]))
    return 1 if (problems or unverified or stale) else 0


def load(root):
    plan = root / "PLAN.md"
    if not plan.exists():
        print("no PLAN.md in %s" % root)
        return None
    return parse_plan(plan)


def cmd_status(root):
    loaded = load(root)
    if not loaded:
        return 2
    goal, tasks, errors = loaded
    problems = plan_problems(tasks, errors)
    state = parse_state(root / "STATE.md")
    counts = {}
    for t in tasks:
        counts[t.status] = counts.get(t.status, 0) + 1
    print("goal: %s" % (goal or "(none recorded)"))
    print("tasks: %d  %s" % (len(tasks), "  ".join("%s=%d" % kv for kv in sorted(counts.items()))))
    ready, blocked = actionable(tasks)
    print("next: %s" % (ready[0].tid + " " + ready[0].text if ready else "(nothing actionable)"))
    print("blocked: %s" % (", ".join(t.tid for t in blocked) or "none"))
    if state.get("CURRENT TASK"):
        print("state current task: %s" % state["CURRENT TASK"])
    if state.get("NEXT ACTION"):
        print("state next action: %s" % state["NEXT ACTION"])
    return report(root, tasks, problems, state, git_sha(root))


def cmd_next(root):
    loaded = load(root)
    if not loaded:
        return 2
    _goal, tasks, errors = loaded
    problems = plan_problems(tasks, errors)
    ready, blocked = actionable(tasks)
    if ready:
        task = ready[0]
        kind, value = verify_of(task)
        print("%s  %s" % (task.tid, task.text))
        print("  status: %s" % task.status)
        print("  verify: %s%s" % (value or "(none recorded)",
                                  " [file]" if kind == "file" else " [run it]" if kind == "cmd" else ""))
        print("  evidence: %s" % (task.evidence or "(none recorded)"))
        if blocked:
            print("  waiting behind: %s" % ", ".join(t.tid for t in blocked))
    else:
        print("nothing actionable; %d blocked or unfinished" % len(blocked))
    return report(root, tasks, problems, parse_state(root / "STATE.md"), git_sha(root))


def desired_state(text, task, sha):
    """Return (new_text, changed_keys, missing_keys). Never touches unrelated lines."""
    changed, missing, updates = [], [], {}
    if task:
        updates["CURRENT TASK"] = task.tid
        updates["NEXT ACTION"] = (task.verify or task.text or "").strip() or "-"
    if sha:
        updates["SHA"] = sha[:12]
    for key, value in updates.items():
        pattern = re.compile(r"(?m)^%s:.*$" % re.escape(key))
        if pattern.search(text):
            new = pattern.sub("%s: %s" % (key, value), text, count=1)
            if new != text:
                changed.append(key)
            text = new
        else:
            text = text.rstrip("\r\n") + "\r\n%s: %s\r\n" % (key, value)
            changed.append(key)
            missing.append(key)
    return text, changed, missing


def cmd_resume(root, fix=False):
    """Reconcile STATE.md with the plan and the repository; --fix writes only real changes."""
    loaded = load(root)
    if not loaded:
        return 2
    _goal, tasks, errors = loaded
    structural = plan_problems(tasks, errors)
    problems = list(structural)
    state_path = root / "STATE.md"
    state = parse_state(state_path)
    sha = git_sha(root)
    ready, _blocked = actionable(tasks)
    next_task = ready[0] if ready else None

    if state.get("CURRENT TASK") and state["CURRENT TASK"] not in {t.tid for t in tasks}:
        problems.append("STATE.md names a task that is not in PLAN.md: %s" % state["CURRENT TASK"])
    elif next_task and state.get("CURRENT TASK") and state["CURRENT TASK"] != next_task.tid:
        problems.append("STATE.md current task %s, plan says %s" % (state["CURRENT TASK"], next_task.tid))

    if fix and structural:
        print("plan is invalid; STATE.md left untouched until it is repaired")
    elif fix:
        if not state_path.exists():
            print("no STATE.md to repair in %s" % root)
        else:
            original = state_path.read_text(encoding="utf-8-sig")
            updated, changed, missing = desired_state(original, next_task, sha)
            if updated != original:
                tmp = state_path.with_suffix(".md.tmp")
                tmp.write_bytes(updated.encode("utf-8"))
                os.replace(tmp, state_path)
                print("STATE.md updated: %s" % ", ".join(changed))
                if missing:
                    print("STATE.md was missing: %s (added)" % ", ".join(missing))
            else:
                print("STATE.md already correct; nothing written")

    code = report(root, tasks, problems, state, sha)
    if next_task:
        print("resume at: %s %s" % (next_task.tid, next_task.text))
        print("verify with: %s" % (next_task.verify or "(none recorded)"))
    return code


def cmd_handoff(root):
    loaded = load(root)
    if not loaded:
        return 2
    goal, tasks, errors = loaded
    problems = plan_problems(tasks, errors)
    state = parse_state(root / "STATE.md")
    sha = git_sha(root)
    ready, blocked = actionable(tasks)
    task = ready[0] if ready else None
    print("## Handoff")
    print()
    print("Goal: %s" % (state.get("GOAL") or goal or "(not recorded)"))
    print("Repo: %s" % (sha[:12] if sha else "(not a git repository)"))
    if task:
        print("Next task: %s - %s" % (task.tid, task.text))
        print("Verify: %s" % (task.verify or "(none recorded)"))
    else:
        print("Next task: none actionable")
    if blocked:
        print("Blocked: %s" % ", ".join("%s (needs %s)" % (t.tid, ",".join(t.deps)) for t in blocked))
    for key in ("BLOCKERS", "LAST VERIFIED"):
        if state.get(key):
            print("%s: %s" % (key.title(), state[key]))
    return report(root, tasks, problems, state, sha)


def main(argv=None):
    ap = argparse.ArgumentParser(description="read PLAN.md and STATE.md without a model")
    ap.add_argument("command", choices=["next", "status", "resume", "handoff"])
    ap.add_argument("--root", default=".", help="project root (default: current directory)")
    ap.add_argument("--fix", action="store_true", help="resume: write STATE.md fields when they differ")
    args = ap.parse_args(argv)
    root = Path(args.root).resolve()
    if args.command == "resume":
        return cmd_resume(root, fix=args.fix)
    return {"next": cmd_next, "status": cmd_status, "handoff": cmd_handoff}[args.command](root)


if __name__ == "__main__":
    sys.exit(main())
