<# Native Codex hook migration: real isolated homes, never the user's config. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-codex-hooks-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA; $savedCodex = $env:CODEX_HOME; $savedPy = $env:SKYRIM_FORGE_PYTHON; $savedPath = $env:PATH; $savedShared = $env:UABS_PYTHON
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
  $env:PATH = ''; $env:SKYRIM_FORGE_PYTHON = ''; $env:UABS_PYTHON = $null
  $output = & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1') -PackRoot $PackRoot -Providers Codex 2>&1 | Out-String
  Assert ($LASTEXITCODE -eq 0 -and $output.Contains('no working python found')) 'Missing-Python fixture did not exercise the skip path.'
  Assert (@(Repair-UabsCodexLegacyHooks -Path $manifest -CheckOnly).Count -eq 0 -and [IO.File]::ReadAllText($config) -ceq $trust.Replace('enabled = true','enabled = false')) 'Missing Python prevented legacy retirement.'
  $env:PATH = $savedPath; $env:SKYRIM_FORGE_PYTHON = $python; $env:UABS_PYTHON = $savedShared
  $oldBackup = Join-Path $env:CODEX_HOME 'hooks.json.before-retired-00000000000000000000000000000000.bak'
  [IO.File]::WriteAllText($oldBackup, 'old owned backup', $utf8)
  [IO.File]::SetLastWriteTimeUtc($oldBackup, [DateTime]'2000-01-01')
  $personalBackup = Join-Path $env:CODEX_HOME 'hooks.json.personal.bak'
  [IO.File]::WriteAllText($personalBackup, 'keep', $utf8)
  # Older-version leftovers in the (sandboxed) state folder: only superseded
  # copies go; the record, unrecorded files, live toolchains and backups stay.
  $stateRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
  $dl = Join-Path $stateRoot 'downloads'; New-Item -ItemType Directory -Force -Path $dl | Out-Null
  [IO.File]::WriteAllText((Join-Path $dl 'companions.json'), '{"schema":1,"companions":[{"id":"skyrim-forge","asset":"Skyrim-Forge-1.0.1.zip"}]}', $utf8)
  foreach ($n in @('Skyrim-Forge-1.0.0.zip','Skyrim-Forge-1.0.1.zip','Other-Tool-2.0.0.zip')) { [IO.File]::WriteAllText((Join-Path $dl $n), 'zip', $utf8) }
  $tc = Join-Path $stateRoot 'toolchains'; New-Item -ItemType Directory -Force -Path (Join-Path $tc 'go1.2.3\go.backup-x') | Out-Null
  foreach ($n in @('go1.2.3.zip','go-current.zip')) { [IO.File]::WriteAllText((Join-Path $tc $n), 'zip', $utf8) }
  New-Item -ItemType Directory -Force -Path (Join-Path $stateRoot 'ponytail-mode') | Out-Null
  [IO.File]::WriteAllText((Join-Path $stateRoot 'ponytail-mode.json'), '{"mode":"off"}', $utf8)
  [IO.File]::WriteAllText((Join-Path $stateRoot 'ponytail-mode\state.json'), '{"mode":"off"}', $utf8)
  $park = Join-Path $stateRoot 'ponytail-mode\parked\Grok'
  foreach ($d in @('ponytail__abc1234567', '_duplicates\ponytail__20260101T000000Z', '_duplicates\ponytail__20260102T000000Z')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $park $d) | Out-Null
  }
  [IO.File]::WriteAllText((Join-Path $park 'ponytail__abc1234567\SKILL.md'), 'same', $utf8)
  [IO.File]::WriteAllText((Join-Path $park '_duplicates\ponytail__20260101T000000Z\SKILL.md'), 'same', $utf8)
  [IO.File]::WriteAllText((Join-Path $park '_duplicates\ponytail__20260102T000000Z\SKILL.md'), 'edited', $utf8)
  $claudeDir = Join-Path $fixture '.claude'; New-Item -ItemType Directory -Force -Path $claudeDir | Out-Null
  $deadPlugin = Join-Path $fixture 'gone-pack-v1\BUNDLED-TOOLS\plugins\ponytail'
  $deadOther = Join-Path $fixture 'gone-elsewhere\my-market'
  $settingsDoc = [ordered]@{ theme = 'dark'; extraKnownMarketplaces = [ordered]@{
    ponytail = [ordered]@{ source = [ordered]@{ source = 'directory'; path = $deadPlugin } }
    mine = [ordered]@{ source = [ordered]@{ source = 'directory'; path = $deadOther } } } }
  [IO.File]::WriteAllText((Join-Path $claudeDir 'settings.json'), ($settingsDoc | ConvertTo-Json -Depth 8), $utf8)
  $savedProfile = $env:USERPROFILE
  try {
    $env:USERPROFILE = $fixture
    $output = & $powerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Clean-StaleState.ps1') -PackRoot $PackRoot -SkipSkills -Apply 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq 0) ('Isolated backup pruning failed: ' + $output)
    Assert (@(Get-ChildItem -LiteralPath $env:CODEX_HOME -Filter 'hooks.json.before-retired-*.bak').Count -eq 3) 'Native hook backups exceeded the retention limit.'
    Assert ([IO.File]::ReadAllText($personalBackup) -ceq 'keep') 'Backup pruning removed an unrelated file.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $dl 'Skyrim-Forge-1.0.0.zip'))) 'A superseded companion archive survived.'
    Assert ((Test-Path -LiteralPath (Join-Path $dl 'Skyrim-Forge-1.0.1.zip')) -and (Test-Path -LiteralPath (Join-Path $dl 'Other-Tool-2.0.0.zip'))) 'The recorded or an unrecorded archive was removed.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $tc 'go1.2.3.zip'))) 'The pre-8.24 Go archive survived.'
    Assert ((Test-Path -LiteralPath (Join-Path $tc 'go-current.zip')) -and (Test-Path -LiteralPath (Join-Path $tc 'go1.2.3\go.backup-x'))) 'The Go cache, SDK folder or its backup was removed.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $stateRoot 'ponytail-mode.json'))) 'The superseded ponytail-mode.json survived.'
    $after = [IO.File]::ReadAllText((Join-Path $claudeDir 'settings.json')) | ConvertFrom-Json
    Assert ($after.extraKnownMarketplaces.ponytail.source.path -eq (Join-Path $PackRoot 'BUNDLED-TOOLS\plugins\ponytail')) 'A dead bundled marketplace path was not repointed.'
    Assert ($after.extraKnownMarketplaces.mine.source.path -eq $deadOther -and $after.theme -eq 'dark') 'An unrelated marketplace or setting was changed.'
    Assert (@(Get-ChildItem -LiteralPath $claudeDir -Filter 'settings.json.bak-retired-*').Count -eq 1) 'settings.json was edited without a backup.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $park '_duplicates\ponytail__20260101T000000Z'))) 'An identical parked duplicate survived.'
    Assert ((Test-Path -LiteralPath (Join-Path $park 'ponytail__abc1234567\SKILL.md')) -and (Test-Path -LiteralPath (Join-Path $park '_duplicates\ponytail__20260102T000000Z'))) 'The archived copy or a differing duplicate was removed.'
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
  $env:LOCALAPPDATA = $savedLocal; $env:CODEX_HOME = $savedCodex; $env:SKYRIM_FORGE_PYTHON = $savedPy; $env:PATH = $savedPath; $env:UABS_PYTHON = $savedShared
  if (Test-Path -LiteralPath $fixture) {
    if (-not (Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath()))) { throw 'Fixture cleanup escaped its temporary root.' }
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}
