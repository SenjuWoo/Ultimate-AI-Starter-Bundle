<#
.SYNOPSIS
  Remove what THIS pack left behind: retired skills and unbounded backups.

.DESCRIPTION
  Two problems, both created by the installer and never cleaned up by it.

  1. RETIRED SKILLS. The installer copies the canonical tree into every
     provider's skills directory but has never removed a skill the pack stopped
     shipping. A machine installed against v7 still carries the v7 names.
     Measured at v8.2.0 on the maintainer's machine: seven retired skills in
     three provider trees, twenty-one directories, each one loaded and offered
     to the agent NEXT TO the skill that replaced it. Two skills claiming KID
     syntax, and the retired one documents the older dialect.

  2. BACKUPS WITHOUT A CEILING. Every run writes config.toml.bak-*,
     AGENTS.md.before-soul-*.bak, settings.json.bak-gate-* and an install log.
     Nothing ever prunes them. Measured on the same machine: 217 files, 2.1 MB,
     86 of them Grok config backups. They are inert, but "inert and unbounded"
     is still a defect, and it buries the one backup someone might actually
     want to restore.

  3. LEFTOVERS OF OLDER VERSIONS in the pack's own state folder: companion
     archives superseded by the one downloads\companions.json records, Go
     archives under the pre-8.24 name, state files a named newer file
     replaced, and parked ponytail duplicates byte-identical to the archived
     copy (which stays). Plus one registration fix: a Claude extraKnownMarketplaces entry
     for a bundled plugin that still points into a pack folder that no longer
     exists (an older install ran from ...-v8.21.0) is repointed to this pack.

  A backup is never one of these. Backups are only pruned by the retention
  limit below; a live toolchain directory and its backups are never touched.

  It also REPORTS, without touching, boot-time autostarts for AI tooling whose
  target no longer exists -- the pack has never written an autostart, so those
  are not its to remove, but a launcher that fails at every boot is worth
  naming.

  DELETION IS LIMITED TO WHAT THIS PACK CREATED. A retired skill is removed
  only when its name is in BUNDLED-TOOLS/RETIRED-SKILLS.json AND the directory
  looks like a copy this pack made. Backups are matched on the pack's own
  naming patterns. Anything else -- plugin-provided skills, the optional
  Other-Games mega-pack, a user's own files -- is REPORTED, never touched.

.PARAMETER Apply
  Perform the deletions. Without this, print the plan and change nothing.

.PARAMETER KeepBackups
  How many backups to keep per family (newest first). Default 3.

.PARAMETER KeepLogs
  How many install logs to keep. Default 5.

.PARAMETER SkipSkills
  Leave retired skills alone; prune backups only.
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [ValidateRange(0, 100)][int]$KeepBackups = 3,
  [ValidateRange(1, 200)][int]$KeepLogs = 5,
  [switch]$SkipSkills,
  [string]$PackRoot
)

$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')

function Remove-UabsRetiredRegistration {
  param([object]$Edit, [switch]$WhatIfOnly)
  $file = [string]$Edit.File
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return $false }
  if ($WhatIfOnly) { return $true }

  # Back up before editing anyone's config, every time.
  $stamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
  try { Copy-Item -LiteralPath $file -Destination ($file + '.bak-retired-' + $stamp) -Force } catch { }

  if ($Edit.Format -eq 'toml-table') {
    $lines = [IO.File]::ReadAllLines($file)
    $out = New-Object System.Collections.Generic.List[string]
    $skip = $false
    $head = '[marketplaces.' + $Edit.Key + ']'
    $pluginSuffix = '@' + $Edit.Key + '"]'
    foreach ($ln in $lines) {
      $t = $ln.Trim()
      if ($t.StartsWith('[')) {
        # A new table always ends any skip; then decide about this one.
        $skip = $false
        if ($t -eq $head) { $skip = $true }
        elseif ($t.StartsWith('[plugins."') -and $t.EndsWith($pluginSuffix)) { $skip = $true }
      }
      if (-not $skip) { [void]$out.Add($ln) }
    }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [IO.File]::WriteAllLines($file, $out, $enc)
    return $true
  }

  # JSON: drop one top-level key, or one key under extraKnownMarketplaces.
  $obj = $null
  try { $obj = [IO.File]::ReadAllText($file) | ConvertFrom-Json } catch { return $false }
  if ($Edit.Format -eq 'json-key') {
    if (-not ($obj.PSObject.Properties.Name -contains $Edit.Key)) { return $false }
    $obj.PSObject.Properties.Remove($Edit.Key)
  } elseif ($Edit.Format -eq 'json-extra-marketplace') {
    if (-not $obj.extraKnownMarketplaces) { return $false }
    if (-not ($obj.extraKnownMarketplaces.PSObject.Properties.Name -contains $Edit.Key)) { return $false }
    $obj.extraKnownMarketplaces.PSObject.Properties.Remove($Edit.Key)
  } elseif ($Edit.Format -eq 'json-extra-marketplace-path') {
    if (-not $obj.extraKnownMarketplaces) { return $false }
    $mp = $obj.extraKnownMarketplaces.PSObject.Properties[[string]$Edit.Key]
    if (-not $mp -or -not $mp.Value.source) { return $false }
    $mp.Value.source.path = [string]$Edit.NewPath
  } else {
    return $false
  }
  $enc2 = New-Object System.Text.UTF8Encoding($false)
  [IO.File]::WriteAllText($file, (($obj | ConvertTo-Json -Depth 32)), $enc2)
  return $true
}

$script:Planned = New-Object System.Collections.Generic.List[object]
$script:Reported = New-Object System.Collections.Generic.List[string]
$script:FreedBytes = 0

function Add-CleanTarget {
  param([string]$Kind, [string]$Path, [string]$Why)
  $size = 0
  try {
    if (Test-Path -LiteralPath $Path -PathType Container) {
      $size = (Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue |
               Measure-Object -Property Length -Sum).Sum
    } elseif (Test-Path -LiteralPath $Path -PathType Leaf) {
      $size = (Get-Item -LiteralPath $Path).Length
    }
  } catch { }
  if (-not $size) { $size = 0 }
  $script:FreedBytes += $size
  [void]$script:Planned.Add([pscustomobject]@{ Kind = $Kind; Path = $Path; Why = $Why; Bytes = $size })
}

# ---------------------------------------------------------------- skills ----
$providerSkillDirs = [ordered]@{
  Claude = Join-Path $env:USERPROFILE '.claude\skills'
  Codex  = Join-Path $env:USERPROFILE '.agents\skills'
  Grok   = Join-Path $env:USERPROFILE '.grok\skills'
  Kimi   = Join-Path $env:USERPROFILE '.kimi-code\skills'
  Hermes = Join-Path $env:LOCALAPPDATA 'hermes\skills'
}
# Hermes named profiles keep their own cloned skills folder; the managed ones
# carried ~72 retired skills each that the default folder had long shed.
$soulSource = Join-Path $PackRoot '3-PREAMBLES\SOUL.md'
if (Test-Path -LiteralPath $soulSource -PathType Leaf) {
  foreach ($pf in @(Get-UabsHermesManagedProfiles -HermesHome (Join-Path $env:LOCALAPPDATA 'hermes') -SoulFile $soulSource -RequireSkills)) {
    $providerSkillDirs[('Hermes.' + $pf.Name)] = Join-Path $pf.FullName 'skills'
  }
}

$retiredPath = Join-Path $PackRoot 'BUNDLED-TOOLS\RETIRED-SKILLS.json'
$retired = @()
if (Test-Path -LiteralPath $retiredPath -PathType Leaf) {
  $retired = @(([IO.File]::ReadAllText($retiredPath) | ConvertFrom-Json).retired)
} else {
  Write-UabsWarn "RETIRED-SKILLS.json not found - skipping retired-skill cleanup"
}

$script:OwnerStamped = @{}
$script:OwnerStampedCount = 0
if (-not $SkipSkills -and $retired.Count) {
  # Ownership receipts written by Sync-UabsProviderSkills: provider -> name -> tree digest.
  $skillLedger = @{}
  $managedDir = Join-Path (Get-UabsStateRoot) 'managed-skills'
  if (Test-Path -LiteralPath $managedDir -PathType Container) {
    foreach ($f in @(Get-ChildItem -LiteralPath $managedDir -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
      try {
        $doc = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json
        if (-not $doc.provider) { continue }
        $map = @{}
        foreach ($s in @($doc.skills)) { if ($s.name) { $map[[string]$s.name] = [string]$s.digest } }
        $skillLedger[[string]$doc.provider] = $map
      } catch { Write-UabsWarn ('managed-skill receipt unreadable, nothing removed for it: ' + $f.Name) }
    }
  }
  $canonical = @{}
  $canonRoot = Join-Path $PackRoot '_CANONICAL-SKILLS'
  if (Test-Path -LiteralPath $canonRoot -PathType Container) {
    foreach ($d in Get-ChildItem -LiteralPath $canonRoot -Directory) { $canonical[$d.Name] = $true }
  }
  foreach ($provider in $providerSkillDirs.Keys) {
    $dir = $providerSkillDirs[$provider]
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
    $preserved = @(Get-UabsPreservedSkillNames -Provider $provider -SkillsDir $dir)
    $external = @((Get-UabsPackCatalog -PackRoot $PackRoot).packs.PSObject.Properties | Where-Object { $_.Value.owner } | ForEach-Object { $_.Value.skills })
    foreach ($entry in $retired) {
      if ($external -contains $entry.name) { continue }
      $name = [string]$entry.name
      if ($preserved -contains $name) {
        [void]$script:Reported.Add("$provider/$name has a verified local override - left alone")
        continue
      }
      # Never delete a name the pack currently ships. A retired list that has
      # drifted must not be able to remove a live skill.
      if ($canonical.ContainsKey($name)) {
        [void]$script:Reported.Add("$provider/$name is in RETIRED-SKILLS.json but ALSO in the canonical tree - left alone, regenerate the list")
        continue
      }
      $target = Join-Path $dir $name
      if (-not (Test-Path -LiteralPath $target -PathType Container)) { continue }
      # It must look like a skill this pack copied, not a coincidence.
      if (-not (Test-Path -LiteralPath (Join-Path $target 'SKILL.md') -PathType Leaf)) {
        [void]$script:Reported.Add("$provider/$name has no SKILL.md - not recognizably ours, left alone")
        continue
      }
      # A forge reinstalls some retired names itself (RobloxForge stamps .rbforge-version); that copy is its, not ours.
      # Counted, then reported once: one line per provider and profile was 20 lines of noise per install.
      $stamp = @(Get-ChildItem -LiteralPath $target -File -Force -Filter '.*-version' -ErrorAction SilentlyContinue | Select-Object -First 1)
      if ($stamp.Count) {
        $script:OwnerStamped[$name] = $stamp[0].Name
        $script:OwnerStampedCount++
        continue
      }
      $successor = if ($entry.superseded_by) { "superseded by $($entry.superseded_by)" } else { 'retired, no successor' }
      # Ownership proof: the installer records the tree digest of every skill it
      # copied (managed-skills\<provider>.json). A name plus a SKILL.md is not
      # evidence - a user's own skill can carry a retired name. No receipt, or a
      # digest that no longer matches, means it is not ours to delete.
      $ledgerEntry = $null
      if ($skillLedger.ContainsKey($provider) -and $skillLedger[$provider].ContainsKey($name)) { $ledgerEntry = $skillLedger[$provider][$name] }
      if (-not $ledgerEntry) {
        [void]$script:Reported.Add("$provider/$name has no bundle ownership receipt - left alone")
        continue
      }
      if ((Get-UabsTreeDigest $target) -cne $ledgerEntry) {
        [void]$script:Reported.Add("$provider/$name was modified since this pack installed it - left alone")
        continue
      }
      Add-CleanTarget -Kind "skill/$provider" -Path $target -Why $successor
    }
  }
  if ($script:OwnerStampedCount) {
    $named = @($script:OwnerStamped.Keys | Sort-Object | ForEach-Object { "$_ ($($script:OwnerStamped[$_]))" }) -join ', '
    [void]$script:Reported.Add(("{0} copies of retired names each carries an owner stamp - another tool's copy, left alone: {1}" -f $script:OwnerStampedCount, $named))
  }
}

# --------------------------------------------------------------- backups ----
# Families are (directory, glob). Everything here is written by this pack's own
# installers; a user's file does not match these names by accident.
$backupFamilies = @(
  @{ Dir = (Join-Path $env:USERPROFILE '.grok');      Glob = 'config.toml.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.grok');      Glob = 'AGENTS.md.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.codex');     Glob = 'config.toml.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.codex');     Glob = 'AGENTS.md.*bak*' }
  @{ Dir = (Get-UabsProviderHome -Provider Codex -Catalog (Get-UabsCatalog)); Glob = 'hooks.json.before-retired-*.bak' }
  @{ Dir = (Join-Path $env:USERPROFILE '.claude');    Glob = 'settings.json.bak*' }
  @{ Dir = $env:USERPROFILE;                          Glob = '.claude.json.bak-mcp-*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.claude');    Glob = 'CLAUDE.md.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.kimi-code'); Glob = 'AGENTS.md.*bak*' }
  @{ Dir = (Join-Path $env:USERPROFILE '.kimi-code'); Glob = 'mcp.json.bak*' }
  @{ Dir = (Join-Path $env:LOCALAPPDATA 'hermes');    Glob = 'config.yaml.bak*' }
  @{ Dir = (Join-Path $env:LOCALAPPDATA 'hermes');    Glob = 'SOUL.md.*bak*' }
  # Install-UabsRtkExecutable keeps the replaced binary beside the new one.
  @{ Dir = (Join-Path $env:USERPROFILE '.local\bin'); Glob = 'rtk.exe.bak-uabs-*' }
)
if (Test-Path -LiteralPath $soulSource -PathType Leaf) {
  foreach ($pf in @(Get-UabsHermesManagedProfiles -HermesHome (Join-Path $env:LOCALAPPDATA 'hermes') -SoulFile $soulSource)) {
    $backupFamilies += @{ Dir = $pf.FullName; Glob = 'SOUL.md.*bak*' }
  }
}

foreach ($family in $backupFamilies) {
  if (-not (Test-Path -LiteralPath $family.Dir -PathType Container)) { continue }
  $files = @(Get-ChildItem -LiteralPath $family.Dir -Filter $family.Glob -File -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTimeUtc -Descending)
  if ($files.Count -le $KeepBackups) { continue }
  foreach ($old in $files[$KeepBackups..($files.Count - 1)]) {
    Add-CleanTarget -Kind 'backup' -Path $old.FullName -Why "older than the $KeepBackups most recent $($family.Glob)"
  }
}

# Install logs and profile-migration backups the pack writes under LOCALAPPDATA.
$uabsRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
$logDir = Join-Path $uabsRoot 'logs'
if (Test-Path -LiteralPath $logDir -PathType Container) {
  $logs = @(Get-ChildItem -LiteralPath $logDir -Filter 'install-*.log' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending)
  if ($logs.Count -gt $KeepLogs) {
    foreach ($old in $logs[$KeepLogs..($logs.Count - 1)]) {
      Add-CleanTarget -Kind 'log' -Path $old.FullName -Why "older than the $KeepLogs most recent install logs"
    }
  }
}
$profileBackups = Join-Path $uabsRoot 'backups\hermes-profiles'
if (Test-Path -LiteralPath $profileBackups -PathType Container) {
  $snaps = @(Get-ChildItem -LiteralPath $profileBackups -Directory -ErrorAction SilentlyContinue |
             Sort-Object Name -Descending)
  if ($snaps.Count -gt $KeepBackups) {
    foreach ($old in $snaps[$KeepBackups..($snaps.Count - 1)]) {
      Add-CleanTarget -Kind 'backup' -Path $old.FullName -Why "older than the $KeepBackups most recent Hermes profile snapshots"
    }
  }
}

# The plugin-owned-skill dedupe writes backups\dedupe-<Provider>-<stamp>\ on
# EVERY install and nothing ever pruned them. This is by far the largest family:
# measured at 160 directories and 52 MB on the maintainer's machine, against
# 2.1 MB for every .bak file combined. Keep the newest per provider, because a
# rollback is only ever wanted for the install that just ran.
$backupsRoot = Join-Path $uabsRoot 'backups'
if (Test-Path -LiteralPath $backupsRoot -PathType Container) {
  $dedupe = @(Get-ChildItem -LiteralPath $backupsRoot -Directory -Filter 'dedupe-*' -ErrorAction SilentlyContinue)
  foreach ($group in ($dedupe | Group-Object { ($_.Name -split '-')[1] })) {
    $ordered = @($group.Group | Sort-Object Name -Descending)
    if ($ordered.Count -le $KeepBackups) { continue }
    foreach ($old in $ordered[$KeepBackups..($ordered.Count - 1)]) {
      Add-CleanTarget -Kind 'backup' -Path $old.FullName -Why "older than the $KeepBackups most recent $($group.Name) dedupe snapshots"
    }
  }
}

# The npm duplicate cleanup keeps a verified copy of the older package it removed
# (npm-rollback\<package>-<version>-<stamp>). Like the dedupe snapshots, only the
# newest per package is worth keeping.
$npmRollback = Join-Path $uabsRoot 'npm-rollback'
if (Test-Path -LiteralPath $npmRollback -PathType Container) {
  $copies = @(Get-ChildItem -LiteralPath $npmRollback -Directory -ErrorAction SilentlyContinue)
  foreach ($group in ($copies | Group-Object { $_.Name -replace '-\d+\.\d+.*$', '' })) {
    $ordered = @($group.Group | Sort-Object Name -Descending)
    if ($ordered.Count -le $KeepBackups) { continue }
    foreach ($old in $ordered[$KeepBackups..($ordered.Count - 1)]) {
      Add-CleanTarget -Kind 'backup' -Path $old.FullName -Why "older than the $KeepBackups most recent $($group.Name) npm recovery copies"
    }
  }
}

# ------------------------------------------- older-version leftovers ------
# Files an older version of this pack wrote under its own state folder that no
# current code reads. Each is named with what replaced it, none is a backup, and
# a file is only removed when its replacement is present.
$supersededState = @(
  @{ Name = 'ponytail-mode.json'; ReplacedBy = 'ponytail-mode\state.json'; Since = '8.37.21' }
)
foreach ($s in $supersededState) {
  $oldFile = Join-Path $uabsRoot $s.Name
  if ((Test-Path -LiteralPath $oldFile -PathType Leaf) -and
      (Test-Path -LiteralPath (Join-Path $uabsRoot $s.ReplacedBy) -PathType Leaf)) {
    Add-CleanTarget -Kind 'superseded' -Path $oldFile -Why ("replaced by {0} in {1}" -f $s.ReplacedBy, $s.Since)
  }
}

# Companion archives of versions that are no longer current. downloads\companions.json
# records the archive each companion was last installed from; an older
# <Name>-<version>.zip of the same companion is never read again. With no
# readable record there is no evidence, so nothing is planned.
$downloadsDir = Join-Path $uabsRoot 'downloads'
$downloadRecord = Join-Path $downloadsDir 'companions.json'
if (Test-Path -LiteralPath $downloadRecord -PathType Leaf) {
  $currentAssets = $null
  try {
    $currentAssets = @(([IO.File]::ReadAllText($downloadRecord) | ConvertFrom-Json).companions |
                       ForEach-Object { [string]$_.asset } | Where-Object { $_ })
  } catch { $currentAssets = $null }
  if ($currentAssets -and $currentAssets.Count) {
    $currentBases = @($currentAssets | ForEach-Object { $_ -replace '-\d+(\.\d+)+\.zip$', '' })
    foreach ($zip in @(Get-ChildItem -LiteralPath $downloadsDir -File -Filter '*.zip' -ErrorAction SilentlyContinue)) {
      if ($currentAssets -contains $zip.Name) { continue }
      if ($zip.Name -notmatch '^(.+)-\d+(\.\d+)+\.zip$') { continue }
      $base = $Matches[1]
      if ($currentBases -notcontains $base) { continue }   # only an older version of a recorded companion
      $kept = @($currentAssets | Where-Object { $_ -like ($base + '-*') }) -join ', '
      Add-CleanTarget -Kind 'stale-download' -Path $zip.FullName -Why ('superseded by ' + $kept)
    }
  }
}

# Ponytail's parking quarantine. Before 8.44.8 every install re-copied the parked
# ponytail skills and parking moved each identical copy into
# ponytail-mode\parked\<provider>\_duplicates: about 1,800 folders on one machine.
# A duplicate whose bytes equal the archived copy beside it adds nothing; that
# archived copy (the backup) always stays, and a duplicate that differs is kept.
$parkRoot = Join-Path $uabsRoot 'ponytail-mode\parked'
if (Test-Path -LiteralPath $parkRoot -PathType Container) {
  foreach ($parkProv in @(Get-ChildItem -LiteralPath $parkRoot -Directory -ErrorAction SilentlyContinue)) {
    $dupDir = Join-Path $parkProv.FullName '_duplicates'
    if (-not (Test-Path -LiteralPath $dupDir -PathType Container)) { continue }
    $archived = @{}
    foreach ($arch in @(Get-ChildItem -LiteralPath $parkProv.FullName -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -ne '_duplicates' })) {
      $skillName = ($arch.Name -split '__')[0]
      if (-not $archived.ContainsKey($skillName)) { $archived[$skillName] = @() }
      $archived[$skillName] += (Get-UabsTreeDigest $arch.FullName)
    }
    foreach ($dup in @(Get-ChildItem -LiteralPath $dupDir -Directory -ErrorAction SilentlyContinue)) {
      $skillName = ($dup.Name -split '__')[0]
      if (-not $archived.ContainsKey($skillName)) { continue }
      if ($archived[$skillName] -contains (Get-UabsTreeDigest $dup.FullName)) {
        Add-CleanTarget -Kind 'parked-duplicate' -Path $dup.FullName -Why ('identical to the archived ' + $skillName + ' copy, which is kept')
      }
    }
  }
}

# Go archives under the pre-8.24 name (go<version>.zip). Since 8.24 the download
# cache is toolchains\go-current.zip, so the old archive is never read. Only
# files are considered: directories hold the live SDK and its backups.
$toolchainsDir = Join-Path $uabsRoot 'toolchains'
if (Test-Path -LiteralPath $toolchainsDir -PathType Container) {
  foreach ($zip in @(Get-ChildItem -LiteralPath $toolchainsDir -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '^go\d+(\.\d+)+\.zip$' })) {
    Add-CleanTarget -Kind 'stale-toolchain' -Path $zip.FullName -Why 'pre-8.24 Go archive name; the cache is go-current.zip'
  }
}

# ------------------------------------------------------------ autostarts ----
# Boot-time launchers for AI tooling are REPORTED, never planned for deletion.
# The rule at the top of this file is that deletion is limited to what this
# pack created, and this pack has never written an autostart -- these come from
# agent sessions, other tools' installers, and the user. A dead one still gets
# named, because it costs a failed process launch at every boot.
# ------------------------------------------- retired plugin marketplaces ---
# Marketplace registration is ADDITIVE in every provider: the installer only
# ever adds to extraKnownMarketplaces, and nothing removes an entry when the
# tool behind it is uninstalled. So a dead registration lives forever -- and it
# propagates, because Grok inherits Claude's marketplace list. One stale entry
# in ~/.claude becomes a failing entry in ~/.grok the user never registered.
#
# Measured 2026-08-27: claude-mem was long uninstalled, yet 'thedotmack' was
# still in Claude's known_marketplaces.json and settings.json, still cloned at
# 140 MB, still present as four orphaned 140 MB temp clones, and had synced
# into ~/.grok/marketplace-cache, where grok reported
#   thedotmack (0 plugins) [error] Git sync failed: failed to lock cache
#
# Safety, deliberately narrow: a marketplace is only touched when its NAME and
# its GIT URL both match an entry in RETIRED-PLUGINS.json, and when it
# contributes no ENABLED plugin. Anything still in use is reported, not removed.
$retiredPluginsPath = Join-Path $PackRoot 'BUNDLED-TOOLS\RETIRED-PLUGINS.json'
$retiredMarkets = @()
if (Test-Path -LiteralPath $retiredPluginsPath -PathType Leaf) {
  try { $retiredMarkets = @(([IO.File]::ReadAllText($retiredPluginsPath) | ConvertFrom-Json).retired) }
  catch { Write-UabsWarn "RETIRED-PLUGINS.json unreadable - skipping marketplace cleanup" }
} else {
  Write-UabsWarn "RETIRED-PLUGINS.json not found - skipping marketplace cleanup"
}

$script:RetiredRegistrationEdits = New-Object System.Collections.Generic.List[object]

function Test-UabsUrlMatch {
  param([string]$A, [string]$B)
  if (-not $A -or -not $B) { return $false }
  $na = $A.Trim().TrimEnd('/'); $nb = $B.Trim().TrimEnd('/')
  if ($na.EndsWith('.git')) { $na = $na.Substring(0, $na.Length - 4) }
  if ($nb.EndsWith('.git')) { $nb = $nb.Substring(0, $nb.Length - 4) }
  return [string]::Equals($na, $nb, [StringComparison]::OrdinalIgnoreCase)
}

if ($retiredMarkets.Count) {

  # ---- Claude: known_marketplaces.json + settings.json + the clones --------
  $claudeHome = Join-Path $env:USERPROFILE '.claude'
  $kmPath = Join-Path $claudeHome 'plugins\known_marketplaces.json'
  $settingsPath = Join-Path $claudeHome 'settings.json'
  # A marketplace is only dead if nothing it provides is still around. Two
  # signals, because they answer different questions: enabledPlugins says the
  # user switched it on, installed_plugins.json says it is on disk at all.
  #
  # This matters for a component the pack still SHIPS. claude-mem is opt-in
  # behind -WithClaudeMem and its catalog entry registers the very marketplace
  # listed as retired here. Without the installed check, the cleanup that runs
  # at the end of every install would unregister what that same install had
  # just registered -- the installer and the cleaner fighting each other on
  # every run.
  $enabledNames = @()
  if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
    try {
      $sj = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
      if ($sj.enabledPlugins) {
        foreach ($pp in $sj.enabledPlugins.PSObject.Properties) {
          if ($pp.Value) { $enabledNames += ([string]$pp.Name) }
        }
      }
    } catch { }
  }
  $installedNames = @()
  $installedPluginsPath = Join-Path $claudeHome 'plugins\installed_plugins.json'
  if (Test-Path -LiteralPath $installedPluginsPath -PathType Leaf) {
    try {
      $ip = [IO.File]::ReadAllText($installedPluginsPath) | ConvertFrom-Json
      if ($ip.plugins) {
        foreach ($pp in $ip.plugins.PSObject.Properties) { $installedNames += ([string]$pp.Name) }
      }
    } catch { }
  }

  foreach ($entry in $retiredMarkets) {
    $name = [string]$entry.marketplace
    if (-not $name) { continue }

    # Never remove a marketplace that still backs an ENABLED plugin.
    $stillUsed = @($enabledNames | Where-Object { $_ -like ('*@' + $name) })
    $stillUsed += @($installedNames | Where-Object { $_ -like ('*@' + $name) })
    $stillUsed = @($stillUsed | Select-Object -Unique)
    if ($stillUsed.Count) {
      [void]$script:Reported.Add(
        ("marketplace '{0}' is retired but is still installed or enabled as: {1} -- left alone" -f $name, ($stillUsed -join ', ')))
      continue
    }

    # known_marketplaces.json -- match name AND url before proposing an edit.
    if (Test-Path -LiteralPath $kmPath -PathType Leaf) {
      try {
        $km = [IO.File]::ReadAllText($kmPath) | ConvertFrom-Json
        $prop = $km.PSObject.Properties | Where-Object { $_.Name -eq $name } | Select-Object -First 1
        if ($prop) {
          $url = ''
          try { $url = [string]$prop.Value.source.url } catch { $url = '' }
          if (Test-UabsUrlMatch $url ([string]$entry.url)) {
            [void]$script:RetiredRegistrationEdits.Add([pscustomobject]@{
              File = $kmPath; Format = 'json-key'; Key = $name
              Why = ("retired marketplace ({0})" -f $entry.reason)
            })
          } else {
            [void]$script:Reported.Add(
              ("marketplace '{0}' in known_marketplaces.json points at '{1}', not the retired '{2}' -- left alone" -f $name, $url, $entry.url))
          }
        }
      } catch { }
    }

    # settings.json -> extraKnownMarketplaces
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
      try {
        $sj2 = [IO.File]::ReadAllText($settingsPath) | ConvertFrom-Json
        if ($sj2.extraKnownMarketplaces) {
          $ep = $sj2.extraKnownMarketplaces.PSObject.Properties | Where-Object { $_.Name -eq $name } | Select-Object -First 1
          if ($ep) {
            $url2 = ''
            try { $url2 = [string]$ep.Value.source.url } catch { $url2 = '' }
            if (Test-UabsUrlMatch $url2 ([string]$entry.url)) {
              [void]$script:RetiredRegistrationEdits.Add([pscustomobject]@{
                File = $settingsPath; Format = 'json-extra-marketplace'; Key = $name
                Why = ("retired marketplace ({0})" -f $entry.reason)
              })
            }
          }
        }
      } catch { }
    }

    # The clone and any plugin cache under Claude.
    foreach ($sub in @('plugins\marketplaces', 'plugins\cache')) {
      $dir = Join-Path (Join-Path $claudeHome $sub) $name
      if (Test-Path -LiteralPath $dir -PathType Container) {
        Add-CleanTarget -Kind 'retired-market' -Path $dir -Why ("clone of retired marketplace " + $name)
      }
    }

    # ---- Grok: cache directories are hashed, so match on the git remote ----
    $grokCache = Join-Path $env:USERPROFILE '.grok\marketplace-cache'
    if (Test-Path -LiteralPath $grokCache -PathType Container) {
      foreach ($d in @(Get-ChildItem -LiteralPath $grokCache -Directory -EA SilentlyContinue)) {
        $gitCfg = Join-Path $d.FullName '.git\config'
        if (-not (Test-Path -LiteralPath $gitCfg -PathType Leaf)) { continue }
        $cfgText = ''
        try { $cfgText = [IO.File]::ReadAllText($gitCfg) } catch { continue }
        $m = [regex]::Match($cfgText, 'url\s*=\s*(\S+)')
        if (-not $m.Success) { continue }
        if (Test-UabsUrlMatch $m.Groups[1].Value ([string]$entry.url)) {
          Add-CleanTarget -Kind 'retired-market' -Path $d.FullName -Why ("Grok cache of retired marketplace " + $name)
          $lock = $d.FullName + '.lock'
          if (Test-Path -LiteralPath $lock -PathType Leaf) {
            Add-CleanTarget -Kind 'retired-market' -Path $lock -Why ("stale lock for retired marketplace " + $name)
          }
        }
      }
    }

    # ---- Codex: [marketplaces.<name>] and [plugins."<x>@<name>"] ----------
    $codexCfg = Join-Path $env:USERPROFILE '.codex\config.toml'
    if (Test-Path -LiteralPath $codexCfg -PathType Leaf) {
      $toml = ''
      try { $toml = [IO.File]::ReadAllText($codexCfg) } catch { $toml = '' }
      if ($toml -match ('(?m)^\[marketplaces\.' + [regex]::Escape($name) + '\]')) {
        [void]$script:RetiredRegistrationEdits.Add([pscustomobject]@{
          File = $codexCfg; Format = 'toml-table'; Key = $name
          Why = ("retired marketplace ({0})" -f $entry.reason)
        })
      }
    }
  }

  # Orphaned temp clones: Claude leaves temp_<epoch> directories behind when a
  # marketplace sync is interrupted. Four of them, 140 MB each, were sitting in
  # marketplaces/ with no entry in known_marketplaces.json pointing at any.
  $mkRoot = Join-Path $claudeHome 'plugins\marketplaces'
  if (Test-Path -LiteralPath $mkRoot -PathType Container) {
    $known = @()
    if (Test-Path -LiteralPath $kmPath -PathType Leaf) {
      try { $known = @(([IO.File]::ReadAllText($kmPath) | ConvertFrom-Json).PSObject.Properties.Name) } catch { }
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $mkRoot -Directory -EA SilentlyContinue)) {
      if ($d.Name -notmatch '^temp_\d+$') { continue }
      if ($known -contains $d.Name) { continue }
      Add-CleanTarget -Kind 'orphan-market' -Path $d.FullName -Why 'interrupted marketplace sync, registered nowhere'
    }
  }
}

# ------------------------------------ bundled marketplaces at a dead path ---
# An older version registered the bundled plugins (superpowers-dev, ponytail) in
# Claude's extraKnownMarketplaces as a directory inside the pack folder it ran
# from. Renaming that folder (...-v8.21.0 -> ...) left the path dead, and the
# starter-settings merge only adds missing keys, so nothing ever corrected it.
# Only a directory source that no longer exists AND ends in
# BUNDLED-TOOLS\plugins\<id> AND has a copy in this pack is repointed; anything
# else is left alone. The file is backed up first like every other edit here.
$claudeSettingsPath = Join-Path $env:USERPROFILE '.claude\settings.json'
if (Test-Path -LiteralPath $claudeSettingsPath -PathType Leaf) {
  try {
    $csObj = [IO.File]::ReadAllText($claudeSettingsPath) | ConvertFrom-Json
    if ($csObj.extraKnownMarketplaces) {
      foreach ($mp in $csObj.extraKnownMarketplaces.PSObject.Properties) {
        $mpSource = $mp.Value.source
        if (-not $mpSource -or [string]$mpSource.source -ne 'directory') { continue }
        $deadPath = [string]$mpSource.path
        if (-not $deadPath -or (Test-Path -LiteralPath $deadPath)) { continue }
        if ($deadPath -notmatch '[\\/]BUNDLED-TOOLS[\\/]plugins[\\/]([^\\/]+)[\\/]?$') { continue }
        $freshPath = Join-Path $PackRoot ('BUNDLED-TOOLS\plugins\' + $Matches[1])
        if (-not (Test-Path -LiteralPath $freshPath -PathType Container)) { continue }
        [void]$script:RetiredRegistrationEdits.Add([pscustomobject]@{
          File = $claudeSettingsPath; Format = 'json-extra-marketplace-path'; Key = $mp.Name; NewPath = $freshPath
          Why = ('pack folder is gone (' + $deadPath + '); repointed to this pack')
        })
      }
    }
  } catch { Write-UabsWarn ('Claude settings.json unreadable; marketplace paths not checked: ' + $_.Exception.Message) }
}

$autostarts = @()
try { $autostarts = @(Get-UabsAiAutostartEntries) } catch { }
foreach ($a in $autostarts) {
  if ($a.Dead) {
    [void]$script:Reported.Add(
      ("autostart '{0}' ({1}) runs at every boot but its target is gone: {2} -- not ours to delete; remove it yourself via  explorer shell:startup" -f `
        $a.Name, $a.Source, ($a.MissingTargets -join '; ')))
  }
}

# ------------------------------------------------------- report / execute ---
Write-Host ''
Write-UabsStep $(if ($Apply) { 'Cleaning pack-created leftovers' } else { 'Leftover plan (nothing removed)' })

if (-not $script:Planned.Count -and -not $script:RetiredRegistrationEdits.Count) {
  Write-UabsOk 'Nothing to clean; no retired skills or marketplaces, no older-version leftovers, and no backups past the retention limit.'
} else {
  foreach ($group in ($script:Planned | Group-Object Kind | Sort-Object Name)) {
    $bytes = ($group.Group | Measure-Object -Property Bytes -Sum).Sum
    Write-Host ("  {0,-16} {1,3} item(s)  {2,8:N1} KB" -f $group.Name, $group.Count, ($bytes / 1KB))
    foreach ($item in $group.Group | Select-Object -First 6) {
      Write-Host ("      " + (Split-Path -Leaf $item.Path) + "  -- " + $item.Why) -ForegroundColor DarkGray
    }
    if ($group.Count -gt 6) { Write-Host ("      ... and " + ($group.Count - 6) + " more") -ForegroundColor DarkGray }
  }
  Write-Host ("  TOTAL            {0,3} item(s)  {1,8:N1} KB" -f $script:Planned.Count, ($script:FreedBytes / 1KB))
}

if ($script:RetiredRegistrationEdits.Count) {
  Write-Host ("  {0,-16} {1,3} registration(s) in provider config" -f 'marketplace', $script:RetiredRegistrationEdits.Count)
  foreach ($e in $script:RetiredRegistrationEdits) {
    Write-Host ("      " + $e.Key + "  in " + (Split-Path -Leaf $e.File) + "  -- " + $e.Why) -ForegroundColor DarkGray
  }
  Write-Host '      Each edited file is backed up alongside itself first.' -ForegroundColor DarkGray
}

foreach ($note in $script:Reported) { Write-UabsWarn $note }

if (-not $Apply) {
  if ($script:Planned.Count -or $script:RetiredRegistrationEdits.Count) {
    Write-Host ''
    Write-Host '  Nothing was removed. Re-run with -Apply to delete the items above.' -ForegroundColor Yellow
  }
  exit 0
}

$removed = 0
$failed = 0
foreach ($item in $script:Planned) {
  try {
    Remove-Item -LiteralPath $item.Path -Recurse -Force -ErrorAction Stop
    $removed++
  } catch {
    $failed++
    Write-UabsWarn ("could not remove " + $item.Path + ": " + $_.Exception.Message)
  }
}
$edited = 0
foreach ($e in $script:RetiredRegistrationEdits) {
  try {
    if (Remove-UabsRetiredRegistration -Edit $e) {
      $edited++
      $verb = if ($e.Format -eq 'json-extra-marketplace-path') { 'repointed' } else { 'unregistered' }
      Write-UabsOk ($verb + " '" + $e.Key + "' in " + (Split-Path -Leaf $e.File))
    }
  } catch {
    $failed++
    Write-UabsWarn ("could not unregister " + $e.Key + " from " + $e.File + ": " + $_.Exception.Message)
  }
}
Write-UabsOk ("removed $removed item(s), freed ~{0:N1} KB" -f ($script:FreedBytes / 1KB))
if ($edited) {
  Write-UabsOk "edited $edited marketplace registration(s)"
  Write-UabsWarn 'Close every AI app before trusting this: a running session holds its config in memory and writes it back on exit, which is how an earlier removal was undone.'
}
if ($failed) {
  Write-UabsWarn "$failed item(s) could not be removed (in use, or permission denied). Re-run after closing the AI apps."
}
exit 0
