# Gate for the external-install version probes in UABS-Common.ps1: the
# installer decides "update / keep / never downgrade" from these, so a wrong
# answer either churns a user's tool every run or blocks the installer.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-version-probes-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Force -Path $fixture | Out-Null

  # Dotted compare: missing segments are zero, never a string compare.
  Assert ((Compare-UabsDottedVersion '2.0.5' '1.9.0') -eq 1) '2.0.5 must be newer than 1.9.0'
  Assert ((Compare-UabsDottedVersion '1.9' '1.9.0') -eq 0) '1.9 must equal 1.9.0'
  Assert ((Compare-UabsDottedVersion '1.10.0' '1.9.9') -eq 1) '1.10.0 must be newer than 1.9.9'
  Assert ($null -eq (Compare-UabsDottedVersion '' '1.0.0')) 'an unknown version must compare as unknown'

  # Folder-name version, then the stamp an in-place update writes: without the
  # stamp the old folder name made every run "update" the toolkit again.
  $root = Join-Path $fixture 'spookys-automod-toolkit-v1.11.2\spookys-automod-toolkit'
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  Assert ((Get-UabsPathVersion $root) -eq '1.11.2') 'version not read from the parent folder name'
  [IO.File]::WriteAllText((Join-Path $root '.uabs-version'), '1.12.0')
  Assert ((Get-UabsPathVersion $root) -eq '1.12.0') 'the update stamp does not win over the stale folder name'
  [IO.File]::WriteAllText((Join-Path $root '.uabs-version'), 'garbage')
  Assert ((Get-UabsPathVersion $root) -eq '1.11.2') 'a malformed stamp must fall back to the folder name'

  # Process probe: reads stdout, and a tool that never exits cannot hang the install.
  $ok = Join-Path $fixture 'tool-ok.cmd'
  [IO.File]::WriteAllText($ok, "@echo off`r`necho tool v3.4.5`r`n")
  Assert ((Get-UabsProcessVersion $ok) -eq '3.4.5') 'version not read from --version output'
  # Waits on stdin like an MCP server that ignores --version; closed stdin ends it.
  $stdin = Join-Path $fixture 'tool-stdin.cmd'
  [IO.File]::WriteAllText($stdin, "@echo off`r`nset /p x=`r`necho got %x%`r`n")
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $v = Get-UabsProcessVersion $stdin -TimeoutMs 5000
  Assert ($null -eq $v -and $sw.Elapsed.TotalSeconds -lt 4) 'a stdin-reading tool blocked the probe'
  $hang = Join-Path $fixture 'tool-hang.cmd'
  [IO.File]::WriteAllText($hang, "@echo off`r`nping -n 5 127.0.0.1 >nul`r`necho tool 9.9.9`r`n")
  $sw.Restart()
  $v = Get-UabsProcessVersion $hang -TimeoutMs 1500
  Assert ($null -eq $v -and $sw.Elapsed.TotalSeconds -lt 6) 'a hung tool was not cut off by the timeout'
  Assert ($null -eq (Get-UabsProcessVersion (Join-Path $fixture 'missing.exe'))) 'a missing binary must be unknown'
} finally {
  Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host 'VERSION PROBES GATE: PASS'
