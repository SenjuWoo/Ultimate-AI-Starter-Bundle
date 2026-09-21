$ErrorActionPreference = 'Stop'

$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { Join-Path $env:LOCALAPPDATA 'hermes' }
$ProfileName = 'sillytavern'
$ProfileDir = Join-Path $HermesHome ("profiles\" + $ProfileName)
$ConfigPath = Join-Path $ProfileDir 'config.yaml'

Write-Host 'LM Studio -> Hermes (sillytavern) -> SillyTavern' -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
  Write-Host '[ERROR] SillyTavern profile is missing. Run TOOLS\Install-SillyTavernGateway.ps1 from the pack.' -ForegroundColor Red
  exit 1
}

try {
  $models = Invoke-RestMethod -Uri 'http://127.0.0.1:1234/v1/models' -Method Get -TimeoutSec 5
} catch {
  Write-Host '[ERROR] Start LM Studio and turn on the developer server, then load a chat model.' -ForegroundColor Red
  exit 1
}
$loaded = @($models.data | Where-Object { $_.id }) | Select-Object -First 1
if (-not $loaded) {
  Write-Host '[ERROR] LM Studio is up but no model is loaded.' -ForegroundColor Red
  exit 1
}
$modelId = [string]$loaded.id

$text = [IO.File]::ReadAllText($ConfigPath)
$pattern = '(?m)^([ \t]*# gateway-model:.*\r?\n[ \t]*default:\s*).*$'
$safeId = $modelId.Replace('$', '$$')
$updated = [regex]::Replace($text, $pattern, ('${1}' + $safeId), 1)
if ($updated -eq $text) {
  Write-Host '[ERROR] Profile config has no gateway-model line. Re-run Install-SillyTavernGateway.ps1 -Force.' -ForegroundColor Red
  exit 1
}
$utf8 = New-Object System.Text.UTF8Encoding($false)
[IO.File]::WriteAllText($ConfigPath, $updated, $utf8)
Write-Host ("[OK] LM Studio model: " + $modelId) -ForegroundColor Green

$envFile = Join-Path $ProfileDir '.env'
$envText = ''
if (Test-Path -LiteralPath $envFile -PathType Leaf) { $envText = [IO.File]::ReadAllText($envFile) }
$keySet = $envText -match '(?m)^API_SERVER_KEY=\S+'
if (-not $keySet) {
  Write-Host '[ERROR] API_SERVER_KEY is unset in the profile .env. SillyTavern cannot authenticate.' -ForegroundColor Red
  exit 1
}
if ($envText -notmatch '(?m)^OPENROUTER_API_KEY=\S+') {
  Write-Host '[WARN] OPENROUTER_API_KEY is unset. Chat still uses LM Studio. Image analysis needs that key or a vision model.' -ForegroundColor Yellow
}

$hermes = $null
$cmd = Get-Command hermes -ErrorAction SilentlyContinue
if ($cmd) { $hermes = $cmd.Source }
if (-not $hermes) {
  foreach ($candidate in @(
      (Join-Path $HermesHome 'bin\hermes.exe'),
      (Join-Path $HermesHome 'hermes-agent\venv\Scripts\hermes.exe')
    )) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $hermes = $candidate; break }
  }
}
if (-not $hermes) {
  Write-Host '[ERROR] hermes.exe was not found on PATH or under the Hermes home.' -ForegroundColor Red
  exit 1
}

Write-Host '[START] SillyTavern base URL: http://127.0.0.1:8642/v1' -ForegroundColor Yellow
Write-Host '[START] Model name: the API_SERVER_MODEL_NAME in your Hermes .env' -ForegroundColor Yellow
Set-Location -LiteralPath $ProfileDir
& $hermes -p $ProfileName gateway
exit $LASTEXITCODE
