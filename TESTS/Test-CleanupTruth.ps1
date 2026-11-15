<# Clean-StaleState must report what it actually did: a removal that failed is a
   failure (non-zero exit, no "freed" bytes for it), and a provider config is
   never edited unless its backup was written first. Isolated homes only. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-cleanup-truth-' + [guid]::NewGuid().ToString('N'))
$saved = @{ LOCALAPPDATA = $env:LOCALAPPDATA; USERPROFILE = $env:USERPROFILE; CODEX_HOME = $env:CODEX_HOME }
$powerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$utf8 = New-Object Text.UTF8Encoding($false)
$cleaner = Join-Path $PackRoot 'TOOLS\Clean-StaleState.ps1'
$lock = $null
$claudeDir = $null
try {
  $env:USERPROFILE = $fixture
  $env:LOCALAPPDATA = Join-Path $fixture 'Local'
  $env:CODEX_HOME = Join-Path $fixture '.codex'
  $dl = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\downloads'
  New-Item -ItemType Directory -Force -Path $dl | Out-Null
  [IO.File]::WriteAllText((Join-Path $dl 'companions.json'), '{"schema":1,"companions":[{"id":"skyrim-forge","asset":"Skyrim-Forge-1.0.1.zip"}]}', $utf8)
  $stale = Join-Path $dl 'Skyrim-Forge-1.0.0.zip'
  # 20 KB, so a "freed" total that counts the unremoved file is visible (20.0 KB, not 0.0).
  foreach ($n in @('Skyrim-Forge-1.0.0.zip', 'Skyrim-Forge-1.0.1.zip')) { [IO.File]::WriteAllBytes((Join-Path $dl $n), (New-Object byte[] 20480)) }

  # 1. A superseded archive held open by another process cannot be removed.
  $lock = [IO.File]::Open($stale, 'Open', 'Read', 'None')
  $out = & $powerShell -NoProfile -ExecutionPolicy Bypass -File $cleaner -PackRoot $PackRoot -SkipSkills -Apply 2>&1 | Out-String
  $code = $LASTEXITCODE
  $lock.Dispose(); $lock = $null
  Assert (Test-Path -LiteralPath $stale) 'Fixture error: the locked archive was removed.'
  Assert ($code -ne 0) ('A failed removal still exited 0: ' + $out)
  Assert ($out -match 'removed 0 item\(s\), freed ~0\.0 KB') ('Freed bytes counted an item that was not removed: ' + $out)

  # Unlocked, the same run succeeds and exits 0.
  $out = & $powerShell -NoProfile -ExecutionPolicy Bypass -File $cleaner -PackRoot $PackRoot -SkipSkills -Apply 2>&1 | Out-String
  Assert ($LASTEXITCODE -eq 0 -and -not (Test-Path -LiteralPath $stale)) ('Clean run failed: ' + $out)

  # 2. A config whose backup cannot be written is left exactly as it was.
  $claudeDir = Join-Path $fixture '.claude'
  New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
  $settings = Join-Path $claudeDir 'settings.json'
  $deadPlugin = Join-Path $fixture 'gone-pack-v1\BUNDLED-TOOLS\plugins\ponytail'
  $doc = [ordered]@{ theme = 'dark'; extraKnownMarketplaces = [ordered]@{ ponytail = [ordered]@{ source = [ordered]@{ source = 'directory'; path = $deadPlugin } } } }
  [IO.File]::WriteAllText($settings, ($doc | ConvertTo-Json -Depth 8), $utf8)
  $before = [IO.File]::ReadAllText($settings)
  # Deny creating new files in the folder (the backup) while the existing file
  # stays writable: exactly the case where an edit would proceed unbacked.
  $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  $null = & icacls.exe $claudeDir /deny ($user + ':(WD)')
  Assert ($LASTEXITCODE -eq 0) 'Fixture error: could not deny file creation.'
  $out = & $powerShell -NoProfile -ExecutionPolicy Bypass -File $cleaner -PackRoot $PackRoot -SkipSkills -Apply 2>&1 | Out-String
  $code = $LASTEXITCODE
  $null = & icacls.exe $claudeDir /remove:d $user
  Assert ([IO.File]::ReadAllText($settings) -ceq $before) ('settings.json was edited although its backup failed: ' + $out)
  Assert ($code -ne 0) ('An unbacked, skipped edit still exited 0: ' + $out)
  Assert (@(Get-ChildItem -LiteralPath $claudeDir -Filter 'settings.json.bak-retired-*').Count -eq 0) 'Fixture error: a backup was written.'

  # With the folder writable again, the edit happens and is backed up.
  $out = & $powerShell -NoProfile -ExecutionPolicy Bypass -File $cleaner -PackRoot $PackRoot -SkipSkills -Apply 2>&1 | Out-String
  Assert ($LASTEXITCODE -eq 0) ('Backed-up edit failed: ' + $out)
  Assert (([IO.File]::ReadAllText($settings) | ConvertFrom-Json).extraKnownMarketplaces.ponytail.source.path -eq (Join-Path $PackRoot 'BUNDLED-TOOLS\plugins\ponytail')) 'Dead marketplace path was not repointed.'
  Assert (@(Get-ChildItem -LiteralPath $claudeDir -Filter 'settings.json.bak-retired-*').Count -eq 1) 'The edit was not backed up.'
  Write-Host 'CLEANUP TRUTH GATE: PASS'
} finally {
  if ($lock) { $lock.Dispose() }
  if ($claudeDir -and (Test-Path -LiteralPath $claudeDir)) {
    $null = & icacls.exe $claudeDir /remove:d ([Security.Principal.WindowsIdentity]::GetCurrent().Name) 2>$null
  }
  foreach ($k in $saved.Keys) { Set-Item -Path ('env:' + $k) -Value $saved[$k] }
  if (Test-Path -LiteralPath $fixture) {
    if (-not (Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath()))) { throw 'Fixture cleanup escaped its temporary root.' }
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}
