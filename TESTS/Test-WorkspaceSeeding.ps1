# Workspace seeding must never replace project rules or follow directory links.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$helper = Join-Path $PackRoot 'TOOLS\Initialize-Workspace.ps1'
if (-not (Test-Path -LiteralPath $helper -PathType Leaf)) { throw 'Workspace seeding helper is missing.' }

function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Put([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}
function Seed([string]$Source, [string]$Destination) {
    & $helper -PackRoot $Source -WorkspaceRoot $Destination
}
function Must-Refuse([string]$Source, [string]$Destination, [string]$Message) {
    $refused = $false
    try { Seed $Source $Destination } catch { $refused = $true }
    Assert $refused $Message
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-workspace-' + [guid]::NewGuid().ToString('N'))
$links = New-Object System.Collections.Generic.List[string]
try {
    # Literal brackets and Unicode catch accidental wildcard or ANSI handling.
    $source = Join-Path $fixture ('pack [x] ' + [char]0xE9)
    $tree = Join-Path $source 'COPY-TO-YOUR-WORKSPACE'
    Put (Join-Path $tree 'AGENTS.md') 'bundle agent rules'
    Put (Join-Path $tree 'CLAUDE.md') 'bundle Claude rules'
    Put (Join-Path $tree '_PROJECT-TEMPLATE\nested\keep.txt') 'bundle template'
    Put (Join-Path $tree '_PROJECT-TEMPLATE\nested\new.txt') 'new template file'
    Put (Join-Path $tree '_PROJECT-TEMPLATE\blocked\new.txt') 'must not cross a file'
    Put (Join-Path $tree '_PROJECT-TEMPLATE\linked\new.txt') 'must not follow a link'
    Put (Join-Path $tree '_PROJECT-TEMPLATE\dangling\new.txt') 'must not replace a dangling link'

    $fresh = Join-Path $fixture 'fresh [workspace]'
    Seed $source $fresh
    Assert ([IO.File]::ReadAllText((Join-Path $fresh 'AGENTS.md')) -ceq 'bundle agent rules') 'Fresh agent rules were not seeded.'
    Assert ([IO.File]::ReadAllText((Join-Path $fresh 'CLAUDE.md')) -ceq 'bundle Claude rules') 'Fresh Claude rules were not seeded.'
    Assert ([IO.File]::ReadAllText((Join-Path $fresh '_PROJECT-TEMPLATE\nested\new.txt')) -ceq 'new template file') 'Fresh template descendants were not seeded.'

    $existing = Join-Path $fixture 'existing [workspace]'
    Put (Join-Path $existing 'AGENTS.md') 'personal agent rules'
    Put (Join-Path $existing 'CLAUDE.md') 'personal Claude rules'
    Put (Join-Path $existing '_PROJECT-TEMPLATE\nested\keep.txt') 'personal template'
    Put (Join-Path $existing '_PROJECT-TEMPLATE\blocked') 'a user file, not a directory'
    $outside = Join-Path $fixture 'outside'
    Put (Join-Path $outside 'sentinel.txt') 'outside data'
    $link = Join-Path $existing '_PROJECT-TEMPLATE\linked'
    [void](New-Item -ItemType Junction -Path $link -Target $outside)
    [void]$links.Add($link)
    $emptyTarget = Join-Path $fixture 'removed target'
    [void][IO.Directory]::CreateDirectory($emptyTarget)
    $dangling = Join-Path $existing '_PROJECT-TEMPLATE\dangling'
    [void](New-Item -ItemType Junction -Path $dangling -Target $emptyTarget)
    [void]$links.Add($dangling)
    [IO.Directory]::Delete($emptyTarget)
    Seed $source $existing
    Seed $source $existing
    Assert ([IO.File]::ReadAllText((Join-Path $existing 'AGENTS.md')) -ceq 'personal agent rules') 'Existing agent rules were overwritten.'
    Assert ([IO.File]::ReadAllText((Join-Path $existing 'CLAUDE.md')) -ceq 'personal Claude rules') 'Existing Claude rules were overwritten.'
    Assert ([IO.File]::ReadAllText((Join-Path $existing '_PROJECT-TEMPLATE\nested\keep.txt')) -ceq 'personal template') 'An existing template file was overwritten.'
    Assert ([IO.File]::ReadAllText((Join-Path $existing '_PROJECT-TEMPLATE\nested\new.txt')) -ceq 'new template file') 'Missing file inside an existing template was not seeded.'
    Assert ([IO.File]::ReadAllText((Join-Path $existing '_PROJECT-TEMPLATE\blocked')) -ceq 'a user file, not a directory') 'A conflicting user file was replaced.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $outside 'new.txt'))) 'Seeding followed an existing template junction.'
    Assert (((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'An existing junction was replaced.'
    Assert (((Get-Item -LiteralPath $dangling -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) 'An existing dangling junction was replaced.'
    Assert (-not (Test-Path -LiteralPath $emptyTarget)) 'Seeding recreated the target of a dangling junction.'

    # Existing objects of the wrong type still belong to the user.
    $conflict = Join-Path $fixture 'type conflicts'
    [void][IO.Directory]::CreateDirectory((Join-Path $conflict 'AGENTS.md'))
    Put (Join-Path $conflict '_PROJECT-TEMPLATE') 'personal template placeholder'
    Seed $source $conflict
    Assert (Test-Path -LiteralPath (Join-Path $conflict 'AGENTS.md') -PathType Container) 'An existing instruction directory was replaced.'
    Assert ([IO.File]::ReadAllText((Join-Path $conflict '_PROJECT-TEMPLATE')) -ceq 'personal template placeholder') 'A conflicting template root was replaced.'

    # A linked destination root or ancestor must not redirect writes.
    $rootLink = Join-Path $fixture 'linked root'
    [void](New-Item -ItemType Junction -Path $rootLink -Target $outside)
    [void]$links.Add($rootLink)
    Must-Refuse $source (Join-Path $rootLink 'child') 'A destination below a junction was accepted.'
    Assert (-not (Test-Path -LiteralPath (Join-Path $outside 'child'))) 'A linked destination ancestor redirected writes.'

    # Validate every required source before creating any destination files.
    [IO.File]::Delete((Join-Path $tree 'CLAUDE.md'))
    Assert (-not (Test-Path -LiteralPath (Join-Path $tree 'CLAUDE.md'))) 'Fixture did not remove the source file.'
    $missing = Join-Path $fixture 'missing-source destination'
    Must-Refuse $source $missing 'A missing required source was accepted.'
    Assert (-not (Test-Path -LiteralPath $missing)) 'A missing required source left a partial workspace.'
    Put (Join-Path $tree 'CLAUDE.md') 'bundle Claude rules'
    $sourceLink = Join-Path $tree '_PROJECT-TEMPLATE\source-link'
    [void](New-Item -ItemType Junction -Path $sourceLink -Target $outside)
    [void]$links.Add($sourceLink)
    $unsafe = Join-Path $fixture 'unsafe-source destination'
    Must-Refuse $source $unsafe 'A source template junction was accepted.'
    Assert (-not (Test-Path -LiteralPath $unsafe)) 'An unsafe source left a partial workspace.'
    Write-Host 'WORKSPACE SEEDING GATE: PASS'
} finally {
    # Unlink junctions themselves before recursively removing our GUID fixture.
    foreach ($linkPath in $links) {
        if (Get-Item -LiteralPath $linkPath -Force -ErrorAction SilentlyContinue) { [IO.Directory]::Delete($linkPath) }
    }
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}
