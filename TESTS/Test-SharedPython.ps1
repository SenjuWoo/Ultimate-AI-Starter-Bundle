# Real interpreter/process-scope tests: shared selection, idempotence and failure preservation.
param([string]$PackRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference='Stop'
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$keys=@('Path','UABS_PYTHON','UV_PYTHON','UV_PYTHON_DOWNLOADS','PYTHONUTF8','PYTHON_MANAGER_DEFAULT','PYTHON_MANAGER_AUTOMATIC_INSTALL')
$saved=@{}; foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('uabs-shared-python-'+[guid]::NewGuid().ToString('N'))
try {
  $python=Get-UabsPythonExecutable
  if(-not $python){throw 'This gate needs a real base Python.'}
  & (Join-Path $PackRoot 'TOOLS\Set-SharedPython.ps1') -Python $python -Apply -Scope Process | Out-Null
  if($env:UABS_PYTHON -ine $python -or $env:UV_PYTHON -ine $python -or $env:UV_PYTHON_DOWNLOADS -ne 'never'){throw 'Shared environment was not configured.'}
  if((Get-UabsPythonExecutable) -ine $python){throw 'Resolver ignored the selected runtime.'}
  $uvxArgs = @(Resolve-UabsUvPythonArgs -Command 'uvx' -Arguments @('--python','3.11','--from','fixture-package','fixture-cli','--python','child-value'))
  if (($uvxArgs -join '|') -cne ((@('--python',$python,'--no-python-downloads','--from','fixture-package','fixture-cli','--python','child-value')) -join '|')) { throw 'uvx changed child options or retained its old runner Python.' }
  $uvArgs = @(Resolve-UabsUvPythonArgs -Command 'uv.exe' -Arguments @('tool','install','-p','3.13','--force','fixture-package'))
  if (($uvArgs -join '|') -cne ((@('tool','install','--python',$python,'--no-python-downloads','--force','fixture-package')) -join '|')) { throw 'uv tool install ignored shared Python.' }
  $untouched = @(Resolve-UabsUvPythonArgs -Command 'other.exe' -Arguments @('--python','child-value'))
  if (($untouched -join '|') -cne '--python|child-value') { throw 'Non-uv command was changed.' }
  $beforePath = $saved['Path'] -split ';'
  $baseDir = Split-Path -Parent $python
  $bare = @(Get-UabsNativeStdout -Exe 'python' -CmdArgs @('-I','-c','import json,sys;print(json.dumps(sys.executable))'))
  if ($LASTEXITCODE -eq 0 -and [string]($bare[-1] | ConvertFrom-Json) -ieq $python -and $beforePath -notcontains $baseDir -and ($env:Path -split ';') -contains $baseDir) { throw 'Setup unnecessarily pinned a working default to a version-specific PATH entry.' }
  $first=$env:Path
  & (Join-Path $PackRoot 'TOOLS\Set-SharedPython.ps1') -Python $python -Apply -Scope Process | Out-Null
  if($env:Path -cne $first){throw 'Repeated selection duplicated PATH entries.'}
  $env:UABS_PYTHON=Join-Path $fixture 'missing.exe'
  $refused=$false
  try{$null=Get-UabsPythonExecutable}catch{$refused=$_.Exception.Message -match 'Configured UABS_PYTHON'}
  if(-not $refused){throw 'Missing selected runtime silently fell back to another Python.'}
  # An explicit repair follows working PATH without trusting a stale binding.
  & (Join-Path $PackRoot 'TOOLS\Set-SharedPython.ps1') -Apply -Scope Process | Out-Null
  if ($env:UABS_PYTHON -ine $python) { throw 'Shared runtime repair did not recover the working user Python.' }
  & $python -m venv --without-pip $fixture
  if($LASTEXITCODE -ne 0){throw 'Fixture venv failed.'}
  $refused=$false
  try { & (Join-Path $PackRoot 'TOOLS\Set-SharedPython.ps1') -Python (Join-Path $fixture 'Scripts\python.exe') -Apply -Scope Process | Out-Null }
  catch {$refused=$_.Exception.Message -match 'base Python'}
  if(-not $refused -or $env:Path -cne $first){throw 'Virtual environment was accepted as a shared base or changed PATH.'}
  # A junction tests a real Unicode base path without copying a runtime.
  $aliasRoot = Join-Path $fixture 'unicode-base'
  New-Item -ItemType Directory -Path $aliasRoot | Out-Null
  $runtimeAlias = Join-Path $aliasRoot ('shared Python ' + [char]0x2603)
  New-Item -ItemType Junction -Path $runtimeAlias -Target (Split-Path -Parent $python) | Out-Null
  try {
    $aliasPython = Join-Path $runtimeAlias 'python.exe'
    $env:UABS_PYTHON = $aliasPython
    if ((Get-UabsPythonExecutable) -ine $aliasPython) { throw 'Unicode selected Python was not resolved.' }
    $env:UABS_PYTHON = $null; $env:Path = $runtimeAlias + ';' + $first
    if ((Get-UabsPythonExecutable) -ine $aliasPython) { throw 'Unicode PATH Python was not resolved.' }
    & (Join-Path $PackRoot 'TOOLS\Set-SharedPython.ps1') -Python $aliasPython -Apply -Scope Process | Out-Null
  } finally {
    $env:UABS_PYTHON = $python; $env:UV_PYTHON = $python; $env:Path = $first
    if ((Get-Item -LiteralPath $runtimeAlias).LinkType -ne 'Junction') { throw 'Unexpected runtime alias type; cleanup refused.' }
    [IO.Directory]::Delete($runtimeAlias)
  }
  $fakeHermes = Join-Path $fixture 'hermes-fixture.ps1'
  $fakeScript = 'param([string]$Operation,[string]$ModuleFlag,[string]$Module)
$code = "import sys,runpy;runpy.run_module(''$Module'', run_name=''__main__'', alter_sys=True)"
ConvertTo-Json -Compress -InputObject @($env:UABS_PYTHON,''-I'',''-c'',$code)
$global:LASTEXITCODE = 0
'
  [IO.File]::WriteAllText($fakeHermes, $fakeScript, (New-Object Text.UTF8Encoding $true))
  $output = @(Invoke-UabsHermesPython -HermesExe $fakeHermes -PythonArgs @('-c','import sys;print(sys.argv[1])','space + Unicode ☃'))
  if ($LASTEXITCODE -ne 0 -or $output[-1] -cne 'space + Unicode ☃') { throw 'Modern Hermes runtime adapter changed arguments.' }
  $null = Invoke-UabsHermesPython -HermesExe $fakeHermes -PythonArgs @('-c','raise SystemExit(7)')
  if ($LASTEXITCODE -ne 7) { throw 'Hermes runtime adapter lost the child failure exit code.' }

  # Exercise the full User branch with an in-memory registry boundary. Never
  # write the test runner's real User environment or a real Hermes config.
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
public static class UabsSharedPythonTestEnvironment {
  private static Dictionary<string,string> values = new Dictionary<string,string>(StringComparer.OrdinalIgnoreCase);
  public static string GetEnvironmentVariable(string name, string target) {
    string value; return values.TryGetValue(target + ":" + name, out value) ? value : null;
  }
  public static void SetEnvironmentVariable(string name, string value, string target) {
    values[target + ":" + name] = value;
  }
  public static string ExpandEnvironmentVariables(string value) { return Environment.ExpandEnvironmentVariables(value); }
}
'@
  foreach ($key in $keys) {
    [UabsSharedPythonTestEnvironment]::SetEnvironmentVariable($key,[Environment]::GetEnvironmentVariable($key,'Process'),'Process')
  }
  $fakeUserPath = Join-Path $fixture 'personal-user-bin'
  [UabsSharedPythonTestEnvironment]::SetEnvironmentVariable('Path',$fakeUserPath,'User')
  [UabsSharedPythonTestEnvironment]::SetEnvironmentVariable('Path',((Split-Path -Parent $python) + ';' + $env:SystemRoot + '\System32'),'Machine')
  [UabsSharedPythonTestEnvironment]::SetEnvironmentVariable('PYTHON_MANAGER_DEFAULT','keep-my-manager-version','User')
  $bindingTools = Join-Path $fixture 'binding-tools'
  [void][IO.Directory]::CreateDirectory($bindingTools)
  $sharedSource = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\Set-SharedPython.ps1'))
  $sharedClone = Join-Path $bindingTools 'Set-SharedPython.ps1'
  [IO.File]::WriteAllText($sharedClone,$sharedSource.Replace('[Environment]::','[UabsSharedPythonTestEnvironment]::'),(New-Object Text.UTF8Encoding $true))
  $commonPath = (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1').Replace("'","''")
  $fakeState = (Join-Path $fixture 'user-state').Replace("'","''")
  $commonShim = ". '$commonPath'`nfunction Refresh-ProcessPath { `$env:Path = [UabsSharedPythonTestEnvironment]::GetEnvironmentVariable('Path','Machine') + ';' + [UabsSharedPythonTestEnvironment]::GetEnvironmentVariable('Path','User') }`nfunction Get-UabsStateRoot { return '$fakeState' }`n"
  [IO.File]::WriteAllText((Join-Path $bindingTools 'UABS-Common.ps1'),$commonShim,(New-Object Text.UTF8Encoding $true))
  $bindingMarker = Join-Path $fixture 'hermes-binding-marker.txt'
  $hermesShim = "[IO.File]::AppendAllText('$($bindingMarker.Replace("'","''"))','bound')"
  [IO.File]::WriteAllText((Join-Path $bindingTools 'Set-HermesSharedPython.ps1'),$hermesShim,(New-Object Text.UTF8Encoding $true))
  & $sharedClone -Python $python -Apply -Scope User | Out-Null
  if (-not (Test-Path -LiteralPath $bindingMarker) -or [IO.File]::ReadAllText($bindingMarker) -cne 'bound') { throw 'Direct User setup stopped binding Hermes by default.' }
  [IO.File]::Delete($bindingMarker)
  & $sharedClone -Python $python -Apply -Scope User -SkipHermesBinding | Out-Null
  if (Test-Path -LiteralPath $bindingMarker) { throw 'Skipping Hermes binding still ran the Hermes configuration writer.' }
  if ([UabsSharedPythonTestEnvironment]::GetEnvironmentVariable('UABS_PYTHON','User') -ine $python -or
      [UabsSharedPythonTestEnvironment]::GetEnvironmentVariable('UV_PYTHON','User') -ine $python -or
      [UabsSharedPythonTestEnvironment]::GetEnvironmentVariable('UV_PYTHON_DOWNLOADS','User') -cne 'never') { throw 'Skipping Hermes prevented shared User runtime setup.' }
  if ([UabsSharedPythonTestEnvironment]::GetEnvironmentVariable('Path','User') -cne $fakeUserPath -or
      [UabsSharedPythonTestEnvironment]::GetEnvironmentVariable('PYTHON_MANAGER_DEFAULT','User') -cne 'keep-my-manager-version') { throw 'User setup changed unrelated PATH or manager version preferences.' }
  'SHARED PYTHON GATE: PASS'
} finally {
  foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
  if(Test-Path -LiteralPath $fixture){
    if(-not [IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup path'}
    if ($runtimeAlias -and (Test-Path -LiteralPath $runtimeAlias)) { throw 'Runtime junction remains; recursive fixture cleanup refused.' }
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}
