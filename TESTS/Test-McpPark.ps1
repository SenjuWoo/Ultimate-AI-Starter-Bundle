# Exercise Set-McpProfile.ps1 -Park / -Unpark / -Auto against a disposable home, never the live configs.
# Proves: task-specific servers leave the machine-wide config, personal servers stay, nothing is
# printed that looks like a credential, the saved copy restores byte-for-byte per project, and
# markers (not guesses) decide where a parked server comes back.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$script = Join-Path $PackRoot 'TOOLS\Set-McpProfile.ps1'
$ps = (Get-Command powershell.exe -ErrorAction Stop).Source
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Bytes($Path) { [IO.File]::ReadAllText($Path) }
function Run-Mcp([string[]]$ArgList) {
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = (& $ps -NoProfile -ExecutionPolicy Bypass -File $script @ArgList -PackRoot $PackRoot 2>&1 | ForEach-Object { "$_" }) -join "`n" }
  finally { $ErrorActionPreference = $prev }
  if ($LASTEXITCODE -ne 0) { throw "Set-McpProfile exited $LASTEXITCODE`: $out" }
  return $out
}

$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-park-' + [guid]::NewGuid().ToString('N'))
$saved = @{}; foreach ($k in 'USERPROFILE', 'APPDATA', 'LOCALAPPDATA', 'UABS_KEEP_GLOBAL_MCP', 'UABS_GH_READY') { $saved[$k] = [Environment]::GetEnvironmentVariable($k) }
try {
  $fakeHome = Join-Path $fixture 'home'
  $env:USERPROFILE = $fakeHome; $env:APPDATA = Join-Path $fixture 'roaming'; $env:LOCALAPPDATA = Join-Path $fixture 'local'
  $env:UABS_KEEP_GLOBAL_MCP = ''; $env:UABS_GH_READY = '0'
  foreach ($d in @($fakeHome, (Join-Path $fakeHome '.codex'), $env:APPDATA, $env:LOCALAPPDATA)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
  $claudeJson = Join-Path $fakeHome '.claude.json'
  $codexToml = Join-Path $fakeHome '.codex\config.toml'
  $secret = 'FAKE-SECRET-TOKEN-123'

  [IO.File]::WriteAllText($claudeJson, @'
{
  "numStartups": 3,
  "mcpServers": {
    "context7": { "command": "npx", "args": ["-y", "@upstash/context7-mcp@4.4.4"] },
    "github": { "command": "C:\\x\\github-mcp-server.exe", "args": ["stdio", "--toolsets", "repos"] },
    "rimworldforge": { "type": "stdio", "command": "S:\\Apps\\RimWorld Tools\\RimWorldForge\\.venv\\Scripts\\python.exe", "args": ["S:\\Apps\\RimWorld Tools\\RimWorldForge\\mcp_server\\server.py"], "env": {} },
    "avatarforge": { "command": "Z:\\Apps\\AvatarForge\\python.exe", "args": ["Z:\\Apps\\AvatarForge\\run.py", "mcp"], "env": { "AVATARFORGE_MANAGED": "1" }, "type": "stdio" },
    "melty": { "type": "http", "url": "https://melty.gg/api/mcp", "headers": { "Authorization": "Bearer FAKE-SECRET-TOKEN-123" } },
    "my-docs": { "command": "node", "args": ["C:\\tools\\my-docs\\server.js"] }
  },
  "projects": { "C:\\other": { "mcpServers": { "x": { "command": "y" } } } }
}
'@)
  [IO.File]::WriteAllText($codexToml, @'
model = "x"

[mcp_servers.github]
command = "C:\\x\\github-mcp-server.exe"
args = ["stdio", "--toolsets", "repos"]
enabled = true

[mcp_servers.avatarforge]
command = "Z:\\Apps\\AvatarForge\\python.exe"
args = ["Z:\\Apps\\AvatarForge\\run.py", "mcp"]
env = { "AVATARFORGE_MANAGED" = "1" }

[mcp_servers.robloxforge]
command = "python"
args = ["S:\\Apps\\Roblox Tools\\RobloxForge\\mcp_server\\server.py"]
enabled = false
'@)
  $before = @{ claude = (Bytes $claudeJson); codex = (Bytes $codexToml) }

  # 1. A check changes nothing; the user's opt-out is honoured.
  $env:UABS_KEEP_GLOBAL_MCP = 'melty,avatarforge'
  $check = Run-Mcp @('-Park', '-CheckOnly', '-Providers', 'Claude,Codex')
  Assert ($check -match 'would park Claude/rimworldforge') 'check did not find the RimWorldForge entry'
  Assert ($check -notmatch 'melty' -and $check -notmatch 'avatarforge') 'UABS_KEEP_GLOBAL_MCP was ignored'
  Assert ((Bytes $claudeJson) -ceq $before.claude -and (Bytes $codexToml) -ceq $before.codex) '-Park -CheckOnly wrote to a config'
  $env:UABS_KEEP_GLOBAL_MCP = ''
  Assert ($check -notmatch 'GitHub MCP') 'the GitHub server was a leak although gh is not signed in'
  $env:UABS_GH_READY = '1'
  $signedIn = Run-Mcp @('-Park', '-CheckOnly', '-Providers', 'Claude,Codex')
  Assert ($signedIn -match 'would park Claude/github' -and $signedIn -match 'would park Codex/github') 'the GitHub server was not a leak although gh is signed in'
  $env:UABS_KEEP_GLOBAL_MCP = 'github'
  Assert ((Run-Mcp @('-Park', '-CheckOnly', '-Providers', 'Claude,Codex')) -notmatch 'GitHub MCP') 'UABS_KEEP_GLOBAL_MCP=github was ignored'
  $env:UABS_KEEP_GLOBAL_MCP = ''

  # 2. Park for real.
  $out = Run-Mcp @('-Park', '-Providers', 'Claude,Codex')
  Assert ($out -notmatch [regex]::Escape($secret)) 'a credential was printed'
  foreach ($line in @('parked Claude/rimworldforge', 'parked Claude/avatarforge', 'parked Claude/melty', 'parked Claude/github', 'parked Codex/avatarforge', 'parked Codex/github')) {
    Assert ($out -match [regex]::Escape($line)) "missing: $line"
  }
  $cj = (Bytes $claudeJson) | ConvertFrom-Json
  $global = @($cj.mcpServers.PSObject.Properties.Name)
  Assert (($global -join ',') -eq 'context7,my-docs') ("machine-wide Claude servers are now: " + ($global -join ','))
  Assert ($cj.projects.'C:\other'.mcpServers.x.command -eq 'y') 'an existing project entry changed'
  $toml = Bytes $codexToml
  Assert ($toml -notmatch 'mcp_servers\.avatarforge' -and $toml -notmatch 'mcp_servers\.github' -and $toml -match 'mcp_servers\.robloxforge') 'Codex entries were not parked/kept correctly'
  $store = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\parked-mcp.json'
  Assert ((Test-Path -LiteralPath $store -PathType Leaf) -and ((Bytes $store) -match [regex]::Escape($secret))) 'the saved copy is missing or lost the credential it must restore'

  # 3. Parking again is a no-op.
  $snap = @{ claude = (Bytes $claudeJson); codex = (Bytes $codexToml); store = (Bytes $store) }
  $again = Run-Mcp @('-Park', '-Providers', 'Claude,Codex')
  Assert ($again -match 'none: nothing task-specific') 'a second park found something to do'
  Assert ((Bytes $claudeJson) -ceq $snap.claude -and (Bytes $codexToml) -ceq $snap.codex -and (Bytes $store) -ceq $snap.store) 'a second park rewrote a file'

  # 4. Explicit unpark restores the exact entry for one project, once.
  $melty = Join-Path $fixture 'proj-melty'; New-Item -ItemType Directory -Force -Path $melty | Out-Null
  $on = Run-Mcp @('-Unpark', 'melty', '-Path', $melty, '-Providers', 'Claude,Codex')
  Assert ($on -notmatch [regex]::Escape($secret)) 'unpark printed a credential'
  $cj = (Bytes $claudeJson) | ConvertFrom-Json
  $entry = $cj.projects.PSObject.Properties | Where-Object { $_.Name -ieq $melty } | Select-Object -First 1
  Assert ($entry -and $entry.Value.mcpServers.melty.url -eq 'https://melty.gg/api/mcp' -and $entry.Value.mcpServers.melty.headers.Authorization -eq "Bearer $secret") 'melty was not restored exactly for the project'
  Assert (-not ($cj.mcpServers.PSObject.Properties.Name -contains 'melty')) 'unpark put melty back machine-wide'
  $twice = Run-Mcp @('-Unpark', 'melty', '-Path', $melty, '-Providers', 'Claude,Codex')
  Assert ($twice -match 'nothing to switch on') 'a second unpark wrote again'

  # 5. Markers decide: RimWorld and avatar projects get theirs, a plain folder gets nothing.
  $rim = Join-Path $fixture 'proj-rim'; New-Item -ItemType Directory -Force -Path (Join-Path $rim 'About') | Out-Null
  [IO.File]::WriteAllText((Join-Path $rim 'About\About.xml'), '<ModMetaData/>')
  $avatar = Join-Path $fixture 'proj-avatar'; New-Item -ItemType Directory -Force -Path $avatar | Out-Null
  [IO.File]::WriteAllText((Join-Path $avatar 'model.vrm'), 'x')
  $plain = Join-Path $fixture 'proj-plain'; New-Item -ItemType Directory -Force -Path $plain | Out-Null
  [void](Run-Mcp @('-Auto', '-Path', $rim, '-Providers', 'Claude,Codex'))
  [void](Run-Mcp @('-Auto', '-Path', $avatar, '-Providers', 'Claude,Codex'))
  [void](Run-Mcp @('-Auto', '-Path', $plain, '-Providers', 'Claude,Codex'))
  $cj = (Bytes $claudeJson) | ConvertFrom-Json
  function Project-Servers($Path) {
    $p = $cj.projects.PSObject.Properties | Where-Object { $_.Name -ieq $Path } | Select-Object -First 1
    if ($p -and $p.Value.mcpServers) { return @($p.Value.mcpServers.PSObject.Properties.Name) }
    return @()
  }
  Assert ((Project-Servers $rim) -contains 'rimworldforge' -and (Project-Servers $rim) -notcontains 'avatarforge') 'the RimWorld project did not get exactly RimWorldForge'
  Assert ((Project-Servers $avatar) -contains 'avatarforge' -and (Project-Servers $avatar) -notcontains 'rimworldforge') 'the avatar project did not get exactly AvatarForge'
  Assert ((Project-Servers $plain).Count -eq 0) 'a project with no markers got a parked server'
  $codexProject = Join-Path $avatar '.codex\config.toml'
  Assert ((Test-Path -LiteralPath $codexProject -PathType Leaf) -and (Bytes $codexProject) -match '\[mcp_servers\.avatarforge\]' -and (Bytes $codexProject) -match 'AVATARFORGE_MANAGED') 'Codex did not get its AvatarForge block in the project'
  Assert (-not (Test-Path -LiteralPath (Join-Path $plain '.codex\config.toml'))) 'a plain project got a Codex config'

  # 6. GitHub's server comes back per project through its profile, from the installed binary.
  $exeDir = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\github-mcp-server'
  New-Item -ItemType Directory -Force -Path $exeDir | Out-Null
  [IO.File]::WriteAllText((Join-Path $exeDir 'github-mcp-server.exe'), 'x')
  $ghProj = Join-Path $fixture 'proj-gh'; New-Item -ItemType Directory -Force -Path $ghProj | Out-Null
  [void](Run-Mcp @('-Enable', 'github', '-Path', $ghProj, '-Providers', 'Claude'))
  $cj = (Bytes $claudeJson) | ConvertFrom-Json
  Assert ((Project-Servers $ghProj) -contains 'github-mcp') 'the github profile did not register for the project'
  Assert (-not ($cj.mcpServers.PSObject.Properties.Name -contains 'github-mcp') -and -not ($cj.mcpServers.PSObject.Properties.Name -contains 'github')) 'the github profile wrote machine-wide'

  Write-Host 'MCP PARK GATE: PASS'
} finally {
  foreach ($k in $saved.Keys) { [Environment]::SetEnvironmentVariable($k, $saved[$k]) }
  if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
