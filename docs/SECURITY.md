# Security and configuration hygiene

## Secrets handling
- **No secrets in code or images.** All configuration (DB credentials, log level) is read from
  environment variables at runtime (`app/config.py`). The Docker image contains no credentials.
- **`.env` is gitignored;** only `.env.example` with placeholder values is committed. Before the
  first commit I verified with `git ls-files` that no `.env`, virtualenv or database files were tracked.
- **`.dockerignore` excludes `.env`,** so secrets can't be copied into an image by accident.
- **Compose fails fast** if a required secret is missing (`${POSTGRES_PASSWORD:?...}`) instead of
  silently starting with an empty password.
- **CI uses no stored credentials.** Pushing to GHCR uses the automatic, short-lived `GITHUB_TOKEN`,
  piped to `docker login --password-stdin` so it never shows up in logs or the process list.
- **Cloud:** secrets would live in a managed secret store (AWS Secrets Manager, Azure Key Vault or
  GCP Secret Manager), injected into the container at runtime, with rotation enabled and access
  limited to the service's own identity.

## Least privilege

| Layer | Control |
|---|---|
| Container user | Runs as UID 10001 (non-root, no login shell). CI fails the build if `id -u` returns 0 |
| Container runtime | `read_only: true` root filesystem (only `/tmp` writable via tmpfs), `cap_drop: [ALL]`, `no-new-privileges` |
| Image | Multi-stage build: compilers/pip caches stay in the builder stage; slim base image |
| Network | Postgres has no `ports:` mapping, so it's only reachable from the api container on the Compose network |
| CI token | Workflow default is `permissions: contents: read`; only the release job gets `packages: write` |
| CI supply chain | Every third-party GitHub Action is pinned to a full commit SHA, not a tag |

**Known gap:** the app connects to Postgres as the database owner created by the
`postgres` image. Improvement: an init script that creates a separate `apex_app` role with
only `SELECT, INSERT, UPDATE, DELETE` on the app's tables, and run migrations with the owner role.

## Dependency and image scanning

| Check | Tool | When | Fails the build when |
|---|---|---|---|
| Python dependency CVEs | `pip-audit` | every CI run | any known vulnerability |
| Container image CVEs (OS + libraries) | Trivy | every CI run | HIGH/CRITICAL with a fix available |
| Lint / code quality | ruff | every CI run | any lint error |

- All Python dependencies are pinned to exact versions in `requirements.txt` for reproducible builds.
- **It worked during this project:** the first `pip-audit` run found 7 known vulnerabilities in
  `starlette 0.41.3` (pulled in by an old FastAPI pin). I upgraded the dependency set
  (FastAPI 0.162.0 → starlette 1.10.0) and the audit came back clean, with all tests still passing.
- **Action pinning:** the CI originally referenced `aquasecurity/trivy-action@0.28.0`; that tag no
  longer exists upstream, which broke the pipeline. Tags can be deleted or moved to malicious code,
  so all actions are now pinned to commit SHAs (with the version in a comment).
- **Next steps:** enable Dependabot for pip, Docker and GitHub Actions updates; add `gitleaks`
  secret scanning to CI; sign images with cosign and generate an SBOM.

## Cost-aware path to cloud hosting

No cloud resources were created for this assessment. Proposed path, cheapest first:

| Stage | Hosting | Approx. cost | Why |
|---|---|---|---|
| 1. Pilot / demo | One small VM (e.g. AWS t4g.small / Azure B1s) running this same `docker-compose.yml` | ~$5–15 / month | Zero changes to the setup; same deploy/rollback scripts |
| 2. Production-ready | Managed container service that **scales to zero** (Google Cloud Run, Azure Container Apps or AWS App Runner) + smallest managed Postgres tier with automated backups | ~$15–40 / month at low traffic | No servers to patch, pay per request, managed DB backups and failover |
| 3. Growth | Add autoscaling limits, read replica, CDN only when metrics show the need | Driven by measured load | Avoid paying for capacity before it is needed |

**Cost guardrails:** budget alerts from day one (e.g. 50% / 80% / 100% of a monthly budget); tag
every resource with `project` and `env`; set max-instance limits on autoscaling; shut down or
scale non-production environments to zero outside working hours; keep images in the free GHCR
tier; set log retention (e.g. 14–30 days) because log storage is a common hidden cost.
