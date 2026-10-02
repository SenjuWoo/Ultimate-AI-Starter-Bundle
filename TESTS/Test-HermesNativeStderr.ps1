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
$HermesExe = $env:COMSPEC
$result = Invoke-UabsHermes -Arguments @('/d','/c','echo fixture-warning 1>&2& echo fixture-result& exit /b 0')
if ($result.Code -ne 0 -or ($result.Output -join ' ') -notmatch 'fixture-result') { throw 'Warning lost successful native result' }
if (($result.Output -join ' ') -notmatch 'fixture-warning') { throw 'Native diagnostics discarded' }
if ($ErrorActionPreference -ne 'Stop') { throw 'Caller preference was not restored' }
$failed = $false
try { [void](Invoke-UabsHermes -Arguments @('/d','/c','echo fixture-error 1>&2& exit /b 7')) }
catch { $failed = $_.Exception.Message -match 'failed \(7\)' }
if (-not $failed) { throw 'Nonzero native exit was accepted' }
$result = Invoke-UabsHermes -Arguments @('/d','/c','exit /b 7') -AllowMissing
if ($result.Code -ne 7) { throw 'AllowMissing lost native exit code' }
Write-Host 'HERMES NATIVE STDERR: PASS'
