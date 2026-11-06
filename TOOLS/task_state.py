"""Read a project's PLAN.md and STATE.md and answer "what next" without a model.

Deterministic only: parses the task table, computes the dependency-ready next
task, finds cycles and duplicate IDs, compares the recorded SHA with the real
repository, and flags tasks claimed complete whose evidence is missing.

    python TOOLS/task_state.py next      [--root DIR]
    python TOOLS/task_state.py status    [--root DIR]
    python TOOLS/task_state.py resume    [--root DIR] [--fix]
    python TOOLS/task_state.py handoff   [--root DIR]

Exit codes: 0 ok, 1 the project needs attention (cycle, contradictory state),
2 no PLAN.md.
"""

import argparse
import re
import subprocess
import sys
from pathlib import Path

STATUSES = {"pending", "active", "complete", "failed", "blocked", "superseded"}
DONE = {"complete", "superseded"}


class Task:
    __slots__ = ("tid", "text", "status", "deps", "verify", "evidence", "line")

    def __init__(self, tid, text, status, deps, verify, evidence, line):
        self.tid, self.text, self.status = tid, text, status
        self.deps, self.verify, self.evidence, self.line = deps, verify, evidence, line


def split_row(line):
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    return cells


def parse_plan(path):
    """Return (goal, tasks, errors). Any markdown table with ID+Status columns counts."""
    text = path.read_text(encoding="utf-8-sig")
    goal = ""
    m = re.search(r"(?mi)^goal:\s*(.+)$", text)
    if m:
        goal = m.group(1).strip()
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
                    if len(cells) >= 2:
                        get = lambda n: cells[col[n]] if n in col and col[n] < len(cells) else ""
                        tid = get("id")
                        status = get("status").lower() or "pending"
                        deps = [d.strip() for d in re.split(r"[,;]", get("depends on")) if d.strip() not in ("", "-", "–")]
                        if not tid:
                            errors.append("row %d has no task ID" % (j + 1))
                        else:
                            tasks.append(Task(tid, get("task"), status, deps,
                                              get("verify"), get("evidence"), j + 1))
                        if status not in STATUSES:
                            errors.append("%s: unknown status %r" % (tid or "?", status))
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


def actionable(tasks):
    done = {t.tid for t in tasks if t.status in DONE}
    ready = [t for t in tasks if t.status in ("pending", "active")
             and all(d in done for d in t.deps)]
    blocked = [t for t in tasks if t.status in ("pending", "active")
               and any(d not in done for d in t.deps)]
    return ready, blocked


def evidence_missing(task, root):
    """A task marked complete with a Verify value that names a missing file."""
    ref = (task.verify or "").strip().strip("`")
    if not ref:
        return False
    if any(ch in ref for ch in " |&;<>$"):
        return False  # a command, not a path; the controller cannot run it safely
    path = root / ref
    return not path.exists()


def cmd_status(root):
    plan = root / "PLAN.md"
    if not plan.exists():
        print("no PLAN.md in %s" % root)
        return 2
    goal, tasks, errors = parse_plan(plan)
    cycle = find_cycle(tasks)
    state = parse_state(root / "STATE.md")
    counts = {}
    for t in tasks:
        counts[t.status] = counts.get(t.status, 0) + 1
    print("goal: %s" % (goal or "(none recorded)"))
    print("tasks: %d  %s" % (len(tasks), "  ".join("%s=%d" % kv for kv in sorted(counts.items()))))
    ready, blocked = actionable(tasks)
    print("next: %s" % (ready[0].tid + " " + ready[0].text if ready else "(nothing actionable)"))
    print("blocked: %s" % (", ".join(t.tid for t in blocked) or "none"))
    missing = [t for t in tasks if t.status == "complete" and evidence_missing(t, root)]
    if missing:
        print("complete without evidence: %s" % ", ".join(t.tid for t in missing))
    sha = git_sha(root)
    if sha and state.get("SHA") and not sha.startswith(state["SHA"][:7]):
        print("state is stale: STATE.md says %s, repository is %s" % (state["SHA"][:7], sha[:7]))
    if state.get("CURRENT TASK"):
        print("state current task: %s" % state["CURRENT TASK"])
    if state.get("NEXT ACTION"):
        print("state next action: %s" % state["NEXT ACTION"])
    if cycle:
        errors.append("dependency cycle: %s" % " -> ".join(cycle))
    for err in errors:
        print("problem: %s" % err)
    return 1 if errors or missing or cycle else 0


def cmd_next(root):
    plan = root / "PLAN.md"
    if not plan.exists():
        print("no PLAN.md in %s" % root)
        return 2
    _goal, tasks, errors = parse_plan(plan)
    cycle = find_cycle(tasks)
    if cycle:
        print("dependency cycle: %s" % " -> ".join(cycle))
        return 1
    ready, blocked = actionable(tasks)
    if not ready:
        print("nothing actionable; %d blocked or unfinished" % len(blocked))
        return 0 if not errors else 1
    task = ready[0]
    print("%s  %s" % (task.tid, task.text))
    print("  status: %s" % task.status)
    print("  verify: %s" % (task.verify or "(none recorded)"))
    print("  evidence: %s" % (task.evidence or "(none recorded)"))
    if blocked:
        print("  waiting behind: %s" % ", ".join(t.tid for t in blocked))
    return 0


def cmd_resume(root):
    """Reconcile STATE.md with the plan and the repository; --fix rewrites fields."""
    plan, state_path = root / "PLAN.md", root / "STATE.md"
    if not plan.exists():
        print("no PLAN.md in %s" % root)
        return 2
    goal, tasks, errors = parse_plan(plan)
    cycle = find_cycle(tasks)
    if cycle:
        print("dependency cycle blocks resumption: %s" % " -> ".join(cycle))
        return 1
    state = parse_state(state_path)
    ready, _blocked = actionable(tasks)
    next_task = ready[0] if ready else None
    sha = git_sha(root)
    problems = []
    if state.get("CURRENT TASK") and state["CURRENT TASK"] not in {t.tid for t in tasks}:
        problems.append("STATE.md names a task that is not in PLAN.md: %s" % state["CURRENT TASK"])
    if next_task and state.get("CURRENT TASK") and state["CURRENT TASK"] != next_task.tid:
        problems.append("STATE.md current task %s, plan says %s" % (state["CURRENT TASK"], next_task.tid))
    stale = [t for t in tasks if t.status == "complete" and evidence_missing(t, root)]
    if stale:
        problems.append("marked complete without evidence: %s" % ", ".join(t.tid for t in stale))
    if sha and state.get("SHA") and not sha.startswith(state["SHA"][:7]):
        problems.append("STATE.md SHA %s is behind %s" % (state["SHA"][:7], sha[:7]))

    if args_fix and state_path.exists():
        text = state_path.read_text(encoding="utf-8-sig")
        updates = {}
        if next_task:
            updates["CURRENT TASK"] = next_task.tid
            updates["NEXT ACTION"] = next_task.verify or next_task.text
        if sha:
            updates["SHA"] = sha[:12]
        if updates:
            for key, value in updates.items():
                text = re.sub(r"(?m)^%s:.*$" % re.escape(key), "%s: %s" % (key, value), text)
            state_path.write_text(text, encoding="utf-8")
            print("STATE.md updated: %s" % ", ".join(sorted(updates)))

    for problem in problems:
        print("problem: %s" % problem)
    if not problems:
        print("state agrees with plan and repository")
    if next_task:
        print("resume at: %s %s" % (next_task.tid, next_task.text))
        print("verify with: %s" % (next_task.verify or "(none recorded)"))
    return 1 if problems else 0


def cmd_handoff(root):
    plan = root / "PLAN.md"
    if not plan.exists():
        print("no PLAN.md in %s" % root)
        return 2
    goal, tasks, _errors = parse_plan(plan)
    state = parse_state(root / "STATE.md")
    ready, blocked = actionable(tasks)
    task = ready[0] if ready else None
    sha = git_sha(root)
    print("## Handoff")
    print()
    print("Goal: %s" % (state.get("GOAL") or goal or "(not recorded)"))
    print("Repo: %s" % sha[:12] if sha else "Repo: (not a git repository)")
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
    return 0


def main(argv=None):
    global args_fix
    ap = argparse.ArgumentParser(description="read PLAN.md and STATE.md without a model")
    ap.add_argument("command", choices=["next", "status", "resume", "handoff"])
    ap.add_argument("--root", default=".", help="project root (default: current directory)")
    ap.add_argument("--fix", action="store_true", help="resume: rewrite STATE.md fields")
    args = ap.parse_args(argv)
    args_fix = args.fix
    root = Path(args.root).resolve()
    return {"next": cmd_next, "status": cmd_status, "resume": cmd_resume,
            "handoff": cmd_handoff}[args.command](root)


if __name__ == "__main__":
    sys.exit(main())
