<#
.SYNOPSIS
  Copy AI chat transcripts to a folder that cleaners and retention limits never touch.

.DESCRIPTION
  Claude Code deletes transcripts after 30 days by default, and disk cleaners
  (BleachBits and friends) wipe provider session folders. Both have cost this
  pack's maintainer a project's chat history. This only COPIES: new and changed
  files, never deleting or moving anything, safe to run at any time.

  Destination, first match wins: -Destination, the UABS_HISTORY_DIR environment
  variable, the first line of %USERPROFILE%\.uabs\profile\HISTORY-DIR.txt. With
  none of them set it says how to set one and exits 0, so the installer can call
  it unconditionally. Nothing is uploaded. Transcripts hold whatever you pasted
  into a chat (keys included), so keep the folder private.

  Copied: Claude projects, Codex sessions (+ archived, + index), Grok sessions,
  Hermes sessions. Not copied: Codex's live SQLite thread database (a copy taken
  while it is open can be torn) and provider caches.

.EXAMPLE
  Backup-AiHistory.ps1 -Destination 'D:\AI-History'
  Backup-AiHistory.ps1 -CheckOnly
#>
[CmdletBinding()]
param(
  [string]$Destination,
  [string[]]$Providers = @('Claude', 'Codex', 'Grok', 'Hermes'),
  [switch]$CheckOnly,
  [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

function Say([string]$m, [string]$color = 'Gray') { if (-not $Quiet) { Write-Host $m -ForegroundColor $color } }

if (-not $Destination) { $Destination = [Environment]::GetEnvironmentVariable('UABS_HISTORY_DIR', 'Process') }
if (-not $Destination) { $Destination = [Environment]::GetEnvironmentVariable('UABS_HISTORY_DIR', 'User') }
if (-not $Destination) {
  $cfg = [IO.Path]::Combine($env:USERPROFILE, '.uabs\profile\HISTORY-DIR.txt')
  if ([IO.File]::Exists($cfg)) { $Destination = ([IO.File]::ReadAllLines($cfg) | Where-Object { $_.Trim() } | Select-Object -First 1) }
}
if (-not $Destination) {
  Say 'AI history backup is not configured. Pick a folder outside every provider home, then either'
  Say '  setx UABS_HISTORY_DIR "<folder>"        or put the path on one line in %USERPROFILE%\.uabs\profile\HISTORY-DIR.txt'
  exit 0
}
$Destination = [IO.Path]::GetFullPath($Destination.Trim().Trim('"'))

$userHome = $env:USERPROFILE
$hermes = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { [IO.Path]::Combine($env:LOCALAPPDATA, 'hermes') }
# One row per copy: provider, source, subfolder in the archive, optional single-file filter.
$jobs = @(
  @{ P = 'Claude'; From = [IO.Path]::Combine($userHome, '.claude\projects');          To = 'claude\projects' }
  @{ P = 'Codex';  From = [IO.Path]::Combine($userHome, '.codex\sessions');           To = 'codex\sessions' }
  @{ P = 'Codex';  From = [IO.Path]::Combine($userHome, '.codex\archived_sessions');  To = 'codex\archived_sessions' }
  @{ P = 'Codex';  From = [IO.Path]::Combine($userHome, '.codex');                    To = 'codex'; File = 'session_index.jsonl' }
  @{ P = 'Grok';   From = [IO.Path]::Combine($userHome, '.grok\sessions');            To = 'grok\sessions' }
  @{ P = 'Hermes'; From = [IO.Path]::Combine($hermes, 'sessions');                To = 'hermes\sessions' }
)

$any = $false
foreach ($j in $jobs) {
  if ($Providers -notcontains $j.P) { continue }
  if (-not [IO.Directory]::Exists($j.From)) { continue }
  $from = [IO.Path]::GetFullPath($j.From)
  # A destination inside a source would be copied into itself forever.
  if ($Destination.StartsWith($from.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Destination $Destination is inside $from; pick another folder." }
  $to = [IO.Path]::Combine($Destination, $j.To)
  $roboArgs = @($from, $to)
  if ($j.File) { $roboArgs += $j.File } else { $roboArgs += '/E' }
  # /XO: never replace a newer copy with an older one. No /MIR, /PURGE or /MOV: nothing is ever removed.
  $roboArgs += @('/XO', '/FFT', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
  if ($CheckOnly) { $roboArgs += '/L' }
  $out = & robocopy.exe @roboArgs 2>&1 | Out-String
  # robocopy: 0-7 are success bitmasks (1 = files copied), 8+ is a failure.
  if ($LASTEXITCODE -ge 8) { throw ("robocopy failed for {0} (exit {1}): {2}" -f $j.From, $LASTEXITCODE, $out.Trim()) }
  $any = $true
  Say ("{0,-7} {1} -> {2}{3}" -f $j.P, $j.From, $to, $(if ($LASTEXITCODE -band 1) { '  (new/changed files copied)' } else { '  (up to date)' }))
}
if (-not $any) { Say 'Nothing to copy: no provider session folders were found.' }
else { Say ("History archive: {0}{1}" -f $Destination, $(if ($CheckOnly) { ' (check only: nothing was copied)' } else { '' })) 'Green' }
exit 0
