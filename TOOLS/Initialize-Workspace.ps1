# Seed missing workspace examples; existing project files always belong to the user.
[CmdletBinding()]
param(
    [string]$PackRoot,
    [Parameter(Mandatory=$true)][string]$WorkspaceRoot
)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$PackRoot = [IO.Path]::GetFullPath($PackRoot)
$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)

function Assert-WorkspaceSeedPath([string]$Path) {
    # Check existing ancestors individually, including links to absent targets.
    # Resolve-Path would follow a junction before we could inspect it.
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction SilentlyContinue
        if ($item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw ('Workspace seeding refuses to traverse a reparse point: ' + $cursor)
        }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Get-WorkspaceSeedNode([string]$Path, [bool]$Directory) {
    if (-not ([IO.File]::Exists($Path) -or [IO.Directory]::Exists($Path))) {
        throw ('Required workspace source is missing: ' + $Path)
    }
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        throw ('Workspace source must not contain a reparse point: ' + $Path)
    }
    if ($Directory -ne [bool]$item.PSIsContainer) {
        throw ('Workspace source has an unexpected file type: ' + $Path)
    }
    $children = @()
    if ($Directory) {
        $children = @(Get-ChildItem -LiteralPath $Path -Force | ForEach-Object {
            Get-WorkspaceSeedNode -Path $_.FullName -Directory ([bool]$_.PSIsContainer)
        })
    }
    return [pscustomobject]@{ Name=$item.Name; Source=$item.FullName; Directory=$Directory; Children=$children }
}

function Copy-WorkspaceSeedNode($Node, [string]$Destination) {
    $existing = Get-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
    if ($existing) {
        # Preserve links, files, and type conflicts without entering their targets.
        if (($existing.Attributes -band [IO.FileAttributes]::ReparsePoint) -or
            -not $Node.Directory -or -not $existing.PSIsContainer) { return }
    }
    Assert-WorkspaceSeedPath -Path $Destination
    if ($Node.Directory) {
        [void][IO.Directory]::CreateDirectory($Destination)
        foreach ($child in $Node.Children) {
            Copy-WorkspaceSeedNode -Node $child -Destination (Join-Path $Destination $child.Name)
        }
    } else {
        # overwrite=false also preserves a file created after the existence check.
        [IO.File]::Copy($Node.Source, $Destination, $false)
    }
}

$source = Join-Path $PackRoot 'COPY-TO-YOUR-WORKSPACE'
Assert-WorkspaceSeedPath -Path $source
Assert-WorkspaceSeedPath -Path $WorkspaceRoot
$rootItem = Get-Item -LiteralPath $WorkspaceRoot -Force -ErrorAction SilentlyContinue
if ($rootItem -and -not $rootItem.PSIsContainer) { throw ('WorkspaceRoot is not a directory: ' + $WorkspaceRoot) }

# Complete source validation before creating even the workspace directory.
$nodes = @(
    Get-WorkspaceSeedNode -Path (Join-Path $source 'AGENTS.md') -Directory $false
    Get-WorkspaceSeedNode -Path (Join-Path $source 'CLAUDE.md') -Directory $false
    Get-WorkspaceSeedNode -Path (Join-Path $source '_PROJECT-TEMPLATE') -Directory $true
)
[void][IO.Directory]::CreateDirectory($WorkspaceRoot)
foreach ($node in $nodes) {
    Copy-WorkspaceSeedNode -Node $node -Destination (Join-Path $WorkspaceRoot $node.Name)
}
Write-Host 'Workspace examples seeded where absent; existing files preserved.'
