# Launch-path checks inspect MCP entries, never unrelated config or credentials.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Mcp-Write.ps1')
. (Join-Path $PackRoot 'TOOLS\UABS-Mcp-Park.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-launch-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
    $missing = Join-Path $fixture 'missing server.mjs'
    $live = Join-Path $fixture 'live.py'
    [IO.File]::WriteAllText($live, '# fixture')
    $entry = [pscustomobject]@{
        Provider='fixture'; Id='demo'; Style='json'; Path='config'; Disabled=$false
        Definition=@{command=$live;args=@($missing);env=@{SECRET='never-print';PATH=(Join-Path $fixture 'env.exe')};headers=@{Authorization='never-print'}}
    }
    $issues = @(Get-UabsDeadMcpLaunchPaths -Entries @($entry))
    if ($issues.Count -ne 1 -or $issues[0].missing_path -ne $missing) { throw 'JSON launch script was not checked precisely' }
    if (($issues | ConvertTo-Json) -match 'never-print|env.exe') { throw 'Unrelated environment or headers leaked into diagnostics' }
    $entry.Disabled = $true
    if (@(Get-UabsDeadMcpLaunchPaths -Entries @($entry)).Count) { throw 'A disabled server was treated as an active failure' }
    $entry.Disabled = $false
    $entry.Style = 'toml'
    $entry | Add-Member NoteProperty Text "[mcp_servers.demo]`ncommand = 'python'`nargs = ['$missing']`n[mcp_servers.demo.env]`ncommand = '$(Join-Path $fixture 'env.exe')'`n"
    $issues = @(Get-UabsDeadMcpLaunchPaths -Entries @($entry))
    if ($issues.Count -ne 1 -or $issues[0].missing_path -ne $missing) { throw 'TOML launch fields or subtable isolation failed' }
    $yaml = Join-Path $fixture 'config.yaml'
    [IO.File]::WriteAllText($yaml, "mcp_servers:`n  demo:`n    command: python`n    args:`n      - '$missing'`n    env:`n      SECRET: never-print`n")
    $entries = @(Get-UabsHermesDefaultEntries -ConfigPath $yaml -Provider 'Hermes/test')
    $issues = @(Get-UabsDeadMcpLaunchPaths -Entries $entries)
    if ($issues.Count -ne 1 -or $issues[0].provider -ne 'Hermes/test') { throw 'Named Hermes profile was not checked' }
    $project = Join-Path $fixture 'project'
    New-Item -ItemType Directory -Path (Join-Path $project '.codex') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $project '.codex\config.toml'), $entry.Text)
    $entries = @(Get-UabsGlobalMcpEntries -Providers Codex -ProjectPath $project)
    if (@(Get-UabsDeadMcpLaunchPaths -Entries $entries).Count -ne 1) { throw 'Project-scoped MCP launch was not checked' }
    Write-Output 'MCP LAUNCH PATH GATE: PASS (JSON, TOML, YAML, project scope, disabled entries, secret exclusion)'
} finally {
    if (Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath())) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
