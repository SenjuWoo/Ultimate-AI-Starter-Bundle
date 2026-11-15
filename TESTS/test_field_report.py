"""A defect found in an owner's tool is recorded in that owner's folder, not patched
from outside and not dropped. Temp owners only; no real forge is touched."""

import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "TOOLS"))

import field_report as fr  # noqa: E402

DATA = {"schema": 1, "owner_allowlist": ["github.com/SenjuWoo/"], "companions": {"demo-forge": {
    "title": "Demo Forge", "repo": "https://github.com/SenjuWoo/Demo-Forge",
    "install": {"kind": "source_only", "asset": None}, "markers": ["demo.cmd"], "platforms": ["windows"]}}}


def owner(tmp, git=True):
    root = Path(tmp) / "Demo-Forge"
    root.mkdir()
    (root / "demo.cmd").write_text("", encoding="ascii")
    if git:
        (root / ".git" / "info").mkdir(parents=True)
    return root


def record(tmp, **fields):
    args = {"title": "doctor crashes on a path with a space", "version": "1.2.0",
            "command": "demoforge doctor", "expected": "exit 0", "actual": "traceback",
            "workaround": "ran it from C:\\x", "found_in": "a mod project"}
    args.update(fields)
    return fr.record("demo-forge", data=DATA, search_roots=[tmp], today="2026-11-15", **args)


def main():
    failures = []

    def check(ok, label):
        if not ok:
            failures.append(label)

    with tempfile.TemporaryDirectory() as tmp:
        root = owner(tmp)
        result = record(tmp)
        inbox = root / fr.INBOX
        text = inbox.read_text(encoding="utf-8")
        check(result["path"] == str(inbox) and result["state"] == "recorded", "first report is recorded in the owner")
        check("## doctor crashes on a path with a space" in text and "- Version: 1.2.0" in text
              and "- Command: `demoforge doctor`" in text and "- Reported: 2026-11-15" in text, "entry carries the facts")
        check("delete the entry" in text, "the header tells the owner what to do with it")
        check(fr.INBOX in (root / ".git" / "info" / "exclude").read_text(encoding="utf-8"),
              "the inbox is kept out of the owner's commits")

        # The same defect again is one entry with a second date, not a duplicate.
        again = record(tmp, title="Doctor crashes on a path with a space")
        text = inbox.read_text(encoding="utf-8")
        check(again["state"] == "seen-again" and text.count("## ") == 1 and "- Seen again: 2026-11-15" in text,
              "a repeat is counted, not duplicated")

        record(tmp, title="package drops the licence file")
        check(inbox.read_text(encoding="utf-8").count("## ") == 2, "a different defect is a new entry")
        listed = fr.open_reports(data=DATA, search_roots=[tmp])
        check(listed == {"demo-forge": {"path": str(inbox), "titles": [
            "doctor crashes on a path with a space", "package drops the licence file"]}}, "list names the open reports")

        # Rerunning never duplicates the exclude line.
        check((root / ".git" / "info" / "exclude").read_text(encoding="utf-8").count(fr.INBOX) == 1,
              "the exclude line is written once")

    with tempfile.TemporaryDirectory() as tmp:
        root = owner(tmp, git=False)
        home = os.path.expanduser("~")
        record(tmp, actual="failed in %s\\Projects\\Secret and %s" % (home, home.replace("\\", "/") + "/x"))
        text = (root / fr.INBOX).read_text(encoding="utf-8")
        check(home not in text and home.replace("\\", "/") not in text and "~" in text,
              "the home folder is not written into another owner's tree")
        check(not (root / ".git").exists(), "no .git is invented for an owner that has none")

    with tempfile.TemporaryDirectory() as tmp:
        try:
            fr.record("nope", title="x", data=DATA, search_roots=[tmp], today="2026-11-15")
        except fr.UnknownOwner as exc:
            check("demo-forge" in str(exc), "an unknown owner names the known ones")
        else:
            failures.append("an unknown owner was accepted")
        try:
            record(tmp)
        except fr.UnknownOwner as exc:
            check("not found" in str(exc), "an owner that is not on this machine is named")
        else:
            failures.append("a report was written for an owner that is not installed")

    # The bundle is an owner too, and the CLI prints one JSON object.
    with tempfile.TemporaryDirectory() as tmp:
        import contextlib
        import io
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = fr.main(["bundle", "--title", "demo", "--json", "--bundle-root", tmp])
        doc = json.loads(out.getvalue())
        check(code == 0 and doc["path"] == str(Path(tmp) / fr.INBOX) and (Path(tmp) / fr.INBOX).is_file(),
              "bundle defects are recorded in the bundle")

    for line in failures:
        print("FAIL: " + line)
    print("field report: %s" % ("FAIL" if failures else "OK"))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
