#!/usr/bin/env bash
set -euo pipefail

PAUSE_FILE="${CLIPMATE_PAUSE_FILE:-$HOME/.clipmate-paused}"

if [[ -f "$PAUSE_FILE" ]]; then
  echo "ClipMate is paused."
else
  echo "ClipMate is running."
fi
