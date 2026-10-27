<#
.SYNOPSIS
  Agent/user helper: detect missing Uabs tools and install/repair from pack or GitHub.
#>
[CmdletBinding()]
param(
  [ValidateSet('BundledFirst','OnlineLatest','BundledOnly')]
  [string]$Mode = 'BundledFirst',
  [string[]]$Components = @(),
  [switch]$DiscoverOnly,
  [switch]$NoUpdate
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
$root = Get-UabsPackRoot

Write-UabsStep 'discover_tools'
& powershell -NoProfile -File (Join-Path $PSScriptRoot 'discover_tools.ps1')

if ($DiscoverOnly) { return }

# Decide what to fix
$need = New-Object System.Collections.Generic.List[string]
$cm = [Environment]::GetEnvironmentVariable('CODEBASE_MEMORY_MCP','User')
if (-not $cm) { $cm = $env:CODEBASE_MEMORY_MCP }
if (-not $cm -or -not (Test-Path $cm)) { [void]$need.Add('codebase-memory') }
if (-not (Get-Command headroom -EA SilentlyContinue) -and -not $env:HEADROOM_CMD) { [void]$need.Add('headroom') }

if ($Components.Count -gt 0) { $need = [System.Collections.Generic.List[string]]$Components }

# Common compilers belong here; Skyrim and RE tool repair belongs to their owners.
& (Join-Path $PSScriptRoot 'Install-BuildTools.ps1') -NoUpdate:$NoUpdate -Offline:($Mode -eq 'BundledOnly')
if ($need.Count -eq 0) { Write-UabsOk 'Common tools ready.'; return }

Write-UabsStep "Installing missing: $($need -join ', ')"
$aioArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'INSTALL-AIO.ps1'),'-Mode',$Mode,'-Components',($need -join ','),'-ToolsOnly','-SkipBuildTools')
if ($NoUpdate) { $aioArgs+='-NoToolUpdates' }
& powershell.exe @aioArgs
if ($LASTEXITCODE -ne 0) { throw "Tool repair failed with exit $LASTEXITCODE." }
