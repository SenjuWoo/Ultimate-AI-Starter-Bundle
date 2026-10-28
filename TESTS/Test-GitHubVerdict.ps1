# Exercise the real waiter against a local native gh fixture, without network or credentials.
# Run with Windows PowerShell 5.1 and PowerShell 7; compilation uses the installed .NET Framework.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
$waiter = Join-Path $PackRoot 'TOOLS\Wait-External.ps1'
$shell = (Get-Process -Id $PID).Path
$root = Join-Path ([IO.Path]::GetTempPath()) ('uabs-ci unicode-' + [char]0x03A9 + '-' + [guid]::NewGuid().ToString('n'))
$savedPath = $env:PATH
$savedFixture = $env:UABS_CI_FIXTURE
$sha = '0123456789abcdef0123456789abcdef01234567'
$repo = 'fixture/repo'
New-Item -ItemType Directory -Path $root | Out-Null

function Write-FixtureJson([string]$Name, $Object) {
    [IO.File]::WriteAllText((Join-Path $root $Name), (ConvertTo-Json -InputObject $Object -Depth 12 -Compress))
}

function Reset-Fixture([string]$State = 'success') {
    Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Name -ne 'gh.exe' } | Remove-Item -Force
    $run = [ordered]@{ id = 100; workflow_id = 1; event = 'push'; name = 'CI'; head_sha = $sha; status = 'completed'; conclusion = $State; html_url = 'https://example.invalid/runs/100' }
    $check = [ordered]@{ id = 200; name = 'gate'; app = @{ id = 1 }; head_sha = $sha; status = 'completed'; conclusion = $State; html_url = 'https://example.invalid/check/200' }
    if ($State -eq 'pending') { $run.status = 'in_progress'; $run.conclusion = $null; $check.status = 'in_progress'; $check.conclusion = $null }
    Write-FixtureJson 'runs.json' @(@{ workflow_runs = @($run) })
    Write-FixtureJson 'selected.json' $run
    Write-FixtureJson 'checks.json' @(@{ check_runs = @($check) })
    Write-FixtureJson 'statuses.json' @(@())
    Write-FixtureJson 'repository.json' @{ default_branch = 'main' }
    Write-FixtureJson 'branch.json' @{ protected = $false }
    Write-FixtureJson 'protection.json' @{ required_status_checks = @{ checks = @(); contexts = @() } }
    [IO.File]::WriteAllText((Join-Path $root 'log.txt'), ((1..300 | ForEach-Object { 'LINE-' + $_ }) -join "`n"))
}

function Invoke-Case([string]$Name, [int]$Expected, [string]$Verdict, [string[]]$Extra = @(), [int]$Seconds = 10, [int]$TailCount = 4) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $arguments = @('-Sha', $sha, '-Repo', $repo, '-TimeoutSeconds', [string]$Seconds, '-PollSeconds', '1', '-TailLines', [string]$TailCount)
    if ($Extra -notcontains '-GitHubRun') { $arguments += @('-GitHubRun', 'auto') }
    $output = @(& $shell -NoProfile -ExecutionPolicy Bypass -File $waiter @arguments @Extra 2>&1)
    $code = $LASTEXITCODE
    $text = $output -join "`n"
    if ($code -ne $Expected -or $text -notmatch ('(?m)^verdict=' + $Verdict + '$') -or @($output | Where-Object { $_ -like 'verdict=*' }).Count -ne 1) {
        throw ($Name + ': exit=' + $code + ' output=' + $text)
    }
    foreach ($field in @('sha=', 'run_id=', 'workflow=', 'checks=', 'failing=', 'url=')) {
        if ($text -notmatch ('(?m)^' + [regex]::Escape($field))) { throw ($Name + ': missing ' + $field) }
    }
    if ($Verdict -ne 'fail' -and $text -match '(?m)^log=') { throw ($Name + ': unexpected log output') }
    if ($watch.Elapsed.TotalSeconds -gt ($Seconds + 10)) { throw ($Name + ': unbounded timeout') }
    Write-Host ('ok   ' + $Name)
    return @{ Output = $output; Text = $text; Seconds = $watch.Elapsed.TotalSeconds }
}

try {
    # Compile with Desktop once so both PowerShell hosts can launch the same real native boundary.
    $fixtureSource = @'
using System;
using System.IO;
using System.Threading;
public class GhFixture {
    public static int Main(string[] args) {
        string root = Environment.GetEnvironmentVariable("UABS_CI_FIXTURE");
        string command = String.Join(" ", args);
        File.AppendAllText(Path.Combine(root, "requests.txt"), command + "\n");
        if (File.Exists(Path.Combine(root, "hang"))) Thread.Sleep(30000);
        if (File.Exists(Path.Combine(root, "error"))) {
            Console.Error.WriteLine(File.ReadAllText(Path.Combine(root, "error")));
            return 1;
        }
        string file;
        if (command.StartsWith("repo view")) { Console.WriteLine("fixture/repo"); return 0; }
        if (command.StartsWith("run view")) file = "log.txt";
        else if (command.Contains("/actions/runs?")) {
            file = "runs.json";
            string countFile = Path.Combine(root, "polls.txt");
            int count = File.Exists(countFile) ? Int32.Parse(File.ReadAllText(countFile)) : 0;
            File.WriteAllText(countFile, (count + 1).ToString());
            if (count > 0 && File.Exists(Path.Combine(root, "runs-next.json"))) {
                File.Copy(Path.Combine(root, "runs-next.json"), Path.Combine(root, "runs.json"), true);
                File.Copy(Path.Combine(root, "checks-next.json"), Path.Combine(root, "checks.json"), true);
            }
        }
        else if (command.Contains("/actions/runs/")) file = "selected.json";
        else if (command.Contains("/check-runs?")) file = "checks.json";
        else if (command.Contains("/statuses?")) file = "statuses.json";
        else if (command.EndsWith("/branches/main/protection")) file = "protection.json";
        else if (command.EndsWith("/branches/main")) file = "branch.json";
        else if (command.EndsWith("repos/fixture/repo")) file = "repository.json";
        else { Console.Error.WriteLine("unexpected fixture command"); return 2; }
        Console.Write(File.ReadAllText(Path.Combine(root, file)));
        return 0;
    }
}
'@
    $sourceFile = Join-Path $root 'fixture.cs'
    [IO.File]::WriteAllText($sourceFile, $fixtureSource)
    $compileFile = Join-Path $root 'compile.ps1'
    [IO.File]::WriteAllText($compileFile, 'Add-Type -Path (Join-Path $PSScriptRoot ''fixture.cs'') -OutputAssembly (Join-Path $PSScriptRoot ''gh.exe'') -OutputType ConsoleApplication')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $compileFile
    if ($LASTEXITCODE -ne 0) { throw 'Native fixture compilation failed' }
    $env:PATH = $root + ';' + $savedPath
    $env:UABS_CI_FIXTURE = $root

    Reset-Fixture
    $r = Invoke-Case 'green run yields positive evidence' 0 'pass'
    if ($r.Text -notmatch 'passed=1 failed=0 pending=0 skipped=0') { throw 'Incorrect green counts' }
    $requests = [IO.File]::ReadAllText((Join-Path $root 'requests.txt'))
    if ($requests -notmatch '/check-runs\?' -or $requests -notmatch '/statuses\?') { throw 'Both check sources must be queried' }

    Reset-Fixture
    Write-FixtureJson 'runs.json' @(@{ workflow_runs = @() })
    Write-FixtureJson 'checks.json' @(@{ check_runs = @() })
    $null = Invoke-Case 'untriggered SHA has no CI, not red CI' 2 'none'

    Reset-Fixture
    [IO.File]::WriteAllText((Join-Path $root 'error'), 'HTTP 404: repository not found')
    $r = Invoke-Case 'bad repository is unknown, not a red check' 3 'unknown'
    if ($r.Text -notmatch 'stderr=HTTP 404' -or $r.Text -notmatch 'command=gh.exe api') { throw 'Unknown must explain command/stderr' }

    Reset-Fixture 'failure'
    $r = Invoke-Case 'red run has bounded log tail' 1 'fail'
    if (@($r.Output | Where-Object { $_ -like 'log=*' }).Count -gt 4 -or $r.Text -notmatch 'LINE-300') { throw 'Log tail is not bounded or loses last line' }

    Reset-Fixture 'failure'
    [IO.File]::WriteAllText((Join-Path $root 'log.txt'), (('X' * 50000) + "`n") * 40)
    $r = Invoke-Case 'huge physical log lines cannot exhaust the output budget' 1 'fail' @() 10 80
    if (@($r.Output | Where-Object { $_ -like 'log=*' -and $_.Length -gt 1004 }).Count -or $r.Text.Length -gt 17000) { throw 'Log character budget exceeded' }

    Reset-Fixture 'pending'
    $r = Invoke-Case 'pending polls then terminates at hard timeout' 8 'pending' @() 3
    if ([int]([IO.File]::ReadAllText((Join-Path $root 'polls.txt')).Trim()) -lt 2 -or $r.Text -notmatch 'url=https://example.invalid/runs/100') { throw 'Pending did not poll or retain URL' }

    Reset-Fixture 'pending'
    $run = @{ id = 100; workflow_id = 1; event = 'push'; name = 'CI'; head_sha = $sha; status = 'completed'; conclusion = 'success'; html_url = 'https://example.invalid/runs/100' }
    Write-FixtureJson 'runs-next.json' @(@{ workflow_runs = @($run) })
    Write-FixtureJson 'checks-next.json' @(@{ check_runs = @(@{ id = 200; name = 'gate'; app = @{ id = 1 }; head_sha = $sha; status = 'completed'; conclusion = 'success' }) })
    $null = Invoke-Case 'pending eventually becomes pass' 0 'pass'

    Reset-Fixture
    Write-FixtureJson 'statuses.json' @(@(@{ id = 5; context = 'external'; state = 'success' }, @{ id = 4; context = 'external'; state = 'failure' }))
    $r = Invoke-Case 'newest external status supersedes historical red' 0 'pass'
    if ($r.Text -notmatch 'checks=2 passed=2') { throw 'External status missing or double counted' }
    Write-FixtureJson 'statuses.json' @(@(@{ id = 6; context = 'external'; state = 'error' }))
    $null = Invoke-Case 'external status failure blocks an otherwise green Actions run' 1 'fail'

    Reset-Fixture
    Write-FixtureJson 'checks.json' @(@{ check_runs = @(@{ id = 200; name = 'gate'; app = @{ id = 1 }; head_sha = $sha; status = 'completed'; conclusion = 'success' }) }, @{ check_runs = @(@{ id = 201; name = 'second page'; app = @{ id = 1 }; head_sha = $sha; status = 'completed'; conclusion = 'failure' }) })
    $null = Invoke-Case 'pagination cannot hide a red check' 1 'fail'

    Reset-Fixture
    Write-FixtureJson 'runs.json' @(@{ workflow_runs = @(@{ id = 99; workflow_id = 1; event = 'push'; name = 'CI'; head_sha = $sha; status = 'completed'; conclusion = 'failure' }, @{ id = 100; workflow_id = 1; event = 'push'; name = 'CI'; head_sha = $sha; status = 'completed'; conclusion = 'success'; html_url = 'https://example.invalid/runs/100' }) })
    Write-FixtureJson 'checks.json' @(@{ check_runs = @(@{ id = 199; name = 'gate'; app = @{ id = 1 }; head_sha = $sha; status = 'completed'; conclusion = 'failure' }, @{ id = 200; name = 'gate'; app = @{ id = 1 }; head_sha = $sha; status = 'completed'; conclusion = 'success' }) })
    $null = Invoke-Case 'latest rerun supersedes the old result for the same workflow' 0 'pass'

    Reset-Fixture
    Write-FixtureJson 'branch.json' @{ protected = $true }
    Write-FixtureJson 'protection.json' @{ required_status_checks = @{ checks = @(@{ context = 'not reported'; app_id = 1 }); contexts = @('not reported') } }
    $r = Invoke-Case 'missing protected context cannot silently become green' 8 'pending' @() 3
    if ($r.Text -notmatch 'Required checks have not reported: not reported') { throw 'Missing protected context was not explained' }

    Reset-Fixture
    Write-FixtureJson 'branch.json' @{ protected = $true }
    Write-FixtureJson 'protection.json' @{ required_status_checks = @{ checks = @(@{ context = 'gate'; app_id = 999 }); contexts = @('gate') } }
    $null = Invoke-Case 'same check name from the wrong App cannot satisfy protection' 8 'pending' @() 3

    Reset-Fixture
    Write-FixtureJson 'runs.json' @(@{ workflow_runs = @(@{ id = 101; workflow_id = 2; event = 'push'; name = 'security'; head_sha = $sha; status = 'in_progress'; conclusion = $null; html_url = 'https://example.invalid/runs/101' }, @{ id = 100; workflow_id = 1; event = 'push'; name = 'CI'; head_sha = $sha; status = 'completed'; conclusion = 'success'; html_url = 'https://example.invalid/runs/100' }) })
    $null = Invoke-Case 'a second workflow cannot be silently ignored' 8 'pending' @() 3

    Reset-Fixture 'skipped'
    $r = Invoke-Case 'skipped checks do not certify a release' 1 'fail'
    if ($r.Text -notmatch 'skipped=2') { throw 'Skipped checks not accounted for' }

    Reset-Fixture
    Write-FixtureJson 'selected.json' @{ head_sha = ('f' * 40) }
    $null = Invoke-Case 'explicit run ID from another SHA is unknown' 3 'unknown' @('-GitHubRun', '99')

    Reset-Fixture
    [IO.File]::WriteAllText((Join-Path $root 'checks.json'), '{broken json')
    $null = Invoke-Case 'malformed API response is unknown' 3 'unknown'

    Reset-Fixture
    [IO.File]::WriteAllText((Join-Path $root 'hang'), '')
    $null = Invoke-Case 'hung gh request respects overall deadline' 3 'unknown' @() 3
    Write-Host 'GITHUB VERDICT GATE: PASS (18 cases)'
} finally {
    $env:PATH = $savedPath
    $env:UABS_CI_FIXTURE = $savedFixture
    $resolved = [IO.Path]::GetFullPath($root)
    if ($resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()), [StringComparison]::OrdinalIgnoreCase) -and (Split-Path -Leaf $resolved) -like 'uabs-ci unicode-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
