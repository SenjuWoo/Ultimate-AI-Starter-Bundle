# Run the hook installer against isolated homes, preserving personal handlers.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$python = Get-UabsPythonExecutable
if (-not $python) { throw 'Provider hook scope gate requires Python.' }
$powershell = (Get-Command powershell.exe -ErrorAction Stop).Source
$gitDirectory = Split-Path -Parent (Get-Command git.exe -ErrorAction Stop).Source
$installer = Join-Path $PackRoot 'TOOLS\Install-Completeness-Gate.ps1'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hook-scope-' + [guid]::NewGuid().ToString('N'))
$saved = @{}
foreach ($key in @('USERPROFILE','LOCALAPPDATA','APPDATA','CLAUDE_CONFIG_DIR','GROK_HOME','CODEX_HOME','KIMI_CODE_HOME','HERMES_HOME','PATH','UABS_HOOK_TEST_PYTHON')) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Put([string]$Path, [string]$Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}
function Run-Gate([string]$Provider, [switch]$Uninstall, [switch]$CheckOnly) {
    $arguments = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$installer,'-PackRoot',$testPack,'-Providers',$Provider)
    if ($Uninstall) { $arguments += '-Uninstall' }
    if ($CheckOnly) { $arguments += '-CheckOnly' }
    $output = @(& $powershell @arguments 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
    $script:lastGateOutput = $output
    Assert ($LASTEXITCODE -eq 0) ('Hook installer failed: ' + $output)
}
function Read-Commands($Document) {
    foreach ($evt in @('PreToolUse','Stop','SessionStart')) {
        foreach ($group in @($Document.hooks.$evt)) {
            foreach ($handler in @($group.hooks)) { if ($handler.command) { [string]$handler.command } }
        }
    }
}
try {
    $testPack = Join-Path $fixture 'pack'
    $common = (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1').Replace("'", "''")
    # The production merge runs unchanged. Disable only persistent PATH repair;
    # Python is a full executable path captured before the environment is isolated.
    Put (Join-Path $testPack 'TOOLS\UABS-Common.ps1') (". '$common'`nfunction Repair-UabsHookShellPath { param([switch]`$CheckOnly) }`nfunction Get-UabsPythonExecutable { return `$env:UABS_HOOK_TEST_PYTHON }`n")
    foreach ($name in @('completeness_gate.py','assumption_gate.py','rtk_safe_hook.py')) {
        $destination = Join-Path $testPack ('TOOLS\hooks\' + $name)
        [void][IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        [IO.File]::Copy((Join-Path $PackRoot ('TOOLS\hooks\' + $name)), $destination)
    }
    $env:USERPROFILE = Join-Path $fixture 'default user'
    $env:LOCALAPPDATA = Join-Path $fixture 'local'
    $env:APPDATA = Join-Path $fixture 'roaming'
    $env:CLAUDE_CONFIG_DIR = Join-Path $fixture 'custom Claude'
    $env:GROK_HOME = Join-Path $fixture 'custom Grok'
    $env:CODEX_HOME = Join-Path $fixture 'custom Codex'
    $env:KIMI_CODE_HOME = Join-Path $fixture 'custom Kimi'
    $env:HERMES_HOME = Join-Path $fixture 'custom Hermes'
    $env:PATH = $gitDirectory + ';' + $env:SystemRoot + '\System32;' + $env:SystemRoot
    $env:UABS_HOOK_TEST_PYTHON = $python
    # Cold PATH must still find Hermes' modern launcher without starting it.
    $modernHermes = Join-Path $env:LOCALAPPDATA 'hermes\bin\hermes.exe'
    Put $modernHermes ''
    $gateAst = [Management.Automation.Language.Parser]::ParseFile($installer,[ref]$null,[ref]$null)
    $resolver = $gateAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-HermesExe' },$true)
    $resolvedHermes = & {
        function Get-UabsProviderPathDirectories { return @($env:SystemRoot + '\System32') }
        . ([scriptblock]::Create($resolver.Extent.Text))
        Get-HermesExe
    }
    Assert ($resolvedHermes -ceq $modernHermes) 'Hook setup missed the modern Hermes launcher on a cold PATH.'
    [IO.File]::Delete($modernHermes)
    $root = Join-Path $env:LOCALAPPDATA 'Ultimate-AI-Starter-Bundle\hooks'
    $owned = '"python.exe" "' + (Join-Path $root 'completeness_gate.py') + '" --pre'
    $personal = '"python.exe" "C:\personal\completeness_gate.py" --pre'
    $initial = [ordered]@{ personal='keep'; hooks=[ordered]@{ PreToolUse=@(
        @{ matcher='Bash'; future='keep'; hooks=@(@{type='command';command=$owned}, @{type='command';command=$personal;future='keep'}) }
    ); SessionStart=@(@{hooks=@(@{type='command';command='personal-start.cmd'})}) } } | ConvertTo-Json -Depth 20
    $claude = Join-Path $env:CLAUDE_CONFIG_DIR 'settings.json'
    Put $claude $initial
    $defaultClaude = Join-Path $env:USERPROFILE '.claude\settings.json'
    Put $defaultClaude '{"personal":"default profile"}'
    $untouched = @{}
    foreach ($relative in @('.grok\hooks\ultimate-bundle.json','.codex\hooks\ultimate-bundle.json','.kimi-code\hooks\ultimate-bundle.json','.hermes\hooks\ultimate-bundle.json','.hermes\config.yaml')) {
        $path = Join-Path $env:USERPROFILE $relative
        $untouched[$path] = 'personal file containing completeness_gate.py'
        Put $path $untouched[$path]
    }
    Run-Gate Claude
    $doc = [IO.File]::ReadAllText($claude) | ConvertFrom-Json
    Assert ((@(Read-Commands $doc) -contains $personal)) 'Custom-home install removed a same-basename personal handler.'
    Assert (@(Read-Commands $doc | Where-Object { $_ -like ('*' + $root + '*') }).Count -eq 5) ('Custom Claude home did not receive the bundle hooks: ' + $script:lastGateOutput)
    Assert ($doc.hooks.PreToolUse[0].future -eq 'keep' -and $doc.hooks.PreToolUse[0].hooks[0].future -eq 'keep' -and $doc.personal -eq 'keep') 'Custom sibling or group metadata was changed.'
    Assert ([IO.File]::ReadAllText($defaultClaude) -ceq '{"personal":"default profile"}') 'A custom-home install changed the default Claude profile.'
    foreach ($path in $untouched.Keys) { Assert ([IO.File]::ReadAllText($path) -ceq $untouched[$path]) ('An unselected provider file changed: ' + $path) }
    $beforeCheck = [IO.File]::ReadAllText($claude)
    Run-Gate Claude -CheckOnly
    Assert ([IO.File]::ReadAllText($claude) -ceq $beforeCheck) 'CheckOnly modified selected settings.'
    Run-Gate Claude -Uninstall
    $doc = [IO.File]::ReadAllText($claude) | ConvertFrom-Json
    Assert (@(Read-Commands $doc).Count -eq 2 -and @(Read-Commands $doc) -contains $personal) 'Selected uninstall removed personal handlers or retained bundle handlers.'
    Put $claude '{ "personal": "untouched selected profile" }'
    Run-Gate Claude -Uninstall
    Assert ([IO.File]::ReadAllText($claude) -ceq '{ "personal": "untouched selected profile" }') 'Uninstall rewrote a selected file without any bundle hooks.'
    foreach ($path in $untouched.Keys) { Assert ([IO.File]::ReadAllText($path) -ceq $untouched[$path]) ('Uninstall changed an unselected provider: ' + $path) }

    # An exact bundle-only legacy drop may be retired only after a byte-exact backup.
    $kimi = Join-Path $env:KIMI_CODE_HOME 'hooks\ultimate-bundle.json'
    $legacy = @{hooks=@{PreToolUse=@(@{hooks=@(@{type='command';command=$owned})})}} | ConvertTo-Json -Depth 12
    Put $kimi $legacy
    Run-Gate Kimi -Uninstall
    Assert (-not (Test-Path -LiteralPath $kimi)) 'The selected owned inert hook was not retired.'
    $backups = @(Get-ChildItem -LiteralPath (Split-Path -Parent $kimi) -Filter 'ultimate-bundle.json.before-retired-*.bak')
    Assert ($backups.Count -eq 1 -and [IO.File]::ReadAllText($backups[0].FullName) -ceq $legacy) 'The retired hook has no exact backup.'
    Put $kimi $initial
    Run-Gate Kimi -Uninstall
    Assert ([IO.File]::ReadAllText($kimi) -ceq $initial) 'A mixed or personal inert hook was deleted.'

    $grok = Join-Path $env:GROK_HOME 'hooks\ultimate-bundle.json'
    Put $grok $initial
    Run-Gate Grok
    $doc = [IO.File]::ReadAllText($grok) | ConvertFrom-Json
    Assert (@(Read-Commands $doc) -contains $personal -and $doc.personal -eq 'keep') 'Grok install overwrote personal hook content.'
    Run-Gate Grok -Uninstall
    $doc = [IO.File]::ReadAllText($grok) | ConvertFrom-Json
    Assert (@(Read-Commands $doc).Count -eq 2 -and @(Read-Commands $doc) -contains $personal) 'Grok uninstall deleted personal hook content.'

    # Hermes must remove hooks through its own dependency runtime, as installation
    # already does. The user base Python may have no PyYAML installed.
    Put $modernHermes ''
    $wireFixture = Join-Path $testPack 'TOOLS\hooks\hermes_wire.py'
    [IO.File]::Copy((Join-Path $PackRoot 'TOOLS\hooks\hermes_wire.py'),$wireFixture)
    $vendorMarker = Join-Path $fixture 'vendor-runtime.jsonl'
    $vendorFailure = Join-Path $fixture 'vendor-failure.flag'
    $vendorShim = @'
function Resolve-UabsProviderExe { param([string]$Provider) if ($Provider -eq 'Hermes') { return '__HERMES__' }; return $null }
function Invoke-UabsHermesPython {
  param([string[]]$PythonArgs,[string]$HermesExe)
  $record = @{executable=$HermesExe;arguments=@($PythonArgs)} | ConvertTo-Json -Compress
  [IO.File]::AppendAllText('__MARKER__',$record + [Environment]::NewLine,(New-Object Text.UTF8Encoding $false))
  $global:LASTEXITCODE = $(if (Test-Path -LiteralPath '__FAILURE__') { 7 } else { 0 })
}
'@
    $vendorShim = $vendorShim.Replace('__HERMES__',$modernHermes.Replace("'","''")).Replace('__MARKER__',$vendorMarker.Replace("'","''")).Replace('__FAILURE__',$vendorFailure.Replace("'","''"))
    [IO.File]::AppendAllText((Join-Path $testPack 'TOOLS\UABS-Common.ps1'),$vendorShim,(New-Object Text.UTF8Encoding $false))
    Run-Gate Hermes -Uninstall
    Assert (Test-Path -LiteralPath $vendorMarker) 'Hermes uninstall bypassed the vendor dependency runtime.'
    $invocations = @([IO.File]::ReadAllLines($vendorMarker) | ForEach-Object { $_ | ConvertFrom-Json })
    Assert ($invocations.Count -eq 3) 'Hermes uninstall did not remove each of the three bundle gates.'
    foreach ($invocation in $invocations) {
        Assert ($invocation.executable -ceq $modernHermes -and $invocation.arguments[0] -ceq $wireFixture -and $invocation.arguments[1] -ceq $modernHermes -and $invocation.arguments -contains '--remove') 'Hermes uninstall passed the wrong runtime or removal arguments.'
    }
    Put $vendorFailure 'fail'
    # Windows PowerShell 5.1 promotes a child's error record to a terminating
    # error while ErrorActionPreference is Stop, so the exit code never gets read.
    $failureEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $failureOutput = @(& $powershell -NoProfile -ExecutionPolicy Bypass -File $installer -PackRoot $testPack -Providers Hermes -Uninstall 2>&1 | ForEach-Object { [string]$_ }) -join "`n"
        $failureCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $failureEap }
    Assert ($failureCode -ne 0 -and $failureOutput -match 'Hermes hook removal failed') 'Hermes uninstall swallowed a vendor runtime failure.'
    Write-Host 'PROVIDER HOOK SCOPE GATE: PASS'
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
    $full = [IO.Path]::GetFullPath($fixture)
    $temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if ($full.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue }
}
