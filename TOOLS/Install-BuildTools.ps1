# Provision the shared compiler suite; existing toolchains and project pins win.
[CmdletBinding()]
param([switch]$CheckOnly,[switch]$Offline,[switch]$NoUpdate)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
$stateRoot = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle'
$logDir = Join-Path $stateRoot 'logs'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$log = Join-Path $logDir 'build-tools.log'
$suiteVersion = '1.2.0'
Add-Content -LiteralPath $log -Value ("$(Get-Date -Format o) build-suite=$suiteVersion check=$CheckOnly offline=$Offline no_update=$NoUpdate")

function Find-BuildCommand([string]$Name, [string[]]$Candidates = @()) {
  $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($command) { return $command.Source }
  foreach ($candidate in $Candidates) { if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate } }
  return $null
}
function Add-BuildPath([string]$Directory) {
  if (($env:PATH -split ';') -notcontains $Directory) { $env:PATH = $Directory + ';' + $env:PATH }
  if ($CheckOnly) { return }
  $userPath = [Environment]::GetEnvironmentVariable('PATH','User')
  if ($null -eq $userPath) { $userPath = '' }
  if (($userPath -split ';') -notcontains $Directory) {
    $backup = Join-Path $stateRoot ('build-path.before-' + (Get-Date -Format 'yyyyMMdd-HHmmss-ffff') + '.json')
    @{path=$userPath} | ConvertTo-Json | Set-Content -LiteralPath $backup -Encoding UTF8
    [Environment]::SetEnvironmentVariable('PATH', ($userPath.TrimEnd(';') + ';' + $Directory).TrimStart(';'), 'User')
  }
}
function Require-BuildCommand([string]$Name, [string]$Package, [string[]]$Candidates = @()) {
  $exe = Find-BuildCommand $Name $Candidates
  if (-not $exe -and -not $CheckOnly -and -not $Offline) {
    if (-not (Install-UabsWinget @($Package))) { throw "Cannot install $Name ($Package)." }
    Refresh-ProcessPath
    $exe = Find-BuildCommand $Name $Candidates
  }
  if (-not $exe) { throw "Required build tool missing: $Name. Run TOOLS\Install-BuildTools.ps1." }
  Add-BuildPath (Split-Path -Parent $exe)
  return $exe
}
function Run-Build([string]$Exe, [string[]]$Arguments, [int[]]$SuccessCodes=@(0)) {
  $before = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { $out = & $Exe @Arguments 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $before }
  $out | Add-Content -LiteralPath $log
  if ($code -notin $SuccessCodes) { throw "Build command failed ($code): $Exe $($Arguments -join ' '); see $log" }
  return (($out | Out-String).Trim())
}

# New CommonLib projects need Xmake 3; a filename alone cannot prove that capability.
function Get-XmakeVersion([string]$Executable) {
  $output=[regex]::Replace((Run-Build $Executable @('--version')),([char]27+'\[[0-9;]*m'),'')
  if ($output -notmatch '(?m)^xmake v(\d+\.\d+\.\d+)(?:[+,\s]|$)') { throw 'Cannot verify the installed Xmake version.' }
  $version=[version]$Matches[1]
  if ($version -lt [version]'3.0.0') { throw 'Xmake 3.0.0 or newer is required; update it through its installation owner.' }
  return $version.ToString()
}

# Existing packages update through their owner; no second installation is created.
function Invoke-BuildPackageUpgrade([string]$Package) {
  $before=$ErrorActionPreference; $ErrorActionPreference='Continue'
  try {
    $output=& winget upgrade --id $Package --exact --source winget --silent --accept-package-agreements --accept-source-agreements --disable-interactivity 2>&1
    return @{code=$LASTEXITCODE;output=($output | Out-String)}
  } finally { $ErrorActionPreference=$before }
}
function Update-BuildPackage([string]$Package) {
  if ($CheckOnly -or $Offline -or $NoUpdate) { return }
  if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw 'winget is required to verify/update managed compiler packages.' }
  $result=Invoke-BuildPackageUpgrade $Package
  Add-Content -LiteralPath $log -Value $result.output
  $hex='{0:X8}' -f [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$result.code),0)
  if ($result.code -in @(0,3010) -or $hex -eq '8A15002B') { return }
  if ($hex -eq '8A150014') {
    Write-Warning "$Package is not registered with winget; the existing copy is preserved and update status is unverified."
    return
  }
  throw "Managed package update failed: $Package ($hex). See $log"
}

# Stage Go so an interrupted extraction cannot poison its stable install path.
function Install-GoArchive([string]$Archive,[string]$Cache,[string]$ExpectedVersion) {
  $stage=$Cache+'.stage-'+[guid]::NewGuid().ToString('N')
  try {
    $goPath=Join-Path $Cache 'go\bin\go.exe'
    if (Test-Path -LiteralPath $Cache) {
      if (-not (Test-Path -LiteralPath $goPath) -or (Get-GoVersion $goPath) -ne $ExpectedVersion) { throw "Existing Go cache needs inspection: $Cache" }
      return $goPath
    }
    Expand-Archive -LiteralPath $Archive -DestinationPath $stage
    $stagedGo=Join-Path $stage 'go\bin\go.exe'
    if ((Get-GoVersion $stagedGo) -ne $ExpectedVersion) { throw 'Staged Go version mismatch.' }
    Move-Item -LiteralPath $stage -Destination $Cache
    return $goPath
  } finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
}
# Probe the selected SDK itself, without project settings or automatic toolchain downloads.
function Run-LocalGo([string]$Executable,[string[]]$Arguments) {
  $settings=@{GOENV='off';GOTOOLCHAIN='local';GOWORK='off';GOROOT=$null;GOFLAGS=$null;GOOS='windows';GOARCH='amd64'}
  $saved=@{}
  try {
    foreach ($name in $settings.Keys) { $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process'); [Environment]::SetEnvironmentVariable($name,$settings[$name],'Process') }
    return (Run-Build $Executable $Arguments)
  } finally { foreach ($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') } }
}
function Get-GoVersion([string]$Executable) {
  $value=Run-LocalGo $Executable @('version')
  if ($value -notmatch '^go version (go\d+\.\d+(?:\.\d+)?(?:(?:beta|rc)\d+)?|devel .+) [^ ]+/[^ ]+$') { throw 'Cannot verify the installed Go version.' }
  return $Matches[1]
}
# A newer release candidate or development SDK is never downgraded to today's stable release.
function Test-GoUpdateRequired([string]$Installed,[string]$Stable) {
  if ($Stable -notmatch '^go(\d+)\.(\d+)(?:\.(\d+))?$') { throw 'Invalid official Go stable version.' }
  $latest=[version]::new([int]$Matches[1],[int]$Matches[2],[int]$Matches[3])
  if ($Installed -like 'devel *') { return $false }
  if ($Installed -notmatch '^go(\d+)\.(\d+)(?:\.(\d+))?((?:beta|rc)\d+)?$') { throw 'Cannot compare the installed Go version.' }
  $current=[version]::new([int]$Matches[1],[int]$Matches[2],[int]$Matches[3])
  return ($current -lt $latest -or ($current -eq $latest -and [bool]$Matches[4]))
}
# Only shared SDKs selected by this suite are mutable; project/version pins remain separate.
function Test-GoSharedSdk([string]$Executable) {
  $path=[IO.Path]::GetFullPath($Executable)
  foreach ($known in @((Join-Path $env:ProgramFiles 'Go\bin\go.exe'),(Join-Path $stateRoot 'toolchains\go-current\go\bin\go.exe'))) {
    if ($path -ieq [IO.Path]::GetFullPath($known)) { return $true }
  }
  $receiptPath=Join-Path $stateRoot 'build-tools.json'
  if (Test-Path -LiteralPath $receiptPath) {
    $receipt=[IO.File]::ReadAllText($receiptPath) | ConvertFrom-Json
    $cacheRoot=[IO.Path]::GetFullPath((Join-Path $stateRoot 'toolchains')).TrimEnd('\')+'\'
    if ($receipt.result -eq 'PASS' -and ($receipt.go_update_managed -eq $true -or $receipt.version -eq '1.0.0') -and $receipt.compile_run -contains 'go' -and $receipt.go -and $path.StartsWith($cacheRoot,[StringComparison]::OrdinalIgnoreCase) -and $path -ieq [IO.Path]::GetFullPath($receipt.go)) { return $true }
  }
  return $false
}
function Update-GoArchive([string]$Archive,[string]$Executable,[string]$ExpectedVersion) {
  if (-not (Test-GoSharedSdk $Executable)) { throw 'Project or externally managed Go SDK preserved; update it through its owner.' }
  if (-not (Test-GoUpdateRequired (Get-GoVersion $Executable) $ExpectedVersion)) { return $Executable }
  $sdk=[IO.Path]::GetFullPath((Split-Path -Parent (Split-Path -Parent $Executable)))
  if (-not (Test-Path -LiteralPath (Join-Path $sdk 'VERSION')) -or -not (Test-Path -LiteralPath (Join-Path $sdk 'LICENSE')) -or $sdk.TrimEnd('\') -eq [IO.Path]::GetPathRoot($sdk).TrimEnd('\')) { throw 'Unrecognized Go SDK layout; existing files were preserved.' }
  $ancestor=Get-Item -LiteralPath $Executable -Force
  while ($ancestor) {
    if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Go SDK is a link; update it through its owner.' }
    $ancestor=if ($ancestor -is [IO.FileInfo]) { $ancestor.Directory } else { $ancestor.Parent }
  }
  $stage=$sdk+'.stage-'+[guid]::NewGuid().ToString('N')
  $backup=$sdk+'.backup-'+[guid]::NewGuid().ToString('N')
  try {
    Expand-Archive -LiteralPath $Archive -DestinationPath $stage
    $incoming=Join-Path $stage 'go'
    if ((Get-GoVersion (Join-Path $incoming 'bin\go.exe')) -ne $ExpectedVersion) { throw 'Go update version mismatch.' }
    Move-Item -LiteralPath $sdk -Destination $backup
    $published=$false
    try {
      [IO.Directory]::Move($incoming,$sdk)
      $published=$true
      if ((Get-GoVersion (Join-Path $sdk 'bin\go.exe')) -ne $ExpectedVersion) { throw 'Published Go update version mismatch.' }
    } catch {
      if ($published) { Remove-Item -LiteralPath $sdk -Recurse -Force }
      if (Test-Path -LiteralPath $sdk) { throw "Go rollback blocked by another directory at $sdk; original SDK retained at $backup" }
      [IO.Directory]::Move($backup,$sdk)
      throw
    }
    Write-Host "Go updated in place; previous SDK retained: $backup"
    return (Join-Path $sdk 'bin\go.exe')
  } finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force } }
}
function Test-WindowsSdk {
  $sdk=Join-Path ${env:ProgramFiles(x86)} 'Windows Kits\10'
  foreach ($header in @(Get-ChildItem -Path (Join-Path $sdk 'Include\*\um\Windows.h') -File -ErrorAction SilentlyContinue)) {
    $version=Split-Path -Leaf (Split-Path -Parent $header.DirectoryName)
    if (Test-Path -LiteralPath (Join-Path $sdk ('Lib\'+$version+'\um\x64\kernel32.lib'))) { return $true }
  }
  return $false
}

$env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1'
$env:DOTNET_CLI_WORKLOAD_UPDATE_NOTIFY_DISABLE='1'
$work = Join-Path ([IO.Path]::GetTempPath()) ('uabs-build-proof-' + [guid]::NewGuid().ToString('N'))
try {
  if (-not $CheckOnly -and -not $Offline -and -not $NoUpdate) {
    foreach ($package in @('Kitware.CMake','Xmake-io.Xmake','Microsoft.DotNet.SDK.10','BrechtSanders.WinLibs.POSIX.UCRT')) { Update-BuildPackage $package }
    $node=Find-BuildCommand 'node.exe'
    if ($node) {
      $nodeMajor=(Run-Build $node @('--version')).TrimStart('v').Split('.')[0]
      Update-BuildPackage $(if ([int]$nodeMajor -ge 26) { 'OpenJS.NodeJS' } else { 'OpenJS.NodeJS.LTS' })
    }
    $rustup=Find-BuildCommand 'rustup.exe' @((Join-Path $env:USERPROFILE '.cargo\bin\rustup.exe'))
    if ($rustup) { Run-Build $rustup @('update','stable') | Out-Null }
    Refresh-ProcessPath
  }
  $rust = Require-BuildCommand 'rustc.exe' 'Rustlang.Rustup' @((Join-Path $env:USERPROFILE '.cargo\bin\rustc.exe'))
  $cargo = Require-BuildCommand 'cargo.exe' 'Rustlang.Rustup' @((Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'))
  $cmake = Require-BuildCommand 'cmake.exe' 'Kitware.CMake' @((Join-Path $env:ProgramFiles 'CMake\bin\cmake.exe'))
  $xmake = Require-BuildCommand 'xmake.exe' 'Xmake-io.Xmake' @((Join-Path $env:ProgramFiles 'xmake\xmake.exe'))
  $xmakeVersion=Get-XmakeVersion $xmake
  $dotnet = Require-BuildCommand 'dotnet.exe' 'Microsoft.DotNet.SDK.10' @((Join-Path $env:ProgramFiles 'dotnet\dotnet.exe'))
  if (-not (@(& $dotnet --list-sdks) -match '^10\.')) {
    if ($CheckOnly -or $Offline -or -not (Install-UabsWinget @('Microsoft.DotNet.SDK.10'))) { throw '.NET 10 SDK missing (a runtime alone cannot compile).' }
  }
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  $vs = if (Test-Path -LiteralPath $vswhere) { & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath }
  if (-not $vs) {
    if ($CheckOnly -or $Offline) { throw 'MSVC C++ tools and Windows SDK missing.' }
    # includeRecommended installs the Windows SDK as part of the C++ workload.
    & winget install --id Microsoft.VisualStudio.BuildTools --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity --override '--wait --quiet --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended' | Out-Host
    if ($LASTEXITCODE -notin @(0,3010)) { throw "MSVC installation failed: $LASTEXITCODE" }
    $vs = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  }
  if (-not $vs) { throw 'MSVC workload still missing after setup; see the Visual Studio Installer.' }
  if (-not $CheckOnly -and -not $Offline -and -not $NoUpdate) {
    $product=@(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property productId) | Select-Object -First 1
    $major=@(& $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationVersion) | Select-Object -First 1
    $edition=([string]$product -split '\.')[-1]
    if ($edition -in @('BuildTools','Community','Professional','Enterprise')) {
      Update-BuildPackage $(if ([version]$major -ge [version]'18.0') { 'Microsoft.VisualStudio.'+$edition } else { 'Microsoft.VisualStudio.2022.'+$edition })
    }
  }
  if (-not (Test-WindowsSdk)) {
    if ($CheckOnly -or $Offline) { throw 'Windows SDK headers/libraries missing.' }
    $setup=Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
    Run-Build $setup @('modify','--installPath',$vs,'--add','Microsoft.VisualStudio.Workload.VCTools','--includeRecommended','--quiet','--norestart') -SuccessCodes @(0,3010) | Out-Null
    if (-not (Test-WindowsSdk)) { throw 'Windows SDK still missing after workload repair; see Visual Studio Installer.' }
  }
  $ninja = Require-BuildCommand 'ninja.exe' 'Ninja-build.Ninja' @((Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'), (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ninja.exe'))
  if (-not $ninja.StartsWith($vs.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)) { Update-BuildPackage 'Ninja-build.Ninja' }
  $gccCandidates=@(Get-ChildItem -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\BrechtSanders.WinLibs.POSIX.UCRT_*\mingw64\bin\gcc.exe') -File -ErrorAction SilentlyContinue | ForEach-Object FullName)
  $gcc=Require-BuildCommand 'gcc.exe' 'BrechtSanders.WinLibs.POSIX.UCRT' $gccCandidates
  $goCandidates=@((Join-Path $env:ProgramFiles 'Go\bin\go.exe'),(Join-Path $stateRoot 'toolchains\go-current\go\bin\go.exe'))
  $previousReceipt=Join-Path $stateRoot 'build-tools.json'
  if (Test-Path -LiteralPath $previousReceipt) { $goCandidates+=([string]([IO.File]::ReadAllText($previousReceipt) | ConvertFrom-Json).go) }
  $go = Find-BuildCommand 'go.exe' $goCandidates
  $goShared=$go -and (Test-GoSharedSdk $go)
  if (-not $go -or (-not $CheckOnly -and -not $Offline -and -not $NoUpdate)) {
    # The official Go manifest carries the current stable archive's checksum.
    if ($CheckOnly -or $Offline) { throw 'Go compiler missing; provision it online once.' }
    $releases = Invoke-RestMethod 'https://go.dev/dl/?mode=json' -UseBasicParsing
    $release = $releases | Where-Object stable | Select-Object -First 1
    $asset = @($release.files | Where-Object { $_.os -eq 'windows' -and $_.arch -eq 'amd64' -and $_.kind -eq 'archive' }) | Select-Object -First 1
    if (-not $asset -or $asset.filename -notmatch '^go[\d.]+\.windows-amd64\.zip$' -or $asset.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid official Go download metadata.' }
    $have=if($go){Get-GoVersion $go}else{$null}
    $needGo=-not $go -or (Test-GoUpdateRequired $have $release.version)
    if ($needGo -and $go -and -not $goShared) { Write-Warning "Go $have is project or externally managed; preserved $go. Update status is unverified."; $needGo=$false }
    $cache = Join-Path $stateRoot 'toolchains\go-current'
    $zip = $cache + '.zip'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $cache) | Out-Null
    if ($needGo) {
      Invoke-WebRequest ('https://go.dev/dl/' + $asset.filename) -OutFile $zip -UseBasicParsing
      if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ine $asset.sha256) { throw 'Go archive checksum mismatch.' }
      if ($go) { $go=Update-GoArchive -Archive $zip -Executable $go -ExpectedVersion $release.version }
      else { $go=Install-GoArchive -Archive $zip -Cache $cache -ExpectedVersion $release.version; $goShared=$true }
    }
  }
  if ($goShared) { Add-BuildPath (Split-Path -Parent $go) }
  New-Item -ItemType Directory -Path $work | Out-Null
  Push-Location -LiteralPath $work
  try {
    # Run compiled programs: a version banner does not prove headers/linkers work.
    [IO.File]::WriteAllText((Join-Path $work 'hello.go'), 'package main; import "fmt"; func main(){fmt.Print("uabs-build-ok")}')
    Run-LocalGo $go @('build','-o','go-proof.exe','hello.go') | Out-Null
    if ((Run-Build (Join-Path $work 'go-proof.exe') @()) -ne 'uabs-build-ok') { throw 'Go smoke output mismatch.' }
    [IO.File]::WriteAllText((Join-Path $work 'hello.rs'), 'fn main(){print!("uabs-build-ok");}')
    [IO.File]::WriteAllText((Join-Path $work 'hello.c'), '#include <stdio.h>' + "`n" + 'int main(){printf("uabs-build-ok");return 0;}')
    Run-Build $gcc @('hello.c','-o','gcc-proof.exe') | Out-Null
    if ((Run-Build (Join-Path $work 'gcc-proof.exe') @()) -ne 'uabs-build-ok') { throw 'GCC smoke output mismatch.' }
    Run-Build $rust @('hello.rs','-o','rust-proof.exe') | Out-Null
    if ((Run-Build (Join-Path $work 'rust-proof.exe') @()) -ne 'uabs-build-ok') { throw 'Rust smoke output mismatch.' }
    [IO.File]::WriteAllText((Join-Path $work 'NuGet.Config'), '<configuration><packageSources><clear /></packageSources></configuration>')
    Run-Build $dotnet @('new','console','--framework','net10.0','--no-restore','-o','dotnet-proof') | Out-Null
    Run-Build $dotnet @('build','dotnet-proof','--nologo') | Out-Null
    if ((Run-Build $dotnet @('dotnet-proof\bin\Debug\net10.0\dotnet-proof.dll')) -ne 'Hello, World!') { throw '.NET smoke output mismatch.' }
    [IO.File]::WriteAllText((Join-Path $work 'hello.cpp'), ('#include <windows.h>' + "`n" + '#include <iostream>' + "`n" + 'int main(){std::cout << (GetCurrentProcessId() ? "uabs-build-ok" : "failed");}'))
    [IO.File]::WriteAllText((Join-Path $work 'CMakeLists.txt'), "cmake_minimum_required(VERSION 3.20)`nproject(UabsProof LANGUAGES CXX)`nadd_executable(cpp-proof hello.cpp)`n")
    $devcmd = Join-Path $vs 'Common7\Tools\VsDevCmd.bat'
    # A batch file keeps cmd quoting local; no user path is interpreted as code.
    $batch = Join-Path $work 'compile.cmd'
    $body = @('@echo off', 'setlocal DisableDelayedExpansion', ('call "{0}" -arch=x64 -host_arch=x64 >nul' -f $devcmd.Replace('%','%%')), 'if errorlevel 1 exit /b 1', ('"{0}" -S . -B cpp-build -G Ninja -DCMAKE_CXX_COMPILER=cl.exe "-DCMAKE_MAKE_PROGRAM={1}"' -f $cmake.Replace('%','%%'),$ninja.Replace('%','%%')), 'if errorlevel 1 exit /b 1', ('"{0}" --build cpp-build' -f $cmake.Replace('%','%%')))
    [IO.File]::WriteAllLines($batch, $body, [Text.Encoding]::Default)
    Run-Build $env:ComSpec @('/d','/v:off','/c','compile.cmd') | Out-Null
    if ((Run-Build (Join-Path $work 'cpp-build\cpp-proof.exe') @()) -ne 'uabs-build-ok') { throw 'C++/Windows SDK smoke output mismatch.' }
    # No dependencies are requested: this verifies the build system without changing a user's project.
    $xmakeWork=Join-Path $work 'xmake-proof'
    New-Item -ItemType Directory -Path $xmakeWork | Out-Null
    Copy-Item -LiteralPath (Join-Path $work 'hello.cpp') -Destination $xmakeWork
    [IO.File]::WriteAllText((Join-Path $xmakeWork 'xmake.lua'), "set_xmakever('3.0.0')`nset_languages('c++23')`ntarget('xmake-proof')`nset_kind('binary')`nset_targetdir('bin')`nadd_files('hello.cpp')`n")
    Push-Location -LiteralPath $xmakeWork
    try {
      Run-Build $xmake @('f','-y','-p','windows','-a','x64','--toolchain=msvc') | Out-Null
      Run-Build $xmake @('build','-y') | Out-Null
      if ((Run-Build (Join-Path $xmakeWork 'bin\xmake-proof.exe') @()) -ne 'uabs-build-ok') { throw 'Xmake C++23/MSVC smoke output mismatch.' }
    } finally { Pop-Location }
  } finally { Pop-Location }
  $receipt = [ordered]@{ schema=1; version=$suiteVersion; result='PASS'; verified_at=(Get-Date -Format o); go=$go; go_update_managed=[bool]$goShared; gcc=$gcc; rust=$rust; cargo=$cargo; cmake=$cmake; xmake=$xmake; xmake_version=$xmakeVersion; ninja=$ninja; dotnet=$dotnet; visual_studio=$vs; compile_run=@('go','gcc','rust','dotnet10','cmake-ninja-msvc-windows-sdk','xmake-cpp23-msvc') }
  $receipt | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $stateRoot 'build-tools.json') -Encoding UTF8
  Write-Host "BUILD TOOLS: PASS (Go, GCC, Rust, .NET, CMake/Ninja, Xmake, MSVC and Windows SDK compiled and ran). Log: $log"
} catch {
  Add-Content -LiteralPath $log -Value ("$(Get-Date -Format o) failure=" + $_.Exception.Message)
  throw
} finally {
  if (Test-UabsPathWithin -Path $work -Root ([IO.Path]::GetTempPath())) { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
}
