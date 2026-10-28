#!/usr/bin/env bash
# Usage: scripts/rollback.sh [version]
# Rolls back to the given version, or to the previously deployed one.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

TARGET="${1:-$(cat .previous_version 2>/dev/null || true)}"
CURRENT="$(cat .current_version 2>/dev/null || true)"
[[ -n "$TARGET" ]] || { log "No previous version recorded; pass one explicitly"; exit 1; }

log "Rolling back: ${CURRENT:-unknown} -> $TARGET"
start_version "$TARGET"

if wait_ready; then
  echo "$TARGET" > .current_version
  [[ -n "$CURRENT" ]] && echo "$CURRENT" > .previous_version
  log "SUCCESS: rolled back to version=$TARGET"
  curl -fs http://localhost:8000/version; echo
else
  log "FAILED: version=$TARGET not ready - escalate (see RUNBOOK)"
  exit 1
fi
