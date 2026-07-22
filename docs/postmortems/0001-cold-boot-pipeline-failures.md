# Postmortem: Four failures found by actually tearing down and rebuilding the environment

**Date:** 2026-07-21
**Severity:** No production impact (dev-only, learning project) — but every
issue below would have blocked or silently corrupted a real deploy.
**Status:** All four resolved and re-verified live.

## Summary

A static code review of this repo's automation had already flagged that the k3s
bootstrap and a few instance-lookup scripts were fragile (see the earlier
connectivity audit). Fixing those on paper and pushing the fix wasn't enough to
prove they worked — the actual verification was destroying the environment
completely and rebuilding it from zero, live, watching each step. That process
surfaced four additional real bugs that reading the code never would have
caught, because they only exist at the intersection of timing, AWS API
behavior, and cold-start state — not in any single file.

None of these were hit in isolation by inspection. All four were found by
running `terraform apply` against a genuinely empty account and watching what
actually happened.

## Timeline (all times UTC, 2026-07-21)

| Time | Event |
|---|---|
| 22:49 | First CI run after pushing the k3s-bootstrap fix. Fails immediately in `resolve`: `Could not assume role with OIDC`. |
| ~22:58 | `scripts/up.sh` run locally to recreate infrastructure from scratch. `terraform apply` fails on `aws_secretsmanager_secret.db_credentials`: name already scheduled for deletion. |
| 23:00 | Old secret force-deleted manually; `recovery_window_in_days = 0` added to prevent recurrence; `terraform apply` re-run, succeeds — 58 resources created including the OIDC role. |
| 23:02–23:07 | `status.sh` shows the Kubernetes phase empty. Direct SSM inspection finds `/usr/local/bin/k3s` doesn't exist, no install process running, cloud-init log frozen mid-script. |
| 23:07 | Root cause found: `curl -sfL https://get.k3s.io \| sh -` ran before the NAT instance's route was up, failed silently (empty pipe → `sh -` exits 0), script continued believing it had succeeded. |
| 23:09 | Fix pushed (retry on binary presence, marker only written once both binaries confirmed); instance replaced; k3s reaches `Ready` in ~15s on the corrected boot. |
| 23:09–23:16 | First fully-automated CI run succeeds end-to-end (`resolve` → `notify`, all green). |
| ~23:17 | Direct inspection of the live pods (not just trusting CI's green check) finds both replicas in `ImagePullBackOff`. |
| 23:20 | Root cause found: the Helm chart already referenced `imagePullSecrets: ecr-pull-secret`, but nothing had ever created that secret. Also found: `deploy` and `smoke-test` only checked that the *AWS API call* to fetch a command's status succeeded, never the command's actual result — a broken deploy was always reported green. |
| 23:23 | Both fixed and pushed: `deploy` now creates/refreshes the pull secret every run; both jobs poll for a terminal status and fail loudly on anything but `Success`. |
| 23:26 | Second fully-automated CI run succeeds end-to-end; pods independently confirmed `Running 1/1`, `/health` returns `200`. |
| (later) | User runs `destroy-all.sh` manually to independently verify the full cycle. Fails: `BucketNotEmpty` on the `ansible_transfer` S3 bucket. |
| | Root cause: the CI `bootstrap` job (added earlier the same session) now writes the Helm chart into that bucket every run, and it had no `force_destroy`. Fixed and pushed. First attempt to re-destroy still failed because `force_destroy` only takes effect once written into Terraform *state*, and `destroy` never runs an apply first — bucket emptied manually as a one-time unblock; state self-corrects on the next `apply`. |

## Impact

None in production — this is a personal dev/learning account. Impact assessed
as: had this been a real service, an instance replacement (auto-scaling
replacement, patching cycle, AZ failure) would have produced a node with no
running application and no automated alerting distinguishing that from a
successful, boring deploy, for an unbounded period.

## Root causes

**1. OIDC role missing after teardown.** Not a bug — a structural property of
having CI authenticate as a role that Terraform itself manages. `destroy-all.sh`
removes it like everything else; CI cannot re-create the trust relationship it
needs in order to authenticate. *(Documented, not "fixed" — see the
[pause/resume/destroy runbook](../runbooks/pause-resume-destroy.md).)*

**2. Secrets Manager soft-delete blocking recreation.** AWS retains a deleted
secret's name for a recovery window by default; recreating a same-named secret
before that window elapses fails outright. Same underlying shape as #4 below —
a disposable, frequently-destroyed environment needs its stateful resources
configured for immediate real deletion, not AWS's default safety window.
*Fixed:* `recovery_window_in_days = 0`.

**3. k3s install race + silently masked failure.** Two compounding issues, not
one: (a) `user_data` runs within seconds of boot, before the NAT instance (a
separate, concurrently-created autoscaling group) necessarily has a working
route; (b) `curl ... | sh -` in a shell pipeline exits with the status of the
*last* command — if curl fails to fetch anything, `sh -` receives empty stdin,
which is a no-op, not an error, so it exits `0`. Combined, a transient network
failure in the first few seconds of boot produced no error, no crash, and no
signal — just a script that quietly skipped the one thing it was supposed to
do. *Fixed:* retry based on the binary's actual presence on disk, not the
pipeline's exit code; the completion marker is only written once both k3s and
Helm are independently verified installed.

**4. No image pull authentication.** The Helm chart was written expecting an
`ecr-pull-secret` to exist (`imagePullSecrets` was already in
`deployment.yaml`) — but nothing in the pipeline ever created it. This gap was
invisible to every check *except* actually looking at pod status, because:

**5. `deploy` and `smoke-test` didn't actually check for failure.** Both jobs
called `aws ssm get-command-invocation` and treated the *API call succeeding*
as the signal of success — but that call succeeds even when the remote command
it's reporting on failed. A broken `helm upgrade` or a failing `curl /health`
would still show a green checkmark in GitHub Actions. This is why issue #4 was
invisible to CI even after the pipeline "passed": the pipeline was never
capable of failing on this class of problem. *Fixed:* both jobs now poll for a
terminal SSM command status and `exit 1` with the full command output on
anything but `Success`.

**6. S3 bucket destroy failure.** A direct side effect of the fix for #4/#3 —
adding the `bootstrap` job's chart-sync step meant the `ansible_transfer`
bucket, previously always empty, now holds objects by the time `destroy` runs.
It never had `force_destroy` (unlike the CloudTrail bucket, which already did).
*Fixed:* added `force_destroy = true`; also learned that this flag only takes
effect via state, so `destroy` right after adding it still needed a one-time
manual bucket-empty to unblock — the *next* full cycle will be clean.

## What went well

- The connectivity audit's static analysis correctly identified the k3s
  bootstrap gap and the instance-lookup fragility *before* any of this — those
  fixes were directionally right, just incomplete until proven live.
- Every fix in this incident was verified by direct inspection (SSM commands
  hitting the real instance, `kubectl get pods`, `curl /health`) rather than by
  trusting a green CI checkmark — which is exactly what caught issue #5, a bug
  that would otherwise have made every future incident in this class invisible.
- Nothing here required rolling back to a previous known-good state — every
  fix was forward-only, and the environment was disposable by design the whole
  time.

## Action items

| Action | Status |
|---|---|
| Retry k3s/Helm install on binary presence, not curl's exit code | Done |
| Only mark bootstrap complete once both binaries verified | Done |
| `recovery_window_in_days = 0` on the DB credentials secret | Done |
| `force_destroy = true` on the ECR repo and the `ansible_transfer` bucket | Done |
| `deploy`/`smoke-test` fail on a real remote-command failure | Done |
| Document the OIDC cold-start dependency so it's not rediscovered | Done — [runbook](../runbooks/pause-resume-destroy.md) |
| Consider: managed NAT Gateway or an explicit NAT-readiness gate before instance boot, to remove the timing race at its source rather than retrying around it | Not done — see [ADR 0001](../adrs/0001-nat-instance-over-nat-gateway.md) for the cost trade-off that keeps this open |
| Add a synthetic test that intentionally breaks `deploy` to prove the new failure-gating actually fails the pipeline (not just that it can succeed) | Not done |
