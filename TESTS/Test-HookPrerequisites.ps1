# Exercise shell discovery and the actual Windows-to-Git-shell boundary.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hook-shell-' + [guid]::NewGuid().ToString('N'))
$savedPath = $env:PATH
try {
  $gitRoot = Join-Path $fixture ('Git space [x] ' + [char]0xE9)
  $git = Join-Path $gitRoot 'cmd\git.exe'
  $shell = Join-Path $gitRoot 'bin'
  New-Item -ItemType Directory -Path (Split-Path -Parent $git),$shell -Force | Out-Null
  [IO.File]::WriteAllText($git, '')
  Assert (-not (Get-UabsGitShellDirectory -GitExecutable $git)) 'An incomplete Git install was accepted.'
  [IO.File]::WriteAllText((Join-Path $shell 'bash.exe'), '')
  Assert (-not (Get-UabsGitShellDirectory -GitExecutable $git)) 'bash alone does not satisfy sh hooks.'
  [IO.File]::WriteAllText((Join-Path $shell 'sh.exe'), '')
  Assert ((Get-UabsGitShellDirectory -GitExecutable $git) -ceq $shell) 'Nondefault Unicode Git path was not resolved.'
  # Git Bash and "Unix tools on PATH" installs resolve git from mingw64\bin.
  $mingwGit = Join-Path $gitRoot 'mingw64\bin\git.exe'
  New-Item -ItemType Directory -Path (Split-Path -Parent $mingwGit) -Force | Out-Null
  [IO.File]::WriteAllText($mingwGit, '')
  Assert ((Get-UabsGitShellDirectory -GitExecutable $mingwGit) -ceq $shell) 'git.exe under mingw64\bin did not resolve the Git shells.'
  Assert (-not (Get-UabsGitShellDirectory -GitExecutable (Join-Path $fixture 'missing\git.exe'))) 'A missing Git executable was accepted.'
  $second = Join-Path $fixture 'other Git\cmd'
  New-Item -ItemType Directory -Path $second -Force | Out-Null
  [IO.File]::WriteAllText((Join-Path $second 'git.exe'), '')
  $env:PATH = (Split-Path -Parent $git) + ';' + $second + ';' + $savedPath
  Assert ((Get-UabsGitShellDirectory) -ceq $shell) 'Multiple Git commands were concatenated instead of resolving one shell directory.'

  # No registry writes in tests. CheckOnly must neither change PATH nor create
  # a backup, even when the prerequisite is absent from the current process.
  $env:PATH = $env:SystemRoot + '\System32'
  $before = $env:PATH
  $issues = @(Repair-UabsHookShellPath -GitExecutable $git -CheckOnly)
  Assert ($issues.Count -eq 1 -and $env:PATH -ceq $before) 'Read-only shell check changed PATH or missed the gap.'
  $env:PATH = $shell + ';' + $env:PATH
  Assert (@(Repair-UabsHookShellPath -GitExecutable $git -CheckOnly).Count -eq 0) 'Available Git shells were reported missing.'
  # WSL puts bash.exe in System32. Only the first match on PATH runs.
  $wsl = Join-Path $fixture 'wsl\System32'
  New-Item -ItemType Directory -Force -Path $wsl | Out-Null
  [IO.File]::WriteAllText((Join-Path $wsl 'bash.exe'), '')
  $env:PATH = $shell + ';' + $wsl + ';' + $env:SystemRoot + '\System32'
  Assert (@(Repair-UabsHookShellPath -GitExecutable $git -CheckOnly).Count -eq 0) 'A later WSL bash.exe hid the Git shell that runs first.'
  $env:PATH = $wsl + ';' + $shell + ';' + $env:SystemRoot + '\System32'
  Assert (@(Repair-UabsHookShellPath -GitExecutable $git -CheckOnly).Count -eq 1) 'A WSL bash.exe ahead of Git was accepted as the hook shell.'
  $env:PATH = $savedPath

  # Hooks must not be wired to an AI app's private Python (inherited first on
  # PATH when the installer runs inside Codex); it moves on every app update.
  Assert (Test-UabsPrivateRuntimePath 'C:\Users\u\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe') 'Codex private runtime not recognized.'
  Assert (-not (Test-UabsPrivateRuntimePath 'C:\Users\u\AppData\Local\Programs\Python\Python312\python.exe')) 'A user Python was treated as private.'
  $realPy = Get-UabsPythonExecutable
  if ($realPy) {
    $savedLocal = $env:LOCALAPPDATA; $savedForge = $env:SKYRIM_FORGE_PYTHON
    try {
      $private = Join-Path $fixture '.cache\codex-runtimes\rt'
      New-Item -ItemType Directory -Path (Split-Path -Parent $private) -Force | Out-Null
      New-Item -ItemType Junction -Path $private -Target (Split-Path -Parent $realPy) | Out-Null
      $env:LOCALAPPDATA = Join-Path $fixture 'empty local'
      $env:SKYRIM_FORGE_PYTHON = Join-Path $private (Split-Path -Leaf $realPy)
      $env:PATH = $env:SystemRoot + '\System32'
      Assert (Test-UabsPrivateRuntimePath (Get-UabsPythonExecutable)) 'The only Python available (private) was not used as a fallback.'
      $env:PATH = (Split-Path -Parent $realPy) + ';' + $env:PATH
      $chosen = Get-UabsPythonExecutable
      Assert ($chosen -and -not (Test-UabsPrivateRuntimePath $chosen)) ('A private app runtime beat a user Python: ' + $chosen)
    } finally {
      $env:LOCALAPPDATA = $savedLocal; $env:SKYRIM_FORGE_PYTHON = $savedForge; $env:PATH = $savedPath
      if (Test-Path -LiteralPath $private) { [IO.Directory]::Delete($private) }
    }
  }

  # Characterize the original bug with a real Git shell, when installed.
  $actual = Get-UabsGitShellDirectory
  if ($actual) {
    $env:PATH = $actual + ';' + $savedPath
    $output = & powershell.exe -NoProfile -Command "sh -c 'printf shell-ok'" 2>&1 | Out-String
    Assert ($LASTEXITCODE -eq 0 -and $output.Trim() -ceq 'shell-ok') 'PowerShell cannot launch the prerequisite shell.'
    Write-Host 'HOOK SHELL RUNTIME: PASS'
  } else { Write-Host 'HOOK SHELL RUNTIME: SKIP (Git for Windows not installed)' }
  Write-Host 'HOOK PREREQUISITES GATE: PASS'
} finally {
  $env:PATH = $savedPath
  if (Test-UabsPathWithin -Path $fixture -Root ([IO.Path]::GetTempPath())) {
    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
  }
}
