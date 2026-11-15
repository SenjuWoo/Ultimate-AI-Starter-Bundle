"""The local release gate, CI and the pack gate must run the same tests.

Releases push to main after `python TOOLS/release_gate.py` passes. Ten contracts
CI ran were missing from that gate, and four passing tests ran nowhere at all,
so a regression they cover could ship unnoticed. This keeps every test file
reachable and the local gate a superset of CI's Python contracts.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))

import release_gate  # noqa: E402

# Probes that need a real executable on the machine (`--rtk`, `--codex`) and say
# so instead of skipping. They are run by hand against an installed tool.
PROBES = {"test_rtk_candidate.py", "test_codex_native_profiles.py"}
# A read-only diagnostic of the live machine's provider homes, not a fixture test.
DIAGNOSTICS = {"Test-HarnessRealization.ps1"}


def gate_scripts():
    return {Path(cmd[1]).name for _, cmd in release_gate.steps(ROOT)
            if not callable(cmd) and len(cmd) > 1 and cmd[1].startswith("TESTS/")}


def ci_python_tests():
    text = (ROOT / ".github" / "workflows" / "ci.yml").read_text(encoding="utf-8")
    return set(re.findall(r"python TESTS/(test_\w+\.py)", text))


def main():
    failures = []
    gate = gate_scripts()
    missing_locally = sorted(ci_python_tests() - gate)
    if missing_locally:
        failures.append("CI runs these, the local release gate does not: %s" % ", ".join(missing_locally))

    runners = "\n".join((ROOT / p).read_text(encoding="utf-8") for p in (
        ".github/workflows/ci.yml", "TOOLS/release_gate.py", "TESTS/Test-Pack.ps1"))
    tests = [p.name for p in (ROOT / "TESTS").iterdir()
             if p.is_file() and re.match(r"^(test_\w+\.py|Test-[\w-]+\.ps1|[\w-]+\.(mjs|cjs))$", p.name)]
    orphans = sorted(n for n in tests if n not in runners and n not in PROBES | DIAGNOSTICS)
    if orphans:
        failures.append("no gate runs these tests: %s" % ", ".join(orphans))
    for name in sorted(PROBES | DIAGNOSTICS):
        if not (ROOT / "TESTS" / name).is_file():
            failures.append("listed probe no longer exists: %s" % name)

    for line in failures:
        print("FAIL: " + line)
    print("gate parity: %s" % ("FAIL" if failures else "OK"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
