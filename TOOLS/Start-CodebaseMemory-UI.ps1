# Starts exactly one codebase-memory dashboard host.
# The HTTP UI is served by the MCP process and dies when its stdin closes, so
# this launches it under a hidden console that keeps stdin open. MCP clients
# keep args=[] and coexist with this host; port 9749 has a single binder.
param(
  [string]$Exe = (Join-Path $env:LOCALAPPDATA 'Programs\codebase-memory-mcp\codebase-memory-mcp.exe'),
  [int]$Port = 9749
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $Exe -PathType Leaf)) {
  throw "codebase-memory-mcp.exe not found at $Exe"
}
$listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if ($listening) {
  Write-Host "codebase-memory UI already listening on http://127.0.0.1:$Port/"
  exit 0
}
# --ui=true is persisted globally by the tool; the hidden console only keeps
# this process alive. Do not add --ui to any provider's MCP args.
# /s plus an outer pair of quotes: without them cmd drops the quotes around a path
# that contains ( ) or &, and /v:off keeps a '!' in the path literal.
Start-Process -FilePath $env:ComSpec -ArgumentList '/d', '/v:off', '/s', '/c', "`"`"$Exe`" --ui=true`"" -WindowStyle Hidden
Start-Sleep -Seconds 2
$listening = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
if (-not $listening) { throw "codebase-memory UI did not bind http://127.0.0.1:$Port/" }
Write-Host "codebase-memory UI: http://127.0.0.1:$Port/"
