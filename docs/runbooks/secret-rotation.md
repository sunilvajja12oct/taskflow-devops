# Runbook: Secret rotation (`taskflow/dev/db-credentials`)

Related: [ADR 0005](../adrs/0005-single-user-secret-rotation.md).

## What's automated

- `aws_secretsmanager_secret_rotation.db_credentials` rotates the secret every
  30 days automatically via `taskflow-dev-secret-rotation` (single-user Lambda,
  `terraform/modules/secrets/lambda/rotate_secret.py`).
- On failure, an EventBridge rule (`taskflow-dev-secret-rotation-failed`)
  matches the `RotationFailed` CloudTrail event and publishes to the
  `taskflow-dev-ops-alerts` SNS topic, which emails the address in
  `terraform/envs/dev/main.tf`'s `module.secrets.alert_email`.

## How to manually trigger a rotation (e.g. to test the alert path)

```bash
aws secretsmanager rotate-secret \
  --secret-id taskflow/dev/db-credentials \
  --profile taskflow --region us-east-1
```

Then check the outcome:

```bash
aws secretsmanager describe-secret \
  --secret-id taskflow/dev/db-credentials \
  --profile taskflow --region us-east-1 \
  --query "[RotationEnabled,LastRotatedDate]"
```

## On success

- `LastRotatedDate` updates, a new `AWSCURRENT` version exists.
- Nothing pages you — this is expected and silent by design. If you want to
  confirm the Lambda actually ran, check its logs:

```bash
aws logs tail /aws/lambda/taskflow-dev-secret-rotation --profile taskflow --region us-east-1 --since 10m
```

## On failure

1. **You'll get an email** from the `taskflow-dev-ops-alerts` SNS topic,
   subject line referencing the pipeline/rotation failure.
2. Check the Lambda's logs first — almost every rotation failure shows up there
   with a clear stack trace:
   ```bash
   aws logs tail /aws/lambda/taskflow-dev-secret-rotation --profile taskflow --region us-east-1 --since 1h
   ```
3. Check the secret's rotation state — a failed rotation can leave a pending
   version:
   ```bash
   aws secretsmanager describe-secret --secret-id taskflow/dev/db-credentials \
     --profile taskflow --region us-east-1 --query "VersionIdsToStages"
   ```
   If a version is stuck at `AWSPENDING`, the rotation didn't complete cleanly.
4. **Since nothing currently reads this secret** (see
   [ADR 0006](../adrs/0006-no-database-yet.md)), a failed rotation today has no
   blast radius beyond the alert itself — safe to investigate at leisure. Once
   a real database consumes this secret, this step changes: a stuck rotation
   could mean the *next* scheduled rotation attempt fails too, and the
   application's actual DB credential could go stale. Re-run rotation manually
   (the command above) once the root cause is fixed.

## Known gap

This runbook exists but the failure path (steps above) has not actually been
exercised end-to-end — the manual-trigger command has never been run against
this account. Recommended first real test: run it once, confirm the email
lands, before relying on this runbook under pressure.
