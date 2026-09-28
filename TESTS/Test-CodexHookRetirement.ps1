<# Native Codex hook migration: real isolated homes, never the user's config. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-codex-hooks-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA; $savedCodex = $env:CODEX_HOME; $savedPy = $env:SKYRIM_FORGE_PYTHON; $savedPath = $env:PATH
$powerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
$python = Get-UabsPythonExecutable
$utf8 = New-Object Text.UTF8Encoding($false)
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
  $env:LOCALAPPDATA = Join-Path $fixture ('App Data [x] ' + [char]0xE9)
  $env:CODEX_HOME = Join-Path $fixture 'custom Codex home'
  $env:SKYRIM_FORGE_PYTHON = $python
  New-Item -ItemType Directory -Force -Path $env:CODEX_HOME | Out-Null
  $manifest = Join-Path $env:CODEX_HOME 'hooks.json'
  Assert (@(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly).Count -eq 0) 'Empty home was reported as broken.'
  Repair-UabsCodexLegacyHooks -Path $manifest | Out-Null
  Assert (-not (Test-Path -LiteralPath $manifest)) 'Retirement created a hook manifest on a fresh home.'

  $root = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\hooks'
  $foreign = '"python.exe" "C:\custom\completeness_gate.py" --pre'
  $custom = [ordered]@{type='command';command=$foreign;timeout=7;future=@{keep='yes'}}
  $originalDoc = [ordered]@{
    description='personal metadata'
    hooks=[ordered]@{
      PreToolUse=@(
        [ordered]@{matcher='Bash';hooks=@([ordered]@{type='command';command=('"python.exe" "{0}\completeness_gate.py" --pre' -f $root)}, $custom);future='keep'},
        [ordered]@{matcher='Write';hooks=@([ordered]@{type='command';commandWindows=('"python.exe" "{0}/assumption_gate.py" --pre' -f $root.Replace('\','/'));command='python other.py'})}
      )
      Stop=@([ordered]@{hooks=@([ordered]@{type='command';command=('"python.exe" "{0}\assumption_gate.py" --stop' -f $root)})})
      SessionStart=@([ordered]@{hooks=@([ordered]@{type='command';command='personal-session.cmd'})})
    }
    personal=@{keep=@('a','b')}
  }
  $before = $originalDoc | ConvertTo-Json -Depth 30
  [IO.File]::WriteAllText($manifest, $before, (New-Object Text.UTF8Encoding($true)))
  Assert (@(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly).Count -eq 3) 'Read-only check missed native legacy handlers.'
  Assert ([IO.File]::ReadAllText($manifest) -ceq $before) 'Read-only check changed the config.'
  $beforeHash = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
  Repair-UabsCodexLegacyHooks -Path $manifest | Out-Null
  $after = [IO.File]::ReadAllText($manifest)
  $doc = $after | ConvertFrom-Json
  Assert (@($doc.hooks.PreToolUse).Count -eq 1 -and @($doc.hooks.PreToolUse[0].hooks).Count -eq 1) 'Wrong native handlers survived.'
  Assert ($doc.hooks.PreToolUse[0].hooks[0].command -ceq $foreign -and $doc.hooks.PreToolUse[0].hooks[0].future.keep -eq 'yes') 'Custom sibling or same-basename hook was lost.'
  Assert ($doc.hooks.PreToolUse[0].future -eq 'keep' -and $doc.description -eq 'personal metadata' -and $doc.personal.keep.Count -eq 2) 'Unrelated metadata changed.'
  Assert (@($doc.hooks.Stop).Count -eq 0 -and $doc.hooks.SessionStart[0].hooks[0].command -eq 'personal-session.cmd') 'Empty group or unrelated event was mishandled.'
  $backups = @(Get-ChildItem -LiteralPath $env:CODEX_HOME -Filter 'hooks.json.before-retired-*.bak')
  Assert ($backups.Count -eq 1 -and (Get-FileHash -LiteralPath $backups[0].FullName -Algorithm SHA256).Hash -ceq $beforeHash) 'Exact original bytes were not backed up.'
  Repair-UabsCodexLegacyHooks -Path $manifest | Out-Null
  Assert ([IO.File]::ReadAllText($manifest) -ceq $after -and @(Get-ChildItem -LiteralPath $env:CODEX_HOME -Filter 'hooks.json.before-retired-*.bak').Count -eq 1) 'Repeated repair changed bytes or made another backup.'

  # Exercise the actual installer, including a process-level custom CODEX_HOME.
  [IO.File]::WriteAllText($manifest, $before, $utf8)
  $config = Join-Path $env:CODEX_HOME 'config.toml'
  $trust = "[hooks.state]`npersonal = 'unchanged'`n[plugins.`"completeness-gate@ultimate-bundle`"]`nenabled = true`n"
  [IO.File]::WriteAllText($config, $trust, $utf8)
  $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1') -PackRoot $PackRoot -Providers Codex 2>&1 | Out-String
  Assert ($LASTEXITCODE -eq 0) ('Isolated installer failed: ' + $output)
  Assert (@(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly).Count -eq 0) 'Installer did not retire native Codex hooks.'
  Assert ([IO.File]::ReadAllText($config) -ceq $trust.Replace('enabled = true','enabled = false')) ('Installer changed trust or failed to disable its legacy plugin: ' + ([IO.File]::ReadAllText($config) | ConvertTo-Json -Compress) + ' output: ' + $output)
  $partial = "[plugins.`"completeness-gate@ultimate-bundle`"]`n# no flag here`n[plugins.`"personal@user`"]`nenabled = true`n"
  [IO.File]::WriteAllText($config, $partial, $utf8)
  $null = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1') -PackRoot $PackRoot -Providers Codex 2>&1 | Out-String
  Assert ($LASTEXITCODE -eq 0 -and [IO.File]::ReadAllText($config) -ceq $partial) 'Legacy-plugin cleanup crossed into an unrelated TOML table.'
  [IO.File]::WriteAllText($manifest, $before, $utf8)
  [IO.File]::WriteAllText($config, $trust, $utf8)
  $env:PATH = ''; $env:SKYRIM_FORGE_PYTHON = ''
  $output = & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1') -PackRoot $PackRoot -Providers Codex 2>&1 | Out-String
  Assert ($LASTEXITCODE -eq 0 -and $output.Contains('no working python found')) 'Missing-Python fixture did not exercise the skip path.'
  Assert (@(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly).Count -eq 0 -and [IO.File]::ReadAllText($config) -ceq $trust.Replace('enabled = true','enabled = false')) 'Missing Python prevented legacy retirement.'
  $env:PATH = $savedPath; $env:SKYRIM_FORGE_PYTHON = $python
  $oldBackup = Join-Path $env:CODEX_HOME 'hooks.json.before-retired-00000000000000000000000000000000.bak'
  [IO.File]::WriteAllText($oldBackup, 'old owned backup', $utf8)
  [IO.File]::SetLastWriteTimeUtc($oldBackup, [DateTime]'2000-01-01')
  $personalBackup = Join-Path $env:CODEX_HOME 'hooks.json.personal.bak'
  [IO.File]::WriteAllText($personalBackup, 'keep', $utf8)
  $savedProfile = $env:USERPROFILE
  try {
    $env:USERPROFILE = $fixture
    $output = & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Clean-StaleState.ps1') -PackRoot $PackRoot -SkipSkills -Apply 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq 0) ('Isolated backup pruning failed: ' + $output)
    Assert (@(Get-ChildItem -LiteralPath $env:CODEX_HOME -Filter 'hooks.json.before-retired-*.bak').Count -eq 3) 'Native hook backups exceeded the retention limit.'
    Assert ([IO.File]::ReadAllText($personalBackup) -ceq 'keep') 'Backup pruning removed an unrelated file.'
  } finally { $env:USERPROFILE = $savedProfile }
  [IO.File]::WriteAllText($manifest, '{invalid', $utf8)
  $refused = $false
  try { Repair-UabsCodexLegacyHooks -Path $manifest | Out-Null } catch { $refused = $true }
  Assert ($refused -and [IO.File]::ReadAllText($manifest) -ceq '{invalid') 'Malformed JSON was overwritten.'
  Write-Host 'CODEX HOOK RETIREMENT GATE: PASS'
} finally {
  $env:LOCALAPPDATA = $savedLocal; $env:CODEX_HOME = $savedCodex; $env:SKYRIM_FORGE_PYTHON = $savedPy; $env:PATH = $savedPath
  if (Test-Path -LiteralPath $fixture) {
    if (-not (Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath()))) { throw 'Fixture cleanup escaped its temporary root.' }
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}
