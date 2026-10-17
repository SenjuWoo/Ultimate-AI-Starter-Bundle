<#
.SYNOPSIS
  Ultimate AI Starter Bundle - All-In-One installer for skills, plugins, MCP tools, and houseCARL (MO2/Vortex).

.DESCRIPTION
  New users: run this once from the pack root.
  - Installs provider skills (Claude/Codex/Grok/Kimi/Hermes)
  - Installs bundled offline tools OR fetches GitHub latest
  - Disables Grok's inheritance of Claude Code hooks (measured 60s/turn) and
    of the Claude MCP import; wires Grok MCP natively, budgeting six configured
    servers when a plugin-provided server may also run
  - NEVER wraps Grok inference through Headroom for subscription/OIDC logins
    (that caused model "unknown" / 401). Opt-in wrap only with XAI_API_KEY.
  - Installs the full catalog by default. Use -CoreOnly for the smaller core.
  - Runs houseCARL MO2/Vortex setup
  - Wires the SOUL + AIO preamble into every selected provider's
    instruction file (Claude CLAUDE.md, Codex/Kimi/Grok AGENTS.md, Hermes
    SOUL.md) - idempotent, backup first, -SkipPreamble to opt out
  - Writes discovery state

.PARAMETER Providers
  Which AI apps to install skills for. Default: all five.

.PARAMETER Mode
  BundledFirst | OnlineLatest | BundledOnly

.PARAMETER Components
  Base components to install. V8 adds the full optional catalog unless
  -CoreOnly is passed. Accepts arrays or comma-separated names through -File.

.PARAMETER WorkspaceRoot
  Optional workspace to receive AGENTS.md / CLAUDE.md / _PROJECT-TEMPLATE

.PARAMETER SkipRuntimes
  Do not try winget for .NET/Python/Node

.PARAMETER SkipHouseCarlSetup
  Do not run Setup-HouseCarl.ps1 at the end

.PARAMETER SkipMcpWire
  Do not edit Grok config.toml

.PARAMETER SkipGrokMcp
  Do not wire MCP servers into Grok. Wiring is on by default. Keep Grok at six
  configured servers when an enabled plugin contributes another server: seven
  running is fine; eight wedges startup.
  See GROK-MCP-TROUBLESHOOTING.md.

.PARAMETER SkipNativePlugins
  Do not install the two bundled skills-plugins (superpowers, ponytail) as
  NATIVE plugins per provider. Native install is on by default for every
  provider with a real plugin mechanism - Grok, Hermes, Codex, Kimi, and
  Claude through its own plugin CLI; fallback everywhere is the copied
  skills.
  -SkipNativePlugins keeps the plain copied-skills behavior and skips the
  plugin-owned skill dedupe.

.EXAMPLE
  .\INSTALL-AIO.ps1
  .\INSTALL-AIO.ps1 -Providers Grok,Claude -Mode OnlineLatest
  .\INSTALL-AIO.ps1 -WorkspaceRoot "D:\Modding\AI-Workspace"
#>
[CmdletBinding()]
param(
  # Empty = auto-detect. Through v8.0.4 this defaulted to all five, and the
  # provider bootstrap then DOWNLOADED the ones that were missing: a machine
  # with only Claude finished the install carrying four vendor CLIs nobody
  # asked for. Now a plain run wires the providers you already have.
  # -AllProviders restores the install-everything behavior for a fresh box.
  # Accepts 'Grok,Claude' as one token because START-HERE.bat forwards through
  # powershell -File, which does not split arrays.
  [string[]]$Providers = @(),
  [switch]$AllProviders,
  [ValidateSet('BundledFirst','OnlineLatest','BundledOnly')]
  [string]$Mode = 'OnlineLatest',
  [string[]]$Components = @('housecarl','spooky','codebase-memory','headroom','superpowers','ponytail','codeburn','impeccable','playwright-cli','github-mcp-server','rtk','universal-modder','uabs-toolbox'),
  [string]$WorkspaceRoot = '',
  # The directory Skyrim Forge is installed INTO, not the folder that
  # contains it: -ForgeRoot 'S:\Apps\Skyrim Tools\Skyrim-Forge' keeps Forge
  # next to xEdit and friends. Defaults to
  # %LOCALAPPDATA%\Skyrim-Tools\Skyrim-Forge, which needs no admin rights and
  # assumes no drive letter. An existing install or a set
  # SKYRIM_FORGE_ROOT is honoured without this. Never version-stamped.
  [string]$ForgeRoot = '',
  [switch]$SkipRuntimes,
  [switch]$SkipHouseCarlSetup,
  [switch]$SkipMcpWire,
  [switch]$SkillsOnly,
  [switch]$ToolsOnly,
  # Grok MCP is wired by default again as of v7.4.2 (v7.4.1 disabled it on a
  # false premise - see docs/history/V7.4.2-CHANGELOG.md). grok-cli 1.0.4
  # wedges at eight RUNNING MCP servers; reserve one slot for a plugin-provided
  # server and keep six configured.
  [switch]$SkipGrokMcp,
  # Max MCP servers to leave configured in ~/.grok/config.toml. grok-cli 1.0.4
  # wedges at EIGHT running; an enabled Claude plugin with a .mcp.json quietly
  # supplies one, so 6 configured is the safe default. Raise to 7 only if no
  # enabled plugin contributes a server.
  [int]$GrokMcpBudget = 6,
  # Compatibility alias. V8 installs extras by default; -CoreOnly opts out.
  #   code-review-skill  obsidian-skills
  #   playwright-mcp     firecrawl-mcp    perplexity-mcp
  [switch]$WithExtras,
  [switch]$CoreOnly,
  # claude-mem is opt-in as of v8.1.0. It is the only component that is not
  # one-click: it pulls in the Bun runtime, runs a background worker daemon,
  # and needs a Claude Code restart before its tools appear. Good software,
  # but three surprises for someone who double-clicked one .bat.
  [switch]$WithClaudeMem,
  # Compatibility alias: rtk is now a default component. The bundle's narrow
  # hook handles only exact status and standalone human-facing tests; the broad
  # upstream hook remains disabled.
  [switch]$WithRtk,
  # Register an optional-key MCP server even when its keyless surface is a
  # fraction of what it charges in schema. Off by default: see
  # keyless_skip_reason in CATALOG.json for the measured numbers.
  [switch]$RegisterKeylessExtras,
  # SOUL + AIO preamble wiring (v7.5.0). On by default: appends the marked
  # preamble block (SOUL.md + 0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md) to every selected
  # provider's instruction file and copies the same SOUL.md into Hermes'
  # home. -SkipPreamble opts out; -ForcePreamble rewrites an identical block.
  [switch]$SkipPreamble,
  [switch]$ForcePreamble,
  # Portable starter settings (v7.7.3; $HOME abort fixed in v7.7.4). On by default: merge/copy
  # 1-TAILORED-PROVIDER-TREES\<Provider>\COPY-TO-PROVIDER-HOME settings
  # into each provider home. Never overwrites CLAUDE.md / AGENTS.md /
  # SOUL.md (unrestraint + preamble live there) and never copies MCP
  # command lines from a live dump. -SkipStarterSettings opts out.
  [switch]$SkipStarterSettings,
  # Hermes config.yaml wiring. Kept as an alias for skipping only Hermes
  # in the starter-settings pass. -SkipHermesConfig opts out.
  [switch]$SkipHermesConfig,
  # Native plugin install for the two bundled skills-plugins (superpowers,
  # ponytail). On by default: a real plugin install where the CLI has a
  # plugin mechanism (Grok/Hermes/Codex), detect-only for Claude, unsupported
  # for Kimi; fallback is the copied skills. -SkipNativePlugins opts out.
  [switch]$SkipNativePlugins,
  # Fresh-machine default: install missing provider CLIs from each vendor's official Windows installer.
  [switch]$SkipProviderBootstrap,
  # Default install proves each always-on MCP with initialize + tools/list.
  [switch]$SkipMcpHandshake,
  # How much of houseCARL the Hermes 'skyrim' profile registers. Empty = leave
  # it to Migrate-HermesProfiles.ps1's own default (Lean) AND do not override a
  # filter the user set by hand -- passing the switch through on every install
  # would replace their `hermes mcp configure housecarl` choice every time.
  #   Full 45 tools ~41,768 schema tokens | Lean 42 ~31,369 (-25%) | ReadOnly 27 ~17,604 (-58%); bytes/4, not billing.
  [ValidateSet('', 'Full', 'Lean', 'ReadOnly')]
  [string]$SkyrimToolset = '',
  # Leftovers this pack created and never removed: skills it stopped shipping,
  # and its own .bak / log files, which had no ceiling. Cleaned every install so
  # a machine converges on the current tree instead of accumulating every
  # version it has ever seen. -SkipCleanup opts out; the tool is also runnable
  # on its own (TOOLS\Clean-StaleState.ps1, dry-run by default).
  [switch]$SkipCleanup,
  # START-HERE checks GitHub for a newer bundle release first: a clean git
  # clone fast-forwards, a release copy installs the new release through
  # INSTALL-REMOTE.ps1. Offline/failed checks fall back to this copy.
  # -SkipSelfUpdate (or UABS_NO_SELF_UPDATE=1) installs this copy as-is.
  [switch]$SkipSelfUpdate,
  # Opt-in skills from BUNDLED-TOOLS\optional-skills, e.g. -OptionalSkills
  # melty-mashups. Never installed by default; refreshed once present.
  [string[]]$OptionalSkills = @(),
  # Content packs from BUNDLED-TOOLS\PACKS.json (today: skyrim). A pack
  # installs when this machine shows evidence for it (game install, mod
  # manager, tool env vars). -Packs turns one on, -ExcludePacks turns it off;
  # both are remembered for later runs. A disabled pack costs no skill index
  # entries, no instruction text and no tool downloads.
  [string[]]$Packs = @(),
  [string[]]$ExcludePacks = @(),
  # Personal profile folder (PROFILE.md + MACHINE-MAP.md). Default
  # %USERPROFILE%\.uabs\profile; its compact text is added to every provider's
  # instruction file. -ProfileTemplate <name> seeds PROFILE.md from
  # BUNDLED-TOOLS\optional-profiles when the user has none yet.
  [string]$ProfileRoot = '',
  [string]$ProfileTemplate = '',
  [switch]$SkipProfile
)

# Match -Providers: powershell -File forwards comma-separated names as one string.
$Components = @($Components | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
if (-not $CoreOnly) {
  $Components = @($Components) + @(
    'code-review-skill', 'obsidian-skills',
    'playwright-mcp', 'firecrawl-mcp', 'perplexity-mcp'
  ) | Select-Object -Unique
}
if ($WithClaudeMem) { $Components = @($Components) + @('claude-mem') | Select-Object -Unique }
$OptionalSkills = @($OptionalSkills | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
foreach ($opt in $OptionalSkills) {
  if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot ('BUNDLED-TOOLS\optional-skills\' + $opt + '\SKILL.md')) -PathType Leaf)) {
    throw ("Unknown optional skill '$opt'. Available: " + ((Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'BUNDLED-TOOLS\optional-skills') -Directory -ErrorAction SilentlyContinue).Name -join ', '))
  }
}
if ($WithRtk) { $Components = @($Components) + @('rtk') | Select-Object -Unique }
$Packs = @($Packs | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
$ExcludePacks = @($ExcludePacks | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ } | Select-Object -Unique)
foreach ($both in @($Packs | Where-Object { $ExcludePacks -contains $_ })) { throw "Pack '$both' is in both -Packs and -ExcludePacks." }

$ErrorActionPreference = 'Stop'
$PackRoot = $PSScriptRoot

# Durable installer diagnostics. A double-clicked .bat used to vanish on the
# first terminating error, leaving only a one-frame red message. Keep one
# timestamped transcript plus stable LAST/FAILED files under LOCALAPPDATA so a
# rerun is self-diagnosing even when the console is gone.
$installLogBase = $env:LOCALAPPDATA
if (-not $installLogBase) { $installLogBase = $env:TEMP }
if (-not $installLogBase) { $installLogBase = $PackRoot }
$installLogRoot = Join-Path $installLogBase 'Ultimate-AI-Starter-Bundle\logs'
New-Item -ItemType Directory -Force -Path $installLogRoot | Out-Null
$installLogPath = Join-Path $installLogRoot ('install-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$installLastPath = Join-Path $installLogRoot 'INSTALL-LAST.log'
$installFailedPath = Join-Path $installLogRoot 'INSTALL-FAILED.txt'
# Every tool's own output (npm, uv, plugin CLIs, child scripts) goes here; the
# console and transcript keep one line per step.
$script:UabsDetailsLog = $installLogPath -replace '\.log$', '-details.log'
$script:UabsTranscriptStarted = $false
$script:UabsHermesGatewayWasRunning = $false
try {
  Start-Transcript -LiteralPath $installLogPath -Force | Out-Null
  $script:UabsTranscriptStarted = $true
} catch {
  # Logging must never become the reason installation fails.
}
# Claude, Hermes and npm print UTF-8; decode it as UTF-8 so a check mark is not
# shown as three junk characters in the window and the log.
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

trap {
  $failure = $_
  Write-Host ''
  Write-Host '=====================================================' -ForegroundColor Red
  Write-Host ' INSTALL FAILED' -ForegroundColor Red
  Write-Host (' ' + $failure.Exception.Message) -ForegroundColor Red
  Write-Host (' Diagnostics: ' + $installFailedPath) -ForegroundColor Yellow
  Write-Host (' Transcript:  ' + $installLogPath) -ForegroundColor Yellow
  Write-Host (' Tool output: ' + $script:UabsDetailsLog) -ForegroundColor Yellow
  Write-Host ' Running START-HERE.bat again is safe.' -ForegroundColor Yellow
  Write-Host '=====================================================' -ForegroundColor Red
  $summary = @(
    'Ultimate AI Starter Bundle installation failed.'
    ('UTC: ' + [DateTime]::UtcNow.ToString('o'))
    ('Pack: ' + $PackRoot)
    ('Error: ' + $failure.Exception.Message)
    ('Category: ' + $failure.CategoryInfo)
    ('Target: ' + $failure.TargetObject)
    ('ScriptStackTrace: ' + $failure.ScriptStackTrace)
    ('Transcript: ' + $installLogPath)
    ('Tool output: ' + $script:UabsDetailsLog)
  ) -join [Environment]::NewLine
  try {
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($installFailedPath, $summary, $enc)
  } catch {}
  if ($script:UabsTranscriptStarted) {
    try { Stop-Transcript | Out-Null } catch {}
    $script:UabsTranscriptStarted = $false
  }
  try { Copy-Item -LiteralPath $installLogPath -Destination $installLastPath -Force } catch {}
  exit 1
}

if (-not (Test-Path (Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json'))) {
  throw "Run INSTALL-AIO.ps1 from the pack root (folder containing BUNDLED-TOOLS)."
}
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
. (Join-Path $PackRoot 'TOOLS\UABS-Mcp-Write.ps1')
. (Join-Path $PackRoot 'TOOLS\UABS-Mcp-Park.ps1')
$script:UabsPackRoot = $PackRoot

# ---------- Quiet console, complete details log ----------
function Add-UabsDetails {
  <# Append a step's full output to the details log beside the transcript. #>
  param([string]$Title, [string[]]$Lines)
  if (-not $script:UabsDetailsLog) { return }
  $text = '==== ' + $Title + ' (' + (Get-Date -Format 'HH:mm:ss') + ")`r`n" + ((@($Lines) | ForEach-Object { [string]$_ }) -join "`r`n") + "`r`n"
  try { [IO.File]::AppendAllText($script:UabsDetailsLog, $text, (New-Object System.Text.UTF8Encoding($false))) } catch { }
}

function Show-UabsTail {
  param([string[]]$Lines, [int]$Count = 20)
  foreach ($line in @(@($Lines) | Select-Object -Last $Count)) { Write-Host ('     ' + $line) -ForegroundColor DarkGray }
}

function Invoke-UabsChildScript {
  <# Run a bundle script in its own powershell.exe. Its output goes to the details
     log; the console shows its tail only when it fails. Returns the exit code
     (the output stays in $script:UabsLastChildOutput for a caller that needs it). #>
  param([string]$Title, [string]$File, [string[]]$ArgList = @(), [switch]$NoTail)
  $psExe = (Get-Command powershell.exe -ErrorAction Stop).Source
  $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $lines = @(& $psExe -NoProfile -ExecutionPolicy Bypass -File $File @ArgList 2>&1 | ForEach-Object { [string]$_ }) }
  finally { $ErrorActionPreference = $prevEap }
  $code = $LASTEXITCODE
  Add-UabsDetails -Title $Title -Lines $lines
  if ($code -ne 0 -and -not $NoTail) { Show-UabsTail -Lines $lines }
  $script:UabsLastChildOutput = $lines
  return $code
}

if (-not $SkipSelfUpdate -and $Mode -ne 'BundledOnly' -and $env:UABS_NO_SELF_UPDATE -ne '1') {
  $handoff = Invoke-UabsBundleSelfUpdate -PackRoot $PackRoot -Bound $PSBoundParameters
  if ($null -ne $handoff) {
    if ($script:UabsTranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
    exit $handoff
  }
}

# One install at a time. Two overlapping runs (a second double-click, or an
# agent's sync during the user's own run) interleaved the skill sync with the
# native-plugin dedupe: the second run found nothing left to dedupe, recorded
# no ownership and failed its doctor. Taken after the self-update handoff, so a
# handed-off installer never waits on this one. Windows releases the mutex
# when the process exits; a crashed holder surfaces as AbandonedMutexException.
$script:UabsInstallMutex = New-Object System.Threading.Mutex($false, 'Local\UltimateAIStarterBundle-Install')
$haveInstallLock = $false
try { $haveInstallLock = $script:UabsInstallMutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $haveInstallLock = $true }
if (-not $haveInstallLock) {
  Write-Host '  ..  Another bundle install is still running - waiting for it to finish...' -ForegroundColor Yellow
  try { $haveInstallLock = $script:UabsInstallMutex.WaitOne([TimeSpan]::FromMinutes(30)) } catch [System.Threading.AbandonedMutexException] { $haveInstallLock = $true }
  if (-not $haveInstallLock) { throw 'Another bundle install has been running for 30 minutes. Close its window, then run START-HERE.bat again.' }
}

# ---------- Which providers this run touches ----------
# powershell -File collapses -Providers Grok,Claude into ONE string, so split
# before validating. ValidateSet cannot do that, which is why it is gone.
$script:UabsAllProviders = @('Claude','Codex','Grok','Kimi','Hermes')
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($requested in $Providers) {
  if ($script:UabsAllProviders -notcontains $requested) {
    throw ("Unknown provider '$requested'. Valid: " + ($script:UabsAllProviders -join ', '))
  }
}
$script:UabsProviderSource = 'explicit'
if ($AllProviders) {
  if ($Providers.Count) { throw 'Use -Providers or -AllProviders, not both.' }
  $Providers = $script:UabsAllProviders
  $script:UabsProviderSource = 'all (-AllProviders)'
} elseif (-not $Providers.Count) {
  $Providers = @(Get-UabsInstalledProviders -Candidates $script:UabsAllProviders)
  $script:UabsProviderSource = 'auto-detected'
  if (-not $Providers.Count) {
    # A genuinely fresh machine has nothing to detect. Bootstrapping all five
    # is the only outcome that leaves the box usable, and it is what someone
    # who ran an installer on an empty profile actually asked for.
    $Providers = $script:UabsAllProviders
    $script:UabsProviderSource = 'none detected - bootstrapping all'
  }
}
$script:UabsSkippedProviders = @($script:UabsAllProviders | Where-Object { $Providers -notcontains $_ })
Invoke-UabsLegacyStateMigration
$catalog = Get-UabsCatalog

# ---------- Content packs ----------
# Skyrim content used to install for everyone: 49 skills (~2.7k tokens of skill
# descriptions in every request), a 24 KB instruction section, Forge, houseCARL
# and Spooky. It now installs where Skyrim is found or asked for.
$packSel = Resolve-UabsPackSelection -PackRoot $PackRoot -Requested $Packs -Excluded $ExcludePacks
foreach ($packName in @($packSel.Reasons.Keys)) {
  $packMeta = $packSel.Catalog.packs.$packName
  if ($packSel.Enabled -contains $packName) {
    Write-UabsOk ("Pack '{0}' on: {1}" -f $packName, $packSel.Reasons[$packName])
    Add-UabsDetails -Title "pack $packName" -Lines @("turn off: " + $packMeta.disable)
  } else {
    Write-Host ("  ..  Pack '{0}' off: {1}  (turn on: {2})" -f $packName, $packSel.Reasons[$packName], $packMeta.enable) -ForegroundColor DarkGray
  }
}
if (-not $PSBoundParameters.ContainsKey('Components')) {
  $Components = @($Components | Where-Object { $packSel.DisabledComponents -notcontains $_ })
}
$skyrimPackOn = (-not $packSel.Catalog) -or ($packSel.Enabled -contains 'skyrim')
$offline = Join-Path $PackRoot 'BUNDLED-TOOLS\offline'
$cache = Join-Path $PackRoot 'BUNDLED-TOOLS\cache'
$plugins = Join-Path $PackRoot 'BUNDLED-TOOLS\plugins'
$log = [System.Collections.Generic.List[string]]::new()
function L($m){ [void]$log.Add("$(Get-Date -Format o) $m"); Write-Host $m }

function Invoke-UabsNative {
  <#
  Run a native command without PowerShell 5.1 mangling its stderr.
  With 2>&1, every stderr line becomes an ErrorRecord: under the script-wide
  $ErrorActionPreference='Stop' that is a TERMINATING NativeCommandError, and
  even under 'Continue' each record prints as a red "RemoteException" block
  (pip's "already satisfied" / pip-version notice did exactly that).
  Fix: drop EAP to Continue locally and stringify every record before it can
  reach the host's error formatting. Returns $true when the exit code is 0.
  NOTE: the parameter must NOT be named $Args - shadowing the automatic
  variable silently breaks $LASTEXITCODE propagation (measured, PS 5.1).
  #>
  param([string]$Exe, [string[]]$ArgList)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $lines = @(& $Exe @ArgList 2>&1 | ForEach-Object { [string]$_ })
  } finally { $ErrorActionPreference = $prevEap }
  $ok = ($null -eq $LASTEXITCODE) -or ($LASTEXITCODE -eq 0)
  # npm/uv/plugin CLIs print pages of progress and JSON. Keep it in the details
  # log; the console gets the tail only when the command failed.
  Add-UabsDetails -Title ((Split-Path -Leaf $Exe) + ' ' + (@($ArgList) -join ' ')) -Lines $lines
  if (-not $ok) { Show-UabsTail -Lines $lines }
  return $ok
}

function Get-UabsNpmGlobalVersion {
  <# Version of a pinned package in the ACTIVE npm global root, or $null. #>
  param([string]$Npm, [string]$Spec)
  $packageName = Get-UabsNpxPackageBase -Arguments @($Spec)
  if (-not $packageName) { return $null }
  $root = [string](@(Get-UabsNativeStdout -Exe $Npm -CmdArgs @('root', '-g')) | Select-Object -Last 1)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($root)) { return $null }
  $json = Join-Path (Join-Path $root.Trim() $packageName) 'package.json'
  if (-not (Test-Path -LiteralPath $json -PathType Leaf)) { return $null }
  try { return [string](([IO.File]::ReadAllText($json) | ConvertFrom-Json).version) } catch { return $null }
}

function Remove-UabsOutdatedHermesNpmDuplicate {
  <#
  npm installs a global package into whichever prefix is active (the first npm
  on PATH). Older pack releases installed CodeBurn/Impeccable through Hermes'
  private Node prefix, and the user's own npm prefix can hold an older copy too.
  Either one can sit earlier on PATH than the fresh install and silently win
  (CodeBurn 0.9.23 shadowed 0.9.27 that way). Remove only that proven shape:
  this run installed the exact catalog version in the active global root and a
  DIFFERENT known prefix carries a lower version of the same package. An equal
  or newer copy is somebody's own install and stays. A verified recovery copy of
  the old package is taken before anything is uninstalled.
  #>
  param([object]$Component, [string]$ActiveNpm)
  try {
    $spec = [string]$Component.npm_spec
    $expectedVersion = [string]$Component.version
    if (-not $expectedVersion -or -not $spec.EndsWith('@' + $expectedVersion)) { return }
    $packageName = Get-UabsNpxPackageBase -Arguments @($spec)
    if (-not $packageName) { return }

    $activeRootText = [string](& $ActiveNpm root -g | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($activeRootText)) { return }
    $activeRoot = [IO.Path]::GetFullPath($activeRootText.Trim()).TrimEnd('\')
    $activeJson = Join-Path (Join-Path $activeRoot $packageName) 'package.json'
    if (-not (Test-Path -LiteralPath $activeJson -PathType Leaf)) { return }
    $activeVersion = [string](([IO.File]::ReadAllText($activeJson) | ConvertFrom-Json).version)
    if ($activeVersion -ne $expectedVersion) { return }

    $others = @(
      @{ Name = "Hermes' private Node prefix"; Prefix = (Join-Path $env:LOCALAPPDATA 'hermes\node') },
      @{ Name = 'the user npm prefix';         Prefix = (Join-Path $env:APPDATA 'npm') }
    )
    foreach ($other in $others) {
      try {
        $legacyPrefix = [string]$other.Prefix
        $legacyRoot = Join-Path $legacyPrefix 'node_modules'
        $legacyJson = Join-Path (Join-Path $legacyRoot $packageName) 'package.json'
        if (-not (Test-Path -LiteralPath $legacyJson -PathType Leaf)) { continue }
        $legacyRootFull = [IO.Path]::GetFullPath($legacyRoot).TrimEnd('\')
        if ([string]::Equals($activeRoot, $legacyRootFull, [StringComparison]::OrdinalIgnoreCase)) { continue }
        $legacyVersion = [string](([IO.File]::ReadAllText($legacyJson) | ConvertFrom-Json).version)
        if (([version]$legacyVersion) -ge ([version]$activeVersion)) { continue }

        # Recovery copy first; an unverified copy means the old package stays.
        $packageDir = Split-Path -Parent $legacyJson
        $safeName = $packageName -replace '[^\w.-]', '_'
        $backup = Join-Path (Join-Path (Get-UabsStateRoot) 'npm-rollback') ('{0}-{1}-{2}' -f $safeName, $legacyVersion, (Get-Date -Format 'yyyyMMddHHmmssfff'))
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Copy-Item -Path (Join-Path $packageDir '*') -Destination $backup -Recurse -Force
        $want = @(Get-ChildItem -LiteralPath $packageDir -Recurse -File -Force)
        $have = @(Get-ChildItem -LiteralPath $backup -Recurse -File -Force)
        $wantBytes = ($want | Measure-Object -Property Length -Sum).Sum
        $haveBytes = ($have | Measure-Object -Property Length -Sum).Sum
        if ($want.Count -ne $have.Count -or $wantBytes -ne $haveBytes) {
          Write-UabsWarn "$packageName $legacyVersion in $($other.Name) left alone: its recovery copy did not verify"
          continue
        }

        # The old prefix's own npm when it has one, else the active npm with --prefix.
        $legacyNpm = Join-Path $legacyPrefix 'npm.cmd'
        if (-not (Test-Path -LiteralPath $legacyNpm -PathType Leaf)) { $legacyNpm = $ActiveNpm }
        if (Invoke-UabsNative $legacyNpm @('--prefix', $legacyPrefix, 'uninstall', '-g', $packageName)) {
          if (Test-Path -LiteralPath $legacyJson -PathType Leaf) {
            Write-UabsWarn "$packageName $legacyVersion remains in $($other.Name) after npm uninstall"
          } else {
            Write-UabsOk "removed obsolete $packageName $legacyVersion from $($other.Name) (active: $activeVersion; recovery copy: $backup)"
          }
        } else {
          Write-UabsWarn "could not remove obsolete $packageName $legacyVersion from $($other.Name); active $activeVersion is still correct"
        }
      } catch {
        Write-UabsWarn ("left npm duplicate in $($other.Name) alone: " + $_.Exception.Message)
      }
    }
  } catch {
    Write-UabsWarn ("left npm duplicates alone: " + $_.Exception.Message)
  }
}

function Remove-UabsGlobalMcpRegistration {
  param([string[]]$Ids, [string[]]$FromProviders)
  $removed = @()
  $targets = Get-UabsMcpTargets
  foreach ($prov in @($FromProviders)) {
    if ($prov -eq 'Hermes') {
      $done = @(Remove-UabsMcpHermes -Ids $Ids)
    } else {
      $target = $targets[$prov]
      if (-not $target) { continue }
      if ($target.Style -eq 'json') {
        $done = @(Remove-UabsMcpJson -Path $target.Path -Section $target.Section -Ids $Ids)
      } else {
        $done = @(Remove-UabsMcpToml -Path $target.Path -Section $target.Section -Ids $Ids)
      }
      if ($target.Desktop) {
        $desktop = Get-ClaudeDesktopConfigPath
        if ($desktop) { $done += @(Remove-UabsMcpJson -Path $desktop -Section 'mcpServers' -Ids $Ids) }
      }
    }
    if ($done.Count) {
      $removed += $prov
      Write-UabsOk ("{0}: removed retired global MCP entry {1}" -f $prov, (($done | Select-Object -Unique) -join ', '))
    }
  }
  return @($removed | Select-Object -Unique)
}

function Find-UabsBunExecutable {
  $cmd = Get-Command bun -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = @(
    (Join-Path $env:USERPROFILE '.bun\bin\bun.exe'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\bun.exe')
  )
  $winget = Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Oven-sh.Bun_*\bun-windows-*\bun.exe') `
                          -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
  if ($winget) { $candidates += $winget.FullName }
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  return $null
}

Write-Host ""
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host " Ultimate AI Starter Bundle v8.17.0 - ALL-IN-ONE INSTALLER" -ForegroundColor Magenta
Write-Host " Mode=$Mode  Providers=$($Providers -join ',') [$script:UabsProviderSource]" -ForegroundColor Magenta
if ($script:UabsSkippedProviders.Count) {
  Write-Host (" Not installed here, so not touched: " + ($script:UabsSkippedProviders -join ', ') + "  (add them with -AllProviders)") -ForegroundColor DarkGray
}
Write-Host "=====================================================" -ForegroundColor Magenta
Write-Host ""

# ---------- Runtimes ----------
if (-not $SkipRuntimes -and -not $SkillsOnly) {
  Write-UabsStep "Runtime checks"
  $needNet9 = -not (Test-UabsDotNetRuntime 'Microsoft\.NETCore\.App 9\.')
  $needAsp9 = -not (Test-UabsDotNetRuntime 'Microsoft\.AspNetCore\.App 9\.')
  $needSdk8 = -not (Test-UabsDotNetSdk '^8\.')
  if ($needNet9 -and -not (Install-UabsWinget @('Microsoft.DotNet.Runtime.9'))) { throw '.NET 9 runtime installation failed.' } elseif (-not $needNet9) { Write-UabsOk '.NET 9 runtime' }
  if ($needAsp9 -and -not (Install-UabsWinget @('Microsoft.DotNet.AspNetCore.9'))) { throw 'ASP.NET Core 9 installation failed.' } elseif (-not $needAsp9) { Write-UabsOk 'ASP.NET Core 9' }
  if ($needSdk8 -and -not (Install-UabsWinget @('Microsoft.DotNet.SDK.8'))) { throw '.NET 8 SDK installation failed.' } elseif (-not $needSdk8) { Write-UabsOk '.NET 8 SDK' }
  # Run the candidate, do not trust PATH: stock Windows 11 ships a python.exe alias
  # that only opens the Microsoft Store, and it counted as "Python present".
  if (-not (Get-UabsPythonExecutable)) {
    Write-UabsWarn 'Python not found (needed for Headroom/Forge) - attempting winget'
    if (-not (Install-UabsWinget @('Python.Python.3.12'))) { throw 'Python 3.12 installation failed.' }
  } else { Write-UabsOk 'Python present' }
  if (-not (Get-Command node -EA SilentlyContinue)) {
    Write-UabsWarn 'Node not found (CodeBurn + reasoning MCPs) - attempting winget LTS'
    if (-not (Install-UabsWinget @('OpenJS.NodeJS.LTS'))) { throw 'Node LTS installation failed.' }
  } else { Write-UabsOk "Node $(node -v)" }
  if (($Components -contains 'claude-mem') -and ($Providers -contains 'Claude')) {
    $bunExe = Find-UabsBunExecutable
    if (-not $bunExe) {
      Write-UabsWarn 'Bun not found (required by claude-mem) - attempting official winget package'
      if (-not (Install-UabsWinget @('Oven-sh.Bun'))) { throw 'Bun installation failed.' }
      $bunExe = Find-UabsBunExecutable
    }
    if (-not $bunExe) { throw 'Bun installed but bun.exe did not resolve in the current installer process.' }
    $env:BUN = $bunExe
    $env:PATH = (Split-Path $bunExe -Parent) + ';' + $env:PATH
    Write-UabsOk ("Bun " + (& $bunExe --version))
  }
}

# Fresh-machine provider bootstrap. Existing commands are preserved; only missing
# CLIs use official vendor Windows installers and every command is startup tested.
if (-not $ToolsOnly -and -not $SkipProviderBootstrap) {
  $providerBootstrap = Join-Path $PackRoot 'TOOLS\Ensure-Provider-CLIs.ps1'
  if (-not (Test-Path -LiteralPath $providerBootstrap -PathType Leaf)) { throw 'Provider bootstrap script missing.' }
  Write-UabsStep 'Checking your AI apps (a missing one is installed from its vendor)'
  $bootCode = Invoke-UabsChildScript -Title 'AI app check' -File $providerBootstrap -ArgList @('-Providers', ($Providers -join ','))
  if ($bootCode -ne 0) { throw "Provider bootstrap failed with exit code $bootCode." }
  $appsFound = @($script:UabsLastChildOutput | ForEach-Object { if ($_ -match 'OK\s+(\w+) executable verified') { $Matches[1] } })
  Write-UabsOk ('AI apps ready: ' + $(if ($appsFound.Count) { $appsFound -join ', ' } else { $Providers -join ', ' }))
}

function Get-ComponentAssetPath {
  param($Comp)
  $name = $Comp.offline_asset
  if ($Mode -eq 'OnlineLatest') {
    # prefer cache newest matching
    if ($Comp.github) {
      try {
        $rel = Get-UabsComponentGitHubRelease -Comp $Comp
        $asset = $null
        if ($Comp.asset_match) { $asset = Get-UabsReleaseAsset -Release $rel -Patterns @($Comp.asset_match) }
        if ($asset) {
          $dest = Join-Path $cache $asset.name
          [void](Save-UabsReleaseAsset -Asset $asset -OutFile $dest -ReuseValid)
          return $dest
        }
        if ($Comp.kind -eq 'skills-plugin') {
          $dest = Join-Path $cache "$($Comp.id)-$($rel.tag_name).zip"
          if (-not (Test-Path $dest)) {
            $zipUrl = "https://github.com/$($Comp.github.owner)/$($Comp.github.repo)/archive/refs/tags/$($rel.tag_name).zip"
            try { Save-UabsUrl -Url $zipUrl -OutFile $dest } catch { Save-UabsUrl -Url $rel.zipball_url -OutFile $dest }
          }
          return $dest
        }
      } catch { Write-UabsWarn "OnlineLatest failed for $($Comp.id): $($_.Exception.Message)" }
    }
  }
  if ($Comp.id -eq 'rtk') {
    $p = Get-UabsRtkFallbackAsset -Comp $Comp -PackRoot $PackRoot -Cache $cache -Offline $offline
    if ($p) { return $p }
  } elseif ($name) {
    $p = Join-Path $offline $name
    if (Test-Path $p) { return $p }
    # any cache match
    if ($Comp.asset_match) {
      foreach ($pat in $Comp.asset_match) {
        $hit = Get-ChildItem $cache,$offline -Filter $pat -File -EA SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($hit) { return $hit.FullName }
      }
    }
  }
  if ($Mode -eq 'BundledOnly') { return $null }
  # fallback online
  if ($Comp.github) {
    try {
      $rel = Get-UabsComponentGitHubRelease -Comp $Comp
      $asset = $null
      if ($Comp.asset_match) { $asset = Get-UabsReleaseAsset -Release $rel -Patterns @($Comp.asset_match) }
      if ($asset) {
        $dest = Join-Path $cache $asset.name
        [void](Save-UabsReleaseAsset -Asset $asset -OutFile $dest -ReuseValid)
        return $dest
      }
    } catch {}
  }
  return $null
}

# ---------- Skills ----------
if (-not $ToolsOnly) {
  Write-UabsStep "Installing provider skills"
  $tailored = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES'
  foreach ($prov in $Providers) {
    $srcSkills = Join-Path $tailored "$prov\COPY-TO-SKILLS-DIRECTORY\skills"
    if (-not (Test-Path $srcSkills)) { Write-UabsBad "Missing $srcSkills"; continue }
    $providerHome = Get-UabsProviderHome -Provider $prov -Catalog $catalog
    $destSkills = Get-UabsProviderSkillsDir -Provider $prov -Catalog $catalog
    Write-Host "  $prov -> $destSkills"
    # Codex stores pack skills in ~/.agents/skills, outside CODEX_HOME. On a
    # clean machine syncing those skills therefore does not create ~/.codex,
    # but the instruction and starter-setting writers need that home.
    New-Item -ItemType Directory -Force -Path $providerHome | Out-Null

    # Codex standardized on ~/.agents/skills but still scans the old
    # $CODEX_HOME/skills root. Snapshot the old ownership ledger before the
    # sync rewrites it, then move only proven bundle copies out of that legacy
    # root after the supported root is healthy.
    $legacyCodexSkills = $null
    $legacyCodexDigests = @{}
    $codexBuiltins = @()
    if ($prov -eq 'Codex') {
      $legacyCodexSkills = Join-Path $providerHome 'skills'
      $codexBuiltins = @(Get-UabsCodexBuiltinSkillNames -CodexHome $providerHome)
      $ledgerPath = Join-Path (Get-UabsStateRoot) 'managed-skills\codex.json'
      if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
        try {
          foreach ($entry in @(([IO.File]::ReadAllText($ledgerPath) | ConvertFrom-Json).skills)) {
            $legacyCodexDigests[[string]$entry.name] = [string]$entry.digest
          }
        } catch { Write-UabsWarn ('Codex legacy skill ledger unreadable; only current exact copies can migrate: ' + $_.Exception.Message) }
      }
    }

    # Skills of a disabled pack are left out; the managed-skill ledger then
    # retires the unmodified copies an earlier install put here.
    Sync-UabsProviderSkills -From $srcSkills -To $destSkills -Provider $prov -ExcludeNames (@($codexBuiltins) + @($packSel.ExcludedSkills))
    $null = Sync-UabsOptionalSkills -SourceRoot (Join-Path $PackRoot 'BUNDLED-TOOLS\optional-skills') -SkillsDir $destSkills -Provider $prov -Requested $OptionalSkills
    if ($prov -eq 'Hermes') {
      # A Hermes profile clones the default skills folder when it is created
      # and nothing refreshes it afterwards: measured 26-47 stale bundle skills
      # per profile and ~72 retired ones in three of them. Refresh the profiles
      # this bundle manages; Skyrim pack skills belong only in `skyrim`.
      $allPackSkills = @($packSel.Catalog.packs.PSObject.Properties | ForEach-Object { @($_.Value.skills) })
      $hermesOverrides = @(Get-UabsPreservedSkillNames -Provider 'Hermes' -SkillsDir $destSkills)
      foreach ($pf in @(Get-UabsHermesManagedProfiles -HermesHome $providerHome -SoulFile (Join-Path $PackRoot '3-PREAMBLES\SOUL.md') -RequireSkills)) {
        $profileSkills = Join-Path $pf.FullName 'skills'
        $notHere = if ($pf.Name -eq 'skyrim') { @($packSel.ExcludedSkills) } else { $allPackSkills }
        try {
          Sync-UabsProviderSkills -From $srcSkills -To $profileSkills -Provider ('Hermes.' + $pf.Name) -ExcludeNames (@($notHere) + $hermesOverrides)
          $aside = Move-UabsSkillsAside -SkillsDir $profileSkills -Names $notHere -Label ('hermes-profile-' + $pf.Name + '-pack-skills')
          if ($aside.Moved.Count) { Write-UabsOk ("Hermes profile {0}: {1} pack skill(s) moved out of its index -> {2}" -f $pf.Name, $aside.Moved.Count, $aside.Backup) }
          Write-UabsOk ("Hermes profile {0}: skills refreshed" -f $pf.Name)
        } catch { Write-UabsWarn ("Hermes profile {0} skills: {1}" -f $pf.Name, $_.Exception.Message) }
      }
    }
    if ($legacyCodexSkills -and
        $legacyCodexSkills.TrimEnd('\') -ine $destSkills.TrimEnd('\') -and
        (Test-Path -LiteralPath $legacyCodexSkills -PathType Container)) {
      $legacyBackup = $null
      $movedLegacy = 0
      foreach ($oldSkill in @(Get-ChildItem -LiteralPath $legacyCodexSkills -Directory -Force -ErrorAction SilentlyContinue)) {
        if ($oldSkill.Name -eq '.system' -or ($oldSkill.Attributes -band [IO.FileAttributes]::ReparsePoint)) { continue }
        $expected = $legacyCodexDigests[$oldSkill.Name]
        if (-not $expected) {
          $currentSource = Join-Path $srcSkills $oldSkill.Name
          if (Test-Path -LiteralPath $currentSource -PathType Container) { $expected = Get-UabsTreeDigest $currentSource }
        }
        if (-not $expected) {
          # A non-pack skill may also exist in both Codex's supported and
          # deprecated roots. Move only a byte-identical legacy duplicate.
          $supportedCopy = Join-Path $destSkills $oldSkill.Name
          if (Test-Path -LiteralPath $supportedCopy -PathType Container) {
            $supportedItem = Get-Item -LiteralPath $supportedCopy -Force
            if (($supportedItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
              $supportedDigest = Get-UabsTreeDigest $supportedCopy
              if ((Get-UabsTreeDigest $oldSkill.FullName) -ceq $supportedDigest) { $expected = $supportedDigest }
            }
          }
        }
        if (-not $expected) { continue }
        if ((Get-UabsTreeDigest $oldSkill.FullName) -cne $expected) {
          Write-UabsWarn ('Codex legacy skill was modified; preserved: ' + $oldSkill.FullName)
          continue
        }
        if (-not $legacyBackup) {
          $legacyBackup = Join-Path (Get-UabsStateRoot) ('backups\codex-legacy-skills-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
          New-Item -ItemType Directory -Force -Path $legacyBackup | Out-Null
        }
        Move-Item -LiteralPath $oldSkill.FullName -Destination (Join-Path $legacyBackup $oldSkill.Name)
        $movedLegacy++
      }
      if ($movedLegacy) { Write-UabsOk "Codex: moved $movedLegacy legacy duplicate skill(s) to $legacyBackup" }
    }
    # provider home instructions
    $pmeta = $catalog.providers.$prov
    if ($pmeta.instructions) {
      $srcInst = Join-Path $tailored "$prov\COPY-TO-PROVIDER-HOME\$($pmeta.instruction_src)"
      if (-not (Test-Path $srcInst)) {
        $srcInst = Join-Path $tailored "$prov\COPY-TO-WORKSPACE\$($pmeta.instruction_src)"
      }
      # Claude uses CLAUDE.md
      if ($prov -eq 'Claude') {
        $srcInst = Join-Path $tailored 'Claude\COPY-TO-PROVIDER-HOME\CLAUDE.md'
        if (-not (Test-Path $srcInst)) { $srcInst = Join-Path $PackRoot 'COPY-TO-YOUR-WORKSPACE\CLAUDE.md' }
      }
      if (Test-Path $srcInst) {
        $instructionTarget = Join-Path $providerHome $pmeta.instructions
        if (Test-Path -LiteralPath $instructionTarget -PathType Leaf) {
          Write-UabsOk ("{0} existing instructions preserved; managed SOUL/AIO block refreshes later" -f $prov)
        } else {
          Copy-Item -LiteralPath $srcInst -Destination $instructionTarget
          Write-UabsOk ("{0} instructions -> {1}" -f $prov, $instructionTarget)
        }
      }
    }
    Write-UabsOk "$prov skills installed"
  }
}

# ---------- Portable starter settings (v7.7.3) ----------
# New users get Claude settings.json / Codex+Grok+Kimi config.toml /
# Hermes config.yaml without a live-machine dump. Existing homes are
# preserved. Instruction files (unrestraint / SOUL / AIO preamble) are
# not touched here.
if (-not $ToolsOnly -and -not $SkipStarterSettings) {
  $starter = Join-Path $PackRoot 'TOOLS\Install-Provider-Starter-Settings.ps1'
  if (Test-Path -LiteralPath $starter) {
    try {
      $starterArgs = @{
        PackRoot = $PackRoot
        Providers = $Providers
      }
      if ($SkipHermesConfig) { $starterArgs.SkipHermes = $true }
      & $starter @starterArgs
    } catch {
      Write-UabsWarn ('Starter settings: ' + $_.Exception.Message)
    }
  } else {
    Write-UabsWarn 'TOOLS\Install-Provider-Starter-Settings.ps1 missing from pack'
  }
}

# ---------- Native plugins: superpowers + ponytail ----------
# Claude refuses to refresh a marketplace whose recorded path no longer exists
# (the pack folder was renamed once, and every later install died on it). Point
# recorded paths that lost their target back at the same plugin inside the
# current pack before any provider plugin command runs.
$claudeKm = Join-Path $env:USERPROFILE '.claude\plugins\known_marketplaces.json'
if (Test-Path -LiteralPath $claudeKm -PathType Leaf) {
  try {
    $km = Get-Content -LiteralPath $claudeKm -Raw | ConvertFrom-Json
    $kmChanged = $false
    foreach ($prop in @($km.PSObject.Properties)) {
      $entry = $prop.Value
      # Claude records the marketplace twice: a directory source path and an
      # installLocation. Both go stale when the pack folder is renamed.
      $holders = @(
        @{ Obj = $entry; Field = 'path' },
        @{ Obj = $entry; Field = 'installLocation' }
      )
      if ($entry.source) { $holders += @{ Obj = $entry.source; Field = 'path' } }
      foreach ($holder in $holders) {
        $recorded = $holder.Obj.($holder.Field)
        if (-not $recorded -or (Test-Path -LiteralPath $recorded)) { continue }
        $leaf = Split-Path $recorded -Leaf
        $candidate = Join-Path $PackRoot ('BUNDLED-TOOLS\plugins\' + $leaf)
        if ($leaf -and (Test-Path -LiteralPath $candidate -PathType Container)) {
          $holder.Obj.($holder.Field) = $candidate
          $kmChanged = $true
          Write-UabsOk ("Claude marketplace '{0}' repointed to this pack: {1}" -f $prop.Name, $candidate)
        }
      }
    }
    if ($kmChanged) {
      Copy-Item -LiteralPath $claudeKm -Destination ($claudeKm + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
      [IO.File]::WriteAllText($claudeKm, (($km | ConvertTo-Json -Depth 8) + "`n"), (New-Object Text.UTF8Encoding $false))
    }
  } catch {
    Write-UabsWarn ('Claude marketplace path repair skipped: ' + $_.Exception.Message)
  }
}

# Installs the two bundled skills-plugins NATIVE per provider where the CLI
# has a real plugin mechanism (all mechanisms verified live on the reference
# machine):
#   Grok    grok plugin install superpowers --trust from the marketplace
#           (never a second local clone next to official_marketplace auto-
#           install - two plugins named superpowers collide on
#           systematic-debugging). ponytail has no Grok manifest and stays
#           as copied skills.
#   Hermes  hermes plugins install file:///<path> --enable from a local git
#           bridge (Hermes rejects plain paths), with
#           plugins.scan_on_install: false in config.yaml because the security
#           scanner false-positives on both plugins and --force does not
#           override it. The Superpowers bridge drops Claude/Codex/Cursor/Devin/Kimi
#           manifests; Hermes would otherwise parse them on every gateway start.
#           A gateway that was already running stays down until profile migration
#           finishes, then restarts. Restarting it here lets it save the pre-migration
#           config back over the file.
#   Codex   bundled superpowers staged into the local marketplace +
#           [plugins."superpowers@ultimate-bundle"] enabled = true in
#           config.toml; ponytail is detected (user's own marketplace
#           install), never reinstalled.
#   Claude  installed through Claude's own plugin CLI when it is on PATH, with
#           the marketplace name read from each plugin's own
#           .claude-plugin\marketplace.json; success is confirmed by the cache
#           directory appearing, not by an exit code. Without the CLI this
#           falls back to detect-only plus the copied skills.
#   Kimi    native plugin written to plugins\managed\<id> + a thin entry in
#           plugins\installed.json. There is no `kimi plugin` subcommand -
#           the plugin system is driven by an in-session /plugins command -
#           but the registry format is stable because Kimi re-derives every
#           record from disk on load.
# Where a plugin is native, its skill name list is computed from the bundled
# tree (never hardcoded) and the matching copies are deduped from the
# provider's skills dir - backup-first, and only when the copy's SKILL.md
# md5 matches that provider's tailored source. Comparing to canonical falsely
# labels deliberate Claude-to-Codex tailoring as a user edit.
$nativePlugins = [ordered]@{}
if (-not $ToolsOnly -and -not $SkipNativePlugins) {
  Write-UabsStep "Native plugins (superpowers + ponytail)"
  $backupRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\backups'
  New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

  function New-UabsPluginStateEntry {
    param([string]$Status = 'fallback-skills', [string]$Reason = '')
    return [ordered]@{ native = $false; status = $Status; reason = $Reason; deduped = @(); skipped_modified = @(); skipped_kept = @() }
  }

  function Invoke-UabsSkillDedupe {
    param([string]$Provider, [string]$PluginId, [string]$SkillsDir, $StateEntry)
    $names = Get-UabsPluginOwnedSkillNames -PluginRoot (Join-Path $plugins $PluginId)
    if (-not $names -or $names.Count -eq 0) {
      $StateEntry.skipped_kept = @('bundled plugin tree has no skills dir')
      return
    }
    $expectedRoot = Join-Path $tailored "$Provider\COPY-TO-SKILLS-DIRECTORY\skills"
    $res = Remove-UabsPluginOwnedSkillCopies -Provider $Provider -SkillsDir $SkillsDir -Names $names -ExpectedRoot $expectedRoot -BackupRoot $backupRoot -Log $log
    # owned = every skill the native plugin provides; deduped = copies removed by
    # THIS run. A re-run whose copies were already gone used to record nothing,
    # and the doctor then failed every one of them as missing.
    $StateEntry.owned = @($names)
    $StateEntry.deduped = @($res.removed)
    $StateEntry.skipped_modified = @($res.skipped_modified)
    $StateEntry.skipped_kept = @($res.skipped)
  }

  foreach ($prov in $Providers) {
    $providerHome = Get-UabsProviderHome -Provider $prov -Catalog $catalog
    $skillsDir = Get-UabsProviderSkillsDir -Provider $prov -Catalog $catalog
    $pstate = [ordered]@{ supported = $true; reason = ''; plugins = [ordered]@{} }
    $nativePlugins[$prov] = $pstate

    switch ($prov) {

      'Grok' {
        # ponytail ships no Grok manifest -> copied skills remain its path.
        $pstate.plugins['ponytail'] = New-UabsPluginStateEntry -Status 'fallback-skills' -Reason 'ponytail has no Grok manifest; copied skills stay'
        $spEntry = New-UabsPluginStateEntry
        $pstate.plugins['superpowers'] = $spEntry
        $grokExe = Join-Path $env:USERPROFILE '.grok\bin\grok.exe'
        if (-not (Test-Path -LiteralPath $grokExe -PathType Leaf)) {
          $gc = Get-Command grok -EA SilentlyContinue
          if ($gc) { $grokExe = $gc.Source } else { $grokExe = $null }
        }
        if (-not $grokExe) {
          $spEntry.status = 'fallback-skills'
          $spEntry.reason = 'grok CLI not found (neither ~/.grok/bin/grok.exe nor PATH); copied skills stay'
          Write-UabsWarn 'Grok CLI not found - superpowers stays as copied skills'
          break
        }
        $pluginStage = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\plugins-src\superpowers'
        Copy-UabsRobo -From (Join-Path $plugins 'superpowers') -To $pluginStage
        $spCatalog = $catalog.components | Where-Object { $_.id -eq 'superpowers' } | Select-Object -First 1
        $pinnedGrokSource = $spCatalog.github.owner + '/' + $spCatalog.github.repo + '@' + $spCatalog.release_tag
        # Collapse marketplace + local-path clones BEFORE treating "already
        # native" as success. Two plugins named superpowers both own
        # systematic-debugging and Grok reports that as a skill error.
        $hits = @(Repair-UabsGrokDuplicatePlugins -GrokExe $grokExe -PluginName 'superpowers')
        $hits = @($hits | Where-Object { -not $_.path -or (Test-Path -LiteralPath $_.path -PathType Container) })
        if ($hits.Count -ge 1) {
          [void](Invoke-UabsNative $grokExe @('plugin','update','superpowers'))
          $hits = @(Get-UabsGrokPluginList -GrokExe $grokExe | Where-Object { $_.name -eq 'superpowers' })
          $currentHits = @($hits | Where-Object { try { [version]$_.version -ge [version]$spCatalog.version } catch { $false } })
          if (-not $currentHits.Count) {
            [void](Invoke-UabsNative $grokExe @('plugin','install',$pinnedGrokSource,'--trust'))
          }
          $hits = @(Repair-UabsGrokDuplicatePlugins -GrokExe $grokExe -PluginName 'superpowers')
          $spEntry.native = $true
          $spEntry.status = 'updated-official-cli'
          Write-UabsOk ('Grok: superpowers installed/updated (' + $hits[0].repo_key + ')')
        } else {
          Write-Host ('  grok plugin install ' + $pinnedGrokSource + ' --trust')
          [void](Invoke-UabsNative $grokExe @('plugin', 'install', $pinnedGrokSource, '--trust'))
          $hits = @(Get-UabsGrokPluginList -GrokExe $grokExe | Where-Object { $_.name -eq 'superpowers' })
          if ($hits.Count -eq 0) {
            Write-Host ('  grok plugin install "' + $pluginStage + '" --trust')
            [void](Invoke-UabsNative $grokExe @('plugin', 'install', $pluginStage, '--trust'))
            $hits = @(Get-UabsGrokPluginList -GrokExe $grokExe | Where-Object { $_.name -eq 'superpowers' })
          }
          if ($hits.Count -gt 1) {
            $hits = @(Repair-UabsGrokDuplicatePlugins -GrokExe $grokExe -PluginName 'superpowers')
          }
          if ($hits.Count -ge 1) {
            $spEntry.native = $true
            $spEntry.status = 'installed'
            Write-UabsOk ('Grok: superpowers installed native (' + $hits[0].repo_key + ')')
          } else {
            $spEntry.status = 'fallback-skills'
            $spEntry.reason = 'grok plugin install did not take; copied skills stay'
            Write-UabsWarn 'Grok: superpowers native install failed - copied skills stay'
          }
        }
        if ($spEntry.native) {
          # Keep the copies. Grok chats and slash commands load
          # ~/.grok/skills/<name>/SKILL.md. Dedupe left that path missing, and
          # the TUI reports the skill as failed with no reason
          # (verification-before-completion, systematic-debugging, ...).
          Write-UabsOk 'Grok: superpowers copies stay under ~/.grok/skills (TUI loads that path; plugin path is opaque)'
        }
      }

      'Hermes' {
        $hermesExe = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
        if (-not (Test-Path -LiteralPath $hermesExe -PathType Leaf)) {
          $hc = Get-Command hermes -EA SilentlyContinue
          if ($hc) { $hermesExe = $hc.Source } else { $hermesExe = $null }
        }
        if (-not $hermesExe) {
          foreach ($pluginId in @('superpowers', 'ponytail')) {
            $pstate.plugins[$pluginId] = New-UabsPluginStateEntry -Status 'fallback-skills' -Reason 'hermes CLI not found; copied skills stay'
          }
          Write-UabsWarn 'Hermes CLI not found - plugins stay as copied skills'
          break
        }
        $gitCmd = Get-Command git -EA SilentlyContinue
        $gatewayStatus = Get-UabsNativeOutput -Exe $hermesExe -CmdArgs @('gateway', 'status')
        $gatewayWasRunning = $gatewayStatus -match '(?i)running' -and $gatewayStatus -notmatch '(?i)not running'
        if ($gatewayWasRunning) {
          if (-not (Invoke-UabsNative $hermesExe @('gateway', 'stop'))) { throw 'Hermes gateway could not be stopped for plugin refresh' }
          $script:UabsHermesGatewayWasRunning = $true
          Write-UabsOk 'Hermes gateway stopped for native plugin refresh; it stays down until config writes finish'
        }
        # Hermes desktop (Hermes.exe) loads config.yaml once at startup and
        # persists ITS in-memory copy on later saves. Left running, it rewrites
        # the file from pre-install state and silently wipes every mcp_servers
        # entry this install adds (same stale-config class as the gateway).
        # Stop it alongside the gateway; relaunched at the end of the script
        # once config.yaml is final.
        $hermesDesktop = Get-Process -Name 'Hermes' -ErrorAction SilentlyContinue
        if ($hermesDesktop) {
          $script:UabsHermesDesktopExe = ($hermesDesktop | Select-Object -First 1).Path
          # An install started from inside a Hermes chat closes the app that IS
          # the agent's parent, so that chat dies mid-run. Say so first: three
          # installs on 2026-10-16 each vanished a session with no explanation,
          # which reads as a crash and sends the owner hunting for a cause.
          if ($env:HERMES_AGENT -or $env:HERMES_DESKTOP) {
            Write-UabsWarn 'Hermes is running this install: closing the desktop app ends this chat session. Hermes is relaunched automatically when the install finishes - reopen the chat afterwards.'
          }
          Write-UabsWarn ('Hermes desktop is running - closing it for the install so its stale config cannot wipe the MCP entries (it will be relaunched when done)')
          $hermesDesktop | Stop-Process -Force -ErrorAction SilentlyContinue
          Start-Sleep -Milliseconds 500
        }
        # The scanner refuses both bundled plugins (false-positive 'traversal'
        # findings; --force does not override) - disarm scan-at-install first.
        $pstate.scan_on_install_fix = Set-UabsHermesPluginScanOff -ConfigPath (Join-Path $providerHome 'config.yaml')
        if ($pstate.scan_on_install_fix -eq 'failed') { throw 'Hermes plugin scanner override failed' }
        $newInstalls = 0
        try {
          foreach ($pluginId in @('superpowers', 'ponytail')) {
          $hEntry = New-UabsPluginStateEntry
          $pstate.plugins[$pluginId] = $hEntry
          # Offline bridge: Hermes rejects plain local paths, so stage the
          # bundled tree as a local git repo and hand Hermes a file:/// URL.
          $pluginStage = Join-Path $env:LOCALAPPDATA ('Ultimate-AI-Starter-Bundle\hermes-plugin-src\' + $pluginId)
          if (-not (Test-Path -LiteralPath (Join-Path $pluginStage 'skills') -PathType Container)) {
            Copy-UabsRobo -From (Join-Path $plugins $pluginId) -To $pluginStage
          }
          # Hermes loads a plugin from .hermes-plugin/plugin.yaml. Ponytail's
          # upstream tree ships only a Claude-style plugin.json, which Hermes
          # rejects with "unsupported or missing Agent Plugins schema" - so write
          # the Hermes manifest here or the native install can never succeed.
          $hermesManifest = Join-Path $pluginStage '.hermes-plugin\plugin.yaml'
          if (-not (Test-Path -LiteralPath $hermesManifest -PathType Leaf)) {
            New-Item -ItemType Directory -Force -Path (Split-Path $hermesManifest) | Out-Null
            $pluginVersion = if ($pluginId -eq 'superpowers') { '7.0.0' } else { '5.3.0' }
            @(
              "name: $pluginId",
              "version: $pluginVersion",
              "description: Bundled $pluginId skills for Hermes Agent"
            ) | Set-Content -LiteralPath $hermesManifest -Encoding utf8
            Write-UabsOk ("Hermes: wrote .hermes-plugin/plugin.yaml for $pluginId")
          }
          if (-not (Test-Path -LiteralPath (Join-Path $pluginStage '.git') -PathType Container)) {
            if (-not $gitCmd) {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'git not found - cannot build the local git bridge Hermes requires; copied skills stay'
              Write-UabsWarn ('Hermes: git missing - cannot stage ' + $pluginId + ' as a git repo; copied skills stay')
              continue
            }
            if ($pluginId -eq 'superpowers') {
              $bridgeStripped = @(Remove-UabsHermesForeignHarnessDirs -PluginRoot $pluginStage)
              if ($bridgeStripped.Count) {
                Write-UabsOk ('Hermes: Superpowers bridge dropped foreign manifests: ' + ($bridgeStripped -join ', '))
              }
            }
            [void](Invoke-UabsNative 'git' @('-C', $pluginStage, 'init'))
            [void](Invoke-UabsNative 'git' @('-C', $pluginStage, 'add', '-A'))
            if (-not (Invoke-UabsNative 'git' @('-C', $pluginStage, '-c', 'user.email=bundle@local', '-c', 'user.name=bundle', 'commit', '-m', 'bundled pin'))) {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'git init/commit of the offline plugin bridge failed; copied skills stay'
              Write-UabsWarn ('Hermes: git commit failed for ' + $pluginStage + ' - copied skills stay')
              continue
            }
          } else {
            # Bridge exists: refresh files from the pack and commit if the
            # bundle changed (safely corrective; a no-op when nothing changed).
            # Robocopy puts the other harness manifests back; strip them before
            # the dirty check so the deletion is part of the bridge commit.
            Copy-UabsRobo -From (Join-Path $plugins $pluginId) -To $pluginStage
            if ($pluginId -eq 'superpowers') {
              $bridgeStripped = @(Remove-UabsHermesForeignHarnessDirs -PluginRoot $pluginStage)
              if ($bridgeStripped.Count) {
                Write-UabsOk ('Hermes: Superpowers bridge dropped foreign manifests: ' + ($bridgeStripped -join ', '))
              }
            }
            $dirty = Get-UabsNativeOutput -Exe 'git' -CmdArgs @('-C', $pluginStage, 'status', '--porcelain')
            if ($dirty -and $dirty.Trim()) {
              [void](Invoke-UabsNative 'git' @('-C', $pluginStage, 'add', '-A'))
              [void](Invoke-UabsNative 'git' @('-C', $pluginStage, '-c', 'user.email=bundle@local', '-c', 'user.name=bundle', 'commit', '-m', 'bundled pin refresh'))
            }
          }
          $fileUrl = 'file:///' + ($pluginStage -replace '\\', '/')
          $listed = Get-UabsNativeOutput -Exe $hermesExe -CmdArgs @('plugins', 'list')
          if ($listed -match $pluginId) {
            $updated = Invoke-UabsNative $hermesExe @('plugins','update',$pluginId)
            if (-not $updated) {
              # V7 local file URLs can point at the retired state root. Replace
              # that official registration with the stable bridge.
              [void](Invoke-UabsNative $hermesExe @('plugins','remove',$pluginId))
              $updated = Invoke-UabsNative $hermesExe @('plugins','install',$fileUrl,'--enable')
            }
            $listed = Get-UabsNativeOutput -Exe $hermesExe -CmdArgs @('plugins','list')
            if ($updated -and $listed -match $pluginId) {
              $newInstalls++
              $hEntry.native = $true
              $hEntry.status = 'updated-official-cli'
              Write-UabsOk ('Hermes: ' + $pluginId + ' installed/updated')
            } else {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'official Hermes update/reinstall failed; copied skills stay'
            }
          } else {
            Write-Host ('  hermes plugins install "' + $fileUrl + '" --enable')
            [void](Invoke-UabsNative $hermesExe @('plugins', 'install', $fileUrl, '--enable'))
            $listed = Get-UabsNativeOutput -Exe $hermesExe -CmdArgs @('plugins', 'list')
            if ($listed -match $pluginId) {
              $hEntry.native = $true
              $hEntry.status = 'installed'
              $newInstalls++
              Write-UabsOk ('Hermes: ' + $pluginId + ' installed native')
            } else {
              $hEntry.status = 'fallback-skills'
              $hEntry.reason = 'hermes plugins install did not take; copied skills stay'
              Write-UabsWarn ('Hermes: ' + $pluginId + ' native install failed - copied skills stay')
            }
          }
            if ($hEntry.native) {
            if ($pluginId -eq 'superpowers') {
              $installedPlugin = Join-Path $providerHome ('plugins\' + $pluginId)
              $liveStripped = @(Remove-UabsHermesForeignHarnessDirs -PluginRoot $installedPlugin)
              if ($liveStripped.Count) {
                Write-UabsOk ('Hermes: installed Superpowers dropped foreign manifests: ' + ($liveStripped -join ', '))
              }
            }
            # Keep the copies. Hermes derives /skill-name slash commands and
            # desktop autofill from the skills dir (scan_skill_commands scans
            # SKILLS_DIR, not plugin registrations). Dedupe left that path
            # missing and /using-superpowers etc. stopped autocompleting -
            # same failure class as Grok's TUI (v7.7.5).
              Write-UabsOk ('Hermes: ' + $pluginId + ' copies stay under ' + $skillsDir + ' (slash commands load that path; plugin path is opaque)')
            }
          }
        } finally {
          # Restore the operator's scanner setting. Leave the gateway down:
          # it rewrites config.yaml from the copy it loaded at start, and the
          # profile migration below has not run yet. Restart is after that write.
          $pstate.scan_on_install_restore = Restore-UabsHermesPluginScan `
            -ConfigPath (Join-Path $providerHome 'config.yaml') `
            -State $pstate.scan_on_install_fix
          if ($script:UabsHermesGatewayWasRunning) {
            Write-UabsOk 'Hermes gateway stays stopped until profile migration finishes'
          } elseif ($newInstalls -gt 0) {
            Write-UabsOk 'Hermes gateway was stopped before install - left stopped'
          }
        }
      }

      'Codex' {
        $codexCli = Get-UabsCodexCli
        if (-not $codexCli) {
          foreach ($pluginId in @('superpowers','ponytail')) {
            $pstate.plugins[$pluginId] = New-UabsPluginStateEntry -Reason 'codex CLI not found; copied skills stay'
          }
          Write-UabsWarn 'Codex CLI not found - plugins stay as copied skills'
          break
        }

        # `codex plugin list --json` refuses to answer AT ALL when any one
        # configured marketplace snapshot is unloadable -- including a
        # marketplace that has nothing to do with the plugin being checked.
        # An empty inventory then reads as "the native install failed", the
        # dedupe below never runs, and the copied skills stay in the index
        # alongside the plugin's own. Measured on this machine: a stale
        # headroom-marketplace snapshot cost 20 duplicate skill entries.
        # Codex's config.toml is the registry the CLI renders, so fall back
        # to it rather than treating an unreadable inventory as empty.
        $script:UabsCodexInventoryDegraded = $false
        function Get-UabsCodexInstalledPluginIds {
          $raw = Get-UabsNativeOutput -Exe $codexCli.Source -CmdArgs @('plugin','list','--json')
          $ids = @()
          try { $ids = @((($raw | ConvertFrom-Json).installed) | ForEach-Object { [string]$_.pluginId }) } catch { }
          if ($ids.Count) { return $ids }
          $fallback = @(Get-UabsCodexEnabledPluginIds -CodexHome $providerHome)
          if ($fallback.Count -and -not $script:UabsCodexInventoryDegraded) {
            $script:UabsCodexInventoryDegraded = $true
            Write-UabsWarn ('Codex: `plugin list --json` returned nothing usable; read ' +
              $fallback.Count + ' plugin(s) from config.toml instead. Repair it with: codex plugin marketplace upgrade <name>')
          }
          return $fallback
        }

        # Retire the manually-written V7 marketplace through Codex's official
        # lifecycle so later upgrades are owned by Codex, not stale TOML.
        $ids = @(Get-UabsCodexInstalledPluginIds)
        foreach ($legacyId in @('completeness-gate@ultimate-bundle','superpowers@ultimate-bundle')) {
          if ($ids -contains $legacyId) {
            [void](Invoke-UabsNative $codexCli.Source @('plugin','remove',$legacyId,'--json'))
            Write-UabsOk ('Codex: removed legacy manual plugin ' + $legacyId)
          }
        }
        $marketRaw = Get-UabsNativeOutput -Exe $codexCli.Source -CmdArgs @('plugin','marketplace','list','--json')
        if ($marketRaw -match '"name"\s*:\s*"ultimate-bundle"') {
          [void](Invoke-UabsNative $codexCli.Source @('plugin','marketplace','remove','ultimate-bundle','--json'))
          Write-UabsOk 'Codex: removed legacy manual ultimate-bundle marketplace'
        }
        foreach ($legacyMarketplace in @(
          (Join-Path $env:LOCALAPPDATA ('Skyrim-AI-' + 'V5\codex-marketplace')),
          (Join-Path (Get-UabsStateRoot) 'codex-marketplace')
        )) {
          $legacyManifest = Join-Path $legacyMarketplace '.claude-plugin\marketplace.json'
          if ((Test-Path -LiteralPath $legacyManifest -PathType Leaf) -and
              ([IO.File]::ReadAllText($legacyManifest) -match '"name"\s*:\s*"ultimate-bundle"')) {
            Remove-Item -LiteralPath $legacyMarketplace -Recurse -Force
            Write-UabsOk ('Codex: removed legacy owned marketplace tree ' + $legacyMarketplace)
          }
        }

        foreach ($pluginId in @('superpowers','ponytail')) {
          $entry = New-UabsPluginStateEntry
          $pstate.plugins[$pluginId] = $entry
          $srcRoot = Join-Path $plugins $pluginId
          $upstreamUrl = @{
            superpowers = 'https://github.com/obra/superpowers.git'
            ponytail    = 'https://github.com/DietrichGebert/ponytail.git'
          }[$pluginId]
          $preferOnline = ($Mode -ne 'BundledOnly') -and $upstreamUrl
          $marketName = Get-UabsClaudeMarketplaceName -PluginRoot $srcRoot
          if (-not $marketName) {
            $entry.reason = 'bundled marketplace manifest missing; copied skills stay'
            continue
          }
          $marketRaw = Get-UabsNativeOutput -Exe $codexCli.Source -CmdArgs @('plugin','marketplace','list','--json')
          $marketEntry = $null
          try {
            $marketDoc = $marketRaw | ConvertFrom-Json
            $marketEntry = @($marketDoc.marketplaces | Where-Object { $_.name -eq $marketName } | Select-Object -First 1)
            if ($marketEntry.Count) { $marketEntry = $marketEntry[0] } else { $marketEntry = $null }
          } catch { }
          # V8.0.0's offline bridge was valid but deliberately had no remote,
          # so Codex correctly disabled Marketplace -> Upgrade. Online modes
          # migrate only our owned bridge to the upstream Git marketplace;
          # BundledOnly and failed network attempts keep the offline source.
          if ($marketEntry -and $preferOnline -and
              $marketEntry.marketplaceSource.sourceType -ne 'git' -and
              $marketEntry.root -and (Test-UabsPathWithin $marketEntry.root (Get-UabsStateRoot))) {
            $oldRoot = [string]$marketEntry.root
            $oldNativeId = $pluginId + '@' + $marketName
            if (@(Get-UabsCodexInstalledPluginIds) -contains $oldNativeId) {
              [void](Invoke-UabsNative $codexCli.Source @('plugin','remove',$oldNativeId,'--json'))
            }
            $removed = Invoke-UabsNative $codexCli.Source @('plugin','marketplace','remove',$marketName,'--json')
            $migrated = $false
            if ($removed) {
              $migrated = Invoke-UabsNative $codexCli.Source @('plugin','marketplace','add',$upstreamUrl,'--json')
            }
            if ($migrated) {
              $marketRaw = Get-UabsNativeOutput -Exe $codexCli.Source -CmdArgs @('plugin','marketplace','list','--json')
              try {
                $marketDoc = $marketRaw | ConvertFrom-Json
                $marketEntry = @($marketDoc.marketplaces | Where-Object { $_.name -eq $marketName } | Select-Object -First 1)[0]
              } catch { $marketEntry = $null }
              if (Test-Path -LiteralPath $oldRoot -PathType Container) {
                Remove-Item -LiteralPath $oldRoot -Recurse -Force
              }
              Write-UabsOk ('Codex: migrated ' + $marketName + ' to its upgradeable upstream Git marketplace')
            } else {
              [void](Invoke-UabsNative $codexCli.Source @('plugin','marketplace','add',$oldRoot,'--json'))
              $marketEntry = [pscustomobject]@{ root = $oldRoot; marketplaceSource = [pscustomobject]@{ sourceType = 'local' } }
              Write-UabsWarn ('Codex: upstream marketplace unavailable for ' + $marketName + '; kept the bundled offline source')
            }
          }
          if ($marketEntry) {
            if ($marketEntry.marketplaceSource.sourceType -eq 'git') {
              [void](Invoke-UabsNative $codexCli.Source @('plugin','marketplace','upgrade',$marketName,'--json'))
            } elseif ($marketEntry.root -and (Test-UabsPathWithin $marketEntry.root (Get-UabsStateRoot)) -and
                      (Test-Path -LiteralPath (Join-Path $marketEntry.root '.git') -PathType Container)) {
              # This is the owned offline marketplace. Refresh its tracked tree
              # in place, then the official plugin remove/add below refreshes
              # Codex's cache. `marketplace upgrade` is Git-remote-only and
              # prints a false error for a local source.
              $gitExe = Get-Command git -ErrorAction SilentlyContinue
              if (-not $gitExe) { $entry.reason = 'git missing; cannot refresh local Codex marketplace'; continue }
              [void](Invoke-UabsNative $gitExe.Source @('-C',$marketEntry.root,'rm','-r','-f','--ignore-unmatch','.'))
              Copy-UabsRobo -From $srcRoot -To $marketEntry.root
              $agentMarket = Join-Path $marketEntry.root '.agents\plugins\marketplace.json'
              if (Test-Path -LiteralPath $agentMarket -PathType Leaf) {
                $agentDoc = [IO.File]::ReadAllText($agentMarket) | ConvertFrom-Json
                foreach ($agentPlugin in @($agentDoc.plugins | Where-Object { $_.name -eq $pluginId })) {
                  $agentPlugin.source = [pscustomobject]@{ source = 'url'; url = './' }
                }
                [IO.File]::WriteAllText($agentMarket, (($agentDoc | ConvertTo-Json -Depth 20) + "`n"), (New-Object Text.UTF8Encoding $false))
              }
              [void](Invoke-UabsNative $gitExe.Source @('-C',$marketEntry.root,'add','-A'))
              $dirty = Get-UabsNativeOutput -Exe $gitExe.Source -CmdArgs @('-C',$marketEntry.root,'status','--porcelain')
              if ($dirty -and $dirty.Trim()) {
                [void](Invoke-UabsNative $gitExe.Source @('-C',$marketEntry.root,'-c','user.email=bundle@local','-c','user.name=bundle','commit','-m','bundled plugin pin refresh'))
              }
              Write-UabsOk ('Codex: refreshed owned local marketplace ' + $marketName)
            } else {
              Write-UabsWarn ('Codex: marketplace ' + $marketName + ' is local but not bundle-owned; preserved without upgrade')
            }
          } else {
            # Codex installs marketplace entries by Git-cloning their source,
            # even when the marketplace itself was added from a local path.
            # Release ZIPs contain no .git directory, so build a small owned
            # local repo and make the Agent Plugins manifest point at itself.
            if ($preferOnline -and (Invoke-UabsNative $codexCli.Source @('plugin','marketplace','add',$upstreamUrl,'--json'))) {
              Write-UabsOk ('Codex: added upgradeable upstream marketplace ' + $marketName)
            } else {
            $gitExe = Get-Command git -ErrorAction SilentlyContinue
            if (-not $gitExe) {
              $entry.reason = 'git missing; official Codex plugin install needs a Git source; copied skills stay'
              continue
            }
            $codexSource = Join-Path (Get-UabsStateRoot) ('codex-plugin-src\' + $pluginId)
            if (Test-Path -LiteralPath $codexSource -PathType Container) {
              Remove-Item -LiteralPath $codexSource -Recurse -Force
            }
            Copy-UabsRobo -From $srcRoot -To $codexSource
            $agentMarket = Join-Path $codexSource '.agents\plugins\marketplace.json'
            if (Test-Path -LiteralPath $agentMarket -PathType Leaf) {
              $agentDoc = [IO.File]::ReadAllText($agentMarket) | ConvertFrom-Json
              foreach ($agentPlugin in @($agentDoc.plugins | Where-Object { $_.name -eq $pluginId })) {
                $agentPlugin.source = [pscustomobject]@{ source = 'url'; url = './' }
              }
              [IO.File]::WriteAllText($agentMarket, (($agentDoc | ConvertTo-Json -Depth 20) + "`n"), (New-Object Text.UTF8Encoding $false))
            }
            [void](Invoke-UabsNative $gitExe.Source @('-C',$codexSource,'init'))
            [void](Invoke-UabsNative $gitExe.Source @('-C',$codexSource,'add','-A'))
            if (-not (Invoke-UabsNative $gitExe.Source @('-C',$codexSource,'-c','user.email=bundle@local','-c','user.name=bundle','commit','-m','bundled plugin pin'))) {
              $entry.reason = 'failed to commit the local Codex plugin source; copied skills stay'
              continue
            }
            if (-not (Invoke-UabsNative $codexCli.Source @('plugin','marketplace','add',$codexSource,'--json'))) {
              $entry.reason = 'official marketplace add failed; copied skills stay'
              continue
            }
            }
          }
          $nativeId = $pluginId + '@' + $marketName
          $ids = @(Get-UabsCodexInstalledPluginIds)
          if ($ids -contains $nativeId) {
            [void](Invoke-UabsNative $codexCli.Source @('plugin','remove',$nativeId,'--json'))
          }
          if (Invoke-UabsNative $codexCli.Source @('plugin','add',$nativeId,'--json')) {
            $ids = @(Get-UabsCodexInstalledPluginIds)
          }
          if ($ids -contains $nativeId) {
            $entry.native = $true
            $entry.status = 'installed-official-cli'
            Write-UabsOk ('Codex: installed/updated through official CLI: ' + $nativeId)
            Invoke-UabsSkillDedupe -Provider 'Codex' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $entry
          } else {
            $entry.status = 'fallback-skills'
            $entry.reason = 'official plugin add did not appear in inventory; copied skills stay'
            Write-UabsWarn ('Codex: ' + $pluginId + ' native install failed - copied skills stay')
          }
        }

      }

      'Claude' {
        # Native install via Claude's own plugin CLI when it is on PATH.
        #
        # Both bundled plugins already ship a Claude marketplace of their own
        # (BUNDLED-TOOLS\plugins\<id>\.claude-plugin\marketplace.json, each
        # with source "./"), so the marketplace name comes from that file
        # rather than a hardcoded string - superpowers publishes itself as
        # 'superpowers-dev', ponytail as 'ponytail'.
        #
        # What this deliberately does NOT do: hand-write
        # plugins\cache\<marketplace>\<plugin> plus the matching
        # .install-manifests entry. That manifest is a per-file SHA256
        # integrity map, and forging one means reimplementing Claude Code's
        # own verification against a format we cannot test here. Kimi's
        # registry was safe to write because the shipped CLI re-derives every
        # record from disk on load; this one is not. Without the CLI the
        # copied skills stay, which is a working fallback.
        $claudeCli = Get-Command claude -ErrorAction SilentlyContinue
        foreach ($pluginId in @('superpowers', 'ponytail')) {
          $cEntry = New-UabsPluginStateEntry
          $pstate.plugins[$pluginId] = $cEntry
          $srcRoot = Join-Path $plugins $pluginId
          $mkName = Get-UabsClaudeMarketplaceName -PluginRoot $srcRoot
          $cacheHit = $false
          if ($mkName) {
            $cachePath = Join-Path $providerHome ('plugins\cache\' + $mkName + '\' + $pluginId)
            $cacheHit = Test-Path -LiteralPath $cachePath -PathType Container
          }
          if ($cacheHit) {
            $updatedClaude = $false
            if ($claudeCli) {
              [void](Invoke-UabsNative $claudeCli.Source @('plugin','marketplace','update',$mkName))
              $updatedClaude = Invoke-UabsNative $claudeCli.Source @('plugin','update',($pluginId + '@' + $mkName),'--scope','user','--yes')
            }
            $cEntry.native = $true
            $cEntry.status = if ($updatedClaude) { 'updated-official-cli' } else { 'already-native' }
            Write-UabsOk ('Claude: ' + $pluginId + ' native (' + $mkName + ') - deduping its copied skills')
            Invoke-UabsSkillDedupe -Provider 'Claude' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $cEntry
            continue
          }
          if (-not $mkName) {
            $cEntry.status = 'fallback-skills'
            $cEntry.reason = 'bundled tree has no .claude-plugin\marketplace.json'
            Write-UabsWarn ('Claude: ' + $pluginId + ' has no Claude marketplace in the bundle - copied skills stay')
            continue
          }
          if (-not $claudeCli) {
            $cEntry.status = 'fallback-skills'
            $cEntry.reason = 'claude CLI not on PATH; copied skills stay'
            Write-UabsWarn ('Claude: ' + $pluginId + ' not native and no claude CLI on PATH - copied skills stay. To wire it natively:')
            Write-Host ('    claude plugin marketplace add "' + $srcRoot + '"')
            Write-Host ('    claude plugin install ' + $pluginId + '@' + $mkName + ' --scope user')
            continue
          }
          try {
            $prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
            & claude plugin marketplace add "$srcRoot" 2>&1 | Out-Null
            & claude plugin install ("$pluginId@$mkName") --scope user 2>&1 | Out-Null
            $ErrorActionPreference=$prevEap
            $cachePath = Join-Path $providerHome ('plugins\cache\' + $mkName + '\' + $pluginId)
            if (Test-Path -LiteralPath $cachePath -PathType Container) {
              $cEntry.native = $true
              $cEntry.status = 'installed'
              Write-UabsOk ('Claude: native plugin installed - ' + $pluginId + '@' + $mkName)
              Invoke-UabsSkillDedupe -Provider 'Claude' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $cEntry
            } else {
              # The CLI returned without producing a cache entry. Do not
              # report success on an exit code alone - the cache directory is
              # the only proof Claude actually loaded it.
              $cEntry.status = 'failed'
              $cEntry.reason = 'claude plugin install left no plugins\cache entry'
              Write-UabsWarn ('Claude: ' + $pluginId + ' install did not take - copied skills stay')
            }
          } catch {
            $cEntry.status = 'failed'
            $cEntry.reason = $_.Exception.Message
            Write-UabsWarn ('Claude: ' + $pluginId + ' install failed (' + $_.Exception.Message + ') - copied skills stay')
          }
        }
        # Retire the old UNREGISTERED plugins\uabs-bundled\<id> drop - dead
        # weight Claude never loaded. Move to the backup dir, never delete.
        $moved = @()
        foreach ($pluginId in @('superpowers', 'ponytail')) {
          $dead = Join-Path $providerHome ('plugins\uabs-bundled\' + $pluginId)
          if (Test-Path -LiteralPath $dead -PathType Container) {
            $mdest = Join-Path $backupRoot ('uabs-bundled-cleanup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '\' + $pluginId)
            Copy-UabsRobo -From $dead -To $mdest
            Remove-Item -LiteralPath $dead -Recurse -Force
            $moved += $mdest
            Write-UabsOk ('Claude: moved dead drop ' + $dead + ' -> ' + $mdest)
          }
        }
        $pstate.v5_bundled_moved = $moved
      }

      'Kimi' {
        # Kimi DOES have a native plugin system. Earlier builds of this
        # installer checked for a `kimi plugin` subcommand, did not find one
        # (correctly - there is none), and concluded Kimi had no plugins at
        # all. It is driven by the in-session `/plugins` slash command, whose
        # install path writes <home>\plugins\managed\<id> plus a thin entry
        # in <home>\plugins\installed.json. Prompt mode cannot stand in for
        # the slash command (it requires a login first), so the registry is
        # written directly - safe because Kimi re-parses each plugin's
        # manifest from disk on load rather than trusting the stored record.
        #
        # This is the fix for "Kimi has the brain but ignores my addons": the
        # bundled adapter declares sessionStart.skill = using-superpowers, so
        # Superpowers bootstraps itself on every Kimi session instead of
        # sitting inert as copied skill files.
        $pstate.supported = $true
        foreach ($pluginId in @('superpowers', 'ponytail')) {
          $kEntry = New-UabsPluginStateEntry
          $pstate.plugins[$pluginId] = $kEntry
          $src = Join-Path (Join-Path $PackRoot 'BUNDLED-TOOLS\plugins') $pluginId
          $manifestDir = Join-Path $src '.kimi-plugin\plugin.json'
          $manifestRoot = Join-Path $src 'plugin.json'
          if (-not (Test-Path -LiteralPath $manifestDir) -and
              -not (Test-Path -LiteralPath $manifestRoot)) {
            # Ponytail ships no Kimi adapter today; that is not a failure,
            # its copied skills remain the delivery path.
            $kEntry.status = 'unsupported'
            $kEntry.reason = 'no Kimi plugin manifest in the bundled tree'
            Write-UabsOk ('Kimi: ' + $pluginId + ' has no Kimi adapter - copied skills stay')
            continue
          }
          $kr = Install-UabsKimiPlugin -KimiHome $providerHome -PluginId $pluginId -SourceRoot $src
          if ($kr.ok) {
            $kEntry.status = 'installed'
            $kEntry.native = $true
            $kEntry.root = $kr.root
            Write-UabsOk ('Kimi: native plugin installed - ' + $pluginId + ' (' + $kr.root + ')')
            Invoke-UabsSkillDedupe -Provider 'Kimi' -PluginId $pluginId -SkillsDir $skillsDir -StateEntry $kEntry
          } else {
            $kEntry.status = 'failed'
            $kEntry.reason = $kr.reason
            Write-UabsWarn ('Kimi: ' + $pluginId + ' native install failed (' + $kr.reason + ') - copied skills stay')
          }
        }
      }
    }
  }
}

# -SkipNativePlugins means "do not install, update, remove, or reconfigure a
# plugin". It must not mean "pretend already-enabled plugins own no skills".
# A skills-only sync recreates canonical copies first; reconcile those copies
# against the provider's existing registry without invoking any plugin CLI.
if (-not $ToolsOnly -and $SkipNativePlugins) {
  $backupRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\backups'
  New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
  foreach ($prov in @($Providers | Where-Object { $_ -in @('Claude', 'Codex', 'Kimi') })) {
    $providerHome = Get-UabsProviderHome -Provider $prov -Catalog $catalog
    $skillsDir = Get-UabsProviderSkillsDir -Provider $prov -Catalog $catalog
    $enabledIds = @()
    if ($prov -eq 'Codex') {
      $enabledIds = @(Get-UabsCodexEnabledPluginIds -CodexHome $providerHome)
    } elseif ($prov -eq 'Kimi') {
      $enabledIds = @(Get-UabsKimiEnabledPluginIds -KimiHome $providerHome)
    } else {
      $settingsPath = Join-Path $providerHome 'settings.json'
      if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        try {
          $settings = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
          if ($settings.enabledPlugins) {
            $enabledIds = @($settings.enabledPlugins.PSObject.Properties |
              Where-Object { $_.Value -eq $true } | ForEach-Object { [string]$_.Name })
          }
        } catch { Write-UabsWarn 'Claude enabled-plugin registry is unreadable; copied skills were kept.' }
      }
    }

    $pstate = [ordered]@{ supported = $true; reason = 'plugin lifecycle skipped; existing ownership reconciled read-only'; plugins = [ordered]@{} }
    foreach ($pluginId in @('superpowers', 'ponytail')) {
      $srcRoot = Join-Path $plugins $pluginId
      $marketName = Get-UabsClaudeMarketplaceName -PluginRoot $srcRoot
      $nativeId = if ($prov -eq 'Kimi') { $pluginId } elseif ($marketName) { $pluginId + '@' + $marketName } else { '' }
      $isNative = $nativeId -and ($enabledIds -contains $nativeId)
      if ($isNative -and $prov -eq 'Claude') {
        $isNative = Test-Path -LiteralPath (Join-Path $providerHome ('plugins\cache\' + $marketName + '\' + $pluginId)) -PathType Container
      }
      $entry = [ordered]@{
        native = [bool]$isNative
        status = $(if ($isNative) { 'detected-existing' } else { 'fallback-skills' })
        reason = $(if ($isNative) { 'left installed plugin unchanged' } else { 'no enabled, reachable native plugin detected' })
        deduped = @(); skipped_modified = @(); skipped_kept = @()
      }
      $pstate.plugins[$pluginId] = $entry
      if (-not $isNative) { continue }
      $names = @(Get-UabsPluginOwnedSkillNames -PluginRoot $srcRoot)
      $expectedRoot = Join-Path $tailored "$prov\COPY-TO-SKILLS-DIRECTORY\skills"
      $res = Remove-UabsPluginOwnedSkillCopies -Provider $prov -SkillsDir $skillsDir `
               -Names $names -ExpectedRoot $expectedRoot -BackupRoot $backupRoot -Log $log
      $entry.owned = @($names)
      $entry.deduped = @($res.removed)
      $entry.skipped_modified = @($res.skipped_modified)
      $entry.skipped_kept = @($res.skipped)
      Write-UabsOk ("${prov}: existing $nativeId left unchanged; reconciled " + @($res.removed).Count + ' copied skill(s)')
    }
    $nativePlugins[$prov] = $pstate
  }
}

# Built-in ownership is independent of plugin lifecycle. Run this once after
# either full plugin reconciliation or -SkipNativePlugins, including skills-only
# syncs. The verified backup preserves modified copies shadowing a built-in.
if (-not $ToolsOnly -and ($Providers -contains 'Codex')) {
  $providerHome = Get-UabsProviderHome -Provider 'Codex' -Catalog $catalog
  $skillsDir = Get-UabsProviderSkillsDir -Provider 'Codex' -Catalog $catalog
  $expectedSkills = Join-Path $tailored 'Codex\COPY-TO-SKILLS-DIRECTORY\skills'
  $backupRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\backups'
  $builtins = @(Get-UabsCodexBuiltinSkillNames -CodexHome $providerHome | Where-Object {
    Test-Path -LiteralPath (Join-Path $expectedSkills $_) -PathType Container
  })
  if ($builtins.Count) {
    if (-not $nativePlugins['Codex']) { $nativePlugins['Codex'] = [ordered]@{ plugins = [ordered]@{} } }
    $nativePlugins['Codex'].codex_builtin_deduped = @($builtins)
    $bres = Remove-UabsPluginOwnedSkillCopies -Provider 'Codex' -SkillsDir $skillsDir `
              -Names $builtins -ExpectedRoot $expectedSkills -BackupRoot $backupRoot -Log $log -BackupModified
    if (@($bres.removed).Count) {
      Write-UabsOk ('Codex: removed ' + @($bres.removed).Count +
        ' copy/copies of a skill Codex ships itself: ' + (@($bres.removed) -join ', '))
    }
  }
}

# ---------- Pack instruction blocks ----------
# Each enabled pack adds one short marked block to every provider instruction
# file; a disabled pack's block is removed. An exact copy of an older bundle's
# long unmarked Skyrim section is replaced by the provider's general template.
if (-not $ToolsOnly) {
  $tailoredHome = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES'
  $soulMark = (([IO.File]::ReadAllText((Join-Path $PackRoot '3-PREAMBLES\SOUL.md'))).Trim() -split '\r?\n')[0]
  $profileText = ''
  $profileReady = $false
  if (-not $SkipProfile) {
    # Personal profile: the user's own PROFILE.md plus a generated map of this
    # PC's game, mod-manager and tool folders. Never part of any repository.
    $profileDir = Get-UabsProfileRoot $ProfileRoot
    if ($ProfileTemplate) {
      $tpl = Join-Path $PackRoot ('BUNDLED-TOOLS\optional-profiles\' + $ProfileTemplate + '.md')
      if (-not (Test-Path -LiteralPath $tpl -PathType Leaf)) { throw ("Unknown profile template '$ProfileTemplate'. Available: " + ((Get-ChildItem -LiteralPath (Join-Path $PackRoot 'BUNDLED-TOOLS\optional-profiles') -Filter '*.md' | ForEach-Object BaseName) -join ', ')) }
      $mine = Join-Path $profileDir 'PROFILE.md'
      if (Test-Path -LiteralPath $mine -PathType Leaf) { Write-UabsOk ('PROFILE.md already exists; template not copied over it: ' + $mine) }
      else { New-Item -ItemType Directory -Force -Path $profileDir | Out-Null; Copy-Item -LiteralPath $tpl -Destination $mine; Write-UabsOk ('profile seeded from ' + $ProfileTemplate + ': ' + $mine) }
    }
    try { & (Join-Path $PackRoot 'TOOLS\Build-MachineMap.ps1') -ProfileRoot $profileDir -PackRoot $PackRoot } catch { Write-UabsWarn ('machine map: ' + $_.Exception.Message) }
    try { $profileText = Get-UabsProfileText -Root $profileDir; $profileReady = $true }
    catch { Write-UabsWarn ($_.Exception.Message + ' Existing profile blocks were preserved.') }
  }
  foreach ($prov in $Providers) {
    $provHome = Get-UabsProviderHome -Provider $prov -Catalog $catalog
    $targets = @()
    $general = $null
    if ($prov -eq 'Hermes') {
      $targets += (Join-Path $provHome 'SOUL.md')
      # Bundle-managed profiles only (they carry the bundle soul); a profile
      # with its own persona, such as a role-play gateway, is left alone.
      foreach ($pf in @(Get-ChildItem -LiteralPath (Join-Path $provHome 'profiles') -Filter 'SOUL.md' -Recurse -Depth 1 -File -ErrorAction SilentlyContinue)) {
        if ([IO.File]::ReadAllText($pf.FullName).Contains($soulMark)) { $targets += $pf.FullName }
      }
    } else {
      $instName = $catalog.providers.$prov.instructions
      if (-not $instName) { $instName = 'AGENTS.md' }
      $targets += (Join-Path $provHome $instName)
      $srcName = $catalog.providers.$prov.instruction_src
      if ($srcName) { $general = Join-Path $tailoredHome ($prov + '\COPY-TO-PROVIDER-HOME\' + $srcName) }
    }
    # A SOUL.md is the provider's persona and Hermes injects the whole file into
    # every request of every profile. The operator's private profile and machine
    # map therefore never go into a soul file: they belong in the provider
    # instruction file (AGENTS/CLAUDE) and in ~/.uabs/profile, which the preamble
    # tells the model to read when a task needs machine paths.
    $targets = @($targets | Where-Object { -not ($_ -match '(?i)(^|[\\/])SOUL\.md$') })
    foreach ($t in $targets) {
      $isSkyrimHermes = $t -match '(?i)[\\/]profiles[\\/]skyrim[\\/]SOUL\.md$'
      $packsHere = if ($prov -eq 'Hermes' -and $t -match '(?i)[\\/]profiles[\\/]' -and -not $isSkyrimHermes) { @() } else { $packSel.Enabled }
      try {
        if (Update-UabsInstructionPacks -Path $t -PackRoot $PackRoot -Enabled $packsHere -GeneralTemplate $general) {
          Write-UabsOk ("{0}: pack instructions updated ({1}) -> {2}" -f $prov, $(if ($packsHere.Count) { $packsHere -join ', ' } else { 'none' }), $t)
        }
        if (-not $SkipProfile -and $profileReady -and (Update-UabsInstructionProfile -Path $t -Text $profileText)) {
          Write-UabsOk ("{0}: personal profile {1} -> {2}" -f $prov, $(if ($profileText) { 'updated' } else { 'removed' }), $t)
        }
      } catch { Write-UabsWarn ("$prov instructions: " + $_.Exception.Message) }
    }
  }
}

# ---------- AI preamble: SOUL + AIO for every agent (v7.5.0) ----------
# Wires the same preamble into every selected provider so a fresh machine
# behaves like the operator's own setup. Idempotent: re-running replaces the
# marked block instead of stacking copies; every write gets a .bak first.
if (-not $ToolsOnly -and -not $SkipPreamble) {
  Write-UabsStep "SOUL + AIO preamble wiring"
  $preDir = Join-Path $PackRoot '3-PREAMBLES'
  # One soul source for every provider. Until v7.6.2 there were two files -
  # SOUL.md opened with 'You are Hermes Agent' and SOUL-UNIVERSAL.md was the
  # de-branded copy. v7.6.0 genericised SOUL.md itself (a provider identity
  # injected into four other providers is what made Kimi refuse its own
  # unrestraint block), which left the two files identical. Keeping a second
  # copy only invites them to drift apart again.
  $soulF = Join-Path $preDir 'SOUL.md'
  $aioF  = Join-Path $PackRoot '0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md'
  foreach ($prov in $Providers) {
    if ($prov -eq 'Hermes') {
      # Hermes reads SOUL.md from its home. Use the same marked SOUL + AIO
      # writer as every other provider; the old raw-copy branch reset Hermes
      # to the short base soul and skipped the operating contract entirely.
      $hhome = Get-UabsProviderHome -Provider Hermes -Catalog $catalog
      $hSoul = Join-Path $hhome 'SOUL.md'
      Install-UabsPreambleBlock -Path $hSoul -SoulFile $soulF -AioFile $aioF -Force:$ForcePreamble
      # Profiles carry their own SOUL.md (a profile is created by cloning the
      # default, which copies it). A profile cloned before a wiring run, or
      # left behind by an older installer, would otherwise run a stale or
      # duplicated soul. Wire every profile that has one; never create one,
      # because a profile without SOUL.md inherits the home copy.
      # Only profiles that carry the bundle soul: a persona profile (the
      # SillyTavern role-play gateway) got the coding contract appended here
      # and its own installer overwrote it again, on every install.
      foreach ($pf in @(Get-UabsHermesManagedProfiles -HermesHome $hhome -SoulFile $soulF)) {
        Install-UabsPreambleBlock -Path (Join-Path $pf.FullName 'SOUL.md') -SoulFile $soulF -AioFile $aioF -Force:$ForcePreamble
      }
      continue
    }
    $pmeta = $catalog.providers.$prov
    $instName = $pmeta.instructions
    if (-not $instName) { $instName = 'AGENTS.md' }
    $target = Join-Path (Get-UabsProviderHome -Provider $prov -Catalog $catalog) $instName
    if (-not (Test-Path -LiteralPath $soulF) -or -not (Test-Path -LiteralPath $aioF)) {
      Write-UabsWarn ("$prov preamble skipped: 3-PREAMBLES or 0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md missing")
      continue
    }
    try {
      Install-UabsPreambleBlock -Path $target -SoulFile $soulF -AioFile $aioF -Force:$ForcePreamble
    } catch {
      Write-UabsWarn ("$prov preamble failed: " + $_.Exception.Message)
    }
  }
}

# ---------- Hermes config.yaml ----------
# v7.7.3: wholesale replace of a live Hermes YAML is gone. That used to
# stamp one operator's MCP paths onto every install. New Hermes homes get
# the portable starter above; existing homes keep their YAML. MCP and
# completeness-gate hooks are still wired later in this script.

# ---------- Workspace ----------
if ($WorkspaceRoot) {
  Write-UabsStep "Workspace files -> $WorkspaceRoot"
  New-Item -ItemType Directory -Force -Path $WorkspaceRoot | Out-Null
  $ws = Join-Path $PackRoot 'COPY-TO-YOUR-WORKSPACE'
  Copy-Item (Join-Path $ws 'AGENTS.md') (Join-Path $WorkspaceRoot 'AGENTS.md') -Force -EA SilentlyContinue
  Copy-Item (Join-Path $ws 'CLAUDE.md') (Join-Path $WorkspaceRoot 'CLAUDE.md') -Force -EA SilentlyContinue
  $tpl = Join-Path $ws '_PROJECT-TEMPLATE'
  if (Test-Path $tpl) { Copy-UabsRobo -From $tpl -To (Join-Path $WorkspaceRoot '_PROJECT-TEMPLATE') }
  Write-UabsOk "Workspace template copied"
}

# ---------- Tools ----------
$installed = [ordered]@{}
if (-not $SkillsOnly) {
  foreach ($id in $Components) {
    $comp = $catalog.components | Where-Object { $_.id -eq $id } | Select-Object -First 1
    if (-not $comp) { Write-UabsWarn "skip unknown $id"; continue }
    Write-UabsStep "Component: $($comp.name) [$id]"

    # A known security hold must not be bypassed by extras or an explicit selection.
    if ($comp.security_hold) {
      # On hold is a decision, not a fault: one quiet line, the reason in the details log.
      Write-UabsInfo ("${id}: on security hold, not installed (reason in CATALOG.json)")
      Add-UabsDetails -Title "$id security hold" -Lines @($comp.security_hold)
      $installed[$id] = @{ status='security-held'; note=$comp.security_hold }
      continue
    }

    switch ($comp.install) {
      'manual-user-product' {
        Write-UabsWarn $comp.note
        $installed[$id] = @{ status='manual'; note=$comp.note }
      }
      'npx-or-npm' {
        $npm = Get-Command npm -EA SilentlyContinue
        if ($npm) {
          try {
            # Already at the pinned version in the active global root: leave it.
            # A reinstall rewrote ~160 packages every run for no change.
            $npmCurrent = [string]$comp.version -and ((Get-UabsNpmGlobalVersion -Npm $npm.Source -Spec $comp.npm_spec) -ceq [string]$comp.version)
            if (-not $npmCurrent -and $comp.npm_integrity) {
              $reported = (& $npm.Source view $comp.npm_spec dist.integrity --json 2>$null | Out-String).Trim()
              if ($LASTEXITCODE -ne 0 -or -not $reported) { throw "INTEGRITY: npm could not verify $($comp.npm_spec)" }
              $actualIntegrity = [string]($reported | ConvertFrom-Json)
              if ($actualIntegrity -cne [string]$comp.npm_integrity) {
                throw "INTEGRITY: $($comp.npm_spec) registry integrity changed"
              }
            }
            $npmArgs = @('install', '-g')
            if ($comp.npm_args) { $npmArgs += @($comp.npm_args) }
            $npmArgs += $comp.npm_spec
            if ($npmCurrent -or (Invoke-UabsNative $npm.Source $npmArgs)) {
              $installed[$id] = @{ status='npm-global'; spec=$comp.npm_spec; integrity=$comp.npm_integrity; args=@($comp.npm_args) }
              if ($npmCurrent) { Write-UabsOk "$($comp.name) $($comp.version) is already installed" }
              else { Write-UabsOk "npm -g $($comp.npm_spec)" }
              Remove-UabsOutdatedHermesNpmDuplicate -Component $comp -ActiveNpm $npm.Source
            } else { throw "npm exited with code $LASTEXITCODE" }
          } catch {
            if ($_.Exception.Message -like 'INTEGRITY:*') {
              Write-UabsBad $_.Exception.Message
              $installed[$id] = @{ status='blocked-integrity'; spec=$comp.npm_spec }
            } else {
              Write-UabsWarn "npm global failed - users can run: npx $($comp.npm_spec)"
              $installed[$id] = @{ status='npx-fallback' }
            }
          }
        } else {
          Write-UabsWarn "Node/npm missing - $($comp.name) can run through its pinned npx package after Node is installed"
          $installed[$id] = @{ status='skipped-no-node' }
        }
      }
      'pip-or-wheel' {
              $cliName = if ($comp.cli) { [string]$comp.cli } else { 'headroom' }
              $cliEnv = if ($comp.cli_env) { [string]$comp.cli_env } else { 'HEADROOM_CMD' }
              $extras = if ($comp.source_dir) { '' } else { '[mcp]' }
              $packageSpec = if ($comp.source_dir) { Join-Path $PackRoot $comp.source_dir } else { $comp.pip_spec }
              <#
              Prefer a python that actually has pip. The Hermes desktop exports its
              own venv python on PATH first (no pip), which used to kill this step
              instantly. Try 'python', then 'py -3', then 'python3', and strip
              PYTHONPATH so pip does not see a venv's site-packages.
              #>
              $py = $null
              foreach ($c in @('python', 'py', 'python3')) {
                if (Get-Command $c -EA SilentlyContinue) {
                  $probe = if ($c -eq 'py') { @('-3', '-m', 'pip', '--version') } else { @('-m', 'pip', '--version') }
                  # Stdout-only probe: the Store python stub's stderr no longer
                  # lands in the install log as a TerminatingError.
                  $null = Get-UabsNativeStdout -Exe $c -CmdArgs $probe
                  if ($LASTEXITCODE -ne 0) { continue }
                  # A venv interpreter cannot --user install (user site-packages
                  # are invisible inside a virtualenv), and shells whose PATH
                  # puts a venv first used to fail the whole component here.
                  $kindArgs = if ($c -eq 'py') { @('-3', '-c', "import sys; print('venv' if sys.prefix != sys.base_prefix else 'base')") } else { @('-c', "import sys; print('venv' if sys.prefix != sys.base_prefix else 'base')") }
                  $kind = (@(Get-UabsNativeStdout -Exe $c -CmdArgs $kindArgs) -join '').Trim()
                  if ($kind -eq 'base' -or $c -eq 'py') { $py = $c; break }
                }
              }
              $uv = Get-Command uv -ErrorAction SilentlyContinue
              if (-not $py -and -not $uv) {
                Write-UabsBad 'No base Python with pip or uv found - install Python 3.12 and re-run'
                $installed[$id] = @{ status = 'failed' }
                continue
              }
              $asset = if ($comp.source_dir) {
                $wheel = Join-Path $offline $comp.offline_asset
                if (Test-Path -LiteralPath $wheel -PathType Leaf) { $wheel }
              } else { Get-ComponentAssetPath -Comp $comp }
              $ok = $false
              $hrInstalled = $null
              $installMethod = 'pip'
              if ($uv) {
                # Already at this exact version and it runs: leave it. Reinstalling
                # every run re-downloaded its dependencies and killed the copy each
                # open chat was using (headroom, the toolbox).
                $uvCurrent = $null; $uvWanted = $null; $uvName = $null
                $wheelName = if ($asset -and $asset.EndsWith('.whl')) { Split-Path -Leaf $asset } else { [string]$comp.offline_asset }
                if ($wheelName -match '^(?<n>[^-]+)-(?<v>[^-]+)-') { $uvName = $Matches['n'].Replace('_', '-').ToLowerInvariant(); $uvWanted = $Matches['v'] }
                if ($uvName) {
                  foreach ($toolLine in @(Get-UabsNativeStdout -Exe $uv.Source -CmdArgs @('tool', 'list'))) {
                    if ($toolLine -match ('^' + [regex]::Escape($uvName) + ' v(?<v>\S+)\s*$')) { $uvCurrent = $Matches['v'] }
                  }
                }
                $activeHeadroom = Get-Command $cliName -ErrorAction SilentlyContinue
                $uvSkip = $false
                if ($uvCurrent -and $uvCurrent -ceq $uvWanted -and $activeHeadroom -and $activeHeadroom.Source) {
                  $null = Get-UabsNativeStdout -Exe $activeHeadroom.Source -CmdArgs @('--version')
                  $uvSkip = ($LASTEXITCODE -eq 0)
                }
                if ($uvSkip) {
                  $ok = $true; $installMethod = 'uv-tool'; $hrInstalled = $activeHeadroom.Source
                  Write-UabsOk "$($comp.name) $uvCurrent is already installed"
                }
              }
              if ($uv -and -not $uvSkip) {
                # Prefer uv's isolated tool environment. A pip --user install
                # can succeed into a Scripts directory that is not on PATH,
                # leaving an older ~/.local/bin/headroom.exe active.
                if ($activeHeadroom -and $activeHeadroom.Source) {
                  [void](Stop-UabsProcessUsingExecutable $activeHeadroom.Source)
                }
                $uvSpec = if ($asset -and $asset.EndsWith('.whl')) { $asset + $extras } else { $packageSpec }
                $uvArgs = @('tool','install','--force')
                if ($comp.python) { $uvArgs += @('--python', [string]$comp.python) }
                $ok = Invoke-UabsNative $uv.Source ($uvArgs + @($uvSpec))
                if ($ok) {
                  $installMethod = 'uv-tool'
                  $uvBin = @(& $uv.Source tool dir --bin 2>$null | Where-Object { $_ } | Select-Object -Last 1)
                  if ($uvBin.Count) {
                    $candidate = Join-Path ([string]$uvBin[0]) ($cliName + '.exe')
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $hrInstalled = $candidate }
                  }
                  Refresh-ProcessPath
                }
              }
              if (-not $ok -and $asset -and $asset.EndsWith('.whl') -and $py) {
                Write-Host "  pip install $asset"
                $env:PYTHONPATH = ''
                $wheelSpec = $asset + $extras
                # Invoke-UabsNative keeps pip's stderr ("already satisfied", the
                # pip-version notice) from surfacing as a NativeCommandError.
                if ($py -eq 'py') { $ok = Invoke-UabsNative 'py' (@('-3','-m','pip','install','--user',$wheelSpec)) }
                else { $ok = Invoke-UabsNative $py @('-m','pip','install','--user',$wheelSpec) }
              }
              if (-not $ok -and $py) {
                $spec = $packageSpec
                $env:PYTHONPATH = ''
                if ($py -eq 'py') { $ok = Invoke-UabsNative 'py' (@('-3','-m','pip','install','--user',$spec)) }
                else { $ok = Invoke-UabsNative $py @('-m','pip','install','--user',$spec) }
              }
              if ($ok -and -not $hrInstalled -and $py) {
                $scriptsProbe = "import os,sysconfig; print(os.path.join(sysconfig.get_path('scripts', scheme='nt_user'), '$cliName.exe'))"
                $probeArgs = if ($py -eq 'py') { @('-3','-c',$scriptsProbe) } else { @('-c',$scriptsProbe) }
                $candidate = @(& $py @probeArgs 2>$null | Where-Object { $_ } | Select-Object -Last 1)
                if ($candidate.Count -and (Test-Path -LiteralPath $candidate[0] -PathType Leaf)) { $hrInstalled = [string]$candidate[0] }
              }
        if ($ok) {
          $hr = $hrInstalled
          if (-not $hr) { try { $hr = (Get-Command $cliName -EA SilentlyContinue).Source } catch {} }
          if ($hr) { Set-UabsUserEnv $cliEnv $hr }
          $installed[$id] = @{ status=$installMethod; exe=$hr; version=$comp.version }
          if ($id -eq 'headroom') { $installed[$id].headroom = $hr }
          if (-not $hr) { $installed[$id].status = 'failed'; Write-UabsBad "$($comp.name) installed but $cliName does not resolve" }
          else { Write-UabsOk "$($comp.name) installed: $hr" }
        } else {
          Write-UabsBad "$($comp.name) install failed (need Python)"
          $installed[$id] = @{ status='failed' }
        }
      }
      'skills-copy' {
        # The plugin tree is now installed NATIVE per provider by the "Native
        # plugins" section above (Grok/Hermes/Codex real installs, Claude
        # detect-only, Kimi unsupported). The old unregistered
        # plugins\uabs-bundled\<id> drop for Claude was dead weight - Claude
        # never loaded it - so it is gone; the native section moves any
        # existing drop to the backup dir instead of deleting it.
        $installed[$id] = @{ status='native-or-skills' }
        Write-UabsOk "$id handled by the native-plugin section (fallback: copied skills)"
      }
      'zip-extract' {
        $asset = Get-ComponentAssetPath -Comp $comp
        if (-not $asset) {
          Write-UabsBad "No asset for $id - run TOOLS\Update-From-GitHub.ps1 -$id or check network"
          $installed[$id] = @{ status='missing-asset' }
          continue
        }
        $target = Expand-UabsEnvPath $comp.target_dir
        $stage = Join-Path $env:TEMP "uabs-extract-$id-$(Get-Random)"
        New-Item -ItemType Directory -Force -Path $stage | Out-Null
        try {
          Expand-UabsZip -Zip $asset -Dest $stage
          $rootExtract = Resolve-UabsSingleRoot $stage
          # houseCARL zip layout: may contain housecarl\server or server
          if ($id -eq 'housecarl') {
            $existingMcp = $env:HOUSECARL_MCP
            if ($existingMcp -and (Test-Path $existingMcp) -and -not (Test-UabsPathWithin $existingMcp $target)) {
              $existingRoot = if ($env:HOUSECARL_ROOT -and (Test-Path $env:HOUSECARL_ROOT)) { $env:HOUSECARL_ROOT } else { Split-Path (Split-Path $existingMcp -Parent) -Parent }
              $want = [string]$comp.version
              $have = Get-UabsBinaryVersion $existingMcp
              $cmp = if ($have) { Compare-UabsDottedVersion $have $want } else { $null }
              # An external install belongs to the user, but it is still the
              # bundle's job to keep it current: refresh it when it is behind the
              # bundled version, leave it alone when it is level or ahead, and
              # never downgrade a newer copy the user installed themselves.
              if ($null -ne $cmp -and $cmp -lt 0) {
                $backupRoot = Join-Path $env:LOCALAPPDATA ('Ultimate-AI-Starter-Bundle\backups\houseCARL-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
                New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
                Copy-Item -LiteralPath $existingRoot -Destination $backupRoot -Recurse -Force
                $srcMcp = Find-UabsFileUnder $rootExtract 'housecarl-mcp.exe' 8
                if (-not $srcMcp) { throw 'housecarl-mcp.exe not in zip' }
                $destServer = Join-Path $existingRoot 'server'
                New-Item -ItemType Directory -Force -Path $destServer | Out-Null
                Copy-UabsRoboSafe -From (Split-Path $srcMcp -Parent) -To $destServer -CriticalFiles @('housecarl-mcp.exe')
                $now = Get-UabsBinaryVersion $existingMcp
                Set-UabsUserEnv 'HOUSECARL_MCP' $existingMcp
                Set-UabsUserEnv 'HOUSECARL_ROOT' $existingRoot
                $installed[$id] = @{ status='external-updated'; mcp=$existingMcp; root=$existingRoot; from=$have; to=$now }
                Write-UabsOk ("houseCARL external install updated {0} -> {1}: {2} (backup: {3})" -f $have, $now, $existingMcp, $backupRoot)
              }
              else {
                Set-UabsUserEnv 'HOUSECARL_MCP' $existingMcp
                Set-UabsUserEnv 'HOUSECARL_ROOT' $existingRoot
                $installed[$id] = @{ status='external-current'; mcp=$existingMcp; root=$existingRoot; version=$have }
                $label = if ($have) { "v$have" } else { 'version unknown' }
                Write-UabsOk ("houseCARL external install kept ({0}, bundle has v{1}): {2}" -f $label, $want, $existingMcp)
              }
            }
            else {
              $mcp = Find-UabsFileUnder $rootExtract 'housecarl-mcp.exe' 8
              if (-not $mcp) { throw "housecarl-mcp.exe not in zip" }
              $serverDir = Split-Path $mcp -Parent
              $productRoot = Split-Path $serverDir -Parent
              # Install to LOCALAPPDATA\houseCARL
              New-Item -ItemType Directory -Force -Path $target | Out-Null
              Copy-UabsRoboSafe -From $productRoot -To $target -CriticalFiles @('server\housecarl-mcp.exe')
              # If setup exe present at outer folder
              $setup = Find-UabsFileUnder $rootExtract 'houseCARL-Setup.exe' 4
              if ($setup) {
                Copy-Item $setup (Join-Path $target 'houseCARL-Setup.exe') -Force
              }
              $mcpFinal = Join-Path $target 'server\housecarl-mcp.exe'
              if (-not (Test-Path $mcpFinal)) { $mcpFinal = Find-UabsFileUnder $target 'housecarl-mcp.exe' 5 }
              Set-UabsUserEnv 'HOUSECARL_MCP' $mcpFinal
              Set-UabsUserEnv 'HOUSECARL_ROOT' $target
              $installed[$id] = @{ status='installed-or-updated'; mcp=$mcpFinal; root=$target }
              Write-UabsOk "houseCARL installed/updated -> $target"
            }
          }
          elseif ($id -eq 'codebase-memory') {
            $existing = Find-UabsCodebaseMemoryExe
            if ($existing -and -not (Test-UabsPathWithin $existing $target)) {
              $want = [string]$comp.version
              $have = Get-UabsBinaryVersion $existing
              if (-not $have) { $have = Get-UabsProcessVersion $existing }
              $cmp = if ($have) { Compare-UabsDottedVersion $have $want } else { $null }
              # Same contract as houseCARL and Spooky: refresh a stale external
              # install, keep a level-or-newer one, never downgrade.
              if ($null -ne $cmp -and $cmp -lt 0) {
                $backupRoot = Join-Path $env:LOCALAPPDATA ('Ultimate-AI-Starter-Bundle\backups\codebase-memory-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
                New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
                Copy-Item -LiteralPath $existing -Destination $backupRoot -Force
                [void](Stop-UabsProcessUsingExecutable $existing)
                $srcExe = Find-UabsFileUnder $rootExtract 'codebase-memory-mcp.exe' 6
                if (-not $srcExe) { throw 'codebase-memory-mcp.exe not in the bundled archive' }
                Copy-Item -LiteralPath $srcExe -Destination $existing -Force
                $now = Get-UabsProcessVersion $existing
                Set-UabsUserEnv 'CODEBASE_MEMORY_MCP' $existing
                $installed[$id] = @{ status='external-updated'; exe=$existing; from=$have; to=$now }
                Write-UabsOk ("codebase-memory external install updated {0} -> {1}: {2} (backup: {3})" -f $have, $now, $existing, $backupRoot)
              }
              else {
                Set-UabsUserEnv 'CODEBASE_MEMORY_MCP' $existing
                $installed[$id] = @{ status='external-current'; exe=$existing; version=$have }
                $label = if ($have) { "v$have" } else { 'version unknown' }
                Write-UabsOk ("codebase-memory external install kept ({0}, bundle has v{1}): {2}" -f $label, $want, $existing)
              }
            }
              else {
                New-Item -ItemType Directory -Force -Path $target | Out-Null
                $destExe = Join-Path $target 'codebase-memory-mcp.exe'
                if ((Test-Path -LiteralPath $destExe) -and (Test-UabsFileLocked $destExe)) {
                  $stopped = Stop-UabsProcessUsingExecutable $destExe
                  if (-not $stopped -or (Test-UabsFileLocked $destExe)) {
                    throw 'codebase-memory exe is locked and its exact owning process could not be stopped safely'
                  }
                  Write-UabsOk 'codebase-memory MCP process stopped for binary refresh; providers will reconnect on demand'
                }
                Copy-UabsRoboSafe -From $rootExtract -To $target -CriticalFiles @('codebase-memory-mcp.exe')
                $exe = Join-Path $target 'codebase-memory-mcp.exe'
                if (-not (Test-Path $exe)) { $exe = Find-UabsFileUnder $target 'codebase-memory-mcp.exe' 4 }
                if (-not $exe) { throw 'codebase-memory-mcp.exe missing after extract' }
                Set-UabsUserEnv 'CODEBASE_MEMORY_MCP' $exe
                $installed[$id] = @{ status = 'installed-or-updated'; exe = $exe }
                Write-UabsOk ("codebase-memory installed/updated -> " + $exe)
              }
          }
          elseif ($id -eq 'spooky') {
            $existingRoot = $env:SPOOKY_AUTOMOD_ROOT
            if ($existingRoot -and (Test-Path (Join-Path $existingRoot 'SpookysAutomod.sln')) -and -not (Test-UabsPathWithin $existingRoot $target)) {
              $want = [string]$comp.version
              $have = Get-UabsPathVersion $existingRoot
              $cmp = if ($have) { Compare-UabsDottedVersion $have $want } else { $null }
              # Same rule as houseCARL: update an older external toolkit in
              # place, never touch one that is level or ahead of the bundle.
              if ($null -ne $cmp -and $cmp -lt 0) {
                $backupRoot = Join-Path $env:LOCALAPPDATA ('Ultimate-AI-Starter-Bundle\backups\spooky-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
                New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
                Copy-Item -LiteralPath $existingRoot -Destination $backupRoot -Recurse -Force
                Copy-UabsRoboSafe -From $rootExtract -To $existingRoot
                Set-UabsUserEnv 'SPOOKY_AUTOMOD_ROOT' $existingRoot
                $installed[$id] = @{ status='external-updated'; root=$existingRoot; from=$have; to=$want }
                Write-UabsOk ("Spooky external install updated {0} -> {1} (backup: {2})" -f $have, $want, $backupRoot)
              }
              else {
                Set-UabsUserEnv 'SPOOKY_AUTOMOD_ROOT' $existingRoot
                $installed[$id] = @{ status='external-current'; root=$existingRoot; version=$have }
                $label = if ($have) { "v$have" } else { 'version unknown' }
                Write-UabsOk ("Spooky external install kept ({0}, bundle has v{1}): {2}" -f $label, $want, $existingRoot)
              }
            }
            else {
              New-Item -ItemType Directory -Force -Path $target | Out-Null
              Copy-UabsRobo -From $rootExtract -To $target
              # find sln
              $sln = Find-UabsFileUnder $target 'SpookysAutomod.sln' 5
              $toolkitRoot = if ($sln) { Split-Path $sln -Parent } else { $target }
              # nested spookys-automod-toolkit folder
              $inner = Join-Path $toolkitRoot 'spookys-automod-toolkit'
              if (Test-Path (Join-Path $inner 'SpookysAutomod.sln')) { $toolkitRoot = $inner }
              Set-UabsUserEnv 'SPOOKY_AUTOMOD_ROOT' $toolkitRoot
              $installed[$id] = @{ status='installed-or-updated'; root=$toolkitRoot }
              Write-UabsOk "Spooky installed/updated -> $toolkitRoot"
              Write-UabsWarn "Optional: run SpookysAutomodSetup.exe inside the toolkit folder for headers/compiler"
            }
          }
          elseif ($id -eq 'rtk') {
            $installed[$id] = Install-UabsRtkExecutable -Source (Join-Path $rootExtract $comp.exe_rel) `
              -Destination (Join-Path $target $comp.exe_rel) -ExpectedVersion $comp.version
            Write-UabsOk ("rtk " + $installed[$id].version + ' installed and verified')
          }
          else {
            # A component whose binary is CURRENTLY RUNNING cannot be
            # overwritten, and robocopy's answer to that is exit code 8, which
            # Copy-UabsRobo turns into a throw, which aborts the ENTIRE
            # install. Measured 2026-08-27: four github-mcp-server processes
            # were alive as MCP servers for open Claude/Codex/Grok/Kimi/Hermes
            # sessions, and running the installer produced
            #   INSTALL FAILED
            #   robocopy failed exit=8 from=...uabs-extract-github-mcp-server...
            # That is the ordinary case -- a user runs the installer with their
            # AI apps open -- and it took the whole run down over one file.
            #
            # houseCARL and codebase-memory already handle this; this generic
            # branch, which every other zip component falls through to, did
            # not. Same treatment: stop the exact owning process, and if it
            # still will not release, SKIP this one component with a loud
            # warning rather than failing everything around it.
            $lockedExes = @()
            if (Test-Path -LiteralPath $target -PathType Container) {
              foreach ($e in @(Get-ChildItem -LiteralPath $target -Recurse -File -Filter '*.exe' -EA SilentlyContinue)) {
                if (Test-UabsFileLocked $e.FullName) { $lockedExes += $e.FullName }
              }
            }
            foreach ($le in $lockedExes) {
              try { [void](Stop-UabsProcessUsingExecutable $le) } catch { }
            }
            $stillLocked = @($lockedExes | Where-Object { Test-UabsFileLocked $_ })
            if ($stillLocked.Count) {
              $installed[$id] = @{
                status = 'skipped-in-use'
                root   = $target
                locked = @($stillLocked)
              }
              Write-UabsWarn ($id + ': binary in use, left at the installed version -- ' +
                (($stillLocked | ForEach-Object { Split-Path -Leaf $_ }) -join ', '))
              Write-Host '     Close every AI app (their MCP servers hold this file) and re-run to update it.' -ForegroundColor DarkGray
              Write-Host '     Nothing else in this install was affected.' -ForegroundColor DarkGray
            } else {
              Copy-UabsRobo -From $rootExtract -To $target
              $componentState = @{ status='installed'; root=$target }
              if ($comp.exe_rel) {
                $installedExe = Join-Path $target $comp.exe_rel
                if (-not (Test-Path -LiteralPath $installedExe -PathType Leaf)) {
                  throw "$id executable missing after extract: $installedExe"
                }
                $componentState.exe = $installedExe
              }
              $installed[$id] = $componentState
            }
          }
        } finally {
          Remove-Item -LiteralPath $stage -Recurse -Force -EA SilentlyContinue
        }
      }
      # ---- extras: skills fetched from a git repo -------------------------
      # Layout differs per repo: some ARE one skill (skill_folder), some ship a
      # skills/ directory of several (skills_subdir). Both land in every
      # selected provider's skills folder, which is what all five CLIs read.
      'skills-git' {
        $wanted = @($Providers | Where-Object { $comp.providers -contains $_ })
        if (-not $wanted) { Write-UabsWarn "${id}: no selected provider wants it"; $installed[$id] = @{ status='skipped' }; continue }
        $stage = Join-Path $env:TEMP "uabs-skillsgit-$id-$(Get-Random)"
        try {
          if (Get-Command git -EA SilentlyContinue) {
            # git writes "Cloning into ..." to stderr even on success; with
            # $ErrorActionPreference='Stop' that would surface as a failure.
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
              & git clone --depth 1 --quiet $comp.git_url $stage 2>&1 | ForEach-Object { Write-Host ("     " + $_) }
              $gitCode = $LASTEXITCODE
            } finally { $ErrorActionPreference = $prevEap }
            if ($gitCode -ne 0) { throw "git clone exited $gitCode for $($comp.git_url)" }
          } else {
            # No git: fall back to the branch tarball via the release/zip path.
            $zip = Join-Path $cache "$id-main.zip"
            $u = "https://github.com/$($comp.github.owner)/$($comp.github.repo)/archive/refs/heads/main.zip"
            Save-UabsUrl -Url $u -OutFile $zip
            Expand-UabsZip -Zip $zip -Dest $stage
            $stage = Resolve-UabsSingleRoot $stage
          }
          if (-not (Test-Path $stage)) { throw "fetch failed for $id" }
          $pairs = @()
          if ($comp.skills_subdir) {
            $srcRoot = Join-Path $stage $comp.skills_subdir
            if (-not (Test-Path $srcRoot)) { throw "${id}: expected '$($comp.skills_subdir)' in the repo" }
            foreach ($sk in Get-ChildItem $srcRoot -Directory) { $pairs += @{ name = $sk.Name; path = $sk.FullName } }
          } else {
            $pairs += @{ name = $comp.skill_folder; path = $stage }
          }
          # The bundle vendors a snapshot of several of these skills in
          # _CANONICAL-SKILLS, and the final doctor verifies every provider
          # skill against what the bundle shipped. Copying an upstream clone
          # over the top makes those two facts disagree: the doctor reported six
          # skills stale/modified on five providers and failed the install, for
          # a switch this installer documents and offers. One owner per skill --
          # canonical owns what it ships, and this component installs the rest.
          $canonRoot = Join-Path $PackRoot '_CANONICAL-SKILLS'
          $ownedByCanonical = @()
          if (Test-Path -LiteralPath $canonRoot) {
            $ownedByCanonical = @(Get-ChildItem -LiteralPath $canonRoot -Directory -EA SilentlyContinue |
              Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
              ForEach-Object { $_.Name })
          }
          $skipped = @($pairs | Where-Object { $ownedByCanonical -contains $_.name } | ForEach-Object { $_.name })
          $pairs = @($pairs | Where-Object { $ownedByCanonical -notcontains $_.name })
          if ($skipped.Count) {
            Write-UabsInfo ("{0}: already vendored by this pack, not overwritten: {1}" -f $id, ($skipped -join ', '))
          }
          if (-not $pairs.Count) {
            Write-UabsOk ("${id}: every skill it provides is already vendored; nothing to copy")
            $installed[$id] = @{ status='vendored'; skills=@($skipped); providers=@() }
          } else {
            foreach ($prov in $wanted) {
              $destRoot = Get-UabsProviderSkillsDir -Provider $prov -Catalog $catalog
              foreach ($pair in $pairs) {
                Copy-UabsRobo -From $pair.path -To (Join-Path $destRoot $pair.name)
              }
              Write-UabsOk ("$id -> $prov ({0} skill(s))" -f $pairs.Count)
            }
            $installed[$id] = @{ status='installed'; skills=@($pairs.name); vendored=@($skipped); providers=$wanted }
          }
          if ($comp.scope_note) { Add-UabsDetails -Title "$id scope" -Lines @($comp.scope_note) }
        } catch {
          Write-UabsBad ("$id failed: " + $_.Exception.Message)
          $installed[$id] = @{ status='failed'; error=$_.Exception.Message }
        } finally {
          Remove-Item -LiteralPath $stage -Recurse -Force -EA SilentlyContinue
        }
      }

      # ---- extras: Claude Code plugin --------------------------------------
      'claude-plugin' {
        # HARD LOCK: never install Claude-only plugins for other providers
        if ($id -eq 'claude-mem' -or ($comp.providers -and ($comp.providers -notcontains 'Grok') -and ($comp.providers -contains 'Claude') -and ($comp.providers.Count -eq 1))) {
          if ($Providers -notcontains 'Claude') {
            Write-UabsWarn "$id is Claude Code ONLY - skipped (not for Grok/Codex/Kimi/Hermes)"
            $installed[$id] = @{ status='skipped-claude-only' }
            continue
          }
        }
        if ($Providers -notcontains 'Claude') { Write-UabsWarn "$id is Claude Code only - skipped"; $installed[$id] = @{ status='skipped' }; continue }
        # claude-mem worker needs Bun (bun:sqlite). Without it Claude shows red MCP errors.
        if ($id -eq 'claude-mem') {
          $bunExe = Find-UabsBunExecutable
          if (-not $bunExe) {
            Write-UabsWarn 'claude-mem requires Bun (https://bun.sh). Install Bun, open a NEW shell, then re-run the installer.'
            Write-UabsWarn 'Without Bun the plugin installs but MCP tools go red (worker cannot start).'
            $installed[$id] = @{ status='skipped-no-bun'; note='install Bun then re-run' }
            continue
          } else {
            $env:BUN = $bunExe
            $env:PATH = (Split-Path $bunExe -Parent) + ';' + $env:PATH
            Write-UabsOk 'Bun present (required for claude-mem worker)'
          }
        }
        if (-not (Get-Command npx -EA SilentlyContinue)) {
          Write-UabsWarn "$id needs Node/npx. Install Node, then: npx $($comp.npx_install -join ' ')"
          $installed[$id] = @{ status='skipped-no-node' }
          continue
        }
        try {
          if (-not (Invoke-UabsNative 'npx' @($comp.npx_install))) { throw "npx exited with code $LASTEXITCODE" }
          if ($id -eq 'claude-mem') {
            if (-not (Invoke-UabsNative 'npx' @('claude-mem','telemetry','disable'))) { throw 'claude-mem telemetry opt-out failed' }
            if (-not (Invoke-UabsNative 'npx' @('claude-mem','start'))) { throw 'claude-mem worker failed to start' }
          }
          $installed[$id] = @{ status='installed'; via='npx' }
          Write-UabsOk "$id installed (restart Claude Code to load the plugin)"
          if ($comp.scope_note) { Add-UabsDetails -Title "$id scope" -Lines @($comp.scope_note) }
        } catch {
          Write-UabsWarn ("$id via npx failed. In Claude Code run: /plugin marketplace add $($comp.marketplace[0])  then  /plugin install $($comp.marketplace[1])")
          $installed[$id] = @{ status='manual'; error=$_.Exception.Message }
        }
      }

      # ---- extras: npx-launched MCP servers --------------------------------
      # Nothing is installed; npx resolves the package on first launch. We only
      # write the server block into each provider's MCP config.
      'mcp-npx' {
        $wanted = @($Providers | Where-Object { $comp.providers -contains $_ })
        if (-not $wanted) { Write-UabsWarn "${id}: not wanted by any selected provider"; $installed[$id] = @{ status='skipped' }; continue }
        if ($comp.PSObject.Properties.Name -contains 'auto_register' -and $comp.auto_register -eq $false) {
          $aliases = @($id, ($id -replace '-mcp$', '')) | Select-Object -Unique
          $cleaned = @(Remove-UabsGlobalMcpRegistration -Ids $aliases -FromProviders $wanted)
          Write-UabsOk "${id}: available through project-scoped profile '$($comp.profile)'; not registered globally"
          $installed[$id] = @{ status='profile-only'; profile=$comp.profile; cleaned_global=$cleaned }
          continue
        }
        if (-not (Get-Command npx -EA SilentlyContinue)) {
          Write-UabsWarn "$id needs Node/npx - skipping registration so we do not write a broken MCP entry"
          $installed[$id] = @{ status='skipped-no-node' }
          continue
        }
        $envMap = $null
        $keyName = $comp.api_key_env
        if ($keyName) {
          $keyVal = [Environment]::GetEnvironmentVariable($keyName, 'User')
          if (-not $keyVal) { $keyVal = [Environment]::GetEnvironmentVariable($keyName, 'Process') }
          if ($keyVal) {
            $envMap = @{ $keyName = $keyVal }
          } elseif ($comp.api_key_optional -and $comp.keyless_registration -eq 'skip' -and -not $RegisterKeylessExtras) {
            # Installed is not registered. A server whose keyless surface is a
            # small fraction of its schema costs full price for a sliver of
            # capability -- firecrawl-mcp keyless is 2 usable tools out of 25,
            # ~9,080 schema-token estimate, duplicating a native capability. Through
            # 7.9.8 -WithExtras registered it anyway and said so in one line
            # nobody reads. Note this is an mcp-npx component: registering IS
            # installing, because npx resolves the package on first launch. So
            # nothing is cached here and nothing is lost -- the entry simply
            # waits for the key that makes the server worth carrying.
            Write-UabsWarn "${id}: NOT registered (no $keyName)"
            if ($comp.keyless_skip_reason) { Write-Host ("     " + $comp.keyless_skip_reason) -ForegroundColor DarkGray }
            Write-Host ("     Enable: setx $keyName ""<key>"" then re-run the installer") -ForegroundColor DarkGray
            Write-Host ("     Or register it keyless anyway: -RegisterKeylessExtras") -ForegroundColor DarkGray
            $aliases = @($id, ($id -replace '-mcp$', '')) | Select-Object -Unique
            $cleaned = @(Remove-UabsGlobalMcpRegistration -Ids $aliases -FromProviders $wanted)
            $installed[$id] = @{ status='not-registered-no-key'; needs=$keyName; cleaned_global=$cleaned }
            continue
          } elseif ($comp.api_key_optional) {
            Write-UabsWarn "${id}: no $keyName - registering anyway ($($comp.keyless_note))"
          } else {
            # Optional extra that needs the user's own paid key: nothing to fix.
            Write-UabsInfo "${id}: optional, needs your own $keyName - skipped"
            $aliases = @($id, ($id -replace '-mcp$', '')) | Select-Object -Unique
            $cleaned = @(Remove-UabsGlobalMcpRegistration -Ids $aliases -FromProviders $wanted)
            $installed[$id] = @{ status='skipped-no-key'; needs=$keyName; cleaned_global=$cleaned }
            continue
          }
        }
        # Optional extra CLI args from a user env var (v7.5.6). Lets an MCP
        # component be pointed at a user-chosen binary without a code change;
        # playwright-mcp uses it for --executable-path so it does not force
        # Google Chrome on people who run Opera GX / Brave / Vivaldi / etc.
        $npxArgs = @($comp.npx_args)
        $extraEnv = $comp.extra_args_env
        if ($extraEnv) {
          $extraVal = [Environment]::GetEnvironmentVariable($extraEnv, 'User')
          if (-not $extraVal) { $extraVal = [Environment]::GetEnvironmentVariable($extraEnv, 'Process') }
          if ($extraVal) {
            foreach ($part in @($comp.extra_args_template)) {
              $npxArgs += ($part -replace [regex]::Escape('{value}'), $extraVal)
            }
            Write-UabsOk ("$id extra args from $extraEnv : " + (($npxArgs | Select-Object -Skip $comp.npx_args.Count) -join ' '))
          } else {
            Write-UabsWarn "${id}: $extraEnv not set - using defaults ($($comp.id) may fall back to Google Chrome; set it to your browser exe to override)"
          }
        }
        $regs = @()
        foreach ($prov in $wanted) {
          switch ($prov) {
            'Grok'  {
              # grok-cli wedges at eight servers running. Add-Reasoning-MCPs and
              # Set-McpProfile both check this ceiling; the extras branch did
              # not, and walked Grok past it with no message.
              $grokCfg = Join-Path $env:USERPROFILE '.grok\config.toml'
              $grokDeclared = (Test-Path -LiteralPath $grokCfg) -and
                ([IO.File]::ReadAllText($grokCfg) -match [regex]::Escape("[mcp_servers.$id]"))
              if (-not $grokDeclared -and (Get-UabsGrokMcpCount) -ge $GrokMcpBudget) {
                Write-UabsWarn ("{0}: Grok already has {1} MCP server(s) (budget {2}); not added." -f $id, (Get-UabsGrokMcpCount), $GrokMcpBudget)
                Write-UabsWarn ('  Remove one from ~/.grok/config.toml, or re-run with -GrokMcpBudget 7 if no plugin adds one.')
              } else {
                Update-UabsGrokMcpBlock -Name $id -Command $comp.npx_command -ArgList $npxArgs -EnvMap $envMap -Startup 120 -Tool 6000 -SkipIfPresent
                $regs += 'Grok'
              }
            }
            'Codex' {
              $cfg = Join-Path (Get-UabsProviderHome -Provider Codex -Catalog $catalog) 'config.toml'
              Update-UabsGrokMcpBlock -Name $id -Command $comp.npx_command -ArgList $npxArgs -EnvMap $envMap -Startup 120 -Tool 6000 -SkipIfPresent -ConfigPath $cfg
              $regs += 'Codex'
            }
            'Claude' {
              if (Get-Command claude -EA SilentlyContinue) {
                $addArgs = @('mcp', 'add', '--scope', 'user')
                if ($envMap) { foreach ($k in $envMap.Keys) { $addArgs += @('--env', ("{0}={1}" -f $k, $envMap[$k])) } }
                $addArgs += @($id, '--', $comp.npx_command) + $npxArgs
                [void](Invoke-UabsNative 'claude' $addArgs)
                $regs += 'Claude'
              } else {
                Write-UabsWarn "$id for Claude: run  claude mcp add --scope user $id -- $($comp.npx_command) $($npxArgs -join ' ')"
              }
            }
            'Kimi' {
              $kimiCfg = Join-Path $env:USERPROFILE '.kimi-code\mcp.json'
              if (Test-Path -LiteralPath (Split-Path -Parent $kimiCfg)) {
                # Adding by catalog id is blind to the same server already
                # present under another name, which is how Hermes ended up with
                # both `playwright` and `playwright-mcp`. Match the package.
                $existingText = if (Test-Path -LiteralPath $kimiCfg) { [IO.File]::ReadAllText($kimiCfg) } else { '' }
                $dupe = Find-UabsServerByPackage -ConfigText $existingText -PackageBase (Get-UabsNpxPackageBase -Arguments $npxArgs)
                if ($dupe -and $dupe -ne $id) {
                  Write-UabsWarn ("{0}: Kimi already runs this package as '{1}', not adding a second entry" -f $id, $dupe)
                } else {
                  $spec = @{ id = $id; command = $comp.npx_command; args = $npxArgs; note = $id; key = $keyName }
                  [void](Add-UabsMcpJson -Path $kimiCfg -Section 'mcpServers' -Servers @($spec) -Provider 'Kimi' -Refresh)
                  $regs += 'Kimi'
                }
              } else {
                Write-UabsWarn "${id}: Kimi not installed, skipped"
              }
            }
            'Hermes' {
              $hp = Get-UabsHermesPaths
              if (Test-Path -LiteralPath $hp.Python -PathType Leaf) {
                $existingText = if (Test-Path -LiteralPath $hp.Config) { [IO.File]::ReadAllText($hp.Config) } else { '' }
                $dupe = Find-UabsServerByPackage -ConfigText $existingText -PackageBase (Get-UabsNpxPackageBase -Arguments $npxArgs)
                if ($dupe -and $dupe -ne $id) {
                  Write-UabsWarn ("{0}: Hermes already runs this package as '{1}', not adding a second entry" -f $id, $dupe)
                } else {
                  $spec = @{ id = $id; command = $comp.npx_command; args = $npxArgs; note = $id; key = $keyName }
                  [void](Add-UabsMcpHermes -Servers @($spec) -Refresh)
                  $regs += 'Hermes'
                }
              } else {
                Write-UabsWarn "${id}: Hermes not installed, skipped"
              }
            }
            default {
              # Reached only by a provider this pack does not know how to write.
              # Printing the block is a handoff, and it is the last resort, not
              # the plan -- Hermes and Kimi used to land here and silently got
              # nothing while the catalog claimed five providers.
              Write-UabsWarn ("{0}: add this MCP block to {1} yourself:" -f $id, $prov)
              Write-Host ("      command = ""{0}""  args = [{1}]" -f $comp.npx_command, (($npxArgs | ForEach-Object { '"' + $_ + '"' }) -join ', '))
            }
          }
        }
        $installed[$id] = @{ status='registered'; providers=$regs; key=$keyName }
        Write-UabsOk ("$id registered for: " + ($regs -join ', '))
        if ($comp.scope_note) { Add-UabsDetails -Title "$id scope" -Lines @($comp.scope_note) }
      }

      default { Write-UabsWarn "No installer for $($comp.install)" }
    }
  }

  # Never print an upstream init command here: it enables the broad rewrite
  # table. The bundle-owned hook installed below has a measured allowlist.
  if ($installed['rtk']) {
    Add-UabsDetails -Title 'rtk routing' -Lines @(
      'rtk is installed - safe routing covers status + standalone pytest/cargo/go tests.',
      'Broad upstream hooks remain off; diff/log/show/find/read/search and mutating Git stay raw.',
      'Use rtk explicitly for other noisy output, then verify savings with `rtk gain`.')
  }
}

# ---------- Grok compat cells (always, before any MCP decision) ----------
# Grok ships Claude-Code compatibility ON: it adopts ~/.claude skills, agents,
# plugins (with their hooks and .mcp.json), ~/.claude.json and settings.json.
# The hook and MCP halves of that were measured as pure cost - see
# GROK-MCP-TROUBLESHOOTING.md. Skills/rules/agents compat stays on.
if (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  Write-UabsStep "Grok Claude-compat cells"
  try {
    Set-UabsGrokCompatCells
  } catch { Write-UabsWarn ("Grok compat cells: " + $_.Exception.Message) }
}

# ---------- MCP wire (Grok) ----------
if (-not $SkipGrokMcp -and -not $SkipMcpWire -and -not $SkillsOnly -and ($Providers -contains 'Grok')) {
  Write-UabsStep "Wiring Grok MCP servers"
  $hr = $null
  try { $hr = (Get-Command headroom -EA SilentlyContinue).Source } catch {}
  if (-not $hr) { $hr = [Environment]::GetEnvironmentVariable('HEADROOM_CMD','User') }
  if ($hr -and (Test-Path $hr)) {
    Update-UabsGrokMcpBlock -Name 'headroom' -Command $hr -ArgList @('mcp','serve') -Startup 60 -Tool 600 -SkipIfPresent
  } elseif ($hr) {
    # might be bare command name
    Update-UabsGrokMcpBlock -Name 'headroom' -Command 'headroom' -ArgList @('mcp','serve') -Startup 60 -Tool 600 -SkipIfPresent
  }
  Write-UabsOk 'Skyrim MCPs stay out of the global Grok config; game profiles own activation'
}
elseif (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  Write-UabsWarn 'Grok MCP wiring skipped (-SkipGrokMcp).'
}

# grok-cli 1.0.4 wedges startup at eight RUNNING MCP servers (measured: 7 running
# = 0ms wait, 8 = ~34900ms and the process never exits). Plugin-provided servers
# count toward that but never appear in config.toml, so budget 6 configured.
if (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  $grokCfg = Join-Path $env:USERPROFILE '.grok\config.toml'
  if (Test-Path -LiteralPath $grokCfg) {
    # [ \t\r]* not [ \t]*: config.toml is CRLF and .NET's multiline $ matches
    # before the \n, so a trailing \r fails the anchor and the count reads 0.
    $srvCount = ([regex]::Matches(([IO.File]::ReadAllText($grokCfg)), '(?m)^[ \t]*\[mcp_servers\.[A-Za-z0-9_-]+\][ \t\r]*$')).Count
    # grok-cli 1.0.4 wedges at EIGHT running servers. Enabled Claude plugins with
    # a .mcp.json still load even with [compat.claude] mcps = false, so each one
    # eats a slot that never appears in config.toml. Budget 6 configured.
    if ($srvCount -ge 7) {
      Write-UabsWarn ("Grok has $srvCount MCP servers configured. Eight RUNNING wedges grok-cli 1.0.4, and enabled Claude plugins add servers you cannot see here - comment some out in ~/.grok/config.toml (see GROK-MCP-TROUBLESHOOTING.md).")
    } else {
      Write-UabsOk ("Grok MCP servers: $srvCount configured (budget 6; plugin-provided servers also count)")
    }
  }
}


# ---------- Headroom + Grok (MCP only; NEVER reroute inference) ----------
# Headroom's Grok proxy authenticates against https://api.x.ai with XAI_API_KEY.
# A Grok subscription / OIDC login uses https://cli-chat-proxy.grok.com instead,
# which Headroom cannot forward - wrapping it kills the model catalog (the model
# shows as "unknown") and 401s every turn. So the installer registers the
# Headroom MCP tools and leaves inference alone.
# API-key users can opt in afterwards:  .\TOOLS\Ensure-Headroom-Grok.ps1 -Wrap
if (-not $SkillsOnly -and ($Providers -contains 'Grok')) {
  $hrEnsure = Join-Path $PackRoot 'TOOLS\Ensure-Headroom-Grok.ps1'
  if (Test-Path $hrEnsure) {
    Write-UabsStep "Headroom Grok MCP registration (auth aware; repairs a v5.0 inference wrap)"
    try {
      $hrArgs = @()
      if ($SkipMcpWire) { $hrArgs += '-SkipMcp' }
      $hrCode = Invoke-UabsChildScript -Title 'Headroom for Grok' -File $hrEnsure -ArgList $hrArgs
      if ($hrCode -ne 0 -and $null -ne $hrCode) {
        Write-UabsWarn ("Ensure-Headroom-Grok exited " + $hrCode)
      } else {
        Write-UabsOk 'Headroom registered for Grok as MCP (inference left on the native endpoint)'
        $installed['headroom-grok-mcp'] = @{ status = 'mcp-only' }
      }
    } catch {
      Write-UabsWarn ("Ensure-Headroom-Grok: " + $_.Exception.Message)
      $installed['headroom-grok-mcp'] = @{ status = 'error'; error = $_.Exception.Message }
    }
  } else {
    Write-UabsWarn 'TOOLS\Ensure-Headroom-Grok.ps1 missing from pack'
  }
}
# ---------- houseCARL MO2/Vortex ----------
if (-not $SkipHouseCarlSetup -and -not $SkillsOnly -and $skyrimPackOn) {
  $setup = Join-Path $PackRoot 'TOOLS\Setup-HouseCarl.ps1'
  if (Test-Path $setup) {
    Write-UabsStep "houseCARL MO2/Vortex setup"
    try {
      # In-process: later steps read the env vars it sets in this process.
      & $setup -WireGrok:$false -WireCodex:$false -Quiet
      if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { Write-UabsWarn "houseCARL setup finished with code $LASTEXITCODE (see the lines above)" }
      else { Write-UabsOk 'houseCARL load-order access is set up (your AI refreshes it after Vortex changes)' }
      $installed['housecarl-setup'] = @{ status='ran' }
    } catch {
      Write-UabsWarn "Setup-HouseCarl: $($_.Exception.Message)"
      $installed['housecarl-setup'] = @{ status='error'; error=$_.Exception.Message }
    }
  }
}

# ---------- Skyrim Forge (Skyrim pack) ----------
# Forge is released from github.com/SenjuWoo/SkyrimForge again. CATALOG.json
# pins the release tag, asset and SHA-256; the installer uses the Full-Offline
# copy or a verified cached download, resolves ONE versionless install root,
# refreshes provider skill descriptors without global MCP registration, and
# proves `forge doctor`. The bundle's CI installs that exact release end to end,
# which is the check 7.8.0 lacked when the two repositories drifted apart.
if (-not $ToolsOnly -and -not $SkillsOnly -and -not $skyrimPackOn) {
  Write-Host '  ..  Skyrim Forge skipped: Skyrim pack is off' -ForegroundColor DarkGray
  $installed['skyrim-forge'] = @{ status='skipped'; reason='skyrim pack off' }
}
if (-not $ToolsOnly -and -not $SkillsOnly -and $skyrimPackOn) {
  $forgeInstaller = Join-Path $PackRoot 'TOOLS\Install-SkyrimForge.ps1'
  if (-not (Test-Path -LiteralPath $forgeInstaller -PathType Leaf)) { throw 'TOOLS\Install-SkyrimForge.ps1 missing from pack.' }
  $forgeEntry = @($catalog.components | Where-Object { $_.id -eq 'skyrim-forge' }) | Select-Object -First 1
  $forgeSourceVersion = if ($forgeEntry) { [string]$forgeEntry.version } else { 'unknown' }
  $forgeArgs = @('-PackRoot',$PackRoot,'-Providers',($Providers -join ','),'-BundleOwnsProviderSkills')
  if ($ForgeRoot) { $forgeArgs += @('-ForgeRoot', $ForgeRoot) }
  Write-UabsStep 'Skyrim Forge'
  $forgeCode = Invoke-UabsChildScript -Title 'Skyrim Forge install' -File $forgeInstaller -ArgList $forgeArgs
  if ($forgeCode -ne 0) { throw "Skyrim Forge installation failed with exit code $forgeCode." }
  Write-UabsOk ("Skyrim Forge $forgeSourceVersion ready")
  $installed['skyrim-forge'] = @{ status='installed'; version=$forgeSourceVersion; root=$env:SKYRIM_FORGE_ROOT }

  # Earlier bundles owned these machine-wide entries. Keep the tools and
  # skills installed, but migrate their schemas out of unrelated sessions.
  $cleaned = @(Remove-UabsGlobalMcpRegistration -Ids @('skyrim-forge','housecarl','codebase-memory-mcp') -FromProviders $Providers)
  $installed['game-mcp-global-migration'] = @{ status='profile-only'; removed_from=$cleaned }
}

# Discover separately installed game Forges without baking this maintainer's
# drive letter into a shipped provider config. Existing valid choices win.
function Set-UabsDiscoveredGameForgeRoot {
  param([string]$Variable, [string]$Marker, [string[]]$RelativeCandidates)
  $root = [Environment]::GetEnvironmentVariable($Variable, 'User')
  if (-not $root) { $root = [Environment]::GetEnvironmentVariable($Variable, 'Process') }
  if ($root -and (Test-Path -LiteralPath (Join-Path $root $Marker) -PathType Leaf)) {
    Set-Item -Path ("Env:" + $Variable) -Value $root
    return $root
  }
  $bases = @($env:LOCALAPPDATA)
  foreach ($letter in @('C','D','E','F','G','H','S','T','Z')) {
    $drive = "${letter}:\"
    if (Test-Path -LiteralPath $drive) { $bases += $drive }
  }
  foreach ($base in @($bases | Where-Object { $_ } | Select-Object -Unique)) {
    foreach ($relative in $RelativeCandidates) {
      $candidate = Join-Path $base $relative
      if (-not (Test-Path -LiteralPath (Join-Path $candidate $Marker) -PathType Leaf)) { continue }
      Set-UabsUserEnv $Variable $candidate
      Set-Item -Path ("Env:" + $Variable) -Value $candidate
      Write-UabsOk ("{0} discovered: {1}" -f $Variable, $candidate)
      return $candidate
    }
  }
  return $null
}

$robloxForge = Set-UabsDiscoveredGameForgeRoot -Variable 'ROBLOX_FORGE_ROOT' -Marker 'mcp_server\server.py' -RelativeCandidates @('RobloxForge','Apps\Roblox Tools\RobloxForge')
$saintsForge = Set-UabsDiscoveredGameForgeRoot -Variable 'SAINTSROW_FORGE_ROOT' -Marker 'mcp_server\server.py' -RelativeCandidates @('SaintsRowForge','Apps\Saints Row Tools\SaintsRowForge')
$installed['roblox-forge-discovery'] = @{ status=$(if($robloxForge){'found'}else{'not-installed'}); root=$robloxForge }
$installed['saints-row-forge-discovery'] = @{ status=$(if($saintsForge){'found'}else{'not-installed'}); root=$saintsForge }

if (-not $SkipMcpWire -and -not $SkillsOnly) {
  $mcpProfile = Join-Path $PackRoot 'TOOLS\Set-McpProfile.ps1'
  if (Test-Path -LiteralPath $mcpProfile) {
    Write-UabsStep 'Project tools'
    $providerList = $Providers -join ','
    $profileSteps = @(
      @{ Title = 'Set-McpProfile -Repair'; Args = @('-Repair', '-Providers', $providerList, '-PackRoot', $PackRoot) },
      # Tool installers register their MCP server machine-wide, which loads its tool
      # list in every chat. Park those entries; the toolbox starts them on demand.
      @{ Title = 'Set-McpProfile -Park'; Args = @('-Park', '-Providers', $providerList, '-PackRoot', $PackRoot) }
    )
    if ($WorkspaceRoot) {
      $profileSteps += @{ Title = 'Set-McpProfile -Auto'; Args = @('-Auto', '-Path', $WorkspaceRoot, '-Providers', $providerList, '-PackRoot', $PackRoot) }
    }
    $profileFailed = $false
    foreach ($ps in $profileSteps) {
      if ((Invoke-UabsChildScript -Title $ps.Title -File $mcpProfile -ArgList $ps.Args) -ne 0) {
        $profileFailed = $true
        Write-UabsWarn ($ps.Title + ' did not finish (its output is above)')
      }
    }
    if (-not $profileFailed) {
      Write-UabsOk 'Task tools stay out of every chat; the toolbox starts the one a task needs'
    }
  }
}

# ---------- Discover + state ----------
Write-UabsStep "Post-install discovery"
$disc = Join-Path $PackRoot 'TOOLS\discover_tools.ps1'
if (Test-Path $disc) {
  # The table goes to the details log; TOOLBELT.md is the readable inventory.
  if ((Invoke-UabsChildScript -Title 'discover_tools' -File $disc) -eq 0) { Write-UabsOk 'Installed tools located' }
}

$stateDir = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
# The toolbox reads the bundle's server catalog from here, so it keeps working
# when this pack folder moves or an update replaces it.
try {
  Copy-Item -LiteralPath (Join-Path $PackRoot 'BUNDLED-TOOLS\PROFILES.json') -Destination (Join-Path $stateDir 'toolbox-profiles.json') -Force
} catch { Write-UabsWarn ('Toolbox catalog copy failed: ' + $_.Exception.Message) }

# A partial run must update what it touched without forgetting everything else.
# native_plugins is always provider-scoped; components are carried forward only
# for SkillsOnly or an explicitly narrowed -Components run. A normal full tool
# pass remains authoritative and can retire old component records.
$statePath = Join-Path $stateDir 'install-state.json'
$priorState = $null
if (Test-Path -LiteralPath $statePath -PathType Leaf) {
  try {
    $priorState = [IO.File]::ReadAllText($statePath) | ConvertFrom-Json
    $priorPlugins = $priorState.native_plugins
    if ($priorPlugins) {
      foreach ($p in $priorPlugins.PSObject.Properties) {
        if (-not $nativePlugins.Contains($p.Name)) { $nativePlugins[$p.Name] = $p.Value }
      }
    }
    $partialComponentRun = $SkillsOnly -or $PSBoundParameters.ContainsKey('Components')
    if ($partialComponentRun -and $priorState.components) {
      foreach ($p in $priorState.components.PSObject.Properties) {
        if (-not $installed.Contains($p.Name)) { $installed[$p.Name] = $p.Value }
      }
    }
  } catch { Write-UabsWarn 'Could not read the previous install state; untouched partial-install records were not carried forward.' }
}
if (-not $SkillsOnly) {
  $ledgerUpdates = @()
  foreach ($id in @($installed.Keys)) {
    $row = $installed[$id]
    $ver = $null
    if ($row.version) { $ver = [string]$row.version }
    elseif ($row.spec) { $ver = [string]$row.spec }
    if ($ver) { $ledgerUpdates += @{ id = [string]$id; installed_version = $ver } }
  }
  if ($ledgerUpdates.Count) {
    try { Update-UabsComponentLedger -Updates $ledgerUpdates }
    catch { Write-UabsWarn ('Component ledger: ' + $_.Exception.Message) }
  }
}
$knownProviders = @($Providers)
if ($priorState -and $priorState.providers) { $knownProviders += @($priorState.providers) }
$stateProviders = @($script:UabsAllProviders | Where-Object { $knownProviders -contains $_ })

  $state = @{
version = '8.17.0'
  status = 'verifying'
  installed_utc = [DateTime]::UtcNow.ToString('o')
  mode = $Mode
  providers = $stateProviders
  components = $installed
  native_plugins = $nativePlugins
  pack_root = $PackRoot
}
$state | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $stateDir 'install-state.json') -Encoding UTF8
$log | Set-Content (Join-Path $stateDir 'install-log.txt') -Encoding UTF8

# Completeness + assumption gates, plus narrow RTK output routing. Every
# provider's prose already says 'be thorough' and 'do not assume'; the first
# two can actually refuse, while RTK only modifies commands on its allowlist.
if (-not $ToolsOnly) {
  Write-UabsStep 'Connecting everything to your AI apps'
  $gateInstaller = Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1'
  $providerList = $Providers -join ','
  if (Test-Path -LiteralPath $gateInstaller) {
    if ((Invoke-UabsChildScript -Title 'Completeness gates' -File $gateInstaller -ArgList @('-Providers', $providerList)) -eq 0) {
      Write-UabsOk 'Completeness + assumption gates and safe RTK routing installed'
    } else { Write-UabsWarn 'Gates: the gate installer reported an error (Tool output log)' }
  } else {
    Write-UabsWarn 'TOOLS\Install-Completeness-Gate.ps1 missing from pack'
  }

  $mcpReason = Join-Path $PackRoot 'TOOLS\Add-Reasoning-MCPs.ps1'
  if (-not $SkillsOnly -and -not $SkipMcpWire -and (Test-Path -LiteralPath $mcpReason)) {
    if ((Invoke-UabsChildScript -Title 'Always-on MCP servers' -File $mcpReason -ArgList @('-Providers', $providerList, '-Refresh', '-Quiet')) -eq 0) {
      Write-UabsOk 'Always-on MCP servers wired (context7, headroom, toolbox)'
    } else { Write-UabsWarn 'Always-on MCP servers: the registrar reported an error (Tool output log)' }
  }

  $hermesProfiles = Join-Path $PackRoot 'TOOLS\Migrate-HermesProfiles.ps1'
  if (-not $SkillsOnly -and -not $SkipMcpWire -and ($Providers -contains 'Hermes') -and (Test-Path -LiteralPath $hermesProfiles)) {
    try {
      # The migrator refuses to run while Hermes.exe is up, because the desktop
      # app persists its stale in-memory config on the next save and would undo
      # the migration (the v8.0.4 defect, in a new place). The install already
      # closes it -- but only inside the plugin block, which -SkipNativePlugins
      # and an absent Hermes CLI both skip. Without this the migration became a
      # warning on exactly the runs that skipped that block, and the profile
      # topology silently never landed.
      $hermesGw = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
      if (-not (Test-Path -LiteralPath $hermesGw -PathType Leaf)) {
        $hermesCmd = Get-Command hermes -ErrorAction SilentlyContinue
        if ($hermesCmd) { $hermesGw = $hermesCmd.Source } else { $hermesGw = $null }
      }
      if ($hermesGw) {
        $gwText = Get-UabsNativeOutput -Exe $hermesGw -CmdArgs @('gateway', 'status')
        $gwUp = $gwText -match '(?i)running' -and $gwText -notmatch '(?i)not running'
        if ($gwUp) {
          if (-not (Invoke-UabsNative $hermesGw @('gateway', 'stop'))) { throw 'Hermes gateway could not be stopped before profile migration' }
          $script:UabsHermesGatewayWasRunning = $true
          Write-UabsOk 'Hermes gateway stopped before profile migration'
        }
      }
      $hermesUp = Get-Process -Name 'Hermes' -ErrorAction SilentlyContinue
      if ($hermesUp) {
        if (-not $script:UabsHermesDesktopExe) {
          $script:UabsHermesDesktopExe = ($hermesUp | Select-Object -First 1).Path
        }
        Write-UabsWarn 'Hermes desktop is running - closing it so the profile migration cannot be overwritten (relaunched when the install finishes)'
        $hermesUp | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
      }
      $profileArgs = @('-Apply')
      if ($SkyrimToolset) { $profileArgs += @('-SkyrimToolset', $SkyrimToolset) }
      $migrateCode = Invoke-UabsChildScript -Title 'Hermes profile migration' -File $hermesProfiles -ArgList $profileArgs
      if ($migrateCode -ne 0) { throw "Hermes profile migrator failed with exit code $migrateCode" }
      $profileHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
      $evaluatedProfiles = @('default') + @(Get-ChildItem -LiteralPath (Join-Path $profileHome 'profiles') -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
      $installed['hermes-native-profiles'] = @{ status='evaluated'; profiles=$evaluatedProfiles; skyrim_toolset=$(if ($SkyrimToolset) { $SkyrimToolset } else { 'default (Lean)' }) }
      Write-UabsOk ('Hermes profiles ready ({0}): task tools start on demand through the toolbox' -f $evaluatedProfiles.Count)
    } catch {
      Write-UabsWarn ('Hermes native profiles: ' + $_.Exception.Message)
    }
  }

  $sillyGateway = Join-Path $PackRoot 'TOOLS\Install-SillyTavernGateway.ps1'
  if (($Providers -contains 'Hermes') -and (Test-Path -LiteralPath $sillyGateway)) {
    if ((Invoke-UabsChildScript -Title 'SillyTavern gateway' -File $sillyGateway -ArgList @('-PackRoot', $PackRoot)) -eq 0) {
      $stLine = @($script:UabsLastChildOutput | Where-Object { $_ -match 'SillyTavern gateway' }) | Select-Object -Last 1
      Write-UabsOk $(if ($stLine) { $stLine } else { 'SillyTavern gateway checked' })
    } else { Write-UabsWarn 'SillyTavern gateway: the profile writer reported an error (Tool output log)' }
  }

  # After every provider config has been written, repoint any MCP command that
  # points at a version-stamped folder which no longer exists. An upgraded tool
  # (Skyrim-Forge-5.1.0 -> 5.1.3) renames its folder, and a provider that was
  # missed just stops connecting silently.
  $mcpRepair = Join-Path $PackRoot 'TOOLS\Repair-McpPaths.ps1'
  if (Test-Path -LiteralPath $mcpRepair) {
    if ((Invoke-UabsChildScript -Title 'MCP path repair' -File $mcpRepair -ArgList @('-Apply', '-Quiet')) -eq 0) {
      Write-UabsOk 'MCP command paths checked'
    } else { Write-UabsWarn 'MCP path repair reported an error (Tool output log)' }
  }

  $toolbelt = Join-Path $PackRoot 'TOOLS\Build-Toolbelt.ps1'
  if (Test-Path -LiteralPath $toolbelt) {
    if ((Invoke-UabsChildScript -Title 'Toolbelt inventory' -File $toolbelt) -eq 0) {
      Write-UabsOk 'Toolbelt inventory written'
    } else { Write-UabsWarn 'Toolbelt inventory reported an error (Tool output log)' }
  }

  # Chat transcripts: copied to the user's history folder when one is configured
  # (UABS_HISTORY_DIR or HISTORY-DIR.txt in the profile folder); a no-op otherwise.
  $historyBackup = Join-Path $PackRoot 'TOOLS\Backup-AiHistory.ps1'
  if (Test-Path -LiteralPath $historyBackup -PathType Leaf) {
    if ((Invoke-UabsChildScript -Title 'AI chat history backup' -File $historyBackup -ArgList @('-Quiet')) -eq 0) {
      Write-UabsOk 'AI chat history backup checked'
    } else { Write-UabsWarn 'History backup reported an error (Tool output log)' }
  }

  if (-not $SkillsOnly -and -not $SkipMcpWire -and -not $SkipMcpHandshake) {
    $probe = Join-Path $PackRoot 'TOOLS\Test-McpHandshake.ps1'
    if (-not (Test-Path -LiteralPath $probe -PathType Leaf)) { throw 'MCP handshake probe missing.' }
    $coreMcp = @()
    if (Get-Command npx -ErrorAction SilentlyContinue) { $coreMcp += 'context7' }
    # The registrar leaves the GitHub server out where gh is signed in; expecting it here
    # would fail the install on exactly the machines that chose the cheaper setup.
    if ((Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\github-mcp-server\github-mcp-server.exe') -PathType Leaf) -and -not (Test-UabsGithubMcpParked)) { $coreMcp += 'github' }
    $hrCheck = [Environment]::GetEnvironmentVariable('HEADROOM_CMD','User')
    if (-not $hrCheck) { try { $hrCheck = (Get-Command headroom -ErrorAction SilentlyContinue).Source } catch { } }
    if ($hrCheck -and (Test-Path -LiteralPath $hrCheck -PathType Leaf)) { $coreMcp += 'headroom' }
    # Same resolution as the registrar (Add-Reasoning-MCPs) and the Hermes migrator.
    $tbCheck = [Environment]::GetEnvironmentVariable('UABS_TOOLBOX_CMD','User')
    if (-not $tbCheck) { try { $tbCheck = (Get-Command uabs-toolbox -ErrorAction SilentlyContinue).Source } catch { } }
    if ($tbCheck -and (Test-Path -LiteralPath $tbCheck -PathType Leaf)) { $coreMcp += 'toolbox' }
    foreach ($prov in $Providers) {
      if ($prov -eq 'Grok' -and $SkipGrokMcp) { continue }
      foreach ($serverName in $coreMcp) {
        $handshakeOk = $false
        foreach ($attempt in 1..2) {
          # A first failure is retried silently; only the final one shows its output.
          $hsCode = Invoke-UabsChildScript -Title ("MCP handshake {0}/{1} attempt {2}" -f $prov, $serverName, $attempt) -File $probe -ArgList @('-Provider', $prov, '-Name', $serverName, '-TimeoutSeconds', '90', '-RequireMatch') -NoTail:($attempt -eq 1)
          if ($hsCode -eq 0) { $handshakeOk = $true; break }
        }
        if (-not $handshakeOk) { throw "MCP handshake failed: $prov/$serverName after 2 attempts" }
      }
      if ($coreMcp.Count) { Write-UabsOk ('{0}: always-on tools answer ({1})' -f $prov, ($coreMcp -join ', ')) }
    }
  }
}

# Final fail-closed proof. Avoid -Switch:$false because powershell.exe -File on
# Windows PowerShell 5.1 cannot bind explicit Boolean values to [switch].
$doctorScript = Join-Path $PackRoot 'TOOLS\Test-Installed-State.ps1'
if (-not (Test-Path -LiteralPath $doctorScript -PathType Leaf)) { throw 'Final installed-state doctor missing.' }
$doctorArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$doctorScript,'-PackRoot',$PackRoot,'-Providers',($Providers -join ','))
if ($ToolsOnly) { $doctorArgs += @('-SkipSkills','-SkipForge') }
elseif ($SkillsOnly) { $doctorArgs += '-SkipForge' }
# Capture the child doctor's streams, then replay them in this process. Windows
# Start-Transcript does not reliably capture output written directly by a child
# powershell.exe process, which previously left INSTALL-LAST.log with only the
# generic exit code and hid the actual failing doctor check.
Write-UabsStep 'Final check of everything installed'
$prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
$doctorOutput = @(& (Get-Command powershell.exe -ErrorAction Stop).Source @doctorArgs 2>&1)
$ErrorActionPreference=$prevEap
$doctorExitCode = $LASTEXITCODE
# Full report to the details log; the console gets only problems and the verdict.
Add-UabsDetails -Title 'Installed-state doctor' -Lines @($doctorOutput | ForEach-Object { [string]$_ })
foreach ($doctorLine in $doctorOutput) {
  $text = [string]$doctorLine
  if ($text -match '^\s*(XX|!!)\s') { Write-Host $text -ForegroundColor $(if ($text -match '^\s*XX') { 'Red' } else { 'Yellow' }) }
  elseif ($text -match 'Installed-state doctor (PASS|FAIL)') { Write-Host $text -ForegroundColor $(if ($doctorExitCode -eq 0) { 'Green' } else { 'Red' }) }
}
if ($doctorExitCode -ne 0) {
  $doctorTail = (@($doctorOutput | Select-Object -Last 12 | ForEach-Object { [string]$_ }) -join ' | ')
  throw "Final installed-state doctor failed with exit code $doctorExitCode. Doctor tail: $doctorTail"
}

# Leftovers, last: only a run that got this far has a current tree to converge
# on, and a failed install must keep every log and backup for diagnosis.
if (-not $SkipCleanup -and -not $ToolsOnly) {
  $cleanTool = Join-Path $PackRoot 'TOOLS\Clean-StaleState.ps1'
  if (Test-Path -LiteralPath $cleanTool -PathType Leaf) {
    try {
      $cleanArgs = @('-Apply', '-PackRoot', $PackRoot)
      if ($SkillsOnly) { $cleanArgs += '-SkipSkills' }
      $cleanCode = Invoke-UabsChildScript -Title 'Leftover cleanup' -File $cleanTool -ArgList $cleanArgs
      if ($cleanCode -ne 0) { throw "cleanup exited with code $cleanCode" }
      Write-UabsOk 'Old bundle leftovers cleaned (newest backups kept)'
      $installed['stale-state-cleanup'] = @{ status = 'applied' }
    } catch {
      # Never fail an otherwise-good install over housekeeping.
      Write-UabsWarn ('Leftover cleanup: ' + $_.Exception.Message)
      $installed['stale-state-cleanup'] = @{ status = 'failed'; error = $_.Exception.Message }
    }
  }
}

$state.status = 'complete'
$state.completed_utc = [DateTime]::UtcNow.ToString('o')
$state | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $stateDir 'install-state.json') -Encoding UTF8

# Relaunch Hermes only after every config write is done. The gateway rewrites
# config.yaml from the copy it loaded at start, so it cannot be up during migration.
if ($script:UabsHermesGatewayWasRunning) {
  $hermesGw = Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'
  if (-not (Test-Path -LiteralPath $hermesGw -PathType Leaf)) {
    $hermesCmd = Get-Command hermes -ErrorAction SilentlyContinue
    if ($hermesCmd) { $hermesGw = $hermesCmd.Source } else { $hermesGw = $null }
  }
  if ($hermesGw -and (Invoke-UabsNative $hermesGw @('gateway', 'start'))) {
    Write-UabsOk 'Hermes gateway restarted after config writes'
  } else {
    Write-UabsWarn 'Hermes gateway was running before install but could not be restarted'
  }
}
if ($script:UabsHermesDesktopExe) {
  if (Test-Path -LiteralPath $script:UabsHermesDesktopExe -PathType Leaf) {
    Start-Process -FilePath $script:UabsHermesDesktopExe
    Write-UabsOk 'Hermes desktop relaunched with the final config'
  } else {
    Write-UabsWarn ('Hermes desktop was closed for the install but its exe is gone (' + $script:UabsHermesDesktopExe + ') - relaunch it manually')
  }
  $script:UabsHermesDesktopExe = $null
}

# One click, nothing to type: the closing text names no command. The toolbox
# count comes from the installed toolbox itself, so it reflects this machine.
$toolboxReady = $null
$tbExe = [Environment]::GetEnvironmentVariable('UABS_TOOLBOX_CMD', 'User')
if (-not $tbExe) { try { $tbExe = (Get-Command uabs-toolbox -ErrorAction SilentlyContinue).Source } catch { } }
if ($tbExe -and (Test-Path -LiteralPath $tbExe -PathType Leaf)) {
  $prevEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $tbLines = @(& $tbExe --list 2>&1 | ForEach-Object { [string]$_ }) } catch { $tbLines = @() }
  finally { $ErrorActionPreference = $prevEap }
  $toolboxReady = @($tbLines | Where-Object { ($_ -split "`t")[1] -match '^(ready|needs a project folder)' }).Count
}
Write-Host ''
Write-Host '=====================================================' -ForegroundColor Green
Write-Host (' INSTALL COMPLETE  (v' + $state.version + ')') -ForegroundColor Green
Write-Host '=====================================================' -ForegroundColor Green
Write-Host ''
Write-Host '  1. Close and reopen your AI apps once (Claude, Codex, Hermes, Grok...).' -ForegroundColor Yellow
Write-Host '  2. Then just tell your AI what you want to build or mod. It switches on'
Write-Host '     the project tools a task needs by itself - nothing to type or set up.'
if ($null -ne $toolboxReady) {
  Write-Host ('     Project tools your AI can start on this PC: {0}' -f $toolboxReady) -ForegroundColor DarkGray
} elseif (-not $SkillsOnly -and -not $ToolsOnly) {
  Write-Host '     The on-demand toolbox is missing, so project tools stay off. Run START-HERE.bat again.' -ForegroundColor Yellow
}
Write-Host ''
Write-Host '  To update later, run START-HERE.bat again.' -ForegroundColor DarkGray
Write-Host ('  Log: ' + $installLogPath) -ForegroundColor DarkGray
Write-Host ('  Tool output: ' + $script:UabsDetailsLog) -ForegroundColor DarkGray
Write-Host ''

# Close the durable transcript only after the success banner/next steps have
# been written, then update the stable LAST log and clear any stale failure note.
if ($script:UabsTranscriptStarted) {
  try { Stop-Transcript | Out-Null } catch {}
  $script:UabsTranscriptStarted = $false
}
try { Copy-Item -LiteralPath $installLogPath -Destination $installLastPath -Force } catch {}
try { Remove-Item -LiteralPath $installFailedPath -Force -ErrorAction SilentlyContinue } catch {}
