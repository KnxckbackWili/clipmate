#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <server-url> <token> [room]" >&2
  echo "Example: $0 https://clip.example.com 'long-random-token' home" >&2
  exit 1
fi

SERVER_URL="$1"
TOKEN="$2"
ROOM="${3:-default}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.clipmate.client.plist"

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.clipmate.client</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/bin/python3</string>
    <string>${SCRIPT_DIR}/clipmate.py</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLIPMATE_SERVER</key>
    <string>${SERVER_URL}</string>
    <key>CLIPMATE_TOKEN</key>
    <string>${TOKEN}</string>
    <key>CLIPMATE_ROOM</key>
    <string>${ROOM}</string>
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/clipmate.out.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/clipmate.err.log</string>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
launchctl enable "gui/$(id -u)/com.clipmate.client"

echo "ClipMate LaunchAgent installed and started: $PLIST"
