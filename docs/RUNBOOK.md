# Runbook: Apex Operations API

## 1. Deploy
1. Make sure the image exists: `docker image ls apex-ops-api` (or that CI pushed it to GHCR).
2. `scripts/deploy.sh <version>`
3. The script waits for `/ready`. On failure it **automatically rolls back** to the previous version.
4. Verify: `curl localhost:8000/version`

## 2. Rollback
- To the previous version: `scripts/rollback.sh`
- To a specific version: `scripts/rollback.sh 1.0.0`
- Verify: `curl localhost:8000/version` and `curl localhost:8000/ready`
- Database note: TODO, describe how schema changes are kept backward compatible so rollback is safe.

## 3. Incident response
1. **Detect:** alert fires or `/ready` returns 503.
2. **Assess:** `docker compose ps`, `curl localhost:8000/ready`
3. **Mitigate first:** if the incident started after a deploy, roll back (`scripts/rollback.sh`).
4. **Diagnose:** `docker compose logs --tail=100 api db`
5. **Fix and verify**, then write a short post-incident note (timeline, cause, prevention).

## 4. Troubleshooting
| Symptom | Likely cause | Check | Fix |
|---|---|---|---|
| `/ready` = 503, `/health` = 200 | DB down/unreachable | `docker compose ps db`, api logs show `database error` | `docker compose start db` |
| api container restarting | Bad config / crash on start | `docker compose logs api` | Fix env in `.env`, redeploy or roll back |
| `compose up` errors "set POSTGRES_... in .env" | Missing `.env` | `ls .env` | `cp .env.example .env` |
| Port 8000 in use | Another process | `netstat -ano \| findstr 8000` | Stop it or change the port mapping |
| TODO | | | |

## 5. Failure investigation (demonstrated)
TODO: write up your DB-outage drill here: timeline, the commands you ran, the log lines you saw, root cause, fix, prevention.
Evidence: `docs/evidence/...`

## 6. Monitoring and alert proposal
| Signal | Source | Alert condition | Severity |
|---|---|---|---|
| Readiness | `/ready` | failing > 1 min | Page |
| Error rate | `http_requests_total{status="5xx"}` | > 5% for 5 min | Page |
| Latency | `http_request_duration_seconds` | p95 > 500 ms for 10 min | Warn |
| Restarts | container restart count | > 3 in 10 min | Warn |
| TODO | | | |
