<#
Deterministic discovery checks against executable stubs. No real app is claimed
verified: these fixtures prove state classification, not an integration.
#>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$script = Join-Path $PackRoot '_CANONICAL-SKILLS\tool-discovery\scripts\discover_tools.ps1'
$fail = 0
function Check([bool]$Condition, [string]$Name) {
  if ($Condition) { Write-Host "ok   $Name" } else { Write-Host "FAIL $Name" -ForegroundColor Red; $script:fail++ }
}
$fx = Join-Path ([IO.Path]::GetTempPath()) ('uabs-discovery-' + [guid]::NewGuid().ToString('N').Substring(0,8))
$bin = Join-Path $fx 'bin'; New-Item -ItemType Directory -Force -Path $bin | Out-Null

function New-Stub([string]$Name, [string]$Body) {
  [IO.File]::WriteAllText((Join-Path $bin ($Name + '.cmd')), "@echo off`r`n$Body`r`n", (New-Object Text.UTF8Encoding $false))
}

# Healthy executable, failing executable, an npx that must never install.
New-Stub 'python' 'echo Python 3.12.0
exit /b 0'
New-Stub 'git' 'exit /b 1'
New-Stub 'npx' 'if "%1"=="--no-install" ( exit /b 1 )
if "%1"=="install" ( echo INSTALL > "%~dp0installed.txt" & exit /b 0 )
exit /b 1'

$json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Json -Isolated -SearchDir $bin | Out-String | ConvertFrom-Json
Check ($json.tools.python.state -eq 'VERIFIED') 'answering executable is VERIFIED'
Check ($json.tools.python.status -eq 'FOUND') 'legacy status stays FOUND'
Check ($json.tools.git.state -eq 'INSTALLED') 'non-answering executable is INSTALLED, not VERIFIED'
Check ($json.tools.gh.state -eq 'MISSING') 'absent executable is MISSING'
Check ($json.tools.codeburn.state -eq 'MISSING') 'npx alone does not make codeburn available'
Check ($json.tools.codeburn.detail -match 'not installed') 'npx-without-codeburn says why'
Check (-not (Test-Path (Join-Path $bin 'installed.txt'))) 'discovery never ran an install'

$hubBin = Join-Path $fx 'hub'; New-Item -ItemType Directory -Force -Path $hubBin | Out-Null
[IO.File]::WriteAllText((Join-Path $hubBin 'cli-hub.cmd'), "@echo off`r`nif `"%1`"==`"--version`" ( echo cli-hub 0.4.1 & exit /b 0 )`r`nif `"%1`"==`"list`" ( echo   3D & echo     blender  3D via blender & echo    AI & echo     comfyui  workflows & exit /b 0 )`r`nexit /b 1`r`n", (New-Object Text.UTF8Encoding $false))
$json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Json -Isolated -SearchDir $hubBin | Out-String | ConvertFrom-Json
Check ($json.tools.'cli-hub'.state -eq 'VERIFIED') 'functional CLI Hub is VERIFIED'
Check ($json.tools.'cli-hub'.detail -match 'harnesses') 'harness count is reported'

$json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Json -Isolated -SearchDir (Join-Path $fx 'empty') | Out-String | ConvertFrom-Json
Check ($json.tools.'cli-hub'.state -eq 'MISSING') 'absent CLI Hub is MISSING'

$checkout = Join-Path $fx 'CLI-Anything-main'; New-Item -ItemType Directory -Force -Path (Join-Path $checkout 'cli_hub') | Out-Null
$json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Json -Isolated -SearchDir (Join-Path $fx 'empty') -ToolRoots @($checkout) | Out-String | ConvertFrom-Json
Check ($json.tools.'cli-anything-source'.state -eq 'DISCOVERED') 'source checkout is DISCOVERED, not installed'

$cfg = Join-Path $fx 'hermes.json'
'{"mcp_servers":{"context7":{"enabled":true},"blender":{"enabled":false}}}' | Set-Content -LiteralPath $cfg -Encoding UTF8
$json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Json -Isolated -SearchDir (Join-Path $fx 'empty') -HermesConfig $cfg | Out-String | ConvertFrom-Json
Check ($json.tools.'mcp:context7'.state -eq 'CONFIGURED') 'an enabled MCP entry is CONFIGURED, not proven CALLABLE'
Check ($json.tools.'mcp:context7'.detail -match 'no tools/list probe') 'CONFIGURED says which probe is missing'
Check ($json.tools.'mcp:blender'.state -eq 'INSTALLED' -and $json.tools.'mcp:blender'.detail -match 'inactive') 'installed but inactive MCP is distinguished'

$cache = Join-Path $fx 'cache'
$first = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Json -Inventory -Refresh -Isolated -SearchDir $bin -CacheDir $cache | Out-String | ConvertFrom-Json
$second = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Json -Inventory -Isolated -SearchDir $bin -CacheDir $cache | Out-String | ConvertFrom-Json
Check ($first.meta.cached -eq $false) 'inventory is computed when forced'
Check ($second.meta.cached -eq $true) 'inventory is reused from cache'
Check (Test-Path (Join-Path $cache 'discovery-inventory.json')) 'cache file written in the requested directory'

$text = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script -Isolated -SearchDir $bin | Out-String
Check ($text -match 'VERIFIED' -and $text -match 'MISSING') 'text output stays readable'

Remove-Item -Recurse -Force $fx -ErrorAction SilentlyContinue
if ($fail) { throw "$fail tool-discovery check(s) failed" }
Write-Host 'TOOL DISCOVERY GATE: PASS'
