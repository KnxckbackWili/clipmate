#!/usr/bin/env bash
set -euo pipefail

PAUSE_FILE="${CLIPMATE_PAUSE_FILE:-$HOME/.clipmate-paused}"
touch "$PAUSE_FILE"
echo "ClipMate paused."
