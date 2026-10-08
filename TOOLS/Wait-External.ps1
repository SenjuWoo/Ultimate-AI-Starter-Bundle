# Wait for a local process or a GitHub Actions run without calling a model.
# A failure returns the log tail or the failed-step log, once.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [int]$ProcessId = 0,
    [string]$LogPath,
    [ValidateRange(1, 2147483647)][int]$TailLines = 80,
    [string]$GitHubRun,
    [string]$Repo
)

$ErrorActionPreference = 'Stop'

function Write-LogTail([string]$Path, [int]$Count) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    Get-Content -LiteralPath $Path -Encoding UTF8 -Tail $Count
}

if ($GitHubRun -and $ProcessId) { throw 'Pass -ProcessId or -GitHubRun, not both.' }
if (-not $GitHubRun -and -not $ProcessId) { throw 'Pass -ProcessId or -GitHubRun.' }

if ($GitHubRun) {
    $watch = @('run', 'watch', $GitHubRun, '--compact', '--exit-status')
    if ($Repo) { $watch += @('-R', $Repo) }
    $shown = 'gh ' + ($watch -join ' ')
    if ($WhatIfPreference) {
        Write-Output $shown
        exit 0
    }
    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if (-not $gh) {
        Write-Output 'gh not on PATH'
        exit 127
    }
    & $gh.Source @watch
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        $view = @('run', 'view', $GitHubRun, '--log-failed')
        if ($Repo) { $view += @('-R', $Repo) }
        & $gh.Source @view
    }
    Write-Output ('state=exited')
    Write-Output ('exit=' + $code)
    exit $code
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
