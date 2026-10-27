"""Compatibility entrypoint; the canonical verifier also ships in the product."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).resolve().parents[2]/"TOOLS"/"verify_manifest.py"),run_name="__main__")
