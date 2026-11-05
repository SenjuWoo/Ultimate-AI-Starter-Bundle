<#
Regenerate and verify every generated release artifact in one step.

A stale MANIFEST.json is the most common red CI gate in this repo: it is
generated from the working tree, and a local install or test run can add an
archive after it was written. This script is the one command to run before a
commit; the pre-push hook calls it.
#>
[CmdletBinding()]
param([string]$PackRoot)
if (-not $PackRoot) {
  $PackRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  if ((Split-Path -Leaf $PackRoot) -eq 'TOOLS') { $PackRoot = Split-Path -Parent $PackRoot }
}

$ErrorActionPreference = 'Stop'
$failed = $false
Push-Location $PackRoot
try {
  function Invoke-MetadataStep([string]$Name, [string[]]$Arguments) {
    Write-Host "==> $Name"
    & python @Arguments
    if ($LASTEXITCODE -ne 0) {
      Write-Host "FAILED: $Name" -ForegroundColor Red
      $script:failed = $true
    }
  }

  # Archives first: a generator or install run writes them, and the manifest
  # must hash the tree that exists after that run.
  Invoke-MetadataStep 'Preamble archive' @('TOOLS\generate_preamble_history.py')
  Invoke-MetadataStep 'MANIFEST' @('TOOLS\generate_manifest.py', '.')
  Invoke-MetadataStep 'MANIFEST verify' @('.github\scripts\verify_manifest.py')
  Invoke-MetadataStep 'Version strings' @('.github\scripts\check_versions.py')
  Invoke-MetadataStep 'Docs gate' @('TOOLS\verify_docs.py')
} finally {
  Pop-Location
}

if ($failed) { exit 1 }
Write-Host 'RELEASE METADATA: PASS' -ForegroundColor Green
