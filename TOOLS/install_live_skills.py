"""Compare canonical skills with the provider homes; never write them.

    python install_live_skills.py <canonical-dir> --check

Counts describe byte differences. Skills a native plugin delivers to a provider
(install-state.json), ponytail copies parked by its off/auto mode, and Python
bytecode are not expected in a skills folder, so they are not counted as drift.
The ownership-aware verdict is TOOLS/Test-Installed-State.ps1. For writes, use
INSTALL-AIO.ps1 with explicit -Providers and the skills-only flags shown when a
write request is refused. This helper never runs it.
"""
import argparse
import io
import json
import os
import stat
import sys

sys.dont_write_bytecode = True  # Read-only checks must not create import caches.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from fanout_providers import SCOPED  # noqa: E402  single source of truth

# Keyed by the same provider names fanout_providers.PROVIDERS uses, so SCOPED
# means the same thing in both tools. Hermes was missing here until v7.2.1,
# which is why the bundle's most-used provider silently drifted three whole
# skills behind canonical while the other four reported "up to date".
HOMES = {
    'Claude': r'%USERPROFILE%\.claude\skills',
    'Grok': r'%USERPROFILE%\.grok\skills',
    'Codex': r'%USERPROFILE%\.agents\skills',
    'Kimi': r'%USERPROFILE%\.kimi-code\skills',
    'Hermes': r'%LOCALAPPDATA%\hermes\skills',
    'Antigravity': r'%USERPROFILE%\.gemini\config\skills',
}

# The installer's registry of skills the owner keeps on purpose (an
# independently updated copy). Measured 2026-10-20: this tool ignored it and
# merged the pack's Impeccable 4.1.3 over a preserved 4.3.1 in three apps, and
# the next START-HERE run then refused to continue ("override changed").
OVERRIDES = os.path.expandvars(r'%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\skill-overrides.json')


def preserved_skills(provider):
    """Names the owner preserves for this provider; never written here."""
    try:
        with io.open(OVERRIDES, encoding='utf-8-sig') as fh:
            doc = json.load(fh)
    except FileNotFoundError:
        return set()
    # A registry that exists but cannot be read must stop the sync, not
    # silently turn into "nothing is preserved".
    return set((doc.get('providers') or {}).get(provider) or {})


PACK_PLUGINS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                            'BUNDLED-TOOLS', 'plugins')


def _state_json(*parts):
    path = os.path.join(os.path.expandvars(r'%LOCALAPPDATA%\Ultimate-AI-Starter-Bundle'), *parts)
    try:
        with io.open(path, encoding='utf-8-sig') as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return {}


def plugin_owned_skills(provider):
    """Skills a native plugin delivers to this provider; no copy is expected.

    Without this, every plugin-delivered skill read as "+new" drift (Claude +95
    files on a healthy install), which buried any real difference.
    """
    owned = set()
    plugins = ((_state_json('install-state.json').get('native_plugins') or {})
               .get(provider) or {}).get('plugins') or {}
    for plugin_id, entry in plugins.items():
        if not isinstance(entry, dict) or not entry.get('native'):
            continue
        owned |= set(entry.get('owned') or []) | set(entry.get('deduped') or [])
        skills_dir = os.path.join(PACK_PLUGINS, plugin_id, 'skills')
        if os.path.isdir(skills_dir):
            owned |= {d for d in os.listdir(skills_dir)
                      if os.path.isfile(os.path.join(skills_dir, d, 'SKILL.md'))}
    return owned


def ponytail_parked():
    """off and auto park ponytail's copied skills on purpose (TOOLS/ponytail_mode.py)."""
    return _state_json('ponytail-mode', 'state.json').get('mode') in ('off', 'auto')


def same(a, b):
    try:
        with open(a, 'rb') as fa, open(b, 'rb') as fb:
            return fa.read() == fb.read()
    except OSError:
        return False


def is_reparse(p):
    """True for a Windows junction or symlink, without following it."""
    try:
        return bool(os.lstat(p).st_file_attributes & stat.FILE_ATTRIBUTE_REPARSE_POINT)
    except (OSError, AttributeError):
        return False


WRITE_GUIDANCE = (r'.\INSTALL-AIO.ps1 -Providers {providers} -SkillsOnly '
                  '-SkipNativePlugins -SkipStarterSettings -SkipPreamble -SkipCleanup')


def install(canon, dest, provider, check, notes):
    """Retain the legacy comparison API, but refuse writes before any I/O."""
    if not check:
        raise ValueError('This legacy helper is check-only. Use ' +
                         WRITE_GUIDANCE.format(providers=provider))
    added = changed = kept = withheld = 0
    codex_sys = os.path.expandvars(r'%USERPROFILE%\.codex\skills\.system')
    keep = preserved_skills(provider)
    by_plugin = plugin_owned_skills(provider)
    parked = ponytail_parked()
    from_plugin = parked_count = 0
    skills = [d for d in sorted(os.listdir(canon))
              if os.path.isdir(os.path.join(canon, d))
              and os.path.exists(os.path.join(canon, d, 'SKILL.md'))]
    for sk in skills:
        if sk in SCOPED and provider not in SCOPED[sk]:
            withheld += 1
            continue
        if sk in by_plugin:
            withheld += 1
            from_plugin += 1
            continue
        if parked and sk.startswith('ponytail'):
            withheld += 1
            parked_count += 1
            continue
        if sk in keep:
            notes.append('preserved local override (skill-overrides.json): %s' % sk)
            withheld += 1
            continue
        if provider == 'Codex' and os.path.isfile(os.path.join(codex_sys, sk, 'SKILL.md')):
            withheld += 1
            continue
        src_dir = os.path.join(canon, sk)
        dst_dir = os.path.join(dest, sk)
        if is_reparse(dst_dir):
            notes.append('%s junction: %s' % (
                'DANGLING' if not os.path.isdir(dst_dir) else 'live', sk))
        for dp, dirs, fs in os.walk(src_dir):
            # Local bytecode is gitignored and never installed: not drift.
            dirs[:] = [d for d in dirs if d != '__pycache__']
            for f in fs:
                if f.endswith('.pyc'):
                    continue
                sp = os.path.join(dp, f)
                op = os.path.join(dst_dir, os.path.relpath(sp, src_dir))
                if not os.path.exists(op):
                    added += 1
                elif same(sp, op):
                    kept += 1
                    continue
                else:
                    changed += 1

    if from_plugin:
        notes.append('delivered by a native plugin, no copy expected: %d skill(s)' % from_plugin)
    if parked_count:
        notes.append('ponytail parked by its off/auto mode: %d skill(s)' % parked_count)
    return added, changed, kept, len(skills) - withheld, withheld


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('canonical_dir')
    parser.add_argument('--check', action='store_true', help='compare only; never write')
    args = parser.parse_args()
    if not args.check:
        parser.error('This legacy helper is check-only; pass --check. For writes '
                     '(select providers explicitly), use ' +
                     WRITE_GUIDANCE.format(providers='Claude'))

    for provider, raw in HOMES.items():
        dest = os.path.expandvars(raw)
        if not os.path.isdir(dest):
            print('%-10s (not installed: %s)' % (provider, dest))
            continue
        existing = len([d for d in os.listdir(dest)
                        if os.path.isdir(os.path.join(dest, d))])
        notes = []
        a, c, k, n, w = install(args.canonical_dir, dest, provider, True, notes)
        held = ', '.join(sorted(s for s, p in SCOPED.items() if provider not in p))
        if w and held:
            notes.insert(0, 'withheld (scoped elsewhere): %s' % held)
        print('%-8s %3d skills present -> canonical %d | +%d new, %d updated, %d unchanged  [CHECK ONLY]'
              % (provider, existing, n, a, c, k))
        for msg in notes:
            print('           ! %s' % msg)


if __name__ == '__main__':
    main()
