# Security and configuration hygiene

## Secrets handling
- All config is read from environment variables; nothing is hard-coded.
- `.env` is gitignored; only `.env.example` (placeholders) is committed.
- CI uses the built-in short-lived `GITHUB_TOKEN`, no stored passwords.
- In the cloud: TODO (e.g. AWS Secrets Manager / Azure Key Vault, injected at runtime).

## Least privilege
- Container runs as UID 10001 (non-root); CI verifies this.
- Container filesystem is read-only, all Linux capabilities dropped, `no-new-privileges`.
- Postgres is not published to the host; only the api container can reach it.
- CI workflow token is `contents: read` by default; only the release job gets `packages: write`.
- Known gap / TODO: the app connects as the Postgres owner user. Improvement: a separate
  app role with only SELECT/INSERT/UPDATE on its tables.

## Dependency and image scanning
- `pip-audit` scans Python dependencies on every CI run.
- Trivy scans the built image; HIGH/CRITICAL fixable vulnerabilities fail the build.
- Dependency versions are pinned in `requirements.txt`.
- TODO: enable Dependabot; consider `gitleaks` for secret scanning.

## Cost-aware path to cloud
TODO: describe in your own words. Ideas:
- Smallest option: one small VM running this same compose file.
- Managed, scale-to-zero container service (Cloud Run / Azure Container Apps / AWS App Runner).
- Smallest managed Postgres tier, automated backups.
- Budget alerts from day one; tear down non-prod outside working hours.
