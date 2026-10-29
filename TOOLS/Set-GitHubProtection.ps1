# Reproduce this bundle's eight required checks, after observing real main CI.
# Default is a JSON plan; -Apply preserves existing review/restriction policy.
[CmdletBinding(SupportsShouldProcess=$true)]
param([ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repo = 'SenjuWoo/Ultimate-AI-Starter-Bundle', [switch]$Apply)
$ErrorActionPreference = 'Stop'
function Api([string[]]$Arguments) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = & gh api @Arguments 2>&1; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { throw ('gh api failed: ' + ($output -join ' ')) }
    return ($output -join "`n" | ConvertFrom-Json)
}
# GET responses contain account objects; PUT accepts login/slug strings only.
function Accounts($Value) {
    return @{users=@($Value.users | Where-Object { $_ } | ForEach-Object {$_.login}); teams=@($Value.teams | Where-Object { $_ } | ForEach-Object {$_.slug}); apps=@($Value.apps | Where-Object { $_ } | ForEach-Object {$_.slug})}
}
function Reviews($Value) {
    if (-not $Value) { return $null }
    $result = @{}
    foreach ($key in @('dismiss_stale_reviews','require_code_owner_reviews','required_approving_review_count','require_last_push_approval')) {
        if ($null -ne $Value.$key) { $result[$key] = $Value.$key }
    }
    foreach ($key in @('bypass_pull_request_allowances','dismissal_restrictions')) {
        if ($null -ne $Value.$key) { $result[$key] = Accounts $Value.$key }
    }
    return $result
}
function Assert-Policy($Wanted, $Actual, [string]$Path) {
    if ($null -eq $Wanted) { if ($null -ne $Actual) { throw "Policy changed at $Path" }; return }
    if ($Wanted -is [Collections.IDictionary]) {
        foreach ($key in $Wanted.Keys) { Assert-Policy $Wanted[$key] $Actual.$key ($Path + '.' + $key) }
    } elseif ($Wanted -is [array]) {
        if ((@($Wanted | Sort-Object) -join '|') -cne (@($Actual | Sort-Object) -join '|')) { throw "Policy changed at $Path" }
    } elseif ($Wanted -ne $Actual) { throw "Policy changed at $Path" }
}
$required = @('Hermes YAML and physical symlink preservation',
    'Pack gate (Windows PowerShell 5.1, Python 3.12)',
    'Pack gate (Windows PowerShell 5.1, Python 3.13)',
    'Pack gate (Windows PowerShell 5.1, Python 3.14)',
    'Pack gate (Windows PowerShell 5.1, Python 3.15)',
    'MANIFEST verifies against the tree', 'Version strings agree',
    'Bundle installs pinned Forge end to end')
$main = Api -Arguments @("repos/$Repo/commits/main")
$checks = Api -Arguments @("repos/$Repo/commits/$($main.sha)/check-runs?per_page=100")
foreach ($name in $required) {
    if (-not @($checks.check_runs | Where-Object { $_.name -eq $name -and $_.conclusion -eq 'success' }).Count) {
        throw "Required check '$name' has no successful observed run on main $($main.sha)."
    }
}
$branch = Api -Arguments @("repos/$Repo/branches/main")
$existing = if ($branch.protected) { Api -Arguments @("repos/$Repo/branches/main/protection") } else { $null }
$bindings = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
foreach ($check in @($existing.required_status_checks.checks | Where-Object { $_ })) {
    $binding = @{context=[string]$check.context}
    if ($null -ne $check.app_id) { $binding.app_id = [long]$check.app_id }
    $bindings[[string]$check.context] = $binding
}
foreach ($context in @($existing.required_status_checks.contexts | Where-Object { $_ })) {
    if (-not $bindings.ContainsKey([string]$context)) { $bindings[[string]$context] = @{context=[string]$context; app_id=-1} }
}
foreach ($name in $required) {
    if ($bindings.ContainsKey($name)) { continue }
    $apps = @($checks.check_runs | Where-Object { $_.name -eq $name -and $_.conclusion -eq 'success' } | ForEach-Object { $_.app.id } | Where-Object { $null -ne $_ } | Select-Object -Unique)
    if ($apps.Count -ne 1) { throw "Cannot bind required check '$name' to one observed GitHub App." }
    $bindings[$name] = @{context=$name; app_id=[long]$apps[0]}
}
$policy = @{ required_status_checks=@{ strict=$true; checks=@($bindings.Keys | Sort-Object | ForEach-Object { $bindings[$_] }) };
    enforce_admins=$true; required_pull_request_reviews=@{required_approving_review_count=0};
    restrictions=$null; allow_force_pushes=$false; allow_deletions=$false }
if ($existing) {
    if ($existing.required_pull_request_reviews) {
        $policy.required_pull_request_reviews = Reviews $existing.required_pull_request_reviews
    } else {
        $policy.required_pull_request_reviews = $null
    }
    if ($existing.restrictions) {
        $policy.restrictions = Accounts $existing.restrictions
    }
    foreach ($key in @('required_linear_history','required_conversation_resolution','lock_branch','allow_fork_syncing','block_creations')) {
        if ($null -ne $existing.$key) { $policy[$key] = [bool]$existing.$key.enabled }
    }
}
$json = $policy | ConvertTo-Json -Depth 15
if (-not $Apply) { Write-Output $json; exit 0 }
if ($PSCmdlet.ShouldProcess("$Repo main", 'require observed checks and prevent force-push/deletion')) {
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('uabs-protection-' + [guid]::NewGuid().ToString('n') + '.json')
    try {
        [IO.File]::WriteAllText($temp,$json,(New-Object Text.UTF8Encoding($false)))
        $null = Api -Arguments @('-X','PUT',"repos/$Repo/branches/main/protection",'--input',$temp)
    } finally { Remove-Item -LiteralPath $temp -ErrorAction SilentlyContinue }
    $verified = Api -Arguments @("repos/$Repo/branches/main/protection")
    if (-not $verified.required_status_checks.strict -or $verified.allow_force_pushes.enabled -or $verified.allow_deletions.enabled) { throw 'Protection verification failed.' }
    foreach ($name in $required) { if ($verified.required_status_checks.contexts -notcontains $name) { throw "Missing protected check $name" } }
    foreach ($binding in $policy.required_status_checks.checks) {
        $found = @($verified.required_status_checks.checks | Where-Object { $_.context -eq $binding.context -and ($null -eq $binding.app_id -or $_.app_id -eq $binding.app_id) })
        if ($found.Count -ne 1) { throw ('Required check binding changed: ' + $binding.context) }
    }
    Assert-Policy $policy.required_pull_request_reviews (Reviews $verified.required_pull_request_reviews) 'reviews'
    $actualRestrictions = if ($verified.restrictions) { Accounts $verified.restrictions } else { $null }
    Assert-Policy $policy.restrictions $actualRestrictions 'restrictions'
    Write-Output "PROTECTION: PASS ($($main.sha))"
}
