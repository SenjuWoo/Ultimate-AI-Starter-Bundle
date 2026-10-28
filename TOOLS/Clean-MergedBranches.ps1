# Report local and origin branches proven ancestors of main. -Apply deletes
# only those branches; unmerged, checked-out and protected branches are kept.
[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Apply, [ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$Remote = 'origin')
$ErrorActionPreference = 'Stop'
function Invoke-BranchGit([string[]]$Arguments) {
    $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $output = & git @Arguments 2>&1; $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $old }
    if ($code -ne 0) { throw ('git ' + ($Arguments -join ' ') + ': ' + ($output -join ' ')) }
    return @($output | ForEach-Object { "$_" })
}
$base = @(Invoke-BranchGit -Arguments @('rev-parse','--verify',"refs/remotes/$Remote/main"))[0]
$inUse = @(Invoke-BranchGit -Arguments @('worktree','list','--porcelain') | Where-Object { $_ -like 'branch refs/heads/*' } | ForEach-Object { $_.Substring(18) })
foreach ($scope in @('local','remote')) {
    $prefix = if ($scope -eq 'local') { 'refs/heads/' } else { "refs/remotes/$Remote/" }
    $merged = @(Invoke-BranchGit -Arguments @('for-each-ref',"--merged=$base",'--format=%(refname)', $prefix))
    foreach ($ref in @(Invoke-BranchGit -Arguments @('for-each-ref','--format=%(refname)', $prefix))) {
        $name = $ref.Substring($prefix.Length)
        if ($name -eq 'HEAD') { continue }
        $status = if ($merged -contains $ref) { 'merged' } else { 'needs-review' }
        if ($name -in @('main','master','develop') -or ($scope -eq 'local' -and $inUse -contains $name)) { $status = 'protected' }
        $deleted = $false
        if ($Apply -and $status -eq 'merged' -and $PSCmdlet.ShouldProcess("$scope branch $name", 'delete merged branch')) {
            if ($scope -eq 'local') { $null = Invoke-BranchGit -Arguments @('branch','-d','--',$name) }
            else {
                # Re-read both remote tips immediately before a normal delete;
                # stale fetched refs never authorize deleting new remote work.
                $tips = @(Invoke-BranchGit -Arguments @('ls-remote','--heads','--',$Remote,'refs/heads/main',('refs/heads/' + $name)))
                $branchTip = @($tips | Where-Object { $_ -match ('\srefs/heads/' + [regex]::Escape($name) + '$') })
                $mainTip = @($tips | Where-Object { $_ -match '\srefs/heads/main$' })
                if ($branchTip.Count -ne 1 -or $mainTip.Count -ne 1 -or $branchTip[0].Split()[0] -ne @(Invoke-BranchGit -Arguments @('rev-parse',$ref))[0] -or $mainTip[0].Split()[0] -ne $base) {
                    throw "Remote changed; fetch and review again before deleting $name."
                }
                # The exact lease makes deletion conditional on that reviewed tip;
                # it never force-pushes a replacement or deletes newly arrived work.
                $expected = $branchTip[0].Split()[0]
                $null = Invoke-BranchGit -Arguments @('push',("--force-with-lease=refs/heads/" + $name + ':' + $expected),'--delete','--',$Remote,('refs/heads/' + $name))
            }
            $deleted = $true
        }
        [pscustomobject]@{ scope=$scope; branch=$name; verdict=$status; deleted=$deleted }
    }
}
