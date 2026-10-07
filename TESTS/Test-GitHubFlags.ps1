# Local only. -WhatIf must not call gh. The live probe is an etiquette step,
# not a pack-gate network call.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $PSCommandPath }
    $PackRoot = Split-Path -Parent $here
}
$fail = 0
function Bad([string]$Message) { Write-Host "FAIL $Message"; $script:fail++ }
function Good([string]$Message) { Write-Host "ok   $Message" }

$probe = Join-Path $PackRoot 'TOOLS\Get-GitHubFlags.ps1'
$ps = (Get-Command powershell.exe -ErrorAction Stop).Source
$out = & $ps -NoProfile -ExecutionPolicy Bypass -File $probe -WhatIf 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Bad ('whatif exit ' + $LASTEXITCODE) }
else { Good 'whatif exits 0' }

$needles = @(
    'dependabot/alerts?state=open',
    'code-scanning/alerts?state=open',
    'secret-scanning/alerts?state=open',
    'code-quality/setup',
    'code-quality/findings?state=open',
    'flags=whatif'
)
foreach ($needle in $needles) {
    if ($out.IndexOf($needle) -ge 0) { Good ('whatif names ' + $needle) }
    else { Bad ('whatif missed ' + $needle) }
}

$source = [IO.File]::ReadAllText($probe)
if ($source -match '\.secret\b') { Bad 'probe selects the secret material field' }
else { Good 'probe source has no secret material field' }
if ($source -match 'dismiss') { Bad 'probe dismisses alerts' }
else { Good 'probe does not dismiss alerts' }

if ($fail -gt 0) {
    Write-Host ('GITHUB FLAGS GATE: FAIL (' + $fail + ')')
    exit 1
}
Write-Host 'GITHUB FLAGS GATE: PASS'
exit 0
