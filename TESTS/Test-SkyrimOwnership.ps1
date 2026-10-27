# Prove that general skill sync hands ownership to Forge without deleting external payloads or source checkouts.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference='Stop'
if(-not $PackRoot) { $PackRoot=Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($ok,[string]$message) { if(-not $ok) { throw $message } }
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('uabs-skyrim-owner-'+[guid]::NewGuid().ToString('N'))
$savedLocal=$env:LOCALAPPDATA
try {
    $env:LOCALAPPDATA=Join-Path $fixture 'state'
    $from=Join-Path $fixture 'general'; $to=Join-Path $fixture 'skills'
    foreach($path in @((Join-Path $from 'coding-discipline'),(Join-Path $to 'skyrim-forge'))) { New-Item -ItemType Directory -Force -Path $path | Out-Null }
    [IO.File]::WriteAllText((Join-Path $from 'coding-discipline\SKILL.md'),'general payload')
    $external=Join-Path $to 'skyrim-forge\SKILL.md'
    [IO.File]::WriteAllText($external,'Forge-owned payload')
    $ledgerDir=Join-Path (Get-UabsStateRoot) 'managed-skills'
    New-Item -ItemType Directory -Force -Path $ledgerDir | Out-Null
    $legacy=@{schema=1;provider='Codex';skills=@(@{name='skyrim-forge';digest=(Get-UabsTreeDigest (Split-Path -Parent $external))})}
    [IO.File]::WriteAllText((Join-Path $ledgerDir 'codex.json'),($legacy|ConvertTo-Json -Depth 5))
    Sync-UabsProviderSkills -From $from -To $to -Provider Codex -ExternalNames @('skyrim-forge')
    Assert (Test-Path -LiteralPath $external) 'General sync deleted a transferred Forge skill.'
    Assert ([IO.File]::ReadAllText($external) -eq 'Forge-owned payload') 'General sync modified a transferred skill.'
    $current=[IO.File]::ReadAllText((Join-Path $ledgerDir 'codex.json'))|ConvertFrom-Json
    Assert (@($current.skills.name) -notcontains 'skyrim-forge') 'Bundle still claims ownership of the external skill.'
    [IO.File]::WriteAllText($external,'Independent Forge update')
    Sync-UabsProviderSkills -From $from -To $to -Provider Codex -ExternalNames @('skyrim-forge')
    Assert ([IO.File]::ReadAllText($external) -eq 'Independent Forge update') 'A second bundle update changed the independent Forge payload.'

    # A version-stamped source checkout is an owner root, never a legacy install to move or replace.
    $scriptText=[IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\Install-SkyrimForge.ps1'))
    $ast=[Management.Automation.Language.Parser]::ParseInput($scriptText,[ref]$null,[ref]$null)
    foreach($name in @('Get-VersionlessRoot','Test-ForgeShippedContentCurrent')) {
        $fn=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
        . ([scriptblock]::Create($fn.Extent.Text))
    }
    $source=Join-Path $fixture 'release'; $checkout=Join-Path $fixture 'Skyrim-Forge-6.1.0'
    New-Item -ItemType Directory -Force -Path $source,(Join-Path $checkout '.git') | Out-Null
    Assert ((Get-VersionlessRoot $checkout) -eq $checkout) 'Resolver renamed a source checkout based on its historical folder name.'
    $forgeVersion='6.1.1'
    [IO.File]::WriteAllText((Join-Path $source 'VERSION.txt'),"Skyrim Forge $forgeVersion")
    [IO.File]::WriteAllText((Join-Path $checkout 'VERSION.txt'),"Skyrim Forge $forgeVersion")
    [IO.File]::WriteAllText((Join-Path $source 'owned.txt'),'release bytes')
    [IO.File]::WriteAllText((Join-Path $checkout 'owned.txt'),'personal development edits')
    $rows=@(foreach($file in @('VERSION.txt','owned.txt')) { @{path=$file;sha256=(Get-FileHash -LiteralPath (Join-Path $source $file)).Hash;size=(Get-Item -LiteralPath (Join-Path $source $file)).Length} })
    $manifest=ConvertTo-Json -InputObject $rows -Depth 5
    foreach($root in @($source,$checkout)) { [IO.File]::WriteAllText((Join-Path $root 'MANIFEST.json'),$manifest) }
    Assert (Test-ForgeShippedContentCurrent -SourceRoot $source -InstalledRoot $checkout) 'Installer would overwrite personal edits in a current source checkout.'
    [IO.File]::WriteAllText((Join-Path $checkout 'VERSION.txt'),'Skyrim Forge 6.0.0')
    $failed=$false
    try { $null=Test-ForgeShippedContentCurrent -SourceRoot $source -InstalledRoot $checkout } catch { $failed=$true }
    Assert $failed 'An older source checkout was treated as a replaceable install.'
    Assert ([IO.File]::ReadAllText((Join-Path $checkout 'owned.txt')) -eq 'personal development edits') 'Source edits changed.'
    'SKYRIM OWNERSHIP GATE: PASS'
} finally {
    $env:LOCALAPPDATA=$savedLocal
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
