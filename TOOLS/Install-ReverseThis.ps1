# Install Reverse THIS!'s latest verified release (the bundle pins no version), then let
# its owner installer manage its own tools and state. A newer installed kit is kept.
[CmdletBinding()]
param([string]$PackRoot, [string]$KitRoot, [string]$SourceZip, [string]$SourceSha256,
      [switch]$Offline, [switch]$PreferBundled, [switch]$NoUpdate, [switch]$ResolveOnly)
$ErrorActionPreference='Stop'
if (-not $PackRoot) { $PackRoot=Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')

function Get-ReverseCanonicalPath([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path) -or -not [IO.Path]::IsPathRooted($Path)) { throw 'Reverse THIS! owner path is not absolute.' }
    return ([IO.Path]::GetFullPath($Path)).TrimEnd([char[]]@('\','/'))
}
function Test-ReverseContainedPath([string]$Parent, [string]$Child) {
    $p=Get-ReverseCanonicalPath $Parent; $c=Get-ReverseCanonicalPath $Child
    return $c.Equals($p,[StringComparison]::OrdinalIgnoreCase) -or $c.StartsWith($p+'\',[StringComparison]::OrdinalIgnoreCase)
}
function Test-ReverseReparse([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}
function Test-ReverseOwnerState {
    # Ownership proof is the state schema plus every bound payload file still
    # matching its receipt inside this candidate root. A folder named
    # reverse-this alone is never enough.
    param([string]$Owner, [string]$StateFile)
    if (-not (Test-Path -LiteralPath $StateFile -PathType Leaf) -or (Test-ReverseReparse $StateFile)) { return $null }
    try { $state=[IO.File]::ReadAllText($StateFile) | ConvertFrom-Json } catch { return $null }
    if ($state.schema -ne 1 -or -not $state.tools -or -not $state.kit_root) { return $null }
    $checked=0
    foreach ($row in @($state.tools.PSObject.Properties.Value)) {
        if (-not $row -or -not $row.dir -or -not $row.files) { return $null }
        $dirPath = if ([IO.Path]::IsPathRooted([string]$row.dir)) { [string]$row.dir } else { Join-Path $Owner ([string]$row.dir) }
        if (-not (Test-ReverseContainedPath $Owner $dirPath)) { return $null }
        if (-not (Test-Path -LiteralPath $dirPath -PathType Container) -or (Test-ReverseReparse $dirPath)) { return $null }
        foreach ($name in @($row.files.PSObject.Properties.Name)) {
            $hash=[string]$row.files.$name
            if ($hash -notmatch '^[0-9a-fA-F]{64}$') { return $null }
            $file=[IO.Path]::GetFullPath((Join-Path $dirPath $name))
            if (-not (Test-ReverseContainedPath $dirPath $file)) { return $null }
            if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or (Test-ReverseReparse $file)) { return $null }
            if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $hash.ToLowerInvariant()) { return $null }
            $checked++
        }
    }
    if (-not $checked) { return $null }
    return $state
}

# A registered owner wins over a default folder; malformed receipts never authorize another installation.
function Resolve-ReverseOwner {
    param([string]$ExplicitRoot, [string]$Pointer, [string]$DefaultRoot)
    if ($ExplicitRoot) { return Get-ReverseCanonicalPath $ExplicitRoot }
    if (-not (Test-Path -LiteralPath $Pointer -PathType Leaf)) { return $DefaultRoot }
    if (Test-ReverseReparse $Pointer) { throw 'Invalid Reverse THIS! owner pointer: reparse point.' }
    $receipt=[IO.File]::ReadAllText($Pointer) | ConvertFrom-Json
    if (-not $receipt.kit_root -or -not [IO.Path]::IsPathRooted($receipt.kit_root)) { throw 'Invalid Reverse THIS! owner pointer.' }
    $owner=Get-ReverseCanonicalPath $receipt.kit_root
    # A receipt whose install folder is gone is a stale owner record, not
    # permission to create a second install. Skip it; do not error the bundle.
    if (-not (Test-Path -LiteralPath $owner -PathType Container)) { return $null }
    if (Test-ReverseReparse $owner) { throw 'Invalid Reverse THIS! owner root: reparse point.' }
    if (-not (Test-ReverseContainedPath $owner $receipt.installed_json) -or
        -not (Test-ReverseContainedPath $owner $receipt.bin) -or
        -not (Test-Path -LiteralPath $receipt.installed_json -PathType Leaf)) { throw 'Invalid Reverse THIS! owner paths; no new installation created.' }
    $state=Test-ReverseOwnerState -Owner $owner -StateFile $receipt.installed_json
    if (-not $state -or (Get-ReverseCanonicalPath $state.kit_root) -ne $owner) { throw 'Invalid Reverse THIS! owner state.' }
    return $owner
}


function Find-ReverseOwnerKit {
    # A moved install keeps its sandbox/installed.json; adopt it instead of
    # creating a second kit. Bounded roots only, never a drive walk. Multiple
    # equally valid candidates are ambiguous and are never guessed through.
    param([string[]]$Roots)
    $found=@()
    foreach ($base in $Roots) {
        if ([string]::IsNullOrWhiteSpace($base) -or -not (Test-Path -LiteralPath $base -PathType Container)) { continue }
        if (Test-ReverseReparse $base) { continue }
        $candidates = @()
        try {
            $candidates = @(Get-ChildItem -LiteralPath $base -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ieq 'reverse-this' -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
        } catch { }
        foreach ($dir in $candidates) {
            $stateFile = Join-Path $dir.FullName 'sandbox\installed.json'
            $owner = Get-ReverseCanonicalPath $dir.FullName
            $state = Test-ReverseOwnerState -Owner $owner -StateFile $stateFile
            if ($state) { $found += [pscustomobject]@{ Owner=$owner; StateFile=$stateFile } }
        }
    }
    $unique=@($found | Sort-Object Owner -Unique)
    if ($unique.Count -gt 1) { throw ('Ambiguous Reverse THIS! owner candidates: ' + (($unique | ForEach-Object Owner) -join ', ')) }
    if ($unique.Count -eq 1) { return $unique[0] }
    return $null
}

function Save-ReverseOwnerReceipt {
    param([object]$Kit, [string]$Pointer)
    $state = Test-ReverseOwnerState -Owner $Kit.Owner -StateFile $Kit.StateFile
    if (-not $state) { throw 'Refusing to write a Reverse THIS! pointer for an invalid owner.' }
    $receipt = [ordered]@{
        schema = 1
        owner = 'reverse-this'
        java_home = $state.java_home
        bin = (Join-Path $Kit.Owner 'sandbox\bin')
        installed_json = $Kit.StateFile
        kit_root = $Kit.Owner
    }
    $parent=Split-Path -Parent $Pointer
    New-Item -ItemType Directory -Force -Path $parent | Out-Null
    $temp=Join-Path $parent ('.kit.json.tmp-'+$PID+'-'+[guid]::NewGuid().ToString('N'))
    $backup=Join-Path $parent 'kit.json.bak'
    try {
        [IO.File]::WriteAllText($temp, ($receipt | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding $false))
        if (Test-Path -LiteralPath $Pointer -PathType Leaf) { Copy-Item -LiteralPath $Pointer -Destination $backup -Force }
        Move-Item -LiteralPath $temp -Destination $Pointer -Force
        $check=[IO.File]::ReadAllText($Pointer) | ConvertFrom-Json
        if ((Get-ReverseCanonicalPath $check.kit_root) -ne $Kit.Owner -or $check.schema -ne 1) { throw 'Written Reverse THIS! pointer did not validate.' }
    } catch {
        if (Test-Path -LiteralPath $backup -PathType Leaf) { Copy-Item -LiteralPath $backup -Destination $Pointer -Force }
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        throw
    }
}

$pointer=Join-Path $env:LOCALAPPDATA 'ReverseThis\kit.json'
$target=Resolve-ReverseOwner -ExplicitRoot $KitRoot -Pointer $pointer -DefaultRoot (Join-Path $env:LOCALAPPDATA 'ReverseThis\kit')
if (-not $target) {
    # Receipt points at a moved or deleted kit: look for the owner in the tool
    # roots before giving up, then repair the receipt.
    $search = @()
    foreach ($k in @('UABS_TOOL_ROOTS','REVERSE_THIS_ROOT')) {
        $v = [Environment]::GetEnvironmentVariable($k, 'Process'); if (-not $v) { $v = [Environment]::GetEnvironmentVariable($k, 'User') }
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
if (-not $target) {
    if ($ResolveOnly) { Write-Error 'Reverse THIS! owner is missing and no verified owner could be recovered.'; exit 2 }
    throw 'Reverse THIS! owner receipt points at a missing install and no verified owner could be recovered; nothing was installed or recorded as ready.'
}
if ($ResolveOnly) { Write-Output $target; exit 0 }
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
