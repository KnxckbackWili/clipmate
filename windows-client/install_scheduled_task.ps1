param(
  [Parameter(Mandatory = $true)]
  [string]$Server,

  [Parameter(Mandatory = $true)]
  [string]$Token,

  [string]$Room = "default",

  [string]$Secret = ""
)

$ErrorActionPreference = "Stop"

$TaskName = "ClipMate"
$ScriptPath = Join-Path $PSScriptRoot "clipmate.ps1"
$LogDir = Join-Path $env:LOCALAPPDATA "ClipMate"
$LogPath = Join-Path $LogDir "clipmate.log"

New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$Argument = @(
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", "`"$ScriptPath`"",
  "-Server", "`"$Server`"",
  "-Token", "`"$Token`"",
  "-Room", "`"$Room`"",
  "-Secret", "`"$Secret`"",
  "*>", "`"$LogPath`""
) -join " "

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $Argument
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings | Out-Null
Start-ScheduledTask -TaskName $TaskName

Write-Host "ClipMate scheduled task installed and started."
Write-Host "Log: $LogPath"
