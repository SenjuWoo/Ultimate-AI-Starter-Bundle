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
  'SHARED PYTHON GATE: PASS'
} finally {
  foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
  if(Test-Path -LiteralPath $fixture){
    if(-not [IO.Path]::GetFullPath($fixture).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe fixture cleanup path'}
    Remove-Item -LiteralPath $fixture -Recurse -Force
  }
}
