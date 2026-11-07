"""Safety tests for TOOLS/refresh-provider-routing.py. No network: prices are stubbed."""

import importlib.util
import tempfile
import unittest
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:  # optional outside CI
    yaml = None

TOOL = Path(__file__).resolve().parents[1] / "TOOLS" / "refresh-provider-routing.py"
_spec = importlib.util.spec_from_file_location("refresh_routing", TOOL)
assert _spec is not None and _spec.loader is not None, TOOL
refresh = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(refresh)

SLUGS = ["cheap-a", "cheap-b", "cheap-c"]

CONFIG = (
    "model:\r\n  default: some/model\r\n"
    "provider_routing:\r\n  sort: price\r\n  require_parameters: true\r\n"
    "  only:\r\n    - stale-one\r\n"
    "  extra_list:\r\n    - keep-me\r\n"
    "  extra_map:\r\n    nested:\r\n      - deep-value\r\n"
    "compression:\r\n  threshold: 0.5\r\n"
)


def stub(monkeypatch_attr, value):
    setattr(refresh, monkeypatch_attr, value)


@unittest.skipUnless(yaml is not None, "PyYAML is not installed in this interpreter")
class RoutingTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.cfg = Path(self.dir.name) / "config.yaml"

    def tearDown(self):
        self.dir.cleanup()

    def write(self, text=CONFIG):
        self.cfg.write_text(text, encoding="utf-8", newline="")

    def test_dry_run_changes_nothing(self):
        self.write()
        before = self.cfg.read_bytes()
        new_text, old = refresh.replace_only(self.cfg.read_bytes().decode("utf-8"), SLUGS)
        self.assertIn("stale-one", old)
        self.assertEqual(before, self.cfg.read_bytes())
        self.assertIn("cheap-a", new_text)

    def test_only_the_only_list_changes(self):
        self.write()
        before = yaml.safe_load(self.cfg.read_text(encoding="utf-8"))
        rc = refresh.write_config(self.cfg, SLUGS)
        after = yaml.safe_load(self.cfg.read_text(encoding="utf-8"))
        self.assertEqual(rc, 0)
        self.assertEqual(after["provider_routing"]["only"], SLUGS)
        self.assertEqual(after["provider_routing"]["extra_list"], ["keep-me"])
        self.assertEqual(after["provider_routing"]["extra_map"], {"nested": ["deep-value"]})
        changed = {k for k in set(before["provider_routing"]) | set(after["provider_routing"])
                   if before["provider_routing"].get(k) != after["provider_routing"].get(k)}
        self.assertEqual(changed, {"only"})

    def test_crlf_survives(self):
        self.write()
        refresh.write_config(self.cfg, SLUGS)
        raw = self.cfg.read_bytes()
        self.assertEqual(raw.replace(b"\r\n", b"").count(b"\n"), 0, "line endings were rewritten to LF")

    def test_backup_is_written_once(self):
        self.write()
        refresh.write_config(self.cfg, SLUGS)
        backups = list(self.cfg.parent.glob("config.yaml.bak-*"))
        self.assertEqual(len(backups), 1)
        self.assertIn("stale-one", backups[0].read_text(encoding="utf-8"))

    def test_second_run_is_a_no_op(self):
        self.write()
        refresh.write_config(self.cfg, SLUGS)
        stamp = self.cfg.stat().st_mtime_ns
        rc = refresh.write_config(self.cfg, SLUGS)
        self.assertEqual(rc, 0)
        self.assertEqual(stamp, self.cfg.stat().st_mtime_ns)
        self.assertEqual(len(list(self.cfg.parent.glob("config.yaml.bak-*"))), 1)

    def test_malformed_config_is_left_alone(self):
        bad = "provider_routing:\n  only: [unclosed\n"
        self.write(bad)
        with self.assertRaises(Exception):
            refresh.write_config(self.cfg, SLUGS)
        self.assertEqual(self.cfg.read_text(encoding="utf-8"), bad)

    def test_missing_keys_are_refused(self):
        self.write("model:\r\n  default: x\r\n")
        with self.assertRaises(ValueError):
            refresh.write_config(self.cfg, SLUGS)

    def test_fp4_routes_are_skipped_and_unknown_precision_is_kept(self):
        stub("endpoints", lambda model, timeout=30: [
            {"pricing": {"input_cache_read": "0.001"}, "tag": "fp4-guy/fp4", "quantization": "fp4",
             "provider_name": "FP4"},
            {"pricing": {"input_cache_read": "0.002"}, "tag": "unknown-guy/unknown", "quantization": "unknown",
             "provider_name": "Unknown"},
            {"pricing": {"input_cache_read": "0.003"}, "tag": "fp8-guy/fp8", "quantization": "fp8",
             "provider_name": "FP8"},
        ])
        picks = refresh.cheapest("x/y", 8)
        slugs = [p[1] for p in picks]
        self.assertEqual(slugs, ["unknown-guy", "fp8-guy"])
        self.assertEqual([p[3] for p in picks], ["unknown", "fp8"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
