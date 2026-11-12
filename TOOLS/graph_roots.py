"""Report codebase-memory projects whose recorded root no longer exists.

A graph keeps answering after its project folder is moved or renamed: every
query returns the old structure and nothing says so. This lists the indexed
projects through the owner CLI, flags a root that is gone, and, when exactly one
git checkout with the same folder name sits under the declared tool roots, names
where the project went. Read-only: it never re-indexes, renames or deletes a graph.

    python TOOLS/graph_roots.py             # text report, always exit 0
    python TOOLS/graph_roots.py --json
    python TOOLS/graph_roots.py --strict    # exit 1 when a root is missing
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import companion_registry as registry  # noqa: E402  (bounded root discovery lives there)

TIMEOUT = 60


def find_cli(explicit=None):
    """The codebase-memory executable: explicit, declared, on PATH, then its default home."""
    local = os.environ.get("LOCALAPPDATA") or os.path.join(os.path.expanduser("~"), "AppData", "Local")
    candidates = [explicit, os.environ.get("CODEBASE_MEMORY_MCP"), shutil.which("codebase-memory-mcp"),
                  os.path.join(local, "Programs", "codebase-memory-mcp", "codebase-memory-mcp.exe")]
    for candidate in candidates:
        if candidate and os.path.isfile(candidate):
            return candidate
    return None


def list_projects(cli):
    """[{name, root_path}] as the graph store records them; raises on an unusable CLI."""
    done = subprocess.run([cli, "cli", "--quiet", "list_projects", json.dumps({"format": "json"})],
                          capture_output=True, text=True, encoding="utf-8", errors="replace", timeout=TIMEOUT)
    if done.returncode != 0:
        raise RuntimeError("list_projects exited %d: %s" % (done.returncode, done.stderr.strip()[-300:]))
    start = done.stdout.find("{")
    if start < 0:
        raise RuntimeError("list_projects returned no JSON")
    payload = json.loads(done.stdout[start:])
    projects = payload.get("projects")
    if not isinstance(projects, list):
        raise RuntimeError("list_projects JSON has no project list")
    return [p for p in projects if isinstance(p, dict) and p.get("name") and p.get("root_path")]


def relocated(old_root, directories):
    """The one git checkout that carries the missing root's folder name, else None."""
    wanted = os.path.basename(old_root.rstrip("/" + os.sep)).casefold()
    if not wanted:
        return None
    matches = [path for path in directories
               if os.path.basename(path.rstrip("/" + os.sep)).casefold() == wanted
               and os.path.exists(os.path.join(path, ".git"))]
    return matches[0] if len(matches) == 1 else None


def audit(projects, directories):
    rows = []
    for project in projects:
        root = project["root_path"]
        exists = os.path.isdir(root)
        rows.append({"name": project["name"], "root": root, "exists": exists,
                     "moved_to": None if exists else relocated(root, directories)})
    return rows


def main(argv=None):
    ap = argparse.ArgumentParser(description="Find code-graph projects whose root has moved (read-only)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--strict", action="store_true", help="exit 1 when any root is missing")
    ap.add_argument("--exe", help="codebase-memory executable (default: discover it)")
    ap.add_argument("--roots", action="append", default=[], help="extra directory to search for a moved project")
    args = ap.parse_args(argv)

    cli = find_cli(args.exe)
    if not cli:
        report = {"available": False, "reason": "codebase-memory-mcp is not installed", "projects": []}
    else:
        try:
            projects = list_projects(cli)
            missing_any = any(not os.path.isdir(p["root_path"]) for p in projects)
            # The bounded inventory costs a directory walk; only pay for it when something moved.
            directories = registry.directory_index(registry.roots(args.roots)) if missing_any else []
            report = {"available": True, "projects": audit(projects, directories)}
        except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as exc:
            report = {"available": False, "reason": str(exc), "projects": []}

    stale = [row for row in report["projects"] if not row["exists"]]
    if args.json:
        print(json.dumps(report, indent=1))
    elif not report["available"]:
        print("code graph not checked: %s" % report["reason"])
    else:
        for row in report["projects"]:
            print("%-8s %-28s %s" % ("ok" if row["exists"] else "MISSING", row["name"], row["root"]))
            if not row["exists"]:
                if row["moved_to"]:
                    print("         now at %s - index that root under the same name, then retire the old graph"
                          % row["moved_to"])
                else:
                    print("         no single checkout named like it was found; index its current root by hand")
        print("\n%d project(s), %d with a missing root" % (len(report["projects"]), len(stale)))
    return 1 if (args.strict and stale) else 0


if __name__ == "__main__":
    sys.exit(main())
