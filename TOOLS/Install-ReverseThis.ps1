# Install Reverse THIS!'s latest verified release (the bundle pins no version), then let
# its owner installer manage its own tools and state. A newer installed kit is kept.
[CmdletBinding()]
param([string]$PackRoot, [string]$KitRoot, [string]$SourceZip, [string]$SourceSha256,
      [switch]$Offline, [switch]$PreferBundled, [switch]$NoUpdate, [switch]$ResolveOnly)
$ErrorActionPreference='Stop'
if (-not $PackRoot) { $PackRoot=Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')

# A registered owner wins over a default folder; malformed receipts never authorize another installation.
function Resolve-ReverseOwner {
    param([string]$ExplicitRoot, [string]$Pointer, [string]$DefaultRoot)
    if ($ExplicitRoot) { return [IO.Path]::GetFullPath($ExplicitRoot) }
    if (-not (Test-Path -LiteralPath $Pointer -PathType Leaf)) { return $DefaultRoot }
    $receipt=[IO.File]::ReadAllText($Pointer) | ConvertFrom-Json
    if (-not $receipt.kit_root -or -not [IO.Path]::IsPathRooted($receipt.kit_root)) { throw 'Invalid Reverse THIS! owner pointer.' }
    $owner=[IO.Path]::GetFullPath($receipt.kit_root).TrimEnd('\')
    # A receipt whose install folder is gone is a stale owner record, not
    # permission to create a second install. Skip it; do not error the bundle.
    if (-not (Test-Path -LiteralPath $owner -PathType Container)) { return $null }
    if ($receipt.installed_json -ne (Join-Path $owner 'sandbox\installed.json') -or
        $receipt.bin -ne (Join-Path $owner 'sandbox\bin') -or
        -not (Test-Path -LiteralPath $receipt.installed_json -PathType Leaf)) { throw 'Invalid Reverse THIS! owner paths; no new installation created.' }
    $state=[IO.File]::ReadAllText($receipt.installed_json) | ConvertFrom-Json
    if ($state.schema -ne 1 -or $state.kit_root.TrimEnd('\') -ne $owner -or -not $state.tools) { throw 'Invalid Reverse THIS! owner state.' }
    return $owner
}


function Find-ReverseOwnerKit {
    # A moved install keeps its sandbox/installed.json; adopt it instead of
    # creating a second kit. Bounded roots only, never a drive walk.
    param([string[]]$Roots)
    foreach ($base in $Roots) {
        if ([string]::IsNullOrWhiteSpace($base) -or -not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        $candidates = @()
        try {
            $candidates = @(Get-ChildItem -LiteralPath $base -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ieq 'reverse-this' })
        } catch { }
        foreach ($dir in $candidates) {
            $stateFile = Join-Path $dir.FullName 'sandbox\installed.json'
            if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) { continue }
            try {
                $state = [IO.File]::ReadAllText($stateFile) | ConvertFrom-Json
                if ($state.schema -eq 1 -and $state.tools -and $state.kit_root) {
                    $owner = [IO.Path]::GetFullPath($dir.FullName).TrimEnd('')
                    return [pscustomobject]@{ Owner = $owner; StateFile = $stateFile }
                }
            } catch { }
        }
    }
    return $null
}

function Save-ReverseOwnerReceipt {
    param([object]$Kit, [string]$Pointer)
    $state = [IO.File]::ReadAllText($Kit.StateFile) | ConvertFrom-Json
    $receipt = [ordered]@{
        java_home = $state.java_home
        bin = (Join-Path $Kit.Owner 'sandbox\bin')
        installed_json = $Kit.StateFile
        kit_root = $Kit.Owner
    }
    [IO.File]::WriteAllText($Pointer, ($receipt | ConvertTo-Json), (New-Object Text.UTF8Encoding $false))
}

$pointer=Join-Path $env:LOCALAPPDATA 'ReverseThis\kit.json'
$target=Resolve-ReverseOwner -ExplicitRoot $KitRoot -Pointer $pointer -DefaultRoot (Join-Path $env:LOCALAPPDATA 'ReverseThis\kit')
if (-not $target) {
    # Receipt points at a moved or deleted kit: look for the owner in the tool
    # roots before giving up, then repair the receipt.
    $search = @()
    foreach ($k in @('UABS_TOOL_ROOTS','REVERSE_THIS_ROOT')) {
        $v = [Environment]::GetEnvironmentVariable($k, 'User'); if (-not $v) { $v = [Environment]::GetEnvironmentVariable($k, 'Process') }
        if ($v) { $search += ($v -split ';' | Where-Object { $_ }) }
    }
    $search += @((Join-Path $env:USERPROFILE 'Tools'), (Join-Path $env:USERPROFILE 'Documents\Tools'), 'C:\Tools')
    $kit = Find-ReverseOwnerKit -Roots $search
    if ($kit) {
        Save-ReverseOwnerReceipt -Kit $kit -Pointer $pointer
        $target = $kit.Owner
        Write-Host ('Adopted moved Reverse THIS! kit at ' + $target)
    }
}
if ($ResolveOnly) { Write-Output $target; exit 0 }
if (-not $target) {
    Write-Host 'Reverse THIS! owner receipt points at a missing install; skipped, nothing replaced.'
    exit 0
}
$comp=@(([IO.File]::ReadAllText((Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json')) | ConvertFrom-Json).components | Where-Object id -eq 'reverse-this')
if ($comp.Count -ne 1) { throw 'Catalog must declare one Reverse THIS! companion.' }
$comp=$comp[0]
$have='0.0.0'
$versionFile=Join-Path $target 'VERSION'
if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
    $have=([IO.File]::ReadAllText($versionFile)).Trim()
    if ($have -notmatch '^\d+\.\d+\.\d+$') { throw 'Existing Reverse THIS! version is unknown; no source replaced.' }
}
$temp=$null
try {
    if ($SourceZip) {
        if ($SourceSha256 -notmatch '^[0-9a-fA-F]{64}$') { throw '-SourceZip needs -SourceSha256; nothing installed.' }
        if ((Split-Path -Leaf $SourceZip) -notmatch '^Reverse-This-(?<ver>\d+\.\d+\.\d+)\.zip$') { throw 'Invalid Reverse THIS! archive name.' }
        $release=[pscustomobject]@{ version=$Matches['ver']; sha256=$SourceSha256.ToLowerInvariant(); path=$SourceZip; source='local archive' }
    } elseif ($NoUpdate -and $have -ne '0.0.0') {
        $release=$null
    } else {
        try { $release=Resolve-UabsCompanionArchive -Comp $comp -PackRoot $PackRoot -Downloads (Join-Path (Get-UabsStateRoot) 'downloads') -Offline:$Offline -PreferBundled:$PreferBundled }
        catch {
            # A working kit at or above the floor outlives an unreachable or offline update source.
            if ($have -eq '0.0.0' -or [version]$have -lt [version]$comp.min_version) { throw }
            Write-UabsWarn ('Reverse THIS! update check failed ('+$_.Exception.Message+'); keeping '+$have+'.')
            $release=$null
        }
    }
    if ($have -ne '0.0.0' -and [version]$have -lt [version]$comp.min_version -and -not $release) { throw 'Reverse THIS! is older than the supported floor; -NoToolUpdates preserved it.' }
    if ($release -and [version]$have -lt [version]$release.version) {
        $zip=$release.path; $digest=$release.sha256
        if (-not (Test-Path -LiteralPath $zip -PathType Leaf) -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $digest) { throw 'Reverse THIS! archive does not match its verified SHA-256; nothing installed.' }
        $temp=Join-Path ([IO.Path]::GetTempPath()) ('uabs-reverse-'+[guid]::NewGuid().ToString('N'))
        # Reject archive paths before extracting even though the complete archive digest is verified.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive=[IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archive.Entries) {
                if ($entry.FullName.Replace('\','/') -match '(^|/)\.\.(/|$)|^/|:' -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Unsafe Reverse THIS! archive path.' }
            }
            [IO.Compression.ZipFileExtensions]::ExtractToDirectory($archive,$temp)
        } finally { $archive.Dispose() }
        $source=Resolve-UabsSingleRoot -Dest $temp
        if (([IO.File]::ReadAllText((Join-Path $source 'VERSION'))).Trim() -ne $release.version) { throw 'Reverse THIS! archive version disagrees with its release.' }
        $updater=Join-Path $source 'Update-ReverseThis.ps1'
        if (-not (Test-Path -LiteralPath $updater -PathType Leaf)) { throw 'Companion archive lacks its owner updater.' }
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $updater -Destination $target -Archive $zip -Sha256 $digest
        if ($LASTEXITCODE -ne 0) { throw 'Reverse THIS! owner source update failed.' }
    }
    $installer=Join-Path $target 'Install-Modkit.ps1'
    if (-not (Test-Path -LiteralPath $installer -PathType Leaf)) { throw 'Reverse THIS! owner installer is missing.' }
    $ownerArgs=@()
    if ($NoUpdate) { $ownerArgs+='-NoUpdate' }
    if ($Offline) { $ownerArgs+='-Offline' }
    $doctorArgs=@('-Doctor')
    # An explicit root is an isolated owner, so its installer must not follow another kit's pointer.
    if ($KitRoot) { $ownerArgs+=@('-InstallRoot',$target); $doctorArgs+=@('-InstallRoot',$target) }
    $stateFile=Join-Path $target 'sandbox\installed.json'
    if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
        # Refresh the owner's existing selection, rather than silently adding every new optional tool.
        $state=[IO.File]::ReadAllText($stateFile) | ConvertFrom-Json
        $selected=@($state.tools.PSObject.Properties.Name)
        if ($selected.Count) { $ownerArgs+=@('-Only',($selected -join ',')); $doctorArgs+=@('-Only',($selected -join ',')) }
    }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer @ownerArgs
    if ($LASTEXITCODE -ne 0) { throw 'Reverse THIS! tool update failed.' }
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer @doctorArgs
    if ($LASTEXITCODE -ne 0) { throw 'Reverse THIS! doctor failed.' }
    Write-UabsOk ('Reverse THIS! ready ('+([IO.File]::ReadAllText((Join-Path $target 'VERSION'))).Trim()+'): '+$target)
} finally {
    if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
