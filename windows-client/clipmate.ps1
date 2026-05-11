param(
  [string]$Server = $env:CLIPMATE_SERVER,
  [string]$Token = $env:CLIPMATE_TOKEN,
  [string]$Room = $(if ($env:CLIPMATE_ROOM) { $env:CLIPMATE_ROOM } else { "default" }),
  [string]$Device = $(if ($env:CLIPMATE_DEVICE) { $env:CLIPMATE_DEVICE } else { $env:COMPUTERNAME }),
  [double]$PollSeconds = $(if ($env:CLIPMATE_POLL_SECONDS) { [double]$env:CLIPMATE_POLL_SECONDS } else { 0.8 }),
  [int]$MaxChars = $(if ($env:CLIPMATE_MAX_CHARS) { [int]$env:CLIPMATE_MAX_CHARS } else { 524288 }),
  [string]$PauseFile = $(if ($env:CLIPMATE_PAUSE_FILE) { $env:CLIPMATE_PAUSE_FILE } else { Join-Path $env:LOCALAPPDATA "ClipMate\paused" })
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Server)) {
  throw "CLIPMATE_SERVER is required, for example https://clip.example.com"
}

if ([string]::IsNullOrWhiteSpace($Token)) {
  throw "CLIPMATE_TOKEN is required"
}

$Server = $Server.TrimEnd("/")
$Headers = @{ Authorization = "Bearer $Token" }
$LastAppliedRemoteHash = ""

function Get-TextHash {
  param([string]$Text)

  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Hash = $Sha.ComputeHash($Bytes)
    return ([BitConverter]::ToString($Hash)).Replace("-", "").ToLowerInvariant()
  }
  finally {
    $Sha.Dispose()
  }
}

function Get-ClipboardTextSafe {
  try {
    $Text = Get-Clipboard -Raw -Format Text
    if ($null -eq $Text) {
      return ""
    }
    return [string]$Text
  }
  catch {
    return ""
  }
}

function Set-ClipboardTextSafe {
  param([string]$Text)
  Set-Clipboard -Value $Text
}

function Test-ClipmatePaused {
  return Test-Path -LiteralPath $PauseFile
}

function Invoke-ClipmateRequest {
  param(
    [string]$Method,
    [string]$Path,
    [object]$Body = $null
  )

  $Uri = "$Server$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -TimeoutSec 8
  }

  $Json = $Body | ConvertTo-Json -Depth 4 -Compress
  return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $Json -TimeoutSec 8
}

function Push-Clip {
  param(
    [string]$Text,
    [string]$Hash
  )

  $EscapedRoom = [uri]::EscapeDataString($Room)
  Invoke-ClipmateRequest -Method "PUT" -Path "/v1/rooms/$EscapedRoom/clip" -Body @{
    text = $Text
    device = $Device
    hash = $Hash
  } | Out-Null
}

function Pull-Clip {
  $EscapedRoom = [uri]::EscapeDataString($Room)
  return Invoke-ClipmateRequest -Method "GET" -Path "/v1/rooms/$EscapedRoom/clip"
}

function Send-Heartbeat {
  param([bool]$LocalPaused)

  $EscapedRoom = [uri]::EscapeDataString($Room)
  $EscapedDevice = [uri]::EscapeDataString($Device)
  return Invoke-ClipmateRequest -Method "POST" -Path "/v1/rooms/$EscapedRoom/devices/$EscapedDevice/heartbeat" -Body @{
    local_paused = $LocalPaused
  }
}

$InitialText = Get-ClipboardTextSafe
$LastSeenHash = Get-TextHash $InitialText
$LastAppliedRemoteHash = $LastSeenHash

Write-Host "clipmate: syncing room '$Room' as '$Device' via $Server"

while ($true) {
  try {
    $LocalPaused = Test-ClipmatePaused
    $DeviceState = Send-Heartbeat -LocalPaused $LocalPaused
    $RemoteEnabled = if ($null -eq $DeviceState) { $true } else { [bool]$DeviceState.enabled }

    if ($LocalPaused -or -not $RemoteEnabled) {
      $LocalText = Get-ClipboardTextSafe
      $LastSeenHash = Get-TextHash $LocalText
      $LastAppliedRemoteHash = $LastSeenHash
      Start-Sleep -Seconds $PollSeconds
      continue
    }

    $LocalText = Get-ClipboardTextSafe
    $LocalHash = Get-TextHash $LocalText

    if (
      -not [string]::IsNullOrEmpty($LocalText) -and
      $LocalHash -ne $LastSeenHash -and
      $LocalHash -ne $LastAppliedRemoteHash
    ) {
      if ($LocalText.Length -le $MaxChars) {
        Push-Clip -Text $LocalText -Hash $LocalHash
        $LastSeenHash = $LocalHash
      }
    }

    $Remote = Pull-Clip
    if ($null -ne $Remote -and $Remote.device -ne $Device) {
      $RemoteText = [string]$Remote.text
      $RemoteHash = if ($Remote.hash) { [string]$Remote.hash } else { Get-TextHash $RemoteText }
      $CurrentHash = Get-TextHash (Get-ClipboardTextSafe)

      if (-not [string]::IsNullOrEmpty($RemoteText) -and $RemoteHash -ne $CurrentHash) {
        Set-ClipboardTextSafe -Text $RemoteText
        $LastAppliedRemoteHash = $RemoteHash
        $LastSeenHash = $RemoteHash
      }
    }
  }
  catch {
    Write-Error "clipmate: $($_.Exception.Message)"
  }

  Start-Sleep -Seconds $PollSeconds
}
