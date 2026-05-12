#!/usr/bin/env sh
set -eu

if [ -n "${CLIPMATE_DOMAIN:-}" ]; then
  APP_HOST="127.0.0.1"
else
  APP_HOST="0.0.0.0"
fi

uvicorn app:app --host "$APP_HOST" --port 8080 &
APP_PID="$!"

shutdown() {
  kill "$APP_PID" 2>/dev/null || true
}
trap shutdown INT TERM

if [ -n "${CLIPMATE_DOMAIN:-}" ]; then
  exec caddy run --config /app/Caddyfile --adapter caddyfile
fi

wait "$APP_PID"
