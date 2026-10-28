#!/usr/bin/env bash
# Usage: scripts/deploy.sh <version>
# Deploys the given image version. If it does not become ready, automatically
# rolls back to the version that was running before.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

VERSION="${1:?usage: scripts/deploy.sh <version>}"
CURRENT="$(cat .current_version 2>/dev/null || true)"

log "Deploying version=$VERSION (currently running: ${CURRENT:-none})"
docker compose up -d db
start_version "$VERSION"

if wait_ready; then
  [[ -n "$CURRENT" && "$CURRENT" != "$VERSION" ]] && echo "$CURRENT" > .previous_version
  echo "$VERSION" > .current_version
  log "SUCCESS: version=$VERSION is ready"
  curl -fs http://localhost:8000/version; echo
else
  log "FAILED: version=$VERSION not ready within ${READY_TIMEOUT}s"
  docker compose logs --tail=30 api || true
  if [[ -n "$CURRENT" ]]; then
    log "AUTO-ROLLBACK to version=$CURRENT"
    start_version "$CURRENT"
    wait_ready && log "Rolled back: version=$CURRENT is ready" || log "Rollback ALSO failed - escalate (see RUNBOOK)"
  fi
  exit 1
fi
