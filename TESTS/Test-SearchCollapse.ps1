# Default search must see canonical skills and provider-specific files, and
# must not see the five generated skill copies. Those copies stay tracked.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $PSCommandPath }
    $PackRoot = Split-Path -Parent $here
}
$fail = 0
function Bad([string]$Message) { Write-Host "FAIL $Message"; $script:fail++ }
function Good([string]$Message) { Write-Host "ok   $Message" }

$rg = (Get-Command rg -ErrorAction SilentlyContinue).Source
if (-not $rg) { Bad 'rg is not on PATH'; exit 1 }

$needle = 'RTK is lossy and command/version dependent, not a universal 97% saving.'
$canonRoot = Join-Path $PackRoot '_CANONICAL-SKILLS'
$provRoot = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES'
$canonHits = @(& $rg -n --fixed-strings --glob '!**/1-TAILORED-PROVIDER-TREES/**' $needle $canonRoot)
if ($LASTEXITCODE -eq 0 -and $canonHits.Count -ge 1) { Good 'canonical skill text is searchable' }
else { Bad 'canonical token-efficiency line was not found' }

$provHits = @(& $rg -n --fixed-strings $needle $provRoot 2>$null)
if (-not $provHits -or $provHits.Count -eq 0) { Good 'generated skill copies are hidden from default search' }
else {
    $sample = ($provHits | Select-Object -First 3) -join ' | '
    Bad "generated skill copies still match: $sample"
}

$profileRoot = Join-Path $provRoot 'Hermes\profiles'
$profileHits = @(& $rg -n -i --fixed-strings sillytavern $profileRoot)
$profileOk = $false
foreach ($line in $profileHits) { if ($line -match 'README\.md') { $profileOk = $true } }
if ($profileOk) { Good 'Hermes profile docs stay searchable' }
else { Bad 'Hermes profiles/README.md was not found by default search' }

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
