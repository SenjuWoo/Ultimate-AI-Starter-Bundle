# Keep Hermes terminal Python on the shared user runtime without changing the app engine.
# Uses Hermes' supported terminal.shell_init_files; backups stay in the local state directory.
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
  $code = 'import copy,os,tempfile
from pathlib import Path
import yaml
from hermes_constants import get_default_hermes_root
home=Path(os.environ.get(''HERMES_HOME'') or get_default_hermes_root())
homes=[home]+sorted(p for p in (home/''profiles'').glob(''*'') if p.is_dir())
shell=os.environ[''UABS_SHARED_SHELL'']; backup=Path(os.environ[''UABS_SHARED_BACKUP''])
changed=0
for folder in homes:
    target=folder/''config.yaml''
    if not target.is_file(): continue
    original=target.read_bytes(); data=yaml.safe_load(original)
    if not isinstance(data,dict): raise RuntimeError(''Hermes config is not a mapping'')
    updated=copy.deepcopy(data); terminal=updated.setdefault(''terminal'',{})
    if not isinstance(terminal,dict): raise RuntimeError(''Hermes terminal settings are not a mapping'')
    files=terminal.get(''shell_init_files'') or []
    if not isinstance(files,list): raise RuntimeError(''Hermes shell init list has an unexpected type'')
    if shell in files: continue
    terminal[''shell_init_files'']=[*files,shell]
    payload=yaml.safe_dump(updated,allow_unicode=True,sort_keys=False).encode(''utf-8'')
    if yaml.safe_load(payload)!=updated: raise RuntimeError(''Hermes config roundtrip changed values'')
    backup.mkdir(parents=True,exist_ok=True)
    (backup/((''default'' if folder==home else folder.name)+''.yaml'')).write_bytes(original)
    if target.read_bytes()!=original: raise RuntimeError(''Hermes config changed concurrently; rerun setup'')
    temp=target.with_name(target.name+''.uabs-shared-tmp'')
    temp.write_bytes(payload)
    try:
        os.replace(temp,target)
        if yaml.safe_load(target.read_bytes())!=updated:
            target.write_bytes(original)
            raise RuntimeError(''Hermes config verification failed; original restored'')
    finally:
        if temp.exists(): temp.unlink()
    changed+=1
print(''Hermes shared Python shell init: ''+str(changed)+'' profiles updated; other settings preserved.'')
'
  Invoke-UabsHermesPython -PythonArgs @('-c',$code)
  if ($LASTEXITCODE -ne 0) { throw 'Hermes shared-Python shell setup failed; inspect its exact error.' }
} finally {
  $env:UABS_SHARED_SHELL = $oldShell; $env:UABS_SHARED_BACKUP = $oldBackup
}
