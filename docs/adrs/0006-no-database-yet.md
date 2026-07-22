# ADR 0006: No database yet (superseded — resolved)

**Status:** Superseded. TaskFlow now runs a real, self-hosted Postgres pod
(`k8s/taskflow/templates/postgres-*.yaml`); `app/src/app.js` uses a real `pg`
client with a startup migration. Kept below for the historical record of why
the gap existed and what closing it involved.

## Original context (as of the first pass)

The original build plan specified a 3-tier app — task API + Postgres backend.
What existed at the time (`app/src/app.js`) was a 2-tier app: an Express API
holding tasks in a plain in-memory array (`let tasks = []`). Restarting the
pod lost all data. Meanwhile, everything *around* where a database would sit
was built as if one existed: a KMS-encrypted Secrets Manager secret named
`taskflow/dev/db-credentials`, a 30-day rotation Lambda, a rotation-failure
alert path — all live, all pointed at credentials nothing read yet.

## What closing the gap actually took

Turned out to be more than "add a client" — two real bugs only surfaced by
running it:

1. The Postgres pod's readiness probe deadlocked against its own Kubernetes
   Service (see the postmortem) - `envFrom` pulled in `PGHOST` meant for the
   *app*, and `pg_isready` used it instead of checking localhost.
2. Wiring the credentials in required refactoring the CI deploy step out of
   an inline SSM JSON string into a real script
   (`scripts/ci/deploy-remote.sh`), which also now fetches the secret
   directly on the instance - no plaintext credential passes through a
   GitHub Actions log.

## Consequences

- The secrets/rotation infrastructure (ADR 0005) is now actually exercised by
  a real consumer for the first time.
- [Phase 9 (DR)](../postmortems/) now has something real to restore - a
  `pg_dump`-to-S3 backup path and restore drill became meaningful.
- Single-user rotation (ADR 0005) is worth revisiting now that a live
  connection pool exists to potentially disrupt mid-rotation.

## Alternatives considered

- **RDS instead of a self-hosted pod** — rejected on cost: RDS bills
  continuously; a pod on the existing instance doesn't add a cent, matching
  every other cost call in this project (NAT instance, self-managed k3s).
