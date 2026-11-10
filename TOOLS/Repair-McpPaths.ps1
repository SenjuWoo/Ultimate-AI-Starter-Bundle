<#
.SYNOPSIS
  Find MCP servers wired to absolute paths that no longer exist, and repoint
  them at the version that is actually installed.

.DESCRIPTION
  Every provider stores MCP server commands as a hard absolute path, in its own
  format: Claude JSON, Kimi JSON, Codex TOML, Grok TOML, Hermes YAML. When a
  tool is upgraded in place (Skyrim-Forge-5.1.0 -> 5.1.3) the folder name
  changes, so each config has to be edited by hand -- and one always gets
  missed. The missed one does not fail loudly; the server just never connects.

  Observed: Forge moved to 5.1.3, Kimi/Codex/Grok/Hermes were updated, Claude
  was left pointing at 5.1.0 and its skyrim-forge MCP silently went dead.

  This script does not parse the five formats. It looks for the dead path as a
  literal string and replaces it with the live one, which is format-agnostic
  and cannot reorder or reformat a user's config. Backup first, always.

  Default is report-only. -Apply performs the edit.

.PARAMETER Apply
  Write the repairs. Without it, nothing is modified.

.PARAMETER Quiet
  Only print problems and repairs, not healthy servers.

.EXAMPLE
  .\Repair-McpPaths.ps1
  .\Repair-McpPaths.ps1 -Apply
#>
[CmdletBinding()]
param(
  [switch]$Apply,
  [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
$hermesRoot = Get-UabsProviderHome -Provider Hermes -Catalog (Get-UabsCatalog)

$configs = @(
  @{ Name = 'Claude'; Path = (Join-Path $env:USERPROFILE '.claude.json') }
  @{ Name = 'Kimi';   Path = (Join-Path $env:USERPROFILE '.kimi-code\mcp.json') }
  @{ Name = 'Codex';  Path = (Join-Path $env:USERPROFILE '.codex\config.toml') }
  @{ Name = 'Grok';   Path = (Join-Path $env:USERPROFILE '.grok\config.toml') }
  @{ Name = 'Hermes'; Path = (Join-Path $hermesRoot 'config.yaml') }
)

# Hermes stores one config per profile under profiles\<name>\config.yaml. The
# top-level file above is only the default profile, so a Codex runtime update
# (which changes the hash folder under runtimes\cua_node) left every profile
# copy pointing at the dead path while the installer still printed
# "MCP command paths checked". Scan the profile copies too.
$hermesProfileRoot = Join-Path $hermesRoot 'profiles'
if (Test-Path -LiteralPath $hermesProfileRoot -PathType Container) {
  foreach ($profileDir in @(Get-ChildItem -LiteralPath $hermesProfileRoot -Directory -ErrorAction SilentlyContinue)) {
    $profileCfg = Join-Path $profileDir.FullName 'config.yaml'
    if (Test-Path -LiteralPath $profileCfg -PathType Leaf) {
      $configs += @{ Name = ('Hermes/' + $profileDir.Name); Path = $profileCfg }
    }
  }
}

# Claude Desktop (Store app) keeps its own MCP config and does NOT read
# ~/.claude.json for its servers. The package folder is hash-suffixed, so
# glob for the config file instead of hardcoding the package name.
$desktopCfg = Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'Packages') -Filter 'claude_desktop_config.json' -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1
if ($desktopCfg) {
  $configs += @{ Name = 'Claude Desktop'; Path = $desktopCfg.FullName }
}

# A path inside a config may be written with \ or /. Compare on a normalized
# form so "S:/x/y" and "S:\x\y" are recognized as the same file.
# JSON escapes every separator, so the literal in the file reads "S:\\x\\y".
# Collapse that doubling before touching the filesystem, or Test-Path and the
# version splitter both see empty path segments.
function Get-NormalPath([string]$p) { return (($p -replace '/', '\') -replace '\\{2,}', '\') }

# Re-apply whatever escaping the config literal used, so a JSON file keeps its
# doubled separators and a TOML/YAML one keeps its single ones. Writing a lone
# backslash into JSON produces an invalid escape and an unparseable config.
# String.Replace, not -replace: the latter is regex on BOTH sides, and getting
# the replacement-side backslash count right is a coin flip (one pass produced
# "S:\.venv\\Scripts", the next "S:\\\\Apps"). Plain string replacement has no
# escape semantics, so what is written is what is meant.
function ConvertTo-ConfigLiteral([string]$LivePath, [string]$DeadLiteral) {
  $single = $LivePath.Replace('/', '\')
  if ($DeadLiteral -match '/') { return $single.Replace('\', '/') }
  if ($DeadLiteral.Contains('\\')) { return $single.Replace('\', '\\') }
  return $single
}

# Absolute Windows paths that look like a program, in either slash style.
$rxPath = '(?<p>[A-Za-z]:[\\\\/](?:[^"''\r\n;]*?)\.(?:exe|cmd|bat|ps1|py))'

# Folder names that are never an owner root. Skipping them keeps the index walk
# to the project level instead of descending into every dependency tree.
$script:ToolIndexSkip = @('.git', 'node_modules', 'dist', 'build', 'target', '__pycache__', '.venv', 'venv')

<#
  Index of tool folders, built once per run and only when a dead path exists.
  Sources: UABS_TOOL_ROOTS (the variable the installer writes), the machine
  map's "Tool folders" line (what the user actually keeps), and the conventional
  per-user tool folders. Bounded to depth 3 and capped, because an owner folder
  always sits at Tools\<category>\<owner> -- never ten levels down.
#>
$script:ToolDirectoryIndex = $null
function Get-ToolDirectoryIndex {
  if ($null -ne $script:ToolDirectoryIndex) { return $script:ToolDirectoryIndex }
  $roots = New-Object System.Collections.Generic.List[string]
  foreach ($scope in @('Process', 'User')) {
    $hints = [Environment]::GetEnvironmentVariable('UABS_TOOL_ROOTS', $scope)
    if ($hints) { foreach ($h in ($hints -split ';')) { if ($h) { [void]$roots.Add($h) } } }
  }
  foreach ($p in @((Join-Path $env:USERPROFILE 'Tools'), (Join-Path $env:USERPROFILE 'Documents\Tools'), (Join-Path $env:SystemDrive 'Tools'))) {
    [void]$roots.Add($p)
  }
  # The user-declared roots file companion_registry.py reads; one path per line.
  $declared = Join-Path $env:USERPROFILE '.uabs\profile\TOOL-ROOTS.txt'
  if (Test-Path -LiteralPath $declared -PathType Leaf) {
    foreach ($line in [IO.File]::ReadAllLines($declared)) {
      $v = $line.Trim()
      if ($v -and -not $v.StartsWith('#')) { [void]$roots.Add([Environment]::ExpandEnvironmentVariables($v)) }
    }
  }
  $map = Join-Path $env:USERPROFILE '.uabs\profile\MACHINE-MAP.md'
  if (Test-Path -LiteralPath $map -PathType Leaf) {
    foreach ($line in [IO.File]::ReadAllLines($map)) {
      if ($line -notmatch '^-\s+Tool folders') { continue }
      $rest = ($line -split ':', 2)
      if ($rest.Count -lt 2) { continue }
      foreach ($piece in ($rest[1] -split ';')) {
        $v = $piece.Trim()
        if ($v) { [void]$roots.Add([Environment]::ExpandEnvironmentVariables($v)) }
      }
    }
  }
  $dirs = New-Object System.Collections.Generic.List[string]
  foreach ($r in @($roots | Select-Object -Unique)) {
    if (-not $r -or -not (Test-Path -LiteralPath $r -PathType Container)) { continue }
    try { [void]$dirs.Add($r) } catch { continue }
    $stack = New-Object System.Collections.Generic.Stack[object]
    $stack.Push(@{ Path = $r; Depth = 0 })
    while ($stack.Count -gt 0 -and $dirs.Count -lt 5000) {
      $cur = $stack.Pop()
      if ($cur.Depth -ge 3) { continue }
      foreach ($d in @(Get-ChildItem -LiteralPath $cur.Path -Directory -ErrorAction SilentlyContinue)) {
        if ($script:ToolIndexSkip -contains $d.Name) { continue }
        [void]$dirs.Add($d.FullName)
        $stack.Push(@{ Path = $d.FullName; Depth = ($cur.Depth + 1) })
      }
    }
  }
  $script:ToolDirectoryIndex = $dirs.ToArray()
  return $script:ToolDirectoryIndex
}

<#
  Repointing rule: if a dead path contains a version-stamped directory
  (Name-1.2.3), look for a sibling directory with the same stem and a different
  version, and prefer the highest one whose target file exists. Anything that
  does not fit that shape is reported but never guessed at.
#>
function Resolve-LivePath([string]$dead) {
  $norm = Get-NormalPath $dead
  $parts = $norm -split '\\'
  for ($i = 0; $i -lt $parts.Count; $i++) {
    if ($parts[$i] -notmatch '^(?<stem>.+?)-(?<ver>\d+(?:\.\d+)*)$') { continue }
    $stem = $Matches['stem']
    $parent = ($parts[0..($i - 1)] -join '\')
    if (-not $parent -or -not (Test-Path -LiteralPath $parent)) { continue }
    $tailParts = @()
    if ($i -lt ($parts.Count - 1)) { $tailParts = $parts[($i + 1)..($parts.Count - 1)] }
    $tail = $tailParts -join '\'
    $cands = @()
    foreach ($d in (Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
      if ($d.Name -notmatch ('^' + [regex]::Escape($stem) + '-(?<ver>\d+(?:\.\d+)*)$')) { continue }
      $full = if ($tail) { Join-Path $d.FullName $tail } else { $d.FullName }
      if (-not (Test-Path -LiteralPath $full)) { continue }
      $v = $null
      # [version] needs at least two parts; pad so "5" parses.
      $vs = $Matches['ver']
      while (($vs -split '\.').Count -lt 2) { $vs = $vs + '.0' }
      if (-not [version]::TryParse($vs, [ref]$v)) { continue }
      $cands += [pscustomobject]@{ Version = $v; Full = $full }
    }
    if ($cands.Count) {
      return (($cands | Sort-Object Version -Descending)[0]).Full
    }
    # No version-stamped sibling found. The user may have renamed the folder
    # to drop the version suffix (Skyrim-Forge-5.1.6 -> Skyrim-Forge), which
    # the regex above cannot match. Fall back to the bare stem as a sibling.
    $bare = Join-Path $parent $stem
    if (Test-Path -LiteralPath $bare) {
      $full = if ($tail) { Join-Path $bare $tail } else { $bare }
      if (Test-Path -LiteralPath $full) { return $full }
    }
  }
  # Version-stamped siblings are this pack's own convention. Other tools rename
  # a directory without any version in it at all -- Codex keys its runtimes by
  # content hash, so 'cua_node\2fb562745e6d66f0' becomes
  # 'cua_node\84464046935436b8' on an update and every config still points at
  # the old one. Same silent failure, unmatched by the rule above.
  #
  # Rule: exactly ONE sibling directory under which the remaining tail exists.
  # Uniqueness is what makes this a resolution and not a guess; if two siblings
  # both fit, report it and let a human choose. Deepest segment first, because
  # that is the smallest substitution that can work.
  for ($i = $parts.Count - 2; $i -ge 1; $i--) {
    # A unique filename under a different owner is not owner identity. The
    # arbitrary-sibling rule is only for content-addressed runtime directories;
    # ordinary moved/renamed owners use the anchored discovery rule below.
    if ($parts[$i] -notmatch '^[0-9a-fA-F]{16,64}$') { continue }
    $parent = ($parts[0..($i - 1)] -join '\')
    if (-not $parent -or -not (Test-Path -LiteralPath $parent -PathType Container)) { continue }
    $tail = ($parts[($i + 1)..($parts.Count - 1)]) -join '\'
    if (-not $tail) { continue }
    $hits = @()
    foreach ($d in (Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
      if ($d.Name -ieq $parts[$i]) { continue }
      $full = Join-Path $d.FullName $tail
      if (Test-Path -LiteralPath $full -PathType Leaf) { $hits += $full }
    }
    if ($hits.Count -eq 1) { return $hits[0] }
  }
  # The bundle registers houseCARL via the HOUSECARL_MCP user env. It is the
  # one server whose live root is NOT a version-stamped sibling of the dead
  # path (users move it to a tools drive; the sibling rule cannot cross
  # drives, so the loop above finds nothing and this used to report
  # "no replacement found" for a perfectly live server). That env is the
  # bundle's own registry - repoint from it, never guess.
  if ((Get-NormalPath $dead) -match '(?i)housecarl-mcp\.exe$') {
    foreach ($envMcp in @($env:HOUSECARL_MCP, [Environment]::GetEnvironmentVariable('HOUSECARL_MCP','User'))) {
      if ($envMcp -and (Test-Path -LiteralPath (Get-NormalPath $envMcp))) { return (Get-NormalPath $envMcp) }
    }
  }

  # Relocated owner folder. A tool can move to a completely different parent:
  # a server under one tools root ends up under a different one. Every rule
  # above only looks at siblings of the dead path, so a live server one tree over
  # is reported as "no replacement found". Search the
  # folders the user actually keeps tools in (UABS_TOOL_ROOTS + the machine map)
  # for a folder with the same name and the same remaining tail. Uniqueness is
  # required: two hits is a question for a human, not a guess.
  #
  # Names compare without case or punctuation (RobloxForge == Roblox-Forge ==
  # roblox_forge), the same rule companion_registry.py uses for owner folders.
  # A rename that only adds a hyphen is still the same owner. This block used to
  # sit inside the houseCARL branch above by a missing brace, so it never ran for
  # any other server and a moved RobloxForge stayed "DEAD (no replacement found)".
  $index = @()
  if (Get-Command Get-ToolDirectoryIndex -ErrorAction SilentlyContinue) { $index = Get-ToolDirectoryIndex }
  if ($index.Count -gt 0) {
    # Anchor on a distinctive folder. Starting at the end walked straight into
    # `bin\tool.exe`, which "uniquely" matches half the machine and repointed a
    # server at an unrelated binary.
    $generic = @('bin', 'lib', 'libs', 'obj', 'dist', 'build', 'src', 'out', 'release',
                 'debug', 'x64', 'x86', 'amd64', 'windows', 'win64', 'cmd', 'app',
                 'data', 'assets', 'resources', 'runtime', 'server', 'mcp_server', 'tools', 'scripts')
    for ($i = $parts.Count - 2; $i -ge 1; $i--) {
      $name = $parts[$i]
      if ($name -notmatch '^[A-Za-z0-9][A-Za-z0-9._ -]*$') { continue }
      if ($generic -contains $name.ToLowerInvariant()) { continue }
      if ($name -match '^\d+(\.\d+)*$') { continue }
      $key = ($name -replace '[^A-Za-z0-9]', '').ToLowerInvariant()
      if (-not $key) { continue }
      $tail = ($parts[($i + 1)..($parts.Count - 1)]) -join '\'
      if (-not $tail) { continue }
      $hits = @()
      foreach ($dir in $index) {
        if (((Split-Path -Leaf $dir) -replace '[^A-Za-z0-9]', '').ToLowerInvariant() -ne $key) { continue }
        $full = Join-Path $dir $tail
        if (Test-Path -LiteralPath $full -PathType Leaf) { $hits += (Get-Item -LiteralPath $full).FullName }
      }
      $hits = @($hits | Sort-Object -Unique)
      if ($hits.Count -eq 1) { return $hits[0] }
    }
  }
  return $null
}

$problems = 0
$repairs = 0

foreach ($c in $configs) {
  if (-not (Test-Path -LiteralPath $c.Path)) {
    if (-not $Quiet) { Write-Host ("{0,-7} not installed" -f $c.Name) -ForegroundColor DarkGray }
    continue
  }
  $text = [IO.File]::ReadAllText($c.Path)
  $problemsBefore = $problems
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  $dead = @()
  foreach ($m in [regex]::Matches($text, $rxPath)) {
    $p = $m.Groups['p'].Value
    if (-not $seen.Add((Get-NormalPath $p).ToLowerInvariant())) { continue }
    if (Test-Path -LiteralPath (Get-NormalPath $p)) { continue }
    $dead += $p
  }
  $filePathsClean = ($dead.Count -eq 0)
  $newText = $text
  $changed = $false
  foreach ($d in $dead) {
    $problems++
    $live = Resolve-LivePath $d
    if (-not $live) {
      Write-Host ("{0,-7} DEAD (no replacement found)" -f $c.Name) -ForegroundColor Red
      Write-Host ("          $d") -ForegroundColor Red
      continue
    }
    # Preserve the slash style AND the escaping the config already used, so the
    # diff is one version number, not a whole-path restyle or a broken escape.
    $liveStyled = ConvertTo-ConfigLiteral -LivePath $live -DeadLiteral $d
    Write-Host ("{0,-7} REPOINT" -f $c.Name) -ForegroundColor Yellow
    Write-Host ("          from $d") -ForegroundColor DarkYellow
    Write-Host ("          to   $liveStyled") -ForegroundColor DarkYellow
    $newText = $newText.Replace($d, $liveStyled)
    $changed = $true
    $repairs++
  }
  # Directory-only references. NODE_REPL_NODE_MODULE_DIRS and
  # NODE_REPL_TRUSTED_CODE_PATHS name folders, so the file-path scan above
  # never sees them. Codex keys both its runtime tree and its CLI folder by a
  # 16-hex content hash; an update changes the hash, the command is repaired,
  # and the module/trust lists still point into the dead tree. The server then
  # starts without its modules -- a silent partial failure.
  #
  # Resolve only a hash folder whose replacement is unique, and only for the
  # two known layouts (cua_node\<hash> and Codex\bin\<hash>). Anything else is
  # reported by the file-path pass or left alone.
  $rxHashRoot = [regex]'(?i)(?<p>[A-Za-z]:[\\/][^"''\r\n;]*?[\\/](?:cua_node|bin)[\\/](?<h>[0-9a-f]{16}))(?=[\\/;"''\r\n]|$)'
  $hashSeen = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($m in [regex]::Matches($newText, $rxHashRoot)) {
    $deadRoot = $m.Groups['p'].Value
    if (-not $hashSeen.Add((Get-NormalPath $deadRoot).ToLowerInvariant())) { continue }
    if (Test-Path -LiteralPath (Get-NormalPath $deadRoot)) { continue }
    $parent = Split-Path -Parent (Get-NormalPath $deadRoot)
    $leaf = Split-Path -Leaf $parent
    $marker = $null
    if ($leaf -ieq 'cua_node') { $marker = 'bin\node_repl.exe' }
    elseif ($leaf -ieq 'bin' -and (Split-Path -Leaf (Split-Path -Parent $parent)) -ieq 'Codex') { $marker = 'codex.exe' }
    if (-not $marker) { continue }
    $cands = @()
    foreach ($d in (Get-ChildItem -LiteralPath $parent -Directory -ErrorAction SilentlyContinue)) {
      if ($d.Name -ieq $m.Groups['h'].Value) { continue }
      $probe = Join-Path $d.FullName $marker
      if (Test-Path -LiteralPath $probe -PathType Leaf) { $cands += $d.FullName }
    }
    if ($cands.Count -ne 1) {
      $problems++
      Write-Host (("{0,-7} DEAD hash folder ({1} candidates)" -f $c.Name, $cands.Count)) -ForegroundColor Red
      Write-Host ("          $deadRoot") -ForegroundColor Red
      continue
    }
    $liveRoot = $cands[0]
    $deadStyled = ConvertTo-ConfigLiteral -LivePath $deadRoot -DeadLiteral $deadRoot
    $liveStyled = ConvertTo-ConfigLiteral -LivePath $liveRoot -DeadLiteral $deadRoot
    $problems++
    Write-Host (("{0,-7} REPOINT" -f $c.Name)) -ForegroundColor Yellow
    Write-Host ("          folder $deadStyled") -ForegroundColor DarkYellow
    Write-Host ("          to     $liveStyled") -ForegroundColor DarkYellow
    # A complete hash reference must not rewrite a longer personal folder prefix.
    $newText = [regex]::Replace($newText, [regex]::Escape($deadStyled) + '(?=[\\/;"''\r\n]|$)',
      [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $liveStyled })
    $changed = $true
    $repairs++
  }

  if ($filePathsClean -and -not $changed -and $problems -eq $problemsBefore) {
    if (-not $Quiet) { Write-Host (("{0,-7} OK" -f $c.Name)) -ForegroundColor Green }
    continue
  }

  if ($changed -and $Apply) {
    $bytes = [IO.File]::ReadAllBytes($c.Path)
    $hadBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $bak = $c.Path + '.before-mcprepair-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.bak'
    Copy-Item -LiteralPath $c.Path -Destination $bak -Force
    [IO.File]::WriteAllText($c.Path, $newText, (New-Object System.Text.UTF8Encoding $hadBom))
    Write-Host ("          written (backup: " + (Split-Path $bak -Leaf) + ")") -ForegroundColor Green
  }
}

Write-Host ''
if ($problems -eq 0) {
  Write-Host 'All MCP command paths resolve.' -ForegroundColor Green
} elseif ($Apply) {
  Write-Host ("Repaired {0} of {1} dead path(s)." -f $repairs, $problems) -ForegroundColor Green
} else {
  Write-Host ("{0} dead path(s); {1} can be repaired. Re-run with -Apply." -f $problems, $repairs) -ForegroundColor Yellow
}
if ($problems -gt $repairs) { exit 3 }
