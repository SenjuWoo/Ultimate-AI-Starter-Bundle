<# Real task plans and scoped registrations in a disposable provider home. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$router = Join-Path $PackRoot 'TOOLS\Set-McpProfile.ps1'
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('uabs task space-' + [char]0x00E9 + '-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($name in @('USERPROFILE','LOCALAPPDATA','APPDATA','HERMES_HOME','CODEBASE_MEMORY_MCP')) {
  $saved[$name] = [Environment]::GetEnvironmentVariable($name)
}
function Assert($ok, $message) { if (-not $ok) { throw $message } }
try {
  New-Item -ItemType Directory -Path $sandbox | Out-Null
  $env:USERPROFILE = $sandbox; $env:LOCALAPPDATA = $sandbox; $env:APPDATA = $sandbox
  $env:HERMES_HOME = Join-Path $sandbox 'hermes'
  $env:CODEBASE_MEMORY_MCP = Join-Path $sandbox 'missing.exe'
  $project = Join-Path $sandbox 'Game project'
  New-Item -ItemType Directory -Path $project | Out-Null
  $plan = (& $router -Task game-unity -Path $project -Plan | Out-String) | ConvertFrom-Json
  Assert ($plan.profiles -contains 'engine-unity') 'Unity task lost its editor profile'
  Assert ($plan.profiles -notcontains 'engine-blender') 'Unity task unnecessarily enables Blender'
  Assert ($plan.skills -contains 'universal-modder') 'Game task lost Universal Modder'
  Assert ($plan.hermes_profiles -contains 'unity') 'Hermes has no narrow Unity route'
  Assert (-not (Test-Path (Join-Path $project '.codex'))) 'Read-only plan wrote project config'
  $combined = (& $router -Task game-unity,assets-3d,publication -Path $project -Plan | Out-String) | ConvertFrom-Json
  Assert ($combined.profiles -contains 'engine-blender') '3D work failed to compose Blender'
  Assert ($combined.skills -contains 'release-checklist') 'Publication lost release verification'
  Assert (@($combined.skills | Select-Object -Unique).Count -eq @($combined.skills).Count) 'Composed skills duplicate'
  $unreal = (& $router -Task game-unreal -Path $project -Plan | Out-String) | ConvertFrom-Json
  Assert ($unreal.profiles -notcontains 'engine-unity' -and $unreal.profiles -notcontains 'engine-blender') 'Unreal enabled unrelated engines'
  Assert ($unreal.notes -match 'Unreal') 'Unreal route hides its actual integration limit'
  $rejected = $false
  try { & $router -Task nonexistent -Path $project -Plan | Out-Null } catch { $rejected = $true }
  Assert $rejected 'Unknown task silently accepted'
  # The real writer must scope to this project and leave personal defaults alone.
  $configDir = Join-Path $sandbox '.codex'
  New-Item -ItemType Directory -Path $configDir | Out-Null
  $personal = "model = `"personal`"`n"
  [IO.File]::WriteAllText((Join-Path $configDir 'config.toml'), $personal)
  & $router -Task desktop -Path $project -Providers Codex | Out-Null
  Assert (-not (Test-Path (Join-Path $project '.codex'))) 'Desktop task silently enabled a global server'
  Assert ([IO.File]::ReadAllText((Join-Path $configDir 'config.toml')) -ceq $personal) 'Desktop task changed global config without opt-in'
  & $router -Task web-ui -Path $project -Providers Codex | Out-Null
  $target = Join-Path $project '.codex\config.toml'
  $first = [IO.File]::ReadAllText($target)
  Assert ($first -match '@playwright/mcp@') 'Task did not register its chosen server'
  Assert ([IO.File]::ReadAllText((Join-Path $configDir 'config.toml')) -ceq $personal) 'Task changed personal global config'
  & $router -Task web-ui -Path $project -Providers Codex | Out-Null
  Assert ([IO.File]::ReadAllText($target) -ceq $first) 'Second task activation is not idempotent'
  $otherProject = Join-Path $sandbox 'Other project'
  New-Item -ItemType Directory -Path (Join-Path $otherProject '.codex') -Force | Out-Null
  $custom = "[mcp_servers.playwright-mcp]`ncommand = `"personal-browser.exe`"`nargs = []`nenabled = false`n"
  $otherTarget = Join-Path $otherProject '.codex\config.toml'
  [IO.File]::WriteAllText($otherTarget, $custom)
  & $router -Disable web -Path $otherProject -Providers Codex | Out-Null
  Assert ([IO.File]::ReadAllText($otherTarget) -ceq $custom) 'Ownership of another project deleted a personal server'
  [IO.File]::WriteAllText((Join-Path $configDir 'config.toml'), $personal + $custom)
  & $router -Disable web -Path $project -Providers Codex | Out-Null
  Assert ([IO.File]::ReadAllText($target) -notmatch '@playwright/mcp@') 'Scoped task cannot be disabled'
  Assert ([IO.File]::ReadAllText((Join-Path $configDir 'config.toml')) -ceq ($personal + $custom)) 'Project disable swept a personal global server'
  [IO.File]::WriteAllText($target, $custom)
  & $router -Task web-ui -Path $project -Providers Codex | Out-Null
  Assert ([IO.File]::ReadAllText($target) -ceq $custom) 'Task replaced a user-owned server or policy'
  & $router -Disable web -Path $project -Providers Codex | Out-Null
  Assert ([IO.File]::ReadAllText($target) -ceq $custom) 'Unowned personal server removed on disable'
  Write-Host 'TASK RECIPE GATE: PASS'
} finally {
  foreach ($name in $saved.Keys) {
    [Environment]::SetEnvironmentVariable($name, $saved[$name], 'Process')
  }
  # Exact GUID-owned temporary directory, never a provider home.
  if ([IO.Path]::GetFullPath($sandbox).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase)) {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
  }
}
