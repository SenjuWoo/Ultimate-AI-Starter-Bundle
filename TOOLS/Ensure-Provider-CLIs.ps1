<#
.SYNOPSIS
  Bootstrap the selected AI provider CLIs on a fresh Windows user profile.
.DESCRIPTION
  Uses each provider's official Windows installer only when its command is absent,
  refreshes the current process PATH, and proves the executable starts. Existing
  installations are preserved. Authentication is deliberately not fabricated;
  providers that need first-run OAuth/API credentials are reported AUTH_REQUIRED.
#>
[CmdletBinding()]
param(
  [string[]]$Providers = @(),
  [switch]$CheckOnly
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')

# -File turns Claude,Codex into one string on Windows PowerShell 5.1.
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
$allowed = @('Claude','Codex','Grok','Kimi','Hermes','Antigravity')
foreach ($p in $Providers) { if ($allowed -notcontains $p) { throw "Unknown provider: $p" } }
if (-not $Providers.Count) { $Providers = @(Get-UabsInstalledProviders) }
if (-not $Providers.Count) {
  throw 'No installed providers detected. Choose the providers to install explicitly with -Providers Claude,Codex (or another supported selection).'
}

function Invoke-VerifiedOfficialScript([string]$Provider,[string]$Url,[string[]]$ScriptArgs=@()) {
  $temp = Join-Path $env:TEMP ("uabs-" + $Provider.ToLowerInvariant() + '-' + [guid]::NewGuid().ToString('N') + '.ps1')
  try {
    Write-UabsStep "$Provider official installer"
    $downloaded = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
      try {
        Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $temp -TimeoutSec 180
        $downloaded = $true
        break
      } catch {
        if ($attempt -ge 3) { throw }
        Start-Sleep -Seconds ([Math]::Pow(2, $attempt))
      }
    }
    if (-not $downloaded -or -not (Test-Path -LiteralPath $temp -PathType Leaf) -or (Get-Item $temp).Length -lt 256) { throw "$Provider installer download was empty." }
    $raw = [IO.File]::ReadAllText($temp)
    if ($raw -match '(?i)<html|cloudflare|just a moment') { throw "$Provider installer endpoint returned HTML/challenge instead of PowerShell." }
    $sha = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash
    Write-Host "  downloaded installer sha256=$sha"
    if ($CheckOnly) { return }

    # Vendor scripts may call `exit`; execute them in a child Windows
    # PowerShell so they cannot terminate the parent AIO before its doctor and
    # install report run. -File also gives us an explicit process exit code.
    $child = (Get-Command powershell.exe -ErrorAction Stop).Source
    $childArgs = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$temp) + @($ScriptArgs)
    & $child @childArgs
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$Provider official installer exited $code." }
  } finally {
    Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
  }
}

# OpenAI documents npm as a supported Windows CLI installation method:
# https://developers.openai.com/codex/enterprise/windows-deployment
# The standalone script endpoint returned 404 on a fresh Windows install.
# Use the official npm package instead of guessing another script URL. npm.cmd
# avoids the unsigned npm.ps1 shim under Windows' normal execution policy.
function Install-CodexCli {
  $npm = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $npm) {
    Write-UabsStep 'Codex requires npm - installing Node.js LTS'
    if (-not (Install-UabsWinget @('OpenJS.NodeJS.LTS'))) { throw 'Node.js LTS installation failed; Codex CLI requires npm.' }
    Refresh-ProcessPath
    $npm = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  }
  if (-not $npm) { throw 'Node.js installation completed but npm.cmd cannot be found. Open a new PowerShell window and retry.' }
  Write-UabsStep 'Codex official npm package'
  & $npm.Source install -g '@openai/codex' | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "Codex npm installation failed with exit code $LASTEXITCODE." }
}

# Every selected provider gets bundled plugin hooks that require Git Bash.
# Codex also needs Git sources for native plugins; npm alone is insufficient.
Refresh-ProcessPath
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  if ($CheckOnly) { Write-Host 'Git would be installed with winget Git.Git' }
  elseif (-not (Install-UabsWinget @('Git.Git'))) { throw 'Git for Windows installation failed.' }
  Refresh-ProcessPath
}
if (-not $CheckOnly) {
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) { throw 'Git installer completed but git is still not resolvable.' }
  & git --version | Out-Host
  if ($LASTEXITCODE -ne 0) { throw 'git --version failed.' }
}

$installers = @{
  Claude = 'https://claude.ai/install.ps1'
  Grok   = 'https://x.ai/cli/install.ps1'
  Kimi   = 'https://code.kimi.com/kimi-code/install.ps1'
  Hermes = 'https://hermes-agent.nousresearch.com/install.ps1'
}
$results = @()
foreach ($provider in $Providers) {
  Refresh-ProcessPath
  $exe = Resolve-UabsProviderExe -Provider $provider
  $installedNow = $false
  if (-not $exe) {
    if ($provider -eq 'Antigravity') {
      # Nothing scriptable to install: Antigravity is a desktop app from
      # antigravity.google. Report it and keep the other providers moving.
      Write-UabsWarn 'Antigravity: desktop app not installed (get it from antigravity.google); skipped'
      continue
    }
    if ($CheckOnly) {
      if ($provider -eq 'Codex') { Write-Host 'Codex would install with npm.cmd install -g @openai/codex (Node.js LTS if npm is missing)' }
      else { Write-Host "$provider would install from $($installers[$provider])" }
      continue
    }
    $extra = if ($provider -eq 'Hermes') { @('-SkipSetup') } else { @() }
    if ($provider -eq 'Codex') { Install-CodexCli }
    else {
      try {
        Invoke-VerifiedOfficialScript -Provider $provider -Url $installers[$provider] -ScriptArgs $extra
      } catch {
        if ($provider -ne 'Claude') { throw }
        Write-Warning "Claude native installer failed; trying Anthropic's official WinGet package. $($_.Exception.Message)"
        if (-not (Install-UabsWinget @('Anthropic.ClaudeCode'))) { throw 'Claude official script and WinGet fallback both failed.' }
      }
    }
    $installedNow = $true
    Refresh-ProcessPath
    $exe = Resolve-UabsProviderExe -Provider $provider
  }
  if (-not $exe) { throw "$provider installer returned but its executable cannot be found." }
  # Hermes --version fetches upstream; --help proves local startup without
  # making the bootstrap wait on a network update check (as the doctor does).
  $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try {
    if ($provider -eq 'Antigravity') {
      # Launching the GUI is not a startup probe; presence is the proof.
      $probeExit = 0
    }
    elseif ($provider -eq 'Hermes') {
      & $exe --help 2>&1 | Out-Null
      $probeExit = $LASTEXITCODE
    } else {
      & $exe --version 2>&1 | Out-Host
      $probeExit = $LASTEXITCODE
    }
  } finally { $ErrorActionPreference = $previous }
  if ($probeExit -ne 0) { throw "$provider local startup probe failed with exit code $probeExit." }
  # Literal verification contracts kept visible for audit tooling:
  # claude --version | codex --version | grok --version | kimi --version | hermes --help
  $auth = 'AUTH_REQUIRED'
  if ($provider -eq 'Grok' -and ((Test-Path (Join-Path $env:USERPROFILE '.grok\auth.json')) -or $env:XAI_API_KEY)) { $auth='AUTH_PRESENT' }
  if ($provider -eq 'Codex' -and ((Test-Path (Join-Path $env:USERPROFILE '.codex\auth.json')) -or $env:OPENAI_API_KEY)) { $auth='AUTH_PRESENT' }
  if ($provider -eq 'Hermes' -and ($env:OPENROUTER_API_KEY -or $env:NOUS_API_KEY)) { $auth='AUTH_PRESENT' }
  $results += [pscustomobject]@{ provider=$provider; executable=$exe; installed_now=$installedNow; auth_state=$auth }
  Write-UabsOk ("$provider executable verified; " + $auth)
}
if (-not $CheckOnly) {
  $reportDir = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
  New-Item -ItemType Directory -Force -Path $reportDir | Out-Null
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText((Join-Path $reportDir 'provider-bootstrap.json'), ($results | ConvertTo-Json -Depth 6), $enc)
}

# Provider bootstrap can install Hermes after runtime setup; apply its shell route now.
if (-not $CheckOnly -and $env:UABS_PYTHON -and $Providers -contains 'Hermes') { & (Join-Path $PSScriptRoot 'Set-HermesSharedPython.ps1') }
