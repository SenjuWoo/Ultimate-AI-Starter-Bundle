# discover_tools.ps1 - read-only probe for the general tools the Ultimate AI Starter Bundle manages.
# Never installs or writes anything. Game-specific tools (Skyrim Forge, houseCARL, other game Forges)
# are owned and discovered by their own repositories; this script only reports the general stack.
param([switch]$Json)
$ErrorActionPreference = 'Continue'

# First existing path from a candidate list (env values may be empty).
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

# Source path of a command on PATH, or $null.
function Find-OnPath {
  param([string]$Name)
  try { $c = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { return $c.Source } } catch {}
  # A desktop opened before installation still has the old process PATH.
  foreach ($dir in @(([Environment]::GetEnvironmentVariable('PATH','User') + ';' + [Environment]::GetEnvironmentVariable('PATH','Machine')) -split ';')) {
    if (-not $dir) { continue }
    foreach ($suffix in @('', '.exe','.cmd')) { $candidate=Join-Path $dir ($Name+$suffix); if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate } }
  }
  return $null
}

# Read a variable from the process first, then from the user's registry scope
# (a freshly installed tool may not be visible in this process yet).
function Get-EnvAnyScope {
  param([string]$Name)
  $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'User') }
  return $v
}

$report = [ordered]@{}

# codebase-memory-mcp: knowledge-graph code navigation
$cm = Find-FirstFile @(
  (Get-EnvAnyScope 'CODEBASE_MEMORY_MCP'),
  (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe'),
  (Join-Path $env:USERPROFILE '.local\bin\codebase-memory-mcp.exe')
)
$report['codebase-memory-mcp'] = @{ status = $(if ($cm) {'FOUND'} else {'MISSING'}); path = $cm; install = 'https://github.com/DeusData/codebase-memory-mcp' }

# headroom: context compression MCP/CLI
$hr = Find-OnPath 'headroom'
if (-not $hr) { $hr = Get-EnvAnyScope 'HEADROOM_CMD' }
$report['headroom'] = @{ status = $(if ($hr) {'FOUND'} else {'MISSING'}); path = $hr; install = 'pip install "headroom-ai[mcp]" - https://github.com/headroomlabs-ai/headroom' }

# codeburn: local AI cost analytics (npx is enough)
$cb = Find-OnPath 'codeburn'
if (-not $cb -and (Find-OnPath 'npx')) { $cb = 'npx codeburn' }
$report['codeburn'] = @{ status = $(if ($cb) {'FOUND'} else {'MISSING'}); path = $cb; install = 'npx codeburn or npm i -g codeburn - https://github.com/getagentseal/codeburn' }

# uabs-toolbox: the bundle's on-demand MCP launcher
$tb = Find-OnPath 'uabs-toolbox'
if (-not $tb) { $tb = Get-EnvAnyScope 'UABS_TOOLBOX_CMD' }
$report['uabs-toolbox'] = @{ status = $(if ($tb) {'FOUND'} else {'MISSING'}); path = $tb; install = 'Run START-HERE.bat from the Ultimate-AI-Starter-Bundle' }

# rtk: output-compression hook binary
$rtk = Find-FirstFile @((Join-Path $env:USERPROFILE '.local\bin\rtk.exe'))
if (-not $rtk) { $rtk = Find-OnPath 'rtk' }
$report['rtk'] = @{ status = $(if ($rtk) {'FOUND'} else {'MISSING'}); path = $rtk; install = 'Run START-HERE.bat from the Ultimate-AI-Starter-Bundle' }

# Runtimes the stack leans on
foreach ($rt in @(@('python','https://www.python.org/downloads/'), @('node','https://nodejs.org/'), @('git','https://git-scm.com/'), @('gh','https://cli.github.com/'), @('uv','https://docs.astral.sh/uv/'))) {
  $p = Find-OnPath $rt[0]
  # python.exe in WindowsApps is often the Microsoft Store stub; only a run that answers counts.
  if ($p -and $rt[0] -eq 'python') {
    $ver = (& $p --version 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $ver -notmatch 'Python \d') { $p = $null }
  }
  $report[$rt[0]] = @{ status = $(if ($p) {'FOUND'} else {'MISSING'}); path = $p; install = $rt[1] }
}

# Compiler locations are recorded only after actual compile-and-run proof.
foreach ($tool in @('go','rustc','cargo','gcc','cmake','xmake','ninja','dotnet')) {
  $path=Find-OnPath $tool
  $report[$tool]=@{status=$(if($path){'FOUND'}else{'MISSING'});path=$path;install='TOOLS/Install-BuildTools.ps1'}
}

if ($Json) {
  $report | ConvertTo-Json -Depth 5
} else {
  foreach ($k in $report.Keys) {
    $r = $report[$k]
    '{0,-22} {1,-8} {2}' -f $k, $r.status, $(if ($r.path) { $r.path } else { $r.install })
  }
}
