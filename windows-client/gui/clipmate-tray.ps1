Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ErrorActionPreference = "Stop"

$AppDir = Join-Path $env:LOCALAPPDATA "ClipMate"
$ConfigPath = Join-Path $AppDir "config.json"
New-Item -ItemType Directory -Path $AppDir -Force | Out-Null

$State = @{
  Server = ""
  Token = ""
  Room = "home"
  Secret = ""
  Device = $env:COMPUTERNAME
  Paused = $false
  LastSeenHash = ""
  LastAppliedRemoteHash = ""
  Status = "Starting"
}

function Save-Config {
  @{
    Server = $State.Server
    Token = $State.Token
    Room = $State.Room
    Secret = $State.Secret
    Paused = $State.Paused
  } | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $ConfigPath
}

function Load-Config {
  if (Test-Path $ConfigPath) {
    $Config = Get-Content -Raw -Path $ConfigPath | ConvertFrom-Json
    foreach ($Name in "Server", "Token", "Room", "Secret", "Paused") {
      if ($null -ne $Config.$Name) { $State[$Name] = $Config.$Name }
    }
  }
}

function Get-TextHash {
  param([string]$Text)
  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $Hash = $Sha.ComputeHash($Bytes)
    return ([BitConverter]::ToString($Hash)).Replace("-", "").ToLowerInvariant()
  }
  finally { $Sha.Dispose() }
}

function Get-KeyBytes {
  param([string]$Secret)
  $Sha = [System.Security.Cryptography.SHA256]::Create()
  try { return $Sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Secret)) }
  finally { $Sha.Dispose() }
}

function Protect-ClipText {
  param([string]$Text)
  if ([string]::IsNullOrEmpty($State.Secret)) { return $Text }
  if (-not ("System.Security.Cryptography.AesGcm" -as [type])) {
    throw "PowerShell 7 or newer is required for encrypted sync."
  }

  $Key = Get-KeyBytes $State.Secret
  $Nonce = New-Object byte[] 12
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($Nonce)
  $Plain = [System.Text.Encoding]::UTF8.GetBytes($Text)
  $Cipher = New-Object byte[] $Plain.Length
  $Tag = New-Object byte[] 16
  $Aes = [System.Security.Cryptography.AesGcm]::new($Key)
  try { $Aes.Encrypt($Nonce, $Plain, $Cipher, $Tag) }
  finally { $Aes.Dispose() }

  $Combined = New-Object byte[] ($Nonce.Length + $Cipher.Length + $Tag.Length)
  [Array]::Copy($Nonce, 0, $Combined, 0, $Nonce.Length)
  [Array]::Copy($Cipher, 0, $Combined, $Nonce.Length, $Cipher.Length)
  [Array]::Copy($Tag, 0, $Combined, $Nonce.Length + $Cipher.Length, $Tag.Length)

  return (@{
    v = 1
    alg = "AES-256-GCM-SHA256"
    data = [Convert]::ToBase64String($Combined)
  } | ConvertTo-Json -Compress)
}

function Unprotect-ClipText {
  param([string]$Payload)
  if ([string]::IsNullOrEmpty($State.Secret)) { return $Payload }
  if (-not ("System.Security.Cryptography.AesGcm" -as [type])) {
    throw "PowerShell 7 or newer is required for encrypted sync."
  }

  $Envelope = $Payload | ConvertFrom-Json
  if ($Envelope.v -ne 1 -or $Envelope.alg -ne "AES-256-GCM-SHA256") {
    throw "Encrypted payload requires the same secret."
  }
  $Combined = [Convert]::FromBase64String([string]$Envelope.data)
  $Nonce = New-Object byte[] 12
  $Tag = New-Object byte[] 16
  $Cipher = New-Object byte[] ($Combined.Length - 28)
  [Array]::Copy($Combined, 0, $Nonce, 0, 12)
  [Array]::Copy($Combined, 12, $Cipher, 0, $Cipher.Length)
  [Array]::Copy($Combined, 12 + $Cipher.Length, $Tag, 0, 16)
  $Plain = New-Object byte[] $Cipher.Length
  $Aes = [System.Security.Cryptography.AesGcm]::new((Get-KeyBytes $State.Secret))
  try { $Aes.Decrypt($Nonce, $Cipher, $Tag, $Plain) }
  finally { $Aes.Dispose() }
  return [System.Text.Encoding]::UTF8.GetString($Plain)
}

function Invoke-ClipmateRequest {
  param([string]$Method, [string]$Path, [object]$Body = $null)
  if ([string]::IsNullOrWhiteSpace($State.Server) -or [string]::IsNullOrWhiteSpace($State.Token)) {
    throw "Open Settings first."
  }
  $Headers = @{ Authorization = "Bearer $($State.Token)" }
  $Uri = "$($State.Server.TrimEnd('/'))$Path"
  if ($null -eq $Body) {
    return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -TimeoutSec 8
  }
  $Json = $Body | ConvertTo-Json -Depth 4 -Compress
  return Invoke-RestMethod -Method $Method -Uri $Uri -Headers $Headers -ContentType "application/json" -Body $Json -TimeoutSec 8
}

function Get-ClipboardTextSafe {
  try { return [string](Get-Clipboard -Raw -Format Text) } catch { return "" }
}

function Set-ClipboardTextSafe {
  param([string]$Text)
  Set-Clipboard -Value $Text
}

function Sync-Tick {
  try {
    $EscapedRoom = [uri]::EscapeDataString($State.Room)
    $EscapedDevice = [uri]::EscapeDataString($State.Device)
    $DeviceState = Invoke-ClipmateRequest -Method "POST" -Path "/v1/rooms/$EscapedRoom/devices/$EscapedDevice/heartbeat" -Body @{ local_paused = [bool]$State.Paused }
    if ($State.Paused) { $State.Status = "Paused"; return }
    if ($null -ne $DeviceState -and -not [bool]$DeviceState.enabled) { $State.Status = "Disabled by relay"; return }

    $LocalText = Get-ClipboardTextSafe
    $LocalHash = Get-TextHash $LocalText
    if (-not [string]::IsNullOrEmpty($LocalText) -and $LocalHash -ne $State.LastSeenHash -and $LocalHash -ne $State.LastAppliedRemoteHash) {
      $Payload = Protect-ClipText $LocalText
      Invoke-ClipmateRequest -Method "PUT" -Path "/v1/rooms/$EscapedRoom/clip" -Body @{
        text = $Payload
        device = $State.Device
        hash = Get-TextHash $Payload
      } | Out-Null
      $State.LastSeenHash = $LocalHash
    }

    $Remote = Invoke-ClipmateRequest -Method "GET" -Path "/v1/rooms/$EscapedRoom/clip"
    if ($null -ne $Remote -and $Remote.device -ne $State.Device) {
      $RemoteText = Unprotect-ClipText ([string]$Remote.text)
      $RemoteHash = Get-TextHash $RemoteText
      if (-not [string]::IsNullOrEmpty($RemoteText) -and $RemoteHash -ne (Get-TextHash (Get-ClipboardTextSafe))) {
        Set-ClipboardTextSafe $RemoteText
        $State.LastAppliedRemoteHash = $RemoteHash
        $State.LastSeenHash = $RemoteHash
      }
    }
    $State.Status = "Connected"
  }
  catch {
    $State.Status = $_.Exception.Message
  }
}

function Show-Settings {
  $Form = New-Object Windows.Forms.Form
  $Form.Text = "ClipMate Settings"
  $Form.Size = New-Object Drawing.Size(480, 300)
  $Form.StartPosition = "CenterScreen"
  $Form.FormBorderStyle = "FixedDialog"
  $Form.MaximizeBox = $false

  $Fields = @{}
  $Labels = @("Server", "Token", "Room", "Encryption Secret")
  $Values = @($State.Server, $State.Token, $State.Room, $State.Secret)
  for ($i = 0; $i -lt $Labels.Count; $i++) {
    $Label = New-Object Windows.Forms.Label
    $Label.Text = $Labels[$i]
    $Label.Location = New-Object Drawing.Point(22, (24 + $i * 46))
    $Label.Size = New-Object Drawing.Size(130, 24)
    $Box = New-Object Windows.Forms.TextBox
    $Box.Text = $Values[$i]
    $Box.Location = New-Object Drawing.Point(160, (20 + $i * 46))
    $Box.Size = New-Object Drawing.Size(280, 26)
    if ($Labels[$i] -match "Token|Secret") { $Box.UseSystemPasswordChar = $true }
    $Form.Controls.Add($Label)
    $Form.Controls.Add($Box)
    $Fields[$Labels[$i]] = $Box
  }

  $Save = New-Object Windows.Forms.Button
  $Save.Text = "Save"
  $Save.Location = New-Object Drawing.Point(342, 214)
  $Save.Size = New-Object Drawing.Size(98, 32)
  $Save.Add_Click({
    $State.Server = $Fields["Server"].Text.TrimEnd("/")
    $State.Token = $Fields["Token"].Text
    $State.Room = if ($Fields["Room"].Text) { $Fields["Room"].Text } else { "home" }
    $State.Secret = $Fields["Encryption Secret"].Text
    Save-Config
    $Form.Close()
  })
  $Form.Controls.Add($Save)
  [void]$Form.ShowDialog()
}

Load-Config
$State.LastSeenHash = Get-TextHash (Get-ClipboardTextSafe)
$Icon = [System.Drawing.SystemIcons]::Information
$Notify = New-Object Windows.Forms.NotifyIcon
$Notify.Icon = $Icon
$Notify.Visible = $true
$Notify.Text = "ClipMate"

$Menu = New-Object Windows.Forms.ContextMenuStrip
$StatusItem = $Menu.Items.Add("Status: Starting")
$RoomItem = $Menu.Items.Add("Room: $($State.Room)")
$Menu.Items.Add("-") | Out-Null
$PauseItem = $Menu.Items.Add("Pause Sync")
$SettingsItem = $Menu.Items.Add("Settings...")
$Menu.Items.Add("-") | Out-Null
$QuitItem = $Menu.Items.Add("Quit")
$Notify.ContextMenuStrip = $Menu

$PauseItem.Add_Click({
  $State.Paused = -not $State.Paused
  Save-Config
})
$SettingsItem.Add_Click({ Show-Settings })
$QuitItem.Add_Click({
  $Notify.Visible = $false
  [Windows.Forms.Application]::Exit()
})
$Notify.Add_DoubleClick({ Show-Settings })

$Timer = New-Object Windows.Forms.Timer
$Timer.Interval = 1000
$Timer.Add_Tick({
  Sync-Tick
  $StatusItem.Text = "Status: $($State.Status)"
  $RoomItem.Text = "Room: $($State.Room)"
  $PauseItem.Text = if ($State.Paused) { "Resume Sync" } else { "Pause Sync" }
  $Notify.Text = "ClipMate - $($State.Status)"
})
$Timer.Start()

[Windows.Forms.Application]::Run()
