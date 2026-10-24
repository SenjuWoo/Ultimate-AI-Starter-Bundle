<# Execute the actual AIO cleanup block; default installs must never delete. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$source = [IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-AIO.ps1'))
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw 'Installer failed to parse.' }
$block = @($ast.FindAll({param($node)
  $node -is [Management.Automation.Language.IfStatementAst] -and
  $node.Extent.Text.StartsWith('if (-not $SkipCleanup -and -not $ToolsOnly)')
}, $true))
if ($block.Count -ne 1) { throw 'Cannot locate actual default cleanup block.' }
$script:invocations = 0
function Invoke-UabsChildScript {
  param($Title, $File, $ArgList)
  $script:invocations++
  if (@($ArgList) -contains '-Apply') { throw 'Default installer would delete personal backups/skills.' }
  if (@($ArgList) -notcontains '-PackRoot') { throw 'Preview lost explicit root.' }
  return 0
}
function Write-UabsOk { param($Message) }
function Write-UabsWarn { param($Message) throw $Message }
foreach ($skillsMode in @($false, $true)) {
  $SkipCleanup = $false; $ToolsOnly = $false; $SkillsOnly = $skillsMode
  $installed = @{}
  & ([scriptblock]::Create($block[0].Extent.Text))
  if ($installed['stale-state-cleanup'].status -ne 'preview-only') { throw 'Installer falsely reported applied cleanup.' }
}
foreach ($skipMode in @('skip','tools')) {
  $SkipCleanup = ($skipMode -eq 'skip'); $ToolsOnly = ($skipMode -eq 'tools')
  $before = $script:invocations
  & ([scriptblock]::Create($block[0].Extent.Text))
  if ($script:invocations -ne $before) { throw 'Cleanup ran despite explicit skip/tools-only.' }
}
if ($script:invocations -ne 2) { throw 'Cleanup preview was not exercised.' }
# Execute the actual mandatory-gate branch with failed/missing child fixtures.
$gateBlock = @($ast.FindAll({param($node)
  $node -is [Management.Automation.Language.IfStatementAst] -and
  $node.Extent.Text.StartsWith('if (Test-Path -LiteralPath $gateInstaller)')
}, $true))
if ($gateBlock.Count -ne 1) { throw 'Cannot locate mandatory gate installer branch.' }
function Invoke-UabsChildScript { param($Title,$File,$ArgList) return $script:gateExit }
function Write-UabsWarn { param($Message) }
$providerList = 'Hermes'
foreach ($case in @('success','failed','missing')) {
  $gateInstaller = Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1'
  $script:gateExit = if ($case -eq 'failed') { 7 } else { 0 }
  if ($case -eq 'missing') { $gateInstaller += '.absent-fixture' }
  $threw = $false
  try { & ([scriptblock]::Create($gateBlock[0].Extent.Text)) } catch { $threw = $true }
  if ($threw -ne ($case -ne 'success')) { throw "Mandatory gate failure accounting is incorrect: $case" }
}
Write-Host 'INSTALLER PRESERVATION GATE: PASS'
