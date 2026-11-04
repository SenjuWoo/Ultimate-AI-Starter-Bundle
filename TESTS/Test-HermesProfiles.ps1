<# Exercise fallback retirement, MoA preset and delegation routing planning in memory; never read or write live profiles. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$path = Join-Path $PackRoot 'TOOLS\Migrate-HermesProfiles.ps1'
$errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
if ($errors.Count) { throw 'Hermes profile migrator does not parse.' }
# Load real planning code without executing the migrator's live-profile entry point.
foreach ($name in @('ConvertTo-UabsPlain', 'Copy-UabsValue', 'Get-UabsFallbackSignature', 'Get-MoaModelId',
    'Get-MoaMigrationPlan', 'Get-DelegationMigrationPlan', 'Ensure-UabsProfilePrefs', 'Add-UabsPlan', 'Add-UabsLedger')) {
  $definition = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name
  }, $true)
  if (-not $definition) { throw "Missing migrator function: $name" }
  . ([scriptblock]::Create($definition.Extent.Text))
}
foreach ($variable in @('$script:UabsSupersededChains', '$script:UabsRetiredMoaAggregators',
    '$script:UabsInheritedMoaReferences', '$script:UabsMoaReferenceModels',
    '$script:UabsMoaPresetName', '$script:UabsDelegationModelMap')) {
  $assignment = $ast.Find({ param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and
    $node.Left.Extent.Text -eq $variable
  }, $true)
  if (-not $assignment) { throw "Missing migrator constant: $variable" }
  . ([scriptblock]::Create($assignment.Extent.Text))
}
$script:UabsModelAliases = @{}
$script:UabsRetiredModels = @()
$script:UabsDiscouragedPlugins = @()
$script:UabsSharedPlugins = @()
$script:Ledger = @{ kept = (New-Object 'System.Collections.Generic.List[string]'); untouched = (New-Object 'System.Collections.Generic.List[string]'); migrated = (New-Object 'System.Collections.Generic.List[string]') }
$script:Plan = New-Object 'System.Collections.Generic.List[object]'
$script:Failures = New-Object 'System.Collections.Generic.List[string]'
$script:Checked = 0
function Get-UabsProfilePrefs { param($Profile) return $script:Fixture }
function Assert-FallbackOwnership($Chain, [bool]$Retire, [string]$Name) {
  $script:Fixture = @{ fallback = $Chain; aliases = @{}; plugins = @(); vision_chain = @(); compression = @{}; model = @{}; delegation = @{}; moa = @{}; moa_vendor_default = $false }
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
# ---- MoA: on-demand preset, never a permanent multi-model main ----
function Assert-MoaPlan($Moa, [bool]$VendorDefault, [bool]$ExpectPlan, [string]$Name) {
  $plan = Get-MoaMigrationPlan -Moa $Moa -IsVendorDefault $VendorDefault -MainProvider 'openrouter' -MainModel 'particle-ai/particle-1'
  if ($ExpectPlan) {
    if (-not $plan) { $script:Failures.Add("$Name : expected a MoA plan"); $script:Checked++; return }
    $preset = $plan['preset']
    if (-not $plan['enabled'] -or $plan['default_preset'] -ne 'deepseek_particle') {
      $script:Failures.Add("$Name : preset is not enabled on demand")
    }
    if ($preset['fanout'] -ne 'user_turn') { $script:Failures.Add("$Name : fanout is not user_turn") }
    $refs = @($preset['reference_models'])
    if ($refs.Count -ne 1) { $script:Failures.Add("$Name : expected exactly one reference") }
    elseif ($refs[0]['model'] -ne 'deepseek/deepseek-v4.1-flash-1017') {
      $script:Failures.Add("$Name : reference is not DeepSeek V4.1 Flash")
    }
    if ($preset['aggregator']['model'] -ne 'particle-ai/particle-1') {
      $script:Failures.Add("$Name : aggregator is not Particle-1")
    }
    if ($preset['aggregator']['reasoning_effort'] -ne 'high' -or ($refs.Count -and $refs[0]['reasoning_effort'] -ne 'high')) {
      $script:Failures.Add("$Name : expected high reasoning on both slots")
    }
  } elseif ($plan) {
    $script:Failures.Add("$Name : a user MoA block was migrated")
  }
  $script:Checked++
}
$vendorMoa = @{ presets = @{ default = @{
  aggregator = @{ provider = 'anthropic'; model = 'anthropic/claude-opus-4.8' }
  reference_models = @(@{ provider = 'openai'; model = 'gpt-5.5'; enabled = $true })
} } }
Assert-MoaPlan $vendorMoa $true $true 'vendor MoA default'
Assert-MoaPlan $vendorMoa $false $false 'vendor block without fingerprint'
Assert-MoaPlan @{ presets = @{ default = @{ aggregator = @{ provider = 'openrouter'; model = 'particle-ai/particle-1' } } } } $true $false 'owner aggregator'
Assert-MoaPlan @{ aggregator = @{ provider = 'anthropic'; model = 'claude-opus-4.8' }; reference_models = @(@{ provider = 'openrouter'; model = 'my/advisor' }) } $true $false 'owner advisor'
Assert-MoaPlan $null $true $false 'missing MoA block'

# ---- Delegation: two routes on an untouched backend, user choices kept ----
function Assert-DelegationPlan($Delegation, [bool]$ExpectPlan, [string]$Name) {
  $plan = Get-DelegationMigrationPlan -Delegation $Delegation
  if ($ExpectPlan) {
    if (-not $plan) { $script:Failures.Add("$Name : expected a delegation plan"); $script:Checked++; return }
    if ($plan['backend'] -ne 'model_map') { $script:Failures.Add("$Name : backend is not model_map") }
    $map = $plan['model_map']
    $options = @($map['options'])
    $names = @($options | ForEach-Object { $_['name'] })
    if (($names -join ',') -ne 'execute,research') { $script:Failures.Add("$Name : routes are $($names -join ',')") }
    $execute = @($options | Where-Object { $_['name'] -eq 'execute' })
    $research = @($options | Where-Object { $_['name'] -eq 'research' })
    if ($execute.Count -eq 1 -and ($execute[0]['model'] -ne 'particle-ai/particle-1' -or $execute[0]['reasoning_effort'] -ne 'medium')) {
      $script:Failures.Add("$Name : execute route is wrong")
    }
    if ($research.Count -eq 1 -and ($research[0]['model'] -ne 'deepseek/deepseek-v4.1-flash-1017' -or $research[0]['reasoning_effort'] -ne 'high')) {
      $script:Failures.Add("$Name : research route is wrong")
    }
    if ($map['default'] -ne 'execute') { $script:Failures.Add("$Name : default route is not execute") }
    if ($plan['max_concurrent_children'] -ne 2) { $script:Failures.Add("$Name : concurrency is not 2") }
  } elseif ($plan) {
    $script:Failures.Add("$Name : a user delegation block was migrated")
  }
  $script:Checked++
}
Assert-DelegationPlan @{} $true 'empty delegation'
Assert-DelegationPlan $null $true 'missing delegation'
Assert-DelegationPlan @{ backend = 'default'; provider = 'auto' } $true 'built-in backend'
Assert-DelegationPlan @{ backend = 'model_map'; backends = @{ model_map = @{ options = @(@{ name = 'execute'; model = 'my/model' }); default = 'execute' } } } $false 'owner model map'
Assert-DelegationPlan @{ backend = 'profile_routes'; backends = @{ profile_routes = @{ profiles = @{}; default = 'code' } } } $false 'owner profile routes'
Assert-DelegationPlan @{ backend = 'my-plugin' } $false 'owner plugin backend'

# ---- Whole-profile planning adds routes without touching the main model ----
$script:Fixture = @{ fallback = @(); aliases = @{}; plugins = @(); vision_chain = @(); compression = @{};
  model = @{ provider = 'openrouter'; default = 'deepseek/deepseek-v4-pro-0813' };
  delegation = @{}; moa = @{}; moa_vendor_default = $false }
$script:Plan.Clear(); $script:Prefs = @{}
Ensure-UabsProfilePrefs 'fixture'
$wanted = $script:Prefs['fixture']
if (-not $wanted -or -not $wanted.ContainsKey('delegation')) { $script:Failures.Add('profile: delegation route was not planned') }
if ($script:Fixture.model['default'] -ne 'deepseek/deepseek-v4-pro-0813') {
  $script:Failures.Add('profile: planning mutated the main model')
}
$script:Checked++

if ($script:Failures.Count) { throw ($script:Failures -join "`n") }
Write-Host "HERMES PROFILE PLANNING: PASS ($script:Checked cases)"
