# Decision memo: Apex Operations API

## Context
The goal was to show a reliable, reviewable path from code commit to a running release for a
small API: containerized, tested in CI, deployed reproducibly, safe to release and roll back,
observable, and secure by default. All within 48 hours, locally, with no paid cloud resources.

## Key decisions and trade-offs

| Decision | Why | Trade-off / alternative considered |
|---|---|---|
| **Python + FastAPI + SQLAlchemy** | Small, readable, built-in request validation (422s for bad input) and auto-generated API docs at `/docs` | Node/Express would work equally well; Go would give a smaller image but slower to build in 48h |
| **PostgreSQL in Docker Compose** | Satisfies "app + database + persistent storage" with a real database; reviewers need only Docker | Not highly available; a production setup would use a managed database |
| **SQLite for unit tests, real Postgres in the CI smoke test** | Unit tests run in < 1 s with no external services; the smoke test still proves the real stack works | SQLite and Postgres differ slightly; the CI Compose smoke test covers that gap |
| **Separate `/health` and `/ready`** | Liveness ("process alive") vs readiness ("can serve traffic"). A DB outage should stop traffic, not cause restart loops | Slightly more code than a single endpoint |
| **GitHub Actions + GHCR** | Free for public repos; run history is built-in evidence; `GITHUB_TOKEN` avoids stored secrets | Ties the pipeline to GitHub (GitLab CI / Jenkins are alternatives) |
| **Pipeline gating with `needs:`** | Build, scan and release only run if lint + tests + dependency audit pass, so a failing test blocks release | Sequential jobs are a little slower than parallel ones |
| **One image built, scanned, smoke-tested and pushed in the same job** | The exact image that was tested is the one released (no rebuild drift) | A separate release job would be cleaner but would need to rebuild or transfer the image |
| **Versioning: git tag `vX.Y.Z` → image `X.Y.Z`; other commits → `sha-<7>`** | Human-readable releases plus traceability of every build to a commit | No `latest` tag on purpose: it hides what is running and makes rollback ambiguous |
| **Rollback = redeploy the previous immutable image tag** | Fast (seconds), simple, and the old image already passed CI | Requires backward-compatible DB schema changes (see RUNBOOK section 2) |
| **Automatic rollback in `deploy.sh` on readiness failure** | A broken release restores itself without a human in the loop | Readiness only catches failures visible at startup; logic bugs need monitoring/alerts |
| **Bash scripts instead of Kubernetes/Helm** | Matches the "local, reproducible" scope; easy to read and explain | Brief downtime during container swap (no rolling update); acceptable for this scope |
| **Hardened container (non-root, read-only, no capabilities)** | Limits the impact if the app is compromised | Needed a tmpfs for `/tmp`; some tools can't write to disk |
| **Actions pinned to commit SHAs** | Protection against deleted/moved tags (it actually happened with trivy-action) | Updates need a bot (Dependabot) or manual SHA bumps |

## Assumptions
- A local Docker host stands in for a production server; "deployment" means running a specific
  image version via Compose on that host.
- "Operations API" data is synthetic: simple items/tickets with a name and status. No real or personal data.
- A short interruption (~5 s) during deploys is acceptable at this scale.
- The reviewer has Docker Desktop (or Docker Engine + Compose v2) and a bash shell.
- Images published from CI are the release artifacts; local builds are used for the demos.

## Problems found and how they were solved
1. **Vulnerable dependency.** `pip-audit` found 7 CVEs in `starlette 0.41.3`. Upgraded the pinned
   dependency set; audit clean; tests still pass.
2. **CI tests failed but passed locally.** `ModuleNotFoundError: No module named 'app'`. Locally I
   ran `python -m pytest` (adds the current directory to the import path); CI runs `pytest`
   (doesn't). Reproduced locally, fixed with `pythonpath = ["."]` in `pyproject.toml`.
   The release job was correctly **skipped**, so nothing broken shipped.
3. **CI couldn't resolve `trivy-action@0.28.0`.** The tag no longer exists upstream. Pinned all
   actions to commit SHAs.
4. **Windows line endings.** Git was converting files to CRLF, which breaks bash scripts. Added
   `.gitattributes` forcing LF.

## Risks and known gaps
- App connects to the DB as the owner role, not a least-privilege app role.
- No real migration tool (tables are created on startup); schema changes need Alembic.
- Slow failure during DB outages (~4 s per request) due to the default connect timeout.
- Single instance, no rolling deploy: brief downtime during releases.
- Alerts are proposed, not deployed (no Prometheus/Alertmanager running).
- GHCR package visibility must be set to public (or a login used) for others to pull the images.

## What I would do with more time
1. Least-privilege DB role + Alembic migrations, with an expand/contract migration demo.
2. Short DB `connect_timeout` and a test for fast failure.
3. Run Prometheus + Grafana in Compose with the proposed alert rules wired up.
4. Zero-downtime deploy (two api replicas behind a reverse proxy, or move to a container platform).
5. Dependabot, gitleaks, image signing (cosign) and SBOM generation in CI.
6. A CD job that deploys to a free-tier staging environment after each tagged release.
