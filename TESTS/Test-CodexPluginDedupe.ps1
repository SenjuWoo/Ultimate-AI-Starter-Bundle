[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-plugin-dedupe-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Path $fixture -Force | Out-Null
  $cfg = Join-Path $fixture 'config.toml'
  $utf8 = New-Object Text.UTF8Encoding($false)
  $original = "model = 'personal-model'`n[hooks.state.personal]`ntrusted_hash = 'unchanged'`n[plugins.`"superpowers@openai-curated-remote`".ambient]`nenabled = true`n"
  [IO.File]::WriteAllText($cfg, $original, $utf8)
  $inventory = @{installed=@(
    @{pluginId='superpowers@superpowers-dev';enabled=$true;version='7.0.0'},
    @{pluginId='superpowers@openai-curated-remote';enabled=$true;version='6.4.2'}
  )}
  Assert (@(Repair-UabsCodexDuplicatePlugins -CodexHome $fixture -Inventory $inventory -CheckOnly).Count -eq 1) 'Duplicate installations were not diagnosed.'
  Assert ([IO.File]::ReadAllText($cfg) -ceq $original) 'Read-only duplicate check modified settings.'
  Repair-UabsCodexDuplicatePlugins -CodexHome $fixture -Inventory $inventory | Out-Null
  $after = [IO.File]::ReadAllText($cfg)
  Assert ($after.StartsWith($original) -and $after.Contains("[plugins.`"superpowers@openai-curated-remote`"]`nenabled = false")) 'Wrong plugin or nested ambient flag was changed.'
  $backups = @(Get-ChildItem -LiteralPath $fixture -Filter 'config.toml.bak-plugin-dedupe-*')
  Assert ($backups.Count -eq 1 -and [IO.File]::ReadAllText($backups[0].FullName) -ceq $original) 'Original config was not backed up exactly.'
  Repair-UabsCodexDuplicatePlugins -CodexHome $fixture -Inventory $inventory | Out-Null
  Assert ([IO.File]::ReadAllText($cfg) -ceq $after -and @(Get-ChildItem -LiteralPath $fixture -Filter 'config.toml.bak-plugin-dedupe-*').Count -eq 1) 'Repeat repair is not idempotent.'
  [IO.File]::WriteAllText($cfg, $original, $utf8)
  $inventory.installed[0].enabled = $false
  Repair-UabsCodexDuplicatePlugins -CodexHome $fixture -Inventory $inventory | Out-Null
  Assert ([IO.File]::ReadAllText($cfg) -ceq $original) 'A sole curated installation was disabled.'
  $inventory.installed[0].enabled = $true
  $script:testInventory = $inventory
  $script:expectedInventoryHome = $fixture
  $outerHome = $env:CODEX_HOME
  try {
    $env:CODEX_HOME = 'unrelated-parent-home'
    function Get-UabsCodexCli { [pscustomobject]@{Source='fixture-codex'} }
    function Get-UabsNativeOutput {
      param($Exe,$CmdArgs)
      Assert ($env:CODEX_HOME -ceq $script:expectedInventoryHome) 'Inventory queried the wrong Codex home.'
      $script:testInventory | ConvertTo-Json -Depth 6
    }
    Assert (@(Repair-UabsCodexDuplicatePlugins -CodexHome $fixture -CheckOnly).Count -eq 1) 'Redirected-home inventory was not used.'
    Assert ($env:CODEX_HOME -ceq 'unrelated-parent-home') 'Inventory lookup leaked CODEX_HOME into its caller.'
  } finally { $env:CODEX_HOME = $outerHome }
  Write-Host 'CODEX PLUGIN DEDUPE GATE: PASS'
} finally {
  if (Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath())) { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
}
