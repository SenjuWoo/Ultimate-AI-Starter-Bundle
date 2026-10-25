<#
.SYNOPSIS
  Write a compact map of where things live on THIS machine for the AI to read.

.DESCRIPTION
  Agents spend real usage rediscovering the same paths every session (and users
  retype them: one user pasted the same folder map into 36 sessions). This
  writes MACHINE-MAP.md into the personal profile folder (default
  %USERPROFILE%\.uabs\profile); the installer adds it, with PROFILE.md, to every
  provider's instruction file. It is regenerated on every install, never
  shipped, and never contains file contents, keys or tokens: only folder paths,
  installed game names and tool roots.

  Read-only except for the one output file.
#>
[CmdletBinding()]
param(
  [string]$ProfileRoot,
  [string]$PackRoot,
  [switch]$Print
)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$ProfileRoot = Get-UabsProfileRoot $ProfileRoot
$lines = New-Object System.Collections.Generic.List[string]
function Add([string]$label, [string[]]$items, [int]$max = 1200) {
  $items = @($items | Where-Object { $_ } | Select-Object -Unique)
  if (-not $items.Count) { return }
  $text = $items -join '; '
  if ($text.Length -gt $max) { $text = $text.Substring(0, $max).TrimEnd(';', ' ') + ' ...' }
  $lines.Add('- ' + $label + ': ' + $text)
}
function Short([string]$path) {
  # Shorter and still exact: the user folder as %USERPROFILE%.
  if ($env:USERPROFILE -and $path.StartsWith($env:USERPROFILE, [StringComparison]::OrdinalIgnoreCase)) { return '%USERPROFILE%' + $path.Substring($env:USERPROFILE.Length) }
  return $path
}

# Steam libraries and the games installed in each.
$steam = $null
try { $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath.Replace('/', '\') } catch {}
$libs = @()
if ($steam) {
  # libraryfolders.vdf keeps the real casing; the registry value is lowercase.
  $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
  if (Test-Path -LiteralPath $vdf -PathType Leaf) {
    foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) { $libs += $m.Groups[1].Value.Replace('\\', '\') }
  }
  $libs += $steam
}
# The full game list goes to GAMES.md, which is read on demand; only the
# library roots ride on every request.
$seen = @{}
$games = New-Object System.Collections.Generic.List[string]
$commons = @()
foreach ($lib in $libs) {
  $full = [IO.Path]::GetFullPath($lib).TrimEnd('\')
  if ($seen.ContainsKey($full.ToLowerInvariant())) { continue }
  $seen[$full.ToLowerInvariant()] = $true
  $names = @()
  foreach ($acf in @(Get-ChildItem -LiteralPath (Join-Path $full 'steamapps') -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
    $m = [regex]::Match([IO.File]::ReadAllText($acf.FullName), '"installdir"\s+"([^"]+)"')
    if ($m.Success -and $m.Groups[1].Value -notmatch '(?i)^(Steamworks Shared|Steam Controller Configs)$|redist|proton|runtime') { $names += $m.Groups[1].Value }
  }
  if ($names.Count) {
    $common = Join-Path $full 'steamapps\common'
    $commons += $common
    $games.Add('## ' + $common)
    foreach ($n in ($names | Sort-Object)) { $games.Add('- ' + $n) }
    $games.Add('')
  }
}
if ($commons.Count) { Add ('Steam game folders (installed list: ' + (Short (Join-Path $ProfileRoot 'GAMES.md')) + ')') $commons }

# Mod managers and game log/config folders.
$vortex = Join-Path $env:APPDATA 'Vortex'
Add ('Vortex staging (' + (Short $vortex) + '\<game>\mods)') @(Get-ChildItem -LiteralPath $vortex -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'mods') } | ForEach-Object Name)
$mo2 = Join-Path $env:LOCALAPPDATA 'ModOrganizer'
Add ('MO2 instances (' + (Short $mo2) + ')') @(Get-ChildItem -LiteralPath $mo2 -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)
$myGames = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'My Games'
Add ('Game logs/configs (' + (Short $myGames) + ')') @(Get-ChildItem -LiteralPath $myGames -Directory -ErrorAction SilentlyContinue | ForEach-Object Name)

# Tool roots the user or the bundle exported (paths only).
$roots = @()
foreach ($scope in 'User', 'Process') {
  foreach ($kv in ([Environment]::GetEnvironmentVariables($scope)).GetEnumerator()) {
    $name = [string]$kv.Key; $value = [string]$kv.Value
    if ($name -notmatch '(_ROOT|_HOME|_INSTANCE|_MCP)$' -or $name -match '(?i)token|key|secret|password') { continue }
    if ($value -and (Test-Path -LiteralPath $value)) { $roots += ($name + '=' + (Short $value)) }
  }
}
Add 'Tool roots' ($roots | Sort-Object -Unique)
$skyrimVaults = @(Get-UabsSkyrimToolDirectories | ForEach-Object { Short $_ })
if ($skyrimVaults.Count) { Add 'Skyrim tool folders' $skyrimVaults }

# AI app homes that exist here.
$homes = @()
foreach ($h in @(
  @('Claude', (Join-Path $env:USERPROFILE '.claude')), @('Codex', (Join-Path $env:USERPROFILE '.codex')),
  @('Codex skills', (Join-Path $env:USERPROFILE '.agents\skills')), @('Grok', (Join-Path $env:USERPROFILE '.grok')),
  @('Hermes', (Join-Path $env:LOCALAPPDATA 'hermes')), @('Kimi', (Join-Path $env:USERPROFILE '.kimi-code'))
)) { if (Test-Path -LiteralPath $h[1]) { $homes += ($h[0] + ' ' + (Short $h[1])) } }
Add 'AI app homes' $homes
Add 'This bundle' @((Short $PackRoot))

$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $login = (& $gh.Source api user --jq .login 2>$null | Out-String).Trim() } finally { $ErrorActionPreference = $prev }
  if ($LASTEXITCODE -eq 0 -and $login -match '^[A-Za-z0-9-]+$') { Add 'GitHub account (gh)' @($login) }
}

# Run Python: modern WindowsApps aliases may be the install manager, not a Store stub.
$python = Get-UabsPythonExecutable
if ($python) {
  Add 'Python' @('Shared user runtime: ' + (Short $python) + '; use `python` on PATH or `UABS_PYTHON`. Reuse it; isolate tool dependencies with venv/uv, and do not download a second base interpreter. Embedded app runtimes stay app-owned.')
}

$text = "## Machine map (generated " + (Get-Date -Format 'yyyy-MM-dd') + " by the bundle installer; your own folders go in " + (Short (Join-Path $ProfileRoot 'PROFILE.md')) + ")`n" + ($lines -join "`n") + "`n"
if ($Print) { Write-Output $text; return }
New-Item -ItemType Directory -Force -Path $ProfileRoot | Out-Null
if ($games.Count) {
  [IO.File]::WriteAllText((Join-Path $ProfileRoot 'GAMES.md'), ("# Installed Steam games (generated; not sent with every request)`n`n" + ($games -join "`n")), (New-Object System.Text.UTF8Encoding $false))
}
$out = Join-Path $ProfileRoot 'MACHINE-MAP.md'
$old = if (Test-Path -LiteralPath $out -PathType Leaf) { [IO.File]::ReadAllText($out) } else { '' }
# The date line alone changing is not a change worth a rewrite (or a new
# instruction-file backup on every install).
$strip = { param($s) ($s -split "`n" | Select-Object -Skip 1) -join "`n" }
if ((& $strip $old) -ceq (& $strip $text)) { Write-Host ('  OK  machine map unchanged: ' + $out) -ForegroundColor Green; return }
[IO.File]::WriteAllText($out, $text, (New-Object System.Text.UTF8Encoding $false))
Write-Host ('  OK  machine map written (' + $lines.Count + ' lines): ' + $out) -ForegroundColor Green
