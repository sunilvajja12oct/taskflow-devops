# Runbook: Deploy & rollback

## Normal deploy (fully automated)

Every push to `main` runs the full pipeline automatically:

```
resolve → lint-scan → terraform-plan → apply → bootstrap → build-scan-push
        → deploy → smoke-test → notify
```

- `bootstrap` waits for the app instance's SSM agent to come online and syncs
  `k8s/taskflow` to the `ansible_transfer` S3 bucket.
- `deploy` waits for `/opt/taskflow/bootstrap-complete` on the instance
  (written by `user_data` once k3s **and** Helm are both confirmed installed),
  refreshes the `ecr-pull-secret` Kubernetes secret with a fresh ECR token, then
  runs `helm upgrade --install`.
- `smoke-test` retries `curl .../health` for up to ~3 minutes and **fails the
  job** if it never returns success — this actually gates the pipeline (fixed
  2026-07-21; previously always reported green regardless of the real result).
- `notify` always runs (`if: always()`) and reports the real
  `smoke-test` result to the ops SNS topic → email.

Watch a run:

```bash
gh run list --limit 5
gh run watch <run-id> --exit-status
```

## Checking what's actually running

```bash
scripts/status.sh   # Phase 6 shows live `kubectl get pods`, Phase 7 shows recent CI runs
```

or directly:

```bash
INSTANCE_ID=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=taskflow-dev-app-01" \
  "Name=instance-state-name,Values=running" --query "Reservations[].Instances[].InstanceId" --output text \
  --profile taskflow --region us-east-1)
aws ssm send-command --instance-ids $INSTANCE_ID --document-name AWS-RunShellScript \
  --parameters 'commands=["export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && kubectl get pods -o wide"]' \
  --profile taskflow --region us-east-1
```

## Rollback

Helm keeps release history. To roll back to the previous working release:

```bash
# from your machine, via SSM (same pattern as the deploy job)
aws ssm send-command --instance-ids $INSTANCE_ID --document-name AWS-RunShellScript \
  --parameters 'commands=["export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && helm history taskflow -n default"]' \
  --profile taskflow --region us-east-1

# once you know the target revision:
aws ssm send-command --instance-ids $INSTANCE_ID --document-name AWS-RunShellScript \
  --parameters 'commands=["export KUBECONFIG=/etc/rancher/k3s/k3s.yaml && helm rollback taskflow <REVISION>"]' \
  --profile taskflow --region us-east-1
```

Then re-run the health check manually to confirm:

```bash
aws ssm send-command --instance-ids $INSTANCE_ID --document-name AWS-RunShellScript \
  --parameters 'commands=["curl -sf -H \"Host: taskflow.local\" http://localhost/health"]' \
  --profile taskflow --region us-east-1
```

## If a deploy fails

`deploy` and `smoke-test` both print the SSM command's full output on failure
(`aws ssm get-command-invocation`) — check the GitHub Actions log for the exact
stdout/stderr of the remote command, not just the pass/fail state.

Common causes seen in practice (see the
[postmortem](../postmortems/0001-cold-boot-pipeline-failures.md) for the full
story on each):

- **Pods stuck `ImagePullBackOff`** — the `ecr-pull-secret` wasn't created/is
  stale. `deploy` refreshes it every run now; if it's still failing, check the
  instance's IAM role has `AmazonEC2ContainerRegistryReadOnly` attached.
- **`deploy` times out waiting for `bootstrap-complete`** — k3s/Helm never
  finished installing on a fresh instance. Check
  `/var/log/cloud-init-output.log` on the instance via SSM.
- **`resolve` fails with an OIDC error** — the GitHub OIDC role/provider
  (`module.cicd`) doesn't exist in AWS, almost always because the environment
  was torn down and hasn't been brought back up yet. Run `scripts/up.sh`
  locally first (see the [pause/resume/destroy runbook](pause-resume-destroy.md)) —
  CI cannot bootstrap this itself.
