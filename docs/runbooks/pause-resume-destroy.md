# Runbook: Pause / resume / full teardown

## Between work sessions: pause, don't destroy

```bash
scripts/pause.sh
```

Stops the app + NAT EC2 instances — the only hourly-billed resources in this
stack. VPC, IAM, ECR, Secrets Manager, and the k3s state on the app instance's
disk all survive untouched and cost nothing while stopped. Leaves a timestamped
log under `reports/`.

To come back:

```bash
scripts/resume.sh
```

Starts both instances, waits for them to report `running`, then polls for the
app instance's SSM agent to come back online (up to ~2 minutes). If SSM isn't
confirmed online by the time the script gives up, it says so — run
`scripts/status.sh` a minute later to check again rather than assuming failure.

## Checking current state

```bash
scripts/status.sh
```

Seven phases: budget/cost, network (NAT), compute (app instance + SSM status),
secrets, observability (alarm state), container registry, and live `kubectl get
pods` if the instance is up. Also drops a copy under `reports/status-*.md`.

Both `status.sh` and `resume.sh` filter instance lookups by
`instance-state-name` and refuse to proceed if more than one instance matches a
tag — AWS can keep a terminated instance listed for up to ~an hour after
termination, and an unfiltered lookup returning two instance IDs on one line
silently corrupts every downstream check. (This actually happened once during
this build — see the
[postmortem](../postmortems/0001-cold-boot-pipeline-failures.md).)

## Full teardown

```bash
scripts/destroy-all.sh
```

Only run this when genuinely done with the project — not between sessions.
Requires typing `destroy everything` to confirm. Destroys the VPC, compute,
secrets, registry, and CI IAM role — everything Terraform manages. The S3 state
bucket and DynamoDB lock table are **not** touched (created outside Terraform on
purpose in Phase 0, specifically so this script can still run after they'd
otherwise be needed to run it).

### Bringing it back after a full teardown

```bash
scripts/up.sh
```

Runs `terraform apply` (recreating all ~58 resources, including the GitHub
OIDC provider/role that CI itself depends on to authenticate — CI cannot do
this step for itself, see below) then calls `resume.sh`.

Give the app instance 1–2 minutes after it's `running` for `user_data` to
finish installing k3s + Helm before expecting `scripts/status.sh`'s Kubernetes
phase to show pods. If a fresh `apply` fails on:

- **`BucketNotEmpty` / secret "already scheduled for deletion"** — both fixed
  (`force_destroy` / `recovery_window_in_days = 0`) as of this build, but if
  either resurfaces on an older Terraform state, it means a bucket now holds
  objects (S3) or the old secret hasn't finished its soft-delete window yet —
  empty the bucket (`aws s3 rm s3://<bucket> --recursive`) or force-delete the
  secret (`aws secretsmanager delete-secret --force-delete-without-recovery`)
  to unblock, then re-run.

### Do not trigger CI/CD before running `up.sh` locally

Pushing to `main` (or opening a PR) right after `destroy-all.sh`, before
`up.sh` has recreated the GitHub OIDC role, will fail at the very first CI job
(`resolve`) with an OIDC "web identity token could not be validated" error.
This is expected — CI authenticates *as* a role that only exists because
Terraform created it, so it cannot bootstrap itself back into existence after a
full teardown. Run `scripts/up.sh` locally (with real AWS credentials) first;
CI can take back over once that role exists again.
