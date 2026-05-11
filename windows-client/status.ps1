$ErrorActionPreference = "Stop"

$Dir = Join-Path $env:LOCALAPPDATA "ClipMate"
$PauseFile = if ($env:CLIPMATE_PAUSE_FILE) { $env:CLIPMATE_PAUSE_FILE } else { Join-Path $Dir "paused" }

if (Test-Path -LiteralPath $PauseFile) {
  Write-Host "ClipMate is paused."
}
else {
  Write-Host "ClipMate is running."
}
