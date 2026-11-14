<# Antigravity plugin ownership and copy dedupe: isolated fixture homes only. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-antigravity-plugins-' + [guid]::NewGuid().ToString('N'))
try {
  $ag = Join-Path $fixture 'home\.gemini\config'
  $plugins = Join-Path $ag 'plugins'
  foreach ($id in @('superpowers', 'ponytail', 'staged-off')) {
    New-Item -ItemType Directory -Force -Path (Join-Path $plugins $id) | Out-Null
    [IO.File]::WriteAllText((Join-Path $plugins "$id\plugin.json"), ('{ "name": "' + $id + '" }'))
  }
  # ponytail's entry is its mode switch (off here), superpowers is enabled,
  # staged-off is staged but disabled, listed-only has an entry but no folder.
  $cfg = '{"plugins":{"superpowers":{"enabled":true},"ponytail":{"enabled":false},"staged-off":{"enabled":false},"listed-only":{"enabled":true}}}'
  [IO.File]::WriteAllText((Join-Path $ag 'config.json'), $cfg)
  $ids = @(Get-UabsAntigravityNativePluginIds -AgHome $ag -PluginIds @('superpowers', 'ponytail', 'staged-off', 'listed-only'))
  Assert (($ids -join ',') -eq 'superpowers,ponytail') ('Wrong delivered plugin set: ' + ($ids -join ','))
  Assert (@(Get-UabsAntigravityNativePluginIds -AgHome (Join-Path $fixture 'absent')).Count -eq 0) 'A missing home reported delivered plugins.'

  # The real dedupe helper against the shipped Antigravity tree: an exact copy
  # moves to a backup, a modified copy stays.
  $expected = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\Antigravity\COPY-TO-SKILLS-DIRECTORY\skills'
  $skills = Join-Path $ag 'skills'
  New-Item -ItemType Directory -Force -Path $skills | Out-Null
  Copy-Item -LiteralPath (Join-Path $expected 'brainstorming') -Destination (Join-Path $skills 'brainstorming') -Recurse
  Copy-Item -LiteralPath (Join-Path $expected 'writing-plans') -Destination (Join-Path $skills 'writing-plans') -Recurse
  Add-Content -LiteralPath (Join-Path $skills 'writing-plans\SKILL.md') -Value 'my own note'
  $backup = Join-Path $fixture 'backups'
  $res = Remove-UabsPluginOwnedSkillCopies -Provider 'Antigravity' -SkillsDir $skills -Names @('brainstorming', 'writing-plans') `
           -ExpectedRoot $expected -BackupRoot $backup -Log $null
  Assert (-not (Test-Path -LiteralPath (Join-Path $skills 'brainstorming'))) 'The exact plugin-owned copy was not removed.'
  Assert (@(Get-ChildItem -LiteralPath $backup -Recurse -Filter 'SKILL.md').Count -eq 1) 'The removed copy has no backup.'
  Assert ((Test-Path -LiteralPath (Join-Path $skills 'writing-plans\SKILL.md')) -and (@($res.skipped_modified) -contains 'writing-plans')) 'A modified copy was removed.'
  'ANTIGRAVITY PLUGIN DEDUPE GATE: PASS'
} finally {
  Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
