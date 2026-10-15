# Exercise the actual installer's npm cleanup against disposable prefixes, never live tools.
# The shipped function is realized from INSTALL-AIO.ps1 below, not copied: function Remove-UabsOutdatedHermesNpmDuplicate {
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
. (Join-Path $PackRoot 'TOOLS\UABS-Mcp-Write.ps1')
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PackRoot 'INSTALL-AIO.ps1'), [ref]$null, [ref]$null)
$function = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Remove-UabsOutdatedHermesNpmDuplicate' }, $true)
. ([scriptblock]::Create($function.Extent.Text))
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-npm-duplicate-' + [guid]::NewGuid().ToString('N'))
$saved = @{}; foreach($key in @('APPDATA','LOCALAPPDATA','USERPROFILE','UABS_TEST_NPM_ROOT')) { $saved[$key] = [Environment]::GetEnvironmentVariable($key) }
try {
  $env:APPDATA = Join-Path $fixture 'roaming'; $env:LOCALAPPDATA = Join-Path $fixture 'local'; $env:USERPROFILE = Join-Path $fixture 'home'
  $roaming = Join-Path $env:APPDATA 'npm'; $hermes = Join-Path $env:LOCALAPPDATA 'hermes\node'
  foreach($prefix in @($roaming,$hermes)) { New-Item -ItemType Directory -Force -Path $prefix | Out-Null; [IO.File]::WriteAllText((Join-Path $prefix 'npm.cmd'), 'fixture only') }
  $npm = Join-Path $fixture 'active-npm.ps1'
  [IO.File]::WriteAllText($npm, 'Write-Output $env:UABS_TEST_NPM_ROOT; $global:LASTEXITCODE = 0')
  $component = [pscustomobject]@{ npm_spec='codeburn@0.9.27'; version='0.9.27' }
  function Put-Package($Prefix, $Version) {
    $dir=Join-Path $Prefix 'node_modules\codeburn'; New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'package.json'), ('{"name":"codeburn","version":"' + $Version + '","bin":{"codeburn":"dist/cli.js"}}'))
    [IO.File]::WriteAllText((Join-Path $dir 'personal-note.txt'), 'preserve this byte-exactly in the rollback copy')
    [IO.File]::WriteAllText((Join-Path $Prefix 'codeburn.cmd'), 'older npm launcher')
  }
  # Only the network/npm uninstall boundary is doubled; ownership and backup logic stay real.
  function Invoke-UabsNative([string]$Exe, [string[]]$ArgList) {
    Assert ($ArgList.Count -eq 5 -and $ArgList[0] -eq '--prefix' -and $ArgList[2] -eq 'uninstall' -and $ArgList[3] -eq '-g' -and $ArgList[4] -eq 'codeburn') 'Wrong npm uninstall arguments.'
    $prefix=[IO.Path]::GetFullPath($ArgList[1])
    Assert ($prefix -in @($roaming,$hermes)) 'Uninstall escaped the known fixture prefixes.'
    Remove-Item -LiteralPath (Join-Path $prefix 'node_modules\codeburn') -Recurse -Force
    Remove-Item -LiteralPath (Join-Path $prefix 'codeburn.cmd') -Force
    return $true
  }
  foreach($pair in @(@($hermes,$roaming),@($roaming,$hermes))) {
    $active=$pair[0]; $old=$pair[1]; $env:UABS_TEST_NPM_ROOT=Join-Path $active 'node_modules'
    Put-Package $active '0.9.27'; Put-Package $old '0.9.23'
    Remove-UabsOutdatedHermesNpmDuplicate -Component $component -ActiveNpm $npm
    Assert (-not(Test-Path -LiteralPath (Join-Path $old 'node_modules\codeburn'))) 'An older npm prefix still shadows the installed version.'
    Assert (Test-Path -LiteralPath (Join-Path $active 'node_modules\codeburn\package.json')) 'The active package was deleted.'
    $backups=@(Get-ChildItem -LiteralPath (Get-UabsStateRoot) -Recurse -Filter 'personal-note.txt' -File)
    Assert ($backups.Count -gt 0 -and [IO.File]::ReadAllText($backups[-1].FullName) -ceq 'preserve this byte-exactly in the rollback copy') 'The old package has no verified recovery copy.'
    Remove-UabsOutdatedHermesNpmDuplicate -Component $component -ActiveNpm $npm
    Put-Package $old '0.9.28'
    Remove-UabsOutdatedHermesNpmDuplicate -Component $component -ActiveNpm $npm
    Assert (Test-Path -LiteralPath (Join-Path $old 'node_modules\codeburn\package.json')) 'A newer personal version was deleted.'
  }
  Write-Host 'NPM DUPLICATE GATE: PASS'
} finally {
  foreach($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key]) }
  if(Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
