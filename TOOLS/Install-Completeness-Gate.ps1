<#
.SYNOPSIS
  Install the completeness gate, assumption gate, and narrow RTK output hook
  using each provider's real hook mechanism.

.DESCRIPTION
  Three controls, same three design rules (precise, cheap, fail open):

    completeness_gate.py  refuses a push, and refuses to end a turn, while a
                          release is internally inconsistent - a version bumped
                          without a changelog entry, a README left declaring the
                          old version, source changes left uncommitted.
    assumption_gate.py    refuses a path nobody verified and code nobody read -
                          a drive letter that does not exist on this machine,
                          another user's home directory hardcoded into a script,
                          remote content piped straight into a shell.
    rtk_safe_hook.py      rewrites only exact status and standalone
                          human-facing pytest/cargo/go tests. It never blocks.

  v6.8.0 wired every provider by dropping the same JSON into
  `~/.<provider>/hooks/`. That was an assumption, and it was wrong for three of
  the five. Each provider is now installed the way it actually loads hooks,
  verified against its own documentation or CLI:

    Claude  ~/.claude/settings.json          hooks key, merged. VERIFIED.
    Grok    ~/.grok/hooks/*.json             always trusted, no folder-trust
                                             needed. VERIFIED against Grok's
                                             own docs/user-guide/10-hooks.md.
    Codex   skills/native-plugin rules      Codex supports native hooks.json and
                                             plugin hooks, with trust review.
                                             The bundle does not forge trust or
                                             install its executable gates there.
                                             Legacy bundle handlers in native
                                             hooks.json are backed up/retired;
                                             obsolete global Impeccable
                                             executable hooks are retired;
                                             custom handlers are preserved.
    Hermes  the path `hermes config path`    NOT ~/.hermes/config.yaml. Hermes's
            reports                          own docs name that path; the
                                             resolved one honours HERMES_HOME.
                                             v6.8.1 shipped an installer that
                                             still wrote to the documented path
                                             and detected Hermes by testing for
                                             a directory a working install does
                                             not have. Both are fixed here by
                                             asking the tool instead.
    Kimi    GATE NOT WIRED                   Both halves of the old claim here
                                             (`no hook or plugin system`) are
                                             false. v7.7.0 established the
                                             plugin system and the AIO installer
                                             now uses it. The shipped binary also
                                             carries a hook engine - PreToolUse,
                                             PostToolUse and Stop - fed from
                                             `config.hooks` plus every enabled
                                             plugin's own hooks. What is NOT
                                             established is the exact config
                                             schema those entries take, so this
                                             script does not write one: guessing
                                             it would corrupt a working
                                             config.toml. Kimi gets the skills
                                             and the native plugin, not the gate.
                                             ~/.kimi-code/hooks is still not a
                                             path Kimi reads, so files dropped
                                             there are still removed.

.PARAMETER CheckOnly
  Report what would change and exit.

.PARAMETER Uninstall
  Remove all three bundle controls from the selected providers.
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  [string[]]$Providers = @('Claude', 'Grok', 'Codex', 'Hermes'),
  [switch]$CheckOnly,
  [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

# powershell.exe -File serializes Claude,Codex as one comma-delimited string.
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$AllowedProviders = @('Claude','Grok','Codex','Hermes','Kimi','Antigravity')
foreach ($ProviderName in $Providers) { if ($AllowedProviders -notcontains $ProviderName) { throw "Unknown provider: $ProviderName" } }

# Windows PowerShell 5.1's `Set-Content -Encoding utf8` writes a UTF-8 BOM, and a
# strict JSON reader rejects a file that starts with one. This pack exists partly
# because a BOM once made seven skills invisible.
function Set-Utf8NoBom {
  param([string]$Path, [string]$Text)
  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $Text, $enc)
}

if (-not $PackRoot) {
  $here = $PSScriptRoot
  if (-not $here -and $PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
  if (-not $here) { $here = (Get-Location).Path }
  $PackRoot = Split-Path -Parent $here
}
$hooksSrc  = Join-Path $PackRoot 'TOOLS\hooks'
$pluginSrc = Join-Path $hooksSrc 'plugin'
$wireSrc   = Join-Path $hooksSrc 'hermes_wire.py'

# Share the verified Python resolver and configuration merge with the AIO.
$v7Common = Join-Path $PackRoot 'TOOLS\UABS-Common.ps1'
. $v7Common

if (-not $Uninstall) {
  foreach ($issue in @(Repair-UabsHookShellPath -CheckOnly:$CheckOnly)) { Write-Host $issue }
}

# Every gate the pack ships, with the tools each one needs to see.
$gates = @(
  @{ Name = 'completeness_gate.py'; Matcher = 'Bash|Shell|Terminal|PowerShell|run_command|execute_command'; AllTools = $false; Stop = $true }
  @{ Name = 'assumption_gate.py';   Matcher = 'Bash|Shell|Terminal|PowerShell|run_command|execute_command|Write|Edit|MultiEdit|NotebookEdit|write_file|create_file|str_replace.*'; AllTools = $true; Stop = $true }
  @{ Name = 'rtk_safe_hook.py';     Matcher = 'Bash|Shell|Terminal|PowerShell|run_command|execute_command'; AllTools = $false; Stop = $false }
)
foreach ($g in $gates) {
  if (-not (Test-Path -LiteralPath (Join-Path $hooksSrc $g.Name))) { throw "$($g.Name) not found under $hooksSrc" }
}

$installRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\hooks'
$marketRoot  = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\codex-marketplace'
# hermes_wire.py inherits this process. The retired folder name stays in
# Get-UabsLegacyHookRoots; the wire script only receives the path.
$legacyHookRoot = @(Get-UabsLegacyHookRoots) | Select-Object -First 1
if ($legacyHookRoot) { $env:UABS_LEGACY_HOOK_ROOT = $legacyHookRoot }

# Retirement must also work without Python and during uninstall/check-only.
$codexHome = Get-UabsProviderHome -Provider Codex -Catalog (Get-UabsCatalog)
if ($Providers -contains 'Codex') {
  if (-not $Uninstall) {
    foreach ($issue in @(Repair-UabsCodexDuplicatePlugins -CodexHome $codexHome -CheckOnly:$CheckOnly)) { Write-Host $issue }
    foreach ($issue in @(Repair-UabsCodexRetiredFeatures -CodexHome $codexHome -CheckOnly:$CheckOnly)) { if ($CheckOnly) { Write-Host ('Codex   needs repair: ' + $issue) } }
  }
  foreach ($issue in @(Repair-UabsCodexLegacyHooks -Path (Join-Path $codexHome 'hooks.json') -CheckOnly:$CheckOnly)) {
    if ($CheckOnly) { Write-Host ('Codex   needs repair: ' + $issue) }
  }
  $codexConfig = Join-Path $codexHome 'config.toml'
  if ((Test-Path -LiteralPath $codexConfig) -and -not $CheckOnly) {
    # Only our retired plugin flag; never synthesize [hooks.state] trust hashes.
    $toml = [IO.File]::ReadAllText($codexConfig)
    $updated = [regex]::Replace($toml,
      '(?ms)(^\[plugins\."completeness-gate@ultimate-bundle"\][^\r\n]*\r?\n(?:(?!^\[).)*?^enabled[ \t]*=[ \t]*)true\b', '${1}false')
    if ($updated -ne $toml) {
      Copy-Item -LiteralPath $codexConfig -Destination "$codexConfig.bak-gate-$(Get-Date -Format yyyyMMdd-HHmmssfff)" -Force
      Set-Utf8NoBom -Path $codexConfig -Text $updated
    }
  }
}

$python = Get-UabsPythonExecutable
if (-not $python) {
  Write-Host 'SKIP: no working python found. Install Python 3.9+ and re-run.' -ForegroundColor Yellow
  if (@($Providers | Where-Object { $_ -in @('Claude','Grok','Hermes') }).Count) { throw 'Required provider gates need a working Python interpreter.' }
  exit 0
}

function Test-BundleHookCommand([string]$Command) {
  # Recognize the generated command shape and the full owned script path.
  # A personal completeness_gate.py elsewhere, or a chained custom command,
  # is not ours to remove merely because the basename matches.
  $shape = '^\s*(?:&\s+)?(?:"[^"]+"|''[^'']+''|[^\s"'']+)\s+(?:"(?<double>[^"]+)"|''(?<single>[^'']+)''|(?<plain>[^\s"'']+))\s+--(?:pre|stop)\s*$'
  $match = [regex]::Match($Command, $shape)
  if (-not $match.Success) { return $false }
  $scriptPath = @('double','single','plain' | ForEach-Object { $match.Groups[$_].Value } | Where-Object { $_ }) | Select-Object -First 1
  try { $scriptPath = [IO.Path]::GetFullPath($scriptPath.Replace('/','\')) } catch { return $false }
  $hookRoots = @($installRoot) + @(Get-UabsLegacyHookRoots)
  foreach ($root in @($hookRoots | Where-Object { $_ })) {
    foreach ($gate in $gates) {
      if ($scriptPath -ieq [IO.Path]::GetFullPath((Join-Path $root $gate.Name))) { return $true }
    }
  }
  return $false
}

function Backup-ProviderHookFile([string]$Path) {
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw ('Refusing to replace a linked hook file: ' + $Path) }
  $backup = $Path + '.before-retired-' + [guid]::NewGuid().ToString('N') + '.bak'
  [IO.File]::WriteAllBytes($backup, [IO.File]::ReadAllBytes($Path))
  if ((Get-FileHash -LiteralPath $backup -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash) {
    throw ('Hook backup verification failed: ' + $Path)
  }
}

function Test-EntireBundleHookDocument($Document) {
  if (@($Document.PSObject.Properties.Name | Where-Object { $_ -ne 'hooks' }).Count -or -not $Document.hooks) { return $false }
  $count = 0
  foreach ($event in $Document.hooks.PSObject.Properties) {
    if ($event.Name -notin @('PreToolUse','Stop')) { return $false }
    foreach ($group in @($event.Value)) {
      if (@($group.PSObject.Properties.Name | Where-Object { $_ -notin @('matcher','hooks') }).Count) { return $false }
      foreach ($handler in @($group.hooks)) {
        if (@($handler.PSObject.Properties.Name | Where-Object { $_ -notin @('type','command','timeout') }).Count -or
            $handler.type -ne 'command' -or -not (Test-BundleHookCommand $handler.command)) { return $false }
        $count++
      }
    }
  }
  return ($count -gt 0)
}

function Merge-ProviderHookDocument($Document, $NewBlock) {
  if ($Document.PSObject.Properties.Name -notcontains 'hooks') {
    if (-not $NewBlock) { return }
    $Document | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{})
  }
  foreach ($evt in @('PreToolUse','Stop')) {
    $remainingGroups = @()
    $removed = $false
    if ($Document.hooks.PSObject.Properties.Name -contains $evt) {
      foreach ($group in @($Document.hooks.$evt)) {
        if ($group.PSObject.Properties.Name -notcontains 'hooks') { $remainingGroups += $group; continue }
        $remaining = @($group.hooks | Where-Object { -not (Test-BundleHookCommand $_.command) })
        if ($remaining.Count -eq @($group.hooks).Count) { $remainingGroups += $group }
        else {
          $removed = $true
          if ($remaining.Count) { $group.hooks = $remaining; $remainingGroups += $group }
        }
      }
    }
    if ($NewBlock) { $remainingGroups += @($NewBlock[$evt]) }
    if (-not $NewBlock -and -not $removed) { continue }
    if ($Document.hooks.PSObject.Properties.Name -contains $evt) { $Document.hooks.$evt = @($remainingGroups) }
    elseif ($remainingGroups.Count) { $Document.hooks | Add-Member -NotePropertyName $evt -NotePropertyValue @($remainingGroups) }
  }
}

# Retire only selected providers' proven bundle-only legacy hook drops. A Hermes
# config.yaml can be a current user home and is never deleted as a legacy drop.
$deadDrops = @($Providers | Where-Object { $_ -in @('Codex','Kimi','Hermes') } | ForEach-Object {
  Join-Path (Get-UabsProviderHome -Provider $_ -Catalog (Get-UabsCatalog)) 'hooks\ultimate-bundle.json'
})

function Remove-DeadDrops {
  foreach ($d in $deadDrops) {
    if (Test-Path -LiteralPath $d -PathType Leaf) {
      $item = Get-Item -LiteralPath $d -Force
      if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
      try { $document = [IO.File]::ReadAllText($d) | ConvertFrom-Json } catch { continue }
      if (-not (Test-EntireBundleHookDocument $document)) { continue }
      if (-not $CheckOnly) { Backup-ProviderHookFile $d; Remove-Item -LiteralPath $d -Force }
      Write-Host "  retired owned inert hook: $d"
    }
  }
}

function Get-HermesExe {
  # Use the shared discovery rule for modern launchers and older source venvs.
  return (Resolve-UabsProviderExe -Provider Hermes)
}

function New-HookBlock {
  param([string]$Py, [string]$Root, [switch]$CallOperator)
  # Grok executes hook commands through PowerShell, where `"exe" "arg"` is a
  # parse error ("Unexpected token ... At line:1 char:65") because a quoted
  # command needs the call operator. cmd.exe (Claude Code's shell) chokes on a
  # leading `&` instead, so only Grok's block gets the `& ` prefix (v7.6.4).
  $co = if ($CallOperator) { '& ' } else { '' }
  $pre  = @()
  $stop = @()
  foreach ($g in $gates) {
    $script = Join-Path $Root $g.Name
    $pre  += [ordered]@{
      matcher = $g.Matcher
      hooks   = @([ordered]@{ type='command'; command=('{0}"{1}" "{2}" --pre'  -f $co,$Py,$script); timeout=15 })
    }
    if ($g.Stop) {
      $stop += [ordered]@{
        hooks = @([ordered]@{ type='command'; command=('{0}"{1}" "{2}" --stop' -f $co,$Py,$script); timeout=30 })
      }
    }
  }
  [ordered]@{ PreToolUse = $pre; Stop = $stop }
}

if ($Uninstall) {
  Remove-DeadDrops
  foreach ($provider in @($Providers | Where-Object { $_ -in @('Claude','Grok') })) {
    $relative = if ($provider -eq 'Claude') { 'settings.json' } else { 'hooks\ultimate-bundle.json' }
    $target = Join-Path (Get-UabsProviderHome -Provider $provider -Catalog (Get-UabsCatalog)) $relative
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { continue }
    $before = [IO.File]::ReadAllText($target)
    $json = $before | ConvertFrom-Json
    if ($provider -eq 'Grok' -and (Test-EntireBundleHookDocument $json)) {
      if (-not $CheckOnly) { Backup-ProviderHookFile $target; Remove-Item -LiteralPath $target -Force }
    } else {
      $beforeSemantic = $json | ConvertTo-Json -Depth 32
      Merge-ProviderHookDocument -Document $json -NewBlock $null
      $after = $json | ConvertTo-Json -Depth 32
      if (-not $CheckOnly -and $after -cne $beforeSemantic) { Backup-ProviderHookFile $target; Set-Utf8NoBom -Path $target -Text $after }
    }
    Write-Host "cleaned selected provider: $target"
  }
  $hx = if ($Providers -contains 'Hermes') { Get-HermesExe } else { $null }
  if ($hx -and -not $CheckOnly -and (Test-Path -LiteralPath $wireSrc)) {
    foreach ($g in $gates) {
      $args = @($wireSrc, $hx, $python, (Join-Path $installRoot $g.Name), '--remove')
      if (-not $g.Stop) { $args += '--pre-only' }
      Invoke-UabsHermesPython -HermesExe $hx -PythonArgs $args
      if ($LASTEXITCODE -ne 0) { throw "Hermes hook removal failed for $($g.Name)." }
    }
  }
  Write-Host 'Codex: disable [plugins."completeness-gate@ultimate-bundle"] in ~/.codex/config.toml'
  exit 0
}

if (-not $CheckOnly) {
  New-Item -ItemType Directory -Force -Path $installRoot | Out-Null
  foreach ($g in $gates) {
    $dest = Join-Path $installRoot $g.Name
    Copy-Item -LiteralPath (Join-Path $hooksSrc $g.Name) -Destination $dest -Force
    # Never wire a gate that cannot prove itself first.
    $selftestEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
      $selftest = & $python $dest --selftest 2>&1 | Out-String
      $selftestCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $selftestEap }
    if ($selftestCode -ne 0 -or $selftest.Trim() -notmatch '\bPASS$') {
      throw "$($g.Name) self-test failed (exit $selftestCode), refusing to wire it:`n$selftest"
    }
    Write-Host "gate: $dest  (self-test PASS)"
  }
}
Write-Host "interpreter: $python"
Remove-DeadDrops

$block = New-HookBlock -Py $python -Root $installRoot

foreach ($p in $Providers) {
  switch ($p) {

    'Claude' {
      $target = Join-Path (Get-UabsProviderHome -Provider Claude -Catalog (Get-UabsCatalog)) 'settings.json'
      if (-not (Test-Path -LiteralPath (Split-Path -Parent $target))) { Write-Host 'Claude  not installed'; break }
      if ($CheckOnly) { Write-Host "Claude  would merge $target"; break }
      $json = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllText($target) | ConvertFrom-Json } else { [pscustomobject]@{} }
      Merge-ProviderHookDocument -Document $json -NewBlock $block
      if (Test-Path -LiteralPath $target -PathType Leaf) { Backup-ProviderHookFile $target }
      Set-Utf8NoBom -Path $target -Text ($json | ConvertTo-Json -Depth 32)
      Write-Host "Claude  merged $($gates.Count) bundle controls into settings.json"
    }

    'Grok' {
      $dir = Join-Path (Get-UabsProviderHome -Provider Grok -Catalog (Get-UabsCatalog)) 'hooks'
      if (-not (Test-Path -LiteralPath (Split-Path -Parent $dir))) { Write-Host 'Grok    not installed'; break }
      if ($CheckOnly) { Write-Host "Grok    would write $dir\ultimate-bundle.json"; break }
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      # A config reset can resurrect the two incompatible Claude Stop hooks.
      # The standalone repair must fix inheritance too, without changing MCPs.
      Set-UabsGrokCompatCells -HooksOnly
      Repair-UabsGrokImpeccableHook -Path (Join-Path $dir 'impeccable.json')
      $grokBlock = New-HookBlock -Py $python -Root $installRoot -CallOperator
      $hookFile = Join-Path $dir 'ultimate-bundle.json'
      $json = if (Test-Path -LiteralPath $hookFile -PathType Leaf) { [IO.File]::ReadAllText($hookFile) | ConvertFrom-Json } else { [pscustomobject]@{} }
      Merge-ProviderHookDocument -Document $json -NewBlock $grokBlock
      $hookText = $json | ConvertTo-Json -Depth 32
      if (Test-Path -LiteralPath $hookFile -PathType Leaf) { Backup-ProviderHookFile $hookFile }
      Set-Utf8NoBom -Path $hookFile -Text $hookText
      Write-Host "Grok    wired ~/.grok/hooks/ultimate-bundle.json ($($gates.Count) controls, PowerShell call-operator form)"
    }

    'Codex' {
      $cfg = Join-Path $codexHome 'config.toml'
      if (-not (Test-Path -LiteralPath $cfg)) { Write-Host 'Codex   not installed'; break }
      if ($CheckOnly) { Write-Host 'Codex   skill/native-plugin enforcement (no executable trust prompt)'; break }

      Write-Host 'Codex   skill/native-plugin enforcement (legacy executable gate disabled; trust state untouched)'
    }

    'Hermes' {
      $hx = Get-HermesExe
      if (-not $hx) { Write-Host 'Hermes  not installed'; break }
      $yamlPython = Get-UabsPythonExecutable
      if (-not $yamlPython) { throw 'Hermes hook wiring requires a working shared user Python; none was found.' }
      if (-not (Test-Path -LiteralPath $wireSrc)) { Write-Host 'Hermes  hermes_wire.py missing from pack'; break }
      if ($CheckOnly) { Write-Host "Hermes  would merge hooks into $(& $hx config path)"; break }

      # Hand off to hermes_wire.py: it asks `hermes config path` for the real
      # location, parses the existing YAML instead of appending text to it, and
      # verifies the result round-trips before reporting success. Writing this
      # config by hand is what shipped broken in v6.8.1.
      foreach ($g in $gates) {
        $args = @($wireSrc, $hx, $yamlPython, (Join-Path $installRoot $g.Name))
        if ($g.AllTools) { $args += '--all-tools' }
        if (-not $g.Stop) { $args += '--pre-only' }
        $args += '--approve'
        Invoke-UabsHermesPython -HermesExe $hx -PythonArgs $args
        if ($LASTEXITCODE -ne 0) { throw "Hermes hook wiring failed for $($g.Name)." }
      }
      # Only the exact, self-tested bundle commands above are persisted. Never
      # set hooks_auto_accept=true, which would approve future third-party hooks.
      & $hx hooks list
      if ($LASTEXITCODE -ne 0) { throw "Hermes hook verification failed with exit $LASTEXITCODE." }
    }
  }
}

Write-Host ''
Write-Host 'Kimi    gate not wired - Kimi has a plugin system (installed by the AIO run) and a'
Write-Host '        hook engine, but its hook config schema is not established, so nothing is'
Write-Host '        guessed into config.toml. Skills and the native plugin are installed.'
Write-Host ''
Write-Host 'Restart each app. Verify: hermes hooks doctor. Codex uses skill/native-plugin enforcement without an executable trust prompt.'
