# ADR 0005: Single-user secret rotation (not alternating-user)

**Status:** Accepted

## Context

Secrets Manager supports two rotation strategies for database-style credentials:

- **Single-user rotation** — one credential exists; rotation generates a new
  password, updates it on the target, then updates the secret. There's a brief
  window where old connections using the previous password may fail until they
  reconnect.
- **Alternating-user rotation** — two credentials (`AWSCURRENT` /
  `AWSPREVIOUS`) exist and rotation alternates between them, so a live
  connection is never invalidated mid-use — the standard pattern for
  zero-downtime rotation against a real production database.

## Decision

Use **single-user rotation** (`terraform/modules/secrets/lambda/rotate_secret.py`,
scheduled every 30 days via `aws_secretsmanager_secret_rotation`, with
`RotationFailed` wired to EventBridge → SNS → email).

## Consequences

- Simpler Lambda (`rotate_secret.py`) and simpler mental model — appropriate
  since there is currently **no actual database consuming this secret** (see
  [ADR 0006](0006-no-database-yet.md)) — there's no live connection pool that
  rotation could disrupt yet.
- Not zero-downtime — if a real database were added today and something held a
  connection using the pre-rotation password across a rotation event, it could
  see an authentication failure until it reconnects. Acceptable now; would need
  revisiting the moment a real database is added, at which point
  alternating-user rotation becomes the right default, not single-user.
- Failure path is real either way: `RotationFailed` → EventBridge rule →
  SNS topic → email, confirmed created live in this account.

## Alternatives considered

- **Alternating-user rotation** — the more correct choice for a real production
  database. Deferred, not rejected: building it now, before there's a database
  to rotate credentials *for*, would be practicing the harder pattern on a
  secret nothing actually reads. Flagged as the first thing to change when
  [ADR 0006](0006-no-database-yet.md) is resolved.
