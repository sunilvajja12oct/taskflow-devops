# ADR 0006: No database yet

**Status:** Accepted (open gap, not a deliberate final design)

## Context

The original build plan specified a 3-tier app — task API + Postgres backend.
What exists today (`app/src/app.js`) is a 2-tier app: an Express API holding
tasks in a plain in-memory array (`let tasks = []`). Restarting the pod loses
all data. Meanwhile, everything *around* where a database would sit was built
as if one existed: a KMS-encrypted Secrets Manager secret named
`taskflow/dev/db-credentials`, a 30-day rotation Lambda, a rotation-failure
alert path — all live, all pointed at credentials nothing currently reads.

## Decision

Ship without a database for now. Document the gap explicitly rather than let it
sit silently, since it's the single largest deviation from the original design.

## Consequences

- The app has no state to lose, back up, or restore — which is also why
  [Phase 9 (DR)](../postmortems/) has nothing real to drill yet: a restore drill
  needs something worth restoring.
- The secrets/rotation infrastructure (ADR 0005) is fully built and tested at
  the AWS level but not yet exercised end-to-end by a real consumer — the
  rotation Lambda has never had its output actually read by a running database
  connection.
- Adding a real database later is mostly additive, not a redesign: an
  `aws_db_instance` (or a Postgres pod + PVC) in `terraform/modules`, wiring
  `SecretsManager` values into the app's environment via the existing
  `taskflow-config` ConfigMap pattern, and switching `app/src/app.js`'s
  in-memory array for a real client.

## Alternatives considered

- **Build RDS now** — deferred by explicit scope decision (see the
  [status/mind-map artifact](../diagrams/architecture.md)) in favor of finishing
  the documentation and process gaps (Phase 11) first, since those apply to
  everything already built and don't cost anything further from the $130
  credit.
