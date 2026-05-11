$ErrorActionPreference = "Stop"

$Dir = Join-Path $env:LOCALAPPDATA "ClipMate"
$PauseFile = if ($env:CLIPMATE_PAUSE_FILE) { $env:CLIPMATE_PAUSE_FILE } else { Join-Path $Dir "paused" }

New-Item -ItemType Directory -Path (Split-Path -Parent $PauseFile) -Force | Out-Null
New-Item -ItemType File -Path $PauseFile -Force | Out-Null

Write-Host "ClipMate paused."
