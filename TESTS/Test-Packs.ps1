<#
.SYNOPSIS
  Content packs: opt-in defaults, remembered choices, instruction blocks, skill retirement.

.DESCRIPTION
  The Skyrim pack used to install for everyone. These cases pin the rules that
  replaced that: Skyrim is opt-in, an explicit choice wins and is
  remembered, the marked instruction block follows the selection, an exact copy
  of an older bundle's long Skyrim section is replaced (anything else in the
  file is kept), and a disabled pack's unmodified skills are retired.
  Fixtures only; no registry, no real provider home.
#>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }

$fx = Join-Path ([IO.Path]::GetTempPath()) ('uabs-packs-' + [guid]::NewGuid().ToString('N'))
$savedLocal = $env:LOCALAPPDATA
$savedEnv = @{}
$catalog = Get-UabsPackCatalog -PackRoot $PackRoot
foreach ($v in @($catalog.packs.skyrim.detect.env)) { $savedEnv[$v] = [Environment]::GetEnvironmentVariable($v, 'Process'); [Environment]::SetEnvironmentVariable($v, $null, 'Process') }
try {
  $env:LOCALAPPDATA = Join-Path $fx 'state'
  $docs = Join-Path $fx 'Documents'; $appData = Join-Path $fx 'AppData'; $steam = Join-Path $fx 'Steam'
  New-Item -ItemType Directory -Force -Path $docs, $appData, (Join-Path $steam 'steamapps') | Out-Null
  $ev = @{ SteamLibraries = @($steam); DocumentsRoot = $docs; AppDataRoot = $appData; SkipRegistry = $true }
  $state = Join-Path $fx 'packs.json'

  # ---- detection ----
  $sel = Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $state -EvidenceArgs $ev
  Assert ($sel.Enabled.Count -eq 0 -and $sel.Disabled -contains 'skyrim') 'Skyrim pack turned on with no evidence.'
  Assert ($sel.ExcludedSkills -contains 'skyrim-tool-router' -and $sel.ExcludedSkills.Count -eq @($catalog.packs.skyrim.skills).Count) 'Disabled pack did not exclude its skills.'
  Assert ($sel.DisabledComponents -contains 'skyrim-forge' -and $sel.DisabledComponents -contains 'housecarl') 'Disabled pack did not drop its components.'
  Assert (-not (Test-Path -LiteralPath $state)) 'Detection alone must not be remembered.'
  foreach ($case in @(
    @{ name='steam manifest'; make={ [IO.File]::WriteAllText((Join-Path $steam 'steamapps\appmanifest_489830.acf'), '"AppState"{}') } },
    @{ name='My Games'; make={ New-Item -ItemType Directory -Force -Path (Join-Path $docs 'My Games\Skyrim Special Edition') | Out-Null } },
    @{ name='Vortex'; make={ New-Item -ItemType Directory -Force -Path (Join-Path $appData 'Vortex\skyrimse') | Out-Null } }
  )) {
    Get-ChildItem -LiteralPath (Join-Path $steam 'steamapps') -Force | Remove-Item -Recurse -Force
    foreach ($d in @((Join-Path $docs 'My Games'), (Join-Path $appData 'Vortex'))) { if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force } }
    & $case.make
    $sel = Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $state -EvidenceArgs $ev
    Assert ($sel.Disabled -contains 'skyrim') ("Game detection opted into Skyrim: " + $case.name)
    Assert ($sel.ExcludedSkills.Count -eq @($catalog.packs.skyrim.skills).Count) ("Default-off pack did not exclude its skills: " + $case.name)
    Assert (@(Find-UabsPackEvidence -Detect $catalog.packs.skyrim.detect @ev).Count -gt 0) ("Evidence fixture was not detected: " + $case.name)
  }
  $toolDir = Join-Path $fx 'Forge'; New-Item -ItemType Directory -Force -Path $toolDir | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $appData 'Vortex') | Remove-Item -Recurse -Force
  $env:SKYRIM_FORGE_ROOT = $toolDir
  Assert ((Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $state -EvidenceArgs $ev).Disabled -contains 'skyrim') 'An existing tool must not silently opt into Skyrim.'
  $env:SKYRIM_FORGE_ROOT = Join-Path $fx 'missing'
  Assert ((Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $state -EvidenceArgs $ev).Enabled.Count -eq 0) 'A stale env var pointing nowhere was taken as evidence.'
  $env:SKYRIM_FORGE_ROOT = $null

  # ---- explicit choices win and are remembered ----
  New-Item -ItemType Directory -Force -Path (Join-Path $docs 'My Games\Skyrim Special Edition') | Out-Null
  $sel = Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $state -EvidenceArgs $ev -Excluded @('skyrim')
  Assert ($sel.Enabled.Count -eq 0 -and $sel.Reasons['skyrim'] -match 'excluded') '-ExcludePacks did not beat evidence.'
  $sel = Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $state -EvidenceArgs $ev
  Assert ($sel.Enabled.Count -eq 0 -and $sel.Reasons['skyrim'] -match 'earlier choice') 'An exclusion was not remembered.'
  Remove-Item -LiteralPath (Join-Path $docs 'My Games') -Recurse -Force
  $sel = Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $state -EvidenceArgs $ev -Requested @('skyrim')
  Assert ($sel.Enabled -contains 'skyrim') '-Packs did not turn the pack on.'
  Assert ((Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $state -EvidenceArgs $ev).Enabled -contains 'skyrim') 'A request was not remembered without evidence.'
  $threw = $false; try { Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $state -EvidenceArgs $ev -Requested @('nope') | Out-Null } catch { $threw = $_.Exception.Message -match 'Unknown pack' }
  Assert $threw 'An unknown pack name was accepted.'

  # ---- instruction blocks ----
  $owner=Join-Path $fx 'owner'
  $ownerInstructions=Join-Path $owner 'integrations\skyrim-pack\INSTRUCTIONS.md'
  New-Item -ItemType Directory -Force -Path (Split-Path $ownerInstructions -Parent) | Out-Null
  [IO.File]::WriteAllText($ownerInstructions, '# Skyrim owner fixture: skyrim-tool-router')
  $env:SKYRIM_FORGE_ROOT=$owner

  $general = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\Claude\COPY-TO-PROVIDER-HOME\CLAUDE.md'
  $legacy = @(Get-ChildItem -LiteralPath (Join-Path $PackRoot 'BUNDLED-TOOLS\packs\skyrim\legacy') -Filter '*.md' | Sort-Object Name)[0]
  Assert $legacy 'No archived legacy Skyrim section to test against.'
  $file = Join-Path $fx 'home\CLAUDE.md'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $file) | Out-Null
  $user = "# My own rules`r`nAlways answer in French."
  [IO.File]::WriteAllText($file, ([IO.File]::ReadAllText($legacy.FullName).Trim() -replace '\r?\n', "`r`n") + "`r`n`r`n" + $user + "`r`n", (New-Object System.Text.UTF8Encoding $false))
  Assert (Update-UabsInstructionPacks -Path $file -PackRoot $PackRoot -Enabled @('skyrim') -GeneralTemplate $general) 'Legacy Skyrim section was not converted.'
  $after = [IO.File]::ReadAllText($file)
  $generalText = ([IO.File]::ReadAllText($general)).Trim() -replace '\r?\n', "`r`n"
  Assert ($after.StartsWith($generalText)) 'Converted file does not start with the general template.'
  Assert ($after -match '<!-- UABS-PACK:skyrim -->' -and $after -match 'skyrim-tool-router') 'Skyrim block missing after conversion.'
  Assert ($after.Contains($user)) 'User text was lost.'
  Assert ($after -notmatch '(?m)^## Start every substantial Skyrim task') 'Legacy section survived.'
  Assert ($after -notmatch '(?<!\r)\n') 'CRLF file was rewritten with LF.'
  Assert (@(Get-ChildItem -LiteralPath (Split-Path -Parent $file) -Filter 'CLAUDE.md.before-pack-*.bak').Count -eq 1) 'No backup before the first rewrite.'
  Assert (-not (Update-UabsInstructionPacks -Path $file -PackRoot $PackRoot -Enabled @('skyrim') -GeneralTemplate $general)) 'Second run was not a no-op.'
  Assert (Update-UabsInstructionPacks -Path $file -PackRoot $PackRoot -Enabled @() -GeneralTemplate $general) 'Disabling the pack changed nothing.'
  $off = [IO.File]::ReadAllText($file)
  Assert ($off -notmatch 'UABS-PACK' -and $off.StartsWith($generalText) -and $off.Contains($user)) 'Disabling removed more or less than the pack block.'

  # Mixed endings: the preamble writer appends LF text to CRLF files. The pack
  # writer must not normalize text it does not own, or the two flip it forever.
  $mixed = Join-Path $fx 'home\MIXED.md'
  [IO.File]::WriteAllText($mixed, "Head`r`n`r`nTail line one`nTail line two`n", (New-Object System.Text.UTF8Encoding $false))
  Assert (Update-UabsInstructionPacks -Path $mixed -PackRoot $PackRoot -Enabled @('skyrim')) 'Block not added to a mixed-ending file.'
  Assert ([IO.File]::ReadAllText($mixed).Contains("Tail line one`nTail line two")) 'LF text the pack writer does not own was rewritten.'
  Assert (-not (Update-UabsInstructionPacks -Path $mixed -PackRoot $PackRoot -Enabled @('skyrim'))) 'A mixed-ending file is rewritten on every run.'

  # A file that never had a Skyrim section: block in, block out, bytes back.
  $plain = Join-Path $fx 'home\AGENTS.md'
  $orig = "# Notes`nKeep it short.`n"
  [IO.File]::WriteAllText($plain, $orig, (New-Object System.Text.UTF8Encoding $false))
  Assert (Update-UabsInstructionPacks -Path $plain -PackRoot $PackRoot -Enabled @('skyrim')) 'Block was not added to a plain file.'
  Assert (Update-UabsInstructionPacks -Path $plain -PackRoot $PackRoot -Enabled @()) 'Block was not removed from a plain file.'
  Assert ([IO.File]::ReadAllText($plain) -ceq $orig) 'Add-then-remove did not restore the original bytes.'
  Assert (-not (Update-UabsInstructionPacks -Path (Join-Path $fx 'home\absent.md') -PackRoot $PackRoot -Enabled @())) 'A missing file was created with nothing to write.'

  # ---- skills of a disabled pack are retired, edited copies kept ----
  $src = Join-Path $fx 'src'; $dst = Join-Path $fx 'dst'
  foreach ($n in 'general-skill', 'skyrim-tool-router', 'skyrim-memory') {
    New-Item -ItemType Directory -Force -Path (Join-Path $src $n) | Out-Null
    [IO.File]::WriteAllText((Join-Path $src "$n\SKILL.md"), "---`nname: $n`ndescription: fixture`n---`nbody`n")
  }
  Sync-UabsProviderSkills -From $src -To $dst -Provider 'PackFixture'
  [IO.File]::AppendAllText((Join-Path $dst 'skyrim-memory\SKILL.md'), 'my edit')
  Sync-UabsProviderSkills -From $src -To $dst -Provider 'PackFixture' -ExcludeNames @('skyrim-tool-router', 'skyrim-memory')
  Assert (-not (Test-Path -LiteralPath (Join-Path $dst 'skyrim-tool-router'))) 'An unmodified skill of a disabled pack was not retired.'
  Assert (Test-Path -LiteralPath (Join-Path $dst 'skyrim-memory\SKILL.md')) 'A user-edited skill of a disabled pack was deleted.'
  Assert (Test-Path -LiteralPath (Join-Path $dst 'general-skill\SKILL.md')) 'A general skill was removed.'

  # ---- Hermes named profiles: managed ones only; pack skills moved aside ----
  $hh = Join-Path $fx 'hermes'
  $soulSrc = Join-Path $PackRoot '3-PREAMBLES\SOUL.md'
  $soulText = [IO.File]::ReadAllText($soulSrc)
  foreach ($p in 'code', 'skyrim', 'rp') {
    New-Item -ItemType Directory -Force -Path (Join-Path $hh "profiles\$p\skills\skyrim-memory") | Out-Null
    [IO.File]::WriteAllText((Join-Path $hh "profiles\$p\skills\skyrim-memory\SKILL.md"), "---`nname: skyrim-memory`n---`nold`n")
    $soul = if ($p -eq 'rp') { "You are a role-play gateway.`n" } else { $soulText }
    [IO.File]::WriteAllText((Join-Path $hh "profiles\$p\SOUL.md"), $soul)
  }
  New-Item -ItemType Directory -Force -Path (Join-Path $hh 'profiles\bare') | Out-Null
  [IO.File]::WriteAllText((Join-Path $hh 'profiles\bare\SOUL.md'), $soulText)
  $managed = @(Get-UabsHermesManagedProfiles -HermesHome $hh -SoulFile $soulSrc -RequireSkills | ForEach-Object Name | Sort-Object)
  Assert (($managed -join ',') -eq 'code,skyrim') ('Managed Hermes profiles with skills misdetected: ' + ($managed -join ','))
  $souls = @(Get-UabsHermesManagedProfiles -HermesHome $hh -SoulFile $soulSrc | ForEach-Object Name | Sort-Object)
  Assert (($souls -join ',') -eq 'bare,code,skyrim') ('Managed Hermes profiles for preamble wiring misdetected: ' + ($souls -join ','))
  $aside = Move-UabsSkillsAside -SkillsDir (Join-Path $hh 'profiles\code\skills') -Names @('skyrim-memory', 'not-there') -Label 'fixture'
  Assert ($aside.Moved -contains 'skyrim-memory' -and $aside.Moved.Count -eq 1 -and (Test-Path -LiteralPath (Join-Path $aside.Backup 'skyrim-memory\SKILL.md'))) 'Pack skill was not moved to a backup.'
  Assert (-not (Test-Path -LiteralPath (Join-Path $hh 'profiles\code\skills\skyrim-memory'))) 'Moved skill is still indexed.'
  Assert ((Move-UabsSkillsAside -SkillsDir (Join-Path $hh 'profiles\code\skills') -Names @('skyrim-memory') -Label 'fixture').Backup -eq $null) 'A second move created an empty backup.'

  # The pointer is a disposable fixture beneath fx/state, never the real user registration.
  $reverseState=Join-Path $fx 'reverse-packs.json'
  $receipt=Join-Path $fx 'state\ReverseThis\kit.json'
  Assert (Test-UabsPathWithin -Path $receipt -Root $fx) 'Companion fixture escaped its temporary root.'
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $receipt) | Out-Null
  [IO.File]::WriteAllText($receipt,'{"fixture":true}')
  $sel=Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $reverseState -Excluded @('skyrim') -EvidenceArgs $ev
  Assert ($sel.Enabled -contains 'reverse') 'Registered Reverse THIS! companion was not detected.'
  $sel=Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $reverseState -Excluded @('reverse') -EvidenceArgs $ev
  Assert ($sel.Disabled -contains 'reverse') 'Explicit companion exclusion did not win.'
  $sel=Resolve-UabsPackSelection -PackRoot $PackRoot -StatePath $reverseState -EvidenceArgs $ev
  Assert ($sel.Disabled -contains 'reverse') 'Companion exclusion was not remembered.'
  Assert ([IO.File]::ReadAllText($receipt) -eq '{"fixture":true}') 'Detection rewrote another owner receipt.'
  Write-Host 'PACKS GATE: PASS'
} finally {
  $env:LOCALAPPDATA = $savedLocal
  foreach ($k in $savedEnv.Keys) { [Environment]::SetEnvironmentVariable($k, $savedEnv[$k], 'Process') }
  if (Test-UabsPathWithin -Path $fx -Root ([IO.Path]::GetTempPath())) { Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue }
}
