# Verify the actual updater cannot poison pinned offline bytes with a newer download.
param([string]$PackRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PackRoot 'TOOLS\Update-From-GitHub.ps1'), [ref]$null, [ref]$null)
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Copy-VerifiedOfflineSnapshot' }, $true)
. ([scriptblock]::Create($fn.Extent.Text))
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-offline-update-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture | Out-Null
try {
  $source = Join-Path $fixture 'candidate.zip'; $dest = Join-Path $fixture 'pinned.zip'; $manifest = Join-Path $fixture 'manifest.json'
  [IO.File]::WriteAllText($dest, 'known-good'); [IO.File]::WriteAllText($source, 'newer-data')
  $hash = (Get-FileHash $dest -Algorithm SHA256).Hash
  @{assets=@(@{file='pinned.zip';size=10;sha256=$hash})} | ConvertTo-Json -Depth 5 | Set-Content $manifest
  $refused = $false
  try { Copy-VerifiedOfflineSnapshot -Source $source -Destination $dest -Manifest $manifest } catch { $refused = $_.Exception.Message -match 'reviewed offline pin' }
  if (-not $refused -or [IO.File]::ReadAllText($dest) -cne 'known-good') { throw 'Candidate poisoned the offline snapshot.' }
  [IO.File]::WriteAllText($source, 'known-good')
  Copy-VerifiedOfflineSnapshot -Source $source -Destination $dest -Manifest $manifest
  if ((Get-FileHash $dest -Algorithm SHA256).Hash -ne $hash) { throw 'Matching snapshot did not round-trip.' }
  'OFFLINE UPDATE GATE: PASS'
} finally {
  if (-not ([IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase))) { throw 'Invalid fixture cleanup path' }
  Remove-Item -LiteralPath $fixture -Recurse -Force
}
