# Default search must see canonical skills and provider-specific files, and
# must not see the five generated skill copies. Those copies stay tracked.
# GitHub's Windows runner does not install ripgrep. The rule under test is the
# gitignore entry, which ripgrep honors. Prove that with git, and also call
# ripgrep when this machine has it.
[CmdletBinding()]
param(
    [string]$PackRoot,
    [switch]$SkipRipgrep
)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $PSCommandPath }
    $PackRoot = Split-Path -Parent $here
}
$fail = 0
function Bad([string]$Message) { Write-Host "FAIL $Message"; $script:fail++ }
function Good([string]$Message) { Write-Host "ok   $Message" }

function Get-RelPath([string]$Full) {
    $root = (Resolve-Path -LiteralPath $PackRoot).Path.TrimEnd('\')
    $item = (Resolve-Path -LiteralPath $Full).Path
    if (-not $item.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "outside pack: $Full"
    }
    return ($item.Substring($root.Length).TrimStart('\') -replace '\\', '/')
}

$needle = 'RTK is lossy and command/version dependent, not a universal 97% saving.'
$canonRoot = Join-Path $PackRoot '_CANONICAL-SKILLS'
$provRoot = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES'
$canonFile = Join-Path $canonRoot 'token-efficiency\SKILL.md'
if (Select-String -LiteralPath $canonFile -SimpleMatch -Pattern $needle -Quiet) {
    Good 'canonical skill text is on disk'
} else { Bad 'canonical token-efficiency line was not found' }

$canonRel = Get-RelPath $canonFile
& git -C $PackRoot check-ignore -q --no-index -- $canonRel
if ($LASTEXITCODE -eq 0) { Bad 'canonical skill is gitignored' }
else { Good 'canonical skill stays searchable' }

$textExt = @{ '.md' = $true; '.txt' = $true; '.py' = $true; '.ps1' = $true; '.json' = $true; '.yml' = $true; '.yaml' = $true }
$provPaths = @(Get-ChildItem -LiteralPath $provRoot -Recurse -File | Where-Object { $textExt.ContainsKey($_.Extension.ToLowerInvariant()) } | ForEach-Object { $_.FullName })
$provHits = @(Select-String -LiteralPath $provPaths -SimpleMatch -Pattern $needle | Where-Object { $_ })
if ($provHits.Count -lt 5) { Bad ("expected the five generated copies on disk, found " + $provHits.Count) }
else { Good ("found " + $provHits.Count + " generated copies on disk") }

$rels = @($provHits | ForEach-Object { Get-RelPath $_.Path })
# Do not pipe paths to git. Windows PowerShell writes a CR and quotes the
# line, so check-ignore --stdin looks at a different path than the file.
$visible = @()
$matchedRule = $false
foreach ($rel in $rels) {
    $line = @(& git -C $PackRoot check-ignore -v --no-index -- $rel)
    if ($LASTEXITCODE -eq 0 -and (($line -join "`n") -match 'COPY-TO-SKILLS-DIRECTORY/skills/')) {
        $matchedRule = $true
    } else { $visible += $rel }
}
if ($visible.Count -eq 0 -and $matchedRule) { Good 'generated skill copies match the gitignore rule' }
else {
    $sample = ($visible | Select-Object -First 3) -join ' | '
    Bad "generated skill copies are not ignored: $sample"
}

$profileReadme = Join-Path $provRoot 'Hermes\profiles\README.md'
$profileRel = Get-RelPath $profileReadme
$profileHit = @(Select-String -LiteralPath $profileReadme -Pattern 'sillytavern' -SimpleMatch | Where-Object { $_ })
& git -C $PackRoot check-ignore -q --no-index -- $profileRel
if ($profileHit.Count -ge 1 -and $LASTEXITCODE -ne 0) { Good 'Hermes profile docs stay searchable' }
else { Bad 'Hermes profiles/README.md was ignored or did not mention sillytavern' }

$rg = $null
if (-not $SkipRipgrep) { $rg = (Get-Command rg -ErrorAction SilentlyContinue).Source }
if ($rg) {
    $canonHits = @(& $rg -n --fixed-strings --glob '!**/1-TAILORED-PROVIDER-TREES/**' $needle $canonRoot)
    if ($LASTEXITCODE -eq 0 -and $canonHits.Count -ge 1) { Good 'ripgrep finds the canonical skill' }
    else { Bad 'ripgrep did not find the canonical token-efficiency line' }

    $rgProv = @(& $rg -n --fixed-strings $needle $provRoot 2>$null)
    if (-not $rgProv -or $rgProv.Count -eq 0) { Good 'ripgrep hides the generated skill copies' }
    else {
        $sample = ($rgProv | Select-Object -First 3) -join ' | '
        Bad "ripgrep still matches generated copies: $sample"
    }
} else { Good 'ripgrep is not installed; gitignore proof stands in' }

$probeDir = Join-Path $provRoot 'Claude\COPY-TO-SKILLS-DIRECTORY\skills\zz-search-collapse-probe'
$probe = Join-Path $probeDir 'SKILL.md'
$tracked = '1-TAILORED-PROVIDER-TREES/Claude/COPY-TO-SKILLS-DIRECTORY/skills/token-efficiency/SKILL.md'
try {
    New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
    [IO.File]::WriteAllText($probe, "search collapse probe`r`n")
    $status = @(& git -C $PackRoot status --short -- $probe | Where-Object { $_ })
    if ($status.Count -eq 0) { Good 'a new ignored skill file stays out of git status' }
    else { Bad ("new skill file is visible to git status: " + ($status -join ' ')) }

    $ignore = @(& git -C $PackRoot check-ignore -v --no-index -- $tracked)
    $ignoreText = $ignore -join "`n"
    if ($ignoreText -match '\.gitignore' -and $ignoreText -match 'COPY-TO-SKILLS-DIRECTORY/skills/') {
        Good 'gitignore rule matches a tracked provider skill'
    } else { Bad ("check-ignore did not match the skill tree: " + $ignoreText) }

    $listed = @(& git -C $PackRoot ls-files -- $tracked)
    if (($listed -join '') -eq $tracked) { Good 'tracked provider skill stays in the git index' }
    else { Bad ("git ls-files lost the provider skill: " + ($listed -join ' ')) }
} finally {
    if (Test-Path -LiteralPath $probeDir) { Remove-Item -LiteralPath $probeDir -Recurse -Force }
}

if ($fail) { Write-Host "SEARCH COLLAPSE GATE: FAIL ($fail)"; exit 1 }
Write-Host 'SEARCH COLLAPSE GATE: PASS'
exit 0
