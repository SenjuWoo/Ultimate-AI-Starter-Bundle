<# Exercise fallback retirement planning in memory; never read or write live profiles. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$path = Join-Path $PackRoot 'TOOLS\Migrate-HermesProfiles.ps1'
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
if ($errors.Count) { throw 'Hermes profile migrator does not parse.' }
# Load real planning code without executing the migrator's live-profile entry point.
foreach ($name in @('ConvertTo-UabsPlain', 'Copy-UabsValue', 'Get-UabsFallbackSignature',
    'Get-MoaMigrationPlan', 'Ensure-UabsProfilePrefs', 'Add-UabsPlan', 'Add-UabsLedger')) {
  $definition = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
  }, $true)
  if (-not $definition) { throw "Missing migrator function: $name" }
  . ([scriptblock]::Create($definition.Extent.Text))
}
$chains = $ast.Find({ param($node)
  $node -is [Management.Automation.Language.AssignmentStatementAst] -and
  $node.Left.Extent.Text -eq '$script:UabsSupersededChains'
}, $true)
if (-not $chains) { throw 'Missing legacy fallback chains.' }
. ([scriptblock]::Create($chains.Extent.Text))
$script:UabsModelAliases = @{}
$script:UabsRetiredModels = @()
$script:UabsDiscouragedPlugins = @()
$script:UabsSharedPlugins = @()
$script:Ledger = @{ kept = (New-Object 'System.Collections.Generic.List[string]'); untouched = (New-Object 'System.Collections.Generic.List[string]') }
$script:Plan = New-Object 'System.Collections.Generic.List[object]'
$script:Failures = New-Object 'System.Collections.Generic.List[string]'
$script:Checked = 0
function Get-UabsProfilePrefs { param($Profile) return $script:Fixture }
function Assert-FallbackOwnership($Chain, [bool]$Retire, [string]$Name) {
  $script:Fixture = @{ fallback = $Chain; aliases = @{}; plugins = @(); vision_chain = @(); compression = @{}; model = @{}; moa = @{}; moa_vendor_default = $false }
  $before = ConvertTo-Json -InputObject $Chain -Depth 20 -Compress
  $script:Plan.Clear()
  $script:Prefs = @{}
  Ensure-UabsProfilePrefs 'fixture'
  $writes = @($script:Plan | Where-Object { $_.Key -eq 'fallback_providers' })
  $planned = $script:Prefs.ContainsKey('fixture') -and $script:Prefs['fixture'].ContainsKey('fallback_providers')
  if (($writes.Count -ne [int]$Retire) -or ($planned -ne $Retire)) {
    $script:Failures.Add("$Name : expected retire=$Retire, planned $($writes.Count) fallback write(s)")
  } elseif ($Retire -and (@($writes[0].Value).Count -ne 0 -or @($script:Prefs['fixture']['fallback_providers']).Count -ne 0)) {
    $script:Failures.Add("$Name : retirement did not plan an empty chain")
  }
  if ($before -cne (ConvertTo-Json -InputObject $script:Fixture.fallback -Depth 20 -Compress)) {
    $script:Failures.Add("$Name : planning mutated the original chain")
  }
  $script:Checked++
}
# Literal historical model sequences, independent of the production allowlist.
foreach ($models in @(
    'dots-studio/dots-3-note-preview:free|openrouter/free',
    'dots-studio/dots-3-note-preview:free',
    'openrouter/free',
    'poolside/laguna-s-2.1:free|thinkingmachines/inkling:free|thinkingmachines/inkling-small:free|poolside/laguna-xs-2.1:free')) {
  $legacy = @($models.Split('|') | ForEach-Object { @{ provider = 'openrouter'; model = $_ } })
  Assert-FallbackOwnership $legacy $true "exact default $models"
  $custom = Copy-UabsValue $legacy
  $custom[0]['provider'] = 'custom-provider'
  Assert-FallbackOwnership $custom $false "different provider $models"
  $custom = Copy-UabsValue $legacy
  $custom[0]['base_url'] = 'https://custom.invalid/v1'
  Assert-FallbackOwnership $custom $false "extra option $models"
  $custom = Copy-UabsValue $legacy
  $custom[0]['count'] = 2
  Assert-FallbackOwnership $custom $false "count-named option $models"
  $custom = Copy-UabsValue $legacy
  $custom[0].Remove('provider')
  Assert-FallbackOwnership $custom $false "missing provider $models"
  Assert-FallbackOwnership @($models.Split('|')) $false "string entries $models"
  Assert-FallbackOwnership @($legacy + @($null)) $false "extra null entry $models"
}
Assert-FallbackOwnership @() $false 'empty chain'
Assert-FallbackOwnership @(@{ provider = 'openrouter'; model = 'dots-studio/dots-3-note-preview:free|openrouter/free' }) $false 'model delimiter collision'
Assert-FallbackOwnership @(@{ provider = 'openrouter'; model = 'OPENROUTER/FREE' }) $false 'different model case'
Assert-FallbackOwnership @(@{ provider = 'openrouter'; model = 'my/custom-model' }) $false 'custom model'
if ($script:Failures.Count) { throw ($script:Failures -join "`n") }
Write-Host "HERMES FALLBACK OWNERSHIP: PASS ($script:Checked cases)"
