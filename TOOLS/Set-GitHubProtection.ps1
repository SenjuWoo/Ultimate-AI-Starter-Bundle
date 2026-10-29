# Write the trunk rulesets: no force-push or deletion for anyone; CI gates only PR merges.
# Two named rulesets on the default branch of a repository its maintainer pushes to:
#   integrity  blocks force-push and deletion for everyone; no bypass actor.
#   checks     requires the named CI jobs before a pull request merges (Dependabot,
#              contributors). Repository admins bypass it, so the maintainer pushes
#              to main after the local gate; release.yml still publishes only from a
#              SHA whose every check passed.
# Default prints the plan; -Apply writes, retires compatible classic protection and
# verifies the effective rules. Rulesets with other names are never touched.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repo = 'SenjuWoo/Ultimate-AI-Starter-Bundle',
    # This bundle's CI jobs; pass another repository's job names explicitly (';'-separated under -File).
    [string[]]$Checks = @('Hermes YAML and physical symlink preservation',
        'Pack gate (Windows PowerShell 5.1, Python 3.12)', 'Pack gate (Windows PowerShell 5.1, Python 3.13)',
        'Pack gate (Windows PowerShell 5.1, Python 3.14)', 'Pack gate (Windows PowerShell 5.1, Python 3.15)',
        'MANIFEST verifies against the tree', 'Version strings agree', 'Bundle installs latest companions end to end'),
    [switch]$Apply
)
$ErrorActionPreference = 'Stop'
# Job names contain commas, so a -File caller separates them with ';'.
$Checks = @($Checks | ForEach-Object { $_ -split ';' } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Select-Object -Unique)
if (-not $Checks.Count) { throw 'Name at least one required check.' }
function Api([string[]]$Arguments, [switch]$Allow404) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = & gh api @Arguments 2>&1; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    if ($code -ne 0) {
        if ($Allow404 -and (($output -join ' ') -match 'HTTP 404|Not Found|not protected')) { return $null }
        throw ('gh api failed: ' + ($output -join ' '))
    }
    $text = ($output -join "`n").Trim()
    if (-not $text) { return $null }
    return ($text | ConvertFrom-Json)
}
function Send([string]$Method, [string]$Endpoint, $Body) {
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('uabs-rules-' + [guid]::NewGuid().ToString('n') + '.json')
    try {
        [IO.File]::WriteAllText($temp, ($Body | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
        return Api -Arguments @('-X', $Method, $Endpoint, '--input', $temp)
    } finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
}

$branch = (Api -Arguments @("repos/$Repo")).default_branch
if (-not $branch) { throw "Default branch of $Repo is unknown." }
$head = (Api -Arguments @("repos/$Repo/commits/$branch")).sha
$runs = @((Api -Arguments @("repos/$Repo/commits/$head/check-runs?per_page=100")).check_runs)
$bindings = @()
foreach ($name in $Checks) {
    $apps = @($runs | Where-Object { $_.name -ceq $name -and $_.conclusion -eq 'success' } | ForEach-Object { $_.app.id } | Select-Object -Unique)
    if (-not $apps.Count) { throw "Required check '$name' has no successful observed run on $branch $head." }
    if ($apps.Count -ne 1) { throw "Cannot bind required check '$name' to one observed GitHub App." }
    $bindings += [ordered]@{ context = $name; integration_id = [long]$apps[0] }
}
$scope = @{ ref_name = @{ include = @('~DEFAULT_BRANCH'); exclude = @() } }
$wanted = @(
    [ordered]@{ name = 'integrity'; target = 'branch'; enforcement = 'active'; conditions = $scope; bypass_actors = @()
        rules = @(@{ type = 'deletion' }, @{ type = 'non_fast_forward' }) },
    [ordered]@{ name = 'checks'; target = 'branch'; enforcement = 'active'; conditions = $scope
        # 5 = the built-in Repository admin role.
        bypass_actors = @(@{ actor_id = 5; actor_type = 'RepositoryRole'; bypass_mode = 'always' })
        rules = @(@{ type = 'required_status_checks'; parameters = [ordered]@{
            strict_required_status_checks_policy = $false; do_not_enforce_on_create = $false; required_status_checks = $bindings } }) }
)
if (-not $Apply) { Write-Output ($wanted | ConvertTo-Json -Depth 12); exit 0 }

# Classic protection would still demand checks on the maintainer's pushes. Retire it
# only when it carries nothing these rulesets do not reproduce.
$classic = Api -Arguments @("repos/$Repo/branches/$branch/protection") -Allow404
if ($classic) {
    $reviews = $classic.required_pull_request_reviews
    if ($classic.restrictions -or ($reviews -and ([int]$reviews.required_approving_review_count -gt 0 -or $reviews.require_code_owner_reviews))) {
        throw 'Classic protection carries reviewer or push restrictions; migrate those by hand before applying rulesets.'
    }
}
if ($PSCmdlet.ShouldProcess("$Repo $branch", 'write integrity/checks rulesets')) {
    $existing = @(Api -Arguments @("repos/$Repo/rulesets"))
    foreach ($ruleset in $wanted) {
        $match = @($existing | Where-Object { $_.name -ceq $ruleset.name -and $_.target -eq 'branch' })
        if ($match.Count -gt 1) { throw "More than one ruleset is named '$($ruleset.name)'." }
        if ($match.Count) { $null = Send 'PUT' "repos/$Repo/rulesets/$($match[0].id)" $ruleset }
        else { $null = Send 'POST' "repos/$Repo/rulesets" $ruleset }
    }
    if ($classic) { $null = Api -Arguments @('-X', 'DELETE', "repos/$Repo/branches/$branch/protection") }
    # Verify what GitHub enforces on the branch, not what was sent.
    $rules = @(Api -Arguments @("repos/$Repo/rules/branches/$branch"))
    foreach ($type in @('deletion', 'non_fast_forward')) {
        if (-not @($rules | Where-Object { $_.type -eq $type }).Count) { throw "Effective rules lack $type." }
    }
    $enforced = @($rules | Where-Object { $_.type -eq 'required_status_checks' } | ForEach-Object { $_.parameters.required_status_checks })
    foreach ($binding in $bindings) {
        if (-not @($enforced | Where-Object { $_.context -ceq $binding.context -and [long]$_.integration_id -eq $binding.integration_id }).Count) {
            throw "Required check binding missing after apply: $($binding.context)"
        }
    }
    $integrity = @(Api -Arguments @("repos/$Repo/rulesets") | Where-Object { $_.name -ceq 'integrity' })
    if ($integrity.Count -ne 1 -or @((Api -Arguments @("repos/$Repo/rulesets/$($integrity[0].id)")).bypass_actors).Count) {
        throw 'The integrity ruleset must exist once with no bypass actor.'
    }
    Write-Output "PROTECTION: PASS ($head)"
}
