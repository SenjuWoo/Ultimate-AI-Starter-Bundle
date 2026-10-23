<# Exercise the doctor's actual private-runtime hook inspection against real,
   disposable provider files. The full doctor is never run and no user settings
   or persistent environment variables are changed. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$doctorPath = Join-Path $PackRoot 'TOOLS\Test-Installed-State.ps1'
$doctorSource = [IO.File]::ReadAllText($doctorPath)
$tokens = $null; $parseErrors = $null
$doctorAst = [Management.Automation.Language.Parser]::ParseInput($doctorSource, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'The installed-state doctor does not parse.' }
$start = $null; $end = $null
foreach ($statement in $doctorAst.EndBlock.Statements) {
  if ($statement -is [Management.Automation.Language.AssignmentStatementAst] -and
      $statement.Left.Extent.Text -eq '$gateHookFiles') { $start = $statement.Extent.StartOffset }
  if ($null -ne $start -and $statement -is [Management.Automation.Language.ForEachStatementAst] -and
      $statement.Variable.VariablePath.UserPath -eq 'f' -and $statement.Condition.Extent.Text -eq '$gateHookFiles') {
    $end = $statement.Extent.EndOffset
    break
  }
}
if ($null -eq $start -or $null -eq $end) { throw 'Cannot locate the actual doctor hook inspection block.' }
$inspection = [scriptblock]::Create('param([string[]]$Providers, $catalog)' + [Environment]::NewLine + $doctorSource.Substring($start, $end - $start))
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-doctor-scope-' + [guid]::NewGuid().ToString('N'))
$allProviders = @('Claude','Codex','Grok','Kimi','Hermes','Antigravity')
$homeVariables = @{
  Claude='CLAUDE_CONFIG_DIR'; Codex='CODEX_HOME'; Grok='GROK_HOME'
  Kimi='KIMI_CODE_HOME'; Hermes='HERMES_HOME'; Antigravity='ANTIGRAVITY_HOME'
}
$environmentNames = @('USERPROFILE','LOCALAPPDATA') + @($homeVariables.Values)
$savedEnvironment = @{}
foreach ($name in $environmentNames) { $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process') }
$snapshots = @{}
$failures = @()
$caseCount = 0
function Err([string]$Message) { $script:hookErrors += $Message }
function Invoke-ScopeCase([string]$Name, [string[]]$Selected, [string[]]$ExpectedFiles, $Catalog) {
  $script:hookErrors = @()
  & $inspection -Providers $Selected -catalog $Catalog
  $script:caseCount++
  if ($script:hookErrors.Count -ne $ExpectedFiles.Count) {
    $script:failures += ($Name + ': expected ' + $ExpectedFiles.Count + ' selected hook errors, got ' + $script:hookErrors.Count)
    return
  }
  foreach ($expected in $ExpectedFiles) {
    if (-not @($script:hookErrors | Where-Object { $_.Contains('Bundle hooks in ' + $expected + ' run on ') }).Count) {
      $script:failures += ($Name + ': actual selected hook path was not inspected: ' + $expected)
    }
  }
}

try {
  $env:USERPROFILE = Join-Path $fixture 'profile'
  $env:LOCALAPPDATA = Join-Path $fixture 'local'
  $defaultHomes = @{
    Claude=(Join-Path $env:USERPROFILE '.claude'); Codex=(Join-Path $env:USERPROFILE '.codex')
    Grok=(Join-Path $env:USERPROFILE '.grok'); Kimi=(Join-Path $env:USERPROFILE '.kimi-code')
    Hermes=(Join-Path $env:LOCALAPPDATA 'hermes'); Antigravity=(Join-Path $env:USERPROFILE '.gemini\config')
  }
  $catalog = [pscustomobject]@{ providers = [pscustomobject]@{} }
  foreach ($provider in $allProviders) {
    $catalog.providers | Add-Member -MemberType NoteProperty -Name $provider -Value ([pscustomobject]@{
      home_env=$homeVariables[$provider]; home_default=$defaultHomes[$provider]
    })
  }
  foreach ($mode in @('default','custom')) {
    $hookFiles = @{}
    foreach ($provider in $allProviders) {
      $providerRoot = if ($mode -eq 'default') { $defaultHomes[$provider] } else { Join-Path $fixture ('custom homes [preserve]\' + $provider) }
      [Environment]::SetEnvironmentVariable($homeVariables[$provider], $providerRoot, 'Process')
      $relative = switch ($provider) {
        'Claude' { 'settings.json' } 'Grok' { 'hooks\ultimate-bundle.json' } 'Hermes' { 'config.yaml' }
      }
      if (-not $relative) { continue }
      $path = Join-Path $providerRoot $relative
      New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
      $content = '# existing hook: C:\fixture\.cache\codex-runtimes\private\python.exe C:\fixture\completeness_gate.py'
      [IO.File]::WriteAllText($path, $content)
      $snapshots[$path] = $content
      $hookFiles[$provider] = $path
    }
    # Every subset, including each of the six single-provider selections and
    # the empty selection. Default files remain as traps during custom-home cases.
    for ($mask = 0; $mask -lt 64; $mask++) {
      $selected = @(); $expected = @()
      for ($bit = 0; $bit -lt $allProviders.Count; $bit++) {
        if ($mask -band (1 -shl $bit)) {
          $provider = $allProviders[$bit]
          $selected += $provider
          if ($hookFiles.ContainsKey($provider)) { $expected += $hookFiles[$provider] }
        }
      }
      Invoke-ScopeCase -Name ($mode + ' selection ' + $mask) -Selected $selected -ExpectedFiles $expected -Catalog $catalog
    }
  }
  # Selected custom homes can be healthy even when default homes contain old,
  # broken private-runtime hooks. Inspection is read-only in both cases.
  foreach ($provider in @('Claude','Grok','Hermes')) {
    $path = $hookFiles[$provider]
    $clean = '# existing hook: C:\SharedPython\python.exe C:\fixture\completeness_gate.py'
    [IO.File]::WriteAllText($path, $clean)
    $snapshots[$path] = $clean
  }
  Invoke-ScopeCase -Name 'healthy selected custom homes ignore broken defaults' -Selected $allProviders -ExpectedFiles @() -Catalog $catalog
  foreach ($path in $snapshots.Keys) {
    if ([IO.File]::ReadAllText($path) -cne $snapshots[$path]) { throw ('Doctor modified a provider hook file: ' + $path) }
  }
} finally {
  foreach ($name in $environmentNames) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name], 'Process') }
  $resolvedFixture = [IO.Path]::GetFullPath($fixture)
  $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
  if (-not $resolvedFixture.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe fixture cleanup target.' }
  if (Test-Path -LiteralPath $resolvedFixture) { Remove-Item -LiteralPath $resolvedFixture -Recurse -Force }
}
if ($failures.Count) {
  throw ('DOCTOR PROVIDER SCOPE GATE: FAIL (' + $failures.Count + '/' + $caseCount + ')' + [Environment]::NewLine + (($failures | Select-Object -First 8) -join [Environment]::NewLine))
}
Write-Host ('DOCTOR PROVIDER SCOPE GATE: PASS (' + $caseCount + ' cases)') -ForegroundColor Green
