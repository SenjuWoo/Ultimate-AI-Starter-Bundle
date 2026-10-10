<# START-HERE bundle update check: decision table, argument forwarding, a real
   git clone fixture and INSTALL-REMOTE's "nothing replaced" exit code. No
   network: GitHub is never queried here. #>
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-self-update-' + [guid]::NewGuid().ToString('N'))
try {
  $p = { param($l, $t, $g, $c, $u) (Get-UabsBundleUpdatePlan -LocalVersion $l -LatestTag $t -IsGit $g -GitClean $c -GitTracksUpstream $u).action }
  Assert ((& $p 'v8.7.40' 'v8.7.40' $false $false $false) -eq 'none') 'Same version was not current.'
  Assert ((& $p 'v8.7.41' 'v8.7.40' $false $false $false) -eq 'none') 'A newer local copy was downgraded.'
  Assert ((& $p 'v8.7.40' 'v8.7.41' $false $false $false) -eq 'release') 'A release copy did not take the newer release.'
  Assert ((& $p 'v8.7.40' 'v8.8.0.1' $true $true $true) -eq 'git-pull') 'A clean tracking clone did not fast-forward.'
  Assert ((& $p 'v8.7.40' 'v8.8.0' $true $false $true) -eq 'skip') 'A dirty clone was updated.'
  Assert ((& $p 'v8.7.40' 'v8.8.0' $true $true $false) -eq 'skip') 'A clone without upstream was updated.'
  Assert ((& $p 'v8.7.40' 'latest' $false $false $false) -eq 'skip') 'An unreadable tag was trusted.'

  $bound = [ordered]@{ Providers = @('Claude','Codex'); CoreOnly = [switch]$true; WithRtk = [switch]$false; WorkspaceRoot = 'D:\My Mods'; SkipSelfUpdate = [switch]$true }
  $list = @(ConvertTo-UabsArgList -Bound $bound -Exclude @('SkipSelfUpdate'))
  Assert (($list -join '|') -ceq '-Providers|Claude,Codex|-CoreOnly|-WorkspaceRoot|D:\My Mods') ('Forwarded arguments drifted: ' + ($list -join '|'))
  $bound.SkipPreamble = [switch]$true
  $remoteArgs = Get-UabsSelfUpdateRemoteArgs -Bound $bound -Tag 'v9.0.0'
  Assert ((@($remoteArgs.InstallerArgs) -join '|') -ceq '-CoreOnly|-WorkspaceRoot|D:\My Mods|-SkipSelfUpdate') ('Installer args duplicate what INSTALL-REMOTE forwards: ' + (@($remoteArgs.InstallerArgs) -join '|'))
  Assert (@($remoteArgs.Providers) -join ',' -ceq 'Claude,Codex' -and $remoteArgs.SkipPreamble -and $remoteArgs.SelfUpdate -and $remoteArgs.Tag -ceq 'v9.0.0') 'INSTALL-REMOTE lost its own forwarded parameters.'
  $remoteParams = (Get-Command (Join-Path $PackRoot 'INSTALL-REMOTE.ps1')).Parameters.Keys
  foreach ($key in $remoteArgs.Keys) { Assert ($remoteParams -contains $key) ('INSTALL-REMOTE has no parameter ' + $key) }

  # Native stderr (git hints, remote errors) must not become terminating errors on PS 5.1.
  $ErrorActionPreference = 'Continue'
  $git = Get-Command git -ErrorAction SilentlyContinue
  if ($git) {
    $origin = Join-Path $fixture 'origin.git'; $clone = Join-Path $fixture 'clone with space'
    $null = & $git.Source init -q --bare $origin 2>&1
    $null = & $git.Source clone -q $origin $clone 2>&1
    [IO.File]::WriteAllText((Join-Path $clone 'VERSION.txt'), 'v8.7.40')
    $null = & $git.Source -C $clone -c user.name=t -c user.email=t@example.invalid add -A 2>&1
    $null = & $git.Source -C $clone -c user.name=t -c user.email=t@example.invalid commit -q -m init 2>&1
    $null = & $git.Source -C $clone push -q -u origin HEAD 2>&1
    $s = Get-UabsGitCheckoutState -Root $clone
    Assert ($s.is_git -and $s.clean -and $s.tracks) 'A clean tracking clone was misread.'
    [IO.File]::WriteAllText((Join-Path $clone 'local.txt'), 'x')
    Assert (-not (Get-UabsGitCheckoutState -Root $clone).clean) 'An untracked change was not seen.'
    Assert (-not (Get-UabsGitCheckoutState -Root $fixture).is_git) 'A plain folder was treated as a clone.'
  }

  # A bad tag fails before anything is downloaded or replaced: 20 for the
  # START-HERE caller (install the local copy), 1 for a direct run.
  $remote = Join-Path $PackRoot 'INSTALL-REMOTE.ps1'
  $dest = Join-Path $fixture 'dest'
  $null = & (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File $remote -Tag 'not-a-tag' -DestRoot $dest -SelfUpdate 2>&1
  Assert ($LASTEXITCODE -eq 20) ('Self-update staging failure returned ' + $LASTEXITCODE)
  $null = & (Get-Command powershell.exe).Source -NoProfile -ExecutionPolicy Bypass -File $remote -Tag 'not-a-tag' -DestRoot $dest 2>&1
  Assert ($LASTEXITCODE -eq 1) ('Direct remote failure returned ' + $LASTEXITCODE)
  Assert (-not (Test-Path -LiteralPath $dest)) 'A failed remote run created the destination.'

  $aio = [IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-AIO.ps1'))
  Assert ($aio.IndexOf('Invoke-UabsBundleSelfUpdate') -gt 0 -and $aio.IndexOf('Invoke-UabsBundleSelfUpdate') -lt $aio.IndexOf('Ensure-Provider-CLIs')) 'The update check no longer runs before provider work.'
  Assert ($aio -match "UABS_NO_SELF_UPDATE -ne '1'" -and $aio -match "Mode -ne 'BundledOnly'") 'Opt-outs for offline/explicit runs are missing.'
  $bat = [IO.File]::ReadAllText((Join-Path $PackRoot 'START-HERE.bat'))
  Assert ($bat -match 'cd /d "%~dp0\.\."') 'START-HERE keeps its console inside the folder an update replaces.'
  Write-Host 'BUNDLE SELF-UPDATE GATE: PASS'
} finally {
  if (Test-Path -LiteralPath $fixture) {
    if (-not (Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath()))) { throw 'Fixture cleanup escaped its temporary root.' }
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}
