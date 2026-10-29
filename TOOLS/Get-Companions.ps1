# Fetch and verify the latest Skyrim Forge and Reverse THIS! releases for CI and Full-Offline.
# Each companion with CATALOG install 'latest-release' lands in BUNDLED-TOOLS\offline,
# listed in companions.json. release.yml runs this before building Full-Offline, and CI runs it
# before the release contracts, so both test what the owners released last. Every
# archive is verified (floor, exact name, GitHub digest, SHA256SUMS); nothing here
# is committed to git.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$offline = Join-Path $PackRoot 'BUNDLED-TOOLS\offline'
New-Item -ItemType Directory -Force -Path $offline | Out-Null
$catalog = [IO.File]::ReadAllText((Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json')) | ConvertFrom-Json
$rows = @()
foreach ($comp in @($catalog.components | Where-Object { $_.install -eq 'latest-release' } | Sort-Object id)) {
    $latest = Get-UabsCompanionLatest -Comp $comp -OutDir $offline
    # An older fetched copy would otherwise ride into Full-Offline beside the new one.
    $stale = ([string]$comp.asset_template).Replace('{version}', '*')
    Get-ChildItem -LiteralPath $offline -Filter $stale -File | Where-Object { $_.Name -cne $latest.asset } | Remove-Item -Force
    $rows += [ordered]@{ id = $latest.id; version = $latest.version; tag = $latest.tag; asset = $latest.asset; size = $latest.size; sha256 = $latest.sha256; url = $latest.url }
    Write-UabsOk ('{0} {1} verified: {2}' -f $comp.name, $latest.version, $latest.asset)
}
if (-not $rows.Count) { throw 'CATALOG.json declares no latest-release companion.' }
$json = (([ordered]@{ schema = 1; companions = $rows } | ConvertTo-Json -Depth 5) -replace "`r`n", "`n") + "`n"
[IO.File]::WriteAllText((Join-Path $offline 'companions.json'), $json, (New-Object Text.UTF8Encoding($false)))
