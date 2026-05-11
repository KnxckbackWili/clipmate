$ErrorActionPreference = "Stop"

$Repo = "KnxckbackWili/clipmate"
$AssetUrl = "https://github.com/$Repo/releases/latest/download/ClipMate-Windows.zip"
$AppDir = Join-Path $env:LOCALAPPDATA "ClipMate"
$ZipPath = Join-Path $env:TEMP "ClipMate-Windows.zip"

if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
  Write-Error "PowerShell 7 is required. Install it from https://aka.ms/powershell"
}

New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

Write-Host "Downloading ClipMate for Windows..."
Invoke-WebRequest -Uri $AssetUrl -OutFile $ZipPath

Write-Host "Installing ClipMate..."
Expand-Archive -Path $ZipPath -DestinationPath $AppDir -Force

$Startup = [Environment]::GetFolderPath("Startup")
$ShortcutPath = Join-Path $Startup "ClipMate Tray.lnk"
$ScriptPath = Join-Path $AppDir "clipmate-tray.ps1"

$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = "pwsh.exe"
$Shortcut.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""
$Shortcut.WorkingDirectory = $AppDir
$Shortcut.Save()

Write-Host "Starting ClipMate..."
Start-Process "pwsh.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`""

Write-Host ""
Write-Host "ClipMate installed. Use the tray icon to open Settings and enter Server, Token, Room, and optional Encryption Secret."
