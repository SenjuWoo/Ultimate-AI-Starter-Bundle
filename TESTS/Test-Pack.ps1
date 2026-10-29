<#
.SYNOPSIS
  Full v6 pack gate: skill health, PowerShell parseability, offline asset
  integrity, and registry sanity. Exits non-zero on any failure.

.DESCRIPTION
  This is the control that v5 lacked. v5.2.5's registry already WARNED that a
  BOM breaks valid-looking files, and v5.2.5 still shipped seven BOM'd skills
  whose descriptions never loaded. A warning in a document is not a control;
  this script is.

.EXAMPLE
  .\TESTS\Test-Pack.ps1
#>
[CmdletBinding()]
param(
    [string]$PackRoot,
    # Dependency-rich disposable interpreter for tests only. Shared-runtime
    # fixtures still resolve the real base Python from their own process.
    [string]$TestPython,
    [switch]$IncludeLiveInstalls
)

# $PSScriptRoot is empty when the script is invoked by a relative -File path
# from some shells, so resolve defensively rather than assuming.
if (-not $PackRoot) {
    $here = $PSScriptRoot
    if (-not $here -and $PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
    if (-not $here) { $here = (Get-Location).Path }
    $PackRoot = Split-Path -Parent $here
}
if (-not (Test-Path (Join-Path $PackRoot '_CANONICAL-SKILLS'))) {
    throw "PackRoot '$PackRoot' does not look like the v6 pack (no _CANONICAL-SKILLS). Pass -PackRoot explicitly."
}

$ErrorActionPreference = 'Stop'
# A host agent can export PYTHONPATH (Hermes points it at its own venv). Child
# test Pythons would then import the host's mcp/pydantic instead of the
# disposable test environment, and the toolbox gate fails on a version this
# repository never pinned. Tests that need a path set it on their own child
# environment; the gate itself owns a clean import path.
Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue
Remove-Item Env:PYTHONHOME -ErrorAction SilentlyContinue
. (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
$fail = 0
$pythonExe = if ($TestPython) { (Resolve-Path -LiteralPath $TestPython -ErrorAction Stop).ProviderPath } else { Get-UabsPythonExecutable }
$py = if ($pythonExe) { [pscustomobject]@{ Source = $pythonExe } } else { $null }

function Section($t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Bad($m) { Write-Host "  FAIL $m" -ForegroundColor Red; $script:fail++ }
function Good($m) { Write-Host "  ok   $m" -ForegroundColor Green }

Section '1. Skill health (all trees)'
if (-not $py) {
    Bad 'python not found; skill audit skipped'
} else {
    $trees = @(Join-Path $PackRoot '_CANONICAL-SKILLS')
    # v7.6.6: only the tailored family remains; 2-OPTIONAL-SHARED-GENERIC was
    # a 97%-identical duplicate the installer never read.
    foreach ($fam in '1-TAILORED-PROVIDER-TREES') {
        foreach ($prov in 'Claude', 'Codex', 'Grok', 'Hermes', 'Kimi', 'Antigravity') {
            $p = Join-Path $PackRoot "$fam\$prov\COPY-TO-SKILLS-DIRECTORY\skills"
            if (Test-Path $p) { $trees += $p }
        }
    }
    foreach ($t in $trees) {
        $out = & $py.Source (Join-Path $PackRoot 'TOOLS\audit_skills.py') $t 2>&1
        $res = ($out | Select-String 'RESULT:').ToString().Trim()
        $short = $t.Replace($PackRoot, '').TrimStart('\')
        if ($res -match 'PASS') { Good "$short  $res" } else { Bad "$short  $res" }
    }

    if ($IncludeLiveInstalls) {
        # Provider homes can contain third-party/user skills. Audit only the
        # bundle-owned names through the installed-state doctor; unrelated
        # malformed skills are reported by their owner, not blamed on UABS.
        $doctor = Join-Path $PackRoot 'TOOLS\Test-Installed-State.ps1'
        $liveOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $doctor -PackRoot $PackRoot -Providers 'Claude,Codex,Grok,Kimi,Hermes,Antigravity' -SkipForge 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) { Good 'all six live provider trees match bundle-owned skills' }
        else { Bad ('live provider audit failed:' + [Environment]::NewLine + $liveOut.Trim()) }
    }
}

if ($py) {
    & $py.Source (Join-Path $PackRoot 'TESTS\test_audit_regressions.py')
    if ($LASTEXITCODE -ne 0) { Bad 'Index/junction safety, Unicode privacy and usage-accounting regressions failed' }
    else { Good 'Index/junction safety, Unicode privacy and usage-accounting regressions' }
    & $py.Source (Join-Path $PackRoot 'TESTS\test_universal_modder.py')
    if ($LASTEXITCODE -ne 0) { Bad 'Universal Modder offline CLI and routing check failed' }
    else { Good 'Universal Modder offline CLI and all-provider routing' }
    # The toolbox gate drives the real server over stdio, so it needs the MCP SDK
    # (CI installs the version the wheel pins).
    $mcpPython = $py.Source
    $probeArgs = @('-c', "from importlib.metadata import version; print(version('mcp'))")
    $mcpSdk = (Get-UabsNativeStdout -Exe $mcpPython -CmdArgs $probeArgs | Out-String).Trim()
    # Reuse the installed toolbox dependency env; keep the shared base clean.
    if (-not $mcpSdk -and (Get-Command uv -ErrorAction SilentlyContinue)) {
      $toolDir = @(Get-UabsNativeStdout -Exe 'uv' -CmdArgs @('tool','dir')) | Select-Object -Last 1
      if ($toolDir) {
        $candidate = Join-Path $toolDir 'uabs-toolbox\Scripts\python.exe'
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
          $mcpPython = $candidate
          $mcpSdk = (Get-UabsNativeStdout -Exe $mcpPython -CmdArgs $probeArgs | Out-String).Trim()
        }
      }
    }
    if (-not $mcpSdk) { Bad 'toolbox gate needs the installed toolbox environment or mcp==1.30.0 in the test environment' }
    else {
        $tbOut = & $mcpPython (Join-Path $PackRoot 'TESTS\test_toolbox.py') 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { Bad ('toolbox gate failed (mcp ' + $mcpSdk + '):' + [Environment]::NewLine + $tbOut.Trim()) }
        else { Good ('On-demand toolbox: find/describe/call, parked entries, project sets, crash restart (mcp ' + $mcpSdk + ')') }
    }
}

$stderrGate = Join-Path $PackRoot 'TESTS\Test-HermesNativeStderr.ps1'
if (-not (Test-Path -LiteralPath $stderrGate)) { Bad 'Hermes native stderr regression missing' }
else {
    & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $stderrGate -PackRoot $PackRoot
    if ($LASTEXITCODE -ne 0) { Bad 'Hermes native stderr handling failed' } else { Good 'Hermes native stderr handling' }
}

& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-HookPrerequisites.ps1') -PackRoot $PackRoot
if ($LASTEXITCODE -ne 0) { Bad 'Hook shell prerequisites failed' } else { Good 'Hook shell prerequisites' }
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-CodexPluginDedupe.ps1') -PackRoot $PackRoot
if ($LASTEXITCODE -ne 0) { Bad 'Codex duplicate plugin repair failed' } else { Good 'Codex duplicate plugin repair' }
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-SharedPython.ps1') -PackRoot $PackRoot
if ($LASTEXITCODE -ne 0) { Bad 'Shared Python selection failed' } else { Good 'Shared Python selection' }
$offlineUpdateOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-OfflineUpdate.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $offlineUpdateOut -match 'OFFLINE UPDATE GATE: PASS') { Good 'Offline updater preserves pinned payloads on candidate mismatch' }
else { Bad ('Offline update gate failed:' + [Environment]::NewLine + $offlineUpdateOut) }
# Require the PASS line, not just exit 0: a script that stops early also exits 0.
$selfUpdateOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-BundleSelfUpdate.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $selfUpdateOut -match 'BUNDLE SELF-UPDATE GATE: PASS') { Good 'START-HERE bundle update decision, forwarding, git fixture and staging exit code' }
else { Bad ('Bundle self-update gate failed:' + [Environment]::NewLine + $selfUpdateOut) }
$jsonCaseOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-JsonCaseKeys.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $jsonCaseOut -match 'JSON CASE-KEY GATE: PASS') { Good 'Provider JSON with case-variant keys: byte-exact round trip, scoped add/remove' }
else { Bad ('JSON case-key gate failed:' + [Environment]::NewLine + $jsonCaseOut) }
$packsOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-Packs.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $packsOut -match 'PACKS GATE: PASS') { Good 'Content packs: detection, remembered choices, instruction blocks, skill retirement' }
else { Bad ('Packs gate failed:' + [Environment]::NewLine + $packsOut) }
$profileOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-UserProfile.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $profileOut -match 'USER PROFILE GATE: PASS') { Good 'Personal profile: seed, machine map, size cap, injection and removal' }
else { Bad ('User profile gate failed:' + [Environment]::NewLine + $profileOut) }
$npmDupOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-NpmDuplicate.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $npmDupOut -match 'NPM DUPLICATE GATE: PASS') { Good 'An older npm copy of a pinned package is removed from either known prefix, after a verified recovery copy' }
else { Bad ('npm duplicate gate failed:' + [Environment]::NewLine + $npmDupOut) }
$probeOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-VersionProbes.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $probeOut -match 'VERSION PROBES GATE: PASS') { Good 'External-install version probes: dotted compare, update stamp, bounded --version' }
else { Bad ('Version probe gate failed:' + [Environment]::NewLine + $probeOut) }
$historyOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-AiHistoryBackup.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $historyOut -match 'AI HISTORY BACKUP GATE: PASS') { Good 'Chat history backup: copies new and changed transcripts, never deletes or overwrites a newer copy' }
else { Bad ('History backup gate failed:' + [Environment]::NewLine + $historyOut) }
$parkOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-McpPark.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $parkOut -match 'MCP PARK GATE: PASS') { Good 'Task-specific MCP servers: park, exact per-project restore, marker detection, no credential printed' }
else { Bad ('MCP park gate failed:' + [Environment]::NewLine + $parkOut) }

Section '2. PowerShell parses (excluding BUNDLED-TOOLS)'
$shippedFiles = @(Get-UabsManifestFiles -PackRoot $PackRoot)
$n = 0; $bad = 0
$shippedFiles | Where-Object { $_.Extension -in @('.ps1','.psm1') } |
    Where-Object { $_.FullName -notlike '*BUNDLED-TOOLS*' } |
    ForEach-Object {
        $n++
        $err = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$err)
        if ($err.Count) { $bad++; Bad "$($_.Name) : $($err[0].Message)" }
    }
if ($n -eq 0) { Bad 'No shipped PowerShell scripts were scanned' }
elseif ($bad -eq 0) { Good "$n scripts parsed" }

Section '3. BOM-less scripts containing non-ASCII (PS 5.1 will mis-decode)'
$risk = 0
$shippedFiles | Where-Object { $_.Extension -in @('.ps1','.psm1','.bat','.cmd') } |
    Where-Object { $_.FullName -notlike '*BUNDLED-TOOLS*' } |
    ForEach-Object {
        $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
        $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
        $nonAscii = @($bytes | Where-Object { $_ -gt 127 }).Count
        if (-not $hasBom -and $nonAscii -gt 0) {
            $risk++
            Bad "$($_.Name): no BOM, $nonAscii non-ASCII bytes"
        }
    }
if ($risk -eq 0) { Good 'no at-risk scripts' }

# Scripts were the only thing checked until v8.3.0. Everything the pack COPIES
# onto a machine was unguarded, and AIO-INSTRUCTION.txt had already been
# corrupted that way once (v7.5.6 cleaned em dashes that had become mojibake in
# exactly that file). These are deployed artifacts, round-tripped by tools whose
# default encoding is the system codepage, so they must stay pure ASCII.
$deployed = @(
    'COPY-TO-YOUR-WORKSPACE\AIO-INSTRUCTION.txt'
    '3-PREAMBLES\MANUAL-PASTE.txt'
    '1-TAILORED-PROVIDER-TREES\Hermes\config.yaml'
    '1-TAILORED-PROVIDER-TREES\Hermes\COPY-TO-PROVIDER-HOME\config.yaml'
    'START-HERE.txt'
    'START-HERE.bat'
    'INSTALL-REMOTE.bat'
    'BOOTSTRAP.txt'
    'VERSION.txt'
)
$deployRisk = 0
foreach ($rel in $deployed) {
    $full = Join-Path $PackRoot $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        $deployRisk++; Bad "deployed artifact missing: $rel"; continue
    }
    $bytes = [System.IO.File]::ReadAllBytes($full)
    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    $nonAscii = 0
    for ($i = $offset; $i -lt $bytes.Length; $i++) { if ($bytes[$i] -gt 127) { $nonAscii++ } }
    if ($nonAscii -gt 0) {
        $deployRisk++
        Bad "$rel : $nonAscii non-ASCII byte(s) in a file this pack copies onto a machine"
    }
}
if ($deployRisk -eq 0) { Good 'every deployed artifact is pure ASCII' }

# Mojibake anywhere is corruption, never intent. Two tools legitimately CONTAIN
# these sequences because they detect them; everything else is a bug.
$mojiAllow = @('audit_skills.py', 'build_canonical_skills.py', 'Test-Pack.ps1', 'test_release_contract.py')
$mojiRisk = 0
$shippedFiles | Where-Object { $_.Extension -in @('.md','.txt','.ps1','.psm1','.json','.yaml','.yml') } |
    Where-Object { $_.FullName -notlike '*BUNDLED-TOOLS*' -and $_.FullName -notlike '*\.git\*' -and
                   $_.FullName -notlike '*docs\history*' -and $_.Name -ne 'README.md' -and
                   $mojiAllow -notcontains $_.Name } |
    ForEach-Object {
        $text = [IO.File]::ReadAllText($_.FullName)
        if ($text -match [char]0xFFFD) {
            $mojiRisk++
            Bad ($_.FullName.Substring($PackRoot.Length).TrimStart('\') + ' contains U+FFFD (decoding already failed on this file)')
        }
    }
if ($mojiRisk -eq 0) { Good 'no replacement characters in shipped text' }

Section '4. Offline assets match OFFLINE-MANIFEST.json'
$manPath = Join-Path $PackRoot 'BUNDLED-TOOLS\OFFLINE-MANIFEST.json'
if (-not (Test-Path $manPath)) {
    Bad 'OFFLINE-MANIFEST.json missing'
} else {
    $man = [IO.File]::ReadAllText($manPath) | ConvertFrom-Json
    foreach ($a in $man.assets) {
        $p = Join-Path $PackRoot "BUNDLED-TOOLS\offline\$($a.file)"
        if (-not (Test-Path $p)) { Bad "missing asset $($a.file)"; continue }
        $h = (Get-FileHash $p -Algorithm SHA256).Hash.ToLower()
        if ($h -ne $a.sha256) { Bad "$($a.file) sha256 mismatch" }
        else { Good "$($a.file)" }
    }
}
# Companion releases are fetched (TOOLS\Get-Companions.ps1), never tracked; when present they must match their index.
$companionIndex = Join-Path $PackRoot 'BUNDLED-TOOLS\offline\companions.json'
$companionRows = @()
if (Test-Path -LiteralPath $companionIndex -PathType Leaf) { $companionRows = @(([IO.File]::ReadAllText($companionIndex) | ConvertFrom-Json).companions) }
foreach ($c in $companionRows) {
    $p = Join-Path $PackRoot "BUNDLED-TOOLS\offline\$($c.asset)"
    if ((Test-Path -LiteralPath $p -PathType Leaf) -and (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -eq $c.sha256) { Good "$($c.asset) (latest $($c.id) release)" }
    else { Bad "$($c.asset) is missing or differs from companions.json" }
}

Section '4b. Release asset cache validates reused filenames'
$releaseCacheGate = Join-Path $PackRoot 'TESTS\Test-ReleaseAssetCache.ps1'
try {
    $releaseCacheOut = & $releaseCacheGate -PackRoot $PackRoot 2>&1 | Out-String
    if ($releaseCacheOut -match 'RELEASE ASSET CACHE GATE: PASS') { Good 'release asset cache gate PASS' }
    else { Bad ('release asset cache gate did not report PASS: ' + $releaseCacheOut.Trim()) }
} catch {
    Bad ('release asset cache gate failed: ' + $_.Exception.Message)
}

$buildOut=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-BuildTools.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $buildOut -match 'BUILD TOOLS GATE: PASS') { Good 'Compiler discovery, check-only and native failure propagation' } else { Bad $buildOut }

Section '5. External Skyrim content ownership'
$packCatalog=Get-UabsPackCatalog -PackRoot $PackRoot
if ($packCatalog.packs.skyrim.owner -eq 'skyrim-forge' -and -not (Test-Path -LiteralPath (Join-Path $PackRoot '_CANONICAL-SKILLS\skyrim-memory'))) {
    Good 'Skyrim content and registry validation belong to Forge'
} else { Bad 'Skyrim content still has duplicate ownership' }
$ownershipOut=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-SkyrimOwnership.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $ownershipOut -match 'OWNERSHIP GATE: PASS') { Good 'External skill preservation and source checkout ownership' } else { Bad $ownershipOut }
$companionOut=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-Companions.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $companionOut -match 'COMPANION GATE: PASS') { Good 'Companion archive, owner reuse and failure boundaries' } else { Bad $companionOut }
$runtimeVersionOut=& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-ForgeRuntimeVersion.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $runtimeVersionOut -match 'FORGE RUNTIME VERSION GATE: PASS') { Good 'Forge runtime version marker works without source bookkeeping' } else { Bad $runtimeVersionOut }

Section '6. Gate self-tests'
$gateDir = Join-Path $PackRoot 'TOOLS\hooks'
foreach ($g in @('completeness_gate.py', 'assumption_gate.py', 'rtk_safe_hook.py')) {
    $gp = Join-Path $gateDir $g
    if (-not (Test-Path -LiteralPath $gp)) { Bad "$g missing"; continue }
    if (-not $py) { Bad "python not found; $g --selftest skipped"; continue }
    $out = & $py.Source $gp --selftest 2>&1 | Out-String
    if ($out -match 'PASS') { Good "$g  self-test PASS" } else { Bad "$g self-test failed: $out" }
}
$wire = Join-Path $gateDir 'hermes_wire.py'
if (-not $py -or -not (Test-Path -LiteralPath $wire)) { Bad 'hermes_wire.py or Python missing' }
else {
    $wireOut = & $py.Source $wire --selftest 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $wireOut -match 'HERMES WIRE SELFTEST: PASS') { Good 'hermes_wire.py self-test PASS' }
    else { Bad ('hermes_wire.py self-test failed: ' + $wireOut.Trim()) }
}
$mcpProbe = Join-Path $PackRoot 'TOOLS\mcp_handshake.py'
if (-not $py -or -not (Test-Path -LiteralPath $mcpProbe -PathType Leaf)) {
    Bad 'mcp_handshake.py or Python missing'
} else {
    $probeOut = & $py.Source $mcpProbe --selftest 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $probeOut -match 'MCP HANDSHAKE SELFTEST: PASS') { Good 'MCP handshake process/stdio self-test PASS' }
    else { Bad ('MCP handshake self-test failed: ' + $probeOut.Trim()) }
}

Section '7. Preamble sources are clean UTF-8 and provider-neutral'
$soulF = Join-Path $PackRoot '3-PREAMBLES\SOUL.md'
$aioF  = Join-Path $PackRoot '0-UNRESTRAINT-PACKS/AIO-INSTRUCTION.md'
foreach ($f in @($soulF, $aioF)) {
    if (-not (Test-Path -LiteralPath $f)) { Bad "missing $(Split-Path $f -Leaf)"; continue }
    $txt = [IO.File]::ReadAllText($f)
    $name = Split-Path $f -Leaf
    # Mojibake signature: a UTF-8 sequence that was decoded as Windows-1252.
    if ($txt -match ([char]0x00E2 + [char]0x20AC)) { Bad "$name contains mojibake" }
    else { Good "$name no mojibake" }
    # Get-Content -Raw uses the ANSI codepage on PS 5.1 and silently corrupts
    # non-ASCII. If these two ever disagree, the installer read path is wrong.
    if ((Get-Content -LiteralPath $f -Raw) -cne $txt) { # ansi-intentional
        Good "$name has non-ASCII (installer must use ReadAllText)"
    }
}
# The block is injected into all five providers, so it must not claim to be any
# one of them. v7.6.0 fixed a SOUL.md that told every agent it was Hermes.
$soulTxt = if (Test-Path -LiteralPath $soulF) { [IO.File]::ReadAllText($soulF) } else { '' }
if ($soulTxt -match 'Hermes Agent|Nous Research|You are Claude|created by (Anthropic|OpenAI|xAI|Moonshot)') {
    Bad 'SOUL.md names a specific provider identity; it is installed into all five'
} else { Good 'SOUL.md is provider-neutral' }
if ($soulTxt) {
    $common = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\UABS-Common.ps1'))
    if ($common -match [regex]::Escape('$soul = ([IO.File]::ReadAllText($SoulFile))')) {
        Good 'Install-UabsPreambleBlock reads preambles as UTF-8'
    } else { Bad 'Install-UabsPreambleBlock no longer uses ReadAllText (mojibake will return)' }

    $probeRoot = Join-Path ([IO.Path]::GetTempPath()) ('uabs-preamble-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $probeRoot | Out-Null
        $probeSoul = Join-Path $probeRoot 'SOUL.md'
        [IO.File]::WriteAllText($probeSoul, $soulTxt, (New-Object Text.UTF8Encoding $false))
        . (Join-Path $PackRoot 'TOOLS\UABS-Common.ps1')
        Install-UabsPreambleBlock -Path $probeSoul -SoulFile $soulF -AioFile $aioF
        $wired = [IO.File]::ReadAllText($probeSoul)
        $soulCopies = ([regex]::Matches($wired, [regex]::Escape($soulTxt.Trim()))).Count
        $aioTxt = [IO.File]::ReadAllText($aioF).Trim()
        if ($soulCopies -eq 1 -and $wired.Contains($aioTxt)) {
            Good 'legacy Hermes base soul upgrades to one combined SOUL + AIO block'
        } else {
            Bad ('legacy Hermes soul migration produced soul copies=' + $soulCopies + ', aio=' + $wired.Contains($aioTxt))
        }
        # v8.7.23: the block is plain text. Comment markers were find-and-replace
        # scaffolding that every provider paid for on every request; stacking
        # copies is what put the operating contract into Hermes' SOUL.md twice.
        $markers = ([regex]::Matches($wired, [regex]::Escape('ULTIMATE-AI-STARTER-BUNDLE'))).Count
        if ($markers -eq 0) { Good 'wired preamble carries no comment markers' }
        else { Bad ("wired preamble still carries $markers marker string(s)") }
        Install-UabsPreambleBlock -Path $probeSoul -SoulFile $soulF -AioFile $aioF
        $again = [IO.File]::ReadAllText($probeSoul)
        $soulAgain = ([regex]::Matches($again, [regex]::Escape($soulTxt.Trim()))).Count
        $aioAgain = ([regex]::Matches($again, [regex]::Escape($aioTxt))).Count
        if ($soulAgain -eq 1 -and $aioAgain -eq 1) { Good 're-wiring replaces the block instead of stacking copies' }
        else { Bad ("re-wiring stacked copies: soul=$soulAgain aio=$aioAgain") }
        # The exact legacy shape that got duplicated: a tail that is only the AIO.
        $probeAio = Join-Path $probeRoot 'AIO-ONLY.md'
        [IO.File]::WriteAllText($probeAio, $aioTxt, (New-Object Text.UTF8Encoding $false))
        Install-UabsPreambleBlock -Path $probeAio -SoulFile $soulF -AioFile $aioF
        $fixed = [IO.File]::ReadAllText($probeAio)
        $soulFixed = ([regex]::Matches($fixed, [regex]::Escape($soulTxt.Trim()))).Count
        $aioFixed = ([regex]::Matches($fixed, [regex]::Escape($aioTxt))).Count
        if ($soulFixed -eq 1 -and $aioFixed -eq 1) { Good 'an AIO-only tail is folded into one block, not duplicated' }
        else { Bad ("AIO-only tail produced soul=$soulFixed aio=$aioFixed") }
    } finally {
        if (Test-Path -LiteralPath $probeRoot) { Remove-Item -LiteralPath $probeRoot -Recurse -Force }
    }
}

& (Join-Path $PackRoot 'TESTS/Test-PreamblePreservation.ps1') -PackRoot $PackRoot

$searchCollapse = Join-Path $PackRoot 'TESTS\Test-SearchCollapse.ps1'
$searchOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $searchCollapse -PackRoot $PackRoot 2>&1 | Out-String
if ($searchOut -match 'SEARCH COLLAPSE GATE: PASS') { Good 'generated skill copies stay out of default search' }
else { Bad ('search collapse gate failed:' + [Environment]::NewLine + $searchOut.Trim()) }

$waitExternal = Join-Path $PackRoot 'TESTS\Test-WaitExternal.ps1'
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $waitExternal -PackRoot $PackRoot
if ($LASTEXITCODE -ne 0) { Bad 'external wait gate failed' }
else { Good 'external waits return an exit code without a model' }

$githubFlags = Join-Path $PackRoot 'TESTS\Test-GitHubFlags.ps1'
$flagsOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $githubFlags -PackRoot $PackRoot 2>&1 | Out-String
if ($flagsOut -match 'GITHUB FLAGS GATE: PASS') { Good 'github flag probe stays local and prints no secrets' }
else { Bad ('github flag gate failed:' + [Environment]::NewLine + $flagsOut.Trim()) }

Section '7b. No script reads a file with the ANSI codepage'
# PS 5.1's Get-Content decodes with the ANSI codepage unless -Encoding is given,
# so any read of a UTF-8 file that is later written back turns non-ASCII into
# mojibake. Measured: a ConvertFrom-Json/ConvertTo-Json round-trip of a real
# ~/.claude.json destroyed all 26 em dashes. v7.6.1 swept 25 call sites to
# [IO.File]::ReadAllText; this stops them coming back.
# Pattern is concatenated so this test's own source cannot match it.
$rxAnsi = 'Get-' + 'Content[^\r\n]*-Raw'
$scanRoots = @(
    (Join-Path $PackRoot 'TOOLS'),
    (Join-Path $PackRoot 'TESTS'),
    $PackRoot
)
$offenders = @()
foreach ($sr in $scanRoots) {
    $depth = if ($sr -eq $PackRoot) { 0 } else { 99 }
    $files = if ($depth -eq 0) {
        Get-ChildItem -LiteralPath $sr -Filter *.ps1 -File -ErrorAction SilentlyContinue
    } else {
        Get-ChildItem -LiteralPath $sr -Filter *.ps1 -File -Recurse -ErrorAction SilentlyContinue
    }
    foreach ($file in $files) {
        $n = 0
        foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
            $n++
            if ($line -notmatch $rxAnsi) { continue }
            if ($line -match '-Encoding') { continue }        # explicit, fine
            if ($line -match 'ansi-intentional') { continue }  # opted out on purpose
            if ($line -match '^\s*#') { continue }             # a comment about it
            $offenders += ('{0}:{1}' -f $file.Name, $n)
        }
    }
}
if ($offenders.Count) {
    Bad ("ANSI-decoding reads found (use [IO.File]::ReadAllText): " + ($offenders -join ', '))
} else {
    Good 'no script decodes a file with the ANSI codepage'
}

# Same trap, but in documentation we ship as copy-paste instructions. Prose that
# *discusses* the bug is fine, and every changelog does; a ```powershell fence is
# not prose, it is code the reader will run. 3-PREAMBLES/README.md shipped a
# manual-install snippet doing exactly this until v7.6.3. docs/history is skipped
# on purpose: those records quote the broken form as a before/after.
$docOffenders = @()
$docFiles = @()
$docFiles += Get-ChildItem -LiteralPath $PackRoot -Filter *.md -File -ErrorAction SilentlyContinue
foreach ($sub in @('3-PREAMBLES', 'PROMPTS', 'TOOLS', 'TESTS', 'docs')) {
    $d = Join-Path $PackRoot $sub
    if (Test-Path -LiteralPath $d) {
        $docFiles += Get-ChildItem -LiteralPath $d -Filter *.md -File -ErrorAction SilentlyContinue
    }
}
foreach ($file in $docFiles) {
    $inPs = $false
    $n = 0
    foreach ($line in [IO.File]::ReadAllLines($file.FullName)) {
        $n++
        if ($line -match '^\s*```') {
            if ($inPs) { $inPs = $false }
            elseif ($line -match '^\s*```\s*(powershell|ps1|pwsh)') { $inPs = $true }
            continue
        }
        if (-not $inPs) { continue }
        if ($line -notmatch $rxAnsi) { continue }
        if ($line -match '-Encoding') { continue }
        if ($line -match 'ansi-intentional') { continue }
        if ($line -match '^\s*#') { continue }
        $docOffenders += ('{0}:{1}' -f $file.Name, $n)
    }
}
if ($docOffenders.Count) {
    Bad ("docs teach an ANSI-decoding read in a powershell fence: " + ($docOffenders -join ', '))
} else {
    Good 'no shipped powershell snippet teaches the ANSI trap'
}

# One soul source, not two. v7.6.0 genericised SOUL.md; SOUL-UNIVERSAL.md then
# existed only as a byte-identical duplicate whose README still described it as
# the de-Hermesed copy -- an invitation to put the provider identity back.
$soulSrc = Join-Path (Join-Path $PackRoot '3-PREAMBLES') 'SOUL.md'
$soulDup = Join-Path (Join-Path $PackRoot '3-PREAMBLES') 'SOUL-UNIVERSAL.md'
if (Test-Path -LiteralPath $soulDup) {
    Bad 'SOUL-UNIVERSAL.md is back; there must be exactly one soul source'
} else {
    Good 'exactly one soul source (SOUL.md)'
}
$instTxt = [IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-AIO.ps1'))
if ($instTxt -match "Join-Path \`$preDir 'SOUL-UNIVERSAL\.md'") {
    Bad 'installer wires SOUL-UNIVERSAL.md instead of the single SOUL.md'
} else {
    Good 'installer wires the single SOUL.md to every provider'
}

Section '8. Repair-McpPaths resolves a version-stamped path'
$repair = Join-Path $PackRoot (Join-Path 'TOOLS' 'Repair-McpPaths.ps1')
if (-not (Test-Path -LiteralPath $repair)) { Bad 'TOOLS\Repair-McpPaths.ps1 missing' }
else {
    # Sandbox: a dead Widget-1.0.0 and a live Widget-1.2.0, so the resolver has
    # to pick the highest version whose target file actually exists.
    $sandbox = Join-Path $env:TEMP ('v7mcprepair-' + [guid]::NewGuid().ToString('N').Substring(0,8))
    try {
        $liveDir = Join-Path (Join-Path $sandbox 'Widget-1.2.0') 'bin'
        New-Item -ItemType Directory -Force -Path $liveDir | Out-Null
        # Canonicalise both. On the GitHub runner $env:TEMP is the 8.3 short
        # form (C:\Users\RUNNER~1\...) while Get-ChildItem's .FullName -- what
        # the resolver returns -- gives the long form (runneradmin). Same file,
        # two spellings, and a plain string compare fails on the difference.
        $sandbox = (Get-Item -LiteralPath $sandbox).FullName
        $liveDir = (Get-Item -LiteralPath $liveDir).FullName
        # A higher version that is missing the target file must be ignored.
        New-Item -ItemType Directory -Force -Path (Join-Path $sandbox 'Widget-1.3.0') | Out-Null
        $liveExe = Join-Path $liveDir 'tool.exe'
        Set-Content -LiteralPath $liveExe -Value 'x'
        # Dot-source only the two resolver functions, not the whole report.
        $src = [IO.File]::ReadAllText($repair)
        $fn1 = [regex]::Match($src, '(?ms)^function Get-NormalPath.*?^\}').Value
        $fn2 = [regex]::Match($src, '(?ms)^function Resolve-LivePath.*?^\}').Value
        if (-not $fn1 -or -not $fn2) { Bad 'could not extract resolver functions' }
        else {
            . ([scriptblock]::Create($fn1 + "`n" + $fn2))
            $dead = Join-Path (Join-Path (Join-Path $sandbox 'Widget-1.0.0') 'bin') 'tool.exe'
            $got = Resolve-LivePath $dead
            if ($got -eq $liveExe) { Good 'resolver picks highest version that really exists' }
            else { Bad "resolver returned '$got', expected '$liveExe'" }
            # No version-stamped folder in the path: it must refuse to guess.
            $got2 = Resolve-LivePath (Join-Path (Join-Path $sandbox 'nothing') 'here.exe')
            if ($null -eq $got2) { Good 'resolver refuses to guess unversioned paths' }
            else { Bad "resolver invented a replacement: $got2" }

            # The bundle registers houseCARL via the HOUSECARL_MCP env, and the
            # resolver must repoint a dead housecarl-mcp.exe from that registry
            # (its live root is not a version-stamped sibling of the dead path).
            $envMcpBak = $env:HOUSECARL_MCP
            try {
              $env:HOUSECARL_MCP = $liveExe
              $got3 = Resolve-LivePath (Join-Path (Join-Path $sandbox 'houseCARL') 'server\housecarl-mcp.exe')
              if ($got3 -eq $liveExe) { Good 'dead housecarl-mcp.exe repoints from HOUSECARL_MCP env' }
              else { Bad "env fallback returned '$got3', expected '$liveExe'" }
            } finally {
              if ($null -eq $envMcpBak) { Remove-Item Env:HOUSECARL_MCP -ErrorAction SilentlyContinue }
              else { $env:HOUSECARL_MCP = $envMcpBak }
            }

            # Escaping. A JSON config stores every separator doubled; writing a
            # lone backslash back produces an invalid escape and an unparseable
            # config. Two earlier attempts got this wrong in opposite directions
            # (one under-escaped, one produced four), so it is asserted here.
            $fnEsc = [regex]::Match($src, '(?ms)^function ConvertTo-ConfigLiteral.*?^\}').Value
            if (-not $fnEsc) { Bad 'ConvertTo-ConfigLiteral not found in Repair-McpPaths.ps1' }
            else {
                . ([scriptblock]::Create($fnEsc))
                $liveP = 'S:' + [char]92 + 'Tools' + [char]92 + 'App-1.2.0' + [char]92 + 'py.exe'
                $bs = [string][char]92
                $deadJson = 'S:' + $bs + $bs + 'Tools' + $bs + $bs + 'App-1.1.0' + $bs + $bs + 'py.exe'
                $deadToml = 'S:' + $bs + 'Tools' + $bs + 'App-1.1.0' + $bs + 'py.exe'
                $wantJson = 'S:' + $bs + $bs + 'Tools' + $bs + $bs + 'App-1.2.0' + $bs + $bs + 'py.exe'
                $gotJson = ConvertTo-ConfigLiteral -LivePath $liveP -DeadLiteral $deadJson
                if ($gotJson -ceq $wantJson) { Good 'JSON config keeps its doubled separators' }
                else { Bad "escaping wrong: got [$gotJson] want [$wantJson]" }
                $gotToml = ConvertTo-ConfigLiteral -LivePath $liveP -DeadLiteral $deadToml
                if ($gotToml -ceq $liveP) { Good 'TOML/YAML config keeps single separators' }
                else { Bad "escaping wrong: got [$gotToml] want [$liveP]" }
                # End to end: the rewritten JSON must still parse.
                $doc = '{"c":"' + $deadJson + '"}'
                try {
                    $round = ($doc.Replace($deadJson, $gotJson) | ConvertFrom-Json)
                    if ($round.c -ceq $liveP) { Good 'repointed JSON still parses to the live path' }
                    else { Bad "round trip produced $($round.c)" }
                } catch { Bad "repointed JSON no longer parses: $_" }
            }
        }
    } finally {
        Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Section '9. Provider starter settings are portable (no live-machine dump)'
$starterFiles = @(
    '1-TAILORED-PROVIDER-TREES\Claude\COPY-TO-PROVIDER-HOME\settings.json',
    '1-TAILORED-PROVIDER-TREES\Codex\COPY-TO-PROVIDER-HOME\config.toml',
    '1-TAILORED-PROVIDER-TREES\Grok\COPY-TO-PROVIDER-HOME\config.toml',
    '1-TAILORED-PROVIDER-TREES\Kimi\COPY-TO-PROVIDER-HOME\config.toml',
    '1-TAILORED-PROVIDER-TREES\Hermes\COPY-TO-PROVIDER-HOME\config.yaml',
    'TOOLS\Install-Provider-Starter-Settings.ps1'
)
foreach ($rel in $starterFiles) {
    $p = Join-Path $PackRoot $rel
    if (-not (Test-Path -LiteralPath $p)) { Bad "missing $rel"; continue }
    $raw = [IO.File]::ReadAllText($p)
    if ($raw -match '(?i)C:\\Users\\[^\\\s"]+' -or $raw -match '(?i)S:\\Apps\\') {
        Bad "$rel contains a machine path"
    } else { Good $rel }
}
$aio = [IO.File]::ReadAllText((Join-Path $PackRoot 'INSTALL-AIO.ps1'))
if ($aio -match 'Install-Provider-Starter-Settings') { Good 'AIO calls starter-settings installer' }
else { Bad 'INSTALL-AIO.ps1 does not call Install-Provider-Starter-Settings.ps1' }
if ($aio -match 'Copy-Item -LiteralPath \$hCfgSrc -Destination \$hCfg') {
    Bad 'AIO still wholesale-copies Hermes config.yaml over a live home'
} else { Good 'AIO no longer overwrites a live Hermes config.yaml' }
$starterSrc = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\Install-Provider-Starter-Settings.ps1'))
if ($starterSrc -match '(?mi)\$home\s*=') {
    Bad 'Install-Provider-Starter-Settings.ps1 assigns $HOME (PowerShell constant; aborts the starter pass)'
} else { Good 'starter settings do not assign $HOME' }
$doctorSrc = [IO.File]::ReadAllText((Join-Path $PackRoot 'TOOLS\Test-Installed-State.ps1'))
if ($doctorSrc -match '(?mi)^\s*\$home\s*=') {
    Bad 'Test-Installed-State.ps1 assigns $HOME (PowerShell constant; aborts the final doctor)'
} else { Good 'installed-state doctor does not assign $HOME' }
if ($doctorSrc -match 'bundle-contract') {
    Bad 'installed-state doctor still calls removed Forge 5.x bundle-contract'
} elseif ($doctorSrc -match '-m\s+skyrim_forge\s+doctor') { Good 'installed-state doctor uses Forge 6 health contract' }
else { Bad 'installed-state doctor does not run Forge doctor' }
# Section 17 executes Set-UabsGrokCompatCells on real temp configs and verifies
# all three default cells; a source-string match cannot prove the written TOML.
if ($aio -match 'Repair-UabsGrokDuplicatePlugins') {
    Good 'AIO collapses duplicate Grok superpowers plugins'
} else { Bad 'INSTALL-AIO.ps1 does not call Repair-UabsGrokDuplicatePlugins' }
if ($aio -match "Invoke-UabsSkillDedupe -Provider 'Grok'") {
    Bad 'AIO still dedupes Grok superpowers copies (TUI then fails with no reason)'
} else { Good 'AIO leaves Grok superpowers copies in ~/.grok/skills' }
if ($aio -match "Invoke-UabsSkillDedupe -Provider 'Hermes'") {
    Bad 'AIO still dedupes Hermes superpowers/ponytail copies (slash commands and autofill then disappear)'
} else { Good 'AIO leaves Hermes plugin copies in the skills dir (slash commands load that path)' }
if ($aio -match 'Remove-UabsHermesForeignHarnessDirs') {
    Good 'AIO strips foreign Superpowers manifests from the Hermes bridge'
} else { Bad 'INSTALL-AIO.ps1 does not strip foreign Superpowers manifests for Hermes' }
$migAt = $aio.IndexOf('Migrate-HermesProfiles.ps1')
$restartAt = $aio.IndexOf('Hermes gateway restarted after config writes')
if ($migAt -ge 0 -and $restartAt -gt $migAt) {
    Good 'AIO restarts the Hermes gateway only after profile migration'
} else { Bad 'Hermes gateway restart is not after Migrate-HermesProfiles.ps1' }
if ($aio -match 'Hermes gateway restarted \(it was running before plugin refresh\)') {
    Bad 'AIO still restarts the Hermes gateway inside the plugin refresh'
} else { Good 'AIO does not restart the Hermes gateway inside plugin refresh' }
$stripRoot = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hermes-strip-' + [guid]::NewGuid().ToString('n'))
try {
    New-Item -ItemType Directory -Force -Path (Join-Path $stripRoot '.hermes-plugin') | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $stripRoot 'skills\using-superpowers') | Out-Null
    [IO.File]::WriteAllText((Join-Path $stripRoot '.hermes-plugin\plugin.yaml'), "name: superpowers`n")
    [IO.File]::WriteAllText((Join-Path $stripRoot 'skills\using-superpowers\SKILL.md'), "---\nname: using-superpowers\n---\n")
    foreach ($foreign in @('.claude-plugin', '.codex-plugin', '.cursor-plugin', '.devin-plugin', '.kimi-plugin', '.muse-plugin')) {
        $dir = Join-Path $stripRoot $foreign
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'plugin.json'), '{ "name": "superpowers" }')
    }
    $stripped = @(Remove-UabsHermesForeignHarnessDirs -PluginRoot $stripRoot)
    $left = @($stripped | Where-Object { $_ })
    $stillThere = @()
    foreach ($foreign in @('.claude-plugin', '.codex-plugin', '.cursor-plugin', '.devin-plugin', '.kimi-plugin', '.muse-plugin')) {
        if (Test-Path -LiteralPath (Join-Path $stripRoot ($foreign + '\plugin.json'))) { $stillThere += $foreign }
    }
    $adapterOk = Test-Path -LiteralPath (Join-Path $stripRoot '.hermes-plugin\plugin.yaml')
    $skillOk = Test-Path -LiteralPath (Join-Path $stripRoot 'skills\using-superpowers\SKILL.md')
    if ($left.Count -eq 6 -and -not $stillThere.Count -and $adapterOk -and $skillOk) {
        Good 'Hermes Superpowers strip removes the six foreign manifests and keeps the adapter'
    } else {
        Bad ("Hermes Superpowers strip mismatch removed=$($left.Count) left=$($stillThere -join ',') adapter=$adapterOk skill=$skillOk")
    }
    $bundleSuper = Join-Path $PackRoot 'BUNDLED-TOOLS\plugins\superpowers'
    $guarded = $false
    try { Remove-UabsHermesForeignHarnessDirs -PluginRoot $bundleSuper } catch { $guarded = $true }
    if ($guarded -and (Test-Path -LiteralPath (Join-Path $bundleSuper '.kimi-plugin\plugin.json'))) {
        Good 'foreign-manifest strip refuses the shared Superpowers tree'
    } else { Bad 'foreign-manifest strip did not protect BUNDLED-TOOLS\plugins\superpowers' }
    $ledger = Join-Path $stripRoot 'last-github-update.json'
    [IO.File]::WriteAllText($ledger, "{`n  `"id`": `"rtk`",`n  `"tag`": `"v0.46.0`"`n}`n")
    Update-UabsComponentLedger -Path $ledger -Updates @(@{ id = 'rtk'; installed_version = '0.47.0' })
    $one = [IO.File]::ReadAllText($ledger) | ConvertFrom-Json
    Update-UabsComponentLedger -Path $ledger -Updates @(@{ id = 'playwright-cli'; installed_version = '@playwright/cli@0.1.20' })
    $two = [IO.File]::ReadAllText($ledger) | ConvertFrom-Json
    $ids = @($two.components | ForEach-Object { [string]$_.id })
    $rtkRow = @($two.components | Where-Object { $_.id -eq 'rtk' }) | Select-Object -First 1
    if ($one.schema -eq 1 -and @($one.components).Count -eq 1 -and $ids.Count -eq 2 -and $rtkRow.tag -eq 'v0.46.0' -and $rtkRow.installed_version -eq '0.47.0' -and ($ids -contains 'playwright-cli')) {
        Good 'component ledger keeps an array and merges installed versions'
    } else { Bad 'component ledger did not merge a legacy single object into a stable array' }
} finally {
    if (Test-Path -LiteralPath $stripRoot) { Remove-Item -LiteralPath $stripRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
$grokStarter = [IO.File]::ReadAllText((Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\Grok\COPY-TO-PROVIDER-HOME\config.toml'))
if ($grokStarter -match '(?m)^\s*skills\s*=\s*false\s*$') {
    Good 'Grok starter config.toml sets compat.claude skills = false'
} else { Bad 'Grok starter config.toml missing skills = false' }

Section '10. Forge framework truth lock (SPID/KID grammar anti-drift)'
# Runs against the latest Forge release Get-Companions.ps1 fetched; Core and offline runs delegate to Forge.
$forgeRow=@($companionRows | Where-Object { $_.id -eq 'skyrim-forge' }) | Select-Object -First 1
$forgeZip=if ($forgeRow) { Join-Path $PackRoot ('BUNDLED-TOOLS\offline\'+$forgeRow.asset) } else { $null }
if (-not $forgeZip -or -not (Test-Path -LiteralPath $forgeZip)) { Good 'Skyrim framework content check delegated to Forge (no fetched release)' }
else {
    $proofRoot=Join-Path ([IO.Path]::GetTempPath()) ('uabs-forge-proof-'+[guid]::NewGuid().ToString('N'))
    try {
        if ((Get-FileHash -LiteralPath $forgeZip -Algorithm SHA256).Hash -ine $forgeRow.sha256) { throw 'Fetched Forge archive differs from companions.json.' }
        Expand-UabsZip -Zip $forgeZip -Dest $proofRoot
        $ownerRoot=Resolve-UabsSingleRoot $proofRoot
        $truthLock=Join-Path $ownerRoot 'integrations\skyrim-pack\skills\skyrim-distr-kid-validation\scripts\verify_framework_truth.py'
        if (-not $py) { throw 'Python missing for framework truth checks.' }
        $out=& $py.Source $truthLock 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0 -and $out -match 'FRAMEWORK TRUTH LOCK: PASS') { Good ('Forge ' + $forgeRow.version + ' framework truth and production-path fixtures PASS') }
        else { Bad ('Owner framework truth lock failed: '+$out.Trim()) }
    } catch { Bad ('Forge framework check failed: '+$_.Exception.Message) }
    finally { if (Test-UabsPathWithin $proofRoot ([IO.Path]::GetTempPath())) { Remove-Item -LiteralPath $proofRoot -Recurse -Force -ErrorAction SilentlyContinue } }
}

Section '11. Forge install root is versionless (upgrade cannot orphan five MCP configs)'
# The failure this exists for: every provider stores the MCP command as a hard
# absolute path, so a version-stamped install directory renames itself out from
# under five configs on upgrade, and a provider that cannot spawn its server
# fails silently -- it just shows no tools. 7.8.0 shipped an installer that
# extracted to Skyrim-Forge-<version>, and Repair-McpPaths.ps1 existed to clean
# up after it. The cure is that the directory name never changes.
$forgeRootGate = Join-Path $PackRoot 'TESTS\Test-ForgeRootResolution.ps1'
if (-not (Test-Path -LiteralPath $forgeRootGate -PathType Leaf)) {
    Bad 'TESTS\Test-ForgeRootResolution.ps1 missing from the pack'
} else {
    $rootOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $forgeRootGate -PackRoot $PackRoot 2>&1 | Out-String
    if ($rootOut -match 'FORGE ROOT RESOLUTION: PASS') {
        Good 'Forge install root resolution PASS'
    } else {
        Bad ('Forge install root resolution failed:' + [Environment]::NewLine + ($rootOut.Trim()))
    }
}


Section '12. Provider skill sync is content-authoritative on Windows'
$providerSyncGate = Join-Path $PackRoot 'TESTS\Test-ProviderSkillSync.ps1'
if (-not (Test-Path -LiteralPath $providerSyncGate -PathType Leaf)) {
    Bad 'TESTS\Test-ProviderSkillSync.ps1 missing from the pack'
} else {
    $syncOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $providerSyncGate -PackRoot $PackRoot 2>&1 | Out-String
    if ($syncOut -match 'PROVIDER SKILL SYNC: PASS') {
        Good 'Provider skill same-metadata overwrite + user-skill preservation PASS'
    } else {
        Bad ('Provider skill sync regression failed:' + [Environment]::NewLine + ($syncOut.Trim()))
    }
}

Section '12b. Hermes scanner override is temporary and reversible'
$common = Join-Path $PackRoot 'TOOLS\UABS-Common.ps1'
$scanFx = Join-Path ([IO.Path]::GetTempPath()) ('uabs-hermes-scan-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scanFx | Out-Null
try {
    . $common
    $cases = @(
        @{ name='missing'; body="plugins:`n  enabled: []`n"; state='inserted'; final='' },
        @{ name='true'; body="plugins:`n  scan_on_install: true # keep`n"; state='changed-true'; final='scan_on_install: true # keep' },
        @{ name='operator-false'; body="plugins:`n  scan_on_install: false # mine`n"; state='already-present'; final='scan_on_install: false # mine' }
    )
    $wrong = @()
    foreach ($case in $cases) {
        $cfg = Join-Path $scanFx ($case.name + '.yaml')
        [IO.File]::WriteAllText($cfg, $case.body)
        $state = Set-UabsHermesPluginScanOff $cfg
        if ($state -ne $case.state -or [IO.File]::ReadAllText($cfg) -notmatch '(?m)^  scan_on_install: false') { $wrong += $case.name; continue }
        [void](Restore-UabsHermesPluginScan $cfg $state)
        $final = [IO.File]::ReadAllText($cfg)
        if (($case.final -and $final -notmatch [regex]::Escape($case.final)) -or
            (-not $case.final -and $final -match '(?m)^  scan_on_install:')) { $wrong += $case.name }
    }
    if ($wrong.Count) { Bad ('Hermes scan lifecycle failed: ' + ($wrong -join ', ')) }
    else { Good 'Hermes scanner setting is restored for inserted, true, and operator-false cases' }
} finally {
    Remove-Item -LiteralPath $scanFx -Recurse -Force -ErrorAction SilentlyContinue
}


function Test-UabsPackPath([string]$Path) {
  if ([string]::IsNullOrEmpty($Path)) { return $false }
  try { return [bool](Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction SilentlyContinue) }
  catch { return $false }
}

Section '13. MCP profile catalog and the shared config writer'
# Both MCP writers share TOOLS\UABS-Mcp-Write.ps1. Every config bug this pack has
# shipped was a bug in one of three config shapes that the other two did not
# have, and each was found on a user's machine rather than in a test.
$mcpGate = Join-Path $PackRoot 'TESTS\Test-McpProfiles.ps1'
if (-not (Test-Path -LiteralPath $mcpGate -PathType Leaf)) {
    Bad 'TESTS\Test-McpProfiles.ps1 missing from the pack'
} else {
    $mcpOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $mcpGate -PackRoot $PackRoot 2>&1 | Out-String
    if ($mcpOut -match 'MCP PROFILE GATE: PASS') {
        Good 'MCP profile catalog + shared config writer PASS'
    } else {
        Bad ('MCP profile gate failed:' + [Environment]::NewLine + ($mcpOut.Trim()))
    }
}
$taskGate = Join-Path $PackRoot 'TESTS\Test-TaskRecipes.ps1'
if (-not (Test-Path -LiteralPath $taskGate -PathType Leaf)) { Bad 'TESTS\Test-TaskRecipes.ps1 missing' }
else {
    $taskOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $taskGate -PackRoot $PackRoot 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $taskOut -match 'TASK RECIPE GATE: PASS') { Good 'Task routing, composition, scoped activation and personal-config preservation PASS' }
    else { Bad ('Task recipe gate failed: ' + $taskOut.Trim()) }
}
Section '14. Evidence-behaviour scenarios still contain their defects'
# These fixtures measure whether an agent goes and looks instead of guessing.
# Scoring the agent is a judgement; scoring the FIXTURE is not, and a benchmark
# whose defects have quietly been repaired passes everything while measuring
# nothing.
$scenCheck = Join-Path $PackRoot 'TESTS\evidence-scenarios\check_fixtures.py'
if (-not (Test-UabsPackPath $scenCheck)) {
    Bad 'TESTS\evidence-scenarios\check_fixtures.py missing from the pack'
} elseif (-not $py) {
    Bad 'python not found; evidence scenario fixtures skipped'
} else {
    $scenOut = & $py.Source $scenCheck 2>&1 | Out-String
    if ($scenOut -match 'EVIDENCE SCENARIOS: fixtures intact') {
        Good 'evidence scenario fixtures intact'
    } else {
        Bad ('evidence scenario fixtures no longer test what they claim:' + [Environment]::NewLine + ($scenOut.Trim()))
    }
}

# Routing fixtures: A's payload must stay unreachable without rendering and B's
# must stay reachable without it. They are a matched pair, and if either drifts
# the benchmark stops measuring the distinction the release exists for.
$routeCheck = Join-Path $PackRoot 'TESTS\routing-scenarios\check_fixtures.py'
if (-not (Test-UabsPackPath $routeCheck)) {
    Bad 'TESTS\routing-scenarios\check_fixtures.py missing from the pack'
} elseif (-not $py) {
    Bad 'python not found; routing scenario fixtures skipped'
} else {
    $routeOut = & $py.Source $routeCheck 2>&1 | Out-String
    if ($routeOut -match 'ROUTING SCENARIOS: fixtures intact') {
        Good 'routing scenario fixtures intact'
    } else {
        Bad ('routing scenario fixtures no longer test what they claim:' + [Environment]::NewLine + ($routeOut.Trim()))
    }
}

# The vision canary is the falsifiable half of visual-verification. If a wrong
# answer passes it, the skill is back to being an unverifiable instruction.
$canaryChk = Join-Path $PackRoot 'TOOLS\Test-VisionCanary.ps1'
if (-not (Test-UabsPackPath $canaryChk)) {
    Bad 'TOOLS\Test-VisionCanary.ps1 missing from the pack'
} else {
    $canOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $canaryChk `
                -Word 'not' -Shape 'the' -Color 'answer' 2>&1 | Out-String
    if ($canOut -match 'VISION CANARY: FAIL') { Good 'the vision canary rejects a wrong answer' }
    else { Bad ('the vision canary accepted an answer that cannot have come from the image:' + [Environment]::NewLine + $canOut.Trim()) }
}

Section '15. Starter templates cannot smuggle MCP servers onto a fresh machine'
# Through 7.9.7 the Hermes starter carried five live servers and this gate said
# PASS. Install-Provider-Starter-Settings.ps1 copies a template WHOLE onto a
# machine with no config, so anything left in one is a fresh-install default.
# A contract in the python suite checks the guard still exists; this checks it
# still WORKS, which is the part that protects a user's machine.
$starterPs = Join-Path $PackRoot 'TOOLS\Install-Provider-Starter-Settings.ps1'
if (-not (Test-UabsPackPath $starterPs)) {
    Bad 'TOOLS\Install-Provider-Starter-Settings.ps1 missing from the pack'
} else {
    $guardSrc = [IO.File]::ReadAllText($starterPs)
    $guardFn = [regex]::Match($guardSrc, '(?s)function Test-UabsPortableTemplate \{.*?\r?\n\}')
    if (-not $guardFn.Success) {
        Bad 'Test-UabsPortableTemplate not found in the starter installer'
    } else {
        . ([scriptblock]::Create($guardFn.Value))

        # 1. Every template the pack actually ships must be accepted.
        $refused = @()
        Get-ChildItem (Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\*\COPY-TO-PROVIDER-HOME\*') -File |
          ForEach-Object {
            try { Test-UabsPortableTemplate -Path $_.FullName }
            catch { $refused += ($_.Directory.Parent.Name + '\' + $_.Name) }
          }
        if ($refused.Count) { Bad ('shipped starter templates refused by the guard: ' + ($refused -join ', ')) }
        else { Good 'all shipped starter templates pass the portability guard' }

        # 2. Each defect 7.9.7 shipped must be refused, plus the comment case
        #    that must NOT be -- the explanation names the banned literals.
        $fx = Join-Path ([IO.Path]::GetTempPath()) ('uabs-starter-fx-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Force -Path $fx | Out-Null
        try {
            $cases = [ordered]@{
                'live-yaml.yaml' = @{ refuse = $true;  body = "model:`n  a: b`nmcp_servers:`n  firecrawl:`n    command: npx`n" }
                'live-toml.toml' = @{ refuse = $true;  body = "model = 'x'`n[mcp_servers.github]`ncommand = 'npx'`n" }
                'live-json.json' = @{ refuse = $true;  body = '{"mcpServers":{"github":{"command":"npx"}}}' }
                'unpinned.yaml'  = @{ refuse = $true;  body = "mcp_servers: {}`na: '@playwright/mcp@latest'`n" }
                'clean.yaml'     = @{ refuse = $false; body = "# mcp_servers: only a comment, and @latest in prose`nmcp_servers: {}`nmodel:`n  a: b`n" }
            }
            $wrong = @()
            foreach ($n in $cases.Keys) {
                $p = Join-Path $fx $n
                [IO.File]::WriteAllText($p, $cases[$n].body)
                $threw = $false
                try { Test-UabsPortableTemplate -Path $p } catch { $threw = $true }
                if ($threw -ne $cases[$n].refuse) {
                    $wrong += ('{0} (expected {1})' -f $n, $(if ($cases[$n].refuse) { 'refused' } else { 'accepted' }))
                }
            }
            if ($wrong.Count) { Bad ('starter guard verdicts wrong for: ' + ($wrong -join ', ')) }
            else { Good 'starter guard refuses live MCP entries and @latest, and tolerates comments' }
        } finally {
            Remove-Item -LiteralPath $fx -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# The Hermes starter is the file that actually regressed. Check the shipped
# artifact directly, not only the guard that is supposed to protect it.
$hermesCfg = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\Hermes\COPY-TO-PROVIDER-HOME\config.yaml'
if (-not (Test-UabsPackPath $hermesCfg)) {
    Bad 'Hermes starter config.yaml missing from the pack'
} else {
    $hraw = [IO.File]::ReadAllText($hermesCfg)
    $hcode = (($hraw -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    $banned = @('sequential-thinking', '@modelcontextprotocol/server-github', '@latest', 'firecrawl-mcp')
    $found = @($banned | Where-Object { $hcode -match [regex]::Escape($_) })
    if ($found.Count) { Bad ('the Hermes starter would register: ' + ($found -join ', ')) }
    elseif ($hcode -notmatch '(?m)^mcp_servers:\s*\{\s*\}') { Bad 'the Hermes starter no longer declares an empty mcp_servers' }
    else { Good 'a fresh Hermes install inherits no MCP servers from the template' }
}

Section '15a. Hermes JSON inventory excludes native stderr notices'
$inventoryFn = [regex]::Match([IO.File]::ReadAllText($starterPs), '(?s)function Remove-UabsHermesLegacyOpenRouterExtra \{.*?\r?\n\}')
$inventoryProbe = [regex]::Match($inventoryFn.Value, '(?s)try \{\s*\$output = .*?finally \{ \$ErrorActionPreference = \$prevEap \}')
if (-not $inventoryProbe.Success) { Bad 'Hermes inventory stdout/stderr probe not found' }
else {
    $fixture = Join-Path ([IO.Path]::GetTempPath()) ('uabs-json-stream-' + [guid]::NewGuid().ToString('N') + '.cmd')
    try {
        $exe = $fixture; $key = 'providers'
        foreach ($missing in @($false, $true)) {
            $body = if ($missing) { "@echo off`r`necho Config key not set: providers 1>&2`r`nexit /b 1`r`n" }
                    else { "@echo off`r`necho {`"fixture`":true}`r`necho harmless runtime notice 1>&2`r`nexit /b 0`r`n" }
            [IO.File]::WriteAllText($fixture, $body, [Text.Encoding]::ASCII)
            $prevEap = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            . ([scriptblock]::Create($inventoryProbe.Value))
            if ($missing) {
                if ($code -ne 1 -or ($output | Out-String) -notmatch 'Config key not set') { throw 'missing-key stderr was lost' }
            } elseif ($code -ne 0 -or -not ($raw | ConvertFrom-Json).fixture) { throw 'stderr contaminated JSON stdout' }
        }
        Good 'valid JSON survives stderr notices; missing-key stderr remains available'
    } catch { Bad ('Hermes inventory stream regression: ' + $_.Exception.Message) }
    finally { Remove-Item -LiteralPath $fixture -Force -ErrorAction SilentlyContinue }
}

Section '15b. SillyTavern gateway stays a roleplay profile'
$stInstaller = Join-Path $PackRoot 'TOOLS\Install-SillyTavernGateway.ps1'
$stTemplate = Join-Path $PackRoot '1-TAILORED-PROVIDER-TREES\Hermes\profiles\sillytavern\config.yaml'
if (-not (Test-Path -LiteralPath $stInstaller) -or -not (Test-Path -LiteralPath $stTemplate)) {
    Bad 'SillyTavern gateway installer or profile template is missing'
} else {
    $stRaw = [IO.File]::ReadAllText($stTemplate)
    $stCode = (($stRaw -split "`r?`n") | Where-Object { $_ -notmatch '^\s*#' }) -join "`n"
    $bannedTools = @('terminal', 'code_execution', 'browser', 'computer_use')
    $inApi = [regex]::Match($stCode, '(?s)platform_toolsets:\s*\r?\n\s*api_server:\s*\r?\n(?<body>(?:\s+-\s+\S+\s*\r?\n)+)')
    $apiBody = if ($inApi.Success) { $inApi.Groups['body'].Value } else { '' }
    $leaked = @($bannedTools | Where-Object { $apiBody -match ('(?m)^\s+-\s+' + [regex]::Escape($_) + '\s*$') })
    $needed = @('vision', 'image_gen', 'web', 'file', 'memory', 'skills')
    $missingTools = @($needed | Where-Object { $apiBody -notmatch ('(?m)^\s+-\s+' + [regex]::Escape($_) + '\s*$') })
    if (-not $inApi.Success) { Bad 'SillyTavern profile has no api_server toolset list' }
    elseif ($leaked.Count) { Bad ('SillyTavern api_server still enables ' + ($leaked -join ', ')) }
    elseif ($missingTools.Count) { Bad ('SillyTavern api_server is missing ' + ($missingTools -join ', ')) }
    elseif ($stCode -match 'sk-or-|ghp_|hsg_') { Bad 'SillyTavern profile template contains a live credential' }
    else { Good 'SillyTavern api_server toolset is roleplay-only' }

    $fxHome = Join-Path ([IO.Path]::GetTempPath()) ('uabs-st-gateway-' + [guid]::NewGuid().ToString('n'))
    try {
        New-Item -ItemType Directory -Force -Path $fxHome | Out-Null
        [IO.File]::WriteAllText((Join-Path $fxHome '.env'), "API_SERVER_ENABLED=true`r`nAPI_SERVER_KEY=local-test-key-not-a-secret`r`nAPI_SERVER_PORT=8642`r`n")
        & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $stInstaller -PackRoot $PackRoot -HermesHome $fxHome | Out-Null
        $skillOk = @(
            'skills\sillytavern-gateway\SKILL.md',
            'skills\adult-character-sheet\SKILL.md',
            'skills\adult-image-caption\SKILL.md'
        ) | Where-Object { -not (Test-Path -LiteralPath (Join-Path $fxHome ('profiles\sillytavern\' + $_))) }
        $link = Get-Item -LiteralPath (Join-Path $fxHome 'profiles\sillytavern\.env')
        $launcher = [IO.File]::ReadAllText((Join-Path $fxHome 'START-HERMES-GATEWAY.ps1'))
        if ($skillOk.Count) { Bad ('SillyTavern install missed skills: ' + ($skillOk -join ', ')) }
        elseif ($link.LinkType -ne 'HardLink') { Bad 'SillyTavern profile .env was not hard-linked to the home .env' }
        elseif ($launcher -notmatch [regex]::Escape('-p $ProfileName gateway')) { Bad 'gateway launcher does not start the sillytavern profile' }
        else { Good 'SillyTavern installer writes the lean profile, three skills, and launcher' }
    } finally {
        Remove-Item -LiteralPath $fxHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Section '16. One-click install wires what is installed, not what is wanted'
$stGatewayGate = Join-Path $PackRoot 'TESTS\Test-SillyTavernGateway.ps1'
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $stGatewayGate -PackRoot $PackRoot
if ($LASTEXITCODE -ne 0) { Bad 'SillyTavern installer/launcher regression checks failed' }
else { Good 'SillyTavern installer/launcher regression checks passed' }
# Through v8.0.4 a plain run assumed all five providers and the bootstrap then
# DOWNLOADED the missing ones. A detector decides that now, so it is exercised
# against a real filesystem rather than trusted because the source reads right.
$detectGate = Join-Path $PackRoot 'TESTS\Test-ProviderDetection.ps1'
if (-not (Test-UabsPackPath $detectGate)) {
    Bad 'TESTS\Test-ProviderDetection.ps1 missing from the pack'
} else {
    $detectOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $detectGate -PackRoot $PackRoot 2>&1 | Out-String
    if ($detectOut -match 'PROVIDER DETECTION GATE: PASS') {
        Good 'provider auto-detection PASS'
    } else {
        Bad ('provider detection gate failed:' + [Environment]::NewLine + ($detectOut.Trim()))
    }
}

foreach ($freshGate in @('Test-ProviderBootstrap.ps1','Test-WorkspaceSeeding.ps1','Test-InstallerPreservation.ps1','Test-ProviderHookScope.ps1','Test-DoctorProviderScope.ps1')) {
    # PS5.1 wraps successful native stderr as ErrorRecords. Capture diagnostics
    # without treating them as process failure; require exit 0 AND a final proof.
    $freshEap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try {
        $freshOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot ('TESTS\' + $freshGate)) -PackRoot $PackRoot 2>&1 | Out-String
        $freshCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $freshEap }
    if ($freshCode -eq 0 -and $freshOut -match 'GATE: PASS') { Good ($freshGate + ' passed') }
    else { Bad ($freshGate + ':' + [Environment]::NewLine + $freshOut.Trim()) }
}

Section '17. Grok hook repair and effective discovery'
$grokPluginOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-GrokPluginDedupe.ps1') -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $grokPluginOut -match 'GROK PLUGIN DEDUPE GATE: PASS') { Good 'Grok plugin version selection and backup scope' }
else { Bad ('Grok plugin dedupe failed:' + [Environment]::NewLine + $grokPluginOut) }
$hookRepairGate = Join-Path $PackRoot 'TESTS\Test-GrokHookRepair.ps1'
$hookRepairOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $hookRepairGate -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $hookRepairOut -match 'GROK HOOK REPAIR GATE: PASS') {
    Good 'hook repair preserves settings, is idempotent, and detects effective duplicate/invalid hooks'
} else { Bad ('Grok hook repair failed:' + [Environment]::NewLine + $hookRepairOut) }

Section '18. Codex native hook retirement'
$codexHookGate = Join-Path $PackRoot 'TESTS\Test-CodexHookRetirement.ps1'
$codexHookOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $codexHookGate -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0 -and $codexHookOut -match 'CODEX HOOK RETIREMENT GATE: PASS') {
    Good 'native legacy gates retired; exact backups, custom hooks/trust, fresh/custom homes and reruns verified'
} else { Bad ('Codex hook retirement failed:' + [Environment]::NewLine + $codexHookOut) }

Section '19. Ponytail Cursor and Impeccable security regressions'
$nodeForCursor = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeForCursor) { Bad 'Node is required to exercise the shipped Ponytail Cursor and Impeccable security regressions' }
else {
    $cursorRegression = & $nodeForCursor.Source (Join-Path $PackRoot 'TESTS\ponytail-cursor-regression.cjs') 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $cursorRegression -match 'PONYTAIL CURSOR REGRESSION: PASS') {
        Good 'adversarial command completes within 3 seconds; real names recognized, embedded personal names preserved'
    } else { Bad ('Ponytail Cursor security regression failed:' + [Environment]::NewLine + $cursorRegression) }
    $impeccableRegression = & $nodeForCursor.Source (Join-Path $PackRoot 'TESTS\impeccable-security-regressions.mjs') 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $impeccableRegression -match '(?i)IMPECCABLE SECURITY REGRESSIONS:?\s+PASS') {
        Good 'Impeccable CodeQL security regressions pass across canonical and live scripts'
    } else { Bad ('Impeccable security regressions failed:' + [Environment]::NewLine + $impeccableRegression) }
}

$headroomCleanupGate = Join-Path $PackRoot 'TESTS\Test-HeadroomTaskCleanup.ps1'
$headroomCleanupOut = & (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File $headroomCleanupGate -PackRoot $PackRoot 2>&1 | Out-String
if ($LASTEXITCODE -eq 0) { Good 'Headroom scheduled-task retirement preserves non-bundle tasks' }
else { Bad ('Headroom task cleanup regression failed:' + [Environment]::NewLine + $headroomCleanupOut) }

Section '20. Maintainer lifecycle and documentation contracts'
& (Get-Command powershell.exe -ErrorAction Stop).Source -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PackRoot 'TESTS\Test-GitHubVerdict.ps1')
if ($LASTEXITCODE -eq 0) { Good 'exact-SHA CI verdicts and bounded waiting pass' }
else { Bad 'GitHub verdict regression failed' }
if ($py) {
    foreach ($gate in @('TOOLS\verify_docs.py','TESTS\test_maintainer_contract.py')) {
        & $py.Source (Join-Path $PackRoot $gate)
        if ($LASTEXITCODE -eq 0) { Good ($gate + ' passed') }
        else { Bad ($gate + ' failed') }
    }
}

Write-Host ''
if ($fail -eq 0) {
    Write-Host "PACK GATE: PASS" -ForegroundColor Green
    exit 0
} else {
    Write-Host "PACK GATE: FAIL ($fail problem(s))" -ForegroundColor Red
    exit 1
}
