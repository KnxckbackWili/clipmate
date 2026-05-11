#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

cd "$ROOT_DIR"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required." >&2
  exit 1
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose is required. On Unraid, install Docker Compose Manager if needed." >&2
  exit 1
fi

if [[ ! -f "$ENV_FILE" ]]; then
  if command -v openssl >/dev/null 2>&1; then
    TOKEN="$(openssl rand -hex 32)"
  else
    TOKEN="$(date +%s | sha256sum | awk '{print $1}')"
  fi
  printf 'CLIPMATE_TOKEN=%s\n' "$TOKEN" > "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "Created .env with a new token:"
  echo "$TOKEN"
else
  echo "Using existing .env"
fi

docker compose up -d --build

echo
echo "ClipMate Relay is running."
echo "Open: http://$(hostname -I | awk '{print $1}'):9673/"
