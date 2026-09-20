[CmdletBinding()]
param([string]$PackRoot)
$ErrorActionPreference = 'Stop'
if (-not $PackRoot) { $PackRoot = Split-Path -Parent $PSScriptRoot }
. (Join-Path $PackRoot 'TOOLS/UABS-Common.ps1')
$scratch = Join-Path ([IO.Path]::GetTempPath()) ('uabs-preamble-preservation-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
try {
    $soulFile = Join-Path $scratch 'source-soul.md'
    $aioFile = Join-Path $scratch 'source-aio.md'
    $target = Join-Path $scratch 'instructions.md'
    $soul = "You are the user's AI assistant.`nKnown soul body."
    $aio = "Operate at the widest level.`nKnown contract body."
    $utf8 = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($soulFile, $soul, $utf8)
    [IO.File]::WriteAllText($aioFile, $aio, $utf8)
    $prefix = '# Personal rules'
    $suffix = '# Keep my trailing project instructions'
    $mention = "You are the user's AI assistant.`n" + ('Personal prose, not bundle text. ' * 20)
    $legacy = "<!-- ULTIMATE-AI-STARTER-BUNDLE SOUL v8.7.20 -->`nOld owned text`n<!-- /ULTIMATE-AI-STARTER-BUNDLE SOUL -->"
    # The pack's own text changes between releases: a machine wired by the older
    # release carries the older block verbatim. The archived copy beside the
    # soul source is what lets the writer replace it instead of stacking.
    $oldSoul = "You are the user's AI assistant.`nPrevious release soul body."
    $oldAio = "Operate at the widest level.`nPrevious release contract body."
    $histDir = Join-Path $scratch 'history'
    New-Item -ItemType Directory -Path $histDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $histDir 'soul-previous.md'), $oldSoul, $utf8)
    [IO.File]::WriteAllText((Join-Path $histDir 'aio-previous.md'), $oldAio, $utf8)
    $cases = @(
        @{ Name = 'plain trailing notes'; Text = "$prefix`n$soul`n`n$aio`n$suffix"; Keep = @($prefix, $suffix) },
        @{ Name = 'marked trailing notes'; Text = "$prefix`n$legacy`n$suffix"; Keep = @($prefix, $suffix) },
        @{ Name = 'opening-line collision'; Text = "$prefix`n$mention`n$suffix"; Keep = @($prefix, $mention, $suffix) },
        @{ Name = 'duplicate plain blocks'; Text = "$soul`n$aio`n$soul`n$aio"; Keep = @() },
        @{ Name = 'literal replacement characters'; Text = "User `$1 and `$&`n$soul`n$aio"; Keep = @('User $1 and $&') },
        @{ Name = 'previous release text replaced via history'; Text = "$prefix`n$oldSoul`n`n$oldAio`n$suffix"; Keep = @($prefix, $suffix); Gone = @($oldSoul, $oldAio) }
    )
    foreach ($case in $cases) {
        [IO.File]::WriteAllText($target, $case.Text, $utf8)
        Install-UabsPreambleBlock -Path $target -SoulFile $soulFile -AioFile $aioFile
        $after = [IO.File]::ReadAllText($target)
        foreach ($kept in $case.Keep) {
            if (-not $after.Contains($kept)) { throw "Lost user content: $($case.Name)" }
        }
        foreach ($gone in @($case.Gone)) {
            if ($gone -and $after.Contains($gone)) { throw "Stale owned text kept: $($case.Name)" }
        }
        foreach ($body in @($soul, $aio)) {
            $normalized = $after.Replace("`r`n", "`n")
            if ([regex]::Matches($normalized, [regex]::Escape($body)).Count -ne 1) { throw "Duplicated/missing block: $($case.Name)" }
        }
        Install-UabsPreambleBlock -Path $target -SoulFile $soulFile -AioFile $aioFile
        if ([IO.File]::ReadAllText($target) -cne $after) { throw "Not idempotent: $($case.Name)" }
        Write-Output "PASS $($case.Name)"
    }
} finally {
    # This exact GUID directory was created by this test under OS temp.
    Remove-Item -LiteralPath $scratch -Recurse -Force
}
