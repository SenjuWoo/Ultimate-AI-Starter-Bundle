# discover_tools.ps1 — read-only optional tool probe for Ultimate AI Starter Bundle
param([switch]$Json)
$ErrorActionPreference = 'Continue'

function Find-FirstFile {
  param([string[]]$Candidates)
  foreach ($c in $Candidates) {
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    try {
      if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path }
    } catch {}
  }
  return $null
}

function Find-Under {
  param([string[]]$Roots,[string]$Filter,[int]$Depth=5)
  foreach ($r in $Roots) {
    if ([string]::IsNullOrWhiteSpace($r)) { continue }
    if (-not (Test-Path -LiteralPath $r)) { continue }
    try {
      $hit = Get-ChildItem -LiteralPath $r -Filter $Filter -Recurse -Depth $Depth -File -ErrorAction SilentlyContinue | Select-Object -First 1
      if ($hit) { return $hit.FullName }
    } catch {}
  }
  return $null
}

function Get-ExistingRoots {
  param([string[]]$Paths)
  $out = @()
  foreach ($p in $Paths) {
    if ([string]::IsNullOrWhiteSpace($p)) { continue }
    try {
      if (Test-Path -LiteralPath $p) { $out += $p }
    } catch {}
  }
  return $out
}

$report = [ordered]@{}

# Forge
$forgeRoot = $env:SKYRIM_FORGE_ROOT
if (-not $forgeRoot) {
  foreach ($p in @(
    (Join-Path $PSScriptRoot '..\skyrim-forge\INSTALLATION.json'),
    (Join-Path $env:USERPROFILE '.grok\skills\skyrim-forge\INSTALLATION.json'),
    (Join-Path $env:USERPROFILE '.claude\skills\skyrim-forge\INSTALLATION.json'),
    (Join-Path $env:USERPROFILE '.agents\skills\skyrim-forge\INSTALLATION.json'),
    (Join-Path $env:USERPROFILE '.codex\skills\skyrim-forge\INSTALLATION.json'),
    (Join-Path $env:USERPROFILE '.agents\skills\skyrim-forge\INSTALLATION.json')
  )) {
    if (Test-Path -LiteralPath $p) {
      try {
        $j = [IO.File]::ReadAllText($p) | ConvertFrom-Json
        if ($j.root -and (Test-Path -LiteralPath [string]$j.root)) { $forgeRoot = [string]$j.root; break }
      } catch {}
    }
  }
}
$report['skyrim-forge'] = @{ status = $(if ($forgeRoot) {'FOUND'} else {'MISSING'}); path = $forgeRoot; install = 'Install Skyrim Forge product; set SKYRIM_FORGE_ROOT or skill INSTALLATION.json' }

# houseCARL
function Get-ExeVersion([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return [version]'0.0.0.0' }
  try {
    $vi = (Get-Item -LiteralPath $Path).VersionInfo
    foreach ($c in @($vi.ProductVersion, $vi.FileVersion)) {
      if ($c -and ($c -match '^\s*(\d+(?:\.\d+){1,3})')) { return [version]$Matches[1] }
    }
  } catch {}
  return [version]'0.0.0.0'
}
$hcCandidates = New-Object System.Collections.Generic.List[string]
foreach ($direct in @($env:HOUSECARL_MCP, [Environment]::GetEnvironmentVariable('HOUSECARL_MCP','User'))) {
  if ($direct -and (Test-Path -LiteralPath $direct -PathType Leaf)) {
    $rp = (Resolve-Path -LiteralPath $direct).Path
    if (-not $hcCandidates.Contains($rp)) { [void]$hcCandidates.Add($rp) }
  }
}
$hcSearchRoots = Get-ExistingRoots @(
  $env:HOUSECARL_ROOT,
  [Environment]::GetEnvironmentVariable('HOUSECARL_ROOT','User'),
  (Join-Path $env:LOCALAPPDATA 'houseCARL'),
  (Join-Path $env:LOCALAPPDATA 'Programs'),
  (Join-Path $env:USERPROFILE '.housecarl'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Programs'),
  (Join-Path $env:USERPROFILE '.agents'),
  (Join-Path $env:USERPROFILE '.claude')
)
foreach ($scope in @('Process','User')) {
  $extra = [Environment]::GetEnvironmentVariable('UABS_TOOL_ROOTS', $scope)
  if ($extra) { $hcSearchRoots += @(Get-ExistingRoots ($extra -split ';')) }
}
$skyrimToolTails = @(
  'Backup\!Skyrim\Skyrim tools',
  'Backup\!Skyrim\Skyrim Tools',
  'Backup\Skyrim tools',
  'Backup\Skyrim Tools',
  '!Skyrim\Skyrim tools',
  '!Skyrim\Skyrim Tools',
  'Apps\Skyrim Tools',
  'Skyrim Tools',
  'Skyrim tools',
  'Tools\Skyrim',
  'Modding\Tools'
)
# Optional common tool vaults on any fixed drive letter that actually exists
foreach ($letter in @('C','D','E','F','G','H','S','T','Z')) {
  $drive = "${letter}:\"
  if (Test-Path -LiteralPath $drive) {
    foreach ($tail in $skyrimToolTails) {
      $cand = Join-Path $drive $tail
      if (Test-Path -LiteralPath $cand) { $hcSearchRoots += $cand }
    }
  }
}
foreach ($r in ($hcSearchRoots | Select-Object -Unique)) {
  $hit = Find-Under @($r) 'housecarl-mcp.exe' 6
  if ($hit -and -not $hcCandidates.Contains($hit)) { [void]$hcCandidates.Add($hit) }
}
$hc = $null
$hcBestVer = [version]'0.0.0.0'
$hcBestExt = $false
$defaultHcRoot = Join-Path $env:LOCALAPPDATA 'houseCARL'
foreach ($cand in $hcCandidates) {
  $v = Get-ExeVersion $cand
  $isExt = -not $cand.StartsWith($defaultHcRoot, [StringComparison]::OrdinalIgnoreCase)
  if (-not $hc -or $v -gt $hcBestVer -or ($v -eq $hcBestVer -and $isExt -and -not $hcBestExt)) {
    $hc = $cand; $hcBestVer = $v; $hcBestExt = $isExt
  }
}
$report['housecarl-mcp'] = @{ status = $(if ($hc) {'FOUND'} else {'MISSING'}); path = $hc; install = 'Run houseCARL-Setup.exe; install .NET 10 Runtime; register MCP; restart AI app' }

# codebase-memory
$cm = Find-FirstFile @(
  $env:CODEBASE_MEMORY_MCP,
  (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe')
)
$report['codebase-memory-mcp'] = @{ status = $(if ($cm) {'FOUND'} else {'MISSING'}); path = $cm; install = 'https://github.com/DeusData/codebase-memory-mcp' }

# headroom
$hr = $null
try { $c = Get-Command headroom -ErrorAction SilentlyContinue; if ($c) { $hr = $c.Source } } catch {}
if (-not $hr -and $env:HEADROOM_CMD) { $hr = $env:HEADROOM_CMD }
$report['headroom'] = @{ status = $(if ($hr) {'FOUND'} else {'MISSING'}); path = $hr; install = 'pip install "headroom-ai[mcp]" — https://github.com/headroomlabs-ai/headroom' }

# codeburn
$cb = $null
try { $c = Get-Command codeburn -ErrorAction SilentlyContinue; if ($c) { $cb = $c.Source } } catch {}
if (-not $cb) { try { $npx = Get-Command npx -ErrorAction SilentlyContinue; if ($npx) { $cb = 'npx codeburn' } } catch {} }
$report['codeburn'] = @{ status = $(if ($cb) {'FOUND'} else {'MISSING'}); path = $cb; install = 'npm i -g codeburn or npx codeburn — https://github.com/getagentseal/codeburn' }

# MO2 / houseCARL instance (real MO2 or Vortex shim)
$mo2 = $env:SKYRIM_MO2_INSTANCE
if (-not $mo2) { $mo2 = $env:HouseCarl__Mo2InstanceDir }
$shimDefault = Join-Path $env:LOCALAPPDATA 'houseCARL-Shim'
if (-not $mo2 -and (Test-Path -LiteralPath (Join-Path $shimDefault 'ModOrganizer.ini'))) { $mo2 = $shimDefault }
# User-scope env may not be visible in this process yet — read from registry
if (-not $mo2) {
  try {
    $mo2 = [Environment]::GetEnvironmentVariable('SKYRIM_MO2_INSTANCE','User')
  } catch {}
}
if (-not $mo2) {
  try {
    $mo2 = [Environment]::GetEnvironmentVariable('HouseCarl__Mo2InstanceDir','User')
  } catch {}
}
$mo2Status = 'UNSET'
if ($mo2) {
  try {
    if (Test-Path -LiteralPath (Join-Path $mo2 'ModOrganizer.ini')) {
      if (Test-Path -LiteralPath (Join-Path $mo2 'HOUSECARL-SHIM.txt')) { $mo2Status = 'VORTEX-SHIM' }
      else { $mo2Status = 'MO2-INSTANCE' }
    } else { $mo2Status = 'INVALID'; $mo2 = $null }
  } catch { $mo2Status = 'INVALID'; $mo2 = $null }
}
$report['mo2-instance'] = @{ status = $mo2Status; path = $mo2; install = 'Run TOOLS\Setup-HouseCarl.ps1 (MO2 or Vortex) or set SKYRIM_MO2_INSTANCE' }

# dotnet
$dn = $null
try { $c = Get-Command dotnet -ErrorAction SilentlyContinue; if ($c) { $dn = $c.Source } } catch {}
$report['dotnet'] = @{ status = $(if ($dn) {'FOUND'} else {'MISSING'}); path = $dn; install = 'https://dotnet.microsoft.com/download' }


# houseCARL instance / Vortex shim
$hcInst = $env:SKYRIM_MO2_INSTANCE
if (-not $hcInst) { $hcInst = $env:HouseCarl__Mo2InstanceDir }
$shimDefault = Join-Path $env:LOCALAPPDATA 'houseCARL-Shim'
$stateFile = Join-Path $env:LOCALAPPDATA 'houseCARL-data\uabs-setup-state.json'
if (-not $hcInst -and (Test-Path -LiteralPath (Join-Path $shimDefault 'ModOrganizer.ini'))) { $hcInst = $shimDefault }
$hcInstStatus = 'UNSET'
if ($hcInst -and (Test-Path -LiteralPath (Join-Path $hcInst 'ModOrganizer.ini'))) {
  if (Test-Path -LiteralPath (Join-Path $hcInst 'HOUSECARL-SHIM.txt')) { $hcInstStatus = 'VORTEX-SHIM' }
  else { $hcInstStatus = 'MO2-INSTANCE' }
} elseif ($hcInst) { $hcInstStatus = 'INVALID' }
$report['housecarl-instance'] = @{ status = $hcInstStatus; path = $hcInst; install = 'Run TOOLS\Setup-HouseCarl.ps1 (MO2 or Vortex)' }
$report['housecarl-setup-state'] = @{ status = $(if (Test-Path -LiteralPath $stateFile) {'FOUND'} else {'MISSING'}); path = $(if (Test-Path -LiteralPath $stateFile) {$stateFile} else {$null}); install = 'Run TOOLS\Setup-HouseCarl.ps1' }

if ($Json) {
  $report | ConvertTo-Json -Depth 5
} else {
  foreach ($k in $report.Keys) {
    $r = $report[$k]
    '{0,-28} {1,-8} {2}' -f $k, $r.status, $(if ($r.path) { $r.path } else { $r.install })
  }
}
