<# Run the real bootstrap with disposable profiles and real .cmd executables.
   Network, WinGet and registry PATH refresh are the external boundaries replaced
   here: no provider, runtime, authentication or user settings are installed. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-provider-bootstrap-' + [guid]::NewGuid().ToString('N'))
$savedEnvironment = @{}
$environmentNames = @('USERPROFILE','LOCALAPPDATA','APPDATA','PATH','UABS_PYTHON','UABS_TEST_NPM_LOG',
  'UABS_TEST_WINGET_LOG','UABS_TEST_NPM_TEMPLATE','UABS_TEST_CLI_TEMPLATE','UABS_TEST_BIN','UABS_TEST_INSTALL_NODE','UABS_TEST_INSTALL_GIT')
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$failures = @()
$commonSource = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\UABS-Common.ps1'))
$bootstrapSource = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\Ensure-Provider-CLIs.ps1'))
$doctorTokens = $null; $doctorErrors = $null
$doctorAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PackRoot 'TOOLS\Test-Installed-State.ps1'), [ref]$doctorTokens, [ref]$doctorErrors)
if ($doctorErrors.Count) { throw 'The installed-state doctor does not parse.' }
$doctorResolver = $doctorAst.Find({ param($node)
  $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Resolve-Exe'
}, $true)
if (-not $doctorResolver) { throw 'The installed-state doctor has no provider resolver.' }
$externalBoundaries = @'
function Refresh-ProcessPath {}
function Get-UabsProviderPathDirectories { @($env:PATH -split ';') }
function Get-AppxPackage { @() }
function Start-Sleep {}
function Invoke-WebRequest { param($Uri) throw "Unexpected installer download: $Uri" }
function Install-UabsWinget([string[]]$Ids) {
  [IO.File]::AppendAllText($env:UABS_TEST_WINGET_LOG, (($Ids -join ',') + [Environment]::NewLine))
  if (($Ids -join ',') -eq 'Git.Git') {
    if ($env:UABS_TEST_INSTALL_GIT -eq 'fail') { return $false }
    if ($env:UABS_TEST_INSTALL_GIT -eq '1') {
      [IO.File]::WriteAllText((Join-Path $env:UABS_TEST_BIN 'git.cmd'), "@echo off`r`necho git version 2.50.0`r`nexit /b 0`r`n")
      foreach ($shell in @('sh.exe','bash.exe')) { [IO.File]::WriteAllText((Join-Path $env:UABS_TEST_BIN $shell), 'presence fixture; never executed') }
      return $true
    }
  }
  if ($env:UABS_TEST_INSTALL_NODE -eq '1' -and ($Ids -join ',') -eq 'OpenJS.NodeJS.LTS') {
    Copy-Item -LiteralPath $env:UABS_TEST_NPM_TEMPLATE -Destination (Join-Path $env:UABS_TEST_BIN 'npm.cmd')
    return $true
  }
  throw ('Unexpected package installation: ' + ($Ids -join ','))
}
'@
$npmTemplate = @'
@echo off
if "%1"=="--version" (echo 10.0.0 & exit /b 0)
echo %*>>"%UABS_TEST_NPM_LOG%"
copy /y "%UABS_TEST_CLI_TEMPLATE%" "%APPDATA%\npm\codex.cmd" >nul
exit /b 0
'@

function Invoke-BootstrapCase {
  param([string]$Name, [scriptblock]$Body)
  $caseRoot = Join-Path $fixture ($Name -replace '[^a-zA-Z0-9]', '-')
  $tools = Join-Path $caseRoot 'TOOLS'
  $env:USERPROFILE = Join-Path $caseRoot 'profile'
  $env:LOCALAPPDATA = Join-Path $caseRoot 'local'
  $env:APPDATA = Join-Path $caseRoot 'roaming'
  $env:UABS_TEST_BIN = Join-Path $caseRoot 'bin'
  $env:PATH = $env:UABS_TEST_BIN
  $env:UABS_PYTHON = $null
  $env:UABS_TEST_INSTALL_NODE = $null
  $env:UABS_TEST_INSTALL_GIT = $null
  $env:UABS_TEST_NPM_LOG = Join-Path $caseRoot 'npm.log'
  $env:UABS_TEST_WINGET_LOG = Join-Path $caseRoot 'winget.log'
  $env:UABS_TEST_CLI_TEMPLATE = Join-Path $caseRoot 'codex-fixture.cmd'
  $env:UABS_TEST_NPM_TEMPLATE = Join-Path $caseRoot 'npm-fixture.cmd'
  New-Item -ItemType Directory -Force -Path $tools,$env:USERPROFILE,$env:LOCALAPPDATA,
    (Join-Path $env:APPDATA 'npm'),$env:UABS_TEST_BIN,(Join-Path $env:USERPROFILE '.codex') | Out-Null
  [IO.File]::WriteAllText((Join-Path $tools 'UABS-Common.ps1'), ($commonSource + [Environment]::NewLine + $externalBoundaries))
  $bootstrap = Join-Path $tools 'Ensure-Provider-CLIs.ps1'
  [IO.File]::WriteAllText($bootstrap, $bootstrapSource)
  [IO.File]::WriteAllText($env:UABS_TEST_CLI_TEMPLATE, "@echo off`r`necho codex-cli 9.9.9`r`nexit /b 0`r`n")
  [IO.File]::WriteAllText($env:UABS_TEST_NPM_TEMPLATE, ($npmTemplate -replace "`r?`n", "`r`n"))
  Copy-Item -LiteralPath $env:UABS_TEST_NPM_TEMPLATE -Destination (Join-Path $env:UABS_TEST_BIN 'npm.cmd')
  [IO.File]::WriteAllText((Join-Path $env:UABS_TEST_BIN 'git.cmd'), "@echo off`r`necho git version 2.50.0`r`nexit /b 0`r`n")
  # npm.ps1 is unsigned in many real Windows installs. It must never be chosen.
  [IO.File]::WriteAllText((Join-Path $env:UABS_TEST_BIN 'npm.ps1'), "throw 'The unsigned npm.ps1 shim was selected.'")
  $settings = Join-Path $env:USERPROFILE '.codex\config.toml'
  $settingsText = "# existing user configuration`r`nmodel = 'keep-me'`r`n"
  [IO.File]::WriteAllText($settings, $settingsText)
  try {
    & $Body $bootstrap $caseRoot
    Assert ([IO.File]::ReadAllText($settings) -ceq $settingsText) 'Existing Codex settings changed.'
    Write-Host ("  OK   " + $Name) -ForegroundColor Green
  } catch {
    $script:failures += ($Name + ': ' + $_.Exception.Message)
    Write-Host ("  FAIL " + $Name + ': ' + $_.Exception.Message) -ForegroundColor Red
  }
}

try {
  Invoke-BootstrapCase 'Codex uses npm.cmd and reuses installed Git without unrelated providers' {
    param($Bootstrap, $CaseRoot)
    # Existing Git lets the original bootstrap reach the broken download route.
    [IO.File]::WriteAllText((Join-Path $env:UABS_TEST_BIN 'git.cmd'), "@echo off`r`necho git version 2.50.0`r`nexit /b 0`r`n")
    & $Bootstrap -Providers ' Codex,Codex '
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_WINGET_LOG)) 'Codex-only bootstrap tried an unrelated package installation.'
    $calls = @([IO.File]::ReadAllLines($env:UABS_TEST_NPM_LOG))
    Assert ($calls.Count -eq 1 -and $calls[0] -eq 'install -g @openai/codex') 'Codex was not installed once with the official npm package.'
    $report = @([IO.File]::ReadAllText((Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\provider-bootstrap.json')) | ConvertFrom-Json)
    Assert ($report.Count -eq 1 -and $report[0].provider -eq 'Codex' -and $report[0].installed_now) 'Bootstrap report did not contain only the selected installed Codex CLI.'
    Assert ($report[0].executable -eq (Join-Path $env:APPDATA 'npm\codex.cmd')) 'The newly installed CLI was not found with a cold PATH.'
  }
  Invoke-BootstrapCase 'solo Codex provisions missing Git for plugin setup and the shell doctor' {
    param($Bootstrap, $CaseRoot)
    Remove-Item -LiteralPath (Join-Path $env:UABS_TEST_BIN 'git.cmd')
    $env:UABS_TEST_INSTALL_GIT = '1'
    & $Bootstrap -Providers Codex
    Assert (([IO.File]::ReadAllText($env:UABS_TEST_WINGET_LOG)).Trim() -eq 'Git.Git') 'Solo Codex did not provision its missing Git/Bash prerequisite.'
    . (Join-Path $CaseRoot 'TOOLS\UABS-Common.ps1')
    Assert (@(Repair-UabsHookShellPath -CheckOnly).Count -eq 0) 'Bootstrap left prerequisites that the final doctor would reject.'
  }
  Invoke-BootstrapCase 'missing Git install failure prevents a false provider success report' {
    param($Bootstrap, $CaseRoot)
    Remove-Item -LiteralPath (Join-Path $env:UABS_TEST_BIN 'git.cmd')
    $env:UABS_TEST_INSTALL_GIT = 'fail'
    $problem = $null
    try { & $Bootstrap -Providers Codex } catch { $problem = $_.Exception.Message }
    Assert ($problem -match 'Git for Windows installation failed') 'Git installation failure was not surfaced.'
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_NPM_LOG)) 'Provider installation continued after Git failed.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\provider-bootstrap.json'))) 'A failed dependency installation wrote success.'
  }
  Invoke-BootstrapCase 'existing Codex CLI survives a cold PATH without reinstall' {
    param($Bootstrap, $CaseRoot)
    Copy-Item -LiteralPath $env:UABS_TEST_CLI_TEMPLATE -Destination (Join-Path $env:APPDATA 'npm\codex.cmd')
    & $Bootstrap -Providers Codex
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_NPM_LOG)) 'An existing Codex CLI was reinstalled.'
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_WINGET_LOG)) 'An existing Codex CLI caused a package installation.'
  }
  Invoke-BootstrapCase 'installed-state doctor finds native versioned and npm Codex CLI paths' {
    param($Bootstrap, $CaseRoot)
    . (Join-Path $CaseRoot 'TOOLS\UABS-Common.ps1')
    # Execute only the doctor's real resolution function; its full entry point
    # audits installed state and writes reports, which this fixture must avoid.
    Invoke-Expression $doctorResolver.Extent.Text
    foreach ($candidate in @(
      (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe'),
      (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\99.1.0\codex.exe'),
      (Join-Path $env:APPDATA 'npm\codex.cmd')
    )) {
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $candidate) | Out-Null
      [IO.File]::WriteAllText($candidate, 'presence fixture; never executed')
      Assert ((Resolve-Exe 'Codex') -eq $candidate) ('The final doctor cannot find the supported Codex CLI path: ' + $candidate)
      Remove-Item -LiteralPath $candidate
    }
  }
  Invoke-BootstrapCase 'Codex installs Node LTS only when npm is unavailable' {
    param($Bootstrap, $CaseRoot)
    Remove-Item -LiteralPath (Join-Path $env:UABS_TEST_BIN 'npm.cmd')
    $env:UABS_TEST_INSTALL_NODE = '1'
    & $Bootstrap -Providers Codex
    Assert ([IO.File]::ReadAllText($env:UABS_TEST_WINGET_LOG).Trim() -eq 'OpenJS.NodeJS.LTS') 'The bootstrap did not install only the missing Node LTS prerequisite.'
    Assert (Test-Path -LiteralPath (Join-Path $env:APPDATA 'npm\codex.cmd')) 'Node installation did not lead to the Codex CLI.'
  }
  Invoke-BootstrapCase 'npm failure stops bootstrap before reporting success' {
    param($Bootstrap, $CaseRoot)
    [IO.File]::WriteAllText((Join-Path $env:UABS_TEST_BIN 'npm.cmd'), "@echo off`r`nexit /b 19`r`n")
    $problem = $null
    try { & $Bootstrap -Providers Codex } catch { $problem = $_.Exception.Message }
    Assert ($problem -match '19') 'The failing npm exit code was not surfaced.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\provider-bootstrap.json'))) 'A failed installation wrote a success report.'
  }
  Invoke-BootstrapCase 'successful npm warnings do not abort Windows PowerShell bootstrap' {
    param($Bootstrap, $CaseRoot)
    [IO.File]::WriteAllText((Join-Path $env:UABS_TEST_BIN 'npm.cmd'),
      ("@echo off`r`necho npm warn optional diagnostic 1>&2`r`n" + ($npmTemplate -replace "`r?`n", "`r`n")))
    & $Bootstrap -Providers Codex
    Assert (Test-Path -LiteralPath (Join-Path $env:APPDATA 'npm\codex.cmd')) 'A successful npm installation was rejected because it wrote stderr.'
  }
  Invoke-BootstrapCase 'no selection detects existing CLI and leaves other providers absent' {
    param($Bootstrap, $CaseRoot)
    Copy-Item -LiteralPath $env:UABS_TEST_CLI_TEMPLATE -Destination (Join-Path $env:UABS_TEST_BIN 'codex.cmd')
    & $Bootstrap
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_NPM_LOG)) 'Automatic selection reinstalled a provider.'
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_WINGET_LOG)) 'Automatic selection installed an unrelated prerequisite.'
    $report = @([IO.File]::ReadAllText((Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\provider-bootstrap.json')) | ConvertFrom-Json)
    Assert ($report.Count -eq 1 -and $report[0].provider -eq 'Codex') 'Automatic selection touched an absent provider.'
  }
  Invoke-BootstrapCase 'desktop-only Claude and Codex preview only their required CLIs' {
    param($Bootstrap, $CaseRoot)
    foreach ($relative in @('AnthropicClaude\Claude.exe','OpenAI\Codex\Codex.exe')) {
      $desktop = Join-Path $env:LOCALAPPDATA $relative
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $desktop) | Out-Null
      [IO.File]::WriteAllText($desktop, 'desktop presence fixture')
    }
    $preview = & $Bootstrap -CheckOnly 6>&1 | Out-String
    Assert ($preview -match 'Claude would install' -and $preview -match 'Codex would install') 'Desktop apps were mistaken for runnable provider CLIs.'
    Assert ($preview -notmatch '(Grok|Kimi|Hermes) would install') 'Desktop detection selected an unrelated provider.'
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_NPM_LOG)) 'Desktop preview installed a CLI.'
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_WINGET_LOG)) 'Desktop preview installed a prerequisite.'
  }
  Invoke-BootstrapCase 'empty machine requires an explicit provider selection' {
    param($Bootstrap, $CaseRoot)
    $problem = $null
    try { & $Bootstrap } catch { $problem = $_.Exception.Message }
    Assert ($problem -match 'Providers') 'The empty machine did not request an explicit -Providers selection.'
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_NPM_LOG)) 'An empty selection installed Codex.'
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_WINGET_LOG)) 'An empty selection installed a prerequisite.'
  }
  Invoke-BootstrapCase 'CheckOnly previews Codex without downloads installs or reports' {
    param($Bootstrap, $CaseRoot)
    & $Bootstrap -Providers Codex -CheckOnly
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_NPM_LOG)) 'CheckOnly installed Codex.'
    Assert (-not (Test-Path -LiteralPath $env:UABS_TEST_WINGET_LOG)) 'CheckOnly installed a prerequisite.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\provider-bootstrap.json'))) 'CheckOnly wrote a bootstrap report.'
  }
} finally {
  foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
  # The resolved target is a freshly created test directory under the temp root.
  $resolvedFixture = [IO.Path]::GetFullPath($fixture)
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup target.' }
  if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
if ($failures.Count) { throw ('PROVIDER BOOTSTRAP GATE: FAIL' + [Environment]::NewLine + ($failures -join [Environment]::NewLine)) }
Write-Host 'PROVIDER BOOTSTRAP GATE: PASS' -ForegroundColor Green
