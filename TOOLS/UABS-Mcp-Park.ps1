# UABS-Mcp-Park.ps1 - keep task-specific MCP servers out of machine-wide config.
#
# Why: a connected MCP server puts its tool list in EVERY chat of a provider, used
# or not. Tool installers (RimWorldForge, AvatarForge, Melty ...) register
# themselves machine-wide, so unrelated chats pay for them. "Parking" saves an
# exact copy of such an entry, then removes it from the machine-wide config;
# "unparking" writes the same entry back for ONE project. Nothing is uninstalled.
#
# Secrets: an entry can carry headers or env values. They are copied only into
# the bundle's own state file (same user profile as the config they came from)
# and are never printed or logged by anything here.
#
# Dot-source after UABS-Common.ps1 and UABS-Mcp-Write.ps1.

function Get-UabsParkRules {
  <# Rules live in BUNDLED-TOOLS/PROFILES.json -> global_scope_guard.rules.
     Each: id, title, match (text found in the entry's launch command/url),
     optional detect {files, globs} (same shape as a profile's), optional
     profile (a profile that already registers it per project), optional
     only_if ('gh-ready': the rule applies only where the gh CLI is signed in), note. #>
  param([string]$PackRoot)
  $path = Join-UabsPath $PackRoot 'BUNDLED-TOOLS\PROFILES.json'
  if (-not (Test-UabsPath -LiteralPath $path -PathType Leaf)) { return @() }
  $guard = ([IO.File]::ReadAllText($path) | ConvertFrom-Json).global_scope_guard
  if (-not $guard) { return @() }
  $rules = @()
  foreach ($r in @($guard.rules)) {
    $detect = $null
    if ($r.detect) {
      $detect = @{ files = @($r.detect.files | Where-Object { $_ }); globs = @($r.detect.globs | Where-Object { $_ }) }
    }
    $rules += @{
      id = [string]$r.id; title = [string]$r.title; match = @($r.match | Where-Object { $_ })
      detect = $detect; profile = [string]$r.profile; note = [string]$r.note; only_if = [string]$r.only_if
    }
  }
  return $rules
}

function Get-UabsKeepGlobalIds {
  <# The user's opt-out: UABS_KEEP_GLOBAL_MCP=id1,id2 keeps those machine-wide. #>
  $v = [Environment]::GetEnvironmentVariable('UABS_KEEP_GLOBAL_MCP', 'Process')
  if (-not $v) { $v = [Environment]::GetEnvironmentVariable('UABS_KEEP_GLOBAL_MCP', 'User') }
  return @(([string]$v) -split '[,; ]+' | Where-Object { $_ })
}

function Test-UabsGhReady {
  <# The gh CLI is installed and signed in, so the GitHub MCP server only repeats it
     (and puts ~46 tool names in every chat). UABS_GH_READY=1|0 overrides detection.
     Offline or signed out reads as "not ready": the MCP stays, which is the safe side. #>
  $force = [Environment]::GetEnvironmentVariable('UABS_GH_READY', 'Process')
  if ($force -eq '1') { return $true }
  if ($force -eq '0') { return $false }
  $gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $gh) { return $false }
  $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & $gh.Source auth status 2>&1 | Out-Null } finally { $ErrorActionPreference = $prev }
  return ($LASTEXITCODE -eq 0)
}

function Test-UabsGithubMcpParked {
  <# True where the GitHub server is left out of the always-on core: gh is signed in
     and the user has not asked to keep it machine-wide. The registrar, the installer's
     handshake and the guard rule all use this one answer. #>
  return ((@(Get-UabsKeepGlobalIds) -notcontains 'github') -and (Test-UabsGhReady))
}

function Get-UabsHermesDefaultEntries {
  <# Hermes' default profile, read for REPORTING only. Hermes profiles are native
     and its desktop app rewrites config.yaml from memory, so nothing here edits it. #>
  $hp = Get-UabsHermesPaths
  if (-not $hp -or -not (Test-UabsPath -LiteralPath $hp.Config -PathType Leaf)) { return }
  $yaml = [IO.File]::ReadAllText($hp.Config)
  $m = [regex]::Match($yaml, '(?ms)^mcp_servers:[ \t]*\r?\n(?<b>(?:^[ \t].*(?:\r?\n|$))*)')
  if (-not $m.Success) { return }
  $name = $null; $buf = New-Object System.Text.StringBuilder
  $flush = {
    if ($name) {
      $block = $buf.ToString()
      [pscustomobject]@{
        Provider = 'Hermes'; Id = $name; Style = 'yaml'; Path = $hp.Config; Section = 'mcp_servers'
        Text = $block; Definition = $null; Block = $block
        Disabled = [bool]($block -match '(?im)^\s+enabled:\s*false\b')
      }
    }
  }
  foreach ($line in ($m.Groups['b'].Value -split "`r?`n")) {
    $head = [regex]::Match($line, '^  ["'']?(?<n>[^\s"'':][^"'':]*)["'']?:\s*$')
    if ($head.Success) { & $flush; $name = $head.Groups['n'].Value; [void]$buf.Clear() }
    elseif ($name) { [void]$buf.AppendLine($line) }
  }
  & $flush
}

function Get-UabsGlobalMcpEntries {
  <# Every machine-wide server the file-based provider configs declare. Hermes
     keeps named YAML profiles that Migrate-HermesProfiles.ps1 owns, so it is
     not read here. #>
  param([string[]]$Providers = @('Claude', 'Codex', 'Grok', 'Kimi', 'Hermes', 'Antigravity'))
  $targets = Get-UabsMcpTargets
  foreach ($provider in $Providers) {
    if ($provider -eq 'Hermes') { Get-UabsHermesDefaultEntries; continue }
    $t = $targets[$provider]
    if (-not $t -or -not (Test-UabsPath -LiteralPath $t.Path -PathType Leaf)) { continue }
    if ($t.Style -eq 'json') {
      $doc = Read-UabsJsonDocument -Path $t.Path
      $map = Get-UabsJsonSection -Container $doc -Section $t.Section
      if ($null -eq $map) { continue }
      foreach ($name in @($map.Keys)) {
        $entry = $map[$name]
        $off = ($entry -is [System.Collections.IDictionary]) -and $entry.ContainsKey('disabled') -and ($entry['disabled'] -eq $true)
        [pscustomobject]@{
          Provider = $provider; Id = [string]$name; Style = 'json'; Path = $t.Path; Section = $t.Section
          Text = (ConvertTo-UabsJsonText $entry -Compress); Definition = $entry; Block = ''; Disabled = $off
        }
      }
      continue
    }
    # TOML: a server is its [section.name] table plus any sub-tables ([..env]).
    $text = [IO.File]::ReadAllText($t.Path)
    $pattern = '(?ms)(?:^[ \t]*#[^\r\n]*\r?\n)?^\[' + [regex]::Escape($t.Section) + '\.(?<name>[^\].]+)(?<sub>\.[^\]]+)?\].*?(?=^(?:[ \t]*#[^\r\n]*\r?\n)?\[|\z)'
    $byName = [ordered]@{}
    foreach ($m in [regex]::Matches($text, $pattern)) {
      $n = $m.Groups['name'].Value
      $byName[$n] = [string]$byName[$n] + $m.Value
    }
    foreach ($n in @($byName.Keys)) {
      [pscustomobject]@{
        Provider = $provider; Id = [string]$n; Style = 'toml'; Path = $t.Path; Section = $t.Section
        Text = $byName[$n]; Definition = $null; Block = $byName[$n]
        Disabled = [bool]($byName[$n] -match '(?im)^\s*enabled\s*=\s*false\b')
      }
    }
  }
}

function Find-UabsGlobalScopeLeaks {
  <# Machine-wide entries that launch a known task-specific server. Matching is on
     what the entry LAUNCHES (command, args, url), not on the name it was given,
     so a renamed registration is still found and a personal server that merely
     shares a name is not. An entry already switched off costs nothing: skipped. #>
  param([string]$PackRoot, [string[]]$Providers = @('Claude', 'Codex', 'Grok', 'Kimi', 'Hermes'))
  $rules = @(Get-UabsParkRules -PackRoot $PackRoot)
  $keep = @(Get-UabsKeepGlobalIds)
  $ghReady = $null
  $leaks = @()
  foreach ($e in @(Get-UabsGlobalMcpEntries -Providers $Providers)) {
    if ($e.Disabled) { continue }
    foreach ($r in $rules) {
      if ($keep -contains $r.id) { continue }
      if ($r.only_if -eq 'gh-ready') {
        if ($null -eq $ghReady) { $ghReady = Test-UabsGhReady }
        if (-not $ghReady) { continue }
      }
      $hit = $false
      foreach ($lit in $r.match) {
        if ($e.Text.IndexOf($lit, [StringComparison]::OrdinalIgnoreCase) -ge 0) { $hit = $true; break }
      }
      if ($hit) { $leaks += [pscustomobject]@{ Provider = $e.Provider; Id = $e.Id; Rule = $r; Entry = $e }; break }
    }
  }
  return $leaks
}

# ---- the park store ----------------------------------------------------------

function Get-UabsParkStorePath { Join-UabsPath (Get-UabsStateRoot) 'parked-mcp.json' }

function Read-UabsParkStore {
  <# entries: provider, id, rule, style, parked_utc, source, definition (json) or
     block (toml), projects (where it was switched back on). A corrupt store
     throws so nothing overwrites it. #>
  $path = Get-UabsParkStorePath
  if (Test-UabsPath -LiteralPath $path -PathType Leaf) {
    $doc = ConvertFrom-UabsJsonText ([IO.File]::ReadAllText($path))
    if ($doc -is [System.Collections.IDictionary] -and $doc.ContainsKey('entries')) { return ,$doc }
  }
  $fresh = New-Object 'System.Collections.Generic.Dictionary[string,object]'
  $fresh['schema'] = 1
  $fresh['entries'] = @()
  return ,$fresh
}

function Save-UabsParkStore {
  param($Store)
  $path = Get-UabsParkStorePath
  $dir = Split-Path -Parent $path
  if (-not (Test-UabsPath -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  Set-Utf8NoBom -Path $path -Text ((ConvertTo-UabsJsonText $Store) + "`n")
}

function Invoke-UabsParkGlobalMcp {
  <# Park every leak. The exact copy is saved and re-read BEFORE anything is
     removed; if it does not verify, nothing is removed. Returns the leaks acted
     on (or, with -CheckOnly, the ones that would be). #>
  param([string]$PackRoot, [string[]]$Providers = @('Claude', 'Codex', 'Grok', 'Kimi'), [switch]$CheckOnly)
  $leaks = @(Find-UabsGlobalScopeLeaks -PackRoot $PackRoot -Providers $Providers | Where-Object { $_.Entry.Style -ne 'yaml' })
  if (-not $leaks.Count -or $CheckOnly) { return $leaks }

  $store = Read-UabsParkStore
  $entries = @($store['entries'] | Where-Object {
    $old = $_
    -not (@($leaks | Where-Object { $_.Provider -eq $old['provider'] -and $_.Id -eq $old['id'] }).Count)
  })
  foreach ($l in $leaks) {
    $rec = New-Object 'System.Collections.Generic.Dictionary[string,object]'
    $rec['provider'] = $l.Provider; $rec['id'] = $l.Id; $rec['rule'] = $l.Rule.id
    $rec['style'] = $l.Entry.Style; $rec['source'] = $l.Entry.Path
    $rec['parked_utc'] = [DateTime]::UtcNow.ToString('o')
    if ($l.Entry.Style -eq 'json') { $rec['definition'] = $l.Entry.Definition } else { $rec['block'] = $l.Entry.Block }
    $rec['projects'] = @()
    $entries += $rec
  }
  $store['entries'] = $entries
  Save-UabsParkStore -Store $store

  $check = Read-UabsParkStore
  foreach ($l in $leaks) {
    $saved = @($check['entries'] | Where-Object { $_['provider'] -eq $l.Provider -and $_['id'] -eq $l.Id })
    $same = $saved.Count -eq 1 -and $(if ($l.Entry.Style -eq 'json') {
      (ConvertTo-UabsJsonText $saved[0]['definition'] -Compress) -ceq (ConvertTo-UabsJsonText $l.Entry.Definition -Compress)
    } else { [string]$saved[0]['block'] -ceq $l.Entry.Block })
    if (-not $same) { throw ("the saved copy of {0}/{1} did not verify; nothing was removed" -f $l.Provider, $l.Id) }
  }

  foreach ($group in @($leaks | Group-Object { $_.Provider })) {
    $first = $group.Group[0].Entry
    $ids = @($group.Group | ForEach-Object { $_.Id })
    if ($first.Style -eq 'json') { [void](Remove-UabsMcpJson -Path $first.Path -Section $first.Section -Ids $ids) }
    else { [void](Remove-UabsMcpToml -Path $first.Path -Section $first.Section -Ids $ids) }
  }
  return $leaks
}

function Invoke-UabsUnparkMcp {
  <# Put parked entries back for ONE project, exactly as saved. Existing entries
     in that project are never overwritten. Returns "Provider/id" for each write. #>
  param([string[]]$Ids, [string]$ProjectPath, [string[]]$Providers = @('Claude', 'Codex', 'Grok', 'Kimi'), [switch]$CheckOnly)
  $store = Read-UabsParkStore
  $wrote = @()
  $touched = $false
  foreach ($rec in @($store['entries'])) {
    # A rule id (from -Auto) or the name the entry was registered under (from -Unpark).
    if (($Ids -notcontains [string]$rec['id'] -and $Ids -notcontains [string]$rec['rule']) -or $Providers -notcontains [string]$rec['provider']) { continue }
    $target = Get-UabsProviderProjectTarget -Provider ([string]$rec['provider']) -ProjectPath $ProjectPath
    if (-not $target) {
      Write-Host ("  --  {0}/{1}: {2}" -f $rec['provider'], $rec['id'], (Get-UabsProviderNoProjectScope -Provider ([string]$rec['provider']))) -ForegroundColor Yellow
      continue
    }
    $did = $false
    if ($target.Style -eq 'json') {
      $doc = Read-UabsJsonDocument -Path $target.Path
      foreach ($key in @(Get-UabsClaudeProjectKeys -ProjectPath $ProjectPath -ConfigPath $target.Path)) {
        $section = Get-UabsJsonSection -Container (Get-UabsJsonScopeContainer -Json $doc -ProjectKey $key -Create) -Section $target.Section -Create
        if ($section.ContainsKey([string]$rec['id'])) { continue }
        $section[[string]$rec['id']] = $rec['definition']
        $did = $true
      }
      if ($did -and -not $CheckOnly) { Write-UabsJsonDocument -Path $target.Path -Document $doc }
    } else {
      $existing = if (Test-UabsPath -LiteralPath $target.Path -PathType Leaf) { [IO.File]::ReadAllText($target.Path) } else { '' }
      if ($existing.IndexOf('[' + $target.Section + '.' + $rec['id'] + ']', [StringComparison]::Ordinal) -lt 0) {
        $did = $true
        if (-not $CheckOnly) {
          $dir = Split-Path -Parent $target.Path
          if (-not (Test-UabsPath -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
          $sep = if ($existing.Trim()) { "`r`n`r`n" } else { '' }
          Set-Utf8NoBom -Path $target.Path -Text ($existing.TrimEnd() + $sep + ([string]$rec['block']).Trim() + "`r`n")
        }
      }
    }
    if (-not $did) { continue }
    $wrote += ('{0}/{1}' -f $rec['provider'], $rec['id'])
    if (-not $CheckOnly) {
      $rec['projects'] = @(@($rec['projects']) + $ProjectPath | Where-Object { $_ } | Select-Object -Unique)
      $touched = $true
    }
  }
  if ($touched) { Save-UabsParkStore -Store $store }
  return $wrote
}
