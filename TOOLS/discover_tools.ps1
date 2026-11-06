# discover_tools.ps1 - compatibility entry point for the verified tool probe.

#

# The real implementation lives in the tool-discovery skill

# (_CANONICAL-SKILLS\tool-discovery\scripts\discover_tools.ps1) because

# that is what an agent reads. This file used to carry a second, older copy that

# reported FOUND for anything on PATH and treated `npx` as proof that `npx

# codeburn` works -- and the installer ran the weaker copy. One implementation,

# forwarded here, so the installer and the skill can never disagree again.

param(

  [switch]$Json,

  [switch]$Inventory,

  [switch]$Refresh,

  [switch]$NoCache,

  [string[]]$ToolRoots = @(),

  [string]$SearchDir,

  [switch]$Isolated,

  [string]$CacheDir,

  [string]$HermesConfig

)



$ErrorActionPreference = 'Stop'

$canonical = Join-Path (Split-Path -Parent $PSScriptRoot) '_CANONICAL-SKILLS\tool-discovery\scripts\discover_tools.ps1'

if (-not (Test-Path -LiteralPath $canonical -PathType Leaf)) {{

  Write-Host "Tool discovery implementation missing: $canonical"

  exit 1

}}

& $canonical @PSBoundParameters

exit $LASTEXITCODE

