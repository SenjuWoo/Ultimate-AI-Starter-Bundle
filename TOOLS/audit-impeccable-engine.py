#!/usr/bin/env python3
"""Compare a real impeccable engine against the malformed-tag fixtures UABS patched for.

The vendored CLI 3.6.1 JS payload is patched so a browser-valid malformed close tag
(``</script \t bogus>``) does not leak its body into text analysis. CLI 4.x moved that
code into a compiled engine binary UABS cannot patch, so the fixture is run against the
real engine whenever one is available. Exits non-zero when the engine leaks a fixture
body or when a control fixture stops producing the expected finding.

Usage: python TOOLS/audit-impeccable-engine.py <path-to-impeccable-binary-or-shim>
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from pathlib import Path

FIXTURES = {
    "wellformed-script": (
        '<!doctype html><html><body><script>const bait = "streamline your";</script><main>plain</main></body></html>',
        False,
    ),
    "malformed-script": (
        "<!doctype html><html><body><script>streamline your</script \t bogus><main>plain</main></body></html>",
        False,
    ),
    "malformed-style": (
        '<!doctype html><html><body><style>.a{content:"streamline your"}</style bogus><main>plain</main></body></html>',
        False,
    ),
    "control": (
        "<!doctype html><html><body><main>Streamline your workflow and leverage synergy today</main></body></html>",
        True,
    ),
}


def command_for(engine: str) -> list[str]:
    """A real engine binary runs directly; the npm shim and the skill launchers need a host."""
    lower = engine.lower()
    if lower.endswith((".js", ".mjs")):
        return ["node", engine]
    if lower.endswith((".cmd", ".bat")):
        return ["cmd", "/c", engine]
    return [engine]


def findings(engine: str, path: Path) -> list[dict]:
    out = subprocess.run(
        [*command_for(engine), "detect", "--json", "--no-config", str(path)],
        capture_output=True, text=True, timeout=180,
    )
    return json.loads(out.stdout or "[]")


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    engine = sys.argv[1]
    failures = 0
    with tempfile.TemporaryDirectory(prefix="impeccable-audit-") as td:
        for name, (html, expect_finding) in FIXTURES.items():
            p = Path(td) / f"{name}.html"
            p.write_text(html, encoding="utf-8")
            got = findings(engine, p)
            buzz = any(f.get("antipattern") == "marketing-buzzword" for f in got)
            ok = buzz == expect_finding
            failures += 0 if ok else 1
            print(f"{'ok  ' if ok else 'LEAK'} {name}: {len(got)} finding(s), buzzword={buzz}, expected={expect_finding}")
    print("engine accepts UABS malformed-tag fixtures" if not failures else f"{failures} fixture(s) failed: engine still leaks tag bodies into analysis")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
