[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference='Stop'
if(-not $PackRoot){$PackRoot=Split-Path -Parent $PSScriptRoot}
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition,$Message){if(-not $Condition){throw $Message}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('uabs-grok-plugins-'+[guid]::NewGuid().ToString('N'))
$savedHome=$env:USERPROFILE; $savedLocal=$env:LOCALAPPDATA
try {
  $env:USERPROFILE=Join-Path $fixture 'home'
  $env:LOCALAPPDATA=Join-Path $fixture 'state'
  $root=Join-Path $env:USERPROFILE '.grok\installed-plugins'
  $old=Join-Path $root 'old'; $new=Join-Path $root 'new'
  New-Item -ItemType Directory -Force -Path $old,$new | Out-Null
  [IO.File]::WriteAllText((Join-Path $old 'keep.txt'),'original plugin bytes')
  [IO.File]::WriteAllText((Join-Path $new 'keep.txt'),'new plugin bytes')
  $reg=Join-Path $root 'registry.json'
  $doc=@{personal='preserve';repos=@{
    old=@{name='superpowers';version='6.4.2';repo_key='old';path=$old;marketplace='official';source='https://github.com/obra/superpowers.git'}
    new=@{name='superpowers';version='7.0.0';repo_key='new';path=$new;source='https://github.com/obra/superpowers'}
  }}
  [IO.File]::WriteAllText($reg,($doc|ConvertTo-Json -Depth 8))
  function Get-UabsGrokPluginList {
    param($GrokExe)
    $registry=[IO.File]::ReadAllText((Join-Path $env:USERPROFILE '.grok\installed-plugins\registry.json'))|ConvertFrom-Json
    @($registry.repos.PSObject.Properties|ForEach-Object {$_.Value})
  }
  $result=@(Repair-UabsGrokDuplicatePlugins -GrokExe 'fixture' -PluginName superpowers)
  Assert ($result.Count -eq 1 -and $result[0].version -eq '7.0.0') 'An older marketplace copy displaced the tested newer plugin.'
  Assert (-not (Test-Path -LiteralPath $old) -and (Test-Path -LiteralPath $new)) 'Wrong duplicate directory removed.'
  $backupFiles=@(Get-ChildItem -LiteralPath (Get-UabsStateRoot) -Recurse -File -Filter keep.txt)
  Assert (@($backupFiles|Where-Object {[IO.File]::ReadAllText($_.FullName) -ceq 'original plugin bytes'}).Count -eq 1) 'Retired plugin bytes were not backed up.'
  Assert (([IO.File]::ReadAllText($reg)|ConvertFrom-Json).personal -ceq 'preserve') 'Personal registry metadata changed.'
  $outside=Join-Path $fixture 'personal plugin'
  New-Item -ItemType Directory -Force -Path $outside|Out-Null
  [IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'personal')
  $doc.repos.Remove('old')
  $doc.repos['outside']=@{name='superpowers';version='5.0.0';repo_key='outside';path=$outside}
  [IO.File]::WriteAllText($reg,($doc|ConvertTo-Json -Depth 8))
  Repair-UabsGrokDuplicatePlugins -GrokExe 'fixture' -PluginName superpowers|Out-Null
  Assert ((Test-Path -LiteralPath $outside) -and ([IO.File]::ReadAllText($reg)|ConvertFrom-Json).repos.outside) 'Unowned external plugin was removed or unregistered.'
  Write-Host 'GROK PLUGIN DEDUPE GATE: PASS'
} finally {
  $env:USERPROFILE=$savedHome; $env:LOCALAPPDATA=$savedLocal
  if(Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath())){Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue}
}
