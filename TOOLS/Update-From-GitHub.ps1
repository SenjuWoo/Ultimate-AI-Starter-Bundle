<#
.SYNOPSIS
  Update the stable bundle installation and re-run the AIO installer.
#>
[CmdletBinding()]
param(
  [string[]]$Components = @('housecarl','spooky','codebase-memory','headroom','superpowers','ponytail'),
  [string[]]$Providers = @(),
  [switch]$ComponentsOnly,
  [switch]$InstallAfter,
  [switch]$UpdateCatalogOffline,
  # Replace a component that the catalog holds on purpose. Without this, a
  # compatibility or security hold is respected even when it is named
  # explicitly on the command line.
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
$root = Get-UabsPackRoot
$catalog = Get-UabsCatalog
$Providers = @($Providers | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($provider in $Providers) {
  if ($provider -notin @('Claude','Codex','Grok','Kimi','Hermes','Antigravity')) { throw "Unknown provider: $provider" }
}

if (-not $ComponentsOnly) {
  $remote = Join-Path $root 'INSTALL-REMOTE.ps1'
  if (-not (Test-Path -LiteralPath $remote -PathType Leaf)) { throw 'INSTALL-REMOTE.ps1 missing from pack.' }
  Write-UabsStep 'Updating stable bundle installation, plugins, skills, MCPs, and tools'
  $remoteArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$remote)
  if ($Providers.Count) { $remoteArgs += @('-Providers', ($Providers -join ',')) }
  & (Get-Command powershell.exe -ErrorAction Stop).Source @remoteArgs
  if ($LASTEXITCODE -ne 0) { throw "bundle update failed with exit code $LASTEXITCODE" }
  return
}

function Copy-VerifiedOfflineSnapshot {
  # Offline bytes are bound to the shipped manifest. Cache a newer release for
  # review; never put it under an older, still-pinned offline filename.
  param([string]$Source, [string]$Destination, [string]$Manifest)
  $entry = @(([IO.File]::ReadAllText($Manifest) | ConvertFrom-Json).assets |
    Where-Object { $_.file -eq (Split-Path -Leaf $Destination) })
  if ($entry.Count -ne 1) { throw 'Offline snapshot has no unique integrity record.' }
  $hash = (Get-FileHash -LiteralPath $Source -Algorithm SHA256).Hash
  if ((Get-Item -LiteralPath $Source).Length -ne [long]$entry[0].size -or $hash -ine $entry[0].sha256) {
    throw 'Candidate differs from the reviewed offline pin. Kept in cache; update and validate catalog and manifests together before shipping it.'
  }
  Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

$cache = Join-Path $root 'BUNDLED-TOOLS\cache'
$offline = Join-Path $root 'BUNDLED-TOOLS\offline'
New-Item -ItemType Directory -Force -Path $cache | Out-Null

$results = @()
foreach ($id in $Components) {
  $comp = $catalog.components | Where-Object { $_.id -eq $id } | Select-Object -First 1
  if (-not $comp) { Write-UabsWarn "Unknown component $id"; continue }
  $hold = if ($comp.compatibility_hold) { $comp.compatibility_hold } elseif ($comp.security_hold) { $comp.security_hold } else { $null }
  if ($hold -and -not $Force) {
    # A hold is a decision recorded with evidence, not a stale pin. Updating
    # past it is how a working install turns into a migration.
    Write-UabsWarn "$id is held in the catalog: $hold"
    Write-UabsWarn "Skipping $id. Re-run with -Force only after migrating what the hold protects."
    continue
  }
  if (-not $comp.github) { Write-UabsWarn "$id has no GitHub source (manual)"; continue }
  Write-UabsStep "GitHub release (RTK uses the measured catalog pin): $($comp.github.owner)/$($comp.github.repo)"
  try {
    $rel = Get-UabsComponentGitHubRelease -Comp $comp
    Write-UabsOk "tag $($rel.tag_name)"
    $asset = $null
    if ($comp.asset_match) { $asset = Get-UabsReleaseAsset -Release $rel -Patterns @($comp.asset_match) }
    $out = $null
    if ($asset) {
      $out = Join-Path $cache $asset.name
      [void](Save-UabsReleaseAsset -Asset $asset -OutFile $out)
      if ($UpdateCatalogOffline -and $comp.offline_asset) {
        Copy-VerifiedOfflineSnapshot -Source $out -Destination (Join-Path $offline $comp.offline_asset) -Manifest (Join-Path $root 'BUNDLED-TOOLS\OFFLINE-MANIFEST.json')
        Write-UabsOk "offline snapshot updated: $($comp.offline_asset)"
      }
    } elseif ($comp.kind -eq 'skills-plugin') {
      # zipball
      $out = Join-Path $cache "$id-$($rel.tag_name).zip"
      $zipUrl = "https://github.com/$($comp.github.owner)/$($comp.github.repo)/archive/refs/tags/$($rel.tag_name).zip"
      try { Save-UabsUrl -Url $zipUrl -OutFile $out }
      catch { Save-UabsUrl -Url $rel.zipball_url -OutFile $out }
      if ($UpdateCatalogOffline -and $comp.offline_asset) {
        Copy-VerifiedOfflineSnapshot -Source $out -Destination (Join-Path $offline $comp.offline_asset) -Manifest (Join-Path $root 'BUNDLED-TOOLS\OFFLINE-MANIFEST.json')
      }
    } else {
      Write-UabsWarn "No matching asset for $id — open $($rel.html_url)"
    }
    $results += [pscustomobject]@{ id=$id; tag=$rel.tag_name; file=$out; url=$rel.html_url }
  } catch {
    Write-UabsBad "$id : $($_.Exception.Message)"
    $results += [pscustomobject]@{ id=$id; tag=$null; file=$null; error=$_.Exception.Message }
  }
}

$ledgerUpdates = @()
foreach ($row in @($results)) {
  $ledgerUpdates += @{
    id = [string]$row.id
    tag = [string]$row.tag
    file = [string]$row.file
    url = [string]$row.url
    error = [string]$row.error
  }
}
if ($ledgerUpdates.Count) { Update-UabsComponentLedger -Updates $ledgerUpdates }
Write-Host ""
$results | Format-Table -AutoSize
if (@($results | Where-Object { $_.error }).Count) { throw 'One or more component updates failed; see the results above. No install was started.' }
if ($InstallAfter) {
  Write-UabsStep "Running INSTALL-AIO.ps1 -Mode OnlineLatest"
  & (Join-Path $root 'INSTALL-AIO.ps1') -Mode OnlineLatest -Providers $Providers
}
