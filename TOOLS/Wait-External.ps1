# Wait for a local process or exact-SHA GitHub checks without calling a model.
# GitHub: -GitHubRun auto (HEAD), an explicit run ID, or -Sha; optional -Repo owner/name.
# Verdict exits: 0 pass, 1 fail, 8 pending at timeout, 2 none, 3 unknown (including gh errors).
# GitHub polling/requests share a deadline; failed logs cap lines, 1,000 chars/line and 16,000 chars total.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [int]$ProcessId = 0,
    [string]$LogPath,
    [ValidateRange(1, 2147483647)][int]$TailLines = 80,
    [string]$GitHubRun,
    [string]$Repo,
    [string]$Sha,
    [ValidateRange(1, 86400)][int]$TimeoutSeconds = 300,
    [ValidateRange(1, 60)][int]$PollSeconds = 2
)

$ErrorActionPreference = 'Stop'

function Write-LogTail([string]$Path, [int]$Count) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    Get-Content -LiteralPath $Path -Encoding UTF8 -Tail $Count
}

if (($GitHubRun -or $Sha) -and $ProcessId) { throw 'Pass -ProcessId or GitHub arguments, not both.' }
if (-not $GitHubRun -and -not $Sha -and -not $ProcessId) { throw 'Pass -ProcessId, -GitHubRun auto/<id>, or -Sha.' }

if ($GitHubRun -or $Sha) {
    if ($WhatIfPreference) {
        Write-Output 'Read exact-SHA GitHub Actions runs, check-runs and statuses; poll to TimeoutSeconds; no changes.'
        exit 0
    }

    $clock = [Diagnostics.Stopwatch]::StartNew()
    $snapshot = @{ Verdict = 'unknown'; Runs = @(); Checks = @(); Reason = ''; Command = ''; Error = '' }
    $gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1

    # These arguments are fixed flags or validated identifiers, never shell text.
    function Invoke-CiNative([string]$File, [string[]]$Arguments) {
        $remaining = [int][Math]::Ceiling(($TimeoutSeconds * 1000) - $clock.Elapsed.TotalMilliseconds)
        if ($remaining -le 0) { throw 'GitHub request timeout' }
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $File
        $info.Arguments = ($Arguments | ForEach-Object { '"' + $_ + '"' }) -join ' '
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $snapshot.Command = ([IO.Path]::GetFileName($File) + ' ' + ($Arguments -join ' '))
        $process = [Diagnostics.Process]::Start($info)
        try {
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit($remaining)) {
                $process.Kill()
                $null = $process.WaitForExit(1000)
                throw 'GitHub request timeout'
            }
            $remaining = [int][Math]::Max(0, [Math]::Ceiling(($TimeoutSeconds * 1000) - $clock.Elapsed.TotalMilliseconds))
            if (-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($stdout, $stderr), $remaining)) {
                throw 'GitHub output timeout'
            }
            if ($process.ExitCode -ne 0) {
                $snapshot.Error = $stderr.Result.Trim()
                throw ('Command exit ' + $process.ExitCode)
            }
            return $stdout.Result
        } finally { $process.Dispose() }
    }

    function Read-CiPages([string]$Endpoint, [string]$Field) {
        $raw = Invoke-CiNative $gh.Source @('api', '--paginate', '--slurp', '-H', 'X-GitHub-Api-Version:2026-03-10', $Endpoint)
        if (-not $raw.Trim().StartsWith('[')) { throw 'Expected paginated JSON array' }
        # Desktop returns the outer JSON array as one pipeline object; assign it directly.
        $pages = ConvertFrom-Json -InputObject $raw
        $rows = @()
        foreach ($page in $pages) {
            if ($Field) {
                if (-not $page.PSObject.Properties[$Field]) { throw ('Missing JSON field ' + $Field) }
                $rows += @($page.$Field)
            } else { $rows += @($page) }
        }
        return ,@($rows | Where-Object { $null -ne $_ })
    }

    function Get-CiState([string]$Status, [string]$Conclusion) {
        if ($Status -ne 'completed') {
            if ($Status -notin @('queued', 'in_progress', 'waiting', 'requested', 'pending')) { throw 'Unknown check status' }
            return 'pending'
        }
        if ($Conclusion -eq 'success') { return 'passed' }
        if ($Conclusion -in @('skipped', 'neutral')) { return 'skipped' }
        if ($Conclusion -in @('failure', 'cancelled', 'timed_out', 'action_required', 'stale', 'startup_failure')) { return 'failed' }
        throw 'Unknown check conclusion'
    }

    function One-Line([string]$Value) {
        return ($Value -replace '[\r\n\t]', ' ' -replace '(?i)(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+)', '[redacted]')
    }

    try {
        if (-not $gh) { throw 'gh not on PATH' }
        if (-not $Repo) { $Repo = (Invoke-CiNative $gh.Source @('repo', 'view', '--json', 'nameWithOwner', '--jq', '.nameWithOwner')).Trim() }
        if ($Repo -notmatch '^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$') { throw 'Invalid owner/repository' }
        if (-not $Sha) {
            $git = Get-Command git -CommandType Application -ErrorAction Stop | Select-Object -First 1
            $Sha = (Invoke-CiNative $git.Source @('rev-parse', 'HEAD')).Trim()
        }
        if ($Sha -notmatch '^[a-fA-F0-9]{40}$') { throw 'Sha must be a full 40-character commit SHA' }
        $Sha = $Sha.ToLowerInvariant()
        if ($GitHubRun -and $GitHubRun -ne 'auto') {
            if ($GitHubRun -notmatch '^[1-9][0-9]*$') { throw 'GitHubRun must be auto or a numeric run ID' }
            $selected = Invoke-CiNative $gh.Source @('api', ('repos/' + $Repo + '/actions/runs/' + $GitHubRun)) | ConvertFrom-Json
            if ($selected.head_sha -ne $Sha) { throw 'Run ID does not target the requested SHA' }
        }
        $repository = Invoke-CiNative $gh.Source @('api', ('repos/' + $Repo)) | ConvertFrom-Json
        if (-not $repository.default_branch) { throw 'Repository default branch is unknown' }
        $branchEndpoint = 'repos/' + $Repo + '/branches/' + [Uri]::EscapeDataString([string]$repository.default_branch)
        $branch = Invoke-CiNative $gh.Source @('api', $branchEndpoint) | ConvertFrom-Json
        if ($null -eq $branch.protected) { throw 'Branch protection state is unknown' }
        $required = @()
        if ($branch.protected) {
            # Unreadable/ruleset-only policy is unknown, never permission to omit expected checks.
            $protection = Invoke-CiNative $gh.Source @('api', ($branchEndpoint + '/protection')) | ConvertFrom-Json
            $required = @($protection.required_status_checks.checks | Where-Object { $_ })
            foreach ($context in @($protection.required_status_checks.contexts | Where-Object { $_ })) {
                if (-not @($required | Where-Object { $_.context -ceq $context }).Count) {
                    $required += [pscustomobject]@{ context = [string]$context; app_id = -1 }
                }
            }
        }
        $delay = $PollSeconds
        do {
            # The latest attempt for every workflow/event is authoritative, not one arbitrary latest run.
            $allRuns = Read-CiPages ('repos/' + $Repo + '/actions/runs?head_sha=' + $Sha + '&per_page=100') 'workflow_runs'
            $runs = @($allRuns | Group-Object -Property workflow_id, event | ForEach-Object {
                $_.Group | Sort-Object -Property @{Expression = { [long]$_.id }; Descending = $true} | Select-Object -First 1
            })
            if (@($runs | Where-Object { $_.head_sha -ne $Sha }).Count) { throw 'Actions returned a different SHA' }
            if ($GitHubRun -and $GitHubRun -ne 'auto' -and -not @($allRuns | Where-Object { [string]$_.id -eq $GitHubRun }).Count) {
                throw 'Selected run was not returned for this SHA'
            }
            $checks = Read-CiPages ('repos/' + $Repo + '/commits/' + $Sha + '/check-runs?filter=latest&per_page=100') 'check_runs'
            $statuses = Read-CiPages ('repos/' + $Repo + '/commits/' + $Sha + '/statuses?per_page=100') ''
            $rows = @()
            foreach ($check in @($checks | Group-Object -Property name, { $_.app.id } | ForEach-Object { $_.Group | Sort-Object -Property @{Expression = { [long]$_.id }; Descending = $true} | Select-Object -First 1 })) {
                if (-not $check.name -or $check.head_sha -ne $Sha) { throw 'Invalid check-run identity' }
                $rows += [pscustomobject]@{ Name = [string]$check.name; State = (Get-CiState $check.status $check.conclusion); Url = [string]$check.html_url }
            }
            # /statuses is historical; old red/pending rows do not override a newer context result.
            foreach ($status in @($statuses | Group-Object -Property context | ForEach-Object { $_.Group | Sort-Object -Property @{Expression = { [long]$_.id }; Descending = $true} | Select-Object -First 1 })) {
                if (-not $status.context) { throw 'Invalid commit-status context' }
                $state = switch ($status.state) { 'success' { 'passed' }; 'failure' { 'failed' }; 'error' { 'failed' }; 'pending' { 'pending' }; default { throw 'Unknown commit-status state' } }
                $rows += [pscustomobject]@{ Name = [string]$status.context; State = $state; Url = [string]$status.target_url }
            }
            foreach ($run in $runs) {
                $state = Get-CiState $run.status $run.conclusion
                # A workflow can fail before jobs/check-runs exist (for example invalid YAML).
                if ($state -ne 'passed' -or $rows.Count -eq 0) {
                    $rows += [pscustomobject]@{ Name = ('workflow: ' + $run.name); State = $state; Url = [string]$run.html_url }
                }
            }
            $missing = @()
            foreach ($expected in $required) {
                if (-not $expected.context) { throw 'Invalid protected check identity' }
                $found = @($checks | Where-Object { $_.name -ceq $expected.context -and ($null -eq $expected.app_id -or $expected.app_id -eq -1 -or $_.app.id -eq $expected.app_id) })
                if (-not $found.Count -and ($null -eq $expected.app_id -or $expected.app_id -eq -1)) {
                    $found = @($statuses | Where-Object { $_.context -ceq $expected.context })
                }
                if (-not $found.Count) { $missing += [string]$expected.context }
            }
            # A partly reported protected suite is pending; no CI at all remains none.
            if ($rows.Count) {
                foreach ($name in $missing) { $rows += [pscustomobject]@{ Name = $name; State = 'pending'; Url = '' } }
            }
            $snapshot.Runs = $runs
            $snapshot.Checks = $rows
            $snapshot.Error = ''
            $snapshot.Command = ''
            $snapshot.Reason = if ($missing.Count) { 'Required checks have not reported: ' + ($missing -join ',') } else { '' }
            $snapshot.Verdict = if (@($rows | Where-Object { $_.State -in @('failed', 'skipped') }).Count) { 'fail' }
                elseif (@($rows | Where-Object { $_.State -eq 'pending' }).Count) { 'pending' }
                elseif ($rows.Count) { 'pass' } else { 'none' }
            if ($snapshot.Verdict -ne 'pending') { break }
            $remaining = ($TimeoutSeconds * 1000) - $clock.Elapsed.TotalMilliseconds
            if ($remaining -le 0) { break }
            Start-Sleep -Milliseconds ([int][Math]::Min($delay * 1000, $remaining))
            $delay = [Math]::Min(30, $delay * 2)
        } while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds)
    } catch {
        $snapshot.Verdict = 'unknown'
        $snapshot.Reason = $_.Exception.Message
    }

    $passed = @($snapshot.Checks | Where-Object { $_.State -eq 'passed' }).Count
    $failed = @($snapshot.Checks | Where-Object { $_.State -eq 'failed' }).Count
    $pending = @($snapshot.Checks | Where-Object { $_.State -eq 'pending' }).Count
    $skipped = @($snapshot.Checks | Where-Object { $_.State -eq 'skipped' }).Count
    Write-Output ('verdict=' + $snapshot.Verdict)
    Write-Output ('sha=' + (One-Line $Sha))
    Write-Output ('run_id=' + (($snapshot.Runs | ForEach-Object { $_.id }) -join ','))
    Write-Output ('workflow=' + (One-Line (($snapshot.Runs | ForEach-Object { $_.name }) -join ',')))
    Write-Output ('checks=' + $snapshot.Checks.Count + ' passed=' + $passed + ' failed=' + $failed + ' pending=' + $pending + ' skipped=' + $skipped)
    Write-Output ('failing=' + (One-Line (($snapshot.Checks | Where-Object { $_.State -in @('failed', 'skipped') } | ForEach-Object { $_.Name }) -join ',')))
    $urls = @($snapshot.Runs | ForEach-Object { $_.html_url })
    if (-not $urls.Count) { $urls = @($snapshot.Checks | ForEach-Object { $_.Url } | Where-Object { $_ }) }
    Write-Output ('url=' + (One-Line (($urls | Select-Object -Unique) -join ',')))
    if ($snapshot.Reason) { Write-Output ('reason=' + (One-Line $snapshot.Reason)) }
    if ($snapshot.Verdict -eq 'unknown') {
        Write-Output ('command=' + (One-Line $snapshot.Command))
        Write-Output ('stderr=' + (One-Line $snapshot.Error).Substring(0, [Math]::Min(2000, (One-Line $snapshot.Error).Length)))
    }
    if ($snapshot.Verdict -eq 'fail') {
        $tails = @()
        foreach ($run in @($snapshot.Runs | Where-Object { $_.conclusion -in @('failure', 'timed_out', 'action_required', 'startup_failure') })) {
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { break }
            try {
                $log = Invoke-CiNative $gh.Source @('run', 'view', [string]$run.id, '-R', $Repo, '--log-failed')
                $tails += @($log -split '\r?\n' | Select-Object -Last $TailLines)
            } catch { $tails += 'Failed-step log unavailable; use the run URL above.' }
        }
        $budget = 16000
        foreach ($line in @($tails | Select-Object -Last $TailLines)) {
            if ($budget -le 5) { break }
            $safe = One-Line $line
            $safe = $safe.Substring(0, [Math]::Min($safe.Length, [Math]::Min(1000, $budget - 5)))
            Write-Output ('log=' + $safe)
            $budget -= $safe.Length + 5
        }
    }
    $codes = @{ pass = 0; fail = 1; pending = 8; none = 2; unknown = 3 }
    exit $codes[$snapshot.Verdict]
}

try {
    $proc = [Diagnostics.Process]::GetProcessById($ProcessId)
} catch {
    throw "No process with id $ProcessId"
}
try {
    # Acquire and retain the handle while the process still exists. .NET then
    # preserves signed Windows exit codes, including -1 and a legitimate 259.
    $null = $proc.Handle
    $proc.WaitForExit()
    $code = $proc.ExitCode
} finally {
    $proc.Dispose()
}
Write-Output 'state=exited'
Write-Output ('exit=' + $code)
Write-LogTail $LogPath $TailLines
exit $code
