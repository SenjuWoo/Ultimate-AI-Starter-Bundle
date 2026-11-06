# Ensures Serena is registered in the Hermes native code profile.
# Serena is the LSP half of code-intel; it advertises 3 tools (~1,056 tokens)
# on 2.1.0. The profile migrator refuses while a gateway is live, so this
# fallback uses the supported `hermes mcp add` path and is idempotent.
param(
  [string]$HermesExe,
  [string]$SerenaExe
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')

if (-not $HermesExe) { $HermesExe = Get-UabsHermesExecutable }
if (-not $HermesExe -or -not (Test-Path -LiteralPath $HermesExe -PathType Leaf)) {
  throw 'Hermes launcher not found.'
}
if (-not $SerenaExe) { $SerenaExe = Join-Path $env:USERPROFILE '.local\bin\serena.exe' }
if (-not (Test-Path -LiteralPath $SerenaExe -PathType Leaf)) {
  $uv = Get-Command uv -ErrorAction SilentlyContinue
  if (-not $uv) {
    Write-Host 'Serena is not installed and uv is unavailable; skipping Serena registration.'
    exit 0
  }
  Write-Host 'Installing Serena 2.1.0...'
  & $uv.Source tool install --force 'serena-agent==2.1.0'
  if ($LASTEXITCODE -ne 0) { throw "uv tool install serena-agent==2.1.0 exited $LASTEXITCODE" }
  Refresh-ProcessPath
  if (-not (Test-Path -LiteralPath $SerenaExe -PathType Leaf)) {
    $SerenaExe = Join-Path $env:USERPROFILE '.local\bin\serena.exe'
  }
}
if (-not (Test-Path -LiteralPath $SerenaExe -PathType Leaf)) {
  throw "Serena was not found after installation at $SerenaExe"
}

# Stdout only: a Hermes warning on stderr must not abort registration (PS 5.1
# promotes redirected stderr to an ErrorRecord under $ErrorActionPreference=Stop).
$listed = (Get-UabsNativeStdout -Exe $HermesExe -CmdArgs @('-p', 'code', 'mcp', 'list')) -join "`n"
if ($listed -match '(?m)^\s*serena\s') {
  Write-Host 'Serena already registered in the Hermes code profile.'
  exit 0
}

$answer = Join-Path ([IO.Path]::GetTempPath()) ('uabs-serena-answer-' + [guid]::NewGuid().ToString('N') + '.txt')
try {
  [IO.File]::WriteAllText($answer, "y`r`n", (New-Object Text.UTF8Encoding $false))
  $addArgs = @(
    '-p', 'code', 'mcp', 'add', 'serena',
    '--command', $SerenaExe,
    '--connect-timeout', '90',
    '--args', 'start-mcp-server', '--context', 'agent', '--enable-web-dashboard', 'false', '--project-from-cwd'
  )
  $p = Start-Process -FilePath $HermesExe -ArgumentList $addArgs -RedirectStandardInput $answer -NoNewWindow -Wait -PassThru
  if ($p.ExitCode -ne 0) { throw "hermes mcp add exited $($p.ExitCode)" }
} finally {
  Remove-Item -LiteralPath $answer -Force -ErrorAction SilentlyContinue
}

$listed = (Get-UabsNativeStdout -Exe $HermesExe -CmdArgs @('-p', 'code', 'mcp', 'list')) -join "`n"
if ($listed -notmatch '(?m)^\s*serena\s') {
  throw 'Serena was added but is absent from the Hermes code profile list.'
}
Write-Host 'Serena registered in the Hermes code profile.'
