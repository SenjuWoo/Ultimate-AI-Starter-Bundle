"""Run every release check in order and stop at the first failure.

A single combined command must never hide an earlier failure, so each step's exit
code is checked immediately and the gate returns the failing step's code.

    python TOOLS/release_gate.py              # full local gate
    python TOOLS/release_gate.py --list       # show the steps
    python TOOLS/release_gate.py --extra "cmd"  # prove fail-fast on purpose
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def base_args(root):
    """Compare against the last release tag: the commits a release would publish."""
    out = subprocess.run(["git", "-C", str(root), "describe", "--tags", "--abbrev=0"],
                         capture_output=True, text=True)
    tag = out.stdout.strip()
    return ["--base", tag] if out.returncode == 0 and tag else []


def steps(root):
    py = sys.executable
    base_args_ = base_args(root)
    pw = ["powershell.exe", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File"]
    return [
        ("manifest matches the tree", [py, "TOOLS/verify_manifest.py"]),
        ("docs gate", [py, "TOOLS/verify_docs.py"]),
        ("version declarations agree", [py, ".github/scripts/check_versions.py"]),
        ("release contracts", [py, "TESTS/test_release_contract.py"]),
        ("task controller", [py, "TESTS/test_task_state.py"]),
        ("provider routing safety", [py, "TESTS/test_provider_routing.py"]),
        ("companion registry", [py, "TESTS/test_companion_registry.py"]),
        ("apps and forges by name", [py, "TESTS/test_app_paths.py"]),
        ("Hermes memory", [py, "TESTS/test_hermes_memory.py"]),
        ("upstream drift report", [py, "TESTS/test_upstream_drift.py"]),
        ("recommended skill packs", [py, "TESTS/test_recommended_skills.py"]),
        ("skill routing", [py, "TESTS/test_skill_routing.py"]),
        ("task routing", [py, "TESTS/test_task_route.py"]),
        ("task router hook", [py, "TESTS/test_task_router_hook.py"]),
        ("ponytail mode", [py, "TESTS/test_ponytail_mode.py"]),
        ("ponytail integration", [py, "TESTS/test_ponytail_integration.py"]),
        ("line endings", [py, "TESTS/test_line_endings.py"]),
        ("line-ending churn", [py, "TOOLS/check_line_endings.py"] + base_args_),
        ("working-tree line endings", [py, "TOOLS/check_line_endings.py"]),
        ("staged line endings", [py, "TOOLS/check_line_endings.py", "--staged"]),
        ("privacy boundary", [py, "TESTS/test_privacy_boundary.py"]),
        ("pack gate", pw + ["TESTS/Test-Pack.ps1"]),
    ]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--extra", action="append", default=[],
                    help="run this command after the listed steps; used to prove fail-fast")
    args = ap.parse_args()

    plan = steps(ROOT)
    if args.list:
        for name, cmd in plan:
            print("%-32s %s" % (name, " ".join(cmd)))
        return 0

    for name, cmd in plan:
        print("==> %s" % name, flush=True)
        # Capture so a failure prints its own reason instead of vanishing above
        # the next step's output; a passing step keeps only its last line.
        env = os.environ.copy()
        if Path(cmd[0]).name.lower() == "powershell.exe":
            # Python does not perform PowerShell 7's compatibility launch cleanup.
            # An inherited PS7 module path can shadow WinPS 5.1's standard modules
            # and make Get-FileHash disappear. Let the child build its own defaults.
            env = {k: v for k, v in env.items() if k.upper() != "PSMODULEPATH"}
        result = subprocess.run(cmd, cwd=str(ROOT), capture_output=True, text=True,
                                errors="replace", env=env)
        tail = [l for l in (result.stdout + result.stderr).splitlines() if l.strip()]
        if result.returncode != 0:
            print(chr(10).join(tail[-40:]))
            print("RELEASE GATE: FAIL at '%s' (exit %d)" % (name, result.returncode))
            return result.returncode
        if tail:
            print("    %s" % tail[-1])

    for cmd in args.extra:
        print("==> extra: %s" % cmd, flush=True)
        result = subprocess.run(cmd, cwd=str(ROOT), shell=True)
        if result.returncode != 0:
            print("RELEASE GATE: FAIL at extra step (exit %d)" % result.returncode)
            return result.returncode

    print("RELEASE GATE: PASS (%d checks)" % (len(plan) + len(args.extra)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
