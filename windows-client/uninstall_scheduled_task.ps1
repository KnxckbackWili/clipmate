$ErrorActionPreference = "Stop"

Unregister-ScheduledTask -TaskName "ClipMate" -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "ClipMate scheduled task removed."
