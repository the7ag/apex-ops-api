# Runbook: Apex Operations API

Operational procedures for the local Docker Compose deployment. All commands run from the
repository root in a bash shell (Git Bash on Windows).

| Quick reference | Command |
|---|---|
| Status | `docker compose ps` |
| Is it serving? | `curl localhost:8000/ready` |
| Which version? | `curl localhost:8000/version` |
| Logs | `docker compose logs --tail=100 api db` |
| Deploy | `scripts/deploy.sh <version>` |
| Roll back | `scripts/rollback.sh [version]` |

---

## 1. Deploy

**Before you start:** `.env` exists (`cp .env.example .env`) and Docker is running.

1. **Get the image.** Either:
   - Build locally: `APP_VERSION=1.1.0 docker compose build api` (tags `apex-ops-api:1.1.0`), or
   - Use the CI-published image: set `IMAGE_NAME=ghcr.io/the7ag/apex-ops-api` in `.env`, then
     `APP_VERSION=1.0.0 docker compose pull api`.
2. **Deploy:** `scripts/deploy.sh 1.1.0`
   - Starts the database if needed, replaces the api container with the new version.
   - Polls `/ready` for up to 60 s (`READY_TIMEOUT` to change).
   - **On success:** records the version in `.current_version` and the old one in `.previous_version`.
   - **On failure:** prints the last 30 api log lines and **automatically rolls back** to the
     version that was running before, then exits non-zero.
3. **Verify:** `curl localhost:8000/version` returns the new version and `curl localhost:8000/ready` returns 200.

Evidence: [`evidence/release-rollback.log`](evidence/release-rollback.log)

## 2. Rollback

| Situation | Command |
|---|---|
| Undo the last deploy | `scripts/rollback.sh` (uses `.previous_version`) |
| Go to a specific version | `scripts/rollback.sh 1.0.0` |
| Deploy failed readiness | Nothing to do, `deploy.sh` already rolled back automatically |

Verify afterwards with `/version` and `/ready`.

**Why rollback is safe:** images are immutable and versioned, so rolling back just points the
container at an older tag that already passed CI. Data lives in the `pgdata` volume, which is
not touched by deploys or rollbacks.

**Database schema rule:** schema changes must be *backward compatible* (expand → migrate →
contract): add new columns/tables first, and only remove old ones in a later release once no
running version uses them. Otherwise an older version may not work against the newer schema
and rollback would break. (The current app only creates its table if missing; a real
migration tool such as Alembic is a listed improvement.)

Evidence (automatic rollback of a broken release): [`evidence/auto-rollback.log`](evidence/auto-rollback.log)

## 3. Incident response

1. **Detect.** An alert fires (see section 6) or users report errors. Confirm with
   `curl -i localhost:8000/ready`.
2. **Assess impact.** Is it total (`/health` failing, container down) or partial (`/ready` 503,
   some endpoints 503)? When did it start? Was there a recent deploy (`cat .current_version`,
   `docker compose ps` shows container age)?
3. **Mitigate first, diagnose second.** If it started right after a deploy, roll back
   immediately (`scripts/rollback.sh`). Restoring service matters more than finding the root cause.
4. **Diagnose.** `docker compose ps -a`, `docker compose logs --tail=100 api db`. Logs are
   JSON: search for `"level": "ERROR"` / `"WARNING"`, and use `request_id` to follow one request.
5. **Fix and verify.** Apply the fix, confirm `/ready` = 200 and normal responses.
6. **Follow up.** Write a short post-incident note (template in section 5) with at least one
   prevention action.

## 4. Troubleshooting

| Symptom | Likely cause | Check | Fix |
|---|---|---|---|
| `/ready` 503 and `/health` 200, logs say `failed to resolve host 'db'` | Database container stopped | `docker compose ps -a` shows `db Exited` | `docker compose start db` |
| `/ready` 503, logs show SQL errors (e.g. `UndefinedTable`) | Bad release (code/schema bug) | `cat .current_version`, api logs | `scripts/rollback.sh` |
| `/ready` 503, logs say `password authentication failed` | `.env` credentials changed after the volume was created | api + db logs | Restore the old password in `.env`, or (dev only, **deletes data**) `docker compose down -v` |
| api container keeps restarting | Crash on startup (bad config, DB unreachable at boot) | `docker compose logs api` | Fix `.env`, or roll back |
| `docker compose up` says `set POSTGRES_... in .env` | Missing `.env` | `ls .env` | `cp .env.example .env` |
| `failed to connect to the docker API ... dockerDesktopLinuxEngine` | Docker Desktop not running | Docker Desktop tray icon | Start Docker Desktop, wait for "Engine running" |
| `deploy.sh` error `No such image` | Version not built/pulled | `docker image ls apex-ops-api` | Build or pull that version first |
| `Bind for 0.0.0.0:8000 failed: port is already allocated` | Another process uses port 8000 | `netstat -ano \| findstr :8000` | Stop that process or change the port mapping |
| CI: `ModuleNotFoundError: No module named 'app'` | pytest import path | CI log of "Unit tests" | Fixed: `pythonpath = ["."]` in `pyproject.toml` |
| CI: `Unable to resolve action ...` | Action tag deleted/renamed upstream | "Set up job" annotations | Fixed: actions pinned to commit SHAs |

## 5. Failure investigation (demonstrated): database outage

Reproduce: `bash scripts/demo.sh db-outage`. Full output: [`evidence/db-outage.log`](evidence/db-outage.log)

**Timeline (2026-10-28, UTC)**

| Time | Event |
|---|---|
| 22:34:08 | Baseline: api and db healthy, `/ready` = 200 |
| ~22:34:09 | **Failure injected:** `docker compose stop db` |
| 22:34:09–17 | `/health` = 200, `/ready` = 503 `{"db":"down"}`, `/items` = 503 `{"detail":"database unavailable"}` |
| 22:34:17 | `docker compose ps -a` shows `db Exited (0)`; api logs show `psycopg.OperationalError: failed to resolve host 'db'` |
| 22:34:18 | **Fix:** `docker compose start db` |
| 22:34:18 | `/ready` = 200, `/items` returns all previous items (no data lost) |

**Symptoms.** The API process stayed up (liveness 200) but could not serve data (readiness and
data endpoints 503).

**Diagnosis.** The readiness/health split pointed straight at a dependency, not the app itself.
The structured logs gave the exact error (`failed to resolve host 'db'`), meaning the `db`
container was no longer on the network, and `docker compose ps -a` confirmed it had exited.

**Root cause.** The database container was stopped (simulated outage).

**What went well.**
- The app did not crash or restart-loop; it returned a clean 503 instead of a stack trace.
- It recovered automatically once the DB returned (connection pool `pool_pre_ping`), with no app restart.
- Data persisted in the `pgdata` volume.

**What to improve.**
- Each failing request took ~4 s (`duration_ms: 3972`) because of the default DB connect timeout.
  Set a short `connect_timeout` (e.g. 2 s) so the API fails fast.
- Alert on `/ready` failing (section 6) so a human knows within a minute.
- In production use a managed database with automatic failover.

## 6. Monitoring and alert proposal

**Already implemented:** JSON logs with `request_id`, method, path, status and `duration_ms`
for every request; Docker `HEALTHCHECK` on `/health`; Postgres healthcheck (`pg_isready`);
Prometheus metrics at `/metrics`.

**Proposed alerts** (Prometheus + Alertmanager, or the cloud provider's equivalent):

| Signal | Source | Alert condition | Severity | First action |
|---|---|---|---|---|
| Service not ready | `/ready` probe (blackbox exporter) | failing for > 1 min | Page | Section 3 / troubleshooting table |
| Error rate | `http_requests_total{status="5xx"}` / all requests | > 5% for 5 min | Page | Check recent deploy → roll back |
| Latency | `http_request_duration_seconds` | p95 > 500 ms for 10 min | Warning | Check DB health, load |
| Container restarts | Docker / cAdvisor restart count | > 3 in 10 min | Warning | `docker compose logs api` |
| DB disk usage | node/postgres exporter | > 80% | Warning | Clean up / grow volume |
| Deploy rolled back | `deploy.sh` exit code (CI/CD notification) | any | Info | Investigate the failed version |

Alerts should link to this runbook. Paging alerts only for user-facing impact, to avoid alert fatigue.
