param([string]$PackRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('uabs-gateway-test-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$ps = (Get-Command powershell.exe -ErrorAction Stop).Source
$failures = 0
$originalHermesHome = $env:HERMES_HOME
function Check([bool]$Condition, [string]$Name) {
  if ($Condition) { Write-Host ('PASS ' + $Name) }
  else { $script:failures++; Write-Host ('FAIL ' + $Name) }
}
function Run([string]$Code) {
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code))
  $ErrorActionPreference = 'Continue'
  $output = & $ps -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1
  return @{ Code = $LASTEXITCODE; Output = ($output | Out-String) }
}
try {
  $installer = Join-Path $PackRoot 'TOOLS/Install-SillyTavernGateway.ps1'
  $fixture = Join-Path $scratch 'home with spaces'
  New-Item -ItemType Directory -Path $fixture | Out-Null
  $prefix = "Set-Location -LiteralPath '$($PackRoot.Replace("'", "''"))/TOOLS'; "
  # Windows PowerShell parses -Force. as the switch plus a positional dot.
  # It must fail at binding, not redirect PackRoot and begin an installation.
  $r = Run ($prefix + "& '$installer' -Force. -HermesHome '$fixture'")
  Check ($r.Code -ne 0 -and -not (Test-Path (Join-Path $fixture 'profiles'))) 'trailing-dot typo fails before writing'
  $r = Run ($prefix + "& '$installer' -HermesHome '$fixture'")
  $config = Join-Path $fixture 'profiles/sillytavern/config.yaml'
  Check ($r.Code -eq 0 -and (Test-Path $config)) 'default root resolves from TOOLS in Windows PowerShell'
  [IO.File]::WriteAllText($config, "# personal tuning`r`nmodel: custom`r`n")
  $before = [IO.File]::ReadAllText($config)
  $r = Run ($prefix + "& '$installer' -HermesHome '$fixture'")
  Check ($r.Code -eq 0 -and [IO.File]::ReadAllText($config) -ceq $before) 'normal reinstall preserves config'
  $r = Run ($prefix + "& '$installer' -HermesHome '$fixture' -Force")
  $backups = @(Get-ChildItem -LiteralPath (Split-Path $config) -Filter 'config.yaml.bak-*')
  Check ($r.Code -eq 0 -and @($backups | Where-Object { [IO.File]::ReadAllText($_.FullName) -ceq $before }).Count -ge 1) 'forced reset backs up original config'

  # Only external boundaries are stubbed: no GPU, credentials, or real gateway.
  $env:HERMES_HOME = $fixture
  $fake = Join-Path $scratch 'hermes.cmd'
  [IO.File]::WriteAllText($fake, "@echo off`r`nif not `"%*`"==`"-p sillytavern gateway`" exit /b 9`r`nexit /b 7`r`n")
  [IO.File]::WriteAllText((Join-Path (Split-Path $config) '.env'), "API_SERVER_KEY=local-fixture-not-a-secret`n")
  $launcher = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES/Hermes/sillytavern-gateway/START-HERMES-GATEWAY.ps1'
  $model = '{"id":"chat-model","type":"llm","state":"loaded"}'
  foreach ($case in @('same', 'same-lf', 'changed', 'special', 'unloaded', 'embedding', 'multiple', 'missing-marker', 'offline')) {
    $initial = if ($case -eq 'changed') { 'old-model' } else { 'chat-model' }
    $text = "model:`r`n  # gateway-model: managed model`r`n  default: $initial`r`n# personal tuning`r`n"
    if ($case -eq 'same-lf') { $text = $text.Replace("`r`n", "`n") }
    if ($case -eq 'missing-marker') { $text = "model:`r`n  default: chat-model`r`n" }
    [IO.File]::WriteAllText($config, $text)
    $models = switch ($case) {
      special { '{"data":[{"id":"demo$1: quoted","type":"llm","state":"loaded"}]}' }
      unloaded { '{"data":[{"id":"chat-model","type":"llm","state":"not-loaded"}]}' }
      embedding { '{"data":[{"id":"embedding","type":"embeddings","state":"loaded"}]}' }
      multiple { '{"data":[' + $model + ',{"id":"other-chat","type":"vlm","state":"loaded"}]}' }
      default { '{"data":[' + $model + ']}' }
    }
    $http = if ($case -eq 'offline') { 'throw "Connection refused"' } else { "return ('$models' | ConvertFrom-Json)" }
    $code = @"
function Invoke-RestMethod { param(`$Uri, `$Method, `$TimeoutSec); $http }
function Get-Command { param(`$Name, `$ErrorAction); if (`$Name -eq 'hermes') { return [pscustomobject]@{Source='$fake'} }; throw 'Unexpected command lookup' }
& '$launcher'
exit `$LASTEXITCODE
"@
    $r = Run $code
    $success = $case -in @('same', 'same-lf', 'changed', 'special')
    Check ($r.Code -eq $(if ($success) { 7 } else { 1 })) ($case + ': launch/stop and propagate child status')
    $after = [IO.File]::ReadAllText($config)
    if (-not $success -or $case -like 'same*') {
      Check ($after -ceq $text) ($case + ': preserve config bytes')
    } elseif ($case -eq 'special') {
      Check ($after.Contains('default: "demo$1: quoted"') -and $after.Contains('# personal tuning')) 'model IDs are quoted without regex substitution'
      $r = Run $code
      Check ($r.Code -eq 7 -and [IO.File]::ReadAllText($config) -ceq $after) 'quoted model restart is idempotent'
    } else {
      Check ($after -match 'default: chat-model' -and $after -match '# personal tuning') 'update model without losing tuning'
    }
  }
} finally {
  $env:HERMES_HOME = $originalHermesHome
  # Only remove the exact per-run fixture created above.
  Remove-Item -LiteralPath $scratch -Recurse -Force
}
if ($failures) { throw "$failures SillyTavern gateway checks failed" }
