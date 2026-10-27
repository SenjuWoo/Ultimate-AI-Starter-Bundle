# Exercise provisioning decisions and failures without installing packages or editing user PATH.
[CmdletBinding()]
param([string]$PackRoot)
if (-not $PackRoot) { $PackRoot=Split-Path -Parent $PSScriptRoot }
$ErrorActionPreference='Stop'
$tokens=$null; $errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PackRoot 'TOOLS\Install-BuildTools.ps1'),[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
foreach ($fn in $ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) { Invoke-Expression $fn.Extent.Text }
function Assert($Ok,$Message) { if (-not $Ok) { throw $Message } }
$work=Join-Path ([IO.Path]::GetTempPath()) ('uabs-build-fixture-'+[guid]::NewGuid().ToString('N'))
$savedPath=$env:PATH
$savedGo=@{}
foreach ($name in @('GOENV','GOTOOLCHAIN','GOWORK','GOROOT','GOFLAGS','GOOS','GOARCH')) { $savedGo[$name]=[Environment]::GetEnvironmentVariable($name,'Process') }
try {
  New-Item -ItemType Directory -Path $work | Out-Null
  $CheckOnly=$true; $log=Join-Path $work 'build.log'
  function Install-UabsWinget { throw 'A check/reused tool must never invoke package installation.' }
  $cmd=Join-Path $work 'compiler.cmd'
  [IO.File]::WriteAllText($cmd,"@echo off`r`necho fixture-version`r`nexit /b 0`r`n")
  $actual=Require-BuildCommand 'uabs-fixture-missing.exe' 'do-not-install' @($cmd)
  Assert ($actual -eq $cmd) 'Existing compiler candidate was replaced.'
  Assert ((Run-Build $cmd @('--version')) -eq 'fixture-version') 'Existing compiler was not executable.'
  $failed=$false
  try { Require-BuildCommand 'uabs-fixture-absent.exe' 'do-not-install' | Out-Null } catch { $failed=$_.Exception.Message -match 'Required build tool missing' }
  Assert $failed 'CheckOnly did not stop for a missing compiler.'
  [IO.File]::WriteAllText($cmd,"@echo off`r`necho real failure 1>&2`r`nexit /b 42`r`n")
  $failed=$false
  try { Run-Build $cmd @() | Out-Null } catch { $failed=$_.Exception.Message -match 'failed \(42\)' }
  Assert $failed 'Native compiler failure was reported as success.'
  [IO.File]::WriteAllText($cmd,("@echo off`r`necho "+[char]27+"[1mxmake v3.1.2+HEAD.fixture, build utility"+[char]27+"[0m`r`nexit /b 0`r`n"))
  Assert ((Get-XmakeVersion $cmd) -eq '3.1.2') 'Xmake vendor suffix was mistaken for an unsupported version.'
  [IO.File]::WriteAllText($cmd,"@echo off`r`necho xmake v2.9.9, old fixture`r`nexit /b 0`r`n")
  $failed=$false; try { Get-XmakeVersion $cmd | Out-Null } catch { $failed=$_.Exception.Message -match '3.0.0 or newer' }
  Assert $failed 'An Xmake too old for the supported CommonLib build was accepted.'
  # A real child process observes isolated probe settings, which are restored on success and failure.
  foreach ($name in $savedGo.Keys) { [Environment]::SetEnvironmentVariable($name,'fixture-personal-value','Process') }
  [IO.File]::WriteAllText($cmd,"@echo off`r`necho %GOENV%:%GOTOOLCHAIN%:%GOWORK%:%GOROOT%:%GOFLAGS%:%GOOS%:%GOARCH%`r`nexit /b 0`r`n")
  Assert ((Run-LocalGo $cmd @()) -eq 'off:local:off:::windows:amd64') 'Go probe inherited a project pin, flags, workspace or target architecture.'
  foreach ($name in $savedGo.Keys) { Assert ([Environment]::GetEnvironmentVariable($name,'Process') -eq 'fixture-personal-value') "Go probe changed personal $name." }
  [IO.File]::WriteAllText($cmd,"@echo off`r`nexit /b 42`r`n")
  try { Run-LocalGo $cmd @() | Out-Null } catch { }
  foreach ($name in $savedGo.Keys) { Assert ([Environment]::GetEnvironmentVariable($name,'Process') -eq 'fixture-personal-value') "Failed Go probe changed personal $name." }
  foreach ($case in @(
    @('go1.27.3',$true),@('go1.28.0',$false),@('go1.29.0',$false),
    @('go1.29rc1',$false),@('go1.28rc1',$true),@('go1.28beta1',$true),
    @('go1.28',$false),@('devel go1.29-abc123',$false)
  )) { Assert ((Test-GoUpdateRequired $case[0] 'go1.28.0') -eq $case[1]) "Wrong Go update decision for $($case[0])." }
  # A failed extraction must leave neither a final cache nor a blocking stage.
  $badZip=Join-Path $work 'bad.zip'; [IO.File]::WriteAllText($badZip,'broken archive')
  $cache=Join-Path $work 'go-cache'; $failed=$false
  try { Install-GoArchive -Archive $badZip -Cache $cache -ExpectedVersion 'go1.2.3' | Out-Null } catch { $failed=$true }
  Assert ($failed -and -not (Test-Path -LiteralPath $cache) -and @(Get-ChildItem -Path ($cache+'.stage-*') -ErrorAction SilentlyContinue).Count -eq 0) 'Failed Go extraction poisoned retry state.'
  # The filesystem/archive boundary is real; only the fixture compiler's version banner is substituted.
  $stateRoot=Join-Path $work 'shared-state'
  $sdk=Join-Path $stateRoot 'toolchains\go-current\go'
  $go=Join-Path $sdk 'bin\go.exe'
  function New-GoFixture([string]$Root,[string]$Version) {
    New-Item -ItemType Directory -Path (Join-Path $Root 'bin') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $Root 'VERSION'),$Version)
    [IO.File]::WriteAllText((Join-Path $Root 'LICENSE'),'fixture license')
    [IO.File]::WriteAllText((Join-Path $Root 'bin\go.exe'),$Version)
  }
  New-GoFixture $sdk 'go1.27.3'
  $payload=Join-Path $work 'payload'; $zip=Join-Path $work 'go.zip'
  New-GoFixture (Join-Path $payload 'go') 'go1.28.0'
  Compress-Archive -LiteralPath (Join-Path $payload 'go') -DestinationPath $zip
  $nativeRunBuild=(Get-Item Function:\Run-Build).ScriptBlock
  $script:failPublished=$false
  function Run-Build([string]$Exe,[string[]]$Arguments,[int[]]$SuccessCodes=@(0)) {
    if ($Exe -like ($work+'\*\go.exe')) {
      $version=[IO.File]::ReadAllText($Exe)
      if ($script:failPublished -and $Exe -eq $go -and $version -eq 'go1.28.0') { $version='go1.0.0' }
      return "go version $version windows/amd64"
    }
    return (& $nativeRunBuild @PSBoundParameters)
  }
  $pinned=Join-Path $stateRoot 'toolchains\go1.23.2\go'
  New-GoFixture $pinned 'go1.23.2'
  Assert (-not (Test-GoSharedSdk (Join-Path $pinned 'bin\go.exe'))) 'Project-pinned Go SDK was classified as shared.'
  $failed=$false
  try { Update-GoArchive $zip (Join-Path $pinned 'bin\go.exe') 'go1.28.0' | Out-Null } catch { $failed=$_.Exception.Message -match 'preserved' }
  Assert ($failed -and [IO.File]::ReadAllText((Join-Path $pinned 'VERSION')) -eq 'go1.23.2') 'Project-pinned Go SDK was modified.'
  $legacyGo=Join-Path $stateRoot 'toolchains\go1.27.3\go\bin\go.exe'
  @{version='1.0.0';result='PASS';go=$legacyGo;compile_run=@('go')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateRoot 'build-tools.json')
  Assert (Test-GoSharedSdk $legacyGo) 'Previously verified shared SDK was not recognized.'
  @{version='1.1.0';result='PASS';go=$legacyGo;go_update_managed=$false;compile_run=@('go')} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $stateRoot 'build-tools.json')
  Assert (-not (Test-GoSharedSdk $legacyGo)) 'A compile-only project SDK became update-managed on the next run.'
  # Mismatched archives must leave the exact prior SDK and no staging/backup debris.
  $failed=$false
  try { Update-GoArchive $zip $go 'go1.29.0' | Out-Null } catch { $failed=$_.Exception.Message -match 'version mismatch' }
  Assert ($failed -and [IO.File]::ReadAllText((Join-Path $sdk 'VERSION')) -eq 'go1.27.3') 'Mismatched Go archive replaced the prior SDK.'
  Assert (@(Get-ChildItem -Path ($sdk+'.stage-*'),($sdk+'.backup-*') -ErrorAction SilentlyContinue).Count -eq 0) 'Rejected Go archive left update debris.'
  $script:failPublished=$true; $failed=$false
  $publishError=''
  try { Update-GoArchive $zip $go 'go1.28.0' | Out-Null } catch { $publishError=$_.Exception.Message; $failed=$publishError -match 'Published Go update version mismatch'; if (-not $failed) { $publishError+=' at '+$_.ScriptStackTrace } }
  Assert ($failed -and [IO.File]::ReadAllText($go) -eq 'go1.27.3' -and [IO.File]::ReadAllText((Join-Path $sdk 'LICENSE')) -eq 'fixture license') "Failed Go publish did not restore the prior SDK: $publishError"
  Assert (@(Get-ChildItem -Path ($sdk+'.stage-*'),($sdk+'.backup-*') -ErrorAction SilentlyContinue).Count -eq 0) 'Rolled-back Go update left retry debris.'
  $script:failPublished=$false
  Assert ((Update-GoArchive $zip $go 'go1.28.0') -eq $go) 'Successful Go update changed the shared executable path.'
  Assert ((Get-GoVersion $go) -eq 'go1.28.0') 'Successful Go update did not publish the new SDK.'
  $backups=@(Get-ChildItem -Path ($sdk+'.backup-*') -Directory)
  Assert ($backups.Count -eq 1 -and [IO.File]::ReadAllText((Join-Path $backups[0].FullName 'VERSION')) -eq 'go1.27.3') 'Successful Go update did not retain the old SDK backup.'
  # Equal and newer SDKs must not even open a malformed candidate archive.
  foreach ($version in @('go1.28.0','go1.29.0','go1.29rc1','devel go1.29-abc123')) {
    [IO.File]::WriteAllText($go,$version)
    Assert ((Update-GoArchive $badZip $go 'go1.28.0') -eq $go) "Go $version was unnecessarily replaced."
    Assert ((Get-GoVersion $go) -eq $version) "Go $version was downgraded."
  }
  Set-Item Function:\Run-Build $nativeRunBuild
  function Test-Path { param([string]$LiteralPath) return $LiteralPath -match 'kernel32.lib$' }
  function Get-ChildItem { return [pscustomobject]@{DirectoryName='C:\sdk\Include\10.0.1\um'} }
  Assert (Test-WindowsSdk) 'A matching SDK header/library pair was not detected.'
  function Test-Path { return $false }
  Assert (-not (Test-WindowsSdk)) 'An SDK without required libraries was accepted.'
  Remove-Item Function:\Test-Path,Function:\Get-ChildItem
  # Vendor updates must distinguish no-op, failure and read-only execution.
  $CheckOnly=$false; $Offline=$false; $NoUpdate=$false
  function winget { throw 'Fixture must never launch a package manager.' }
  function Invoke-BuildPackageUpgrade { return @{code=-1978335189;output='No applicable upgrade'} }
  Update-BuildPackage 'fixture-package'
  function Invoke-BuildPackageUpgrade { return @{code=42;output='injected vendor failure'} }
  $failed=$false
  try { Update-BuildPackage 'fixture-package' } catch { $failed=$_.Exception.Message -match 'Managed package update failed' }
  Assert $failed 'An updater failure was accepted as current.'
  $CheckOnly=$true
  function Invoke-BuildPackageUpgrade { throw 'CheckOnly must not update.' }
  Update-BuildPackage 'fixture-package'
  $CheckOnly=$false; $Offline=$true
  Update-BuildPackage 'fixture-package'
  $Offline=$false; $NoUpdate=$true
  Update-BuildPackage 'fixture-package'
  $source=[IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-AIO.ps1'))
  Assert ($source -match '\[switch\]\$SkipBuildTools' -and $source -match "TOOLS\\Install-BuildTools.ps1") 'Default installer does not reach the suite/opt-out.'
  # Cross the real powershell -File boundary: comma lists and switches must reach the child unchanged.
  $repair=Join-Path $work 'repair'; $repairTools=Join-Path $repair 'TOOLS'
  New-Item -ItemType Directory -Path $repairTools -Force | Out-Null
  Copy-Item -LiteralPath (Join-Path $PackRoot 'TOOLS\Ensure-Tools.ps1') -Destination $repairTools
  [IO.File]::WriteAllText((Join-Path $repairTools 'UABS-Common.ps1'),'function Get-UabsPackRoot { Split-Path -Parent $PSScriptRoot }; function Write-UabsStep($m) {}; function Write-UabsOk($m) {}')
  [IO.File]::WriteAllText((Join-Path $repairTools 'discover_tools.ps1'),'# Fixture discovery has no side effects.')
  [IO.File]::WriteAllText((Join-Path $repairTools 'Install-BuildTools.ps1'),@'
param([switch]$Offline,[switch]$NoUpdate)
@{offline=[bool]$Offline;no_update=[bool]$NoUpdate}|ConvertTo-Json|Set-Content (Join-Path (Split-Path -Parent $PSScriptRoot) 'suite.json')
'@)
  [IO.File]::WriteAllText((Join-Path $repair 'INSTALL-AIO.ps1'),@'
param([string]$Mode,[string[]]$Components,[switch]$ToolsOnly,[switch]$SkipBuildTools,[switch]$NoToolUpdates)
@{mode=$Mode;components=@($Components);no_update=[bool]$NoToolUpdates}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'child.json')
'@)
  foreach ($noUpdateCase in @($false,$true)) {
    $repairArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $repairTools 'Ensure-Tools.ps1'),'-Mode','BundledOnly','-Components','first,second')
    if ($noUpdateCase) { $repairArgs+='-NoUpdate' }
    & powershell.exe @repairArgs | Out-Null
    Assert ($LASTEXITCODE -eq 0) 'Ensure-Tools lost its native switch/list arguments.'
    $child=[IO.File]::ReadAllText((Join-Path $repair 'child.json')) | ConvertFrom-Json
    $suite=[IO.File]::ReadAllText((Join-Path $repair 'suite.json')) | ConvertFrom-Json
    Assert ($child.components[0] -eq 'first,second' -and $child.no_update -eq $noUpdateCase -and $suite.offline -and $suite.no_update -eq $noUpdateCase) 'Repair child arguments disagree with the requested mode.'
  }
  'BUILD TOOLS GATE: PASS'
} finally {
  $env:PATH=$savedPath
  foreach ($name in $savedGo.Keys) { [Environment]::SetEnvironmentVariable($name,$savedGo[$name],'Process') }
  if ([IO.Path]::GetFullPath($work).StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
