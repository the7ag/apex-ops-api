#!/usr/bin/env bash
# Shared helpers for deploy.sh / rollback.sh

READY_URL="${READY_URL:-http://localhost:8000/ready}"
READY_TIMEOUT="${READY_TIMEOUT:-60}"

log() { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*"; }

# Start the api container at a given image version.
start_version() {
  APP_VERSION="$1" docker compose up -d --no-build api
}

# Poll /ready until it returns 200 or we time out.
wait_ready() {
  local deadline=$((SECONDS + READY_TIMEOUT))
  while (( SECONDS < deadline )); do
    if curl -fs "$READY_URL" >/dev/null; then
      return 0
    fi
    sleep 2
  done
  return 1
}
