# Exercise Backup-AiHistory.ps1 against a disposable home: it copies new and changed transcripts and
# never deletes, overwrites a newer copy, or writes into a provider folder.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$script = Join-Path $PackRoot 'TOOLS\Backup-AiHistory.ps1'
$ps = (Get-Command powershell.exe -ErrorAction Stop).Source
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Run([string[]]$ArgList) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = (& $ps -NoProfile -ExecutionPolicy Bypass -File $script @ArgList 2>&1 | ForEach-Object { "$_" }) -join "`n" }
  finally { $ErrorActionPreference = $prev }
  return [pscustomobject]@{ Out = $out; Exit = $LASTEXITCODE }
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hist-' + [guid]::NewGuid().ToString('N'))
$saved = @{}; foreach ($k in 'USERPROFILE', 'LOCALAPPDATA', 'HERMES_HOME', 'UABS_HISTORY_DIR') { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
try {
  $fakeHome = Join-Path $fixture 'home'; $dest = Join-Path $fixture 'archive'
  $env:USERPROFILE = $fakeHome; $env:LOCALAPPDATA = Join-Path $fixture 'local'; $env:HERMES_HOME = ''; $env:UABS_HISTORY_DIR = ''
  $claude = Join-Path $fakeHome '.claude\projects\proj'; $codex = Join-Path $fakeHome '.codex\sessions\2026'
  $grok = Join-Path $fakeHome '.grok\sessions'; $hermes = Join-Path $env:LOCALAPPDATA 'hermes\sessions'
  foreach ($d in @($claude, $codex, $grok, $hermes)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  [IO.File]::WriteAllText((Join-Path $claude 'a.jsonl'), 'one'); [IO.File]::WriteAllText((Join-Path $codex 'b.jsonl'), 'two')
  [IO.File]::WriteAllText((Join-Path $grok 'c.json'), 'three');   [IO.File]::WriteAllText((Join-Path $hermes 'd.json'), 'four')
  [IO.File]::WriteAllText((Join-Path $fakeHome '.codex\session_index.jsonl'), 'idx')
  [IO.File]::WriteAllText((Join-Path $fakeHome '.codex\thread_history_1.sqlite'), 'db')

  # 1. Not configured: it says how and does nothing.
  $r = Run @()
  Assert ($r.Exit -eq 0 -and $r.Out -match 'not configured' -and -not (Test-Path -LiteralPath $dest)) 'an unconfigured run wrote something or failed'

  # 2. -CheckOnly lists, copies nothing.
  $r = Run @('-Destination', $dest, '-CheckOnly')
  Assert ($r.Exit -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $dest 'claude'))) '-CheckOnly copied files'

  # 3. A real run copies every transcript store and the Codex index, but not the live SQLite database.
  $r = Run @('-Destination', $dest)
  Assert ($r.Exit -eq 0) ('copy failed: ' + $r.Out)
  foreach ($rel in @('claude\projects\proj\a.jsonl', 'codex\sessions\2026\b.jsonl', 'grok\sessions\c.json', 'hermes\sessions\d.json', 'codex\session_index.jsonl')) {
    Assert (Test-Path -LiteralPath (Join-Path $dest $rel) -PathType Leaf) "not archived: $rel"
  }
  Assert (-not (Test-Path -LiteralPath (Join-Path $dest 'codex\thread_history_1.sqlite'))) 'the live SQLite database was copied'

  # 4. A changed transcript is updated; a deleted source file keeps its archived copy.
  [IO.File]::WriteAllText((Join-Path $claude 'a.jsonl'), 'one-longer')
  Remove-Item -LiteralPath (Join-Path $codex 'b.jsonl')
  $r = Run @('-Destination', $dest)
  Assert ($r.Exit -eq 0) ('second copy failed: ' + $r.Out)
  Assert ([IO.File]::ReadAllText((Join-Path $dest 'claude\projects\proj\a.jsonl')) -ceq 'one-longer') 'a changed transcript was not updated'
  Assert ((Test-Path -LiteralPath (Join-Path $dest 'codex\sessions\2026\b.jsonl')) -and [IO.File]::ReadAllText((Join-Path $dest 'codex\sessions\2026\b.jsonl')) -ceq 'two') 'a transcript deleted at the source was deleted from the archive too'

  # 5. A newer archived copy is never replaced by an older source file.
  $newer = Join-Path $dest 'grok\sessions\c.json'
  [IO.File]::WriteAllText($newer, 'archive-edit'); (Get-Item -LiteralPath $newer).LastWriteTime = (Get-Date).AddDays(1)
  [void](Run @('-Destination', $dest))
  Assert ([IO.File]::ReadAllText($newer) -ceq 'archive-edit') 'an older source overwrote a newer archived copy'

  # 6. The destination can come from the profile file, and may not sit inside a provider folder.
  $cfg = Join-Path $fakeHome '.uabs\profile\HISTORY-DIR.txt'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cfg) | Out-Null
  $fromFile = Join-Path $fixture 'from-file'
  [IO.File]::WriteAllText($cfg, $fromFile + "`r`n")
  $r = Run @()
  Assert ($r.Exit -eq 0 -and (Test-Path -LiteralPath (Join-Path $fromFile 'hermes\sessions\d.json'))) 'HISTORY-DIR.txt was not honoured'
  $r = Run @('-Destination', (Join-Path $fakeHome '.claude\projects\archive'))
  Assert ($r.Exit -ne 0 -and $r.Out -match 'inside') 'a destination inside a provider folder was accepted'

  Write-Host 'AI HISTORY BACKUP GATE: PASS'
} finally {
  foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
