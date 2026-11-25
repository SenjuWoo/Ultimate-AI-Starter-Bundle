<# The Claude agent-team routing block (Update-UabsClaudeAgentTeam) must land
   once, after the profile and before the preamble, be replaced where it stands,
   drop a second copy, leave unchanged files byte-identical and come out cleanly.
   Scratch files only; no provider home is touched. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Blocks($Path) { ([regex]::Matches([IO.File]::ReadAllText($Path), '<!-- agent-team:start -->')).Count }
$work = Join-Path ([IO.Path]::GetTempPath()) ('uabs-agent-team-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force $work | Out-Null
try {
  $team = [IO.File]::ReadAllText((Join-Path $PackRoot 'BUNDLED-TOOLS\claude-team\AGENT-TEAM.md'))
  $crlf = "`r`n"
  $layout = '<!-- UABS-PROFILE -->' + $crlf + 'profile' + $crlf + '<!-- /UABS-PROFILE -->' + $crlf + $crlf +
            'user text' + $crlf + $crlf + '<!-- UABS-PREAMBLE -->' + $crlf + 'soul' + $crlf + '<!-- /UABS-PREAMBLE -->' + $crlf
  $cases = @{
    'profile-and-preamble' = $layout
    'preamble-only'        = 'A' + $crlf + $crlf + '<!-- UABS-PREAMBLE -->' + $crlf + 'P' + $crlf + '<!-- /UABS-PREAMBLE -->' + $crlf
    'agreements'           = "x`n<!-- personal-working-agreements:start -->`ny`n<!-- personal-working-agreements:end -->`n`nz`n"
    'empty'                = ''
  }
  foreach ($name in $cases.Keys) {
    $p = Join-Path $work ($name + '.md')
    [IO.File]::WriteAllText($p, $cases[$name])
    Assert (Update-UabsClaudeAgentTeam -Path $p -Text $team) "${name}: block not written"
    $once = [IO.File]::ReadAllText($p)
    Assert (-not (Update-UabsClaudeAgentTeam -Path $p -Text $team)) "${name}: a second run rewrote the file"
    Assert ([IO.File]::ReadAllText($p) -ceq $once) "${name}: a second run changed bytes"
    Assert ((Blocks $p) -eq 1) "${name}: expected one block"
  }
  $p = Join-Path $work 'profile-and-preamble.md'
  $text = [IO.File]::ReadAllText($p)
  Assert ($text.IndexOf('<!-- /UABS-PROFILE -->') -lt $text.IndexOf('<!-- agent-team:start -->')) 'block landed before the profile'
  Assert ($text.IndexOf('<!-- agent-team:end -->') -lt $text.IndexOf('<!-- UABS-PREAMBLE -->')) 'block landed after the preamble'
  Assert (-not $text.Contains("`r`n`n") -and -not ($text -replace "`r`n", '').Contains("`n")) 'CRLF file gained LF line endings'
  $p = Join-Path $work 'agreements.md'
  $text = [IO.File]::ReadAllText($p)
  Assert ($text.IndexOf('personal-working-agreements:end') -lt $text.IndexOf('agent-team:start')) 'block not placed after the working agreements'

  # Replaced in place, and a stale second copy is dropped.
  $p = Join-Path $work 'profile-and-preamble.md'
  $good = [IO.File]::ReadAllText($p)
  $stale = $good.Replace('## Agent team', '## Old agent team') + $crlf + '<!-- agent-team:start -->' + $crlf + 'older copy' + $crlf + '<!-- agent-team:end -->' + $crlf
  [IO.File]::WriteAllText($p, $stale)
  Assert (Update-UabsClaudeAgentTeam -Path $p -Text $team) 'stale block not refreshed'
  Assert ((Blocks $p) -eq 1) 'a duplicate block survived'
  Assert ([IO.File]::ReadAllText($p).TrimEnd() -ceq $good.TrimEnd()) 'refresh did not restore the managed layout'

  # Removal (-SkipClaudeAgents) restores the original text.
  $p = Join-Path $work 'preamble-only.md'
  Assert (Update-UabsClaudeAgentTeam -Path $p -Text '') 'block not removed'
  Assert ([IO.File]::ReadAllText($p) -ceq $cases['preamble-only']) 'removal did not restore the original bytes'
  Assert (-not (Update-UabsClaudeAgentTeam -Path $p -Text '')) 'removing an absent block rewrote the file'
  Write-Host 'CLAUDE AGENT TEAM: PASS'
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
