"""Refresh provider_routing.only from live OpenRouter prices.

Prices change daily, so the bundle ships no static allowlist. This prints the
current cheapest cache-read providers for a model (fp4/int4 excluded) in the YAML
shape `provider_routing.only` expects. Nothing runs on install by itself.

`--write` rewrites exactly one key: the `only:` list inside `provider_routing`.
It backs the file up, parses the result before replacing it atomically, and
leaves the file untouched on an API failure or an unexpected config shape.

    python TOOLS/refresh-provider-routing.py
    python TOOLS/refresh-provider-routing.py --write %LOCALAPPDATA%\\hermes\\config.yaml
"""

import argparse
import datetime
import json
import os
import pathlib
import re
import shutil
import sys
import tempfile
import urllib.request

DEFAULT_MODEL = "deepseek/deepseek-v4.1-flash-1017"
API = "https://openrouter.ai/api/v1/models/%s/endpoints"
BANNED = {"fp4", "int4"}  # the operator does not run these


def _replace(src, dst, attempts=6):
    """os.replace with a short retry.

    On Windows a virus scanner or the search indexer can hold a just-written file
    open for a moment, and the rename then fails with PermissionError although
    nothing is wrong. Retrying keeps the write atomic; the last error still raises.
    """
    import time as _time
    for attempt in range(attempts):
        try:
            os.replace(src, dst)
            return
        except PermissionError:
            if attempt == attempts - 1:
                raise
            _time.sleep(0.05 * (2 ** attempt))


def endpoints(model, timeout=30):
    req = urllib.request.Request(API % model, headers={"User-Agent": "uabs-refresh-routing"})
    with urllib.request.urlopen(req, timeout=timeout) as fh:
        return json.load(fh)["data"]["endpoints"]


def cheapest(model, count):
    """Cheapest distinct providers by cache-read price. Unknown precision stays unknown."""
    rows, seen = [], set()
    for e in endpoints(model):
        quant = (e.get("quantization") or "unknown").lower()
        if quant in BANNED:
            continue
        price = (e.get("pricing") or {}).get("input_cache_read")
        if price in (None, ""):
            continue
        slug = (e.get("tag") or "").split("/")[0]
        if not slug or slug in seen:
            continue
        seen.add(slug)
        rows.append((float(price), slug, e.get("provider_name"), quant))
    return sorted(rows)[:count]


def replace_only(text, slugs):
    """Rewrite only the `only:` list inside provider_routing. Returns (new_text, old_list)."""
    lines = text.splitlines(keepends=True)
    start = next((i for i, l in enumerate(lines) if re.match(r"^provider_routing:\s*$", l)), None)
    if start is None:
        raise ValueError("no provider_routing block")
    end = next((i for i in range(start + 1, len(lines))
                if lines[i].strip() and not lines[i][0].isspace()), len(lines))
    block = lines[start + 1:end]

    only_at = next((i for i, l in enumerate(block) if re.match(r"^\s+only:\s*$", l)), None)
    old_list = []
    if only_at is not None:
        indent = len(block[only_at]) - len(block[only_at].lstrip())
        stop = only_at + 1
        while stop < len(block) and block[stop].strip() and \
                len(block[stop]) - len(block[stop].lstrip()) > indent:
            old_list.append(block[stop].strip().lstrip("- ").strip())
            stop += 1
        block = block[:only_at] + block[stop:]

    nl = "\r\n" if any(l.endswith("\r\n") for l in lines) else "\n"
    anchor_at = next((i for i, l in enumerate(block) if l.strip() == "require_parameters: true"), None)
    if anchor_at is None:
        raise ValueError("no require_parameters line to anchor the list to")
    indent = len(block[anchor_at]) - len(block[anchor_at].lstrip())
    new_block = [" " * indent + "only:" + nl] + [" " * (indent + 2) + "- %s%s" % (s, nl) for s in slugs]
    block = block[:anchor_at + 1] + new_block + block[anchor_at + 1:]
    return "".join(lines[:start + 1] + block + lines[end:]), old_list


def write_config(path, slugs):
    import yaml  # only the write path needs it; printing prices stays dependency-free

    with path.open(encoding="utf-8", newline="") as fh:  # keep CRLF exactly
        text = fh.read()
    before = yaml.safe_load(text)
    new_text, old_list = replace_only(text, slugs)
    after = yaml.safe_load(new_text)
    if after == before:
        print("config already lists exactly these providers; nothing written")
        return 0
    expected = json.loads(json.dumps(before))
    expected.setdefault("provider_routing", {})["only"] = slugs
    if after != expected:
        print("refusing to write: the edit would change more than provider_routing.only")
        return 1

    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = path.with_name(path.name + ".bak-" + stamp)
    shutil.copy2(path, backup)
    fd, tmp = tempfile.mkstemp(dir=str(path.parent), prefix=".routing-", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
            fh.write(new_text)
        _replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise
    print("updated %s" % path)
    print("  backup: %s" % backup.name)
    print("  only: %s -> %s" % (", ".join(old_list) or "(none)", ", ".join(slugs)))
    return 0


def main():
    ap = argparse.ArgumentParser(description="print or refresh provider_routing.only")
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--count", type=int, default=8)
    ap.add_argument("--write", metavar="CONFIG", help="update that config.yaml in place")
    args = ap.parse_args()

    try:
        picks = cheapest(args.model, args.count)
    except Exception as exc:  # network, JSON or shape problem: change nothing
        print("could not read provider prices (%s); config left untouched" % exc)
        return 1
    if not picks:
        print("no priced provider found; config left untouched")
        return 1

    for _price, slug, name, quant in picks:
        print("# %-14s %-22s cache-read $%.4f/M  %s" % (slug, name, _price * 1e6, quant))
    slugs = [p[1] for p in picks]
    print("  only:\n" + "".join("    - %s\n" % s for s in slugs).rstrip("\n"))

    if args.write:
        return write_config(pathlib.Path(os.path.expanduser(args.write)), slugs)
    return 0


if __name__ == "__main__":
    sys.exit(main())
