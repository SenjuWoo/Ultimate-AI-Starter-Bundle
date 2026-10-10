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
$shellDirectory = Get-UabsGitShellDirectory
if ($shellDirectory) { $env:PATH = $shellDirectory + ';' + $env:PATH }
$utf8 = New-Object Text.UTF8Encoding($false)
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Invoke-CodexCmd([string]$Line) {
  # Exactly what Codex does on Windows: cmd.exe /C "<command>" (raw argument).
  $info = New-Object Diagnostics.ProcessStartInfo $env:ComSpec
  $info.Arguments = '/d /c "' + $Line + '"'
  $info.UseShellExecute = $false; $info.RedirectStandardOutput = $true; $info.RedirectStandardError = $true
  $proc = [Diagnostics.Process]::Start($info)
  $err = $proc.StandardError.ReadToEndAsync(); $out = $proc.StandardOutput.ReadToEnd(); $proc.WaitForExit()
  [pscustomobject]@{ Code = $proc.ExitCode; Out = $out + $err.Result }
}
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

  # Obsolete global Impeccable commands must not survive upgrades. Modern
  # hook.mjs entries and similarly labelled custom commands are not ours.
  $impeccableUnix = '[ ! -f ".codex/skills/impeccable/scripts/impeccable" ] || ".codex/skills/impeccable/scripts/impeccable" hook'
  $impeccableWindows = 'if exist ".codex/skills/impeccable/scripts/impeccable.cmd" (".codex/skills/impeccable/scripts/impeccable.cmd" hook & exit /b)'
  $impeccableDoc = [ordered]@{
    personal='keep'
    hooks=[ordered]@{
      Stop=@([ordered]@{hooks=@(
        [ordered]@{type='command';command=$impeccableUnix;commandWindows=$impeccableWindows;timeout=30;statusMessage='Design deep pass'},
        [ordered]@{type='command';command='node ".agents/skills/impeccable/scripts/hook.mjs"';timeout=30;statusMessage='Design deep pass';future='keep'}
      )})
      PostToolUse=@([ordered]@{matcher='Edit|Write|apply_patch';hooks=@([ordered]@{type='command';command=$impeccableUnix;commandWindows=$impeccableWindows;timeout=5;statusMessage='Checking UI changes'})})
      PreToolUse=@([ordered]@{matcher='Write';hooks=@([ordered]@{type='command';command='personal-hook';commandWindows=$impeccableWindows;statusMessage='Checking UI changes'})})
    }
  }
  [IO.File]::WriteAllText($manifest, ($impeccableDoc | ConvertTo-Json -Depth 30), $utf8)
  $impeccableHash = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash
  Assert (@(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly).Count -eq 2) 'Read-only check missed the two broken Impeccable Windows overrides.'
  Assert ((Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash -ceq $impeccableHash) 'Impeccable read-only check wrote the manifest.'
  $trustBefore = [IO.File]::ReadAllText($config)
  $output = & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1') -PackRoot $PackRoot -Providers Codex 2>&1 | Out-String
  Assert ($LASTEXITCODE -eq 0) ('Impeccable upgrade failed: ' + $output)
  Assert ([IO.File]::ReadAllText($config) -ceq $trustBefore) 'Impeccable repair changed hook trust or unrelated settings.'
  $doc = [IO.File]::ReadAllText($manifest) | ConvertFrom-Json
  Assert (@(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly).Count -eq 0) 'Impeccable overrides still need repair.'
  Assert ($doc.personal -eq 'keep' -and $doc.hooks.Stop[0].hooks[0].future -eq 'keep') 'Impeccable retirement lost metadata.'
  Assert (@($doc.hooks.Stop).Count -eq 1 -and @($doc.hooks.Stop[0].hooks).Count -eq 1 -and $doc.hooks.Stop[0].hooks[0].command -ceq 'node ".agents/skills/impeccable/scripts/hook.mjs"' -and $doc.hooks.Stop[0].hooks[0].timeout -eq 30 -and $doc.hooks.Stop[0].hooks[0].statusMessage -eq 'Design deep pass') 'Retirement removed or changed a current hook.mjs handler.'
  Assert (@($doc.hooks.PostToolUse).Count -eq 0) 'Obsolete global post-edit handler survived.'
  Assert ($doc.hooks.PreToolUse[0].hooks[0].commandWindows -ceq $impeccableWindows) 'Repair rewrote a similarly labelled custom hook without exact ownership.'
  $impeccableBackups = @(Get-ChildItem -LiteralPath $env:CODEX_HOME -Filter 'hooks.json.before-retired-*.bak')
  Assert (@($impeccableBackups | Where-Object { (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash -ceq $impeccableHash }).Count -eq 1) 'Impeccable original bytes were not backed up exactly once.'
  $repairedBytes = [IO.File]::ReadAllText($manifest)
  Repair-UabsCodexLegacyHooks -Path $manifest | Out-Null
  Assert ([IO.File]::ReadAllText($manifest) -ceq $repairedBytes -and @(Get-ChildItem -LiteralPath $env:CODEX_HOME -Filter 'hooks.json.before-retired-*.bak').Count -eq $impeccableBackups.Count) 'Repeated Impeccable repair wrote another backup.'

  # Retire only the upstream-generated, unconditional indexing reminders.
  # Gated or personal same-basename hooks must stay untouched.
  $cbmDir = Join-Path $env:CODEX_HOME 'hooks'
  New-Item -ItemType Directory -Path $cbmDir -Force | Out-Null
  $cbm = Join-Path $cbmDir 'cbm-session-reminder'
  [IO.File]::WriteAllText($cbm, "#!/bin/bash`ncat << 'REMINDER'`nCRITICAL - Code Discovery Protocol:`nrun index_repository FIRST.`nREMINDER`n", $utf8)
  $cbmDoc = @{ hooks=@{SessionStart=@(@{matcher='startup';hooks=@(
    @{type='command';command=("'" + $cbm + "'")},
    @{type='command';command="'C:\personal\cbm-session-reminder'"}
  )})} }
  [IO.File]::WriteAllText($manifest, ($cbmDoc | ConvertTo-Json -Depth 20), $utf8)
  Assert (@(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly).Count -eq 1) 'Unconditional legacy CBM indexing reminder was missed.'
  Repair-UabsCodexLegacyHooks -Path $manifest | Out-Null
  $cbmAfter = [IO.File]::ReadAllText($manifest) | ConvertFrom-Json
  Assert ($cbmAfter.hooks.SessionStart[0].hooks.Count -eq 1 -and $cbmAfter.hooks.SessionStart[0].hooks[0].command -ceq "'C:\personal\cbm-session-reminder'") 'CBM migration removed a personal hook.'
  [IO.File]::WriteAllText($cbm, "#!/bin/bash`ntest -x /no-cbm-registered || exit 0`ncat << 'REMINDER'`nCRITICAL - Code Discovery Protocol:`nrun index_repository FIRST.`nREMINDER`n", $utf8)
  [IO.File]::WriteAllText($manifest, ($cbmDoc | ConvertTo-Json -Depth 20), $utf8)
  # Codex on Windows runs `cmd.exe /C "<command>"`; prove the quoted bash path
  # really cannot start there, then that the added commandWindows can.
  $quoted = "'" + $cbm + "'"
  Assert ((Invoke-CodexCmd $quoted).Code -ne 0) 'cmd.exe unexpectedly ran a quoted bash script.'
  $gated = @(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly)
  if ($shellDirectory) {
    Assert ($gated.Count -eq 1 -and $gated[0] -match 'Windows command') ('A user-gated reminder was not given a Windows command: ' + ($gated -join '; '))
    Repair-UabsCodexLegacyHooks -Path $manifest | Out-Null
    $g = @(([IO.File]::ReadAllText($manifest) | ConvertFrom-Json).hooks.SessionStart[0].hooks)
    Assert ($g.Count -eq 2 -and $g[0].command -ceq $quoted -and $g[0].commandWindows -like '*bash.exe" "*/cbm-session-reminder"') 'Gated reminder was lost or not wrapped for Windows.'
    Assert ($g[1].command -ceq "'C:\personal\cbm-session-reminder'" -and -not $g[1].PSObject.Properties['commandWindows']) 'A hook outside CODEX_HOME\hooks was rewritten.'
    $run = Invoke-CodexCmd $g[0].commandWindows
    Assert ($run.Code -eq 0 -and -not $run.Out.Trim()) ('Windows command did not run the gated script quietly: ' + $run.Out)
    Assert (@(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly).Count -eq 0) 'Windows command repair is not idempotent.'
  } else {
    Assert ($gated.Count -eq 1 -and $gated[0] -match 'Git for Windows') 'Missing Git was not reported for a bash-only hook.'
  }

  # The ungated subagent reminder steers every subagent at profile-gated tools.
  $sub = Join-Path $cbmDir 'cbm-subagent-reminder'
  [IO.File]::WriteAllText($sub, "#!/usr/bin/env bash`ncat << 'REMINDER'`n{""hookSpecificOutput"":{""additionalContext"":""Code discovery: prefer codebase-memory-mcp tools (search_graph)""}}`nREMINDER`n", $utf8)
  $subDoc = @{ hooks=@{SubagentStart=@(@{matcher='*';hooks=@(@{type='command';command=("'" + $sub + "'")})})} }
  [IO.File]::WriteAllText($manifest, ($subDoc | ConvertTo-Json -Depth 20), $utf8)
  Repair-UabsCodexLegacyHooks -Path $manifest | Out-Null
  Assert (@(([IO.File]::ReadAllText($manifest) | ConvertFrom-Json).hooks.SubagentStart).Count -eq 0) 'Ungated subagent reminder survived.'

  # Retired [features] keys: only that exact line in [features] goes.
  $cfg = Join-Path $env:CODEX_HOME 'config.toml'
  $toml = "model = 'x'`r`n[features]`r`nmemories = true`r`nrmcp_client = true`r`n`r`n[mcp_servers.demo]`r`nrmcp_client = true`r`nurl = 'https://example.invalid/mcp'`r`n"
  [IO.File]::WriteAllText($cfg, $toml, $utf8)
  Assert (@(Repair-UabsCodexRetiredFeatures -CodexHome $env:CODEX_HOME -CheckOnly).Count -eq 1 -and [IO.File]::ReadAllText($cfg) -ceq $toml) 'Check-only feature cleanup changed config or missed the key.'
  Repair-UabsCodexRetiredFeatures -CodexHome $env:CODEX_HOME | Out-Null
  Assert ([IO.File]::ReadAllText($cfg) -ceq $toml.Replace("rmcp_client = true`r`n`r`n", "`r`n")) ('Feature cleanup touched more than the retired key: ' + [IO.File]::ReadAllText($cfg))
  Assert (@(Repair-UabsCodexRetiredFeatures -CodexHome $env:CODEX_HOME -CheckOnly).Count -eq 0) 'Feature cleanup is not idempotent.'

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
