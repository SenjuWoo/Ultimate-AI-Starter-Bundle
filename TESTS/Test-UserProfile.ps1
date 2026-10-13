<#
.SYNOPSIS
  Personal profile: text assembly, size cap, block placement and removal, machine map.

.DESCRIPTION
  The profile rides on every request of every provider, so it must stay small,
  land in one marked place, refresh in place, and vanish completely when the
  user deletes it. Fixtures only; the real profile folder is never touched.
#>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$fx = Join-Path ([IO.Path]::GetTempPath()) ('uabs-profile-' + [guid]::NewGuid().ToString('N'))
try {
  $root = Join-Path $fx 'profile'
  New-Item -ItemType Directory -Force -Path $root | Out-Null
  Assert ((Get-UabsProfileText -Root $root) -eq '') 'An empty profile folder produced text.'
  [IO.File]::WriteAllText((Join-Path $root 'PROFILE.md'), "## Me`n- terse`n")
  [IO.File]::WriteAllText((Join-Path $root 'MACHINE-MAP.md'), "## Machine map`n- Steam: X`n")
  $text = Get-UabsProfileText -Root $root
  Assert ($text -match '## Me' -and $text -match '## Machine map' -and $text.IndexOf('## Me') -lt $text.IndexOf('## Machine')) 'Profile text is not PROFILE.md then MACHINE-MAP.md.'
  $threw = $false
  try { Get-UabsProfileText -Root $root -MaxChars 10 | Out-Null } catch { $threw = $_.Exception.Message -match 'cap' }
  Assert $threw 'An oversized profile was not refused.'
  Assert ((Get-UabsProfileRoot (Join-Path $fx 'x')) -eq [IO.Path]::GetFullPath((Join-Path $fx 'x'))) 'Explicit profile root ignored.'

  # Placement: after the last pack block; refresh in place; full removal.
  $file = Join-Path $fx 'home\CLAUDE.md'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
  $orig = "# Head`r`n`r`n<!-- UABS-PACK:skyrim -->`r`n## Skyrim pack`r`n<!-- /UABS-PACK:skyrim -->`r`n`r`nUser rules`r`n"
  [IO.File]::WriteAllText($file, $orig, (New-Object System.Text.UTF8Encoding $false))
  Assert (Update-UabsInstructionProfile -Path $file -Text $text) 'Profile block was not added.'
  $t1 = [IO.File]::ReadAllText($file)
  $iPack = $t1.IndexOf('<!-- /UABS-PACK:skyrim -->'); $iProf = $t1.IndexOf('<!-- UABS-PROFILE -->'); $iUser = $t1.IndexOf('User rules')
  Assert ($iPack -lt $iProf -and $iProf -lt $iUser) 'Profile block is not between the pack block and user text.'
  Assert ($t1 -notmatch '(?<!\r)\n') 'CRLF file was rewritten with LF.'
  Assert (-not (Update-UabsInstructionProfile -Path $file -Text $text)) 'An unchanged profile rewrote the file.'
  Assert (Update-UabsInstructionProfile -Path $file -Text "## Me`n- verbose") 'A changed profile was not refreshed.'
  $t2 = [IO.File]::ReadAllText($file)
  Assert (([regex]::Matches($t2, '<!-- UABS-PROFILE -->')).Count -eq 1 -and $t2 -match 'verbose' -and $t2 -notmatch 'terse') 'Refresh stacked or kept the old block.'
  Assert (Update-UabsInstructionProfile -Path $file -Text '') 'An emptied profile was not removed.'
  Assert ([IO.File]::ReadAllText($file) -ceq $orig) 'Removing the profile did not restore the original bytes.'
  Assert (-not (Update-UabsInstructionProfile -Path $file -Text '')) 'Removing an absent profile rewrote the file.'
  Assert (-not (Update-UabsInstructionProfile -Path (Join-Path $fx 'home\none.md') -Text '')) 'A missing file was created for an empty profile.'
  Assert (@(Get-ChildItem -LiteralPath (Split-Path -Parent $file) -Filter '*.before-profile-*.bak').Count -ge 1) 'No backup was kept.'

  # Mixed endings stay as they are; a second run is a no-op.
  $mixed = Join-Path $fx 'home\MIXED.md'
  [IO.File]::WriteAllText($mixed, "Head`r`n`r`nTail one`nTail two`n")
  [void](Update-UabsInstructionProfile -Path $mixed -Text 'P')
  Assert ([IO.File]::ReadAllText($mixed).Contains("Tail one`nTail two")) 'Profile writer rewrote LF text it does not own.'
  Assert (-not (Update-UabsInstructionProfile -Path $mixed -Text 'P')) 'Profile writer is not idempotent on a mixed-ending file.'

  # Plain file without packs: the block goes first, then the user text.
  $plain = Join-Path $fx 'home\AGENTS.md'
  [IO.File]::WriteAllText($plain, "Mine`n")
  [void](Update-UabsInstructionProfile -Path $plain -Text 'P')
  Assert ([IO.File]::ReadAllText($plain) -ceq "<!-- UABS-PROFILE -->`nP`n<!-- /UABS-PROFILE -->`n`nMine`n") 'Profile block in a plain file is malformed.'

  # Machine map: paths only, written once, unchanged on a rerun.
  $map = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Build-MachineMap.ps1') -PackRoot $PackRoot -ProfileRoot $root -Print | Out-String
  Assert ($LASTEXITCODE -eq 0 -and $map -match '(?m)^## Machine map') 'Machine map did not render.'
  Assert ($map -notmatch '(?i)(token|secret|password|api_key)=') 'Machine map exposed a secret-named variable.'
  Assert ($map.Length -lt 3000) ('Machine map is too long for every request: ' + $map.Length)
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Build-MachineMap.ps1') -PackRoot $PackRoot -ProfileRoot $root | Out-Null
  $first = [IO.File]::ReadAllText((Join-Path $root 'MACHINE-MAP.md'))
  $second = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TOOLS\Build-MachineMap.ps1') -PackRoot $PackRoot -ProfileRoot $root | Out-String
  Assert ($second -match 'unchanged' -and [IO.File]::ReadAllText((Join-Path $root 'MACHINE-MAP.md')) -ceq $first) 'Machine map rewrote itself without a change.'

  # A legacy unmarked copy with the pack's orphan closing tag must not double
  # the always-loaded profile when a marked copy is added on upgrade.
  $legacyFile = Join-Path $fx 'home\legacy-profile.md'
  $privateText = "## Operator profile (private; this PC only)`n- Preserve my model choice`n## Machine map`n- resolved tool`n"
  $plain = $privateText.Trim().Replace('## Operator profile','Operator profile')
  $legacyOriginal = "<!-- UABS-PROFILE -->`n$($privateText.Trim())`n<!-- /UABS-PROFILE -->`n`n$plain`n<!-- /UABS-PROFILE -->`n`nMy distinct custom rule`n"
  [IO.File]::WriteAllText($legacyFile, $legacyOriginal)
  [void](Update-UabsInstructionProfile -Path $legacyFile -Text $privateText)
  $cleaned = [IO.File]::ReadAllText($legacyFile)
  Assert (([regex]::Matches($cleaned, 'Preserve my model choice')).Count -eq 1) 'Identical legacy profile still doubles context.'
  Assert (([regex]::Matches($cleaned, '<!-- /UABS-PROFILE -->')).Count -eq 1 -and $cleaned.Contains('My distinct custom rule')) 'Legacy repair removed custom text or kept a stray profile tag.'
  $legacyBackup = @(Get-ChildItem -LiteralPath (Split-Path -Parent $legacyFile) -Filter 'legacy-profile.md.before-profile-*.bak')
  Assert ($legacyBackup.Count -eq 1 -and [IO.File]::ReadAllText($legacyBackup[0].FullName) -ceq $legacyOriginal) 'Legacy profile original was not backed up exactly.'
  Assert (-not (Update-UabsInstructionProfile -Path $legacyFile -Text $privateText)) 'Legacy profile cleanup is not idempotent.'
  $different = $legacyOriginal.Replace("`n`n$plain`n<!-- /UABS-PROFILE -->", "`n`n$($plain.Replace('Preserve my model choice','Keep a different personal choice'))`n<!-- /UABS-PROFILE -->")
  [IO.File]::WriteAllText($legacyFile, $different)
  [void](Update-UabsInstructionProfile -Path $legacyFile -Text $privateText)
  Assert ([IO.File]::ReadAllText($legacyFile).Contains('Keep a different personal choice')) 'A differing personal profile copy was deleted.'

  # Run the actual installer's instruction section, not a reimplementation.
  # An invalid oversized input must not mean "the user deleted the profile".
  & {
    $savedClaude = $env:CLAUDE_CONFIG_DIR
    try {
      $env:CLAUDE_CONFIG_DIR = Join-Path $fx 'isolated Claude home'
      New-Item -ItemType Directory -Force -Path $env:CLAUDE_CONFIG_DIR | Out-Null
      $target = Join-Path $env:CLAUDE_CONFIG_DIR 'CLAUDE.md'
      $original = "My rules`n`n<!-- UABS-PROFILE -->`nKeep my existing preferences`n<!-- /UABS-PROFILE -->`n"
      [IO.File]::WriteAllText($target, $original)
      $ProfileRoot = Join-Path $fx 'oversized profile'
      New-Item -ItemType Directory -Force -Path $ProfileRoot | Out-Null
      [IO.File]::WriteAllText((Join-Path $ProfileRoot 'PROFILE.md'), ('x' * 6100))
      $catalog = Get-UabsCatalog
      $Providers = @('Claude'); $ToolsOnly = $false; $SkipProfile = $false
      $ProfileTemplate = ''; $packSel = @{ Enabled = @() }
      $parseErrors = $null
      $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PackRoot 'INSTALL-AIO.ps1'), [ref]$null, [ref]$parseErrors)
      $sections = @($ast.FindAll({ param($node)
        $node -is [Management.Automation.Language.IfStatementAst] -and
        $node.Extent.Text -match '^if \(-not \$ToolsOnly\) \{\s+\$tailoredHome = Join-Path \$PackRoot'
      }, $true))
      Assert ($sections.Count -eq 1 -and -not $parseErrors.Count) 'Installer profile section was not uniquely located.'
      & ([scriptblock]::Create($sections[0].Extent.Text)) | Out-Null
      Assert ([IO.File]::ReadAllText($target) -ceq $original) 'Oversized profile removed or changed existing preferences.'
      Assert (@(Get-ChildItem -LiteralPath $env:CLAUDE_CONFIG_DIR -Filter '*.before-profile-*.bak').Count -eq 0) 'Invalid profile input unexpectedly rewrote the live block.'
    } finally { $env:CLAUDE_CONFIG_DIR = $savedClaude }
  }

  Write-Host 'USER PROFILE GATE: PASS'
} finally {
  if (Test-UabsPathWithin -Path $fx -Root ([IO.Path]::GetTempPath())) { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
}
