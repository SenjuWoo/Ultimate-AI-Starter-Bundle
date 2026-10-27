# Exercise the companion boundary with real ZIPs and child scripts, without network or installed-state writes.
[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference='Stop'
if (-not $PackRoot) { $PackRoot=Split-Path -Parent $PSScriptRoot }
function Assert($ok,[string]$why) { if (-not $ok) { throw $why } }
$catalog=[IO.File]::ReadAllText((Join-Path $PackRoot 'BUNDLED-TOOLS\CATALOG.json')) | ConvertFrom-Json
$releasePin=@($catalog.components | Where-Object id -eq 'reverse-this')
Assert ($releasePin.Count -eq 1 -and $releasePin[0].sha256 -match '^[a-f0-9]{64}$' -and $releasePin[0].release_tag -eq ('v'+$releasePin[0].version)) 'Companion catalog lacks its verified release identity.'
$packs=[IO.File]::ReadAllText((Join-Path $PackRoot 'BUNDLED-TOOLS\PACKS.json')) | ConvertFrom-Json
Assert ($packs.packs.reverse.owner -eq 'reverse-this' -and @($packs.packs.reverse.skills).Count -eq 0) 'Reverse payload ownership leaked into bundle skills.'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('uabs-companions-'+[guid]::NewGuid().ToString('N'))
$savedLocal=$env:LOCALAPPDATA
$scriptFile=Join-Path $PackRoot 'TOOLS\Install-ReverseThis.ps1'
function Run-Companion([string[]]$Options) {
    $previous=$ErrorActionPreference; $ErrorActionPreference='Continue'
    try { $output=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $scriptFile -PackRoot $fixture @Options 2>&1 | Out-String; $code=$LASTEXITCODE }
    finally { $ErrorActionPreference=$previous }
    return @{code=$code;output=$output}
}
try {
    $env:LOCALAPPDATA=Join-Path $fixture 'local'
    New-Item -ItemType Directory -Force -Path (Join-Path $fixture 'TOOLS'),(Join-Path $fixture 'BUNDLED-TOOLS'),(Join-Path $fixture 'release') | Out-Null
    Copy-Item -LiteralPath (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1') -Destination (Join-Path $fixture 'TOOLS\UABS-Common.ps1')
    $release=Join-Path $fixture 'release'
    [IO.File]::WriteAllText((Join-Path $release 'VERSION'),'1.4.0')
    [IO.File]::WriteAllText((Join-Path $release 'Install-Modkit.ps1'),@'
param([switch]$Doctor,[switch]$Offline,[switch]$NoUpdate,[string[]]$Only,[string]$InstallRoot)
$root=$PSScriptRoot
$pointer=Join-Path $env:LOCALAPPDATA 'ReverseThis\kit.json'
if ($InstallRoot) { $root=$InstallRoot } elseif (Test-Path -LiteralPath $pointer) { $root=([IO.File]::ReadAllText($pointer) | ConvertFrom-Json).kit_root }
@{root=$root;doctor=[bool]$Doctor;offline=[bool]$Offline;no_update=[bool]$NoUpdate;only=@($Only)} | ConvertTo-Json -Compress | Add-Content -LiteralPath (Join-Path $root 'calls.jsonl')
if ($env:UABS_REVERSE_FAIL) { exit 7 }
exit 0
'@)
    [IO.File]::WriteAllText((Join-Path $release 'Update-ReverseThis.ps1'),@'
param([string]$Destination,[string]$Archive,[string]$Sha256)
New-Item -ItemType Directory -Path $Destination -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'VERSION'),(Join-Path $PSScriptRoot 'Install-Modkit.ps1') -Destination $Destination
'@)
    $zip=Join-Path $fixture 'Reverse-This-1.4.0.zip'
    Compress-Archive -LiteralPath $release -DestinationPath $zip
    $pin=@{id='reverse-this';version='1.4.0';asset='Reverse-This-1.4.0.zip';sha256=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash}
    [IO.File]::WriteAllText((Join-Path $fixture 'BUNDLED-TOOLS\CATALOG.json'),(@{components=@($pin)} | ConvertTo-Json -Depth 5))
    $target=Join-Path $fixture 'owner'
    $result=Run-Companion @('-KitRoot',$target,'-Offline')
    Assert ($result.code -ne 0 -and $result.output -match 'not cached') 'Offline missing archive did not fail clearly.'
    Assert (-not (Test-Path -LiteralPath $target)) 'Offline missing archive created an owner.'
    $bad=Join-Path $fixture 'bad.zip'; [IO.File]::WriteAllText($bad,'tampered')
    $result=Run-Companion @('-KitRoot',$target,'-SourceZip',$bad)
    Assert ($result.code -ne 0 -and $result.output -match 'pinned SHA-256') 'Tampered companion archive was accepted.'
    Assert (-not (Test-Path -LiteralPath $target)) 'Tampered archive wrote installed source.'
    $result=Run-Companion @('-KitRoot',$target,'-SourceZip',$zip,'-Offline')
    Assert ($result.code -eq 0) ('Fresh verified owner delegation failed: '+$result.output)
    $calls=@(Get-Content -LiteralPath (Join-Path $target 'calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    Assert ($calls.Count -eq 2 -and $calls[0].offline -and $calls[1].doctor) 'Offline/Doctor options did not reach the owner.'
    # A registered older-folder owner is reused. Newer source and existing selection survive.
    [IO.File]::WriteAllText((Join-Path $target 'VERSION'),'9.0.0')
    New-Item -ItemType Directory -Force -Path (Join-Path $target 'sandbox'),(Join-Path $env:LOCALAPPDATA 'ReverseThis') | Out-Null
    $statePath=Join-Path $target 'sandbox\installed.json'
    [IO.File]::WriteAllText($statePath,(@{schema=1;kit_root=$target;tools=@{rea=@{version='6.8.0'}}} | ConvertTo-Json -Depth 5))
    $pointerPath=Join-Path $env:LOCALAPPDATA 'ReverseThis\kit.json'
    [IO.File]::WriteAllText($pointerPath,(@{kit_root=$target;installed_json=$statePath;bin=(Join-Path $target 'sandbox\bin');personal='preserve'} | ConvertTo-Json))
    $before=(Get-FileHash -LiteralPath $pointerPath -Algorithm SHA256).Hash
    $result=Run-Companion @('-ResolveOnly')
    Assert ($result.code -eq 0 -and $result.output.Trim() -eq $target) 'Registered owner resolution created a parallel root.'
    $result=Run-Companion @('-NoUpdate')
    Assert ($result.code -eq 0) ('Newer owner reuse failed: '+$result.output)
    $calls=@(Get-Content -LiteralPath (Join-Path $target 'calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    Assert ($calls[-2].no_update -and $calls[-2].only[0] -eq 'rea' -and $calls[-1].only[0] -eq 'rea') 'Existing selection/NoUpdate was not delegated.'
    Assert (([IO.File]::ReadAllText((Join-Path $target 'VERSION'))) -eq '9.0.0') 'Newer companion source was downgraded.'
    Assert ((Get-FileHash -LiteralPath $pointerPath -Algorithm SHA256).Hash -eq $before) 'Wrapper rewrote another owner pointer.'
    $isolated=Join-Path $fixture 'isolated'
    $result=Run-Companion @('-KitRoot',$isolated,'-SourceZip',$zip)
    Assert ($result.code -eq 0) ('Explicit isolated companion failed: '+$result.output)
    $isolatedCalls=@(Get-Content -LiteralPath (Join-Path $isolated 'calls.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
    Assert ($isolatedCalls.Count -eq 2 -and $isolatedCalls[0].root -eq $isolated -and $isolatedCalls[1].root -eq $isolated) 'Explicit source root updated a different registered tool owner.'
    Assert (@(Get-Content -LiteralPath (Join-Path $target 'calls.jsonl')).Count -eq $calls.Count) 'Isolated install wrote calls to the registered owner.'
    Assert ((Get-FileHash -LiteralPath $pointerPath -Algorithm SHA256).Hash -eq $before) 'Isolated install rewrote the registered owner pointer.'
    $env:UABS_REVERSE_FAIL='1'
    $result=Run-Companion @('-NoUpdate')
    Assert ($result.code -ne 0 -and $result.output -match 'tool update failed') 'Native child failure was reported as success.'
    Remove-Item Env:UABS_REVERSE_FAIL
    [IO.File]::WriteAllText($pointerPath,'{"kit_root":"relative"}')
    $result=Run-Companion @('-ResolveOnly')
    Assert ($result.code -ne 0 -and $result.output -match 'Invalid Reverse THIS') 'Malformed owner pointer triggered default installation.'
    Write-Host 'COMPANION GATE: PASS'
} finally {
    $env:LOCALAPPDATA=$savedLocal
    Remove-Item Env:UABS_REVERSE_FAIL -ErrorAction SilentlyContinue
    if (([IO.Path]::GetFullPath($fixture)).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)) { Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue }
}
