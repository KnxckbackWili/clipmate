#!/usr/bin/env bash
set -euo pipefail

REPO="KnxckbackWili/clipmate"
ASSET_URL="https://github.com/$REPO/releases/latest/download/ClipMate-macOS.zip"
TMP_DIR="$(mktemp -d)"
APP_NAME="ClipMate.app"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Downloading ClipMate for macOS..."
curl -fL "$ASSET_URL" -o "$TMP_DIR/ClipMate-macOS.zip"

echo "Installing ClipMate..."
unzip -q "$TMP_DIR/ClipMate-macOS.zip" -d "$TMP_DIR"

DEST="/Applications"
if [[ ! -w "$DEST" ]]; then
  DEST="$HOME/Applications"
  mkdir -p "$DEST"
fi

rm -rf "$DEST/$APP_NAME"
ditto "$TMP_DIR/$APP_NAME" "$DEST/$APP_NAME"
xattr -dr com.apple.quarantine "$DEST/$APP_NAME" 2>/dev/null || true

echo "Opening ClipMate..."
open "$DEST/$APP_NAME"

echo
echo "ClipMate installed: $DEST/$APP_NAME"
echo "Use the menu bar item to open Settings and enter Server, Token, Room, and optional Encryption Secret."
