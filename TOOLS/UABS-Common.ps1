# UABS-Common.ps1 - shared helpers for Ultimate AI Starter Bundle AIO installer
$script:UabsPackRoot = $null
$script:UabsHeaders = @{ 'User-Agent' = 'Ultimate-AI-Starter-Bundle-AIO' }

function Get-UabsStateRoot {
  $base = $env:LOCALAPPDATA
  if (-not $base) { $base = $env:TEMP }
  if (-not $base) { throw 'LOCALAPPDATA and TEMP are both unavailable.' }
  return (Join-Path $base 'Ultimate-AI-Starter-Bundle')
}

function Refresh-ProcessPath {
  $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $user = [Environment]::GetEnvironmentVariable('Path', 'User')
  $env:Path = (@($machine, $user) | Where-Object { $_ }) -join ';'
}

function Get-UabsGitShellDirectory {
  param([string]$GitExecutable)
  # Git's cmd directory is normally on PATH, but its POSIX shells are not.
  # Resolve from the installed executable, never a developer's drive/root.
  $executables = if ($GitExecutable) { @($GitExecutable) } else {
    @(Get-Command git.exe -CommandType Application -All -ErrorAction SilentlyContinue | ForEach-Object Source)
  }
  # git.exe lives in <Git>\cmd, <Git>\bin or <Git>\mingw64\bin; the shells
  # live in <Git>\bin. Walk up to the install root rather than one level.
  foreach ($exe in $executables) {
    if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { continue }
    $dir = Split-Path -Parent $exe
    for ($i = 0; $i -lt 3 -and $dir; $i++) {
      foreach ($candidate in @($dir, (Join-Path $dir 'bin'))) {
        if ((Test-Path -LiteralPath (Join-Path $candidate 'bash.exe') -PathType Leaf) -and
            (Test-Path -LiteralPath (Join-Path $candidate 'sh.exe') -PathType Leaf)) { return $candidate }
      }
      $dir = Split-Path -Parent $dir
    }
  }
  return $null
}

function Repair-UabsHookShellPath {
  param([switch]$CheckOnly, [string]$GitExecutable)
  $directory = Get-UabsGitShellDirectory -GitExecutable $GitExecutable
  # Judge only the first match, the one a hook would run: with WSL installed,
  # System32\bash.exe also matches and made a working Git bash look missing.
  $missing = @('sh.exe','bash.exe' | Where-Object {
    $command = Get-Command $_ -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    -not $command -or $command.Source -match '(?i)\\(System32|Sysnative|WindowsApps)\\'
  })
  if ($CheckOnly) {
    if ($missing.Count) { 'Plugin shell prerequisite missing: ' + ($missing -join ', ') + '. Run TOOLS\Install-Completeness-Gate.ps1 and restart the AI apps.' }
    return
  }
  if (-not $directory) {
    if ($missing.Count) { Write-UabsWarn 'Git POSIX shells not found. Install Git for Windows, then re-run the installer; plugin hooks need sh/bash.' }
    return
  }
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $entries = @($userPath -split ';' | Where-Object { $_ })
  $present = @($entries | Where-Object { [Environment]::ExpandEnvironmentVariables($_).TrimEnd('\') -ieq $directory.TrimEnd('\') }).Count -gt 0
  if (-not $present -and $missing.Count) {
    $backupRoot = Join-Path (Get-UabsStateRoot) 'backups'
    New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null
    $backup = Join-Path $backupRoot ('hook-shell-path-' + [guid]::NewGuid().ToString('N') + '.json')
    $snapshot = [ordered]@{ schema=1; user_path=$userPath; added_directory=$directory }
    [IO.File]::WriteAllText($backup, ($snapshot | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))
    $roundTrip = [IO.File]::ReadAllText($backup) | ConvertFrom-Json
    if ($roundTrip.user_path -cne $userPath) { throw 'PATH backup verification failed; PATH was not changed.' }
    $updated = (@($userPath, $directory) | Where-Object { $_ }) -join ';'
    [Environment]::SetEnvironmentVariable('Path', $updated, 'User')
    if ([Environment]::GetEnvironmentVariable('Path', 'User') -cne $updated) {
      [Environment]::SetEnvironmentVariable('Path', $userPath, 'User')
      throw 'PATH repair verification failed; original restored.'
    }
    Write-UabsOk ('Git hook shells added to user PATH; original saved at ' + $backup)
    Write-UabsWarn 'Restart AI apps launched before this repair; their inherited PATH is unchanged.'
  }
  # Preserve private runtime prefixes in this process; Refresh-ProcessPath
  # would replace them with the registry PATH and can hide its Python/Node.
  if ($missing.Count) { $env:PATH = $directory + ';' + $env:PATH }
}

function Get-UabsCodexCli {
  <# Prefer an independently updatable Codex CLI over Hermes' private copy.
     The desktop AppX resource appears on PATH but Windows does not permit
     launching it out-of-process, so it is not a CLI candidate. #>
  $commands = @(
    @(Get-Command codex -All -ErrorAction SilentlyContinue)
    @(Get-Command codex.exe -All -ErrorAction SilentlyContinue)
    @(Get-Command codex.cmd -All -ErrorAction SilentlyContinue)
  )
  $seen = @{}
  $preferred = @()
  $fallback = @()
  $hermesNode = Join-Path $env:LOCALAPPDATA 'hermes\node'
  foreach ($command in $commands) {
    $source = [string]$command.Source
    if (-not $source) { $source = [string]$command.Path }
    if (-not $source -or $seen.ContainsKey($source.ToLowerInvariant())) { continue }
    if ($source -match '(?i)\\WindowsApps\\OpenAI\.Codex_') { continue }
    $seen[$source.ToLowerInvariant()] = $true
    $candidate = [pscustomobject]@{ Source = $source }
    if (Test-UabsPathWithin -Path $source -Root $hermesNode) { $fallback += $candidate }
    else { $preferred += $candidate }
  }
  foreach ($candidate in @($preferred + $fallback)) {
    $version = Get-UabsNativeOutput -Exe $candidate.Source -CmdArgs @('--version')
    if ($version -match '(?m)^codex-cli\s+\d') { return $candidate }
  }
  return $null
}

function Invoke-UabsLegacyStateMigration {
  <# Move only paths owned by older bundle installers. Conflicts and unknown
     files stay where they are; this is deliberately not a directory mirror. #>
  $old = Join-Path $env:LOCALAPPDATA 'Skyrim-AI-V5'
  $new = Get-UabsStateRoot
  if (-not (Test-Path -LiteralPath $old -PathType Container)) { return }
  New-Item -ItemType Directory -Force -Path $new | Out-Null
  # Old provider sessions may still hold these generated helpers open. Stop
  # only the two bundle-owned command lines before moving their directory.
  try {
    $legacyHelpers = @('\tools\cbm-dashboard-plus.py','\tools\headroom-mcp-launch.py')
    foreach ($proc in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
      if (-not $proc.CommandLine) { continue }
      $commandLine = $proc.CommandLine.Replace('/', '\')
      if (@($legacyHelpers | Where-Object { $commandLine.IndexOf(($old + $_), [StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count) {
        Stop-Process -Id $proc.ProcessId -Force -ErrorAction SilentlyContinue
        Write-UabsOk ('stopped legacy helper process: ' + $proc.ProcessId)
      }
    }
  } catch { Write-UabsWarn ('could not stop a legacy helper process: ' + $_.Exception.Message) }
  # codex-marketplace stays until `codex plugin remove` detaches its official
  # registry entry; moving it first would turn a healthy legacy entry dead.
  $owned = @(
    'backups','cache','github-mcp-server','hermes-plugin-src','hooks','plugins-src',
    'spookys-automod-toolkit','tools','install-state.json','installed-state-doctor.json',
    'mcp-profiles.json','provider-bootstrap.json','toolbelt.json','TOOLBELT.md'
  )
  foreach ($name in $owned) {
    $src = Join-Path $old $name
    $dst = Join-Path $new $name
    if ((Test-Path -LiteralPath $src) -and -not (Test-Path -LiteralPath $dst)) {
      Move-Item -LiteralPath $src -Destination $dst
      Write-UabsOk ('migrated legacy state: ' + $name)
    }
  }
  # These are generated reports or versioned bundle binaries. Once V8 has a
  # replacement, retaining the older copy cannot preserve user data; it only
  # leaves two apparent authorities on disk.
  foreach ($name in @('github-mcp-server','installed-state-doctor.json','provider-bootstrap.json','TOOLBELT.md')) {
    $src = Join-Path $old $name
    $dst = Join-Path $new $name
    if ((Test-Path -LiteralPath $src) -and (Test-Path -LiteralPath $dst)) {
      Remove-Item -LiteralPath $src -Recurse -Force
      Write-UabsOk ('removed replaced legacy state: ' + $name)
    }
  }
  foreach ($envName in @('HEADROOM_CMD','SPOOKY_AUTOMOD_ROOT')) {
    $value = [Environment]::GetEnvironmentVariable($envName, 'User')
    if ($value -and $value.StartsWith($old, [StringComparison]::OrdinalIgnoreCase)) {
      Set-UabsUserEnv $envName ($new + $value.Substring($old.Length))
    }
  }
  if (-not @(Get-ChildItem -LiteralPath $old -Force -ErrorAction SilentlyContinue).Count) {
    Remove-Item -LiteralPath $old -Force
  } else {
    Write-UabsWarn ('legacy state has unowned/conflicting files; preserved: ' + $old)
  }
}

function Get-UabsPackRoot {
  if ($script:UabsPackRoot -and (Test-Path -LiteralPath $script:UabsPackRoot)) { return $script:UabsPackRoot }
  $here = $PSScriptRoot
  if (Test-Path (Join-Path $here 'BUNDLED-TOOLS\CATALOG.json')) { $script:UabsPackRoot = $here; return $here }
  $parent = Split-Path $here -Parent
  if (Test-Path (Join-Path $parent 'BUNDLED-TOOLS\CATALOG.json')) { $script:UabsPackRoot = $parent; return $parent }
  throw 'Cannot locate pack root (BUNDLED-TOOLS\CATALOG.json). Run from the Uabs pack folder.'
}

function Get-UabsCatalog {
  $root = Get-UabsPackRoot
  $path = Join-Path $root 'BUNDLED-TOOLS\CATALOG.json'
  return ([IO.File]::ReadAllText($path) | ConvertFrom-Json)
}

function Expand-UabsEnvPath([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $p }
  return [Environment]::ExpandEnvironmentVariables($p)
}

function Test-UabsPath([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $false }
  try { return Test-Path -LiteralPath (Expand-UabsEnvPath $p) } catch { return $false }
}

function Get-UabsPythonExecutable {
  param([string[]]$RequiredModules = @())
  <# Return a real, runnable interpreter path rather than trusting a PATH alias.
     A fresh winget install may expose only `py`, WindowsApps can expose a dead
     `python.exe`, and the AIO's Hermes install already carries a stable Python
     even when neither launcher is visible in the current process. #>
  $candidates = @()
  if ($env:SKYRIM_FORGE_PYTHON) {
    $candidates += [pscustomobject]@{ Source = $env:SKYRIM_FORGE_PYTHON; Prefix = @() }
  }
  foreach ($name in @('python', 'python3')) {
    $cmd = Get-Command $name -ErrorAction SilentlyContinue
    if ($cmd) { $candidates += [pscustomobject]@{ Source = $cmd.Source; Prefix = @() } }
  }
  $launcher = Get-Command py -ErrorAction SilentlyContinue
  if ($launcher) { $candidates += [pscustomobject]@{ Source = $launcher.Source; Prefix = @('-3') } }
  # Flattened with +=: two installed versions used to land as ONE array element.
  $knownPaths = @()
  $knownPaths += @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Programs\Python\Python*\python.exe') -File -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | ForEach-Object FullName)
  # The Python install manager (python.org's default since 3.14) keeps runtimes here.
  $knownPaths += @(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Python\pythoncore-*\python.exe') -File -ErrorAction SilentlyContinue |
    Sort-Object FullName -Descending | ForEach-Object FullName)
  $knownPaths += (Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\python.exe')
  foreach ($path in $knownPaths) {
    if ($path) { $candidates += [pscustomobject]@{ Source = [string]$path; Prefix = @() } }
  }

  $seen = @{}
  $privateFallback = $null
  foreach ($candidate in $candidates) {
    $key = ([string]$candidate.Source + '|' + (@($candidate.Prefix) -join ' ')).ToLowerInvariant()
    if ($seen.ContainsKey($key)) { continue }
    $seen[$key] = $true
    try {
      $probeArgs = @($candidate.Prefix) + @('-c', 'import importlib,os,sys;[importlib.import_module(n) for n in sys.argv[1:]];print(os.path.abspath(sys.executable))') + @($RequiredModules)
      $resolved = @(Get-UabsNativeStdout -Exe $candidate.Source -CmdArgs $probeArgs | Where-Object { $_ } | Select-Object -Last 1)
      if ($LASTEXITCODE -eq 0 -and $resolved.Count -and (Test-Path -LiteralPath $resolved[0] -PathType Leaf)) {
        # An installer run from inside an AI app inherits that app's private
        # runtime first on PATH; hooks wired to it break when the app updates.
        if (Test-UabsPrivateRuntimePath $resolved[0]) {
          if (-not $privateFallback) { $privateFallback = [string]$resolved[0] }
          continue
        }
        return [string]$resolved[0]
      }
    } catch { }
  }
  return $privateFallback
}

function Test-UabsPrivateRuntimePath([string]$Path) {
  <# True for interpreters an AI desktop app ships for itself (Codex keeps one
     under ~\.cache\codex-runtimes and %LOCALAPPDATA%\OpenAI\Codex\runtimes).
     The app replaces or removes them on update/uninstall without notice. #>
  if (-not $Path) { return $false }
  return $Path -match '(?i)[\\/](\.cache[\\/]codex-runtimes|OpenAI[\\/]Codex[\\/]runtimes|AnthropicClaude[\\/]app-[^\\/]+)[\\/]'
}

function Test-UabsPathWithin([string]$Path, [string]$Root) {
  if (-not $Path -or -not $Root) { return $false }
  try {
    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    return $fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase) -or
      $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)
  } catch { return $false }
}

function Write-UabsStep([string]$m) { Write-Host ("==> " + $m) -ForegroundColor Cyan }
function Write-UabsOk([string]$m)   { Write-Host ("  OK  " + $m) -ForegroundColor Green }
function Write-UabsWarn([string]$m) { Write-Host ("  !!  " + $m) -ForegroundColor Yellow }
# A normal condition worth one line (skipped by design, optional, already done):
# not a warning, so it does not look like something for the user to fix.
function Write-UabsInfo([string]$m) { Write-Host ("  ..  " + $m) -ForegroundColor DarkGray }
function Write-UabsBad([string]$m)  { Write-Host ("  XX  " + $m) -ForegroundColor Red }

function Set-UabsUserEnv([string]$Name, [string]$Value) {
  [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
  Set-Item -Path ("Env:" + $Name) -Value $Value
}

function Get-UabsProviderHome([string]$Provider, $Catalog) {
  $p = $Catalog.providers.$Provider
  if (-not $p) { throw ("Unknown provider " + $Provider) }
  $envName = $p.home_env
  # Process BEFORE User. Process is the more specific scope: it is what someone
  # sets to redirect a single run, and honouring User first made that override
  # impossible on any machine where the User variable exists. Two consequences,
  # both real: Get-UabsHermesPaths resolves the same path from $env: (which is
  # process scope), so the two helpers disagreed about the same home; and the
  # installer could not be exercised against an isolated empty home, which is
  # why "installer PASS" was never evidence about fresh installs.
  $fromEnv = [Environment]::GetEnvironmentVariable($envName, 'Process')
  if (-not $fromEnv) { $fromEnv = [Environment]::GetEnvironmentVariable($envName, 'User') }
  if ($fromEnv) { return $fromEnv }
  return (Expand-UabsEnvPath $p.home_default)
}

function Get-UabsProviderSkillsDir([string]$Provider, $Catalog) {
  # Codex still reads $CODEX_HOME\skills for compatibility, but its supported
  # user-level Agent Skills root is $HOME\.agents\skills. Writing both makes
  # Codex index every bundle skill twice and can erase every description.
  if ($Provider -eq 'Codex') { return (Join-Path $env:USERPROFILE '.agents\skills') }
  return (Join-Path (Get-UabsProviderHome -Provider $Provider -Catalog $Catalog) 'skills')
}

function Invoke-UabsGitHubLatest {
  param([string]$Owner, [string]$Repo)
  $uri = "https://api.github.com/repos/$Owner/$Repo/releases/latest"
  return Invoke-RestMethod -Uri $uri -Headers $script:UabsHeaders -TimeoutSec 60
}

function Get-UabsBundleUpdatePlan {
  <# Pure decision for START-HERE's update check; no I/O.
     none = already latest, skip = keep the local pack (with reason),
     git-pull = fast-forward a clean clone, release = install the newer release. #>
  param([string]$LocalVersion, [string]$LatestTag, [bool]$IsGit, [bool]$GitClean, [bool]$GitTracksUpstream)
  $plan = [ordered]@{ action = 'skip'; reason = ''; latest = $LatestTag }
  try {
    $local = [version]($LocalVersion.Trim().TrimStart('v','V'))
    $latest = [version]($LatestTag.Trim().TrimStart('v','V'))
  } catch { $plan.reason = 'Bundle update check skipped: unreadable version (local ' + $LocalVersion + ', latest ' + $LatestTag + ').'; return $plan }
  if ($latest -le $local) { $plan.action = 'none'; return $plan }
  if ($IsGit -and -not ($GitClean -and $GitTracksUpstream)) {
    $plan.reason = "Bundle $LatestTag is available, but this git checkout has local changes or no upstream branch; not updating it. Commit/stash, then git pull."
    return $plan
  }
  $plan.action = $(if ($IsGit) { 'git-pull' } else { 'release' })
  return $plan
}

function Get-UabsGitCheckoutState {
  param([string]$Root)
  $state = [ordered]@{ is_git = $false; clean = $false; tracks = $false }
  if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) { return $state }
  $git = Get-Command git -ErrorAction SilentlyContinue
  if (-not $git) { return $state }
  $state.is_git = $true
  $porcelain = @(Get-UabsNativeStdout -Exe $git.Source -CmdArgs @('-C', $Root, 'status', '--porcelain'))
  $state.clean = ($LASTEXITCODE -eq 0 -and -not $porcelain.Count)
  $null = Get-UabsNativeStdout -Exe $git.Source -CmdArgs @('-C', $Root, 'rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}')
  $state.tracks = ($LASTEXITCODE -eq 0)
  return $state
}

function ConvertTo-UabsArgList {
  <# Re-create a script's bound parameters as powershell.exe -File arguments. #>
  param([System.Collections.IDictionary]$Bound, [string[]]$Exclude = @())
  $out = @()
  foreach ($key in $Bound.Keys) {
    if ($Exclude -contains $key) { continue }
    $value = $Bound[$key]
    if ($value -is [System.Management.Automation.SwitchParameter]) { if ($value.IsPresent) { $out += ('-' + $key) }; continue }
    if ($value -is [bool]) { if ($value) { $out += ('-' + $key) }; continue }
    $out += ('-' + $key)
    $out += $(if ($value -is [array]) { (@($value) -join ',') } else { [string]$value })
  }
  return $out
}

function Get-UabsSelfUpdateRemoteArgs {
  <# INSTALL-REMOTE forwards -Providers/-SkipPreamble/-SkipHouseCarlSetup to the
     new installer itself; everything else rides in -InstallerArgs. Passing a
     parameter both ways makes the new installer fail to bind it twice. #>
  param([System.Collections.IDictionary]$Bound, [string]$Tag)
  $own = @('Providers','SkipPreamble','SkipHouseCarlSetup')
  $splat = @{ Tag = $Tag; SelfUpdate = $true; InstallerArgs = @(@(ConvertTo-UabsArgList -Bound $Bound -Exclude (@('SkipSelfUpdate') + $own)) + '-SkipSelfUpdate') }
  if ($Bound.Contains('Providers')) { $splat.Providers = @(@($Bound['Providers']) -join ',') }
  foreach ($name in @('SkipPreamble','SkipHouseCarlSetup')) { if ($Bound.Contains($name) -and $Bound[$name]) { $splat[$name] = $true } }
  return $splat
}

function Invoke-UabsBundleSelfUpdate {
  <# START-HERE update check. Returns $null to continue the local install, or
     the exit code of the newer installer that already ran. Never blocks: any
     network, git or staging failure falls back to the local pack. #>
  param([string]$PackRoot, [System.Collections.IDictionary]$Bound)
  $local = ([IO.File]::ReadAllText((Join-Path $PackRoot 'VERSION.txt'))).Trim()
  Write-UabsStep ('Checking for a newer bundle release (local ' + $local + ')')
  try {
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/SenjuWoo/Ultimate-AI-Starter-Bundle/releases/latest' -Headers $script:UabsHeaders -TimeoutSec 15
    $latest = [string]$release.tag_name
  } catch { Write-UabsWarn ('Bundle update check skipped (offline or GitHub unavailable): ' + $_.Exception.Message); return $null }
  $git = Get-UabsGitCheckoutState -Root $PackRoot
  $plan = Get-UabsBundleUpdatePlan -LocalVersion $local -LatestTag $latest -IsGit $git.is_git -GitClean $git.clean -GitTracksUpstream $git.tracks
  $forward = @(ConvertTo-UabsArgList -Bound $Bound -Exclude @('SkipSelfUpdate'))
  $powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
  switch ($plan.action) {
    'none' {
      if ($local.TrimStart('v','V') -eq $latest.TrimStart('v','V')) { Write-UabsOk ('Bundle ' + $local + ' is the latest release.') }
      else { Write-UabsOk ('Bundle ' + $local + ' is newer than the latest published release ' + $latest + '; keeping it.') }
      return $null
    }
    'skip' { Write-UabsWarn $plan.reason; return $null }
    'git-pull' {
      Write-UabsStep ('Fast-forwarding this clone to ' + $latest)
      $previous = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
      try { $pull = & (Get-Command git).Source -C $PackRoot pull --ff-only 2>&1 | Out-String; $pulled = ($LASTEXITCODE -eq 0) }
      finally { $ErrorActionPreference = $previous }
      if (-not $pulled) { Write-UabsWarn ('git pull --ff-only failed; installing the local copy instead: ' + $pull.Trim()); return $null }
      & $powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'INSTALL-AIO.ps1') @forward -SkipSelfUpdate
      return $LASTEXITCODE
    }
    'release' {
      $remote = Join-Path $PackRoot 'INSTALL-REMOTE.ps1'
      $remoteArgs = Get-UabsSelfUpdateRemoteArgs -Bound $Bound -Tag $latest
      try { & $remote @remoteArgs } catch { Write-UabsWarn ('Bundle update failed; installing the local copy instead: ' + $_.Exception.Message); return $null }
      # 20 = the newer release could not be staged; the local copy is still whole.
      if ($LASTEXITCODE -eq 20) { Write-UabsWarn 'Newer release could not be staged; installing the local copy instead.'; return $null }
      return $LASTEXITCODE
    }
  }
  return $null
}

function Get-UabsComponentGitHubRelease {
  param($Comp)
  $tag = [string]$Comp.release_tag
  if ($Comp.id -eq 'rtk') {
    # RTK's hook and benchmarks require the catalog version, not upstream latest.
    if ([string]$Comp.version -notmatch '^\d+\.\d+\.\d+$') { throw 'RTK catalog version is invalid.' }
    $tag = 'v' + $Comp.version
  }
  if (-not $tag) {
    return Invoke-UabsGitHubLatest -Owner $Comp.github.owner -Repo $Comp.github.repo
  }
  if ($tag -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') { throw 'Catalog release_tag is invalid.' }
  $uri = "https://api.github.com/repos/$($Comp.github.owner)/$($Comp.github.repo)/releases/tags/$tag"
  $release = Invoke-RestMethod -Uri $uri -Headers $script:UabsHeaders -TimeoutSec 60
  if ($release.tag_name -ne $tag) { throw "$($Comp.id) release tag mismatch: expected $tag" }
  return $release
}

function Get-UabsRtkFallbackAsset {
  param($Comp, [string]$PackRoot, [string]$Cache, [string]$Offline)
  # A reused asset filename proves no version. Only trust the shipped digest
  # without a network response; Core has no offline row and fails closed here.
  $manifest = Get-Content -LiteralPath (Join-Path $PackRoot 'BUNDLED-TOOLS\OFFLINE-MANIFEST.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $row = @($manifest.assets | Where-Object { $_.file -eq $Comp.offline_asset } | Select-Object -First 1)
  if (-not $row.Count) { return $null }
  $asset = [pscustomobject]@{ size=$row[0].size; digest=('sha256:' + $row[0].sha256) }
  foreach ($dir in @($Offline, $Cache)) {
    $path = Join-Path $dir $Comp.offline_asset
    if (Test-UabsReleaseAssetFile -Asset $asset -Path $path -RequireDigest) { return $path }
  }
  return $null
}

function Get-UabsRtkVersion {
  param([string]$Path, [string]$ExpectedVersion)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "RTK executable missing: $Path" }
  $previous = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    $text = (& $Path --version 2>&1 | Out-String).Trim()
    $code = $LASTEXITCODE
  } finally { $ErrorActionPreference = $previous }
  $match = [regex]::Match($text, '(?im)^rtk\s+([0-9]+(?:\.[0-9]+){2,})\s*$')
  if ($code -ne 0 -or -not $match.Success) { throw "RTK --version check failed (exit $code): $text" }
  $actual = $match.Groups[1].Value
  if ($actual -ne $ExpectedVersion) { throw "RTK candidate version $actual, expected $ExpectedVersion; replacement refused." }
  return $actual
}

function Install-UabsRtkExecutable {
  param([string]$Source, [string]$Destination, [string]$ExpectedVersion)
  $Source = [IO.Path]::GetFullPath($Source)
  $Destination = [IO.Path]::GetFullPath($Destination)
  if ($Source -eq $Destination) { throw 'RTK source and destination must differ.' }
  # Validate before touching the existing binary. Stage beside it for an atomic
  # file replacement, retaining the previous executable as a recoverable backup.
  [void](Get-UabsRtkVersion -Path $Source -ExpectedVersion $ExpectedVersion)
  $digest = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
  $parent = Split-Path -Parent $Destination
  # Same bytes already installed: re-copying only left a 9.5 MB backup per run
  # (14 of them measured beside one rtk.exe, 2026-10-10).
  if ((Test-Path -LiteralPath $Destination -PathType Leaf) -and (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -eq $digest) {
    $version = Get-UabsRtkVersion -Path $Destination -ExpectedVersion $ExpectedVersion
    return @{ status='current'; root=$parent; exe=$Destination; version=$version; backup=$null }
  }
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
  $nonce = [Guid]::NewGuid().ToString('N')
  $part = Join-Path $parent ('rtk.part-' + $nonce + '.exe')
  $backup = $Destination + '.bak-uabs-' + $nonce
  $hadPrevious = Test-Path -LiteralPath $Destination -PathType Leaf
  $committed = $false
  try {
    Copy-Item -LiteralPath $Source -Destination $part
    if ((Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash -ne $digest) { throw 'RTK staged hash mismatch.' }
    if ($hadPrevious) { [IO.File]::Replace($part, $Destination, $backup) }
    else { [IO.File]::Move($part, $Destination) }
    $committed = $true
    if ((Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -ne $digest) { throw 'RTK installed hash mismatch.' }
    $version = Get-UabsRtkVersion -Path $Destination -ExpectedVersion $ExpectedVersion
    return @{ status='installed'; root=$parent; exe=$Destination; version=$version; backup=$(if ($hadPrevious) { $backup } else { $null }) }
  } catch {
    # Roll back only our exact replacement; never clobber a concurrent writer.
    if ($committed -and (Test-Path -LiteralPath $Destination -PathType Leaf) -and
        (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -eq $digest) {
      if ($hadPrevious) { [IO.File]::Replace($backup, $Destination, [NullString]::Value) }
      else { [IO.File]::Delete($Destination) }
    }
    throw
  } finally {
    if (Test-Path -LiteralPath $part -PathType Leaf) { [IO.File]::Delete($part) }
  }
}

function Get-UabsReleaseAsset {
  param($Release, [string[]]$Patterns)
  foreach ($pat in $Patterns) {
    $a = @($Release.assets | Where-Object { $_.name -like $pat }) | Select-Object -First 1
    if ($a) { return $a }
  }
  return $null
}

function Test-UabsReleaseAssetFile {
  param($Asset, [string]$Path, [switch]$RequireDigest)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  $file = Get-Item -LiteralPath $Path
  if ($file.Length -le 0) { return $false }

  $expectedSize = 0L
  try { $expectedSize = [long]$Asset.size } catch { $expectedSize = 0L }
  if ($expectedSize -gt 0 -and $file.Length -ne $expectedSize) { return $false }

  $digest = ''
  try { $digest = [string]$Asset.digest } catch { $digest = '' }
  $match = [regex]::Match($digest, '^sha256:([0-9a-fA-F]{64})$')
  if ($match.Success) {
    $actual = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    return [string]::Equals($actual, $match.Groups[1].Value, [StringComparison]::OrdinalIgnoreCase)
  }
  if ($digest -or $expectedSize -le 0) { return $false }
  if ($RequireDigest) { return $false }
  return $true
}

function Save-UabsUrl {
  param([string]$Url, [string]$OutFile)
  $dir = Split-Path $OutFile -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Write-UabsStep ("Download " + (Split-Path $OutFile -Leaf))
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -Headers $script:UabsHeaders -TimeoutSec 900
  Write-UabsOk (("{0:N1} MB" -f ((Get-Item $OutFile).Length / 1MB)))
}

function Save-UabsReleaseAsset {
  param($Asset, [string]$OutFile, [switch]$ReuseValid)
  if (-not $Asset -or -not $Asset.browser_download_url) { throw 'GitHub release asset has no download URL.' }
  if ($ReuseValid -and (Test-UabsReleaseAssetFile -Asset $Asset -Path $OutFile -RequireDigest)) {
    Write-UabsOk ("Verified cached " + (Split-Path $OutFile -Leaf))
    return $OutFile
  }

  $part = $OutFile + '.part-' + $PID + '-' + [Guid]::NewGuid().ToString('N')
  try {
    Save-UabsUrl -Url $Asset.browser_download_url -OutFile $part
    if (-not (Test-UabsReleaseAssetFile -Asset $Asset -Path $part)) {
      throw ("Downloaded release asset failed size or SHA-256 validation: " + $Asset.name)
    }
    Move-Item -LiteralPath $part -Destination $OutFile -Force
    return $OutFile
  } finally {
    Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue
  }
}

function Expand-UabsZip {
  param([string]$Zip, [string]$Dest, [switch]$WipeDest)
  if ($WipeDest -and (Test-Path $Dest)) { Remove-Item -LiteralPath $Dest -Recurse -Force }
  New-Item -ItemType Directory -Force -Path $Dest | Out-Null
  Expand-Archive -LiteralPath $Zip -DestinationPath $Dest -Force
}

function Resolve-UabsSingleRoot {
  param([string]$Dest)
  $kids = @(Get-ChildItem -LiteralPath $Dest -Force | Where-Object { $_.Name -ne '__MACOSX' })
  if ($kids.Count -eq 1 -and $kids[0].PSIsContainer) { return $kids[0].FullName }
  return $Dest
}

function Find-UabsFileUnder {
  param([string]$Root, [string]$Name, [int]$Depth = 6)
  if (-not (Test-Path $Root)) { return $null }
  $hit = Get-ChildItem -LiteralPath $Root -Filter $Name -Recurse -Depth $Depth -File -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($hit) { return $hit.FullName }
  return $null
}

function Test-UabsDotNetRuntime([string]$Pattern) {
  try {
    $r = & dotnet --list-runtimes 2>$null
    return [bool]($r | Where-Object { $_ -match $Pattern })
  } catch { return $false }
}

function Test-UabsDotNetSdk([string]$Pattern) {
  try {
    $r = & dotnet --list-sdks 2>$null
    return [bool]($r | Where-Object { $_ -match $Pattern })
  } catch { return $false }
}

function Install-UabsWinget([string[]]$Ids) {
  $winget = Get-Command winget -ErrorAction SilentlyContinue
  if (-not $winget) { Write-UabsWarn 'winget not available'; return $false }
  foreach ($id in $Ids) {
    Write-UabsStep ("winget install " + $id)
    & winget install --id $id -e --accept-package-agreements --accept-source-agreements --disable-interactivity | Out-Host
    if ($LASTEXITCODE -ne 0) {
      Write-UabsBad ("winget failed for " + $id + " exit=" + $LASTEXITCODE)
      return $false
    }
  }
  return $true
}

function Test-UabsFileLocked([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
  try {
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $fs.Close()
    return $false
  } catch {
    return $true
  }
}

function Stop-UabsProcessUsingExecutable([string]$Path) {
  if (-not $Path) { return 0 }
  $wanted = [IO.Path]::GetFullPath($Path)
  $stopped = 0
  foreach ($proc in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
    if (-not $proc.ExecutablePath) { continue }
    if (-not [string]::Equals([IO.Path]::GetFullPath($proc.ExecutablePath), $wanted, [StringComparison]::OrdinalIgnoreCase)) { continue }
    Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
    $stopped++
  }
  if ($stopped) {
    for ($i = 0; $i -lt 20 -and (Test-UabsFileLocked $wanted); $i++) { Start-Sleep -Milliseconds 250 }
  }
  return $stopped
}

function Find-UabsCodebaseMemoryExe {
  $cands = @()
  if ($env:CODEBASE_MEMORY_MCP) { $cands += $env:CODEBASE_MEMORY_MCP }
  $u = [Environment]::GetEnvironmentVariable('CODEBASE_MEMORY_MCP', 'User')
  if ($u) { $cands += $u }
  $cands += (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe')
  $cands += (Join-Path $env:USERPROFILE '.local\bin\codebase-memory-mcp.exe')
  foreach ($c in $cands) {
    if ($c -and (Test-Path -LiteralPath $c -PathType Leaf)) {
      return (Resolve-Path -LiteralPath $c).Path
    }
  }
  return $null
}

function Update-UabsGrokMcpBlock {
  param(
    [string]$Name,
    [string]$Command,
    [string[]]$ArgList = @(),
    [hashtable]$EnvMap = $null,
    [int]$Startup = 90,
    [int]$Tool = 6000,
    [switch]$SkipIfPresent,
    # Codex uses the same [mcp_servers.<name>] TOML shape as Grok, so the same
    # writer serves both. Defaults to ~/.grok/config.toml.
    [string]$ConfigPath = $null
  )
  if ($ConfigPath) {
    $configPath = $ConfigPath
    $grokDir = Split-Path $configPath -Parent
  } else {
    $grokDir = Join-Path $env:USERPROFILE '.grok'
    $configPath = Join-Path $grokDir 'config.toml'
  }
  New-Item -ItemType Directory -Force -Path $grokDir | Out-Null
  $content = ''
  if (Test-Path -LiteralPath $configPath) {
    $content = [IO.File]::ReadAllText($configPath)
  }

  $cmdNorm = ($Command -replace '\\', '/').Trim()
  $argNorm = (@($ArgList | ForEach-Object { ($_ -replace '\\', '/').Trim() }) -join ([char]31))
  if ($SkipIfPresent -and $content) {
    $nameEsc = [regex]::Escape($Name)
    $block = [regex]::Match($content, '(?ms)^[ \t]*\[mcp_servers\.' + $nameEsc + '\][ \t]*\r?\n(?<body>.*?)(?=^[ \t]*\[|\z)')
    if ($block.Success) {
      $body = $block.Groups['body'].Value
      $m = [regex]::Match($body, '(?m)^[ \t]*command[ \t]*=[ \t]*["'']([^"'']+)["'']')
      $existingCmd = if ($m.Success) { ($m.Groups[1].Value -replace '\\', '/').Trim() } else { '' }
      # Every npx server shares one command, so comparing only the command
      # always matched and a drifted pin in the args survived every upgrade.
      $am = [regex]::Match($body, '(?ms)^[ \t]*args[ \t]*=[ \t]*\[(?<v>.*?)\]')
      $existingArgs = @()
      if ($am.Success) {
        foreach ($a in [regex]::Matches($am.Groups['v'].Value, '"(?<v>(?:[^"\\]|\\.)*)"|''(?<v>[^'']*)''')) {
          $existingArgs += (($a.Groups['v'].Value -replace '\\\\', '/' -replace '\\', '/').Trim())
        }
      }
      if (($existingCmd -ieq $cmdNorm) -and ((@($existingArgs) -join ([char]31)) -ieq $argNorm)) {
        Write-UabsOk ('Grok MCP unchanged (already correct): ' + $Name)
        return
      }
      if ($existingCmd -ieq $cmdNorm) {
        Write-UabsWarn ('Grok MCP args drifted, rewriting: ' + $Name + '  was [' + (@($existingArgs) -join ' ') + ']')
      }
    }
  }

  if (Test-Path -LiteralPath $configPath) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bak = $configPath + '.before-uabs-' + $Name + '-' + $ts + '.bak'
    Copy-Item -LiteralPath $configPath -Destination $bak -Force
  }

  $nameEsc = [regex]::Escape($Name)
  $q = [char]39
  $pat1 = '(?ms)^[ \t]*\[mcp_servers\.(?:' + $nameEsc + '|"' + $nameEsc + '|' + $q + $nameEsc + $q + ')\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)'
  $pat2 = '(?ms)^[ \t]*\[mcp_servers\.' + $nameEsc + '\.env\][ \t]*\r?\n.*?(?=^[ \t]*\[|\z)'
  $content = [regex]::Replace([string]$content, $pat1, '')
  $content = [regex]::Replace([string]$content, $pat2, '')
  $content = [regex]::Replace([string]$content, '(\r?\n){3,}', "`r`n`r`n").Trim()

  $cmd = $Command.Replace('\', '/')
  $argsToml = ''
  if ($ArgList -and $ArgList.Count -gt 0) {
    $parts = foreach ($a in $ArgList) { '"' + ($a -replace '\\', '/') + '"' }
    $argsToml = ($parts -join ', ')
  }

  $nl = "`r`n"
  $block = '[mcp_servers.' + $Name + ']' + $nl
  $block += 'command = "' + $cmd + '"' + $nl
  $block += 'args = [' + $argsToml + ']' + $nl
  $block += 'enabled = true' + $nl
  $block += 'startup_timeout_sec = ' + $Startup + $nl
  $block += 'tool_timeout_sec = ' + $Tool + $nl

  if ($EnvMap -and $EnvMap.Count -gt 0) {
    $block += $nl + '[mcp_servers.' + $Name + '.env]' + $nl
    foreach ($k in $EnvMap.Keys) {
      $v = [string]$EnvMap[$k]
      if ($v -match '^%(.+)%$') {
        $en = $Matches[1]
        $ev = [Environment]::GetEnvironmentVariable($en, 'User')
        if (-not $ev) { $ev = [Environment]::GetEnvironmentVariable($en, 'Process') }
        if ($ev) { $v = $ev }
      }
      $block += $k + ' = "' + ($v.Replace('\', '/')) + '"' + $nl
    }
  }

  if ($content.Length -gt 0) {
    $new = $content.TrimEnd() + $nl + $nl + $block.Trim() + $nl
  } else {
    $new = $block.Trim() + $nl
  }
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($configPath, $new, $enc)
  Write-UabsOk ('Grok MCP: ' + $Name)
}

function Copy-UabsRobo([string]$From, [string]$To) {
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  & robocopy $From $To /E /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
  $code = $LASTEXITCODE
  if ($code -ge 8) {
    throw ('robocopy failed exit=' + $code + ' from=' + $From + ' to=' + $To)
  }
}

function Sync-UabsOptionalSkills {
  <# Opt-in skills never join the default index. Install one only when
     requested; afterwards refresh it only where the user already has it,
     backing up a changed copy first. Returns the names it wrote. #>
  param([string]$SourceRoot, [string]$SkillsDir, [string]$Provider, [string[]]$Requested = @())
  $written = @()
  foreach ($opt in @(Get-ChildItem -LiteralPath $SourceRoot -Directory -ErrorAction SilentlyContinue)) {
    $target = Join-Path $SkillsDir $opt.Name
    $present = Test-Path -LiteralPath (Join-Path $target 'SKILL.md') -PathType Leaf
    if (-not $present -and $Requested -notcontains $opt.Name) { continue }
    if ($present -and (Get-UabsTreeDigest $target -Ordinal) -ceq (Get-UabsTreeDigest $opt.FullName -Ordinal)) { continue }
    if ($present) { Copy-UabsRobo -From $target -To (Join-Path (Get-UabsStateRoot) ('backups\optional-skill-' + $Provider + '-' + $opt.Name + '-' + [guid]::NewGuid().ToString('N'))) }
    Copy-UabsRobo -From $opt.FullName -To $target
    Write-UabsOk ("${Provider}: optional skill " + $opt.Name + $(if ($present) { ' refreshed' } else { ' installed' }))
    $written += $opt.Name
  }
  return $written
}

function Get-UabsPackCatalog([string]$PackRoot) {
  $path = Join-Path $PackRoot 'BUNDLED-TOOLS\PACKS.json'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
  $doc = [IO.File]::ReadAllText($path) | ConvertFrom-Json
  if ($doc.schema -ne 1 -or -not $doc.packs) { throw ('Invalid pack catalog: ' + $path) }
  return $doc
}

function Find-UabsPackEvidence {
  <# Signs on this machine that a pack's subject is installed or used. Read-only.
     Roots are parameters so tests can point detection at fixtures. #>
  param(
    $Detect,
    [string[]]$SteamLibraries,
    [string]$DocumentsRoot = [Environment]::GetFolderPath('MyDocuments'),
    [string]$AppDataRoot = $env:APPDATA,
    [switch]$SkipRegistry
  )
  $found = New-Object System.Collections.Generic.List[string]
  if (-not $Detect) { return @() }
  if ($null -eq $SteamLibraries) {
    $SteamLibraries = @()
    $steam = $null
    if (-not $SkipRegistry) {
      try { $steam = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -Name SteamPath -ErrorAction Stop).SteamPath } catch { $steam = $null }
    }
    if ($steam) {
      $steam = $steam.Replace('/', '\')
      $SteamLibraries += $steam
      $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
      if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        foreach ($m in [regex]::Matches([IO.File]::ReadAllText($vdf), '"path"\s+"([^"]+)"')) {
          $SteamLibraries += $m.Groups[1].Value.Replace('\\', '\')
        }
      }
    }
  }
  foreach ($lib in @($SteamLibraries | Where-Object { $_ } | Select-Object -Unique)) {
    foreach ($id in @($Detect.steam_appids)) {
      if (Test-Path -LiteralPath (Join-Path $lib ('steamapps\appmanifest_' + $id + '.acf')) -PathType Leaf) { $found.Add('steam app ' + $id) }
    }
  }
  if ($DocumentsRoot) {
    foreach ($name in @($Detect.my_games)) {
      if ($name -and (Test-Path -LiteralPath (Join-Path $DocumentsRoot ('My Games\' + $name)) -PathType Container)) { $found.Add('My Games\' + $name) }
    }
  }
  if ($AppDataRoot) {
    foreach ($game in @($Detect.vortex_games)) {
      if ($game -and (Test-Path -LiteralPath (Join-Path $AppDataRoot ('Vortex\' + $game)) -PathType Container)) { $found.Add('Vortex ' + $game) }
    }
  }
  foreach ($var in @($Detect.env)) {
    if (-not $var) { continue }
    $value = [Environment]::GetEnvironmentVariable($var, 'Process')
    if (-not $value -and -not $SkipRegistry) { $value = [Environment]::GetEnvironmentVariable($var, 'User') }
    if ($value -and (Test-Path -LiteralPath $value)) { $found.Add($var) }
  }
  if ($Detect.gog_game_name -and -not $SkipRegistry) {
    foreach ($key in @(Get-ChildItem -Path 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games' -ErrorAction SilentlyContinue)) {
      $name = $null
      try { $name = (Get-ItemProperty -LiteralPath $key.PSPath -Name gameName -ErrorAction Stop).gameName } catch { $name = $null }
      if ($name -and $name -like ('*' + $Detect.gog_game_name + '*')) { $found.Add('GOG ' + $name) }
    }
  }
  return @($found | Select-Object -Unique)
}

function Resolve-UabsPackSelection {
  <# Decide which packs install. Precedence: -ExcludePacks, -Packs, a choice
     remembered from an earlier explicit run, then evidence on this machine.
     Only explicit choices are remembered; detection runs again every time,
     so installing the game later turns its pack on by itself. #>
  param(
    [string]$PackRoot,
    [string[]]$Requested = @(),
    [string[]]$Excluded = @(),
    [string]$StatePath = (Join-Path (Get-UabsStateRoot) 'packs.json'),
    [hashtable]$EvidenceArgs = @{}
  )
  $catalog = Get-UabsPackCatalog -PackRoot $PackRoot
  $result = [ordered]@{ Enabled=@(); Disabled=@(); Reasons=[ordered]@{}; ExcludedSkills=@(); DisabledComponents=@(); Catalog=$catalog }
  if (-not $catalog) { return [pscustomobject]$result }
  $names = @($catalog.packs.PSObject.Properties.Name)
  foreach ($n in @($Requested) + @($Excluded)) {
    if ($n -and $names -notcontains $n) { throw ("Unknown pack '" + $n + "'. Available: " + ($names -join ', ')) }
  }
  $remembered = @{}
  if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
    try {
      $doc = [IO.File]::ReadAllText($StatePath) | ConvertFrom-Json
      foreach ($p in @($doc.packs.PSObject.Properties)) { $remembered[$p.Name] = [bool]$p.Value.enabled }
    } catch { Write-UabsWarn ('pack choices unreadable; detecting again: ' + $_.Exception.Message) }
  }
  $changed = $false
  foreach ($name in $names) {
    $pack = $catalog.packs.$name
    if ($Excluded -contains $name) { $on = $false; $why = 'excluded (-ExcludePacks)'; if ($remembered[$name] -ne $false) { $remembered[$name] = $false; $changed = $true } }
    elseif ($Requested -contains $name) { $on = $true; $why = 'requested (-Packs)'; if ($remembered[$name] -ne $true) { $remembered[$name] = $true; $changed = $true } }
    elseif ($remembered.ContainsKey($name)) { $on = $remembered[$name]; $why = 'your earlier choice' }
    else {
      $evidence = @(Find-UabsPackEvidence -Detect $pack.detect @EvidenceArgs)
      $on = $evidence.Count -gt 0
      $why = if ($on) { 'found ' + ($evidence -join ', ') } else { 'nothing found on this machine' }
    }
    $result.Reasons[$name] = $why
    if ($on) { $result.Enabled += $name } else {
      $result.Disabled += $name
      $result.ExcludedSkills += @($pack.skills)
      $result.DisabledComponents += @($pack.components)
    }
  }
  if ($changed) {
    $out = [ordered]@{ schema = 1; packs = [ordered]@{} }
    foreach ($k in @($remembered.Keys | Sort-Object)) { $out.packs[$k] = [ordered]@{ enabled = $remembered[$k] } }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $StatePath) | Out-Null
    [IO.File]::WriteAllText($StatePath, ($out | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding $false))
  }
  return [pscustomobject]$result
}

function Update-UabsInstructionPacks {
  <# Keep pack text in a provider instruction file in step with the selection.
     Pack blocks are marked so they can be refreshed or removed. Older bundles
     wrote a long Skyrim section unmarked; an exact copy of one is ours, so it is
     replaced by the provider's short general template and the marked block.
     Anything else in the file belongs to the user and is left alone. #>
  param(
    [string]$Path,
    [string]$PackRoot,
    [string[]]$Enabled = @(),
    [string]$GeneralTemplate
  )
  $catalog = Get-UabsPackCatalog -PackRoot $PackRoot
  if (-not $catalog) { return $false }
  $exists = Test-Path -LiteralPath $Path -PathType Leaf
  $pre = if ($exists) { [IO.File]::ReadAllText($Path) } else { '' }
  $bom = $false
  if ($exists) { $b = [IO.File]::ReadAllBytes($Path); $bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) }
  $nl = if ($pre -match "`r`n") { "`r`n" } else { "`n" }
  $text = [regex]::Replace($pre, '(?ms)^[ \t]*<!-- UABS-PACK:([a-z0-9-]+) -->[ \t]*\r?\n.*?^[ \t]*<!-- /UABS-PACK:\1 -->[ \t]*(?:\r?\n|$)', '')
  $legacyHit = $false
  foreach ($name in @($catalog.packs.PSObject.Properties.Name)) {
    $legacyDir = Join-Path $PackRoot ('BUNDLED-TOOLS\packs\' + $name + '\legacy')
    foreach ($h in @(Get-ChildItem -LiteralPath $legacyDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
      $owned = ([IO.File]::ReadAllText($h.FullName)).Trim()
      if (-not $owned) { continue }
      $lines = @($owned -split '\r?\n' | ForEach-Object { [regex]::Escape($_) })
      $rx = '(?m)^' + ($lines -join '\r?\n') + '(?=\r?$)(?:\r?\n)?'
      if ([regex]::IsMatch($text, $rx)) { $text = [regex]::Replace($text, $rx, ''); $legacyHit = $true }
    }
  }
  $text = $text.Trim("`r", "`n")
  $head = ''
  if ($GeneralTemplate -and (Test-Path -LiteralPath $GeneralTemplate -PathType Leaf)) {
    $general = (([IO.File]::ReadAllText($GeneralTemplate)).TrimStart([char]0xFEFF).Trim()) -replace '\r?\n', $nl
    if ($text.StartsWith($general, [StringComparison]::Ordinal)) {
      $head = $general; $text = $text.Substring($general.Length).Trim("`r", "`n")
    } elseif ($legacyHit -and $text.IndexOf($general, [StringComparison]::Ordinal) -lt 0) {
      $head = $general
    }
  }
  $blocks = @()
  foreach ($name in @($Enabled)) {
    $rel = [string]$catalog.packs.$name.instructions
    if (-not $rel) { continue }
    $src = Join-Path $PackRoot ($rel.Replace('/', '\'))
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { throw ('pack instructions missing: ' + $src) }
    $body = ([IO.File]::ReadAllText($src)).Trim() -replace '\r?\n', $nl
    $blocks += ('<!-- UABS-PACK:' + $name + ' -->' + $nl + $body + $nl + '<!-- /UABS-PACK:' + $name + ' -->')
  }
  # Provider head, then pack blocks, then everything else: the bundle preamble
  # is appended after this step and re-appended at the end by later installs.
  $parts = @($(if ($head) { $head })) + @($blocks) + @($(if ($text) { $text }))
  # Only the text built here uses $nl. The rest keeps its bytes: the preamble
  # writer appends LF text to CRLF files, and normalizing the whole file made
  # the two writers convert it back and forth on every install.
  $new = if ($parts.Count) { ($parts -join ($nl + $nl)) + $nl } else { '' }
  if ($new -ceq $pre) { return $false }
  # Nothing of ours was there and nothing is added: never rewrite user text
  # just to normalise its whitespace.
  if (-not $legacyHit -and -not $blocks.Count -and $pre -notmatch '<!-- UABS-PACK:') { return $false }
  if ($exists) { Copy-Item -LiteralPath $Path -Destination ($Path + '.before-pack-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.bak') -Force }
  else { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null }
  [IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding $bom))
  return $true
}

function Get-UabsHermesManagedProfiles {
  <# Hermes named profiles that this bundle manages: they have their own skills
     folder and carry the bundle soul. A profile with its own persona (for
     example a role-play gateway) is not returned. #>
  param([string]$HermesHome, [string]$SoulFile, [switch]$RequireSkills)
  $mark = (([IO.File]::ReadAllText($SoulFile)).Trim() -split '\r?\n')[0]
  foreach ($pf in @(Get-ChildItem -LiteralPath (Join-Path $HermesHome 'profiles') -Directory -ErrorAction SilentlyContinue)) {
    $soul = Join-Path $pf.FullName 'SOUL.md'
    if ($RequireSkills -and -not (Test-Path -LiteralPath (Join-Path $pf.FullName 'skills') -PathType Container)) { continue }
    if (-not (Test-Path -LiteralPath $soul -PathType Leaf)) { continue }
    if (-not ([IO.File]::ReadAllText($soul)).Contains($mark)) { continue }
    $pf
  }
}

function Move-UabsSkillsAside {
  <# Move named skill folders out of an indexed skills root into a backup.
     Reversible, unlike deletion: used for pack skills a profile should not
     index when no ledger proves the copy is unmodified. #>
  param([string]$SkillsDir, [string[]]$Names, [string]$Label)
  $moved = @()
  $dest = $null
  foreach ($n in @($Names | Select-Object -Unique)) {
    $src = Join-Path $SkillsDir $n
    if (-not (Test-Path -LiteralPath (Join-Path $src 'SKILL.md') -PathType Leaf)) { continue }
    if (-not $dest) {
      $dest = Join-Path (Get-UabsStateRoot) ('backups\' + $Label + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
      New-Item -ItemType Directory -Force -Path $dest | Out-Null
    }
    Move-Item -LiteralPath $src -Destination (Join-Path $dest $n)
    $moved += $n
  }
  return [pscustomobject]@{ Moved = $moved; Backup = $dest }
}

function Get-UabsProfileRoot([string]$Override) {
  if ($Override) { return [IO.Path]::GetFullPath($Override) }
  if ($env:UABS_PROFILE_ROOT) { return [IO.Path]::GetFullPath($env:UABS_PROFILE_ROOT) }
  return (Join-Path $env:USERPROFILE '.uabs\profile')
}

function Get-UabsProfileText {
  <# PROFILE.md (the user's own preferences) plus MACHINE-MAP.md (generated
     paths for this PC). Lives outside every repository. Capped: this text
     rides on every request of every provider. #>
  param([string]$Root, [int]$MaxChars = 6000)
  $parts = @()
  foreach ($name in 'PROFILE.md', 'MACHINE-MAP.md') {
    $p = Join-Path $Root $name
    if (Test-Path -LiteralPath $p -PathType Leaf) {
      $t = ([IO.File]::ReadAllText($p)).TrimStart([char]0xFEFF).Trim()
      if ($t) { $parts += $t }
    }
  }
  $text = ($parts -join "`n`n")
  if ($text.Length -gt $MaxChars) {
    throw ("Profile text is {0} characters; the cap is {1} because it is sent with every request. Shorten {2}." -f $text.Length, $MaxChars, (Join-Path $Root 'PROFILE.md'))
  }
  return $text
}

function Update-UabsInstructionProfile {
  <# One marked UABS-PROFILE block per instruction file: refreshed when the
     profile changes, removed when it is empty. It sits after any pack block. #>
  param([string]$Path, [string]$Text)
  $exists = Test-Path -LiteralPath $Path -PathType Leaf
  if (-not $exists -and -not $Text) { return $false }
  $pre = if ($exists) { [IO.File]::ReadAllText($Path) } else { '' }
  if (-not $Text -and $pre -notmatch '<!-- UABS-PROFILE -->') { return $false }
  $bom = $false
  if ($exists) { $b = [IO.File]::ReadAllBytes($Path); $bom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) }
  $nl = if ($pre -match "`r`n") { "`r`n" } else { "`n" }
  $knownProfiles = @()
  if ($Text) { $knownProfiles += $Text.Trim() }
  foreach ($m in [regex]::Matches($pre, '(?ms)^<!--[ \t]*UABS-PROFILE[ \t]*-->\r?\n(?<text>.*?)^<!--[ \t]*/UABS-PROFILE[ \t]*-->')) {
    $knownProfiles += $m.Groups['text'].Value.Trim()
  }
  # Take the blank line that separated the block with it, so removal restores
  # the surrounding text exactly.
  $body = [regex]::Replace($pre, '(?ms)(?:\r?\n)?^[ \t]*<!-- UABS-PROFILE -->[ \t]*\r?\n.*?^[ \t]*<!-- /UABS-PROFILE -->[ \t]*(?:\r?\n|$)', '').Trim("`r", "`n")
  # Retire only a complete known copy carrying the pack's orphan closing tag.
  # Older manual copies sometimes omitted the heading's Markdown prefix.
  foreach ($known in $knownProfiles) {
    foreach ($candidate in @($known, ($known -replace '^## (?=Operator profile \(private; this PC only\))', ''))) {
      $literalLines = @($candidate -split '\r?\n' | ForEach-Object { [regex]::Escape($_) })
      $duplicate = '(?m)^' + ($literalLines -join '\r?\n') + '\r?\n[ \t]*<!-- /UABS-PROFILE -->[ \t]*(?:\r?\n|$)'
      $body = [regex]::Replace($body, $duplicate, '').Trim("`r", "`n")
    }
  }
  $new = $body
  if ($Text) {
    $block = '<!-- UABS-PROFILE -->' + $nl + ($Text.Trim() -replace '\r?\n', $nl) + $nl + '<!-- /UABS-PROFILE -->'
    $packs = [regex]::Matches($body, '(?m)^[ \t]*<!-- /UABS-PACK:[a-z0-9-]+ -->[ \t]*(?=\r?$)')
    if ($packs.Count) {
      $at = $packs[$packs.Count - 1].Index + $packs[$packs.Count - 1].Length
      $new = $body.Substring(0, $at).TrimEnd() + $nl + $nl + $block + $nl + $nl + $body.Substring($at).Trim("`r", "`n")
    } else {
      $new = $block + $(if ($body) { $nl + $nl + $body } else { '' })
    }
  }
  $new = $new.Trim("`r", "`n") + $nl
  if ($new -ceq $pre) { return $false }
  if ($exists) { Copy-Item -LiteralPath $Path -Destination ($Path + '.before-profile-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.bak') -Force }
  else { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null }
  [IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding $bom))
  return $true
}

function Get-UabsTreeDigest([string]$Path, [switch]$Ordinal) {
  $root = (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\') + '\'
  $rows = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Force -ErrorAction Stop |
    ForEach-Object { $_.FullName.Substring($root.Length).Replace('\','/') + '=' + (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash })
  # New portable fingerprints use ordinal sorting; keep old ledger semantics.
  if ($Ordinal) { [string[]]$rows = $rows; [Array]::Sort($rows, [StringComparer]::Ordinal) }
  else { $rows = @($rows | Sort-Object) }
  $bytes = [Text.Encoding]::UTF8.GetBytes(($rows -join "`n"))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','') } finally { $sha.Dispose() }
}

function Get-UabsPreservedSkillNames([string]$Provider, [string]$SkillsDir) {
  # Local, explicit ownership exceptions. A changed digest requires review;
  # never silently accept arbitrary drift or overwrite an approved local copy.
  $path = Join-Path (Get-UabsStateRoot) 'skill-overrides.json'
  if (-not $Provider -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
  $doc = [IO.File]::ReadAllText($path) | ConvertFrom-Json
  if ($doc.schema -ne 1 -or -not $doc.providers) { throw ('Invalid skill override registry: ' + $path) }
  $entry = $doc.providers.PSObject.Properties[$Provider]
  if (-not $entry) { return }
  foreach ($skill in $entry.Value.PSObject.Properties) {
    if ($skill.Name -notmatch '^[a-z0-9][a-z0-9-]*$' -or
        [string]$skill.Value.digest -notmatch '^[a-fA-F0-9]{64}$' -or
        [string]::IsNullOrWhiteSpace([string]$skill.Value.reason)) {
      throw ('Invalid local skill override for ' + $Provider + ': ' + $skill.Name)
    }
    $dir = Join-Path $SkillsDir $skill.Name
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'SKILL.md') -PathType Leaf) -or
        (Get-UabsTreeDigest $dir -Ordinal) -ne $skill.Value.digest) {
      throw ('Local skill override changed or missing: ' + $Provider + '/' + $skill.Name + '. Review before syncing; registry: ' + $path)
    }
    $skill.Name
  }
}

function Sync-UabsProviderSkills(
  [string]$From,
  [string]$To,
  [string]$Provider = '',
  [string[]]$ExcludeNames = @()
) {
  <#
    Bundle-owned provider skills are content-authoritative.

    Deterministic release archives normalize timestamps, so metadata cannot
    prove that an installed skill has the current bytes. Each bundle-owned
    skill is therefore copied into a fresh sibling staging directory, verified
    by SHA-256, swapped into place, and verified again. Only the named
    bundle-owned skill directory is replaced; unrelated user-created sibling
    skills are never mirrored or deleted.
  #>
  if (-not (Test-Path -LiteralPath $From -PathType Container)) {
    throw ('provider skill source missing: ' + $From)
  }
  $preserved = @(Get-UabsPreservedSkillNames -Provider $Provider -SkillsDir $To)
  $ExcludeNames = @($ExcludeNames) + $preserved
  foreach ($name in $preserved) { Write-UabsOk ($Provider + ': verified local skill override preserved: ' + $name) }
  New-Item -ItemType Directory -Force -Path $To | Out-Null

  # Clean interrupted V8 staging only. The exact prefix is bundle-owned.
  Get-ChildItem -LiteralPath $To -Directory -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '.uabs-skill-stage-*' -or $_.Name -like '.uabs-skill-backup-*' } |
    Remove-Item -Recurse -Force

  $currentNames = @(Get-ChildItem -LiteralPath $From -Directory -Force |
    Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } |
    Where-Object { $ExcludeNames -notcontains $_.Name } |
    Select-Object -ExpandProperty Name)
  $ledgerPath = $null
  if ($Provider) {
    $ledgerDir = Join-Path (Get-UabsStateRoot) 'managed-skills'
    New-Item -ItemType Directory -Force -Path $ledgerDir | Out-Null
    $ledgerPath = Join-Path $ledgerDir ($Provider.ToLowerInvariant() + '.json')
    if (Test-Path -LiteralPath $ledgerPath -PathType Leaf) {
      try {
        $previous = [IO.File]::ReadAllText($ledgerPath) | ConvertFrom-Json
        foreach ($entry in @($previous.skills)) {
          if ($preserved -contains [string]$entry.name) { continue }
          if ($currentNames -contains [string]$entry.name) { continue }
          $retired = Join-Path $To ([string]$entry.name)
          if (-not (Test-Path -LiteralPath $retired -PathType Container)) { continue }
          if ((Get-UabsTreeDigest $retired) -ceq [string]$entry.digest) {
            Remove-Item -LiteralPath $retired -Recurse -Force
            Write-UabsOk ('retired managed skill removed: ' + $entry.name)
          } else {
            Write-UabsWarn ('retired skill was modified; preserved: ' + $retired)
          }
        }
      } catch { Write-UabsWarn ('managed-skill ledger unreadable; no retired skills removed: ' + $_.Exception.Message) }
    }
  }

  New-Item -ItemType Directory -Force -Path $To | Out-Null
  $workRoot = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($To).TrimEnd('\'))) '.uabs-skill-work'
  New-Item -ItemType Directory -Force -Path $workRoot | Out-Null
  # Older installers staged inside the skills root. Restore an orphaned backup
  # whose skill is missing (an interrupted swap); drop every other leftover.
  foreach ($left in @(Get-ChildItem -LiteralPath $To -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\.uabs-skill-(stage|backup)-(.+)-[0-9a-f]{32}$' })) {
    $owner = Join-Path $To $Matches[2]
    if ($Matches[1] -eq 'backup' -and -not (Test-Path -LiteralPath $owner)) { Move-Item -LiteralPath $left.FullName -Destination $owner; Write-UabsWarn ('restored interrupted skill swap: ' + $Matches[2]) }
    else { Remove-Item -LiteralPath $left.FullName -Recurse -Force }
  }

  foreach ($skillDir in @(Get-ChildItem -LiteralPath $From -Directory -Force -ErrorAction Stop)) {
    if ($ExcludeNames -contains $skillDir.Name) { continue }
    $sourceSkillMd = Join-Path $skillDir.FullName 'SKILL.md'
    if (-not (Test-Path -LiteralPath $sourceSkillMd -PathType Leaf)) { continue }
    if (($skillDir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
      throw ('provider skill source is a reparse point: ' + $skillDir.FullName)
    }
    foreach ($sourceItem in @(Get-ChildItem -LiteralPath $skillDir.FullName -Recurse -Force -ErrorAction Stop)) {
      if (($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw ('provider skill source contains a reparse point: ' + $sourceItem.FullName)
      }
    }

    $destSkill = Join-Path $To $skillDir.Name
    # Identical bytes already installed: rewriting them made every skill vanish
    # and reappear in running apps on each install.
    if ((Test-Path -LiteralPath $destSkill -PathType Container) -and
        -not ((Get-Item -LiteralPath $destSkill -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -and
        (Get-UabsTreeDigest $destSkill -Ordinal) -ceq (Get-UabsTreeDigest $skillDir.FullName -Ordinal)) { continue }
    $nonce = [Guid]::NewGuid().ToString('N')
    # Stage beside the skills root, not inside it: apps index every folder in
    # the root, so a staging copy showed up as a second skill mid-install.
    $stage = Join-Path $workRoot ('stage-' + $skillDir.Name + '-' + $nonce)
    $backup = Join-Path $workRoot ('backup-' + $skillDir.Name + '-' + $nonce)
    $movedExisting = $false

    try {
      New-Item -ItemType Directory -Force -Path $stage | Out-Null
      $sourceRoot = $skillDir.FullName.TrimEnd('\') + '\'
      $expected = @{}

      foreach ($sourceDir in @(Get-ChildItem -LiteralPath $skillDir.FullName -Recurse -Directory -Force -ErrorAction Stop)) {
        $relDir = $sourceDir.FullName.Substring($sourceRoot.Length)
        if ($relDir) { New-Item -ItemType Directory -Force -Path (Join-Path $stage $relDir) | Out-Null }
      }

      foreach ($srcFile in @(Get-ChildItem -LiteralPath $skillDir.FullName -Recurse -File -Force -ErrorAction Stop)) {
        $rel = $srcFile.FullName.Substring($sourceRoot.Length)
        $expected[$rel] = (Get-FileHash -LiteralPath $srcFile.FullName -Algorithm SHA256).Hash
        $stageFile = Join-Path $stage $rel
        $stageParent = Split-Path -Parent $stageFile
        if ($stageParent) { New-Item -ItemType Directory -Force -Path $stageParent | Out-Null }
        Copy-Item -LiteralPath $srcFile.FullName -Destination $stageFile -Force
        $stageHash = (Get-FileHash -LiteralPath $stageFile -Algorithm SHA256).Hash
        if ($stageHash -cne $expected[$rel]) {
          throw ('provider skill staging hash mismatch: ' + $skillDir.Name + '\' + $rel +
            ' expected=' + $expected[$rel] + ' actual=' + $stageHash)
        }
      }

      if (-not (Test-Path -LiteralPath (Join-Path $stage 'SKILL.md') -PathType Leaf)) {
        throw ('provider skill staging missing SKILL.md: ' + $skillDir.Name)
      }

      if (Test-Path -LiteralPath $destSkill) {
        $destItem = Get-Item -LiteralPath $destSkill -Force
        if (($destItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
          throw ('refusing provider skill target that is a reparse point: ' + $destSkill)
        }
        Move-Item -LiteralPath $destSkill -Destination $backup
        $movedExisting = $true
      }

      Move-Item -LiteralPath $stage -Destination $destSkill

      foreach ($rel in @($expected.Keys)) {
        $dstFile = Join-Path $destSkill $rel
        if (-not (Test-Path -LiteralPath $dstFile -PathType Leaf)) {
          throw ('provider skill sync missing file after swap: ' + $skillDir.Name + '\' + $rel)
        }
        $actualHash = (Get-FileHash -LiteralPath $dstFile -Algorithm SHA256).Hash
        if ($actualHash -cne $expected[$rel]) {
          throw ('provider skill sync hash mismatch after swap: ' + $skillDir.Name + '\' + $rel +
            ' expected=' + $expected[$rel] + ' actual=' + $actualHash)
        }
      }
      $destRoot = $destSkill.TrimEnd('\') + '\'
      foreach ($dstFile in @(Get-ChildItem -LiteralPath $destSkill -Recurse -File -Force -ErrorAction Stop)) {
        $rel = $dstFile.FullName.Substring($destRoot.Length)
        if (-not $expected.ContainsKey($rel)) {
          throw ('provider skill sync left unexpected file after swap: ' + $skillDir.Name + '\' + $rel)
        }
      }

      if ($movedExisting -and (Test-Path -LiteralPath $backup)) {
        Remove-Item -LiteralPath $backup -Recurse -Force
        $movedExisting = $false
      }
    }
    catch {
      if ($movedExisting -and (Test-Path -LiteralPath $backup)) {
        if (Test-Path -LiteralPath $destSkill) {
          Remove-Item -LiteralPath $destSkill -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path -LiteralPath $destSkill)) {
          Move-Item -LiteralPath $backup -Destination $destSkill -ErrorAction SilentlyContinue
          $movedExisting = $false
        }
      }
      throw
    }
    finally {
      Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
      if (-not $movedExisting) {
        Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
      }
    }
  }

  if ($ledgerPath) {
    $records = @($currentNames | Sort-Object | ForEach-Object {
      $path = Join-Path $To $_
      [ordered]@{ name = $_; digest = Get-UabsTreeDigest $path }
    })
    $doc = [ordered]@{ schema = 1; provider = $Provider; skills = $records }
    $tmp = $ledgerPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
    [IO.File]::WriteAllText($tmp, (($doc | ConvertTo-Json -Depth 5) + "`n"), (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $ledgerPath -Force
  }
}

function Copy-UabsRoboSafe([string]$From, [string]$To, [string[]]$CriticalFiles = @()) {
  foreach ($rel in $CriticalFiles) {
    $destFile = Join-Path $To $rel
    if ((Test-Path -LiteralPath $destFile -PathType Leaf) -and (Test-UabsFileLocked $destFile)) {
      throw ('REFUSE overwrite locked file (MCP likely running): ' + $destFile + ' - stop the AI app or MCP process first, or skip this component.')
    }
  }
  Copy-UabsRobo -From $From -To $To
}

function Set-UabsGrokCompatCells {
  <#
    Turn off Grok's inheritance of Claude Code's hooks, MCP servers, and
    skills.

    Grok ships Claude-Code compatibility ON by default: it adopts
    ~/.claude/skills, ~/.claude/agents, ~/.claude/plugins (with their
    hooks/hooks.json, .mcp.json, and skill dirs), ~/.claude.json and
    ~/.claude/settings.json. Measured on grok-cli 1.0.4 (2026-08-15):

      - inherited Claude hooks cost 60.037s per turn (two Stop hooks at
        timeout 30, and Grok never closes a hook's stdin);
      - MCP startup cost 65s on the first turn of every session and
        attached ZERO tools - tool_count was 26 (the built-in count) in
        all 12 turns recorded, with 8 servers configured and with 0.

    Skills compat is also OFF as of v7.7.4. AIO already copies the pack
    into ~/.grok/skills. Leaving Claude skill scan ON duplicates native
    superpowers skills (systematic-debugging is the one that errors in
    the TUI) and surfaces claude-mem / other Claude plugin skills in
    Grok, which is how mcp-search rides in as an extra running MCP
    server. See GROK-MCP-TROUBLESHOOTING.md.
  #>
  param(
    [string]$ConfigPath = $null,
    [switch]$AllowMcp,
    [switch]$HooksOnly
  )
  if (-not $ConfigPath) {
    $grokDir = Get-UabsProviderHome -Provider Grok -Catalog (Get-UabsCatalog)
    $ConfigPath = Join-Path $grokDir 'config.toml'
  } else {
    $grokDir = Split-Path $ConfigPath -Parent
  }
  New-Item -ItemType Directory -Force -Path $grokDir | Out-Null

  $content = ''
  if (Test-Path -LiteralPath $ConfigPath) {
    $content = [IO.File]::ReadAllText($ConfigPath)
  }
  $original = $content
  $newline = if ($content.Contains("`r`n")) { "`r`n" } else { "`n" }
  # Patch only owned booleans. A hook-only repair must not change a user's
  # inherited MCPs, skills, rules, agents, or later tables.
  $cells = [ordered]@{ hooks = 'false' }
  if (-not $HooksOnly) {
    $cells['mcps'] = if ($AllowMcp) { 'true' } else { 'false' }
    $cells['skills'] = 'false'
  }
  $section = [regex]::Match($content, '(?m)^[ \t]*\[compat\.claude\][^\r\n]*(?:\r?\n(?![ \t]*\[)[^\r\n]*)*')
  $block = if ($section.Success) { $section.Value } else { '[compat.claude]' + $newline }
  foreach ($name in $cells.Keys) {
    $pattern = '(?m)^([ \t]*' + $name + '[ \t]*=[ \t]*)(true|false)([ \t]*(?:#[^\r\n]*)?)(?=\r?$)'
    # Preserve comments and unrelated keys, including future compatibility cells.
    if ([regex]::IsMatch($block, $pattern)) {
      $block = [regex]::Replace($block, $pattern, ('${1}' + $cells[$name] + '${3}'))
    } else {
      if ($block -match ('(?m)^[ \t]*' + $name + '[ \t]*=')) { throw "Grok compatibility cell '$name' is not a boolean; config left unchanged." }
      $block = $block.TrimEnd("`r", "`n") + $newline + $name + ' = ' + $cells[$name] + $newline
    }
  }
  if ($section.Success) {
    $content = $content.Substring(0, $section.Index) + $block + $content.Substring($section.Index + $section.Length)
  } else {
    $content = $content.TrimEnd("`r", "`n") + $newline + $newline + $block
  }
  # UTF-8 with NO BOM: PS 5.1's -Encoding utf8 emits a BOM, and a BOM makes the
  # first line unparseable TOML ("Invalid statement at line 1, column 1").
  if ($content -ne $original) {
    if (Test-Path -LiteralPath $ConfigPath) {
      Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.before-compat-' + (Get-Date -Format 'yyyyMMdd-HHmmssfff') + '.bak')
    }
    [System.IO.File]::WriteAllText($ConfigPath, $content, (New-Object System.Text.UTF8Encoding $false))
  }
  if ($HooksOnly) {
    Write-UabsOk 'Grok: Claude hook inheritance disabled; other compatibility settings preserved'
  } elseif ($AllowMcp) {
    Write-UabsOk 'Grok: Claude hook + skill inheritance disabled; MCP inheritance retained by request'
  } else {
    Write-UabsOk 'Grok: Claude hook + MCP + skill inheritance disabled'
  }
}

function Repair-UabsGrokImpeccableHook([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  if ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing a redirected Grok hook file.' }
  $before = [IO.File]::ReadAllText($Path)
  $doc = $before | ConvertFrom-Json
  $old = '[ ! -f ".grok/skills/impeccable/scripts/impeccable" ] || ".grok/skills/impeccable/scripts/impeccable" hook'
  # Both known global wrappers target a removed executable. Keep custom hooks;
  # current project-local Impeccable hook.mjs integrations have a different path.
  $new = 'if (Test-Path -LiteralPath ".grok/skills/impeccable/scripts/impeccable.cmd" -PathType Leaf) { & ".grok/skills/impeccable/scripts/impeccable.cmd" hook }'
  $changed = $false
  if (-not $doc.hooks) { return }
  foreach ($event in @('PostToolUse','Stop')) {
    $property = $doc.hooks.PSObject.Properties[$event]
    if (-not $property) { continue }
    $groups = @()
    foreach ($group in @($property.Value)) {
      $handlers = $group.PSObject.Properties['hooks']
      if (-not $handlers) { $groups += $group; continue }
      $keep = @(); $removed = $false
      foreach ($handler in @($handlers.Value)) {
        if ($handler.command -ceq $old -or $handler.command -ceq $new) {
          $removed = $true; $changed = $true
        } else { $keep += $handler }
      }
      if ($keep.Count -or -not $removed) { $handlers.Value = @($keep); $groups += $group }
    }
    $property.Value = @($groups)
  }
  if (-not $changed) { return }
  $after = ($doc | ConvertTo-Json -Depth 100) + [Environment]::NewLine
  $null = $after | ConvertFrom-Json
  $bytes = [IO.File]::ReadAllBytes($Path)
  $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
  $backup = $Path + '.before-powershell-' + [Guid]::NewGuid().ToString('N') + '.bak'
  $temp = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
  try {
    [IO.File]::WriteAllText($temp, $after, (New-Object Text.UTF8Encoding $bom))
    [IO.File]::Replace($temp, $Path, $backup)
    if ([IO.File]::ReadAllText($Path) -cne $after) {
      Copy-Item -LiteralPath $backup -Destination $Path -Force
      throw 'Grok hook verification failed; original restored.'
    }
    Write-UabsOk 'Grok: retired obsolete global Impeccable launchers; original backed up'
  } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
}

function Repair-UabsCodexLegacyHooks {
  param([Parameter(Mandatory=$true)][string]$Path, [switch]$CheckOnly)
  # Codex supports native hooks.json now. Our zero-chore policy still uses
  # skills/native plugins there; old user-level executable gates must not
  # survive upgrades. Ownership is the FULL bundle script path, not a basename.
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
  if ((Get-Item -LiteralPath $Path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing a redirected Codex hook file.' }
  $before = [IO.File]::ReadAllText($Path)
  $doc = $before | ConvertFrom-Json
  $hookProperty = $doc.PSObject.Properties['hooks']
  if (-not $hookProperty -or -not $hookProperty.Value) { return }
  $root = (Join-Path (Get-UabsStateRoot) 'hooks').Replace('\','/').TrimEnd('/')
  $owned = '(?i)(?:^|[\s"''])' + [regex]::Escape($root) + '/(completeness_gate\.py|assumption_gate\.py|rtk_safe_hook\.py)(?=[\s"'']|$)'
  $impeccableUnix = '[ ! -f ".codex/skills/impeccable/scripts/impeccable" ] || ".codex/skills/impeccable/scripts/impeccable" hook'
  $impeccableWindows = 'if exist ".codex/skills/impeccable/scripts/impeccable.cmd" (".codex/skills/impeccable/scripts/impeccable.cmd" hook & exit /b)'
  # This legacy global pair targets an executable no longer shipped by the
  # skill. Current Impeccable uses opt-in project-local hook.mjs manifests;
  # do not manufacture global engine wiring or identify ownership by a label.
  $issues = @()
  foreach ($event in $hookProperty.Value.PSObject.Properties) {
    $groups = @()
    foreach ($group in @($event.Value)) {
      $handlers = $group.PSObject.Properties['hooks']
      if (-not $handlers) { $groups += $group; continue }
      $keep = @(); $removed = $false
      foreach ($handler in @($handlers.Value)) {
        $scriptName = $null
        foreach ($field in @('command','commandWindows','command_windows')) {
          $command = $handler.PSObject.Properties[$field]
          if ($command -and $command.Value -is [string] -and $command.Value.Replace('\','/') -match $owned) {
            $scriptName = $Matches[1]; break
          }
        }
        if (-not $scriptName -and $event.Name -in @('SessionStart','SubagentStart')) {
          $command = $handler.PSObject.Properties['command']
          if ($command -and $command.Value -is [string]) {
            $target = $command.Value.Trim().Trim('"',"'").Replace('/','\')
            $hookRoot = Join-Path (Split-Path -Parent $Path) 'hooks'
            foreach ($name in @('cbm-session-reminder','cbm-subagent-reminder')) {
              $expected = Join-Path $hookRoot $name
              if ($target -ieq $expected -and (Test-Path -LiteralPath $expected -PathType Leaf)) {
                $body = [IO.File]::ReadAllText($expected)
                $steers = ($body.Contains('CRITICAL - Code Discovery Protocol:') -and $body.Contains('run index_repository FIRST')) -or
                  ($name -eq 'cbm-subagent-reminder' -and $body.Contains('prefer codebase-memory-mcp tools'))
                if ($steers -and $body -notmatch '\|\|\s*(exit\s+0|return)\b') {
                  $scriptName = ($name + ' (unconditional legacy codebase-memory reminder)')
                }
              }
            }
          }
        }
        if ($scriptName) { $issues += ($event.Name + ': retired bundle executable hook ' + $scriptName); $removed = $true }
        else {
          $unix = $handler.PSObject.Properties['command']
          $legacyImpeccable = $false
          if ($handler.type -eq 'command' -and $unix -and $unix.Value -ceq $impeccableUnix) {
            foreach ($field in @('commandWindows','command_windows')) {
              $windows = $handler.PSObject.Properties[$field]
              if ($windows -and $windows.Value -ceq $impeccableWindows) {
                $legacyImpeccable = $true
              }
            }
          }
          if ($legacyImpeccable) {
            $issues += ($event.Name + ': retired obsolete global Impeccable executable hook'); $removed = $true
          } else {
            # Codex on Windows runs `cmd.exe /C "<command>"` unless commandWindows
            # is set, so a quoted extensionless bash script can never start.
            $posix = Get-UabsCodexPosixOnlyScript -Handler $handler -HookRoot (Join-Path (Split-Path -Parent $Path) 'hooks')
            if ($posix) {
              $bashDir = Get-UabsGitShellDirectory
              $bash = if ($bashDir) { Join-Path $bashDir 'bash.exe' } else { $null }
              if ($bash -and (Test-Path -LiteralPath $bash -PathType Leaf)) {
                $issues += ($event.Name + ': bash-only hook given a Windows command: ' + (Split-Path -Leaf $posix))
                $handler | Add-Member -NotePropertyName commandWindows -NotePropertyValue ('"' + $bash + '" "' + $posix.Replace('\','/') + '"') -Force
              } else {
                $issues += ($event.Name + ': bash-only hook cannot run on Windows without Git for Windows: ' + (Split-Path -Leaf $posix))
              }
            }
            $keep += $handler
          }
        }
      }
      if ($keep.Count -or -not $removed) { $handlers.Value = @($keep); $groups += $group }
    }
    $event.Value = @($groups)
  }
  $after = ($doc | ConvertTo-Json -Depth 100) + [Environment]::NewLine
  if ($issues.Count -and -not $CheckOnly -and ($after | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress) -cne ($before | ConvertFrom-Json | ConvertTo-Json -Depth 100 -Compress)) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191
    $nonce = [Guid]::NewGuid().ToString('N')
    $backup = $Path + '.before-retired-' + $nonce + '.bak'
    $temp = $Path + '.tmp-' + $nonce
    try {
      [IO.File]::WriteAllText($temp, $after, (New-Object Text.UTF8Encoding $bom))
      [IO.File]::Replace($temp, $Path, $backup)
      if ([IO.File]::ReadAllText($Path) -cne $after) {
        Copy-Item -LiteralPath $backup -Destination $Path -Force
        throw 'Codex hook retirement verification failed; original restored.'
      }
      Write-UabsOk ('Codex: repaired ' + $issues.Count + ' native hook handler(s); backup: ' + $backup)
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
  }
  $issues
}

function Get-UabsCodexPosixOnlyScript {
  <# Full path of the bash script a Codex handler runs when that handler has no
     Windows override and its command is just a (quoted) path to a shebang
     script inside <CODEX_HOME>\hooks; otherwise $null. Never executes it. #>
  param($Handler, [string]$HookRoot)
  if (-not $Handler -or $Handler.type -ne 'command') { return $null }
  foreach ($field in @('commandWindows','command_windows')) { if ($Handler.PSObject.Properties[$field]) { return $null } }
  $command = $Handler.PSObject.Properties['command']
  if (-not $command -or $command.Value -isnot [string]) { return $null }
  $target = $command.Value.Trim().Trim('"',"'").Replace('/','\')
  if (-not $target -or $target.IndexOfAny([IO.Path]::GetInvalidPathChars() + [char[]]'"*?<>|') -ge 0) { return $null }
  if ($target -match '\s' -and -not (Test-Path -LiteralPath $target -PathType Leaf)) { return $null }
  if (-not (Test-UabsPathWithin -Path $target -Root $HookRoot) -or [IO.Path]::GetExtension($target)) { return $null }
  if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { return $null }
  $first = @([IO.File]::ReadAllLines($target) | Select-Object -First 1)
  if ($first.Count -and $first[0] -match '^#!.*\b(ba)?sh\b') { return $target }
  return $null
}

function Get-UabsGrokHookIssues {
  param([Parameter(Mandatory=$true)]$Inspection, [string]$HooksDir)
  # inspect lists discovered hooks even when disabled. Consult the effective
  # compatibility cell before treating a discovered Claude hook as active.
  $cell = @($Inspection.externalCompat.cells | Where-Object { $_.vendor -eq 'claude' -and $_.surface -eq 'hooks' })
  if ($cell.Count -ne 1) { throw 'Grok inspect did not report its effective Claude hooks compatibility cell.' }
  $managed = 'completeness_gate\.py|assumption_gate\.py|rtk_safe_hook\.py'
  if (-not $HooksDir) { $HooksDir = Join-Path (Get-UabsProviderHome -Provider Grok -Catalog (Get-UabsCatalog)) 'hooks' }
  $native = @($Inspection.hooks | Where-Object { ([string]$_.source.path).TrimEnd('\','/').Replace('/','\') -ieq $HooksDir.TrimEnd('\','/').Replace('/','\') })
  $inherited = @($Inspection.hooks | Where-Object { $_.target -match $managed -and $_.source.path -match '[\\/]\.claude(?:[\\/]|$)' })
  if (@($native | Where-Object { $_.target -match $managed }).Count -and $inherited.Count -and $cell[0].enabled -eq $true) {
    'Grok is inheriting duplicate Claude bundle hooks. Run TOOLS\Install-Completeness-Gate.ps1 -Providers Grok, then restart Grok.'
  }
  foreach ($hook in $native) {
    $parseErrors = $null; $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseInput($hook.target, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { 'Grok native ' + $hook.event + ' hook is not valid PowerShell. Run TOOLS\Install-Completeness-Gate.ps1 -Providers Grok; review custom hooks if it persists.' }
  }
}

# v7.5.0: SOUL + AIO preamble wiring. Appends (or replaces) the pack preamble
# block in an agent instruction file. Idempotent, backup first.
# Existing files keep their own encoding; writes are UTF-8 without BOM.
# v8.7.23: the HTML comment markers are gone. v7.5-v8.7 wrapped the block in
# `<!-- ULTIMATE-AI-STARTER-BUNDLE SOUL ... -->` so it could be found again;
# every provider paid for those lines on every request and they instructed
# nothing. Match complete owned content, never an opening line through EOF:
# users can append instructions after the block or reuse its opening sentence.
function Install-UabsPreambleBlock {
  param(
    [string]$Path,
    [string]$SoulFile,
    [string]$AioFile,
    [switch]$Force
  )
  if (-not (Test-Path -LiteralPath $SoulFile)) { throw 'preamble SOUL file missing: ' + $SoulFile }
  if (-not (Test-Path -LiteralPath $AioFile))  { throw 'preamble AIO file missing: ' + $AioFile }
  # ReadAllText, NOT Get-Content -Raw. On PS 5.1 Get-Content without -Encoding
  # decodes using the ANSI codepage (Windows-1252 here), so a UTF-8 em dash
  # (E2 80 94) comes back as three chars and gets written out as mojibake.
  # v7.5.6 swept the mojibake out of the pack files but left this read path,
  # so every install re-created it. ReadAllText honours the UTF-8 encoding.
  $soul = ([IO.File]::ReadAllText($SoulFile)).Trim()
  $aio  = ([IO.File]::ReadAllText($AioFile)).Trim()
  $nl = "`r`n"
  # Plain text: the soul, a blank line, then the operating contract.
  $block = $soul + $nl + $nl + $aio
  $dir = Split-Path $Path -Parent
  if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $pre = ''
  $origBom = $false
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    $pre = [IO.File]::ReadAllText($Path)
    $pb = [IO.File]::ReadAllBytes($Path)
    $origBom = ($pb.Length -ge 3 -and $pb[0] -eq 0xEF -and $pb[1] -eq 0xBB -and $pb[2] -eq 0xBF)
  }
  # Historic markers give an explicit end boundary. Unmarked content is ours
  # only if its entire text matches a source block (LF/CRLF both accepted).
  # Unknown/edited old text stays intact; a generic first line is not ownership.
  $legacy = '(?ms)^[ \t]*<!-- ULTIMATE-AI-STARTER-BUNDLE SOUL[^\r\n]*-->[ \t]*\r?\n.*?^[ \t]*<!-- /ULTIMATE-AI-STARTER-BUNDLE SOUL -->[ \t]*(?:\r?\n|$)'
  $remaining = [regex]::Replace($pre, $legacy, '')
  foreach ($owned in @($soul, $aio)) {
    if (-not $owned) { throw 'preamble source must not be empty' }
    $lines = @($owned -split '\r?\n' | ForEach-Object { [regex]::Escape($_) })
    $exact = '(?m)^' + ($lines -join '\r?\n') + '(?=\r?$)(?:\r?\n)?'
    $remaining = [regex]::Replace($remaining, $exact, '')
  }
  # The pack's own text changes between releases, and a machine wired by an
  # older release still carries that exact block - which the source match
  # above cannot see, because this release no longer ships it. Outgoing copies
  # are archived beside the soul source and stripped the same exact way, so
  # editing the pack's text converges installed machines instead of stacking a
  # second block on them. (Without this: old block stays, new one appends.)
  $histDir = Join-Path (Split-Path -Path $SoulFile -Parent) 'history'
  if (Test-Path -LiteralPath $histDir) {
    foreach ($h in @(Get-ChildItem -LiteralPath $histDir -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
      $archived = ([IO.File]::ReadAllText($h.FullName)).Trim()
      if (-not $archived) { continue }
      $lines = @($archived -split '\r?\n' | ForEach-Object { [regex]::Escape($_) })
      $exact = '(?m)^' + ($lines -join '\r?\n') + '(?=\r?$)(?:\r?\n)?'
      $remaining = [regex]::Replace($remaining, $exact, '')
    }
  }
  $remaining = $remaining.TrimEnd("`r", "`n")
  $new = if ($remaining) { $remaining + $nl + $nl + $block + $nl } else { $block + $nl }
    if (-not $Force -and $new -ceq $pre) {
      Write-UabsOk ('preamble unchanged (already current): ' + $Path)
      return
    }
    $ts = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
      Copy-Item -LiteralPath $Path -Destination ($Path + '.before-soul-' + $ts + '.bak') -Force
    }
    # UTF-8. A file that already had a BOM keeps it (ReadAllText strips it, so
    # write it back); a BOM-less file stays BOM-less. PS 5.1 -Encoding utf8 would
    # add one and break strict readers.
    [IO.File]::WriteAllText($Path, $new, (New-Object System.Text.UTF8Encoding $origBom))
    Write-UabsOk ('preamble wired: ' + $Path)
}

function Remove-UabsHermesForeignHarnessDirs {
  <#
  Hermes walks one level into a plugin directory that has no root plugin.yaml.
  Superpowers keeps the Hermes adapter at .hermes-plugin/plugin.yaml and ships
  sibling plugin.json files for other harnesses (including Muse). Hermes
  parses those siblings as its own plugins and warns on every gateway start.
  The shared BUNDLED-TOOLS tree must keep them: Kimi installs .kimi-plugin.
  Call this only on the Hermes git bridge or the installed Hermes plugin copy.
  #>
  param([Parameter(Mandatory)][string]$PluginRoot)
  if (-not (Test-Path -LiteralPath $PluginRoot -PathType Container)) { return }
  $full = [IO.Path]::GetFullPath($PluginRoot).TrimEnd('\')
  if ($full -match '(?i)[\\/]BUNDLED-TOOLS[\\/]plugins([\\/]|$)') {
    throw 'Refusing to strip foreign harness manifests inside BUNDLED-TOOLS\plugins'
  }
  $adapter = Join-Path $PluginRoot '.hermes-plugin\plugin.yaml'
  if (-not (Test-Path -LiteralPath $adapter -PathType Leaf)) { return }
  # Write-Output one name at a time. Returning the whole list makes PowerShell
  # hand the caller a single nested array, and @() then counts it as one.
  foreach ($name in @(Get-ChildItem -LiteralPath $PluginRoot -Directory -Force | Where-Object {
    $_.Name -like '.*-plugin' -and $_.Name -ne '.hermes-plugin'
  } | Select-Object -ExpandProperty Name)) {
    $dir = Join-Path $PluginRoot $name
    if (-not (Test-Path -LiteralPath (Join-Path $dir 'plugin.json') -PathType Leaf)) { continue }
    Remove-Item -LiteralPath $dir -Recurse -Force
    Write-Output $name
  }
}

function Update-UabsComponentLedger {
  <#
  Merge fetched or installed component facts into last-github-update.json.
  A one-component run used to replace the file, and PowerShell 5.1 ConvertTo-Json
  turned that single object into the whole document, so the sidecar claimed RTK
  was still the last fetched tag after the installer had moved on.
  installed_version is what this machine has. tag/file/url stay the last fetch.
  #>
  param(
    [Parameter(Mandatory)][object[]]$Updates,
    [string]$Path
  )
  if (-not $Path) { $Path = Join-Path (Get-UabsStateRoot) 'last-github-update.json' }
  $byId = @{}
  if (Test-Path -LiteralPath $Path -PathType Leaf) {
    try {
      $old = [IO.File]::ReadAllText($Path) | ConvertFrom-Json
      $items = @()
      if ($old.components) { $items = @($old.components) }
      elseif ($old.id) { $items = @($old) }
      foreach ($item in $items) {
        if (-not $item.id) { continue }
        $byId[[string]$item.id] = $item
      }
    } catch { }
  }
  foreach ($update in @($Updates)) {
    if (-not $update) { continue }
    $id = [string]$update.id
    if (-not $id) { continue }
    $prior = $byId[$id]
    $row = [ordered]@{ id = $id }
    foreach ($key in @('tag', 'file', 'url', 'error', 'installed_version')) {
      $incoming = $update.$key
      if ($incoming) { $row[$key] = [string]$incoming }
      elseif ($prior -and $prior.$key) { $row[$key] = [string]$prior.$key }
    }
    $byId[$id] = [pscustomobject]$row
  }
  $components = New-Object System.Collections.Generic.List[object]
  foreach ($id in @($byId.Keys | Sort-Object)) {
    $src = $byId[$id]
    $entry = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    $entry['id'] = [string]$id
    foreach ($key in @('tag', 'file', 'url', 'error', 'installed_version')) {
      $val = [string]$src.$key
      if ($val) { $entry[$key] = $val }
    }
    [void]$components.Add($entry)
  }
  $doc = New-Object 'System.Collections.Generic.Dictionary[string,object]'
  $doc['schema'] = 1
  $doc['updated_utc'] = [DateTime]::UtcNow.ToString('o')
  $doc['components'] = $components.ToArray()
  Add-Type -AssemblyName System.Web.Extensions
  $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
  $serializer.MaxJsonLength = 67108864
  $json = $serializer.Serialize($doc)
  $enc = New-Object System.Text.UTF8Encoding($false)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  [IO.File]::WriteAllText($Path, ($json + "`n"), $enc)
}

# ---------------------------------------------------------------------------
# Native bundled plugins (superpowers / ponytail) - shared helpers.
# The per-provider orchestration lives in INSTALL-AIO.ps1; these are the
# mechanism pieces: native command output capture, plugin-owned skill name
# discovery, the md5-guarded dedupe, a TOML plugin-section probe, the Hermes
# scan_on_install config fix, and a style-preserving marketplace.json edit.
# ---------------------------------------------------------------------------

function Get-UabsManifestFiles {
  # Source and extracted-archive gates audit the same shipped files. Never walk
  # ignored artifact/cache trees, which can contain old releases and huge logs.
  param([Parameter(Mandatory=$true)][string]$PackRoot)
  $manifest = [IO.File]::ReadAllText((Join-Path $PackRoot 'MANIFEST.json')) | ConvertFrom-Json
  $entries = @(if ($manifest.PSObject.Properties['files']) { $manifest.files } else { $manifest })
  if (-not $entries.Count) { throw 'Manifest has no files to audit.' }
  foreach ($entry in $entries) {
    $path = Join-Path $PackRoot ([string]$entry.path)
    if (-not (Test-UabsPathWithin -Path $path -Root $PackRoot)) { throw 'Manifest path escapes pack root.' }
    if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Item -LiteralPath $path }
  }
}

function Get-UabsNativeOutput {
  <#
  Run a native command and return its combined output as one string, without
  PowerShell 5.1 turning stderr lines into terminating ErrorRecords under the
  script-wide $ErrorActionPreference='Stop'. (Same disease Invoke-UabsNative
  cures; this variant is for DETECTION, where the output itself is needed.)
  #>
  param([string]$Exe, [string[]]$CmdArgs)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try { return (& $Exe @CmdArgs 2>&1 | Out-String) } finally { $ErrorActionPreference = $prevEap }
}

function Get-UabsNativeStdout {
  <#
  Stdout lines only. Stderr is dropped inside the pipeline, so it never reaches
  the host or the install transcript: Windows PowerShell 5.1 logs even `2>$null`
  stderr there, which is how the Store python stub's "Python was not found" and
  git's "no upstream configured" landed in every install log. $LASTEXITCODE is
  the command's own.
  #>
  param([string]$Exe, [string[]]$CmdArgs)
  $prevEap = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  try {
    return @(& $Exe @CmdArgs 2>&1 | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] } | ForEach-Object { [string]$_ })
  } finally { $ErrorActionPreference = $prevEap }
}

function Get-UabsGrokPluginList {
  <#
  Parse `grok plugin list --json`. Returns an array of plugin objects with
  name / repo_key / source / marketplace / path. Empty array on failure.
  #>
  param([string]$GrokExe)
  if (-not $GrokExe) { return @() }
  $out = Get-UabsNativeOutput -Exe $GrokExe -CmdArgs @('plugin', 'list', '--json')
  if ([string]::IsNullOrWhiteSpace($out)) { return @() }
  $start = $out.IndexOf('[')
  if ($start -lt 0) { $start = $out.IndexOf('{') }
  if ($start -lt 0) { return @() }
  try {
    $parsed = $out.Substring($start) | ConvertFrom-Json
    return @($parsed)
  } catch {
    return @()
  }
}

function Get-UabsAutostartTargetPaths {
  <#
  Pull every filesystem path out of an autostart command line or launcher
  script. A .vbs wrapper names two of them - the interpreter and the script it
  runs - and it is normally the SECOND one that has gone missing, so all of
  them are returned and the caller decides.

  Environment variables are expanded, because launcher scripts written by
  other tools use %LOCALAPPDATA% freely and an unexpanded string always
  "does not exist".
  #>
  param([string]$Text)
  $paths = New-Object System.Collections.Generic.List[string]
  if ([string]::IsNullOrWhiteSpace($Text)) { return @() }
  $rx = '(?<p>(?:[A-Za-z]:\\|%[A-Za-z_()0-9]+%\\)[^"''<>|\r\n]*?\.[A-Za-z0-9]{1,6})(?=["''\s,)]|$)'
  foreach ($m in [regex]::Matches($Text, $rx)) {
    $p = $m.Groups['p'].Value.Trim()
    try { $p = [Environment]::ExpandEnvironmentVariables($p) } catch { }
    if ($p -and -not $paths.Contains($p)) { [void]$paths.Add($p) }
  }
  return @($paths)
}

function Get-UabsAiAutostartEntries {
  <#
  Enumerate the boot-time autostarts that launch AI tooling: the per-user
  Startup folder plus the HKCU Run key.

  NOTHING HERE IS OWNED BY THIS PACK. The installer has never written an
  autostart and never will. These entries are created by agent sessions,
  by other tools' installers, and by the user - so this function REPORTS and
  callers must not delete on their own initiative.

  Measured on the maintainer's machine 2026-08-26: three Startup entries, all
  written by past agent sessions, one of them (`cbm-dashboard-plus.vbs`)
  pointing into a `Skyrim-AI-V5` tree that no longer existed at all. A dead
  autostart costs a failed process launch at every single boot and is
  invisible unless someone opens Task Manager's Startup tab.

  Each entry carries: Name, Source, Command, Targets, MissingTargets, Dead.
  `Dead` means at least one path the entry needs is not on disk.
  #>
  [CmdletBinding()] param()
  $out = New-Object System.Collections.Generic.List[object]
  # Broad on purpose: a false positive is only ever printed, never acted on,
  # whereas a miss leaves the user staring at Task Manager. Bare `chroma` is
  # deliberately NOT in this list - it matched Razer's RGB autostart
  # (`--url-params=apps=synapse,chroma-app`) on the maintainer's machine.
  $needle = 'claude|codex|grok|kimi|hermes|housecarl|codebase-memory|cbm[-_]|claude[-_]mem|superpowers|ponytail|headroom|chroma-mcp|skyrim-ai|forge|\bmcp\b|anthropic|openai|openrouter|ollama|spooky'

  $startup = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup'
  if (Test-Path -LiteralPath $startup -PathType Container) {
    foreach ($f in Get-ChildItem -LiteralPath $startup -File -ErrorAction SilentlyContinue) {
      if ($f.Name -eq 'desktop.ini') { continue }
      $command = ''
      if ($f.Extension -eq '.lnk') {
        try {
          $sh = New-Object -ComObject WScript.Shell
          $lnk = $sh.CreateShortcut($f.FullName)
          $command = ('{0} {1}' -f $lnk.TargetPath, $lnk.Arguments).Trim()
        } catch { $command = '' }
      } else {
        try { $command = [IO.File]::ReadAllText($f.FullName) } catch { $command = '' }
      }
      $haystack = ($f.Name + ' ' + $command)
      if ($haystack -notmatch $needle) { continue }
      $targets = @(Get-UabsAutostartTargetPaths -Text $command)
      $missing = @($targets | Where-Object { -not (Test-Path -LiteralPath $_) })
      [void]$out.Add([pscustomobject]@{
        Name           = $f.Name
        Source         = 'Startup folder'
        Path           = $f.FullName
        Command        = $command.Trim()
        Targets        = $targets
        MissingTargets = $missing
        Dead           = [bool]($targets.Count -and $missing.Count)
      })
    }
  }

  $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
  if (Test-Path -LiteralPath $runKey) {
    $props = $null
    try { $props = Get-ItemProperty -LiteralPath $runKey -ErrorAction Stop } catch { }
    if ($props) {
      foreach ($p in $props.PSObject.Properties) {
        if ($p.Name -like 'PS*') { continue }
        $command = [string]$p.Value
        if (($p.Name + ' ' + $command) -notmatch $needle) { continue }
        $targets = @(Get-UabsAutostartTargetPaths -Text $command)
        $missing = @($targets | Where-Object { -not (Test-Path -LiteralPath $_) })
        [void]$out.Add([pscustomobject]@{
          Name           = $p.Name
          Source         = 'HKCU Run'
          Path           = $runKey + '\' + $p.Name
          Command        = $command
          Targets        = $targets
          MissingTargets = $missing
          Dead           = [bool]($targets.Count -and $missing.Count)
        })
      }
    }
  }
  # .ToArray(), not @($out): on PS 5.1, wrapping a List[object] whose items
  # carry array-valued properties throws "Argument types do not match".
  # Callers wrap the CALL in @() to survive the single-item unroll.
  return $out.ToArray()
}

function Get-UabsCodexEnabledPluginIds {
  <#
  Read Codex's OWN plugin registry - ~/.codex/config.toml - and return the
  ids (`<plugin>@<marketplace>`) that are not explicitly disabled.

  Why this exists: `codex plugin list --json` fails WHOLESALE when any one
  configured marketplace snapshot is unloadable, even a marketplace unrelated
  to the plugin being asked about. Measured on 2026-08-26:

    Error: failed to load configured marketplace snapshot(s):
    - `headroom-marketplace` at ...\.tmp/marketplaces\headroom-marketplace:
      marketplace root does not contain a supported manifest

  An empty inventory then reads as "the plugin is not installed", which made
  the installer keep its copied skill duplicates. This file is what the CLI
  renders, so it stays right when the CLI cannot answer.

  Only the top-level [plugins."<id>"] table counts. Codex also writes nested
  tables such as [plugins."browser@openai-bundled".ambient] that carry their
  own `enabled` keys; reading those as the plugin's state inverts the answer.
  #>
  param([string]$CodexHome)
  if (-not $CodexHome) { return @() }
  $cfg = Join-Path $CodexHome 'config.toml'
  if (-not (Test-Path -LiteralPath $cfg -PathType Leaf)) { return @() }
  $ids = New-Object System.Collections.Generic.List[string]
  $current = $null
  $disabled = $false
  foreach ($line in [IO.File]::ReadAllLines($cfg)) {
    $t = $line.Trim()
    if ($t.StartsWith('[')) {
      if ($current -and -not $disabled) { [void]$ids.Add($current) }
      $current = $null
      $disabled = $false
      $m = [regex]::Match($t, '^\[plugins\."(?<id>[^"]+)"\]$')
      if ($m.Success) { $current = $m.Groups['id'].Value }
      continue
    }
    if ($current -and $t -match '^enabled\s*=\s*false') { $disabled = $true }
  }
  if ($current -and -not $disabled) { [void]$ids.Add($current) }
  return @($ids)
}

function Repair-UabsCodexDuplicatePlugins {
  param([string]$CodexHome, $Inventory, [switch]$CheckOnly)
  $path = Join-Path $CodexHome 'config.toml'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
  if (-not $Inventory) {
    $cli = Get-UabsCodexCli
    if (-not $cli) { return }
    $savedCodexHome = $env:CODEX_HOME
    try {
      $env:CODEX_HOME = $CodexHome
      $Inventory = Get-UabsNativeOutput -Exe $cli.Source -CmdArgs @('plugin','list','--json') | ConvertFrom-Json
    }
    catch { Write-UabsWarn 'Codex plugin inventory unavailable; duplicate-plugin repair skipped.'; return }
    finally { $env:CODEX_HOME = $savedCodexHome }
  }
  $native = @($Inventory.installed | Where-Object { $_.pluginId -eq 'superpowers@superpowers-dev' -and $_.enabled })
  $curated = @($Inventory.installed | Where-Object { $_.pluginId -eq 'superpowers@openai-curated-remote' -and $_.enabled })
  if ($native.Count -ne 1 -or $curated.Count -ne 1) { return }
  try { if ([version]$native[0].version -lt [version]$curated[0].version) { return } } catch { return }
  $before = [IO.File]::ReadAllText($path)
  $header = '[plugins."superpowers@openai-curated-remote"]'
  $newline = if ($before.Contains("`r`n")) { "`r`n" } else { "`n" }
  $pattern = '(?ms)^' + [regex]::Escape($header) + '[ \t]*\r?\n(?:(?!^\[).)*'
  $match = [regex]::Match($before, $pattern)
  if ($match.Success) {
    $section = $match.Value
    if ($section -match '(?m)^enabled\s*=\s*false\b') { return }
    if ($section -match '(?m)^enabled\s*=') {
      $replacement = [regex]::Replace($section, '(?m)^(enabled[ \t]*=[ \t]*)true\b', '${1}false')
    } else { $replacement = $section.Insert($section.IndexOf("`n") + 1, 'enabled = false' + $newline) }
    $after = $before.Substring(0,$match.Index) + $replacement + $before.Substring($match.Index+$match.Length)
  } else { $after = $before + $newline + $header + $newline + 'enabled = false' + $newline }
  if ($after -ceq $before) { return }
  $issue = 'Two Superpowers plugins enabled; keep the same/newer upstream installation and disable the duplicate curated copy.'
  if (-not $CheckOnly) {
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing redirected Codex config.' }
    $nonce = [guid]::NewGuid().ToString('N')
    $backup = $path + '.bak-plugin-dedupe-' + $nonce
    $temp = $path + '.tmp-' + $nonce
    try {
      [IO.File]::WriteAllText($temp, $after, (New-Object Text.UTF8Encoding($false)))
      [IO.File]::Replace($temp, $path, $backup)
      if ([IO.File]::ReadAllText($path) -cne $after) {
        Copy-Item -LiteralPath $backup -Destination $path -Force
        throw 'Plugin dedupe verification failed; original restored.'
      }
      Write-UabsOk ('Codex: duplicate curated Superpowers disabled; upstream retained. Backup: ' + $backup)
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
  }
  $issue
}

function Repair-UabsCodexRetiredFeatures {
  <# Codex reports these [features] keys as unknown/ignored on every config
     load (1,180+ log lines in one day, measured 2026-10-10). Codex already
     ignores them, so dropping the exact line changes no behaviour. Other
     tables and every other key are left byte-for-byte. #>
  param([string]$CodexHome, [switch]$CheckOnly)
  $retired = @('rmcp_client')   # the streamable-HTTP MCP client is always on now
  if (-not $CodexHome) { return }
  $path = Join-Path $CodexHome 'config.toml'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return }
  $before = [IO.File]::ReadAllText($path)
  $newline = if ($before.Contains("`r`n")) { "`r`n" } else { "`n" }
  $kept = New-Object System.Collections.Generic.List[string]
  $inFeatures = $false; $dropped = @()
  foreach ($line in ($before -split '\r?\n')) {
    $t = $line.Trim()
    if ($t.StartsWith('[')) { $inFeatures = ($t -ceq '[features]') }
    elseif ($inFeatures -and $t -match '^([A-Za-z0-9_-]+)\s*=' -and $retired -contains $Matches[1]) { $dropped += $Matches[1]; continue }
    $kept.Add($line)
  }
  if (-not $dropped.Count) { return }
  $issue = 'Codex ignores retired [features] key(s): ' + ($dropped -join ', ') + ' (log noise on every load).'
  if (-not $CheckOnly) {
    if ((Get-Item -LiteralPath $path).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Refusing redirected Codex config.' }
    $after = $kept -join $newline
    $nonce = [guid]::NewGuid().ToString('N')
    $backup = $path + '.bak-retired-features-' + $nonce
    $temp = $path + '.tmp-' + $nonce
    try {
      [IO.File]::WriteAllText($temp, $after, (New-Object Text.UTF8Encoding($false)))
      [IO.File]::Replace($temp, $path, $backup)
      if ([IO.File]::ReadAllText($path) -cne $after) {
        Copy-Item -LiteralPath $backup -Destination $path -Force
        throw 'Codex feature cleanup verification failed; original restored.'
      }
      Write-UabsOk ('Codex: removed ignored feature key(s) ' + ($dropped -join ', ') + '; backup: ' + $backup)
    } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
  }
  $issue
}

function Get-UabsCodexBuiltinSkillNames {
  <#
  Names of the skills Codex ships ITSELF, from <CodexHome>\skills\.system.

  Why this exists: v8.6.6 adopted `skill-creator` into the canonical tree so
  all five providers would carry it. Codex already ships a `skill-creator` of
  its own, so on Codex alone the pack's copy became a SECOND index entry for a
  capability that was already there -- measured as 184 entries / 48 visible
  description chars with the duplicate, against 183 / 50 without it.

  This is the same class of waste the native-plugin dedupe already removes,
  with a different owner: there the owner is an enabled plugin, here it is
  Codex's own built-in set. Discovered, never hardcoded -- `.system` also holds
  `imagegen`, `openai-docs`, `plugin-creator`, `review-agent` and
  `skill-installer`, and any future canonical skill taking one of those names
  would collide in exactly the same way with no code change to catch it.

  A directory only counts when it actually carries a SKILL.md: an empty or
  half-written folder owns nothing, and treating it as an owner would evict
  the pack's working copy in favour of nothing.
  #>
  param([string]$CodexHome)
  if (-not $CodexHome) { return @() }
  $sys = Join-Path (Join-Path $CodexHome 'skills') '.system'
  if (-not (Test-Path -LiteralPath $sys -PathType Container)) { return @() }
  $names = New-Object System.Collections.Generic.List[string]
  foreach ($d in @(Get-ChildItem -LiteralPath $sys -Directory -EA SilentlyContinue)) {
    if (Test-Path -LiteralPath (Join-Path $d.FullName 'SKILL.md') -PathType Leaf) {
      [void]$names.Add($d.Name)
    }
  }
  return @($names)
}

function Repair-UabsGrokDuplicatePlugins {
  <#
  Grok's official marketplace auto-installs superpowers. The AIO used to
  also `grok plugin install` the staged local copy under
  %LOCALAPPDATA%\Ultimate-AI-Starter-Bundle\plugins-src\superpowers. Two plugins with the
  same name both own systematic-debugging, and the TUI reports that as a
  skill error. Keep the newest version, preferring marketplace on a tie.
  Back up duplicate bytes and registry before removing owned install folders.

  Do NOT `grok plugin uninstall <name>` while duplicates exist: the CLI
  matches on plugin name only, so it removed the marketplace copy and left
  the local clone (measured). repo_key is not accepted as <NAME>. Edit
  installed-plugins/registry.json and delete the extra repo folder instead.
  #>
  param([string]$GrokExe, [string]$PluginName)
  $hits = @(Get-UabsGrokPluginList -GrokExe $GrokExe | Where-Object { $_.name -eq $PluginName })
  if ($hits.Count -le 1) { return $hits }
  $keep = $hits | Sort-Object @{Expression={try{[version]$_.version}catch{[version]'0.0.0'}};Descending=$true},
    @{Expression={[bool]$_.marketplace};Descending=$true} | Select-Object -First 1
  $installRoot = Join-Path $env:USERPROFILE '.grok\installed-plugins'
  $regPath = Join-Path $installRoot 'registry.json'
  foreach ($h in $hits) {
    if ($h.repo_key -eq $keep.repo_key) { continue }
    if (-not $h.path -or -not (Test-UabsPathWithin -Path $h.path -Root $installRoot) -or
        ([IO.Path]::GetFullPath($h.path).TrimEnd('\') -ieq [IO.Path]::GetFullPath($installRoot).TrimEnd('\'))) {
      Write-UabsWarn ('Grok: duplicate outside the managed install root was preserved: ' + $h.repo_key)
      continue
    }
    if ((Test-Path -LiteralPath $h.path) -and ((Get-Item -LiteralPath $h.path).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
      Write-UabsWarn 'Grok: redirected duplicate directory preserved.'
      continue
    }
    if (Test-Path -LiteralPath $regPath -PathType Leaf) {
      $doc = ([IO.File]::ReadAllText($regPath) | ConvertFrom-Json)
      if ($doc.repos -and $doc.repos.PSObject.Properties.Name -contains [string]$h.repo_key) {
        $nonce = [guid]::NewGuid().ToString('N')
        if (Test-Path -LiteralPath $h.path -PathType Container) {
          $backup = Join-Path (Get-UabsStateRoot) ('backups\grok-plugin-dedupe-' + $nonce)
          Copy-UabsRobo -From $h.path -To $backup
          if ((Get-UabsTreeDigest $h.path -Ordinal) -cne (Get-UabsTreeDigest $backup -Ordinal)) {
            throw 'Grok plugin backup verification failed; duplicate was not changed.'
          }
        }
        $doc.repos.PSObject.Properties.Remove([string]$h.repo_key)
        $utf8 = New-Object System.Text.UTF8Encoding $false
        $temp = $regPath + '.tmp-' + $nonce
        try {
          [IO.File]::WriteAllText($temp, (($doc | ConvertTo-Json -Depth 20) + [Environment]::NewLine), $utf8)
          [IO.File]::Replace($temp, $regPath, ($regPath + '.before-dedupe-' + $nonce + '.bak'))
        } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force } }
        if (Test-Path -LiteralPath $h.path) { Remove-Item -LiteralPath $h.path -Recurse -Force }
        Write-UabsOk ('Grok: backed up and retired duplicate ' + $h.repo_key)
      }
    }
  }
  $left = @(Get-UabsGrokPluginList -GrokExe $GrokExe | Where-Object { $_.name -eq $PluginName })
  if ($left.Count -gt 1) {
    Write-UabsWarn ("Grok: still {0} copies of {1} after registry drop - skill names will collide" -f $left.Count, $PluginName)
  } elseif ($left.Count -eq 1) {
    Write-UabsOk ("Grok: one {0} plugin remains ({1})" -f $PluginName, $left[0].repo_key)
  }
  return $left
}

function Get-UabsClaudeMarketplaceName {
  <#
  The marketplace directory name Claude Code caches a bundled plugin under.

  Claude installs a plugin to ~/.claude/plugins/cache/<marketplace>/<plugin>,
  and <marketplace> is the `name` inside the plugin's OWN
  .claude-plugin/marketplace.json - not the plugin id. Superpowers ships as
  'superpowers-dev', ponytail as 'ponytail', so guessing the id is right half
  the time and silently wrong the other half.

  Returns $null when the bundle has no manifest for that plugin, so callers
  can report SKIP instead of inventing a path.

  Restored in 7.9.0: 7.8.0 dropped this function but left
  TESTS\Test-HarnessRealization.ps1 calling it, so that gate died on its first
  Claude check. It is not in CI, so nothing noticed.
  #>
  param([string]$PluginRoot)
  $manifest = Join-Path $PluginRoot '.claude-plugin\marketplace.json'
  if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { return $null }
  try {
    # ReadAllText, never Get-Content -Raw: on Windows PowerShell 5.1 the latter
    # decodes with the ANSI codepage and mojibakes any non-ASCII owner name.
    $json = [IO.File]::ReadAllText($manifest) | ConvertFrom-Json
  } catch { return $null }
  if ($json -and $json.name) { return [string]$json.name }
  return $null
}

function Get-UabsPluginOwnedSkillNames {
  <#
  Skill names a bundled plugin owns, computed from the tree at install time -
  never a hardcoded list, so a plugin version bump that adds/renames a skill
  is picked up automatically.
  #>
  param([string]$PluginRoot)
  $sk = Join-Path $PluginRoot 'skills'
  if (-not (Test-Path -LiteralPath $sk -PathType Container)) { return @() }
  return @(Get-ChildItem -LiteralPath $sk -Directory | Select-Object -ExpandProperty Name)
}

function Remove-UabsPluginOwnedSkillCopies {
  <#
  Remove provider-skills copies that a natively installed plugin now owns.

  Safety rules (the destructive step of the native-plugin rework):
    - skip names with no <SkillsDir>\<name> directory (nothing to do);
    - by default, NEVER remove a copy whose SKILL.md md5 differs from the exact
      provider source (<ExpectedRoot>\<name>\SKILL.md) - a difference means the
      user may have modified the copy, so warn and record skipped_modified;
    - BackupModified is reserved for names the provider itself owns. Such a
      copy cannot remain active without shadowing/duplicating the provider's
      built-in, so move it to the same verified backup instead of deleting it;
    - a copy with no SKILL.md, or a name absent from the expected tree, is
      unverifiable - keep it and record why;
    - before any Remove-Item, robocopy the directory to
      <BackupRoot>\dedupe-<Provider>-<yyyyMMdd-HHmmss>\<name>.

  Returns an ordered dict: removed / skipped_modified / skipped (string lists).
  #>
  param(
    [string]$Provider,
    [string]$SkillsDir,
    [string[]]$Names,
    [string]$ExpectedRoot,
    [string]$BackupRoot,
    [System.Collections.Generic.List[string]]$Log,
    [switch]$BackupModified
  )
  $result = [ordered]@{ removed = @(); skipped_modified = @(); skipped = @() }
  if (-not (Test-Path -LiteralPath $SkillsDir -PathType Container)) { return $result }
  $preserved = @(Get-UabsPreservedSkillNames -Provider $Provider -SkillsDir $SkillsDir)
  $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
  $bkDir = Join-Path $BackupRoot ('dedupe-' + $Provider + '-' + $ts)
  foreach ($name in $Names) {
    if ($preserved -contains $name) {
      $result.skipped += ($name + ' (verified local override - kept)')
      continue
    }
    $target = Join-Path $SkillsDir $name
    if (-not (Test-Path -LiteralPath $target -PathType Container)) { continue }
    $copyMd = Join-Path $target 'SKILL.md'
    $expectedMd = Join-Path (Join-Path $ExpectedRoot $name) 'SKILL.md'
    if (-not (Test-Path -LiteralPath $copyMd -PathType Leaf)) {
      $result.skipped += ($name + ' (copy has no SKILL.md - unverifiable, kept)')
      Write-UabsWarn ('dedupe: kept ' + $name + ' - copy has no SKILL.md to verify against provider source')
      if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: kept ' + $name + ' in ' + $SkillsDir + ' (no SKILL.md)') }
      continue
    }
    if (-not (Test-Path -LiteralPath $expectedMd -PathType Leaf)) {
      # This provider tree never shipped a skill of this name, so there is
      # nothing to verify the copy against. Keep it.
      $result.skipped += ($name + ' (absent from expected provider tree - kept)')
      Write-UabsWarn ('dedupe: kept ' + $name + ' - no expected provider SKILL.md to verify against')
      if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: kept ' + $name + ' in ' + $SkillsDir + ' (not in provider source)') }
      continue
    }
    $hCopy = (Get-FileHash -LiteralPath $copyMd -Algorithm MD5).Hash
    $hExpected = (Get-FileHash -LiteralPath $expectedMd -Algorithm MD5).Hash
    $wasModified = $hCopy -ne $hExpected
    if ($wasModified -and -not $BackupModified) {
      $result.skipped_modified += $name
      Write-UabsWarn ('dedupe: REFUSED to remove ' + $target + ' - SKILL.md differs from the pack provider source (user-modified?). Back up your changes and remove it by hand if unwanted.')
      if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: REFUSED ' + $target + ' (md5 differs from provider source)') }
      continue
    }
    New-Item -ItemType Directory -Force -Path $bkDir | Out-Null
    Copy-UabsRobo -From $target -To (Join-Path $bkDir $name)
    Remove-Item -LiteralPath $target -Recurse -Force
    $result.removed += $name
    if ($wasModified) {
      Write-UabsWarn ('dedupe: moved modified copy shadowing provider-owned skill ' + $name + ' (backup: ' + (Join-Path $bkDir $name) + ')')
    } else {
      Write-UabsOk ('dedupe: removed plugin-owned copy ' + $name + ' (backup: ' + (Join-Path $bkDir $name) + ')')
    }
    if ($Log) { [void]$Log.Add((Get-Date -Format o) + ' dedupe: removed ' + $target + ' (backup ' + $bkDir + ')') }
  }
  return $result
}

function Test-UabsTomlPluginEnabled {
  <#
  True when TOML content has a section whose header starts with
  [<HeaderPrefix> and whose body contains enabled = true. Line-based on
  purpose: regex-over-sections is how config.toml readers have been burned
  before (see the [compat.claude] comment in Set-UabsGrokCompatCells).
  #>
  param([string]$Content, [string]$HeaderPrefix)
  if ([string]::IsNullOrEmpty($Content)) { return $false }
  $inSection = $false
  foreach ($ln in ($Content -split "\r?\n")) {
    $t = $ln.Trim()
    if ($t.StartsWith('[')) {
      $inSection = $t.StartsWith('[' + $HeaderPrefix)
      continue
    }
    if ($inSection -and $t -match '^enabled\s*=\s*true\s*$') { return $true }
  }
  return $false
}

function Set-UabsHermesPluginScanOff {
  <#
  Ensure plugins.scan_on_install: false in the Hermes config.yaml.

  Hermes' security scanner refuses both bundled plugins with 214
  false-positive 'traversal' findings in upstream test scripts, and --force
  does not override it, so the scanner must be told not to run at install
  time. This is a TEXT edit, never a YAML re-serialize: any comment the
  operator added survives untouched.

  Rules: an operator-owned false value is left exactly as-is, true is changed
  temporarily and restored later, and a missing setting is inserted directly
  under plugins:. Backup to config.yaml.bak-<yyyyMMdd-HHmmss> first.

  Returns 'already-present' | 'inserted' | 'appended-section' | 'created' | 'failed'.
  #>
  param([string]$ConfigPath)
  try {
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
      $dir = Split-Path $ConfigPath -Parent
      New-Item -ItemType Directory -Force -Path $dir | Out-Null
      $enc0 = New-Object System.Text.UTF8Encoding($false)
      [IO.File]::WriteAllText($ConfigPath, ("plugins:`r`n  scan_on_install: false`r`n"), $enc0)
      Write-UabsWarn ('Hermes config.yaml missing - created with plugins.scan_on_install: false (' + $ConfigPath + ')')
      return 'created'
    }
    $text = [IO.File]::ReadAllText($ConfigPath)
    $nl = "`r`n"
    if ($text -notmatch "`r`n") { $nl = "`n" }
    $lines = @($text -split '\r?\n')
    $out = @()
    $inPlugins = $false
    $pluginsFound = $false
    $settingFound = $false
    $changedTrue = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      if ($line -match '^plugins\s*:') {
        $pluginsFound = $true
        $inPlugins = $true
        $out += $line
        continue
      }
      if ($inPlugins -and $line -match '^\S') { $inPlugins = $false }
      if ($inPlugins -and $line -match '^(\s+scan_on_install\s*:\s*)(true|false)(\s*(?:#.*)?)$') {
        $settingFound = $true
        if ($Matches[2] -eq 'false') {
          Write-UabsOk 'Hermes config: scan_on_install already false - left operator setting unchanged'
          return 'already-present'
        }
        $out += ($Matches[1] + 'false' + $Matches[3])
        $changedTrue = $true
        continue
      }
      $out += $line
    }
    if (-not $settingFound) {
      if ($pluginsFound) {
        $header = 0
        for ($j = 0; $j -lt $out.Count; $j++) {
          if ($out[$j] -match '^plugins\s*:') { $header = $j; break }
        }
        $before = @($out[0..$header])
        $after = if ($header + 1 -lt $out.Count) { @($out[($header + 1)..($out.Count - 1)]) } else { @() }
        $out = @($before + '  scan_on_install: false' + $after)
      } else {
        if ($out.Count -and $out[-1] -ne '') { $out += '' }
        $out += @('plugins:', '  scan_on_install: false')
      }
    }
    Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ConfigPath, ($out -join $nl), $enc)
    $state = if ($changedTrue) { 'changed-true' } elseif ($pluginsFound) { 'inserted' } else { 'appended-section' }
    Write-UabsInfo 'Hermes config: plugin scanning paused while the two bundled, pinned plugins install'
    return $state
  } catch {
    Write-UabsWarn ('Hermes scan_on_install override failed: ' + $_.Exception.Message)
    return 'failed'
  }
}

function Install-UabsKimiPlugin {
  <#
  Install a bundled plugin into Kimi Code natively, without the TUI.

  kimi-code 0.27.0 has no `kimi plugin` SUBCOMMAND, which is what earlier
  versions of this installer observed - and then wrongly concluded that Kimi
  has no plugin system at all, so Kimi got copied skills only. It does have
  one; it is driven by the in-session `/plugins` slash command, and prompt
  mode cannot stand in for that because it demands a login first.

  Reading the shipped CLI settles the contract:
    - `/plugins install` copies the source to <home>\plugins\managed\<id>
    - the registry is <home>\plugins\installed.json, {version:1, plugins:[]}
    - each persisted entry is thin: id, root, source, enabled, installedAt,
      updatedAt, originalSource, capabilities, github
    - on load, materialize(entry) re-runs parseManifest(entry.root), so
      manifest, skillCount and state are DERIVED from disk every time

  That last point is what makes writing the registry safe rather than
  brittle: nothing here has to reproduce Kimi's manifest parsing, and a Kimi
  upgrade that changes the manifest schema cannot leave a stale record behind.

  The manifest itself is read from <root>\plugin.json, else
  <root>\.kimi-plugin\plugin.json - which is where the bundled Superpowers
  Kimi adapter (sessionStart.skill + the Kimi tool mapping) already lives.

  Returns @{ ok; status; root; reason }.
  #>
  param(
    [Parameter(Mandatory)][string]$KimiHome,
    [Parameter(Mandatory)][string]$PluginId,
    [Parameter(Mandatory)][string]$SourceRoot
  )
  $res = [ordered]@{ ok = $false; status = 'failed'; root = ''; reason = '' }
  try {
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
      $res.reason = 'source plugin tree missing: ' + $SourceRoot
      return $res
    }
    # Refuse to install something Kimi will only reject at load time.
    $mRoot = Join-Path $SourceRoot 'plugin.json'
    $mDir  = Join-Path $SourceRoot '.kimi-plugin\plugin.json'
    if (-not (Test-Path -LiteralPath $mRoot -PathType Leaf) -and
        -not (Test-Path -LiteralPath $mDir -PathType Leaf)) {
      $res.reason = 'no plugin.json or .kimi-plugin\plugin.json in ' + $SourceRoot
      return $res
    }

    $managedDir  = Join-Path (Join-Path $KimiHome 'plugins') 'managed'
    $managedRoot = Join-Path $managedDir $PluginId
    New-Item -ItemType Directory -Force -Path $managedDir | Out-Null

    # Stage then swap, the way the CLI does: a half-copied plugin tree left in
    # place by an interrupted copy would load as a broken plugin.
    $staging = Join-Path $managedDir ($PluginId + '-staging-' + (Get-Date -Format 'yyyyMMddHHmmssfff'))
    Copy-Item -LiteralPath $SourceRoot -Destination $staging -Recurse -Force
    if (Test-Path -LiteralPath $managedRoot) {
      Remove-Item -LiteralPath $managedRoot -Recurse -Force
    }
    Move-Item -LiteralPath $staging -Destination $managedRoot -Force
    $res.root = $managedRoot

    # Merge into installed.json, preserving every other plugin's entry as-is.
    $store = Join-Path (Join-Path $KimiHome 'plugins') 'installed.json'
    $plugins = @()
    if (Test-Path -LiteralPath $store -PathType Leaf) {
      $existing = $null
      try {
        $existing = ([IO.File]::ReadAllText($store)) | ConvertFrom-Json
      } catch {
        Copy-Item -LiteralPath $store -Destination ($store + '.bad-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
        Write-UabsWarn ('Kimi installed.json was unparseable - kept a copy and rebuilt it')
      }
      if ($existing -and $existing.plugins) {
        foreach ($p in @($existing.plugins)) {
          if ($p.id -eq $PluginId) { continue }   # replaced below
          $keep = [ordered]@{}
          foreach ($prop in $p.PSObject.Properties) { $keep[$prop.Name] = $prop.Value }
          $plugins += ,$keep
        }
      }
    }

    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $entry = [ordered]@{
      id          = $PluginId
      root        = $managedRoot
      source      = 'local-path'
      enabled     = $true
      installedAt = $now
      updatedAt   = $now
    }
    $plugins += ,$entry

    $doc = [ordered]@{ version = 1; plugins = $plugins }
    $json = $doc | ConvertTo-Json -Depth 12
    $enc = New-Object System.Text.UTF8Encoding($false)
    New-Item -ItemType Directory -Force -Path (Split-Path $store -Parent) | Out-Null
    $tmp = $store + '.tmp'
    [IO.File]::WriteAllText($tmp, $json, $enc)
    if (Test-Path -LiteralPath $store) { Remove-Item -LiteralPath $store -Force }
    Move-Item -LiteralPath $tmp -Destination $store -Force

    $res.ok = $true
    $res.status = 'installed'
    return $res
  } catch {
    $res.reason = $_.Exception.Message
    return $res
  }
}

function Get-UabsKimiEnabledPluginIds {
  <#
  Read-only: ids in Kimi's <home>\plugins\installed.json that are enabled and
  whose root still holds a parseable manifest (plugin.json, else
  .kimi-plugin\plugin.json - Kimi's own lookup order). A disabled, missing or
  malformed plugin owns no skills, so its copied skills must stay.
  #>
  param([string]$KimiHome)
  if (-not $KimiHome) { return @() }
  $store = Join-Path $KimiHome 'plugins\installed.json'
  if (-not (Test-Path -LiteralPath $store -PathType Leaf)) { return @() }
  try { $doc = [IO.File]::ReadAllText($store) | ConvertFrom-Json } catch { return @() }
  $ids = @()
  foreach ($p in @($doc.plugins)) {
    if (-not $p -or -not $p.id -or $p.enabled -ne $true -or -not $p.root) { continue }
    $manifest = @((Join-Path $p.root 'plugin.json'), (Join-Path $p.root '.kimi-plugin\plugin.json')) |
      Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $manifest) { continue }
    try { $null = [IO.File]::ReadAllText($manifest) | ConvertFrom-Json } catch { continue }
    $ids += [string]$p.id
  }
  return $ids
}

function Restore-UabsHermesPluginScan {
  <#
  Undo the temporary scan_on_install override once the bundled plugins are in.

  Turning Hermes' install-time security scanner off permanently would weaken
  every FUTURE third-party plugin the operator installs, which is not ours to
  decide - Hermes treats plugin loading as an explicit trust boundary. So the
  override is scoped to our own install window and removed here.

  This removes a single line rather than restoring a snapshot of the file: the
  Hermes gateway re-serializes config.yaml on its own schedule (observed ~13
  min after start), so a whole-file restore taken before the install would
  clobber whatever the gateway legitimately wrote in between.

  $State is the string returned by Set-UabsHermesPluginScanOff. When it reports
  'already-present' the operator had their own setting and it is left alone.

  Returns 'removed' | 'restored-true' | 'kept-user-setting' | 'absent' | 'failed'.
  #>
  param([string]$ConfigPath, [string]$State)
  try {
    if ($State -eq 'already-present') {
      Write-UabsOk 'Hermes config: scan_on_install was the operator''s own setting - left as-is'
      return 'kept-user-setting'
    }
    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) { return 'absent' }
    $text = [IO.File]::ReadAllText($ConfigPath)
    $nl = "`r`n"
    if ($text -notmatch "`r`n") { $nl = "`n" }
    $lines = @($text -split '\r?\n')
    $keep = @()
    $dropped = 0
    $inPlugins = $false
    foreach ($line in $lines) {
      if ($line -match '^plugins\s*:') { $inPlugins = $true; $keep += $line; continue }
      if ($inPlugins -and $line -match '^\S') { $inPlugins = $false }
      if ($inPlugins -and $line -match '^(\s+scan_on_install\s*:\s*)false(\s*(?:#.*)?)$') {
        if ($State -eq 'changed-true') { $keep += ($Matches[1] + 'true' + $Matches[2]) }
        $dropped++
        continue
      }
      $keep += $line
    }
    if ($dropped -eq 0) {
      Write-UabsOk 'Hermes config: no scan_on_install override left to remove'
      return 'absent'
    }
    Copy-Item -LiteralPath $ConfigPath -Destination ($ConfigPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllText($ConfigPath, ($keep -join $nl), $enc)
    if ($State -eq 'changed-true') {
      Write-UabsOk 'Hermes config: operator scan_on_install: true restored'
      return 'restored-true'
    }
    Write-UabsOk 'Hermes config: temporary scan_on_install override removed - plugin scanning is back on'
    return 'removed'
  } catch {
    Write-UabsWarn ('Hermes scan_on_install restore failed: ' + $_.Exception.Message)
    return 'failed'
  }
}

function Add-UabsMarketplacePluginEntry {
  <#
  Idempotently add a plugin entry to a marketplace.json, preserving the
  file's own style: existing newline convention, 2-space indentation (entry
  object at 4, fields at 6, matching the canonical ultimate-bundle manifest),
  UTF-8 no BOM. This is a TEXT insertion because PS 5.1's ConvertTo-Json
  emits CRLF with 4-space indents and would reformat the whole file.

  The edit is validated (re-parse + entry present) BEFORE anything is
  written; the original is backed up to marketplace.json.bak-<ts>.
  Returns $true when the entry is present at the end (already or added).
  #>
  param(
    [string]$ManifestPath,
    [string]$EntryName,
    [string]$EntryDescription,
    [string]$EntrySource,
    [string]$EntryCategory
  )
  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) { return $false }
  $text = [IO.File]::ReadAllText($ManifestPath)
  if ($text -match ('"name"\s*:\s*"' + [regex]::Escape($EntryName) + '"')) { return $true }
  try { $parsed = $text | ConvertFrom-Json } catch {
    Write-UabsWarn ('marketplace manifest is not valid JSON - left untouched: ' + $ManifestPath)
    return $false
  }
  if (-not $parsed -or -not $parsed.plugins) {
    Write-UabsWarn ('marketplace manifest has no plugins array - left untouched: ' + $ManifestPath)
    return $false
  }
  $nl = "`n"
  if ($text -match "`r`n") { $nl = "`r`n" }
  $entry = '    {' + $nl +
           '      "name": "' + $EntryName + '",' + $nl +
           '      "description": "' + $EntryDescription + '",' + $nl +
           '      "source": "' + $EntrySource + '",' + $nl +
           '      "category": "' + $EntryCategory + '"' + $nl +
           '    },'
  $new = $null
  $m = [regex]::Match($text, '"plugins"\s*:\s*\[\s*\r?\n')
  if ($m.Success) {
    # insert as the first element of the non-empty array
    $idx = $m.Index + $m.Length
    $new = $text.Substring(0, $idx) + $entry + $nl + $text.Substring($idx)
  } else {
    $m2 = [regex]::Match($text, '"plugins"\s*:\s*\[\s*\]')
    if (-not $m2.Success) {
      Write-UabsWarn ('could not locate the plugins array in ' + $ManifestPath)
      return $false
    }
    $replacement = '"plugins": [' + $nl + $entry.TrimEnd(',') + $nl + '  ]'
    $new = $text.Substring(0, $m2.Index) + $replacement + $text.Substring($m2.Index + $m2.Length)
  }
  try {
    $check = $new | ConvertFrom-Json
    $found = $false
    foreach ($pl in @($check.plugins)) { if ($pl.name -eq $EntryName) { $found = $true } }
    if (-not $found) { throw 'entry missing after edit' }
  } catch {
    Write-UabsWarn ('marketplace edit failed validation - file left untouched: ' + $_.Exception.Message)
    return $false
  }
  Copy-Item -LiteralPath $ManifestPath -Destination ($ManifestPath + '.bak-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
  $enc = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($ManifestPath, $new, $enc)
  return $true
}

<# Resolve a provider CLI without installing anything.

   Shared so INSTALL-AIO.ps1's auto-detection and Ensure-Provider-CLIs.ps1's
   bootstrap agree on what "installed" means. They disagreed before v8.1.0:
   the installer assumed all five providers were wanted and the bootstrap then
   downloaded the missing ones, so a machine with only Claude ended up with
   four vendor CLIs nobody asked for. #>
function Resolve-UabsProviderExe {
  param([Parameter(Mandatory)][string]$Provider)
  $cmd = Get-Command $Provider.ToLowerInvariant() -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $candidates = switch ($Provider) {
    'Claude' { @((Join-Path $env:USERPROFILE '.local\bin\claude.exe')) }
    'Codex'  { @((Join-Path $env:USERPROFILE '.local\bin\codex.exe'), (Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin\codex.exe')) }
    'Grok'   { @((Join-Path $env:USERPROFILE '.grok\bin\grok.exe')) }
    'Kimi'   { @((Join-Path $env:USERPROFILE '.local\bin\kimi.exe'), (Join-Path $env:USERPROFILE '.kimi-code\bin\kimi.exe')) }
    'Hermes' { @((Join-Path $env:LOCALAPPDATA 'hermes\hermes-agent\venv\Scripts\hermes.exe'), (Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe')) }
    default  { @() }
  }
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
  }
  return $null
}

# Providers whose CLI is actually on this machine. Executable presence only:
# a leftover ~/.kimi-code or ~/.codex directory survives an uninstall, and
# treating a stale config folder as an install would keep re-wiring a provider
# the user deliberately removed.
function Get-UabsInstalledProviders {
  param([string[]]$Candidates = @('Claude','Codex','Grok','Kimi','Hermes'))
  return @($Candidates | Where-Object { Resolve-UabsProviderExe -Provider $_ })
}
