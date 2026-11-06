# discover_tools.ps1 - read-only probe for the general tools the Ultimate AI Starter Bundle manages.
# Never installs or writes anything. A tool is only VERIFIED after its own version/help call
# succeeds; an executable on PATH is INSTALLED at best. Game-specific tools are owned by their forges.
param(
  [switch]$Json,
  [switch]$Inventory,
  [switch]$Refresh,
  [switch]$NoCache,
  [string[]]$ToolRoots = @(),
  [string]$SearchDir,
  [switch]$Isolated,
  [string]$CacheDir,
  [string]$HermesConfig
)
$ErrorActionPreference = 'Continue'

function Find-FirstFile {
  param([string[]]$Candidates)
  foreach ($c in $Candidates) {
    if ([string]::IsNullOrWhiteSpace($c)) { continue }
    try { if (Test-Path -LiteralPath $c) { return (Resolve-Path -LiteralPath $c).Path } } catch {}
  }
  return $null
}

function Find-OnPath {
  param([string]$Name)
  if ($SearchDir) {
    foreach ($suffix in @('', '.exe', '.cmd', '.bat')) {
      $candidate = Join-Path $SearchDir ($Name + $suffix)
      if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
  }
  if ($Isolated) { return $null }
  try { $c = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1; if ($c) { return $c.Source } } catch {}
  foreach ($dir in @(([Environment]::GetEnvironmentVariable('PATH','User') + ';' + [Environment]::GetEnvironmentVariable('PATH','Machine')) -split ';')) {
    if (-not $dir) { continue }
    foreach ($suffix in @('', '.exe', '.cmd')) { $candidate=Join-Path $dir ($Name+$suffix); if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate } }
  }
  return $null
}

function Get-EnvAnyScope {
  param([string]$Name)
  $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
  if (-not $v) { $v = [Environment]::GetEnvironmentVariable($Name, 'User') }
  return $v
}

# Run a probe with a hard timeout; a hanging tool must not hang discovery.
function Invoke-Probe {
  param([string]$Exe, [string[]]$Arguments = @(), [int]$TimeoutSeconds = 6)
  try {
    # A script shim (.ps1/.cmd/.bat) is not a PE image: Process.Start throws on
    # it, so the tool would be reported INSTALLED forever even though it answers
    # fine in a shell (npm puts codeburn.ps1 on PATH). Wrap it in its host.
    $file = $Exe
    $argLine = ($Arguments -join ' ')
    $ext = [IO.Path]::GetExtension($Exe).ToLowerInvariant()
    if ($ext -eq '.ps1') {
      $file = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
      $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $Exe + '"' + $(if ($argLine) { ' ' + $argLine } else { '' })
    } elseif ($ext -eq '.cmd' -or $ext -eq '.bat') {
      $file = $env:ComSpec
      $argLine = '/c "' + $Exe + '"' + $(if ($argLine) { ' ' + $argLine } else { '' })
    }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $file
    $psi.Arguments = $argLine
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $p = [System.Diagnostics.Process]::Start($psi)
    # Read asynchronously: a 4 KB pipe fills and deadlocks WaitForExit otherwise.
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit($TimeoutSeconds * 1000)) { try { $p.Kill() } catch {}; return @{ ok = $false; code = -1; text = 'timeout' } }
    $p.WaitForExit()
    $out = $outTask.Result + $errTask.Result
    return @{ ok = ($p.ExitCode -eq 0); code = $p.ExitCode; text = $out.Trim() }
  } catch {
    return @{ ok = $false; code = -1; text = $_.Exception.Message }
  }
}

# Report shape: legacy `status` (FOUND/MISSING) stays for old consumers; `state`
# carries the precise value: VERIFIED, CALLABLE, CONFIGURED, INSTALLED,
# DISCOVERED, MISSING. VERIFIED means a probe of the real entrypoint answered;
# a directory or a config entry is not proof and must not claim that state.
function New-Row {
  param([string]$State, [string]$Path, [string]$Install, [string]$Version, [string]$Detail)
  $legacy = if ($State -in @('VERIFIED','CALLABLE','CONFIGURED','INSTALLED','DISCOVERED')) { 'FOUND' } else { 'MISSING' }
  $row = [ordered]@{ status = $legacy; state = $State; path = $Path; install = $Install }
  if ($Version) { $row.version = $Version }
  if ($Detail) { $row.detail = $Detail }
  return $row
}

function Test-Tool {
  param([string]$Name, [string[]]$Candidates, [string]$Install, [string[]]$ProbeArgs = @())
  $path = Find-FirstFile $Candidates
  if (-not $path) { return New-Row 'MISSING' $null $Install }
  $probe = Invoke-Probe $path $ProbeArgs
  if ($probe.ok) {
    $version = ($probe.text -split "`r?`n" | Select-Object -First 1)
    return New-Row 'VERIFIED' $path $Install $version
  }
  return New-Row 'INSTALLED' $path $Install $null ('probe failed: ' + $probe.text.Split("`n")[0])
}

$report = [ordered]@{}

# codebase-memory-mcp: knowledge-graph code navigation
$report['codebase-memory-mcp'] = Test-Tool 'codebase-memory-mcp' @(
  (Get-EnvAnyScope 'CODEBASE_MEMORY_MCP'),
  (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe'),
  (Join-Path $env:USERPROFILE '.local\bin\codebase-memory-mcp.exe')
) 'https://github.com/DeusData/codebase-memory-mcp' @('--version')

# headroom: context compression MCP/CLI
$hr = Find-OnPath 'headroom'
if (-not $hr) { $hr = Get-EnvAnyScope 'HEADROOM_CMD' }
$report['headroom'] = Test-Tool 'headroom' @($hr) 'pip install "headroom-ai[mcp]" - https://github.com/headroomlabs-ai/headroom' @('--version')

# codeburn: npx existing says nothing about codeburn existing. Ask npm for the
# package, with --no-install so the probe can never fetch it.
$cb = Find-OnPath 'codeburn'
if ($cb) {
  $probe = Invoke-Probe $cb @('--version')
  $report['codeburn'] = if ($probe.ok) { New-Row 'VERIFIED' $cb 'https://github.com/getagentseal/codeburn' ($probe.text.Split("`n")[0]) }
                        else { New-Row 'INSTALLED' $cb 'https://github.com/getagentseal/codeburn' $null 'version probe failed' }
} else {
  $npx = Find-OnPath 'npx'
  if ($npx) {
    $probe = Invoke-Probe $npx @('--no-install', 'codeburn', '--version')
    $report['codeburn'] = if ($probe.ok) { New-Row 'VERIFIED' 'npx codeburn' 'https://github.com/getagentseal/codeburn' ($probe.text.Split("`n")[0]) }
                          else { New-Row 'MISSING' $null 'npx codeburn or npm i -g codeburn - https://github.com/getagentseal/codeburn' $null 'npx exists but codeburn is not installed' }
  } else {
    $report['codeburn'] = New-Row 'MISSING' $null 'npx codeburn or npm i -g codeburn - https://github.com/getagentseal/codeburn'
  }
}

# uabs-toolbox: the bundle's on-demand MCP launcher
$tb = Find-OnPath 'uabs-toolbox'
if (-not $tb) { $tb = Get-EnvAnyScope 'UABS_TOOLBOX_CMD' }
$report['uabs-toolbox'] = Test-Tool 'uabs-toolbox' @($tb) 'Run START-HERE.bat from the Ultimate-AI-Starter-Bundle' @('--version')

# rtk: output-compression hook binary
$rtk = Find-FirstFile @((Join-Path $env:USERPROFILE '.local\bin\rtk.exe'))
if (-not $rtk) { $rtk = Find-OnPath 'rtk' }
$report['rtk'] = Test-Tool 'rtk' @($rtk) 'Run START-HERE.bat from the Ultimate-AI-Starter-Bundle' @('--version')

# Owner kits. The bundle never installs these; it reports where the owner kept
# them so an agent does not build a second copy. kit.json is the reverse-this
# registry (authoritative after a move); REVERSE_THIS_ROOT only overrides one
# task. No directory walks here -- a moved kit is repaired in one place.
$rtRoot = Get-EnvAnyScope 'REVERSE_THIS_ROOT'
if (-not $rtRoot) {
  $kitPointer = Join-Path $env:LOCALAPPDATA 'ReverseThis\kit.json'
  if (Test-Path -LiteralPath $kitPointer -PathType Leaf) {
    try { $kit = [IO.File]::ReadAllText($kitPointer) | ConvertFrom-Json; if ($kit.kit_root) { $rtRoot = [string]$kit.kit_root } } catch {}
  }
}
if (-not $rtRoot) { $rtRoot = Join-Path $env:LOCALAPPDATA 'ReverseThis\kit' }
$rtBin = Get-EnvAnyScope 'REVERSE_THIS_BIN'
if (-not $rtBin) { $rtBin = Join-Path $rtRoot 'sandbox\bin' }
$rtVersion = $null
$rtVersionFile = Join-Path $rtRoot 'VERSION'
if (Test-Path -LiteralPath $rtVersionFile -PathType Leaf) { $rtVersion = ([IO.File]::ReadAllText($rtVersionFile)).Trim() }
$rtOk = (Test-Path -LiteralPath $rtRoot -PathType Container) -and (Test-Path -LiteralPath $rtBin -PathType Container)
$report['reverse-this'] = if ($rtOk) { New-Row 'INSTALLED' $rtRoot 'https://github.com/SenjuWoo/reverse-this (owner kit; do not duplicate)' $rtVersion ('kit present at ' + $rtBin + '; the owner CLI was not probed') }
  else { New-Row 'MISSING' $null 'https://github.com/SenjuWoo/reverse-this (owner kit; do not duplicate)' }

$sfRoot = Get-EnvAnyScope 'SKYRIM_FORGE_ROOT'
if (-not $sfRoot) { $sfRoot = Join-Path $env:LOCALAPPDATA 'Skyrim-Tools\Skyrim-Forge' }
$report['skyrim-forge'] = if (Test-Path -LiteralPath $sfRoot -PathType Container) { New-Row 'INSTALLED' $sfRoot 'https://github.com/SenjuWoo/SkyrimForge (owner tool; do not duplicate)' $null 'kit present; houseCARL is owned by Forge and was not probed' }
  else { New-Row 'MISSING' $null 'https://github.com/SenjuWoo/SkyrimForge (owner tool; do not duplicate)' }

foreach ($rt in @(@('python','https://www.python.org/downloads/'), @('node','https://nodejs.org/'), @('git','https://git-scm.com/'), @('gh','https://cli.github.com/'), @('uv','https://docs.astral.sh/uv/'))) {
  $p = Find-OnPath $rt[0]
  if ($p) {
    $probe = Invoke-Probe $p @('--version')
    if ($probe.ok) { $report[$rt[0]] = New-Row 'VERIFIED' $p $rt[1] ($probe.text.Split("`n")[0]) }
    else { $report[$rt[0]] = New-Row 'INSTALLED' $p $rt[1] $null 'version probe failed' }
  } else { $report[$rt[0]] = New-Row 'MISSING' $null $rt[1] }
}

# Compilers: path presence is INSTALLED; VERIFIED needs the tool to answer.
# `go` spells its version probe differently -- `go --version` is a flag error,
# which used to mark a working toolchain INSTALLED on every run.
foreach ($tool in @('go','rustc','cargo','gcc','cmake','xmake','ninja','dotnet')) {
  $path = Find-OnPath $tool
  if (-not $path) { $report[$tool] = New-Row 'MISSING' $null 'TOOLS/Install-BuildTools.ps1'; continue }
  $probeArgs = if ($tool -eq 'go') { @('version') } else { @('--version') }
  $probe = Invoke-Probe $path $probeArgs
  if ($probe.ok) { $report[$tool] = New-Row 'VERIFIED' $path 'TOOLS/Install-BuildTools.ps1' ($probe.text.Split("`n")[0]) }
  else { $report[$tool] = New-Row 'INSTALLED' $path 'TOOLS/Install-BuildTools.ps1' $null 'version probe failed' }
}

# CLI Hub (CLI-Anything): optional companion. Detect the executable, verify its
# own version/help, count harnesses, and find a source checkout without vendoring.
$hub = Find-OnPath 'cli-hub'
if ($hub) {
  $v = Invoke-Probe $hub @('--version')
  $list = if ($v.ok) { Invoke-Probe $hub @('list') -TimeoutSeconds 20 } else { @{ ok = $false; text = '' } }
  $count = if ($list.ok) { ([regex]::Matches($list.text, '(?m)^\s{4,}\S+\s{2,}')).Count } else { 0 }
  $detail = if ($v.ok -and $list.ok) { "$count harnesses listed" } elseif ($v.ok) { 'version ok; list failed' } else { 'cli-hub found but does not answer' }
  $report['cli-hub'] = New-Row $(if ($v.ok -and $list.ok) { 'VERIFIED' } else { 'INSTALLED' }) $hub `
    'pip install cli-anything-hub - https://github.com/HKUDS/CLI-Anything' $(if ($v.ok) { $v.text.Split("`n")[0] }) $detail
} else {
  $report['cli-hub'] = New-Row 'MISSING' $null 'pip install cli-anything-hub - https://github.com/HKUDS/CLI-Anything'
}

# A checkout may sit at a root, one level down, or under a category folder
# (Tools\Github\CLI-Anything-main). UABS_TOOL_ROOTS is a ';' list, not one path;
# treating it as one string made a moved checkout look absent. Two bounded
# levels, never a drive walk.
$roots = New-Object System.Collections.Generic.List[string]
foreach ($r in @($ToolRoots)) { if ($r) { [void]$roots.Add($r) } }
foreach ($name in @('UABS_TOOL_ROOTS', 'CLI_ANYTHING_ROOT')) {
  $value = Get-EnvAnyScope $name
  if ($value) { foreach ($piece in ($value -split ';')) { if ($piece.Trim()) { [void]$roots.Add($piece.Trim()) } } }
}
foreach ($p in @(
    (Join-Path $env:USERPROFILE 'CLI-Anything-main'),
    (Join-Path $env:USERPROFILE 'Downloads\CLI-Anything-main'),
    (Join-Path $env:LOCALAPPDATA 'CLI-Anything'))) { [void]$roots.Add($p) }
$map = Join-Path $env:USERPROFILE '.uabs\profile\MACHINE-MAP.md'
if (Test-Path -LiteralPath $map -PathType Leaf) {
  foreach ($line in [IO.File]::ReadAllLines($map)) {
    if ($line -notmatch '^-\s+Tool folders') { continue }
    $rest = $line -split ':', 2
    if ($rest.Count -lt 2) { continue }
    foreach ($piece in ($rest[1] -split ';')) { if ($piece.Trim()) { [void]$roots.Add([Environment]::ExpandEnvironmentVariables($piece.Trim())) } }
  }
}

$candidates = New-Object System.Collections.Generic.List[string]
foreach ($root in @($roots | Select-Object -Unique)) {
  if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
  [void]$candidates.Add($root)
  [void]$candidates.Add((Join-Path $root 'CLI-Anything-main'))
  foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
    [void]$candidates.Add($d.FullName)
    foreach ($g in @(Get-ChildItem -LiteralPath $d.FullName -Directory -Filter 'CLI-Anything*' -ErrorAction SilentlyContinue)) { [void]$candidates.Add($g.FullName) }
  }
}
$checkout = $null
foreach ($candidate in @($candidates | Select-Object -Unique)) {
  # A pyproject.toml alone proves nothing -- every Python project has one, and an
  # unrelated repo was reported as a CLI-Anything checkout. The package folder is
  # the exact marker; the name check keeps a renamed checkout recognizable.
  if (Test-Path -LiteralPath (Join-Path $candidate 'cli_hub') -PathType Container) { $checkout = $candidate; break }
  if (Test-Path -LiteralPath (Join-Path $candidate 'cli-hub') -PathType Container) { $checkout = $candidate; break }
  if ((Split-Path -Leaf $candidate) -match '^CLI-Anything' -and (Test-Path -LiteralPath (Join-Path $candidate 'pyproject.toml') -PathType Leaf)) { $checkout = $candidate; break }
}
$report['cli-anything-source'] = if ($checkout) { New-Row 'DISCOVERED' $checkout 'https://github.com/HKUDS/CLI-Anything' $null 'source checkout; not installed by the bundle' }
                                  else { New-Row 'MISSING' $null 'https://github.com/HKUDS/CLI-Anything' }

# Host inventory is opt-in and cached: registry and package managers are only
# read when a task actually needs an application that is not in the list above.
$cacheDir = if ($CacheDir) { $CacheDir } else { Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle' }
$cacheFile = Join-Path $cacheDir 'discovery-inventory.json'
$meta = [ordered]@{ cached = $false }
if ($Inventory) {
  $fresh = $false
  if (-not $NoCache -and -not $Refresh -and (Test-Path -LiteralPath $cacheFile)) {
    try {
      $age = (Get-Date) - (Get-Item -LiteralPath $cacheFile).LastWriteTime
      if ($age.TotalHours -lt 24) { $report['host'] = [IO.File]::ReadAllText($cacheFile) | ConvertFrom-Json; $meta.cached = $true; $fresh = $true } catch {}
    } catch {}
  }
  if (-not $fresh) {
    $hostInfo = [ordered]@{ apps = @(); package_managers = @() }
    foreach ($pm in @('winget','scoop','choco')) { if (Find-OnPath $pm) { $hostInfo.package_managers += $pm } }
    $keywords = @('blender','godot','unity','unreal','freecad','krita','gimp','obs','audacity','davinci')
    $keys = @(
      'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
      'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $keys) {
      foreach ($item in @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)) {
        $name = [string]$item.DisplayName
        if (-not $name) { continue }
        foreach ($kw in $keywords) {
          if ($name.ToLowerInvariant().Contains($kw)) { $hostInfo.apps += $name; break }
        }
      }
    }
    $hostInfo.apps = @($hostInfo.apps | Sort-Object -Unique)
    try { New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null; [IO.File]::WriteAllText($cacheFile, ($hostInfo | ConvertTo-Json -Depth 4)) } catch {}
    $report['host'] = $hostInfo
  }
}

if ($HermesConfig -and (Test-Path -LiteralPath $HermesConfig -PathType Leaf)) {
  try {
    $cfg = [IO.File]::ReadAllText($HermesConfig) | ConvertFrom-Json
    foreach ($prop in $cfg.mcp_servers.PSObject.Properties) {
      $enabled = $true
      if ($prop.Value -and $prop.Value.PSObject.Properties['enabled']) { $enabled = [bool]$prop.Value.enabled }
      $report['mcp:' + $prop.Name] = New-Row $(if ($enabled) { 'CONFIGURED' } else { 'INSTALLED' }) $null 'Enable the server in the profile that needs it' $null $(if ($enabled) { 'configured and enabled; no tools/list probe was run' } else { 'configured but inactive in this profile' })
    }
  } catch { $meta.config_error = $_.Exception.Message }
}

if ($Json) {
  @{ tools = $report; meta = $meta } | ConvertTo-Json -Depth 6
} else {
  foreach ($k in $report.Keys) {
    if ($k -eq 'host') { continue }
    $r = $report[$k]
    '{0,-22} {1,-9} {2}' -f $k, $r.state, $(if ($r.path) { $r.path } else { $r.install })
  }
  if ($Inventory -and $report.Contains('host')) {
    'host apps: ' + (@($report['host'].apps) -join ', ')
  }
}
