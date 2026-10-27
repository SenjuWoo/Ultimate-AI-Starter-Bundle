# Compatibility entry point; Skyrim Forge owns houseCARL setup.
[CmdletBinding()]
param([bool]$WireGrok=$false,[bool]$WireCodex=$false,[switch]$Quiet)
$ErrorActionPreference='Stop'
$root=$env:SKYRIM_FORGE_ROOT
if (-not $root) { $root=[Environment]::GetEnvironmentVariable('SKYRIM_FORGE_ROOT','User') }
if (-not $root) { throw 'Install Skyrim Forge first: TOOLS\Install-SkyrimForge.ps1.' }
$setup=Join-Path $root 'integrations\skyrim-pack\skills\housecarl\scripts\Setup-HouseCarl.ps1'
if (-not (Test-Path -LiteralPath $setup -PathType Leaf)) { throw "Forge-owned houseCARL setup missing: $setup" }
& $setup -WireGrok:$WireGrok -WireCodex:$WireCodex -Quiet:$Quiet
