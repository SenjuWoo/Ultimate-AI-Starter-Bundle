<#
RELEASE verification: the existing mandatory gates, in order, with one verdict.

FAST (`Verify-Fast.ps1`) is for the edit loop. FULL is `Test-Pack.ps1`. This
wrapper is the release path: refresh generated metadata, run the pack gate, and
say plainly whether the tree is publishable. It adds no new checks and never
weakens one.
#>
[CmdletBinding()]
param([string]$PackRoot)
if (-not $PackRoot) {
  $PackRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  if ((Split-Path -Leaf $PackRoot) -eq 'TOOLS') { $PackRoot = Split-Path -Parent $PackRoot }
}
$ErrorActionPreference = 'Stop'
$python = if (Get-Command python -ErrorAction SilentlyContinue) { (Get-Command python).Source } else { $null }
if (-not $python) { Write-Host 'RELEASE: Python is required' -ForegroundColor Red; exit 1 }

& (Join-Path $PackRoot 'TOOLS\Refresh-Release-Metadata.ps1') -PackRoot $PackRoot
if ($LASTEXITCODE -ne 0) { Write-Host 'RELEASE: metadata refresh failed' -ForegroundColor Red; exit 1 }

& (Join-Path $PackRoot 'TESTS\Test-Pack.ps1') -TestPython $python
if ($LASTEXITCODE -ne 0) { Write-Host 'RELEASE: pack gate failed' -ForegroundColor Red; exit 1 }

Write-Host 'RELEASE VERIFY: PASS' -ForegroundColor Green
