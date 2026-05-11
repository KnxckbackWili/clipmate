$ErrorActionPreference = "Stop"

$ScriptPath = Join-Path $PSScriptRoot "clipmate-tray.ps1"
$Startup = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $Startup "ClipMate Tray.lnk"

$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "pwsh.exe"
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
$Shortcut.WorkingDirectory = $PSScriptRoot
$Shortcut.Save()

Write-Host "ClipMate tray startup shortcut installed: $ShortcutPath"
