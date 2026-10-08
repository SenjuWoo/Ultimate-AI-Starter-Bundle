# Local only. -WhatIf must not call gh. The live probe is an etiquette step,
# not a pack-gate network call.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $PSCommandPath }
    $PackRoot = Split-Path -Parent $here
}
$fail = 0
function Bad([string]$Message) { Write-Host "FAIL $Message"; $script:fail++ }
function Good([string]$Message) { Write-Host "ok   $Message" }

$probe = Join-Path $PackRoot 'TOOLS\Get-GitHubFlags.ps1'
$ps = (Get-Command powershell.exe -ErrorAction Stop).Source
$out = & $ps -NoProfile -ExecutionPolicy Bypass -File $probe -WhatIf 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { Bad ('whatif exit ' + $LASTEXITCODE) }
else { Good 'whatif exits 0' }

$needles = @(
    'dependabot/alerts?state=open',
    'code-scanning/alerts?state=open',
    'secret-scanning/alerts?state=open',
    'code-quality/setup',
    'code-quality/findings?state=open',
    'flags=whatif'
)
foreach ($needle in $needles) {
    if ($out.IndexOf($needle) -ge 0) { Good ('whatif names ' + $needle) }
    else { Bad ('whatif missed ' + $needle) }
}

$source = [IO.File]::ReadAllText($probe)
if ($source -match '\.secret\b') { Bad 'probe selects the secret material field' }
else { Good 'probe source has no secret material field' }
if ($source -match 'dismiss') { Bad 'probe dismisses alerts' }
else { Good 'probe does not dismiss alerts' }

# Exercise the actual child script against a local fake gh, never GitHub.
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-flags-' + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$oldPath = $env:PATH
$oldCase = $env:UABS_FLAGS_TEST_CASE
try {
    Add-Type -OutputAssembly (Join-Path $fixture 'gh.exe') -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.Threading;
public class FakeGh {
    public static int Main(string[] args) {
        string mode = Environment.GetEnvironmentVariable("UABS_FLAGS_TEST_CASE");
        string path = args[args.Length - 1];
        if (!path.StartsWith("repos/test/bundle")) return 9;
        if (path == "repos/test/bundle") {
            if (mode == "timeout") Thread.Sleep(2500);
            if (mode == "stderr-flood") Console.Error.Write(new string('x', 131072));
            Console.Write("{\"security_and_analysis\":{}}"); return 0;
        }
        if (path.Contains("code-quality/setup")) {
            if (mode == "quality-unknown") { Console.Write("{}"); return 0; }
            if (mode == "quality-off") { Console.Write("{\"state\":\"not-configured\"}"); return 0; }
            if (mode == "quality-open" || mode == "quality-denied") { Console.Write("{\"state\":\"configured\"}"); return 0; }
            Console.Error.Write("gh: Not Found (HTTP 404)"); return 1;
        }
        if (mode == "alert-error" && path.Contains("dependabot/alerts")) {
            Console.Error.Write("gh: Requires authentication (HTTP 401)"); return 1;
        }
        if (mode == "empty-alert" && path.Contains("dependabot/alerts")) return 0;
        if (mode == "null-alert" && path.Contains("dependabot/alerts")) { Console.Write("[null]"); return 0; }
        if (mode == "quality-denied" && path.Contains("code-quality/findings")) {
            Console.Error.Write("gh: Forbidden (HTTP 403)"); return 1;
        }
        if (mode == "bad-json" && path.Contains("secret-scanning/alerts")) {
            Console.Write("[{\"secret\":\"FIXTURE-DO-NOT-PRINT\", BROKEN"); return 0;
        }
        if ((mode == "secret-open" && path.Contains("secret-scanning/alerts")) ||
            (mode == "quality-open" && path.Contains("code-quality/findings"))) {
            Console.Write("[{\"number\":1,\"secret_type\":\"fixture\",\"secret\":\"FIXTURE-DO-NOT-PRINT\"}]"); return 0;
        }
        Console.Write("[]"); return 0;
    }
}
'@
    $env:PATH = $fixture + ';' + $oldPath
    foreach ($case in @(
        @{ Name='clean'; Code=0; Verdict='clean' },
        @{ Name='quality-off'; Code=0; Verdict='clean' },
        @{ Name='quality-unknown'; Code=1; Verdict='unknown' },
        @{ Name='empty-alert'; Code=1; Verdict='unknown' },
        @{ Name='null-alert'; Code=1; Verdict='unknown' },
        @{ Name='bad-json'; Code=1; Verdict='unknown' },
        @{ Name='alert-error'; Code=1; Verdict='unknown' },
        @{ Name='secret-open'; Code=2; Verdict='open' },
        @{ Name='quality-open'; Code=2; Verdict='open' },
        @{ Name='quality-denied'; Code=0; Verdict='clean' },
        @{ Name='stderr-flood'; Code=0; Verdict='clean' },
        @{ Name='timeout'; Code=1; Verdict='unknown' },
        @{ Name='invalid-repo'; Code=1; Verdict='unknown' }
    )) {
        $env:UABS_FLAGS_TEST_CASE = $case.Name
        $repo = if ($case.Name -eq 'invalid-repo') { 'test/bundle --method DELETE' } else { 'test/bundle' }
        $command = "$" + "ProgressPreference='SilentlyContinue'; & '" + $probe.Replace("'", "''") + "' -Repo '" + $repo + "'"
        if ((Get-Command $probe).Parameters.ContainsKey('TimeoutSeconds')) { $command += ' -TimeoutSeconds 1' }
        $command += '; exit $LASTEXITCODE'
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $ps
        $info.Arguments = '-NoProfile -OutputFormat Text -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $proc = [Diagnostics.Process]::Start($info)
        try {
            $stdout = $proc.StandardOutput.ReadToEndAsync()
            $stderr = $proc.StandardError.ReadToEndAsync()
            if (-not $proc.WaitForExit(15000)) {
                $proc.Kill(); $proc.WaitForExit()
                Bad ($case.Name + ' hung'); continue
            }
            $body = $stdout.Result + $stderr.Result
            $valid = $proc.ExitCode -eq $case.Code -and $body -match ('flags=' + $case.Verdict + '\b') -and $body -notmatch 'FIXTURE-DO-NOT-PRINT'
            if ($case.Name -eq 'invalid-repo') { $valid = $valid -and $body -match 'reason=invalid-repo' }
            if ($valid) {
                Good ($case.Name + ' returns ' + $case.Verdict + ' without sensitive fields')
            } else {
                Bad ($case.Name + ' returned exit=' + $proc.ExitCode + ', expected ' + $case.Code + '/' + $case.Verdict)
            }
        } finally { $proc.Dispose() }
    }
} finally {
    $env:PATH = $oldPath
    $env:UABS_FLAGS_TEST_CASE = $oldCase
    # Only this test's freshly created, resolved temporary directory is removed.
    Remove-Item -LiteralPath $fixture -Recurse -Force
}

if ($fail -gt 0) {
    Write-Host ('GITHUB FLAGS GATE: FAIL (' + $fail + ')')
    exit 1
}
Write-Host 'GITHUB FLAGS GATE: PASS'
exit 0
