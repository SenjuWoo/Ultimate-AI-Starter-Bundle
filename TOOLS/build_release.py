#!/usr/bin/env python3
"""Deterministic UTF-8-safe release ZIP builder for Ultimate AI Starter Bundle.

Builds Core and Full-Offline archives from the source manifest, never from an
unrestricted filesystem walk that could include ignored personal settings.
Each ZIP is CRC-tested, extracted under a path containing spaces + Unicode, and
hashed with SHA256 before success is reported.
"""
from __future__ import annotations
import argparse, hashlib, json, os, re, shutil, tempfile, zipfile
from pathlib import Path, PurePosixPath

FIXED_TIME=(2026,8,20,0,0,0)
# The archive prefix follows VERSION.txt. It was restated in four places, so a
# release bump could ship v7.8.0-named archives containing a 7.9.0 tree.
def _pack_version(root:Path)->str:
    return (root/'VERSION.txt').read_text(encoding='utf-8-sig').strip().lstrip('vV')
def _prefix(root:Path)->str:
    return 'Ultimate-AI-Starter-Bundle-v'+_pack_version(root)
EXCLUDE_PARTS={'.git','.worktrees','.venv','venv','__pycache__','node_modules','.pytest_cache','.mypy_cache','.ruff_cache','.tox','.nox','htmlcov','cache','dist','artifacts'}
EXCLUDE_SUFFIXES={'.pyc','.pyo','.log'}
EXCLUDE_NAMES={'INSTALLATION.json','.DS_Store','.coverage','coverage.xml','config.MAINTAINER.yaml'}
# Companion products (Skyrim Forge, Reverse THIS!) are released by their owners and
# never committed here. TOOLS/Get-Companions.ps1 fetches each latest release, verifies
# it and lists it in companions.json; Full-Offline carries exactly those files, Core
# carries none and the installer downloads what an enabled pack needs.
COMPANIONS=PurePosixPath('BUNDLED-TOOLS/offline/companions.json')
def companions(root:Path)->list[tuple[Path,Path]]:
    index=root/COMPANIONS
    if not index.is_file(): return []
    out=[(index,Path(COMPANIONS))]
    for row in json.loads(index.read_text(encoding='utf-8-sig')).get('companions',[]):
        name=str(row.get('asset',''))
        if not re.fullmatch(r'[A-Za-z0-9._-]+\.zip',name): raise RuntimeError(f'unsafe companion asset name: {name!r}')
        rel=Path('BUNDLED-TOOLS/offline')/name; p=root/rel
        if not p.is_file() or hashlib.sha256(p.read_bytes()).hexdigest()!=str(row.get('sha256','')).lower():
            raise RuntimeError(f'companion {name} is missing or differs from companions.json')
        out.append((p,rel))
    return out

# Product ZIPs are not repository exports. Templates/references are intentional product inputs.
PRODUCT_ROOT_FILES={'START-HERE.bat','START-HERE.txt','INSTALL-AIO.ps1','INSTALL-REMOTE.ps1',
    'INSTALL-REMOTE.bat','BOOTSTRAP.txt','AIO-GUIDE.md','README.md','README-CORE.txt','LICENSE',
    'VERSION.txt','MANIFEST.json','.cbmignore','.ignore','GROK-MCP-TROUBLESHOOTING.md',
    'WHICH-AI-SHOULD-I-USE-FOR-SKYRIM.md','WINDOWS-PATH-MAP.md'}
PRODUCT_DIRS={'_CANONICAL-SKILLS','1-TAILORED-PROVIDER-TREES','0-UNRESTRAINT-PACKS',
    '2-OPTIONAL-MANUAL-OTHER-GAMES-MEGA-PACK','3-PREAMBLES','COPY-TO-YOUR-WORKSPACE',
    'BUNDLED-TOOLS','TOOLS','docs','PROMPTS','assets'}

def product_path(rel:Path)->bool:
    if len(rel.parts)==1:
        return rel.name in PRODUCT_ROOT_FILES
    if rel.parts[0] not in PRODUCT_DIRS:
        return False
    template=any(part.casefold() in {'templates','_project-template'} for part in rel.parts)
    development=rel.stem.casefold() in {'state','plan','decisions','current','validation','workspace_ownership','project_ownership','ownership'}
    return template or not ((development or 'changelog' in rel.stem.casefold()) and rel.suffix.casefold() in {'.md','.txt','.rst'})

def excluded(rel:Path)->bool:
    if any(part in EXCLUDE_PARTS for part in rel.parts): return True
    if rel.as_posix() == '.git': return True
    if rel.name in EXCLUDE_NAMES or rel.suffix.lower() in EXCLUDE_SUFFIXES: return True
    if rel.name.startswith('Ultimate-AI-Starter-Bundle-v') and rel.suffix.lower()=='.zip': return True
    return False

CORE_NOTE=(
    'Core release: the vendored third-party offline payloads are omitted and\n'
    'installed from source or downloaded when absent. Full-Offline carries\n'
    'archive/wheel snapshots; uncached runtimes and dependencies may need network.\n'
    '\n'
    'Skyrim Forge and Reverse THIS! are released by their owners: the installer\n'
    'downloads each latest release (SHA-256 checked) only for an enabled pack.\n'
).encode('utf-8')

def files(root:Path, core:bool):
    # The tracked-file manifest is the release allowlist, including when built
    # from an extracted release with no Git checkout. Ignore unrecorded files.
    manifest=json.loads((root/'MANIFEST.json').read_text(encoding='utf-8'))
    rows=manifest.get('files',[]) if isinstance(manifest,dict) else manifest
    paths=[str(row['path']) for row in rows]+['MANIFEST.json']
    if len(paths)!=len({p.casefold() for p in paths}): raise RuntimeError('duplicate source manifest path')
    checked_ancestors=set()
    for name in sorted(paths, key=lambda x:(x.lower(),x)):
        rel=Path(name)
        p=root/rel
        if rel.is_absolute() or '..' in rel.parts or '\\' in name or ':' in name or not p.resolve().is_relative_to(root.resolve()):
            raise RuntimeError(f'unsafe source manifest path: {name}')
        for ancestor in (p,*p.parents):
            if ancestor == root.parent: break
            if ancestor in checked_ancestors: break
            if ancestor.is_symlink() or getattr(ancestor,'is_junction',lambda:False)():
                raise RuntimeError(f'linked source manifest path: {name}')
            checked_ancestors.add(ancestor)
        if not p.is_file(): raise RuntimeError(f'source manifest file missing: {name}')
        if excluded(rel) or not product_path(rel): continue
        if not core and rel.as_posix()=="README-CORE.txt": continue
        # Core drops every vendored payload, Forge included; the installer
        # downloads and verifies what an enabled pack needs.
        if core and len(rel.parts)>=2 and rel.parts[0]=='BUNDLED-TOOLS' and rel.parts[1]=='offline':
            continue
        yield p,rel
    if not core:
        yield from companions(root)

def _row(rel:Path,data:bytes)->dict[str,object]:
    return {'path':rel.as_posix(),'size':len(data),'sha256':hashlib.sha256(data).hexdigest()}

def _core_offline_manifest_bytes(root:Path)->bytes:
    # BUNDLED-TOOLS/OFFLINE-MANIFEST.json inventories the vendored payloads.
    # Core carries none of them. Shipping the Full inventory unchanged made the
    # Core archive describe six files it does not contain -- and the release
    # contract run FROM the extracted Core failed on exactly that, while the
    # same suite passed on Full. Rewrite it to describe Core.
    m=json.loads((root/'BUNDLED-TOOLS'/'OFFLINE-MANIFEST.json').read_text(encoding='utf-8-sig'))
    m['assets']=[]
    m['variant']='Core'
    m['note']=('Core ships no vendored payloads; the installer downloads each component '
               'when absent or builds vendored source. Full-Offline carries the '
               'archive/wheel snapshots; uncached runtimes/dependencies may need network.')
    return (json.dumps(m,indent=2)+'\n').encode('utf-8')

def _core_overrides(root:Path)->dict[str,bytes]:
    """Files whose Core bytes differ from the source tree's."""
    return {'BUNDLED-TOOLS/OFFLINE-MANIFEST.json':_core_offline_manifest_bytes(root)}

def _delivery_manifest_bytes(root:Path,core:bool)->bytes:
    # Core intentionally omits most offline payloads. Generate its manifest
    # from the exact bytes that the Core archive will contain instead of
    # copying the Full tree manifest and creating false MISSING failures.
    overrides=_core_overrides(root) if core else {}
    rows=[]
    for p,rel in files(root,core):
        if rel.as_posix()=='MANIFEST.json':
            continue
        # The note is generated, not copied. A tracked copy must not become a
        # second archive entry or a second manifest row.
        if core and rel.as_posix()=='README-CORE.txt':
            rows.append(_row(rel,CORE_NOTE))
            continue
        rows.append(_row(rel,overrides.get(rel.as_posix(),None) or p.read_bytes()))
    if core and not any(row['path']=='README-CORE.txt' for row in rows):
        rows.append(_row(Path('README-CORE.txt'),CORE_NOTE))
    rows.sort(key=lambda r:str(r['path']))
    return (json.dumps(rows,indent=1)+'\n').encode('utf-8')

def _core_manifest_bytes(root:Path)->bytes:
    return _delivery_manifest_bytes(root,True)

def _archive_mode(rel:Path)->int:
    # ZIPs created on Windows do not preserve POSIX execute bits; encode the
    # few shipped POSIX scripts explicitly.
    if rel.parent.name == 'scripts' and rel.name in ('task-start', 'task-done', 'task-brief', 'sdd-workspace', 'review-package'):
        return 0o100755
    return 0o100644

def _write(z:zipfile.ZipFile,prefix:str,rel:Path,data:bytes)->None:
    zi=zipfile.ZipInfo(str(PurePosixPath(prefix)/PurePosixPath(rel.as_posix())),FIXED_TIME)
    zi.compress_type=zipfile.ZIP_DEFLATED; zi.flag_bits |= 0x800
    zi.create_system=3
    zi.external_attr=(_archive_mode(rel) & 0xFFFF)<<16
    z.writestr(zi,data,compress_type=zipfile.ZIP_DEFLATED,compresslevel=9)

def build(root:Path,out:Path,core:bool)->None:
    prefix=_prefix(root)
    delivery_manifest=_delivery_manifest_bytes(root,core)
    overrides=_core_overrides(root) if core else {}
    with zipfile.ZipFile(out,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as z:
        wrote_note=False
        for p,rel in files(root,core):
            if core and rel.as_posix()=='README-CORE.txt':
                _write(z,prefix,rel,CORE_NOTE)
                wrote_note=True
            elif rel.as_posix()=='MANIFEST.json':
                _write(z,prefix,rel,delivery_manifest)
            elif rel.as_posix() in overrides:
                _write(z,prefix,rel,overrides[rel.as_posix()])
            else:
                _write(z,prefix,rel,p.read_bytes())
        if core and not wrote_note:
            _write(z,prefix,Path('README-CORE.txt'),CORE_NOTE)

def verify(path:Path,root:Path)->None:
    with zipfile.ZipFile(path) as z:
        bad=z.testzip()
        if bad: raise RuntimeError(f'ZIP CRC failure: {bad}')
        names=z.namelist()
        forbidden=('/.git/','/__pycache__/','/.venv/','/node_modules/')
        if any(any(x in '/'+n for x in forbidden) for n in names): raise RuntimeError('forbidden developer state in ZIP')
        with tempfile.TemporaryDirectory(prefix='UABS Unicode Ω Space ') as td:
            z.extractall(td)
            top=Path(td)/_prefix(root)
            for rel in ('START-HERE.bat','INSTALL-AIO.ps1','BUNDLED-TOOLS/CATALOG.json','VERSION.txt'):
                if not (top/rel).is_file(): raise RuntimeError(f'extracted required file missing: {rel}')
            if (top/'BUNDLED-TOOLS'/'skyrim-forge').exists():
                raise RuntimeError('archive still carries vendored Forge source')
            # Full-Offline carries exactly the verified companions the build fetched; Core none.
            core_variant=json.loads((top/'BUNDLED-TOOLS/OFFLINE-MANIFEST.json').read_text(encoding='utf-8-sig')).get('variant')=='Core'
            shipped=companions(top)
            if core_variant and shipped:
                raise RuntimeError('Core archive carries companion payloads')
            if not core_variant and [rel for _,rel in shipped]!=[rel for _,rel in companions(root)]:
                raise RuntimeError('Full-Offline companions differ from the fetched companions.json')
            if (top/'VERSION.txt').read_text(encoding='utf-8-sig').strip().lstrip('vV')!=_pack_version(root):
                raise RuntimeError('extracted VERSION.txt does not match the archive name')
            manifest=top/'MANIFEST.json'
            if not manifest.is_file(): raise RuntimeError('extracted MANIFEST.json missing')
            rows=json.loads(manifest.read_text(encoding='utf-8'))
            rows=rows.get('files',[]) if isinstance(rows,dict) else rows
            expected={str(PurePosixPath(_prefix(root))/str(row['path'])) for row in rows}
            expected.add(_prefix(root)+'/MANIFEST.json')
            if len(names)!=len(set(names)) or set(names)!=expected:
                raise RuntimeError('archive entries differ from its manifest')
            for row in rows:
                rel=Path(str(row['path']))
                target=top/rel
                if not target.is_file(): raise RuntimeError(f'manifest missing after extraction: {rel.as_posix()}')
                data=target.read_bytes()
                if len(data)!=int(row.get('size',-1)) or hashlib.sha256(data).hexdigest()!=row.get('sha256'):
                    raise RuntimeError(f'manifest mismatch after extraction: {rel.as_posix()}')

def sha256(path:Path)->str:
    h=hashlib.sha256()
    with path.open('rb') as f:
        for b in iter(lambda:f.read(1024*1024),b''): h.update(b)
    return h.hexdigest()

def main()->int:
    ap=argparse.ArgumentParser(); ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parent.parent); ap.add_argument('--outdir',type=Path,default=Path.cwd())
    mode=ap.add_mutually_exclusive_group(); mode.add_argument('--core-only',action='store_true'); mode.add_argument('--full-only',action='store_true')
    # Releases pass this: a Full-Offline without the companions would install nothing offline.
    ap.add_argument('--require-companions',action='store_true')
    a=ap.parse_args(); root=a.root.resolve(); outdir=a.outdir.resolve(); outdir.mkdir(parents=True,exist_ok=True)
    if a.require_companions and not a.core_only and len(companions(root))<2:
        raise SystemExit('Full-Offline needs the fetched companions: run TOOLS/Get-Companions.ps1 first')
    outputs=[]
    variants=(('Core',True),) if a.core_only else ((('Full-Offline',False),) if a.full_only else (('Core',True),('Full-Offline',False)))
    for label,core in variants:
        out=outdir/f'{_prefix(root)}-{label}.zip'
        build(root,out,core); verify(out,root); digest=sha256(out); (out.with_suffix(out.suffix+'.sha256')).write_text(f'{digest}  {out.name}\n',encoding='ascii'); outputs.append((out,digest))
    for p,d in outputs: print(f'PASS {p.name} sha256={d} bytes={p.stat().st_size}')
    return 0
if __name__=='__main__': raise SystemExit(main())
