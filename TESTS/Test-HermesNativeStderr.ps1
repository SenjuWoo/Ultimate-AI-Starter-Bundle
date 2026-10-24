[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$path = Join-Path $PackRoot 'TOOLS\Migrate-HermesProfiles.ps1'
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
if ($errors.Count) { throw 'Hermes profile migrator does not parse' }
$definition = $ast.Find({ param($node)
  $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
  $node.Name -eq 'Invoke-UabsHermes'
}, $true)
if (-not $definition) { throw 'Shared Hermes runner not found' }
. ([scriptblock]::Create($definition.Extent.Text))
$migratorRunner = Get-Command -Name $definition.Name -CommandType Function -ErrorAction Stop
$HermesExe = $env:COMSPEC
$result = & $migratorRunner -Arguments @('/d','/c','echo fixture-warning 1>&2& echo fixture-result& exit /b 0')
if ($result.Code -ne 0 -or ($result.Output -join ' ') -notmatch 'fixture-result') { throw 'Warning lost successful native result' }
if (($result.Output -join ' ') -notmatch 'fixture-warning') { throw 'Native diagnostics discarded' }
if ($ErrorActionPreference -ne 'Stop') { throw 'Caller preference was not restored' }
$failed = $false
try { [void](& $migratorRunner -Arguments @('/d','/c','echo fixture-error 1>&2& exit /b 7')) }
catch { $failed = $_.Exception.Message -match 'failed \(7\)' }
if (-not $failed) { throw 'Nonzero native exit was accepted' }
$result = & $migratorRunner -Arguments @('/d','/c','exit /b 7') -AllowMissing
if ($result.Code -ne 7) { throw 'AllowMissing lost native exit code' }
# A cached runtime can disappear or become unlaunchable after a provider update.
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hermes-launch-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
  $python = Get-UabsPythonExecutable
  $script:UabsHermesRuntimeCache = @{'fixture|runpy' = @($python)}
  $out = @(Invoke-UabsHermesPython -HermesExe fixture -PythonArgs @('-c', 'import sys; print("result"); print("diagnostic", file=sys.stderr)'))
  if ($LASTEXITCODE -ne 0 -or ($out -join '') -ne 'result' -or $script:UabsHermesPythonError -notmatch 'diagnostic') { throw 'Python adapter lost successful stdout/stderr.' }
  Invoke-UabsHermesPython -HermesExe fixture -PythonArgs @('-c', 'import sys; print("failed-child", file=sys.stderr); sys.exit(7)') | Out-Null
  if ($LASTEXITCODE -ne 7 -or $script:UabsHermesPythonError -notmatch 'failed-child') { throw 'Python adapter lost a failing child exit.' }
  $invalid = Join-Path $fixture 'invalid.exe'
  [IO.File]::WriteAllText($invalid, 'not an executable image')
  foreach ($runtime in @((Join-Path $fixture 'missing.exe'), $invalid)) {
    $script:UabsHermesRuntimeCache['fixture|runpy'] = @($runtime)
    $global:LASTEXITCODE = 0
    $refused = $false
    try { Invoke-UabsHermesPython -HermesExe fixture -PythonArgs @('-c', 'print("never")') | Out-Null } catch { $refused = $true }
    if (-not $refused -or $LASTEXITCODE -eq 0) { throw 'An unavailable cached Python runtime reported success.' }
  }
  if ($ErrorActionPreference -ne 'Stop') { throw 'Python adapter changed caller error handling.' }
} finally {
  if (Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath())) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
Write-Host 'HERMES NATIVE STDERR: PASS'
