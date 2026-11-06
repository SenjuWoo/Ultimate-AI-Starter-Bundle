# Ensures codebase-memory-mcp is registered in the Hermes native code profile.
# The profile migrator refuses while a gateway is live; this fallback uses the
# supported `hermes mcp add` path and is safe to run repeatedly.
param(
  [string]$HermesExe,
  [string]$CodebaseMemoryExe
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')

if (-not $HermesExe) { $HermesExe = Get-UabsHermesExecutable }
if (-not $HermesExe -or -not (Test-Path -LiteralPath $HermesExe -PathType Leaf)) {
  throw 'Hermes launcher not found.'
}
if (-not $CodebaseMemoryExe) {
  $CodebaseMemoryExe = [Environment]::GetEnvironmentVariable('CODEBASE_MEMORY_MCP', 'Process')
  if (-not $CodebaseMemoryExe) { $CodebaseMemoryExe = [Environment]::GetEnvironmentVariable('CODEBASE_MEMORY_MCP', 'User') }
  if (-not $CodebaseMemoryExe) {
    $CodebaseMemoryExe = Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe'
  }
}
if (-not (Test-Path -LiteralPath $CodebaseMemoryExe -PathType Leaf)) {
  Write-Host 'codebase-memory-mcp is not installed; skipping Hermes registration.'
  exit 0
}

# Stdout only. Any Hermes warning (a plugin manifest it cannot read, an update
# hint) arrives on stderr, and Windows PowerShell 5.1 turns a redirected stderr
# line into an ErrorRecord -- with $ErrorActionPreference='Stop' that aborts this
# script before the server is ever registered. A warning is not a failure.
$listed = (Get-UabsNativeStdout -Exe $HermesExe -CmdArgs @('-p', 'code', 'mcp', 'list')) -join "`n"
if ($listed -match '(?m)^\s*codebase-memory-mcp\s') {
  Write-Host 'codebase-memory-mcp already registered in the Hermes code profile.'
  exit 0
}

# `hermes mcp add` asks "Enable all N tools?" even with --args. Feed one y;
# Start-Process needs a real file for RedirectStandardInput on PS 5.1.
$answer = Join-Path ([IO.Path]::GetTempPath()) ('uabs-cbm-answer-' + [guid]::NewGuid().ToString('N') + '.txt')
try {
  [IO.File]::WriteAllText($answer, "y`r`n", (New-Object Text.UTF8Encoding $false))
  $addArgs = @(
    '-p', 'code', 'mcp', 'add', 'codebase-memory-mcp',
    '--command', $CodebaseMemoryExe,
    '--connect-timeout', '90',
    '--args'
  )
  $p = Start-Process -FilePath $HermesExe -ArgumentList $addArgs -RedirectStandardInput $answer -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "hermes mcp add exited $($p.ExitCode)" }
} finally {
  Remove-Item -LiteralPath $answer -Force -ErrorAction SilentlyContinue
}

$listed = (Get-UabsNativeStdout -Exe $HermesExe -CmdArgs @('-p', 'code', 'mcp', 'list')) -join "`n"
if ($listed -notmatch '(?m)^\s*codebase-memory-mcp\s') {
  throw 'codebase-memory-mcp was added but is absent from the Hermes code profile list.'
}
Write-Host 'codebase-memory-mcp registered in the Hermes code profile.'
