# Select one user-owned Python for agents and uv. Does not delete any runtime.
# -Apply writes only PATH and the documented runtime settings, with rollback.
[CmdletBinding()]
param([string]$Python, [switch]$Apply, [ValidateSet('User','Process')][string]$Scope = 'User')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
if (-not $Python) {
  # Re-select the user's working PATH after an upgrade, even if the old binding
  # points at an interpreter they removed. This never downloads a replacement.
  $previousSelection = $env:UABS_PYTHON; $selectionPath = $env:Path
  try {
    if ($Scope -eq 'User') { Refresh-ProcessPath }
    $env:UABS_PYTHON = $null; $Python = Get-UabsPythonExecutable
  } finally { $env:UABS_PYTHON = $previousSelection; $env:Path = $selectionPath }
}
if (-not $Python) { throw 'No runnable Python found. Install one shared base Python first.' }
$raw = @(Get-UabsNativeStdout -Exe $Python -CmdArgs @('-I','-c','import json,sys;print(json.dumps(dict(exe=sys.executable,base=sys.base_prefix,prefix=sys.prefix,version=sys.version.split()[0])))'))
if ($LASTEXITCODE -ne 0 -or -not $raw.Count) { throw 'Selected Python does not run.' }
$info = ($raw -join '') | ConvertFrom-Json
if ($info.base -cne $info.prefix -or (Test-UabsPrivateRuntimePath $info.exe)) { throw 'Choose a base Python installation, not an agent or tool virtual environment.' }
$resolved = [IO.Path]::GetFullPath([string]$info.exe)
if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw 'Resolved Python executable is missing.' }
Write-Host ('Shared Python candidate: ' + $info.version + ' at ' + $resolved)
if (-not $Apply) { Write-Host 'Check only. Use -Apply to configure PATH and disable extra uv runtime downloads.'; return }
# Preserve the unrelated PATH entries and deduplicate only exact directory names.
$old = @{}; $oldProcess = @{}
foreach ($key in @('Path','UABS_PYTHON','UV_PYTHON','UV_PYTHON_DOWNLOADS','PYTHONUTF8','PYTHON_MANAGER_AUTOMATIC_INSTALL')) {
  $old[$key] = [Environment]::GetEnvironmentVariable($key, $Scope)
  $oldProcess[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
$base = Split-Path -Parent $resolved
# Keep a working launcher/manager alias so future user upgrades remain the default.
$probePath = $env:Path; $alreadyDefault = $false
try {
  if ($Scope -eq 'User') { Refresh-ProcessPath }
  $current = @(Get-UabsNativeStdout -Exe 'python' -CmdArgs @('-I','-c','import json,sys;print(json.dumps(sys.executable))'))
  if ($LASTEXITCODE -eq 0 -and $current.Count) { $alreadyDefault = ([string]($current[-1] | ConvertFrom-Json) -ieq $resolved) }
} finally { $env:Path = $probePath }
$dirs = @()
if (-not $alreadyDefault) {
  $dirs += $base
  $scripts = Join-Path $base 'Scripts'
  if (Test-Path -LiteralPath $scripts -PathType Container) { $dirs += $scripts }
}
$dirs += @(([string]$old['Path']) -split ';' | Where-Object { $_ })
$seen = @{}; $unique = @()
foreach ($dir in $dirs) {
  $key = [Environment]::ExpandEnvironmentVariables($dir).TrimEnd('\').ToLowerInvariant()
  if (-not $seen.ContainsKey($key)) { $seen[$key] = $true; $unique += $dir }
}
$desired = @{ Path=($unique -join ';'); UABS_PYTHON=$resolved; UV_PYTHON=$resolved; UV_PYTHON_DOWNLOADS='never'; PYTHONUTF8='1'; PYTHON_MANAGER_AUTOMATIC_INSTALL='false' }
# Backup is local state, never a portable provider template or repository file.
$backup = $null
if ($Scope -eq 'User') {
  $backupDir = Join-Path (Get-UabsStateRoot) 'backups\shared-python'
  New-Item -ItemType Directory -Force -Path $backupDir | Out-Null
  $backup = Join-Path $backupDir ((Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.json')
  [IO.File]::WriteAllText($backup, ($old | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
}
try {
  foreach ($key in $desired.Keys) { [Environment]::SetEnvironmentVariable($key, $desired[$key], $Scope) }
  if ($Scope -eq 'User') { Refresh-ProcessPath }
  foreach ($key in @('UABS_PYTHON','UV_PYTHON','UV_PYTHON_DOWNLOADS','PYTHONUTF8','PYTHON_MANAGER_AUTOMATIC_INSTALL')) {
    [Environment]::SetEnvironmentVariable($key, $desired[$key], 'Process')
  }
  $got = @(Get-UabsNativeStdout -Exe 'python' -CmdArgs @('-I','-c','import json,sys;print(json.dumps(sys.executable))'))
  if ($LASTEXITCODE -eq 0 -and $got.Count) { $got[-1] = [string]($got[-1] | ConvertFrom-Json) }
  if ($LASTEXITCODE -ne 0 -or $got[-1] -ine $resolved) { throw 'PATH verification failed; prior environment will be restored.' }
  foreach ($key in $desired.Keys) {
    if ([Environment]::GetEnvironmentVariable($key, $Scope) -cne $desired[$key]) { throw ('Environment verification failed: ' + $key) }
  }
} catch {
  foreach ($key in $old.Keys) {
    [Environment]::SetEnvironmentVariable($key, $old[$key], $Scope)
    [Environment]::SetEnvironmentVariable($key, $oldProcess[$key], 'Process')
  }
  throw
}
if ($Scope -eq 'User') { & (Join-Path $PSScriptRoot 'Set-HermesSharedPython.ps1') }
Write-Host ('Configured shared Python ' + $info.version + '; uv runtime downloads disabled. Backup: ' + $backup)
Write-Host 'Reopen agent apps to inherit the new environment. Tool dependency environments stay isolated.'
