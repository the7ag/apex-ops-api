# AI assistance disclosure

AI assistance was permitted for this assessment and was used substantially. This file states
exactly how.

**Tool:** Claude (Anthropic), via Claude Code, an AI coding assistant running in my terminal with
access to the project folder.

## What the AI did
| Area | AI contribution |
|---|---|
| Planning | Explained the assessment brief and proposed the stack, repo layout and step-by-step plan |
| Application code | Wrote `app/` (FastAPI endpoints, health/readiness, structured logging, metrics) |
| Tests | Wrote `tests/` (10 tests + the intentional failure test) |
| Containers | Wrote the `Dockerfile`, `.dockerignore` and `docker-compose.yml` |
| CI/CD | Wrote `.github/workflows/ci.yml` |
| Scripts | Wrote `scripts/deploy.sh`, `rollback.sh`, `lib.sh` and `demo.sh` |
| Verification | Ran lint, tests, `pip-audit`, Docker builds and the deploy/rollback/outage demos on my machine; the logs in `docs/evidence/*.log` are real output from those runs |
| Debugging | Found and fixed the vulnerable `starlette` dependency, the CI pytest import error, the missing trivy-action tag (and pinned actions to SHAs), and the CRLF line-ending issue |
| Git | Made the commits and pushed to GitHub at my request (commits carry a `Co-Authored-By: Claude` trailer) |
| Documentation | Drafted the README, RUNBOOK, SECURITY notes, this DECISION_MEMO and this disclosure |

## What I did
- Chose to use Python and directed the work step by step.
- Installed and ran Docker Desktop, created the GitHub repository (`the7ag/apex-ops-api`).
- Ran the CI workflow with the intentional failure enabled and took the CI screenshots in
  `docs/evidence/*.png`.
- Read every file in the repository to understand how and why it works.
- TODO before submitting: confirm you have read the generated documentation, and add anything
  you changed or wrote yourself.

## How I verified the AI's work
- Every claim of success in the docs is backed by a CI run on GitHub or a log in `docs/evidence/`.
- I can re-run any demo myself with `scripts/demo.sh` during the review.
