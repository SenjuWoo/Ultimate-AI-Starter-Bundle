<#
FAST verification: syntax and schema checks on changed files only.

This is the inner loop, not a release gate. It never replaces `Test-Pack.ps1`
or CI; optional linters are used only when already installed, so a fresh clone
needs nothing but PowerShell and Python. Results are cached by content hash in
`.uabs-cache/verify/` (gitignored) so re-running on the same tree is free.

    .\TOOLS\Verify-Fast.ps1              # changed files vs HEAD
    .\TOOLS\Verify-Fast.ps1 -All         # whole tree
#>
[CmdletBinding()]
param(
  [string]$PackRoot,
  [switch]$All,
  [switch]$NoCache
)
if (-not $PackRoot) {
  $PackRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
  if ((Split-Path -Leaf $PackRoot) -eq 'TOOLS') { $PackRoot = Split-Path -Parent $PackRoot }
}
$ErrorActionPreference = 'Stop'
$failed = 0
$checked = 0
$skipped = 0

function Get-ChangedFiles {
  if ($All) {
    return @(& git -C $PackRoot ls-files)
  }
  $tracked = @(& git -C $PackRoot diff --name-only HEAD 2>$null)
  $staged = @(& git -C $PackRoot diff --cached --name-only 2>$null)
  $untracked = @(& git -C $PackRoot ls-files --others --exclude-standard 2>$null)
  return @($tracked + $staged + $untracked | Where-Object { $_ } | Sort-Object -Unique)
}

function Test-Cached([string]$Key) {
  if ($NoCache) { return $false }
  $file = Join-Path $cacheDir ($Key + '.ok')
  return (Test-Path -LiteralPath $file -PathType Leaf)
}

function Set-Cached([string]$Key) {
  if ($NoCache) { return }
  New-Item -ItemType Directory -Force -Path $cacheDir | Out-Null
  New-Item -ItemType File -Force -Path (Join-Path $cacheDir ($Key + '.ok')) | Out-Null
}

function Get-ContentKey([string]$Path) {
  $sha = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
  return $sha + '-' + ([IO.Path]::GetFileName($Path))
}

$cacheDir = Join-Path $PackRoot '.uabs-cache\verify'
$files = Get-ChangedFiles

# PowerShell: every shipped script must at least parse. The AST parser is the
# same one the editor uses and costs a few milliseconds per file.
$psFiles = @($files | Where-Object { $_ -match '\.ps1$' -and (Test-Path (Join-Path $PackRoot $_)) })
foreach ($rel in $psFiles) {
  $path = Join-Path $PackRoot $rel
  $key = Get-ContentKey $path
  if (Test-Cached $key) { $skipped++; continue }
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
  if ($errors -and $errors.Count) {
    Write-Host "FAIL parse $rel ($($errors.Count) error(s))" -ForegroundColor Red
    $errors | Select-Object -First 3 | ForEach-Object { Write-Host "     $($_.Message)" }
    $failed++
  } else {
    Set-Cached $key
    $checked++
  }
}

$python = if (Get-Command python -ErrorAction SilentlyContinue) { (Get-Command python).Source } else { $null }
$pyFiles = @($files | Where-Object { $_ -match '\.py$' -and (Test-Path (Join-Path $PackRoot $_)) })
foreach ($rel in $pyFiles) {
  $path = Join-Path $PackRoot $rel
  $key = Get-ContentKey $path
  if (Test-Cached $key) { $skipped++; continue }
  if (-not $python) { Write-Host "SKIP python missing: $rel" -ForegroundColor Yellow; $skipped++; continue }
  & $python -m py_compile $path 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Host "FAIL compile $rel" -ForegroundColor Red; $failed++ }
  else { Set-Cached $key; $checked++ }
}

# JSON must parse; a BOM is legal input but never written by the pack.
$jsonFiles = @($files | Where-Object { $_ -match '\.json$' -and (Test-Path (Join-Path $PackRoot $_)) })
foreach ($rel in $jsonFiles) {
  $path = Join-Path $PackRoot $rel
  if ($rel -in @('MANIFEST.json', 'BUNDLED-TOOLS/OFFLINE-MANIFEST.json')) { continue }
  try {
    $null = [IO.File]::ReadAllText($path) | ConvertFrom-Json
    $checked++
  } catch {
    Write-Host ("FAIL json {0}: {1}" -f $rel, $_.Exception.Message) -ForegroundColor Red
    $failed++
  }
}

# Optional linters: used when present, named when absent. Installing one is a
# separate, recorded decision (docs/TOOLING-MATRIX.md), never a FAST requirement.
if (Get-Command actionlint -ErrorAction SilentlyContinue) {
  $workflows = @(Get-ChildItem -LiteralPath (Join-Path $PackRoot '.github\workflows') -Filter '*.yml' -File |
    ForEach-Object { $_.FullName })
  & actionlint -shellcheck= -pyflakes= @workflows 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL actionlint' -ForegroundColor Red; $failed++ }
  else { $checked++ }
} else { $skipped++ }

if ($python -and (Get-Command ruff -ErrorAction SilentlyContinue)) {
  & ruff check --quiet (Join-Path $PackRoot 'TOOLS') (Join-Path $PackRoot 'TESTS') 2>$null
  if ($LASTEXITCODE -ne 0) { Write-Host 'FAIL ruff' -ForegroundColor Red; $failed++ }
  else { $checked++ }
}

Write-Host ("FAST: {0} checked, {1} cached/skipped, {2} failed" -f $checked, $skipped, $failed)
if ($failed) { exit 1 }
Write-Host 'FAST VERIFY: PASS' -ForegroundColor Green
