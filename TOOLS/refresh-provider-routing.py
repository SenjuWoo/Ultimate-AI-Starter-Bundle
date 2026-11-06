"""Refresh provider_routing.only from live OpenRouter prices.

Prices change daily, so the bundle ships no static allowlist. This prints the
current cheapest cache-read providers for a model (fp4 endpoints excluded) in the
exact YAML shape `provider_routing.only` expects. `--write` updates a config file
in place; nothing here runs on install by itself.

    python TOOLS/refresh-provider-routing.py
    python TOOLS/refresh-provider-routing.py --model deepseek/deepseek-v4.1-flash-1017
    python TOOLS/refresh-provider-routing.py --write %LOCALAPPDATA%\\hermes\\config.yaml
"""

import argparse
import json
import os
import pathlib
import sys
import urllib.request

DEFAULT_MODEL = "deepseek/deepseek-v4.1-flash-1017"
API = "https://openrouter.ai/api/v1/models/%s/endpoints"
# Quantizations the operator refuses to run.
BANNED = {"fp4", "int4"}


def endpoints(model, timeout=30):
    req = urllib.request.Request(API % model, headers={"User-Agent": "uabs-refresh-routing"})
    with urllib.request.urlopen(req, timeout=timeout) as fh:
        return json.load(fh)["data"]["endpoints"]


def cheapest(model, count):
    rows = []
    for e in endpoints(model):
        quant = (e.get("quantization") or "unknown").lower()
        if quant in BANNED:
            continue
        price = (e.get("pricing") or {}).get("input_cache_read")
        if price in (None, ""):
            continue
        slug = (e.get("tag") or "").split("/")[0]
        if not slug:
            continue
        rows.append((float(price), slug, e.get("provider_name"), quant))
    seen, out = set(), []
    for price, slug, name, quant in sorted(rows):
        if slug in seen:
            continue
        seen.add(slug)
        out.append((slug, price, name, quant))
        if len(out) == count:
            break
    return out


def block(slugs, nl="\n"):
    return "  only:" + nl + "".join("    - %s%s" % (s, nl) for s in slugs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--count", type=int, default=8)
    ap.add_argument("--write", metavar="CONFIG", help="update provider_routing.only in this config.yaml")
    args = ap.parse_args()

    picks = cheapest(args.model, args.count)
    slugs = [p[0] for p in picks]
    for slug, price, name, quant in picks:
        print("# %-14s %-22s cache-read $%.4f/M  %s" % (slug, name, price * 1e6, quant))
    print(block(slugs, "\n").rstrip())

    if args.write:
        path = pathlib.Path(os.path.expanduser(args.write))
        text = path.read_text(encoding="utf-8")
        nl = "\r\n" if "\r\n" in text else "\n"
        lines = [l for l in text.splitlines(keepends=True)]
        start = next(i for i, l in enumerate(lines) if l.startswith("provider_routing:"))
        end = next((i for i in range(start + 1, len(lines))
                    if lines[i] and not lines[i][0].isspace()), len(lines))
        body = [l for l in lines[start + 1:end] if not l.lstrip().startswith(("- ", "only:"))]
        at = next(i for i, l in enumerate(body) if l.strip() == "require_parameters: true") + 1
        body[at:at] = [("  only:" + nl)] + ["    - %s%s" % (s, nl) for s in slugs]
        lines[start + 1:end] = body
        path.write_text("".join(lines), encoding="utf-8")
        print("\nupdated %s" % path, file=sys.stderr)


if __name__ == "__main__":
    main()
