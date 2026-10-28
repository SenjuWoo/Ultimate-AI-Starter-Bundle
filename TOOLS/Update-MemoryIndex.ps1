# Regenerate the source-only maintainer index; -Check never writes.
# Machine paths, preferences and task progress are deliberately not inputs.
[CmdletBinding()]
param([switch]$Check)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UABS-Common.ps1')
$python = Get-UabsPythonExecutable
if (-not $python) { throw 'A shared Python interpreter is required.' }
$arguments = @((Join-Path $PSScriptRoot 'update_memory_index.py'))
if ($Check) { $arguments += '--check' }
& $python @arguments
exit $LASTEXITCODE
