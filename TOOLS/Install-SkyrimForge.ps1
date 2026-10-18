<#
.SYNOPSIS
  Install the pinned Skyrim Forge release and prove it runs.

.DESCRIPTION
  Forge is released from github.com/SenjuWoo/SkyrimForge. CATALOG.json pins the
  release tag, the archive name and its SHA-256. The archive comes from, in
  order: -SourceZip, the Full-Offline copy in BUNDLED-TOOLS\offline, a verified
  earlier download in the bundle state folder, or a fresh download that must
  match the pinned digest before anything is extracted. -SourceDir installs an
  already extracted tree or a Forge checkout (development and tests).

  Bundle 7.8.0 ended this script with `if (-not $contract.compatible) { throw }`.
  Forge never emitted a `compatible` field, `-not $null` is `$true`, so it threw
  on every run. The only contract kept between the two repositories is the one
  that can genuinely fail: `forge doctor` after installation, run by this script
  and by the bundle's CI against the exact pinned release.

  The install directory carries NO version suffix, and that is the whole point.

  Every provider stores an MCP server command as a hard absolute path: Claude
  JSON, Kimi JSON, Codex TOML, Grok TOML, Hermes YAML. A version-stamped
  install directory renames itself on every upgrade, so each upgrade silently
  disconnects whichever configs were not rewritten -- and the failure is quiet,
  because a provider that cannot spawn its MCP server just shows no tools.

  Observed on the live machine before 7.9.0: SKYRIM_FORGE_ROOT pointed at
  Skyrim-Forge-5.1.6 (deleted), all five provider configs pointed at
  Skyrim-Forge (never created), and the actual install was version-stamped with
  no virtualenv. Three paths, no two agreeing, MCP dead everywhere.

  So: the SOURCE keeps its version in VERSION.txt (provenance), the INSTALL
  DIRECTORY never does (stability), and an existing version-stamped install is
  migrated onto the versionless name instead of being duplicated beside it.
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  # The directory Forge is installed INTO -- the same thing
  # SKYRIM_FORGE_ROOT names, e.g. 'S:\Apps\Skyrim Tools\Skyrim-Forge', not
  # the tools folder that contains it. Highest precedence: a caller that
  # names a root means it, even if nothing is there yet. Without it, an
  # existing install or SKYRIM_FORGE_ROOT wins, and failing all of that it
  # goes under LOCALAPPDATA, which needs no admin rights and assumes no
  # drive letter.
  [string]$ForgeRoot,
  [string[]]$Providers = @('Claude','Codex','Grok','Kimi','Hermes','Antigravity'),
  # In the all-in-one bundle, provider skill content is owned by the bundle's
  # tailored trees. Forge may add its per-machine INSTALLATION.json descriptor
  # but must not replace that bundle-owned Forge skill with a second copy.
  [switch]$BundleOwnsProviderSkills,
  # Resolve and print the install root, migrate a version-stamped install if one
  # is found, then stop. Path resolution is the part that has broken repeatedly,
  # so it has to be runnable on its own -- TESTS/Test-ForgeRootResolution.ps1
  # drives this switch against synthetic layouts.
  [switch]$ResolveOnly,
  # A release archive to use instead of the offline copy or a download. It
  # must still match the SHA-256 pinned in CATALOG.json.
  [string]$SourceZip,
  # An extracted Forge tree or checkout to install as-is (no digest check).
  [string]$SourceDir
)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')

$catalogPath = Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json'
$forgeEntry = @(([IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json).components | Where-Object { $_.id -eq 'skyrim-forge' }) | Select-Object -First 1
if (-not $forgeEntry) { throw "CATALOG.json has no skyrim-forge entry: $catalogPath" }
$forgeVersion = [string]$forgeEntry.version
if ($forgeVersion -notmatch '^\d+\.\d+\.\d+$') { throw "CATALOG.json skyrim-forge version is invalid: $forgeVersion" }

function Resolve-ForgeSource {
  if ($SourceDir) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDir 'Install-or-Update.ps1') -PathType Leaf)) { throw "-SourceDir is not a Forge tree: $SourceDir" }
    return (Resolve-Path -LiteralPath $SourceDir).Path
  }
  $asset = [string]$forgeEntry.asset
  $pinned = ([string]$forgeEntry.sha256).ToUpperInvariant()
  if ($asset -notmatch '^[A-Za-z0-9._-]+\.zip$' -or $pinned -notmatch '^[0-9A-F]{64}$') { throw 'CATALOG.json skyrim-forge asset or sha256 is invalid.' }
  $downloads = Join-Path (Get-UabsStateRoot) 'downloads'
  $zip = $null
  if ($SourceZip) {
    # A named archive is a decision: refuse it outright instead of silently
    # installing something else.
    if (-not (Test-Path -LiteralPath $SourceZip -PathType Leaf)) { throw "-SourceZip not found: $SourceZip" }
    if ((Get-FileHash -LiteralPath $SourceZip -Algorithm SHA256).Hash -ne $pinned) {
      throw "-SourceZip $SourceZip does not match the pinned release SHA-256 $pinned. Nothing was installed."
    }
    $zip = $SourceZip
  }
  foreach ($candidate in @($(if (-not $zip) { @((Join-Path $PackRoot ('BUNDLED-TOOLS\offline\' + $asset)), (Join-Path $downloads $asset)) }))) {
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
    if ((Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -eq $pinned) { $zip = $candidate; break }
    Write-Host "  ..  ignoring $candidate (SHA-256 does not match the pinned release)" -ForegroundColor DarkYellow
  }
  if (-not $zip) {
    $repo = [string]$forgeEntry.github.owner + '/' + [string]$forgeEntry.github.repo
    $url = 'https://github.com/' + $repo + '/releases/download/' + [string]$forgeEntry.release_tag + '/' + $asset
    $part = Join-Path $downloads ($asset + '.part-' + [guid]::NewGuid().ToString('N'))
    try {
      Save-UabsUrl -Url $url -OutFile $part
      $actual = (Get-FileHash -LiteralPath $part -Algorithm SHA256).Hash
      if ($actual -ne $pinned) { throw "Downloaded $asset has SHA-256 $actual; the bundle pins $pinned. Nothing was installed." }
      Move-Item -LiteralPath $part -Destination (Join-Path $downloads $asset) -Force
      $zip = Join-Path $downloads $asset
    } finally { Remove-Item -LiteralPath $part -Force -ErrorAction SilentlyContinue }
  }
  # Extract once per pinned digest; later runs reuse the verified tree.
  $extractRoot = Join-Path (Get-UabsStateRoot) 'forge-src'
  $extract = Join-Path $extractRoot ($forgeVersion + '-' + $pinned.Substring(0, 12).ToLowerInvariant())
  $tree = Join-Path $extract ('Skyrim-Forge-' + $forgeVersion)
  if (-not (Test-Path -LiteralPath (Join-Path $tree 'MANIFEST.json') -PathType Leaf)) {
    $stage = $extract + '.part-' + [guid]::NewGuid().ToString('N')
    try {
      Expand-UabsZip -Zip $zip -Dest $stage -WipeDest
      if (-not (Test-Path -LiteralPath (Join-Path $stage ('Skyrim-Forge-' + $forgeVersion + '\Install-or-Update.ps1')) -PathType Leaf)) { throw "$asset does not contain Skyrim-Forge-$forgeVersion\Install-or-Update.ps1" }
      if (Test-Path -LiteralPath $extract) { Remove-Item -LiteralPath $extract -Recurse -Force }
      Move-Item -LiteralPath $stage -Destination $extract
    } finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } }
  }
  # Only the pinned extraction is kept.
  foreach ($old in @(Get-ChildItem -LiteralPath $extractRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $extract })) {
    Remove-Item -LiteralPath $old.FullName -Recurse -Force -ErrorAction SilentlyContinue
  }
  return $tree
}

if ($ResolveOnly) { $source = $null } else { $source = Resolve-ForgeSource }
if ($source) {
  $versionText = [IO.File]::ReadAllText((Join-Path $source 'VERSION.txt'))
  if ($versionText -notmatch '(?m)^Skyrim Forge\s+(?<ver>\d+\.\d+\.\d+)\s*$') { throw "Cannot read a version from $source\VERSION.txt" }
  if (-not $SourceDir -and $Matches['ver'] -ne $forgeVersion) { throw "Release archive holds Forge $($Matches['ver']); CATALOG.json pins $forgeVersion." }
  $forgeVersion = $Matches['ver']
}

# ---- Resolve ONE versionless install root -------------------------------
# Strip a trailing -1.2 / -1.2.3 from a directory leaf.
function Get-VersionlessRoot([string]$path) {
  if (-not $path) { return $null }
  $path = $path.TrimEnd('\', '/')
  $leaf = Split-Path -Leaf $path
  $parent = Split-Path -Parent $path
  if ($parent -and $leaf -match '^(?<stem>.+?)-\d+(?:\.\d+)*$') { return (Join-Path $parent $Matches['stem']) }
  return $path
}

# Process env before the persisted User value: a caller that exported
# SKYRIM_FORGE_ROOT for this run means it, and the persisted value is normally
# the same string anyway. It also keeps the resolver testable without writing to
# the user's registry.
$declared = $env:SKYRIM_FORGE_ROOT
if (-not $declared) { $declared = [Environment]::GetEnvironmentVariable('SKYRIM_FORGE_ROOT', 'User') }
$default = Join-Path (Join-Path $env:LOCALAPPDATA 'Skyrim-Tools') 'Skyrim-Forge'

# An explicitly named root is a decision, not a guess, so its parent is created
# rather than skipped. The other candidates must already exist to be considered.
if ($ForgeRoot) {
  $explicit = Get-VersionlessRoot $ForgeRoot
  # The natural mistake is to pass the tools FOLDER ('S:\Apps\Skyrim Tools')
  # instead of the install directory inside it. That is a directory full of
  # someone else's tools, and this installer replaces the directory it is
  # given. Say so instead of scattering Forge across xEdit.
  $marks = @('Install-or-Update.ps1', 'VERSION.txt', 'skyrim_forge', '.venv', 'Workspaces')
  if ((Test-Path -LiteralPath $explicit -PathType Container) -and
      -not (@($marks | Where-Object { Test-Path -LiteralPath (Join-Path $explicit $_) }).Count) -and
      @(Get-ChildItem -LiteralPath $explicit -Force).Count -gt 0) {
    throw "-ForgeRoot is the directory Forge is installed INTO, and '$explicit' already holds other files. Use '$(Join-Path $explicit 'Skyrim-Forge')'."
  }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $explicit) | Out-Null
}

$target = $null
$migrationNote = $null
foreach ($candidate in @($ForgeRoot, $declared, $default)) {
  if (-not $candidate) { continue }
  $wanted = Get-VersionlessRoot $candidate
  $parent = Split-Path -Parent $wanted
  if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { continue }

  # Already versionless and present: upgrade in place, nothing to migrate.
  if (Test-Path -LiteralPath $wanted -PathType Container) { $target = $wanted; break }

  # A version-stamped install of the same product is the thing that keeps
  # breaking configs. Move it onto the versionless name -- move, never copy, so
  # the machine is not left with two installs and one of them stale.
  $stem = Split-Path -Leaf $wanted
  $stemRx = '^' + [regex]::Escape($stem) + '-(?<ver>\d+(?:\.\d+)*)$'
  $legacy = @()
  foreach ($dir in (Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
    if ($dir.Name -notmatch $stemRx) { continue }
    # [version] needs at least two parts, so "6" would not parse on its own.
    $text = $Matches['ver']
    while (($text -split '\.').Count -lt 2) { $text = $text + '.0' }
    $parsed = $null
    if (-not [version]::TryParse($text, [ref]$parsed)) { continue }
    $legacy += [pscustomobject]@{ Version = $parsed; Full = $dir.FullName }
  }
  if ($legacy.Count -gt 0) {
    $from = (($legacy | Sort-Object Version -Descending)[0]).Full
    Move-Item -LiteralPath $from -Destination $wanted
    # Held, not printed yet: under -ResolveOnly this script's stdout is a
    # contract -- exactly one line, the resolved path -- and a chatty notice
    # would be parsed as part of it by any caller.
    $migrationNote = '  ..  migrated version-stamped Forge install: ' + (Split-Path -Leaf $from) + ' -> ' + $stem
    $target = $wanted
    break
  }

  # Nothing installed here yet. A named root and the default may be created
  # fresh; a stale SKYRIM_FORGE_ROOT pointing at nothing should not be.
  if ($candidate -eq $ForgeRoot -or $candidate -eq $default) { $target = $wanted; break }
}
if (-not $target) { $target = $default }
if ($target -match '-\d+(?:\.\d+)*$') { throw "Refusing a version-stamped Forge install directory: $target" }
if ($ResolveOnly) { Write-Output $target; exit 0 }
if ($migrationNote) { Write-Host $migrationNote -ForegroundColor DarkCyan }

# ---- Stage the source tree ----------------------------------------------
# Job staging defaults to <install root>\Workspaces, so a replace-in-place that
# deleted the old directory would delete the user's mod work with it. These
# survive an upgrade; everything else is shipped content and is replaced.
$preserve = @('Workspaces', '.venv', 'REPORTS', 'config.toml')

# VERSION.txt alone is not an upgrade key. v7.9.1 ships Forge as in-tree source,
# and a bundle hotfix may legitimately change Forge scripts while keeping the
# product version at 6.0.0. If we gate refreshes only on VERSION.txt, the AIO can
# package a fixed Register-MCP.ps1 and then execute an older live copy forever.
# Compare the live shipped tree against the source MANIFEST instead. This also
# repairs a locally modified/missing shipped file without touching user state.
function Test-ForgeShippedContentCurrent {
  param([string]$SourceRoot, [string]$InstalledRoot)
  if (-not (Test-Path -LiteralPath $InstalledRoot -PathType Container)) { return $false }
  $sourceManifestPath = Join-Path $SourceRoot 'MANIFEST.json'
  $installedManifestPath = Join-Path $InstalledRoot 'MANIFEST.json'
  if (-not (Test-Path -LiteralPath $sourceManifestPath -PathType Leaf)) { throw "Bundled Forge MANIFEST.json missing: $sourceManifestPath" }
  if (-not (Test-Path -LiteralPath $installedManifestPath -PathType Leaf)) { return $false }

  $sourceManifestHash = (Get-FileHash -LiteralPath $sourceManifestPath -Algorithm SHA256).Hash
  $installedManifestHash = (Get-FileHash -LiteralPath $installedManifestPath -Algorithm SHA256).Hash
  if ($sourceManifestHash -ine $installedManifestHash) { return $false }

  $manifest = [IO.File]::ReadAllText($sourceManifestPath) | ConvertFrom-Json
  foreach ($entry in @($manifest.files)) {
    $relative = ([string]$entry.path) -replace '/', '\'
    $installedFile = Join-Path $InstalledRoot $relative
    if (-not (Test-Path -LiteralPath $installedFile -PathType Leaf)) { return $false }
    if ((Get-Item -LiteralPath $installedFile).Length -ne [long]$entry.size) { return $false }
    $actualHash = (Get-FileHash -LiteralPath $installedFile -Algorithm SHA256).Hash
    if ($actualHash -ine [string]$entry.sha256) { return $false }
  }
  return $true
}

$refreshRequired = -not (Test-ForgeShippedContentCurrent -SourceRoot $source -InstalledRoot $target)
if ($refreshRequired) {
  Write-Host '  .. Skyrim Forge shipped content differs from this bundle; refreshing source tree (same-version hotfixes included)' -ForegroundColor DarkCyan
  $base = Split-Path -Parent $target
  New-Item -ItemType Directory -Force -Path $base | Out-Null
  $stage = Join-Path $base ('.forge-stage-' + [guid]::NewGuid().ToString('N'))
  $backup = $target + '.backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  try {
    Copy-Item -LiteralPath $source -Destination $stage -Recurse -Force
    if (-not (Test-Path -LiteralPath (Join-Path $stage 'Install-or-Update.ps1') -PathType Leaf)) { throw 'Staged Forge tree is incomplete.' }
    if (Test-Path -LiteralPath $target -PathType Container) {
      foreach ($keep in $preserve) {
        $from = Join-Path $target $keep
        if (-not (Test-Path -LiteralPath $from)) { continue }
        $to = Join-Path $stage $keep
        if (Test-Path -LiteralPath $to) { Remove-Item -LiteralPath $to -Recurse -Force }
        Move-Item -LiteralPath $from -Destination $to
      }
      Move-Item -LiteralPath $target -Destination $backup
    }
    try { Move-Item -LiteralPath $stage -Destination $target }
    catch {
      if ((Test-Path -LiteralPath $backup) -and -not (Test-Path -LiteralPath $target)) { Move-Item -LiteralPath $backup -Destination $target }
      throw
    }
    if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
  } finally { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue }
} else {
  Write-Host '  OK  Skyrim Forge shipped content already matches this bundle exactly' -ForegroundColor Green
}

& (Join-Path $target 'Install-or-Update.ps1') -BootstrapPython

$bundleCatalog = $null
if ($BundleOwnsProviderSkills) {
  $bundleCatalog = [IO.File]::ReadAllText($catalogPath) | ConvertFrom-Json
}

foreach ($provider in $Providers) {
  if ($BundleOwnsProviderSkills) {
    # The all-in-one bundle already installed the canonical skill. Preserve that
    # single writer and add only Forge's per-machine launch descriptor beside it.
    $providerSkill = Join-Path (Get-UabsProviderSkillsDir -Provider $provider -Catalog $bundleCatalog) 'skyrim-forge'
    $providerSkillMd = Join-Path $providerSkill 'SKILL.md'
    if (-not (Test-Path -LiteralPath $providerSkillMd -PathType Leaf)) {
      throw "Expected bundle-owned Forge skill is missing for ${provider}: $providerSkillMd"
    }
    $descriptorSource = Join-Path $target 'INSTALLATION.json'
    if (-not (Test-Path -LiteralPath $descriptorSource -PathType Leaf)) {
      throw "Forge installation descriptor missing after install: $descriptorSource"
    }
    Copy-Item -LiteralPath $descriptorSource -Destination (Join-Path $providerSkill 'INSTALLATION.json') -Force
    Write-Host ("  OK  {0}: bundle-owned Forge skill preserved; descriptor refreshed" -f $provider) -ForegroundColor Green
  } else {
    & (Join-Path $target 'Install-Forge-Skill.ps1') -Provider $provider
  }
  if (-not $BundleOwnsProviderSkills) {
    & (Join-Path $target 'Register-MCP.ps1') -Provider $provider -Yes -ReportPath (Join-Path $target ("REGISTER-$provider.json"))
  }
}

if ($BundleOwnsProviderSkills) {
  Write-Host '  OK  Skyrim Forge installed but not registered globally; the bundle game-skyrim profile owns MCP activation' -ForegroundColor Green
}

# ---- Prove it actually runs ---------------------------------------------
# Not a version handshake. Forge and this installer ship in the same commit, so
# a negotiated compatibility range between them cannot fail for a real reason --
# it can only go stale and start rejecting the pack it lives inside, which is
# one edit away from the 7.8.0 bug. `doctor` answers a question that can still
# genuinely be no: does this install run, find its native helper, and read its
# config? TESTS/test_release_contract.py checks that every field read below is
# one Forge actually emits.
$python = Join-Path $target '.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Forge venv Python is missing after installation.' }
$installedText = [IO.File]::ReadAllText((Join-Path $target 'VERSION.txt'))
if ($installedText -notmatch ('(?m)^Skyrim Forge\s+' + [regex]::Escape($forgeVersion) + '\s*$')) {
  throw "Installed Forge is not the version this pack ships ($forgeVersion): $target"
}
$prevEap=$ErrorActionPreference; $ErrorActionPreference='Continue'
$doctorRaw = (& $python -m skyrim_forge doctor 2>&1 | Out-String)
$ErrorActionPreference=$prevEap
if ($LASTEXITCODE -ne 0) { throw "Forge doctor failed after installation.`n$doctorRaw" }
$doctor = $doctorRaw | ConvertFrom-Json
if ($doctor.result -ne 'PASS') { throw "Forge doctor reports $($doctor.result) after installation.`n$doctorRaw" }
if (-not $doctor.read_only_ready) { throw "Forge installed but is not read-only ready.`n$doctorRaw" }

[Environment]::SetEnvironmentVariable('SKYRIM_FORGE_ROOT',$target,'User')
$env:SKYRIM_FORGE_ROOT = $target
Write-Host ("  OK  Skyrim Forge $forgeVersion installed and healthy -> $target") -ForegroundColor Green
