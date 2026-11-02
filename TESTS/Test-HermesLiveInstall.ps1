# Run the installer's real Hermes plugin branch without touching a live profile.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$text = [IO.File]::ReadAllText((Join-Path $root 'INSTALL-AIO.ps1'))
$start = $text.IndexOf("      'Hermes' {", $text.IndexOf('function Invoke-UabsSkillDedupe'))
$end = $text.IndexOf("      'Codex' {", $start)
$branch = [scriptblock]::Create("switch ('Hermes') {`n" + $text.Substring($start, $end - $start) + "`n}")
function Get-UabsHermesExecutable { return $PSCommandPath }
function Get-UabsNativeOutput {
  param($Exe, $CmdArgs)
  if ($CmdArgs[0] -eq 'gateway') { return $script:GatewayStatus }
  if ($CmdArgs[0] -eq 'plugins') { return 'superpowers ponytail' }
  throw 'Unexpected native query'
}
function Get-Process { return $script:Desktop }
function Invoke-UabsNative { throw 'Live install attempted a native mutation' }
function Stop-Process { throw 'Live install killed an application' }
function Start-Process { throw 'Live install restarted an application' }
function Set-UabsHermesPluginScanOff { throw 'Live install changed plugin config' }
function Write-UabsOk { param($Message) }
function Write-UabsWarn { param($Message) }
function New-UabsPluginStateEntry { param($Status, $Reason) return @{native=$false;status=$Status;reason=$Reason} }
foreach ($case in @('desktop', 'gateway')) {
  $script:Desktop = if ($case -eq 'desktop') { [pscustomobject]@{Path='fixture.exe'} } else { $null }
  $script:GatewayStatus = if ($case -eq 'gateway') { 'running' } else { 'not running' }
  $pstate = @{plugins=@{}}
  & $branch
  foreach ($id in @('superpowers','ponytail')) {
    if ($pstate.plugins[$id].status -ne 'deferred-live-gateway') { throw "$case did not defer $id" }
    if (-not $pstate.plugins[$id].native) { throw "$case forgot existing native ownership for $id" }
  }
}
if ($text -match 'Stop-Process' -or $text -match "@\('gateway', 'stop'\)") {
  throw 'The installer still stops a running app outside the plugin branch'
}
Write-Host 'HERMES LIVE INSTALL: PASS'
