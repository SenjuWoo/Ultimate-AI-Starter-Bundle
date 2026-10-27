# Exercise the real installer function against product markers without running the installer body.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference='Stop'
if (-not $PackRoot) { $PackRoot=Split-Path -Parent $PSScriptRoot }
$tokens=$null; $parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PackRoot 'INSTALL-AIO.ps1'),[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw 'Installer parse failed.' }
$definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-UabsForgeRuntimeVersion'},$true)
if (-not $definition) { throw 'Runtime version function missing.' }
. ([scriptblock]::Create($definition.Extent.Text))
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('uabs-forge-version-'+[guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Path $fixture | Out-Null
  [IO.File]::WriteAllText((Join-Path $fixture 'VERSION.txt'),"Skyrim Forge 6.3.1`n")
  if ((Get-UabsForgeRuntimeVersion $fixture) -ne '6.3.1') { throw 'Slim runtime needs a source-only CURRENT file.' }
  [IO.File]::WriteAllText((Join-Path $fixture 'CURRENT.txt'),'999.0.0')
  if ((Get-UabsForgeRuntimeVersion $fixture) -ne '6.3.1') { throw 'Source bookkeeping overrode the runtime marker.' }
  if ((Get-UabsForgeRuntimeVersion '') -ne '0.0.0') { throw 'Absent owner sentinel changed.' }
  foreach ($bad in @('Other Product 6.3.1','Skyrim Forge invalid')) {
    [IO.File]::WriteAllText((Join-Path $fixture 'VERSION.txt'),$bad)
    $rejected=$false
    try { Get-UabsForgeRuntimeVersion $fixture | Out-Null } catch { $rejected=$true }
    if (-not $rejected) { throw 'Invalid product/version was accepted.' }
  }
  $code=[IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-AIO.ps1'))
  if ($code -match "Join-Path [^\r\n]+ 'CURRENT.txt'") { throw 'Installer still consumes developer CURRENT.txt.' }
  Write-Host 'FORGE RUNTIME VERSION GATE: PASS'
} finally {
  $resolved=[IO.Path]::GetFullPath($fixture)
  if ((Split-Path -Parent $resolved).TrimEnd('\') -ne ([IO.Path]::GetTempPath()).TrimEnd('\') -or (Split-Path -Leaf $resolved) -notmatch '^uabs-forge-version-[a-f0-9]{32}$') { throw 'Unsafe fixture cleanup.' }
  if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
