<# Provider JSON with keys that differ only in case. ~/.claude.json records each
   project under the cwd spelling it saw, and Windows PowerShell's ConvertFrom-Json
   throws on that, which aborted the whole install (2026-10-10). #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
. (Join-Path $PackRoot 'TOOLS\UABS-Mcp-Write.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-json-case-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
try {
  $lower = 'Z:/Backup/Ai documentation/Pack'
  $upper = 'Z:/Backup/Ai Documentation/Pack'
  $nl = "`n"
  # Exactly what JSON.stringify(value, null, 2) writes, plus a trailing newline.
  $text = @(
    '{',
    '  "numStartups": 1760000000000,',
    '  "ratio": 0.5,',
    '  "neg": -3,',
    '  "flag": true,',
    '  "none": null,',
    ('  "note": "em ' + [char]0x2014 + ' dash, quote \" slash \\ line\nnext\u0001",'),
    '  "empty": {},',
    '  "list": [],',
    '  "mcpServers": {',
    '    "melty": {',
    '      "type": "http",',
    '      "url": "https://example.invalid/mcp"',
    '    },',
    '    "keep": {',
    '      "command": "C:\\Tools\\keep.exe",',
    '      "args": [',
    '        "serve",',
    '        "--port",',
    '        "8080"',
    '      ]',
    '    }',
    '  },',
    '  "projects": {',
    ('    "' + $lower + '": {'),
    '      "allowedTools": [],',
    '      "mcpServers": {}',
    '    },',
    ('    "' + $upper + '": {'),
    '      "allowedTools": [',
    '        "Bash"',
    '      ],',
    '      "mcpServers": {}',
    '    }',
    '  }',
    '}'
  ) -join $nl
  $text += $nl
  $path = Join-Path $fixture 'claude.json'
  [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($false)))

  $threw = $false
  try { $null = $text | ConvertFrom-Json } catch { $threw = $true }
  if ($PSVersionTable.PSEdition -ne 'Core') { Assert $threw 'Fixture no longer reproduces the ConvertFrom-Json duplicate-key failure.' }

  $doc = Read-UabsJsonDocument -Path $path
  Assert ($doc['projects'].ContainsKey($lower) -and $doc['projects'].ContainsKey($upper)) 'A case variant project key was lost.'
  Write-UabsJsonDocument -Path $path -Document $doc
  Assert ([IO.File]::ReadAllText($path) -ceq $text) ('Round trip changed bytes:' + $nl + [IO.File]::ReadAllText($path))

  Assert (Test-UabsServerDeclared -Path $path -Style json -Section mcpServers -Id 'melty') 'Declared check failed on a case-variant file.'
  Assert (-not (Test-UabsServerDeclared -Path $path -Style json -Section mcpServers -Id 'keep' -ProjectKey $upper)) 'Project scope leaked the global entry.'

  $keys = @(Get-UabsClaudeProjectKeys -ProjectPath 'Z:\Backup\Ai Documentation\Pack' -ConfigPath $path)
  Assert ($keys -ccontains $lower -and $keys -ccontains $upper) ('Project keys missed a spelling: ' + ($keys -join ' | '))

  $server = @{ id = 'probe'; command = 'probe.exe'; args = @('a') }
  $added = @(Add-UabsMcpJson -Path $path -Section 'mcpServers' -Servers @($server) -Provider 'Claude' -ProjectKey $lower -Scope 'project')
  Assert ($added -contains 'probe') 'Project-scoped add failed on a case-variant file.'
  $after = Read-UabsJsonDocument -Path $path
  Assert ($after['projects'][$lower]['mcpServers'].ContainsKey('probe') -and -not $after['projects'][$upper]['mcpServers'].ContainsKey('probe')) 'Add wrote the wrong spelling.'
  Assert (@($after['projects'][$upper]['allowedTools']) -join ',' -ceq 'Bash') 'Add damaged the sibling spelling.'
  Assert (@(Add-UabsMcpJson -Path $path -Section 'mcpServers' -Servers @($server) -Provider 'Claude' -ProjectKey $lower -Scope 'project' -Refresh).Count -eq 0) 'An identical refresh was reported as a change.'

  $removed = @(Remove-UabsMcpJson -Path $path -Section 'mcpServers' -Ids @('keep'))
  Assert ($removed -contains 'keep') 'Global remove failed on a case-variant file.'
  $final = Read-UabsJsonDocument -Path $path
  Assert ($final['mcpServers'].ContainsKey('melty') -and -not $final['mcpServers'].ContainsKey('keep')) 'Remove touched another server.'
  Assert ($final['note'] -ceq ('em ' + [char]0x2014 + ' dash, quote " slash \ line' + "`n" + 'next' + [char]1)) 'String escapes did not survive.'
  Assert ($final['numStartups'] -eq 1760000000000 -and $final['ratio'] -eq 0.5 -and $final['neg'] -eq -3) 'Numbers changed.'

  [IO.File]::WriteAllText($path, '{broken', (New-Object Text.UTF8Encoding($false)))
  $refused = $false
  try { $null = Remove-UabsMcpJson -Path $path -Section 'mcpServers' -Ids @('x') } catch { $refused = $true }
  Assert ($refused -and [IO.File]::ReadAllText($path) -ceq '{broken') 'A malformed config was overwritten.'
  Write-Host 'JSON CASE-KEY GATE: PASS'
} finally {
  if ((Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath()))) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
