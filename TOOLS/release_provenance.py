#!/usr/bin/env python3
"""Write the provenance files a release attaches beside its archives.

release.yml calls this after building twice: it records what was built, from
which commit and inputs, by which workflow run, and what CI proved on that
exact SHA, so someone holding a 140 MB Full-Offline archive can answer "what is
this and who built it" without reading a changelog. Everything is derived from
the tree, the fetched companions and the observed check runs -- nothing is
hand-written -- and the output is deterministic for the same inputs.

  SHA256SUMS.txt      every published file
  BUILD-RECEIPT.json  commit, workflow run, runner, toolchain, inputs, outputs
  SBOM.spdx.json      SPDX 2.3: the bundle, its bundled payloads and installed components
  VALIDATION.json     the tracked validation contract plus the checks CI observed on the SHA
  MANIFEST.json       the source tree manifest the archives were built from
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import shutil
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def load(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def dump(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8", newline="\n")


def spdx_id(text: str) -> str:
    return "SPDXRef-" + re.sub(r"[^A-Za-z0-9.-]+", "-", text).strip("-")


def license_of(component: dict) -> str:
    value = str(component.get("license") or "")
    # SPDX expressions only; free-text licence notes stay NOASSERTION rather than guessed.
    return value if re.fullmatch(r"[A-Za-z0-9.+-]+(?: (?:AND|OR|WITH) [A-Za-z0-9.+-]+)*", value) else "NOASSERTION"


def build(root: Path, dist: Path, checks: Path, commit: str, commit_time: str, repo: str) -> list[Path]:
    version = (root / "VERSION.txt").read_text(encoding="utf-8-sig").strip().lstrip("vV")
    tag = "v" + version
    archives = sorted(dist.glob("*.zip"))
    if not archives:
        raise SystemExit("no archives in " + str(dist))
    catalog = load(root / "BUNDLED-TOOLS/CATALOG.json")
    offline = load(root / "BUNDLED-TOOLS/OFFLINE-MANIFEST.json").get("assets", [])
    companions_index = root / "BUNDLED-TOOLS/offline/companions.json"
    companions = load(companions_index).get("companions", []) if companions_index.is_file() else []
    observed = load(checks)
    run_url = "{}/{}/actions/runs/{}".format(os.environ.get("GITHUB_SERVER_URL", "https://github.com"), repo,
                                             os.environ.get("GITHUB_RUN_ID", "local"))

    shutil.copyfile(root / "MANIFEST.json", dist / "MANIFEST.json")
    receipt = {
        "product": "Ultimate AI Starter Bundle", "version": version, "tag": tag, "repository": repo,
        "commit": commit, "commit_time": commit_time,
        "builder": {"workflow_run": run_url, "run_attempt": os.environ.get("GITHUB_RUN_ATTEMPT", ""),
                    "runner_os": os.environ.get("RUNNER_OS", platform.system()),
                    "runner_image": os.environ.get("ImageOS", ""), "runner_image_version": os.environ.get("ImageVersion", ""),
                    "python": platform.python_version()},
        "procedure": "built twice from the commit's MANIFEST.json and required byte-identical archives; "
                     "companions fetched at their latest release and verified against GitHub's digest and SHA256SUMS",
        "inputs": {"tree_manifest_sha256": sha256(root / "MANIFEST.json"),
                   "companions": companions,
                   "offline_payloads": [{k: a[k] for k in ("file", "size", "sha256") if k in a} for a in offline]},
        "outputs": [{"name": a.name, "size": a.stat().st_size, "sha256": sha256(a)} for a in archives],
    }
    dump(dist / "BUILD-RECEIPT.json", receipt)

    root_id = "SPDXRef-Package-ultimate-ai-starter-bundle"
    packages = [{"SPDXID": root_id, "name": "Ultimate AI Starter Bundle", "versionInfo": version,
                 "downloadLocation": "git+https://github.com/%s@%s" % (repo, commit), "supplier": "Organization: SenjuWoo",
                 "licenseConcluded": "MIT", "licenseDeclared": "MIT", "copyrightText": "NOASSERTION", "filesAnalyzed": False}]
    relationships = [{"spdxElementId": "SPDXRef-DOCUMENT", "relationshipType": "DESCRIBES", "relatedSpdxElement": root_id}]
    bundled = {a["file"]: a for a in offline}
    fetched = {c["id"]: c for c in companions}
    for comp in sorted(catalog.get("components", []), key=lambda c: c["id"]):
        github = comp.get("github") or {}
        location = "https://github.com/%s/%s" % (github["owner"], github["repo"]) if github.get("owner") else "NOASSERTION"
        package = {"SPDXID": spdx_id("Package-" + comp["id"]), "name": comp.get("name", comp["id"]),
                   "versionInfo": str(comp.get("version") or fetched.get(comp["id"], {}).get("version") or "NOASSERTION"),
                   "downloadLocation": location, "licenseConcluded": "NOASSERTION", "licenseDeclared": license_of(comp),
                   "copyrightText": "NOASSERTION", "filesAnalyzed": False}
        payload = bundled.get(comp.get("offline_asset", "")) or (
            {"file": fetched[comp["id"]]["asset"], "sha256": fetched[comp["id"]]["sha256"]} if comp["id"] in fetched else None)
        if payload:
            package["packageFileName"] = "BUNDLED-TOOLS/offline/" + payload["file"]
            package["checksums"] = [{"algorithm": "SHA256", "checksumValue": payload["sha256"]}]
        packages.append(package)
        relationships.append({"spdxElementId": root_id, "relationshipType": "CONTAINS" if payload else "DEPENDS_ON",
                              "relatedSpdxElement": package["SPDXID"]})
    dump(dist / "SBOM.spdx.json", {
        "spdxVersion": "SPDX-2.3", "dataLicense": "CC0-1.0", "SPDXID": "SPDXRef-DOCUMENT",
        "name": "Ultimate-AI-Starter-Bundle-" + tag,
        "documentNamespace": "https://github.com/%s/releases/tag/%s#sbom-%s" % (repo, tag, commit),
        "creationInfo": {"created": commit_time, "creators": ["Tool: TOOLS/release_provenance.py", "Organization: SenjuWoo"]},
        "packages": packages, "relationships": relationships})

    validation = load(root / "VALIDATION.json")
    validation["ci"] = {"commit": commit, "workflow_run": run_url, "checks": observed.get("checks", []),
                        "statuses": observed.get("statuses", [])}
    dump(dist / "VALIDATION.json", validation)

    published = sorted(p for p in dist.iterdir() if p.is_file() and p.name != "SHA256SUMS.txt")
    (dist / "SHA256SUMS.txt").write_text("".join("%s  %s\n" % (sha256(p), p.name) for p in published),
                                         encoding="ascii", newline="\n")
    return published + [dist / "SHA256SUMS.txt"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    ap.add_argument("--dist", type=Path, required=True)
    ap.add_argument("--checks", type=Path, required=True, help="JSON {checks:[...], statuses:[...]} observed on the SHA")
    ap.add_argument("--commit", required=True)
    ap.add_argument("--commit-time", required=True)
    ap.add_argument("--repo", required=True)
    a = ap.parse_args()
    for path in build(a.root.resolve(), a.dist.resolve(), a.checks, a.commit, a.commit_time, a.repo):
        print("%s  %s" % (sha256(path), path.name))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
