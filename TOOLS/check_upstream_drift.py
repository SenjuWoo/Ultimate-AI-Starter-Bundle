"""Report upstream drift for pinned and recommended third-party repositories.

Never updates anything: it prints each pinned revision, asks GitHub for the
current default-branch head when a network client is available, and says whether
they differ. Absence of network is a normal outcome, not a failure.

    python TOOLS/check_upstream_drift.py            # network, read-only
    python TOOLS/check_upstream_drift.py --offline  # pins only
    python TOOLS/check_upstream_drift.py --json
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REGISTRY = ROOT / "BUNDLED-TOOLS" / "COMPANIONS.json"


def load(path=REGISTRY):
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    rows = []
    for cid, entry in sorted(data.get("recommended", {}).items()):
        rows.append({"id": cid, "repo": entry["repo"], "pin": entry["pin"], "kind": "recommended"})
    for cid, entry in sorted(data.get("companions", {}).items()):
        # Owners track their own releases; the bundle only records which one it saw.
        pin = (entry.get("version") or entry.get("pin") or "").strip()
        rows.append({"id": cid, "repo": entry["repo"], "pin": pin or "-", "kind": "owner"})
    return rows


def remote_head(repo):
    """Current default-branch head via the authenticated CLI, or None."""
    parts = [p for p in repo.rstrip("/").split("/") if p]
    if len(parts) < 2:
        return None
    slug = "/".join(parts[-2:])
    try:
        out = subprocess.run(["gh", "api", "repos/%s/commits/HEAD" % slug, "--jq", ".sha"],
                             capture_output=True, text=True, timeout=25)
    except (OSError, subprocess.SubprocessError):
        return None
    sha = out.stdout.strip()
    return sha if out.returncode == 0 and len(sha) >= 7 else None


def report(rows, fetch=None, offline=False):
    out = []
    for row in rows:
        head = None if offline else (fetch or remote_head)(row["repo"])
        state = "unknown" if head is None else (
            "current" if head.lower().startswith(row["pin"].lower()[:7]) else "drifted")
        if row["kind"] == "owner" and row["pin"] == "-":
            state = "tracks-latest"
        out.append(dict(row, head=head, state=state))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description="Report upstream drift for pinned third-party code (never updates)")
    ap.add_argument("--offline", action="store_true", help="print pins without asking GitHub")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)
    rows = report(load(), offline=args.offline)
    if args.json:
        print(json.dumps(rows, indent=1))
        return 0
    for row in rows:
        head = (row["head"] or "-")[:7]
        print("%-16s %-12s pin=%s head=%s" % (row["id"], row["state"], row["pin"][:7], head))
    return 0


if __name__ == "__main__":
    sys.exit(main())
