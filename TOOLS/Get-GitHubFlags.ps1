# Read-only GitHub security and quality flags for one repository.
# Prints allowlisted fields only. A secret-scanning row is number, type, and
# url. A 403 or 404 on code quality is unavailable, not an empty clean scan.
# A failed Dependabot, code-scanning, or secret-scanning query is unknown,
# not zero. This script only reads. It does not change settings or alerts.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$Repo,
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 60
)
$ErrorActionPreference = 'Stop'

$endpoints = @(
    'dependabot/alerts?state=open&per_page=100',
    'code-scanning/alerts?state=open&per_page=100',
    'secret-scanning/alerts?state=open&per_page=100',
    'code-quality/setup',
    'code-quality/findings?state=open&per_page=100'
)

if (-not $PSCmdlet.ShouldProcess('github flags', 'query')) {
    foreach ($endpoint in $endpoints) { Write-Host ('endpoint ' + $endpoint) }
    Write-Host 'flags=whatif'
    exit 0
}

function Invoke-Native([string]$File, [string]$Arguments) {
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $File
    $info.Arguments = $Arguments
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    try { $proc = [Diagnostics.Process]::Start($info) }
    catch { return @{ Exit = 127; Out = ''; Err = 'Unable to start gh' } }
    try {
        # Drain both pipes together; a full stderr pipe must not hang stdout.
        $stdout = $proc.StandardOutput.ReadToEndAsync()
        $stderr = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
            $proc.Kill()
            $proc.WaitForExit()
            return @{ Exit = 124; Out = ''; Err = 'gh request timed out' }
        }
        return @{ Exit = $proc.ExitCode; Out = $stdout.Result; Err = $stderr.Result }
    } finally { $proc.Dispose() }
}

function Get-HttpStatus($Result) {
    if ($Result.Exit -eq 0) { return 200 }
    $blob = [string]$Result.Err
    if ($blob -match '404' -or $Result.Out -match '"status":\s*"404"' -or $Result.Out -match 'Not Found') { return 404 }
    if ($blob -match '403' -or $Result.Out -match '"status":\s*"403"') { return 403 }
    return 0
}

function Convert-Rows($Text) {
    # The comma keeps an empty array from unrolling into $null. @($null).Count
    # is 1 in Windows PowerShell 5.1, which would report one phantom flag.
    if (-not $Text) { throw 'Missing alert response' }
    $trimmed = $Text.Trim()
    if (-not $trimmed.StartsWith('[') -or -not $trimmed.EndsWith(']')) { throw 'Expected an alert array' }
    if ($trimmed -match '^\[\s*\]$') { return ,@() }
    $parsed = $trimmed | ConvertFrom-Json
    foreach ($row in @($parsed)) {
        if ($null -eq $row -or -not $row.PSObject.Properties['number']) { throw 'Invalid alert row' }
    }
    return ,@($parsed)
}

function Get-Field($Object, [string[]]$Names) {
    $cur = $Object
    foreach ($name in $Names) {
        if ($null -eq $cur) { return '' }
        $prop = $cur.PSObject.Properties[$name]
        if ($null -eq $prop) { return '' }
        $cur = $prop.Value
    }
    if ($null -eq $cur) { return '' }
    return [string]$cur
}

if (-not $Repo) {
    $view = Invoke-Native 'gh' 'repo view --json nameWithOwner --jq .nameWithOwner'
    if ($view.Exit -ne 0 -or -not $view.Out.Trim()) {
        Write-Host 'repo='
        Write-Host 'flags=unknown'
        Write-Host 'reason=repo-view-failed'
        exit 1
    }
    $Repo = $view.Out.Trim()
}
if ($Repo -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$') {
    Write-Host 'reason=invalid-repo'
    Write-Host 'flags=unknown'
    exit 1
}
Write-Host ('repo=' + $Repo)

$unknown = $false
$open = 0

$settings = Invoke-Native 'gh' ('api repos/' + $Repo)
if ($settings.Exit -ne 0) {
    Write-Host 'settings=unknown'
    $unknown = $true
} else {
    try { $repoObj = $settings.Out | ConvertFrom-Json } catch { $repoObj = $null }
    $analysis = $repoObj.security_and_analysis
    if ($null -eq $analysis) {
        Write-Host 'settings=missing'
        $unknown = $true
    } else {
    function Setting([string]$Name) {
        $block = $analysis.PSObject.Properties[$Name]
        if ($null -eq $block -or $null -eq $block.Value) { return 'missing' }
        $status = $block.Value.PSObject.Properties['status']
        if ($null -eq $status -or -not $status.Value) { return 'missing' }
        return [string]$status.Value
    }
    Write-Host ('settings secret_scanning=' + (Setting 'secret_scanning') + ' push_protection=' + (Setting 'secret_scanning_push_protection') + ' validity_checks=' + (Setting 'secret_scanning_validity_checks') + ' non_provider_patterns=' + (Setting 'secret_scanning_non_provider_patterns') + ' dependabot_security_updates=' + (Setting 'dependabot_security_updates'))
    }
}

function Get-Api([string]$ApiPath) {
    $ghArgs = 'api -H Accept:application/vnd.github+json -H X-GitHub-Api-Version:2026-03-10 repos/' + $Repo + '/' + $ApiPath
    $result = Invoke-Native 'gh' $ghArgs
    return @{ Exit = $result.Exit; Status = (Get-HttpStatus $result); Out = $result.Out }
}

function Write-AlertCount([string]$Name, $Result) {
    if ($Result.Status -eq 200 -and $Result.Exit -eq 0) {
        try {
            $rows = Convert-Rows $Result.Out
            $count = @($rows).Count
            Write-Host ($Name + '_open=' + $count)
            if ($count -ge 100) { Write-Host ('truncated ' + $Name + '=yes') }
            $script:open += $count
            return $rows
        } catch { } # Do not echo malformed JSON: it may contain secret material.
    }
    Write-Host ($Name + '_open=unknown')
    $script:unknown = $true
    return @()
}

$dependabot = Get-Api 'dependabot/alerts?state=open&per_page=100'
foreach ($row in @(Write-AlertCount 'dependabot' $dependabot)) {
    Write-Host ('flag dependabot number=' + (Get-Field $row @('number')) + ' severity=' + (Get-Field $row @('security_advisory','severity')) + ' package=' + (Get-Field $row @('dependency','package','name')) + ' manifest=' + (Get-Field $row @('dependency','manifest_path')) + ' url=' + (Get-Field $row @('html_url')))
}

$codeScan = Get-Api 'code-scanning/alerts?state=open&per_page=100'
foreach ($row in @(Write-AlertCount 'code_scanning' $codeScan)) {
    Write-Host ('flag code_scanning number=' + (Get-Field $row @('number')) + ' rule=' + (Get-Field $row @('rule','id')) + ' path=' + (Get-Field $row @('most_recent_instance','location','path')) + ' line=' + (Get-Field $row @('most_recent_instance','location','start_line')) + ' url=' + (Get-Field $row @('html_url')))
}

$secrets = Get-Api 'secret-scanning/alerts?state=open&per_page=100'
foreach ($row in @(Write-AlertCount 'secret_scanning' $secrets)) {
    Write-Host ('flag secret_scanning number=' + (Get-Field $row @('number')) + ' secret_type=' + (Get-Field $row @('secret_type')) + ' url=' + (Get-Field $row @('html_url')))
}

$quality = Get-Api 'code-quality/setup'
if ($quality.Status -eq 404 -or $quality.Status -eq 403) {
    Write-Host 'code_quality=unavailable'
    Write-Host 'code_quality_open=unavailable'
} elseif ($quality.Exit -ne 0) {
    Write-Host 'code_quality=unknown'
    Write-Host 'code_quality_open=unknown'
    $unknown = $true
} else {
    try { $setup = $quality.Out | ConvertFrom-Json } catch { $setup = $null }
    $state = Get-Field $setup @('state')
    if (-not $state) { $state = 'unknown' }
    Write-Host ('code_quality=' + $state)
    if ($state -eq 'configured') {
        $findings = Get-Api 'code-quality/findings?state=open&per_page=100'
        if ($findings.Status -in @(403, 404)) {
            Write-Host 'code_quality_open=unavailable'
        } else {
            foreach ($row in @(Write-AlertCount 'code_quality' $findings)) {
                Write-Host ('flag code_quality number=' + (Get-Field $row @('number')) + ' rule=' + (Get-Field $row @('rule','id')) + ' severity=' + (Get-Field $row @('rule','severity')) + ' path=' + (Get-Field $row @('location','path')) + ' line=' + (Get-Field $row @('location','start_line')) + ' url=' + (Get-Field $row @('url')))
            }
        }
    } elseif ($state -eq 'not-configured') {
        Write-Host 'code_quality_open=unavailable'
    } else {
        Write-Host 'code_quality_open=unknown'
        $unknown = $true
    }
}

if ($unknown) {
    Write-Host 'flags=unknown'
    exit 1
}
if ($open -gt 0) {
    Write-Host 'flags=open'
    exit 2
}
Write-Host 'flags=clean'
exit 0
