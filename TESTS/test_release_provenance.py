"""release_provenance.py output is complete, honest about its inputs and deterministic."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("release_provenance", ROOT / "TOOLS/release_provenance.py")
provenance = importlib.util.module_from_spec(spec)
spec.loader.exec_module(provenance)


def write(path: Path, data) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(data if isinstance(data, str) else json.dumps(data), encoding="utf-8")


class ReleaseProvenance(unittest.TestCase):
    def fixture(self, root: Path) -> tuple[Path, Path]:
        write(root / "VERSION.txt", "v9.1.0\n")
        write(root / "MANIFEST.json", [{"path": "README.md", "size": 1, "sha256": "0" * 64}])
        write(root / "VALIDATION.json", {"version": "9.1.0", "gates": ["pack gate"]})
        write(root / "BUNDLED-TOOLS/CATALOG.json", {"components": [
            {"id": "tool", "name": "Tool", "version": "1.2.3", "license": "MIT", "offline_asset": "tool.zip",
             "github": {"owner": "up", "repo": "tool"}},
            {"id": "skyrim-forge", "name": "Skyrim Forge", "install": "latest-release", "github": {"owner": "o", "repo": "f"}},
            {"id": "notes", "name": "Notes", "license": "see upstream"}]})
        write(root / "BUNDLED-TOOLS/OFFLINE-MANIFEST.json", {"assets": [{"file": "tool.zip", "size": 3, "sha256": "a" * 64}]})
        write(root / "BUNDLED-TOOLS/offline/companions.json", {"companions": [
            {"id": "skyrim-forge", "version": "6.5.0", "asset": "Skyrim-Forge-6.5.0.zip", "sha256": "b" * 64}]})
        dist = root / "dist"
        write(dist / "Bundle-Core.zip", "core")
        write(dist / "Bundle-Full-Offline.zip", "full")
        checks = root / "checks.json"
        write(checks, {"checks": [{"name": "Pack gate", "conclusion": "success", "url": "u"}], "statuses": []})
        return dist, checks

    def test_outputs_are_complete_and_deterministic(self):
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            runs = []
            for td in (a, b):
                root = Path(td)
                dist, checks = self.fixture(root)
                provenance.build(root, dist, checks, "c" * 40, "2026-10-29T00:00:00Z", "owner/bundle")
                runs.append({p.name: p.read_bytes() for p in dist.iterdir()})
            self.assertEqual(runs[0], runs[1], "same inputs must give byte-identical provenance")
            files = runs[0]
            self.assertEqual(set(files), {"Bundle-Core.zip", "Bundle-Full-Offline.zip", "MANIFEST.json", "BUILD-RECEIPT.json",
                                          "SBOM.spdx.json", "VALIDATION.json", "SHA256SUMS.txt"})
            sums = dict(reversed(line.split("  ", 1)) for line in files["SHA256SUMS.txt"].decode().splitlines())
            self.assertEqual(set(sums), set(files) - {"SHA256SUMS.txt"})
            for name, digest in sums.items():
                self.assertEqual(hashlib.sha256(files[name]).hexdigest(), digest)
            receipt = json.loads(files["BUILD-RECEIPT.json"])
            self.assertEqual((receipt["commit"], receipt["tag"]), ("c" * 40, "v9.1.0"))
            self.assertEqual({o["name"]: o["sha256"] for o in receipt["outputs"]},
                             {n: hashlib.sha256(files[n]).hexdigest() for n in ("Bundle-Core.zip", "Bundle-Full-Offline.zip")})
            self.assertEqual(receipt["inputs"]["companions"][0]["version"], "6.5.0")
            sbom = json.loads(files["SBOM.spdx.json"])
            self.assertEqual(sbom["spdxVersion"], "SPDX-2.3")
            byname = {p["name"]: p for p in sbom["packages"]}
            self.assertEqual(byname["Tool"]["checksums"][0]["checksumValue"], "a" * 64)
            self.assertEqual(byname["Skyrim Forge"]["versionInfo"], "6.5.0", "a companion's version is the fetched release")
            self.assertEqual(byname["Notes"]["licenseDeclared"], "NOASSERTION", "free-text licences are not guessed")
            kinds = {r["relatedSpdxElement"]: r["relationshipType"] for r in sbom["relationships"]}
            self.assertEqual(kinds[byname["Tool"]["SPDXID"]], "CONTAINS")
            self.assertEqual(kinds[byname["Notes"]["SPDXID"]], "DEPENDS_ON")
            validation = json.loads(files["VALIDATION.json"])
            self.assertEqual(validation["gates"], ["pack gate"])
            self.assertEqual(validation["ci"]["checks"][0]["conclusion"], "success")


if __name__ == "__main__":
    unittest.main()
