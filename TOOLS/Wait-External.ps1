# Wait for a local process or a GitHub Actions run without calling a model.
# A failure returns the log tail or the failed-step log, once.
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [int]$ProcessId = 0,
    [string]$LogPath,
    [int]$TailLines = 80,
    [string]$GitHubRun,
    [string]$Repo
)

$ErrorActionPreference = 'Stop'

function Write-LogTail([string]$Path, [int]$Count) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $lines = [IO.File]::ReadAllLines($Path)
    if ($lines.Length -eq 0) { return }
    $start = $lines.Length - $Count
    if ($start -lt 0) { $start = 0 }
    for ($i = $start; $i -lt $lines.Length; $i++) { Write-Output $lines[$i] }
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
$proc.WaitForExit()
# Process.ExitCode stays empty for a process this component did not start.
# PROCESS_QUERY_LIMITED_INFORMATION is enough to read the exit status.
if (-not ('Uabs.Win32Exit' -as [type])) {
    Add-Type -Namespace Uabs -Name Win32Exit -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern System.IntPtr OpenProcess(uint access, bool inherit, int pid);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern bool GetExitCodeProcess(System.IntPtr handle, out uint exitCode);
[System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError=true)]
public static extern bool CloseHandle(System.IntPtr handle);
'@
}
$handle = [Uabs.Win32Exit]::OpenProcess(0x1000, $false, $ProcessId)
if ($handle -eq [IntPtr]::Zero) { throw "Cannot read exit code for process $ProcessId" }
$raw = [uint32]0
$ok = [Uabs.Win32Exit]::GetExitCodeProcess($handle, [ref]$raw)
[void][Uabs.Win32Exit]::CloseHandle($handle)
if (-not $ok -or $raw -eq 259) { throw "Process $ProcessId has no exit code yet" }
$code = [int]$raw
Write-Output 'state=exited'
Write-Output ('exit=' + $code)
Write-LogTail $LogPath $TailLines
exit $code
