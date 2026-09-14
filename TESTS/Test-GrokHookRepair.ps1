<# Regression for config-reset hook duplication. Uses temp fixtures only. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('uabs-grok-hooks-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixtureRoot | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
try {
  foreach ($newline in @("`n", "`r`n")) {
    $config = Join-Path $fixtureRoot ('config-' + $newline.Length + '.toml')
    $original = @('[ui]', 'compact_mode = true', '[compat.claude]', 'hooks = true # keep comment', 'mcps = true', 'skills = true', 'rules = false', 'future_setting = "keep"', '[mcp_servers.personal]', 'command = "personal-server"', '') -join $newline
    [IO.File]::WriteAllText($config, $original, $utf8)
    Set-UabsGrokCompatCells -ConfigPath $config -HooksOnly
    $actual = [IO.File]::ReadAllText($config)
    Assert ($actual -ceq $original.Replace('hooks = true', 'hooks = false')) 'Hook-only repair changed an unrelated byte.'
    $backups = @(Get-ChildItem -LiteralPath $fixtureRoot -Filter ([IO.Path]::GetFileName($config) + '.before-compat-*.bak'))
    Assert ($backups.Count -eq 1) 'Original config was not backed up.'
    Assert ([IO.File]::ReadAllText($backups[0].FullName) -ceq $original) 'Backup differs from original.'
    Set-UabsGrokCompatCells -ConfigPath $config -HooksOnly
    Assert ([IO.File]::ReadAllText($config) -ceq $actual) 'Repeated hook repair is not idempotent.'
    Assert (@(Get-ChildItem -LiteralPath $fixtureRoot -Filter ([IO.Path]::GetFileName($config) + '.before-compat-*.bak')).Count -eq 1) 'No-op repair created another backup.'
    Set-UabsGrokCompatCells -ConfigPath $config
    $actual = [IO.File]::ReadAllText($config)
    $expected = $original.Replace('hooks = true','hooks = false').Replace('mcps = true','mcps = false').Replace('skills = true','skills = false')
    Assert ($actual -ceq $expected) 'Full repair dropped user keys or later MCP sections.'
    Set-UabsGrokCompatCells -ConfigPath $config -AllowMcp
    Assert ([IO.File]::ReadAllText($config) -ceq $expected.Replace('mcps = false','mcps = true')) 'Explicit inherited MCP preference not honored.'
  }
  $fresh = Join-Path $fixtureRoot 'fresh.toml'
  Set-UabsGrokCompatCells -ConfigPath $fresh -HooksOnly
  $freshText = [IO.File]::ReadAllText($fresh)
  Assert ($freshText -match '(?m)^hooks = false$') 'Fresh hook repair missing its setting.'
  Assert ($freshText -notmatch 'mcps|skills') 'Fresh hook-only repair imposed unrelated defaults.'
  $missing = Join-Path $fixtureRoot 'missing-section.toml'
  [IO.File]::WriteAllText($missing, "[ui]`ncompact_mode = true`n", $utf8)
  Set-UabsGrokCompatCells -ConfigPath $missing -HooksOnly
  Assert ([IO.File]::ReadAllText($missing).StartsWith("[ui]`ncompact_mode = true`n")) 'Missing-section repair overwrote existing config.'
  $invalid = Join-Path $fixtureRoot 'invalid.toml'
  $invalidText = "[compat.claude]`nhooks = 'invalid'`n"
  [IO.File]::WriteAllText($invalid, $invalidText, $utf8)
  $refused = $false
  try { Set-UabsGrokCompatCells -ConfigPath $invalid -HooksOnly } catch { $refused = $true }
  Assert ($refused -and [IO.File]::ReadAllText($invalid) -ceq $invalidText) 'Invalid owned cell was silently rewritten.'

  $inspection = [pscustomobject]@{
    externalCompat = [pscustomobject]@{ cells = @([pscustomobject]@{vendor='claude';surface='hooks';enabled=$true}) }
    hooks = @(
      [pscustomobject]@{event='stop'; target='& "python.exe" "completeness_gate.py" --stop';source=[pscustomobject]@{type='user';path=(Join-Path (Get-UabsProviderHome -Provider Grok -Catalog (Get-UabsCatalog)) 'hooks')}},
      [pscustomobject]@{event='stop'; target='"python.exe" "completeness_gate.py" --stop';source=[pscustomobject]@{type='user';path='C:\fixture\.claude'}}
    )
  }
  Assert (@(Get-UabsGrokHookIssues -Inspection $inspection).Count -eq 1) 'Inherited duplicate was not detected.'
  $inspection.externalCompat.cells[0].enabled = $false
  Assert (@(Get-UabsGrokHookIssues -Inspection $inspection).Count -eq 0) 'Disabled discovery was misreported as active.'
  $inspection.hooks[0].target = '"python.exe" "completeness_gate.py" --stop'
  Assert (@(Get-UabsGrokHookIssues -Inspection $inspection).Count -eq 1) 'Broken native PowerShell command was not detected.'
  $bash = '[ ! -f ".grok/skills/impeccable/scripts/impeccable" ] || ".grok/skills/impeccable/scripts/impeccable" hook'
  $inspection.hooks[0].target = $bash
  Assert (@(Get-UabsGrokHookIssues -Inspection $inspection).Count -eq 1) 'Unmanaged Impeccable Bash syntax was missed.'
  $inspection.hooks[0].source = [pscustomobject]@{type='user';path='C:\fixture\custom Grok home\hooks'}
  Assert (@(Get-UabsGrokHookIssues -Inspection $inspection -HooksDir 'C:\fixture\custom Grok home\hooks').Count -eq 1) 'Custom Grok home escaped hook syntax checking.'
  $inspection.hooks[0].source.path = Join-Path (Get-UabsProviderHome -Provider Grok -Catalog (Get-UabsCatalog)) 'hooks'
  $hookPath = Join-Path $fixtureRoot 'impeccable.json'
  $hookDoc = @{hooks=@{PostToolUse=@(@{matcher='Edit|Write|MultiEdit';hooks=@(@{command=$bash;timeout=5})});Stop=@(@{hooks=@(@{command=$bash;timeout=30})})};personal='keep'}
  $original = $hookDoc | ConvertTo-Json -Depth 10
  [IO.File]::WriteAllText($hookPath, $original, $utf8)
  Repair-UabsGrokImpeccableHook -Path $hookPath
  $repaired = [IO.File]::ReadAllText($hookPath)
  $parsed = $repaired | ConvertFrom-Json
  Assert ($parsed.personal -eq 'keep' -and $parsed.hooks.Stop[0].hooks[0].timeout -eq 30) 'Hook repair changed unrelated settings.'
  $fixed = $parsed.hooks.PostToolUse[0].hooks[0].command
  Assert ($fixed -eq $parsed.hooks.Stop[0].hooks[0].command -and $fixed -ne $bash) 'Both legacy commands were not repaired.'
  $inspection.hooks[0].target = $fixed
  Assert (@(Get-UabsGrokHookIssues -Inspection $inspection).Count -eq 0) 'Repaired Impeccable is not valid PowerShell.'
  Repair-UabsGrokImpeccableHook -Path $hookPath
  Assert ([IO.File]::ReadAllText($hookPath) -ceq $repaired) 'Hook repair is not idempotent.'
  $backups = @(Get-ChildItem -LiteralPath $fixtureRoot -Filter 'impeccable.json.before-powershell-*.bak')
  Assert ($backups.Count -eq 1 -and [IO.File]::ReadAllText($backups[0].FullName) -ceq $original) 'Hook backup missing, duplicated or altered.'
  $custom = $original.Replace($bash.Replace('"','\"'), 'Write-Output custom')
  [IO.File]::WriteAllText($hookPath, $custom, $utf8)
  Repair-UabsGrokImpeccableHook -Path $hookPath
  Assert ([IO.File]::ReadAllText($hookPath) -ceq $custom) 'Unknown custom hook was overwritten.'
  $project = Join-Path $fixtureRoot ('project ! ' + [char]0x00E9)
  New-Item -ItemType Directory -Path $project | Out-Null
  Push-Location -LiteralPath $project
  try {
    $global:LASTEXITCODE = 0
    & ([scriptblock]::Create($fixed))
    Assert ($LASTEXITCODE -eq 0) 'Absent project launcher was not a silent no-op.'
    $scripts = Join-Path $project '.grok\skills\impeccable\scripts'
    New-Item -ItemType Directory -Force -Path $scripts | Out-Null
    [IO.File]::WriteAllText((Join-Path $scripts 'impeccable.cmd'), "@echo off`r`nif not `"%1`"==`"hook`" exit /b 8`r`necho called>proof.txt`r`nexit /b 0`r`n", $utf8)
    & ([scriptblock]::Create($fixed))
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $project 'proof.txt'))) 'Project launcher did not receive hook in a spaces/Unicode/! path.'
  } finally { Pop-Location }
  $inspection.externalCompat.cells = @()
  $refused = $false
  try { Get-UabsGrokHookIssues -Inspection $inspection | Out-Null } catch { $refused = $true }
  Assert $refused 'Unknown inspect schema was silently accepted.'
  Write-Host 'GROK HOOK REPAIR GATE: PASS'
} finally {
  $resolved = (Resolve-Path -LiteralPath $fixtureRoot).Path
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($resolved) -notlike 'uabs-grok-hooks-*') { throw 'Unsafe fixture cleanup target.' }
  Remove-Item -LiteralPath $resolved -Recurse -Force
}
