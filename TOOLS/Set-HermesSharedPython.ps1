# Keep Hermes terminal Python on the shared user runtime without changing the app engine.
# Uses Hermes' supported terminal.shell_init_files; backups stay in the local state directory.
# Current Hermes builds expose ruamel as hermes_yaml and do not install PyYAML. A failed
# child prints its own error into the installer failure record instead of a generic line.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
if (-not $env:UABS_PYTHON -or -not (Get-UabsHermesExecutable)) { return }
$stateRoot = Get-UabsStateRoot
$hookDir = Join-Path $stateRoot 'hooks'
New-Item -ItemType Directory -Path $hookDir -Force | Out-Null
$shellFile = Join-Path $hookDir 'shared-python.sh'
$shellText = '# Bundle-owned shell init: user Python first; embedded application runtimes remain private.
if [ -n "${UABS_PYTHON:-}" ] && [ -z "${VIRTUAL_ENV:-}" ]; then
  _uabs_python="$UABS_PYTHON"
  if command -v cygpath >/dev/null 2>&1; then _uabs_python=$(cygpath -u "$_uabs_python"); fi
  if [ -x "$_uabs_python" ]; then
    export PATH="${_uabs_python%/*}:$PATH"
    export UV_PYTHON="$UABS_PYTHON" UV_PYTHON_DOWNLOADS=never PYTHONUTF8=1
  fi
  unset _uabs_python
fi
'
[IO.File]::WriteAllText($shellFile, $shellText, (New-Object Text.UTF8Encoding $false))
$oldShell = $env:UABS_SHARED_SHELL; $oldBackup = $env:UABS_SHARED_BACKUP
try {
  $env:UABS_SHARED_SHELL = $shellFile.Replace('\','/')
  $env:UABS_SHARED_BACKUP = Join-Path $stateRoot ('backups\shared-python-shell\' + (Get-Date -Format 'yyyyMMdd-HHmmss-fff'))
  # PyYAML is absent inside Hermes. hermes_yaml's round-trip writer appends one
  # shell path and leaves comments, quoting and every other setting alone.
  $code = 'import copy, os, tempfile
from pathlib import Path
try:
    import yaml
    _pyyaml = True
except ModuleNotFoundError:
    import hermes_yaml
    _pyyaml = False
from hermes_constants import get_default_hermes_root
home = Path(os.environ.get(''HERMES_HOME'') or get_default_hermes_root())
homes = [home] + sorted(p for p in (home / ''profiles'').glob(''*'') if p.is_dir())
shell = os.environ[''UABS_SHARED_SHELL'']
backup = Path(os.environ[''UABS_SHARED_BACKUP''])
changed = 0

def _plain(value):
    if isinstance(value, dict):
        return {key: _plain(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_plain(item) for item in value]
    return value

def _without_shell(doc):
    doc = _plain(doc) if isinstance(doc, dict) else doc
    if not isinstance(doc, dict):
        return doc
    terminal = doc.get(''terminal'')
    if isinstance(terminal, dict):
        files = terminal.get(''shell_init_files'')
        if isinstance(files, list):
            terminal[''shell_init_files''] = [item for item in files if item != shell]
            if not terminal[''shell_init_files'']:
                terminal.pop(''shell_init_files'', None)
        if not terminal:
            doc.pop(''terminal'', None)
    return doc

for folder in homes:
    target = folder / ''config.yaml''
    if not target.is_file():
        continue
    original = target.read_bytes()
    if _pyyaml:
        data = yaml.safe_load(original)
        if not isinstance(data, dict):
            raise RuntimeError(''Hermes config is not a mapping'')
        updated = copy.deepcopy(data)
        terminal = updated.setdefault(''terminal'', {})
        if not isinstance(terminal, dict):
            raise RuntimeError(''Hermes terminal settings are not a mapping'')
        files = terminal.get(''shell_init_files'') or []
        if not isinstance(files, list):
            raise RuntimeError(''Hermes shell init list has an unexpected type'')
        if shell in files:
            continue
        terminal[''shell_init_files''] = [*files, shell]
        payload = yaml.safe_dump(updated, allow_unicode=True, sort_keys=False).encode(''utf-8'')
        if yaml.safe_load(payload) != updated:
            raise RuntimeError(''Hermes config roundtrip changed values'')
    else:
        editor = hermes_yaml.roundtrip_yaml()
        # Drop CR before load. A dump that still contains the source CR, written
        # later in text mode, becomes a blank line for every preserved break.
        logical = original.decode(''utf-8-sig'').replace(''\r\n'', ''\n'').replace(''\r'', ''\n'')
        data = editor.load(logical)
        if not isinstance(data, dict):
            raise RuntimeError(''Hermes config is not a mapping'')
        terminal = data.get(''terminal'')
        if terminal is None:
            terminal = {}
            data[''terminal''] = terminal
        if not isinstance(terminal, dict):
            raise RuntimeError(''Hermes terminal settings are not a mapping'')
        files = terminal.get(''shell_init_files'')
        if files is None:
            files = []
            terminal[''shell_init_files''] = files
        if not isinstance(files, list):
            raise RuntimeError(''Hermes shell init list has an unexpected type'')
        if shell in list(files):
            continue
        files.append(shell)
        from io import StringIO
        buffer = StringIO()
        editor.dump(data, buffer)
        dumped = buffer.getvalue().replace(''\r\n'', ''\n'').replace(''\r'', ''\n'')
        if dumped and not dumped.endswith(''\n''):
            dumped += ''\n''
        newline = ''\r\n'' if b''\r\n'' in original and b''\n'' not in original.replace(b''\r\n'', b'''') else ''\n''
        payload = dumped.replace(''\n'', newline).encode(''utf-8'')
        if _without_shell(hermes_yaml.safe_load(original)) != _without_shell(hermes_yaml.safe_load(payload)):
            raise RuntimeError(''Hermes config roundtrip changed values'')
        updated = data
    backup.mkdir(parents=True, exist_ok=True)
    (backup / ((''default'' if folder == home else folder.name) + ''.yaml'')).write_bytes(original)
    if target.read_bytes() != original:
        raise RuntimeError(''Hermes config changed concurrently; rerun setup'')
    temp = target.with_name(target.name + ''.uabs-shared-tmp'')
    temp.write_bytes(payload)
    try:
        os.replace(temp, target)
        if _pyyaml:
            ok = yaml.safe_load(target.read_bytes()) == updated
        else:
            seen = hermes_yaml.safe_load(target.read_bytes())
            seq = []
            if isinstance(seen, dict) and isinstance(seen.get(''terminal''), dict):
                seq = seen[''terminal''].get(''shell_init_files'') or []
            ok = shell in list(seq)
        if not ok:
            target.write_bytes(original)
            raise RuntimeError(''Hermes config verification failed; original restored'')
    finally:
        if temp.exists():
            temp.unlink()
    changed += 1
print(''Hermes shared Python shell init: '' + str(changed) + '' profiles updated; other settings preserved.'')
'
  Invoke-UabsHermesPython -PythonArgs @('-c',$code)
  if ($LASTEXITCODE -ne 0) {
    $detail = [string]$script:UabsHermesPythonError
    if ($detail.Length -gt 4000) { $detail = $detail.Substring($detail.Length - 4000) }
    if (-not $detail) { $detail = 'Python exited without an error message. The installer transcript has the child output.' }
    throw ("Hermes shared-Python shell setup failed.`r`n" + $detail)
  }
} finally {
  $env:UABS_SHARED_SHELL = $oldShell; $env:UABS_SHARED_BACKUP = $oldBackup
}
