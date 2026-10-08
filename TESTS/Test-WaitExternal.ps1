# Local waits only. The GitHub path is checked with -WhatIf and does not call gh.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) {
    $here = $PSScriptRoot
    if (-not $here) { $here = Split-Path -Parent $PSCommandPath }
    $PackRoot = Split-Path -Parent $here
}
$waiter = Join-Path $PackRoot 'TOOLS\Wait-External.ps1'
$ps = (Get-Command powershell.exe -ErrorAction Stop).Source
$fail = 0
function Bad([string]$Message) { Write-Host "FAIL $Message"; $script:fail++ }
function Good([string]$Message) { Write-Host "ok   $Message" }

function Invoke-Waiter([string[]]$ArgList) {
    $out = & $ps -NoProfile -ExecutionPolicy Bypass -File $waiter @ArgList 2>&1
    return @{ Code = $LASTEXITCODE; Output = @($out | ForEach-Object { "$_" }) }
}

$ok = Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 1; exit 0') -WindowStyle Hidden -PassThru
$r = Invoke-Waiter @('-ProcessId', "$($ok.Id)")
if ($r.Code -eq 0 -and ($r.Output -join "`n") -match 'exit=0') { Good 'local success returns 0' }
else { Bad ("local success returned $($r.Code): " + ($r.Output -join ' | ')) }

$log = Join-Path ([IO.Path]::GetTempPath()) ('uabs-wait-' + [guid]::NewGuid().ToString('n') + '.log')
try {
    $writer = @"
`$log = '$($log.Replace("'", "''"))'
1..200 | ForEach-Object { 'LINE-' + `$_ } | Set-Content -LiteralPath `$log -Encoding Ascii
exit 3
"@
    $failProc = Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-Command', $writer) -WindowStyle Hidden -PassThru
    $r = Invoke-Waiter @('-ProcessId', "$($failProc.Id)", '-LogPath', $log, '-TailLines', '80')
    $text = $r.Output -join "`n"
    $lineCount = @($r.Output | Where-Object { $_ -like 'LINE-*' }).Count
    $hasLast = $false
    foreach ($line in $r.Output) { if ($line -eq 'LINE-200') { $hasLast = $true } }
    if ($r.Code -eq 3 -and $lineCount -le 80 -and $lineCount -ge 1 -and $hasLast) {
        Good "local failure returns 3 and $lineCount tail lines"
    } else {
        Bad "local failure code=$($r.Code) lines=$lineCount last=$hasLast"
    }
} finally {
    if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
}

$r = Invoke-Waiter @('-GitHubRun', '1', '-WhatIf')
$text = $r.Output -join "`n"
if ($r.Code -eq 0 -and $text -match 'gh run watch 1 --compact --exit-status' -and $text -notmatch 'refreshing') {
    Good 'GitHub -WhatIf prints the watch command and does not call gh'
} else { Bad ("GitHub -WhatIf returned $($r.Code): $text") }

foreach ($code in @(259, -1)) {
    $child = Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-Command',("Start-Sleep -Seconds 2; exit " + $code)) -WindowStyle Hidden -PassThru
    try {
        $r = Invoke-Waiter @('-ProcessId', "$($child.Id)")
        if ($r.Code -eq $code -and ($r.Output -join "`n") -match ("exit=" + $code + '\b')) {
            Good ("local exit " + $code + " is preserved")
        } else { Bad ("local exit " + $code + " returned " + $r.Code + ': ' + ($r.Output -join ' | ')) }
    } finally { $child.Dispose() }
}

if ($fail) { Write-Host "WAIT EXTERNAL GATE: FAIL ($fail)"; exit 1 }
Write-Host 'WAIT EXTERNAL GATE: PASS'
exit 0
