param(
  [string]$Server = $env:CLIPMATE_SERVER,
  [string]$Token = $env:CLIPMATE_TOKEN,
  [string]$Room = $(if ($env:CLIPMATE_ROOM) { $env:CLIPMATE_ROOM } else { "default" }),
  [string]$Device = $(if ($env:CLIPMATE_DEVICE) { $env:CLIPMATE_DEVICE } else { $env:COMPUTERNAME }),
  [string]$Secret = $env:CLIPMATE_SECRET,
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

function Get-KeyBytes {
  param([string]$Text)

  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return $Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))
  }
  finally {
    $Sha.Dispose()
  }
}

function Protect-ClipText {
  param([string]$Text)

  if ([string]::IsNullOrEmpty($Secret)) {
    return $Text
  }
  if (-not ("System.Security.Cryptography.AesGcm" -as [type])) {
    throw "CLIPMATE_SECRET requires PowerShell 7 or newer."
  }

  $Nonce = New-Object byte[] 12
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($Nonce)
  $Plain = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Cipher = New-Object byte[] $Plain.Length
  $Tag = New-Object byte[] 16
  $Aes = [System.Security.Cryptography.AesGcm]::new((Get-KeyBytes $Secret))
  try {
    $Aes.Encrypt($Nonce, $Plain, $Cipher, $Tag)
  }
  finally {
    $Aes.Dispose()
  }

  $Combined = New-Object byte[] ($Nonce.Length + $Cipher.Length + $Tag.Length)
  [Array]::Copy($Nonce, 0, $Combined, 0, $Nonce.Length)
  [Array]::Copy($Cipher, 0, $Combined, $Nonce.Length, $Cipher.Length)
  [Array]::Copy($Tag, 0, $Combined, $Nonce.Length + $Cipher.Length, $Tag.Length)
  return (@{ v = 1; alg = "AES-256-GCM-SHA256"; data = [Convert]::ToBase64String($Combined) } | ConvertTo-Json -Compress)
}

function Unprotect-ClipText {
  param([string]$Payload)

  if ([string]::IsNullOrEmpty($Secret)) {
    return $Payload
  }
  if (-not ("System.Security.Cryptography.AesGcm" -as [type])) {
    throw "CLIPMATE_SECRET requires PowerShell 7 or newer."
  }

  $Envelope = $Payload | ConvertFrom-Json
  if ($Envelope.v -ne 1 -or $Envelope.alg -ne "AES-256-GCM-SHA256") {
    throw "Encrypted payload requires the same CLIPMATE_SECRET."
  }
  $Combined = [Convert]::FromBase64String([string]$Envelope.data)
  $Nonce = New-Object byte[] 12
  $Tag = New-Object byte[] 16
  $Cipher = New-Object byte[] ($Combined.Length - 28)
  [Array]::Copy($Combined, 0, $Nonce, 0, 12)
  [Array]::Copy($Combined, 12, $Cipher, 0, $Cipher.Length)
  [Array]::Copy($Combined, 12 + $Cipher.Length, $Tag, 0, 16)
  $Plain = New-Object byte[] $Cipher.Length
  $Aes = [System.Security.Cryptography.AesGcm]::new((Get-KeyBytes $Secret))
  try {
    $Aes.Decrypt($Nonce, $Cipher, $Tag, $Plain)
  }
  finally {
    $Aes.Dispose()
  }
  return [System.Text.Encoding]::UTF8.GetString($Plain)
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
  $Payload = Protect-ClipText $Text
  Invoke-ClipmateRequest -Method "PUT" -Path "/v1/rooms/$EscapedRoom/clip" -Body @{
    text = $Payload
    device = $Device
    hash = Get-TextHash $Payload
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
      $RemoteText = Unprotect-ClipText ([string]$Remote.text)
      $RemoteHash = Get-TextHash $RemoteText
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
