<#
.SYNOPSIS
  Install the lean SillyTavern Hermes profile and its gateway launcher.
.DESCRIPTION
  Copies the profile template into %LOCALAPPDATA%\hermes\profiles\sillytavern,
  adds the two roleplay skills, hard-links the existing Hermes .env so API keys
  stay in one file, and replaces START-HERMES-GATEWAY.bat/.ps1 in the Hermes home.
  An existing profile config is left alone unless -Force is passed (no trailing
  dot). Replaced text files are backed up beside the originals.
#>
[CmdletBinding(PositionalBinding = $false)]
param(
  [string]$PackRoot,
  [string]$HermesHome,
  [switch]$Force
)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) {
  $here = $PSScriptRoot
  if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
  $PackRoot = Split-Path -Parent $here
}
if (-not $HermesHome) {
  $HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
}
if (-not (Test-Path -LiteralPath $HermesHome -PathType Container)) {
  Write-Host ('Hermes home not found, SillyTavern gateway skipped: ' + $HermesHome)
  exit 0
}

$PackRoot = (Resolve-Path -LiteralPath $PackRoot).ProviderPath
$template = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\Hermes\profiles\sillytavern'
$launcher = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\Hermes\sillytavern-gateway'
if (-not (Test-Path -LiteralPath (Join-Path $template 'config.yaml') -PathType Leaf)) {
  throw 'PackRoot must point to the bundle root, not TOOLS. Use -Force without a trailing dot only when resetting the profile.'
}
$profile = Join-Path $HermesHome 'profiles\sillytavern'
New-Item -ItemType Directory -Force -Path (Join-Path $profile 'skills') | Out-Null

$utf8 = New-Object System.Text.UTF8Encoding($false)
function Copy-TextFile([string]$From, [string]$To) {
  $text = [IO.File]::ReadAllText($From)
  $dir = Split-Path -Parent $To
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  if (Test-Path -LiteralPath $To -PathType Leaf) {
    if ([IO.File]::ReadAllText($To) -ceq $text) { return }
    Copy-Item -LiteralPath $To -Destination ($To + '.bak-' + [guid]::NewGuid().ToString('n'))
  }
  [IO.File]::WriteAllText($To, $text, $utf8)
}

$configDest = Join-Path $profile 'config.yaml'
if ($Force -or -not (Test-Path -LiteralPath $configDest -PathType Leaf)) {
  Copy-TextFile (Join-Path $template 'config.yaml') $configDest
}
Copy-TextFile (Join-Path $template 'profile.yaml') (Join-Path $profile 'profile.yaml')
Copy-TextFile (Join-Path $template 'SOUL.md') (Join-Path $profile 'SOUL.md')
Copy-TextFile (Join-Path $template 'skills\sillytavern-gateway\SKILL.md') (Join-Path $profile 'skills\sillytavern-gateway\SKILL.md')

$skillSource = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\Hermes\COPY-TO-SKILLS-DIRECTORY\skills'
foreach ($name in @('adult-character-sheet', 'adult-image-caption')) {
  $from = Join-Path $skillSource ($name + '\SKILL.md')
  if (-not (Test-Path -LiteralPath $from -PathType Leaf)) { throw ('Missing roleplay skill: ' + $from) }
  Copy-TextFile $from (Join-Path $profile ('skills\' + $name + '\SKILL.md'))
}

$homeEnv = Join-Path $HermesHome '.env'
$profileEnv = Join-Path $profile '.env'
if (-not (Test-Path -LiteralPath $profileEnv)) {
  if (Test-Path -LiteralPath $homeEnv -PathType Leaf) {
    New-Item -ItemType HardLink -Path $profileEnv -Target $homeEnv | Out-Null
  } else {
    Copy-TextFile (Join-Path $template 'env.example') $profileEnv
  }
}

Copy-TextFile (Join-Path $launcher 'START-HERMES-GATEWAY.ps1') (Join-Path $HermesHome 'START-HERMES-GATEWAY.ps1')
Copy-TextFile (Join-Path $launcher 'START-HERMES-GATEWAY.bat') (Join-Path $HermesHome 'START-HERMES-GATEWAY.bat')
Write-Host ('SillyTavern gateway profile ready: ' + $profile)
