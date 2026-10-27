# Install the verified companion source, then let Reverse THIS! manage its own tools and state.
[CmdletBinding()]
param([string]$PackRoot, [string]$KitRoot, [string]$SourceZip,
      [switch]$Offline, [switch]$NoUpdate, [switch]$ResolveOnly)
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
    if ($receipt.installed_json -ne (Join-Path $owner 'sandbox\installed.json') -or
        $receipt.bin -ne (Join-Path $owner 'sandbox\bin') -or
        -not (Test-Path -LiteralPath $receipt.installed_json -PathType Leaf)) { throw 'Invalid Reverse THIS! owner paths; no new installation created.' }
    $state=[IO.File]::ReadAllText($receipt.installed_json) | ConvertFrom-Json
    if ($state.schema -ne 1 -or $state.kit_root.TrimEnd('\') -ne $owner -or -not $state.tools) { throw 'Invalid Reverse THIS! owner state.' }
    return $owner
}

$pointer=Join-Path $env:LOCALAPPDATA 'ReverseThis\kit.json'
$target=Resolve-ReverseOwner -ExplicitRoot $KitRoot -Pointer $pointer -DefaultRoot (Join-Path $env:LOCALAPPDATA 'ReverseThis\kit')
if ($ResolveOnly) { Write-Output $target; exit 0 }
$pin=@(([IO.File]::ReadAllText((Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json')) | ConvertFrom-Json).components | Where-Object id -eq 'reverse-this')
if ($pin.Count -ne 1 -or $pin[0].version -notmatch '^\d+\.\d+\.\d+$') { throw 'Catalog must declare one Reverse THIS! companion release.' }
$pin=$pin[0]
$have='0.0.0'
$versionFile=Join-Path $target 'VERSION'
if (Test-Path -LiteralPath $versionFile -PathType Leaf) {
    $have=([IO.File]::ReadAllText($versionFile)).Trim()
    if ($have -notmatch '^\d+\.\d+\.\d+$') { throw 'Existing Reverse THIS! version is unknown; no source replaced.' }
}
$temp=$null
try {
    if ([version]$have -lt [version]$pin.version) {
        if ($NoUpdate -and $have -ne '0.0.0') { throw 'Reverse THIS! needs its companion source update; -NoToolUpdates preserved the older source.' }
        $asset=[string]$pin.asset; $digest=[string]$pin.sha256
        if ($asset -notmatch '^Reverse-This-\d+\.\d+\.\d+\.zip$' -or $digest -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid Reverse THIS! release pin.' }
        $zip=$SourceZip
        if (-not $zip) {
            foreach ($candidate in @((Join-Path $PackRoot ('BUNDLED-TOOLS\offline\'+$asset)),(Join-Path (Get-UabsStateRoot) ('downloads\'+$asset)))) {
                if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash -eq $digest) { $zip=$candidate; break }
            }
        }
        if (-not $zip) {
            if ($Offline) { throw 'Reverse THIS! verified source archive is not cached; offline mode downloaded nothing.' }
            $zip=Join-Path (Get-UabsStateRoot) ('downloads\'+$asset)
            $releaseAsset=[pscustomobject]@{name=$asset;digest=('sha256:'+$digest);browser_download_url=('https://github.com/SenjuWoo/reverse-this/releases/download/v'+$pin.version+'/'+$asset)}
            [void](Save-UabsReleaseAsset -Asset $releaseAsset -OutFile $zip -ReuseValid)
        }
        if (-not (Test-Path -LiteralPath $zip -PathType Leaf) -or (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $digest) { throw 'Reverse THIS! archive does not match the pinned SHA-256; nothing installed.' }
        $temp=Join-Path ([IO.Path]::GetTempPath()) ('uabs-reverse-'+[guid]::NewGuid().ToString('N'))
        # Reject archive paths before extracting even though the complete archive digest is pinned.
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive=[IO.Compression.ZipFile]::OpenRead($zip)
        try {
            foreach ($entry in $archive.Entries) {
                if ($entry.FullName.Replace('\','/') -match '(^|/)\.\.(/|$)|^/|:' -or (($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Unsafe Reverse THIS! archive path.' }
            }
            [IO.Compression.ZipFileExtensions]::ExtractToDirectory($archive,$temp)
        } finally { $archive.Dispose() }
        $source=Resolve-UabsSingleRoot -Dest $temp
        if (([IO.File]::ReadAllText((Join-Path $source 'VERSION'))).Trim() -ne $pin.version) { throw 'Reverse THIS! archive version disagrees with its pin.' }
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
    Write-UabsOk ('Reverse THIS! ready: '+$target)
} finally {
    if ($temp -and (Test-Path -LiteralPath $temp)) { Remove-Item -LiteralPath $temp -Recurse -Force }
}
