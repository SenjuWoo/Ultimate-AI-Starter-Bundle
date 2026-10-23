<#
.SYNOPSIS
  Prove Get-UabsInstalledProviders reports what is installed, not what is wanted.

.DESCRIPTION
  Through v8.0.4 INSTALL-AIO.ps1 defaulted -Providers to all five and the
  provider bootstrap then downloaded whichever were missing. Someone with only
  Claude finished a "one-click install" carrying four vendor CLIs they never
  asked for, and a provider they had deliberately uninstalled came back on the
  next run.

  The detector is the thing that decides that, so it is tested against a real
  filesystem rather than by reading the installer's source. Each case builds a
  throwaway USERPROFILE/LOCALAPPDATA, plants (or omits) the exact executables
  installed desktop apps and CLI launchers, constrains PATH and Store discovery
  so the build machine cannot leak into the answer, and compares the result.
#>
[CmdletBinding()]
param([string]$PackRoot)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$fail = 0
function Good($m) { Write-Host "  OK   $m" -ForegroundColor Green }
function Bad($m) { Write-Host "  FAIL $m" -ForegroundColor Red; $script:fail++ }

. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')

# Execute only the installer's pure provider-selection statements. Running the
# full installer here would mutate the operator's settings and install tools.
$aio = [IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-AIO.ps1'))
$parseTokens = $null; $parseErrors = $null
$aioAst = [System.Management.Automation.Language.Parser]::ParseInput($aio, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'INSTALL-AIO.ps1 does not parse.' }
$selectionStart = $aioAst.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$script:UabsAllProviders'
} | Select-Object -First 1
$selectionEnd = $aioAst.EndBlock.Statements | Where-Object {
    $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and $_.Left.Extent.Text -eq '$script:UabsSkippedProviders'
} | Select-Object -First 1
if (-not $selectionStart -or -not $selectionEnd) { throw 'Cannot isolate installer provider selection.' }
$selectionText = $aio.Substring($selectionStart.Extent.StartOffset, $selectionEnd.Extent.EndOffset - $selectionStart.Extent.StartOffset)
$script:providerSelection = [scriptblock]::Create($selectionText + [Environment]::NewLine + '[pscustomobject]@{Providers=@($Providers);Skipped=@($script:UabsSkippedProviders);Source=$script:UabsProviderSource}')

function Invoke-ProviderSelection {
    param([string[]]$Providers=@(), [string[]]$Detected=@(), [switch]$AllProviders, [switch]$ToolsOnly)
    # The detector itself is tested below against real files; this boundary
    # supplies its result to the real selection branch without touching PATH.
    function Get-UabsInstalledProviders { param([string[]]$Candidates) @($Detected) }
    & $script:providerSelection
}

$sandboxRoot = Join-Path ([IO.Path]::GetTempPath()) ('uabs-provider-detect-' + [guid]::NewGuid().ToString('N'))

# Executable layouts Resolve-UabsProviderExe knows, keyed by provider. Relative
# to USERPROFILE unless the path starts with LOCALAPPDATA:.
$layout = @{
    Claude = '.local\bin\claude.exe'
    Codex  = '.local\bin\codex.exe'
    Grok   = '.grok\bin\grok.exe'
    Kimi   = '.kimi-code\bin\kimi.exe'
    Hermes = 'LOCALAPPDATA:hermes\hermes-agent\venv\Scripts\hermes.exe'
    Antigravity = 'LOCALAPPDATA:Programs\Antigravity\Antigravity.exe'
    ClaudeDesktop = 'LOCALAPPDATA:AnthropicClaude\app-1.2.3\Claude.exe'
    CodexDesktop = 'LOCALAPPDATA:OpenAI\Codex\Codex.exe'
    CodexVersioned = 'LOCALAPPDATA:OpenAI\Codex\bin\37f54d68e5533a51\codex.exe'
    CodexNative = 'LOCALAPPDATA:Programs\OpenAI\Codex\bin\codex.exe'
    CodexNpm = 'APPDATA:npm\codex.cmd'
    KimiUv = '.local\bin\kimi.exe'
    HermesNative = 'LOCALAPPDATA:hermes\bin\hermes.exe'
    CodexRedirected = 'AppData\Local\OpenAI\Codex\bin\37f54d68e5533a51\codex.exe'
    ClaudeRedirected = 'AppData\Local\AnthropicClaude\app-1.2.3\Claude.exe'
}

# Current-user Store registrations are an external OS boundary; never inspect
# the operator's real registrations while the filesystem fixture is selected.
$script:testAppxPackages = @()
function Get-UabsProviderAppxPackages { return @($script:testAppxPackages) }

function Invoke-DetectionCase {
    param(
        [Parameter(Mandatory)][string]$Name,
        [string[]]$Present = @(),
        [string[]]$StaleHomes = @(),
        [string[]]$CliAbsent = @(),
        [string[]]$StoreApps = @(),
        [switch]$StaleStore,
        [switch]$VerifyCodexCli,
        # Not Mandatory: PowerShell 5.1 refuses to bind an empty array to a
        # mandatory parameter, and "detects nothing" is the most important case.
        [string[]]$Expected = @()
    )
    $case = Join-Path $sandboxRoot ($Name -replace '[^A-Za-z0-9]', '-')
    $profileDir = Join-Path $case 'profile'
    $localDir = Join-Path $case 'local'
    $roamingDir = Join-Path $case 'roaming'
    New-Item -ItemType Directory -Force -Path $profileDir, $localDir, $roamingDir | Out-Null

    foreach ($provider in $Present) {
        $rel = $layout[$provider]
        $full = if ($rel.StartsWith('LOCALAPPDATA:')) {
            Join-Path $localDir $rel.Substring('LOCALAPPDATA:'.Length)
        } elseif ($rel.StartsWith('APPDATA:')) {
            Join-Path $roamingDir $rel.Substring('APPDATA:'.Length)
        } else { Join-Path $profileDir $rel }
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $full) | Out-Null
        # Presence checks do not execute binaries; the npm fallback also gets
        # one runnable version fixture to exercise Get-UabsCodexCli.
        $content = if ($provider -eq 'CodexNpm') { "@echo off`r`necho codex-cli 1.2.3`r`nexit /b 0`r`n" } else { 'stub' }
        [IO.File]::WriteAllText($full, $content)
    }
    # A config directory left behind by an uninstall must NOT read as installed.
    foreach ($provider in $StaleHomes) {
        # $homeDir, never $home: $HOME is read-only in Windows PowerShell 5.1
        # and assigning to it is a terminating error, not a shadowed local.
        $homeDir = switch ($provider) {
            'Claude' { '.claude' } 'Codex' { '.codex' } 'Grok' { '.grok' }
            'Kimi' { '.kimi-code' } 'Hermes' { '.hermes' }
            'Antigravity' { '.gemini\antigravity' }
        }
        New-Item -ItemType Directory -Force -Path (Join-Path $profileDir $homeDir) | Out-Null
    }

    $savedProfile = $env:USERPROFILE
    $savedLocal = $env:LOCALAPPDATA
    $savedPath = $env:PATH
    $savedRoaming = $env:APPDATA
    try {
        $env:USERPROFILE = $profileDir
        $env:LOCALAPPDATA = $localDir
        $env:APPDATA = $roamingDir
        # Empty PATH: otherwise the build machine's own claude/codex/grok answer
        # for the sandbox and every case reports five.
        $env:PATH = Join-Path $case 'no-such-bin'
        $script:testAppxPackages = @()
        foreach ($app in $StoreApps) {
            $installDir = Join-Path $case ('packages\' + $app)
            New-Item -ItemType Directory -Force -Path $installDir | Out-Null
            if (-not $StaleStore) { [IO.File]::WriteAllText((Join-Path $installDir 'AppxManifest.xml'), '<Package/>') }
            $script:testAppxPackages += [pscustomobject]@{ Name=$app; InstallLocation=$installDir; IsFramework=$false }
        }
        $before = @(Get-ChildItem -LiteralPath $case -Recurse -Force | ForEach-Object FullName) -join '|'
        $got = @(Get-UabsInstalledProviders -PathDirectories @())
        if ($got.Count) {
            $automatic = Invoke-ProviderSelection -Detected $got
            if (($automatic.Providers -join ',') -ne ($Expected -join ',')) { Bad "$Name -> automatic selection added or dropped a provider" }
            $explicit = Invoke-ProviderSelection -Providers $Expected -Detected @('Claude','Codex','Grok','Kimi','Hermes','Antigravity')
            if (($explicit.Providers -join ',') -ne ($Expected -join ',')) { Bad "$Name -> explicit selection added or dropped a provider" }
        }
        if ($VerifyCodexCli) {
            # Keep command lookup inside the same fixture even if the test
            # machine has a provider in its persisted user/machine PATH.
            function Get-UabsProviderPathDirectories { @() }
            $cli = Get-UabsCodexCli
            if (-not $cli -or $cli.Source -ne (Join-Path $roamingDir 'npm\codex.cmd')) {
                Bad "$Name -> verified CLI resolver missed the native/npm fallback"
            }
        }
        foreach ($provider in $CliAbsent) {
            if (Resolve-UabsProviderExe -Provider $provider -PathDirectories @()) { Bad "$Name -> desktop app was treated as a usable $provider CLI" }
        }
        $after = @(Get-ChildItem -LiteralPath $case -Recurse -Force | ForEach-Object FullName) -join '|'
        if ($before -ne $after) { Bad "$Name -> detection created or changed profile paths" }
    } finally {
        $env:USERPROFILE = $savedProfile
        $env:LOCALAPPDATA = $savedLocal
        $env:PATH = $savedPath
        $env:APPDATA = $savedRoaming
        $script:testAppxPackages = @()
    }

    $gotText = if ($got.Count) { ($got -join ',') } else { '(none)' }
    $wantText = if ($Expected.Count) { ($Expected -join ',') } else { '(none)' }
    if ($gotText -eq $wantText) { Good "$Name -> $gotText" }
    else { Bad "$Name -> got $gotText, expected $wantText" }
}

Write-Host '=== provider detection ===' -ForegroundColor Cyan
try {
    Invoke-DetectionCase -Name 'empty profile detects nothing' -Expected @()

    Invoke-DetectionCase -Name 'only Claude installed' -Present @('Claude') -Expected @('Claude')

    Invoke-DetectionCase -Name 'fresh Windows desktop-only Claude and Codex' `
        -Present @('ClaudeDesktop', 'CodexDesktop') -CliAbsent @('Claude','Codex') -Expected @('Claude', 'Codex')

    Invoke-DetectionCase -Name 'Codex app native versioned CLI is off inherited PATH' `
        -Present @('CodexVersioned') -Expected @('Codex')

    Invoke-DetectionCase -Name 'Codex official native location' -Present @('CodexNative') -Expected @('Codex')
    Invoke-DetectionCase -Name 'Codex npm shim before process PATH refresh' -Present @('CodexNpm') -VerifyCodexCli -Expected @('Codex')
    Invoke-DetectionCase -Name 'Kimi uv native launcher' -Present @('KimiUv') -Expected @('Kimi')
    Invoke-DetectionCase -Name 'Hermes modern native launcher' -Present @('HermesNative') -Expected @('Hermes')
    Invoke-DetectionCase -Name 'Microsoft Store Claude and Codex without CLIs' `
        -StoreApps @('AnthropicPBC.Claude','OpenAI.Codex') -CliAbsent @('Claude','Codex') -Expected @('Claude','Codex')
    Invoke-DetectionCase -Name 'unrelated Store package is not an AI provider' -StoreApps @('Unrelated.ClaudeNotes') -Expected @()
    Invoke-DetectionCase -Name 'stale Store registration has no installed payload' -StoreApps @('OpenAI.Codex','Claude') -StaleStore -Expected @()
    Invoke-DetectionCase -Name 'sandbox redirected LOCALAPPDATA still finds real profile apps' `
        -Present @('ClaudeRedirected','CodexRedirected') -Expected @('Claude','Codex')

    Write-Host '=== inherited and persisted PATH ===' -ForegroundColor Cyan
    $pathRoot = Join-Path $sandboxRoot 'persisted-path'
    $processBin = Join-Path $pathRoot 'inherited'
    $machineBin = Join-Path $pathRoot 'machine'
    $userBin = Join-Path $pathRoot 'new user bin'
    New-Item -ItemType Directory -Force -Path $processBin, $machineBin, $userBin | Out-Null
    [IO.File]::WriteAllText((Join-Path $machineBin 'claude.cmd'), '@echo fixture')
    [IO.File]::WriteAllText((Join-Path $userBin 'codex.cmd'), '@echo fixture')
    $inheritedPath = $env:PATH
    $lookup = @(Get-UabsProviderPathDirectories -ProcessPath $processBin -MachinePath $machineBin -UserPath ('"' + $userBin + '";' + $processBin))
    if (($lookup -join '|') -eq (@($processBin,$machineBin,$userBin) -join '|') -and $env:PATH -ceq $inheritedPath) {
        Good 'PATH lookup combines current, machine and newly installed user entries without replacing process PATH'
    } else { Bad 'PATH lookup omitted persisted entries, duplicated a directory or changed process PATH' }
    try {
        $env:PATH = $processBin
        $persistedDirectories = @(Get-UabsProviderPathDirectories -ProcessPath '')
        Refresh-ProcessPath
        $refreshedDirectories = @($env:PATH -split ';')
        if ($refreshedDirectories -contains $processBin -and
            @($persistedDirectories | Where-Object { $refreshedDirectories -notcontains $_ }).Count -eq 0) {
            Good 'Refresh-ProcessPath keeps inherited app CLI paths and adds persisted machine/user paths'
        } else { Bad 'Refresh-ProcessPath dropped inherited app CLI paths or persisted paths' }
    } finally { $env:PATH = $inheritedPath }
    foreach ($entry in @(@{provider='Claude';expected=(Join-Path $machineBin 'claude.cmd')}, @{provider='Codex';expected=(Join-Path $userBin 'codex.cmd')})) {
        $resolved = Resolve-UabsProviderExe -Provider $entry.provider -PathDirectories $lookup
        if ($resolved -eq $entry.expected) { Good ($entry.provider + ' resolves through persisted PATH before app restart') }
        else { Bad ($entry.provider + ' did not resolve through persisted PATH') }
    }
    $appxBin = Join-Path $pathRoot 'Microsoft\WindowsApps'
    New-Item -ItemType Directory -Force -Path $appxBin | Out-Null
    [IO.File]::WriteAllText((Join-Path $appxBin 'codex.exe'), 'desktop alias')
    $savedProfile = $env:USERPROFILE; $savedLocal = $env:LOCALAPPDATA; $savedRoaming = $env:APPDATA
    try {
        $env:USERPROFILE = $pathRoot; $env:LOCALAPPDATA = $pathRoot; $env:APPDATA = $pathRoot
        if (Resolve-UabsProviderExe -Provider Codex -PathDirectories @($appxBin)) { Bad 'Store desktop alias was accepted as a Codex CLI' }
        else { Good 'Store desktop alias is excluded from runnable Codex CLI lookup' }
    } finally { $env:USERPROFILE=$savedProfile; $env:LOCALAPPDATA=$savedLocal; $env:APPDATA=$savedRoaming }

    foreach ($mask in 1..63) {
        $combination = @()
        $canonical = @('Claude','Codex','Grok','Kimi','Hermes','Antigravity')
        for ($index = 0; $index -lt $canonical.Count; $index++) {
            if ($mask -band (1 -shl $index)) { $combination += $canonical[$index] }
        }
        Invoke-DetectionCase -Name ('all-six combination ' + $mask) -Present $combination -Expected $combination
    }

    Invoke-DetectionCase -Name 'Claude plus Hermes under LOCALAPPDATA' `
        -Present @('Claude', 'Hermes') -Expected @('Claude', 'Hermes')

    # The case the maintainer hit: Kimi is gone but ~/.kimi-code survives with
    # AGENTS.md backups in it. Treating that folder as an install would keep
    # re-wiring a provider that was deliberately removed.
    Invoke-DetectionCase -Name 'uninstalled provider leaves a config folder' `
        -Present @('Claude') -StaleHomes @('Kimi','Codex','Grok','Hermes','Antigravity') -Expected @('Claude')

    Invoke-DetectionCase -Name 'all five installed' `
        -Present @('Claude', 'Codex', 'Grok', 'Kimi', 'Hermes') `
        -Expected @('Claude', 'Codex', 'Grok', 'Kimi', 'Hermes')

    # Order must follow the canonical list, not the filesystem, so the banner
    # and install-state.json read the same on every machine.
    Invoke-DetectionCase -Name 'result order is canonical, not filesystem order' `
        -Present @('Kimi', 'Claude', 'Grok') -Expected @('Claude', 'Grok', 'Kimi')

    Write-Host '=== installer honours the detector ===' -ForegroundColor Cyan
    # Execute the installer's own normalization, including the single string
    # that powershell -File passes for a comma-separated component list.
    $componentSplit = $aioAst.Find({ param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
        $node.Left.Extent.Text -eq '$Components' -and $node.Right.Extent.Text -match '-split'
    }, $true)
    if (-not $componentSplit) {
        Bad 'installer does not normalize comma-separated component choices'
    } else {
        $normalize = [scriptblock]::Create('param([string[]]$Components)' + [Environment]::NewLine +
            $componentSplit.Extent.Text + [Environment]::NewLine + '$Components')
        foreach ($inputList in @(
            @{value=@(' github-mcp-server,firecrawl-mcp,super-mcp-router '); expected='github-mcp-server,firecrawl-mcp,super-mcp-router'},
            @{value=@('rtk', ' headroom,rtk ', ''); expected='rtk,headroom'}
        )) {
            $normalized = @(& $normalize -Components $inputList.value)
            if (($normalized -join ',') -eq $inputList.expected) { Good 'component names split, trim and deduplicate correctly' }
            else { Bad ('wrong normalized components: ' + ($normalized -join ',')) }
        }
    }
    try { $unexpected = Invoke-ProviderSelection; Bad ('empty detection silently selected: ' + ($unexpected.Providers -join ',')) }
    catch {
        if ($_.Exception.Message -match 'No supported AI apps detected' -and $_.Exception.Message -match '-Providers' -and $_.Exception.Message -match '-AllProviders') {
            Good 'empty detection stops before installation with explicit provider guidance'
        } else { Bad ('empty detection failed unexpectedly: ' + $_.Exception.Message) }
    }
    $tools = Invoke-ProviderSelection -ToolsOnly
    if ($tools.Providers.Count -eq 0) { Good 'tools-only with no detected providers keeps provider selection empty' }
    else { Bad 'tools-only unexpectedly selected providers' }
    $all = Invoke-ProviderSelection -AllProviders
    if (($all.Providers -join ',') -eq 'Claude,Codex,Grok,Kimi,Hermes,Antigravity') { Good 'AllProviders explicitly selects all six' }
    else { Bad 'AllProviders did not select all six canonical provider names' }
    $normalized = Invoke-ProviderSelection -Providers @(' codex,CLAUDE ', 'Claude', 'antigravity')
    if (($normalized.Providers -join ',') -eq 'Claude,Codex,Antigravity') { Good 'explicit choices split, trim, canonicalize case and deduplicate' }
    else { Bad ('explicit provider normalization returned: ' + ($normalized.Providers -join ',')) }
    foreach ($invalid in @(
        @{Providers=@('Claude','Unknown');AllProviders=$false},
        @{Providers=@('Codex');AllProviders=$true}
    )) {
        try { $null = Invoke-ProviderSelection @invalid; Bad 'invalid provider selection was accepted' }
        catch { Good 'unknown names and conflicting explicit/all choices are rejected' }
    }
    # Run the actual updater against no-op fixture installers. No network,
    # credentials or real provider homes: check defaults and both forwarding paths.
    $updateRoot = Join-Path $sandboxRoot 'update'
    New-Item -ItemType Directory -Force -Path (Join-Path $updateRoot 'TOOLS') | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackRoot 'TOOLS\Update-From-GitHub.ps1') -Destination (Join-Path $updateRoot 'TOOLS\Update-From-GitHub.ps1')
    $commonStub = @'
function Get-UabsPackRoot { Split-Path -Parent $PSScriptRoot }
function Get-UabsCatalog { @{components=@()} }
function Write-UabsStep($m) {}
'@
    [IO.File]::WriteAllText((Join-Path $updateRoot 'TOOLS\UABS-Common.ps1'), $commonStub)
    $installerStub = @'
param([string[]]$Providers=@(), [string]$Mode)
$value = ($Providers -join ',')
if ($value -ne [string]$env:UABS_TEST_PROVIDERS) { throw "Wrong providers: $value" }
Write-Output 'FORWARDING_OK'
'@
    foreach ($name in @('INSTALL-REMOTE.ps1','INSTALL-AIO.ps1')) {
        [IO.File]::WriteAllText((Join-Path $updateRoot $name), $installerStub)
    }
    $savedLocal = $env:LOCALAPPDATA
    $savedExpected = $env:UABS_TEST_PROVIDERS
    try {
        $env:LOCALAPPDATA = $updateRoot
        $updater = Join-Path $updateRoot 'TOOLS\Update-From-GitHub.ps1'
        foreach ($wanted in @('', 'Claude,Hermes')) {
            $env:UABS_TEST_PROVIDERS = $wanted
            foreach ($componentMode in @($false, $true)) {
                $updateArgs = @{Providers=@($wanted)}
                if ($componentMode) { $updateArgs.ComponentsOnly=$true; $updateArgs.InstallAfter=$true; $updateArgs.Components=@() }
                $out = & $updater @updateArgs | Out-String
                if ($out -notmatch 'FORWARDING_OK') { throw 'Updater did not reach the selected installer' }
            }
        }
        # Also exercise the parameter's implicit default, not just explicit [].
        $env:UABS_TEST_PROVIDERS = ''
        if ((& $updater | Out-String) -notmatch 'FORWARDING_OK') { throw 'Updater default failed' }
        Good 'updater preserves auto-detection and comma-separated provider choices on both paths'
    } finally {
        $env:LOCALAPPDATA = $savedLocal
        $env:UABS_TEST_PROVIDERS = $savedExpected
    }
} finally {
    if (Test-Path -LiteralPath $sandboxRoot) {
        Remove-Item -LiteralPath $sandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host 'PROVIDER DETECTION GATE: PASS' -ForegroundColor Green
    exit 0
} else {
    Write-Host "PROVIDER DETECTION GATE: FAIL ($fail problem(s))" -ForegroundColor Red
    exit 1
}
