$ErrorActionPreference = "Stop"

$Dir = Join-Path $env:LOCALAPPDATA "ClipMate"
$PauseFile = if ($env:CLIPMATE_PAUSE_FILE) { $env:CLIPMATE_PAUSE_FILE } else { Join-Path $Dir "paused" }

Remove-Item -LiteralPath $PauseFile -Force -ErrorAction SilentlyContinue

Write-Host "ClipMate resumed."
