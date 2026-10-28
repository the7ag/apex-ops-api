#!/usr/bin/env bash
# Reproducible demos for the assessment evidence. Output is saved to docs/evidence/<demo>.log
#
# Usage: scripts/demo.sh release | auto-rollback | db-outage | all
#   release        build 1.0.0 + 1.1.0, deploy both, then roll back
#   auto-rollback  deploy a deliberately broken 1.2.0 -> readiness fails -> automatic rollback
#   db-outage      stop the database, investigate with health/ready/logs, recover
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

EVIDENCE=docs/evidence
step() { echo; echo "================ $* ================"; }
run()  { echo "\$ $*"; "$@"; }

build() {  # build <version>
  APP_VERSION="$1" docker compose build -q api && log "built apex-ops-api:$1"
}

demo_release() {
  step "Clean start (database volume is kept)"
  run docker compose down
  rm -f .current_version .previous_version

  step "Build versioned images"
  build 1.0.0
  build 1.1.0

  step "Deploy 1.0.0"
  run scripts/deploy.sh 1.0.0
  run curl -s -X POST localhost:8000/items -H 'content-type: application/json' \
    -d '{"name":"created on 1.0.0"}'; echo

  step "Release 1.1.0"
  run scripts/deploy.sh 1.1.0

  step "Roll back to the previous version"
  run scripts/rollback.sh
  echo "Data still present after rollback:"
  run curl -s localhost:8000/items; echo
}

demo_auto_rollback() {
  step "Make sure a good version (1.1.0) is running"
  build 1.1.0
  run scripts/deploy.sh 1.1.0

  step "Build a BROKEN 1.2.0 (bug: readiness query hits a table that does not exist)"
  local tmp; tmp=$(mktemp -d)
  cp -r app Dockerfile requirements.txt .dockerignore "$tmp"/
  sed -i 's/SELECT 1"/SELECT 1 FROM table_that_does_not_exist"/' "$tmp/app/main.py"
  grep -n "table_that_does_not_exist" "$tmp/app/main.py"
  docker build -q --build-arg APP_VERSION=1.2.0 -t apex-ops-api:1.2.0 "$tmp" >/dev/null
  rm -rf "$tmp"
  log "built apex-ops-api:1.2.0 (broken on purpose)"

  step "Deploy 1.2.0 - expected to FAIL and roll back automatically"
  READY_TIMEOUT=20 scripts/deploy.sh 1.2.0 && echo "UNEXPECTED: broken release passed" \
    || echo "deploy.sh exited non-zero as expected"

  step "Verify service is healthy on the previous version"
  run curl -s localhost:8000/version; echo
  run curl -s localhost:8000/ready; echo
}

demo_db_outage() {
  step "Baseline"
  run docker compose ps --format 'table {{.Service}}\t{{.Status}}'
  run curl -s -w ' HTTP %{http_code}\n' localhost:8000/ready

  step "Inject failure: stop the database"
  run docker compose stop db

  step "Symptoms"
  run curl -s -w ' HTTP %{http_code}\n' localhost:8000/health
  run curl -s -w ' HTTP %{http_code}\n' localhost:8000/ready
  run curl -s -w ' HTTP %{http_code}\n' localhost:8000/items

  step "Investigate"
  run docker compose ps -a --format 'table {{.Service}}\t{{.Status}}'
  echo "\$ docker compose logs --tail=4 api"
  docker compose logs --no-log-prefix --tail=4 api

  step "Fix: start the database and verify recovery"
  run docker compose start db
  wait_ready && log "service ready again"
  run curl -s -w ' HTTP %{http_code}\n' localhost:8000/ready
  run curl -s localhost:8000/items; echo
}

record() {  # record <name> <function>
  log "Recording $1 -> $EVIDENCE/$1.log"
  "$2" 2>&1 | tee "$EVIDENCE/$1.log"
}

case "${1:-}" in
  release)       record release-rollback demo_release ;;
  auto-rollback) record auto-rollback demo_auto_rollback ;;
  db-outage)     record db-outage demo_db_outage ;;
  all)
    record release-rollback demo_release
    record auto-rollback demo_auto_rollback
    record db-outage demo_db_outage ;;
  *) echo "usage: $0 release|auto-rollback|db-outage|all"; exit 1 ;;
esac
